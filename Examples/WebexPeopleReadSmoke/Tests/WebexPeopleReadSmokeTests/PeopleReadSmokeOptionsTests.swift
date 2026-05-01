import XCTest
import WebexSwiftSDK
@testable import WebexPeopleReadSmoke

final class PeopleReadSmokeOptionsTests: XCTestCase {
    func testDisplayNameDefaultsToHarrison() {
        let options = PeopleReadOptions(environment: [:])

        XCTAssertEqual(options.displayName, "Harrison")
    }

    func testDisplayNameTrimsWhitespace() {
        let options = PeopleReadOptions(environment: [
            "WEBEX_PEOPLE_DISPLAY_NAME": "  Harrison \n"
        ])

        XCTAssertEqual(options.displayName, "Harrison")
    }

    func testEmptyDisplayNameFallsBackToHarrison() {
        let options = PeopleReadOptions(environment: [
            "WEBEX_PEOPLE_DISPLAY_NAME": " \n\t "
        ])

        XCTAssertEqual(options.displayName, "Harrison")
    }

    func testInvalidRedirectURIErrorDescriptionDoesNotExposeURL() throws {
        let redirectURI = "http://[::1/oauth/callback"

        XCTAssertThrowsError(try WebexPeopleReadSmoke.configurationFromEnvironment([
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
        let description = WebexPeopleReadSmoke.failureDescription(
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
