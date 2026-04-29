public actor InMemoryWebexStore: WebexCredentialStore, WebexTokenStore, WebexAccountMetadataStore, WebexAccountIndexStore {
    private var credentials: [WebexAccountID: WebexCredentialRecord]
    private var tokenRecords: [WebexAccountID: WebexTokenRecord]
    private var metadataRecords: [WebexAccountID: WebexAccountMetadata]
    private var accountIDs: [WebexAccountID]

    public init(
        credentials: [WebexAccountID: WebexCredentialRecord] = [:],
        tokenRecords: [WebexAccountID: WebexTokenRecord] = [:],
        metadataRecords: [WebexAccountID: WebexAccountMetadata] = [:],
        accountIDs: [WebexAccountID] = []
    ) {
        self.credentials = credentials
        self.tokenRecords = tokenRecords
        self.metadataRecords = metadataRecords
        self.accountIDs = accountIDs
    }

    public func loadCredential(for accountID: WebexAccountID) async throws -> WebexCredentialRecord? {
        credentials[accountID]
    }

    public func saveCredential(_ credential: WebexCredentialRecord, for accountID: WebexAccountID) async throws {
        credentials[accountID] = credential
    }

    public func deleteCredential(for accountID: WebexAccountID) async throws {
        credentials[accountID] = nil
    }

    public func loadTokenRecord(for accountID: WebexAccountID) async throws -> WebexTokenRecord? {
        tokenRecords[accountID]
    }

    public func saveTokenRecord(_ tokenRecord: WebexTokenRecord, for accountID: WebexAccountID) async throws {
        tokenRecords[accountID] = tokenRecord
    }

    public func deleteTokenRecord(for accountID: WebexAccountID) async throws {
        tokenRecords[accountID] = nil
    }

    public func loadMetadata(for accountID: WebexAccountID) async throws -> WebexAccountMetadata? {
        metadataRecords[accountID]
    }

    public func saveMetadata(_ metadata: WebexAccountMetadata, for accountID: WebexAccountID) async throws {
        metadataRecords[accountID] = metadata
    }

    public func deleteMetadata(for accountID: WebexAccountID) async throws {
        metadataRecords[accountID] = nil
    }

    public func loadAccountIDs() async throws -> [WebexAccountID] {
        accountIDs
    }

    public func saveAccountIDs(_ accountIDs: [WebexAccountID]) async throws {
        var seenAccountIDs = Set<WebexAccountID>()
        self.accountIDs = accountIDs.filter { accountID in
            seenAccountIDs.insert(accountID).inserted
        }
    }
}
