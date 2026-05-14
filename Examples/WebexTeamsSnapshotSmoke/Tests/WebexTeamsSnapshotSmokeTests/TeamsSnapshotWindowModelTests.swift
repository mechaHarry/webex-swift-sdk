import Foundation
import XCTest
import WebexSwiftSDK
@testable import WebexTeamsSnapshotSmoke

@MainActor
final class TeamsSnapshotWindowModelTests: XCTestCase {
    func testStartSubscribesRefreshesAndMapsSnapshot() async throws {
        let runtime = RecordingTeamsSnapshotRuntime()
        let model = TeamsSnapshotWindowModel(runtimeFactory: { runtime.runtime })

        await model.start()
        runtime.yield(snapshot(
            items: [
                WebexTeam(
                    id: "team-1",
                    name: "Platform",
                    additionalFields: ["color": .string("blue")]
                )
            ],
            revision: 1,
            lastUpdatedAt: Date(timeIntervalSince1970: 1_768_348_800),
            hasMore: true,
            pageLimit: 2
        ))
        let didPublishRows = await waitUntil { model.rows.count == 1 }

        XCTAssertTrue(didPublishRows)
        XCTAssertEqual(runtime.refreshCount, 1)
        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.rows.map(\.id), ["team-1"])
        XCTAssertEqual(model.selectedTeamID, "team-1")
        XCTAssertEqual(model.selectedDetail?.additionalFields.first?.name, "additionalFields.color")
        XCTAssertEqual(model.revision, 1)
        XCTAssertTrue(model.hasMore)
        XCTAssertFalse(model.capReached)
        XCTAssertNil(model.lastErrorText)
    }

    func testSelectionIsPreservedWhenTeamStillExists() async throws {
        let runtime = RecordingTeamsSnapshotRuntime()
        let model = TeamsSnapshotWindowModel(runtimeFactory: { runtime.runtime })

        await model.start()
        runtime.yield(snapshot(items: [
            WebexTeam(id: "team-1", name: "One"),
            WebexTeam(id: "team-2", name: "Two")
        ], revision: 1))
        let didPublishInitialRows = await waitUntil { model.rows.count == 2 }
        XCTAssertTrue(didPublishInitialRows)

        model.select(teamID: "team-2")
        runtime.yield(snapshot(items: [
            WebexTeam(id: "team-2", name: "Two Updated"),
            WebexTeam(id: "team-3", name: "Three")
        ], revision: 2))
        let didUpdateSelection = await waitUntil { model.selectedDetail?.title == "Two Updated" }
        XCTAssertTrue(didUpdateSelection)

        XCTAssertEqual(model.selectedTeamID, "team-2")
        XCTAssertEqual(model.selectedDetail?.title, "Two Updated")
    }

    func testCommandsForwardToRuntimeAndRespectLoadMoreState() async throws {
        let runtime = RecordingTeamsSnapshotRuntime()
        let model = TeamsSnapshotWindowModel(runtimeFactory: { runtime.runtime })

        await model.start()
        runtime.yield(snapshot(
            items: [WebexTeam(id: "team-1", name: "One")],
            revision: 1,
            hasMore: true,
            capReached: false
        ))
        let didEnablePagination = await waitUntil { model.canLoadMore }
        XCTAssertTrue(didEnablePagination)

        await model.refresh()
        await model.loadNextPage()

        XCTAssertEqual(runtime.refreshCount, 2)
        XCTAssertEqual(runtime.loadNextPageCount, 1)
    }

    func testStartFailureUsesSafeErrorText() async {
        let model = TeamsSnapshotWindowModel(runtimeFactory: {
            throw WebexSDKError.invalidAuthorizationCallback("code=secret")
        })

        await model.start()

        XCTAssertEqual(model.phase, .failed("Invalid authorization callback"))
    }
}

private func snapshot(
    items: [WebexTeam],
    revision: UInt64,
    lastUpdatedAt: Date? = Date(timeIntervalSince1970: 0),
    isRefreshing: Bool = false,
    isLoadingNextPage: Bool = false,
    lastError: WebexSDKError? = nil,
    hasMore: Bool = false,
    pageLimit: Int? = 1,
    capReached: Bool = false
) -> WebexStreamSnapshot<WebexTeam> {
    WebexStreamSnapshot(
        items: items,
        revision: revision,
        lastUpdatedAt: lastUpdatedAt,
        isRefreshing: isRefreshing,
        isLoadingNextPage: isLoadingNextPage,
        lastError: lastError,
        pagination: WebexStreamPagination(
            hasMore: hasMore,
            nextPage: hasMore ? WebexPageLink(url: URL(string: "https://webexapis.com/v1/teams?cursor=next")!) : nil,
            pagesLoaded: capReached ? 2 : 1,
            pageLimit: pageLimit,
            capReached: capReached
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

private final class RecordingTeamsSnapshotRuntime: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<WebexStreamSnapshot<WebexTeam>>.Continuation?
    private(set) var refreshCount = 0
    private(set) var loadNextPageCount = 0

    var runtime: TeamsSnapshotRuntime {
        TeamsSnapshotRuntime(
            snapshots: AsyncStream { continuation in
                lock.withLock {
                    self.continuation = continuation
                }
                continuation.yield(snapshot(items: [], revision: 0))
            },
            currentSnapshot: { snapshot(items: [], revision: 0) },
            refresh: { [self] in lock.withLock { refreshCount += 1 } },
            loadNextPage: { [self] in lock.withLock { loadNextPageCount += 1 } }
        )
    }

    func yield(_ snapshot: WebexStreamSnapshot<WebexTeam>) {
        let _: Void = lock.withLock {
            continuation?.yield(snapshot)
        }
    }
}
