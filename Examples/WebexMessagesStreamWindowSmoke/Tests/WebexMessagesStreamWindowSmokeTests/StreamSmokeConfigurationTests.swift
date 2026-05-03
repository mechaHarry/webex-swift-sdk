import XCTest
@testable import WebexMessagesStreamWindowSmoke

final class StreamSmokeConfigurationTests: XCTestCase {
    func testConfigurationRequiresCredentialsAndRoomID() {
        XCTAssertThrowsError(try StreamSmokeConfiguration(environment: [:])) { error in
            XCTAssertEqual(error as? StreamSmokeError, .missingEnvironment("WEBEX_CLIENT_ID"))
        }
    }

    func testConfigurationDefaultsToLoopbackRealtimeScopesAndSinglePageStream() throws {
        let configuration = try StreamSmokeConfiguration(environment: [
            "WEBEX_CLIENT_ID": "client-id",
            "WEBEX_CLIENT_SECRET": "client-secret",
            "WEBEX_ROOM_ID": "room-id"
        ])

        XCTAssertEqual(configuration.integration.clientID, "client-id")
        XCTAssertEqual(configuration.integration.clientSecret, "client-secret")
        XCTAssertEqual(configuration.integration.redirectURI.absoluteString, "http://127.0.0.1:8282/oauth/callback")
        XCTAssertEqual(configuration.integration.scopes, ["spark:all", "spark:kms"])
        XCTAssertEqual(configuration.roomID, "room-id")
        XCTAssertEqual(configuration.pageSize, 25)
        XCTAssertEqual(configuration.pageLimit, 1)
        XCTAssertEqual(configuration.keychainService, "com.webex.swift-sdk.messages-stream-window-smoke")
        XCTAssertEqual(configuration.listParams.roomID, "room-id")
        XCTAssertEqual(configuration.listParams.max, 25)
    }

    func testConfigurationAppliesOverrides() throws {
        let configuration = try StreamSmokeConfiguration(environment: [
            "WEBEX_CLIENT_ID": "client-id",
            "WEBEX_CLIENT_SECRET": "client-secret",
            "WEBEX_ROOM_ID": "room-id",
            "WEBEX_REDIRECT_URI": "http://127.0.0.1:8282/oauth/callback",
            "WEBEX_SCOPES": "spark:messages_read spark:people_read",
            "WEBEX_MESSAGES_PAGE_SIZE": "10",
            "WEBEX_MESSAGES_STREAM_PAGE_LIMIT": "3",
            "WEBEX_KEYCHAIN_SERVICE": "custom.service"
        ])

        XCTAssertEqual(configuration.integration.scopes, ["spark:messages_read", "spark:people_read"])
        XCTAssertEqual(configuration.pageSize, 10)
        XCTAssertEqual(configuration.pageLimit, 3)
        XCTAssertEqual(configuration.keychainService, "custom.service")
    }

    func testInvalidRedirectURIErrorDoesNotExposeInput() {
        let redirectURI = "http://[::1/oauth/callback"

        XCTAssertThrowsError(try StreamSmokeConfiguration(environment: [
            "WEBEX_CLIENT_ID": "client-id",
            "WEBEX_CLIENT_SECRET": "client-secret",
            "WEBEX_ROOM_ID": "room-id",
            "WEBEX_REDIRECT_URI": redirectURI
        ])) { error in
            let description = String(describing: error)
            XCTAssertEqual(description, "Invalid WEBEX_REDIRECT_URI")
            XCTAssertFalse(description.contains(redirectURI))
            XCTAssertFalse(description.contains("/oauth/callback"))
        }
    }

    func testMissingRealtimeScopesExplainsRequestedAndGrantedScopes() {
        let error = StreamSmokeError.missingRealtimeScopes(
            requested: ["spark:all"],
            granted: ["spark:people_read"]
        )

        XCTAssertEqual(
            error.description,
            "OAuth token is missing realtime scopes. Required: spark:all spark:kms. Requested: spark:all. Granted: spark:people_read. Update the Webex integration scopes and reauthorize."
        )
    }
}
