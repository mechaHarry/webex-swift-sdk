public protocol WebexAccountIndexStore: Sendable {
    func loadAccountIDs() async throws -> [WebexAccountID]
    func saveAccountIDs(_ accountIDs: [WebexAccountID]) async throws
}
