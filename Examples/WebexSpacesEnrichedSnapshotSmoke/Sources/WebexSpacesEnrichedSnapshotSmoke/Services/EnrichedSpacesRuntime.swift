import Foundation
import WebexSwiftSDK

final class EnrichedSpacesRuntime: @unchecked Sendable {
    let snapshots: AsyncStream<WebexStreamSnapshot<WebexSpace>>
    let currentSnapshot: @Sendable () async -> WebexStreamSnapshot<WebexSpace>
    let refresh: @Sendable () async -> Void
    let refreshEnrichment: @Sendable () async -> Void
    let loadNextPage: @Sendable () async -> Void

    private let lock = NSLock()
    private var cancelHandler: (@Sendable () -> Void)?

    init(
        stream: SpacesStream,
        cancel: @escaping @Sendable () -> Void = {}
    ) {
        self.snapshots = stream.snapshots
        self.currentSnapshot = {
            await stream.currentSnapshot()
        }
        self.refresh = {
            await stream.refresh()
        }
        self.refreshEnrichment = {
            await stream.refreshEnrichment()
        }
        self.loadNextPage = {
            await stream.loadNextPage()
        }
        self.cancelHandler = cancel
    }

    init(
        snapshots: AsyncStream<WebexStreamSnapshot<WebexSpace>>,
        currentSnapshot: @escaping @Sendable () async -> WebexStreamSnapshot<WebexSpace>,
        refresh: @escaping @Sendable () async -> Void,
        refreshEnrichment: @escaping @Sendable () async -> Void,
        loadNextPage: @escaping @Sendable () async -> Void,
        cancel: @escaping @Sendable () -> Void = {}
    ) {
        self.snapshots = snapshots
        self.currentSnapshot = currentSnapshot
        self.refresh = refresh
        self.refreshEnrichment = refreshEnrichment
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
