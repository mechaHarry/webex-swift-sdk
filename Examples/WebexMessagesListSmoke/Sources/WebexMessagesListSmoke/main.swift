import AppKit
import Foundation
import WebexSwiftSDK

@main
struct WebexMessagesListSmoke {
    static func main() async {
        do {
            try await run()
        } catch is CancellationError {
            fputs("Cancelled.\n", stderr)
            Foundation.exit(130)
        } catch {
            fputs("Messages list smoke failed: \(failureDescription(for: error))\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func run() async throws {
        let environment = ProcessInfo.processInfo.environment
        let configuration = try configurationFromEnvironment(environment)
        let listOptions = try MessageListOptions(environment: environment)
        let keychainService = environment["WEBEX_KEYCHAIN_SERVICE"] ?? "com.webex.swift-sdk.messages-list-smoke"
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
        print("Listing Webex Messages for room \(listOptions.roomID)")
        print("pageSize: \(listOptions.pageSize)")
        print("maxPages: \(listOptions.maxPages)")

        let result = try await collectMessages(
            client: authorized.client,
            params: listOptions.params,
            maxPages: listOptions.maxPages
        )

        let messages = result.messages
        print("messages.count: \(messages.count)")
        print("pagesFetched: \(result.pagesFetched)")
        print("hasMore: \(result.hasMore)")
        if result.hasMore {
            print("Reached WEBEX_MESSAGES_MAX_PAGES before all pages were fetched. Increase WEBEX_MESSAGES_MAX_PAGES to fetch more pages.")
        }

        for (index, message) in messages.enumerated() {
            print("")
            print("message[\(index)]")
            print("id: \(message.id)")
            print("parentID: \(message.parentID ?? "(nil)")")
            print("roomID: \(message.roomID ?? "(nil)")")
            print("roomType: \(message.roomType?.rawValue ?? "(nil)")")
            print("personID: \(message.personID ?? "(nil)")")
            print("personEmail: \(message.personEmail ?? "(nil)")")
            print("mentionedPeople: \(optionalList(message.mentionedPeople))")
            print("mentionedGroups: \(optionalList(message.mentionedGroups))")
            print("files.count: \(message.files?.count ?? 0)")
            print("attachments.count: \(message.attachments?.count ?? 0)")
            print("created: \(iso8601(message.created))")
            print("updated: \(iso8601(message.updated))")
            print("isVoiceClip: \(optionalBool(message.isVoiceClip))")
            print("text: \(preview(message.text))")
            print("markdown: \(preview(message.markdown))")
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

        let scopes = (environment["WEBEX_SCOPES"] ?? "spark:messages_read")
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

    private static func preview(_ value: String?) -> String {
        guard let value, !value.isEmpty else {
            return "(nil)"
        }

        let normalized = value.replacingOccurrences(of: "\n", with: "\\n")
        let limit = 160
        guard normalized.count > limit else {
            return normalized
        }

        return String(normalized.prefix(limit)) + "..."
    }

    static func collectMessages(
        client: WebexClient,
        params: ListMessagesParams,
        maxPages: Int
    ) async throws -> MessageCollectionResult {
        var page = try await client.messages.list(params: params)
        var messages = page.items
        var pagesFetched = 1

        while let nextPage = page.nextPage {
            guard pagesFetched < maxPages else {
                return MessageCollectionResult(
                    messages: messages,
                    pagesFetched: pagesFetched,
                    hasMore: true
                )
            }

            page = try await client.messages.list(nextPage: nextPage)
            messages.append(contentsOf: page.items)
            pagesFetched += 1
        }

        return MessageCollectionResult(
            messages: messages,
            pagesFetched: pagesFetched,
            hasMore: false
        )
    }
}

struct MessageCollectionResult: Equatable {
    let messages: [WebexMessage]
    let pagesFetched: Int
    let hasMore: Bool
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

struct MessageListOptions {
    let roomID: String
    let pageSize: Int
    let maxPages: Int
    let params: ListMessagesParams

    init(environment: [String: String]) throws {
        self.roomID = try requiredEnvironment("WEBEX_ROOM_ID", environment: environment)
        self.pageSize = try Self.integer(
            named: "WEBEX_MESSAGES_PAGE_SIZE",
            defaultValue: 25,
            minimum: 1,
            maximum: 1_000,
            environment: environment
        )
        self.maxPages = try Self.integer(
            named: "WEBEX_MESSAGES_MAX_PAGES",
            defaultValue: 1,
            minimum: 1,
            maximum: 10_000,
            environment: environment
        )
        self.params = ListMessagesParams(
            roomID: roomID,
            parentID: Self.trimmedOptional(environment["WEBEX_MESSAGES_PARENT_ID"]),
            mentionedPeople: Self.trimmedOptional(environment["WEBEX_MESSAGES_MENTIONED_PEOPLE"]),
            before: Self.trimmedOptional(environment["WEBEX_MESSAGES_BEFORE"]),
            beforeMessage: Self.trimmedOptional(environment["WEBEX_MESSAGES_BEFORE_MESSAGE"]),
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
