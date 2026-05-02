import XCTest
@testable import WebexSwiftSDK

final class WebexMercuryDeviceServiceTests: XCTestCase {
    func testDiscoversWDMAndReusesMatchingDevice() async throws {
        let httpClient = MockMercuryDeviceHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://u2c.wbx2.com/u2c/api/v1/catalog?format=hostmap")!,
            statusCode: 200,
            body: #"{"serviceLinks":{"wdm":"https://wdm.example.com/wdm/api/v1"}}"#
        ))
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://wdm.example.com/wdm/api/v1/devices")!,
            statusCode: 200,
            body: #"{"devices":[{"id":"other","name":"other","webSocketUrl":"wss://other.example.com"},{"id":"device-1","name":"desk","webSocketUrl":"wss://mercury.example.com"}]}"#
        ))
        let service = makeService(httpClient: httpClient)

        let device = try await service.device(options: WebexRealtimeOptions(deviceName: "desk"))

        XCTAssertEqual(device, WebexMercuryDevice(id: "device-1", name: "desk", webSocketURL: URL(string: "wss://mercury.example.com")!))
        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(requests.map(\.url?.absoluteString), [
            "https://u2c.wbx2.com/u2c/api/v1/catalog?format=hostmap",
            "https://wdm.example.com/wdm/api/v1/devices"
        ])
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer realtime-token")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer realtime-token")
    }

    func testCreatesDeviceWhenNoMatchingDeviceExists() async throws {
        let httpClient = MockMercuryDeviceHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://u2c.wbx2.com/u2c/api/v1/catalog?format=hostmap")!,
            statusCode: 200,
            body: #"{"serviceLinks":{"wdm":"https://wdm.example.com/wdm/api/v1"}}"#
        ))
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://wdm.example.com/wdm/api/v1/devices")!,
            statusCode: 200,
            body: #"{"devices":[]}"#
        ))
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://wdm.example.com/wdm/api/v1/devices")!,
            statusCode: 201,
            body: #"{"id":"device-2","name":"desk","webSocketUrl":"wss://created.example.com"}"#
        ))
        let service = makeService(httpClient: httpClient)

        let device = try await service.device(options: WebexRealtimeOptions(deviceName: "desk"))

        XCTAssertEqual(device.id, "device-2")
        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[2].httpMethod, "POST")
        XCTAssertEqual(requests[2].url?.absoluteString, "https://wdm.example.com/wdm/api/v1/devices")
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(requests[2].httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json["deviceName"], "desk")
        XCTAssertEqual(json["deviceType"], "DESKTOP")
        XCTAssertEqual(json["localizedModel"], "Swift")
        XCTAssertEqual(json["model"], "webex-swift-sdk")
        XCTAssertEqual(json["name"], "desk")
        XCTAssertEqual(json["systemName"], "webex-swift-sdk")
        XCTAssertEqual(json["systemVersion"], "0.1")
    }

    func testRejectsNonWSSWebSocketURL() async throws {
        let httpClient = MockMercuryDeviceHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://u2c.wbx2.com/u2c/api/v1/catalog?format=hostmap")!,
            statusCode: 200,
            body: #"{"serviceLinks":{"wdm":"https://wdm.example.com/wdm/api/v1"}}"#
        ))
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://wdm.example.com/wdm/api/v1/devices")!,
            statusCode: 200,
            body: #"{"devices":[{"id":"unsafe","name":"desk","webSocketUrl":"ws://unsafe.example.com/token=secret"}]}"#
        ))
        let service = makeService(httpClient: httpClient)

        do {
            _ = try await service.device(options: WebexRealtimeOptions(deviceName: "desk"))
            XCTFail("Expected invalid WebSocket URL error")
        } catch {
            let description = String(describing: error)
            XCTAssertTrue(description.contains("Invalid Webex realtime WebSocket URL"))
            XCTAssertFalse(description.contains("ws://unsafe.example.com"))
            XCTAssertFalse(description.contains("token=secret"))
        }
    }

    func testInvalidatesCachedDeviceForStaleHandshake() async {
        let cache = WebexMercuryDeviceCache()
        let device = WebexMercuryDevice(id: "device-1", name: "desk", webSocketURL: URL(string: "wss://mercury.example.com")!)

        await cache.save(device)
        let savedDevice = await cache.load()
        XCTAssertEqual(savedDevice, device)

        await cache.invalidate()
        let invalidatedDevice = await cache.load()
        XCTAssertNil(invalidatedDevice)
    }

    func testCachedDeviceIsNotReusedForDifferentDeviceName() async throws {
        let httpClient = MockMercuryDeviceHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://u2c.wbx2.com/u2c/api/v1/catalog?format=hostmap")!,
            statusCode: 200,
            body: #"{"serviceLinks":{"wdm":"https://wdm.example.com/wdm/api/v1"}}"#
        ))
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://wdm.example.com/wdm/api/v1/devices")!,
            statusCode: 200,
            body: #"{"devices":[{"id":"device-1","name":"desk-one","webSocketUrl":"wss://one.example.com"}]}"#
        ))
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://u2c.wbx2.com/u2c/api/v1/catalog?format=hostmap")!,
            statusCode: 200,
            body: #"{"serviceLinks":{"wdm":"https://wdm.example.com/wdm/api/v1"}}"#
        ))
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://wdm.example.com/wdm/api/v1/devices")!,
            statusCode: 200,
            body: #"{"devices":[{"id":"device-2","name":"desk-two","webSocketUrl":"wss://two.example.com"}]}"#
        ))
        let service = makeService(httpClient: httpClient)

        let firstDevice = try await service.device(options: WebexRealtimeOptions(deviceName: "desk-one"))
        let secondDevice = try await service.device(options: WebexRealtimeOptions(deviceName: "desk-two"))

        XCTAssertEqual(firstDevice.name, "desk-one")
        XCTAssertEqual(secondDevice, WebexMercuryDevice(id: "device-2", name: "desk-two", webSocketURL: URL(string: "wss://two.example.com")!))
        let requestCount = await httpClient.requestCount()
        XCTAssertEqual(requestCount, 4)
    }

    func testPreservesNonNetworkWebexSDKErrorFromAccessTokenProvider() async throws {
        let accountID = WebexAccountID()
        let expectedError = WebexSDKError.reauthenticationRequired(accountID)
        let service = WebexMercuryDeviceService(
            httpClient: MockMercuryDeviceHTTPClient(),
            accessTokenProvider: {
                throw expectedError
            },
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, jitter: 0, maximumDelay: 10),
            sleeper: { _ in }
        )

        do {
            _ = try await service.device(options: WebexRealtimeOptions(deviceName: "desk"))
            XCTFail("Expected reauthenticationRequired error")
        } catch let error as WebexSDKError {
            XCTAssertEqual(error, expectedError)
        } catch {
            XCTFail("Expected WebexSDKError, got \(error)")
        }
    }

    func testRetriesRateLimitWithRetryAfterThenSucceeds() async throws {
        let httpClient = MockMercuryDeviceHTTPClient()
        let sleeper = SleepRecorder()
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://u2c.wbx2.com/u2c/api/v1/catalog?format=hostmap")!,
            statusCode: 429,
            headers: ["Retry-After": "2"],
            body: #"{"message":"slow down"}"#
        ))
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://u2c.wbx2.com/u2c/api/v1/catalog?format=hostmap")!,
            statusCode: 200,
            body: #"{"serviceLinks":{"wdm":"https://wdm.example.com/wdm/api/v1"}}"#
        ))
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://wdm.example.com/wdm/api/v1/devices")!,
            statusCode: 200,
            body: #"{"devices":[{"id":"device-1","name":"desk","webSocketUrl":"wss://mercury.example.com"}]}"#
        ))
        let service = makeService(httpClient: httpClient, sleeper: { delay in
            await sleeper.record(delay)
        })

        _ = try await service.device(options: WebexRealtimeOptions(deviceName: "desk"))

        let delays = await sleeper.delays()
        let requestCount = await httpClient.requestCount()
        XCTAssertEqual(delays, [2])
        XCTAssertEqual(requestCount, 3)
        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(requests.prefix(2).map(\.url?.absoluteString), [
            "https://u2c.wbx2.com/u2c/api/v1/catalog?format=hostmap",
            "https://u2c.wbx2.com/u2c/api/v1/catalog?format=hostmap"
        ])
    }

    private func makeService(
        httpClient: HTTPClient,
        retryPolicy: RetryPolicy = RetryPolicy(maxAttempts: 3, baseDelay: 0, jitter: 0, maximumDelay: 10),
        sleeper: @escaping @Sendable (TimeInterval) async throws -> Void = { _ in }
    ) -> WebexMercuryDeviceService {
        WebexMercuryDeviceService(
            httpClient: httpClient,
            accessTokenProvider: {
                AccessTokenState(
                    value: "realtime-token",
                    expiresAt: Date(timeIntervalSince1970: 1_000),
                    tokenType: "Bearer"
                )
            },
            retryPolicy: retryPolicy,
            sleeper: sleeper
        )
    }

    private func httpResponse(
        url: URL,
        statusCode: Int,
        headers: [String: String] = [:],
        body: String
    ) -> HTTPResponse {
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        return HTTPResponse(data: Data(body.utf8), response: response)
    }
}

private actor MockMercuryDeviceHTTPClient: HTTPClient {
    private enum Result: Sendable {
        case response(HTTPResponse)
        case error(WebexSDKError)
    }

    private var results: [Result] = []
    private var requests: [URLRequest] = []

    func enqueue(response: HTTPResponse) {
        results.append(.response(response))
    }

    func enqueue(error: WebexSDKError) {
        results.append(.error(error))
    }

    func requestCount() -> Int {
        requests.count
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard !results.isEmpty else {
            throw WebexSDKError.network("Unexpected Mercury device request")
        }

        switch results.removeFirst() {
        case .response(let response):
            return response
        case .error(let error):
            throw error
        }
    }
}

private actor SleepRecorder {
    private var recordedDelays: [TimeInterval] = []

    func record(_ delay: TimeInterval) {
        recordedDelays.append(delay)
    }

    func delays() -> [TimeInterval] {
        recordedDelays
    }
}
