import XCTest
@testable import WebexSwiftSDK

final class WebexTokenEndpointTests: XCTestCase {
    func testAuthorizationCodeRequestUsesFormBody() throws {
        let config = WebexIntegrationConfiguration(
            clientID: "client",
            clientSecret: "secret",
            redirectURI: URL(string: "myapp://oauth/webex")!,
            scopes: ["openid"]
        )

        let request = try WebexTokenEndpoint.authorizationCodeRequest(
            configuration: config,
            code: "code-1",
            codeVerifier: "verifier-1"
        )

        let body = String(data: request.httpBody!, encoding: .utf8)!
        XCTAssertEqual(request.url?.absoluteString, "https://webexapis.com/v1/access_token")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertFalse(request.url?.absoluteString.contains("secret") == true)
        XCTAssertTrue(body.contains("grant_type=authorization_code"))
        XCTAssertTrue(body.contains("client_id=client"))
        XCTAssertTrue(body.contains("client_secret=secret"))
        XCTAssertTrue(body.contains("code=code-1"))
        XCTAssertTrue(body.contains("code_verifier=verifier-1"))
    }

    func testRefreshTokenRequestUsesFormBody() throws {
        let config = WebexIntegrationConfiguration(
            clientID: "client",
            clientSecret: "secret",
            redirectURI: URL(string: "myapp://oauth/webex")!,
            scopes: ["openid"]
        )

        let request = try WebexTokenEndpoint.refreshTokenRequest(
            configuration: config,
            refreshToken: "refresh-1"
        )

        let body = String(data: request.httpBody!, encoding: .utf8)!
        XCTAssertEqual(request.url?.absoluteString, "https://webexapis.com/v1/access_token")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertTrue(body.contains("grant_type=refresh_token"))
        XCTAssertTrue(body.contains("client_id=client"))
        XCTAssertTrue(body.contains("client_secret=secret"))
        XCTAssertTrue(body.contains("refresh_token=refresh-1"))
        XCTAssertFalse(request.url?.absoluteString.contains("secret") == true)
    }

    func testFormBodyPercentEncodesReservedCharactersAndLiteralPlusSigns() throws {
        let config = WebexIntegrationConfiguration(
            clientID: "client+1",
            clientSecret: "secret+1",
            redirectURI: URL(string: "myapp://oauth/webex?tenant=one+two")!,
            scopes: ["openid"]
        )

        let request = try WebexTokenEndpoint.authorizationCodeRequest(
            configuration: config,
            code: "code+1 & symbols",
            codeVerifier: "verifier+1/2="
        )

        let body = String(data: request.httpBody!, encoding: .utf8)!
        XCTAssertTrue(body.contains("client_id=client%2B1"))
        XCTAssertTrue(body.contains("client_secret=secret%2B1"))
        XCTAssertTrue(body.contains("redirect_uri=myapp%3A%2F%2Foauth%2Fwebex%3Ftenant%3Done%2Btwo"))
        XCTAssertTrue(body.contains("code=code%2B1%20%26%20symbols"))
        XCTAssertTrue(body.contains("code_verifier=verifier%2B1%2F2%3D"))
        XCTAssertFalse(body.contains("client_id=client+1"))
        XCTAssertFalse(body.contains("client_secret=secret+1"))
        XCTAssertFalse(body.contains("code=code+1"))
        XCTAssertFalse(body.contains("code_verifier=verifier+1"))
    }

    func testURLSessionHTTPClientThrowsRedactedNetworkErrorForNonHTTPResponse() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NonHTTPURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
        }

        var request = URLRequest(
            url: URL(string: "https://example.com/token?client_secret=query-secret&access_token=query-access")!
        )
        request.setValue("Bearer header-secret", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("client_secret=body-secret&access_token=body-access&id_token=body-id".utf8)

        do {
            _ = try await URLSessionHTTPClient(session: session).send(request)
            XCTFail("Expected non-HTTP response to throw")
        } catch let error as WebexSDKError {
            XCTAssertEqual(error, .network("Received non-HTTP URL response"))

            let description = String(describing: error)
            XCTAssertFalse(description.contains("query-secret"))
            XCTAssertFalse(description.contains("query-access"))
            XCTAssertFalse(description.contains("header-secret"))
            XCTAssertFalse(description.contains("body-secret"))
            XCTAssertFalse(description.contains("body-access"))
            XCTAssertFalse(description.contains("body-id"))
        } catch {
            XCTFail("Expected WebexSDKError.network, got \(error)")
        }
    }

    func testTokenResponseDecodesWebexSnakeCasePayload() throws {
        let json = """
        {
          "access_token": "access",
          "expires_in": 10,
          "refresh_token": "refresh",
          "refresh_token_expires_in": 100,
          "token_type": "Bearer",
          "scope": "openid spark:people_read",
          "id_token": "id"
        }
        """

        let response = try JSONDecoder().decode(WebexTokenResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.accessToken, "access")
        XCTAssertEqual(response.expiresIn, 10)
        XCTAssertEqual(response.refreshToken, "refresh")
        XCTAssertEqual(response.refreshTokenExpiresIn, 100)
        XCTAssertEqual(response.tokenType, "Bearer")
        XCTAssertEqual(response.scope, "openid spark:people_read")
        XCTAssertEqual(response.idToken, "id")
    }

    func testTokenResponseDoesNotConformToEncodable() {
        let response = WebexTokenResponse(
            accessToken: "access-secret",
            expiresIn: 10,
            refreshToken: "refresh-secret",
            refreshTokenExpiresIn: 100,
            tokenType: "Bearer",
            scope: "openid",
            idToken: "id-secret"
        )

        XCTAssertFalse(response as Any is Encodable)
    }

    func testTokenResponseBuildsRecordAndMemoryToken() throws {
        let now = Date(timeIntervalSince1970: 100)
        let response = WebexTokenResponse(
            accessToken: "access",
            expiresIn: 10,
            refreshToken: "refresh",
            refreshTokenExpiresIn: 100,
            tokenType: "Bearer",
            scope: "openid spark:people_read",
            idToken: nil
        )

        let record = response.tokenRecord(receivedAt: now)
        let memoryToken = response.accessTokenState(receivedAt: now)

        XCTAssertEqual(record.refreshToken, "refresh")
        XCTAssertEqual(record.refreshTokenExpiresAt, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(record.lastAccessTokenExpiresAt, Date(timeIntervalSince1970: 110))
        XCTAssertEqual(record.grantedScopes, ["openid", "spark:people_read"])
        XCTAssertEqual(memoryToken.value, "access")
        XCTAssertEqual(memoryToken.expiresAt, Date(timeIntervalSince1970: 110))
    }

    func testTokenResponseRecordEncodingOmitsAccessAndIDTokens() throws {
        let response = WebexTokenResponse(
            accessToken: "access-secret",
            expiresIn: 10,
            refreshToken: "refresh-secret",
            refreshTokenExpiresIn: 100,
            tokenType: "Bearer",
            scope: "openid",
            idToken: "id-secret"
        )

        let record = response.tokenRecord(receivedAt: Date(timeIntervalSince1970: 100))
        let data = try JSONEncoder().encode(record)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertEqual(record.refreshToken, "refresh-secret")
        XCTAssertTrue(json.contains("refresh-secret"))
        XCTAssertFalse(json.contains("access-secret"))
        XCTAssertFalse(json.contains("id-secret"))
        XCTAssertFalse(json.contains("accessToken"))
        XCTAssertFalse(json.contains("access_token"))
        XCTAssertFalse(json.contains("idToken"))
        XCTAssertFalse(json.contains("id_token"))
    }

    func testTokenResponseDescriptionsRedactTokens() {
        let response = WebexTokenResponse(
            accessToken: "access-secret",
            expiresIn: 10,
            refreshToken: "refresh-secret",
            refreshTokenExpiresIn: 100,
            tokenType: "Bearer",
            scope: "openid",
            idToken: "id-secret"
        )

        let description = String(describing: response)
        let debugDescription = String(reflecting: response)

        for output in [description, debugDescription] {
            XCTAssertFalse(output.contains("access-secret"))
            XCTAssertFalse(output.contains("refresh-secret"))
            XCTAssertFalse(output.contains("id-secret"))
            XCTAssertTrue(output.contains("[redacted]"))
            XCTAssertTrue(output.contains("Bearer"))
            XCTAssertTrue(output.contains("openid"))
        }
    }

    func testAccessTokenStateDescriptionsRedactAccessToken() {
        let token = AccessTokenState(
            value: "access-secret",
            expiresAt: Date(timeIntervalSince1970: 110),
            tokenType: "Bearer"
        )

        let description = String(describing: token)
        let debugDescription = String(reflecting: token)

        for output in [description, debugDescription] {
            XCTAssertFalse(output.contains("access-secret"))
            XCTAssertTrue(output.contains("[redacted]"))
            XCTAssertTrue(output.contains("Bearer"))
        }
    }
}

private final class NonHTTPURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: WebexSDKError.network("Test request missing URL"))
            return
        }

        let response = URLResponse(
            url: url,
            mimeType: nil,
            expectedContentLength: 0,
            textEncodingName: nil
        )

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
