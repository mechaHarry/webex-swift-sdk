import XCTest
@testable import WebexSwiftSDK

final class TokenManagerTests: XCTestCase {
    func testFreshMemoryTokenSkipsRefresh() async throws {
        let accountID = WebexAccountID()
        let store = InMemoryWebexStore()
        let httpClient = MockHTTPClient()
        let manager = makeTokenManager(
            accountID: accountID,
            store: store,
            httpClient: httpClient,
            now: Date(timeIntervalSince1970: 100)
        )
        let token = AccessTokenState(
            value: "memory-access",
            expiresAt: Date(timeIntervalSince1970: 1_000),
            tokenType: "Bearer"
        )
        await manager.setAccessTokenForTesting(token)

        let loadedToken = try await manager.validAccessToken()

        XCTAssertEqual(loadedToken, token)
        let requestCount = await httpClient.requestCount()
        XCTAssertEqual(requestCount, 0)
    }

    func testNearExpiredTokenRefreshesAndPersistsOnlyNewRefreshTokenRecord() async throws {
        let accountID = WebexAccountID()
        let store = InMemoryWebexStore()
        let httpClient = MockHTTPClient()
        let now = Date(timeIntervalSince1970: 100)
        let manager = makeTokenManager(accountID: accountID, store: store, httpClient: httpClient, now: now)
        await manager.setAccessTokenForTesting(
            AccessTokenState(
                value: "old-access",
                expiresAt: Date(timeIntervalSince1970: 120),
                tokenType: "Bearer"
            )
        )
        try await store.saveTokenRecord(tokenRecord(refreshToken: "old-refresh", now: now), for: accountID)
        await httpClient.enqueue(response: tokenHTTPResponse(
            accessToken: "new-access",
            refreshToken: "new-refresh",
            idToken: "new-id-token",
            receivedAt: now
        ))

        let token = try await manager.validAccessToken()
        let loadedRecord = try await store.loadTokenRecord(for: accountID)
        let savedRecord = try XCTUnwrap(loadedRecord)

        XCTAssertEqual(token.value, "new-access")
        XCTAssertEqual(savedRecord.refreshToken, "new-refresh")
        XCTAssertEqual(savedRecord.lastAccessTokenExpiresAt, Date(timeIntervalSince1970: 700))
        let encodedRecord = try JSONEncoder().encode(savedRecord)
        let json = try XCTUnwrap(String(data: encodedRecord, encoding: .utf8))
        XCTAssertFalse(json.contains("new-access"))
        XCTAssertFalse(json.contains("new-id-token"))
        let requestCount = await httpClient.requestCount()
        XCTAssertEqual(requestCount, 1)
    }

    func testMissingMemoryTokenWithStoredRefreshTokenRefreshesAndPersistsNewRecord() async throws {
        let accountID = WebexAccountID()
        let store = InMemoryWebexStore()
        let httpClient = MockHTTPClient()
        let now = Date(timeIntervalSince1970: 100)
        let manager = makeTokenManager(accountID: accountID, store: store, httpClient: httpClient, now: now)
        try await store.saveTokenRecord(tokenRecord(refreshToken: "stored-refresh", now: now), for: accountID)
        await httpClient.enqueue(response: tokenHTTPResponse(
            accessToken: "refreshed-access",
            refreshToken: "refreshed-refresh",
            receivedAt: now
        ))

        let token = try await manager.validAccessToken()
        let loadedRecord = try await store.loadTokenRecord(for: accountID)
        let savedRecord = try XCTUnwrap(loadedRecord)

        XCTAssertEqual(token.value, "refreshed-access")
        XCTAssertEqual(token.expiresAt, Date(timeIntervalSince1970: 700))
        XCTAssertEqual(savedRecord.refreshToken, "refreshed-refresh")
        XCTAssertEqual(savedRecord.lastAccessTokenExpiresAt, Date(timeIntervalSince1970: 700))
        let requestCount = await httpClient.requestCount()
        XCTAssertEqual(requestCount, 1)
    }

    func testInvalidateAccessTokenClearsOnlyMemoryAndNextCallRefreshes() async throws {
        let accountID = WebexAccountID()
        let store = InMemoryWebexStore()
        let httpClient = MockHTTPClient()
        let now = Date(timeIntervalSince1970: 100)
        let manager = makeTokenManager(accountID: accountID, store: store, httpClient: httpClient, now: now)
        let storedRecord = tokenRecord(refreshToken: "stored-refresh", now: now)
        try await store.saveTokenRecord(storedRecord, for: accountID)
        await manager.setAccessTokenForTesting(
            AccessTokenState(
                value: "fresh-memory-access",
                expiresAt: Date(timeIntervalSince1970: 1_000),
                tokenType: "Bearer"
            )
        )
        await manager.invalidateAccessToken()
        await httpClient.enqueue(response: tokenHTTPResponse(
            accessToken: "post-invalidate-access",
            refreshToken: "post-invalidate-refresh",
            receivedAt: now
        ))

        let token = try await manager.validAccessToken()
        let loadedRecord = try await store.loadTokenRecord(for: accountID)
        let savedRecord = try XCTUnwrap(loadedRecord)

        XCTAssertEqual(token.value, "post-invalidate-access")
        XCTAssertNotEqual(token.value, "fresh-memory-access")
        XCTAssertEqual(savedRecord.refreshToken, "post-invalidate-refresh")
        XCTAssertEqual(savedRecord.grantedScopes, storedRecord.grantedScopes)
        XCTAssertEqual(savedRecord.tokenType, storedRecord.tokenType)
        let requestCount = await httpClient.requestCount()
        XCTAssertEqual(requestCount, 1)
    }

    func testConcurrentCallsShareOneRefreshRequest() async throws {
        let accountID = WebexAccountID()
        let store = InMemoryWebexStore()
        let httpClient = MockHTTPClient()
        let now = Date(timeIntervalSince1970: 100)
        let manager = makeTokenManager(accountID: accountID, store: store, httpClient: httpClient, now: now)
        try await store.saveTokenRecord(tokenRecord(refreshToken: "old-refresh", now: now), for: accountID)
        await httpClient.enqueue(response: tokenHTTPResponse(
            accessToken: "shared-access",
            refreshToken: "shared-refresh",
            receivedAt: now
        ))

        async let first = manager.validAccessToken()
        async let second = manager.validAccessToken()
        async let third = manager.validAccessToken()
        let tokens = try await [first, second, third]

        XCTAssertEqual(tokens.map { $0.value }, ["shared-access", "shared-access", "shared-access"])
        let requestCount = await httpClient.requestCount()
        XCTAssertEqual(requestCount, 1)
    }

    func testFiveHundredRefreshRetriesWithBackoff() async throws {
        let accountID = WebexAccountID()
        let store = InMemoryWebexStore()
        let httpClient = MockHTTPClient()
        let sleeper = SleepRecorder()
        let now = Date(timeIntervalSince1970: 100)
        let manager = makeTokenManager(
            accountID: accountID,
            store: store,
            httpClient: httpClient,
            now: now,
            retryPolicy: RetryPolicy(maxAttempts: 3, baseDelay: 0.5, jitter: 0),
            sleeper: { delay in try await sleeper.sleep(for: delay) }
        )
        try await store.saveTokenRecord(tokenRecord(refreshToken: "old-refresh", now: now), for: accountID)
        await httpClient.enqueue(response: httpResponse(statusCode: 500, body: #"{"error":"temporary"}"#))
        await httpClient.enqueue(response: tokenHTTPResponse(
            accessToken: "retried-access",
            refreshToken: "retried-refresh",
            receivedAt: now
        ))

        let token = try await manager.validAccessToken()

        XCTAssertEqual(token.value, "retried-access")
        let requestCount = await httpClient.requestCount()
        let delays = await sleeper.recordedDelays()
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(delays, [0.5])
    }

    func testMissingRefreshTokenThrowsMissingRefreshToken() async throws {
        let accountID = WebexAccountID()
        let store = InMemoryWebexStore()
        let httpClient = MockHTTPClient()
        let manager = makeTokenManager(accountID: accountID, store: store, httpClient: httpClient)

        do {
            _ = try await manager.validAccessToken()
            XCTFail("Expected missing refresh token")
        } catch let error as WebexSDKError {
            XCTAssertEqual(error, .missingRefreshToken(accountID))
        }

        let requestCount = await httpClient.requestCount()
        XCTAssertEqual(requestCount, 0)
    }

    func testExpiredRefreshTokenThrowsReauthenticationRequiredWithoutHTTP() async throws {
        let accountID = WebexAccountID()
        let store = InMemoryWebexStore()
        let httpClient = MockHTTPClient()
        let now = Date(timeIntervalSince1970: 100)
        let manager = makeTokenManager(accountID: accountID, store: store, httpClient: httpClient, now: now)
        try await store.saveTokenRecord(
            WebexTokenRecord(
                refreshToken: "expired-refresh",
                refreshTokenExpiresAt: Date(timeIntervalSince1970: 99),
                lastAccessTokenExpiresAt: Date(timeIntervalSince1970: 90),
                grantedScopes: ["openid"],
                tokenType: "Bearer",
                lastRefreshAt: Date(timeIntervalSince1970: 50)
            ),
            for: accountID
        )

        do {
            _ = try await manager.validAccessToken()
            XCTFail("Expected reauthentication required")
        } catch let error as WebexSDKError {
            XCTAssertEqual(error, .reauthenticationRequired(accountID))
        }

        let requestCount = await httpClient.requestCount()
        XCTAssertEqual(requestCount, 0)
    }

    func testFailedNonRetryTokenExchangeSurfacesRedactedTokenExchangeFailed() async throws {
        let accountID = WebexAccountID()
        let store = InMemoryWebexStore()
        let httpClient = MockHTTPClient()
        let now = Date(timeIntervalSince1970: 100)
        let manager = makeTokenManager(accountID: accountID, store: store, httpClient: httpClient, now: now)
        try await store.saveTokenRecord(tokenRecord(refreshToken: "stored-refresh-token", now: now), for: accountID)
        await httpClient.enqueue(response: httpResponse(
            statusCode: 400,
            headers: ["TrackingID": "tracking-1"],
            body: "invalid refresh token stored-refresh-token for client-secret"
        ))

        do {
            _ = try await manager.validAccessToken()
            XCTFail("Expected token exchange failure")
        } catch let error as WebexSDKError {
            guard case .tokenExchangeFailed(let statusCode, let message, let trackingID) = error else {
                return XCTFail("Expected tokenExchangeFailed, got \(error)")
            }

            XCTAssertEqual(statusCode, 400)
            XCTAssertEqual(trackingID, "tracking-1")
            XCTAssertEqual(message, "Token endpoint returned HTTP 400")
            assertSensitiveValuesRedacted(in: message, extraSecrets: ["stored-refresh-token"])
            let description = String(describing: error)
            assertSensitiveValuesRedacted(in: description, extraSecrets: ["stored-refresh-token"])
        }

        let requestCount = await httpClient.requestCount()
        XCTAssertEqual(requestCount, 1)
    }

    func testNetworkErrorRetriesOnceUnderRetryPolicy() async throws {
        let accountID = WebexAccountID()
        let store = InMemoryWebexStore()
        let httpClient = MockHTTPClient()
        let sleeper = SleepRecorder()
        let now = Date(timeIntervalSince1970: 100)
        let manager = makeTokenManager(
            accountID: accountID,
            store: store,
            httpClient: httpClient,
            now: now,
            retryPolicy: RetryPolicy(maxAttempts: 2, baseDelay: 0.25, jitter: 0),
            sleeper: { delay in try await sleeper.sleep(for: delay) }
        )
        try await store.saveTokenRecord(tokenRecord(refreshToken: "old-refresh", now: now), for: accountID)
        await httpClient.enqueue(error: WebexSDKError.network("transient network"))
        await httpClient.enqueue(response: tokenHTTPResponse(
            accessToken: "network-retry-access",
            refreshToken: "network-retry-refresh",
            receivedAt: now
        ))

        let token = try await manager.validAccessToken()

        XCTAssertEqual(token.value, "network-retry-access")
        let requestCount = await httpClient.requestCount()
        let delays = await sleeper.recordedDelays()
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(delays, [0.25])
    }

    func testRateLimitedRefreshRetriesWithRetryAfter() async throws {
        let accountID = WebexAccountID()
        let store = InMemoryWebexStore()
        let httpClient = MockHTTPClient()
        let sleeper = SleepRecorder()
        let now = Date(timeIntervalSince1970: 100)
        let manager = makeTokenManager(
            accountID: accountID,
            store: store,
            httpClient: httpClient,
            now: now,
            retryPolicy: RetryPolicy(maxAttempts: 2, baseDelay: 0.25, jitter: 0),
            sleeper: { delay in try await sleeper.sleep(for: delay) }
        )
        try await store.saveTokenRecord(tokenRecord(refreshToken: "stored-refresh", now: now), for: accountID)
        await httpClient.enqueue(response: httpResponse(
            statusCode: 429,
            headers: ["Retry-After": "1.5"],
            body: "rate limited"
        ))
        await httpClient.enqueue(response: tokenHTTPResponse(
            accessToken: "rate-limit-retry-access",
            refreshToken: "rate-limit-retry-refresh",
            receivedAt: now
        ))

        let token = try await manager.validAccessToken()

        XCTAssertEqual(token.value, "rate-limit-retry-access")
        let requestCount = await httpClient.requestCount()
        let delays = await sleeper.recordedDelays()
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(delays, [1.5])
    }

    func testRateLimitedRefreshHonorsPolicyMaximumDelayAboveSixty() async throws {
        let accountID = WebexAccountID()
        let store = InMemoryWebexStore()
        let httpClient = MockHTTPClient()
        let sleeper = SleepRecorder()
        let now = Date(timeIntervalSince1970: 100)
        let manager = makeTokenManager(
            accountID: accountID,
            store: store,
            httpClient: httpClient,
            now: now,
            retryPolicy: RetryPolicy(maxAttempts: 2, baseDelay: 0.25, jitter: 0, maximumDelay: 120),
            sleeper: { delay in try await sleeper.sleep(for: delay) }
        )
        try await store.saveTokenRecord(tokenRecord(refreshToken: "stored-refresh", now: now), for: accountID)
        await httpClient.enqueue(response: httpResponse(
            statusCode: 429,
            headers: ["Retry-After": "90"],
            body: "rate limited"
        ))
        await httpClient.enqueue(response: tokenHTTPResponse(
            accessToken: "rate-limit-long-retry-access",
            refreshToken: "rate-limit-long-retry-refresh",
            receivedAt: now
        ))

        let token = try await manager.validAccessToken()

        XCTAssertEqual(token.value, "rate-limit-long-retry-access")
        let requestCount = await httpClient.requestCount()
        let delays = await sleeper.recordedDelays()
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(delays, [90])
    }

    func testExhaustedRateLimitSurfacesRateLimitedErrorWithRetryAfter() async throws {
        let accountID = WebexAccountID()
        let store = InMemoryWebexStore()
        let httpClient = MockHTTPClient()
        let sleeper = SleepRecorder()
        let now = Date(timeIntervalSince1970: 100)
        let manager = makeTokenManager(
            accountID: accountID,
            store: store,
            httpClient: httpClient,
            now: now,
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0.25, jitter: 0),
            sleeper: { delay in try await sleeper.sleep(for: delay) }
        )
        try await store.saveTokenRecord(tokenRecord(refreshToken: "stored-refresh-token", now: now), for: accountID)
        await httpClient.enqueue(response: httpResponse(
            statusCode: 429,
            headers: ["Retry-After": "2.5"],
            body: "rate limit for stored-refresh-token and client-secret"
        ))

        do {
            _ = try await manager.validAccessToken()
            XCTFail("Expected rate limited error")
        } catch let error as WebexSDKError {
            XCTAssertEqual(error, .rateLimited(retryAfter: 2.5))
            assertSensitiveValuesRedacted(
                in: String(describing: error),
                extraSecrets: ["stored-refresh-token"]
            )
        }

        let requestCount = await httpClient.requestCount()
        let delays = await sleeper.recordedDelays()
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(delays, [])
    }

    func testExhaustedNetworkErrorSurfacesRedactedNetworkError() async throws {
        let accountID = WebexAccountID()
        let store = InMemoryWebexStore()
        let httpClient = MockHTTPClient()
        let now = Date(timeIntervalSince1970: 100)
        let manager = makeTokenManager(
            accountID: accountID,
            store: store,
            httpClient: httpClient,
            now: now,
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, jitter: 0)
        )
        try await store.saveTokenRecord(tokenRecord(refreshToken: "stored-refresh", now: now), for: accountID)
        await httpClient.enqueue(error: WebexSDKError.network(
            "client_secret=client-secret&refresh_token=refresh-secret&access_token=access-secret&id_token=id-secret&code_verifier=verifier-secret"
        ))

        do {
            _ = try await manager.validAccessToken()
            XCTFail("Expected exhausted network error")
        } catch let error as WebexSDKError {
            guard case .network(let message) = error else {
                return XCTFail("Expected network error, got \(error)")
            }

            assertSensitiveValuesRedacted(in: message)
            assertSensitiveValuesRedacted(in: String(describing: error))
        }

        let requestCount = await httpClient.requestCount()
        XCTAssertEqual(requestCount, 1)
    }

    func testExhaustedFiveHundredSurfacesRedactedTokenExchangeFailureWithoutExtraSleep() async throws {
        let accountID = WebexAccountID()
        let store = InMemoryWebexStore()
        let httpClient = MockHTTPClient()
        let sleeper = SleepRecorder()
        let now = Date(timeIntervalSince1970: 100)
        let manager = makeTokenManager(
            accountID: accountID,
            store: store,
            httpClient: httpClient,
            now: now,
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0.25, jitter: 0),
            sleeper: { delay in try await sleeper.sleep(for: delay) }
        )
        try await store.saveTokenRecord(tokenRecord(refreshToken: "stored-refresh", now: now), for: accountID)
        await httpClient.enqueue(response: httpResponse(
            statusCode: 500,
            headers: ["TrackingID": "tracking-500"],
            body: "server error for stored-refresh and client-secret"
        ))

        do {
            _ = try await manager.validAccessToken()
            XCTFail("Expected exhausted token exchange failure")
        } catch let error as WebexSDKError {
            guard case .tokenExchangeFailed(let statusCode, let message, let trackingID) = error else {
                return XCTFail("Expected tokenExchangeFailed, got \(error)")
            }

            XCTAssertEqual(statusCode, 500)
            XCTAssertEqual(trackingID, "tracking-500")
            XCTAssertEqual(message, "Token endpoint returned HTTP 500")
            assertSensitiveValuesRedacted(in: message, extraSecrets: ["stored-refresh"])
            assertSensitiveValuesRedacted(in: String(describing: error), extraSecrets: ["stored-refresh"])
        }

        let requestCount = await httpClient.requestCount()
        let delays = await sleeper.recordedDelays()
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(delays, [])
    }

    func testRetryPolicyDefaultsAndClampsInvalidValues() {
        let defaultPolicy = RetryPolicy()

        XCTAssertEqual(defaultPolicy.maxAttempts, 3)
        XCTAssertEqual(defaultPolicy.baseDelay, 0.5)
        XCTAssertEqual(defaultPolicy.jitter, 0.25)
        XCTAssertEqual(defaultPolicy.maximumDelay, 60)

        let clampedPolicy = RetryPolicy(maxAttempts: 0, baseDelay: -1, jitter: -2, maximumDelay: -3)

        XCTAssertEqual(clampedPolicy.maxAttempts, 1)
        XCTAssertEqual(clampedPolicy.baseDelay, 0)
        XCTAssertEqual(clampedPolicy.jitter, 0)
        XCTAssertEqual(clampedPolicy.maximumDelay, 0)
    }

    func testRetryPolicyExponentialDelaysWithoutJitter() {
        let policy = RetryPolicy(maxAttempts: 4, baseDelay: 0.25, jitter: 0)

        XCTAssertEqual(policy.delay(forAttempt: 0), 0.25)
        XCTAssertEqual(policy.delay(forAttempt: 1), 0.25)
        XCTAssertEqual(policy.delay(forAttempt: 2), 0.5)
        XCTAssertEqual(policy.delay(forAttempt: 3), 1.0)
        XCTAssertEqual(policy.delay(forAttempt: 4), 2.0)
    }

    func testRetryPolicyJitterStaysWithinConfiguredBounds() {
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0.5, jitter: 0.25)

        for _ in 0..<100 {
            let delay = policy.delay(forAttempt: 2)

            XCTAssertGreaterThanOrEqual(delay, 1.0)
            XCTAssertLessThanOrEqual(delay, 1.25)
        }
    }

    func testRetryPolicyClampsLargeDelaysToMaximumDelay() {
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 100, jitter: 0, maximumDelay: 60)

        XCTAssertEqual(policy.delay(forAttempt: 1), 60)
        XCTAssertEqual(
            policy.retryAfter(from: httpURLResponse(headers: ["Retry-After": "120"])),
            60
        )
    }

    func testRetryPolicyParsesNumericRetryAfterHeaders() {
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0.5, jitter: 0)

        XCTAssertEqual(
            policy.retryAfter(from: httpURLResponse(headers: ["Retry-After": "2.5"])),
            2.5
        )
        XCTAssertEqual(
            policy.retryAfter(from: httpURLResponse(headers: ["retry-after": "3"])),
            3
        )
        XCTAssertNil(policy.retryAfter(from: httpURLResponse(headers: ["Retry-After": "-1"])))
        XCTAssertNil(policy.retryAfter(from: httpURLResponse(headers: ["Retry-After": "soon"])))
        XCTAssertNil(policy.retryAfter(from: httpURLResponse(headers: ["Retry-After": "inf"])))
        XCTAssertNil(policy.retryAfter(from: httpURLResponse(headers: ["Retry-After": "nan"])))
        XCTAssertNil(policy.retryAfter(from: httpURLResponse(headers: [:])))
    }

    private func makeTokenManager(
        accountID: WebexAccountID,
        store: WebexTokenStore,
        httpClient: HTTPClient,
        now: Date = Date(timeIntervalSince1970: 100),
        retryPolicy: RetryPolicy = RetryPolicy(maxAttempts: 1, baseDelay: 0, jitter: 0),
        sleeper: @escaping @Sendable (TimeInterval) async throws -> Void = { _ in }
    ) -> TokenManager {
        TokenManager(
            accountID: accountID,
            configuration: WebexIntegrationConfiguration(
                clientID: "client",
                clientSecret: "client-secret",
                redirectURI: URL(string: "myapp://oauth/webex")!,
                scopes: ["openid"]
            ),
            tokenStore: store,
            httpClient: httpClient,
            refreshLeeway: 60,
            clock: { now },
            retryPolicy: retryPolicy,
            sleeper: sleeper
        )
    }

    private func tokenRecord(refreshToken: String, now: Date) -> WebexTokenRecord {
        WebexTokenRecord(
            refreshToken: refreshToken,
            refreshTokenExpiresAt: now.addingTimeInterval(3_600),
            lastAccessTokenExpiresAt: now.addingTimeInterval(600),
            grantedScopes: ["openid"],
            tokenType: "Bearer",
            lastRefreshAt: now
        )
    }

    private func tokenHTTPResponse(
        accessToken: String,
        refreshToken: String,
        idToken: String? = nil,
        receivedAt: Date
    ) -> HTTPResponse {
        let idTokenLine = idToken.map { #","id_token":"\#($0)""# } ?? ""
        return httpResponse(
            statusCode: 200,
            body: """
            {"access_token":"\(accessToken)","expires_in":600,"refresh_token":"\(refreshToken)","refresh_token_expires_in":3600,"token_type":"Bearer","scope":"openid"\(idTokenLine)}
            """
        )
    }

    private func httpResponse(
        statusCode: Int,
        headers: [String: String] = [:],
        body: String
    ) -> HTTPResponse {
        let url = URL(string: "https://webexapis.com/v1/access_token")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        return HTTPResponse(data: Data(body.utf8), response: response)
    }

    private func httpURLResponse(headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://webexapis.com/v1/access_token")!,
            statusCode: 503,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }

    private func assertSensitiveValuesRedacted(
        in output: String,
        extraSecrets: [String] = [],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for secret in ["client-secret", "refresh-secret", "access-secret", "id-secret", "verifier-secret"] + extraSecrets {
            XCTAssertFalse(output.contains(secret), "Leaked \(secret)", file: file, line: line)
        }
    }
}

private actor MockHTTPClient: HTTPClient {
    private enum Result: Sendable {
        case response(HTTPResponse)
        case error(WebexSDKError)
    }

    private var results: [Result] = []
    private var requests: [URLRequest] = []

    func requestCount() -> Int {
        requests.count
    }

    func enqueue(response: HTTPResponse) {
        results.append(.response(response))
    }

    func enqueue(error: WebexSDKError) {
        results.append(.error(error))
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard !results.isEmpty else {
            throw WebexSDKError.network("Unexpected token request")
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
    private var delays: [TimeInterval] = []

    func recordedDelays() -> [TimeInterval] {
        delays
    }

    func sleep(for delay: TimeInterval) async throws {
        delays.append(delay)
    }
}
