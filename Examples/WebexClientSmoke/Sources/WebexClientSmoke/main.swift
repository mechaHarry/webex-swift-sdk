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
        print("Creating registry account for client id: \(configuration.clientID)")
        let account = try await registry.addAccount(configuration: configuration)
        print("Created local account id: \(account.id.rawValue)")

        let codeVerifier = try PKCE.generateVerifier()
        let state = UUID().uuidString
        let authorizationURL = try WebexAuthorizationRequest(
            configuration: configuration,
            state: state,
            codeChallenge: PKCE.s256Challenge(for: codeVerifier)
        ).url()

        print("")
        print("Opening Webex authorization URL in your default browser.")
        print("If the browser does not open, paste this URL manually:")
        print(authorizationURL.absoluteString)
        print("")
        NSWorkspace.shared.open(authorizationURL)

        print("After Webex redirects, paste the full redirect URL here:")
        guard let callbackURLString = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
              let callbackURL = URL(string: callbackURLString),
              !callbackURLString.isEmpty else {
            throw SmokeError.missingCallbackURL
        }

        let authorizationCode = try OAuthCallbackParser.parse(callbackURL: callbackURL, expectedState: state)
        let tokenResponse = try await exchangeAuthorizationCode(
            authorizationCode.code,
            codeVerifier: codeVerifier,
            configuration: configuration,
            httpClient: httpClient
        )

        let receivedAt = Date()
        try await store.saveTokenRecord(tokenResponse.tokenRecord(receivedAt: receivedAt), for: account.id)
        print("Saved refresh token record. Access token expires at: \(tokenResponse.accessTokenState(receivedAt: receivedAt).expiresAt)")

        let client = try await registry.client(for: account.id)
        let person = try await client.people.me()
        try await store.saveMetadata(person.metadata(verifiedAt: Date()), for: account.id)

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
        let redirectURIString = try requiredEnvironment("WEBEX_REDIRECT_URI", environment: environment)
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

    private static func exchangeAuthorizationCode(
        _ code: String,
        codeVerifier: String,
        configuration: WebexIntegrationConfiguration,
        httpClient: HTTPClient
    ) async throws -> WebexTokenResponse {
        let request = try WebexTokenEndpoint.authorizationCodeRequest(
            configuration: configuration,
            code: code,
            codeVerifier: codeVerifier
        )
        let response = try await httpClient.send(request)
        guard (200..<300).contains(response.response.statusCode) else {
            let body = String(data: response.data, encoding: .utf8) ?? "<non-UTF8 response body>"
            throw WebexSDKError.tokenExchangeFailed(
                statusCode: response.response.statusCode,
                message: body,
                trackingID: response.response.value(forHTTPHeaderField: "trackingid")
            )
        }

        return try JSONDecoder().decode(WebexTokenResponse.self, from: response.data)
    }
}

private enum SmokeError: Error, CustomStringConvertible {
    case missingEnvironment(String)
    case invalidRedirectURI(String)
    case missingCallbackURL

    var description: String {
        switch self {
        case .missingEnvironment(let name):
            return "Missing required environment variable \(name)"
        case .invalidRedirectURI(let value):
            return "Invalid WEBEX_REDIRECT_URI: \(value)"
        case .missingCallbackURL:
            return "No callback URL was provided"
        }
    }
}
