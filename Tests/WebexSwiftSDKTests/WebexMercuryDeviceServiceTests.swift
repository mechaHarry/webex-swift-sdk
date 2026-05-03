import XCTest
@testable import WebexSwiftSDK

final class WebexMercuryDeviceServiceTests: XCTestCase {
    func testDiscoversWDMRegistersDeviceAndReusesCachedDevice() async throws {
        let httpClient = MockMercuryDeviceHTTPClient()
        await enqueueLimitedCatalog(on: httpClient, wdmURL: "https://wdm-limited.example.com/wdm/api/v1")
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://u2c-r.wbx2.com/u2c/api/v1/catalog?format=hostmap")!,
            statusCode: 200,
            body: #"{"serviceLinks":{"wdm":"https://wdm.example.com/wdm/api/v1"}}"#
        ))
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://wdm.example.com/wdm/api/v1/devices")!,
            statusCode: 201,
            body: #"{"id":"device-1","name":"desk","webSocketUrl":"wss://mercury.example.com"}"#
        ))
        let service = makeService(httpClient: httpClient)

        let device = try await service.device(options: WebexRealtimeOptions(deviceName: "desk"))
        let cachedDevice = try await service.device(options: WebexRealtimeOptions(deviceName: "desk"))

        XCTAssertEqual(device, WebexMercuryDevice(id: "device-1", name: "desk", webSocketURL: URL(string: "wss://mercury.example.com")!))
        XCTAssertEqual(cachedDevice, device)
        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(requests.map(\.httpMethod), ["GET", "GET", "POST"])
        XCTAssertEqual(requests.map(\.url?.absoluteString), [
            "https://u2c.wbx2.com/u2c/api/v1/limited/catalog?mode=DEFAULT_BY_PROXIMITY&format=hostmap",
            "https://u2c-r.wbx2.com/u2c/api/v1/catalog?format=hostmap",
            "https://wdm.example.com/wdm/api/v1/devices?includeUpstreamServices=all"
        ])
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer realtime-token")
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer realtime-token")
    }

    func testCreatesDeviceWhenNoMatchingDeviceExists() async throws {
        let httpClient = MockMercuryDeviceHTTPClient()
        await enqueueLimitedCatalog(on: httpClient)
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://u2c-r.wbx2.com/u2c/api/v1/catalog?format=hostmap")!,
            statusCode: 200,
            body: #"{"serviceLinks":{"wdm":"https://wdm.example.com/wdm/api/v1"}}"#
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
        XCTAssertEqual(requests[2].url?.absoluteString, "https://wdm.example.com/wdm/api/v1/devices?includeUpstreamServices=all")
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Content-Type"), "application/json;charset=utf-8")
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer realtime-token")
        XCTAssertTrue(requests[2].value(forHTTPHeaderField: "User-Agent")?.hasPrefix("webex-swift-sdk/") == true)
        XCTAssertTrue(requests[2].value(forHTTPHeaderField: "trackingid")?.hasPrefix("webex-swift-sdk_") == true)

        let body = try XCTUnwrap(requests[2].httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json["deviceName"], "desk")
        XCTAssertEqual(json["deviceType"], "WEB")
        XCTAssertEqual(json["localizedModel"], "webex-swift-sdk")
        XCTAssertEqual(json["model"], "webex-swift-sdk")
        XCTAssertEqual(json["name"], "desk")
        XCTAssertEqual(json["systemName"], "WEBEX_SWIFT_SDK")
        XCTAssertEqual(json["systemVersion"], "0.1.0")
    }

    func testRegistersDeviceWithoutListingDevicesFirst() async throws {
        let httpClient = MockMercuryDeviceHTTPClient()
        await enqueueLimitedCatalog(on: httpClient)
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://u2c-r.wbx2.com/u2c/api/v1/catalog?format=hostmap")!,
            statusCode: 200,
            body: #"{"serviceLinks":{"wdm":"https://wdm.example.com/wdm/api/v1"}}"#
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
        XCTAssertEqual(requests.map(\.httpMethod), ["GET", "GET", "POST"])
        XCTAssertEqual(requests.map(\.url?.absoluteString), [
            "https://u2c.wbx2.com/u2c/api/v1/limited/catalog?mode=DEFAULT_BY_PROXIMITY&format=hostmap",
            "https://u2c-r.wbx2.com/u2c/api/v1/catalog?format=hostmap",
            "https://wdm.example.com/wdm/api/v1/devices?includeUpstreamServices=all"
        ])
    }

    func testFallsBackToLimitedCatalogWDMWhenPostauthU2CIsForbidden() async throws {
        let httpClient = MockMercuryDeviceHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://u2c.wbx2.com/u2c/api/v1/limited/catalog?mode=DEFAULT_BY_PROXIMITY&format=hostmap")!,
            statusCode: 200,
            body: #"{"serviceLinks":{"u2c":"https://u2c-r.wbx2.com/u2c/api/v1","wdm":"https://wdm-r.wbx2.com/wdm/api/v1"}}"#
        ))
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://u2c-r.wbx2.com/u2c/api/v1/catalog?format=hostmap")!,
            statusCode: 403,
            headers: ["TrackingID": "ROUTERGW_test"],
            body: #"{}"#
        ))
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://wdm-r.wbx2.com/wdm/api/v1/devices")!,
            statusCode: 201,
            body: #"{"id":"device-2","name":"desk","webSocketUrl":"wss://created.example.com"}"#
        ))
        let service = makeService(httpClient: httpClient, retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, jitter: 0, maximumDelay: 10))

        let device = try await service.device(options: WebexRealtimeOptions(deviceName: "desk"))

        XCTAssertEqual(device.id, "device-2")
        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(requests.map(\.httpMethod), ["GET", "GET", "POST"])
        XCTAssertEqual(requests.map(\.url?.absoluteString), [
            "https://u2c.wbx2.com/u2c/api/v1/limited/catalog?mode=DEFAULT_BY_PROXIMITY&format=hostmap",
            "https://u2c-r.wbx2.com/u2c/api/v1/catalog?format=hostmap",
            "https://wdm-r.wbx2.com/wdm/api/v1/devices?includeUpstreamServices=all"
        ])
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer realtime-token")
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer realtime-token")
    }

    func testRejectsNonWSSWebSocketURL() async throws {
        let httpClient = MockMercuryDeviceHTTPClient()
        await enqueueLimitedCatalog(on: httpClient)
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://u2c-r.wbx2.com/u2c/api/v1/catalog?format=hostmap")!,
            statusCode: 200,
            body: #"{"serviceLinks":{"wdm":"https://wdm.example.com/wdm/api/v1"}}"#
        ))
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://wdm.example.com/wdm/api/v1/devices")!,
            statusCode: 201,
            body: #"{"id":"unsafe","name":"desk","webSocketUrl":"ws://unsafe.example.com/token=secret"}"#
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
        await enqueueLimitedCatalog(on: httpClient)
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://u2c-r.wbx2.com/u2c/api/v1/catalog?format=hostmap")!,
            statusCode: 200,
            body: #"{"serviceLinks":{"wdm":"https://wdm.example.com/wdm/api/v1"}}"#
        ))
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://wdm.example.com/wdm/api/v1/devices")!,
            statusCode: 201,
            body: #"{"id":"device-1","name":"desk-one","webSocketUrl":"wss://one.example.com"}"#
        ))
        await enqueueLimitedCatalog(on: httpClient)
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://u2c-r.wbx2.com/u2c/api/v1/catalog?format=hostmap")!,
            statusCode: 200,
            body: #"{"serviceLinks":{"wdm":"https://wdm.example.com/wdm/api/v1"}}"#
        ))
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://wdm.example.com/wdm/api/v1/devices")!,
            statusCode: 201,
            body: #"{"id":"device-2","name":"desk-two","webSocketUrl":"wss://two.example.com"}"#
        ))
        let service = makeService(httpClient: httpClient)

        let firstDevice = try await service.device(options: WebexRealtimeOptions(deviceName: "desk-one"))
        let secondDevice = try await service.device(options: WebexRealtimeOptions(deviceName: "desk-two"))

        XCTAssertEqual(firstDevice.name, "desk-one")
        XCTAssertEqual(secondDevice, WebexMercuryDevice(id: "device-2", name: "desk-two", webSocketURL: URL(string: "wss://two.example.com")!))
        let requestCount = await httpClient.requestCount()
        XCTAssertEqual(requestCount, 6)
    }

    func testPreservesNonNetworkWebexSDKErrorFromAccessTokenProvider() async throws {
        let accountID = WebexAccountID()
        let expectedError = WebexSDKError.reauthenticationRequired(accountID)
        let httpClient = MockMercuryDeviceHTTPClient()
        await enqueueLimitedCatalog(on: httpClient)
        let service = WebexMercuryDeviceService(
            httpClient: httpClient,
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
            url: URL(string: "https://u2c.wbx2.com/u2c/api/v1/limited/catalog?mode=DEFAULT_BY_PROXIMITY&format=hostmap")!,
            statusCode: 429,
            headers: ["Retry-After": "2"],
            body: #"{"message":"slow down"}"#
        ))
        await enqueueLimitedCatalog(on: httpClient)
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://u2c-r.wbx2.com/u2c/api/v1/catalog?format=hostmap")!,
            statusCode: 200,
            body: #"{"serviceLinks":{"wdm":"https://wdm.example.com/wdm/api/v1"}}"#
        ))
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://wdm.example.com/wdm/api/v1/devices")!,
            statusCode: 201,
            body: #"{"id":"device-1","name":"desk","webSocketUrl":"wss://mercury.example.com"}"#
        ))
        let service = makeService(httpClient: httpClient, sleeper: { delay in
            await sleeper.record(delay)
        })

        _ = try await service.device(options: WebexRealtimeOptions(deviceName: "desk"))

        let delays = await sleeper.delays()
        let requestCount = await httpClient.requestCount()
        XCTAssertEqual(delays, [2])
        XCTAssertEqual(requestCount, 4)
        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(requests.prefix(2).map(\.url?.absoluteString), [
            "https://u2c.wbx2.com/u2c/api/v1/limited/catalog?mode=DEFAULT_BY_PROXIMITY&format=hostmap",
            "https://u2c.wbx2.com/u2c/api/v1/limited/catalog?mode=DEFAULT_BY_PROXIMITY&format=hostmap"
        ])
    }

    func testWDMDeviceCreateFailureIdentifiesOperation() async throws {
        let httpClient = MockMercuryDeviceHTTPClient()
        await enqueueLimitedCatalog(on: httpClient)
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://u2c-r.wbx2.com/u2c/api/v1/catalog?format=hostmap")!,
            statusCode: 200,
            body: #"{"serviceLinks":{"wdm":"https://wdm.example.com/wdm/api/v1"}}"#
        ))
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://wdm.example.com/wdm/api/v1/devices")!,
            statusCode: 403,
            headers: ["TrackingID": "ROUTERGW_test"],
            body: #"{}"#
        ))
        let service = makeService(httpClient: httpClient, retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, jitter: 0, maximumDelay: 10))

        do {
            _ = try await service.device(options: WebexRealtimeOptions(deviceName: "desk"))
            XCTFail("Expected WDM device create error")
        } catch let error as WebexSDKError {
            guard case .webexAPI(let statusCode, let trackingID, let message) = error else {
                XCTFail("Expected webexAPI error, got \(error)")
                return
            }

            XCTAssertEqual(statusCode, 403)
            XCTAssertEqual(trackingID, "ROUTERGW_test")
            XCTAssertTrue(message.contains("WDM device create"), message)
            XCTAssertFalse(message.contains("realtime-token"))
            XCTAssertFalse(message.contains("wdm.example.com"))
        }
    }

    private func enqueueLimitedCatalog(
        on httpClient: MockMercuryDeviceHTTPClient,
        u2cURL: String = "https://u2c-r.wbx2.com/u2c/api/v1",
        wdmURL: String = "https://wdm.example.com/wdm/api/v1"
    ) async {
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://u2c.wbx2.com/u2c/api/v1/limited/catalog?mode=DEFAULT_BY_PROXIMITY&format=hostmap")!,
            statusCode: 200,
            body: #"{"serviceLinks":{"u2c":"\#(u2cURL)","wdm":"\#(wdmURL)"}}"#
        ))
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
