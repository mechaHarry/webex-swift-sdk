import Foundation
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
        let model = MessagesStreamWindowModel(runtimeFactory: {
            MessageStreamRuntime(stream: stream)
        })

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
        XCTAssertEqual(model.realtimeStatusText, "Realtime idle")
    }

    func testRefreshKeepsCurrentRowsUntilStreamPublishesNewSnapshot() async throws {
        let loader = ControllableMessageStreamLoader()
        let stream = MessagesStream(
            id: { $0.id },
            loadFirstPage: { try await loader.loadFirstPage() },
            loadNextPage: { try await loader.loadNextPage($0) }
        )
        let model = MessagesStreamWindowModel(runtimeFactory: {
            MessageStreamRuntime(stream: stream)
        })

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
        let model = MessagesStreamWindowModel(runtimeFactory: {
            throw WebexSDKError.invalidAuthorizationCallback("http://127.0.0.1:8282/oauth/callback?code=secret")
        })

        await model.start()

        XCTAssertEqual(model.phase, .failed("Invalid authorization callback"))
    }

    func testRealtimeStateUpdatesStatusText() async throws {
        let loader = ControllableMessageStreamLoader()
        let stream = MessagesStream(
            id: { $0.id },
            loadFirstPage: { try await loader.loadFirstPage() },
            loadNextPage: { try await loader.loadNextPage($0) }
        )
        let states = ControllableRealtimeStates()
        let model = MessagesStreamWindowModel(runtimeFactory: {
            MessageStreamRuntime(
                stream: stream,
                realtimeStates: states.stream
            )
        })

        let startTask = Task { await model.start() }
        while await loader.firstPageCallCount == 0 {
            await Task.yield()
        }
        states.yield(.discovering)
        await waitUntil { model.realtimeStatusText == "Realtime discovering" }

        await loader.succeedFirstPage(items: [])
        await startTask.value
        states.yield(.connected)
        await waitUntil { model.realtimeStatusText == "Realtime connected" }

        XCTAssertEqual(model.realtimeStatusText, "Realtime connected")
    }

    func testRuntimeCancelHandlerRunsOnce() {
        let stream = MessagesStream(
            id: { $0.id },
            loadFirstPage: { WebexStreamPage(items: [], nextPage: nil) },
            loadNextPage: { _ in WebexStreamPage(items: [], nextPage: nil) }
        )
        let cancelCounter = CancelCounter()
        let runtime = MessageStreamRuntime(stream: stream, cancel: {
            cancelCounter.increment()
        })

        runtime.cancel()
        runtime.cancel()

        XCTAssertEqual(cancelCounter.count, 1)
    }
}

final class MessageStreamBootstrapTests: XCTestCase {
    func testShouldRefreshMessagesStreamOnlyForConfiguredRoomMessageChanges() {
        XCTAssertTrue(MessageStreamBootstrap.shouldRefreshMessagesStream(
            for: WebexStreamTrigger(resource: "messages", event: "created", roomID: "room-1"),
            roomID: "room-1"
        ))
        XCTAssertTrue(MessageStreamBootstrap.shouldRefreshMessagesStream(
            for: WebexStreamTrigger(resource: "messages", event: "updated", roomID: "room-1"),
            roomID: "room-1"
        ))
        XCTAssertTrue(MessageStreamBootstrap.shouldRefreshMessagesStream(
            for: WebexStreamTrigger(resource: "messages", event: "deleted", roomID: "room-1"),
            roomID: "room-1"
        ))

        XCTAssertFalse(MessageStreamBootstrap.shouldRefreshMessagesStream(
            for: WebexStreamTrigger(resource: "messages", event: "created", roomID: "room-2"),
            roomID: "room-1"
        ))
        XCTAssertFalse(MessageStreamBootstrap.shouldRefreshMessagesStream(
            for: WebexStreamTrigger(resource: "memberships", event: "created", roomID: "room-1"),
            roomID: "room-1"
        ))
        XCTAssertFalse(MessageStreamBootstrap.shouldRefreshMessagesStream(
            for: WebexStreamTrigger(resource: "messages", event: "seen", roomID: "room-1"),
            roomID: "room-1"
        ))
    }

    func testShouldRefreshMessagesStreamMatchesRealtimeUUIDAgainstEncodedRestRoomID() {
        let roomUUID = "4f0a6580-f43b-11e9-91e4-e7caffe0d0b0"
        let encodedRestRoomID = Data("ciscospark://us/ROOM/\(roomUUID)".utf8).base64EncodedString()

        XCTAssertTrue(MessageStreamBootstrap.shouldRefreshMessagesStream(
            for: WebexStreamTrigger(resource: "messages", event: "created", roomID: roomUUID),
            roomID: encodedRestRoomID
        ))
        XCTAssertFalse(MessageStreamBootstrap.shouldRefreshMessagesStream(
            for: WebexStreamTrigger(resource: "messages", event: "created", roomID: "6e6b9986-0b19-4d7d-8f87-bc14c5ed58ad"),
            roomID: encodedRestRoomID
        ))
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

private final class ControllableRealtimeStates: @unchecked Sendable {
    let stream: AsyncStream<WebexRealtimeConnectionState>

    private let lock = NSLock()
    private var continuation: AsyncStream<WebexRealtimeConnectionState>.Continuation?

    init() {
        var continuation: AsyncStream<WebexRealtimeConnectionState>.Continuation?
        self.stream = AsyncStream { streamContinuation in
            continuation = streamContinuation
        }
        self.continuation = continuation
    }

    func yield(_ state: WebexRealtimeConnectionState) {
        _ = lock.withLock {
            continuation?.yield(state)
        }
    }
}

private final class CancelCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.withLock { value }
    }

    func increment() {
        lock.withLock {
            value += 1
        }
    }
}
