import XCTest
@testable import WebexSwiftSDK

final class WebexAPIStreamAdapterTests: XCTestCase {
    func testSpacesStreamUsesSpacesListAndNextPage() async throws {
        let httpClient = StreamAdapterHTTPClient()
        await httpClient.enqueue(
            json: #"{"items":[{"id":"space-1","title":"General"}]}"#,
            link: #"<https://webexapis.com/v1/rooms?cursor=next>; rel="next""#
        )
        await httpClient.enqueue(json: #"{"items":[{"id":"space-2","title":"Older"}]}"#)

        let stream = makeSpacesAPI(httpClient: httpClient)
            .stream(params: .init(sortBy: .lastActivity, max: 1), pageLimit: 2)

        await stream.refresh()
        await stream.loadNextPage()

        let snapshot = await stream.currentSnapshot()
        XCTAssertEqual(snapshot.items.map(\.id), ["space-1", "space-2"])
        XCTAssertEqual(snapshot.pagination.pagesLoaded, 2)
        XCTAssertFalse(snapshot.pagination.hasMore)

        let requestURLs = await httpClient.requestURLs
        XCTAssertEqual(requestURLs, [
            "https://webexapis.com/v1/rooms?sortBy=lastactivity&max=1",
            "https://webexapis.com/v1/rooms?cursor=next"
        ])
    }

    func testMessagesStreamUsesMessagesListAndNextPage() async throws {
        let httpClient = StreamAdapterHTTPClient()
        await httpClient.enqueue(
            json: #"{"items":[{"id":"message-1","roomId":"room-1","text":"Recent"}]}"#,
            link: #"<https://webexapis.com/v1/messages?cursor=next>; rel="next""#
        )
        await httpClient.enqueue(
            json: #"{"items":[{"id":"message-2","roomId":"room-1","text":"Older"}]}"#
        )

        let stream = makeMessagesAPI(httpClient: httpClient)
            .stream(params: .init(roomID: "room-1", max: 1), pageLimit: 2)

        await stream.refresh()
        await stream.loadNextPage()

        let snapshot = await stream.currentSnapshot()
        XCTAssertEqual(snapshot.items.map(\.id), ["message-1", "message-2"])
        XCTAssertEqual(snapshot.items.map(\.text), ["Recent", "Older"])

        let requestURLs = await httpClient.requestURLs
        XCTAssertEqual(requestURLs, [
            "https://webexapis.com/v1/messages?roomId=room-1&max=1",
            "https://webexapis.com/v1/messages?cursor=next"
        ])
    }

    func testMembershipsStreamUsesMembershipsListAndNextPage() async throws {
        let httpClient = StreamAdapterHTTPClient()
        await httpClient.enqueue(
            json: #"{"items":[{"id":"membership-1","roomId":"room-1","personEmail":"one@example.com"}]}"#,
            link: #"<https://webexapis.com/v1/memberships?cursor=next>; rel="next""#
        )
        await httpClient.enqueue(
            json: #"{"items":[{"id":"membership-2","roomId":"room-1","personEmail":"two@example.com"}]}"#
        )

        let stream = makeMembershipsAPI(httpClient: httpClient)
            .stream(params: .init(roomID: "room-1", max: 1), pageLimit: 2)

        await stream.refresh()
        await stream.loadNextPage()

        let snapshot = await stream.currentSnapshot()
        XCTAssertEqual(snapshot.items.map(\.id), ["membership-1", "membership-2"])
        XCTAssertEqual(snapshot.items.map(\.personEmail), ["one@example.com", "two@example.com"])

        let requestURLs = await httpClient.requestURLs
        XCTAssertEqual(requestURLs, [
            "https://webexapis.com/v1/memberships?roomId=room-1&max=1",
            "https://webexapis.com/v1/memberships?cursor=next"
        ])
    }
}

private func makeSpacesAPI(httpClient: HTTPClient) -> SpacesAPI {
    SpacesAPI(transport: makeStreamAdapterTransport(httpClient: httpClient))
}

private func makeMessagesAPI(httpClient: HTTPClient) -> MessagesAPI {
    MessagesAPI(transport: makeStreamAdapterTransport(httpClient: httpClient))
}

private func makeMembershipsAPI(httpClient: HTTPClient) -> MembershipsAPI {
    MembershipsAPI(transport: makeStreamAdapterTransport(httpClient: httpClient))
}

private func makeStreamAdapterTransport(httpClient: HTTPClient) -> WebexTransport {
    WebexTransport(httpClient: httpClient) {
        AccessTokenState(
            value: "access-token",
            expiresAt: Date(timeIntervalSince1970: 1_900_000_000),
            tokenType: "Bearer"
        )
    }
}

private actor StreamAdapterHTTPClient: HTTPClient {
    private(set) var requestURLs: [String] = []
    private var responses: [HTTPResponse] = []

    func enqueue(
        json: String,
        link: String? = nil,
        statusCode: Int = 200
    ) {
        let url = URL(string: "https://webexapis.com/v1/test")!
        var headers: [String: String] = [:]
        if let link {
            headers["Link"] = link
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )!
        responses.append(HTTPResponse(
            data: Data(json.utf8),
            response: response
        ))
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requestURLs.append(try XCTUnwrap(request.url?.absoluteString))
        return responses.removeFirst()
    }
}
