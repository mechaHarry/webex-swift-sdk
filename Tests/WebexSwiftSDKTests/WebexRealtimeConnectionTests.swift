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

    func testConnectionFanOutGivesEachSubscriberFullEventSequence() async throws {
        let source = FakeRealtimeConnectionSource()
        let connection = WebexRealtimeConnection(source: source)
        var firstEventIterator = connection.events.makeAsyncIterator()
        var secondEventIterator = connection.events.makeAsyncIterator()
        var triggerIterator = connection.triggers.makeAsyncIterator()
        let event = messageEvent()

        source.emit(event)

        let firstEvent = await firstEventIterator.next()
        let secondEvent = await secondEventIterator.next()
        let trigger = await triggerIterator.next()

        XCTAssertEqual(firstEvent, event)
        XCTAssertEqual(secondEvent, event)
        XCTAssertEqual(trigger, event.streamTrigger())
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

    func testLateEventAndTriggerSubscribersFinishAfterSourceEventsComplete() async throws {
        let source = FakeRealtimeConnectionSource()
        let connection = WebexRealtimeConnection(source: source)
        var firstEventIterator = connection.events.makeAsyncIterator()

        source.finishEvents()
        let firstEvent = await firstEventIterator.next()

        var lateEventIterator = connection.events.makeAsyncIterator()
        var lateTriggerIterator = connection.triggers.makeAsyncIterator()
        let lateEvent = await lateEventIterator.next()
        let lateTrigger = await lateTriggerIterator.next()

        XCTAssertNil(firstEvent)
        XCTAssertNil(lateEvent)
        XCTAssertNil(lateTrigger)
    }

    func testLateStateSubscriberFinishesAfterSourceStatesComplete() async throws {
        let source = FakeRealtimeConnectionSource()
        let connection = WebexRealtimeConnection(source: source)
        var firstStateIterator = connection.states.makeAsyncIterator()

        source.finishStates()
        let firstState = await firstStateIterator.next()

        var lateStateIterator = connection.states.makeAsyncIterator()
        let lateState = await lateStateIterator.next()

        XCTAssertNil(firstState)
        XCTAssertNil(lateState)
    }

    func testConnectionDeinitCancelsSource() async throws {
        let source = FakeRealtimeConnectionSource()
        var connection: WebexRealtimeConnection? = WebexRealtimeConnection(source: source)

        XCTAssertNotNil(connection)
        connection = nil

        try await eventually {
            source.cancelCount() == 1
        }
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

    func testLiveSourceWaitsForAuthorizationBeforeEmittingConnected() async throws {
        let device = WebexMercuryDevice(
            id: "device-id",
            name: "webex-swift-sdk",
            webSocketURL: URL(string: "wss://mercury.example.com")!
        )
        let session = GatedMercurySession()
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

        source.start()

        var states: [WebexRealtimeConnectionState] = []
        for _ in 0..<4 {
            if let state = await stateIterator.next() {
                states.append(state)
            }
        }

        XCTAssertEqual(states, [.discovering, .registeringDevice, .connecting, .authorizing])

        let capturedState = RealtimeStateCapture()
        let pendingConnectedRead = Task {
            await capturedState.set(await stateIterator.next())
        }

        try await Task.sleep(for: .milliseconds(50))
        let stateBeforeAuthorizationCompletes = await capturedState.state()
        XCTAssertNil(stateBeforeAuthorizationCompletes)

        session.finishAuthorization()
        try await eventually {
            await capturedState.state() == .connected
        }

        source.cancel()
        pendingConnectedRead.cancel()
    }

    func testConnectionDeinitCancelsLiveSourceSessionAndSocket() async throws {
        let device = WebexMercuryDevice(
            id: "device-id",
            name: "webex-swift-sdk",
            webSocketURL: URL(string: "wss://mercury.example.com")!
        )
        let session = BlockingFakeMercurySession()
        let webSocket = InspectableFakeWebSocket()
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
                webSocket
            },
            sessionFactory: { _, _ in
                session
            }
        )
        var connection: WebexRealtimeConnection? = WebexRealtimeConnection(source: source)
        var stateIterator = connection!.states.makeAsyncIterator()

        source.start()
        for _ in 0..<5 {
            _ = await stateIterator.next()
        }
        connection = nil

        try await eventually {
            session.cancelCount() > 0 && webSocket.cancelCount() > 0
        }
    }

    func testLiveSourceRetriesOnceAfterUnauthorizedSessionErrorInvalidatesToken() async throws {
        let device = WebexMercuryDevice(
            id: "device-id",
            name: "webex-swift-sdk",
            webSocketURL: URL(string: "wss://mercury.example.com")!
        )
        let invalidator = TokenInvalidatorSpy()
        let sessions = MercurySessionQueue([
            FakeMercurySession(frames: [], error: WebexSDKError.webexAPI(statusCode: 401, trackingID: nil, message: "unauthorized")),
            FakeMercurySession(frames: [
                """
                {"id":"event-1","resource":"messages","event":"created","data":{"id":"message-id","roomId":"room-id","personId":"person-id"}}
                """
            ])
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
            tokenInvalidator: {
                await invalidator.invalidate()
            },
            options: WebexRealtimeOptions(),
            deviceServiceFactory: { _, _, _, _ in
                FakeDeviceService(device: device)
            },
            webSocketFactory: { _ in
                FakeLiveWebSocket()
            },
            sessionFactory: { _, _ in
                sessions.next()
            }
        )
        var eventIterator = source.events.makeAsyncIterator()

        source.start()
        let event = await eventIterator.next()
        let invalidationCount = await invalidator.count()

        XCTAssertEqual(event?.resourceID, "message-id")
        XCTAssertEqual(invalidationCount, 1)
    }

    func testLiveSourceInvalidatesTokenOnceThenFailsWhenUnauthorizedDeviceSetupRepeats() async throws {
        let invalidator = TokenInvalidatorSpy()
        let source = WebexRealtimeLiveConnectionSource(
            httpClient: NoopHTTPClient(),
            accessTokenProvider: {
                AccessTokenState(
                    value: "access-token",
                    expiresAt: Date(timeIntervalSince1970: 1_000),
                    tokenType: "Bearer"
                )
            },
            tokenInvalidator: {
                await invalidator.invalidate()
            },
            options: WebexRealtimeOptions(),
            deviceServiceFactory: { _, _, _, _ in
                FailingDeviceService(error: .webexAPI(statusCode: 401, trackingID: nil, message: "unauthorized"))
            }
        )
        var stateIterator = source.states.makeAsyncIterator()

        source.start()
        let failedState = await firstFailedState(from: &stateIterator)
        let invalidationCount = await invalidator.count()

        XCTAssertEqual(failedState, .failed(.webexAPI(statusCode: 401, trackingID: nil, message: "unauthorized")))
        XCTAssertEqual(invalidationCount, 1)
    }

    func testLiveSourceDoesNotRetryUnauthorizedWhenMaxAttemptsIsOne() async throws {
        let device = WebexMercuryDevice(
            id: "device-id",
            name: "webex-swift-sdk",
            webSocketURL: URL(string: "wss://mercury.example.com")!
        )
        let invalidator = TokenInvalidatorSpy()
        let sessions = MercurySessionQueue([
            FakeMercurySession(frames: [], error: WebexSDKError.webexAPI(statusCode: 401, trackingID: nil, message: "unauthorized")),
            FakeMercurySession(frames: [
                """
                {"id":"event-1","resource":"messages","event":"created","data":{"id":"message-id","roomId":"room-id","personId":"person-id"}}
                """
            ])
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
            tokenInvalidator: {
                await invalidator.invalidate()
            },
            options: WebexRealtimeOptions(retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 1, jitter: 0, maximumDelay: 10)),
            deviceServiceFactory: { _, _, _, _ in
                FakeDeviceService(device: device)
            },
            webSocketFactory: { _ in
                FakeLiveWebSocket()
            },
            sessionFactory: { _, _ in
                sessions.next()
            }
        )
        var stateIterator = source.states.makeAsyncIterator()
        var eventIterator = source.events.makeAsyncIterator()

        source.start()
        let failedState = await firstFailedState(from: &stateIterator)
        let event = await eventIterator.next()
        let invalidationCount = await invalidator.count()

        XCTAssertEqual(failedState, .failed(.webexAPI(statusCode: 401, trackingID: nil, message: "unauthorized")))
        XCTAssertNil(event)
        XCTAssertEqual(invalidationCount, 1)
        XCTAssertEqual(sessions.requestCount(), 1)
    }

    func testLiveSourceInvalidatesStaleDeviceAndRetriesPromptly() async throws {
        let deviceService = InspectableDeviceService(device: WebexMercuryDevice(
            id: "device-id",
            name: "webex-swift-sdk",
            webSocketURL: URL(string: "wss://mercury.example.com")!
        ))
        let sessions = MercurySessionQueue([
            FakeMercurySession(frames: [], error: WebexSDKError.webexAPI(statusCode: 404, trackingID: nil, message: "device not found")),
            FakeMercurySession(frames: [
                """
                {"id":"event-1","resource":"messages","event":"created","data":{"id":"message-id","roomId":"room-id","personId":"person-id"}}
                """
            ])
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
                deviceService
            },
            webSocketFactory: { _ in
                FakeLiveWebSocket()
            },
            sessionFactory: { _, _ in
                sessions.next()
            }
        )
        var eventIterator = source.events.makeAsyncIterator()

        source.start()
        let event = await eventIterator.next()
        let invalidationCount = deviceService.invalidateCount()

        XCTAssertEqual(event?.resourceID, "message-id")
        XCTAssertEqual(invalidationCount, 1)
    }

    func testLiveSourceDoesNotRetryStaleDeviceWhenMaxAttemptsIsOne() async throws {
        let deviceService = InspectableDeviceService(device: WebexMercuryDevice(
            id: "device-id",
            name: "webex-swift-sdk",
            webSocketURL: URL(string: "wss://mercury.example.com")!
        ))
        let sessions = MercurySessionQueue([
            FakeMercurySession(frames: [], error: WebexSDKError.webexAPI(statusCode: 404, trackingID: nil, message: "device not found")),
            FakeMercurySession(frames: [
                """
                {"id":"event-1","resource":"messages","event":"created","data":{"id":"message-id","roomId":"room-id","personId":"person-id"}}
                """
            ])
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
            options: WebexRealtimeOptions(retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 1, jitter: 0, maximumDelay: 10)),
            deviceServiceFactory: { _, _, _, _ in
                deviceService
            },
            webSocketFactory: { _ in
                FakeLiveWebSocket()
            },
            sessionFactory: { _, _ in
                sessions.next()
            }
        )
        var stateIterator = source.states.makeAsyncIterator()
        var eventIterator = source.events.makeAsyncIterator()

        source.start()
        let failedState = await firstFailedState(from: &stateIterator)
        let event = await eventIterator.next()

        XCTAssertEqual(failedState, .failed(.webexAPI(statusCode: 404, trackingID: nil, message: "device not found")))
        XCTAssertNil(event)
        XCTAssertEqual(deviceService.invalidateCount(), 1)
        XCTAssertEqual(sessions.requestCount(), 1)
    }

    func testLiveSourceDoesNotRetryRealtimeSetupDecodeFailure() async throws {
        let error = WebexSDKError.network(
            #"Webex realtime WDM device create response decoding failed (HTTP 201): missing field id; body={"normal":"visible"}"#
        )
        let deviceService = CountingFailingDeviceService(error: error)
        let sleeper = RealtimeSleepRecorder()
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
            options: WebexRealtimeOptions(retryPolicy: RetryPolicy(maxAttempts: 3, baseDelay: 1, jitter: 0, maximumDelay: 10)),
            deviceServiceFactory: { _, _, _, _ in
                deviceService
            },
            sleeper: { delay in
                await sleeper.record(delay)
            }
        )
        var stateIterator = source.states.makeAsyncIterator()

        source.start()
        var states: [WebexRealtimeConnectionState] = []
        while let state = await stateIterator.next() {
            states.append(state)
            if case .failed = state {
                break
            }
        }
        let requestCount = await deviceService.requestCount()
        let delays = await sleeper.delays()

        XCTAssertEqual(states, [.discovering, .registeringDevice, .failed(error)])
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(delays, [])
    }

    func testLiveSourceReconnectsTransientNetworkFailureWithBackoff() async throws {
        let device = WebexMercuryDevice(
            id: "device-id",
            name: "webex-swift-sdk",
            webSocketURL: URL(string: "wss://mercury.example.com")!
        )
        let sleeper = RealtimeSleepRecorder()
        let sessions = MercurySessionQueue([
            FakeMercurySession(frames: [], error: WebexSDKError.network("socket closed")),
            FakeMercurySession(frames: [
                """
                {"id":"event-1","resource":"messages","event":"created","data":{"id":"message-id","roomId":"room-id","personId":"person-id"}}
                """
            ])
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
            options: WebexRealtimeOptions(retryPolicy: RetryPolicy(maxAttempts: 2, baseDelay: 1, jitter: 0, maximumDelay: 10)),
            deviceServiceFactory: { _, _, _, _ in
                FakeDeviceService(device: device)
            },
            webSocketFactory: { _ in
                FakeLiveWebSocket()
            },
            sessionFactory: { _, _ in
                sessions.next()
            },
            sleeper: { delay in
                await sleeper.record(delay)
            }
        )
        var stateIterator = source.states.makeAsyncIterator()
        var eventIterator = source.events.makeAsyncIterator()

        source.start()
        let reconnectingState = await firstReconnectingState(from: &stateIterator)
        let event = await eventIterator.next()
        let delays = await sleeper.delays()

        XCTAssertEqual(reconnectingState, WebexRealtimeConnectionState.reconnecting(attempt: 1, delay: 1))
        XCTAssertEqual(delays, [1])
        XCTAssertEqual(event?.resourceID, "message-id")
    }

    func testLiveSourceAcknowledgesMercuryFrameIDNotResourceID() async throws {
        let device = WebexMercuryDevice(
            id: "device-id",
            name: "webex-swift-sdk",
            webSocketURL: URL(string: "wss://mercury.example.com")!
        )
        let session = FakeMercurySession(frames: [
            """
            {
              "id": "mercury-frame-id",
              "data": {
                "eventType": "conversation.activity",
                "activity": {
                  "id": "activity-id",
                  "verb": "post",
                  "object": {
                    "id": "message-id"
                  },
                  "target": {
                    "id": "room-id"
                  },
                  "actor": {
                    "id": "person-id"
                  }
                }
              }
            }
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
        var eventIterator = source.events.makeAsyncIterator()

        source.start()
        let event = await eventIterator.next()

        XCTAssertEqual(event?.resourceID, "message-id")
        XCTAssertEqual(event?.ackID, "mercury-frame-id")
        XCTAssertEqual(session.acknowledgedMessageIDs(), ["mercury-frame-id"])
    }

    func testLiveSourceReportsDecodedEventAckFailureAndReconnectDiagnostics() async throws {
        let device = WebexMercuryDevice(
            id: "device-id",
            name: "webex-swift-sdk",
            webSocketURL: URL(string: "wss://mercury.example.com")!
        )
        let ackError = WebexSDKError.network("ack rejected")
        let session = FakeMercurySession(frames: [
            """
            {
              "id": "mercury-frame-id",
              "data": {
                "eventType": "conversation.activity",
                "activity": {
                  "id": "activity-id",
                  "verb": "post",
                  "object": {
                    "id": "message-id"
                  },
                  "target": {
                    "id": "room-id"
                  },
                  "actor": {
                    "id": "person-id"
                  }
                }
              }
            }
            """
        ], ackError: ackError)
        let diagnostics = RealtimeDiagnosticRecorder()
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
            options: WebexRealtimeOptions(
                retryPolicy: RetryPolicy(maxAttempts: 2, baseDelay: 1, jitter: 0, maximumDelay: 10),
                diagnosticHandler: { event in
                    diagnostics.record(event)
                }
            ),
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

        source.start()
        let reconnectingState = await firstReconnectingState(from: &stateIterator)
        let metadata = WebexRealtimeEventMetadata(
            id: "mercury-frame-id",
            resource: "messages",
            event: "created",
            knownResource: .messages,
            knownEvent: .created,
            decodeStatus: .known,
            resourceID: "message-id",
            roomID: "room-id",
            actorID: "person-id",
            ackID: "mercury-frame-id",
            sourceEventType: "conversation.activity",
            activityVerb: "post"
        )

        XCTAssertEqual(reconnectingState, WebexRealtimeConnectionState.reconnecting(attempt: 1, delay: 1))
        XCTAssertEqual(diagnostics.events(), [
            .eventDecoded(metadata),
            .ackFailed(metadata, error: ackError),
            .reconnectScheduled(attempt: 1, delay: 1, reason: ackError)
        ])
    }

    func testLiveSourceAcknowledgesFilteredMercuryEvents() async throws {
        let device = WebexMercuryDevice(
            id: "device-id",
            name: "webex-swift-sdk",
            webSocketURL: URL(string: "wss://mercury.example.com")!
        )
        let session = FakeMercurySession(frames: [
            """
            {
              "id": "filtered-frame-id",
              "data": {
                "eventType": "conversation.activity",
                "activity": {
                  "id": "filtered-activity-id",
                  "verb": "post",
                  "object": {
                    "id": "filtered-message-id"
                  },
                  "target": {
                    "id": "room-id"
                  },
                  "actor": {
                    "id": "person-id"
                  }
                }
              }
            }
            """
        ])
        let diagnostics = RealtimeDiagnosticRecorder()
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
            options: WebexRealtimeOptions(
                events: [.deleted],
                diagnosticHandler: { event in
                    diagnostics.record(event)
                }
            ),
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
        var eventIterator = source.events.makeAsyncIterator()

        source.start()
        let event = await eventIterator.next()
        let metadata = WebexRealtimeEventMetadata(
            id: "filtered-frame-id",
            resource: "messages",
            event: "created",
            knownResource: .messages,
            knownEvent: .created,
            decodeStatus: .known,
            resourceID: "filtered-message-id",
            roomID: "room-id",
            actorID: "person-id",
            ackID: "filtered-frame-id",
            sourceEventType: "conversation.activity",
            activityVerb: "post"
        )

        XCTAssertNil(event)
        XCTAssertEqual(session.acknowledgedMessageIDs(), ["filtered-frame-id"])
        XCTAssertEqual(diagnostics.events(), [
            .eventDecoded(metadata),
            .eventFilteredOut(metadata),
            .ackSucceeded(metadata)
        ])
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

    private func eventually(
        timeout: Duration = .seconds(1),
        predicate: @escaping @Sendable () async -> Bool
    ) async throws {
        let start = ContinuousClock.now

        while !(await predicate()) {
            if start.duration(to: ContinuousClock.now) >= timeout {
                XCTFail("Condition was not satisfied before timeout")
                return
            }

            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func firstFailedState(
        from iterator: inout AsyncStream<WebexRealtimeConnectionState>.AsyncIterator
    ) async -> WebexRealtimeConnectionState? {
        while let state = await iterator.next() {
            if case .failed = state {
                return state
            }
        }
        return nil
    }

    private func firstReconnectingState(
        from iterator: inout AsyncStream<WebexRealtimeConnectionState>.AsyncIterator
    ) async -> WebexRealtimeConnectionState? {
        while let state = await iterator.next() {
            if case .reconnecting = state {
                return state
            }
        }
        return nil
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

    func finishEvents() {
        let continuation = lock.withLock {
            let continuation = eventContinuation
            eventContinuation = nil
            return continuation
        }

        continuation?.finish()
    }

    func finishStates() {
        let continuation = lock.withLock {
            let continuation = stateContinuation
            stateContinuation = nil
            return continuation
        }

        continuation?.finish()
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

    func invalidateCachedDevice() async {}
}

private struct FailingDeviceService: WebexMercuryDeviceProviding {
    let error: WebexSDKError

    func device(options: WebexRealtimeOptions) async throws -> WebexMercuryDevice {
        throw error
    }

    func invalidateCachedDevice() async {}
}

private actor CountingFailingDeviceService: WebexMercuryDeviceProviding {
    private let error: WebexSDKError
    private var requests = 0

    init(error: WebexSDKError) {
        self.error = error
    }

    func device(options: WebexRealtimeOptions) async throws -> WebexMercuryDevice {
        requests += 1
        throw error
    }

    func invalidateCachedDevice() async {}

    func requestCount() -> Int {
        requests
    }
}

private final class InspectableDeviceService: WebexMercuryDeviceProviding, @unchecked Sendable {
    private let lock = NSLock()
    private let storedDevice: WebexMercuryDevice
    private var invalidations = 0

    init(device: WebexMercuryDevice) {
        self.storedDevice = device
    }

    func device(options: WebexRealtimeOptions) async throws -> WebexMercuryDevice {
        storedDevice
    }

    func invalidateCachedDevice() async {
        lock.withLock {
            invalidations += 1
        }
    }

    func invalidateCount() -> Int {
        lock.withLock {
            invalidations
        }
    }
}

private final class FakeMercurySession: WebexMercurySession, @unchecked Sendable {
    private let lock = NSLock()
    private let framesToEmit: [String]
    private let error: Error?
    private let ackError: Error?
    private var acknowledged: [String] = []
    private var cancels = 0

    init(frames: [String], error: Error? = nil, ackError: Error? = nil) {
        self.framesToEmit = frames
        self.error = error
        self.ackError = ackError
    }

    func connect() async throws {}

    func authorize() async throws {}

    func frames() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            for frame in framesToEmit {
                continuation.yield(frame)
            }
            continuation.finish(throwing: error)
        }
    }

    func ack(messageID: String) async throws {
        if let ackError {
            throw ackError
        }

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

private final class RealtimeDiagnosticRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [WebexRealtimeDiagnosticEvent] = []

    func record(_ event: WebexRealtimeDiagnosticEvent) {
        lock.withLock {
            storedEvents.append(event)
        }
    }

    func events() -> [WebexRealtimeDiagnosticEvent] {
        lock.withLock {
            storedEvents
        }
    }
}

private final class MercurySessionQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var sessions: [WebexMercurySession]
    private var requests = 0

    init(_ sessions: [WebexMercurySession]) {
        self.sessions = sessions
    }

    func next() -> WebexMercurySession {
        lock.withLock {
            requests += 1
            guard !sessions.isEmpty else {
                return FakeMercurySession(frames: [], error: WebexSDKError.network("Unexpected session request"))
            }

            return sessions.removeFirst()
        }
    }

    func requestCount() -> Int {
        lock.withLock {
            requests
        }
    }
}

private final class BlockingFakeMercurySession: WebexMercurySession, @unchecked Sendable {
    private let lock = NSLock()
    private var cancels = 0
    private var frameContinuation: AsyncThrowingStream<String, Error>.Continuation?

    func connect() async throws {}

    func authorize() async throws {}

    func frames() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            lock.withLock {
                frameContinuation = continuation
            }
        }
    }

    func ack(messageID: String) async throws {}

    func cancel() {
        let continuation = lock.withLock {
            cancels += 1
            return frameContinuation
        }
        continuation?.finish()
    }

    func cancelCount() -> Int {
        lock.withLock {
            cancels
        }
    }
}

private final class GatedMercurySession: WebexMercurySession, @unchecked Sendable {
    private let lock = NSLock()
    private var isAuthorizationFinished = false
    private var frameContinuation: AsyncThrowingStream<String, Error>.Continuation?
    private var cancels = 0

    func connect() async throws {}

    func authorize() async throws {
        while true {
            if lock.withLock({ isAuthorizationFinished }) {
                return
            }

            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func frames() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            lock.withLock {
                frameContinuation = continuation
            }
        }
    }

    func ack(messageID: String) async throws {}

    func cancel() {
        let continuation = lock.withLock {
            cancels += 1
            return frameContinuation
        }
        continuation?.finish()
    }

    func finishAuthorization() {
        lock.withLock {
            isAuthorizationFinished = true
        }
    }
}

private actor RealtimeStateCapture {
    private var capturedState: WebexRealtimeConnectionState?

    func set(_ state: WebexRealtimeConnectionState?) {
        capturedState = state
    }

    func state() -> WebexRealtimeConnectionState? {
        capturedState
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

private final class InspectableFakeWebSocket: WebexRealtimeWebSocket, @unchecked Sendable {
    private let lock = NSLock()
    private var cancels = 0

    func connect() async throws {}
    func send(text: String) async throws {}
    func receiveText() async throws -> String {
        throw CancellationError()
    }
    func cancel() {
        lock.withLock {
            cancels += 1
        }
    }

    func cancelCount() -> Int {
        lock.withLock {
            cancels
        }
    }
}

private actor TokenInvalidatorSpy {
    private var invalidations = 0

    func invalidate() {
        invalidations += 1
    }

    func count() -> Int {
        invalidations
    }
}

private actor RealtimeSleepRecorder {
    private var recordedDelays: [TimeInterval] = []

    func record(_ delay: TimeInterval) {
        recordedDelays.append(delay)
    }

    func delays() -> [TimeInterval] {
        recordedDelays
    }
}

private struct NoopHTTPClient: HTTPClient {
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        throw WebexSDKError.network("Unexpected request")
    }
}
