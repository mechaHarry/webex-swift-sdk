import Foundation

public struct WebexRequest: Sendable {
    public let method: String
    public let path: String
    public let queryItems: [URLQueryItem]
    public let headers: [String: String]
    public let body: Data?

    public init(
        method: String = "GET",
        path: String,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.method = method
        self.path = path
        self.queryItems = queryItems
        self.headers = headers
        self.body = body
    }
}

public struct WebexTransport: Sendable {
    private let baseURL: URL
    private let httpClient: HTTPClient
    private let accessTokenProvider: @Sendable () async throws -> AccessTokenState
    private let tokenInvalidator: @Sendable () async -> Void
    private let retryPolicy: RetryPolicy
    private let sleeper: @Sendable (TimeInterval) async throws -> Void

    public init(
        baseURL: URL = URL(string: "https://webexapis.com")!,
        httpClient: HTTPClient = URLSessionHTTPClient(),
        accessTokenProvider: @escaping @Sendable () async throws -> AccessTokenState,
        tokenInvalidator: @escaping @Sendable () async -> Void = {},
        retryPolicy: RetryPolicy = RetryPolicy(),
        sleeper: @escaping @Sendable (TimeInterval) async throws -> Void = { delay in
            guard delay > 0, delay.isFinite else {
                return
            }

            let nanoseconds = delay * 1_000_000_000
            guard nanoseconds.isFinite, nanoseconds < Double(UInt64.max) else {
                return
            }

            try await Task.sleep(nanoseconds: UInt64(nanoseconds.rounded(.down)))
        }
    ) {
        self.baseURL = baseURL
        self.httpClient = httpClient
        self.accessTokenProvider = accessTokenProvider
        self.tokenInvalidator = tokenInvalidator
        self.retryPolicy = retryPolicy
        self.sleeper = sleeper
    }

    public func send(_ webexRequest: WebexRequest) async throws -> Data {
        let url = try buildURL(for: webexRequest)
        var didRetryUnauthorized = false
        var lastAccessToken: String?

        var attempt = 1
        while true {
            let response: HTTPResponse
            let accessToken: String

            do {
                let token = try await accessTokenProvider()
                lastAccessToken = token.value
                accessToken = token.value
                let request = buildURLRequest(for: webexRequest, url: url, accessToken: token.value)
                response = try await httpClient.send(request)
            } catch let error as CancellationError {
                throw error
            } catch let error as WebexSDKError {
                guard shouldRetry(error: error, attempt: attempt) else {
                    throw redactedNetworkError(error, accessToken: lastAccessToken)
                }

                try await sleepBeforeRetry(retryPolicy.delay(forAttempt: attempt))
                attempt += 1
                continue
            } catch {
                if error is CancellationError {
                    throw error
                }

                guard shouldRetry(error: error, attempt: attempt) else {
                    throw redactedNetworkError(error, accessToken: lastAccessToken)
                }

                try await sleepBeforeRetry(retryPolicy.delay(forAttempt: attempt))
                attempt += 1
                continue
            }

            if (200..<300).contains(response.response.statusCode) {
                return response.data
            }

            if response.response.statusCode == 401, !didRetryUnauthorized {
                didRetryUnauthorized = true
                await tokenInvalidator()
                continue
            }

            if shouldRetry(response: response, attempt: attempt) {
                try await sleepBeforeRetry(retryDelay(for: response, attempt: attempt))
                attempt += 1
                continue
            }

            throw responseError(for: response, accessToken: accessToken)
        }
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

    private func buildURL(for request: WebexRequest) throws -> URL {
        guard !request.path.hasPrefix("//"),
              !request.path.localizedCaseInsensitiveContains("://") else {
            throw WebexSDKError.network("Invalid Webex API request path")
        }

        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              components.scheme != nil,
              components.host != nil else {
            throw WebexSDKError.network("Invalid Webex API base URL")
        }

        components.path = normalizedPath(request.path)
        if !request.queryItems.isEmpty {
            components.queryItems = request.queryItems
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }

        guard let url = components.url else {
            throw WebexSDKError.network("Invalid Webex API URL")
        }

        return url
    }

    private func normalizedPath(_ path: String) -> String {
        if path.isEmpty {
            return "/"
        }

        if path.hasPrefix("/") {
            return path
        }

        return "/" + path
    }

    private func buildURLRequest(
        for webexRequest: WebexRequest,
        url: URL,
        accessToken: String
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = webexRequest.method
        request.httpBody = webexRequest.body
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        for (name, value) in webexRequest.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }

        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        if webexRequest.body != nil, request.value(forHTTPHeaderField: "Content-Type") == nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    private func shouldRetry(response: HTTPResponse, attempt: Int) -> Bool {
        (response.response.statusCode == 429 || response.response.statusCode >= 500) &&
            attempt < retryPolicy.maxAttempts
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

    private func responseError(for response: HTTPResponse, accessToken: String) -> WebexSDKError {
        if response.response.statusCode == 429 {
            return .rateLimited(retryAfter: retryPolicy.retryAfter(from: response.response))
        }

        return .webexAPI(
            statusCode: response.response.statusCode,
            trackingID: trackingID(from: response.response),
            message: responseMessage(from: response, accessToken: accessToken)
        )
    }

    private func responseMessage(from response: HTTPResponse, accessToken: String) -> String {
        let fallback = "Webex API returned HTTP \(response.response.statusCode)"
        guard let json = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any],
              let message = json["message"] as? String,
              !message.isEmpty else {
            return fallback
        }

        return redact(message, accessToken: accessToken)
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

    private func redactedNetworkError(_ error: WebexSDKError, accessToken: String?) -> WebexSDKError {
        if case .network(let message) = error {
            return .network(redact(message, accessToken: accessToken))
        }

        return error
    }

    private func redactedNetworkError(_ error: Error, accessToken: String?) -> WebexSDKError {
        .network("Webex request failed: \(redact(error.localizedDescription, accessToken: accessToken))")
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
