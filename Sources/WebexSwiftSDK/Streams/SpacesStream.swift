import Foundation

public final class SpacesStream: @unchecked Sendable {
    private let baseStream: WebexSnapshotStream<WebexSpace>
    private let enricher: WebexSpaceEnrichmentCoordinator
    private let operationGate = SpacesStreamOperationGate()
    private let operationQueue = SpacesStreamOperationQueue()

    public var snapshots: AsyncStream<WebexStreamSnapshot<WebexSpace>> {
        baseStream.snapshots
    }

    init(
        baseStream: WebexSnapshotStream<WebexSpace>,
        enricher: WebexSpaceEnrichmentCoordinator
    ) {
        self.baseStream = baseStream
        self.enricher = enricher
    }

    public func currentSnapshot() async -> WebexStreamSnapshot<WebexSpace> {
        await baseStream.currentSnapshot()
    }

    public func refresh() async {
        guard !Task.isCancelled else {
            return
        }

        let operation = await operationGate.reserve()
        await operationQueue.run(
            cancellation: operation.cancellation,
            onStart: { [operationGate] in
                await operationGate.start(operation)
            },
            onCancel: { [operationGate] in
                await operationGate.cancel(operation)
            },
            onFinish: { [operationGate] in
                await operationGate.finish(operation)
            }
        ) { [self] in
            await baseStream.refresh()
            let snapshot = await baseStream.currentSnapshot()
            guard snapshot.lastError == nil else {
                return
            }
            await runEnrichment(forceRefresh: false, operation: operation, snapshot: snapshot)
        }
    }

    public func loadNextPage() async {
        guard !Task.isCancelled else {
            return
        }

        let operation = await operationGate.reserve()
        await operationQueue.run(
            cancellation: operation.cancellation,
            onStart: { [operationGate] in
                await operationGate.start(operation)
            },
            onCancel: { [operationGate] in
                await operationGate.cancel(operation)
            },
            onFinish: { [operationGate] in
                await operationGate.finish(operation)
            }
        ) { [self] in
            await baseStream.loadNextPage()
            let snapshot = await baseStream.currentSnapshot()
            guard snapshot.lastError == nil else {
                return
            }
            await runEnrichment(forceRefresh: false, operation: operation, snapshot: snapshot)
        }
    }

    public func refreshEnrichment() async {
        guard !Task.isCancelled else {
            return
        }

        let operation = await operationGate.reserve()
        await operationQueue.run(
            cancellation: operation.cancellation,
            onStart: { [operationGate] in
                await operationGate.start(operation)
            },
            onCancel: { [operationGate] in
                await operationGate.cancel(operation)
            },
            onFinish: { [operationGate] in
                await operationGate.finish(operation)
            }
        ) { [self] in
            let snapshot = await baseStream.currentSnapshot()
            await runEnrichment(forceRefresh: true, operation: operation, snapshot: snapshot)
        }
    }

    public func refreshOnTriggers(
        _ triggers: AsyncStream<WebexStreamTrigger>,
        where shouldRefresh: @escaping @Sendable (WebexStreamTrigger) -> Bool = { _ in true }
    ) -> Task<Void, Never> {
        Task { [weak self] in
            for await trigger in triggers {
                guard !Task.isCancelled else {
                    return
                }

                guard shouldRefresh(trigger) else {
                    continue
                }

                guard let self else {
                    return
                }

                await self.refresh()
            }
        }
    }

    private func runEnrichment(
        forceRefresh: Bool,
        operation: SpacesStreamOperation,
        snapshot: WebexStreamSnapshot<WebexSpace>
    ) async {
        guard !Task.isCancelled else {
            return
        }

        let loadingItems = await enricher.immediateItems(
            for: snapshot.items,
            forceRefresh: forceRefresh
        )
        guard await operationGate.canCommit(operation) else {
            return
        }
        await baseStream.replaceItems(loadingItems, incrementRevision: false)

        guard !Task.isCancelled else {
            return
        }

        let enrichedItems = await enricher.enrichedItems(
            for: snapshot.items,
            forceRefresh: forceRefresh,
            shouldCommitCache: { [operationGate] in
                await operationGate.canCommit(operation)
            }
        )
        guard await operationGate.canCommit(operation) else {
            return
        }
        if enrichedItems != loadingItems {
            await baseStream.replaceItems(enrichedItems, incrementRevision: true)
        }
    }
}

private actor SpacesStreamOperationQueue {
    private var tail: Task<Void, Never>?
    private var tailID: UInt64 = 0

    func run(
        cancellation: SpacesStreamOperationCancellation,
        onStart: @escaping @Sendable () async -> Bool,
        onCancel: @escaping @Sendable () async -> Void,
        onFinish: @escaping @Sendable () async -> Void,
        operation: @escaping @Sendable () async -> Void
    ) async {
        guard !Task.isCancelled else {
            await onCancel()
            return
        }

        let previous = tail
        tailID += 1
        let operationID = tailID
        let task = Task {
            await previous?.value
            guard !Task.isCancelled,
                  !cancellation.isCancelled else {
                return
            }
            guard await onStart() else {
                return
            }
            await operation()
        }
        tail = task

        if Task.isCancelled {
            task.cancel()
            cancellation.cancel()
            await onCancel()
        }

        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            cancellation.cancel()
            task.cancel()
            Task {
                await onCancel()
            }
        }

        if Task.isCancelled {
            cancellation.cancel()
            await onCancel()
        }

        if cancellation.isCancelled {
            await onCancel()
        } else {
            await onFinish()
        }

        if tailID == operationID {
            tail = nil
        }
    }
}

private struct SpacesStreamOperation: Sendable {
    let id: UInt64
    let cancellation: SpacesStreamOperationCancellation
}

private final class SpacesStreamOperationCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
    }
}

private actor SpacesStreamOperationGate {
    private var nextID: UInt64 = 0
    private var pending: [UInt64: SpacesStreamOperationCancellation] = [:]
    private var running: Set<UInt64> = []

    func reserve() -> SpacesStreamOperation {
        nextID += 1
        let cancellation = SpacesStreamOperationCancellation()
        pending[nextID] = cancellation
        return SpacesStreamOperation(id: nextID, cancellation: cancellation)
    }

    func start(_ operation: SpacesStreamOperation) -> Bool {
        pruneCancelledPending()
        guard pending.removeValue(forKey: operation.id) != nil,
              !operation.cancellation.isCancelled else {
            return false
        }
        running.insert(operation.id)
        return true
    }

    func cancel(_ operation: SpacesStreamOperation) {
        operation.cancellation.cancel()
        pending.removeValue(forKey: operation.id)
        running.remove(operation.id)
    }

    func finish(_ operation: SpacesStreamOperation) {
        pending.removeValue(forKey: operation.id)
        running.remove(operation.id)
    }

    func canCommit(_ operation: SpacesStreamOperation) -> Bool {
        pruneCancelledPending()
        return running.contains(operation.id)
            && !pending.keys.contains(where: { $0 > operation.id })
            && !running.contains(where: { $0 > operation.id })
    }

    private func pruneCancelledPending() {
        pending = pending.filter { _, cancellation in
            !cancellation.isCancelled
        }
    }
}

public typealias RoomsStream = SpacesStream
