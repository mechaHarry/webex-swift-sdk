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

    public func removeAccount(_ accountID: WebexAccountID) async throws {
        try Task.checkCancellation()
        try await store.removeAccount(accountID: accountID)
    }
}
