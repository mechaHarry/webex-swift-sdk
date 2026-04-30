import XCTest
@testable import WebexSwiftSDK

final class AuthorizationRequestTests: XCTestCase {
    func testAuthorizationURLContainsRequiredWebexParameters() throws {
        let config = WebexIntegrationConfiguration(
            clientID: "client-123",
            clientSecret: "secret-123",
            redirectURI: URL(string: "myapp://oauth/webex")!,
            scopes: ["spark:people_read", "openid"]
        )

        let request = WebexAuthorizationRequest(
            configuration: config,
            state: "state-123",
            codeChallenge: "challenge-123",
            loginHint: "user@example.com",
            prompt: "select_account"
        )

        let url = try request.url()
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = Dictionary(uniqueKeysWithValues: components!.queryItems!.map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "webexapis.com")
        XCTAssertEqual(url.path, "/v1/authorize")
        XCTAssertEqual(query["response_type"], "code")
        XCTAssertEqual(query["client_id"], "client-123")
        XCTAssertEqual(query["redirect_uri"], "myapp://oauth/webex")
        XCTAssertEqual(query["scope"], "openid spark:people_read")
        XCTAssertEqual(query["state"], "state-123")
        XCTAssertEqual(query["code_challenge"], "challenge-123")
        XCTAssertEqual(query["code_challenge_method"], "S256")
        XCTAssertEqual(query["login_hint"], "user@example.com")
        XCTAssertEqual(query["prompt"], "select_account")
    }

    func testAuthorizationURLDoesNotIncludeClientSecret() throws {
        let config = WebexIntegrationConfiguration(
            clientID: "client-123",
            clientSecret: "secret-123",
            redirectURI: URL(string: "myapp://oauth/webex")!,
            scopes: ["openid"]
        )

        let request = WebexAuthorizationRequest(
            configuration: config,
            state: "state-123",
            codeChallenge: "challenge-123"
        )

        let url = try request.url()

        XCTAssertFalse(url.absoluteString.contains("client_secret"))
        XCTAssertFalse(url.absoluteString.contains("secret-123"))
    }

    func testAuthorizationURLEncodesReservedCharacters() throws {
        let config = WebexIntegrationConfiguration(
            clientID: "client-123",
            clientSecret: "secret-123",
            redirectURI: URL(string: "myapp://oauth/webex")!,
            scopes: ["openid"]
        )

        let request = WebexAuthorizationRequest(
            configuration: config,
            state: "state with spaces & symbols",
            codeChallenge: "challenge-123",
            loginHint: "user+webex@example.com",
            prompt: "consent select_account"
        )

        let url = try request.url()
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = Dictionary(uniqueKeysWithValues: components!.queryItems!.map { ($0.name, $0.value ?? "") })

        XCTAssertFalse(url.absoluteString.contains("state with spaces"))
        XCTAssertEqual(query["state"], "state with spaces & symbols")
        XCTAssertEqual(query["login_hint"], "user+webex@example.com")
        XCTAssertEqual(query["prompt"], "consent select_account")
    }

    func testAuthorizationURLPercentEncodesLiteralPlusSignsOnWire() throws {
        let config = WebexIntegrationConfiguration(
            clientID: "client-123",
            clientSecret: "secret-123",
            redirectURI: URL(string: "myapp://oauth/webex")!,
            scopes: ["openid"]
        )

        let request = WebexAuthorizationRequest(
            configuration: config,
            state: "state+one",
            codeChallenge: "challenge-123",
            loginHint: "user+webex@example.com",
            prompt: "select+account"
        )

        let url = try request.url()
        let percentEncodedQuery = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery

        XCTAssertTrue(percentEncodedQuery?.contains("state=state%2Bone") == true)
        XCTAssertTrue(percentEncodedQuery?.contains("login_hint=user%2Bwebex@example.com") == true)
        XCTAssertTrue(percentEncodedQuery?.contains("prompt=select%2Baccount") == true)
        XCTAssertFalse(percentEncodedQuery?.contains("state=state+one") == true)
        XCTAssertFalse(percentEncodedQuery?.contains("login_hint=user+webex@example.com") == true)
        XCTAssertFalse(percentEncodedQuery?.contains("prompt=select+account") == true)
        XCTAssertFalse(url.absoluteString.contains("secret-123"))
    }
}
