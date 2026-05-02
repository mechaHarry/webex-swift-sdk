import Foundation

internal final class WebexMercuryWebSocketSession: @unchecked Sendable {
    private let webSocket: WebexRealtimeWebSocket
    private let accessTokenProvider: @Sendable () async throws -> AccessTokenState

    internal init(
        webSocket: WebexRealtimeWebSocket,
        accessTokenProvider: @escaping @Sendable () async throws -> AccessTokenState
    ) {
        self.webSocket = webSocket
        self.accessTokenProvider = accessTokenProvider
    }

    internal func frames() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var accessToken: String?

                do {
                    try await webSocket.connect()
                    let token = try await accessTokenProvider()
                    accessToken = token.value
                    try await webSocket.send(text: try authorizationFrame(accessToken: token.value))

                    while !Task.isCancelled {
                        continuation.yield(try await webSocket.receiveText())
                    }

                    throw CancellationError()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: redactedNetworkError(error, accessToken: accessToken))
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
        try encode(AuthorizationFrame(data: AuthorizationFrame.DataFrame(token: "Bearer \(accessToken)")))
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

    private func redactedNetworkError(_ error: Error, accessToken: String?) -> WebexSDKError {
        if case .network(let message) = error as? WebexSDKError {
            return .network(redact(message, accessToken: accessToken))
        }

        return .network("Webex realtime WebSocket failed: \(redact(error.localizedDescription, accessToken: accessToken))")
    }

    private func redact(_ value: String, accessToken: String?) -> String {
        var redacted = Redactor.redactSecrets(value)
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
}

private struct AuthorizationFrame: Encodable {
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
