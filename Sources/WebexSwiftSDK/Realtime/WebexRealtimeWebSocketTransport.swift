import Foundation

internal protocol WebexRealtimeWebSocket: Sendable {
    func connect() async throws
    func send(text: String) async throws
    func receiveText() async throws -> String
    func cancel()
}

internal final class URLSessionWebSocketTransport: WebexRealtimeWebSocket, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    internal init(url: URL, session: URLSession = .shared) {
        self.task = session.webSocketTask(with: Self.preparedURL(for: url))
    }

    internal static func preparedURL(
        for url: URL,
        clientTimestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
    ) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        var queryItems = components.queryItems ?? []
        setQueryItem(name: "outboundWireFormat", value: "text", in: &queryItems)
        setQueryItem(name: "bufferStates", value: "true", in: &queryItems)
        setQueryItem(name: "aliasHttpStatus", value: "true", in: &queryItems)
        setQueryItem(name: "clientTimestamp", value: String(clientTimestamp), in: &queryItems)
        components.queryItems = queryItems

        return components.url ?? url
    }

    internal func connect() async throws {
        task.resume()
    }

    internal func send(text: String) async throws {
        try await task.send(.string(text))
    }

    internal func receiveText() async throws -> String {
        switch try await task.receive() {
        case .string(let text):
            return text
        case .data:
            throw WebexSDKError.network("Webex realtime WebSocket received unsupported binary frame")
        @unknown default:
            throw WebexSDKError.network("Webex realtime WebSocket received unsupported frame")
        }
    }

    internal func cancel() {
        task.cancel(with: .goingAway, reason: nil)
    }

    private static func setQueryItem(
        name: String,
        value: String,
        in queryItems: inout [URLQueryItem]
    ) {
        queryItems.removeAll { $0.name == name }
        queryItems.append(URLQueryItem(name: name, value: value))
    }
}
