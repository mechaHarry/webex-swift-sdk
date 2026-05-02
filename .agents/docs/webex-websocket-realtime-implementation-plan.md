# Webex WebSocket Realtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build native Swift receive-only Webex WebSocket realtime support that emits rich events and Snapshot Stream refresh triggers.

**Architecture:** Add a `Realtime` slice beside REST API clients. The slice discovers WDM through U2C, reuses an in-memory SDK-owned device while valid, directly registers a new WDM device when needed, connects with `URLSessionWebSocketTask`, decodes incoming frames into `WebexRealtimeEvent`, and maps them into `WebexStreamTrigger`. REST remains the canonical write/detail path.

**Tech Stack:** Swift 5.9, Foundation `URLSession`, `URLSessionWebSocketTask`, `AsyncStream`, XCTest, existing `HTTPClient`, `RetryPolicy`, `TokenManager`, `WebexJSONValue`, and Snapshot Streams.

---

## File Structure

Create:

- `Sources/WebexSwiftSDK/Realtime/WebexRealtimeModels.swift`
  - Public realtime options, resources, events, decode status, connection state, and event value.
- `Sources/WebexSwiftSDK/Realtime/WebexMercuryDeviceService.swift`
  - Internal U2C/WDM discovery, in-memory device reuse, direct device creation, and stale-device invalidation.
- `Sources/WebexSwiftSDK/Realtime/WebexRealtimeWebSocketTransport.swift`
  - Internal mockable WebSocket transport protocol and Foundation adapter.
- `Sources/WebexSwiftSDK/Realtime/WebexMercuryWebSocketSession.swift`
  - Internal session loop, auth frame, receive loop, ack frame, cancellation.
- `Sources/WebexSwiftSDK/Realtime/WebexRealtimeEventDecoder.swift`
  - Internal decoder for JS SDK-like event payloads and raw Mercury envelopes.
- `Sources/WebexSwiftSDK/Realtime/WebexRealtimeTriggerAdapter.swift`
  - Event-to-`WebexStreamTrigger` mapping.
- `Sources/WebexSwiftSDK/Realtime/WebexRealtimeConnection.swift`
  - Public cancellable connection with `events`, `triggers`, and `states`.
- `Sources/WebexSwiftSDK/Realtime/WebexRealtimeClient.swift`
  - Public client entry point exposed from `WebexClient.realtime`.
- `Tests/WebexSwiftSDKTests/WebexRealtimeModelTests.swift`
- `Tests/WebexSwiftSDKTests/WebexMercuryDeviceServiceTests.swift`
- `Tests/WebexSwiftSDKTests/WebexMercuryWebSocketSessionTests.swift`
- `Tests/WebexSwiftSDKTests/WebexRealtimeEventDecoderTests.swift`
- `Tests/WebexSwiftSDKTests/WebexRealtimeConnectionTests.swift`
- `Examples/WebexRealtimeEventsSmoke/Package.swift`
- `Examples/WebexRealtimeEventsSmoke/README.md`
- `Examples/WebexRealtimeEventsSmoke/Sources/WebexRealtimeEventsSmoke/main.swift`
- `Examples/WebexRealtimeEventsSmoke/Tests/WebexRealtimeEventsSmokeTests/RealtimeSmokeOptionsTests.swift`

Modify:

- `Sources/WebexSwiftSDK/WebexClient.swift`
  - Add `public let realtime: WebexRealtimeClient`.
- `.agents/docs/webex-realtime-triggers.md`
  - Mark WebSocket realtime as implemented experimentally after code lands.
- `.agents/docs/webex-sdk-streams-roadmap.md`
  - Move websocket transport from next-step to experimental realtime foundation after code lands.

Subagent-friendly split:

- Worker 1 can own Task 1 models.
- Worker 2 can own Task 2 device service.
- Worker 3 can own Task 3 WebSocket transport/session.
- Worker 4 can own Task 4 decoder/trigger mapping.
- Main agent should integrate Tasks 5-8 to avoid API drift.

## Task 1: Realtime Models

**Files:**
- Create: `Sources/WebexSwiftSDK/Realtime/WebexRealtimeModels.swift`
- Create: `Tests/WebexSwiftSDKTests/WebexRealtimeModelTests.swift`

- [ ] **Step 1: Write failing model tests**

Add:

```swift
import XCTest
@testable import WebexSwiftSDK

final class WebexRealtimeModelTests: XCTestCase {
    func testResourceAndEventPreserveUnknownRawValues() {
        XCTAssertEqual(WebexRealtimeResource.messages.rawValue, "messages")
        XCTAssertEqual(WebexRealtimeResource.spaces.rawValue, "rooms")
        XCTAssertEqual(WebexRealtimeResource.rooms.rawValue, "rooms")
        XCTAssertEqual(WebexRealtimeResource.unknown("future").rawValue, "future")

        XCTAssertEqual(WebexRealtimeEventName.created.rawValue, "created")
        XCTAssertEqual(WebexRealtimeEventName.seen.rawValue, "seen")
        XCTAssertEqual(WebexRealtimeEventName.unknown("renamed").rawValue, "renamed")
    }

    func testRealtimeEventBuildsStreamTrigger() {
        let event = WebexRealtimeEvent(
            id: "event-id",
            resource: "messages",
            event: "created",
            knownResource: .messages,
            knownEvent: .created,
            decodeStatus: .known,
            resourceID: "message-id",
            roomID: "room-id",
            actorID: "actor-id",
            ackID: "message-id",
            payload: ["id": .string("message-id")]
        )

        let trigger = event.streamTrigger()

        XCTAssertEqual(trigger.resource, "messages")
        XCTAssertEqual(trigger.event, "created")
        XCTAssertEqual(trigger.resourceID, "message-id")
        XCTAssertEqual(trigger.roomID, "room-id")
        XCTAssertEqual(trigger.actorID, "actor-id")
    }

    func testDefaultOptionsExcludeSeenEvents() {
        let options = WebexRealtimeOptions(resources: [.messages, .memberships])

        XCTAssertEqual(options.resources, [.messages, .memberships])
        XCTAssertFalse(options.includeMembershipSeen)
        XCTAssertEqual(options.retryPolicy.maximumDelay, 240)
    }
}
```

- [ ] **Step 2: Run model tests and verify failure**

Run:

```bash
swift test --filter WebexRealtimeModelTests
```

Expected: compile failure for missing realtime types.

- [ ] **Step 3: Add realtime model implementation**

Create `Sources/WebexSwiftSDK/Realtime/WebexRealtimeModels.swift`:

```swift
import Foundation

public enum WebexRealtimeResource: Hashable, Sendable {
    case messages
    case spaces
    case rooms
    case memberships
    case attachmentActions
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .messages: return "messages"
        case .spaces, .rooms: return "rooms"
        case .memberships: return "memberships"
        case .attachmentActions: return "attachmentActions"
        case .unknown(let value): return value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "messages": self = .messages
        case "spaces": self = .spaces
        case "rooms": self = .rooms
        case "memberships": self = .memberships
        case "attachmentActions": self = .attachmentActions
        default: self = .unknown(rawValue)
        }
    }
}

public enum WebexRealtimeEventName: Hashable, Sendable {
    case created
    case updated
    case deleted
    case seen
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .created: return "created"
        case .updated: return "updated"
        case .deleted: return "deleted"
        case .seen: return "seen"
        case .unknown(let value): return value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "created": self = .created
        case "updated": self = .updated
        case "deleted": self = .deleted
        case "seen": self = .seen
        default: self = .unknown(rawValue)
        }
    }
}

public enum WebexRealtimeDecodeStatus: Equatable, Sendable {
    case known
    case unknownEvent
    case unknownPayload
}

public enum WebexRealtimeConnectionState: Equatable, Sendable {
    case disconnected
    case discovering
    case registeringDevice
    case connecting
    case authorizing
    case connected
    case reconnecting(attempt: Int, delay: TimeInterval)
    case failed(WebexSDKError)
}

public struct WebexRealtimeOptions: Sendable {
    public let resources: [WebexRealtimeResource]
    public let events: [WebexRealtimeEventName]
    public let includeMembershipSeen: Bool
    public let retryPolicy: RetryPolicy
    public let deviceName: String

    public init(
        resources: [WebexRealtimeResource] = [.messages, .spaces, .memberships, .attachmentActions],
        events: [WebexRealtimeEventName] = [],
        includeMembershipSeen: Bool = false,
        retryPolicy: RetryPolicy = RetryPolicy(maxAttempts: 5, baseDelay: 1, jitter: 0.25, maximumDelay: 240),
        deviceName: String = "webex-swift-sdk"
    ) {
        self.resources = resources
        self.events = events
        self.includeMembershipSeen = includeMembershipSeen
        self.retryPolicy = retryPolicy
        self.deviceName = deviceName
    }
}

public struct WebexRealtimeEvent: Equatable, Sendable {
    public let id: String?
    public let resource: String
    public let event: String
    public let knownResource: WebexRealtimeResource
    public let knownEvent: WebexRealtimeEventName
    public let decodeStatus: WebexRealtimeDecodeStatus
    public let resourceID: String?
    public let roomID: String?
    public let actorID: String?
    public let ackID: String?
    public let payload: [String: WebexJSONValue]

    public init(
        id: String? = nil,
        resource: String,
        event: String,
        knownResource: WebexRealtimeResource? = nil,
        knownEvent: WebexRealtimeEventName? = nil,
        decodeStatus: WebexRealtimeDecodeStatus,
        resourceID: String? = nil,
        roomID: String? = nil,
        actorID: String? = nil,
        ackID: String? = nil,
        payload: [String: WebexJSONValue] = [:]
    ) {
        self.id = id
        self.resource = resource
        self.event = event
        self.knownResource = knownResource ?? WebexRealtimeResource(rawValue: resource)
        self.knownEvent = knownEvent ?? WebexRealtimeEventName(rawValue: event)
        self.decodeStatus = decodeStatus
        self.resourceID = resourceID
        self.roomID = roomID
        self.actorID = actorID
        self.ackID = ackID
        self.payload = payload
    }

    public func streamTrigger() -> WebexStreamTrigger {
        WebexStreamTrigger(
            resource: resource,
            event: event,
            resourceID: resourceID,
            roomID: roomID,
            actorID: actorID
        )
    }
}
```

- [ ] **Step 4: Run model tests and full tests**

Run:

```bash
swift test --filter WebexRealtimeModelTests
swift test
```

Expected: model tests pass; full suite still passes.

- [ ] **Step 5: Commit Task 1**

```bash
git add Sources/WebexSwiftSDK/Realtime/WebexRealtimeModels.swift Tests/WebexSwiftSDKTests/WebexRealtimeModelTests.swift
git commit -S -m "feat: add Webex realtime models"
```

## Task 2: U2C/WDM Device Service

**Files:**
- Create: `Sources/WebexSwiftSDK/Realtime/WebexMercuryDeviceService.swift`
- Create: `Tests/WebexSwiftSDKTests/WebexMercuryDeviceServiceTests.swift`

- [ ] **Step 1: Write failing device service tests**

Add tests:

```swift
import XCTest
@testable import WebexSwiftSDK

final class WebexMercuryDeviceServiceTests: XCTestCase {
    func testDiscoversWDMAndReusesMatchingDevice() async throws {
        let httpClient = MockRealtimeHTTPClient()
        await httpClient.enqueue(statusCode: 200, body: #"{"serviceLinks":{"wdm":"https://wdm.example.com/wdm/api/v1"}}"#)
        await httpClient.enqueue(statusCode: 200, body: #"{"devices":[{"id":"device-1","name":"webex-swift-sdk","webSocketUrl":"wss://mercury.example.com/ws"}]}"#)
        let service = makeService(httpClient: httpClient)

        let device = try await service.device(options: WebexRealtimeOptions(deviceName: "webex-swift-sdk"))

        XCTAssertEqual(device.id, "device-1")
        XCTAssertEqual(device.webSocketURL.absoluteString, "wss://mercury.example.com/ws")
        let requests = await httpClient.requests()
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, [
            "https://u2c.wbx2.com/u2c/api/v1/catalog?format=hostmap",
            "https://wdm.example.com/wdm/api/v1/devices"
        ])
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer realtime-token")
    }

    func testCreatesDeviceWhenNoMatchingDeviceExists() async throws {
        let httpClient = MockRealtimeHTTPClient()
        await httpClient.enqueue(statusCode: 200, body: #"{"serviceLinks":{"wdm":"https://wdm.example.com/wdm/api/v1"}}"#)
        await httpClient.enqueue(statusCode: 200, body: #"{"devices":[]}"#)
        await httpClient.enqueue(statusCode: 200, body: #"{"id":"device-2","name":"webex-swift-sdk","webSocketUrl":"wss://mercury.example.com/ws2"}"#)
        let service = makeService(httpClient: httpClient)

        let device = try await service.device(options: WebexRealtimeOptions(deviceName: "webex-swift-sdk"))

        XCTAssertEqual(device.id, "device-2")
        let requests = await httpClient.requests()
        XCTAssertEqual(requests[2].httpMethod, "POST")
        let body = try XCTUnwrap(requests[2].httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["deviceType"] as? String, "DESKTOP")
        XCTAssertEqual(json["model"] as? String, "webex-swift-sdk")
        XCTAssertEqual(json["name"] as? String, "webex-swift-sdk")
    }

    func testRejectsNonWSSWebSocketURL() async throws {
        let httpClient = MockRealtimeHTTPClient()
        await httpClient.enqueue(statusCode: 200, body: #"{"serviceLinks":{"wdm":"https://wdm.example.com/wdm/api/v1"}}"#)
        await httpClient.enqueue(statusCode: 200, body: #"{"devices":[{"id":"device-1","name":"webex-swift-sdk","webSocketUrl":"ws://unsafe.example.com/ws"}]}"#)
        let service = makeService(httpClient: httpClient)

        do {
            _ = try await service.device(options: WebexRealtimeOptions())
            XCTFail("Expected non-wss URL failure")
        } catch let error as WebexSDKError {
            XCTAssertTrue(String(describing: error).contains("Invalid Webex realtime WebSocket URL"))
            XCTAssertFalse(String(describing: error).contains("ws://unsafe.example.com/ws"))
        }
    }
}
```

Add local test helpers in the same file:

```swift
private func makeService(httpClient: MockRealtimeHTTPClient) -> WebexMercuryDeviceService {
    WebexMercuryDeviceService(
        httpClient: httpClient,
        accessTokenProvider: {
            AccessTokenState(value: "realtime-token", expiresAt: .distantFuture, tokenType: "Bearer")
        },
        retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, jitter: 0),
        sleeper: { _ in }
    )
}

private actor MockRealtimeHTTPClient: HTTPClient {
    private var responses: [HTTPResponse] = []
    private var recorded: [URLRequest] = []

    func enqueue(statusCode: Int, headers: [String: String] = [:], body: String) {
        responses.append(HTTPResponse(
            data: Data(body.utf8),
            response: HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: headers
            )!
        ))
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        recorded.append(request)
        guard !responses.isEmpty else {
            throw WebexSDKError.network("No queued response")
        }
        return responses.removeFirst()
    }

    func requests() -> [URLRequest] {
        recorded
    }
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
swift test --filter WebexMercuryDeviceServiceTests
```

Expected: compile failure for missing `WebexMercuryDeviceService`.

- [ ] **Step 3: Implement device service**

Create `Sources/WebexSwiftSDK/Realtime/WebexMercuryDeviceService.swift` with:

```swift
import Foundation

internal struct WebexMercuryDevice: Equatable, Sendable {
    let id: String
    let name: String
    let webSocketURL: URL
}

internal actor WebexMercuryDeviceCache {
    private var device: WebexMercuryDevice?

    func load() -> WebexMercuryDevice? { device }
    func save(_ device: WebexMercuryDevice) { self.device = device }
    func invalidate() { device = nil }
}

internal struct WebexMercuryDeviceService: Sendable {
    private let u2cURL: URL
    private let httpClient: HTTPClient
    private let accessTokenProvider: @Sendable () async throws -> AccessTokenState
    private let retryPolicy: RetryPolicy
    private let sleeper: @Sendable (TimeInterval) async throws -> Void
    private let cache: WebexMercuryDeviceCache

    init(
        u2cURL: URL = URL(string: "https://u2c.wbx2.com/u2c/api/v1/catalog")!,
        httpClient: HTTPClient,
        accessTokenProvider: @escaping @Sendable () async throws -> AccessTokenState,
        retryPolicy: RetryPolicy,
        sleeper: @escaping @Sendable (TimeInterval) async throws -> Void,
        cache: WebexMercuryDeviceCache = WebexMercuryDeviceCache()
    ) {
        self.u2cURL = u2cURL
        self.httpClient = httpClient
        self.accessTokenProvider = accessTokenProvider
        self.retryPolicy = retryPolicy
        self.sleeper = sleeper
        self.cache = cache
    }

    func device(options: WebexRealtimeOptions) async throws -> WebexMercuryDevice {
        if let cached = await cache.load(), cached.name == options.deviceName {
            return cached
        }

        let wdmURL = try await discoverWDMURL()
        let created = try await createDevice(wdmURL: wdmURL, options: options)
        await cache.save(created)
        return created
    }

    func invalidateCachedDevice() async {
        await cache.invalidate()
    }
}
```

Implement the private helpers in the same file:

- `discoverWDMURL()` fetches `limited/catalog?mode=DEFAULT_BY_PROXIMITY&format=hostmap` without authorization first.
- Use the limited catalog's `u2c` service URL for the authorized postauth `catalog?format=hostmap` request.
- Prefer postauth `wdm` when available; fall back to limited `wdm` when postauth catalog returns 401/403.
- Avoid `GET <wdm>/devices` in the default path; OAuth integration tokens may be allowed to register devices without being allowed to list all devices.
- In-memory cache reuse is scoped to the live `WebexClient`.
- `createDevice(wdmURL:options:)` sends `POST <wdm>/devices` with JSON fields `deviceName`, `deviceType`, `localizedModel`, `model`, `name`, `systemName`, `systemVersion`.
- `sendWithRetry(_:)` uses `retryPolicy`, retries transient network errors, 429, and 5xx, and respects `Retry-After`.
- `authorizedRequest(url:method:body:)` injects `Authorization: Bearer <token>`, `Accept: application/json`, and JSON content type for bodies.
- `decodeDevice(_:)` rejects missing or non-`wss://` `webSocketUrl` with `WebexSDKError.network("Invalid Webex realtime WebSocket URL")`.
- All thrown messages use `Redactor.redactSecrets`.

- [ ] **Step 4: Run device service tests and full tests**

Run:

```bash
swift test --filter WebexMercuryDeviceServiceTests
swift test
```

Expected: tests pass.

- [ ] **Step 5: Commit Task 2**

```bash
git add Sources/WebexSwiftSDK/Realtime/WebexMercuryDeviceService.swift Tests/WebexSwiftSDKTests/WebexMercuryDeviceServiceTests.swift
git commit -S -m "feat: add Webex realtime device service"
```

## Task 3: WebSocket Transport And Mercury Session

**Files:**
- Create: `Sources/WebexSwiftSDK/Realtime/WebexRealtimeWebSocketTransport.swift`
- Create: `Sources/WebexSwiftSDK/Realtime/WebexMercuryWebSocketSession.swift`
- Create: `Tests/WebexSwiftSDKTests/WebexMercuryWebSocketSessionTests.swift`

- [ ] **Step 1: Write failing WebSocket session tests**

Add:

```swift
import XCTest
@testable import WebexSwiftSDK

final class WebexMercuryWebSocketSessionTests: XCTestCase {
    func testSendsAuthorizationFrameAfterConnect() async throws {
        let socket = FakeWebSocket()
        socket.queueReceive(#"{"id":"frame-1","data":{"resource":"messages","event":"created","id":"message-id"}}"#)
        socket.queueReceiveFailure(CancellationError())
        let session = WebexMercuryWebSocketSession(
            webSocket: socket,
            accessTokenProvider: { AccessTokenState(value: "access-token", expiresAt: .distantFuture, tokenType: "Bearer") }
        )

        let stream = session.frames()
        var iterator = stream.makeAsyncIterator()
        _ = try await iterator.next()
        session.cancel()

        let sent = socket.sentTexts()
        XCTAssertEqual(sent.count, 1)
        XCTAssertTrue(sent[0].contains(#""type":"authorization""#))
        XCTAssertTrue(sent[0].contains(#""token":"Bearer access-token""#))
    }

    func testAckFrameUsesMessageID() async throws {
        let socket = FakeWebSocket()
        let session = WebexMercuryWebSocketSession(
            webSocket: socket,
            accessTokenProvider: { AccessTokenState(value: "access-token", expiresAt: .distantFuture, tokenType: "Bearer") }
        )

        try await session.ack(messageID: "message-id")

        XCTAssertEqual(socket.sentTexts(), [#"{"messageId":"message-id","type":"ack"}"#])
    }

    func testCancelClosesSocket() async {
        let socket = FakeWebSocket()
        let session = WebexMercuryWebSocketSession(
            webSocket: socket,
            accessTokenProvider: { AccessTokenState(value: "access-token", expiresAt: .distantFuture, tokenType: "Bearer") }
        )

        session.cancel()

        XCTAssertEqual(socket.cancelCallCount(), 1)
    }
}
```

Add a fake socket in the same test file:

```swift
private final class FakeWebSocket: WebexRealtimeWebSocket, @unchecked Sendable {
    private let lock = NSLock()
    private var receives: [Result<String, Error>] = []
    private var sent: [String] = []
    private var cancels = 0

    func connect() async throws {}

    func send(text: String) async throws {
        locked { sent.append(text) }
    }

    func receiveText() async throws -> String {
        try locked {
            guard !receives.isEmpty else {
                throw CancellationError()
            }
            return try receives.removeFirst().get()
        }
    }

    func cancel() {
        locked { cancels += 1 }
    }

    func queueReceive(_ text: String) {
        locked { receives.append(.success(text)) }
    }

    func queueReceiveFailure(_ error: Error) {
        locked { receives.append(.failure(error)) }
    }

    func sentTexts() -> [String] { locked { sent } }
    func cancelCallCount() -> Int { locked { cancels } }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
swift test --filter WebexMercuryWebSocketSessionTests
```

Expected: compile failure for missing WebSocket protocol/session.

- [ ] **Step 3: Implement mockable WebSocket transport**

Create `Sources/WebexSwiftSDK/Realtime/WebexRealtimeWebSocketTransport.swift`:

```swift
import Foundation

internal protocol WebexRealtimeWebSocket: Sendable {
    func connect() async throws
    func send(text: String) async throws
    func receiveText() async throws -> String
    func cancel()
}

internal struct URLSessionWebSocketTransport: WebexRealtimeWebSocket {
    private let task: URLSessionWebSocketTask

    init(url: URL, session: URLSession = .shared) {
        self.task = session.webSocketTask(with: url)
    }

    func connect() async throws {
        task.resume()
    }

    func send(text: String) async throws {
        try await task.send(.string(text))
    }

    func receiveText() async throws -> String {
        let message = try await task.receive()
        switch message {
        case .string(let text):
            return text
        case .data:
            throw WebexSDKError.network("Webex realtime socket returned unsupported binary frame")
        @unknown default:
            throw WebexSDKError.network("Webex realtime socket returned unknown frame type")
        }
    }

    func cancel() {
        task.cancel(with: .goingAway, reason: nil)
    }
}
```

- [ ] **Step 4: Implement Mercury session**

Create `Sources/WebexSwiftSDK/Realtime/WebexMercuryWebSocketSession.swift`:

```swift
import Foundation

internal final class WebexMercuryWebSocketSession: @unchecked Sendable {
    private let webSocket: WebexRealtimeWebSocket
    private let accessTokenProvider: @Sendable () async throws -> AccessTokenState

    init(
        webSocket: WebexRealtimeWebSocket,
        accessTokenProvider: @escaping @Sendable () async throws -> AccessTokenState
    ) {
        self.webSocket = webSocket
        self.accessTokenProvider = accessTokenProvider
    }

    func frames() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await webSocket.connect()
                    try await sendAuthorization()
                    while !Task.isCancelled {
                        let text = try await webSocket.receiveText()
                        continuation.yield(text)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: WebexSDKError.network(Redactor.redactSecrets(error.localizedDescription)))
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
                webSocket.cancel()
            }
        }
    }

    func ack(messageID: String) async throws {
        let data = try JSONSerialization.data(withJSONObject: ["type": "ack", "messageId": messageID], options: [.sortedKeys])
        try await webSocket.send(text: String(decoding: data, as: UTF8.self))
    }

    func cancel() {
        webSocket.cancel()
    }

    private func sendAuthorization() async throws {
        let token = try await accessTokenProvider()
        let envelope: [String: Any] = [
            "id": UUID().uuidString,
            "type": "authorization",
            "data": ["token": "Bearer \(token.value)"]
        ]
        let data = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
        try await webSocket.send(text: String(decoding: data, as: UTF8.self))
    }
}
```

- [ ] **Step 5: Run WebSocket session tests and full tests**

Run:

```bash
swift test --filter WebexMercuryWebSocketSessionTests
swift test
```

Expected: tests pass.

- [ ] **Step 6: Commit Task 3**

```bash
git add Sources/WebexSwiftSDK/Realtime/WebexRealtimeWebSocketTransport.swift Sources/WebexSwiftSDK/Realtime/WebexMercuryWebSocketSession.swift Tests/WebexSwiftSDKTests/WebexMercuryWebSocketSessionTests.swift
git commit -S -m "feat: add Webex realtime websocket session"
```

## Task 4: Event Decoder And Trigger Mapping

**Files:**
- Create: `Sources/WebexSwiftSDK/Realtime/WebexRealtimeEventDecoder.swift`
- Create: `Sources/WebexSwiftSDK/Realtime/WebexRealtimeTriggerAdapter.swift`
- Create: `Tests/WebexSwiftSDKTests/WebexRealtimeEventDecoderTests.swift`

- [ ] **Step 1: Write failing decoder tests**

Add:

```swift
import XCTest
@testable import WebexSwiftSDK

final class WebexRealtimeEventDecoderTests: XCTestCase {
    func testDecodesJSSDKLikeMessageCreatedEvent() throws {
        let data = Data("""
        {
          "id": "event-id",
          "resource": "messages",
          "event": "created",
          "data": {
            "id": "message-id",
            "roomId": "room-id",
            "personId": "person-id"
          }
        }
        """.utf8)

        let event = try WebexRealtimeEventDecoder().decode(data)

        XCTAssertEqual(event.id, "event-id")
        XCTAssertEqual(event.resource, "messages")
        XCTAssertEqual(event.event, "created")
        XCTAssertEqual(event.decodeStatus, .known)
        XCTAssertEqual(event.resourceID, "message-id")
        XCTAssertEqual(event.roomID, "room-id")
        XCTAssertEqual(event.actorID, "person-id")
    }

    func testPreservesUnknownEvent() throws {
        let data = Data("""
        {
          "id": "event-id",
          "resource": "messages",
          "event": "updated",
          "data": {
            "id": "message-id",
            "roomId": "room-id"
          }
        }
        """.utf8)

        let event = try WebexRealtimeEventDecoder().decode(data)

        XCTAssertEqual(event.knownEvent, .updated)
        XCTAssertEqual(event.decodeStatus, .unknownEvent)
        XCTAssertEqual(event.resourceID, "message-id")
    }

    func testMarksKnownEventWithUnexpectedPayloadAsUnknownPayload() throws {
        let data = Data("""
        {
          "id": "event-id",
          "resource": "messages",
          "event": "created",
          "data": {
            "unexpected": "value"
          }
        }
        """.utf8)

        let event = try WebexRealtimeEventDecoder().decode(data)

        XCTAssertEqual(event.decodeStatus, .unknownPayload)
        XCTAssertNil(event.resourceID)
        XCTAssertEqual(event.payload["unexpected"], .string("value"))
    }

    func testMapsMercuryConversationActivityPostToMessageCreated() throws {
        let data = Data("""
        {
          "id": "mercury-id",
          "data": {
            "eventType": "conversation.activity",
            "activity": {
              "id": "activity-id",
              "verb": "post",
              "actor": { "id": "actor-id" },
              "target": { "id": "conversation-id" },
              "object": { "id": "message-id", "objectType": "activity" }
            }
          }
        }
        """.utf8)

        let event = try WebexRealtimeEventDecoder().decode(data)

        XCTAssertEqual(event.resource, "messages")
        XCTAssertEqual(event.event, "created")
        XCTAssertEqual(event.resourceID, "message-id")
        XCTAssertEqual(event.roomID, "conversation-id")
        XCTAssertEqual(event.actorID, "actor-id")
        XCTAssertEqual(event.ackID, "message-id")
    }

    func testTriggerAdapterUsesEventStreamTrigger() {
        let event = WebexRealtimeEvent(resource: "rooms", event: "updated", decodeStatus: .known, resourceID: "room-id")

        XCTAssertEqual(WebexRealtimeTriggerAdapter.trigger(for: event), event.streamTrigger())
    }
}
```

- [ ] **Step 2: Run decoder tests and verify failure**

Run:

```bash
swift test --filter WebexRealtimeEventDecoderTests
```

Expected: compile failure for missing decoder and adapter.

- [ ] **Step 3: Implement event decoder**

Create `Sources/WebexSwiftSDK/Realtime/WebexRealtimeEventDecoder.swift` with:

```swift
import Foundation

internal struct WebexRealtimeEventDecoder: Sendable {
    func decode(_ data: Data) throws -> WebexRealtimeEvent {
        let json = try JSONDecoder().decode(WebexJSONValue.self, from: data)
        guard case .object(let object) = json else {
            throw WebexSDKError.network("Invalid Webex realtime frame")
        }

        if let resource = object["resource"]?.stringValue,
           let event = object["event"]?.stringValue {
            return decodeJSSDKLikeEvent(object: object, resource: resource, event: event)
        }

        if let mercury = decodeMercuryConversationActivity(object: object) {
            return mercury
        }

        return WebexRealtimeEvent(
            id: object["id"]?.stringValue,
            resource: object["resource"]?.stringValue ?? "unknown",
            event: object["event"]?.stringValue ?? "unknown",
            decodeStatus: .unknownPayload,
            payload: object
        )
    }
}
```

In the same file add private helpers:

- `decodeJSSDKLikeEvent(object:resource:event:)`
  - Reads `data` object.
  - Pulls `id`, `roomId`, `personId`, and `actorId`.
  - Marks `.known` only for sample-backed pairs with required IDs.
  - Marks `.unknownEvent` for unmodeled event names like `messages:updated`.
  - Marks `.unknownPayload` when known event names lack expected IDs.
- `decodeMercuryConversationActivity(object:)`
  - Handles `data.eventType == "conversation.activity"`.
  - Maps `activity.verb == "post"` to `messages:created`.
  - Maps `activity.verb == "update"` to `messages:updated`.
  - Maps unsupported verbs to `unknownEvent`.
  - Extracts `activity.object.id`, `activity.target.id`, and `activity.actor.id` when present.
  - Sets `ackID` when a safe message/activity identifier is available.
- An internal `WebexJSONValue.stringValue` extension in this file if one is not already public.

- [ ] **Step 4: Implement trigger adapter**

Create `Sources/WebexSwiftSDK/Realtime/WebexRealtimeTriggerAdapter.swift`:

```swift
import Foundation

internal enum WebexRealtimeTriggerAdapter {
    static func trigger(for event: WebexRealtimeEvent) -> WebexStreamTrigger {
        event.streamTrigger()
    }
}
```

- [ ] **Step 5: Run decoder tests and full tests**

Run:

```bash
swift test --filter WebexRealtimeEventDecoderTests
swift test
```

Expected: tests pass.

- [ ] **Step 6: Commit Task 4**

```bash
git add Sources/WebexSwiftSDK/Realtime/WebexRealtimeEventDecoder.swift Sources/WebexSwiftSDK/Realtime/WebexRealtimeTriggerAdapter.swift Tests/WebexSwiftSDKTests/WebexRealtimeEventDecoderTests.swift
git commit -S -m "feat: decode Webex realtime events"
```

## Task 5: Public Connection And `WebexClient.realtime`

**Files:**
- Create: `Sources/WebexSwiftSDK/Realtime/WebexRealtimeConnection.swift`
- Create: `Sources/WebexSwiftSDK/Realtime/WebexRealtimeClient.swift`
- Create: `Tests/WebexSwiftSDKTests/WebexRealtimeConnectionTests.swift`
- Modify: `Sources/WebexSwiftSDK/WebexClient.swift`

- [ ] **Step 1: Write failing connection tests**

Add:

```swift
import XCTest
@testable import WebexSwiftSDK

final class WebexRealtimeConnectionTests: XCTestCase {
    func testConnectionEmitsEventsAndTriggers() async throws {
        let source = RealtimeTestSource()
        let connection = WebexRealtimeConnection(source: source)

        var stateIterator = connection.states.makeAsyncIterator()
        var eventIterator = connection.events.makeAsyncIterator()
        var triggerIterator = connection.triggers.makeAsyncIterator()

        source.emitState(.connected)
        source.emitEvent(WebexRealtimeEvent(
            resource: "messages",
            event: "created",
            decodeStatus: .known,
            resourceID: "message-id",
            roomID: "room-id"
        ))

        XCTAssertEqual(await stateIterator.next(), .connected)
        XCTAssertEqual(await eventIterator.next()?.resourceID, "message-id")
        XCTAssertEqual(await triggerIterator.next()?.roomID, "room-id")
    }

    func testCancelFinishesConnection() async {
        let source = RealtimeTestSource()
        let connection = WebexRealtimeConnection(source: source)

        connection.cancel()

        XCTAssertEqual(source.cancelCallCount(), 1)
    }

    func testWebexClientExposesRealtimeClient() async throws {
        let store = InMemoryWebexStore()
        let accountID = WebexAccountID()
        let client = WebexClient(
            accountID: accountID,
            configuration: WebexIntegrationConfiguration(
                clientID: "client",
                clientSecret: "secret",
                redirectURI: URL(string: "http://127.0.0.1:8282/oauth")!,
                scopes: ["spark:messages_read"]
            ),
            tokenStore: store,
            httpClient: MockNoopHTTPClient(),
            initialAccessToken: AccessTokenState(value: "access", expiresAt: .distantFuture, tokenType: "Bearer")
        )

        XCTAssertEqual(client.realtime.accountID, accountID)
    }
}
```

Add test fakes:

```swift
private final class RealtimeTestSource: WebexRealtimeConnectionSource, @unchecked Sendable {
    private let lock = NSLock()
    private var eventsContinuations: [AsyncStream<WebexRealtimeEvent>.Continuation] = []
    private var statesContinuations: [AsyncStream<WebexRealtimeConnectionState>.Continuation] = []
    private var cancels = 0

    var events: AsyncStream<WebexRealtimeEvent> {
        AsyncStream { continuation in
            locked {
                eventsContinuations.append(continuation)
            }
        }
    }

    var states: AsyncStream<WebexRealtimeConnectionState> {
        AsyncStream { continuation in
            locked {
                statesContinuations.append(continuation)
            }
        }
    }

    func cancel() {
        let continuations = locked {
            cancels += 1
            return (eventsContinuations, statesContinuations)
        }
        continuations.0.forEach { $0.finish() }
        continuations.1.forEach { $0.finish() }
    }

    func emitEvent(_ event: WebexRealtimeEvent) {
        locked { eventsContinuations }.forEach { $0.yield(event) }
    }

    func emitState(_ state: WebexRealtimeConnectionState) {
        locked { statesContinuations }.forEach { $0.yield(state) }
    }

    func cancelCallCount() -> Int {
        locked { cancels }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private struct MockNoopHTTPClient: HTTPClient {
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        throw WebexSDKError.network("No requests expected")
    }
}
```

- [ ] **Step 2: Run connection tests and verify failure**

Run:

```bash
swift test --filter WebexRealtimeConnectionTests
```

Expected: compile failure for missing connection types and `client.realtime`.

- [ ] **Step 3: Implement connection source and connection**

Create `Sources/WebexSwiftSDK/Realtime/WebexRealtimeConnection.swift`:

```swift
import Foundation

internal protocol WebexRealtimeConnectionSource: Sendable {
    var events: AsyncStream<WebexRealtimeEvent> { get }
    var states: AsyncStream<WebexRealtimeConnectionState> { get }
    func cancel()
}

public final class WebexRealtimeConnection: @unchecked Sendable {
    public let events: AsyncStream<WebexRealtimeEvent>
    public let states: AsyncStream<WebexRealtimeConnectionState>
    public let triggers: AsyncStream<WebexStreamTrigger>

    private let source: WebexRealtimeConnectionSource

    internal init(source: WebexRealtimeConnectionSource) {
        self.source = source
        self.events = source.events
        self.states = source.states
        self.triggers = AsyncStream { continuation in
            let task = Task {
                for await event in source.events {
                    continuation.yield(WebexRealtimeTriggerAdapter.trigger(for: event))
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    public func cancel() {
        source.cancel()
    }
}
```

- [ ] **Step 4: Implement realtime client**

Create `Sources/WebexSwiftSDK/Realtime/WebexRealtimeClient.swift` with a final-class source that owns private synchronized stream state. The source wires device service, session, decoder, states, and cancellation:

```swift
import Foundation

public struct WebexRealtimeClient: Sendable {
    public let accountID: WebexAccountID

    private let httpClient: HTTPClient
    private let accessTokenProvider: @Sendable () async throws -> AccessTokenState
    private let tokenInvalidator: @Sendable () async -> Void

    internal init(
        accountID: WebexAccountID,
        httpClient: HTTPClient,
        accessTokenProvider: @escaping @Sendable () async throws -> AccessTokenState,
        tokenInvalidator: @escaping @Sendable () async -> Void
    ) {
        self.accountID = accountID
        self.httpClient = httpClient
        self.accessTokenProvider = accessTokenProvider
        self.tokenInvalidator = tokenInvalidator
    }

    public func connect(options: WebexRealtimeOptions = WebexRealtimeOptions()) -> WebexRealtimeConnection {
        let source = WebexRealtimeLiveConnectionSource(
            httpClient: httpClient,
            accessTokenProvider: accessTokenProvider,
            tokenInvalidator: tokenInvalidator,
            options: options
        )
        source.start()
        return WebexRealtimeConnection(source: source)
    }
}
```

The `WebexRealtimeLiveConnectionSource` final class must:

- Store event/state stream continuations.
- Emit `.discovering`, `.registeringDevice`, `.connecting`, `.authorizing`, `.connected`.
- Create `WebexMercuryDeviceService`.
- Create `URLSessionWebSocketTransport(url: device.webSocketURL)`.
- Create `WebexMercuryWebSocketSession`.
- Decode each frame with `WebexRealtimeEventDecoder`.
- Call `session.ack(messageID:)` after yielding a decoded event when `event.ackID` is present.
- Yield events that pass resource/event filters.
- Yield triggers through `WebexRealtimeConnection`.
- Finish streams on cancellation.

- [ ] **Step 5: Expose realtime from WebexClient**

Modify `Sources/WebexSwiftSDK/WebexClient.swift`:

```swift
public struct WebexClient: Sendable {
    public let accountID: WebexAccountID
    public let people: PeopleAPI
    public let spaces: SpacesAPI
    public let memberships: MembershipsAPI
    public let messages: MessagesAPI
    public let webhooks: WebhooksAPI
    public let realtime: WebexRealtimeClient
```

Initialize it after `transport`:

```swift
self.realtime = WebexRealtimeClient(
    accountID: accountID,
    httpClient: httpClient,
    accessTokenProvider: {
        try await tokenManager.validAccessToken()
    },
    tokenInvalidator: {
        await tokenManager.invalidateAccessToken()
    }
)
```

- [ ] **Step 6: Run connection tests and full tests**

Run:

```bash
swift test --filter WebexRealtimeConnectionTests
swift test
```

Expected: tests pass.

- [ ] **Step 7: Commit Task 5**

```bash
git add Sources/WebexSwiftSDK/Realtime/WebexRealtimeConnection.swift Sources/WebexSwiftSDK/Realtime/WebexRealtimeClient.swift Sources/WebexSwiftSDK/WebexClient.swift Tests/WebexSwiftSDKTests/WebexRealtimeConnectionTests.swift
git commit -S -m "feat: expose Webex realtime connections"
```

## Task 6: Reconnect, Auth Refresh, And Stale Device Handling

**Files:**
- Modify: `Sources/WebexSwiftSDK/Realtime/WebexRealtimeClient.swift`
- Modify: `Sources/WebexSwiftSDK/Realtime/WebexMercuryDeviceService.swift`
- Modify: `Sources/WebexSwiftSDK/Realtime/WebexRealtimeWebSocketTransport.swift`
- Modify: `Tests/WebexSwiftSDKTests/WebexRealtimeConnectionTests.swift`
- Modify: `Tests/WebexSwiftSDKTests/WebexMercuryDeviceServiceTests.swift`

- [ ] **Step 1: Write failing reconnect tests**

Add to `WebexRealtimeConnectionTests`:

```swift
func testReconnectEmitsBackoffStateAfterTransientSocketFailure() async throws {
    let sleeper = SleepRecorder()
    let source = WebexRealtimeLiveConnectionSource(
        httpClient: MockNoopHTTPClient(),
        accessTokenProvider: { AccessTokenState(value: "access", expiresAt: .distantFuture, tokenType: "Bearer") },
        tokenInvalidator: {},
        options: WebexRealtimeOptions(retryPolicy: RetryPolicy(maxAttempts: 2, baseDelay: 1, jitter: 0, maximumDelay: 240)),
        makeDeviceService: { FakeDeviceService(devices: [WebexMercuryDevice(id: "device", name: "webex-swift-sdk", webSocketURL: URL(string: "wss://example.com/ws")!)]) },
        makeWebSocket: { _ in FakeFailingWebSocket(error: WebexSDKError.network("socket closed")) },
        sleeper: { delay in try await sleeper.sleep(for: delay) }
    )
    source.start()

    let states = await collectStates(from: source.states, count: 4)

    XCTAssertTrue(states.contains(.reconnecting(attempt: 1, delay: 1)))
    XCTAssertEqual(await sleeper.recordedDelays(), [1])
}
```

Add these test fakes to `WebexRealtimeConnectionTests`:

```swift
private actor SleepRecorder {
    private var delays: [TimeInterval] = []

    func sleep(for delay: TimeInterval) async throws {
        delays.append(delay)
    }

    func recordedDelays() -> [TimeInterval] {
        delays
    }
}

private struct FakeDeviceService: WebexMercuryDeviceProviding {
    let devices: [WebexMercuryDevice]

    func device(options: WebexRealtimeOptions) async throws -> WebexMercuryDevice {
        guard let device = devices.first else {
            throw WebexSDKError.network("No fake realtime device")
        }
        return device
    }

    func invalidateCachedDevice() async {}
}

private struct FakeFailingWebSocket: WebexRealtimeWebSocket {
    let error: WebexSDKError

    init(error: WebexSDKError) {
        self.error = error
    }

    func connect() async throws {}
    func send(text: String) async throws {}
    func receiveText() async throws -> String { throw error }
    func cancel() {}
}

private func collectStates(
    from stream: AsyncStream<WebexRealtimeConnectionState>,
    count: Int
) async -> [WebexRealtimeConnectionState] {
    var states: [WebexRealtimeConnectionState] = []
    var iterator = stream.makeAsyncIterator()
    while states.count < count, let state = await iterator.next() {
        states.append(state)
    }
    return states
}
```

Add to `WebexMercuryDeviceServiceTests`:

```swift
func testInvalidatesCachedDeviceForStaleHandshake() async throws {
    let cache = WebexMercuryDeviceCache()
    await cache.save(WebexMercuryDevice(id: "stale", name: "webex-swift-sdk", webSocketURL: URL(string: "wss://old.example.com/ws")!))
    await cache.invalidate()

    XCTAssertNil(await cache.load())
}
```

- [ ] **Step 2: Run reconnect tests and verify failure**

Run:

```bash
swift test --filter WebexRealtimeConnectionTests/testReconnectEmitsBackoffStateAfterTransientSocketFailure
swift test --filter WebexMercuryDeviceServiceTests/testInvalidatesCachedDeviceForStaleHandshake
```

Expected: compile failure until injectable factories/backoff hooks exist.

- [ ] **Step 3: Add injectable factories and backoff loop**

Modify `WebexRealtimeLiveConnectionSource` to accept internal test-only factory parameters. Use optional factories so production construction stays concise:

```swift
init(
    httpClient: HTTPClient,
    accessTokenProvider: @escaping @Sendable () async throws -> AccessTokenState,
    tokenInvalidator: @escaping @Sendable () async -> Void,
    options: WebexRealtimeOptions,
    makeDeviceService: (@Sendable () -> WebexMercuryDeviceProviding)? = nil,
    makeWebSocket: @escaping @Sendable (URL) -> WebexRealtimeWebSocket = { URLSessionWebSocketTransport(url: $0) },
    sleeper: @escaping @Sendable (TimeInterval) async throws -> Void = { delay in
        guard delay > 0, delay.isFinite else { return }
        try await Task.sleep(nanoseconds: UInt64((delay * 1_000_000_000).rounded(.down)))
    }
) {
    self.makeDeviceService = makeDeviceService ?? {
        WebexMercuryDeviceService(
            httpClient: httpClient,
            accessTokenProvider: accessTokenProvider,
            retryPolicy: options.retryPolicy,
            sleeper: sleeper
        )
    }
    self.makeWebSocket = makeWebSocket
    self.sleeper = sleeper
}
```

Add an internal protocol:

```swift
internal protocol WebexMercuryDeviceProviding: Sendable {
    func device(options: WebexRealtimeOptions) async throws -> WebexMercuryDevice
    func invalidateCachedDevice() async
}
```

Make `WebexMercuryDeviceService` conform.

The connection loop must:

- Retry while not cancelled and attempt count remains below `options.retryPolicy.maxAttempts`.
- Emit `.reconnecting(attempt:delay:)` before sleeping.
- Use `retryPolicy.delay(forAttempt:)`.
- On stale-handshake 404, call `invalidateCachedDevice()` and retry device setup without treating it as a normal backoff attempt.
- On 401/403, call `tokenInvalidator()` once and retry once with a fresh access token.
- Finish with `.failed(error)` when retries are exhausted.

- [ ] **Step 4: Run reconnect tests and full tests**

Run:

```bash
swift test --filter WebexRealtimeConnectionTests
swift test --filter WebexMercuryDeviceServiceTests
swift test
```

Expected: tests pass.

- [ ] **Step 5: Commit Task 6**

```bash
git add Sources/WebexSwiftSDK/Realtime Tests/WebexSwiftSDKTests/WebexRealtimeConnectionTests.swift Tests/WebexSwiftSDKTests/WebexMercuryDeviceServiceTests.swift
git commit -S -m "feat: add realtime reconnect handling"
```

## Task 7: Realtime Events Smoke Example

**Files:**
- Create: `Examples/WebexRealtimeEventsSmoke/Package.swift`
- Create: `Examples/WebexRealtimeEventsSmoke/README.md`
- Create: `Examples/WebexRealtimeEventsSmoke/Sources/WebexRealtimeEventsSmoke/main.swift`
- Create: `Examples/WebexRealtimeEventsSmoke/Tests/WebexRealtimeEventsSmokeTests/RealtimeSmokeOptionsTests.swift`

- [ ] **Step 1: Write failing smoke option tests**

Create `RealtimeSmokeOptionsTests.swift`:

```swift
import XCTest
@testable import WebexRealtimeEventsSmoke

final class RealtimeSmokeOptionsTests: XCTestCase {
    func testDefaults() throws {
        let options = try RealtimeSmokeOptions(environment: [:])

        XCTAssertNil(options.resource)
        XCTAssertNil(options.event)
        XCTAssertFalse(options.includeSeen)
        XCTAssertFalse(options.printRawUnknown)
    }

    func testParsesFiltersAndBooleans() throws {
        let options = try RealtimeSmokeOptions(environment: [
            "WEBEX_REALTIME_RESOURCE": "messages",
            "WEBEX_REALTIME_EVENT": "created",
            "WEBEX_REALTIME_INCLUDE_SEEN": "true",
            "WEBEX_REALTIME_PRINT_RAW_UNKNOWN": "1"
        ])

        XCTAssertEqual(options.resource, "messages")
        XCTAssertEqual(options.event, "created")
        XCTAssertTrue(options.includeSeen)
        XCTAssertTrue(options.printRawUnknown)
    }
}
```

- [ ] **Step 2: Add smoke package**

Create `Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "webex-realtime-events-smoke",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "WebexRealtimeEventsSmoke",
            dependencies: [
                .product(name: "WebexSwiftSDK", package: "webex-swift-sdk")
            ]
        ),
        .testTarget(
            name: "WebexRealtimeEventsSmokeTests",
            dependencies: ["WebexRealtimeEventsSmoke"]
        )
    ]
)
```

- [ ] **Step 3: Add smoke executable**

Create `main.swift` with:

```swift
import AppKit
import Foundation
import WebexSwiftSDK

@main
struct WebexRealtimeEventsSmoke {
    static func main() async {
        do {
            try await run()
        } catch is CancellationError {
            fputs("Cancelled.\n", stderr)
            Foundation.exit(130)
        } catch {
            fputs("Realtime events smoke failed: \(String(describing: error))\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func run() async throws {
        let environment = ProcessInfo.processInfo.environment
        let smokeOptions = try RealtimeSmokeOptions(environment: environment)
        let configuration = try configurationFromEnvironment(environment)
        let keychainService = environment["WEBEX_KEYCHAIN_SERVICE"] ?? "com.webex.swift-sdk.realtime-events-smoke"
        let store = KeychainWebexStore(service: keychainService)
        let registry = WebexClientRegistry(store: store, httpClient: URLSessionHTTPClient())

        print("Using Keychain service: \(keychainService)")
        let authorized = try await registry.authorizeAndAddAccount(
            configuration: configuration,
            openAuthorizationURL: { url in
                print("Opening Webex authorization in your default browser.")
                guard NSWorkspace.shared.open(url) else {
                    throw SmokeError.failedToOpenAuthorizationURL
                }
            }
        )

        let connection = authorized.client.realtime.connect(options: smokeOptions.realtimeOptions)
        defer { connection.cancel() }

        Task {
            for await state in connection.states {
                print("[\(timestamp())] state: \(state)")
            }
        }

        for await event in connection.events {
            guard smokeOptions.allows(event: event) else {
                continue
            }
            printEvent(event, printRawUnknown: smokeOptions.printRawUnknown)
        }
    }
}
```

In the same file define:

- `RealtimeSmokeOptions`
  - Parses `WEBEX_REALTIME_RESOURCE`, `WEBEX_REALTIME_EVENT`, `WEBEX_REALTIME_INCLUDE_SEEN`, `WEBEX_REALTIME_PRINT_RAW_UNKNOWN`.
  - Builds `WebexRealtimeOptions`.
  - Filters events by raw resource/event strings.
- `configurationFromEnvironment(_:)`
  - Same pattern as existing smoke examples.
  - Default scopes include `spark:messages_read spark:rooms_read spark:memberships_read spark:people_read`.
- `printEvent(_:printRawUnknown:)`
  - Prints timestamp, `resource:event`, decode status, IDs.
  - Prints `UNKNOWN EVENT` for `.unknownEvent`.
  - Prints `UNKNOWN PAYLOAD` for `.unknownPayload`.
  - Prints compact redacted payload only when `printRawUnknown == true`.
- `SmokeError`
  - `missingEnvironment(String)`, `invalidRedirectURI`, `failedToOpenAuthorizationURL`.

- [ ] **Step 4: Add README**

Create `README.md` with:

```markdown
# Webex Realtime Events Smoke

Runs the SDK WebSocket realtime listener and prints events as they arrive.

## Required

- `WEBEX_CLIENT_ID`
- `WEBEX_CLIENT_SECRET`
- Webex integration redirect URI set to `http://127.0.0.1:8282/oauth/callback`

## Optional

- `WEBEX_REDIRECT_URI`
- `WEBEX_SCOPES`
- `WEBEX_KEYCHAIN_SERVICE`
- `WEBEX_REALTIME_RESOURCE`
- `WEBEX_REALTIME_EVENT`
- `WEBEX_REALTIME_INCLUDE_SEEN=true`
- `WEBEX_REALTIME_PRINT_RAW_UNKNOWN=true`

## Run

```bash
cd Examples/WebexRealtimeEventsSmoke
swift run WebexRealtimeEventsSmoke
```

Known events print normally. Unknown event names print `UNKNOWN EVENT`. Known event names with unexpected payload shape print `UNKNOWN PAYLOAD`.
```

- [ ] **Step 5: Run smoke tests and build smoke**

Run:

```bash
cd Examples/WebexRealtimeEventsSmoke
swift test
swift build
```

Expected: tests and build pass. Do not require live Webex for package tests/build.

- [ ] **Step 6: Commit Task 7**

```bash
git add Examples/WebexRealtimeEventsSmoke
git commit -S -m "test: add Webex realtime events smoke"
```

## Task 8: Docs, Verification, And Branch Finish

**Files:**
- Modify: `.agents/docs/webex-realtime-triggers.md`
- Modify: `.agents/docs/webex-sdk-streams-roadmap.md`

- [ ] **Step 1: Update realtime docs**

In `.agents/docs/webex-realtime-triggers.md`, add a section:

```markdown
## WebSocket Realtime Status

The SDK includes experimental native Swift WebSocket realtime support. It discovers WDM through the limited/preauth U2C catalog with postauth preference when available, registers a desktop device, connects with `URLSessionWebSocketTask`, emits `WebexRealtimeEvent`, and maps events into `WebexStreamTrigger`.

This is receive-only. REST remains the write/detail API. Unknown resource/event/payload shapes are preserved and surfaced for iteration through `Examples/WebexRealtimeEventsSmoke`.
```

In `.agents/docs/webex-sdk-streams-roadmap.md`, move WebSocket transport from future work to experimental foundation and keep follow-ups:

```markdown
### Realtime Transport Follow-Ups

- Use `WebexRealtimeEventsSmoke` to capture unknown payloads.
- Add typed support when live Webex emits useful undocumented events.
- Revisit WDM device persistence only if smoke testing shows repeated registration is expensive or rate-limited.
```

- [ ] **Step 2: Run complete verification**

Run from repo root:

```bash
swift test
swift build
cd Examples/WebexRealtimeEventsSmoke
swift test
swift build
cd ../..
git diff --check
```

Expected:

- SDK tests pass.
- SDK build passes.
- Realtime smoke package tests pass.
- Realtime smoke package build passes.
- Diff check has no whitespace errors.

- [ ] **Step 3: Commit docs**

```bash
git add .agents/docs/webex-realtime-triggers.md .agents/docs/webex-sdk-streams-roadmap.md
git commit -S -m "docs: document Webex realtime websocket support"
```

- [ ] **Step 4: Final branch status**

Run:

```bash
git status --short --branch
git log --show-signature --oneline -5
```

Expected:

- Working tree clean.
- Recent commits show good signatures.

## Self-Review Checklist

Spec coverage:

- Pure Swift runtime: Task 3 uses `URLSessionWebSocketTask`.
- U2C/WDM discovery and device registration: Task 2.
- Single public connection type: Task 5.
- Event and trigger streams: Tasks 1, 4, 5.
- Unknown event/payload preservation: Task 4 and Task 7.
- Graceful backoff: Tasks 2 and 6.
- 401/403 token invalidation: Task 6.
- Stale-device 404 handling: Task 6.
- Security/redaction: Tasks 2, 3, 7.
- Strict tests: each task starts with tests.
- Committed smoke example: Task 7.

Placeholder scan:

- Passed. The plan uses concrete file paths, commands, tests, and code snippets.

Type consistency:

- Public entry point is `WebexClient.realtime`.
- Public live type is `WebexRealtimeConnection`.
- Rich event type is `WebexRealtimeEvent`.
- Refresh signal remains `WebexStreamTrigger`.
