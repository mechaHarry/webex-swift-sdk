import AppKit
import Foundation
import WebexSwiftSDK

@main
struct WebexSpacesListSmoke {
    static func main() async {
        do {
            try await run()
        } catch is CancellationError {
            fputs("Cancelled.\n", stderr)
            Foundation.exit(130)
        } catch WebexSDKError.network(let message) where message == "Spaces smoke page cap exceeded" {
            fputs("Spaces list smoke failed: \(message).\n", stderr)
            fputs("Increase WEBEX_SPACES_MAX_PAGES or narrow the listing with WEBEX_SPACES_TYPE / WEBEX_SPACES_TEAM_ID.\n", stderr)
            Foundation.exit(1)
        } catch {
            fputs("Spaces list smoke failed: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func run() async throws {
        let environment = ProcessInfo.processInfo.environment
        let configuration = try configurationFromEnvironment(environment)
        let listOptions = try ListOptions(environment: environment)
        let keychainService = environment["WEBEX_KEYCHAIN_SERVICE"] ?? "com.webex.swift-sdk.spaces-list-smoke"
        let httpClient = URLSessionHTTPClient()
        let store = KeychainWebexStore(service: keychainService)
        let registry = WebexClientRegistry(store: store, httpClient: httpClient)

        print("Using Keychain service: \(keychainService)")
        print("Using redirect URI: \(configuration.redirectURI.absoluteString)")
        print("Opening Webex authorization for client id: \(configuration.clientID)")
        let authorized = try await registry.authorizeAndAddAccount(
            configuration: configuration,
            openAuthorizationURL: { authorizationURL in
                print("")
                print("Opening Webex authorization URL in your default browser.")
                print("If the browser does not open, verify your redirect URI matches the README and rerun after fixing browser defaults.")
                print("")
                guard NSWorkspace.shared.open(authorizationURL) else {
                    throw SmokeError.failedToOpenAuthorizationURL
                }
            }
        )

        print("Created local account id: \(authorized.account.id.rawValue)")
        print("Saved refresh token record. Access token expires at: \(authorized.accessTokenExpiresAt)")
        print("")
        print("Listing Webex Spaces with page size \(listOptions.pageSize), max pages \(listOptions.maxPages)")

        let spaces = try await collectSpaces(
            client: authorized.client,
            params: listOptions.params,
            maxPages: listOptions.maxPages
        )

        print("spaces.count: \(spaces.count)")
        for (index, space) in spaces.enumerated() {
            print("")
            print("space[\(index)]")
            print("id: \(space.id)")
            print("title: \(space.title ?? "(nil)")")
            print("type: \(space.type?.rawValue ?? "(nil)")")
            print("teamID: \(space.teamID ?? "(nil)")")
            print("isLocked: \(optionalBool(space.isLocked))")
            print("isReadOnly: \(optionalBool(space.isReadOnly))")
            print("isAnnouncementOnly: \(optionalBool(space.isAnnouncementOnly))")
            print("lastActivity: \(iso8601(space.lastActivity))")
            print("created: \(iso8601(space.created))")
        }
    }

    private static func configurationFromEnvironment(
        _ environment: [String: String]
    ) throws -> WebexIntegrationConfiguration {
        let clientID = try requiredEnvironment("WEBEX_CLIENT_ID", environment: environment)
        let clientSecret = try requiredEnvironment("WEBEX_CLIENT_SECRET", environment: environment)
        let redirectURIString = environment["WEBEX_REDIRECT_URI"] ?? WebexOAuthLoopbackRedirectListener.defaultRedirectURI.absoluteString
        guard let redirectURI = URL(string: redirectURIString) else {
            throw SmokeError.invalidRedirectURI(redirectURIString)
        }

        let scopes = (environment["WEBEX_SCOPES"] ?? "spark:rooms_read")
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map(String.init)

        return WebexIntegrationConfiguration(
            clientID: clientID,
            clientSecret: clientSecret,
            redirectURI: redirectURI,
            scopes: scopes,
            prefersEphemeralWebBrowserSession: false
        )
    }

    private static func requiredEnvironment(
        _ name: String,
        environment: [String: String]
    ) throws -> String {
        guard let value = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            throw SmokeError.missingEnvironment(name)
        }

        return value
    }

    private static func optionalBool(_ value: Bool?) -> String {
        guard let value else {
            return "(nil)"
        }

        return String(value)
    }

    private static func iso8601(_ date: Date?) -> String {
        guard let date else {
            return "(nil)"
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func collectSpaces(
        client: WebexClient,
        params: ListSpacesParams,
        maxPages: Int
    ) async throws -> [WebexSpace] {
        var page = try await client.spaces.list(params: params)
        var spaces = page.items
        var pagesFetched = 1

        while let nextPage = page.nextPage {
            guard pagesFetched < maxPages else {
                throw WebexSDKError.network("Spaces smoke page cap exceeded")
            }

            page = try await client.spaces.list(nextPage: nextPage)
            spaces.append(contentsOf: page.items)
            pagesFetched += 1
        }

        return spaces
    }
}

struct ListOptions {
    let pageSize: Int
    let maxPages: Int
    let params: ListSpacesParams

    init(environment: [String: String]) throws {
        self.pageSize = try Self.integer(
            named: "WEBEX_SPACES_PAGE_SIZE",
            defaultValue: 100,
            minimum: 1,
            maximum: 1_000,
            environment: environment
        )
        self.maxPages = try Self.integer(
            named: "WEBEX_SPACES_MAX_PAGES",
            defaultValue: 1_000,
            minimum: 1,
            maximum: 10_000,
            environment: environment
        )
        self.params = ListSpacesParams(
            teamID: Self.trimmedOptional(environment["WEBEX_SPACES_TEAM_ID"]),
            type: try Self.spaceType(environment["WEBEX_SPACES_TYPE"]),
            sortBy: try Self.sort(environment["WEBEX_SPACES_SORT_BY"]),
            max: pageSize
        )
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
            throw SmokeError.invalidInteger(name: name, value: rawValue, minimum: minimum, maximum: maximum)
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
            throw SmokeError.invalidSpaceType(value)
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
            throw SmokeError.invalidSort(value)
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

private enum SmokeError: Error, CustomStringConvertible {
    case missingEnvironment(String)
    case invalidRedirectURI(String)
    case failedToOpenAuthorizationURL
    case invalidInteger(name: String, value: String, minimum: Int, maximum: Int)
    case invalidSpaceType(String)
    case invalidSort(String)

    var description: String {
        switch self {
        case .missingEnvironment(let name):
            return "Missing required environment variable \(name)"
        case .invalidRedirectURI(let value):
            return "Invalid WEBEX_REDIRECT_URI: \(value)"
        case .failedToOpenAuthorizationURL:
            return "Failed to open the Webex authorization URL"
        case .invalidInteger(let name, let value, let minimum, let maximum):
            return "\(name) must be an integer from \(minimum) through \(maximum); got \(value)"
        case .invalidSpaceType(let value):
            return "WEBEX_SPACES_TYPE must be direct or group; got \(value)"
        case .invalidSort(let value):
            return "WEBEX_SPACES_SORT_BY must be id, lastactivity, or created; got \(value)"
        }
    }
}
