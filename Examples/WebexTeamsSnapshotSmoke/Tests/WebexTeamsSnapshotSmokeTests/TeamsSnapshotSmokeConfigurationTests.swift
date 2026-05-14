import XCTest
import WebexSwiftSDK
@testable import WebexTeamsSnapshotSmoke

final class TeamsSnapshotSmokeConfigurationTests: XCTestCase {
    func testConfigurationRequiresCredentials() {
        XCTAssertThrowsError(try TeamsSnapshotSmokeConfiguration(environment: [:])) { error in
            XCTAssertEqual(error as? TeamsSnapshotSmokeError, .missingEnvironment("WEBEX_CLIENT_ID"))
        }
    }

    func testConfigurationDefaultsToTeamsReadAndSinglePageStream() throws {
        let configuration = try TeamsSnapshotSmokeConfiguration(environment: [
            "WEBEX_CLIENT_ID": "client-id",
            "WEBEX_CLIENT_SECRET": "client-secret"
        ])

        XCTAssertEqual(configuration.integration.clientID, "client-id")
        XCTAssertEqual(configuration.integration.clientSecret, "client-secret")
        XCTAssertEqual(configuration.integration.redirectURI.absoluteString, "http://127.0.0.1:8282/oauth/callback")
        XCTAssertEqual(configuration.integration.scopes, ["spark:teams_read"])
        XCTAssertEqual(configuration.pageSize, 25)
        XCTAssertEqual(configuration.pageLimit, 1)
        XCTAssertEqual(configuration.keychainService, "com.webex.swift-sdk.teams-snapshot-smoke")
        XCTAssertEqual(configuration.listParams.max, 25)
    }

    func testConfigurationAppliesOverrides() throws {
        let configuration = try TeamsSnapshotSmokeConfiguration(environment: [
            "WEBEX_CLIENT_ID": "client-id",
            "WEBEX_CLIENT_SECRET": "client-secret",
            "WEBEX_SCOPES": "spark:teams_read,spark:teams_write",
            "WEBEX_TEAMS_PAGE_SIZE": "10",
            "WEBEX_TEAMS_STREAM_PAGE_LIMIT": "3",
            "WEBEX_KEYCHAIN_SERVICE": "custom.service"
        ])

        XCTAssertEqual(configuration.integration.scopes, ["spark:teams_read", "spark:teams_write"])
        XCTAssertEqual(configuration.pageSize, 10)
        XCTAssertEqual(configuration.pageLimit, 3)
        XCTAssertEqual(configuration.keychainService, "custom.service")
        XCTAssertEqual(configuration.listParams.max, 10)
    }

    func testInvalidEnvironmentValuesUseSafeErrors() {
        let redirectURI = "http://[::1/oauth/callback"
        XCTAssertThrowsError(try TeamsSnapshotSmokeConfiguration(environment: [
            "WEBEX_CLIENT_ID": "client-id",
            "WEBEX_CLIENT_SECRET": "client-secret",
            "WEBEX_REDIRECT_URI": redirectURI
        ])) { error in
            let description = String(describing: error)
            XCTAssertEqual(description, "Invalid WEBEX_REDIRECT_URI")
            XCTAssertFalse(description.contains(redirectURI))
        }

        XCTAssertThrowsError(try TeamsSnapshotSmokeConfiguration(environment: [
            "WEBEX_CLIENT_ID": "client-id",
            "WEBEX_CLIENT_SECRET": "client-secret",
            "WEBEX_TEAMS_PAGE_SIZE": "0"
        ])) { error in
            XCTAssertEqual(
                String(describing: error),
                "WEBEX_TEAMS_PAGE_SIZE must be an integer between 1 and 1000; received 0"
            )
        }
    }
}
