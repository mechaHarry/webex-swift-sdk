public protocol WebexAccountMetadataStore: Sendable {
    func loadMetadata(for accountID: WebexAccountID) async throws -> WebexAccountMetadata?
    func saveMetadata(_ metadata: WebexAccountMetadata, for accountID: WebexAccountID) async throws
    func deleteMetadata(for accountID: WebexAccountID) async throws
}
