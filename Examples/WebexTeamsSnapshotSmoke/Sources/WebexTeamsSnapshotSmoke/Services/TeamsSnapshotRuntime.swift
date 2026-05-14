import Foundation
import WebexSwiftSDK

final class TeamsSnapshotRuntime: @unchecked Sendable {
    let snapshots: AsyncStream<WebexStreamSnapshot<WebexTeam>>
    let currentSnapshot: @Sendable () async -> WebexStreamSnapshot<WebexTeam>
    var refresh: @Sendable () async -> Void
    var loadNextPage: @Sendable () async -> Void

    private let lock = NSLock()
    private var cancelHandler: (@Sendable () -> Void)?

    init(
        stream: TeamsStream,
        cancel: @escaping @Sendable () -> Void = {}
    ) {
        self.snapshots = stream.snapshots
        self.currentSnapshot = {
            await stream.currentSnapshot()
        }
        self.refresh = {
            await stream.refresh()
        }
        self.loadNextPage = {
            await stream.loadNextPage()
        }
        self.cancelHandler = cancel
    }

    init(
        snapshots: AsyncStream<WebexStreamSnapshot<WebexTeam>>,
        currentSnapshot: @escaping @Sendable () async -> WebexStreamSnapshot<WebexTeam>,
        refresh: @escaping @Sendable () async -> Void,
        loadNextPage: @escaping @Sendable () async -> Void,
        cancel: @escaping @Sendable () -> Void = {}
    ) {
        self.snapshots = snapshots
        self.currentSnapshot = currentSnapshot
        self.refresh = refresh
        self.loadNextPage = loadNextPage
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
