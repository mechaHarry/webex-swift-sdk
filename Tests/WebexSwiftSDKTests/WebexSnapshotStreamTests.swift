import XCTest
@testable import WebexSwiftSDK

final class WebexSnapshotStreamTests: XCTestCase {
    func testRefreshEmitsLoadingSnapshotAndKeepsPreviousItemsVisible() async throws {
        let loader = ControllableStreamPageLoader()
        let clock = IncrementingClock()
        let stream = WebexSnapshotStream<StreamTestItem>(
            pageLimit: 3,
            clock: { clock.now() },
            id: { $0.id },
            loadFirstPage: { try await loader.loadFirstPage() },
            loadNextPage: { try await loader.loadNextPage($0) }
        )

        var iterator = stream.snapshots.makeAsyncIterator()
        let initial = try await nextSnapshot(from: &iterator)
        XCTAssertEqual(initial.items, [])
        XCTAssertEqual(initial.revision, 0)
        XCTAssertFalse(initial.isRefreshing)
        XCTAssertFalse(initial.isLoadingNextPage)
        XCTAssertNil(initial.lastUpdatedAt)
        XCTAssertNil(initial.lastError)
        XCTAssertEqual(initial.pagination.pagesLoaded, 0)

        let firstRefresh = Task { await stream.refresh() }
        let firstLoading = try await nextSnapshot(from: &iterator)
        XCTAssertEqual(firstLoading.items, [])
        XCTAssertTrue(firstLoading.isRefreshing)

        await loader.succeedFirstPage(items: [.init(id: "space-1", value: "General")])
        await firstRefresh.value

        let firstLoaded = try await nextSnapshot(from: &iterator)
        XCTAssertEqual(firstLoaded.items, [.init(id: "space-1", value: "General")])
        XCTAssertEqual(firstLoaded.revision, 1)
        XCTAssertFalse(firstLoaded.isRefreshing)
        XCTAssertNotNil(firstLoaded.lastUpdatedAt)
        XCTAssertEqual(firstLoaded.pagination.pagesLoaded, 1)

        let secondRefresh = Task { await stream.refresh() }
        let secondLoading = try await nextSnapshot(from: &iterator)
        XCTAssertEqual(secondLoading.items, [.init(id: "space-1", value: "General")])
        XCTAssertTrue(secondLoading.isRefreshing)

        await loader.succeedFirstPage(items: [.init(id: "space-2", value: "Updated")])
        await secondRefresh.value

        let secondLoaded = try await nextSnapshot(from: &iterator)
        XCTAssertEqual(secondLoaded.items, [.init(id: "space-2", value: "Updated")])
        XCTAssertEqual(secondLoaded.revision, 2)
        XCTAssertFalse(secondLoaded.isRefreshing)
    }

    func testLoadNextPageAppendsUniqueItemsAndExposesPageCap() async throws {
        let firstNextPage = WebexPageLink(url: URL(string: "https://webexapis.com/v1/rooms?cursor=first")!)
        let secondNextPage = WebexPageLink(url: URL(string: "https://webexapis.com/v1/rooms?cursor=second")!)
        let loader = ControllableStreamPageLoader()
        let stream = WebexSnapshotStream<StreamTestItem>(
            pageLimit: 2,
            id: { $0.id },
            loadFirstPage: { try await loader.loadFirstPage() },
            loadNextPage: { try await loader.loadNextPage($0) }
        )

        var iterator = stream.snapshots.makeAsyncIterator()
        _ = await iterator.next()

        let refresh = Task { await stream.refresh() }
        _ = await iterator.next()
        await loader.succeedFirstPage(
            items: [.init(id: "item-1", value: "First")],
            nextPage: firstNextPage
        )
        await refresh.value

        let firstLoaded = try await nextSnapshot(from: &iterator)
        XCTAssertEqual(firstLoaded.items.map(\.id), ["item-1"])
        XCTAssertTrue(firstLoaded.pagination.hasMore)
        XCTAssertFalse(firstLoaded.pagination.capReached)
        XCTAssertEqual(firstLoaded.pagination.nextPage, firstNextPage)

        let nextPage = Task { await stream.loadNextPage() }
        let loadingNext = try await nextSnapshot(from: &iterator)
        XCTAssertEqual(loadingNext.items.map(\.id), ["item-1"])
        XCTAssertTrue(loadingNext.isLoadingNextPage)

        await loader.succeedNextPage(
            items: [
                .init(id: "item-1", value: "Updated First"),
                .init(id: "item-2", value: "Second")
            ],
            nextPage: secondNextPage
        )
        await nextPage.value

        let loadedNext = try await nextSnapshot(from: &iterator)
        XCTAssertEqual(
            loadedNext.items,
            [
                .init(id: "item-1", value: "Updated First"),
                .init(id: "item-2", value: "Second")
            ]
        )
        XCTAssertEqual(loadedNext.pagination.pagesLoaded, 2)
        XCTAssertTrue(loadedNext.pagination.hasMore)
        XCTAssertTrue(loadedNext.pagination.capReached)
        XCTAssertEqual(loadedNext.pagination.nextPage, secondNextPage)

        await stream.loadNextPage()
        let nextPageCallCount = await loader.nextPageCallCount
        XCTAssertEqual(nextPageCallCount, 1)
    }

    func testRefreshFailurePreservesExistingItemsAndPublishesRedactedError() async throws {
        let loader = ControllableStreamPageLoader()
        let stream = WebexSnapshotStream<StreamTestItem>(
            id: { $0.id },
            loadFirstPage: { try await loader.loadFirstPage() },
            loadNextPage: { try await loader.loadNextPage($0) }
        )

        var iterator = stream.snapshots.makeAsyncIterator()
        _ = await iterator.next()

        let firstRefresh = Task { await stream.refresh() }
        _ = await iterator.next()
        await loader.succeedFirstPage(items: [.init(id: "item-1", value: "First")])
        await firstRefresh.value
        _ = await iterator.next()

        let failedRefresh = Task { await stream.refresh() }
        _ = await iterator.next()
        await loader.failFirstPage(WebexSDKError.network("callback code=secret-code"))
        await failedRefresh.value

        let failedSnapshot = try await nextSnapshot(from: &iterator)
        XCTAssertEqual(failedSnapshot.items, [.init(id: "item-1", value: "First")])
        XCTAssertEqual(failedSnapshot.lastError, .network("callback code=[redacted]"))
        XCTAssertFalse(failedSnapshot.isRefreshing)
    }

    func testReplaceItemsEmitsSnapshotWithoutChangingPagination() async throws {
        let nextPage = WebexPageLink(url: URL(string: "https://webexapis.com/v1/rooms?cursor=next")!)
        let loader = ControllableStreamPageLoader()
        let stream = WebexSnapshotStream<StreamTestItem>(
            pageLimit: 3,
            id: { $0.id },
            loadFirstPage: { try await loader.loadFirstPage() },
            loadNextPage: { try await loader.loadNextPage($0) }
        )

        var iterator = stream.snapshots.makeAsyncIterator()
        _ = await iterator.next()

        let refresh = Task { await stream.refresh() }
        _ = await iterator.next()
        await loader.succeedFirstPage(
            items: [.init(id: "item-1", value: "Base")],
            nextPage: nextPage
        )
        await refresh.value
        _ = try await nextSnapshot(from: &iterator)

        await stream.replaceItems(
            [.init(id: "item-1", value: "Enriched")],
            incrementRevision: true
        )

        let replaced = try await nextSnapshot(from: &iterator)
        XCTAssertEqual(replaced.items, [.init(id: "item-1", value: "Enriched")])
        XCTAssertEqual(replaced.revision, 2)
        XCTAssertEqual(replaced.pagination.nextPage, nextPage)
        XCTAssertEqual(replaced.pagination.pagesLoaded, 1)
        XCTAssertFalse(replaced.isRefreshing)
        XCTAssertFalse(replaced.isLoadingNextPage)
    }

    func testReplaceItemsWithoutIncrementingRevisionPreservesStreamState() async throws {
        let nextPage = WebexPageLink(url: URL(string: "https://webexapis.com/v1/rooms?cursor=next")!)
        let loader = ControllableStreamPageLoader()
        let clock = IncrementingClock()
        let stream = WebexSnapshotStream<StreamTestItem>(
            pageLimit: 3,
            clock: { clock.now() },
            id: { $0.id },
            loadFirstPage: { try await loader.loadFirstPage() },
            loadNextPage: { try await loader.loadNextPage($0) }
        )

        var iterator = stream.snapshots.makeAsyncIterator()
        _ = await iterator.next()

        let refresh = Task { await stream.refresh() }
        _ = await iterator.next()
        await loader.succeedFirstPage(
            items: [.init(id: "item-1", value: "Base")],
            nextPage: nextPage
        )
        await refresh.value
        let loaded = try await nextSnapshot(from: &iterator)

        let failedNextPage = Task { await stream.loadNextPage() }
        _ = await iterator.next()
        await loader.failNextPage(WebexSDKError.network("callback code=secret-code"))
        await failedNextPage.value
        let failed = try await nextSnapshot(from: &iterator)
        XCTAssertEqual(failed.revision, loaded.revision)
        XCTAssertEqual(failed.lastError, .network("callback code=[redacted]"))

        await stream.replaceItems(
            [.init(id: "item-1", value: "Enriched")],
            incrementRevision: false
        )

        let replaced = try await nextSnapshot(from: &iterator)
        XCTAssertEqual(replaced.items, [.init(id: "item-1", value: "Enriched")])
        XCTAssertEqual(replaced.revision, failed.revision)
        XCTAssertEqual(replaced.lastUpdatedAt, failed.lastUpdatedAt)
        XCTAssertEqual(replaced.pagination, failed.pagination)
        XCTAssertEqual(replaced.lastError, failed.lastError)
        XCTAssertEqual(replaced.isRefreshing, failed.isRefreshing)
        XCTAssertEqual(replaced.isLoadingNextPage, failed.isLoadingNextPage)
    }

    func testConcurrentRefreshesCoalesceIntoOneLoad() async throws {
        let loader = ControllableStreamPageLoader()
        let stream = WebexSnapshotStream<StreamTestItem>(
            id: { $0.id },
            loadFirstPage: { try await loader.loadFirstPage() },
            loadNextPage: { try await loader.loadNextPage($0) }
        )

        let firstRefresh = Task { await stream.refresh() }
        while await loader.firstPageCallCount == 0 {
            await Task.yield()
        }

        let secondRefresh = Task { await stream.refresh() }
        await loader.succeedFirstPage(items: [.init(id: "item-1", value: "First")])
        await firstRefresh.value
        await secondRefresh.value

        let firstPageCallCount = await loader.firstPageCallCount
        XCTAssertEqual(firstPageCallCount, 1)
    }

    func testCancelledRefreshClearsRefreshingWithoutCommittingResultOrError() async throws {
        let loader = ControllableStreamPageLoader()
        let stream = WebexSnapshotStream<StreamTestItem>(
            id: { $0.id },
            loadFirstPage: { try await loader.loadFirstPage() },
            loadNextPage: { try await loader.loadNextPage($0) }
        )

        var iterator = stream.snapshots.makeAsyncIterator()
        _ = try await nextSnapshot(from: &iterator)

        let refresh = Task { await stream.refresh() }
        let loading = try await nextSnapshot(from: &iterator)
        XCTAssertTrue(loading.isRefreshing)

        refresh.cancel()
        await loader.succeedFirstPage(items: [.init(id: "item-1", value: "Canceled")])
        await refresh.value

        let canceled = try await nextSnapshot(from: &iterator)
        XCTAssertEqual(canceled.items, [])
        XCTAssertEqual(canceled.revision, 0)
        XCTAssertNil(canceled.lastError)
        XCTAssertFalse(canceled.isRefreshing)
    }

    func testCancelledNextPageClearsLoadingWithoutCommittingResultOrError() async throws {
        let firstNextPage = WebexPageLink(url: URL(string: "https://webexapis.com/v1/rooms?cursor=first")!)
        let loader = ControllableStreamPageLoader()
        let stream = WebexSnapshotStream<StreamTestItem>(
            id: { $0.id },
            loadFirstPage: { try await loader.loadFirstPage() },
            loadNextPage: { try await loader.loadNextPage($0) }
        )

        var iterator = stream.snapshots.makeAsyncIterator()
        _ = try await nextSnapshot(from: &iterator)

        let refresh = Task { await stream.refresh() }
        _ = try await nextSnapshot(from: &iterator)
        await loader.succeedFirstPage(
            items: [.init(id: "item-1", value: "First")],
            nextPage: firstNextPage
        )
        await refresh.value
        let loaded = try await nextSnapshot(from: &iterator)

        let nextPage = Task { await stream.loadNextPage() }
        let loadingNext = try await nextSnapshot(from: &iterator)
        XCTAssertTrue(loadingNext.isLoadingNextPage)

        nextPage.cancel()
        await loader.succeedNextPage(items: [.init(id: "item-2", value: "Canceled")])
        await nextPage.value

        let canceled = try await nextSnapshot(from: &iterator)
        XCTAssertEqual(canceled.items, loaded.items)
        XCTAssertEqual(canceled.revision, loaded.revision)
        XCTAssertNil(canceled.lastError)
        XCTAssertFalse(canceled.isLoadingNextPage)
    }

    func testRefreshOnTriggersRefreshesWhenPredicateMatches() async throws {
        let loader = ControllableStreamPageLoader()
        let stream = WebexSnapshotStream<StreamTestItem>(
            id: { $0.id },
            loadFirstPage: { try await loader.loadFirstPage() },
            loadNextPage: { try await loader.loadNextPage($0) }
        )
        var continuation: AsyncStream<WebexStreamTrigger>.Continuation?
        let triggers = AsyncStream<WebexStreamTrigger> { streamContinuation in
            continuation = streamContinuation
        }

        let triggerTask = stream.refreshOnTriggers(triggers) { trigger in
            trigger.resource == "messages" && trigger.roomID == "room-id"
        }
        continuation?.yield(WebexStreamTrigger(
            resource: "messages",
            event: "created",
            resourceID: "message-id",
            roomID: "room-id",
            actorID: "person-id"
        ))

        while await loader.firstPageCallCount == 0 {
            await Task.yield()
        }
        await loader.succeedFirstPage(items: [.init(id: "message-id", value: "Hello")])
        while (await stream.currentSnapshot()).revision == 0 {
            await Task.yield()
        }

        triggerTask.cancel()
        continuation?.finish()
        let firstPageCallCount = await loader.firstPageCallCount
        let snapshot = await stream.currentSnapshot()
        XCTAssertEqual(firstPageCallCount, 1)
        XCTAssertEqual(snapshot.items, [.init(id: "message-id", value: "Hello")])
    }

    func testRefreshOnTriggersIgnoresNonMatchingTriggers() async throws {
        let loader = ControllableStreamPageLoader()
        let stream = WebexSnapshotStream<StreamTestItem>(
            id: { $0.id },
            loadFirstPage: { try await loader.loadFirstPage() },
            loadNextPage: { try await loader.loadNextPage($0) }
        )
        var continuation: AsyncStream<WebexStreamTrigger>.Continuation?
        let triggers = AsyncStream<WebexStreamTrigger> { streamContinuation in
            continuation = streamContinuation
        }

        let triggerTask = stream.refreshOnTriggers(triggers) { trigger in
            trigger.resource == "messages"
        }
        continuation?.yield(WebexStreamTrigger(
            resource: "memberships",
            event: "created",
            resourceID: "membership-id",
            roomID: "room-id",
            actorID: "person-id"
        ))
        await Task.yield()

        triggerTask.cancel()
        continuation?.finish()
        let firstPageCallCount = await loader.firstPageCallCount
        XCTAssertEqual(firstPageCallCount, 0)
    }

    func testSnapshotsDoesNotRetainRapidlyCancelledSubscriptions() async throws {
        let loader = ControllableStreamPageLoader()
        let stream = WebexSnapshotStream<StreamTestItem>(
            id: { $0.id },
            loadFirstPage: { try await loader.loadFirstPage() },
            loadNextPage: { try await loader.loadNextPage($0) }
        )

        for _ in 0..<200 {
            let snapshots = stream.snapshots
            var iterator: AsyncStream<WebexStreamSnapshot<StreamTestItem>>.Iterator? = snapshots.makeAsyncIterator()
            _ = iterator
            iterator = nil
        }

        for _ in 0..<1_000 {
            let subscriberCount = await stream.subscriberCount()
            let tombstoneCount = await stream.subscriptionTombstoneCount()
            if subscriberCount == 0, tombstoneCount == 0 {
                break
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }

        let subscriberCount = await stream.subscriberCount()
        XCTAssertEqual(subscriberCount, 0)
        let tombstoneCount = await stream.subscriptionTombstoneCount()
        XCTAssertEqual(tombstoneCount, 0)
    }
}

private struct StreamTestItem: Equatable, Sendable {
    let id: String
    let value: String
}

private func nextSnapshot<Item: Sendable>(
    from iterator: inout AsyncStream<WebexStreamSnapshot<Item>>.Iterator
) async throws -> WebexStreamSnapshot<Item> {
    let snapshot = await iterator.next()
    return try XCTUnwrap(snapshot)
}

private final class IncrementingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var seconds: TimeInterval = 0

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        seconds += 1
        return Date(timeIntervalSince1970: seconds)
    }
}

private actor ControllableStreamPageLoader {
    private(set) var firstPageCallCount = 0
    private(set) var nextPageCallCount = 0

    private var firstPageContinuations: [CheckedContinuation<WebexStreamPage<StreamTestItem>, Error>] = []
    private var nextPageContinuations: [CheckedContinuation<WebexStreamPage<StreamTestItem>, Error>] = []

    func loadFirstPage() async throws -> WebexStreamPage<StreamTestItem> {
        firstPageCallCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            firstPageContinuations.append(continuation)
        }
    }

    func loadNextPage(_ page: WebexPageLink) async throws -> WebexStreamPage<StreamTestItem> {
        nextPageCallCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            nextPageContinuations.append(continuation)
        }
    }

    func succeedFirstPage(
        items: [StreamTestItem],
        nextPage: WebexPageLink? = nil
    ) {
        firstPageContinuations.removeFirst().resume(returning: WebexStreamPage(
            items: items,
            nextPage: nextPage
        ))
    }

    func succeedNextPage(
        items: [StreamTestItem],
        nextPage: WebexPageLink? = nil
    ) {
        nextPageContinuations.removeFirst().resume(returning: WebexStreamPage(
            items: items,
            nextPage: nextPage
        ))
    }

    func failFirstPage(_ error: WebexSDKError) {
        firstPageContinuations.removeFirst().resume(throwing: error)
    }

    func failNextPage(_ error: WebexSDKError) {
        nextPageContinuations.removeFirst().resume(throwing: error)
    }
}
