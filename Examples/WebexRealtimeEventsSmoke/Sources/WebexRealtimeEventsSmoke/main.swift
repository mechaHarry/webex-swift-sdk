import AppKit
import Dispatch
import Foundation
import WebexSwiftSDK

@main
struct WebexRealtimeEventsSmoke {
    static func main() async {
        do {
            try await run()
        } catch is CancellationError {
            fputs("Cancelled.\n", stderr)
            Foundation.exit(130)
        } catch {
            fputs("Realtime events smoke failed: \(failureDescription(for: error))\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func run() async throws {
        let environment = ProcessInfo.processInfo.environment
        let smokeOptions = try RealtimeSmokeOptions(environment: environment)
        let keychainService = environment["WEBEX_KEYCHAIN_SERVICE"] ?? "com.webex.swift-sdk.realtime-events-smoke"
        let httpClient = URLSessionHTTPClient()
        let store = KeychainWebexStore(service: keychainService)
        let registry = WebexClientRegistry(store: store, httpClient: httpClient)
        let authorized: RealtimeAuthorizedClient

        if let accessToken = directAccessToken(from: environment) {
            authorized = directAccessTokenClient(accessToken: accessToken, httpClient: httpClient)
            print("Using direct WEBEX_ACCESS_TOKEN; OAuth authorization will not be opened.")
            print("Created temporary local account id: \(authorized.accountID.rawValue)")
            print("Access token assumed to expire at: \(authorized.accessTokenExpiresAt)")
        } else {
            let configuration = try configurationFromEnvironment(environment)

            print("Using Keychain service: \(keychainService)")
            print("Opening Webex authorization for client id: \(configuration.clientID)")
            print("Requested scopes: \(configuration.scopes.joined(separator: " "))")
            let oauthAuthorized = try await registry.authorizeAndAddAccount(
                configuration: configuration,
                openAuthorizationURL: { authorizationURL in
                    print("")
                    print("Opening Webex authorization in your default browser.")
                    print("If the browser does not open, verify your redirect URI matches the README and rerun after fixing browser defaults.")
                    print("")
                    guard NSWorkspace.shared.open(authorizationURL) else {
                        throw RealtimeSmokeError.failedToOpenAuthorizationURL
                    }
                }
            )

            let tokenRecord = try await store.loadTokenRecord(for: oauthAuthorized.account.id)
            authorized = RealtimeAuthorizedClient(
                accountID: oauthAuthorized.account.id,
                client: oauthAuthorized.client,
                accessTokenExpiresAt: oauthAuthorized.accessTokenExpiresAt
            )

            print("Created local account id: \(authorized.accountID.rawValue)")
            print("Saved refresh token record. Access token expires at: \(authorized.accessTokenExpiresAt)")
            if let tokenRecord {
                print("Granted scopes: \(tokenRecord.grantedScopes.joined(separator: " "))")
                try validateGrantedOAuthScopes(
                    requestedScopes: configuration.scopes,
                    grantedScopes: tokenRecord.grantedScopes
                )
            }
        }
        print("")
        print("Starting Webex realtime listener.")
        print("resource filter: \(smokeOptions.resource?.rawValue ?? "(SDK default)")")
        print("event filter: \(smokeOptions.event?.rawValue ?? "(SDK default)")")
        print("include membership seen: \(smokeOptions.includeSeen)")
        print("print raw unknown payloads: \(smokeOptions.printRawUnknown)")
        print("")
        print("Press Ctrl-C to stop.")

        let connection = authorized.client.realtime.connect(options: smokeOptions.realtimeOptions)
        defer {
            connection.cancel()
        }

        let stateTask = Task {
            for await state in connection.states {
                print("\(iso8601(Date())) state=\(description(for: state))")
            }
        }

        let eventTask = Task {
            for await event in connection.events {
                print(format(event: event, printRawUnknown: smokeOptions.printRawUnknown))
            }
        }

        defer {
            stateTask.cancel()
            eventTask.cancel()
        }

        let signal = await SignalWaiter().wait()
        print("")
        print("Received signal \(signal). Stopping realtime listener.")
    }

    static func configurationFromEnvironment(
        _ environment: [String: String]
    ) throws -> WebexIntegrationConfiguration {
        let clientID = try requiredEnvironment("WEBEX_CLIENT_ID", environment: environment)
        let clientSecret = try requiredEnvironment("WEBEX_CLIENT_SECRET", environment: environment)
        let redirectURIString = environment["WEBEX_REDIRECT_URI"] ?? WebexOAuthLoopbackRedirectListener.defaultRedirectURI.absoluteString
        guard let redirectURI = URL(string: redirectURIString) else {
            throw RealtimeSmokeError.invalidRedirectURI
        }

        let scopes = (environment["WEBEX_SCOPES"] ?? "spark:all spark:kms")
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

    static func directAccessToken(from environment: [String: String]) -> String? {
        guard let value = environment["WEBEX_ACCESS_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        return value
    }

    private static func directAccessTokenClient(
        accessToken: String,
        httpClient: HTTPClient
    ) -> RealtimeAuthorizedClient {
        let accountID = WebexAccountID()
        let expiresAt = Date().addingTimeInterval(12 * 60 * 60)
        let configuration = WebexIntegrationConfiguration(
            clientID: "direct-access-token",
            clientSecret: "direct-access-token",
            redirectURI: WebexOAuthLoopbackRedirectListener.defaultRedirectURI,
            scopes: [],
            prefersEphemeralWebBrowserSession: false
        )
        let client = WebexClient(
            accountID: accountID,
            configuration: configuration,
            tokenStore: InMemoryWebexStore(),
            httpClient: httpClient,
            initialAccessToken: AccessTokenState(
                value: accessToken,
                expiresAt: expiresAt,
                tokenType: "Bearer"
            )
        )

        return RealtimeAuthorizedClient(
            accountID: accountID,
            client: client,
            accessTokenExpiresAt: expiresAt
        )
    }

    static func validateGrantedOAuthScopes(requestedScopes: [String], grantedScopes: [String]) throws {
        let requiredScopes = ["spark:all", "spark:kms"]
        let grantedSet = Set(grantedScopes)
        let missingScopes = requiredScopes.filter { !grantedSet.contains($0) }
        guard missingScopes.isEmpty else {
            throw RealtimeSmokeError.missingRealtimeScopes(
                requested: requestedScopes,
                granted: grantedScopes
            )
        }
    }

    static func failureDescription(for error: Error) -> String {
        if case WebexSDKError.invalidAuthorizationCallback = error {
            return "Invalid authorization callback"
        }

        return RealtimeSmokeRedactor.redact(String(describing: error))
    }

    static func format(event: WebexRealtimeEvent, printRawUnknown: Bool) -> String {
        var fields = [
            iso8601(Date()),
            "\(event.resource):\(event.event)",
            "status=\(description(for: event.decodeStatus))",
            "resourceID=\(event.resourceID ?? "(nil)")",
            "roomID=\(event.roomID ?? "(nil)")",
            "actorID=\(event.actorID ?? "(nil)")"
        ]

        if event.decodeStatus != .known {
            fields.append("UNKNOWN_REALTIME_DECODE_STATUS")
        }

        if printRawUnknown, event.decodeStatus != .known {
            fields.append("payload=\(redactedCompactPayload(event.payload))")
        }

        return fields.joined(separator: " ")
    }

    private static func description(for status: WebexRealtimeDecodeStatus) -> String {
        switch status {
        case .known:
            return "known"
        case .unknownEvent:
            return "unknownEvent"
        case .unknownPayload:
            return "unknownPayload"
        }
    }

    private static func description(for state: WebexRealtimeConnectionState) -> String {
        switch state {
        case .disconnected:
            return "disconnected"
        case .discovering:
            return "discovering"
        case .registeringDevice:
            return "registeringDevice"
        case .connecting:
            return "connecting"
        case .authorizing:
            return "authorizing"
        case .connected:
            return "connected"
        case .reconnecting(let attempt, let delay):
            return "reconnecting(attempt: \(attempt), delay: \(delay))"
        case .failed(let error):
            return "failed(\(RealtimeSmokeRedactor.redact(String(describing: error))))"
        }
    }

    private static func redactedCompactPayload(_ payload: [String: WebexJSONValue]) -> String {
        guard !payload.isEmpty else {
            return "{}"
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        do {
            let data = try encoder.encode(payload)
            let raw = String(decoding: data, as: UTF8.self)
            return RealtimeSmokeRedactor.redact(raw).singleLinePreview(limit: 2_000)
        } catch {
            return RealtimeSmokeRedactor.redact(String(describing: payload)).singleLinePreview(limit: 2_000)
        }
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

struct RealtimeAuthorizedClient {
    let accountID: WebexAccountID
    let client: WebexClient
    let accessTokenExpiresAt: Date
}

struct RealtimeSmokeOptions {
    let resource: WebexRealtimeResource?
    let event: WebexRealtimeEventName?
    let includeSeen: Bool
    let printRawUnknown: Bool
    let realtimeOptions: WebexRealtimeOptions

    init(environment: [String: String]) throws {
        let resource = Self.trimmedOptional(environment["WEBEX_REALTIME_RESOURCE"])
            .map(WebexRealtimeResource.init(rawValue:))
        let event = Self.trimmedOptional(environment["WEBEX_REALTIME_EVENT"])
            .map(WebexRealtimeEventName.init(rawValue:))
        let includeSeen = try Self.boolean(
            named: "WEBEX_REALTIME_INCLUDE_SEEN",
            environment: environment,
            defaultValue: false
        )
        let printRawUnknown = try Self.boolean(
            named: "WEBEX_REALTIME_PRINT_RAW_UNKNOWN",
            environment: environment,
            defaultValue: false
        )

        self.resource = resource
        self.event = event
        self.includeSeen = includeSeen
        self.printRawUnknown = printRawUnknown

        let defaults = WebexRealtimeOptions()
        self.realtimeOptions = WebexRealtimeOptions(
            resources: resource.map { [$0] } ?? defaults.resources,
            events: event.map { [$0] } ?? defaults.events,
            includeMembershipSeen: includeSeen,
            retryPolicy: defaults.retryPolicy,
            deviceName: defaults.deviceName
        )
    }

    static func boolean(
        named name: String,
        environment: [String: String],
        defaultValue: Bool
    ) throws -> Bool {
        guard let rawValue = trimmedOptional(environment[name]) else {
            return defaultValue
        }

        switch rawValue.lowercased() {
        case "true", "1", "yes":
            return true
        case "false", "0", "no":
            return false
        default:
            throw RealtimeSmokeError.invalidBoolean(name: name, value: rawValue)
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

enum RealtimeSmokeError: Error, Equatable, CustomStringConvertible {
    case missingEnvironment(String)
    case invalidRedirectURI
    case failedToOpenAuthorizationURL
    case invalidBoolean(name: String, value: String)
    case missingRealtimeScopes(requested: [String], granted: [String])

    var description: String {
        switch self {
        case .missingEnvironment(let name):
            return "Missing required environment variable \(name)"
        case .invalidRedirectURI:
            return "Invalid WEBEX_REDIRECT_URI"
        case .failedToOpenAuthorizationURL:
            return "Failed to open the Webex authorization URL"
        case .invalidBoolean(let name, let value):
            return "\(name) must be one of true, false, 1, 0, yes, or no; got \(RealtimeSmokeRedactor.redact(value))"
        case .missingRealtimeScopes(let requested, let granted):
            return [
                "OAuth token is missing realtime scopes.",
                "Required: spark:all spark:kms.",
                "Requested: \(scopeDescription(requested)).",
                "Granted: \(scopeDescription(granted)).",
                "Update the Webex integration scopes and reauthorize."
            ].joined(separator: " ")
        }
    }

    private func scopeDescription(_ scopes: [String]) -> String {
        scopes.isEmpty ? "(none)" : scopes.sorted().joined(separator: " ")
    }
}

enum RealtimeSmokeRedactor {
    static func redact(_ value: String) -> String {
        var redacted = value
        redacted = replacing(
            pattern: #"(?i)("(?:access_token|refresh_token|client_secret|clientSecret|authorization|token|secret)"\s*:\s*)"(?:\\.|[^"\\])*""#,
            in: redacted,
            with: #"$1"[REDACTED]""#
        )
        redacted = replacing(
            pattern: #"(?i)\b(authorization\s*[:=]\s*bearer\s+)([^\s,;]+)"#,
            in: redacted,
            with: "$1[REDACTED]"
        )
        redacted = replacing(
            pattern: #"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]+"#,
            in: redacted,
            with: "Bearer [REDACTED]"
        )
        redacted = replacing(
            pattern: #"(?i)\b(access[_-]?token|refresh[_-]?token|client[_-]?secret|clientSecret|authorization|token|secret)(\s*[:=]\s*)("[^"]*"|'[^']*'|[^\s,&;]+)"#,
            in: redacted,
            with: "$1$2[REDACTED]"
        )
        redacted = replacing(
            pattern: #"[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{8,}"#,
            in: redacted,
            with: "[REDACTED]"
        )
        return redacted
    }

    private static func replacing(pattern: String, in value: String, with template: String) -> String {
        do {
            let expression = try NSRegularExpression(pattern: pattern)
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            return expression.stringByReplacingMatches(
                in: value,
                options: [],
                range: range,
                withTemplate: template
            )
        } catch {
            return value
        }
    }
}

private final class SignalWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var sources: [DispatchSourceSignal] = []
    private var didResume = false

    func wait() async -> Int32 {
        await withCheckedContinuation { continuation in
            for signalNumber in [SIGINT, SIGTERM] {
                signal(signalNumber, SIG_IGN)
                let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
                source.setEventHandler { [weak self] in
                    self?.resumeOnce(signalNumber, continuation: continuation)
                }
                sources.append(source)
                source.resume()
            }
        }
    }

    private func resumeOnce(_ signalNumber: Int32, continuation: CheckedContinuation<Int32, Never>) {
        let shouldResume = lock.withLock {
            guard !didResume else {
                return false
            }
            didResume = true
            for source in sources {
                source.cancel()
            }
            sources.removeAll()
            return true
        }

        if shouldResume {
            continuation.resume(returning: signalNumber)
        }
    }
}

private func requiredEnvironment(
    _ name: String,
    environment: [String: String]
) throws -> String {
    guard let value = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
          !value.isEmpty else {
        throw RealtimeSmokeError.missingEnvironment(name)
    }

    return value
}

private extension String {
    func singleLinePreview(limit: Int) -> String {
        let normalized = replacingOccurrences(of: "\n", with: "\\n")
        guard normalized.count > limit else {
            return normalized
        }

        return String(normalized.prefix(limit)) + "..."
    }
}
