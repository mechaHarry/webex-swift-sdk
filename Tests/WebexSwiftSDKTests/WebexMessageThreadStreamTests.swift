import XCTest
@testable import WebexSwiftSDK

final class WebexMessageThreadStreamTests: XCTestCase {
    func testBuildsArbitraryDepthSnapshotWithPlaceholderParentAndChronologicalOrder() throws {
        let flatSnapshot = WebexStreamSnapshot(
            items: [
                message(id: "reply-2", parentID: "reply-1", created: 30),
                message(id: "parent-1", created: 10),
                message(id: "orphan-grandchild", parentID: "orphan-child", created: 8),
                message(id: "reply-1", parentID: "parent-1", created: 20),
                message(id: "orphan-child", parentID: "deleted-parent", created: 5)
            ],
            revision: 7,
            lastUpdatedAt: date(99),
            isRefreshing: false,
            isLoadingNextPage: true,
            lastError: nil,
            pagination: WebexStreamPagination(
                hasMore: true,
                nextPage: WebexPageLink(url: URL(string: "https://webexapis.com/v1/messages?cursor=next")!),
                pagesLoaded: 2,
                pageLimit: 3,
                capReached: false
            )
        )

        let threaded = WebexMessageThreadSnapshot(flatSnapshot: flatSnapshot)

        XCTAssertEqual(threaded.revision, 7)
        XCTAssertEqual(threaded.lastUpdatedAt, date(99))
        XCTAssertFalse(threaded.isRefreshing)
        XCTAssertTrue(threaded.isLoadingNextPage)
        XCTAssertEqual(threaded.pagination.pagesLoaded, 2)
        XCTAssertEqual(threaded.topLevelMessageIDs, ["deleted-parent", "parent-1"])
        XCTAssertEqual(threaded.chronologicalMessageIDs, [
            "orphan-child",
            "orphan-grandchild",
            "parent-1",
            "reply-1",
            "reply-2"
        ])

        let deletedParent = try XCTUnwrap(threaded.threadEntryByID["deleted-parent"])
        XCTAssertNil(deletedParent.message)
        XCTAssertNil(deletedParent.parentID)
        XCTAssertEqual(deletedParent.childIDs, ["orphan-child"])
        XCTAssertEqual(deletedParent.effectiveCreated, date(5))
        XCTAssertTrue(deletedParent.isPlaceholderParent)

        XCTAssertEqual(threaded.threadEntryByID["orphan-child"]?.parentID, "deleted-parent")
        XCTAssertEqual(threaded.threadEntryByID["orphan-child"]?.childIDs, ["orphan-grandchild"])
        XCTAssertEqual(threaded.threadEntryByID["parent-1"]?.childIDs, ["reply-1"])
        XCTAssertEqual(threaded.threadEntryByID["reply-1"]?.childIDs, ["reply-2"])
        XCTAssertEqual(threaded.threadEntryByID["reply-2"]?.childIDs, [])
    }

    func testBreaksSelfParentsAndCyclesWithoutDroppingEntries() {
        let flatSnapshot = WebexStreamSnapshot(
            items: [
                message(id: "self-parent", parentID: "self-parent", created: 1),
                message(id: "cycle-a", parentID: "cycle-b", created: 2),
                message(id: "cycle-b", parentID: "cycle-a", created: 3)
            ],
            revision: 1,
            lastUpdatedAt: nil,
            isRefreshing: false,
            isLoadingNextPage: false,
            lastError: nil,
            pagination: WebexStreamPagination(
                hasMore: false,
                nextPage: nil,
                pagesLoaded: 1,
                pageLimit: nil,
                capReached: false
            )
        )

        let threaded = WebexMessageThreadSnapshot(flatSnapshot: flatSnapshot)

        XCTAssertEqual(Set(threaded.threadEntryByID.keys), ["self-parent", "cycle-a", "cycle-b"])
        XCTAssertEqual(threaded.threadEntryByID["self-parent"]?.parentID, nil)
        XCTAssertEqual(threaded.threadEntryByID["cycle-a"]?.parentID, "cycle-b")
        XCTAssertEqual(threaded.threadEntryByID["cycle-b"]?.parentID, nil)
        XCTAssertEqual(threaded.threadEntryByID["cycle-b"]?.childIDs, ["cycle-a"])
        XCTAssertEqual(threaded.topLevelMessageIDs, ["self-parent", "cycle-b"])
    }

    func testThreadStreamProjectsFlatSnapshotsAndDelegatesRefresh() async throws {
        let loader = ControllableMessagePageLoader()
        let flatStream = MessagesStream(
            clock: { date(42) },
            id: { $0.id },
            loadFirstPage: { try await loader.loadFirstPage() },
            loadNextPage: { try await loader.loadNextPage($0) }
        )
        let threadedStream = MessagesThreadStream(flatStream: flatStream)

        var iterator = threadedStream.snapshots.makeAsyncIterator()
        let initial = try await nextThreadSnapshot(from: &iterator)
        XCTAssertEqual(initial.topLevelMessageIDs, [])
        XCTAssertEqual(initial.revision, 0)

        let refresh = Task { await threadedStream.refresh() }
        let loading = try await nextThreadSnapshot(from: &iterator)
        XCTAssertTrue(loading.isRefreshing)

        await loader.succeedFirstPage(items: [
            message(id: "parent", created: 1),
            message(id: "child", parentID: "parent", created: 2)
        ])
        await refresh.value

        let loaded = try await nextThreadSnapshot(from: &iterator)
        XCTAssertEqual(loaded.topLevelMessageIDs, ["parent"])
        XCTAssertEqual(loaded.threadEntryByID["parent"]?.childIDs, ["child"])
        XCTAssertEqual(loaded.revision, 1)
        XCTAssertEqual(loaded.lastUpdatedAt, date(42))
        XCTAssertFalse(loaded.isRefreshing)
        let firstPageCallCount = await loader.firstPageCallCountValue()
        XCTAssertEqual(firstPageCallCount, 1)
    }

    func testThreadStreamKeepsKnownDeletedMessageAsEphemeralTombstoneAfterTriggerRefresh() async throws {
        let childID = webexMessageID(uuid: "child")
        let loader = ControllableMessagePageLoader()
        let flatStream = MessagesStream(
            clock: { date(100) },
            id: { $0.id },
            loadFirstPage: { try await loader.loadFirstPage() },
            loadNextPage: { try await loader.loadNextPage($0) }
        )
        let threadedStream = MessagesThreadStream(flatStream: flatStream)
        let triggers = ControllableStreamTriggers()
        let refreshTask = threadedStream.refreshOnTriggers(triggers.stream)
        defer { refreshTask.cancel() }

        var iterator = threadedStream.snapshots.makeAsyncIterator()
        _ = try await nextThreadSnapshot(from: &iterator)

        let initialRefresh = Task { await threadedStream.refresh() }
        _ = try await nextThreadSnapshot(from: &iterator)
        await loader.succeedFirstPage(items: [
            message(id: "parent", created: 10),
            message(id: childID, parentID: "parent", created: 20)
        ])
        await initialRefresh.value
        _ = try await nextThreadSnapshot(from: &iterator)

        triggers.yield(WebexStreamTrigger(
            resource: "messages",
            event: "deleted",
            resourceID: "child",
            roomID: "room-id"
        ))
        while await loader.firstPageCallCountValue() < 2 {
            await Task.yield()
        }
        _ = try await nextThreadSnapshot(from: &iterator)
        await loader.succeedFirstPage(items: [
            message(id: "parent", created: 10)
        ])

        let tombstoneSnapshot = try await nextThreadSnapshot(from: &iterator)
        let parent = try XCTUnwrap(tombstoneSnapshot.threadEntryByID["parent"])
        let deletedChild = try XCTUnwrap(tombstoneSnapshot.threadEntryByID[childID])

        XCTAssertEqual(parent.childIDs, [childID])
        XCTAssertNil(deletedChild.message)
        XCTAssertEqual(deletedChild.parentID, "parent")
        XCTAssertEqual(deletedChild.effectiveCreated, date(20))
        XCTAssertFalse(deletedChild.isPlaceholderParent)
        XCTAssertTrue(deletedChild.isDeletedTombstone)
        XCTAssertEqual(tombstoneSnapshot.chronologicalMessageIDs, ["parent", childID])
    }

    func testThreadStreamDoesNotCreateTombstoneForUnknownDeletedTrigger() async throws {
        let loader = ControllableMessagePageLoader()
        let flatStream = MessagesStream(
            id: { $0.id },
            loadFirstPage: { try await loader.loadFirstPage() },
            loadNextPage: { try await loader.loadNextPage($0) }
        )
        let threadedStream = MessagesThreadStream(flatStream: flatStream)
        let triggers = ControllableStreamTriggers()
        let refreshTask = threadedStream.refreshOnTriggers(triggers.stream)
        defer { refreshTask.cancel() }

        var iterator = threadedStream.snapshots.makeAsyncIterator()
        _ = try await nextThreadSnapshot(from: &iterator)

        let initialRefresh = Task { await threadedStream.refresh() }
        _ = try await nextThreadSnapshot(from: &iterator)
        await loader.succeedFirstPage(items: [
            message(id: "parent", created: 10)
        ])
        await initialRefresh.value
        _ = try await nextThreadSnapshot(from: &iterator)

        triggers.yield(WebexStreamTrigger(
            resource: "messages",
            event: "deleted",
            resourceID: "unknown-message",
            roomID: "room-id"
        ))
        while await loader.firstPageCallCountValue() < 2 {
            await Task.yield()
        }
        _ = try await nextThreadSnapshot(from: &iterator)
        await loader.succeedFirstPage(items: [
            message(id: "parent", created: 10)
        ])

        let refreshed = try await nextThreadSnapshot(from: &iterator)
        XCTAssertEqual(refreshed.topLevelMessageIDs, ["parent"])
        XCTAssertNil(refreshed.threadEntryByID["unknown-message"])
        XCTAssertEqual(refreshed.chronologicalMessageIDs, ["parent"])
    }
}

private func message(
    id: String,
    parentID: String? = nil,
    created seconds: TimeInterval
) -> WebexMessage {
    WebexMessage(
        id: id,
        parentID: parentID,
        roomID: "room-id",
        text: id,
        personEmail: "\(id)@example.com",
        created: date(seconds)
    )
}

private func date(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: seconds)
}

private func webexMessageID(uuid: String) -> String {
    Data("ciscospark://us/MESSAGE/\(uuid)".utf8).base64EncodedString()
}

private func nextThreadSnapshot(
    from iterator: inout AsyncStream<WebexMessageThreadSnapshot>.Iterator
) async throws -> WebexMessageThreadSnapshot {
    let snapshot = await iterator.next()
    return try XCTUnwrap(snapshot)
}

private actor ControllableMessagePageLoader {
    private(set) var firstPageCallCount = 0

    private var firstPageContinuations: [CheckedContinuation<WebexStreamPage<WebexMessage>, Error>] = []

    func loadFirstPage() async throws -> WebexStreamPage<WebexMessage> {
        firstPageCallCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            firstPageContinuations.append(continuation)
        }
    }

    func loadNextPage(_ page: WebexPageLink) async throws -> WebexStreamPage<WebexMessage> {
        WebexStreamPage(items: [], nextPage: nil)
    }

    func succeedFirstPage(items: [WebexMessage]) {
        firstPageContinuations.removeFirst().resume(returning: WebexStreamPage(
            items: items,
            nextPage: nil
        ))
    }

    func firstPageCallCountValue() -> Int {
        firstPageCallCount
    }
}

private final class ControllableStreamTriggers: @unchecked Sendable {
    let stream: AsyncStream<WebexStreamTrigger>

    private let lock = NSLock()
    private var continuation: AsyncStream<WebexStreamTrigger>.Continuation?

    init() {
        var capturedContinuation: AsyncStream<WebexStreamTrigger>.Continuation?
        self.stream = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation
    }

    func yield(_ trigger: WebexStreamTrigger) {
        _ = lock.withLock {
            continuation?.yield(trigger)
        }
    }
}
