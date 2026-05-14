import XCTest
@testable import WebexSwiftSDK

final class TeamMembershipsAPITests: XCTestCase {
    func testTeamMembershipDecodesKnownAndUnknownFields() throws {
        let json = Data("""
        {
          "id": "team-membership-id",
          "teamId": "team-1",
          "personId": "person-1",
          "personEmail": "person@example.com",
          "personDisplayName": "Ada Lovelace",
          "personOrgId": "org-1",
          "isModerator": true,
          "created": "2026-05-14T10:11:12Z",
          "source": "directory",
          "archived": false
        }
        """.utf8)

        let membership = try JSONDecoder().decode(WebexTeamMembership.self, from: json)

        XCTAssertEqual(membership.id, "team-membership-id")
        XCTAssertEqual(membership.teamID, "team-1")
        XCTAssertEqual(membership.personID, "person-1")
        XCTAssertEqual(membership.personEmail, "person@example.com")
        XCTAssertEqual(membership.personDisplayName, "Ada Lovelace")
        XCTAssertEqual(membership.personOrgID, "org-1")
        XCTAssertEqual(membership.isModerator, true)
        XCTAssertEqual(iso8601(membership.created), "2026-05-14T10:11:12Z")
        XCTAssertEqual(membership.additionalFields["source"], .string("directory"))
        XCTAssertEqual(membership.additionalFields["archived"], .bool(false))
        XCTAssertNil(membership.additionalFields["teamId"])
    }

    func testListTeamMembershipsSendsParamsAndDecodesPage() async throws {
        let httpClient = MockTeamMembershipsHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            headers: [
                "Link": #"<https://webexapis.com/v1/team/memberships?cursor=next>; rel="next""#
            ],
            body: #"{"items":[{"id":"membership-1","teamId":"team-1"}]}"#
        ))
        let api = makeAPI(httpClient: httpClient)

        let page = try await api.list(params: ListTeamMembershipsParams(
            teamID: "team-1",
            personID: "person-1",
            personEmail: "person@example.com",
            max: 10
        ))

        XCTAssertEqual(page.items.map(\.id), ["membership-1"])
        XCTAssertEqual(page.nextPage?.url.absoluteString, "https://webexapis.com/v1/team/memberships?cursor=next")
        let requests = await httpClient.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://webexapis.com/v1/team/memberships?teamId=team-1&personId=person-1&personEmail=person@example.com&max=10"
        )
    }

    func testListTeamMembershipsNextPageUsesParsedWebexPageLink() async throws {
        let httpClient = MockTeamMembershipsHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            body: #"{"items":[{"id":"membership-2"}]}"#
        ))
        let api = makeAPI(httpClient: httpClient)
        let nextPage = WebexPageLink(url: URL(string: "https://webexapis.com/v1/team/memberships?cursor=next")!)

        let page = try await api.list(nextPage: nextPage)

        XCTAssertEqual(page.items.map(\.id), ["membership-2"])
        let requests = await httpClient.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://webexapis.com/v1/team/memberships?cursor=next")
    }

    func testCreateTeamMembershipWithPersonIDPostsExactlyOneIdentity() async throws {
        let httpClient = MockTeamMembershipsHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            body: #"{"id":"membership-1","teamId":"team-1","personId":"person-1","isModerator":true}"#
        ))
        let api = makeAPI(httpClient: httpClient)

        _ = try await api.create(CreateTeamMembershipRequest(
            teamID: "team-1",
            personID: "person-1",
            isModerator: true
        ))

        let requests = await httpClient.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://webexapis.com/v1/team/memberships")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["teamId", "personId", "isModerator"])
        XCTAssertEqual(json["teamId"] as? String, "team-1")
        XCTAssertEqual(json["personId"] as? String, "person-1")
        XCTAssertEqual(json["isModerator"] as? Bool, true)
        XCTAssertNil(json["personEmail"])
    }

    func testCreateTeamMembershipWithPersonEmailPostsExactlyOneIdentity() async throws {
        let httpClient = MockTeamMembershipsHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            body: #"{"id":"membership-1","teamId":"team-1","personEmail":"person@example.com"}"#
        ))
        let api = makeAPI(httpClient: httpClient)

        _ = try await api.create(CreateTeamMembershipRequest(
            teamID: "team-1",
            personEmail: "person@example.com"
        ))

        let requests = await httpClient.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["teamId", "personEmail"])
        XCTAssertEqual(json["personEmail"] as? String, "person@example.com")
        XCTAssertNil(json["personId"])
    }

    func testGetUpdateAndDeleteTeamMembershipPercentEncodePathSegment() async throws {
        let httpClient = MockTeamMembershipsHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            body: #"{"id":"membership/id with spaces"}"#
        ))
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            body: #"{"id":"membership/id with spaces","isModerator":false}"#
        ))
        await httpClient.enqueue(response: httpResponse(statusCode: 204, body: ""))
        let api = makeAPI(httpClient: httpClient)

        _ = try await api.get(teamMembershipID: "membership/id with spaces")
        _ = try await api.update(
            teamMembershipID: "membership/id with spaces",
            UpdateTeamMembershipRequest(isModerator: false)
        )
        try await api.delete(teamMembershipID: "membership/id with spaces")

        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(requests.map(\.httpMethod), ["GET", "PUT", "DELETE"])
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, [
            "https://webexapis.com/v1/team/memberships/membership%2Fid%20with%20spaces",
            "https://webexapis.com/v1/team/memberships/membership%2Fid%20with%20spaces",
            "https://webexapis.com/v1/team/memberships/membership%2Fid%20with%20spaces"
        ])
        let updateBody = try XCTUnwrap(requests[1].httpBody)
        let updateJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: updateBody) as? [String: Any])
        XCTAssertEqual(Set(updateJSON.keys), ["isModerator"])
        XCTAssertEqual(updateJSON["isModerator"] as? Bool, false)
    }

    func testInvalidTeamMembershipIDValidationFailsBeforeHTTPWithoutLeakingRawID() async throws {
        let httpClient = MockTeamMembershipsHTTPClient()
        let api = makeAPI(httpClient: httpClient)

        do {
            _ = try await api.get(teamMembershipID: "   ")
            XCTFail("Expected invalid team membership ID")
        } catch WebexSDKError.network(let message) {
            XCTAssertEqual(message, "Invalid Webex team membership ID")
            XCTAssertFalse(message.contains("   "))
        } catch {
            XCTFail("Expected network error, got \(error)")
        }

        let requests = await httpClient.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testWebexClientExposesTeamMembershipsAPI() async throws {
        let accountID = WebexAccountID()
        let store = InMemoryWebexStore()
        let httpClient = MockTeamMembershipsHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            body: #"{"id":"membership-1","teamId":"team-1","personId":"person-1"}"#
        ))
        let client = WebexClient(
            accountID: accountID,
            configuration: WebexIntegrationConfiguration(
                clientID: "client",
                clientSecret: "secret",
                redirectURI: URL(string: "myapp://oauth/webex")!,
                scopes: ["spark:teams_read"]
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

        let membership = try await client.teamMemberships.get(teamMembershipID: "membership-1")

        XCTAssertEqual(membership.teamID, "team-1")
        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(
            requests.first?.url?.absoluteString,
            "https://webexapis.com/v1/team/memberships/membership-1"
        )
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer client-token")
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

private func makeAPI(httpClient: HTTPClient) -> TeamMembershipsAPI {
    TeamMembershipsAPI(transport: WebexTransport(httpClient: httpClient) {
        AccessTokenState(
            value: "team-memberships-token",
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
            url: URL(string: "https://webexapis.com/v1/team/memberships")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    )
}

private actor MockTeamMembershipsHTTPClient: HTTPClient {
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
            throw WebexSDKError.network("Unexpected team memberships request")
        }

        return responses.removeFirst()
    }
}
