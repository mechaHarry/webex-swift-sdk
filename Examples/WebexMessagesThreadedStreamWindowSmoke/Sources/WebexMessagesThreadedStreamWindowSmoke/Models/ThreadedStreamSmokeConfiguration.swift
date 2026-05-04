import Foundation
import WebexSwiftSDK

struct ThreadedStreamSmokeConfiguration: Equatable {
    let integration: WebexIntegrationConfiguration
    let roomID: String
    let pageSize: Int
    let pageLimit: Int
    let keychainService: String

    var listParams: ListMessagesParams {
        ListMessagesParams(roomID: roomID, max: pageSize)
    }

    init(environment: [String: String]) throws {
        let clientID = try Self.required("WEBEX_CLIENT_ID", environment: environment)
        let clientSecret = try Self.required("WEBEX_CLIENT_SECRET", environment: environment)
        self.roomID = try Self.required("WEBEX_ROOM_ID", environment: environment)
        self.pageSize = try Self.integer(
            named: "WEBEX_MESSAGES_PAGE_SIZE",
            defaultValue: 25,
            minimum: 1,
            maximum: 1_000,
            environment: environment
        )
        self.pageLimit = try Self.integer(
            named: "WEBEX_MESSAGES_STREAM_PAGE_LIMIT",
            defaultValue: 1,
            minimum: 1,
            maximum: 1_000,
            environment: environment
        )
        self.keychainService = environment["WEBEX_KEYCHAIN_SERVICE"]
            ?? "com.webex.swift-sdk.messages-threaded-stream-window-smoke"

        let redirectURIString = environment["WEBEX_REDIRECT_URI"]
            ?? WebexOAuthLoopbackRedirectListener.defaultRedirectURI.absoluteString
        guard let redirectURI = URL(string: redirectURIString) else {
            throw ThreadedStreamSmokeError.invalidRedirectURI
        }

        let scopes = (environment["WEBEX_SCOPES"] ?? "spark:all spark:kms")
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map(String.init)

        self.integration = WebexIntegrationConfiguration(
            clientID: clientID,
            clientSecret: clientSecret,
            redirectURI: redirectURI,
            scopes: scopes,
            prefersEphemeralWebBrowserSession: false
        )
    }

    private static func required(
        _ name: String,
        environment: [String: String]
    ) throws -> String {
        guard let value = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            throw ThreadedStreamSmokeError.missingEnvironment(name)
        }

        return value
    }

    private static func integer(
        named name: String,
        defaultValue: Int,
        minimum: Int,
        maximum: Int,
        environment: [String: String]
    ) throws -> Int {
        guard let rawValue = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return defaultValue
        }
        guard let value = Int(rawValue),
              value >= minimum,
              value <= maximum else {
            throw ThreadedStreamSmokeError.invalidInteger(
                name: name,
                value: rawValue,
                minimum: minimum,
                maximum: maximum
            )
        }

        return value
    }
}

enum ThreadedStreamSmokeError: Error, Equatable, CustomStringConvertible {
    case missingEnvironment(String)
    case invalidRedirectURI
    case invalidInteger(name: String, value: String, minimum: Int, maximum: Int)
    case failedToOpenAuthorizationURL
    case missingRealtimeScopes(requested: [String], granted: [String])

    var description: String {
        switch self {
        case .missingEnvironment(let name):
            return "Missing required environment variable \(name)"
        case .invalidRedirectURI:
            return "Invalid WEBEX_REDIRECT_URI"
        case .invalidInteger(let name, let value, let minimum, let maximum):
            return "\(name) must be an integer between \(minimum) and \(maximum); received \(value)"
        case .failedToOpenAuthorizationURL:
            return "Failed to open the Webex authorization URL"
        case .missingRealtimeScopes(let requested, let granted):
            return [
                "OAuth token is missing realtime scopes.",
                "Required: spark:all spark:kms.",
                "Requested: \(Self.scopeDescription(requested)).",
                "Granted: \(Self.scopeDescription(granted)).",
                "Update the Webex integration scopes and reauthorize."
            ].joined(separator: " ")
        }
    }

    private static func scopeDescription(_ scopes: [String]) -> String {
        scopes.isEmpty ? "(none)" : scopes.sorted().joined(separator: " ")
    }
}
