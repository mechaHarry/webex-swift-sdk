import AppKit
import Foundation
import WebexSwiftSDK

@main
struct WebexMembershipsListSmoke {
    static func main() async {
        do {
            try await run()
        } catch is CancellationError {
            fputs("Cancelled.\n", stderr)
            Foundation.exit(130)
        } catch WebexSDKError.network(let message) where message == "Memberships pagination page cap exceeded" {
            fputs("Memberships list smoke failed: \(message).\n", stderr)
            fputs("Increase WEBEX_MEMBERSHIPS_MAX_PAGES or lower WEBEX_MEMBERSHIPS_PAGE_SIZE.\n", stderr)
            Foundation.exit(1)
        } catch {
            fputs("Memberships list smoke failed: \(failureDescription(for: error))\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func run() async throws {
        let environment = ProcessInfo.processInfo.environment
        let configuration = try configurationFromEnvironment(environment)
        let listOptions = try MembershipListOptions(environment: environment)
        let keychainService = environment["WEBEX_KEYCHAIN_SERVICE"] ?? "com.webex.swift-sdk.memberships-list-smoke"
        let httpClient = URLSessionHTTPClient()
        let store = KeychainWebexStore(service: keychainService)
        let registry = WebexClientRegistry(store: store, httpClient: httpClient)

        print("Using Keychain service: \(keychainService)")
        print("Opening Webex authorization for client id: \(configuration.clientID)")
        let authorized = try await registry.authorizeAndAddAccount(
            configuration: configuration,
            openAuthorizationURL: { authorizationURL in
                print("")
                print("Opening Webex authorization in your default browser.")
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
        print("Listing Webex Memberships for room \(listOptions.roomID)")

        let memberships = try await authorized.client.memberships.listAll(
            query: listOptions.query,
            maxPages: listOptions.maxPages
        )

        print("memberships.count: \(memberships.count)")
        for (index, membership) in memberships.enumerated() {
            print("")
            print("membership[\(index)]")
            print("id: \(membership.id)")
            print("roomID: \(membership.roomID ?? "(nil)")")
            print("personID: \(membership.personID ?? "(nil)")")
            print("personEmail: \(membership.personEmail ?? "(nil)")")
            print("personDisplayName: \(membership.personDisplayName ?? "(nil)")")
            print("isModerator: \(optionalBool(membership.isModerator))")
            print("isMonitor: \(optionalBool(membership.isMonitor))")
            print("isRoomHidden: \(optionalBool(membership.isRoomHidden))")
            print("created: \(iso8601(membership.created))")
        }
    }

    static func configurationFromEnvironment(
        _ environment: [String: String]
    ) throws -> WebexIntegrationConfiguration {
        let clientID = try requiredEnvironment("WEBEX_CLIENT_ID", environment: environment)
        let clientSecret = try requiredEnvironment("WEBEX_CLIENT_SECRET", environment: environment)
        let redirectURIString = environment["WEBEX_REDIRECT_URI"] ?? WebexOAuthLoopbackRedirectListener.defaultRedirectURI.absoluteString
        guard let redirectURI = URL(string: redirectURIString) else {
            throw SmokeError.invalidRedirectURI
        }

        let scopes = (environment["WEBEX_SCOPES"] ?? "spark:memberships_read")
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

    static func failureDescription(for error: Error) -> String {
        if case WebexSDKError.invalidAuthorizationCallback = error {
            return "Invalid authorization callback"
        }

        return String(describing: error)
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
}

private func requiredEnvironment(
    _ name: String,
    environment: [String: String]
) throws -> String {
    guard let value = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
          !value.isEmpty else {
        throw SmokeError.missingEnvironment(name)
    }

    return value
}

struct MembershipListOptions {
    let roomID: String
    let pageSize: Int
    let maxPages: Int
    let query: ListMembershipsQuery

    init(environment: [String: String]) throws {
        self.roomID = try requiredEnvironment("WEBEX_ROOM_ID", environment: environment)
        self.pageSize = try Self.integer(
            named: "WEBEX_MEMBERSHIPS_PAGE_SIZE",
            defaultValue: 100,
            minimum: 1,
            maximum: 1_000,
            environment: environment
        )
        self.maxPages = try Self.integer(
            named: "WEBEX_MEMBERSHIPS_MAX_PAGES",
            defaultValue: 1_000,
            minimum: 1,
            maximum: 10_000,
            environment: environment
        )
        self.query = ListMembershipsQuery(roomID: roomID, max: pageSize)
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
            throw SmokeError.invalidInteger(name: name, value: rawValue, minimum: minimum, maximum: maximum)
        }

        return value
    }
}

private enum SmokeError: Error, CustomStringConvertible {
    case missingEnvironment(String)
    case invalidRedirectURI
    case failedToOpenAuthorizationURL
    case invalidInteger(name: String, value: String, minimum: Int, maximum: Int)

    var description: String {
        switch self {
        case .missingEnvironment(let name):
            return "Missing required environment variable \(name)"
        case .invalidRedirectURI:
            return "Invalid WEBEX_REDIRECT_URI"
        case .failedToOpenAuthorizationURL:
            return "Failed to open the Webex authorization URL"
        case .invalidInteger(let name, let value, let minimum, let maximum):
            return "\(name) must be an integer from \(minimum) through \(maximum); got \(value)"
        }
    }
}
