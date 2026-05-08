import Foundation

public struct WebexStreamPage<Item: Sendable>: Sendable {
    public let items: [Item]
    public let nextPage: WebexPageLink?

    public init(items: [Item], nextPage: WebexPageLink?) {
        self.items = items
        self.nextPage = nextPage
    }
}

extension WebexStreamPage: Equatable where Item: Equatable {}

public struct WebexStreamPagination: Equatable, Sendable {
    public let hasMore: Bool
    public let nextPage: WebexPageLink?
    public let pagesLoaded: Int
    public let pageLimit: Int?
    public let capReached: Bool

    public init(
        hasMore: Bool,
        nextPage: WebexPageLink?,
        pagesLoaded: Int,
        pageLimit: Int?,
        capReached: Bool
    ) {
        self.hasMore = hasMore
        self.nextPage = nextPage
        self.pagesLoaded = pagesLoaded
        self.pageLimit = pageLimit
        self.capReached = capReached
    }
}

public struct WebexStreamSnapshot<Item: Sendable>: Sendable {
    public let items: [Item]
    public let revision: UInt64
    public let lastUpdatedAt: Date?
    public let isRefreshing: Bool
    public let isLoadingNextPage: Bool
    public let lastError: WebexSDKError?
    public let pagination: WebexStreamPagination

    public init(
        items: [Item],
        revision: UInt64,
        lastUpdatedAt: Date?,
        isRefreshing: Bool,
        isLoadingNextPage: Bool,
        lastError: WebexSDKError?,
        pagination: WebexStreamPagination
    ) {
        self.items = items
        self.revision = revision
        self.lastUpdatedAt = lastUpdatedAt
        self.isRefreshing = isRefreshing
        self.isLoadingNextPage = isLoadingNextPage
        self.lastError = lastError
        self.pagination = pagination
    }
}

extension WebexStreamSnapshot: Equatable where Item: Equatable {}

public final class WebexSnapshotStream<Item: Sendable>: @unchecked Sendable {
    private let state: WebexSnapshotStreamState<Item>

    public var snapshots: AsyncStream<WebexStreamSnapshot<Item>> {
        let state = state
        return AsyncStream { continuation in
            let id = UUID()
            let subscribeTask = Task {
                await state.subscribe(id: id, continuation: continuation)
            }
            continuation.onTermination = { @Sendable _ in
                subscribeTask.cancel()
                Task {
                    await subscribeTask.value
                    await state.unsubscribe(id: id)
                    await state.cancelPendingSubscribe(id: id)
                }
            }
        }
    }

    public init(
        pageLimit: Int? = nil,
        clock: @escaping @Sendable () -> Date = { Date() },
        id: @escaping @Sendable (Item) -> String,
        loadFirstPage: @escaping @Sendable () async throws -> WebexStreamPage<Item>,
        loadNextPage: @escaping @Sendable (WebexPageLink) async throws -> WebexStreamPage<Item>
    ) {
        self.state = WebexSnapshotStreamState(
            pageLimit: pageLimit.map { max(1, $0) },
            clock: clock,
            id: id,
            loadFirstPage: loadFirstPage,
            loadNextPage: loadNextPage
        )
    }

    public func currentSnapshot() async -> WebexStreamSnapshot<Item> {
        await state.currentSnapshot()
    }

    public func refresh() async {
        await state.refresh()
    }

    public func loadNextPage() async {
        await state.loadNextPage()
    }

    func replaceItems(
        _ items: [Item],
        incrementRevision: Bool = true
    ) async {
        await state.replaceItems(items, incrementRevision: incrementRevision)
    }

    func subscriberCount() async -> Int {
        await state.subscriberCount()
    }

    func subscriptionTombstoneCount() async -> Int {
        await state.subscriptionTombstoneCount()
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
}

private actor WebexSnapshotStreamState<Item: Sendable> {
    private let pageLimit: Int?
    private let clock: @Sendable () -> Date
    private let id: @Sendable (Item) -> String
    private let loadFirstPage: @Sendable () async throws -> WebexStreamPage<Item>
    private let loadNextPage: @Sendable (WebexPageLink) async throws -> WebexStreamPage<Item>

    private var continuations: [UUID: AsyncStream<WebexStreamSnapshot<Item>>.Continuation] = [:]
    private var terminatedSubscriptionIDs: Set<UUID> = []
    private var items: [Item] = []
    private var revision: UInt64 = 0
    private var lastUpdatedAt: Date?
    private var isRefreshing = false
    private var isLoadingNextPage = false
    private var lastError: WebexSDKError?
    private var nextPage: WebexPageLink?
    private var pagesLoaded = 0

    init(
        pageLimit: Int?,
        clock: @escaping @Sendable () -> Date,
        id: @escaping @Sendable (Item) -> String,
        loadFirstPage: @escaping @Sendable () async throws -> WebexStreamPage<Item>,
        loadNextPage: @escaping @Sendable (WebexPageLink) async throws -> WebexStreamPage<Item>
    ) {
        self.pageLimit = pageLimit
        self.clock = clock
        self.id = id
        self.loadFirstPage = loadFirstPage
        self.loadNextPage = loadNextPage
    }

    func subscribe(
        id: UUID,
        continuation: AsyncStream<WebexStreamSnapshot<Item>>.Continuation
    ) {
        guard terminatedSubscriptionIDs.remove(id) == nil else {
            return
        }

        continuations[id] = continuation
        continuation.yield(makeSnapshot())
    }

    func unsubscribe(id: UUID) {
        if continuations.removeValue(forKey: id) == nil {
            terminatedSubscriptionIDs.insert(id)
        }
    }

    func cancelPendingSubscribe(id: UUID) {
        terminatedSubscriptionIDs.remove(id)
    }

    func currentSnapshot() -> WebexStreamSnapshot<Item> {
        makeSnapshot()
    }

    func subscriberCount() -> Int {
        continuations.count
    }

    func subscriptionTombstoneCount() -> Int {
        terminatedSubscriptionIDs.count
    }

    func refresh() async {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        lastError = nil
        emitSnapshot()

        do {
            let page = try await loadFirstPage()
            items = page.items
            nextPage = page.nextPage
            pagesLoaded = 1
            revision += 1
            lastUpdatedAt = clock()
            lastError = nil
        } catch {
            lastError = WebexStreamErrorRedactor.webexStreamError(from: error)
        }

        isRefreshing = false
        emitSnapshot()
    }

    func replaceItems(
        _ newItems: [Item],
        incrementRevision: Bool
    ) {
        items = newItems
        if incrementRevision {
            revision += 1
        }
        emitSnapshot()
    }

    func loadNextPage() async {
        guard !isRefreshing,
              !isLoadingNextPage,
              !isPageCapReached,
              let nextPage else {
            return
        }

        isLoadingNextPage = true
        lastError = nil
        emitSnapshot()

        do {
            let page = try await loadNextPage(nextPage)
            items = mergedItems(existing: items, incoming: page.items)
            self.nextPage = page.nextPage
            pagesLoaded += 1
            revision += 1
            lastUpdatedAt = clock()
            lastError = nil
        } catch {
            lastError = WebexStreamErrorRedactor.webexStreamError(from: error)
        }

        isLoadingNextPage = false
        emitSnapshot()
    }

    private var isPageCapReached: Bool {
        guard let pageLimit else {
            return false
        }

        return pagesLoaded >= pageLimit && nextPage != nil
    }

    private func mergedItems(existing: [Item], incoming: [Item]) -> [Item] {
        var merged = existing
        var indexByID: [String: Int] = [:]
        for (index, item) in merged.enumerated() {
            indexByID[id(item)] = index
        }

        for item in incoming {
            let itemID = id(item)
            if let index = indexByID[itemID] {
                merged[index] = item
            } else {
                indexByID[itemID] = merged.count
                merged.append(item)
            }
        }

        return merged
    }

    private func emitSnapshot() {
        let snapshot = makeSnapshot()
        for continuation in continuations.values {
            continuation.yield(snapshot)
        }
    }

    private func makeSnapshot() -> WebexStreamSnapshot<Item> {
        WebexStreamSnapshot(
            items: items,
            revision: revision,
            lastUpdatedAt: lastUpdatedAt,
            isRefreshing: isRefreshing,
            isLoadingNextPage: isLoadingNextPage,
            lastError: lastError,
            pagination: WebexStreamPagination(
                hasMore: nextPage != nil,
                nextPage: nextPage,
                pagesLoaded: pagesLoaded,
                pageLimit: pageLimit,
                capReached: isPageCapReached
            )
        )
    }

}
