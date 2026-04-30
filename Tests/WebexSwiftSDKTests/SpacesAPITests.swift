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

    func testSpaceRejectsInvalidTimestamp() throws {
        let json = Data(#"{"id":"space-id","created":"not-a-date"}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(WebexSpace.self, from: json)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted error, got \(error)")
            }

            XCTAssertEqual(context.debugDescription, "Invalid Webex timestamp")
        }
    }

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

    private func iso8601(_ date: Date?) -> String? {
        guard let date else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

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
