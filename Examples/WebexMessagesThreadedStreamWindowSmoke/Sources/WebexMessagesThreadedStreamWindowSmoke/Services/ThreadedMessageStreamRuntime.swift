import Foundation
import WebexSwiftSDK

final class ThreadedMessageStreamRuntime: @unchecked Sendable {
    let stream: MessagesThreadStream
    let realtimeStates: AsyncStream<WebexRealtimeConnectionState>?

    private let lock = NSLock()
    private var cancelHandler: (@Sendable () -> Void)?

    init(
        stream: MessagesThreadStream,
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
