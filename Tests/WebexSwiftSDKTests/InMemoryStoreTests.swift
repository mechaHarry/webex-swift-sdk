import XCTest
@testable import WebexSwiftSDK

final class InMemoryStoreTests: XCTestCase {
    func testCredentialRecordRoundTripsByAccountID() async throws {
        let accountID = WebexAccountID()
        let store = InMemoryWebexStore()
        let credential = WebexCredentialRecord(
            clientID: "client-id-value",
            clientSecret: "client-secret-value",
            redirectURI: URL(string: "myapp://oauth/webex")!,
            scopes: ["openid"],
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )

        try await store.saveCredential(credential, for: accountID)

        let loadedCredential = try await store.loadCredential(for: accountID)
        XCTAssertEqual(loadedCredential, credential)
    }

    func testCredentialRecordCodableRoundTripsWithSortedScopes() throws {
        let credential = WebexCredentialRecord(
            clientID: "client-id-value",
            clientSecret: "client-secret-value",
            redirectURI: URL(string: "myapp://oauth/webex")!,
            scopes: ["spark:people_read", " openid ", "spark:people_read"],
            prefersEphemeralWebBrowserSession: true,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )

        let data = try JSONEncoder().encode(credential)
        let decoded = try JSONDecoder().decode(WebexCredentialRecord.self, from: data)

        XCTAssertEqual(decoded, credential)
        XCTAssertEqual(decoded.scopes, ["openid", "spark:people_read"])
        XCTAssertTrue(decoded.prefersEphemeralWebBrowserSession)
    }

    func testCredentialRecordConfigurationUsesStoredCredentialFields() {
        let credential = WebexCredentialRecord(
            clientID: "client-id-value",
            clientSecret: "client-secret-value",
            redirectURI: URL(string: "myapp://oauth/webex")!,
            scopes: ["spark:people_read", "openid"],
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )

        let configuration = credential.configuration

        XCTAssertEqual(configuration.clientID, "client-id-value")
        XCTAssertEqual(configuration.clientSecret, "client-secret-value")
        XCTAssertEqual(configuration.redirectURI, URL(string: "myapp://oauth/webex")!)
        XCTAssertEqual(configuration.scopes, ["openid", "spark:people_read"])
        XCTAssertFalse(configuration.prefersEphemeralWebBrowserSession)
    }

    func testCredentialRecordConfigurationPreservesEphemeralBrowserPreference() {
        let credential = WebexCredentialRecord(
            clientID: "client-id-value",
            clientSecret: "client-secret-value",
            redirectURI: URL(string: "myapp://oauth/webex")!,
            scopes: ["openid"],
            prefersEphemeralWebBrowserSession: true,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )

        let configuration = credential.configuration

        XCTAssertTrue(configuration.prefersEphemeralWebBrowserSession)
    }

    func testTokenRecordDoesNotRequirePersistedAccessToken() async throws {
        let accountID = WebexAccountID()
        let store = InMemoryWebexStore()
        let token = WebexTokenRecord(
            refreshToken: "refresh",
            refreshTokenExpiresAt: Date(timeIntervalSince1970: 100),
            lastAccessTokenExpiresAt: Date(timeIntervalSince1970: 10),
            grantedScopes: ["openid"],
            tokenType: "Bearer",
            lastRefreshAt: Date(timeIntervalSince1970: 5)
        )

        try await store.saveTokenRecord(token, for: accountID)

        let loadedToken = try await store.loadTokenRecord(for: accountID)
        XCTAssertEqual(loadedToken, token)
    }

    func testTokenRecordCodableRoundTripsWithSortedGrantedScopes() throws {
        let token = WebexTokenRecord(
            refreshToken: "refresh",
            refreshTokenExpiresAt: Date(timeIntervalSince1970: 100),
            lastAccessTokenExpiresAt: Date(timeIntervalSince1970: 10),
            grantedScopes: ["spark:people_read", " openid ", "spark:people_read"],
            tokenType: "Bearer",
            lastRefreshAt: Date(timeIntervalSince1970: 5)
        )

        let data = try JSONEncoder().encode(token)
        let decoded = try JSONDecoder().decode(WebexTokenRecord.self, from: data)

        XCTAssertEqual(decoded, token)
        XCTAssertEqual(decoded.grantedScopes, ["openid", "spark:people_read"])
    }

    func testTokenRecordEncodedJSONDoesNotPersistAccessToken() throws {
        let accessToken = "access-token-value"
        let token = WebexTokenRecord(
            refreshToken: "refresh-token-value",
            refreshTokenExpiresAt: Date(timeIntervalSince1970: 100),
            lastAccessTokenExpiresAt: Date(timeIntervalSince1970: 10),
            grantedScopes: ["openid"],
            tokenType: "Bearer",
            lastRefreshAt: Date(timeIntervalSince1970: 5)
        )

        let data = try JSONEncoder().encode(token)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertFalse(json.contains("accessToken"))
        XCTAssertFalse(json.contains(accessToken))
    }

    func testDeleteRemovesCredentialTokenAndMetadataRecordsForAccount() async throws {
        let accountID = WebexAccountID()
        let store = InMemoryWebexStore()
        let credential = WebexCredentialRecord(
            clientID: "client-id-value",
            clientSecret: "client-secret-value",
            redirectURI: URL(string: "myapp://oauth/webex")!,
            scopes: ["openid"],
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        let token = WebexTokenRecord(
            refreshToken: "refresh",
            refreshTokenExpiresAt: Date(timeIntervalSince1970: 100),
            lastAccessTokenExpiresAt: Date(timeIntervalSince1970: 10),
            grantedScopes: ["openid"],
            tokenType: "Bearer",
            lastRefreshAt: Date(timeIntervalSince1970: 5)
        )

        try await store.saveCredential(credential, for: accountID)
        try await store.saveTokenRecord(token, for: accountID)
        try await store.saveMetadata(WebexAccountMetadata(email: "user@example.com"), for: accountID)
        try await store.deleteCredential(for: accountID)
        try await store.deleteTokenRecord(for: accountID)
        try await store.deleteMetadata(for: accountID)

        let loadedCredential = try await store.loadCredential(for: accountID)
        let loadedToken = try await store.loadTokenRecord(for: accountID)
        let loadedMetadata = try await store.loadMetadata(for: accountID)
        XCTAssertNil(loadedCredential)
        XCTAssertNil(loadedToken)
        XCTAssertNil(loadedMetadata)
    }

    func testUnknownAccountLoadsReturnNil() async throws {
        let store = InMemoryWebexStore()
        let unknownAccountID = WebexAccountID()

        let loadedCredential = try await store.loadCredential(for: unknownAccountID)
        let loadedToken = try await store.loadTokenRecord(for: unknownAccountID)
        let loadedMetadata = try await store.loadMetadata(for: unknownAccountID)

        XCTAssertNil(loadedCredential)
        XCTAssertNil(loadedToken)
        XCTAssertNil(loadedMetadata)
    }

    func testAccountIndexRoundTripsPersistedIDs() async throws {
        let first = WebexAccountID()
        let second = WebexAccountID()
        let store = InMemoryWebexStore()

        try await store.saveAccountIDs([first, second])

        let loadedAccountIDs = try await store.loadAccountIDs()
        XCTAssertEqual(loadedAccountIDs, [first, second])
    }

    func testAccountIndexDeduplicatesPersistedIDsWhilePreservingOrder() async throws {
        let first = WebexAccountID()
        let second = WebexAccountID()
        let third = WebexAccountID()
        let store = InMemoryWebexStore()

        try await store.saveAccountIDs([first, second, first, third, second])

        let loadedAccountIDs = try await store.loadAccountIDs()
        XCTAssertEqual(loadedAccountIDs, [first, second, third])
    }

    func testCredentialRecordDescriptionsRedactClientSecret() {
        let credential = WebexCredentialRecord(
            clientID: "client-id-value",
            clientSecret: "client-secret-value",
            redirectURI: URL(string: "myapp://oauth/webex")!,
            scopes: ["openid"],
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )

        let description = String(describing: credential)
        let debugDescription = String(reflecting: credential)

        for output in [description, debugDescription] {
            XCTAssertFalse(output.contains("client-secret-value"))
            XCTAssertTrue(output.contains("client-id-value"))
            XCTAssertTrue(output.contains("[redacted]"))
        }
    }

    func testTokenRecordDescriptionsRedactRefreshToken() {
        let token = WebexTokenRecord(
            refreshToken: "refresh-secret-value",
            refreshTokenExpiresAt: Date(timeIntervalSince1970: 100),
            lastAccessTokenExpiresAt: Date(timeIntervalSince1970: 10),
            grantedScopes: ["openid"],
            tokenType: "Bearer",
            lastRefreshAt: Date(timeIntervalSince1970: 5)
        )

        let description = String(describing: token)
        let debugDescription = String(reflecting: token)

        for output in [description, debugDescription] {
            XCTAssertFalse(output.contains("refresh-secret-value"))
            XCTAssertTrue(output.contains("Bearer"))
            XCTAssertTrue(output.contains("[redacted]"))
        }
    }
}
