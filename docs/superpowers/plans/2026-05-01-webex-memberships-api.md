# Webex Memberships API Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a typed `client.memberships` SDK surface over Webex's `/v1/memberships` endpoints for normal user and bot membership management.

**Architecture:** Follow the established `SpacesAPI` pattern: `WebexClient` owns typed API groups backed by one authenticated `WebexTransport`. Memberships gets its own focused model/API files and tests, while reusing existing pagination link parsing, date decoding, retry/backoff, and path safety patterns. Compliance Officer convenience flows remain documented but out of scope.

**Tech Stack:** Swift 5.9, SwiftPM, XCTest, Foundation `URLSession`, Webex REST API, RFC5988 `Link` headers.

---

## File Structure

- Create `Sources/WebexSwiftSDK/API/WebexMembership.swift`
  - Defines `WebexMembership` and decodes known Memberships fields.
  - Reuses `WebexSpaceType` for `roomType`.
  - Reuses `WebexDateDecoding` for `created`.
- Create `Sources/WebexSwiftSDK/API/MembershipsAPI.swift`
  - Defines `ListMembershipsQuery`, `WebexMembershipListPage`, `CreateMembershipRequest`, `UpdateMembershipRequest`, and `MembershipsAPI`.
  - Implements list/listAll/create/get/update/delete.
  - Contains membership-specific safe path encoding and repeated pagination detection.
- Modify `Sources/WebexSwiftSDK/WebexClient.swift`
  - Adds `public let memberships: MembershipsAPI`.
- Create `Tests/WebexSwiftSDKTests/MembershipsAPITests.swift`
  - Covers model decoding, list pagination, create, get, update, delete, safe errors, and `WebexClient.memberships`.
- Create `.agents/docs/webex-memberships-api.md`
  - Captures endpoint notes, fields, scopes, non-compliance scope, and smoke-test guidance for future agents.
- Modify `README.md`
  - Adds a concise Memberships usage example.
- Create `Examples/WebexMembershipsListSmoke`
  - Safe list-only smoke gated by `WEBEX_ROOM_ID`.
  - Does not create, update, or delete memberships.

---

## Task 1: Membership Model

**Files:**
- Create: `Sources/WebexSwiftSDK/API/WebexMembership.swift`
- Create: `Tests/WebexSwiftSDKTests/MembershipsAPITests.swift`

- [ ] **Step 1: Write failing model tests**

Create `Tests/WebexSwiftSDKTests/MembershipsAPITests.swift` with:

```swift
import XCTest
@testable import WebexSwiftSDK

final class MembershipsAPITests: XCTestCase {
    func testMembershipDecodesKnownFields() throws {
        let json = Data("""
        {
          "id": "membership-id",
          "roomId": "room-id",
          "roomType": "group",
          "personId": "person-id",
          "personEmail": "person@example.com",
          "personDisplayName": "Ada Lovelace",
          "personOrgId": "org-id",
          "isModerator": true,
          "isMonitor": false,
          "isRoomHidden": true,
          "created": "2026-05-01T10:11:12.123Z"
        }
        """.utf8)

        let membership = try JSONDecoder().decode(WebexMembership.self, from: json)

        XCTAssertEqual(membership.id, "membership-id")
        XCTAssertEqual(membership.roomID, "room-id")
        XCTAssertEqual(membership.roomType, .group)
        XCTAssertEqual(membership.personID, "person-id")
        XCTAssertEqual(membership.personEmail, "person@example.com")
        XCTAssertEqual(membership.personDisplayName, "Ada Lovelace")
        XCTAssertEqual(membership.personOrgID, "org-id")
        XCTAssertEqual(membership.isModerator, true)
        XCTAssertEqual(membership.isMonitor, false)
        XCTAssertEqual(membership.isRoomHidden, true)
        XCTAssertEqual(iso8601(membership.created), "2026-05-01T10:11:12Z")
    }

    func testMembershipPreservesUnknownRoomType() throws {
        let json = Data(#"{"id":"membership-id","roomType":"future-room"}"#.utf8)

        let membership = try JSONDecoder().decode(WebexMembership.self, from: json)

        XCTAssertEqual(membership.roomType, .unknown("future-room"))
    }

    func testMembershipRejectsInvalidCreatedTimestamp() throws {
        let json = Data(#"{"id":"membership-id","created":"not-a-date"}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(WebexMembership.self, from: json)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted error, got \\(error)")
            }

            XCTAssertEqual(context.debugDescription, "Invalid Webex timestamp")
        }
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

- [ ] **Step 2: Run model tests to verify they fail**

Run:

```bash
swift test --filter MembershipsAPITests/testMembershipDecodesKnownFields
swift test --filter MembershipsAPITests/testMembershipPreservesUnknownRoomType
swift test --filter MembershipsAPITests/testMembershipRejectsInvalidCreatedTimestamp
```

Expected: compile failure because `WebexMembership` does not exist.

- [ ] **Step 3: Implement `WebexMembership`**

Create `Sources/WebexSwiftSDK/API/WebexMembership.swift`:

```swift
import Foundation

public struct WebexMembership: Equatable, Decodable, Sendable {
    public let id: String
    public let roomID: String?
    public let roomType: WebexSpaceType?
    public let personID: String?
    public let personEmail: String?
    public let personDisplayName: String?
    public let personOrgID: String?
    public let isModerator: Bool?
    public let isMonitor: Bool?
    public let isRoomHidden: Bool?
    public let created: Date?

    public init(
        id: String,
        roomID: String? = nil,
        roomType: WebexSpaceType? = nil,
        personID: String? = nil,
        personEmail: String? = nil,
        personDisplayName: String? = nil,
        personOrgID: String? = nil,
        isModerator: Bool? = nil,
        isMonitor: Bool? = nil,
        isRoomHidden: Bool? = nil,
        created: Date? = nil
    ) {
        self.id = id
        self.roomID = roomID
        self.roomType = roomType
        self.personID = personID
        self.personEmail = personEmail
        self.personDisplayName = personDisplayName
        self.personOrgID = personOrgID
        self.isModerator = isModerator
        self.isMonitor = isMonitor
        self.isRoomHidden = isRoomHidden
        self.created = created
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case roomID = "roomId"
        case roomType
        case personID = "personId"
        case personEmail
        case personDisplayName
        case personOrgID = "personOrgId"
        case isModerator
        case isMonitor
        case isRoomHidden
        case created
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.roomID = try container.decodeIfPresent(String.self, forKey: .roomID)
        self.roomType = try container.decodeIfPresent(WebexSpaceType.self, forKey: .roomType)
        self.personID = try container.decodeIfPresent(String.self, forKey: .personID)
        self.personEmail = try container.decodeIfPresent(String.self, forKey: .personEmail)
        self.personDisplayName = try container.decodeIfPresent(String.self, forKey: .personDisplayName)
        self.personOrgID = try container.decodeIfPresent(String.self, forKey: .personOrgID)
        self.isModerator = try container.decodeIfPresent(Bool.self, forKey: .isModerator)
        self.isMonitor = try container.decodeIfPresent(Bool.self, forKey: .isMonitor)
        self.isRoomHidden = try container.decodeIfPresent(Bool.self, forKey: .isRoomHidden)
        self.created = try WebexDateDecoding.decodeIfPresent(from: container, forKey: .created)
    }
}
```

- [ ] **Step 4: Run model tests to verify they pass**

Run:

```bash
swift test --filter MembershipsAPITests/testMembershipDecodesKnownFields
swift test --filter MembershipsAPITests/testMembershipPreservesUnknownRoomType
swift test --filter MembershipsAPITests/testMembershipRejectsInvalidCreatedTimestamp
```

Expected: all selected tests pass.

- [ ] **Step 5: Commit model**

```bash
git add Sources/WebexSwiftSDK/API/WebexMembership.swift Tests/WebexSwiftSDKTests/MembershipsAPITests.swift
git commit -m "feat: model Webex memberships"
```

---

## Task 2: List Memberships And Pagination

**Files:**
- Create: `Sources/WebexSwiftSDK/API/MembershipsAPI.swift`
- Modify: `Tests/WebexSwiftSDKTests/MembershipsAPITests.swift`

- [ ] **Step 1: Add failing list and pagination tests**

Append these tests inside `MembershipsAPITests`, before `iso8601(_:)`:

```swift
func testListMembershipsSendsTypedQueryAndDecodesPage() async throws {
    let httpClient = MockMembershipsHTTPClient()
    await httpClient.enqueue(response: httpResponse(
        statusCode: 200,
        headers: ["Link": #"<https://webexapis.com/v1/memberships?cursor=next>; rel="next""#],
        body: #"{"items":[{"id":"membership-1","roomId":"room-1","personEmail":"user@example.com"}]}"#
    ))
    let api = makeAPI(httpClient: httpClient)

    let page = try await api.list(query: ListMembershipsQuery(
        roomID: "room-1",
        personID: "person-1",
        personEmail: "user@example.com",
        max: 50
    ))

    XCTAssertEqual(page.items.map(\\.id), ["membership-1"])
    XCTAssertEqual(page.nextPage?.url.absoluteString, "https://webexapis.com/v1/memberships?cursor=next")
    let requests = await httpClient.recordedRequests()
    XCTAssertEqual(requests.count, 1)
    XCTAssertEqual(
        requests[0].url?.absoluteString,
        "https://webexapis.com/v1/memberships?roomId=room-1&personId=person-1&personEmail=user@example.com&max=50"
    )
    XCTAssertEqual(requests[0].httpMethod, "GET")
    XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer memberships-token")
}

func testListAllMembershipsFollowsNextLinksThroughEmptyPages() async throws {
    let httpClient = MockMembershipsHTTPClient()
    await httpClient.enqueue(response: httpResponse(
        statusCode: 200,
        headers: ["Link": #"<https://webexapis.com/v1/memberships?cursor=second>; rel="next""#],
        body: #"{"items":[{"id":"membership-1"}]}"#
    ))
    await httpClient.enqueue(response: httpResponse(
        statusCode: 200,
        headers: ["Link": #"<https://webexapis.com/v1/memberships?cursor=third>; rel="next""#],
        body: #"{"items":[]}"#
    ))
    await httpClient.enqueue(response: httpResponse(
        statusCode: 200,
        body: #"{"items":[{"id":"membership-3"}]}"#
    ))
    let api = makeAPI(httpClient: httpClient)

    let memberships = try await api.listAll(query: .init(max: 2))

    XCTAssertEqual(memberships.map(\\.id), ["membership-1", "membership-3"])
    let requests = await httpClient.recordedRequests()
    XCTAssertEqual(requests.map { $0.url?.absoluteString }, [
        "https://webexapis.com/v1/memberships?max=2",
        "https://webexapis.com/v1/memberships?cursor=second",
        "https://webexapis.com/v1/memberships?cursor=third"
    ])
}

func testListAllMembershipsRejectsPageCapWithoutLeakingURLOrToken() async throws {
    let httpClient = MockMembershipsHTTPClient()
    await httpClient.enqueue(response: httpResponse(
        statusCode: 200,
        headers: ["Link": #"<https://webexapis.com/v1/memberships?cursor=second>; rel="next""#],
        body: #"{"items":[{"id":"membership-1"}]}"#
    ))
    let api = makeAPI(httpClient: httpClient)

    do {
        _ = try await api.listAll(maxPages: 1)
        XCTFail("Expected page cap to throw")
    } catch WebexSDKError.network(let message) {
        XCTAssertEqual(message, "Memberships pagination page cap exceeded")
        XCTAssertFalse(message.contains("cursor=second"))
        XCTAssertFalse(message.contains("memberships-token"))
    } catch {
        XCTFail("Expected network error, got \\(error)")
    }

    let requests = await httpClient.recordedRequests()
    XCTAssertEqual(requests.map { $0.url?.absoluteString }, [
        "https://webexapis.com/v1/memberships"
    ])
}

func testListAllMembershipsRejectsRepeatedNextLinkBeforeRefetching() async throws {
    let httpClient = MockMembershipsHTTPClient()
    await httpClient.enqueue(response: httpResponse(
        statusCode: 200,
        headers: ["Link": #"<https://webexapis.com/v1/memberships?max=2>; rel="next""#],
        body: #"{"items":[{"id":"membership-1"}]}"#
    ))
    await httpClient.enqueue(response: httpResponse(
        statusCode: 200,
        body: #"{"items":[{"id":"membership-again"}]}"#
    ))
    let api = makeAPI(httpClient: httpClient)

    do {
        _ = try await api.listAll(query: .init(max: 2))
        XCTFail("Expected repeated initial link to throw")
    } catch WebexSDKError.network(let message) {
        XCTAssertEqual(message, "Repeated Memberships pagination link")
        XCTAssertFalse(message.contains("max=2"))
        XCTAssertFalse(message.contains("memberships-token"))
    } catch {
        XCTFail("Expected network error, got \\(error)")
    }

    let requests = await httpClient.recordedRequests()
    XCTAssertEqual(requests.map { $0.url?.absoluteString }, [
        "https://webexapis.com/v1/memberships?max=2"
    ])
}
```

Append these helpers after `MembershipsAPITests`:

```swift
private func makeAPI(httpClient: HTTPClient) -> MembershipsAPI {
    MembershipsAPI(transport: WebexTransport(httpClient: httpClient) {
        AccessTokenState(
            value: "memberships-token",
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
            url: URL(string: "https://webexapis.com/v1/memberships")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    )
}

private actor MockMembershipsHTTPClient: HTTPClient {
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
            throw WebexSDKError.network("Unexpected memberships request")
        }

        return responses.removeFirst()
    }
}
```

- [ ] **Step 2: Run list tests to verify they fail**

Run:

```bash
swift test --filter MembershipsAPITests/testListMembershipsSendsTypedQueryAndDecodesPage
swift test --filter MembershipsAPITests/testListAllMembershipsFollowsNextLinksThroughEmptyPages
swift test --filter MembershipsAPITests/testListAllMembershipsRejectsPageCapWithoutLeakingURLOrToken
swift test --filter MembershipsAPITests/testListAllMembershipsRejectsRepeatedNextLinkBeforeRefetching
```

Expected: compile failure because `MembershipsAPI`, `ListMembershipsQuery`, and `WebexMembershipListPage` do not exist.

- [ ] **Step 3: Implement list and pagination**

Create `Sources/WebexSwiftSDK/API/MembershipsAPI.swift`:

```swift
import Foundation

public struct ListMembershipsQuery: Equatable, Sendable {
    public let roomID: String?
    public let personID: String?
    public let personEmail: String?
    public let max: Int?

    public init(
        roomID: String? = nil,
        personID: String? = nil,
        personEmail: String? = nil,
        max: Int? = nil
    ) {
        self.roomID = roomID
        self.personID = personID
        self.personEmail = personEmail
        self.max = max
    }

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let roomID {
            items.append(URLQueryItem(name: "roomId", value: roomID))
        }
        if let personID {
            items.append(URLQueryItem(name: "personId", value: personID))
        }
        if let personEmail {
            items.append(URLQueryItem(name: "personEmail", value: personEmail))
        }
        if let max {
            items.append(URLQueryItem(name: "max", value: String(max)))
        }
        return items
    }
}

public struct WebexMembershipListPage: Equatable, Sendable {
    public let items: [WebexMembership]
    public let nextPage: WebexPageLink?

    public init(items: [WebexMembership], nextPage: WebexPageLink?) {
        self.items = items
        self.nextPage = nextPage
    }
}

public struct MembershipsAPI: Sendable {
    private let transport: WebexTransport

    public init(transport: WebexTransport) {
        self.transport = transport
    }

    public func list(query: ListMembershipsQuery = ListMembershipsQuery()) async throws -> WebexMembershipListPage {
        try await list(request: WebexRequest(
            path: "/v1/memberships",
            queryItems: query.queryItems
        ))
    }

    public func listAll(
        query: ListMembershipsQuery = ListMembershipsQuery(),
        maxPages: Int = 1_000
    ) async throws -> [WebexMembership] {
        guard maxPages > 0 else {
            throw WebexSDKError.network("Memberships pagination page cap must be greater than zero")
        }

        let firstRequest = WebexRequest(
            path: "/v1/memberships",
            queryItems: query.queryItems
        )
        var page = try await list(request: firstRequest)
        var pagesFetched = 1
        var seenPageRequests: Set<String> = [paginationRequestKey(firstRequest)]
        var memberships = page.items

        while let nextPage = page.nextPage {
            let nextRequest = nextPage.request

            guard pagesFetched < maxPages else {
                throw WebexSDKError.network("Memberships pagination page cap exceeded")
            }
            guard seenPageRequests.insert(paginationRequestKey(nextRequest)).inserted else {
                throw WebexSDKError.network("Repeated Memberships pagination link")
            }

            try Task.checkCancellation()
            page = try await list(request: nextRequest)
            pagesFetched += 1
            memberships.append(contentsOf: page.items)
        }

        return memberships
    }

    private func list(request: WebexRequest) async throws -> WebexMembershipListPage {
        let response = try await transport.sendResponse(request)
        let envelope = try JSONDecoder().decode(WebexMembershipListEnvelope.self, from: response.data)
        return WebexMembershipListPage(
            items: envelope.items,
            nextPage: WebexPageLink.next(from: response.response)
        )
    }

    private func paginationRequestKey(_ request: WebexRequest) -> String {
        let normalizedPath = request.path.hasPrefix("/") ? request.path : "/\(request.path)"
        let queryKey = request.queryItems
            .map { item in
                "\(item.name.count):\(item.name)=\(item.value?.count ?? -1):\(item.value ?? "")"
            }
            .sorted()
            .joined(separator: "&")

        if queryKey.isEmpty {
            return "\(request.method.uppercased()) \(normalizedPath)"
        }

        return "\(request.method.uppercased()) \(normalizedPath)?\(queryKey)"
    }
}

private struct WebexMembershipListEnvelope: Decodable {
    let items: [WebexMembership]
}
```

- [ ] **Step 4: Run list tests to verify they pass**

Run:

```bash
swift test --filter MembershipsAPITests/testListMembershipsSendsTypedQueryAndDecodesPage
swift test --filter MembershipsAPITests/testListAllMembershipsFollowsNextLinksThroughEmptyPages
swift test --filter MembershipsAPITests/testListAllMembershipsRejectsPageCapWithoutLeakingURLOrToken
swift test --filter MembershipsAPITests/testListAllMembershipsRejectsRepeatedNextLinkBeforeRefetching
```

Expected: all selected tests pass.

- [ ] **Step 5: Commit list support**

```bash
git add Sources/WebexSwiftSDK/API/MembershipsAPI.swift Tests/WebexSwiftSDKTests/MembershipsAPITests.swift
git commit -m "feat: list Webex memberships"
```

---

## Task 3: Create, Get, Update, Delete Memberships

**Files:**
- Modify: `Sources/WebexSwiftSDK/API/MembershipsAPI.swift`
- Modify: `Tests/WebexSwiftSDKTests/MembershipsAPITests.swift`

- [ ] **Step 1: Add failing CRUD tests**

Append these tests inside `MembershipsAPITests`, before `iso8601(_:)`:

```swift
func testCreateMembershipWithPersonEmailPostsJSONAndDecodesMembership() async throws {
    let httpClient = MockMembershipsHTTPClient()
    await httpClient.enqueue(response: httpResponse(
        statusCode: 200,
        body: #"{"id":"created-membership","roomId":"room-id","personEmail":"person@example.com","isModerator":true}"#
    ))
    let api = makeAPI(httpClient: httpClient)

    let membership = try await api.create(CreateMembershipRequest(
        roomID: "room-id",
        personEmail: "person@example.com",
        isModerator: true
    ))

    XCTAssertEqual(membership.id, "created-membership")
    XCTAssertEqual(membership.personEmail, "person@example.com")
    let request = try XCTUnwrap(await httpClient.recordedRequests().first)
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.url?.absoluteString, "https://webexapis.com/v1/memberships")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    let body = try XCTUnwrap(request.httpBody)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    XCTAssertEqual(Set(json.keys), ["roomId", "personEmail", "isModerator"])
    XCTAssertEqual(json["roomId"] as? String, "room-id")
    XCTAssertEqual(json["personEmail"] as? String, "person@example.com")
    XCTAssertEqual(json["isModerator"] as? Bool, true)
    XCTAssertNil(json["personId"])
}

func testCreateMembershipWithPersonIDPostsExactlyOneIdentity() async throws {
    let httpClient = MockMembershipsHTTPClient()
    await httpClient.enqueue(response: httpResponse(
        statusCode: 200,
        body: #"{"id":"created-membership","roomId":"room-id","personId":"person-id"}"#
    ))
    let api = makeAPI(httpClient: httpClient)

    _ = try await api.create(CreateMembershipRequest(roomID: "room-id", personID: "person-id"))

    let request = try XCTUnwrap(await httpClient.recordedRequests().first)
    let body = try XCTUnwrap(request.httpBody)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    XCTAssertEqual(Set(json.keys), ["roomId", "personId"])
    XCTAssertEqual(json["personId"] as? String, "person-id")
    XCTAssertNil(json["personEmail"])
}

func testGetMembershipPercentEncodesPathSegment() async throws {
    let httpClient = MockMembershipsHTTPClient()
    await httpClient.enqueue(response: httpResponse(
        statusCode: 200,
        body: #"{"id":"membership/id+1"}"#
    ))
    let api = makeAPI(httpClient: httpClient)

    let membership = try await api.get(membershipID: "membership/id+1")

    XCTAssertEqual(membership.id, "membership/id+1")
    let request = try XCTUnwrap(await httpClient.recordedRequests().first)
    XCTAssertEqual(request.httpMethod, "GET")
    XCTAssertEqual(request.url?.absoluteString, "https://webexapis.com/v1/memberships/membership%2Fid+1")
}

func testUpdateMembershipPutsOnlyMutableFields() async throws {
    let httpClient = MockMembershipsHTTPClient()
    await httpClient.enqueue(response: httpResponse(
        statusCode: 200,
        body: #"{"id":"membership-id","isModerator":true,"isRoomHidden":false}"#
    ))
    let api = makeAPI(httpClient: httpClient)

    let membership = try await api.update(membershipID: "membership-id", UpdateMembershipRequest(
        isModerator: true,
        isRoomHidden: false
    ))

    XCTAssertEqual(membership.isModerator, true)
    let request = try XCTUnwrap(await httpClient.recordedRequests().first)
    XCTAssertEqual(request.httpMethod, "PUT")
    XCTAssertEqual(request.url?.absoluteString, "https://webexapis.com/v1/memberships/membership-id")
    let body = try XCTUnwrap(request.httpBody)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    XCTAssertEqual(Set(json.keys), ["isModerator", "isRoomHidden"])
    XCTAssertEqual(json["isModerator"] as? Bool, true)
    XCTAssertEqual(json["isRoomHidden"] as? Bool, false)
    XCTAssertNil(json["roomId"])
    XCTAssertNil(json["personEmail"])
    XCTAssertNil(json["isMonitor"])
}

func testDeleteMembershipSendsDeleteAndAcceptsNoContent() async throws {
    let httpClient = MockMembershipsHTTPClient()
    await httpClient.enqueue(response: httpResponse(statusCode: 204, body: ""))
    let api = makeAPI(httpClient: httpClient)

    try await api.delete(membershipID: "membership-id")

    let request = try XCTUnwrap(await httpClient.recordedRequests().first)
    XCTAssertEqual(request.httpMethod, "DELETE")
    XCTAssertEqual(request.url?.absoluteString, "https://webexapis.com/v1/memberships/membership-id")
}

func testMembershipIDValidationFailsBeforeHTTPWithoutLeakingID() async throws {
    let httpClient = MockMembershipsHTTPClient()
    let api = makeAPI(httpClient: httpClient)

    do {
        _ = try await api.get(membershipID: "   ")
        XCTFail("Expected invalid membership ID")
    } catch WebexSDKError.network(let message) {
        XCTAssertEqual(message, "Invalid Webex membership ID")
    } catch {
        XCTFail("Expected network error, got \\(error)")
    }

    let requests = await httpClient.recordedRequests()
    XCTAssertTrue(requests.isEmpty)
}
```

- [ ] **Step 2: Run CRUD tests to verify they fail**

Run:

```bash
swift test --filter MembershipsAPITests/testCreateMembershipWithPersonEmailPostsJSONAndDecodesMembership
swift test --filter MembershipsAPITests/testCreateMembershipWithPersonIDPostsExactlyOneIdentity
swift test --filter MembershipsAPITests/testGetMembershipPercentEncodesPathSegment
swift test --filter MembershipsAPITests/testUpdateMembershipPutsOnlyMutableFields
swift test --filter MembershipsAPITests/testDeleteMembershipSendsDeleteAndAcceptsNoContent
swift test --filter MembershipsAPITests/testMembershipIDValidationFailsBeforeHTTPWithoutLeakingID
```

Expected: compile failure because create/get/update/delete request types and methods do not exist.

- [ ] **Step 3: Implement CRUD request types and methods**

Insert these request types above `public struct MembershipsAPI` in `MembershipsAPI.swift`:

```swift
public struct CreateMembershipRequest: Encodable, Equatable, Sendable {
    public let roomID: String
    public let personID: String?
    public let personEmail: String?
    public let isModerator: Bool?

    public init(roomID: String, personID: String, isModerator: Bool? = nil) {
        self.roomID = roomID
        self.personID = personID
        self.personEmail = nil
        self.isModerator = isModerator
    }

    public init(roomID: String, personEmail: String, isModerator: Bool? = nil) {
        self.roomID = roomID
        self.personID = nil
        self.personEmail = personEmail
        self.isModerator = isModerator
    }

    private enum CodingKeys: String, CodingKey {
        case roomID = "roomId"
        case personID = "personId"
        case personEmail
        case isModerator
    }
}

public struct UpdateMembershipRequest: Encodable, Equatable, Sendable {
    public let isModerator: Bool?
    public let isRoomHidden: Bool?

    public init(
        isModerator: Bool? = nil,
        isRoomHidden: Bool? = nil
    ) {
        self.isModerator = isModerator
        self.isRoomHidden = isRoomHidden
    }

    private enum CodingKeys: String, CodingKey {
        case isModerator
        case isRoomHidden
    }
}
```

Add these public methods inside `MembershipsAPI`, after `listAll(query:maxPages:)`:

```swift
public func create(_ request: CreateMembershipRequest) async throws -> WebexMembership {
    let body = try JSONEncoder().encode(request)
    let data = try await transport.send(WebexRequest(
        method: "POST",
        path: "/v1/memberships",
        body: body
    ))
    return try JSONDecoder().decode(WebexMembership.self, from: data)
}

public func get(membershipID: String) async throws -> WebexMembership {
    let data = try await transport.send(WebexRequest(
        path: try membershipPath(membershipID),
        isPathPercentEncoded: true
    ))
    return try JSONDecoder().decode(WebexMembership.self, from: data)
}

public func update(
    membershipID: String,
    _ request: UpdateMembershipRequest
) async throws -> WebexMembership {
    let body = try JSONEncoder().encode(request)
    let data = try await transport.send(WebexRequest(
        method: "PUT",
        path: try membershipPath(membershipID),
        isPathPercentEncoded: true,
        body: body
    ))
    return try JSONDecoder().decode(WebexMembership.self, from: data)
}

public func delete(membershipID: String) async throws {
    _ = try await transport.send(WebexRequest(
        method: "DELETE",
        path: try membershipPath(membershipID),
        isPathPercentEncoded: true
    ))
}
```

Add this helper inside `MembershipsAPI`:

```swift
private func membershipPath(_ membershipID: String) throws -> String {
    let trimmedID = membershipID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedID.isEmpty else {
        throw WebexSDKError.network("Invalid Webex membership ID")
    }

    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/?#%")

    guard let encodedID = trimmedID.addingPercentEncoding(withAllowedCharacters: allowed),
          !encodedID.isEmpty else {
        throw WebexSDKError.network("Invalid Webex membership ID")
    }

    return "/v1/memberships/\(encodedID)"
}
```

- [ ] **Step 4: Run CRUD tests to verify they pass**

Run:

```bash
swift test --filter MembershipsAPITests/testCreateMembershipWithPersonEmailPostsJSONAndDecodesMembership
swift test --filter MembershipsAPITests/testCreateMembershipWithPersonIDPostsExactlyOneIdentity
swift test --filter MembershipsAPITests/testGetMembershipPercentEncodesPathSegment
swift test --filter MembershipsAPITests/testUpdateMembershipPutsOnlyMutableFields
swift test --filter MembershipsAPITests/testDeleteMembershipSendsDeleteAndAcceptsNoContent
swift test --filter MembershipsAPITests/testMembershipIDValidationFailsBeforeHTTPWithoutLeakingID
```

Expected: all selected tests pass.

- [ ] **Step 5: Commit CRUD support**

```bash
git add Sources/WebexSwiftSDK/API/MembershipsAPI.swift Tests/WebexSwiftSDKTests/MembershipsAPITests.swift
git commit -m "feat: manage Webex memberships"
```

---

## Task 4: Expose Memberships On WebexClient

**Files:**
- Modify: `Sources/WebexSwiftSDK/WebexClient.swift`
- Modify: `Tests/WebexSwiftSDKTests/MembershipsAPITests.swift`

- [ ] **Step 1: Add failing client exposure test**

Append this test inside `MembershipsAPITests`, before `iso8601(_:)`:

```swift
func testWebexClientExposesMemberships() async throws {
    let accountID = WebexAccountID()
    let store = InMemoryWebexStore()
    let httpClient = MockMembershipsHTTPClient()
    await httpClient.enqueue(response: httpResponse(
        statusCode: 200,
        body: #"{"items":[{"id":"membership-from-client"}]}"#
    ))
    let client = WebexClient(
        accountID: accountID,
        configuration: WebexIntegrationConfiguration(
            clientID: "client",
            clientSecret: "secret",
            redirectURI: URL(string: "myapp://oauth/webex")!,
            scopes: ["spark:memberships_read"]
        ),
        tokenStore: store,
        httpClient: httpClient,
        initialAccessToken: AccessTokenState(
            value: "client-token",
            expiresAt: Date(timeIntervalSince1970: 1_000),
            tokenType: "Bearer"
        ),
        clock: { Date(timeIntervalSince1970: 0) }
    )

    let page = try await client.memberships.list()

    XCTAssertEqual(page.items.map(\\.id), ["membership-from-client"])
}
```

- [ ] **Step 2: Run client exposure test to verify it fails**

Run:

```bash
swift test --filter MembershipsAPITests/testWebexClientExposesMemberships
```

Expected: compile failure because `WebexClient` has no `memberships` property.

- [ ] **Step 3: Add `memberships` to `WebexClient`**

Modify `Sources/WebexSwiftSDK/WebexClient.swift`:

```swift
public struct WebexClient: Sendable {
    public let accountID: WebexAccountID
    public let people: PeopleAPI
    public let spaces: SpacesAPI
    public let memberships: MembershipsAPI

    public var rooms: RoomsAPI {
        spaces
    }

    private let tokenManager: TokenManager

    public init(
        accountID: WebexAccountID,
        configuration: WebexIntegrationConfiguration,
        tokenStore: WebexTokenStore,
        httpClient: HTTPClient = URLSessionHTTPClient(),
        initialAccessToken: AccessTokenState? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        let tokenManager = TokenManager(
            accountID: accountID,
            configuration: configuration,
            tokenStore: tokenStore,
            httpClient: httpClient,
            initialAccessToken: initialAccessToken,
            clock: clock
        )
        let transport = WebexTransport(
            httpClient: httpClient,
            accessTokenProvider: {
                try await tokenManager.validAccessToken()
            },
            tokenInvalidator: {
                await tokenManager.invalidateAccessToken()
            }
        )

        self.accountID = accountID
        self.people = PeopleAPI(transport: transport)
        self.spaces = SpacesAPI(transport: transport)
        self.memberships = MembershipsAPI(transport: transport)
        self.tokenManager = tokenManager
    }
}
```

- [ ] **Step 4: Run Memberships tests**

Run:

```bash
swift test --filter MembershipsAPITests
```

Expected: all `MembershipsAPITests` pass.

- [ ] **Step 5: Commit client exposure**

```bash
git add Sources/WebexSwiftSDK/WebexClient.swift Tests/WebexSwiftSDKTests/MembershipsAPITests.swift
git commit -m "feat: expose Webex memberships API"
```

---

## Task 5: Memberships Agent Notes, README, And Safe Smoke

**Files:**
- Create: `.agents/docs/webex-memberships-api.md`
- Modify: `README.md`
- Create: `Examples/WebexMembershipsListSmoke/Package.swift`
- Create: `Examples/WebexMembershipsListSmoke/README.md`
- Create: `Examples/WebexMembershipsListSmoke/Sources/WebexMembershipsListSmoke/main.swift`
- Create: `Examples/WebexMembershipsListSmoke/Tests/WebexMembershipsListSmokeTests/ListOptionsTests.swift`

- [ ] **Step 1: Add Memberships agent notes**

Create `.agents/docs/webex-memberships-api.md`:

```markdown
# Webex Memberships API Notes

Date captured: 2026-05-01

Primary source: https://developer.webex.com/messaging/docs/api/v1/memberships

Memberships represent a person's relationship to a Webex room/space.

## v1.2.0 Scope

- `GET /v1/memberships`
- `POST /v1/memberships`
- `GET /v1/memberships/{membershipId}`
- `PUT /v1/memberships/{membershipId}`
- `DELETE /v1/memberships/{membershipId}`

Compliance Officer convenience flows are out of scope for v1.2.0.

## Normal Scopes

- `spark:memberships_read`: list and get.
- `spark:memberships_write`: create, update, delete.

The SDK does not enforce scopes locally. Webex returns `401` or `403` when the
token lacks permission.

## Fields

Known response fields:

- `id`
- `roomId`
- `roomType`
- `personId`
- `personEmail`
- `personDisplayName`
- `personOrgId`
- `isModerator`
- `isMonitor`
- `isRoomHidden`
- `created`

`roomType` uses the same known values as Spaces: `direct` and `group`.

## Safety

- List smoke tests are safe when scoped by `WEBEX_ROOM_ID`.
- Create/update/delete smoke tests can alter real rooms and should require
  explicit environment variables in a separate example.
- Do not include person emails, membership IDs, tokens, or full pagination URLs
  in SDK-generated error messages.
```

- [ ] **Step 2: Add README Memberships example**

Add this section after the Spaces section in `README.md`:

```markdown
## Memberships

Memberships manage who belongs to a Webex space and whether a member is a
moderator.

```swift
let members = try await client.memberships.listAll(query: .init(roomID: spaceID))
let created = try await client.memberships.create(.init(
    roomID: spaceID,
    personEmail: "person@example.com"
))
let updated = try await client.memberships.update(
    membershipID: created.id,
    .init(isModerator: true)
)
try await client.memberships.delete(membershipID: updated.id)
```
```

- [ ] **Step 3: Add safe list smoke package**

Create `Examples/WebexMembershipsListSmoke/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "webex-memberships-list-smoke",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "WebexMembershipsListSmoke",
            dependencies: [
                .product(name: "WebexSwiftSDK", package: "webex-swift-sdk")
            ]
        ),
        .testTarget(
            name: "WebexMembershipsListSmokeTests",
            dependencies: ["WebexMembershipsListSmoke"]
        )
    ]
)
```

Create `Examples/WebexMembershipsListSmoke/Sources/WebexMembershipsListSmoke/main.swift` with a safe list-only flow:

```swift
import AppKit
import Foundation
import WebexSwiftSDK

@main
struct WebexMembershipsListSmoke {
    static func main() async {
        do {
            try await run()
        } catch is CancellationError {
            fputs("Cancelled.\n", stderr)
            Foundation.exit(130)
        } catch WebexSDKError.network(let message) where message == "Memberships pagination page cap exceeded" {
            fputs("Memberships list smoke failed: \(message).\n", stderr)
            fputs("Increase WEBEX_MEMBERSHIPS_MAX_PAGES or lower WEBEX_MEMBERSHIPS_PAGE_SIZE.\n", stderr)
            Foundation.exit(1)
        } catch {
            fputs("Memberships list smoke failed: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func run() async throws {
        let environment = ProcessInfo.processInfo.environment
        let configuration = try configurationFromEnvironment(environment)
        let listOptions = try MembershipListOptions(environment: environment)
        let keychainService = environment["WEBEX_KEYCHAIN_SERVICE"] ?? "com.webex.swift-sdk.memberships-list-smoke"
        let httpClient = URLSessionHTTPClient()
        let store = KeychainWebexStore(service: keychainService)
        let registry = WebexClientRegistry(store: store, httpClient: httpClient)

        print("Using Keychain service: \(keychainService)")
        print("Using redirect URI: \(configuration.redirectURI.absoluteString)")
        print("Opening Webex authorization for client id: \(configuration.clientID)")
        let authorized = try await registry.authorizeAndAddAccount(
            configuration: configuration,
            openAuthorizationURL: { authorizationURL in
                print("")
                print("Opening Webex authorization URL in your default browser.")
                print("If the browser does not open, paste this URL manually:")
                print(authorizationURL.absoluteString)
                print("")
                guard NSWorkspace.shared.open(authorizationURL) else {
                    throw SmokeError.failedToOpenAuthorizationURL
                }
            }
        )

        print("Created local account id: \(authorized.account.id.rawValue)")
        print("Saved refresh token record. Access token expires at: \(authorized.accessTokenExpiresAt)")
        print("")
        print("Listing Webex Memberships for room \(listOptions.roomID)")

        let memberships = try await authorized.client.memberships.listAll(
            query: listOptions.query,
            maxPages: listOptions.maxPages
        )

        print("memberships.count: \(memberships.count)")
        for (index, membership) in memberships.enumerated() {
            print("")
            print("membership[\(index)]")
            print("id: \(membership.id)")
            print("roomID: \(membership.roomID ?? "(nil)")")
            print("personID: \(membership.personID ?? "(nil)")")
            print("personEmail: \(membership.personEmail ?? "(nil)")")
            print("personDisplayName: \(membership.personDisplayName ?? "(nil)")")
            print("isModerator: \(optionalBool(membership.isModerator))")
            print("isMonitor: \(optionalBool(membership.isMonitor))")
            print("isRoomHidden: \(optionalBool(membership.isRoomHidden))")
            print("created: \(iso8601(membership.created))")
        }
    }

    private static func configurationFromEnvironment(
        _ environment: [String: String]
    ) throws -> WebexIntegrationConfiguration {
        let clientID = try requiredEnvironment("WEBEX_CLIENT_ID", environment: environment)
        let clientSecret = try requiredEnvironment("WEBEX_CLIENT_SECRET", environment: environment)
        let redirectURIString = environment["WEBEX_REDIRECT_URI"] ?? WebexOAuthLoopbackRedirectListener.defaultRedirectURI.absoluteString
        guard let redirectURI = URL(string: redirectURIString) else {
            throw SmokeError.invalidRedirectURI(redirectURIString)
        }

        let scopes = (environment["WEBEX_SCOPES"] ?? "spark:memberships_read")
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map(String.init)

        return WebexIntegrationConfiguration(
            clientID: clientID,
            clientSecret: clientSecret,
            redirectURI: redirectURI,
            scopes: scopes,
            prefersEphemeralWebBrowserSession: false
        )
    }

    private static func optionalBool(_ value: Bool?) -> String {
        guard let value else {
            return "(nil)"
        }

        return String(value)
    }

    private static func iso8601(_ date: Date?) -> String {
        guard let date else {
            return "(nil)"
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

private func requiredEnvironment(
    _ name: String,
    environment: [String: String]
) throws -> String {
    guard let value = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
          !value.isEmpty else {
        throw SmokeError.missingEnvironment(name)
    }

    return value
}

struct MembershipListOptions {
    let roomID: String
    let pageSize: Int
    let maxPages: Int
    let query: ListMembershipsQuery

    init(environment: [String: String]) throws {
        self.roomID = try requiredEnvironment("WEBEX_ROOM_ID", environment: environment)
        self.pageSize = try Self.integer(
            named: "WEBEX_MEMBERSHIPS_PAGE_SIZE",
            defaultValue: 100,
            minimum: 1,
            maximum: 1_000,
            environment: environment
        )
        self.maxPages = try Self.integer(
            named: "WEBEX_MEMBERSHIPS_MAX_PAGES",
            defaultValue: 1_000,
            minimum: 1,
            maximum: 10_000,
            environment: environment
        )
        self.query = ListMembershipsQuery(roomID: roomID, max: pageSize)
    }

    private static func integer(
        named name: String,
        defaultValue: Int,
        minimum: Int,
        maximum: Int,
        environment: [String: String]
    ) throws -> Int {
        guard let rawValue = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return defaultValue
        }
        guard let value = Int(rawValue),
              value >= minimum,
              value <= maximum else {
            throw SmokeError.invalidInteger(name: name, value: rawValue, minimum: minimum, maximum: maximum)
        }

        return value
    }
}

private enum SmokeError: Error, CustomStringConvertible {
    case missingEnvironment(String)
    case invalidRedirectURI(String)
    case failedToOpenAuthorizationURL
    case invalidInteger(name: String, value: String, minimum: Int, maximum: Int)

    var description: String {
        switch self {
        case .missingEnvironment(let name):
            return "Missing required environment variable \(name)"
        case .invalidRedirectURI(let value):
            return "Invalid WEBEX_REDIRECT_URI: \(value)"
        case .failedToOpenAuthorizationURL:
            return "Failed to open the Webex authorization URL"
        case .invalidInteger(let name, let value, let minimum, let maximum):
            return "\(name) must be an integer from \(minimum) through \(maximum); got \(value)"
        }
    }
}
```

Create `Examples/WebexMembershipsListSmoke/Tests/WebexMembershipsListSmokeTests/ListOptionsTests.swift`:

```swift
import XCTest
@testable import WebexMembershipsListSmoke

final class ListOptionsTests: XCTestCase {
    func testRequiresRoomIDAndDefaultsAvoidLowPageCaps() throws {
        XCTAssertThrowsError(try MembershipListOptions(environment: [:]))

        let options = try MembershipListOptions(environment: ["WEBEX_ROOM_ID": "room-id"])

        XCTAssertEqual(options.roomID, "room-id")
        XCTAssertEqual(options.pageSize, 100)
        XCTAssertEqual(options.maxPages, 1_000)
        XCTAssertEqual(options.query.roomID, "room-id")
        XCTAssertEqual(options.query.max, 100)
    }
}
```

Create `Examples/WebexMembershipsListSmoke/README.md`:

````markdown
# WebexMembershipsListSmoke

Interactive OAuth smoke test for listing Webex Memberships through
`WebexSwiftSDK`.

This example is list-only. It does not create, update, moderate, or delete room
members.

## Run

Create a Webex integration whose redirect URI is:

```text
http://127.0.0.1:8282/oauth/callback
```

Then run:

```bash
cd Examples/WebexMembershipsListSmoke

WEBEX_CLIENT_ID="your-client-id" \
WEBEX_CLIENT_SECRET="your-client-secret" \
WEBEX_ROOM_ID="room-id-to-list" \
WEBEX_SCOPES="spark:memberships_read" \
swift run WebexMembershipsListSmoke
```

The SDK opens a temporary listener on `127.0.0.1:8282`, waits for the browser
redirect, then closes the listener after the callback is received.
````

- [ ] **Step 4: Build and test docs/smoke changes**

Run:

```bash
swift test --package-path Examples/WebexMembershipsListSmoke
swift build --package-path Examples/WebexMembershipsListSmoke
swift test
swift build
git diff --check
```

Expected:

- Memberships smoke package test passes.
- Memberships smoke package builds.
- Root package tests pass.
- Root package builds.
- Whitespace check passes.

- [ ] **Step 5: Commit docs and smoke**

```bash
git add .agents/docs/webex-memberships-api.md README.md Examples/WebexMembershipsListSmoke
git commit -m "docs: add Memberships API usage"
```

---

## Task 6: Final Verification And Review

**Files:**
- No new files.
- Verify all files changed in Tasks 1-5.

- [ ] **Step 1: Run full verification**

Run:

```bash
swift test
swift test --package-path Examples/WebexMembershipsListSmoke
swift build
swift build --package-path Examples/WebexMembershipsListSmoke
git diff --check
git status --short
```

Expected:

- `swift test` passes with the current expected skipped keychain integration tests.
- `swift test --package-path Examples/WebexMembershipsListSmoke` passes.
- Both build commands pass.
- `git diff --check` exits 0.
- `git status --short` shows a clean worktree.

- [ ] **Step 2: Request final code review**

Use a fresh reviewer agent with this prompt:

```text
Review the current branch for the Webex Memberships API v1.2.0 implementation.

Spec:
- docs/superpowers/specs/2026-05-01-webex-memberships-api-design.md

Please check:
- compliance-officer helpers are not implemented
- Memberships models cover known fields safely
- list/listAll pagination follows the Spaces safety behavior
- create request cannot encode both personId and personEmail
- update encodes only mutable fields
- path encoding for membership IDs is safe
- SDK-generated errors do not leak tokens, person emails, IDs, or pagination URLs
- README and smoke example are safe and accurate

Run verification as needed. Return FINAL REVIEW: APPROVED or FINAL REVIEW: CHANGES_REQUESTED with concrete findings.
```

- [ ] **Step 3: Fix review findings one at a time**

For each review finding:

1. Reproduce or inspect the exact issue.
2. Add or adjust the smallest failing test that proves the issue.
3. Run that focused test and verify it fails for the expected reason.
4. Patch the code or docs.
5. Run the focused test and relevant package test.
6. Commit with a conventional message such as:

```bash
git add <changed-files>
git commit -m "fix: tighten Memberships <specific issue>"
```

- [ ] **Step 4: Finish branch**

After final review approval, use `superpowers:finishing-a-development-branch`.

Expected completion state:

- Branch `agent/webex-memberships-api-v1.2.0` contains focused commits.
- Worktree is clean.
- Tests/builds pass.
- The branch is ready for signed merge to `main` and eventual tag `v1.2.0`.
