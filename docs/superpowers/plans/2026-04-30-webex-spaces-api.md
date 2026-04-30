# Webex Spaces API Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a typed Webex Spaces SDK surface over Webex's `/v1/rooms` endpoints, with Spaces-first names, Rooms compatibility aliases, robust pagination, explicit status classification, and full known field coverage.

**Architecture:** Keep the SDK shape consistent with `PeopleAPI`: `WebexClient` owns typed API groups backed by one authenticated `WebexTransport`. Add a response-returning transport path for paginated headers, then build `SpacesAPI` on small request/response models. Use TDD for each behavior, commit after each green task, and preserve current auth/retry/redaction behavior.

**Tech Stack:** Swift 5.9, SwiftPM, XCTest, Foundation `URLSession`, Webex REST API, RFC5988 `Link` headers.

---

## File Structure

- Modify `Sources/WebexSwiftSDK/Core/WebexSDKError.swift`
  - Add `WebexAPIErrorKind`.
  - Add `apiErrorKind` computed classification without changing existing cases.
- Modify `Sources/WebexSwiftSDK/HTTP/WebexTransport.swift`
  - Add internal `sendResponse(_:) async throws -> HTTPResponse`.
  - Keep public `send(_:) async throws -> Data`.
  - Add bounded `423 Locked` retry only when `Retry-After` is present.
- Create `Sources/WebexSwiftSDK/HTTP/WebexPageLink.swift`
  - Parse RFC5988 `Link` headers.
  - Expose the `rel="next"` URL and conversion back to a `WebexRequest`.
- Create `Sources/WebexSwiftSDK/Core/WebexDateDecoding.swift`
  - Decode Webex ISO8601 timestamps with and without fractional seconds.
- Create `Sources/WebexSwiftSDK/API/WebexSpace.swift`
  - Model `WebexSpace`, `WebexSpaceType`, and partial item errors.
- Create `Sources/WebexSwiftSDK/API/SpacesAPI.swift`
  - Implement list, listAll, create, get, update, delete.
  - Add Spaces-first types and Rooms compatibility aliases.
- Modify `Sources/WebexSwiftSDK/WebexClient.swift`
  - Add `spaces`.
  - Add `rooms` alias returning the same API group.
- Create `Tests/WebexSwiftSDKTests/WebexPageLinkTests.swift`
  - Cover pagination header parsing.
- Create `Tests/WebexSwiftSDKTests/SpacesAPITests.swift`
  - Cover all Spaces API request/response behavior.
- Modify `Tests/WebexSwiftSDKTests/WebexTransportTests.swift`
  - Cover response-returning transport and new status classification.
- Modify `README.md`
  - Add a concise Spaces usage example.

---

## Task 1: Transport Response Path And Error Classification

**Files:**
- Modify: `Sources/WebexSwiftSDK/Core/WebexSDKError.swift`
- Modify: `Sources/WebexSwiftSDK/HTTP/WebexTransport.swift`
- Modify: `Tests/WebexSwiftSDKTests/WebexTransportTests.swift`

- [ ] **Step 1: Write failing transport and classification tests**

Add these tests to `WebexTransportTests` before the helper methods:

```swift
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
    XCTAssertEqual(await httpClient.requestCount(), 2)
    XCTAssertEqual(await sleeper.recordedDelays(), [1.5])
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

    XCTAssertEqual(await httpClient.requestCount(), 1)
    XCTAssertEqual(await sleeper.recordedDelays(), [])
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
```

- [ ] **Step 2: Run the failing transport tests**

Run:

```bash
swift test --filter WebexTransportTests/testSendResponseReturnsDataAndHeadersForSuccessfulRequest
swift test --filter WebexTransportTests/testLockedResponseRetriesWhenRetryAfterIsPresent
swift test --filter WebexTransportTests/testLockedResponseWithoutRetryAfterDoesNotRetryAndIsClassified
swift test --filter WebexTransportTests/testAPIErrorKindClassifiesDocumentedStatuses
```

Expected: the first command fails because `sendResponse` is not visible, and the classification tests fail because `WebexAPIErrorKind`, `apiErrorKind`, and the structured `locked` error case do not exist.

- [ ] **Step 3: Add error kind classification**

Add this enum above `public enum WebexSDKError` in `WebexSDKError.swift`:

```swift
public enum WebexAPIErrorKind: Equatable, Sendable {
    case badRequest
    case unauthorized
    case forbidden
    case notFound
    case methodNotAllowed
    case conflict
    case gone
    case unsupportedMediaType
    case locked(retryAfter: TimeInterval?)
    case preconditionRequired
    case rateLimited(retryAfter: TimeInterval?)
    case serverError
    case unexpected(statusCode: Int)
}
```

Add this computed property inside `public enum WebexSDKError`, after the cases:

```swift
public var apiErrorKind: WebexAPIErrorKind? {
    switch self {
    case .locked(let retryAfter, _, _):
        return .locked(retryAfter: retryAfter)
    case .rateLimited(let retryAfter):
        return .rateLimited(retryAfter: retryAfter)
    case .webexAPI(let statusCode, _, _), .tokenExchangeFailed(let statusCode, _, _):
        return Self.apiErrorKind(for: statusCode, retryAfter: nil)
    default:
        return nil
    }
}

private static func apiErrorKind(for statusCode: Int, retryAfter: TimeInterval?) -> WebexAPIErrorKind {
    switch statusCode {
    case 400:
        return .badRequest
    case 401:
        return .unauthorized
    case 403:
        return .forbidden
    case 404:
        return .notFound
    case 405:
        return .methodNotAllowed
    case 409:
        return .conflict
    case 410:
        return .gone
    case 415:
        return .unsupportedMediaType
    case 423:
        return .locked(retryAfter: retryAfter)
    case 428:
        return .preconditionRequired
    case 429:
        return .rateLimited(retryAfter: retryAfter)
    case 500...599:
        return .serverError
    default:
        return .unexpected(statusCode: statusCode)
    }
}
```

Add this case to `WebexSDKError` with the other cases:

```swift
case locked(retryAfter: TimeInterval?, trackingID: String?, message: String)
```

Add this branch inside `description`:

```swift
case .locked(let retryAfter, let trackingID, let message):
    let retryDescription = retryAfter.map { "; retry after \($0) seconds" } ?? ""
    return "Webex API resource locked: \(Redactor.redactSecrets(message))\(retryDescription)\(trackingIDDescription(trackingID))"
```

- [ ] **Step 4: Add response-returning transport and locked retry**

In `WebexTransport.swift`, replace the existing `send(_:)` body with a delegating implementation and move the existing loop into `sendResponse(_:)`:

```swift
public func send(_ webexRequest: WebexRequest) async throws -> Data {
    try await sendResponse(webexRequest).data
}

func sendResponse(_ webexRequest: WebexRequest) async throws -> HTTPResponse {
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
            return response
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
```

Update `shouldRetry(response:attempt:)` to include `423` only when Webex sends `Retry-After`:

```swift
private func shouldRetry(response: HTTPResponse, attempt: Int) -> Bool {
    guard attempt < retryPolicy.maxAttempts else {
        return false
    }

    if response.response.statusCode == 423 {
        return retryPolicy.retryAfter(from: response.response) != nil
    }

    return response.response.statusCode == 429 || response.response.statusCode >= 500
}
```

Update `responseError(for:accessToken:)` so exhausted or non-retryable `423`
keeps structured retry context:

```swift
private func responseError(for response: HTTPResponse, accessToken: String) -> WebexSDKError {
    if response.response.statusCode == 429 {
        return .rateLimited(retryAfter: retryPolicy.retryAfter(from: response.response))
    }

    if response.response.statusCode == 423 {
        return .locked(
            retryAfter: retryPolicy.retryAfter(from: response.response),
            trackingID: trackingID(from: response.response),
            message: responseMessage(from: response, accessToken: accessToken)
        )
    }

    return .webexAPI(
        statusCode: response.response.statusCode,
        trackingID: trackingID(from: response.response),
        message: responseMessage(from: response, accessToken: accessToken)
    )
}
```

- [ ] **Step 5: Run focused transport tests**

Run:

```bash
swift test --filter WebexTransportTests
```

Expected: all `WebexTransportTests` pass.

- [ ] **Step 6: Commit Task 1**

Run:

```bash
git add Sources/WebexSwiftSDK/Core/WebexSDKError.swift Sources/WebexSwiftSDK/HTTP/WebexTransport.swift Tests/WebexSwiftSDKTests/WebexTransportTests.swift
git commit -m "feat: classify Webex API statuses"
```

---

## Task 2: RFC5988 Page Link Parser

**Files:**
- Create: `Sources/WebexSwiftSDK/HTTP/WebexPageLink.swift`
- Create: `Tests/WebexSwiftSDKTests/WebexPageLinkTests.swift`

- [ ] **Step 1: Write failing page link tests**

Create `Tests/WebexSwiftSDKTests/WebexPageLinkTests.swift`:

```swift
import XCTest
@testable import WebexSwiftSDK

final class WebexPageLinkTests: XCTestCase {
    func testExtractsNextLinkFromRFC5988Header() throws {
        let response = httpResponse(headers: [
            "Link": #"<https://webexapis.com/v1/rooms?max=2&cursor=abc>; rel="next""#
        ])

        let link = try XCTUnwrap(WebexPageLink.next(from: response))

        XCTAssertEqual(link.url.absoluteString, "https://webexapis.com/v1/rooms?max=2&cursor=abc")
        XCTAssertEqual(link.request.path, "/v1/rooms")
        XCTAssertEqual(link.request.queryItems, [
            URLQueryItem(name: "max", value: "2"),
            URLQueryItem(name: "cursor", value: "abc")
        ])
    }

    func testIgnoresFirstAndPrevWhenNextIsAbsent() {
        let response = httpResponse(headers: [
            "Link": #"<https://webexapis.com/v1/rooms?page=1>; rel="first", <https://webexapis.com/v1/rooms?page=0>; rel="prev""#
        ])

        XCTAssertNil(WebexPageLink.next(from: response))
    }

    func testFindsNextAmongMultipleRelationsAndHeaderCaseVariants() throws {
        let response = httpResponse(headers: [
            "link": #"<https://webexapis.com/v1/rooms?page=1>; rel="first", <https://webexapis.com/v1/rooms?page=2>; rel="next""#
        ])

        let link = try XCTUnwrap(WebexPageLink.next(from: response))

        XCTAssertEqual(link.url.absoluteString, "https://webexapis.com/v1/rooms?page=2")
    }

    func testRejectsNonWebexNextLink() {
        let response = httpResponse(headers: [
            "Link": #"<https://evil.example/v1/rooms?page=2>; rel="next""#
        ])

        XCTAssertNil(WebexPageLink.next(from: response))
    }

    private func httpResponse(headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://webexapis.com/v1/rooms")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }
}
```

- [ ] **Step 2: Run the failing page link test**

Run:

```bash
swift test --filter WebexPageLinkTests/testExtractsNextLinkFromRFC5988Header
```

Expected: compile failure because `WebexPageLink` does not exist.

- [ ] **Step 3: Implement WebexPageLink**

Create `Sources/WebexSwiftSDK/HTTP/WebexPageLink.swift`:

```swift
import Foundation

public struct WebexPageLink: Equatable, Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public var request: WebexRequest {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return WebexRequest(
            path: url.path,
            queryItems: components?.queryItems ?? []
        )
    }

    public static func next(from response: HTTPURLResponse) -> WebexPageLink? {
        guard let header = linkHeader(from: response) else {
            return nil
        }

        for segment in splitLinkHeader(header) {
            guard let parsed = parse(segment),
                  parsed.relation == "next",
                  parsed.url.scheme == "https",
                  parsed.url.host == "webexapis.com" else {
                continue
            }

            return WebexPageLink(url: parsed.url)
        }

        return nil
    }

    private static func linkHeader(from response: HTTPURLResponse) -> String? {
        for (key, value) in response.allHeaderFields {
            guard String(describing: key).caseInsensitiveCompare("Link") == .orderedSame else {
                continue
            }

            return String(describing: value)
        }

        return nil
    }

    private static func splitLinkHeader(_ header: String) -> [String] {
        var segments: [String] = []
        var current = ""
        var isInsideQuotes = false

        for character in header {
            if character == "\"" {
                isInsideQuotes.toggle()
            }

            if character == ",", !isInsideQuotes {
                segments.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
                continue
            }

            current.append(character)
        }

        let finalSegment = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalSegment.isEmpty {
            segments.append(finalSegment)
        }

        return segments
    }

    private static func parse(_ segment: String) -> (url: URL, relation: String)? {
        guard let urlStart = segment.firstIndex(of: "<"),
              let urlEnd = segment[urlStart...].firstIndex(of: ">") else {
            return nil
        }

        let rawURL = String(segment[segment.index(after: urlStart)..<urlEnd])
        guard let url = URL(string: rawURL) else {
            return nil
        }

        let parameters = segment[segment.index(after: urlEnd)...]
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        for parameter in parameters {
            let parts = parameter.split(separator: "=", maxSplits: 1)
            guard parts.count == 2,
                  parts[0].caseInsensitiveCompare("rel") == .orderedSame else {
                continue
            }

            let relation = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return (url, relation)
        }

        return nil
    }
}
```

- [ ] **Step 4: Run page link tests**

Run:

```bash
swift test --filter WebexPageLinkTests
```

Expected: all `WebexPageLinkTests` pass.

- [ ] **Step 5: Commit Task 2**

Run:

```bash
git add Sources/WebexSwiftSDK/HTTP/WebexPageLink.swift Tests/WebexSwiftSDKTests/WebexPageLinkTests.swift
git commit -m "feat: parse Webex pagination links"
```

---

## Task 3: Space Models And Webex Date Decoding

**Files:**
- Create: `Sources/WebexSwiftSDK/Core/WebexDateDecoding.swift`
- Create: `Sources/WebexSwiftSDK/API/WebexSpace.swift`
- Create: `Tests/WebexSwiftSDKTests/SpacesAPITests.swift`

- [ ] **Step 1: Write failing model decoding tests**

Create `Tests/WebexSwiftSDKTests/SpacesAPITests.swift` with model-focused tests and shared helpers:

```swift
import XCTest
@testable import WebexSwiftSDK

final class SpacesAPITests: XCTestCase {
    func testSpaceDecodesKnownFieldsAndPartialErrors() throws {
        let json = Data("""
        {
          "id": "space-id",
          "title": "Incident Review",
          "type": "group",
          "isLocked": true,
          "teamId": "team-id",
          "lastActivity": "2026-04-30T18:01:02.123Z",
          "creatorId": "creator-id",
          "created": "2026-04-29T17:00:00Z",
          "ownerId": "owner-id",
          "description": "Postmortem space",
          "isPublic": true,
          "isReadOnly": false,
          "isAnnouncementOnly": true,
          "classificationId": "classification-id",
          "madePublic": "2026-04-30T19:00:00.000Z",
          "errors": {
            "title": {
              "code": "kms_failure",
              "reason": "Could not decrypt title"
            }
          }
        }
        """.utf8)

        let space = try JSONDecoder().decode(WebexSpace.self, from: json)

        XCTAssertEqual(space.id, "space-id")
        XCTAssertEqual(space.title, "Incident Review")
        XCTAssertEqual(space.type, .group)
        XCTAssertEqual(space.isLocked, true)
        XCTAssertEqual(space.teamID, "team-id")
        XCTAssertEqual(space.creatorID, "creator-id")
        XCTAssertEqual(space.ownerID, "owner-id")
        XCTAssertEqual(space.description, "Postmortem space")
        XCTAssertEqual(space.isPublic, true)
        XCTAssertEqual(space.isReadOnly, false)
        XCTAssertEqual(space.isAnnouncementOnly, true)
        XCTAssertEqual(space.classificationID, "classification-id")
        XCTAssertEqual(space.errors?["title"], WebexPartialResourceError(code: "kms_failure", reason: "Could not decrypt title"))
        XCTAssertEqual(iso8601(space.lastActivity), "2026-04-30T18:01:02Z")
        XCTAssertEqual(iso8601(space.created), "2026-04-29T17:00:00Z")
        XCTAssertEqual(iso8601(space.madePublic), "2026-04-30T19:00:00Z")
    }

    func testSpaceTypePreservesUnknownValues() throws {
        let json = Data(#"{"id":"space-id","type":"future-type"}"#.utf8)

        let space = try JSONDecoder().decode(WebexSpace.self, from: json)

        XCTAssertEqual(space.type, .unknown("future-type"))
    }

    private func iso8601(_ date: Date?) -> String? {
        guard let date else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
```

- [ ] **Step 2: Run the failing model tests**

Run:

```bash
swift test --filter SpacesAPITests/testSpaceDecodesKnownFieldsAndPartialErrors
swift test --filter SpacesAPITests/testSpaceTypePreservesUnknownValues
```

Expected: compile failure because `WebexSpace`, `WebexSpaceType`, and `WebexPartialResourceError` do not exist.

- [ ] **Step 3: Implement date decoding helper**

Create `Sources/WebexSwiftSDK/Core/WebexDateDecoding.swift`:

```swift
import Foundation

enum WebexDateDecoding {
    static func decodeIfPresent<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> Date? {
        guard let value = try container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }

        if let date = parse(value) {
            return date
        }

        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "Invalid Webex timestamp"
        )
    }

    private static func parse(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
```

- [ ] **Step 4: Implement Space models**

Create `Sources/WebexSwiftSDK/API/WebexSpace.swift`:

```swift
import Foundation

public struct WebexPartialResourceError: Equatable, Decodable, Sendable {
    public let code: String
    public let reason: String

    public init(code: String, reason: String) {
        self.code = code
        self.reason = reason
    }
}

public enum WebexSpaceType: Equatable, Sendable {
    case direct
    case group
    case unknown(String)
}

extension WebexSpaceType: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        switch value {
        case "direct":
            self = .direct
        case "group":
            self = .group
        default:
            self = .unknown(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var rawValue: String {
        switch self {
        case .direct:
            return "direct"
        case .group:
            return "group"
        case .unknown(let value):
            return value
        }
    }
}

public struct WebexSpace: Equatable, Decodable, Sendable {
    public let id: String
    public let title: String?
    public let type: WebexSpaceType?
    public let isLocked: Bool?
    public let teamID: String?
    public let lastActivity: Date?
    public let creatorID: String?
    public let created: Date?
    public let ownerID: String?
    public let description: String?
    public let isPublic: Bool?
    public let isReadOnly: Bool?
    public let isAnnouncementOnly: Bool?
    public let classificationID: String?
    public let madePublic: Date?
    public let errors: [String: WebexPartialResourceError]?

    public init(
        id: String,
        title: String? = nil,
        type: WebexSpaceType? = nil,
        isLocked: Bool? = nil,
        teamID: String? = nil,
        lastActivity: Date? = nil,
        creatorID: String? = nil,
        created: Date? = nil,
        ownerID: String? = nil,
        description: String? = nil,
        isPublic: Bool? = nil,
        isReadOnly: Bool? = nil,
        isAnnouncementOnly: Bool? = nil,
        classificationID: String? = nil,
        madePublic: Date? = nil,
        errors: [String: WebexPartialResourceError]? = nil
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.isLocked = isLocked
        self.teamID = teamID
        self.lastActivity = lastActivity
        self.creatorID = creatorID
        self.created = created
        self.ownerID = ownerID
        self.description = description
        self.isPublic = isPublic
        self.isReadOnly = isReadOnly
        self.isAnnouncementOnly = isAnnouncementOnly
        self.classificationID = classificationID
        self.madePublic = madePublic
        self.errors = errors
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case type
        case isLocked
        case teamID = "teamId"
        case lastActivity
        case creatorID = "creatorId"
        case created
        case ownerID = "ownerId"
        case description
        case isPublic
        case isReadOnly
        case isAnnouncementOnly
        case classificationID = "classificationId"
        case madePublic
        case errors
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.type = try container.decodeIfPresent(WebexSpaceType.self, forKey: .type)
        self.isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked)
        self.teamID = try container.decodeIfPresent(String.self, forKey: .teamID)
        self.lastActivity = try WebexDateDecoding.decodeIfPresent(from: container, forKey: .lastActivity)
        self.creatorID = try container.decodeIfPresent(String.self, forKey: .creatorID)
        self.created = try WebexDateDecoding.decodeIfPresent(from: container, forKey: .created)
        self.ownerID = try container.decodeIfPresent(String.self, forKey: .ownerID)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.isPublic = try container.decodeIfPresent(Bool.self, forKey: .isPublic)
        self.isReadOnly = try container.decodeIfPresent(Bool.self, forKey: .isReadOnly)
        self.isAnnouncementOnly = try container.decodeIfPresent(Bool.self, forKey: .isAnnouncementOnly)
        self.classificationID = try container.decodeIfPresent(String.self, forKey: .classificationID)
        self.madePublic = try WebexDateDecoding.decodeIfPresent(from: container, forKey: .madePublic)
        self.errors = try container.decodeIfPresent([String: WebexPartialResourceError].self, forKey: .errors)
    }
}

public typealias WebexRoom = WebexSpace
```

- [ ] **Step 5: Run model tests**

Run:

```bash
swift test --filter SpacesAPITests/testSpaceDecodesKnownFieldsAndPartialErrors
swift test --filter SpacesAPITests/testSpaceTypePreservesUnknownValues
```

Expected: both tests pass.

- [ ] **Step 6: Commit Task 3**

Run:

```bash
git add Sources/WebexSwiftSDK/Core/WebexDateDecoding.swift Sources/WebexSwiftSDK/API/WebexSpace.swift Tests/WebexSwiftSDKTests/SpacesAPITests.swift
git commit -m "feat: model Webex spaces"
```

---

## Task 4: List Spaces And Pagination

**Files:**
- Create: `Sources/WebexSwiftSDK/API/SpacesAPI.swift`
- Modify: `Tests/WebexSwiftSDKTests/SpacesAPITests.swift`

- [ ] **Step 1: Add failing list and pagination tests**

Append these tests to `SpacesAPITests`, before `iso8601(_:)`:

```swift
func testListSpacesSendsTypedQueryAndDecodesPage() async throws {
    let httpClient = MockSpacesHTTPClient()
    await httpClient.enqueue(response: httpResponse(
        statusCode: 200,
        headers: ["Link": #"<https://webexapis.com/v1/rooms?cursor=next>; rel="next""#],
        body: #"{"items":[{"id":"space-1","title":"One","type":"group"}]}"#
    ))
    let api = makeAPI(httpClient: httpClient)

    let page = try await api.list(query: ListSpacesQuery(
        teamID: "team-1",
        type: .group,
        sortBy: .lastActivity,
        max: 50
    ))

    XCTAssertEqual(page.items.map(\.id), ["space-1"])
    XCTAssertEqual(page.nextPage?.url.absoluteString, "https://webexapis.com/v1/rooms?cursor=next")
    let requests = await httpClient.recordedRequests()
    XCTAssertEqual(requests.count, 1)
    XCTAssertEqual(
        requests[0].url?.absoluteString,
        "https://webexapis.com/v1/rooms?teamId=team-1&type=group&sortBy=lastactivity&max=50"
    )
    XCTAssertEqual(requests[0].httpMethod, "GET")
    XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer spaces-token")
}

func testListAllFollowsNextLinksThroughEmptyPages() async throws {
    let httpClient = MockSpacesHTTPClient()
    await httpClient.enqueue(response: httpResponse(
        statusCode: 200,
        headers: ["Link": #"<https://webexapis.com/v1/rooms?cursor=second>; rel="next""#],
        body: #"{"items":[{"id":"space-1","title":"One"}]}"#
    ))
    await httpClient.enqueue(response: httpResponse(
        statusCode: 200,
        headers: ["Link": #"<https://webexapis.com/v1/rooms?cursor=third>; rel="next""#],
        body: #"{"items":[]}"#
    ))
    await httpClient.enqueue(response: httpResponse(
        statusCode: 200,
        body: #"{"items":[{"id":"space-3","title":"Three"}]}"#
    ))
    let api = makeAPI(httpClient: httpClient)

    let spaces = try await api.listAll(query: .init(max: 2))

    XCTAssertEqual(spaces.map(\.id), ["space-1", "space-3"])
    let requests = await httpClient.recordedRequests()
    XCTAssertEqual(requests.map { $0.url?.absoluteString }, [
        "https://webexapis.com/v1/rooms?max=2",
        "https://webexapis.com/v1/rooms?cursor=second",
        "https://webexapis.com/v1/rooms?cursor=third"
    ])
}
```

Append these helpers after `SpacesAPITests`:

```swift
private func makeAPI(httpClient: HTTPClient) -> SpacesAPI {
    SpacesAPI(transport: WebexTransport(httpClient: httpClient) {
        AccessTokenState(
            value: "spaces-token",
            expiresAt: Date(timeIntervalSince1970: 1_000),
            tokenType: "Bearer"
        )
    })
}

private func httpResponse(
    statusCode: Int,
    headers: [String: String] = [:],
    body: String
) -> HTTPResponse {
    HTTPResponse(
        data: Data(body.utf8),
        response: HTTPURLResponse(
            url: URL(string: "https://webexapis.com/v1/rooms")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    )
}

private actor MockSpacesHTTPClient: HTTPClient {
    private var responses: [HTTPResponse] = []
    private var requests: [URLRequest] = []

    func enqueue(response: HTTPResponse) {
        responses.append(response)
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else {
            throw WebexSDKError.network("Unexpected spaces request")
        }

        return responses.removeFirst()
    }
}
```

- [ ] **Step 2: Run failing list tests**

Run:

```bash
swift test --filter SpacesAPITests/testListSpacesSendsTypedQueryAndDecodesPage
swift test --filter SpacesAPITests/testListAllFollowsNextLinksThroughEmptyPages
```

Expected: compile failure because `SpacesAPI`, `ListSpacesQuery`, and `WebexSpaceListPage` do not exist.

- [ ] **Step 3: Implement SpacesAPI list support**

Create `Sources/WebexSwiftSDK/API/SpacesAPI.swift`:

```swift
import Foundation

public enum WebexSpaceSort: String, Equatable, Sendable {
    case id
    case lastActivity = "lastactivity"
    case created
}

public struct ListSpacesQuery: Equatable, Sendable {
    public let teamID: String?
    public let type: WebexSpaceType?
    public let sortBy: WebexSpaceSort?
    public let max: Int?

    public init(
        teamID: String? = nil,
        type: WebexSpaceType? = nil,
        sortBy: WebexSpaceSort? = nil,
        max: Int? = nil
    ) {
        self.teamID = teamID
        self.type = type
        self.sortBy = sortBy
        self.max = max
    }

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let teamID {
            items.append(URLQueryItem(name: "teamId", value: teamID))
        }
        if let type {
            items.append(URLQueryItem(name: "type", value: type.rawValue))
        }
        if let sortBy {
            items.append(URLQueryItem(name: "sortBy", value: sortBy.rawValue))
        }
        if let max {
            items.append(URLQueryItem(name: "max", value: String(max)))
        }
        return items
    }
}

public struct WebexSpaceListPage: Equatable, Sendable {
    public let items: [WebexSpace]
    public let nextPage: WebexPageLink?

    public init(items: [WebexSpace], nextPage: WebexPageLink?) {
        self.items = items
        self.nextPage = nextPage
    }
}

public struct SpacesAPI: Sendable {
    private let transport: WebexTransport

    public init(transport: WebexTransport) {
        self.transport = transport
    }

    public func list(query: ListSpacesQuery = ListSpacesQuery()) async throws -> WebexSpaceListPage {
        try await list(request: WebexRequest(
            path: "/v1/rooms",
            queryItems: query.queryItems
        ))
    }

    public func listAll(query: ListSpacesQuery = ListSpacesQuery()) async throws -> [WebexSpace] {
        var page = try await list(query: query)
        var spaces = page.items

        while let nextPage = page.nextPage {
            try Task.checkCancellation()
            page = try await list(request: nextPage.request)
            spaces.append(contentsOf: page.items)
        }

        return spaces
    }

    private func list(request: WebexRequest) async throws -> WebexSpaceListPage {
        let response = try await transport.sendResponse(request)
        let envelope = try JSONDecoder().decode(WebexSpaceListEnvelope.self, from: response.data)
        return WebexSpaceListPage(
            items: envelope.items,
            nextPage: WebexPageLink.next(from: response.response)
        )
    }
}

private struct WebexSpaceListEnvelope: Decodable {
    let items: [WebexSpace]
}

public typealias RoomsAPI = SpacesAPI
public typealias ListRoomsQuery = ListSpacesQuery
```

- [ ] **Step 4: Run list tests**

Run:

```bash
swift test --filter SpacesAPITests/testListSpacesSendsTypedQueryAndDecodesPage
swift test --filter SpacesAPITests/testListAllFollowsNextLinksThroughEmptyPages
```

Expected: both tests pass.

- [ ] **Step 5: Commit Task 4**

Run:

```bash
git add Sources/WebexSwiftSDK/API/SpacesAPI.swift Tests/WebexSwiftSDKTests/SpacesAPITests.swift
git commit -m "feat: list Webex spaces"
```

---

## Task 5: Create, Get, Update, Delete, And Client Aliases

**Files:**
- Modify: `Sources/WebexSwiftSDK/API/SpacesAPI.swift`
- Modify: `Sources/WebexSwiftSDK/WebexClient.swift`
- Modify: `Tests/WebexSwiftSDKTests/SpacesAPITests.swift`

- [ ] **Step 1: Add failing CRUD and client alias tests**

Append these tests to `SpacesAPITests`, before `iso8601(_:)`:

```swift
func testCreateSpacePostsJSONAndDecodesCreatedSpace() async throws {
    let httpClient = MockSpacesHTTPClient()
    await httpClient.enqueue(response: httpResponse(
        statusCode: 201,
        body: #"{"id":"created-space","title":"Incident Review","type":"group"}"#
    ))
    let api = makeAPI(httpClient: httpClient)

    let space = try await api.create(CreateSpaceRequest(
        title: "Incident Review",
        teamID: "team-id",
        classificationID: "classification-id",
        isLocked: true,
        isPublic: true,
        description: "Public incident room",
        isAnnouncementOnly: true
    ))

    XCTAssertEqual(space.id, "created-space")
    XCTAssertEqual(space.title, "Incident Review")
    let request = try XCTUnwrap(await httpClient.recordedRequests().first)
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.url?.absoluteString, "https://webexapis.com/v1/rooms")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    let body = try XCTUnwrap(request.httpBody)
    let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    XCTAssertEqual(json?["title"] as? String, "Incident Review")
    XCTAssertEqual(json?["teamId"] as? String, "team-id")
    XCTAssertEqual(json?["classificationId"] as? String, "classification-id")
    XCTAssertEqual(json?["isLocked"] as? Bool, true)
    XCTAssertEqual(json?["isPublic"] as? Bool, true)
    XCTAssertEqual(json?["description"] as? String, "Public incident room")
    XCTAssertEqual(json?["isAnnouncementOnly"] as? Bool, true)
}

func testGetSpacePercentEncodesPathSegment() async throws {
    let httpClient = MockSpacesHTTPClient()
    await httpClient.enqueue(response: httpResponse(
        statusCode: 200,
        body: #"{"id":"room/id+1","title":"Encoded"}"#
    ))
    let api = makeAPI(httpClient: httpClient)

    let space = try await api.get(spaceID: "room/id+1")

    XCTAssertEqual(space.id, "room/id+1")
    let request = try XCTUnwrap(await httpClient.recordedRequests().first)
    XCTAssertEqual(request.httpMethod, "GET")
    XCTAssertEqual(request.url?.absoluteString, "https://webexapis.com/v1/rooms/room%2Fid+1")
}

func testUpdateSpacePutsOnlyProvidedFields() async throws {
    let httpClient = MockSpacesHTTPClient()
    await httpClient.enqueue(response: httpResponse(
        statusCode: 200,
        body: #"{"id":"space-id","title":"Updated"}"#
    ))
    let api = makeAPI(httpClient: httpClient)

    let space = try await api.update(spaceID: "space-id", UpdateSpaceRequest(
        title: "Updated",
        description: "Updated description",
        isLocked: false
    ))

    XCTAssertEqual(space.title, "Updated")
    let request = try XCTUnwrap(await httpClient.recordedRequests().first)
    XCTAssertEqual(request.httpMethod, "PUT")
    XCTAssertEqual(request.url?.absoluteString, "https://webexapis.com/v1/rooms/space-id")
    let body = try XCTUnwrap(request.httpBody)
    let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    XCTAssertEqual(json?["title"] as? String, "Updated")
    XCTAssertEqual(json?["description"] as? String, "Updated description")
    XCTAssertEqual(json?["isLocked"] as? Bool, false)
    XCTAssertNil(json?["teamId"])
    XCTAssertNil(json?["creatorId"])
}

func testDeleteSpaceSendsDeleteAndAcceptsNoContent() async throws {
    let httpClient = MockSpacesHTTPClient()
    await httpClient.enqueue(response: httpResponse(statusCode: 204, body: ""))
    let api = makeAPI(httpClient: httpClient)

    try await api.delete(spaceID: "space-id")

    let request = try XCTUnwrap(await httpClient.recordedRequests().first)
    XCTAssertEqual(request.httpMethod, "DELETE")
    XCTAssertEqual(request.url?.absoluteString, "https://webexapis.com/v1/rooms/space-id")
}

func testWebexClientExposesSpacesAndRoomsAlias() async throws {
    let accountID = WebexAccountID()
    let store = InMemoryWebexStore()
    let httpClient = MockSpacesHTTPClient()
    await httpClient.enqueue(response: httpResponse(
        statusCode: 200,
        body: #"{"items":[{"id":"space-from-spaces"}]}"#
    ))
    await httpClient.enqueue(response: httpResponse(
        statusCode: 200,
        body: #"{"items":[{"id":"space-from-rooms"}]}"#
    ))
    let client = WebexClient(
        accountID: accountID,
        configuration: WebexIntegrationConfiguration(
            clientID: "client",
            clientSecret: "secret",
            redirectURI: URL(string: "myapp://oauth/webex")!,
            scopes: ["spark:rooms_read"]
        ),
        tokenStore: store,
        httpClient: httpClient,
        initialAccessToken: AccessTokenState(
            value: "client-token",
            expiresAt: Date(timeIntervalSince1970: 1_000),
            tokenType: "Bearer"
        )
    )

    let spaces = try await client.spaces.list()
    let rooms = try await client.rooms.list()

    XCTAssertEqual(spaces.items.map(\.id), ["space-from-spaces"])
    XCTAssertEqual(rooms.items.map(\.id), ["space-from-rooms"])
}
```

- [ ] **Step 2: Run failing CRUD and alias tests**

Run:

```bash
swift test --filter SpacesAPITests/testCreateSpacePostsJSONAndDecodesCreatedSpace
swift test --filter SpacesAPITests/testGetSpacePercentEncodesPathSegment
swift test --filter SpacesAPITests/testUpdateSpacePutsOnlyProvidedFields
swift test --filter SpacesAPITests/testDeleteSpaceSendsDeleteAndAcceptsNoContent
swift test --filter SpacesAPITests/testWebexClientExposesSpacesAndRoomsAlias
```

Expected: compile failure because create/get/update/delete methods and `client.spaces` do not exist.

- [ ] **Step 3: Implement request models and CRUD methods**

Add these request types to `SpacesAPI.swift` above `public struct SpacesAPI`:

```swift
public struct CreateSpaceRequest: Encodable, Equatable, Sendable {
    public let title: String
    public let teamID: String?
    public let classificationID: String?
    public let isLocked: Bool?
    public let isPublic: Bool?
    public let description: String?
    public let isAnnouncementOnly: Bool?

    public init(
        title: String,
        teamID: String? = nil,
        classificationID: String? = nil,
        isLocked: Bool? = nil,
        isPublic: Bool? = nil,
        description: String? = nil,
        isAnnouncementOnly: Bool? = nil
    ) {
        self.title = title
        self.teamID = teamID
        self.classificationID = classificationID
        self.isLocked = isLocked
        self.isPublic = isPublic
        self.description = description
        self.isAnnouncementOnly = isAnnouncementOnly
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case teamID = "teamId"
        case classificationID = "classificationId"
        case isLocked
        case isPublic
        case description
        case isAnnouncementOnly
    }
}

public struct UpdateSpaceRequest: Encodable, Equatable, Sendable {
    public let title: String?
    public let teamID: String?
    public let classificationID: String?
    public let isLocked: Bool?
    public let isPublic: Bool?
    public let description: String?
    public let isAnnouncementOnly: Bool?
    public let isReadOnly: Bool?

    public init(
        title: String? = nil,
        teamID: String? = nil,
        classificationID: String? = nil,
        isLocked: Bool? = nil,
        isPublic: Bool? = nil,
        description: String? = nil,
        isAnnouncementOnly: Bool? = nil,
        isReadOnly: Bool? = nil
    ) {
        self.title = title
        self.teamID = teamID
        self.classificationID = classificationID
        self.isLocked = isLocked
        self.isPublic = isPublic
        self.description = description
        self.isAnnouncementOnly = isAnnouncementOnly
        self.isReadOnly = isReadOnly
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case teamID = "teamId"
        case classificationID = "classificationId"
        case isLocked
        case isPublic
        case description
        case isAnnouncementOnly
        case isReadOnly
    }
}

public typealias CreateRoomRequest = CreateSpaceRequest
public typealias UpdateRoomRequest = UpdateSpaceRequest
```

Add these methods inside `SpacesAPI` after `listAll(query:)`:

```swift
public func create(_ request: CreateSpaceRequest) async throws -> WebexSpace {
    let body = try JSONEncoder().encode(request)
    let data = try await transport.send(WebexRequest(
        method: "POST",
        path: "/v1/rooms",
        body: body
    ))
    return try JSONDecoder().decode(WebexSpace.self, from: data)
}

public func get(spaceID: String) async throws -> WebexSpace {
    let data = try await transport.send(WebexRequest(
        path: try spacePath(spaceID)
    ))
    return try JSONDecoder().decode(WebexSpace.self, from: data)
}

public func update(spaceID: String, _ request: UpdateSpaceRequest) async throws -> WebexSpace {
    let body = try JSONEncoder().encode(request)
    let data = try await transport.send(WebexRequest(
        method: "PUT",
        path: try spacePath(spaceID),
        body: body
    ))
    return try JSONDecoder().decode(WebexSpace.self, from: data)
}

public func delete(spaceID: String) async throws {
    _ = try await transport.send(WebexRequest(
        method: "DELETE",
        path: try spacePath(spaceID)
    ))
}

private func spacePath(_ spaceID: String) throws -> String {
    let trimmedID = spaceID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedID.isEmpty else {
        throw WebexSDKError.network("Invalid Webex space ID")
    }

    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/?#")

    guard let encodedID = trimmedID.addingPercentEncoding(withAllowedCharacters: allowed),
          !encodedID.isEmpty else {
        throw WebexSDKError.network("Invalid Webex space ID")
    }

    return "/v1/rooms/\(encodedID)"
}
```

- [ ] **Step 4: Add Spaces and Rooms to WebexClient**

Modify `WebexClient.swift`:

```swift
public struct WebexClient: Sendable {
    public let accountID: WebexAccountID
    public let people: PeopleAPI
    public let spaces: SpacesAPI

    public var rooms: RoomsAPI {
        spaces
    }

    private let tokenManager: TokenManager
```

Inside the initializer, after `self.people = PeopleAPI(transport: transport)`, add:

```swift
self.spaces = SpacesAPI(transport: transport)
```

- [ ] **Step 5: Run CRUD and alias tests**

Run:

```bash
swift test --filter SpacesAPITests
```

Expected: all `SpacesAPITests` pass.

- [ ] **Step 6: Commit Task 5**

Run:

```bash
git add Sources/WebexSwiftSDK/API/SpacesAPI.swift Sources/WebexSwiftSDK/WebexClient.swift Tests/WebexSwiftSDKTests/SpacesAPITests.swift
git commit -m "feat: add Webex Spaces API"
```

---

## Task 6: Documentation, Final Verification, And Release Readiness

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add README Spaces example**

Append this section to `README.md` after the existing usage content:

````markdown
## Spaces

Webex's REST API still uses `/v1/rooms`, while modern product language calls
these collaboration containers spaces. The SDK exposes `client.spaces` as the
preferred interface and `client.rooms` as a compatibility alias.

```swift
let page = try await client.spaces.list(query: .init(max: 50))
for space in page.items {
    print(space.id, space.title ?? "(untitled)")
}

let allSpaces = try await client.spaces.listAll(query: .init(type: .group))
let created = try await client.spaces.create(.init(title: "Incident Review"))
let updated = try await client.spaces.update(
    spaceID: created.id,
    .init(title: "Incident Review - Closed")
)
try await client.spaces.delete(spaceID: updated.id)
```

For developers following Webex's endpoint reference, `client.rooms` maps to the
same implementation as `client.spaces`.
````

- [ ] **Step 2: Run full verification**

Run:

```bash
git diff --check
swift test
swift build
```

Expected:

- `git diff --check` exits 0.
- `swift test` passes all non-opt-in tests.
- `swift build` exits 0.

- [ ] **Step 3: Inspect public API naming**

Run:

```bash
rg -n "meetingInfo|MeetingInfo|meetingInfo\\(" Sources Tests README.md .agents docs
rg -n "client\\.rooms|RoomsAPI|WebexRoom|ListRoomsQuery|CreateRoomRequest|UpdateRoomRequest" Sources Tests README.md
rg -n "client\\.spaces|SpacesAPI|WebexSpace|ListSpacesQuery|CreateSpaceRequest|UpdateSpaceRequest" Sources Tests README.md
```

Expected:

- `meetingInfo` appears only in docs/spec notes explaining EOL exclusion.
- Room aliases appear in source/tests/docs.
- Space primary names appear in source/tests/docs.

- [ ] **Step 4: Commit Task 6**

Run:

```bash
git add README.md
git commit -m "docs: add Spaces API usage"
```

- [ ] **Step 5: Summarize release-readiness**

Run:

```bash
git status --short --branch
git log --oneline --decorate -6
```

Expected:

- Working tree is clean.
- The branch contains the design commit plus implementation commits.
- The branch remains `agentic/webex-rooms-api-v1.1.0`.

Record in the final implementation summary:

- Full test result.
- Whether opt-in Keychain tests were skipped.
- The exact commits created.
- Any Webex endpoint field uncertainty discovered during implementation.
