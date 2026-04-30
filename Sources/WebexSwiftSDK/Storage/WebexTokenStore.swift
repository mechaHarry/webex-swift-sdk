import Foundation

public struct WebexTokenRecord: Equatable, Codable, Sendable {
    public let refreshToken: String
    public let refreshTokenExpiresAt: Date
    public let lastAccessTokenExpiresAt: Date
    public let grantedScopes: [String]
    public let tokenType: String
    public let lastRefreshAt: Date

    public init(
        refreshToken: String,
        refreshTokenExpiresAt: Date,
        lastAccessTokenExpiresAt: Date,
        grantedScopes: [String],
        tokenType: String,
        lastRefreshAt: Date
    ) {
        self.refreshToken = refreshToken
        self.refreshTokenExpiresAt = refreshTokenExpiresAt
        self.lastAccessTokenExpiresAt = lastAccessTokenExpiresAt
        self.grantedScopes = Self.normalizedScopes(grantedScopes)
        self.tokenType = tokenType
        self.lastRefreshAt = lastRefreshAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            refreshToken: try container.decode(String.self, forKey: .refreshToken),
            refreshTokenExpiresAt: try container.decode(Date.self, forKey: .refreshTokenExpiresAt),
            lastAccessTokenExpiresAt: try container.decode(Date.self, forKey: .lastAccessTokenExpiresAt),
            grantedScopes: try container.decode([String].self, forKey: .grantedScopes),
            tokenType: try container.decode(String.self, forKey: .tokenType),
            lastRefreshAt: try container.decode(Date.self, forKey: .lastRefreshAt)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case refreshToken
        case refreshTokenExpiresAt
        case lastAccessTokenExpiresAt
        case grantedScopes
        case tokenType
        case lastRefreshAt
    }

    private static func normalizedScopes(_ scopes: [String]) -> [String] {
        let normalizedScopes = scopes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(normalizedScopes)).sorted()
    }
}

extension WebexTokenRecord: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        redactedDescription
    }

    public var debugDescription: String {
        redactedDescription
    }

    private var redactedDescription: String {
        [
            "WebexTokenRecord(",
            "refreshToken: [redacted], ",
            "refreshTokenExpiresAt: \(refreshTokenExpiresAt), ",
            "lastAccessTokenExpiresAt: \(lastAccessTokenExpiresAt), ",
            "grantedScopes: \(grantedScopes), ",
            "tokenType: \(tokenType), ",
            "lastRefreshAt: \(lastRefreshAt)",
            ")"
        ].joined()
    }
}

public protocol WebexTokenStore: Sendable {
    func loadTokenRecord(for accountID: WebexAccountID) async throws -> WebexTokenRecord?
    func saveTokenRecord(_ tokenRecord: WebexTokenRecord, for accountID: WebexAccountID) async throws
    func deleteTokenRecord(for accountID: WebexAccountID) async throws
}
