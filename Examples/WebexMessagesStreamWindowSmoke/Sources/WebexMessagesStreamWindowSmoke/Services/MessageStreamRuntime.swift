import Foundation
import WebexSwiftSDK

final class MessageStreamRuntime: @unchecked Sendable {
    let stream: MessagesStream
    let realtimeStates: AsyncStream<WebexRealtimeConnectionState>?

    private let lock = NSLock()
    private var cancelHandler: (@Sendable () -> Void)?

    init(
        stream: MessagesStream,
        realtimeStates: AsyncStream<WebexRealtimeConnectionState>? = nil,
        cancel: @escaping @Sendable () -> Void = {}
    ) {
        self.stream = stream
        self.realtimeStates = realtimeStates
        self.cancelHandler = cancel
    }

    deinit {
        cancel()
    }

    func cancel() {
        let handler = lock.withLock {
            let handler = cancelHandler
            cancelHandler = nil
            return handler
        }
        handler?()
    }
}
