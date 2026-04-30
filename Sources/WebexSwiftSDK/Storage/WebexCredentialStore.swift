import Foundation

public struct WebexCredentialRecord: Equatable, Codable, Sendable {
    public let clientID: String
    public let clientSecret: String
    public let redirectURI: URL
    public let scopes: [String]
    public let prefersEphemeralWebBrowserSession: Bool
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        clientID: String,
        clientSecret: String,
        redirectURI: URL,
        scopes: [String],
        prefersEphemeralWebBrowserSession: Bool = false,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI
        self.scopes = Self.normalizedScopes(scopes)
        self.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var configuration: WebexIntegrationConfiguration {
        WebexIntegrationConfiguration(
            clientID: clientID,
            clientSecret: clientSecret,
            redirectURI: redirectURI,
            scopes: scopes,
            prefersEphemeralWebBrowserSession: prefersEphemeralWebBrowserSession
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            clientID: try container.decode(String.self, forKey: .clientID),
            clientSecret: try container.decode(String.self, forKey: .clientSecret),
            redirectURI: try container.decode(URL.self, forKey: .redirectURI),
            scopes: try container.decode([String].self, forKey: .scopes),
            prefersEphemeralWebBrowserSession: try container.decodeIfPresent(Bool.self, forKey: .prefersEphemeralWebBrowserSession) ?? false,
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case clientID
        case clientSecret
        case redirectURI
        case scopes
        case prefersEphemeralWebBrowserSession
        case createdAt
        case updatedAt
    }

    private static func normalizedScopes(_ scopes: [String]) -> [String] {
        let normalizedScopes = scopes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(normalizedScopes)).sorted()
    }
}

extension WebexCredentialRecord: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        redactedDescription
    }

    public var debugDescription: String {
        redactedDescription
    }

    private var redactedDescription: String {
        [
            "WebexCredentialRecord(",
            "clientID: \(clientID), ",
            "clientSecret: [redacted], ",
            "redirectURI: \(redirectURI.absoluteString), ",
            "scopes: \(scopes), ",
            "prefersEphemeralWebBrowserSession: \(prefersEphemeralWebBrowserSession), ",
            "createdAt: \(createdAt), ",
            "updatedAt: \(updatedAt)",
            ")"
        ].joined()
    }
}

public protocol WebexCredentialStore: Sendable {
    func loadCredential(for accountID: WebexAccountID) async throws -> WebexCredentialRecord?
    func saveCredential(_ credential: WebexCredentialRecord, for accountID: WebexAccountID) async throws
    func deleteCredential(for accountID: WebexAccountID) async throws
}
