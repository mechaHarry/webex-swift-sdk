import XCTest
import WebexSwiftSDK
@testable import WebexMessagesListSmoke

final class ListOptionsTests: XCTestCase {
    func testRequiresRoomIDAndDefaultsToSmallFirstPage() throws {
        XCTAssertThrowsError(try MessageListOptions(environment: [:]))

        let options = try MessageListOptions(environment: ["WEBEX_ROOM_ID": "room-id"])

        XCTAssertEqual(options.roomID, "room-id")
        XCTAssertEqual(options.pageSize, 25)
        XCTAssertEqual(options.maxPages, 1)
        XCTAssertEqual(options.params.roomID, "room-id")
        XCTAssertEqual(options.params.max, 25)
    }

    func testPageAndFilterOverridesAreApplied() throws {
        let options = try MessageListOptions(environment: [
            "WEBEX_ROOM_ID": "room-id",
            "WEBEX_MESSAGES_PAGE_SIZE": "50",
            "WEBEX_MESSAGES_MAX_PAGES": "3",
            "WEBEX_MESSAGES_PARENT_ID": "parent-id",
            "WEBEX_MESSAGES_MENTIONED_PEOPLE": "me",
            "WEBEX_MESSAGES_BEFORE": "2026-05-01T00:00:00Z",
            "WEBEX_MESSAGES_BEFORE_MESSAGE": "message-id"
        ])

        XCTAssertEqual(options.pageSize, 50)
        XCTAssertEqual(options.maxPages, 3)
        XCTAssertEqual(options.params.parentID, "parent-id")
        XCTAssertEqual(options.params.mentionedPeople, "me")
        XCTAssertEqual(options.params.before, "2026-05-01T00:00:00Z")
        XCTAssertEqual(options.params.beforeMessage, "message-id")
        XCTAssertEqual(options.params.max, 50)
    }

    func testInvalidPageSizeAndMaxPagesThrow() {
        XCTAssertThrowsError(try MessageListOptions(environment: [
            "WEBEX_ROOM_ID": "room-id",
            "WEBEX_MESSAGES_PAGE_SIZE": "0"
        ]))

        XCTAssertThrowsError(try MessageListOptions(environment: [
            "WEBEX_ROOM_ID": "room-id",
            "WEBEX_MESSAGES_MAX_PAGES": "not-a-number"
        ]))
    }

    func testInvalidRedirectURIErrorDescriptionDoesNotExposeURL() throws {
        let redirectURI = "http://[::1/oauth/callback"

        XCTAssertThrowsError(try WebexMessagesListSmoke.configurationFromEnvironment([
            "WEBEX_CLIENT_ID": "client-id",
            "WEBEX_CLIENT_SECRET": "client-secret",
            "WEBEX_REDIRECT_URI": redirectURI
        ])) { error in
            let description = String(describing: error)

            XCTAssertEqual(description, "Invalid WEBEX_REDIRECT_URI")
            XCTAssertFalse(description.contains(redirectURI))
            XCTAssertFalse(description.contains("/oauth/callback"))
        }
    }

    func testFailureDescriptionDoesNotExposeInvalidAuthorizationCallbackURL() {
        let callbackURL = "http://127.0.0.1:8282/oauth/callback?code=secret-code&state=secret-state"
        let description = WebexMessagesListSmoke.failureDescription(
            for: WebexSDKError.invalidAuthorizationCallback(callbackURL)
        )

        XCTAssertEqual(description, "Invalid authorization callback")
        XCTAssertFalse(description.contains("http://"))
        XCTAssertFalse(description.contains("127.0.0.1"))
        XCTAssertFalse(description.contains("/oauth/callback"))
        XCTAssertFalse(description.contains("code="))
        XCTAssertFalse(description.contains("state="))
    }

    func testCollectMessagesStopsAtPageCapWithoutFailingWhenMorePagesExist() async throws {
        let httpClient = MockMessagesSmokeHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            headers: ["Link": #"<https://webexapis.com/v1/messages?cursor=next>; rel="next""#],
            body: #"{"items":[{"id":"message-1","roomId":"room-id"}]}"#
        ))
        let client = makeClient(httpClient: httpClient)

        let result = try await WebexMessagesListSmoke.collectMessages(
            client: client,
            params: .init(roomID: "room-id", max: 25),
            maxPages: 1
        )

        XCTAssertEqual(result.messages.map(\.id), ["message-1"])
        XCTAssertEqual(result.pagesFetched, 1)
        XCTAssertTrue(result.hasMore)
        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, [
            "https://webexapis.com/v1/messages?roomId=room-id&max=25"
        ])
    }

    func testCollectMessagesFollowsNextPageUntilCap() async throws {
        let httpClient = MockMessagesSmokeHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            headers: ["Link": #"<https://webexapis.com/v1/messages?cursor=next>; rel="next""#],
            body: #"{"items":[{"id":"message-1","roomId":"room-id"}]}"#
        ))
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            body: #"{"items":[{"id":"message-2","roomId":"room-id"}]}"#
        ))
        let client = makeClient(httpClient: httpClient)

        let result = try await WebexMessagesListSmoke.collectMessages(
            client: client,
            params: .init(roomID: "room-id", max: 25),
            maxPages: 2
        )

        XCTAssertEqual(result.messages.map(\.id), ["message-1", "message-2"])
        XCTAssertEqual(result.pagesFetched, 2)
        XCTAssertFalse(result.hasMore)
        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, [
            "https://webexapis.com/v1/messages?roomId=room-id&max=25",
            "https://webexapis.com/v1/messages?cursor=next"
        ])
    }
}

private func makeClient(httpClient: HTTPClient) -> WebexClient {
    WebexClient(
        accountID: WebexAccountID(),
        configuration: WebexIntegrationConfiguration(
            clientID: "client",
            clientSecret: "secret",
            redirectURI: URL(string: "myapp://oauth/webex")!,
            scopes: ["spark:messages_read"]
        ),
        tokenStore: InMemoryWebexStore(),
        httpClient: httpClient,
        initialAccessToken: AccessTokenState(
            value: "messages-smoke-token",
            expiresAt: Date(timeIntervalSince1970: 1_000),
            tokenType: "Bearer"
        ),
        clock: { Date(timeIntervalSince1970: 0) }
    )
}

private func httpResponse(
    statusCode: Int,
    headers: [String: String] = [:],
    body: String
) -> HTTPResponse {
    HTTPResponse(
        data: Data(body.utf8),
        response: HTTPURLResponse(
            url: URL(string: "https://webexapis.com/v1/messages")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    )
}

private actor MockMessagesSmokeHTTPClient: HTTPClient {
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
            throw WebexSDKError.network("Unexpected messages smoke request")
        }

        return responses.removeFirst()
    }
}
