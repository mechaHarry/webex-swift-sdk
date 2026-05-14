import Foundation
import WebexSwiftSDK

struct TeamsSnapshotSmokeConfiguration: Equatable {
    let integration: WebexIntegrationConfiguration
    let pageSize: Int
    let pageLimit: Int
    let keychainService: String
    let listParams: ListTeamsParams

    init(environment: [String: String]) throws {
        let clientID = try Self.required("WEBEX_CLIENT_ID", environment: environment)
        let clientSecret = try Self.required("WEBEX_CLIENT_SECRET", environment: environment)
        self.pageSize = try Self.integer(
            named: "WEBEX_TEAMS_PAGE_SIZE",
            defaultValue: 25,
            minimum: 1,
            maximum: 1_000,
            environment: environment
        )
        self.pageLimit = try Self.integer(
            named: "WEBEX_TEAMS_STREAM_PAGE_LIMIT",
            defaultValue: 1,
            minimum: 1,
            maximum: 1_000,
            environment: environment
        )
        self.keychainService = environment["WEBEX_KEYCHAIN_SERVICE"] ?? "com.webex.swift-sdk.teams-snapshot-smoke"

        let redirectURIString = environment["WEBEX_REDIRECT_URI"] ?? WebexOAuthLoopbackRedirectListener.defaultRedirectURI.absoluteString
        guard let redirectURI = URL(string: redirectURIString) else {
            throw TeamsSnapshotSmokeError.invalidRedirectURI
        }

        let scopes = (environment["WEBEX_SCOPES"] ?? "spark:teams_read")
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map(String.init)

        self.integration = WebexIntegrationConfiguration(
            clientID: clientID,
            clientSecret: clientSecret,
            redirectURI: redirectURI,
            scopes: scopes,
            prefersEphemeralWebBrowserSession: false
        )
        self.listParams = ListTeamsParams(max: pageSize)
    }

    private static func required(
        _ name: String,
        environment: [String: String]
    ) throws -> String {
        guard let value = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            throw TeamsSnapshotSmokeError.missingEnvironment(name)
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
        guard let rawValue = trimmedOptional(environment[name]) else {
            return defaultValue
        }
        guard let value = Int(rawValue),
              value >= minimum,
              value <= maximum else {
            throw TeamsSnapshotSmokeError.invalidInteger(
                name: name,
                value: rawValue,
                minimum: minimum,
                maximum: maximum
            )
        }
        return value
    }

    private static func trimmedOptional(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

enum TeamsSnapshotSmokeError: Error, Equatable, CustomStringConvertible {
    case missingEnvironment(String)
    case invalidRedirectURI
    case invalidInteger(name: String, value: String, minimum: Int, maximum: Int)
    case failedToOpenAuthorizationURL

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
        }
    }
}
