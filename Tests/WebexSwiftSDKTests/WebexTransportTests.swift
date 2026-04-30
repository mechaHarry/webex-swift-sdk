import XCTest
@testable import WebexSwiftSDK

final class WebexTransportTests: XCTestCase {
    func testTrailingTokenProviderInitializerSendsRequest() async throws {
        @Sendable func token(_ value: String) -> AccessTokenState {
            AccessTokenState(
                value: value,
                expiresAt: Date(timeIntervalSinceNow: 100),
                tokenType: "Bearer"
            )
        }

        let httpClient = MockTransportHTTPClient()
        await httpClient.enqueue(response: httpResponse(statusCode: 200, body: #"{"ok":true}"#))
        let transport = WebexTransport(httpClient: httpClient) {
            token("access")
        }

        let data = try await transport.send(WebexRequest(path: "v1/people/me"))

        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"ok":true}"#)
        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer access")
    }

    func testAddsBearerTokenAndBuildsDefaultBaseURLPath() async throws {
        let httpClient = MockTransportHTTPClient()
        let tokenProvider = TokenProvider(tokens: [token("first-access-token")])
        await httpClient.enqueue(response: httpResponse(statusCode: 200, body: #"{"ok":true}"#))
        let transport = makeTransport(httpClient: httpClient, tokenProvider: tokenProvider)

        let data = try await transport.send(WebexRequest(path: "v1/people/me"))

        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"ok":true}"#)
        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].url?.absoluteString, "https://webexapis.com/v1/people/me")
        XCTAssertEqual(requests[0].httpMethod, "GET")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer first-access-token")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testQueryItemsReservedCharactersAndLiteralPlusSignsAreEncoded() async throws {
        let httpClient = MockTransportHTTPClient()
        let tokenProvider = TokenProvider(tokens: [token("query-token")])
        await httpClient.enqueue(response: httpResponse(statusCode: 200, body: "{}"))
        let transport = makeTransport(httpClient: httpClient, tokenProvider: tokenProvider)

        _ = try await transport.send(WebexRequest(
            path: "/v1/people",
            queryItems: [
                URLQueryItem(name: "email", value: "user+webex@example.com"),
                URLQueryItem(name: "display name", value: "A/B & C")
            ]
        ))

        let encodedRequests = await httpClient.recordedRequests()
        let request = try XCTUnwrap(encodedRequests.first)
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://webexapis.com/v1/people?email=user%2Bwebex@example.com&display%20name=A/B%20%26%20C"
        )
        XCTAssertFalse(request.url?.absoluteString.contains("user+webex") == true)
    }

    func testRawPathContainingLiteralPercentIsEncodedSafely() async throws {
        let httpClient = MockTransportHTTPClient()
        let tokenProvider = TokenProvider(tokens: [token("percent-token")])
        await httpClient.enqueue(response: httpResponse(statusCode: 200, body: "{}"))
        let transport = makeTransport(httpClient: httpClient, tokenProvider: tokenProvider)

        _ = try await transport.send(WebexRequest(path: "/v1/rooms/100% legit"))

        let requests = await httpClient.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://webexapis.com/v1/rooms/100%25%20legit")
    }

    func testExplicitPercentEncodedPathPreservesEscapedPathSeparators() async throws {
        let httpClient = MockTransportHTTPClient()
        let tokenProvider = TokenProvider(tokens: [token("encoded-path-token")])
        await httpClient.enqueue(response: httpResponse(statusCode: 200, body: "{}"))
        let transport = makeTransport(httpClient: httpClient, tokenProvider: tokenProvider)

        _ = try await transport.send(WebexRequest(
            path: "/v1/rooms/room%2Fid+1",
            isPathPercentEncoded: true
        ))

        let requests = await httpClient.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://webexapis.com/v1/rooms/room%2Fid+1")
    }

    func testInvalidExplicitPercentEncodedPathThrowsSafeErrorWithoutTokenOrHTTP() async throws {
        let httpClient = MockTransportHTTPClient()
        let tokenProvider = TokenProvider(tokens: [token("encoded-path-secret-token")])
        let transport = makeTransport(httpClient: httpClient, tokenProvider: tokenProvider)

        do {
            _ = try await transport.send(WebexRequest(
                path: "/v1/rooms/100% legit",
                isPathPercentEncoded: true
            ))
            XCTFail("Expected invalid encoded path error")
        } catch let error as WebexSDKError {
            guard case .network(let message) = error else {
                return XCTFail("Expected network error, got \(error)")
            }

            XCTAssertEqual(message, "Invalid Webex API request path")
            assertSensitiveValuesRedacted(in: String(describing: error), extraSecrets: ["encoded-path-secret-token"])
        }

        let requestCount = await httpClient.requestCount()
        let tokenCallCount = await tokenProvider.tokenCallCount()
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(tokenCallCount, 0)
    }

    func testBodyIsPreservedAndDefaultsJSONContentType() async throws {
        let httpClient = MockTransportHTTPClient()
        let tokenProvider = TokenProvider(tokens: [token("body-token")])
        let body = Data(#"{"displayName":"Ada"}"#.utf8)
        await httpClient.enqueue(response: httpResponse(statusCode: 200, body: "{}"))
        let transport = makeTransport(httpClient: httpClient, tokenProvider: tokenProvider)

        _ = try await transport.send(WebexRequest(method: "POST", path: "v1/rooms", body: body))

        let requests = await httpClient.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpBody, body)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testCallerContentTypeHeaderOverridesDefaultForBody() async throws {
        let httpClient = MockTransportHTTPClient()
        let tokenProvider = TokenProvider(tokens: [token("body-token")])
        let body = Data("plain body".utf8)
        await httpClient.enqueue(response: httpResponse(statusCode: 200, body: "{}"))
        let transport = makeTransport(httpClient: httpClient, tokenProvider: tokenProvider)

        _ = try await transport.send(WebexRequest(
            method: "POST",
            path: "v1/messages",
            headers: ["Content-Type": "text/plain"],
            body: body
        ))

        let requests = await httpClient.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpBody, body)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "text/plain")
    }

    func testUnauthorizedInvalidatesOnceAndRetriesWithFreshToken() async throws {
        let httpClient = MockTransportHTTPClient()
        let tokenProvider = TokenProvider(tokens: [token("stale-token"), token("fresh-token")])
        await httpClient.enqueue(response: httpResponse(statusCode: 401, body: #"{"message":"expired"}"#))
        await httpClient.enqueue(response: httpResponse(statusCode: 200, body: #"{"id":"me"}"#))
        let transport = makeTransport(httpClient: httpClient, tokenProvider: tokenProvider)

        let data = try await transport.send(WebexRequest(path: "v1/people/me"))

        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"id":"me"}"#)
        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(requests.map { $0.value(forHTTPHeaderField: "Authorization") }, [
            "Bearer stale-token",
            "Bearer fresh-token"
        ])
        let tokenCallCount = await tokenProvider.tokenCallCount()
        let invalidateCallCount = await tokenProvider.invalidateCallCount()
        XCTAssertEqual(tokenCallCount, 2)
        XCTAssertEqual(invalidateCallCount, 1)
    }

    func testRateLimitedRetriesWithRetryAfterAndSucceeds() async throws {
        let httpClient = MockTransportHTTPClient()
        let sleeper = SleepRecorder()
        let tokenProvider = TokenProvider(tokens: [token("rate-token"), token("rate-token")])
        await httpClient.enqueue(response: httpResponse(
            statusCode: 429,
            headers: ["Retry-After": "1.25"],
            body: #"{"message":"slow down"}"#
        ))
        await httpClient.enqueue(response: httpResponse(statusCode: 200, body: #"{"ok":true}"#))
        let transport = makeTransport(
            httpClient: httpClient,
            tokenProvider: tokenProvider,
            retryPolicy: RetryPolicy(maxAttempts: 2, baseDelay: 0.5, jitter: 0),
            sleeper: { delay in try await sleeper.sleep(for: delay) }
        )

        let data = try await transport.send(WebexRequest(path: "v1/messages"))

        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"ok":true}"#)
        let requestCount = await httpClient.requestCount()
        let tokenCallCount = await tokenProvider.tokenCallCount()
        let delays = await sleeper.recordedDelays()
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(tokenCallCount, 2)
        XCTAssertEqual(delays, [1.25])
    }

    func testExhaustedRateLimitSurfacesRetryAfterWithoutLeakingBodyOrToken() async throws {
        let httpClient = MockTransportHTTPClient()
        let tokenProvider = TokenProvider(tokens: [token("secret-access-token")])
        await httpClient.enqueue(response: httpResponse(
            statusCode: 429,
            headers: ["Retry-After": "2.5"],
            body: #"{"message":"rate limited secret-access-token","access_token":"body-token"}"#
        ))
        let transport = makeTransport(
            httpClient: httpClient,
            tokenProvider: tokenProvider,
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, jitter: 0)
        )

        do {
            _ = try await transport.send(WebexRequest(path: "v1/messages"))
            XCTFail("Expected rate limited error")
        } catch let error as WebexSDKError {
            XCTAssertEqual(error, .rateLimited(retryAfter: 2.5))
            assertSensitiveValuesRedacted(in: String(describing: error), extraSecrets: ["secret-access-token", "body-token"])
        }

        let requestCount = await httpClient.requestCount()
        XCTAssertEqual(requestCount, 1)
    }

    func testFiveHundredRetriesWithBackoffAndSucceeds() async throws {
        let httpClient = MockTransportHTTPClient()
        let sleeper = SleepRecorder()
        let tokenProvider = TokenProvider(tokens: [token("server-token"), token("server-token")])
        await httpClient.enqueue(response: httpResponse(statusCode: 503, body: #"{"message":"temporarily unavailable"}"#))
        await httpClient.enqueue(response: httpResponse(statusCode: 200, body: #"{"ok":true}"#))
        let transport = makeTransport(
            httpClient: httpClient,
            tokenProvider: tokenProvider,
            retryPolicy: RetryPolicy(maxAttempts: 2, baseDelay: 0.75, jitter: 0),
            sleeper: { delay in try await sleeper.sleep(for: delay) }
        )

        let data = try await transport.send(WebexRequest(path: "v1/rooms"))

        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"ok":true}"#)
        let requestCount = await httpClient.requestCount()
        let delays = await sleeper.recordedDelays()
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(delays, [0.75])
    }

    func testExhaustedFiveHundredSurfacesWebexAPIWithTrackingIDAndRedactedMessage() async throws {
        let httpClient = MockTransportHTTPClient()
        let tokenProvider = TokenProvider(tokens: [token("server-secret-token")])
        await httpClient.enqueue(response: httpResponse(
            statusCode: 500,
            headers: ["trackingId": "tracking-500"],
            body: #"{"message":"server failed Bearer body-token server-secret-token"}"#
        ))
        let transport = makeTransport(
            httpClient: httpClient,
            tokenProvider: tokenProvider,
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, jitter: 0)
        )

        do {
            _ = try await transport.send(WebexRequest(path: "v1/rooms"))
            XCTFail("Expected Webex API error")
        } catch let error as WebexSDKError {
            guard case .webexAPI(let statusCode, let trackingID, let message) = error else {
                return XCTFail("Expected webexAPI, got \(error)")
            }

            XCTAssertEqual(statusCode, 500)
            XCTAssertEqual(trackingID, "tracking-500")
            XCTAssertTrue(message.contains("server failed"))
            assertSensitiveValuesRedacted(in: message, extraSecrets: ["server-secret-token", "body-token"])
            assertSensitiveValuesRedacted(in: String(describing: error), extraSecrets: ["server-secret-token", "body-token"])
        }

        let requestCount = await httpClient.requestCount()
        XCTAssertEqual(requestCount, 1)
    }

    func testWebexAPIErrorPreservesTrackingIDHeaderVariants() async throws {
        let variants = [
            ("TrackingID", "tracking-a"),
            ("trackingId", "tracking-b"),
            ("X-TrackingID", "tracking-c"),
            ("x-trackingid", "tracking-d")
        ]

        for (header, expectedTrackingID) in variants {
            let httpClient = MockTransportHTTPClient()
            let tokenProvider = TokenProvider(tokens: [token("tracking-token")])
            await httpClient.enqueue(response: httpResponse(
                statusCode: 500,
                headers: [header: expectedTrackingID],
                body: #"{"message":"failed"}"#
            ))
            let transport = makeTransport(httpClient: httpClient, tokenProvider: tokenProvider)

            do {
                _ = try await transport.send(WebexRequest(path: "v1/rooms"))
                XCTFail("Expected Webex API error for \(header)")
            } catch let error as WebexSDKError {
                guard case .webexAPI(_, let trackingID, _) = error else {
                    return XCTFail("Expected webexAPI for \(header), got \(error)")
                }

                XCTAssertEqual(trackingID, expectedTrackingID)
            }
        }
    }

    func testSchemeRelativePathHandlingSurfacesSafeSDKErrorWithoutTokenOrHTTP() async throws {
        let httpClient = MockTransportHTTPClient()
        let tokenProvider = TokenProvider(tokens: [token("path-secret-token")])
        let transport = makeTransport(httpClient: httpClient, tokenProvider: tokenProvider)

        do {
            _ = try await transport.send(WebexRequest(path: "//evil.example/v1/people"))
            XCTFail("Expected invalid URL error")
        } catch let error as WebexSDKError {
            guard case .network(let message) = error else {
                return XCTFail("Expected network error, got \(error)")
            }

            XCTAssertFalse(message.contains("evil.example"))
            XCTAssertFalse(String(describing: error).contains("evil.example"))
            assertSensitiveValuesRedacted(in: String(describing: error), extraSecrets: ["path-secret-token"])
        }

        let requestCount = await httpClient.requestCount()
        let tokenCallCount = await tokenProvider.tokenCallCount()
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(tokenCallCount, 0)
    }

    func testThrownNetworkErrorRetriesAndFinalErrorIsRedacted() async throws {
        let httpClient = MockTransportHTTPClient()
        let sleeper = SleepRecorder()
        let tokenProvider = TokenProvider(tokens: [token("network-secret-token"), token("network-secret-token")])
        await httpClient.enqueue(error: WebexSDKError.network("transient Authorization: Bearer network-secret-token"))
        await httpClient.enqueue(error: WebexSDKError.network("final access_token=network-secret-token"))
        let transport = makeTransport(
            httpClient: httpClient,
            tokenProvider: tokenProvider,
            retryPolicy: RetryPolicy(maxAttempts: 2, baseDelay: 0.2, jitter: 0),
            sleeper: { delay in try await sleeper.sleep(for: delay) }
        )

        do {
            _ = try await transport.send(WebexRequest(path: "v1/meetings"))
            XCTFail("Expected network error")
        } catch let error as WebexSDKError {
            guard case .network(let message) = error else {
                return XCTFail("Expected network error, got \(error)")
            }

            assertSensitiveValuesRedacted(in: message, extraSecrets: ["network-secret-token"])
            assertSensitiveValuesRedacted(in: String(describing: error), extraSecrets: ["network-secret-token"])
        }

        let requestCount = await httpClient.requestCount()
        let delays = await sleeper.recordedDelays()
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(delays, [0.2])
    }

    func testTokenProviderCancellationPropagatesWithoutRetry() async throws {
        let httpClient = MockTransportHTTPClient()
        let sleeper = SleepRecorder()
        let tokenProvider = TokenProvider(cancels: true)
        let transport = makeTransport(
            httpClient: httpClient,
            tokenProvider: tokenProvider,
            retryPolicy: RetryPolicy(maxAttempts: 2, baseDelay: 0.2, jitter: 0),
            sleeper: { delay in try await sleeper.sleep(for: delay) }
        )

        do {
            _ = try await transport.send(WebexRequest(path: "v1/people/me"))
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        let requestCount = await httpClient.requestCount()
        let tokenCallCount = await tokenProvider.tokenCallCount()
        let delays = await sleeper.recordedDelays()
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(tokenCallCount, 1)
        XCTAssertEqual(delays, [])
    }

    func testHTTPClientCancellationPropagatesWithoutRetry() async throws {
        let httpClient = MockTransportHTTPClient()
        let sleeper = SleepRecorder()
        let tokenProvider = TokenProvider(tokens: [token("cancel-token"), token("cancel-token")])
        await httpClient.enqueueCancellation()
        let transport = makeTransport(
            httpClient: httpClient,
            tokenProvider: tokenProvider,
            retryPolicy: RetryPolicy(maxAttempts: 2, baseDelay: 0.2, jitter: 0),
            sleeper: { delay in try await sleeper.sleep(for: delay) }
        )

        do {
            _ = try await transport.send(WebexRequest(path: "v1/people/me"))
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        let requestCount = await httpClient.requestCount()
        let tokenCallCount = await tokenProvider.tokenCallCount()
        let delays = await sleeper.recordedDelays()
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(tokenCallCount, 1)
        XCTAssertEqual(delays, [])
    }

    func testSleeperCancellationDuringRetryableResponsePropagatesWithoutSecondRequest() async throws {
        let httpClient = MockTransportHTTPClient()
        let sleeper = SleepRecorder(throwsCancellation: true)
        let tokenProvider = TokenProvider(tokens: [token("sleep-token"), token("sleep-token")])
        await httpClient.enqueue(response: httpResponse(statusCode: 503, body: #"{"message":"temporary"}"#))
        await httpClient.enqueue(response: httpResponse(statusCode: 200, body: #"{"ok":true}"#))
        let transport = makeTransport(
            httpClient: httpClient,
            tokenProvider: tokenProvider,
            retryPolicy: RetryPolicy(maxAttempts: 2, baseDelay: 0.5, jitter: 0),
            sleeper: { delay in try await sleeper.sleep(for: delay) }
        )

        do {
            _ = try await transport.send(WebexRequest(path: "v1/rooms"))
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        let requestCount = await httpClient.requestCount()
        let tokenCallCount = await tokenProvider.tokenCallCount()
        let delays = await sleeper.recordedDelays()
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(tokenCallCount, 1)
        XCTAssertEqual(delays, [0.5])
    }

    func testInvalidPathHandlingSurfacesSafeSDKError() async throws {
        let httpClient = MockTransportHTTPClient()
        let tokenProvider = TokenProvider(tokens: [token("path-secret-token")])
        let transport = makeTransport(httpClient: httpClient, tokenProvider: tokenProvider)

        do {
            _ = try await transport.send(WebexRequest(path: "https://evil.example/v1/people"))
            XCTFail("Expected invalid URL error")
        } catch let error as WebexSDKError {
            guard case .network(let message) = error else {
                return XCTFail("Expected network error, got \(error)")
            }

            XCTAssertFalse(message.contains("evil.example"))
            assertSensitiveValuesRedacted(in: String(describing: error), extraSecrets: ["path-secret-token"])
        }

        let requestCount = await httpClient.requestCount()
        let tokenCallCount = await tokenProvider.tokenCallCount()
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(tokenCallCount, 0)
    }

    func testSendResponseReturnsDataAndHeadersForSuccessfulRequest() async throws {
        let httpClient = MockTransportHTTPClient()
        let tokenProvider = TokenProvider(tokens: [token("response-token")])
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            headers: ["Link": #"<https://webexapis.com/v1/rooms?cursor=next>; rel="next""#],
            body: #"{"items":[]}"#
        ))
        let transport = makeTransport(httpClient: httpClient, tokenProvider: tokenProvider)

        let response = try await transport.sendResponse(WebexRequest(path: "v1/rooms"))

        XCTAssertEqual(String(data: response.data, encoding: .utf8), #"{"items":[]}"#)
        XCTAssertEqual(response.response.value(forHTTPHeaderField: "Link"), #"<https://webexapis.com/v1/rooms?cursor=next>; rel="next""#)
        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer response-token")
    }

    func testLockedResponseRetriesWhenRetryAfterIsPresent() async throws {
        let httpClient = MockTransportHTTPClient()
        let sleeper = SleepRecorder()
        let tokenProvider = TokenProvider(tokens: [token("locked-token"), token("locked-token")])
        await httpClient.enqueue(response: httpResponse(
            statusCode: 423,
            headers: ["Retry-After": "1.5"],
            body: #"{"message":"locked"}"#
        ))
        await httpClient.enqueue(response: httpResponse(statusCode: 200, body: #"{"ok":true}"#))
        let transport = makeTransport(
            httpClient: httpClient,
            tokenProvider: tokenProvider,
            retryPolicy: RetryPolicy(maxAttempts: 2, baseDelay: 0.5, jitter: 0),
            sleeper: { delay in try await sleeper.sleep(for: delay) }
        )

        let data = try await transport.send(WebexRequest(path: "v1/rooms"))

        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"ok":true}"#)
        let requestCount = await httpClient.requestCount()
        let delays = await sleeper.recordedDelays()
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(delays, [1.5])
    }

    func testLockedResponseWithoutRetryAfterDoesNotRetryAndIsClassified() async throws {
        let httpClient = MockTransportHTTPClient()
        let sleeper = SleepRecorder()
        let tokenProvider = TokenProvider(tokens: [token("locked-secret-token")])
        await httpClient.enqueue(response: httpResponse(
            statusCode: 423,
            body: #"{"message":"locked locked-secret-token"}"#
        ))
        let transport = makeTransport(
            httpClient: httpClient,
            tokenProvider: tokenProvider,
            retryPolicy: RetryPolicy(maxAttempts: 2, baseDelay: 0.5, jitter: 0),
            sleeper: { delay in try await sleeper.sleep(for: delay) }
        )

        do {
            _ = try await transport.send(WebexRequest(path: "v1/rooms"))
            XCTFail("Expected locked error")
        } catch let error as WebexSDKError {
            guard case .locked(let retryAfter, let trackingID, let message) = error else {
                return XCTFail("Expected locked error, got \(error)")
            }

            XCTAssertNil(retryAfter)
            XCTAssertNil(trackingID)
            XCTAssertTrue(message.contains("locked"))
            XCTAssertEqual(error.apiErrorKind, .locked(retryAfter: nil))
            assertSensitiveValuesRedacted(in: String(describing: error), extraSecrets: ["locked-secret-token"])
        }

        let requestCount = await httpClient.requestCount()
        let delays = await sleeper.recordedDelays()
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(delays, [])
    }

    func testLockedResponseRedactsAccessTokenFromTrackingID() async throws {
        let httpClient = MockTransportHTTPClient()
        let tokenProvider = TokenProvider(tokens: [token("locked-secret-token")])
        await httpClient.enqueue(response: httpResponse(
            statusCode: 423,
            headers: ["trackingId": "trace locked-secret-token"],
            body: #"{"message":"locked"}"#
        ))
        let transport = makeTransport(httpClient: httpClient, tokenProvider: tokenProvider)

        do {
            _ = try await transport.send(WebexRequest(path: "v1/rooms"))
            XCTFail("Expected locked error")
        } catch let error as WebexSDKError {
            guard case .locked(_, let trackingID, _) = error else {
                return XCTFail("Expected locked error, got \(error)")
            }

            XCTAssertNotNil(trackingID)
            XCTAssertFalse(trackingID?.contains("locked-secret-token") == true)
            XCTAssertFalse(String(describing: error).contains("locked-secret-token"))
        }
    }

    func testAPIErrorKindClassifiesDocumentedStatuses() {
        let mappings: [(WebexSDKError, WebexAPIErrorKind)] = [
            (.webexAPI(statusCode: 400, trackingID: nil, message: "bad"), .badRequest),
            (.webexAPI(statusCode: 401, trackingID: nil, message: "auth"), .unauthorized),
            (.webexAPI(statusCode: 403, trackingID: nil, message: "forbidden"), .forbidden),
            (.webexAPI(statusCode: 404, trackingID: nil, message: "missing"), .notFound),
            (.webexAPI(statusCode: 405, trackingID: nil, message: "method"), .methodNotAllowed),
            (.webexAPI(statusCode: 409, trackingID: nil, message: "conflict"), .conflict),
            (.webexAPI(statusCode: 410, trackingID: nil, message: "gone"), .gone),
            (.webexAPI(statusCode: 415, trackingID: nil, message: "media"), .unsupportedMediaType),
            (.locked(retryAfter: 3.5, trackingID: nil, message: "locked"), .locked(retryAfter: 3.5)),
            (.webexAPI(statusCode: 428, trackingID: nil, message: "precondition"), .preconditionRequired),
            (.rateLimited(retryAfter: 2.5), .rateLimited(retryAfter: 2.5)),
            (.webexAPI(statusCode: 500, trackingID: nil, message: "server"), .serverError),
            (.webexAPI(statusCode: 502, trackingID: nil, message: "gateway"), .serverError),
            (.webexAPI(statusCode: 503, trackingID: nil, message: "unavailable"), .serverError),
            (.webexAPI(statusCode: 504, trackingID: nil, message: "timeout"), .serverError),
            (.webexAPI(statusCode: 499, trackingID: nil, message: "odd"), .unexpected(statusCode: 499))
        ]

        for (error, expectedKind) in mappings {
            XCTAssertEqual(error.apiErrorKind, expectedKind, "Unexpected kind for \(error)")
        }
    }

    private func makeTransport(
        httpClient: HTTPClient,
        tokenProvider: TokenProvider,
        retryPolicy: RetryPolicy = RetryPolicy(maxAttempts: 1, baseDelay: 0, jitter: 0),
        sleeper: @escaping @Sendable (TimeInterval) async throws -> Void = { _ in }
    ) -> WebexTransport {
        WebexTransport(
            httpClient: httpClient,
            accessTokenProvider: { try await tokenProvider.nextToken() },
            tokenInvalidator: { await tokenProvider.invalidate() },
            retryPolicy: retryPolicy,
            sleeper: sleeper
        )
    }

    private func token(_ value: String) -> AccessTokenState {
        AccessTokenState(
            value: value,
            expiresAt: Date(timeIntervalSince1970: 1_000),
            tokenType: "Bearer"
        )
    }

    private func httpResponse(
        statusCode: Int,
        headers: [String: String] = [:],
        body: String
    ) -> HTTPResponse {
        let response = HTTPURLResponse(
            url: URL(string: "https://webexapis.com/v1/test")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        return HTTPResponse(data: Data(body.utf8), response: response)
    }

    private func assertSensitiveValuesRedacted(
        in output: String,
        extraSecrets: [String] = [],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for secret in ["secret-access-token", "body-token", "server-secret-token", "network-secret-token", "path-secret-token"] + extraSecrets {
            XCTAssertFalse(output.contains(secret), "Leaked \(secret)", file: file, line: line)
        }
    }
}

private actor MockTransportHTTPClient: HTTPClient {
    private enum Result: Sendable {
        case response(HTTPResponse)
        case error(WebexSDKError)
        case cancellation
    }

    private var results: [Result] = []
    private var requests: [URLRequest] = []

    func enqueue(response: HTTPResponse) {
        results.append(.response(response))
    }

    func enqueue(error: WebexSDKError) {
        results.append(.error(error))
    }

    func enqueueCancellation() {
        results.append(.cancellation)
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
            throw WebexSDKError.network("Unexpected request")
        }

        switch results.removeFirst() {
        case .response(let response):
            return response
        case .error(let error):
            throw error
        case .cancellation:
            throw CancellationError()
        }
    }
}

private actor TokenProvider {
    private enum Result: Sendable {
        case token(AccessTokenState)
        case cancellation
    }

    private var results: [Result]
    private var tokenCalls = 0
    private var invalidateCalls = 0

    init(tokens: [AccessTokenState]) {
        self.results = tokens.map(Result.token)
    }

    init(cancels: Bool) {
        self.results = cancels ? [.cancellation] : []
    }

    func nextToken() throws -> AccessTokenState {
        tokenCalls += 1
        guard !results.isEmpty else {
            throw WebexSDKError.network("Unexpected token request")
        }

        switch results.removeFirst() {
        case .token(let token):
            return token
        case .cancellation:
            throw CancellationError()
        }
    }

    func invalidate() {
        invalidateCalls += 1
    }

    func tokenCallCount() -> Int {
        tokenCalls
    }

    func invalidateCallCount() -> Int {
        invalidateCalls
    }
}

private actor SleepRecorder {
    private var delays: [TimeInterval] = []
    private let throwsCancellation: Bool

    init(throwsCancellation: Bool = false) {
        self.throwsCancellation = throwsCancellation
    }

    func sleep(for delay: TimeInterval) async throws {
        delays.append(delay)
        if throwsCancellation {
            throw CancellationError()
        }
    }

    func recordedDelays() -> [TimeInterval] {
        delays
    }
}
