import XCTest
@testable import WebexSwiftSDK

final class TeamsAPITests: XCTestCase {
    func testTeamDecodesKnownFields() throws {
        let json = Data("""
        {
          "id": "team-id",
          "name": "Platform Team",
          "creatorId": "creator-id",
          "created": "2026-05-08T10:11:12.123Z"
        }
        """.utf8)

        let team = try JSONDecoder().decode(WebexTeam.self, from: json)

        XCTAssertEqual(team.id, "team-id")
        XCTAssertEqual(team.name, "Platform Team")
        XCTAssertEqual(team.creatorID, "creator-id")
        XCTAssertEqual(iso8601(team.created), "2026-05-08T10:11:12Z")
    }

    func testTeamPreservesUnknownWireFields() throws {
        let json = Data("""
        {
          "id": "team-id",
          "name": "Platform Team",
          "creatorId": "creator-id",
          "created": "2026-05-08T10:11:12.123Z",
          "color": "blue",
          "description": "Incident response",
          "archived": false,
          "nested": { "flag": true }
        }
        """.utf8)

        let team = try JSONDecoder().decode(WebexTeam.self, from: json)

        XCTAssertEqual(team.id, "team-id")
        XCTAssertEqual(team.additionalFields["color"], .string("blue"))
        XCTAssertEqual(team.additionalFields["description"], .string("Incident response"))
        XCTAssertEqual(team.additionalFields["archived"], .bool(false))
        XCTAssertEqual(team.additionalFields["nested"], .object(["flag": .bool(true)]))
        XCTAssertNil(team.additionalFields["id"])
        XCTAssertNil(team.additionalFields["name"])
        XCTAssertNil(team.additionalFields["creatorId"])
        XCTAssertNil(team.additionalFields["created"])
    }

    func testGetTeamPercentEncodesPathSegment() async throws {
        let httpClient = MockTeamsHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            body: #"{"id":"team/id with spaces","name":"Encoded Team"}"#
        ))
        let api = makeAPI(httpClient: httpClient)

        let team = try await api.get(teamID: "team/id with spaces")

        XCTAssertEqual(team.id, "team/id with spaces")
        XCTAssertEqual(team.name, "Encoded Team")
        let requests = await httpClient.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://webexapis.com/v1/teams/team%2Fid%20with%20spaces"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer teams-token")
    }

    func testInvalidTeamIDValidationFailsBeforeHTTPWithoutLeakingRawID() async throws {
        let httpClient = MockTeamsHTTPClient()
        let api = makeAPI(httpClient: httpClient)

        do {
            _ = try await api.get(teamID: "   ")
            XCTFail("Expected invalid team ID")
        } catch WebexSDKError.network(let message) {
            XCTAssertEqual(message, "Invalid Webex team ID")
            XCTAssertFalse(message.contains("   "))
        } catch {
            XCTFail("Expected network error, got \(error)")
        }

        let requests = await httpClient.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testWebexClientExposesTeamsAPI() async throws {
        let accountID = WebexAccountID()
        let store = InMemoryWebexStore()
        let httpClient = MockTeamsHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            body: #"{"id":"team-id","name":"Client Team"}"#
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
            ),
            clock: { Date(timeIntervalSince1970: 0) }
        )

        let team = try await client.teams.get(teamID: "team-id")

        XCTAssertEqual(team.name, "Client Team")
        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(requests.first?.url?.absoluteString, "https://webexapis.com/v1/teams/team-id")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer client-token")
    }

    func testListTeamsSendsParamsAndDecodesPage() async throws {
        let httpClient = MockTeamsHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            headers: [
                "Link": #"<https://webexapis.com/v1/teams?cursor=next>; rel="next""#
            ],
            body: #"{"items":[{"id":"team-1","name":"One"},{"id":"team-2","name":"Two"}]}"#
        ))
        let api = makeAPI(httpClient: httpClient)

        let page = try await api.list(params: ListTeamsParams(max: 2))

        XCTAssertEqual(page.items.map(\.id), ["team-1", "team-2"])
        XCTAssertNotNil(page.nextPage)
        let requests = await httpClient.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://webexapis.com/v1/teams?max=2")
    }

    func testListTeamsNextPageUsesParsedWebexPageLink() async throws {
        let httpClient = MockTeamsHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            body: #"{"items":[{"id":"team-2","name":"Two"}]}"#
        ))
        let api = makeAPI(httpClient: httpClient)
        let nextPage = WebexPageLink(url: URL(string: "https://webexapis.com/v1/teams?cursor=next")!)

        let page = try await api.list(nextPage: nextPage)

        XCTAssertEqual(page.items.map(\.id), ["team-2"])
        let requests = await httpClient.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://webexapis.com/v1/teams?cursor=next")
    }

    func testCreateTeamPostsDocumentedJSON() async throws {
        let httpClient = MockTeamsHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            body: #"{"id":"team-1","name":"Created"}"#
        ))
        let api = makeAPI(httpClient: httpClient)

        let team = try await api.create(CreateTeamRequest(name: "Created"))

        XCTAssertEqual(team.name, "Created")
        let requests = await httpClient.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://webexapis.com/v1/teams")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        XCTAssertEqual(json["name"] as? String, "Created")
        XCTAssertNil(json["color"])
        XCTAssertNil(json["description"])
    }

    func testUpdateTeamPutsDocumentedJSON() async throws {
        let httpClient = MockTeamsHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            body: #"{"id":"team/id with spaces","name":"Renamed"}"#
        ))
        let api = makeAPI(httpClient: httpClient)

        let team = try await api.update(
            teamID: "team/id with spaces",
            UpdateTeamRequest(name: "Renamed")
        )

        XCTAssertEqual(team.name, "Renamed")
        let requests = await httpClient.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://webexapis.com/v1/teams/team%2Fid%20with%20spaces"
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        XCTAssertEqual(json["name"] as? String, "Renamed")
    }

    func testDeleteTeamSendsDelete() async throws {
        let httpClient = MockTeamsHTTPClient()
        await httpClient.enqueue(response: httpResponse(statusCode: 204, body: ""))
        let api = makeAPI(httpClient: httpClient)

        try await api.delete(teamID: "team/id with spaces")

        let requests = await httpClient.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://webexapis.com/v1/teams/team%2Fid%20with%20spaces"
        )
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

private func makeAPI(httpClient: HTTPClient) -> TeamsAPI {
    TeamsAPI(transport: WebexTransport(httpClient: httpClient) {
        AccessTokenState(
            value: "teams-token",
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
            url: URL(string: "https://webexapis.com/v1/teams")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    )
}

private actor MockTeamsHTTPClient: HTTPClient {
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
            throw WebexSDKError.network("Unexpected teams request")
        }

        return responses.removeFirst()
    }
}
