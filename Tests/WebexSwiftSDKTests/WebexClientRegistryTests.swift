import XCTest
@testable import WebexSwiftSDK

final class WebexClientRegistryTests: XCTestCase {
    func testAddAccountGeneratesIDAndSavesCredentialMetadataAndIndex() async throws {
        let store = InMemoryWebexStore()
        let registry = WebexClientRegistry(store: store, httpClient: RegistryHTTPClient())
        let now = Date(timeIntervalSince1970: 1_777_777)
        let metadata = WebexAccountMetadata(
            webexUserID: "webex-user-1",
            oidcSubject: "oidc-subject-1",
            email: "user@example.com",
            displayName: "Ada Lovelace",
            organizationID: "org-1",
            lastVerifiedAt: now
        )

        let record = try await registry.addAccount(
            configuration: configuration(
                clientID: "client-1",
                clientSecret: "client-secret-1",
                scopes: ["spark:people_read", " openid ", "spark:people_read"],
                prefersEphemeralWebBrowserSession: true
            ),
            metadata: metadata,
            now: now
        )

        XCTAssertEqual(record.metadata, metadata)
        XCTAssertNotNil(UUID(uuidString: record.id.rawValue))
        let accountIDs = try await store.loadAccountIDs()
        let savedMetadata = try await store.loadMetadata(for: record.id)
        let loadedCredential = try await store.loadCredential(for: record.id)
        XCTAssertEqual(accountIDs, [record.id])
        XCTAssertEqual(savedMetadata, metadata)

        let credential = try XCTUnwrap(loadedCredential)
        XCTAssertEqual(credential.clientID, "client-1")
        XCTAssertEqual(credential.clientSecret, "client-secret-1")
        XCTAssertEqual(credential.redirectURI, URL(string: "myapp://oauth/webex")!)
        XCTAssertEqual(credential.scopes, ["openid", "spark:people_read"])
        XCTAssertTrue(credential.prefersEphemeralWebBrowserSession)
        XCTAssertEqual(credential.createdAt, now)
        XCTAssertEqual(credential.updatedAt, now)
    }

    func testAddAccountWithoutMetadataStoresEmptyMetadataAndDoesNotDuplicate() async throws {
        let store = InMemoryWebexStore()
        let registry = WebexClientRegistry(store: store, httpClient: RegistryHTTPClient())
        let now = Date(timeIntervalSince1970: 2_000)

        let first = try await registry.addAccount(
            configuration: configuration(clientID: "client-1"),
            now: now
        )
        let second = try await registry.addAccount(
            configuration: configuration(clientID: "client-1"),
            now: now.addingTimeInterval(1)
        )

        XCTAssertEqual(first.metadata, WebexAccountMetadata())
        XCTAssertEqual(second.metadata, WebexAccountMetadata())
        let firstMetadata = try await store.loadMetadata(for: first.id)
        let secondMetadata = try await store.loadMetadata(for: second.id)
        let accountIDs = try await store.loadAccountIDs()
        XCTAssertEqual(firstMetadata, WebexAccountMetadata())
        XCTAssertEqual(secondMetadata, WebexAccountMetadata())
        XCTAssertEqual(accountIDs, [first.id, second.id])
    }

    func testListAccountsUsesStoredIndexOrderAcrossRegistryInstancesAndEmptyMetadataWhenMissing() async throws {
        let store = InMemoryWebexStore()
        let firstRegistry = WebexClientRegistry(store: store, httpClient: RegistryHTTPClient())
        let firstMetadata = WebexAccountMetadata(email: "first@example.com", displayName: "First")
        let secondMetadata = WebexAccountMetadata(email: "second@example.com", displayName: "Second")
        let first = try await firstRegistry.addAccount(
            configuration: configuration(clientID: "client-1"),
            metadata: firstMetadata,
            now: Date(timeIntervalSince1970: 1)
        )
        let second = try await firstRegistry.addAccount(
            configuration: configuration(clientID: "client-2"),
            metadata: secondMetadata,
            now: Date(timeIntervalSince1970: 2)
        )
        try await store.deleteCredential(for: first.id)
        try await store.deleteMetadata(for: first.id)

        let registry = WebexClientRegistry(store: store, httpClient: RegistryHTTPClient())

        let records = try await registry.listAccounts()

        XCTAssertEqual(records, [
            WebexAccountRecord(id: first.id, metadata: WebexAccountMetadata()),
            WebexAccountRecord(id: second.id, metadata: secondMetadata)
        ])
    }

    func testClientForReturnsClientUsingSavedCredentialTokenStoreAndHTTPClient() async throws {
        let store = InMemoryWebexStore()
        let httpClient = RegistryHTTPClient()
        let registry = WebexClientRegistry(store: store, httpClient: httpClient)
        let now = Date(timeIntervalSince1970: 100)
        let account = try await registry.addAccount(
            configuration: configuration(
                clientID: "client-for-people",
                clientSecret: "client-secret-for-people",
                scopes: ["openid", "spark:people_read"]
            ),
            metadata: WebexAccountMetadata(webexUserID: "person-id"),
            now: now
        )
        try await store.saveTokenRecord(
            WebexTokenRecord(
                refreshToken: "stored-refresh",
                refreshTokenExpiresAt: .distantFuture,
                lastAccessTokenExpiresAt: now.addingTimeInterval(10),
                grantedScopes: ["openid", "spark:people_read"],
                tokenType: "Bearer",
                lastRefreshAt: now
            ),
            for: account.id
        )
        await httpClient.enqueue(response: tokenHTTPResponse(accessToken: "refreshed-access", refreshToken: "new-refresh"))
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://webexapis.com/v1/people/me")!,
            statusCode: 200,
            body: """
            {"id":"person-id","emails":["user@example.com"],"displayName":"Ada Lovelace","orgId":"org-id","created":"2026-04-29T10:11:12Z"}
            """
        ))

        let client = try await registry.client(for: account.id)
        let person = try await client.people.me()

        XCTAssertEqual(client.accountID, account.id)
        XCTAssertEqual(
            person,
            WebexPerson(
                id: "person-id",
                emails: ["user@example.com"],
                displayName: "Ada Lovelace",
                orgID: "org-id",
                created: "2026-04-29T10:11:12Z"
            )
        )
        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(requests.map { $0.url?.path }, ["/v1/access_token", "/v1/people/me"])
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer refreshed-access")
    }

    func testClientForMissingCredentialThrowsMissingCredential() async throws {
        let accountID = WebexAccountID()
        let registry = WebexClientRegistry(store: InMemoryWebexStore(), httpClient: RegistryHTTPClient())

        do {
            _ = try await registry.client(for: accountID)
            XCTFail("Expected missing credential")
        } catch let error as WebexSDKError {
            XCTAssertEqual(error, .missingCredential(accountID))
        }
    }

    func testAuthorizeAndAddAccountStoresTokenOpensAuthorizationURLAndReturnsPrimedClient() async throws {
        let store = InMemoryWebexStore()
        let httpClient = RegistryHTTPClient()
        let registry = WebexClientRegistry(store: store, httpClient: httpClient)
        await httpClient.enqueue(response: tokenHTTPResponse(accessToken: "access-from-code", refreshToken: "refresh-from-code"))
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://webexapis.com/v1/people/me")!,
            statusCode: 200,
            body: """
            {"id":"person-id","emails":["user@example.com"],"displayName":"Ada Lovelace","orgId":"org-id","created":"2026-04-29T10:11:12Z"}
            """
        ))
        let callbackReceiver = FakeOAuthCallbackReceiver(
            callbackURL: URL(string: "http://127.0.0.1:8282/oauth/callback?code=auth-code&state=fixed-state")!
        )
        let opener = AuthorizationURLOpener()

        let authorized = try await registry.authorizeAndAddAccount(
            configuration: configuration(
                clientID: "client-1",
                clientSecret: "client-secret",
                scopes: ["spark:people_read"],
                redirectURI: URL(string: "http://127.0.0.1:8282/oauth/callback")!
            ),
            now: Date(timeIntervalSince1970: 100),
            stateGenerator: { "fixed-state" },
            codeVerifierGenerator: { "fixed-verifier" },
            clock: { Date(timeIntervalSince1970: 200) },
            callbackReceiver: callbackReceiver,
            openAuthorizationURL: { url in
                await opener.open(url)
            }
        )
        let person = try await authorized.client.people.me()

        XCTAssertEqual(authorized.account.id, authorized.client.accountID)
        XCTAssertEqual(authorized.accessTokenExpiresAt, Date(timeIntervalSince1970: 800))
        XCTAssertEqual(authorized.refreshTokenExpiresAt, Date(timeIntervalSince1970: 3_800))
        XCTAssertEqual(person.id, "person-id")

        let openedURL = try await opener.openedURL()
        let openedComponents = try XCTUnwrap(URLComponents(url: openedURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(openedComponents.queryItems?.firstValue(named: "state"), "fixed-state")
        XCTAssertEqual(openedComponents.queryItems?.firstValue(named: "redirect_uri"), "http://127.0.0.1:8282/oauth/callback")
        XCTAssertEqual(openedComponents.queryItems?.firstValue(named: "code_challenge"), PKCE.s256Challenge(for: "fixed-verifier"))

        let accountIDs = try await store.loadAccountIDs()
        let tokenRecord = try await store.loadTokenRecord(for: authorized.account.id)
        XCTAssertEqual(accountIDs, [authorized.account.id])
        XCTAssertEqual(tokenRecord?.refreshToken, "refresh-from-code")

        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(requests.map { $0.url?.path }, ["/v1/access_token", "/v1/people/me"])
        let tokenRequestBody = String(data: try XCTUnwrap(requests[0].httpBody), encoding: .utf8)
        XCTAssertTrue(tokenRequestBody?.contains("code=auth-code") == true)
        XCTAssertTrue(tokenRequestBody?.contains("code_verifier=fixed-verifier") == true)
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer access-from-code")
    }

    func testAuthorizeAndAddAccountRollsBackAccountWhenTokenExchangeFails() async throws {
        let store = InMemoryWebexStore()
        let httpClient = RegistryHTTPClient()
        let registry = WebexClientRegistry(store: store, httpClient: httpClient)
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://webexapis.com/v1/access_token")!,
            statusCode: 400,
            body: "invalid client_secret=client-secret access_token=access-token"
        ))
        let callbackReceiver = FakeOAuthCallbackReceiver(
            callbackURL: URL(string: "http://127.0.0.1:8282/oauth/callback?code=auth-code&state=fixed-state")!
        )

        do {
            _ = try await registry.authorizeAndAddAccount(
                configuration: configuration(
                    clientID: "client-1",
                    clientSecret: "client-secret",
                    redirectURI: URL(string: "http://127.0.0.1:8282/oauth/callback")!
                ),
                stateGenerator: { "fixed-state" },
                codeVerifierGenerator: { "fixed-verifier" },
                clock: { Date(timeIntervalSince1970: 200) },
                callbackReceiver: callbackReceiver,
                openAuthorizationURL: { _ in }
            )
            XCTFail("Expected token exchange failure")
        } catch let error as WebexSDKError {
            guard case .tokenExchangeFailed(let statusCode, let message, _) = error else {
                return XCTFail("Expected tokenExchangeFailed, got \(error)")
            }

            XCTAssertEqual(statusCode, 400)
            assertNoSecretLeak(in: message)
            assertNoSecretLeak(in: String(describing: error))
        }

        let accountIDs = try await store.loadAccountIDs()
        XCTAssertEqual(accountIDs, [])
    }

    func testRemoveAccountDeletesCredentialTokenMetadataAndIndexEntry() async throws {
        let store = InMemoryWebexStore()
        let registry = WebexClientRegistry(store: store, httpClient: RegistryHTTPClient())
        let now = Date(timeIntervalSince1970: 10)
        let first = try await registry.addAccount(
            configuration: configuration(clientID: "client-1"),
            metadata: WebexAccountMetadata(email: "first@example.com"),
            now: now
        )
        let second = try await registry.addAccount(
            configuration: configuration(clientID: "client-2"),
            metadata: WebexAccountMetadata(email: "second@example.com"),
            now: now
        )
        try await store.saveTokenRecord(tokenRecord(now: now), for: first.id)

        try await registry.removeAccount(first.id)

        let removedCredential = try await store.loadCredential(for: first.id)
        let removedToken = try await store.loadTokenRecord(for: first.id)
        let removedMetadata = try await store.loadMetadata(for: first.id)
        let accountIDs = try await store.loadAccountIDs()
        XCTAssertNil(removedCredential)
        XCTAssertNil(removedToken)
        XCTAssertNil(removedMetadata)
        XCTAssertEqual(accountIDs, [second.id])
    }

    func testDuplicateByClientIDAndWebexUserIDThrowsSafeError() async throws {
        let store = InMemoryWebexStore()
        let registry = WebexClientRegistry(store: store, httpClient: RegistryHTTPClient())
        let existing = try await registry.addAccount(
            configuration: configuration(clientID: "client-1", clientSecret: "existing-client-secret"),
            metadata: WebexAccountMetadata(webexUserID: "webex-user-1", email: "first@example.com"),
            now: Date(timeIntervalSince1970: 1)
        )

        do {
            _ = try await registry.addAccount(
                configuration: configuration(clientID: "client-1", clientSecret: "new-client-secret"),
                metadata: WebexAccountMetadata(webexUserID: "webex-user-1", email: "second@example.com"),
                now: Date(timeIntervalSince1970: 2)
            )
            XCTFail("Expected duplicate account")
        } catch let error as WebexSDKError {
            guard case .duplicateAccount(let existingID, let reason) = error else {
                return XCTFail("Expected duplicateAccount, got \(error)")
            }

            XCTAssertEqual(existingID, existing.id)
            XCTAssertTrue(reason.localizedCaseInsensitiveContains("webex user"))
            assertNoSecretLeak(in: reason)
            assertNoSecretLeak(in: String(describing: error))
        }
    }

    func testConcurrentDuplicateAddsAreSerialized() async throws {
        let store = ControllableRegistryStore(emptyIndexLoadDelayCount: 2)
        let registry = WebexClientRegistry(store: store, httpClient: RegistryHTTPClient())
        let metadata = WebexAccountMetadata(webexUserID: "webex-user-1")

        async let first = captureResult {
            try await registry.addAccount(
                configuration: configuration(clientID: "client-1"),
                metadata: metadata,
                now: Date(timeIntervalSince1970: 1)
            )
        }
        async let second = captureResult {
            try await registry.addAccount(
                configuration: configuration(clientID: "client-1"),
                metadata: metadata,
                now: Date(timeIntervalSince1970: 2)
            )
        }

        let results = await [first, second]
        let successes = results.compactMap { result -> WebexAccountRecord? in
            guard case .success(let record) = result else {
                return nil
            }
            return record
        }
        let duplicateErrors = results.compactMap { result -> WebexSDKError? in
            guard case .failure(let error as WebexSDKError) = result,
                  case .duplicateAccount = error else {
                return nil
            }
            return error
        }

        XCTAssertEqual(successes.count, 1)
        XCTAssertEqual(duplicateErrors.count, 1)
        let accountIDs = try await store.loadAccountIDs()
        XCTAssertEqual(accountIDs, successes.map(\.id))
    }

    func testConcurrentAddsThroughTwoRegistriesSharingStoreDoNotLoseIndexEntries() async throws {
        let store = ControllableRegistryStore(loadAccountIDsDelayCount: 2)
        let firstRegistry = WebexClientRegistry(store: store, httpClient: RegistryHTTPClient())
        let secondRegistry = WebexClientRegistry(store: store, httpClient: RegistryHTTPClient())

        async let first = firstRegistry.addAccount(
            configuration: configuration(clientID: "client-1"),
            now: Date(timeIntervalSince1970: 1)
        )
        async let second = secondRegistry.addAccount(
            configuration: configuration(clientID: "client-2"),
            now: Date(timeIntervalSince1970: 2)
        )
        let records = try await [first, second]

        let accountIDs = try await store.loadAccountIDs()
        XCTAssertEqual(Set(accountIDs), Set(records.map(\.id)))
        XCTAssertEqual(accountIDs.count, 2)
    }

    func testConcurrentDuplicateAddsThroughTwoRegistriesSharingStoreAreSerialized() async throws {
        let store = ControllableRegistryStore(loadAccountIDsDelayCount: 2)
        let firstRegistry = WebexClientRegistry(store: store, httpClient: RegistryHTTPClient())
        let secondRegistry = WebexClientRegistry(store: store, httpClient: RegistryHTTPClient())
        let metadata = WebexAccountMetadata(webexUserID: "webex-user-1")

        async let first = captureResult {
            try await firstRegistry.addAccount(
                configuration: configuration(clientID: "client-1"),
                metadata: metadata,
                now: Date(timeIntervalSince1970: 1)
            )
        }
        async let second = captureResult {
            try await secondRegistry.addAccount(
                configuration: configuration(clientID: "client-1"),
                metadata: metadata,
                now: Date(timeIntervalSince1970: 2)
            )
        }

        let results = await [first, second]
        let successes = results.compactMap { result -> WebexAccountRecord? in
            guard case .success(let record) = result else {
                return nil
            }
            return record
        }
        let duplicateErrors = results.compactMap { result -> WebexSDKError? in
            guard case .failure(let error as WebexSDKError) = result,
                  case .duplicateAccount = error else {
                return nil
            }
            return error
        }

        let accountIDs = try await store.loadAccountIDs()
        XCTAssertEqual(successes.count, 1)
        XCTAssertEqual(duplicateErrors.count, 1)
        XCTAssertEqual(accountIDs, successes.map(\.id))
    }

    func testConcurrentAddAndRemoveThroughTwoRegistriesSharingStorePreservesUnrelatedIndexChanges() async throws {
        let existing = WebexAccountID()
        let store = ControllableRegistryStore(
            credentials: [existing: credential(clientID: "existing-client")],
            tokenRecords: [existing: tokenRecord(now: Date(timeIntervalSince1970: 1))],
            metadataRecords: [existing: WebexAccountMetadata(email: "existing@example.com")],
            accountIDs: [existing],
            loadAccountIDsDelayCount: 2
        )
        let firstRegistry = WebexClientRegistry(store: store, httpClient: RegistryHTTPClient())
        let secondRegistry = WebexClientRegistry(store: store, httpClient: RegistryHTTPClient())

        async let add = firstRegistry.addAccount(
            configuration: configuration(clientID: "new-client"),
            now: Date(timeIntervalSince1970: 2)
        )
        async let remove: Void = secondRegistry.removeAccount(existing)
        let added = try await add
        try await remove

        let accountIDs = try await store.loadAccountIDs()
        XCTAssertEqual(accountIDs, [added.id])
    }

    func testDuplicateByClientIDAndOIDCSubjectThrowsSafeError() async throws {
        let store = InMemoryWebexStore()
        let registry = WebexClientRegistry(store: store, httpClient: RegistryHTTPClient())
        let existing = try await registry.addAccount(
            configuration: configuration(clientID: "client-1"),
            metadata: WebexAccountMetadata(oidcSubject: "oidc-subject-1"),
            now: Date(timeIntervalSince1970: 1)
        )

        do {
            _ = try await registry.addAccount(
                configuration: configuration(clientID: "client-1"),
                metadata: WebexAccountMetadata(oidcSubject: "oidc-subject-1"),
                now: Date(timeIntervalSince1970: 2)
            )
            XCTFail("Expected duplicate account")
        } catch let error as WebexSDKError {
            guard case .duplicateAccount(let existingID, let reason) = error else {
                return XCTFail("Expected duplicateAccount, got \(error)")
            }

            XCTAssertEqual(existingID, existing.id)
            XCTAssertTrue(reason.localizedCaseInsensitiveContains("oidc subject"))
            assertNoSecretLeak(in: reason)
            assertNoSecretLeak(in: String(describing: error))
        }
    }

    func testAddAccountRollsBackCredentialWhenMetadataSaveFails() async throws {
        let store = ControllableRegistryStore(failingOperations: [.saveMetadata])
        let registry = WebexClientRegistry(store: store, httpClient: RegistryHTTPClient())

        do {
            _ = try await registry.addAccount(
                configuration: configuration(clientID: "client-1"),
                metadata: WebexAccountMetadata(email: "user@example.com"),
                now: Date(timeIntervalSince1970: 1)
            )
            XCTFail("Expected metadata save failure")
        } catch ControllableRegistryStoreError.requestedFailure(let operation) {
            XCTAssertEqual(operation, "saveMetadata")
        }

        let accountIDs = try await store.loadAccountIDs()
        let credentialCount = await store.credentialCount()
        let metadataCount = await store.metadataCount()
        XCTAssertEqual(accountIDs, [])
        XCTAssertEqual(credentialCount, 0)
        XCTAssertEqual(metadataCount, 0)
    }

    func testAddAccountRollsBackCredentialAndMetadataWhenIndexSaveFails() async throws {
        let store = ControllableRegistryStore(failingOperations: [.saveAccountIDs])
        let registry = WebexClientRegistry(store: store, httpClient: RegistryHTTPClient())

        do {
            _ = try await registry.addAccount(
                configuration: configuration(clientID: "client-1"),
                metadata: WebexAccountMetadata(email: "user@example.com"),
                now: Date(timeIntervalSince1970: 1)
            )
            XCTFail("Expected index save failure")
        } catch ControllableRegistryStoreError.requestedFailure(let operation) {
            XCTAssertEqual(operation, "saveAccountIDs")
        }

        let accountIDs = try await store.loadAccountIDs()
        let credentialCount = await store.credentialCount()
        let metadataCount = await store.metadataCount()
        XCTAssertEqual(accountIDs, [])
        XCTAssertEqual(credentialCount, 0)
        XCTAssertEqual(metadataCount, 0)
    }

    func testRemoveAccountDoesNotDeleteRecordsWhenIndexSaveFails() async throws {
        let accountID = WebexAccountID()
        let store = ControllableRegistryStore(
            credentials: [accountID: credential(clientID: "client-1")],
            tokenRecords: [accountID: tokenRecord(now: Date(timeIntervalSince1970: 1))],
            metadataRecords: [accountID: WebexAccountMetadata(email: "user@example.com")],
            accountIDs: [accountID],
            failingOperations: [.saveAccountIDs]
        )
        let registry = WebexClientRegistry(store: store, httpClient: RegistryHTTPClient())

        do {
            try await registry.removeAccount(accountID)
            XCTFail("Expected index save failure")
        } catch ControllableRegistryStoreError.requestedFailure(let operation) {
            XCTAssertEqual(operation, "saveAccountIDs")
        }

        let accountIDs = try await store.loadAccountIDs()
        let credential = try await store.loadCredential(for: accountID)
        let token = try await store.loadTokenRecord(for: accountID)
        let metadata = try await store.loadMetadata(for: accountID)
        XCTAssertEqual(accountIDs, [accountID])
        XCTAssertNotNil(credential)
        XCTAssertNotNil(token)
        XCTAssertNotNil(metadata)
    }

    func testRemoveAccountRemovesIndexBeforeBestEffortDeleteFailure() async throws {
        let accountID = WebexAccountID()
        let store = ControllableRegistryStore(
            credentials: [accountID: credential(clientID: "client-1")],
            tokenRecords: [accountID: tokenRecord(now: Date(timeIntervalSince1970: 1))],
            metadataRecords: [accountID: WebexAccountMetadata(email: "user@example.com")],
            accountIDs: [accountID],
            failingOperations: [.deleteCredential]
        )
        let registry = WebexClientRegistry(store: store, httpClient: RegistryHTTPClient())

        do {
            try await registry.removeAccount(accountID)
            XCTFail("Expected credential delete failure")
        } catch ControllableRegistryStoreError.requestedFailure(let operation) {
            XCTAssertEqual(operation, "deleteCredential")
        }

        let accountIDs = try await store.loadAccountIDs()
        let credential = try await store.loadCredential(for: accountID)
        let token = try await store.loadTokenRecord(for: accountID)
        let metadata = try await store.loadMetadata(for: accountID)
        XCTAssertEqual(accountIDs, [])
        XCTAssertNotNil(credential)
        XCTAssertNil(token)
        XCTAssertNil(metadata)
    }

    func testSameEmailOnlyIsAllowedAndBothIDsRemainIndexed() async throws {
        let store = InMemoryWebexStore()
        let registry = WebexClientRegistry(store: store, httpClient: RegistryHTTPClient())

        let first = try await registry.addAccount(
            configuration: configuration(clientID: "client-1"),
            metadata: WebexAccountMetadata(email: "same@example.com"),
            now: Date(timeIntervalSince1970: 1)
        )
        let second = try await registry.addAccount(
            configuration: configuration(clientID: "client-1"),
            metadata: WebexAccountMetadata(email: "same@example.com"),
            now: Date(timeIntervalSince1970: 2)
        )

        XCTAssertNotEqual(first.id, second.id)
        let accountIDs = try await store.loadAccountIDs()
        XCTAssertEqual(accountIDs, [first.id, second.id])
    }

    func testSameWebexUserIDWithDifferentClientIDIsAllowed() async throws {
        let store = InMemoryWebexStore()
        let registry = WebexClientRegistry(store: store, httpClient: RegistryHTTPClient())

        let first = try await registry.addAccount(
            configuration: configuration(clientID: "client-1"),
            metadata: WebexAccountMetadata(webexUserID: "webex-user-1"),
            now: Date(timeIntervalSince1970: 1)
        )
        let second = try await registry.addAccount(
            configuration: configuration(clientID: "client-2"),
            metadata: WebexAccountMetadata(webexUserID: "webex-user-1"),
            now: Date(timeIntervalSince1970: 2)
        )

        let accountIDs = try await store.loadAccountIDs()
        XCTAssertEqual(accountIDs, [first.id, second.id])
    }

    func testNoPostAuthIdentifiersAreAllowed() async throws {
        let store = InMemoryWebexStore()
        let registry = WebexClientRegistry(store: store, httpClient: RegistryHTTPClient())

        let first = try await registry.addAccount(
            configuration: configuration(clientID: "client-1"),
            metadata: WebexAccountMetadata(),
            now: Date(timeIntervalSince1970: 1)
        )
        let second = try await registry.addAccount(
            configuration: configuration(clientID: "client-1"),
            metadata: WebexAccountMetadata(),
            now: Date(timeIntervalSince1970: 2)
        )

        let accountIDs = try await store.loadAccountIDs()
        XCTAssertEqual(accountIDs, [first.id, second.id])
    }

    private func captureResult<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }

    private func configuration(
        clientID: String,
        clientSecret: String = "client-secret",
        scopes: [String] = ["openid"],
        redirectURI: URL = URL(string: "myapp://oauth/webex")!,
        prefersEphemeralWebBrowserSession: Bool = false
    ) -> WebexIntegrationConfiguration {
        WebexIntegrationConfiguration(
            clientID: clientID,
            clientSecret: clientSecret,
            redirectURI: redirectURI,
            scopes: scopes,
            prefersEphemeralWebBrowserSession: prefersEphemeralWebBrowserSession
        )
    }

    private func credential(clientID: String) -> WebexCredentialRecord {
        WebexCredentialRecord(
            clientID: clientID,
            clientSecret: "client-secret",
            redirectURI: URL(string: "myapp://oauth/webex")!,
            scopes: ["openid"],
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }

    private func tokenRecord(now: Date) -> WebexTokenRecord {
        WebexTokenRecord(
            refreshToken: "refresh-token",
            refreshTokenExpiresAt: now.addingTimeInterval(3_600),
            lastAccessTokenExpiresAt: now.addingTimeInterval(600),
            grantedScopes: ["openid"],
            tokenType: "Bearer",
            lastRefreshAt: now
        )
    }

    private func tokenHTTPResponse(accessToken: String, refreshToken: String) -> HTTPResponse {
        httpResponse(
            url: URL(string: "https://webexapis.com/v1/access_token")!,
            statusCode: 200,
            body: """
            {"access_token":"\(accessToken)","expires_in":600,"refresh_token":"\(refreshToken)","refresh_token_expires_in":3600,"token_type":"Bearer","scope":"openid spark:people_read"}
            """
        )
    }

    private func httpResponse(
        url: URL,
        statusCode: Int,
        headers: [String: String] = [:],
        body: String
    ) -> HTTPResponse {
        HTTPResponse(
            data: Data(body.utf8),
            response: HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
        )
    }

    private func assertNoSecretLeak(
        in output: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for secret in ["client-secret", "existing-client-secret", "new-client-secret", "refresh-token", "access-token"] {
            XCTAssertFalse(output.contains(secret), "Leaked \(secret)", file: file, line: line)
        }
    }
}

private enum ControllableRegistryStoreError: Error, Equatable {
    case requestedFailure(String)
}

private enum ControllableRegistryStoreOperation: Hashable, Sendable {
    case saveCredential
    case saveMetadata
    case saveAccountIDs
    case deleteCredential
    case deleteTokenRecord
    case deleteMetadata
}

private actor ControllableRegistryStore: WebexClientRegistryStore {
    private var credentials: [WebexAccountID: WebexCredentialRecord]
    private var tokenRecords: [WebexAccountID: WebexTokenRecord]
    private var metadataRecords: [WebexAccountID: WebexAccountMetadata]
    private var accountIDs: [WebexAccountID]
    private let failingOperations: Set<ControllableRegistryStoreOperation>
    private var emptyIndexLoadDelayCount: Int
    private var loadAccountIDsDelayCount: Int

    init(
        credentials: [WebexAccountID: WebexCredentialRecord] = [:],
        tokenRecords: [WebexAccountID: WebexTokenRecord] = [:],
        metadataRecords: [WebexAccountID: WebexAccountMetadata] = [:],
        accountIDs: [WebexAccountID] = [],
        failingOperations: Set<ControllableRegistryStoreOperation> = [],
        emptyIndexLoadDelayCount: Int = 0,
        loadAccountIDsDelayCount: Int = 0
    ) {
        self.credentials = credentials
        self.tokenRecords = tokenRecords
        self.metadataRecords = metadataRecords
        self.accountIDs = accountIDs
        self.failingOperations = failingOperations
        self.emptyIndexLoadDelayCount = emptyIndexLoadDelayCount
        self.loadAccountIDsDelayCount = loadAccountIDsDelayCount
    }

    func credentialCount() -> Int {
        credentials.count
    }

    func metadataCount() -> Int {
        metadataRecords.count
    }

    func loadCredential(for accountID: WebexAccountID) async throws -> WebexCredentialRecord? {
        credentials[accountID]
    }

    func saveCredential(_ credential: WebexCredentialRecord, for accountID: WebexAccountID) async throws {
        try failIfNeeded(.saveCredential)
        credentials[accountID] = credential
    }

    func deleteCredential(for accountID: WebexAccountID) async throws {
        try failIfNeeded(.deleteCredential)
        credentials[accountID] = nil
    }

    func loadTokenRecord(for accountID: WebexAccountID) async throws -> WebexTokenRecord? {
        tokenRecords[accountID]
    }

    func saveTokenRecord(_ tokenRecord: WebexTokenRecord, for accountID: WebexAccountID) async throws {
        tokenRecords[accountID] = tokenRecord
    }

    func deleteTokenRecord(for accountID: WebexAccountID) async throws {
        try failIfNeeded(.deleteTokenRecord)
        tokenRecords[accountID] = nil
    }

    func loadMetadata(for accountID: WebexAccountID) async throws -> WebexAccountMetadata? {
        metadataRecords[accountID]
    }

    func saveMetadata(_ metadata: WebexAccountMetadata, for accountID: WebexAccountID) async throws {
        try failIfNeeded(.saveMetadata)
        metadataRecords[accountID] = metadata
    }

    func deleteMetadata(for accountID: WebexAccountID) async throws {
        try failIfNeeded(.deleteMetadata)
        metadataRecords[accountID] = nil
    }

    func loadAccountIDs() async throws -> [WebexAccountID] {
        if loadAccountIDsDelayCount > 0 {
            loadAccountIDsDelayCount -= 1
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        if accountIDs.isEmpty, emptyIndexLoadDelayCount > 0 {
            emptyIndexLoadDelayCount -= 1
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        return accountIDs
    }

    func saveAccountIDs(_ accountIDs: [WebexAccountID]) async throws {
        try failIfNeeded(.saveAccountIDs)
        var seenAccountIDs = Set<WebexAccountID>()
        self.accountIDs = accountIDs.filter { accountID in
            seenAccountIDs.insert(accountID).inserted
        }
    }

    func addAccount(
        accountID: WebexAccountID,
        credential: WebexCredentialRecord,
        metadata: WebexAccountMetadata
    ) async throws {
        try Task.checkCancellation()
        try WebexAccountDuplicateDetector.validateNoDuplicate(
            candidateCredential: credential,
            candidateMetadata: metadata,
            existingAccountIDs: accountIDs,
            loadCredential: { credentials[$0] },
            loadMetadata: { metadataRecords[$0] }
        )

        do {
            try failIfNeeded(.saveCredential)
            credentials[accountID] = credential

            try failIfNeeded(.saveMetadata)
            metadataRecords[accountID] = metadata

            try failIfNeeded(.saveAccountIDs)
            saveAccountID(accountID)
        } catch {
            credentials[accountID] = nil
            tokenRecords[accountID] = nil
            metadataRecords[accountID] = nil
            accountIDs.removeAll { $0 == accountID }
            throw error
        }
    }

    func removeAccount(accountID: WebexAccountID) async throws {
        try Task.checkCancellation()
        try failIfNeeded(.saveAccountIDs)
        accountIDs.removeAll { $0 == accountID }

        var firstDeleteError: Error?
        do {
            try failIfNeeded(.deleteCredential)
            credentials[accountID] = nil
        } catch {
            firstDeleteError = firstDeleteError ?? error
        }

        do {
            try failIfNeeded(.deleteTokenRecord)
            tokenRecords[accountID] = nil
        } catch {
            firstDeleteError = firstDeleteError ?? error
        }

        do {
            try failIfNeeded(.deleteMetadata)
            metadataRecords[accountID] = nil
        } catch {
            firstDeleteError = firstDeleteError ?? error
        }

        if let firstDeleteError {
            throw firstDeleteError
        }
    }

    private func saveAccountID(_ accountID: WebexAccountID) {
        guard !accountIDs.contains(accountID) else {
            return
        }

        accountIDs.append(accountID)
    }

    private func failIfNeeded(_ operation: ControllableRegistryStoreOperation) throws {
        guard failingOperations.contains(operation) else {
            return
        }

        throw ControllableRegistryStoreError.requestedFailure(String(describing: operation))
    }
}

private actor RegistryHTTPClient: HTTPClient {
    private enum Result: Sendable {
        case response(HTTPResponse)
    }

    private var results: [Result] = []
    private var requests: [URLRequest] = []

    func enqueue(response: HTTPResponse) {
        results.append(.response(response))
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard !results.isEmpty else {
            throw WebexSDKError.network("Unexpected registry request")
        }

        switch results.removeFirst() {
        case .response(let response):
            return response
        }
    }
}

private struct FakeOAuthCallbackReceiver: OAuthCallbackReceiver {
    let callbackURL: URL

    func receiveCallback() async throws -> URL {
        callbackURL
    }
}

private actor AuthorizationURLOpener {
    private var url: URL?

    func open(_ url: URL) {
        self.url = url
    }

    func openedURL() throws -> URL {
        try XCTUnwrap(url)
    }
}

private extension Array where Element == URLQueryItem {
    func firstValue(named name: String) -> String? {
        first { $0.name == name }?.value
    }
}
