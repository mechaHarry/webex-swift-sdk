import XCTest
import WebexSwiftSDK
@testable import WebexMessagesStreamWindowSmoke

@MainActor
final class MessagesStreamWindowModelTests: XCTestCase {
    func testStartSubscribesToStreamAndPublishesSnapshots() async throws {
        let loader = ControllableMessageStreamLoader()
        let stream = MessagesStream(
            id: { $0.id },
            loadFirstPage: { try await loader.loadFirstPage() },
            loadNextPage: { try await loader.loadNextPage($0) }
        )
        let model = MessagesStreamWindowModel(streamFactory: { stream })

        let startTask = Task { await model.start() }
        while await loader.firstPageCallCount == 0 {
            await Task.yield()
        }

        await loader.succeedFirstPage(items: [
            WebexMessage(id: "message-1", text: "First", personEmail: "one@example.com")
        ])
        await startTask.value
        await waitUntil { model.rows.count == 1 }

        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.rows.map(\.id), ["message-1"])
        XCTAssertEqual(model.rows.map(\.body), ["First"])
        XCTAssertEqual(model.revision, 1)
        XCTAssertFalse(model.isRefreshing)
        XCTAssertTrue(model.canRefresh)
    }

    func testRefreshKeepsCurrentRowsUntilStreamPublishesNewSnapshot() async throws {
        let loader = ControllableMessageStreamLoader()
        let stream = MessagesStream(
            id: { $0.id },
            loadFirstPage: { try await loader.loadFirstPage() },
            loadNextPage: { try await loader.loadNextPage($0) }
        )
        let model = MessagesStreamWindowModel(streamFactory: { stream })

        let startTask = Task { await model.start() }
        while await loader.firstPageCallCount == 0 {
            await Task.yield()
        }
        await loader.succeedFirstPage(items: [
            WebexMessage(id: "message-1", text: "Original", personEmail: "one@example.com")
        ])
        await startTask.value
        await waitUntil { model.rows.map(\.body) == ["Original"] }

        let refreshTask = Task { await model.refresh() }
        while await loader.firstPageCallCount < 2 {
            await Task.yield()
        }
        await waitUntil { model.isRefreshing }

        XCTAssertEqual(model.rows.map(\.body), ["Original"])

        await loader.succeedFirstPage(items: [
            WebexMessage(id: "message-2", text: "New", personEmail: "two@example.com"),
            WebexMessage(id: "message-1", text: "Updated", personEmail: "one@example.com")
        ])
        await refreshTask.value
        await waitUntil { model.rows.map(\.body) == ["New", "Updated"] }

        XCTAssertEqual(model.revision, 2)
        XCTAssertFalse(model.isRefreshing)
    }

    func testStartFailurePublishesSafeError() async {
        let model = MessagesStreamWindowModel(streamFactory: {
            throw WebexSDKError.invalidAuthorizationCallback("http://127.0.0.1:8282/oauth/callback?code=secret")
        })

        await model.start()

        XCTAssertEqual(model.phase, .failed("Invalid authorization callback"))
    }
}

@MainActor
private func waitUntil(
    timeout: TimeInterval = 1,
    predicate: @MainActor @escaping () -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !predicate(), Date() < deadline {
        await Task.yield()
    }
}

private actor ControllableMessageStreamLoader {
    private(set) var firstPageCallCount = 0
    private(set) var nextPageCallCount = 0

    private var firstPageContinuations: [CheckedContinuation<WebexStreamPage<WebexMessage>, Error>] = []
    private var nextPageContinuations: [CheckedContinuation<WebexStreamPage<WebexMessage>, Error>] = []

    func loadFirstPage() async throws -> WebexStreamPage<WebexMessage> {
        firstPageCallCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            firstPageContinuations.append(continuation)
        }
    }

    func loadNextPage(_ page: WebexPageLink) async throws -> WebexStreamPage<WebexMessage> {
        nextPageCallCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            nextPageContinuations.append(continuation)
        }
    }

    func succeedFirstPage(items: [WebexMessage], nextPage: WebexPageLink? = nil) {
        firstPageContinuations.removeFirst().resume(returning: WebexStreamPage(
            items: items,
            nextPage: nextPage
        ))
    }

    func succeedNextPage(items: [WebexMessage], nextPage: WebexPageLink? = nil) {
        nextPageContinuations.removeFirst().resume(returning: WebexStreamPage(
            items: items,
            nextPage: nextPage
        ))
    }
}
