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
            let previousSnapshot = await baseStream.currentSnapshot()
            await baseStream.loadNextPage()
            let snapshot = await baseStream.currentSnapshot()
            guard snapshot.lastError == nil else {
                return
            }
            guard snapshot.revision != previousSnapshot.revision else {
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
        let didEmitLoading: Bool
        if await operationGate.canCommitCache(operation) {
            await baseStream.replaceItems(loadingItems, incrementRevision: false)
            didEmitLoading = true
        } else {
            didEmitLoading = false
        }

        guard !Task.isCancelled else {
            await restoreItems(from: snapshot, operation: operation)
            return
        }

        guard didEmitLoading else {
            return
        }

        let enrichedItems = await enricher.enrichedItems(
            for: snapshot.items,
            forceRefresh: forceRefresh,
            shouldCommitCache: { [operationGate] in
                await operationGate.canCommitCache(operation)
            }
        )
        guard !Task.isCancelled else {
            await restoreItems(from: snapshot, operation: operation)
            return
        }
        guard await canReplaceItems(from: snapshot, operation: operation) else {
            return
        }
        if enrichedItems != loadingItems {
            await baseStream.replaceItems(enrichedItems, incrementRevision: true)
        }
    }

    private func canReplaceItems(
        from snapshot: WebexStreamSnapshot<WebexSpace>,
        operation: SpacesStreamOperation
    ) async -> Bool {
        guard await operationGate.isRunning(operation) else {
            return false
        }

        let currentSnapshot = await baseStream.currentSnapshot()
        return currentSnapshot.revision == snapshot.revision
    }

    private func restoreItems(
        from snapshot: WebexStreamSnapshot<WebexSpace>,
        operation: SpacesStreamOperation
    ) async {
        guard await operationGate.canRestore(operation) else {
            return
        }

        let currentSnapshot = await baseStream.currentSnapshot()
        guard currentSnapshot.revision == snapshot.revision else {
            return
        }

        await baseStream.replaceItems(snapshot.items, incrementRevision: false)
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
        let execution = SpacesStreamQueuedExecution()
        let task = Task {
            await previous?.value
            guard !Task.isCancelled,
                  !cancellation.isCancelled else {
                return
            }
            guard await onStart() else {
                return
            }
            await execution.markStarted()
            await operation()
        }
        tail = task

        if Task.isCancelled {
            task.cancel()
            cancellation.cancel()
            await onCancel()
        }

        let completed = await withTaskCancellationHandler {
            await waitForCompletionOrQueuedCancellation(
                task: task,
                cancellation: cancellation,
                execution: execution
            )
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
            tail = completed ? nil : previous
        }
    }

    private func waitForCompletionOrQueuedCancellation(
        task: Task<Void, Never>,
        cancellation: SpacesStreamOperationCancellation,
        execution: SpacesStreamQueuedExecution
    ) async -> Bool {
        let race = SpacesStreamOperationWaitRace()
        let completionWaiter = Task {
            await task.value
            race.complete(with: true)
        }
        let cancellationWaiter = Task {
            await cancellation.waitUntilCancelled()
            if await execution.hasStarted {
                await task.value
                race.complete(with: true)
            } else {
                race.complete(with: false)
            }
        }
        let completed = await race.wait()
        completionWaiter.cancel()
        cancellationWaiter.cancel()
        return completed
    }
}

struct SpacesStreamOperation: Sendable {
    let id: UInt64
    let cancellation: SpacesStreamOperationCancellation
}

private actor SpacesStreamQueuedExecution {
    private var started = false

    var hasStarted: Bool {
        started
    }

    func markStarted() {
        started = true
    }
}

private final class SpacesStreamOperationWaitRace: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Bool?
    private var continuation: CheckedContinuation<Bool, Never>?

    func wait() async -> Bool {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(returning: result)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    func complete(with result: Bool) {
        let continuation: CheckedContinuation<Bool, Never>?
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        continuation?.resume(returning: result)
    }
}

final class SpacesStreamOperationCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        let continuations: [CheckedContinuation<Void, Never>]
        lock.lock()
        guard !cancelled else {
            lock.unlock()
            return
        }
        cancelled = true
        continuations = Array(waiters.values)
        waiters.removeAll()
        lock.unlock()

        for continuation in continuations {
            continuation.resume()
        }
    }

    func waitUntilCancelled() async {
        let waiterID = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.lock()
                if cancelled {
                    lock.unlock()
                    continuation.resume()
                } else {
                    waiters[waiterID] = continuation
                    lock.unlock()
                }
            }
        } onCancel: {
            removeWaiter(waiterID)
        }
    }

    private func removeWaiter(_ waiterID: UUID) {
        let continuation: CheckedContinuation<Void, Never>?
        lock.lock()
        continuation = waiters.removeValue(forKey: waiterID)
        lock.unlock()

        continuation?.resume()
    }
}

actor SpacesStreamOperationGate {
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

    func canCommitCache(_ operation: SpacesStreamOperation) -> Bool {
        pruneCancelledPending()
        return running.contains(operation.id)
            && !operation.cancellation.isCancelled
            && !pending.keys.contains(where: { $0 > operation.id })
            && !running.contains(where: { $0 > operation.id })
    }

    func isRunning(_ operation: SpacesStreamOperation) -> Bool {
        running.contains(operation.id)
    }

    func canRestore(_ operation: SpacesStreamOperation) -> Bool {
        pruneCancelledPending()
        return !pending.keys.contains(where: { $0 > operation.id })
            && !running.contains(where: { $0 > operation.id })
    }

    private func pruneCancelledPending() {
        pending = pending.filter { _, cancellation in
            !cancellation.isCancelled
        }
    }
}

public typealias RoomsStream = SpacesStream
