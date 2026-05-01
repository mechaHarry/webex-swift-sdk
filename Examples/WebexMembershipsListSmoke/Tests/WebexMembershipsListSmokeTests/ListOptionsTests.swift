import XCTest
@testable import WebexMembershipsListSmoke

final class ListOptionsTests: XCTestCase {
    func testRequiresRoomIDAndDefaultsAvoidLowPageCaps() throws {
        XCTAssertThrowsError(try MembershipListOptions(environment: [:]))

        let options = try MembershipListOptions(environment: ["WEBEX_ROOM_ID": "room-id"])

        XCTAssertEqual(options.roomID, "room-id")
        XCTAssertEqual(options.pageSize, 100)
        XCTAssertEqual(options.maxPages, 1_000)
        XCTAssertEqual(options.query.roomID, "room-id")
        XCTAssertEqual(options.query.max, 100)
    }

    func testInvalidRedirectURIErrorDescriptionDoesNotExposeURL() throws {
        let redirectURI = "http://[::1/oauth/callback"

        XCTAssertThrowsError(try WebexMembershipsListSmoke.configurationFromEnvironment([
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
}
