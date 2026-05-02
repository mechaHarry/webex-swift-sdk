import Foundation

internal struct WebexMercuryDevice: Equatable, Sendable {
    internal let id: String
    internal let name: String
    internal let webSocketURL: URL

    internal init(id: String, name: String, webSocketURL: URL) {
        self.id = id
        self.name = name
        self.webSocketURL = webSocketURL
    }
}

internal actor WebexMercuryDeviceCache {
    private var device: WebexMercuryDevice?

    internal init() {}

    internal func load() -> WebexMercuryDevice? {
        device
    }

    internal func save(_ device: WebexMercuryDevice) {
        self.device = device
    }

    internal func invalidate() {
        device = nil
    }
}

internal struct WebexMercuryDeviceService: Sendable {
    private let u2cURL: URL
    private let httpClient: HTTPClient
    private let accessTokenProvider: @Sendable () async throws -> AccessTokenState
    private let retryPolicy: RetryPolicy
    private let sleeper: @Sendable (TimeInterval) async throws -> Void
    private let cache: WebexMercuryDeviceCache

    internal init(
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

    internal func device(options: WebexRealtimeOptions) async throws -> WebexMercuryDevice {
        if let cached = await cache.load(), cached.name == options.deviceName {
            return cached
        }

        let wdmURL = try await discoverWDMURL()
        let devicesURL = try devicesURL(from: wdmURL)
        let devices = try await sendJSON(
            DeviceListResponse.self,
            request: makeRequest(url: devicesURL),
            operation: "WDM device list"
        )
            .deviceList

        let selectedDevice: WebexMercuryDevice
        if let existing = devices.first(where: { $0.name == options.deviceName }) {
            selectedDevice = try existing.webexMercuryDevice()
        } else {
            let body = DeviceCreateRequest(deviceName: options.deviceName)
            selectedDevice = try await sendJSON(
                DeviceResponse.self,
                request: makeRequest(url: devicesURL, method: "POST", body: JSONEncoder().encode(body)),
                operation: "WDM device create"
            )
            .webexMercuryDevice()
        }

        await cache.save(selectedDevice)
        return selectedDevice
    }

    internal func invalidateCachedDevice() async {
        await cache.invalidate()
    }

    private func discoverWDMURL() async throws -> URL {
        guard var components = URLComponents(url: u2cURL, resolvingAgainstBaseURL: false) else {
            throw WebexSDKError.network("Invalid Webex realtime U2C URL")
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "format", value: "hostmap"))
        components.queryItems = queryItems

        guard let url = components.url else {
            throw WebexSDKError.network("Invalid Webex realtime U2C URL")
        }

        let response = try await sendJSON(
            U2CCatalogResponse.self,
            request: makeRequest(url: url),
            operation: "U2C catalog"
        )
        guard let wdmURL = URL(string: response.serviceLinks.wdm),
              wdmURL.scheme?.lowercased() == "https",
              wdmURL.host != nil else {
            throw WebexSDKError.network("Invalid Webex realtime WDM URL")
        }

        return wdmURL
    }

    private func devicesURL(from wdmURL: URL) throws -> URL {
        guard var components = URLComponents(url: wdmURL, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host != nil else {
            throw WebexSDKError.network("Invalid Webex realtime WDM URL")
        }

        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty {
            components.path = "/devices"
        } else {
            components.path = "/" + path + "/devices"
        }

        guard let url = components.url else {
            throw WebexSDKError.network("Invalid Webex realtime WDM URL")
        }

        return url
    }

    private func makeRequest(url: URL, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func sendJSON<Response: Decodable>(
        _ type: Response.Type,
        request: URLRequest,
        operation: String
    ) async throws -> Response {
        let response = try await send(request, operation: operation)
        do {
            return try JSONDecoder().decode(Response.self, from: response.data)
        } catch {
            throw WebexSDKError.network("Webex realtime response decoding failed: \(Redactor.redactSecrets(error.localizedDescription))")
        }
    }

    private func send(_ originalRequest: URLRequest, operation: String) async throws -> HTTPResponse {
        var attempt = 1
        var lastAccessToken: String?

        while true {
            let accessToken: String
            let response: HTTPResponse
            do {
                let token = try await accessTokenProvider()
                accessToken = token.value
                lastAccessToken = token.value

                var request = originalRequest
                request.setValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")
                response = try await httpClient.send(request)
            } catch let error as CancellationError {
                throw error
            } catch {
                guard shouldRetry(error: error, attempt: attempt) else {
                    throw redactedNetworkError(error, accessToken: lastAccessToken)
                }

                try await sleepBeforeRetry(retryPolicy.delay(forAttempt: attempt))
                attempt += 1
                continue
            }

            if (200..<300).contains(response.response.statusCode) {
                return response
            }

            guard shouldRetry(response: response, attempt: attempt) else {
                throw responseError(for: response, operation: operation, accessToken: accessToken)
            }

            try await sleepBeforeRetry(retryDelay(for: response, attempt: attempt))
            attempt += 1
        }
    }

    private func shouldRetry(response: HTTPResponse, attempt: Int) -> Bool {
        guard attempt < retryPolicy.maxAttempts else {
            return false
        }

        return response.response.statusCode == 429 || response.response.statusCode >= 500
    }

    private func shouldRetry(error: Error, attempt: Int) -> Bool {
        guard attempt < retryPolicy.maxAttempts else {
            return false
        }

        guard let error = error as? WebexSDKError else {
            return true
        }

        if case .network = error {
            return true
        }

        return false
    }

    private func retryDelay(for response: HTTPResponse, attempt: Int) -> TimeInterval {
        retryPolicy.retryAfter(from: response.response) ?? retryPolicy.delay(forAttempt: attempt)
    }

    private func sleepBeforeRetry(_ delay: TimeInterval) async throws {
        do {
            try await sleeper(delay)
        } catch let error as CancellationError {
            throw error
        } catch {
            throw WebexSDKError.network("Retry sleep failed: \(Redactor.redactSecrets(error.localizedDescription))")
        }
    }

    private func responseError(for response: HTTPResponse, operation: String, accessToken: String) -> WebexSDKError {
        if response.response.statusCode == 429 {
            return .rateLimited(retryAfter: retryPolicy.retryAfter(from: response.response))
        }

        return .webexAPI(
            statusCode: response.response.statusCode,
            trackingID: trackingID(from: response.response).map { redact($0, accessToken: accessToken) },
            message: responseMessage(from: response, operation: operation, accessToken: accessToken)
        )
    }

    private func responseMessage(from response: HTTPResponse, operation: String, accessToken: String) -> String {
        let fallback = "Webex realtime \(operation) request returned HTTP \(response.response.statusCode)"
        guard let json = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any],
              let message = json["message"] as? String,
              !message.isEmpty else {
            return fallback
        }

        return "\(fallback): \(redact(message, accessToken: accessToken))"
    }

    private func trackingID(from response: HTTPURLResponse) -> String? {
        for (key, value) in response.allHeaderFields {
            let header = String(describing: key)
            guard header.caseInsensitiveCompare("TrackingID") == .orderedSame ||
                header.caseInsensitiveCompare("trackingId") == .orderedSame ||
                header.caseInsensitiveCompare("X-TrackingID") == .orderedSame else {
                continue
            }

            return String(describing: value)
        }

        return nil
    }

    private func redactedNetworkError(_ error: Error, accessToken: String?) -> WebexSDKError {
        guard let sdkError = error as? WebexSDKError else {
            return .network("Webex realtime request failed: \(redact(error.localizedDescription, accessToken: accessToken))")
        }

        if case .network(let message) = sdkError {
            return .network(redact(message, accessToken: accessToken))
        }

        return sdkError
    }

    private func redact(_ value: String, accessToken: String?) -> String {
        var redacted = Redactor.redactSecrets(value)
        redacted = redactBearerTokens(redacted)
        if let accessToken, !accessToken.isEmpty {
            redacted = redacted.replacingOccurrences(of: accessToken, with: "[redacted]")
        }
        return redacted
    }

    private func redactBearerTokens(_ value: String) -> String {
        let expression = try! NSRegularExpression(
            pattern: #"\bBearer\s+([^\s,;]+)"#,
            options: [.caseInsensitive]
        )
        let mutableValue = NSMutableString(string: value)
        let range = NSRange(location: 0, length: mutableValue.length)
        let matches = expression.matches(in: value, range: range)

        for match in matches.reversed() {
            let tokenRange = match.range(at: 1)
            guard tokenRange.location != NSNotFound else {
                continue
            }

            mutableValue.replaceCharacters(in: tokenRange, with: "[redacted]")
        }

        return mutableValue as String
    }
}

private struct U2CCatalogResponse: Decodable {
    let serviceLinks: ServiceLinks

    struct ServiceLinks: Decodable {
        let wdm: String
    }
}

private struct DeviceListResponse: Decodable {
    let deviceList: [DeviceResponse]

    init(from decoder: Decoder) throws {
        if let devices = try? [DeviceResponse](from: decoder) {
            self.deviceList = devices
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.deviceList = try container.decode([DeviceResponse].self, forKey: .devices)
    }

    private enum CodingKeys: String, CodingKey {
        case devices
    }
}

private struct DeviceResponse: Decodable {
    let id: String
    let name: String
    let webSocketUrl: String

    func webexMercuryDevice() throws -> WebexMercuryDevice {
        guard let url = URL(string: webSocketUrl),
              url.scheme?.lowercased() == "wss",
              url.host != nil else {
            throw WebexSDKError.network("Invalid Webex realtime WebSocket URL")
        }

        return WebexMercuryDevice(id: id, name: name, webSocketURL: url)
    }
}

private struct DeviceCreateRequest: Encodable {
    let deviceName: String
    let deviceType = "DESKTOP"
    let localizedModel = "Swift"
    let model = "webex-swift-sdk"
    let name: String
    let systemName = "webex-swift-sdk"
    let systemVersion = "0.1"

    init(deviceName: String) {
        self.deviceName = deviceName
        self.name = deviceName
    }
}
