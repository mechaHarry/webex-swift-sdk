import AppKit
import Foundation
import WebexSwiftSDK

@main
struct WebexClientSmoke {
    static func main() async {
        do {
            try await run()
        } catch is CancellationError {
            fputs("Cancelled.\n", stderr)
            Foundation.exit(130)
        } catch {
            fputs("Smoke test failed: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func run() async throws {
        let configuration = try configurationFromEnvironment()
        let keychainService = ProcessInfo.processInfo.environment["WEBEX_KEYCHAIN_SERVICE"] ?? "com.webex.swift-sdk.smoke"
        let httpClient = URLSessionHTTPClient()
        let store = KeychainWebexStore(service: keychainService)
        let registry = WebexClientRegistry(store: store, httpClient: httpClient)

        print("Using Keychain service: \(keychainService)")
        print("Using redirect URI: \(configuration.redirectURI.absoluteString)")
        print("Creating registry account and opening Webex authorization for client id: \(configuration.clientID)")
        let authorized = try await registry.authorizeAndAddAccount(
            configuration: configuration,
            openAuthorizationURL: { authorizationURL in
                print("")
                print("Opening Webex authorization URL in your default browser.")
                print("If the browser does not open, paste this URL manually:")
                print(authorizationURL.absoluteString)
                print("")
                guard NSWorkspace.shared.open(authorizationURL) else {
                    throw SmokeError.failedToOpenAuthorizationURL
                }
            }
        )

        print("Created local account id: \(authorized.account.id.rawValue)")
        print("Saved refresh token record. Access token expires at: \(authorized.accessTokenExpiresAt)")

        let person = try await authorized.client.people.me()
        try await store.saveMetadata(person.metadata(verifiedAt: Date()), for: authorized.account.id)

        print("")
        print("people.me()")
        print("id: \(person.id)")
        print("displayName: \(person.displayName ?? "(nil)")")
        print("emails: \(person.emails.joined(separator: ", "))")
        print("orgID: \(person.orgID ?? "(nil)")")
        print("created: \(person.created ?? "(nil)")")
    }

    private static func configurationFromEnvironment() throws -> WebexIntegrationConfiguration {
        let environment = ProcessInfo.processInfo.environment
        let clientID = try requiredEnvironment("WEBEX_CLIENT_ID", environment: environment)
        let clientSecret = try requiredEnvironment("WEBEX_CLIENT_SECRET", environment: environment)
        let redirectURIString = environment["WEBEX_REDIRECT_URI"] ?? WebexOAuthLoopbackRedirectListener.defaultRedirectURI.absoluteString
        guard let redirectURI = URL(string: redirectURIString) else {
            throw SmokeError.invalidRedirectURI(redirectURIString)
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
}

private enum SmokeError: Error, CustomStringConvertible {
    case missingEnvironment(String)
    case invalidRedirectURI(String)
    case failedToOpenAuthorizationURL

    var description: String {
        switch self {
        case .missingEnvironment(let name):
            return "Missing required environment variable \(name)"
        case .invalidRedirectURI(let value):
            return "Invalid WEBEX_REDIRECT_URI: \(value)"
        case .failedToOpenAuthorizationURL:
            return "Failed to open the Webex authorization URL"
        }
    }
}
