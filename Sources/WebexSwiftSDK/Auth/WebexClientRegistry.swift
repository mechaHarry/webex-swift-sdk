import Foundation

public struct WebexAccountRecord: Equatable, Sendable {
    public let id: WebexAccountID
    public let metadata: WebexAccountMetadata

    public var accountID: WebexAccountID {
        id
    }

    public init(id: WebexAccountID, metadata: WebexAccountMetadata) {
        self.id = id
        self.metadata = metadata
    }

    public init(accountID: WebexAccountID, metadata: WebexAccountMetadata) {
        self.init(id: accountID, metadata: metadata)
    }
}

public struct WebexOAuthAuthorizedAccount: Sendable {
    public let account: WebexAccountRecord
    public let client: WebexClient
    public let accessTokenExpiresAt: Date
    public let refreshTokenExpiresAt: Date

    public init(
        account: WebexAccountRecord,
        client: WebexClient,
        accessTokenExpiresAt: Date,
        refreshTokenExpiresAt: Date
    ) {
        self.account = account
        self.client = client
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.refreshTokenExpiresAt = refreshTokenExpiresAt
    }
}

public protocol WebexClientRegistryStore: WebexCredentialStore, WebexTokenStore, WebexAccountMetadataStore, WebexAccountIndexStore {
    func addAccount(
        accountID: WebexAccountID,
        credential: WebexCredentialRecord,
        metadata: WebexAccountMetadata
    ) async throws

    func removeAccount(accountID: WebexAccountID) async throws
}

enum WebexAccountDuplicateDetector {
    static func validateNoDuplicate(
        candidateCredential: WebexCredentialRecord,
        candidateMetadata: WebexAccountMetadata,
        existingAccountIDs: [WebexAccountID],
        loadCredential: (WebexAccountID) throws -> WebexCredentialRecord?,
        loadMetadata: (WebexAccountID) throws -> WebexAccountMetadata?
    ) throws {
        guard candidateMetadata.webexUserID != nil || candidateMetadata.oidcSubject != nil else {
            return
        }

        for existingAccountID in existingAccountIDs {
            guard let existingCredential = try loadCredential(existingAccountID),
                  existingCredential.clientID == candidateCredential.clientID,
                  let existingMetadata = try loadMetadata(existingAccountID) else {
                continue
            }

            if let webexUserID = candidateMetadata.webexUserID,
               webexUserID == existingMetadata.webexUserID {
                throw WebexSDKError.duplicateAccount(
                    existing: existingAccountID,
                    reason: "matching Webex user ID for client ID \(candidateCredential.clientID)"
                )
            }

            if let oidcSubject = candidateMetadata.oidcSubject,
               oidcSubject == existingMetadata.oidcSubject {
                throw WebexSDKError.duplicateAccount(
                    existing: existingAccountID,
                    reason: "matching OIDC subject for client ID \(candidateCredential.clientID)"
                )
            }
        }
    }
}

public actor WebexClientRegistry {
    private let store: any WebexClientRegistryStore
    private let httpClient: any HTTPClient

    public init(
        store: any WebexClientRegistryStore = KeychainWebexStore(),
        httpClient: any HTTPClient = URLSessionHTTPClient()
    ) {
        self.store = store
        self.httpClient = httpClient
    }

    public func addAccount(
        configuration: WebexIntegrationConfiguration,
        metadata: WebexAccountMetadata = WebexAccountMetadata(),
        now: Date = Date()
    ) async throws -> WebexAccountRecord {
        try Task.checkCancellation()

        let accountID = WebexAccountID()
        let credential = WebexCredentialRecord(
            clientID: configuration.clientID,
            clientSecret: configuration.clientSecret,
            redirectURI: configuration.redirectURI,
            scopes: configuration.scopes,
            prefersEphemeralWebBrowserSession: configuration.prefersEphemeralWebBrowserSession,
            createdAt: now,
            updatedAt: now
        )

        try await store.addAccount(accountID: accountID, credential: credential, metadata: metadata)

        return WebexAccountRecord(id: accountID, metadata: metadata)
    }

    public func listAccounts() async throws -> [WebexAccountRecord] {
        let accountIDs = try await store.loadAccountIDs()
        var records: [WebexAccountRecord] = []
        records.reserveCapacity(accountIDs.count)

        for accountID in accountIDs {
            let metadata = try await store.loadMetadata(for: accountID) ?? WebexAccountMetadata()
            records.append(WebexAccountRecord(id: accountID, metadata: metadata))
        }

        return records
    }

    public func client(for accountID: WebexAccountID) async throws -> WebexClient {
        guard let credential = try await store.loadCredential(for: accountID) else {
            throw WebexSDKError.missingCredential(accountID)
        }

        return WebexClient(
            accountID: accountID,
            configuration: credential.configuration,
            tokenStore: store,
            httpClient: httpClient
        )
    }

    public func authorizeAndAddAccount(
        configuration: WebexIntegrationConfiguration,
        metadata: WebexAccountMetadata = WebexAccountMetadata(),
        now: Date = Date(),
        openAuthorizationURL: @escaping @Sendable (URL) async throws -> Void
    ) async throws -> WebexOAuthAuthorizedAccount {
        try await authorizeAndAddAccount(
            configuration: configuration,
            metadata: metadata,
            now: now,
            stateGenerator: { UUID().uuidString },
            codeVerifierGenerator: { try PKCE.generateVerifier() },
            clock: { Date() },
            callbackReceiver: WebexOAuthLoopbackRedirectListener(redirectURI: configuration.redirectURI),
            openAuthorizationURL: openAuthorizationURL
        )
    }

    func authorizeAndAddAccount(
        configuration: WebexIntegrationConfiguration,
        metadata: WebexAccountMetadata = WebexAccountMetadata(),
        now: Date = Date(),
        stateGenerator: @escaping @Sendable () -> String,
        codeVerifierGenerator: @escaping @Sendable () throws -> String,
        clock: @escaping @Sendable () -> Date,
        callbackReceiver: any OAuthCallbackReceiver,
        openAuthorizationURL: @escaping @Sendable (URL) async throws -> Void
    ) async throws -> WebexOAuthAuthorizedAccount {
        let account = try await addAccount(configuration: configuration, metadata: metadata, now: now)

        do {
            let codeVerifier = try codeVerifierGenerator()
            let state = stateGenerator()
            let authorizationURL = try WebexAuthorizationRequest(
                configuration: configuration,
                state: state,
                codeChallenge: PKCE.s256Challenge(for: codeVerifier)
            ).url()

            async let callbackURL = callbackReceiver.receiveCallback()
            try await openAuthorizationURL(authorizationURL)

            let authorizationCode = try OAuthCallbackParser.parse(
                callbackURL: try await callbackURL,
                expectedState: state
            )
            let tokenResponse = try await exchangeAuthorizationCode(
                authorizationCode.code,
                codeVerifier: codeVerifier,
                configuration: configuration
            )
            let receivedAt = clock()
            let tokenRecord = tokenResponse.tokenRecord(receivedAt: receivedAt)
            let accessToken = tokenResponse.accessTokenState(receivedAt: receivedAt)
            try await store.saveTokenRecord(tokenRecord, for: account.id)

            let client = WebexClient(
                accountID: account.id,
                configuration: configuration,
                tokenStore: store,
                httpClient: httpClient,
                initialAccessToken: accessToken,
                clock: clock
            )

            return WebexOAuthAuthorizedAccount(
                account: account,
                client: client,
                accessTokenExpiresAt: accessToken.expiresAt,
                refreshTokenExpiresAt: tokenRecord.refreshTokenExpiresAt
            )
        } catch {
            try? await removeAccount(account.id)
            throw error
        }
    }

    public func removeAccount(_ accountID: WebexAccountID) async throws {
        try Task.checkCancellation()
        try await store.removeAccount(accountID: accountID)
    }

    private func exchangeAuthorizationCode(
        _ code: String,
        codeVerifier: String,
        configuration: WebexIntegrationConfiguration
    ) async throws -> WebexTokenResponse {
        let request = try WebexTokenEndpoint.authorizationCodeRequest(
            configuration: configuration,
            code: code,
            codeVerifier: codeVerifier
        )
        let response = try await httpClient.send(request)
        guard (200..<300).contains(response.response.statusCode) else {
            let body = String(data: response.data, encoding: .utf8) ?? "<non-UTF8 response body>"
            throw WebexSDKError.tokenExchangeFailed(
                statusCode: response.response.statusCode,
                message: Redactor.redactSecrets(body),
                trackingID: response.response.value(forHTTPHeaderField: "trackingid")
            )
        }

        return try JSONDecoder().decode(WebexTokenResponse.self, from: response.data)
    }
}
