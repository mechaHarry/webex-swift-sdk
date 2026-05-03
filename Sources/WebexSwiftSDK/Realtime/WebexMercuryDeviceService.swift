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
        let body = DeviceCreateRequest(deviceName: options.deviceName)
        let selectedDevice = try await sendJSON(
            DeviceResponse.self,
            request: makeRequest(url: devicesURL, method: "POST", body: JSONEncoder().encode(body)),
            operation: "WDM device create"
        )
        .webexMercuryDevice(deviceName: options.deviceName)

        await cache.save(selectedDevice)
        return selectedDevice
    }

    internal func invalidateCachedDevice() async {
        await cache.invalidate()
    }

    private func discoverWDMURL() async throws -> URL {
        let limitedCatalog = try await sendJSON(
            U2CCatalogResponse.self,
            request: makeRequest(url: limitedCatalogURL()),
            operation: "U2C limited catalog",
            requiresAuthorization: false
        )

        do {
            let postauthCatalog = try await sendJSON(
                U2CCatalogResponse.self,
                request: makeRequest(url: postauthCatalogURL(from: limitedCatalog)),
                operation: "U2C catalog"
            )
            return try serviceURL(named: "wdm", in: postauthCatalog, errorName: "WDM")
        } catch {
            guard shouldUseLimitedCatalog(after: error) else {
                throw error
            }

            return try serviceURL(named: "wdm", in: limitedCatalog, errorName: "WDM")
        }
    }

    private func limitedCatalogURL() throws -> URL {
        try catalogURL(
            from: u2cURL,
            path: "limited/catalog",
            queryItems: [
                URLQueryItem(name: "mode", value: "DEFAULT_BY_PROXIMITY"),
                URLQueryItem(name: "format", value: "hostmap")
            ]
        )
    }

    private func postauthCatalogURL(from limitedCatalog: U2CCatalogResponse) throws -> URL {
        let baseURL = try serviceURL(named: "u2c", in: limitedCatalog, errorName: "U2C")
        return try catalogURL(
            from: baseURL,
            path: "catalog",
            queryItems: [URLQueryItem(name: "format", value: "hostmap")]
        )
    }

    private func catalogURL(from baseURL: URL, path catalogPath: String, queryItems: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host != nil else {
            throw WebexSDKError.network("Invalid Webex realtime U2C URL")
        }

        let basePath = components.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .removingSuffix("limited/catalog")
            .removingSuffix("catalog")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let pathParts = [basePath, catalogPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))]
            .filter { !$0.isEmpty }
        components.path = "/" + pathParts.joined(separator: "/")
        components.queryItems = queryItems

        guard let url = components.url else {
            throw WebexSDKError.network("Invalid Webex realtime U2C URL")
        }

        return url
    }

    private func serviceURL(named name: String, in catalog: U2CCatalogResponse, errorName: String) throws -> URL {
        guard let value = catalog.serviceLinks[name],
              let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            throw WebexSDKError.network("Invalid Webex realtime \(errorName) URL")
        }

        return url
    }

    private func shouldUseLimitedCatalog(after error: Error) -> Bool {
        guard let error = error as? WebexSDKError,
              case .webexAPI(let statusCode, _, _) = error else {
            return false
        }

        return statusCode == 401 || statusCode == 403
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
        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "includeUpstreamServices", value: "all"))
        components.queryItems = queryItems

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
        request.setValue("webex-swift-sdk/0.1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("webex-swift-sdk_\(UUID().uuidString)", forHTTPHeaderField: "trackingid")
        if body != nil {
            request.setValue("application/json;charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func sendJSON<Response: Decodable>(
        _ type: Response.Type,
        request: URLRequest,
        operation: String,
        requiresAuthorization: Bool = true
    ) async throws -> Response {
        let response = try await send(
            request,
            operation: operation,
            requiresAuthorization: requiresAuthorization
        )
        do {
            return try JSONDecoder().decode(Response.self, from: response.data)
        } catch {
            throw WebexSDKError.network(decodingErrorMessage(error, response: response, operation: operation))
        }
    }

    private func send(
        _ originalRequest: URLRequest,
        operation: String,
        requiresAuthorization: Bool
    ) async throws -> HTTPResponse {
        var attempt = 1
        var lastAccessToken: String?

        while true {
            let accessToken: String?
            let response: HTTPResponse
            do {
                var request = originalRequest
                if requiresAuthorization {
                    let token = try await accessTokenProvider()
                    accessToken = token.value
                    lastAccessToken = token.value
                    request.setValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")
                } else {
                    accessToken = nil
                }
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

    private func responseError(for response: HTTPResponse, operation: String, accessToken: String?) -> WebexSDKError {
        if response.response.statusCode == 429 {
            return .rateLimited(retryAfter: retryPolicy.retryAfter(from: response.response))
        }

        return .webexAPI(
            statusCode: response.response.statusCode,
            trackingID: trackingID(from: response.response).map { redact($0, accessToken: accessToken) },
            message: responseMessage(from: response, operation: operation, accessToken: accessToken)
        )
    }

    private func responseMessage(from response: HTTPResponse, operation: String, accessToken: String?) -> String {
        let fallback = "Webex realtime \(operation) request returned HTTP \(response.response.statusCode)"
        guard let json = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any],
              let message = json["message"] as? String,
              !message.isEmpty else {
            return fallback
        }

        return "\(fallback): \(redact(message, accessToken: accessToken))"
    }

    private func decodingErrorMessage(_ error: Error, response: HTTPResponse, operation: String) -> String {
        let statusCode = response.response.statusCode
        return "Webex realtime \(operation) response decoding failed (HTTP \(statusCode)): " +
            "\(decodingErrorDetail(error)); body=\(responseBodyPreview(response.data))"
    }

    private func decodingErrorDetail(_ error: Error) -> String {
        switch error {
        case DecodingError.keyNotFound(let key, let context):
            return "missing field \(codingPathDescription(context.codingPath + [key]))"
        case DecodingError.typeMismatch(let type, let context):
            return "type mismatch at \(codingPathDescription(context.codingPath)): expected \(type); " +
                redact(context.debugDescription, accessToken: nil)
        case DecodingError.valueNotFound(let type, let context):
            return "missing value at \(codingPathDescription(context.codingPath)): expected \(type); " +
                redact(context.debugDescription, accessToken: nil)
        case DecodingError.dataCorrupted(let context):
            return "data corrupted at \(codingPathDescription(context.codingPath)): " +
                redact(context.debugDescription, accessToken: nil)
        default:
            return redact(error.localizedDescription, accessToken: nil)
        }
    }

    private func codingPathDescription(_ codingPath: [CodingKey]) -> String {
        let value = codingPath
            .map(\.stringValue)
            .filter { !$0.isEmpty }
            .joined(separator: ".")
        return value.isEmpty ? "(root)" : value
    }

    private func responseBodyPreview(_ data: Data) -> String {
        guard !data.isEmpty else {
            return "<empty>"
        }

        guard let value = String(data: data, encoding: .utf8) else {
            return "<\(data.count) non-UTF8 bytes>"
        }

        return redact(value, accessToken: nil).singleLinePreview(limit: 2_000)
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
        redacted = redactWebSocketURLs(redacted)
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

    private func redactWebSocketURLs(_ value: String) -> String {
        let expression = try! NSRegularExpression(
            pattern: #"\bwss://[^\s"'<>)]+"#,
            options: [.caseInsensitive]
        )
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.stringByReplacingMatches(
            in: value,
            options: [],
            range: range,
            withTemplate: "wss://[redacted]"
        )
    }
}

private struct U2CCatalogResponse: Decodable {
    let serviceLinks: [String: String]
}

private struct DeviceResponse: Decodable {
    let id: String?
    let url: String?
    let name: String?
    let webSocketUrl: String

    func webexMercuryDevice(deviceName: String) throws -> WebexMercuryDevice {
        guard let id = resolvedID else {
            throw WebexSDKError.network("Invalid Webex realtime WDM device response: missing device id")
        }

        guard let url = URL(string: webSocketUrl),
              url.scheme?.lowercased() == "wss",
              url.host != nil else {
            throw WebexSDKError.network("Invalid Webex realtime WebSocket URL")
        }

        return WebexMercuryDevice(id: id, name: resolvedName(fallback: deviceName), webSocketURL: url)
    }

    private var resolvedID: String? {
        if let id, !id.isEmpty {
            return id
        }

        guard let url,
              let deviceURL = URL(string: url) else {
            return nil
        }

        let id = deviceURL.lastPathComponent
        return id.isEmpty ? nil : id
    }

    private func resolvedName(fallback: String) -> String {
        guard let name, !name.isEmpty else {
            return fallback
        }

        return name
    }
}

private struct DeviceCreateRequest: Encodable {
    let deviceName: String
    let deviceType = "WEB"
    let localizedModel = "webex-swift-sdk"
    let model = "webex-swift-sdk"
    let name: String
    let systemName = "WEBEX_SWIFT_SDK"
    let systemVersion = "0.1.0"

    init(deviceName: String) {
        self.deviceName = deviceName
        self.name = deviceName
    }
}

private extension String {
    func removingSuffix(_ suffix: String) -> String {
        guard hasSuffix(suffix) else {
            return self
        }

        return String(dropLast(suffix.count))
    }

    func singleLinePreview(limit: Int) -> String {
        let compact = replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        guard compact.count > limit else {
            return compact
        }

        return String(compact.prefix(limit)) + "...<truncated>"
    }
}
