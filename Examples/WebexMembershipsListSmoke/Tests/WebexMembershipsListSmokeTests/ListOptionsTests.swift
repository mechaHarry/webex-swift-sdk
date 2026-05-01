import XCTest
import WebexSwiftSDK
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

    func testPageSizeAndMaxPagesOverridesAreApplied() throws {
        let options = try MembershipListOptions(environment: [
            "WEBEX_ROOM_ID": "room-id",
            "WEBEX_MEMBERSHIPS_PAGE_SIZE": "25",
            "WEBEX_MEMBERSHIPS_MAX_PAGES": "3"
        ])

        XCTAssertEqual(options.pageSize, 25)
        XCTAssertEqual(options.maxPages, 3)
        XCTAssertEqual(options.query.max, 25)
    }

    func testInvalidPageSizeAndMaxPagesThrow() {
        XCTAssertThrowsError(try MembershipListOptions(environment: [
            "WEBEX_ROOM_ID": "room-id",
            "WEBEX_MEMBERSHIPS_PAGE_SIZE": "0"
        ]))

        XCTAssertThrowsError(try MembershipListOptions(environment: [
            "WEBEX_ROOM_ID": "room-id",
            "WEBEX_MEMBERSHIPS_MAX_PAGES": "not-a-number"
        ]))
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

    func testFailureDescriptionDoesNotExposeInvalidAuthorizationCallbackURL() {
        let callbackURL = "http://127.0.0.1:8282/oauth/callback?code=secret-code&state=secret-state"
        let description = WebexMembershipsListSmoke.failureDescription(
            for: WebexSDKError.invalidAuthorizationCallback(callbackURL)
        )

        XCTAssertEqual(description, "Invalid authorization callback")
        XCTAssertFalse(description.contains("http://"))
        XCTAssertFalse(description.contains("127.0.0.1"))
        XCTAssertFalse(description.contains("/oauth/callback"))
        XCTAssertFalse(description.contains("code="))
        XCTAssertFalse(description.contains("state="))
    }
}
