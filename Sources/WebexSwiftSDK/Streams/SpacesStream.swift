import Foundation

public final class SpacesStream: @unchecked Sendable {
    private let baseStream: WebexSnapshotStream<WebexSpace>
    private let enricher: WebexSpaceEnrichmentCoordinator
    private let generation = SpacesStreamGeneration()
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
        let generationID = await generation.next()
        await operationQueue.run { [self] in
            await baseStream.refresh()
            let snapshot = await baseStream.currentSnapshot()
            guard snapshot.lastError == nil else {
                return
            }
            await runEnrichment(forceRefresh: true, generationID: generationID, snapshot: snapshot)
        }
    }

    public func loadNextPage() async {
        let generationID = await generation.next()
        await operationQueue.run { [self] in
            await baseStream.loadNextPage()
            let snapshot = await baseStream.currentSnapshot()
            guard snapshot.lastError == nil else {
                return
            }
            await runEnrichment(forceRefresh: false, generationID: generationID, snapshot: snapshot)
        }
    }

    public func refreshEnrichment() async {
        let generationID = await generation.next()
        await operationQueue.run { [self] in
            let snapshot = await baseStream.currentSnapshot()
            await runEnrichment(forceRefresh: true, generationID: generationID, snapshot: snapshot)
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
        generationID: UInt64,
        snapshot: WebexStreamSnapshot<WebexSpace>
    ) async {
        let loadingItems = await enricher.immediateItems(
            for: snapshot.items,
            forceRefresh: forceRefresh
        )
        guard await generation.isCurrent(generationID) else {
            return
        }
        await baseStream.replaceItems(loadingItems, incrementRevision: false)

        let enrichedItems = await enricher.enrichedItems(
            for: snapshot.items,
            forceRefresh: forceRefresh,
            shouldCommitCache: { [generation] in
                await generation.isCurrent(generationID)
            }
        )
        guard await generation.isCurrent(generationID) else {
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

    func run(_ operation: @escaping @Sendable () async -> Void) async {
        let previous = tail
        tailID += 1
        let operationID = tailID
        let task = Task {
            await previous?.value
            await operation()
        }
        tail = task
        await task.value
        if tailID == operationID {
            tail = nil
        }
    }
}

private actor SpacesStreamGeneration {
    private var current: UInt64 = 0

    func next() -> UInt64 {
        current += 1
        return current
    }

    func isCurrent(_ generationID: UInt64) -> Bool {
        generationID == current
    }
}

public typealias RoomsStream = SpacesStream
