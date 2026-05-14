import XCTest
import WebexSwiftSDK
@testable import WebexSpacesEnrichedSnapshotSmoke

final class EnrichedSpacesSmokeConfigurationTests: XCTestCase {
    func testConfigurationRequiresCredentials() {
        XCTAssertThrowsError(try EnrichedSpacesSmokeConfiguration(environment: [:])) { error in
            XCTAssertEqual(error as? EnrichedSpacesSmokeError, .missingEnvironment("WEBEX_CLIENT_ID"))
        }
    }

    func testConfigurationDefaultsToLoopbackRestScopesAndSinglePageStream() throws {
        let configuration = try EnrichedSpacesSmokeConfiguration(environment: [
            "WEBEX_CLIENT_ID": "client-id",
            "WEBEX_CLIENT_SECRET": "client-secret"
        ])

        XCTAssertEqual(configuration.integration.clientID, "client-id")
        XCTAssertEqual(configuration.integration.clientSecret, "client-secret")
        XCTAssertEqual(configuration.integration.redirectURI.absoluteString, "http://127.0.0.1:8282/oauth/callback")
        XCTAssertEqual(Set(configuration.integration.scopes), Set([
            "spark:memberships_read",
            "spark:people_read",
            "spark:rooms_read"
        ]))
        XCTAssertEqual(configuration.pageSize, 25)
        XCTAssertEqual(configuration.pageLimit, 1)
        XCTAssertEqual(configuration.keychainService, "com.webex.swift-sdk.spaces-enriched-snapshot-smoke")
        XCTAssertNil(configuration.listParams.teamID)
        XCTAssertNil(configuration.listParams.type)
        XCTAssertNil(configuration.listParams.sortBy)
        XCTAssertEqual(configuration.listParams.max, 25)
    }

    func testConfigurationAppliesOverrides() throws {
        let configuration = try EnrichedSpacesSmokeConfiguration(environment: [
            "WEBEX_CLIENT_ID": "client-id",
            "WEBEX_CLIENT_SECRET": "client-secret",
            "WEBEX_REDIRECT_URI": "http://127.0.0.1:8282/oauth/callback",
            "WEBEX_SCOPES": "spark:rooms_read spark:memberships_read spark:people_read spark:teams_read",
            "WEBEX_SPACES_PAGE_SIZE": "10",
            "WEBEX_SPACES_STREAM_PAGE_LIMIT": "3",
            "WEBEX_SPACES_TYPE": "direct",
            "WEBEX_SPACES_TEAM_ID": "team-id",
            "WEBEX_SPACES_SORT_BY": "lastactivity",
            "WEBEX_KEYCHAIN_SERVICE": "custom.service"
        ])

        XCTAssertEqual(Set(configuration.integration.scopes), Set([
            "spark:memberships_read",
            "spark:people_read",
            "spark:rooms_read",
            "spark:teams_read"
        ]))
        XCTAssertEqual(configuration.pageSize, 10)
        XCTAssertEqual(configuration.pageLimit, 3)
        XCTAssertEqual(configuration.keychainService, "custom.service")
        XCTAssertEqual(configuration.listParams.teamID, "team-id")
        XCTAssertEqual(configuration.listParams.type, .direct)
        XCTAssertEqual(configuration.listParams.sortBy, .lastActivity)
        XCTAssertEqual(configuration.listParams.max, 10)
    }

    func testInvalidEnvironmentValuesUseSafeErrors() {
        let redirectURI = "http://[::1/oauth/callback"
        XCTAssertThrowsError(try EnrichedSpacesSmokeConfiguration(environment: [
            "WEBEX_CLIENT_ID": "client-id",
            "WEBEX_CLIENT_SECRET": "client-secret",
            "WEBEX_REDIRECT_URI": redirectURI
        ])) { error in
            let description = String(describing: error)
            XCTAssertEqual(description, "Invalid WEBEX_REDIRECT_URI")
            XCTAssertFalse(description.contains(redirectURI))
        }

        XCTAssertThrowsError(try EnrichedSpacesSmokeConfiguration(environment: [
            "WEBEX_CLIENT_ID": "client-id",
            "WEBEX_CLIENT_SECRET": "client-secret",
            "WEBEX_SPACES_PAGE_SIZE": "0"
        ])) { error in
            XCTAssertEqual(
                String(describing: error),
                "WEBEX_SPACES_PAGE_SIZE must be an integer between 1 and 1000; received 0"
            )
        }

        XCTAssertThrowsError(try EnrichedSpacesSmokeConfiguration(environment: [
            "WEBEX_CLIENT_ID": "client-id",
            "WEBEX_CLIENT_SECRET": "client-secret",
            "WEBEX_SPACES_TYPE": "team"
        ])) { error in
            XCTAssertEqual(
                String(describing: error),
                "WEBEX_SPACES_TYPE must be direct or group; received team"
            )
        }

        XCTAssertThrowsError(try EnrichedSpacesSmokeConfiguration(environment: [
            "WEBEX_CLIENT_ID": "client-id",
            "WEBEX_CLIENT_SECRET": "client-secret",
            "WEBEX_SPACES_SORT_BY": "updated"
        ])) { error in
            XCTAssertEqual(
                String(describing: error),
                "WEBEX_SPACES_SORT_BY must be id, lastactivity, or created; received updated"
            )
        }
    }
}
