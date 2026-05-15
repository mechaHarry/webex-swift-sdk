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
          "source": "directory",
          "flags": {
            "hiddenReason": "user"
          },
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
        XCTAssertEqual(membership.additionalFields["source"], .string("directory"))
        XCTAssertEqual(membership.additionalFields["flags"], .object(["hiddenReason": .string("user")]))
        XCTAssertNil(membership.additionalFields["id"])
        XCTAssertNil(membership.additionalFields["roomId"])
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

    func testListMembershipsSendsParamsAndDecodesPage() async throws {
        let httpClient = MockMembershipsHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            headers: ["Link": #"<https://webexapis.com/v1/memberships?cursor=next>; rel="next""#],
            body: #"{"items":[{"id":"membership-1","roomId":"room-1","personEmail":"user@example.com"}]}"#
        ))
        let api = makeAPI(httpClient: httpClient)

        let page = try await api.list(params: ListMembershipsParams(
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

    func testListMembershipsNextPageUsesParsedWebexPageLink() async throws {
        let httpClient = MockMembershipsHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            headers: ["Link": #"<https://webexapis.com/v1/memberships?cursor=second>; rel="next""#],
            body: #"{"items":[{"id":"membership-1"}]}"#
        ))
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            body: #"{"items":[{"id":"membership-2"}]}"#
        ))
        let api = makeAPI(httpClient: httpClient)

        let firstPage = try await api.list(params: .init(roomID: "room-1", max: 10))
        let nextPage = try XCTUnwrap(firstPage.nextPage)
        let secondPage = try await api.list(nextPage: nextPage)

        XCTAssertEqual(firstPage.items.map(\.id), ["membership-1"])
        XCTAssertEqual(secondPage.items.map(\.id), ["membership-2"])
        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, [
            "https://webexapis.com/v1/memberships?roomId=room-1&max=10",
            "https://webexapis.com/v1/memberships?cursor=second"
        ])
    }

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
        let requests = await httpClient.recordedRequests()
        let request = try XCTUnwrap(requests.first)
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

        let requests = await httpClient.recordedRequests()
        let request = try XCTUnwrap(requests.first)
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
        let requests = await httpClient.recordedRequests()
        let request = try XCTUnwrap(requests.first)
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
        let requests = await httpClient.recordedRequests()
        let request = try XCTUnwrap(requests.first)
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

        let requests = await httpClient.recordedRequests()
        let request = try XCTUnwrap(requests.first)
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
            XCTFail("Expected network error, got \(error)")
        }

        let requests = await httpClient.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

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

        XCTAssertEqual(page.items.map(\.id), ["membership-from-client"])
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
