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
                return XCTFail("Expected dataCorrupted error, got \(error)")
            }

            XCTAssertEqual(context.debugDescription, "Invalid Webex timestamp")
        }
    }

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

        XCTAssertEqual(page.items.map(\.id), ["membership-1"])
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

        XCTAssertEqual(memberships.map(\.id), ["membership-1", "membership-3"])
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
            XCTFail("Expected network error, got \(error)")
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
            XCTFail("Expected network error, got \(error)")
        }

        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, [
            "https://webexapis.com/v1/memberships?max=2"
        ])
    }

    func testListAllMembershipsRejectsInvalidPageCapWithoutRequest() async throws {
        let httpClient = MockMembershipsHTTPClient()
        let api = makeAPI(httpClient: httpClient)

        do {
            _ = try await api.listAll(maxPages: 0)
            XCTFail("Expected invalid page cap to throw")
        } catch WebexSDKError.network(let message) {
            XCTAssertEqual(message, "Memberships pagination page cap must be greater than zero")
            XCTAssertFalse(message.contains("memberships-token"))
        } catch {
            XCTFail("Expected network error, got \(error)")
        }

        let requests = await httpClient.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
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
