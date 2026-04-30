import Security
import XCTest
@testable import WebexSwiftSDK

final class KeychainStoreServiceTests: XCTestCase {
    func testDefaultServiceUsesHostBundleIdentifier() {
        let service = KeychainWebexStoreService.defaultService(
            bundleIdentifier: "com.example.host-app",
            processName: "ignored-process",
            executablePath: "/usr/local/bin/ignored"
        )

        XCTAssertEqual(service, "com.example.host-app.webex-swift-sdk")
    }

    func testDefaultServiceFallbackUsesProcessNameAndExecutablePathFingerprint() {
        let service = KeychainWebexStoreService.defaultService(
            bundleIdentifier: nil,
            processName: "webex-sdk-tool",
            executablePath: "/usr/local/bin/webex-sdk-tool"
        )

        XCTAssertTrue(service.hasPrefix("process.webex-sdk-tool."))
        XCTAssertTrue(service.hasSuffix(".webex-swift-sdk"))
        XCTAssertNotEqual(service, "process.webex-sdk-tool.webex-swift-sdk")
    }

    func testDefaultServiceFallbackSeparatesSameProcessNameAtDifferentPaths() {
        let first = KeychainWebexStoreService.defaultService(
            bundleIdentifier: nil,
            processName: "webex-sdk-tool",
            executablePath: "/Applications/First/webex-sdk-tool"
        )
        let second = KeychainWebexStoreService.defaultService(
            bundleIdentifier: nil,
            processName: "webex-sdk-tool",
            executablePath: "/Applications/Second/webex-sdk-tool"
        )

        XCTAssertNotEqual(first, second)
    }

    func testDefaultServiceFallbackSanitizesProcessNameAndUsesDeterministicNilPathFallback() {
        let first = KeychainWebexStoreService.defaultService(
            bundleIdentifier: "",
            processName: "Webex SDK Tool!",
            executablePath: nil
        )
        let second = KeychainWebexStoreService.defaultService(
            bundleIdentifier: "",
            processName: "Webex SDK Tool!",
            executablePath: nil
        )

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.hasPrefix("process.Webex-SDK-Tool-."))
        XCTAssertTrue(first.hasSuffix(".webex-swift-sdk"))
        XCTAssertNotEqual(first, "com.webex.swift-sdk")
    }

    func testDefaultServiceFallbackContainsOnlyKeychainSafeCharacters() {
        let service = KeychainWebexStoreService.defaultService(
            bundleIdentifier: "",
            processName: "Webex SDK Tool!",
            executablePath: "/tmp/Webex SDK Tool!"
        )
        let safeCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))

        XCTAssertTrue(service.unicodeScalars.allSatisfy { safeCharacters.contains($0) })
    }
}

final class KeychainStoreTests: XCTestCase {
    private var service: String!
    private var store: KeychainWebexStore!
    private var cleanupAccountIDs: [WebexAccountID] = []

    override func setUpWithError() throws {
        try skipUnlessKeychainTestsEnabled()
        service = "com.webex.swift-sdk.tests.\(ProcessInfo.processInfo.processIdentifier).\(UUID().uuidString)"
        store = KeychainWebexStore(service: service)
    }

    override func tearDown() async throws {
        if let store {
            for accountID in cleanupAccountIDs {
                try await store.deleteCredential(for: accountID)
                try await store.deleteTokenRecord(for: accountID)
                try await store.deleteMetadata(for: accountID)
            }
            try await store.deleteAccountIndex()
        }

        cleanupAccountIDs = []
        store = nil
        service = nil
    }

    func testCredentialTokenAndMetadataRoundTripByAccountID() async throws {
        let accountID = track(WebexAccountID())
        let credential = Self.credential()
        let token = Self.tokenRecord()
        let metadata = WebexAccountMetadata(
            webexUserID: "webex-user-1",
            oidcSubject: "subject-1",
            email: "person@example.com",
            displayName: "Person One",
            organizationID: "org-1",
            lastVerifiedAt: Date(timeIntervalSince1970: 1_776_000_000.125)
        )

        try await store.saveCredential(credential, for: accountID)
        try await store.saveTokenRecord(token, for: accountID)
        try await store.saveMetadata(metadata, for: accountID)

        let loadedCredential = try await store.loadCredential(for: accountID)
        let loadedToken = try await store.loadTokenRecord(for: accountID)
        let loadedMetadata = try await store.loadMetadata(for: accountID)

        XCTAssertEqual(loadedCredential, credential)
        XCTAssertEqual(loadedToken, token)
        XCTAssertEqual(loadedMetadata, metadata)
    }

    func testSavesUpdateExistingItemsWithoutChangingRecordShape() async throws {
        let accountID = track(WebexAccountID())
        let firstCredential = Self.credential(clientID: "client-1", updatedAt: Date(timeIntervalSince1970: 2.25))
        let secondCredential = Self.credential(clientID: "client-2", updatedAt: Date(timeIntervalSince1970: 3.5))
        let firstToken = Self.tokenRecord(refreshToken: "refresh-1", lastRefreshAt: Date(timeIntervalSince1970: 10.25))
        let secondToken = Self.tokenRecord(refreshToken: "refresh-2", lastRefreshAt: Date(timeIntervalSince1970: 20.5))
        let firstMetadata = WebexAccountMetadata(email: "first@example.com")
        let secondMetadata = WebexAccountMetadata(email: "second@example.com", lastVerifiedAt: Date(timeIntervalSince1970: 30.75))

        try await store.saveCredential(firstCredential, for: accountID)
        try await store.saveTokenRecord(firstToken, for: accountID)
        try await store.saveMetadata(firstMetadata, for: accountID)
        try await store.saveCredential(secondCredential, for: accountID)
        try await store.saveTokenRecord(secondToken, for: accountID)
        try await store.saveMetadata(secondMetadata, for: accountID)

        let loadedCredential = try await store.loadCredential(for: accountID)
        let loadedToken = try await store.loadTokenRecord(for: accountID)
        let loadedMetadata = try await store.loadMetadata(for: accountID)

        XCTAssertEqual(loadedCredential, secondCredential)
        XCTAssertEqual(loadedToken, secondToken)
        XCTAssertEqual(loadedMetadata, secondMetadata)
    }

    func testAccountIndexRoundTripsAndDeduplicatesWhilePreservingOrder() async throws {
        let first = track(WebexAccountID())
        let second = track(WebexAccountID())
        let third = track(WebexAccountID())

        try await store.saveAccountIDs([first, second, first, third, second])

        let loadedAccountIDs = try await store.loadAccountIDs()
        XCTAssertEqual(loadedAccountIDs, [first, second, third])
    }

    func testMissingLoadsReturnNilOrEmptyArrayAndMissingDeletesDoNotThrow() async throws {
        let unknown = track(WebexAccountID())

        let loadedCredential = try await store.loadCredential(for: unknown)
        let loadedToken = try await store.loadTokenRecord(for: unknown)
        let loadedMetadata = try await store.loadMetadata(for: unknown)
        let loadedAccountIDs = try await store.loadAccountIDs()

        XCTAssertNil(loadedCredential)
        XCTAssertNil(loadedToken)
        XCTAssertNil(loadedMetadata)
        XCTAssertEqual(loadedAccountIDs, [])

        try await store.deleteCredential(for: unknown)
        try await store.deleteTokenRecord(for: unknown)
        try await store.deleteMetadata(for: unknown)
        try await store.deleteAccountIndex()
    }

    func testDeleteRemovesStoredRecords() async throws {
        let accountID = track(WebexAccountID())

        try await store.saveCredential(Self.credential(), for: accountID)
        try await store.saveTokenRecord(Self.tokenRecord(), for: accountID)
        try await store.saveMetadata(WebexAccountMetadata(email: "person@example.com"), for: accountID)
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

    func testKeychainErrorsDoNotExposeStoredSecretValues() async throws {
        let error = KeychainWebexStoreError.unhandledStatus(
            operation: "save",
            status: errSecAuthFailed,
            service: "service-without-secrets",
            account: "credential:\(WebexAccountID().rawValue)"
        )
        let description = String(describing: error)

        XCTAssertFalse(description.contains("client-secret-value"))
        XCTAssertFalse(description.contains("refresh-token-value"))
        XCTAssertTrue(description.contains(String(errSecAuthFailed)))
    }

    private func skipUnlessKeychainTestsEnabled() throws {
        guard ProcessInfo.processInfo.environment["WEBEX_SDK_RUN_KEYCHAIN_TESTS"] == "1" else {
            throw XCTSkip("Set WEBEX_SDK_RUN_KEYCHAIN_TESTS=1 to run keychain integration tests.")
        }
    }

    private func track(_ accountID: WebexAccountID) -> WebexAccountID {
        cleanupAccountIDs.append(accountID)
        return accountID
    }

    private static func credential(
        clientID: String = "client-id-value",
        updatedAt: Date = Date(timeIntervalSince1970: 2.5)
    ) -> WebexCredentialRecord {
        WebexCredentialRecord(
            clientID: clientID,
            clientSecret: "client-secret-value",
            redirectURI: URL(string: "myapp://oauth/webex")!,
            scopes: ["spark:people_read", " openid ", "spark:people_read"],
            prefersEphemeralWebBrowserSession: true,
            createdAt: Date(timeIntervalSince1970: 1.25),
            updatedAt: updatedAt
        )
    }

    private static func tokenRecord(
        refreshToken: String = "refresh-token-value",
        lastRefreshAt: Date = Date(timeIntervalSince1970: 5.125)
    ) -> WebexTokenRecord {
        WebexTokenRecord(
            refreshToken: refreshToken,
            refreshTokenExpiresAt: Date(timeIntervalSince1970: 100.25),
            lastAccessTokenExpiresAt: Date(timeIntervalSince1970: 10.5),
            grantedScopes: ["spark:people_read", "openid", "spark:people_read"],
            tokenType: "Bearer",
            lastRefreshAt: lastRefreshAt
        )
    }
}
