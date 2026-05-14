import Foundation
import XCTest
import WebexSwiftSDK
@testable import WebexSpacesEnrichedSnapshotSmoke

@MainActor
final class EnrichedSpacesWindowModelTests: XCTestCase {
    func testStartSubscribesToStreamAndPublishesSnapshotRowsAndDetail() async throws {
        let stream = SpacesStreamTestDriver()
        let model = EnrichedSpacesWindowModel(runtimeFactory: {
            EnrichedSpacesRuntime(
                snapshots: stream.snapshots,
                currentSnapshot: { await stream.currentSnapshot() },
                refresh: { await stream.refresh() },
                refreshEnrichment: { await stream.refreshEnrichment() },
                loadNextPage: { await stream.loadNextPage() }
            )
        })

        await model.start()
        stream.yield(snapshot(items: [
            WebexSpace(
                id: "space-1",
                title: "Incident Review",
                type: .group,
                teamID: "team-1",
                enriched: WebexSpaceEnrichment(teamName: "Platform Team", status: .complete)
            )
        ], revision: 1))
        let didPublishRows = await waitUntil { model.rows.count == 1 }

        XCTAssertTrue(didPublishRows)
        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.rows.map(\.id), ["space-1"])
        XCTAssertEqual(model.rows.first?.enrichmentSummary, "Platform Team")
        XCTAssertEqual(model.selectedSpaceID, "space-1")
        XCTAssertEqual(model.selectedDetail?.title, "Incident Review")
        XCTAssertEqual(model.revision, 1)
        XCTAssertFalse(model.isRefreshing)
        XCTAssertTrue(model.canRefresh)
        XCTAssertFalse(model.canLoadMore)
    }

    func testSelectionIsPreservedWhenSnapshotStillContainsSelectedSpace() async throws {
        let stream = SpacesStreamTestDriver()
        let model = EnrichedSpacesWindowModel(runtimeFactory: {
            EnrichedSpacesRuntime(
                snapshots: stream.snapshots,
                currentSnapshot: { await stream.currentSnapshot() },
                refresh: { await stream.refresh() },
                refreshEnrichment: { await stream.refreshEnrichment() },
                loadNextPage: { await stream.loadNextPage() }
            )
        })

        await model.start()
        stream.yield(snapshot(items: [
            WebexSpace(id: "space-1", title: "One", type: .group),
            WebexSpace(id: "space-2", title: "Two", type: .direct)
        ], revision: 1))
        let didPublishInitialRows = await waitUntil { model.rows.count == 2 }
        XCTAssertTrue(didPublishInitialRows)

        model.select(spaceID: "space-2")
        stream.yield(snapshot(items: [
            WebexSpace(id: "space-2", title: "Two Updated", type: .direct),
            WebexSpace(id: "space-3", title: "Three", type: .group)
        ], revision: 2))
        let didUpdateSelection = await waitUntil { model.selectedDetail?.title == "Two Updated" }
        XCTAssertTrue(didUpdateSelection)

        XCTAssertEqual(model.selectedSpaceID, "space-2")
        XCTAssertEqual(model.selectedDetail?.title, "Two Updated")
    }

    func testCommandsCallRuntimeActions() async {
        let runtime = RecordingEnrichedSpacesRuntime()
        let model = EnrichedSpacesWindowModel(runtimeFactory: { runtime.runtime })

        await model.start()
        await model.refresh()
        await model.refreshEnrichment()
        await model.loadNextPage()

        XCTAssertEqual(runtime.refreshCount, 2)
        XCTAssertEqual(runtime.refreshEnrichmentCount, 1)
        XCTAssertEqual(runtime.loadNextPageCount, 0)

        runtime.yield(snapshot(
            items: [WebexSpace(id: "space-1", title: "One", type: .group)],
            revision: 1,
            hasMore: true
        ))
        let didEnablePagination = await waitUntil { model.canLoadMore }
        XCTAssertTrue(didEnablePagination)

        await model.loadNextPage()

        XCTAssertEqual(runtime.loadNextPageCount, 1)
    }

    func testConcurrentStartsOnlyCreateOneRuntime() async {
        let factory = DelayedRuntimeFactory()
        let model = EnrichedSpacesWindowModel(runtimeFactory: {
            await factory.makeRuntime()
        })

        let firstStart = Task { await model.start() }
        let didStartFactory = await factory.waitForCallCount(1)
        XCTAssertTrue(didStartFactory)

        let secondStart = Task { await model.start() }
        await Task.yield()
        factory.release()
        await firstStart.value
        await secondStart.value

        let callCount = factory.callCountValue()
        XCTAssertEqual(callCount, 1)
    }

    func testStartFailurePublishesSafeError() async {
        let model = EnrichedSpacesWindowModel(runtimeFactory: {
            throw WebexSDKError.invalidAuthorizationCallback("http://127.0.0.1:8282/oauth/callback?code=secret")
        })

        await model.start()

        XCTAssertEqual(model.phase, .failed("Invalid authorization callback"))
    }
}

private func snapshot(
    items: [WebexSpace],
    revision: UInt64,
    isRefreshing: Bool = false,
    isLoadingNextPage: Bool = false,
    lastError: WebexSDKError? = nil,
    hasMore: Bool = false
) -> WebexStreamSnapshot<WebexSpace> {
    WebexStreamSnapshot(
        items: items,
        revision: revision,
        lastUpdatedAt: Date(timeIntervalSince1970: 0),
        isRefreshing: isRefreshing,
        isLoadingNextPage: isLoadingNextPage,
        lastError: lastError,
        pagination: WebexStreamPagination(
            hasMore: hasMore,
            nextPage: hasMore ? WebexPageLink(url: URL(string: "https://webexapis.com/v1/rooms?cursor=next")!) : nil,
            pagesLoaded: 1,
            pageLimit: 1,
            capReached: false
        )
    )
}

@MainActor
private func waitUntil(
    timeout: TimeInterval = 1,
    predicate: @MainActor @escaping () -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !predicate(), Date() < deadline {
        await Task.yield()
    }
    return predicate()
}

private final class SpacesStreamTestDriver: @unchecked Sendable {
    let snapshots: AsyncStream<WebexStreamSnapshot<WebexSpace>>

    private let lock = NSLock()
    private var continuation: AsyncStream<WebexStreamSnapshot<WebexSpace>>.Continuation?
    private var current = snapshot(items: [], revision: 0)
    private(set) var refreshCount = 0
    private(set) var refreshEnrichmentCount = 0
    private(set) var loadNextPageCount = 0

    init() {
        var continuation: AsyncStream<WebexStreamSnapshot<WebexSpace>>.Continuation?
        self.snapshots = AsyncStream { streamContinuation in
            continuation = streamContinuation
            streamContinuation.yield(snapshot(items: [], revision: 0))
        }
        self.continuation = continuation
    }

    func yield(_ snapshot: WebexStreamSnapshot<WebexSpace>) {
        lock.withLock {
            current = snapshot
            continuation?.yield(snapshot)
        }
    }

    func currentSnapshot() async -> WebexStreamSnapshot<WebexSpace> {
        lock.withLock { current }
    }

    func refresh() async {
        lock.withLock {
            refreshCount += 1
        }
    }

    func refreshEnrichment() async {
        lock.withLock {
            refreshEnrichmentCount += 1
        }
    }

    func loadNextPage() async {
        lock.withLock {
            loadNextPageCount += 1
        }
    }
}

private final class RecordingEnrichedSpacesRuntime: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<WebexStreamSnapshot<WebexSpace>>.Continuation?
    private(set) var refreshCount = 0
    private(set) var refreshEnrichmentCount = 0
    private(set) var loadNextPageCount = 0

    var runtime: EnrichedSpacesRuntime {
        EnrichedSpacesRuntime(
            snapshots: AsyncStream { continuation in
                lock.withLock {
                    self.continuation = continuation
                }
                continuation.yield(snapshot(items: [], revision: 0))
            },
            currentSnapshot: { snapshot(items: [], revision: 0) },
            refresh: { [self] in lock.withLock { refreshCount += 1 } },
            refreshEnrichment: { [self] in lock.withLock { refreshEnrichmentCount += 1 } },
            loadNextPage: { [self] in lock.withLock { loadNextPageCount += 1 } }
        )
    }

    func yield(_ snapshot: WebexStreamSnapshot<WebexSpace>) {
        let _: Void = lock.withLock {
            continuation?.yield(snapshot)
        }
    }
}

private final class DelayedRuntimeFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0
    private var isReleased = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var callCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func makeRuntime() async -> EnrichedSpacesRuntime {
        lock.withLock {
            callCount += 1
            let readyWaiters = callCountWaiters.filter { callCount >= $0.0 }
            callCountWaiters.removeAll { callCount >= $0.0 }
            readyWaiters.forEach { $0.1.resume() }
        }

        await withCheckedContinuation { continuation in
            lock.withLock {
                if isReleased {
                    continuation.resume()
                } else {
                    waiters.append(continuation)
                }
            }
        }

        return EnrichedSpacesRuntime(
            snapshots: AsyncStream { $0.yield(snapshot(items: [], revision: 0)) },
            currentSnapshot: { snapshot(items: [], revision: 0) },
            refresh: {},
            refreshEnrichment: {},
            loadNextPage: {}
        )
    }

    func release() {
        let continuations = lock.withLock {
            isReleased = true
            let continuations = waiters
            waiters.removeAll()
            return continuations
        }
        continuations.forEach { $0.resume() }
    }

    func waitForCallCount(_ expectedCount: Int) async -> Bool {
        if lock.withLock({ callCount >= expectedCount }) {
            return true
        }

        await withCheckedContinuation { continuation in
            lock.withLock {
                if callCount >= expectedCount {
                    continuation.resume()
                } else {
                    callCountWaiters.append((expectedCount, continuation))
                }
            }
        }
        return true
    }

    func callCountValue() -> Int {
        lock.withLock { callCount }
    }
}
