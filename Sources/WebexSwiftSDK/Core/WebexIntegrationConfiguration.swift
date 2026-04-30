import Foundation

public struct WebexIntegrationConfiguration: Equatable, Sendable {
    public let clientID: String
    public let clientSecret: String
    public let redirectURI: URL
    public let scopes: [String]
    public let prefersEphemeralWebBrowserSession: Bool

    public init(
        clientID: String,
        clientSecret: String,
        redirectURI: URL,
        scopes: [String],
        prefersEphemeralWebBrowserSession: Bool = false
    ) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI
        let normalizedScopes = scopes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.scopes = Array(Set(normalizedScopes)).sorted()
        self.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
    }

    public var scopeString: String {
        scopes.joined(separator: " ")
    }
}

extension WebexIntegrationConfiguration: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        redactedDescription
    }

    public var debugDescription: String {
        redactedDescription
    }

    private var redactedDescription: String {
        [
            "WebexIntegrationConfiguration(",
            "clientID: \(clientID), ",
            "clientSecret: [redacted], ",
            "redirectURI: \(redirectURI.absoluteString), ",
            "scopes: \(scopes), ",
            "prefersEphemeralWebBrowserSession: \(prefersEphemeralWebBrowserSession)",
            ")"
        ].joined()
    }
}
