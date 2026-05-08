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

        while true {
            let snapshot = try await nextSnapshot(from: &iterator)
            if snapshot.items.first?.enriched.teamName == "Old" {
                break
            }
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
}

private func nextSnapshot(
    from iterator: inout AsyncStream<WebexStreamSnapshot<WebexSpace>>.Iterator
) async throws -> WebexStreamSnapshot<WebexSpace> {
    let snapshot = await iterator.next()
    return try XCTUnwrap(snapshot)
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

    func firstPageCallCountValue() -> Int {
        firstPageCallCount
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
