import Foundation
import XCTest
@testable import WebexSwiftSDK

final class WebexRealtimeConnectionTests: XCTestCase {
    func testConnectionEmitsEventsAndTriggers() async throws {
        let source = FakeRealtimeConnectionSource()
        let connection = WebexRealtimeConnection(source: source)
        var stateIterator = connection.states.makeAsyncIterator()
        var eventIterator = connection.events.makeAsyncIterator()
        var triggerIterator = connection.triggers.makeAsyncIterator()

        source.emit(.connected)
        source.emit(messageEvent())

        let state = await stateIterator.next()
        let event = await eventIterator.next()
        let trigger = await triggerIterator.next()

        XCTAssertEqual(state, .connected)
        XCTAssertEqual(event?.resourceID, "message-id")
        XCTAssertEqual(trigger?.roomID, "room-id")
    }

    func testCancelFinishesConnection() async {
        let source = FakeRealtimeConnectionSource()
        let connection = WebexRealtimeConnection(source: source)
        var eventIterator = connection.events.makeAsyncIterator()

        connection.cancel()

        XCTAssertEqual(source.cancelCount(), 1)
        let event = await eventIterator.next()
        XCTAssertNil(event)
    }

    func testWebexClientExposesRealtimeClient() throws {
        let accountID = WebexAccountID()
        let client = WebexClient(
            accountID: accountID,
            configuration: WebexIntegrationConfiguration(
                clientID: "client-id",
                clientSecret: "client-secret",
                redirectURI: URL(string: "myapp://oauth/webex")!,
                scopes: ["openid"]
            ),
            tokenStore: InMemoryWebexStore(),
            httpClient: NoopHTTPClient(),
            initialAccessToken: AccessTokenState(
                value: "access-token",
                expiresAt: Date(timeIntervalSince1970: 1_000),
                tokenType: "Bearer"
            )
        )

        XCTAssertEqual(client.realtime.accountID, accountID)
    }

    func testLiveSourceEmitsStateOrderAndFiltersMembershipSeenByDefault() async throws {
        let device = WebexMercuryDevice(
            id: "device-id",
            name: "webex-swift-sdk",
            webSocketURL: URL(string: "wss://mercury.example.com")!
        )
        let session = FakeMercurySession(frames: [
            """
            {"id":"event-1","resource":"memberships","event":"seen","data":{"id":"membership-id","roomId":"room-id","personId":"person-id"}}
            """,
            """
            {"id":"event-2","resource":"messages","event":"created","data":{"id":"message-id","roomId":"room-id","personId":"person-id"}}
            """
        ])
        let source = WebexRealtimeLiveConnectionSource(
            httpClient: NoopHTTPClient(),
            accessTokenProvider: {
                AccessTokenState(
                    value: "access-token",
                    expiresAt: Date(timeIntervalSince1970: 1_000),
                    tokenType: "Bearer"
                )
            },
            tokenInvalidator: {},
            options: WebexRealtimeOptions(),
            deviceServiceFactory: { _, _, _, _ in
                FakeDeviceService(device: device)
            },
            webSocketFactory: { _ in
                FakeLiveWebSocket()
            },
            sessionFactory: { _, _ in
                session
            }
        )
        var stateIterator = source.states.makeAsyncIterator()
        var eventIterator = source.events.makeAsyncIterator()

        source.start()

        var states: [WebexRealtimeConnectionState] = []
        for _ in 0..<5 {
            if let state = await stateIterator.next() {
                states.append(state)
            }
        }
        let event = await eventIterator.next()
        let nextEvent = await eventIterator.next()

        XCTAssertEqual(states, [.discovering, .registeringDevice, .connecting, .authorizing, .connected])
        XCTAssertEqual(event?.resourceID, "message-id")
        XCTAssertNil(nextEvent)
        XCTAssertEqual(session.acknowledgedMessageIDs(), [])
    }

    func testLiveSourceFilteringHelperExcludesMembershipSeenByDefault() {
        let event = WebexRealtimeEvent(
            resource: "memberships",
            event: "seen",
            knownResource: .memberships,
            knownEvent: .seen,
            decodeStatus: .known,
            resourceID: "membership-id"
        )

        XCTAssertFalse(WebexRealtimeLiveConnectionSource.shouldYield(event, options: WebexRealtimeOptions()))
        XCTAssertTrue(WebexRealtimeLiveConnectionSource.shouldYield(
            event,
            options: WebexRealtimeOptions(includeMembershipSeen: true)
        ))
    }

    private func messageEvent() -> WebexRealtimeEvent {
        WebexRealtimeEvent(
            id: "event-id",
            resource: "messages",
            event: "created",
            knownResource: .messages,
            knownEvent: .created,
            decodeStatus: .known,
            resourceID: "message-id",
            roomID: "room-id",
            actorID: "actor-id"
        )
    }
}

private final class FakeRealtimeConnectionSource: WebexRealtimeConnectionSource, @unchecked Sendable {
    let events: AsyncStream<WebexRealtimeEvent>
    let states: AsyncStream<WebexRealtimeConnectionState>

    private let lock = NSLock()
    private var eventContinuation: AsyncStream<WebexRealtimeEvent>.Continuation?
    private var stateContinuation: AsyncStream<WebexRealtimeConnectionState>.Continuation?
    private var cancels = 0

    init() {
        var eventContinuation: AsyncStream<WebexRealtimeEvent>.Continuation?
        var stateContinuation: AsyncStream<WebexRealtimeConnectionState>.Continuation?
        self.events = AsyncStream { continuation in
            eventContinuation = continuation
        }
        self.states = AsyncStream { continuation in
            stateContinuation = continuation
        }
        self.eventContinuation = eventContinuation
        self.stateContinuation = stateContinuation
    }

    func emit(_ event: WebexRealtimeEvent) {
        lock.withLock {
            _ = eventContinuation?.yield(event)
        }
    }

    func emit(_ state: WebexRealtimeConnectionState) {
        lock.withLock {
            _ = stateContinuation?.yield(state)
        }
    }

    func cancel() {
        let continuations = lock.withLock {
            cancels += 1
            let continuations = (eventContinuation, stateContinuation)
            eventContinuation = nil
            stateContinuation = nil
            return continuations
        }

        continuations.0?.finish()
        continuations.1?.finish()
    }

    func cancelCount() -> Int {
        lock.withLock {
            cancels
        }
    }
}

private struct FakeDeviceService: WebexMercuryDeviceProviding {
    let device: WebexMercuryDevice

    func device(options: WebexRealtimeOptions) async throws -> WebexMercuryDevice {
        device
    }
}

private final class FakeMercurySession: WebexMercurySession, @unchecked Sendable {
    private let lock = NSLock()
    private let framesToEmit: [String]
    private var acknowledged: [String] = []
    private var cancels = 0

    init(frames: [String]) {
        self.framesToEmit = frames
    }

    func frames() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            for frame in framesToEmit {
                continuation.yield(frame)
            }
            continuation.finish()
        }
    }

    func ack(messageID: String) async throws {
        lock.withLock {
            acknowledged.append(messageID)
        }
    }

    func cancel() {
        lock.withLock {
            cancels += 1
        }
    }

    func acknowledgedMessageIDs() -> [String] {
        lock.withLock {
            acknowledged
        }
    }
}

private struct FakeLiveWebSocket: WebexRealtimeWebSocket {
    func connect() async throws {}
    func send(text: String) async throws {}
    func receiveText() async throws -> String {
        throw CancellationError()
    }
    func cancel() {}
}

private struct NoopHTTPClient: HTTPClient {
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        throw WebexSDKError.network("Unexpected request")
    }
}
