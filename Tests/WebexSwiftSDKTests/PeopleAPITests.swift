import XCTest
@testable import WebexSwiftSDK

final class PeopleAPITests: XCTestCase {
    func testMeSendsPeopleMeRequestWithBearerAuthAndDecodesPerson() async throws {
        let httpClient = MockPeopleHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://webexapis.com/v1/people/me")!,
            statusCode: 200,
            body: """
            {"id":"person-id","emails":["user@example.com"],"displayName":"Ada Lovelace","orgId":"org-id","created":"2026-04-29T10:11:12Z"}
            """
        ))
        let transport = WebexTransport(httpClient: httpClient) {
            AccessTokenState(
                value: "people-access-token",
                expiresAt: Date(timeIntervalSince1970: 1_000),
                tokenType: "Bearer"
            )
        }
        let api = PeopleAPI(transport: transport)

        let person = try await api.me()

        XCTAssertEqual(
            person,
            WebexPerson(
                id: "person-id",
                emails: ["user@example.com"],
                displayName: "Ada Lovelace",
                orgID: "org-id",
                created: "2026-04-29T10:11:12Z"
            )
        )
        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].url?.absoluteString, "https://webexapis.com/v1/people/me")
        XCTAssertEqual(requests[0].httpMethod, "GET")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer people-access-token")
    }

    func testMetadataDerivationUsesFirstEmailAndExplicitVerificationDate() {
        let verifiedAt = Date(timeIntervalSince1970: 1_777_777)
        let person = WebexPerson(
            id: "person-id",
            emails: ["primary@example.com", "secondary@example.com"],
            displayName: "Grace Hopper",
            orgID: "org-id",
            created: "2026-04-29T10:11:12Z"
        )

        let metadata = person.metadata(verifiedAt: verifiedAt)

        XCTAssertEqual(metadata.webexUserID, "person-id")
        XCTAssertEqual(metadata.email, "primary@example.com")
        XCTAssertEqual(metadata.displayName, "Grace Hopper")
        XCTAssertEqual(metadata.organizationID, "org-id")
        XCTAssertEqual(metadata.lastVerifiedAt, verifiedAt)
    }

    func testClientPeopleMeRefreshesStoredTokenAndFetchesPerson() async throws {
        let accountID = WebexAccountID()
        let store = InMemoryWebexStore()
        let httpClient = MockPeopleHTTPClient()
        let now = Date(timeIntervalSince1970: 100)
        try await store.saveTokenRecord(
            WebexTokenRecord(
                refreshToken: "stored-refresh",
                refreshTokenExpiresAt: .distantFuture,
                lastAccessTokenExpiresAt: now.addingTimeInterval(10),
                grantedScopes: ["openid", "spark:people_read"],
                tokenType: "Bearer",
                lastRefreshAt: now
            ),
            for: accountID
        )
        await httpClient.enqueue(response: tokenHTTPResponse(
            accessToken: "refreshed-access",
            refreshToken: "refreshed-refresh"
        ))
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://webexapis.com/v1/people/me")!,
            statusCode: 200,
            body: """
            {"id":"person-id","emails":["user@example.com"],"displayName":"Ada Lovelace","orgId":"org-id","created":"2026-04-29T10:11:12Z"}
            """
        ))
        let client = WebexClient(
            accountID: accountID,
            configuration: configuration,
            tokenStore: store,
            httpClient: httpClient
        )

        let person = try await client.people.me()

        XCTAssertEqual(person.id, "person-id")
        XCTAssertEqual(person.emails, ["user@example.com"])
        XCTAssertEqual(person.displayName, "Ada Lovelace")
        XCTAssertEqual(person.orgID, "org-id")
        XCTAssertEqual(person.created, "2026-04-29T10:11:12Z")
        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, [
            "https://webexapis.com/v1/access_token",
            "https://webexapis.com/v1/people/me"
        ])
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer refreshed-access")
    }

    func testMalformedPeopleJSONDoesNotLeakAccessToken() async throws {
        let httpClient = MockPeopleHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            url: URL(string: "https://webexapis.com/v1/people/me")!,
            statusCode: 200,
            body: #"{"id":"person-id","emails":"not-an-array","displayName":"secret-access-token"}"#
        ))
        let transport = WebexTransport(httpClient: httpClient) {
            AccessTokenState(
                value: "secret-access-token",
                expiresAt: Date(timeIntervalSince1970: 1_000),
                tokenType: "Bearer"
            )
        }
        let api = PeopleAPI(transport: transport)

        do {
            _ = try await api.me()
            XCTFail("Expected malformed people JSON to throw")
        } catch {
            XCTAssertFalse(String(describing: error).contains("secret-access-token"))
        }
    }

    private var configuration: WebexIntegrationConfiguration {
        WebexIntegrationConfiguration(
            clientID: "client",
            clientSecret: "client-secret",
            redirectURI: URL(string: "myapp://oauth/webex")!,
            scopes: ["openid", "spark:people_read"]
        )
    }

    private func tokenHTTPResponse(
        accessToken: String,
        refreshToken: String
    ) -> HTTPResponse {
        httpResponse(
            url: URL(string: "https://webexapis.com/v1/access_token")!,
            statusCode: 200,
            body: """
            {"access_token":"\(accessToken)","expires_in":600,"refresh_token":"\(refreshToken)","refresh_token_expires_in":3600,"token_type":"Bearer","scope":"openid spark:people_read"}
            """
        )
    }

    private func httpResponse(
        url: URL,
        statusCode: Int,
        headers: [String: String] = [:],
        body: String
    ) -> HTTPResponse {
        HTTPResponse(
            data: Data(body.utf8),
            response: HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
        )
    }
}

private actor MockPeopleHTTPClient: HTTPClient {
    private enum Result: Sendable {
        case response(HTTPResponse)
    }

    private var results: [Result] = []
    private var requests: [URLRequest] = []

    func enqueue(response: HTTPResponse) {
        results.append(.response(response))
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard !results.isEmpty else {
            throw WebexSDKError.network("Unexpected people request")
        }

        switch results.removeFirst() {
        case .response(let response):
            return response
        }
    }
}
