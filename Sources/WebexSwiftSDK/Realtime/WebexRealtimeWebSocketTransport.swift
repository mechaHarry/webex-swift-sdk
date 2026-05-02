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
        self.task = session.webSocketTask(with: url)
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
}
