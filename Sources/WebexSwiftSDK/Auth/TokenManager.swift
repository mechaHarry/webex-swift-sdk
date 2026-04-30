import Foundation

public actor TokenManager {
    public let accountID: WebexAccountID

    private let configuration: WebexIntegrationConfiguration
    private let tokenStore: WebexTokenStore
    private let httpClient: HTTPClient
    private let refreshLeeway: TimeInterval
    private let clock: @Sendable () -> Date
    private let retryPolicy: RetryPolicy
    private let sleeper: @Sendable (TimeInterval) async throws -> Void

    private var accessToken: AccessTokenState?
    private var refreshTask: Task<AccessTokenState, Error>?

    public init(
        accountID: WebexAccountID,
        configuration: WebexIntegrationConfiguration,
        tokenStore: WebexTokenStore,
        httpClient: HTTPClient,
        initialAccessToken: AccessTokenState? = nil,
        refreshLeeway: TimeInterval = 60,
        clock: @escaping @Sendable () -> Date = { Date() },
        retryPolicy: RetryPolicy = RetryPolicy(),
        sleeper: @escaping @Sendable (TimeInterval) async throws -> Void = { delay in
            guard delay > 0, delay.isFinite else {
                return
            }

            let nanoseconds = delay * 1_000_000_000
            guard nanoseconds.isFinite, nanoseconds < Double(UInt64.max) else {
                return
            }

            let sleepNanoseconds = UInt64(nanoseconds.rounded(.down))
            try await Task.sleep(nanoseconds: sleepNanoseconds)
        }
    ) {
        self.accountID = accountID
        self.configuration = configuration
        self.tokenStore = tokenStore
        self.httpClient = httpClient
        self.refreshLeeway = refreshLeeway
        self.clock = clock
        self.retryPolicy = retryPolicy
        self.sleeper = sleeper
        self.accessToken = initialAccessToken
    }

    public func validAccessToken() async throws -> AccessTokenState {
        if let accessToken, isFresh(accessToken, now: clock()) {
            return accessToken
        }

        if let refreshTask {
            return try await refreshTask.value
        }

        let accountID = accountID
        let configuration = configuration
        let tokenStore = tokenStore
        let httpClient = httpClient
        let clock = clock
        let retryPolicy = retryPolicy
        let sleeper = sleeper

        let task = Task {
            try await Self.refreshAccessToken(
                accountID: accountID,
                configuration: configuration,
                tokenStore: tokenStore,
                httpClient: httpClient,
                clock: clock,
                retryPolicy: retryPolicy,
                sleeper: sleeper
            )
        }
        refreshTask = task

        do {
            let token = try await task.value
            accessToken = token
            refreshTask = nil
            return token
        } catch {
            refreshTask = nil
            throw error
        }
    }

    public func invalidateAccessToken() {
        accessToken = nil
    }

    func setAccessTokenForTesting(_ accessToken: AccessTokenState?) {
        self.accessToken = accessToken
    }

    private func isFresh(_ accessToken: AccessTokenState, now: Date) -> Bool {
        accessToken.expiresAt.timeIntervalSince(now) > refreshLeeway
    }

    private static func refreshAccessToken(
        accountID: WebexAccountID,
        configuration: WebexIntegrationConfiguration,
        tokenStore: WebexTokenStore,
        httpClient: HTTPClient,
        clock: @Sendable () -> Date,
        retryPolicy: RetryPolicy,
        sleeper: @Sendable (TimeInterval) async throws -> Void
    ) async throws -> AccessTokenState {
        let now = clock()
        guard let tokenRecord = try await tokenStore.loadTokenRecord(for: accountID) else {
            throw WebexSDKError.missingRefreshToken(accountID)
        }

        guard tokenRecord.refreshTokenExpiresAt > now else {
            throw WebexSDKError.reauthenticationRequired(accountID)
        }

        let request = try WebexTokenEndpoint.refreshTokenRequest(
            configuration: configuration,
            refreshToken: tokenRecord.refreshToken
        )

        for attempt in 1...retryPolicy.maxAttempts {
            var response: HTTPResponse?
            do {
                response = try await httpClient.send(request)
            } catch let error as WebexSDKError {
                guard shouldRetry(error: error, attempt: attempt, retryPolicy: retryPolicy) else {
                    throw redactedNetworkError(error)
                }

                try await sleeper(retryPolicy.delay(forAttempt: attempt))
            } catch {
                guard shouldRetry(error: error, attempt: attempt, retryPolicy: retryPolicy) else {
                    throw redactedNetworkError(error)
                }

                try await sleeper(retryPolicy.delay(forAttempt: attempt))
            }

            guard let response else {
                continue
            }

            if (200..<300).contains(response.response.statusCode) {
                return try await handleSuccessfulRefreshResponse(
                    response,
                    accountID: accountID,
                    tokenStore: tokenStore,
                    clock: clock
                )
            }

            if shouldRetry(response: response, attempt: attempt, retryPolicy: retryPolicy) {
                try await sleeper(retryDelay(for: response, attempt: attempt, retryPolicy: retryPolicy))
                continue
            }

            if response.response.statusCode == 429 {
                throw WebexSDKError.rateLimited(retryAfter: retryPolicy.retryAfter(from: response.response))
            }

            throw tokenExchangeFailed(for: response)
        }

        throw WebexSDKError.network("Token refresh exhausted retry attempts")
    }

    private static func handleSuccessfulRefreshResponse(
        _ response: HTTPResponse,
        accountID: WebexAccountID,
        tokenStore: WebexTokenStore,
        clock: @Sendable () -> Date
    ) async throws -> AccessTokenState {
        let tokenResponse: WebexTokenResponse
        do {
            tokenResponse = try JSONDecoder().decode(WebexTokenResponse.self, from: response.data)
        } catch {
            throw WebexSDKError.tokenExchangeFailed(
                statusCode: response.response.statusCode,
                message: "Unable to decode token response",
                trackingID: trackingID(from: response.response)
            )
        }

        let receivedAt = clock()
        try await tokenStore.saveTokenRecord(
            tokenResponse.tokenRecord(receivedAt: receivedAt),
            for: accountID
        )
        return tokenResponse.accessTokenState(receivedAt: receivedAt)
    }

    private static func shouldRetry(
        response: HTTPResponse,
        attempt: Int,
        retryPolicy: RetryPolicy
    ) -> Bool {
        (response.response.statusCode >= 500 || response.response.statusCode == 429) &&
            attempt < retryPolicy.maxAttempts
    }

    private static func shouldRetry(
        error: Error,
        attempt: Int,
        retryPolicy: RetryPolicy
    ) -> Bool {
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

    private static func retryDelay(
        for response: HTTPResponse,
        attempt: Int,
        retryPolicy: RetryPolicy
    ) -> TimeInterval {
        retryPolicy.retryAfter(from: response.response) ?? retryPolicy.delay(forAttempt: attempt)
    }

    private static func tokenExchangeFailed(for response: HTTPResponse) -> WebexSDKError {
        return WebexSDKError.tokenExchangeFailed(
            statusCode: response.response.statusCode,
            message: "Token endpoint returned HTTP \(response.response.statusCode)",
            trackingID: trackingID(from: response.response)
        )
    }

    private static func trackingID(from response: HTTPURLResponse) -> String? {
        for (key, value) in response.allHeaderFields {
            let header = String(describing: key)
            guard header.caseInsensitiveCompare("TrackingID") == .orderedSame ||
                header.caseInsensitiveCompare("X-TrackingID") == .orderedSame else {
                continue
            }

            return String(describing: value)
        }

        return nil
    }

    private static func redactedNetworkError(_ error: Error) -> WebexSDKError {
        if case .network(let message) = error as? WebexSDKError {
            return .network(Redactor.redactSecrets(message))
        }

        return .network("Token refresh request failed: \(Redactor.redactSecrets(error.localizedDescription))")
    }
}
