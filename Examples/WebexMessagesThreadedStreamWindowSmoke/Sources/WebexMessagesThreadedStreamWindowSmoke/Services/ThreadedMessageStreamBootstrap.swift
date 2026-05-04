import AppKit
import Foundation
import WebexSwiftSDK

enum ThreadedMessageStreamBootstrap {
    static func makeRuntime(configuration: ThreadedStreamSmokeConfiguration) async throws -> ThreadedMessageStreamRuntime {
        let httpClient = URLSessionHTTPClient()
        let store = KeychainWebexStore(service: configuration.keychainService)
        let registry = WebexClientRegistry(store: store, httpClient: httpClient)
        let authorized = try await registry.authorizeAndAddAccount(
            configuration: configuration.integration,
            openAuthorizationURL: { authorizationURL in
                guard NSWorkspace.shared.open(authorizationURL) else {
                    throw ThreadedStreamSmokeError.failedToOpenAuthorizationURL
                }
            }
        )
        let tokenRecord = try await store.loadTokenRecord(for: authorized.account.id)
        do {
            try validateGrantedRealtimeScopes(
                requestedScopes: configuration.integration.scopes,
                grantedScopes: tokenRecord?.grantedScopes ?? []
            )
        } catch {
            try? await registry.removeAccount(authorized.account.id)
            throw error
        }

        let stream = authorized.client.messages.threadedStream(
            params: configuration.listParams,
            pageLimit: configuration.pageLimit
        )
        let connection = authorized.client.realtime.connect(options: WebexRealtimeOptions(
            resources: [.messages],
            events: [.created, .updated, .deleted],
            deviceName: "webex-messages-threaded-stream-window-smoke"
        ))
        let refreshTask = stream.refreshOnTriggers(connection.triggers) { trigger in
            shouldRefreshMessagesStream(for: trigger, roomID: configuration.roomID)
        }

        return ThreadedMessageStreamRuntime(
            stream: stream,
            realtimeStates: connection.states,
            cancel: {
                refreshTask.cancel()
                connection.cancel()
            }
        )
    }

    static func shouldRefreshMessagesStream(
        for trigger: WebexStreamTrigger,
        roomID: String
    ) -> Bool {
        guard trigger.resource == WebexRealtimeResource.messages.rawValue else {
            return false
        }

        guard webexID(trigger.roomID, matches: roomID) else {
            return false
        }

        switch WebexRealtimeEventName(rawValue: trigger.event) {
        case .created, .updated, .deleted:
            return true
        case .seen, .unknown:
            return false
        }
    }

    static func validateGrantedRealtimeScopes(
        requestedScopes: [String],
        grantedScopes: [String]
    ) throws {
        let requiredScopes = ["spark:all", "spark:kms"]
        let grantedSet = Set(grantedScopes)
        let missingScopes = requiredScopes.filter { !grantedSet.contains($0) }
        guard missingScopes.isEmpty else {
            throw ThreadedStreamSmokeError.missingRealtimeScopes(
                requested: requestedScopes,
                granted: grantedScopes
            )
        }
    }

    private static func webexID(_ left: String?, matches right: String) -> Bool {
        guard let left else {
            return false
        }

        let leftCandidates = webexIDCandidates(left)
        let rightCandidates = webexIDCandidates(right)
        return !leftCandidates.isDisjoint(with: rightCandidates)
    }

    private static func webexIDCandidates(_ value: String) -> Set<String> {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        var candidates = Set([trimmed])
        guard let decoded = base64DecodedString(trimmed) else {
            return candidates
        }

        candidates.insert(decoded)
        if let terminalComponent = decoded.split(separator: "/").last {
            candidates.insert(String(terminalComponent))
        }
        return candidates
    }

    private static func base64DecodedString(_ value: String) -> String? {
        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - normalized.count % 4) % 4
        if padding > 0 {
            normalized.append(String(repeating: "=", count: padding))
        }

        guard let data = Data(base64Encoded: normalized),
              let decoded = String(data: data, encoding: .utf8),
              !decoded.isEmpty else {
            return nil
        }

        return decoded
    }
}
