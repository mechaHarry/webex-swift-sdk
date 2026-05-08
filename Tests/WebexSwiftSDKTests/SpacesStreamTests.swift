import XCTest
@testable import WebexSwiftSDK

final class SpacesStreamTests: XCTestCase {
    func testCancelledRunningOperationCannotCommitEnrichmentCache() async {
        let gate = SpacesStreamOperationGate()
        let operation = await gate.reserve()

        let didStart = await gate.start(operation)
        operation.cancellation.cancel()

        XCTAssertTrue(didStart)
        let canCommitCache = await gate.canCommitCache(operation)
        XCTAssertFalse(canCommitCache)
    }

    func testRefreshEmitsLoadingThenResolvedEnrichment() async throws {
        let loader = ControllableSpacesPageLoader()
        let dependencies = RecordingSpacesStreamDependencies()
        dependencies.teamByID["team-1"] = WebexTeam(id: "team-1", name: "Platform")
        let stream = SpacesStream(
            baseStream: WebexSnapshotStream<WebexSpace>(
                id: { $0.id },
                loadFirstPage: { try await loader.loadFirstPage() },
                loadNextPage: { try await loader.loadNextPage($0) }
            ),
            enricher: WebexSpaceEnrichmentCoordinator(dependencies: dependencies.makeDependencies())
        )

        var iterator = stream.snapshots.makeAsyncIterator()
        _ = try await nextSnapshot(from: &iterator)

        let refresh = Task { await stream.refresh() }
        _ = try await nextSnapshot(from: &iterator)
        await loader.succeedFirstPage(items: [
            WebexSpace(id: "space-1", title: "General", type: .group, teamID: "team-1")
        ])

        let firstLoadedOrLoading = try await nextSnapshot(from: &iterator)
        let loading: WebexStreamSnapshot<WebexSpace>
        if firstLoadedOrLoading.items.first?.enriched.status == .loading {
            loading = firstLoadedOrLoading
        } else {
            loading = try await nextSnapshot(from: &iterator)
        }
        XCTAssertEqual(loading.items[0].enriched.status, .loading)
        XCTAssertNil(loading.items[0].enriched.teamName)

        await refresh.value
        let enriched = try await nextSnapshot(from: &iterator)
        XCTAssertEqual(enriched.items[0].enriched.teamName, "Platform")
        XCTAssertEqual(enriched.items[0].enriched.status, .complete)
        XCTAssertNil(enriched.lastError)
    }

    func testRefreshEnrichmentDoesNotReloadBaseSpaces() async throws {
        let loader = ControllableSpacesPageLoader()
        let dependencies = RecordingSpacesStreamDependencies()
        dependencies.teamByID["team-1"] = WebexTeam(id: "team-1", name: "Old")
        let stream = SpacesStream(
            baseStream: WebexSnapshotStream<WebexSpace>(
                id: { $0.id },
                loadFirstPage: { try await loader.loadFirstPage() },
                loadNextPage: { try await loader.loadNextPage($0) }
            ),
            enricher: WebexSpaceEnrichmentCoordinator(dependencies: dependencies.makeDependencies())
        )

        var iterator = stream.snapshots.makeAsyncIterator()
        _ = try await nextSnapshot(from: &iterator)

        let refresh = Task { await stream.refresh() }
        _ = try await nextSnapshot(from: &iterator)
        await loader.succeedFirstPage(items: [
            WebexSpace(id: "space-1", title: "General", type: .group, teamID: "team-1")
        ])

        _ = try await nextSnapshot(from: &iterator) { snapshot in
            snapshot.items.first?.enriched.teamName == "Old"
        }
        await refresh.value

        dependencies.teamByID["team-1"] = WebexTeam(id: "team-1", name: "New")
        let enrichmentRefresh = Task { await stream.refreshEnrichment() }

        let loading = try await nextSnapshot(from: &iterator)
        XCTAssertEqual(loading.items[0].enriched.status, .loading)
        await enrichmentRefresh.value
        let refreshed = try await nextSnapshot(from: &iterator)
        XCTAssertEqual(refreshed.items[0].enriched.teamName, "New")
        let firstPageCallCount = await loader.firstPageCallCountValue()
        XCTAssertEqual(firstPageCallCount, 1)
        XCTAssertEqual(dependencies.teamRequests, ["team-1", "team-1"])
    }

    func testFailedRefreshDoesNotCallEnrichmentDependencies() async throws {
        let loader = ControllableSpacesPageLoader()
        let dependencies = RecordingSpacesStreamDependencies()
        let baseStream = WebexSnapshotStream<WebexSpace>(
            id: { $0.id },
            loadFirstPage: { try await loader.loadFirstPage() },
            loadNextPage: { try await loader.loadNextPage($0) }
        )
        await baseStream.replaceItems([
            WebexSpace(id: "space-1", title: "General", type: .group, teamID: "team-1")
        ])
        let stream = SpacesStream(
            baseStream: baseStream,
            enricher: WebexSpaceEnrichmentCoordinator(dependencies: dependencies.makeDependencies())
        )

        let refresh = Task { await stream.refresh() }
        let didStartRefresh = await loader.waitForFirstPageCallCount(1)
        XCTAssertTrue(didStartRefresh)
        await loader.failFirstPage(WebexSDKError.network("rooms unavailable"))
        await refresh.value

        XCTAssertEqual(dependencies.teamRequests, [])
    }

    func testRepeatedRefreshReusesCachedTeamName() async throws {
        let loader = ControllableSpacesPageLoader()
        let dependencies = RecordingSpacesStreamDependencies()
        dependencies.teamByID["team-1"] = WebexTeam(id: "team-1", name: "Old")
        let stream = SpacesStream(
            baseStream: WebexSnapshotStream<WebexSpace>(
                id: { $0.id },
                loadFirstPage: { try await loader.loadFirstPage() },
                loadNextPage: { try await loader.loadNextPage($0) }
            ),
            enricher: WebexSpaceEnrichmentCoordinator(dependencies: dependencies.makeDependencies())
        )

        let firstRefresh = Task { await stream.refresh() }
        let didStartFirstRefresh = await loader.waitForFirstPageCallCount(1)
        XCTAssertTrue(didStartFirstRefresh)
        await loader.succeedFirstPage(items: [
            WebexSpace(id: "space-1", title: "First Space", type: .group, teamID: "team-1")
        ])
        await firstRefresh.value

        dependencies.teamByID["team-1"] = WebexTeam(id: "team-1", name: "New")
        let secondRefresh = Task { await stream.refresh() }
        let didStartSecondRefresh = await loader.waitForFirstPageCallCount(2)
        XCTAssertTrue(didStartSecondRefresh)
        await loader.succeedFirstPage(items: [
            WebexSpace(id: "space-2", title: "Second Space", type: .group, teamID: "team-1")
        ])
        await secondRefresh.value

        let snapshot = await stream.currentSnapshot()
        XCTAssertEqual(snapshot.items.map(\.id), ["space-2"])
        XCTAssertEqual(snapshot.items.first?.enriched.teamName, "Old")
        XCTAssertEqual(dependencies.teamRequests, ["team-1"])
    }

    func testRefreshEnrichmentStartedBeforeBaseRefreshCannotOverwriteInFlightRefresh() async throws {
        let loader = ControllableSpacesPageLoader()
        let dependencies = PausingSpacesStreamDependencies()
        await dependencies.setTeam(WebexTeam(id: "team-1", name: "Old"))
        await dependencies.setTeam(WebexTeam(id: "team-2", name: "New"))
        let stream = SpacesStream(
            baseStream: WebexSnapshotStream<WebexSpace>(
                id: { $0.id },
                loadFirstPage: { try await loader.loadFirstPage() },
                loadNextPage: { try await loader.loadNextPage($0) }
            ),
            enricher: WebexSpaceEnrichmentCoordinator(dependencies: dependencies.makeDependencies())
        )

        var iterator = stream.snapshots.makeAsyncIterator()
        _ = try await nextSnapshot(from: &iterator)

        let initialRefresh = Task { await stream.refresh() }
        _ = try await nextSnapshot(from: &iterator)
        await loader.succeedFirstPage(items: [
            WebexSpace(id: "space-1", title: "Old Space", type: .group, teamID: "team-1")
        ])
        _ = try await nextSnapshot(from: &iterator) { snapshot in
            snapshot.items.first?.enriched.teamName == "Old"
        }
        await initialRefresh.value

        await dependencies.pauseTeam("team-1")
        let staleEnrichment = Task { await stream.refreshEnrichment() }
        _ = try await nextSnapshot(from: &iterator) { snapshot in
            snapshot.items.first?.enriched.status == .loading
        }
        await dependencies.waitForPausedTeamRequest("team-1")

        let baseRefresh = Task { await stream.refresh() }
        await dependencies.resumeTeam("team-1")
        await staleEnrichment.value

        let didStartQueuedRefresh = await loader.waitForFirstPageCallCount(2)
        XCTAssertTrue(didStartQueuedRefresh)
        guard didStartQueuedRefresh else {
            await baseRefresh.value
            return
        }

        await loader.succeedFirstPage(items: [
            WebexSpace(id: "space-2", title: "New Space", type: .group, teamID: "team-2")
        ])
        await baseRefresh.value

        let refreshed = await stream.currentSnapshot()
        XCTAssertEqual(refreshed.items.map(\.id), ["space-2"])
        XCTAssertEqual(refreshed.items.first?.enriched.teamName, "New")
    }

    func testStaleEnrichmentResultDoesNotOverwriteNewerSnapshot() async throws {
        let dependencies = PausingSpacesStreamDependencies()
        await dependencies.setTeam(WebexTeam(id: "team-1", name: "Old"))
        let baseStream = WebexSnapshotStream<WebexSpace>(
            id: { $0.id },
            loadFirstPage: { WebexStreamPage(items: [], nextPage: nil) },
            loadNextPage: { _ in WebexStreamPage(items: [], nextPage: nil) }
        )
        await baseStream.replaceItems([
            WebexSpace(id: "space-1", title: "Old Space", type: .group, teamID: "team-1")
        ])
        let stream = SpacesStream(
            baseStream: baseStream,
            enricher: WebexSpaceEnrichmentCoordinator(dependencies: dependencies.makeDependencies())
        )

        await dependencies.pauseTeam("team-1")
        let staleEnrichment = Task { await stream.refreshEnrichment() }
        await dependencies.waitForPausedTeamRequest("team-1")

        await baseStream.replaceItems([
            WebexSpace(
                id: "space-1",
                title: "Newer Space",
                type: .group,
                teamID: "team-2",
                enriched: WebexSpaceEnrichment(teamName: "Newer", status: .complete)
            )
        ])
        await dependencies.resumeTeam("team-1")
        await staleEnrichment.value

        let snapshot = await stream.currentSnapshot()
        XCTAssertEqual(snapshot.items.map(\.id), ["space-1"])
        XCTAssertEqual(snapshot.items.first?.title, "Newer Space")
        XCTAssertEqual(snapshot.items.first?.enriched.teamName, "Newer")
        XCTAssertEqual(snapshot.items.first?.enriched.status, .complete)
    }

    func testOverlappingRefreshesRunSeriallyAndEnrichFinalRefreshResult() async throws {
        let loader = ControllableSpacesPageLoader()
        let dependencies = RecordingSpacesStreamDependencies()
        dependencies.teamByID["team-1"] = WebexTeam(id: "team-1", name: "First")
        dependencies.teamByID["team-2"] = WebexTeam(id: "team-2", name: "Second")
        let stream = SpacesStream(
            baseStream: WebexSnapshotStream<WebexSpace>(
                id: { $0.id },
                loadFirstPage: { try await loader.loadFirstPage() },
                loadNextPage: { try await loader.loadNextPage($0) }
            ),
            enricher: WebexSpaceEnrichmentCoordinator(dependencies: dependencies.makeDependencies())
        )

        let firstRefresh = Task { await stream.refresh() }
        let didStartFirstRefresh = await loader.waitForFirstPageCallCount(1)
        XCTAssertTrue(didStartFirstRefresh)

        let secondRefresh = Task { await stream.refresh() }
        await loader.succeedFirstPage(items: [
            WebexSpace(id: "space-1", title: "First Space", type: .group, teamID: "team-1")
        ])
        await firstRefresh.value

        let didStartSecondRefresh = await loader.waitForFirstPageCallCount(2)
        XCTAssertTrue(didStartSecondRefresh)
        guard didStartSecondRefresh else {
            await secondRefresh.value
            return
        }
        await loader.succeedFirstPage(items: [
            WebexSpace(id: "space-2", title: "Second Space", type: .group, teamID: "team-2")
        ])
        await secondRefresh.value

        let snapshot = await stream.currentSnapshot()
        XCTAssertEqual(snapshot.items.map(\.id), ["space-2"])
        XCTAssertEqual(snapshot.items.first?.enriched.teamName, "Second")
        let firstPageCallCount = await loader.firstPageCallCountValue()
        XCTAssertEqual(firstPageCallCount, 2)
        XCTAssertEqual(dependencies.teamRequests, ["team-2"])
    }

    func testQueuedRefreshPreventsStaleForceRefreshCachePoisoningFinalSnapshot() async throws {
        let loader = ControllableSpacesPageLoader()
        let dependencies = PausingSpacesStreamDependencies()
        await dependencies.setTeam(WebexTeam(id: "team-1", name: "Old"))
        let stream = SpacesStream(
            baseStream: WebexSnapshotStream<WebexSpace>(
                id: { $0.id },
                loadFirstPage: { try await loader.loadFirstPage() },
                loadNextPage: { try await loader.loadNextPage($0) }
            ),
            enricher: WebexSpaceEnrichmentCoordinator(dependencies: dependencies.makeDependencies())
        )

        let initialRefresh = Task { await stream.refresh() }
        let didStartInitialRefresh = await loader.waitForFirstPageCallCount(1)
        XCTAssertTrue(didStartInitialRefresh)
        await loader.succeedFirstPage(items: [
            WebexSpace(id: "space-1", title: "Old Space", type: .group, teamID: "team-1")
        ])
        await initialRefresh.value

        await dependencies.setTeam(WebexTeam(id: "team-1", name: "Stale"))
        await dependencies.pauseTeam("team-1")
        let staleForceRefresh = Task { await stream.refreshEnrichment() }
        await dependencies.waitForPausedTeamRequest("team-1")

        let refresh = Task { await stream.refresh() }
        await dependencies.setTeam(WebexTeam(id: "team-1", name: "Fresh"))
        await dependencies.resumeTeam("team-1")
        await staleForceRefresh.value

        let didStartQueuedRefresh = await loader.waitForFirstPageCallCount(2)
        XCTAssertTrue(didStartQueuedRefresh)
        guard didStartQueuedRefresh else {
            await refresh.value
            return
        }
        await loader.succeedFirstPage(items: [
            WebexSpace(id: "space-2", title: "Fresh Space", type: .group, teamID: "team-1")
        ], nextPage: WebexPageLink(url: URL(string: "https://webexapis.com/v1/rooms?cursor=next")!))
        await refresh.value

        let snapshot = await stream.currentSnapshot()
        XCTAssertEqual(snapshot.items.map(\.id), ["space-2"])
        XCTAssertEqual(snapshot.items.first?.enriched.teamName, "Old")
        let teamRequests = await dependencies.teamRequestsValue()
        XCTAssertEqual(teamRequests, ["team-1", "team-1"])

        await dependencies.setTeam(WebexTeam(id: "team-1", name: "Fresh Again"))
        let nextPage = Task { await stream.loadNextPage() }
        let didStartNextPage = await loader.waitForNextPageCallCount(1)
        XCTAssertTrue(didStartNextPage)
        guard didStartNextPage else {
            await nextPage.value
            return
        }
        await loader.succeedNextPage(items: [
            WebexSpace(id: "space-3", title: "Cached Space", type: .group, teamID: "team-1")
        ])
        await nextPage.value

        let cachedSnapshot = await stream.currentSnapshot()
        XCTAssertEqual(cachedSnapshot.items.map(\.id), ["space-2", "space-3"])
        XCTAssertEqual(cachedSnapshot.items.map(\.enriched.teamName), ["Old", "Old"])
        let finalTeamRequests = await dependencies.teamRequestsValue()
        XCTAssertEqual(finalTeamRequests, ["team-1", "team-1"])
    }

    func testCancelledQueuedRefreshDoesNotRunBaseLoadOrEnrichment() async throws {
        let loader = ControllableSpacesPageLoader()
        let dependencies = PausingSpacesStreamDependencies()
        await dependencies.setTeam(WebexTeam(id: "team-1", name: "Old"))
        let stream = SpacesStream(
            baseStream: WebexSnapshotStream<WebexSpace>(
                id: { $0.id },
                loadFirstPage: { try await loader.loadFirstPage() },
                loadNextPage: { try await loader.loadNextPage($0) }
            ),
            enricher: WebexSpaceEnrichmentCoordinator(dependencies: dependencies.makeDependencies())
        )

        let initialRefresh = Task { await stream.refresh() }
        let didStartInitialRefresh = await loader.waitForFirstPageCallCount(1)
        XCTAssertTrue(didStartInitialRefresh)
        await loader.succeedFirstPage(items: [
            WebexSpace(id: "space-1", title: "Old Space", type: .group, teamID: "team-1")
        ])
        await initialRefresh.value

        await dependencies.pauseTeam("team-1")
        let pausedEnrichment = Task { await stream.refreshEnrichment() }
        await dependencies.waitForPausedTeamRequest("team-1")

        let queuedRefresh = Task { await stream.refresh() }
        await Task.yield()
        queuedRefresh.cancel()
        await dependencies.resumeTeam("team-1")
        await pausedEnrichment.value

        for _ in 0..<20 {
            await Task.yield()
        }

        let firstPageCallCount = await loader.firstPageCallCountValue()
        XCTAssertEqual(firstPageCallCount, 1)
        let teamRequests = await dependencies.teamRequestsValue()
        XCTAssertEqual(teamRequests, ["team-1", "team-1"])
        let snapshot = await stream.currentSnapshot()
        XCTAssertEqual(snapshot.items.first?.enriched.teamName, "Old")
        queuedRefresh.cancel()
    }

    func testCancelledQueuedRefreshReturnsBeforePreviousOperationCompletes() async throws {
        let loader = ControllableSpacesPageLoader()
        let dependencies = PausingSpacesStreamDependencies()
        await dependencies.setTeam(WebexTeam(id: "team-1", name: "Old"))
        let stream = SpacesStream(
            baseStream: WebexSnapshotStream<WebexSpace>(
                id: { $0.id },
                loadFirstPage: { try await loader.loadFirstPage() },
                loadNextPage: { try await loader.loadNextPage($0) }
            ),
            enricher: WebexSpaceEnrichmentCoordinator(dependencies: dependencies.makeDependencies())
        )

        let initialRefresh = Task { await stream.refresh() }
        let didStartInitialRefresh = await loader.waitForFirstPageCallCount(1)
        XCTAssertTrue(didStartInitialRefresh)
        await loader.succeedFirstPage(items: [
            WebexSpace(id: "space-1", title: "Old Space", type: .group, teamID: "team-1")
        ])
        await initialRefresh.value

        await dependencies.pauseTeam("team-1")
        let pausedEnrichment = Task { await stream.refreshEnrichment() }
        await dependencies.waitForPausedTeamRequest("team-1")

        let queuedRefresh = Task { await stream.refresh() }
        await Task.yield()
        queuedRefresh.cancel()

        let finishedBeforeResume = await taskFinishesWithin(queuedRefresh)
        XCTAssertTrue(finishedBeforeResume)

        await dependencies.resumeTeam("team-1")
        await pausedEnrichment.value
        await queuedRefresh.value
    }

    func testQueuedRefreshFailureDoesNotLeaveActiveEnrichmentLoading() async throws {
        let loader = ControllableSpacesPageLoader()
        let dependencies = PausingSpacesStreamDependencies()
        await dependencies.setTeam(WebexTeam(id: "team-1", name: "Old"))
        let stream = SpacesStream(
            baseStream: WebexSnapshotStream<WebexSpace>(
                id: { $0.id },
                loadFirstPage: { try await loader.loadFirstPage() },
                loadNextPage: { try await loader.loadNextPage($0) }
            ),
            enricher: WebexSpaceEnrichmentCoordinator(dependencies: dependencies.makeDependencies())
        )

        let initialRefresh = Task { await stream.refresh() }
        let didStartInitialRefresh = await loader.waitForFirstPageCallCount(1)
        XCTAssertTrue(didStartInitialRefresh)
        await loader.succeedFirstPage(items: [
            WebexSpace(id: "space-1", title: "Old Space", type: .group, teamID: "team-1")
        ])
        await initialRefresh.value

        await dependencies.setTeam(WebexTeam(id: "team-1", name: "Manual"))
        await dependencies.pauseTeam("team-1")
        let pausedEnrichment = Task { await stream.refreshEnrichment() }
        await dependencies.waitForPausedTeamRequest("team-1")

        let queuedRefresh = Task { await stream.refresh() }
        await dependencies.resumeTeam("team-1")
        await pausedEnrichment.value

        let didStartQueuedRefresh = await loader.waitForFirstPageCallCount(2)
        XCTAssertTrue(didStartQueuedRefresh)
        await loader.failFirstPage(WebexSDKError.network("rooms unavailable"))
        await queuedRefresh.value

        let snapshot = await stream.currentSnapshot()
        XCTAssertEqual(snapshot.lastError, .network("rooms unavailable"))
        XCTAssertEqual(snapshot.items.first?.enriched.status, .complete)
        XCTAssertEqual(snapshot.items.first?.enriched.teamName, "Manual")
        let teamRequests = await dependencies.teamRequestsValue()
        XCTAssertEqual(teamRequests, ["team-1", "team-1"])
    }

    func testCancelledRefreshEnrichmentRestoresPreviousEnrichment() async throws {
        let loader = ControllableSpacesPageLoader()
        let dependencies = PausingSpacesStreamDependencies()
        await dependencies.setTeam(WebexTeam(id: "team-1", name: "Old"))
        let stream = SpacesStream(
            baseStream: WebexSnapshotStream<WebexSpace>(
                id: { $0.id },
                loadFirstPage: { try await loader.loadFirstPage() },
                loadNextPage: { try await loader.loadNextPage($0) }
            ),
            enricher: WebexSpaceEnrichmentCoordinator(dependencies: dependencies.makeDependencies())
        )

        var iterator = stream.snapshots.makeAsyncIterator()
        _ = try await nextSnapshot(from: &iterator)

        let initialRefresh = Task { await stream.refresh() }
        _ = try await nextSnapshot(from: &iterator)
        await loader.succeedFirstPage(items: [
            WebexSpace(id: "space-1", title: "Old Space", type: .group, teamID: "team-1")
        ])
        let oldEnriched = try await nextSnapshot(from: &iterator) { snapshot in
            snapshot.items.first?.enriched.teamName == "Old"
        }
        await initialRefresh.value

        await dependencies.pauseTeam("team-1")
        let enrichmentRefresh = Task { await stream.refreshEnrichment() }
        _ = try await nextSnapshot(from: &iterator) { snapshot in
            snapshot.items.first?.enriched.status == .loading
        }
        await dependencies.waitForPausedTeamRequest("team-1")

        enrichmentRefresh.cancel()
        await dependencies.setTeamError(CancellationError(), for: "team-1")
        await dependencies.resumeTeam("team-1")
        await enrichmentRefresh.value

        let restored = await stream.currentSnapshot()
        XCTAssertEqual(restored.items, oldEnriched.items)
        XCTAssertNil(restored.lastError)
    }

    func testCancelledRefreshEnrichmentDoesNotUpdateEnrichmentCache() async throws {
        let loader = ControllableSpacesPageLoader()
        let dependencies = PausingSpacesStreamDependencies()
        await dependencies.setTeam(WebexTeam(id: "team-1", name: "Old"))
        let stream = SpacesStream(
            baseStream: WebexSnapshotStream<WebexSpace>(
                id: { $0.id },
                loadFirstPage: { try await loader.loadFirstPage() },
                loadNextPage: { try await loader.loadNextPage($0) }
            ),
            enricher: WebexSpaceEnrichmentCoordinator(dependencies: dependencies.makeDependencies())
        )

        let initialRefresh = Task { await stream.refresh() }
        let didStartInitialRefresh = await loader.waitForFirstPageCallCount(1)
        XCTAssertTrue(didStartInitialRefresh)
        await loader.succeedFirstPage(items: [
            WebexSpace(id: "space-1", title: "Old Space", type: .group, teamID: "team-1")
        ])
        await initialRefresh.value

        await dependencies.setTeam(WebexTeam(id: "team-1", name: "Canceled"))
        await dependencies.pauseTeam("team-1")
        let enrichmentRefresh = Task { await stream.refreshEnrichment() }
        await dependencies.waitForPausedTeamRequest("team-1")

        enrichmentRefresh.cancel()
        await dependencies.resumeTeam("team-1")
        await enrichmentRefresh.value

        await dependencies.setTeam(WebexTeam(id: "team-1", name: "Fresh"))
        let ordinaryRefresh = Task { await stream.refresh() }
        let didStartOrdinaryRefresh = await loader.waitForFirstPageCallCount(2)
        XCTAssertTrue(didStartOrdinaryRefresh)
        await loader.succeedFirstPage(items: [
            WebexSpace(id: "space-2", title: "Ordinary Space", type: .group, teamID: "team-1")
        ])
        await ordinaryRefresh.value

        let snapshot = await stream.currentSnapshot()
        XCTAssertEqual(snapshot.items.map(\.id), ["space-2"])
        XCTAssertEqual(snapshot.items.first?.enriched.teamName, "Old")
        let teamRequests = await dependencies.teamRequestsValue()
        XCTAssertEqual(teamRequests, ["team-1", "team-1"])
    }
}

private func nextSnapshot(
    from iterator: inout AsyncStream<WebexStreamSnapshot<WebexSpace>>.Iterator
) async throws -> WebexStreamSnapshot<WebexSpace> {
    let snapshot = await iterator.next()
    return try XCTUnwrap(snapshot)
}

private func nextSnapshot(
    from iterator: inout AsyncStream<WebexStreamSnapshot<WebexSpace>>.Iterator,
    matching predicate: (WebexStreamSnapshot<WebexSpace>) -> Bool
) async throws -> WebexStreamSnapshot<WebexSpace> {
    for _ in 0..<10 {
        let snapshot = try await nextSnapshot(from: &iterator)
        if predicate(snapshot) {
            return snapshot
        }
    }

    XCTFail("Timed out waiting for matching spaces stream snapshot")
    return try await nextSnapshot(from: &iterator)
}

private func taskFinishesWithin(
    _ task: Task<Void, Never>,
    nanoseconds: UInt64 = 50_000_000
) async -> Bool {
    let completion = TaskCompletionFlag()
    Task {
        await task.value
        await completion.complete()
    }
    try? await Task.sleep(nanoseconds: nanoseconds)
    return await completion.isComplete
}

private actor TaskCompletionFlag {
    private var completed = false

    var isComplete: Bool {
        completed
    }

    func complete() {
        completed = true
    }
}

private actor ControllableSpacesPageLoader {
    private(set) var firstPageCallCount = 0
    private(set) var nextPageCallCount = 0
    private var firstPageContinuations: [CheckedContinuation<WebexStreamPage<WebexSpace>, Error>] = []
    private var nextPageContinuations: [CheckedContinuation<WebexStreamPage<WebexSpace>, Error>] = []

    func loadFirstPage() async throws -> WebexStreamPage<WebexSpace> {
        firstPageCallCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            firstPageContinuations.append(continuation)
        }
    }

    func loadNextPage(_ nextPage: WebexPageLink) async throws -> WebexStreamPage<WebexSpace> {
        nextPageCallCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            nextPageContinuations.append(continuation)
        }
    }

    func succeedFirstPage(
        items: [WebexSpace],
        nextPage: WebexPageLink? = nil
    ) {
        firstPageContinuations.removeFirst().resume(returning: WebexStreamPage(
            items: items,
            nextPage: nextPage
        ))
    }

    func succeedNextPage(
        items: [WebexSpace],
        nextPage: WebexPageLink? = nil
    ) {
        nextPageContinuations.removeFirst().resume(returning: WebexStreamPage(
            items: items,
            nextPage: nextPage
        ))
    }

    func failFirstPage(_ error: Error) {
        firstPageContinuations.removeFirst().resume(throwing: error)
    }

    func firstPageCallCountValue() -> Int {
        firstPageCallCount
    }

    func waitForFirstPageCallCount(_ expectedCount: Int) async -> Bool {
        for _ in 0..<1_000 {
            if firstPageCallCount >= expectedCount {
                return true
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return firstPageCallCount >= expectedCount
    }

    func waitForNextPageCallCount(_ expectedCount: Int) async -> Bool {
        for _ in 0..<1_000 {
            if nextPageCallCount >= expectedCount {
                return true
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return nextPageCallCount >= expectedCount
    }
}

private actor PausingSpacesStreamDependencies {
    private var teamByID: [String: WebexTeam] = [:]
    private var teamErrorByID: [String: Error] = [:]
    private var teamRequests: [String] = []
    private var pausedTeamIDs: Set<String> = []
    private var pausedTeamContinuations: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var waitersByTeamID: [String: [CheckedContinuation<Void, Never>]] = [:]

    func setTeam(_ team: WebexTeam) {
        teamByID[team.id] = team
    }

    func setTeamError(_ error: Error, for teamID: String) {
        teamErrorByID[teamID] = error
    }

    func teamRequestsValue() -> [String] {
        teamRequests
    }

    func pauseTeam(_ teamID: String) {
        pausedTeamIDs.insert(teamID)
    }

    func resumeTeam(_ teamID: String) {
        pausedTeamIDs.remove(teamID)
        let continuations = pausedTeamContinuations.removeValue(forKey: teamID) ?? []
        for continuation in continuations {
            continuation.resume()
        }
    }

    func waitForPausedTeamRequest(_ teamID: String) async {
        if pausedTeamContinuations[teamID]?.isEmpty == false {
            return
        }

        await withCheckedContinuation { continuation in
            waitersByTeamID[teamID, default: []].append(continuation)
        }
    }

    nonisolated func makeDependencies() -> WebexSpaceEnrichmentCoordinator.Dependencies {
        WebexSpaceEnrichmentCoordinator.Dependencies(
            getTeam: { [self] teamID in
                try await team(teamID)
            },
            getSelf: {
                WebexPerson(id: "self", emails: ["self@example.com"])
            },
            listMemberships: { _ in [] },
            getPerson: { personID in
                WebexPerson(id: personID, emails: ["\(personID)@example.com"])
            }
        )
    }

    private func team(_ teamID: String) async throws -> WebexTeam {
        teamRequests.append(teamID)
        let team = teamByID[teamID] ?? WebexTeam(id: teamID)
        if pausedTeamIDs.contains(teamID) {
            await withCheckedContinuation { continuation in
                pausedTeamContinuations[teamID, default: []].append(continuation)
                let waiters = waitersByTeamID.removeValue(forKey: teamID) ?? []
                for waiter in waiters {
                    waiter.resume()
                }
            }
        }

        if let error = teamErrorByID[teamID] {
            throw error
        }
        return team
    }
}

private final class RecordingSpacesStreamDependencies: @unchecked Sendable {
    var teamByID: [String: WebexTeam] = [:]
    private(set) var teamRequests: [String] = []

    func makeDependencies() -> WebexSpaceEnrichmentCoordinator.Dependencies {
        WebexSpaceEnrichmentCoordinator.Dependencies(
            getTeam: { [self] teamID in
                teamRequests.append(teamID)
                return teamByID[teamID] ?? WebexTeam(id: teamID)
            },
            getSelf: {
                WebexPerson(id: "self", emails: ["self@example.com"])
            },
            listMemberships: { _ in [] },
            getPerson: { personID in
                WebexPerson(id: personID, emails: ["\(personID)@example.com"])
            }
        )
    }
}
