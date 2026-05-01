import AppKit
import Foundation
import WebexSwiftSDK

@main
struct WebexPeopleReadSmoke {
    static func main() async {
        do {
            try await run()
        } catch is CancellationError {
            fputs("Cancelled.\n", stderr)
            Foundation.exit(130)
        } catch {
            fputs("People read smoke failed: \(failureDescription(for: error))\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func run() async throws {
        let environment = ProcessInfo.processInfo.environment
        let configuration = try configurationFromEnvironment(environment)
        let options = PeopleReadOptions(environment: environment)
        let keychainService = environment["WEBEX_KEYCHAIN_SERVICE"] ?? "com.webex.swift-sdk.people-read-smoke"
        let httpClient = URLSessionHTTPClient()
        let store = KeychainWebexStore(service: keychainService)
        let registry = WebexClientRegistry(store: store, httpClient: httpClient)

        let authorized = try await registry.authorizeAndAddAccount(
            configuration: configuration,
            openAuthorizationURL: { authorizationURL in
                print("Opening Webex authorization in your default browser.")
                print("If the browser does not open, verify your redirect URI matches the README and rerun after fixing browser defaults.")
                guard NSWorkspace.shared.open(authorizationURL) else {
                    throw SmokeError.failedToOpenAuthorizationURL
                }
            }
        )

        let me = try await authorized.client.people.me()
        let metadata = WebexAccountMetadata(
            webexUserID: me.id,
            email: me.emails.first,
            displayName: me.displayName,
            organizationID: me.orgID,
            lastVerifiedAt: Date()
        )
        try await store.saveMetadata(metadata, for: authorized.account.id)

        print("")
        print("people.me()")
        printPerson(me)

        let fetched = try await authorized.client.people.get(personID: me.id)
        print("")
        print("people.get(personID: me.id)")
        printPerson(fetched)

        let page = try await authorized.client.people.list(params: .init(
            displayName: options.displayName,
            max: 25,
            excludeStatus: true
        ))

        print("")
        print("people.list(params:)")
        print("displayName: \(options.displayName)")
        print("notFoundIDs: \(optionalList(page.notFoundIDs))")
        print("nextPageExists: \(page.nextPage != nil)")
        for (index, person) in page.items.enumerated() {
            print("")
            print("person[\(index)]")
            printPerson(person)
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

        let scopes = (environment["WEBEX_SCOPES"] ?? "spark:people_read")
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

    private static func printPerson(_ person: WebexPerson) {
        print("id: \(person.id)")
        print("displayName: \(person.displayName ?? "(nil)")")
        print("emails: \(person.emails.joined(separator: ", "))")
        print("orgID: \(person.orgID ?? "(nil)")")
        print("created: \(iso8601(person.created))")
        print("lastModified: \(iso8601(person.lastModified))")
        print("status: \(person.status?.rawValue ?? "(nil)")")
        print("type: \(person.type?.rawValue ?? "(nil)")")
    }

    private static func optionalList(_ values: [String]?) -> String {
        guard let values, !values.isEmpty else {
            return "(nil)"
        }

        return values.joined(separator: ", ")
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

struct PeopleReadOptions {
    let displayName: String

    init(environment: [String: String]) {
        self.displayName = Self.trimmedOptional(environment["WEBEX_PEOPLE_DISPLAY_NAME"]) ?? "Harrison"
    }

    private static func trimmedOptional(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        return trimmed
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

private enum SmokeError: Error, CustomStringConvertible {
    case missingEnvironment(String)
    case invalidRedirectURI
    case failedToOpenAuthorizationURL

    var description: String {
        switch self {
        case .missingEnvironment(let name):
            return "Missing required environment variable \(name)"
        case .invalidRedirectURI:
            return "Invalid WEBEX_REDIRECT_URI"
        case .failedToOpenAuthorizationURL:
            return "Failed to open the Webex authorization URL"
        }
    }
}
