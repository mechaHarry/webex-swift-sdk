import Foundation
import WebexSwiftSDK

struct EnrichedSpacesSmokeConfiguration: Equatable {
    let integration: WebexIntegrationConfiguration
    let pageSize: Int
    let pageLimit: Int
    let keychainService: String
    let listParams: ListSpacesParams

    init(environment: [String: String]) throws {
        let clientID = try Self.required("WEBEX_CLIENT_ID", environment: environment)
        let clientSecret = try Self.required("WEBEX_CLIENT_SECRET", environment: environment)
        self.pageSize = try Self.integer(
            named: "WEBEX_SPACES_PAGE_SIZE",
            defaultValue: 25,
            minimum: 1,
            maximum: 1_000,
            environment: environment
        )
        self.pageLimit = try Self.integer(
            named: "WEBEX_SPACES_STREAM_PAGE_LIMIT",
            defaultValue: 1,
            minimum: 1,
            maximum: 1_000,
            environment: environment
        )
        self.keychainService = environment["WEBEX_KEYCHAIN_SERVICE"] ?? "com.webex.swift-sdk.spaces-enriched-snapshot-smoke"

        let redirectURIString = environment["WEBEX_REDIRECT_URI"] ?? WebexOAuthLoopbackRedirectListener.defaultRedirectURI.absoluteString
        guard let redirectURI = URL(string: redirectURIString) else {
            throw EnrichedSpacesSmokeError.invalidRedirectURI
        }

        let scopes = (environment["WEBEX_SCOPES"] ?? "spark:rooms_read spark:memberships_read spark:people_read")
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map(String.init)

        self.integration = WebexIntegrationConfiguration(
            clientID: clientID,
            clientSecret: clientSecret,
            redirectURI: redirectURI,
            scopes: scopes,
            prefersEphemeralWebBrowserSession: false
        )

        self.listParams = ListSpacesParams(
            teamID: Self.trimmedOptional(environment["WEBEX_SPACES_TEAM_ID"]),
            type: try Self.spaceType(environment["WEBEX_SPACES_TYPE"]),
            sortBy: try Self.sort(environment["WEBEX_SPACES_SORT_BY"]),
            max: pageSize
        )
    }

    private static func required(
        _ name: String,
        environment: [String: String]
    ) throws -> String {
        guard let value = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            throw EnrichedSpacesSmokeError.missingEnvironment(name)
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
            throw EnrichedSpacesSmokeError.invalidInteger(
                name: name,
                value: rawValue,
                minimum: minimum,
                maximum: maximum
            )
        }
        return value
    }

    private static func spaceType(_ rawValue: String?) throws -> WebexSpaceType? {
        guard let value = trimmedOptional(rawValue) else {
            return nil
        }

        switch value.lowercased() {
        case "direct":
            return .direct
        case "group":
            return .group
        default:
            throw EnrichedSpacesSmokeError.invalidSpaceType(value)
        }
    }

    private static func sort(_ rawValue: String?) throws -> WebexSpaceSort? {
        guard let value = trimmedOptional(rawValue) else {
            return nil
        }

        switch value.lowercased() {
        case "id":
            return .id
        case "lastactivity", "last_activity", "last-activity":
            return .lastActivity
        case "created":
            return .created
        default:
            throw EnrichedSpacesSmokeError.invalidSort(value)
        }
    }

    private static func trimmedOptional(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

enum EnrichedSpacesSmokeError: Error, Equatable, CustomStringConvertible {
    case missingEnvironment(String)
    case invalidRedirectURI
    case invalidInteger(name: String, value: String, minimum: Int, maximum: Int)
    case invalidSpaceType(String)
    case invalidSort(String)
    case failedToOpenAuthorizationURL

    var description: String {
        switch self {
        case .missingEnvironment(let name):
            return "Missing required environment variable \(name)"
        case .invalidRedirectURI:
            return "Invalid WEBEX_REDIRECT_URI"
        case .invalidInteger(let name, let value, let minimum, let maximum):
            return "\(name) must be an integer between \(minimum) and \(maximum); received \(value)"
        case .invalidSpaceType(let value):
            return "WEBEX_SPACES_TYPE must be direct or group; received \(value)"
        case .invalidSort(let value):
            return "WEBEX_SPACES_SORT_BY must be id, lastactivity, or created; received \(value)"
        case .failedToOpenAuthorizationURL:
            return "Failed to open the Webex authorization URL"
        }
    }
}
