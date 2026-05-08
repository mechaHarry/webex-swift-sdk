import XCTest
@testable import WebexSwiftSDK

final class SpacesStreamTests: XCTestCase {
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
        ])
        await refresh.value

        let snapshot = await stream.currentSnapshot()
        XCTAssertEqual(snapshot.items.map(\.id), ["space-2"])
        XCTAssertEqual(snapshot.items.first?.enriched.teamName, "Fresh")
        let teamRequests = await dependencies.teamRequestsValue()
        XCTAssertEqual(teamRequests, ["team-1", "team-1", "team-1"])

        await dependencies.setTeam(WebexTeam(id: "team-1", name: "Fresh Again"))
        let ordinaryRefresh = Task { await stream.refresh() }
        let didStartOrdinaryRefresh = await loader.waitForFirstPageCallCount(3)
        XCTAssertTrue(didStartOrdinaryRefresh)
        guard didStartOrdinaryRefresh else {
            await ordinaryRefresh.value
            return
        }
        await loader.succeedFirstPage(items: [
            WebexSpace(id: "space-3", title: "Cached Space", type: .group, teamID: "team-1")
        ])
        await ordinaryRefresh.value

        let cachedSnapshot = await stream.currentSnapshot()
        XCTAssertEqual(cachedSnapshot.items.map(\.id), ["space-3"])
        XCTAssertEqual(cachedSnapshot.items.first?.enriched.teamName, "Fresh Again")
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

private actor ControllableSpacesPageLoader {
    private(set) var firstPageCallCount = 0
    private var firstPageContinuations: [CheckedContinuation<WebexStreamPage<WebexSpace>, Error>] = []

    func loadFirstPage() async throws -> WebexStreamPage<WebexSpace> {
        firstPageCallCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            firstPageContinuations.append(continuation)
        }
    }

    func loadNextPage(_ nextPage: WebexPageLink) async throws -> WebexStreamPage<WebexSpace> {
        WebexStreamPage(items: [], nextPage: nil)
    }

    func succeedFirstPage(items: [WebexSpace]) {
        firstPageContinuations.removeFirst().resume(returning: WebexStreamPage(
            items: items,
            nextPage: nil
        ))
    }

    func failFirstPage(_ error: Error) {
        firstPageContinuations.removeFirst().resume(throwing: error)
    }

    func firstPageCallCountValue() -> Int {
        firstPageCallCount
    }

    func waitForFirstPageCallCount(_ expectedCount: Int) async -> Bool {
        for _ in 0..<100 {
            if firstPageCallCount >= expectedCount {
                return true
            }
            await Task.yield()
        }
        return firstPageCallCount >= expectedCount
    }
}

private actor PausingSpacesStreamDependencies {
    private var teamByID: [String: WebexTeam] = [:]
    private var teamRequests: [String] = []
    private var pausedTeamIDs: Set<String> = []
    private var pausedTeamContinuations: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var waitersByTeamID: [String: [CheckedContinuation<Void, Never>]] = [:]

    func setTeam(_ team: WebexTeam) {
        teamByID[team.id] = team
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
                await team(teamID)
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

    private func team(_ teamID: String) async -> WebexTeam {
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
