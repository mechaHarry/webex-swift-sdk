import Foundation

internal final class WebexMercuryWebSocketSession: @unchecked Sendable {
    private let webSocket: WebexRealtimeWebSocket
    private let accessTokenProvider: @Sendable () async throws -> AccessTokenState
    private let state = WebexMercuryWebSocketSessionState()

    internal init(
        webSocket: WebexRealtimeWebSocket,
        accessTokenProvider: @escaping @Sendable () async throws -> AccessTokenState
    ) {
        self.webSocket = webSocket
        self.accessTokenProvider = accessTokenProvider
    }

    internal func connect() async throws {
        do {
            try await webSocket.connect()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw redactedError(error, accessToken: state.accessToken())
        }
    }

    internal func authorize() async throws {
        var accessToken: String?

        do {
            let token = try await accessTokenProvider()
            accessToken = token.value
            state.setAccessToken(token.value)
            try await webSocket.send(text: try authorizationFrame(accessToken: token.value))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw redactedError(error, accessToken: accessToken ?? state.accessToken())
        }
    }

    internal func frames() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    while !Task.isCancelled {
                        continuation.yield(try await webSocket.receiveText())
                    }

                    throw CancellationError()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: redactedError(error, accessToken: state.accessToken()))
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
                self.webSocket.cancel()
            }
        }
    }

    internal func ack(messageID: String) async throws {
        try await webSocket.send(text: try encode(AckFrame(messageId: messageID)))
    }

    internal func cancel() {
        webSocket.cancel()
    }

    private func authorizationFrame(accessToken: String) throws -> String {
        try encode(AuthorizationFrame(
            id: UUID().uuidString,
            data: AuthorizationFrame.DataFrame(token: "Bearer \(accessToken)")
        ))
    }

    private func encode<Frame: Encodable>(_ frame: Frame) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(frame)
        guard let text = String(data: data, encoding: .utf8) else {
            throw WebexSDKError.network("Webex realtime WebSocket frame encoding failed")
        }

        return text
    }

    private func redactedError(_ error: Error, accessToken: String?) -> WebexSDKError {
        if case .network(let message) = error as? WebexSDKError {
            return .network(redact(message, accessToken: accessToken))
        }

        if let error = error as? WebexSDKError {
            return error
        }

        return .network("Webex realtime WebSocket failed: \(redact(error.localizedDescription, accessToken: accessToken))")
    }

    private func redact(_ value: String, accessToken: String?) -> String {
        var redacted = Redactor.redactSecrets(value)
        redacted = redactWebSocketURLs(redacted)
        redacted = redactBearerTokens(redacted)
        if let accessToken, !accessToken.isEmpty {
            redacted = redacted.replacingOccurrences(of: accessToken, with: "[redacted]")
        }
        return redacted
    }

    private func redactBearerTokens(_ value: String) -> String {
        let expression = try! NSRegularExpression(
            pattern: #"\bBearer\s+([^\s,;]+)"#,
            options: [.caseInsensitive]
        )
        let mutableValue = NSMutableString(string: value)
        let range = NSRange(location: 0, length: mutableValue.length)
        let matches = expression.matches(in: value, range: range)

        for match in matches.reversed() {
            let tokenRange = match.range(at: 1)
            guard tokenRange.location != NSNotFound else {
                continue
            }

            mutableValue.replaceCharacters(in: tokenRange, with: "[redacted]")
        }

        return mutableValue as String
    }

    private func redactWebSocketURLs(_ value: String) -> String {
        let expression = try! NSRegularExpression(
            pattern: #"\bwss://[^\s"'<>)]+"#,
            options: [.caseInsensitive]
        )
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.stringByReplacingMatches(
            in: value,
            options: [],
            range: range,
            withTemplate: "wss://[redacted]"
        )
    }
}

private struct AuthorizationFrame: Encodable {
    let id: String
    let data: DataFrame
    let type = "authorization"

    struct DataFrame: Encodable {
        let token: String
    }
}

private struct AckFrame: Encodable {
    let messageId: String
    let type = "ack"
}

private final class WebexMercuryWebSocketSessionState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedAccessToken: String?

    func setAccessToken(_ accessToken: String) {
        lock.withLock {
            storedAccessToken = accessToken
        }
    }

    func accessToken() -> String? {
        lock.withLock {
            storedAccessToken
        }
    }
}
