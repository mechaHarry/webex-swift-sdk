import XCTest
@testable import WebexSwiftSDK

final class CoreModelTests: XCTestCase {
    func testAccountIDRoundTripsStableUUIDString() throws {
        let raw = "A4B0F5D9-6F9B-4B98-92A3-85B32B722001"
        let accountID = try WebexAccountID(rawValue: raw)

        XCTAssertEqual(accountID.rawValue, raw.lowercased())
        XCTAssertEqual(try WebexAccountID(rawValue: accountID.rawValue), accountID)
    }

    func testAccountIDCodableRoundTripsAsStableString() throws {
        let accountID = try WebexAccountID(rawValue: "A4B0F5D9-6F9B-4B98-92A3-85B32B722001")

        let data = try JSONEncoder().encode(accountID)
        let encoded = String(data: data, encoding: .utf8)
        let decoded = try JSONDecoder().decode(WebexAccountID.self, from: data)

        XCTAssertEqual(encoded, #""a4b0f5d9-6f9b-4b98-92a3-85b32b722001""#)
        XCTAssertEqual(decoded, accountID)
    }

    func testAccountIDGeneratesUniqueValues() {
        let first = WebexAccountID()
        let second = WebexAccountID()

        XCTAssertNotEqual(first, second)
        XCTAssertFalse(first.rawValue.isEmpty)
    }

    func testIntegrationConfigurationNormalizesScopes() {
        let config = WebexIntegrationConfiguration(
            clientID: "client-1",
            clientSecret: "secret-1",
            redirectURI: URL(string: "myapp://oauth/webex")!,
            scopes: ["spark:people_read", "openid", "spark:people_read"]
        )

        XCTAssertEqual(config.scopeString, "openid spark:people_read")
    }

    func testIntegrationConfigurationTrimsAndDropsEmptyScopes() {
        let config = WebexIntegrationConfiguration(
            clientID: "client-1",
            clientSecret: "secret-1",
            redirectURI: URL(string: "myapp://oauth/webex")!,
            scopes: [" spark:people_read ", "", "openid", "  ", "openid"]
        )

        XCTAssertEqual(config.scopes, ["openid", "spark:people_read"])
        XCTAssertEqual(config.scopeString, "openid spark:people_read")
    }

    func testIntegrationConfigurationDescriptionsRedactClientSecret() {
        let config = WebexIntegrationConfiguration(
            clientID: "client-1",
            clientSecret: "secret-1",
            redirectURI: URL(string: "myapp://oauth/webex")!,
            scopes: ["openid"]
        )

        let description = String(describing: config)
        let debugDescription = String(reflecting: config)

        for output in [description, debugDescription] {
            XCTAssertFalse(output.contains("secret-1"))
            XCTAssertTrue(output.contains("client-1"))
            XCTAssertTrue(output.contains("myapp://oauth/webex"))
            XCTAssertTrue(output.contains("[redacted]"))
        }
    }

    func testAccountMetadataAllowsMutation() {
        var metadata = WebexAccountMetadata(displayName: "Old Name")

        metadata.displayName = "New Name"

        XCTAssertEqual(metadata.displayName, "New Name")
    }

    func testAccountMetadataCodableRoundTrips() throws {
        let metadata = WebexAccountMetadata(
            webexUserID: "webex-user-1",
            oidcSubject: "subject-1",
            email: "person@example.com",
            displayName: "Person One",
            organizationID: "org-1",
            lastVerifiedAt: Date(timeIntervalSince1970: 1_776_000_000)
        )

        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(WebexAccountMetadata.self, from: data)

        XCTAssertEqual(decoded, metadata)
    }

    func testErrorDescriptionRedactsSensitiveValues() {
        let error = WebexSDKError.tokenExchangeFailed(
            statusCode: 400,
            message: "client_secret=secret-1 access_token=token-1 refresh_token=refresh-1 id_token=id-1",
            trackingID: "API_123"
        )

        let description = String(describing: error)
        XCTAssertFalse(description.contains("secret-1"))
        XCTAssertFalse(description.contains("token-1"))
        XCTAssertFalse(description.contains("refresh-1"))
        XCTAssertFalse(description.contains("id-1"))
        XCTAssertTrue(description.contains("[redacted]"))
        XCTAssertTrue(description.contains("API_123"))
    }

    func testWebexAPIErrorDescriptionPreservesGenericJSONCode() {
        let error = WebexSDKError.webexAPI(
            statusCode: 500,
            trackingID: "API_456",
            message: #"{"code":"SERVICE_ERROR","message":"failed"}"#
        )

        let description = String(describing: error)
        XCTAssertTrue(description.contains("SERVICE_ERROR"))
        XCTAssertTrue(description.contains("failed"))
        XCTAssertTrue(description.contains("API_456"))
    }

    func testWebexAPIErrorDescriptionPreservesGenericKeyValueCode() {
        let equalsError = WebexSDKError.webexAPI(
            statusCode: 500,
            trackingID: nil,
            message: "code=SERVICE_ERROR message=failed"
        )
        let colonError = WebexSDKError.webexAPI(
            statusCode: 500,
            trackingID: nil,
            message: "code: SERVICE_ERROR message: failed"
        )

        XCTAssertTrue(String(describing: equalsError).contains("SERVICE_ERROR"))
        XCTAssertTrue(String(describing: colonError).contains("SERVICE_ERROR"))
    }

    func testAuthorizationCallbackDescriptionRedactsOAuthCode() {
        let error = WebexSDKError.invalidAuthorizationCallback(
            "myapp://oauth/webex?code=auth-code&state=state-1"
        )

        let description = String(describing: error)
        XCTAssertFalse(description.contains("auth-code"))
        XCTAssertTrue(description.contains("[redacted]"))
        XCTAssertTrue(description.contains("state-1"))
    }

    func testRedactorHandlesSensitiveKeyValueStylesPromptly() {
        let value = """
        client_secret=secret-1
        Authorization: Bearer token-1
        "refresh_token": "refresh-1"
        code_verifier: verifier-1
        """

        let redacted = Redactor.redactSecrets(value)

        XCTAssertFalse(redacted.contains("secret-1"))
        XCTAssertFalse(redacted.contains("token-1"))
        XCTAssertFalse(redacted.contains("refresh-1"))
        XCTAssertFalse(redacted.contains("verifier-1"))
        XCTAssertEqual(redacted.components(separatedBy: "[redacted]").count - 1, 4)
    }

    func testOAuthCallbackRedactionRedactsAuthorizationCode() {
        let redacted = Redactor.redactOAuthCallback("myapp://oauth/webex?code=auth-code&state=s")

        XCTAssertFalse(redacted.contains("auth-code"))
        XCTAssertTrue(redacted.contains("state=s"))
    }

    func testRedactorRedactsIDTokenKeyValueAndJSONValues() {
        let value = #"id_token=id-1 "id_token":"id-2" "id_token": "id-3""#

        let redacted = Redactor.redactSecrets(value)

        XCTAssertFalse(redacted.contains("id-1"))
        XCTAssertFalse(redacted.contains("id-2"))
        XCTAssertFalse(redacted.contains("id-3"))
        XCTAssertEqual(redacted.components(separatedBy: "[redacted]").count - 1, 3)
    }

    func testRedactorHandlesLargeRepeatedSensitiveInput() {
        let value = (0..<1_000)
            .map { index in
                """
                client_secret=secret-\(index)&id_token=id-\(index)
                "refresh_token": "refresh-\(index)"
                Authorization: Bearer auth-\(index)
                """
            }
            .joined(separator: "\n")

        let redacted = Redactor.redactSecrets(value)

        XCTAssertFalse(redacted.contains("secret-999"))
        XCTAssertFalse(redacted.contains("id-999"))
        XCTAssertFalse(redacted.contains("refresh-999"))
        XCTAssertFalse(redacted.contains("auth-999"))
        XCTAssertEqual(redacted.components(separatedBy: "[redacted]").count - 1, 4_000)
    }
}
