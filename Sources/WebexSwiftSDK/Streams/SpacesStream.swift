import Foundation

public final class SpacesStream: @unchecked Sendable {
    private let baseStream: WebexSnapshotStream<WebexSpace>
    private let enricher: WebexSpaceEnrichmentCoordinator
    private let generation = SpacesStreamGeneration()

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
        await baseStream.refresh()
        await runEnrichment(forceRefresh: false)
    }

    public func loadNextPage() async {
        await baseStream.loadNextPage()
        await runEnrichment(forceRefresh: false)
    }

    public func refreshEnrichment() async {
        await runEnrichment(forceRefresh: true)
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

    private func runEnrichment(forceRefresh: Bool) async {
        let generationID = await generation.next()
        let snapshot = await baseStream.currentSnapshot()
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
            forceRefresh: forceRefresh
        )
        guard await generation.isCurrent(generationID) else {
            return
        }
        if enrichedItems != loadingItems {
            await baseStream.replaceItems(enrichedItems, incrementRevision: true)
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
