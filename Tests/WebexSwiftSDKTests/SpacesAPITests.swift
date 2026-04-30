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

    func testListAllRejectsRepeatedNextLinkWithoutLeakingURLOrToken() async throws {
        let httpClient = MockSpacesHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            headers: ["Link": #"<https://webexapis.com/v1/rooms?cursor=loop>; rel="next""#],
            body: #"{"items":[{"id":"space-1","title":"One"}]}"#
        ))
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            headers: ["Link": #"<https://webexapis.com/v1/rooms?cursor=loop>; rel="next""#],
            body: #"{"items":[{"id":"space-2","title":"Two"}]}"#
        ))
        let api = makeAPI(httpClient: httpClient)

        do {
            _ = try await api.listAll()
            XCTFail("Expected repeated next link to throw")
        } catch WebexSDKError.network(let message) {
            XCTAssertEqual(message, "Repeated Spaces pagination link")
            XCTAssertFalse(message.contains("cursor=loop"))
            XCTAssertFalse(message.contains("spaces-token"))
        } catch {
            XCTFail("Expected network error, got \(error)")
        }

        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, [
            "https://webexapis.com/v1/rooms",
            "https://webexapis.com/v1/rooms?cursor=loop"
        ])
    }

    func testListAllRejectsNextLinkBackToInitialRequestWithoutRefetching() async throws {
        let httpClient = MockSpacesHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            headers: ["Link": #"<https://webexapis.com/v1/rooms?max=2>; rel="next""#],
            body: #"{"items":[{"id":"space-1","title":"One"}]}"#
        ))
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            body: #"{"items":[{"id":"space-1-again","title":"One Again"}]}"#
        ))
        let api = makeAPI(httpClient: httpClient)

        do {
            _ = try await api.listAll(query: .init(max: 2))
            XCTFail("Expected initial pagination loop to throw")
        } catch WebexSDKError.network(let message) {
            XCTAssertEqual(message, "Repeated Spaces pagination link")
            XCTAssertFalse(message.contains("max=2"))
            XCTAssertFalse(message.contains("spaces-token"))
        } catch {
            XCTFail("Expected network error, got \(error)")
        }

        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, [
            "https://webexapis.com/v1/rooms?max=2"
        ])
    }

    func testListAllRejectsABAPaginationCycleBeforeRefetchingA() async throws {
        let httpClient = MockSpacesHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            headers: ["Link": #"<https://webexapis.com/v1/rooms?cursor=b>; rel="next""#],
            body: #"{"items":[{"id":"space-a","title":"A"}]}"#
        ))
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            headers: ["Link": #"<https://webexapis.com/v1/rooms?max=1>; rel="next""#],
            body: #"{"items":[{"id":"space-b","title":"B"}]}"#
        ))
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            body: #"{"items":[{"id":"space-a-again","title":"A Again"}]}"#
        ))
        let api = makeAPI(httpClient: httpClient)

        do {
            _ = try await api.listAll(query: .init(max: 1))
            XCTFail("Expected pagination cycle to throw")
        } catch WebexSDKError.network(let message) {
            XCTAssertEqual(message, "Repeated Spaces pagination link")
            XCTAssertFalse(message.contains("max=1"))
            XCTAssertFalse(message.contains("spaces-token"))
        } catch {
            XCTFail("Expected network error, got \(error)")
        }

        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, [
            "https://webexapis.com/v1/rooms?max=1",
            "https://webexapis.com/v1/rooms?cursor=b"
        ])
    }

    func testListAllEnforcesPageCapWithoutFollowingNextLink() async throws {
        let httpClient = MockSpacesHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            headers: ["Link": #"<https://webexapis.com/v1/rooms?cursor=second>; rel="next""#],
            body: #"{"items":[{"id":"space-1","title":"One"}]}"#
        ))
        let api = makeAPI(httpClient: httpClient)

        do {
            _ = try await api.listAll(maxPages: 1)
            XCTFail("Expected page cap to throw")
        } catch WebexSDKError.network(let message) {
            XCTAssertEqual(message, "Spaces pagination page cap exceeded")
            XCTAssertFalse(message.contains("cursor=second"))
            XCTAssertFalse(message.contains("spaces-token"))
        } catch {
            XCTFail("Expected network error, got \(error)")
        }

        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, [
            "https://webexapis.com/v1/rooms"
        ])
    }

    func testListAllRejectsInvalidPageCapWithoutRequest() async throws {
        let httpClient = MockSpacesHTTPClient()
        let api = makeAPI(httpClient: httpClient)

        do {
            _ = try await api.listAll(maxPages: 0)
            XCTFail("Expected invalid page cap to throw")
        } catch WebexSDKError.network(let message) {
            XCTAssertEqual(message, "Spaces pagination page cap must be greater than zero")
            XCTAssertFalse(message.contains("spaces-token"))
        } catch {
            XCTFail("Expected network error, got \(error)")
        }

        let requests = await httpClient.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

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
        let requests = await httpClient.recordedRequests()
        let request = try XCTUnwrap(requests.first)
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
        let requests = await httpClient.recordedRequests()
        let request = try XCTUnwrap(requests.first)
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
        let requests = await httpClient.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.absoluteString, "https://webexapis.com/v1/rooms/space-id")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["title", "description", "isLocked"])
        XCTAssertEqual(json["title"] as? String, "Updated")
        XCTAssertEqual(json["description"] as? String, "Updated description")
        XCTAssertEqual(json["isLocked"] as? Bool, false)
        XCTAssertNil(json["isReadOnly"])
        XCTAssertNil(json["teamId"])
        XCTAssertNil(json["creatorId"])
    }

    func testDeleteSpaceSendsDeleteAndAcceptsNoContent() async throws {
        let httpClient = MockSpacesHTTPClient()
        await httpClient.enqueue(response: httpResponse(statusCode: 204, body: ""))
        let api = makeAPI(httpClient: httpClient)

        try await api.delete(spaceID: "space-id")

        let requests = await httpClient.recordedRequests()
        let request = try XCTUnwrap(requests.first)
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
            ),
            clock: { Date(timeIntervalSince1970: 0) }
        )

        let spaces = try await client.spaces.list()
        let rooms = try await client.rooms.list()

        XCTAssertEqual(spaces.items.map(\.id), ["space-from-spaces"])
        XCTAssertEqual(rooms.items.map(\.id), ["space-from-rooms"])
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
