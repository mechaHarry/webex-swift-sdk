import XCTest
import WebexSwiftSDK
@testable import WebexRealtimeEventsSmoke

final class RealtimeSmokeOptionsTests: XCTestCase {
    func testDefaultsUseSDKRealtimeSubscriptionsAndDoNotPrintRawUnknownPayloads() throws {
        let options = try RealtimeSmokeOptions(environment: [:])

        XCTAssertNil(options.resource)
        XCTAssertNil(options.event)
        XCTAssertFalse(options.includeSeen)
        XCTAssertFalse(options.printRawUnknown)
        XCTAssertEqual(options.realtimeOptions.resources, WebexRealtimeOptions().resources)
        XCTAssertEqual(options.realtimeOptions.events, WebexRealtimeOptions().events)
        XCTAssertFalse(options.realtimeOptions.includeMembershipSeen)
    }

    func testParsesResourceEventAndEnabledBooleans() throws {
        let options = try RealtimeSmokeOptions(environment: [
            "WEBEX_REALTIME_RESOURCE": "messages",
            "WEBEX_REALTIME_EVENT": "created",
            "WEBEX_REALTIME_INCLUDE_SEEN": "yes",
            "WEBEX_REALTIME_PRINT_RAW_UNKNOWN": "1"
        ])

        XCTAssertEqual(options.resource, WebexRealtimeResource.messages)
        XCTAssertEqual(options.event, WebexRealtimeEventName.created)
        XCTAssertTrue(options.includeSeen)
        XCTAssertTrue(options.printRawUnknown)
        XCTAssertEqual(options.realtimeOptions.resources, [.messages])
        XCTAssertEqual(options.realtimeOptions.events, [.created])
        XCTAssertTrue(options.realtimeOptions.includeMembershipSeen)
    }

    func testParsesUnknownResourceAndEventNamesAsExactFilters() throws {
        let options = try RealtimeSmokeOptions(environment: [
            "WEBEX_REALTIME_RESOURCE": "futureResource",
            "WEBEX_REALTIME_EVENT": "futureEvent"
        ])

        XCTAssertEqual(options.resource, WebexRealtimeResource.unknown("futureResource"))
        XCTAssertEqual(options.event, WebexRealtimeEventName.unknown("futureEvent"))
        XCTAssertEqual(options.realtimeOptions.resources, [.unknown("futureResource")])
        XCTAssertEqual(options.realtimeOptions.events, [.unknown("futureEvent")])
    }

    func testBooleanParserAcceptsDocumentedValuesCaseInsensitively() throws {
        XCTAssertTrue(try RealtimeSmokeOptions.boolean(named: "FLAG", environment: ["FLAG": "TrUe"], defaultValue: false))
        XCTAssertTrue(try RealtimeSmokeOptions.boolean(named: "FLAG", environment: ["FLAG": "YES"], defaultValue: false))
        XCTAssertTrue(try RealtimeSmokeOptions.boolean(named: "FLAG", environment: ["FLAG": "1"], defaultValue: false))
        XCTAssertFalse(try RealtimeSmokeOptions.boolean(named: "FLAG", environment: ["FLAG": "FaLsE"], defaultValue: true))
        XCTAssertFalse(try RealtimeSmokeOptions.boolean(named: "FLAG", environment: ["FLAG": "NO"], defaultValue: true))
        XCTAssertFalse(try RealtimeSmokeOptions.boolean(named: "FLAG", environment: ["FLAG": "0"], defaultValue: true))
    }

    func testInvalidBooleanThrowsLoudlyWithoutLeakingValueIntoSecrets() {
        XCTAssertThrowsError(try RealtimeSmokeOptions(environment: [
            "WEBEX_REALTIME_INCLUDE_SEEN": "maybe"
        ])) { error in
            XCTAssertEqual(
                String(describing: error),
                "WEBEX_REALTIME_INCLUDE_SEEN must be one of true, false, 1, 0, yes, or no; got maybe"
            )
        }
    }

    func testRedactorRemovesTokenAndSecretLikeValues() {
        let raw = #"Authorization: Bearer abc.def.ghi access_token=abc123 refresh_token=def456 client_secret=shh token: "xyz" normal=value"#
        let redacted = RealtimeSmokeRedactor.redact(raw)

        XCTAssertFalse(redacted.contains("abc.def.ghi"))
        XCTAssertFalse(redacted.contains("abc123"))
        XCTAssertFalse(redacted.contains("def456"))
        XCTAssertFalse(redacted.contains("shh"))
        XCTAssertFalse(redacted.contains(#""xyz""#))
        XCTAssertTrue(redacted.contains("normal=value"))
    }
}
