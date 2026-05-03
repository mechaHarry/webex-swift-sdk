import XCTest
import WebexSwiftSDK
@testable import WebexRealtimeEventsSmoke

final class RealtimeSmokeOptionsTests: XCTestCase {
    func testDefaultConfigurationRequestsWebSocketRequiredScopes() throws {
        let configuration = try WebexRealtimeEventsSmoke.configurationFromEnvironment([
            "WEBEX_CLIENT_ID": "client-id",
            "WEBEX_CLIENT_SECRET": "client-secret"
        ])

        XCTAssertEqual(configuration.scopes, ["spark:all", "spark:kms"])
    }

    func testValidatesGrantedOAuthScopesForRealtime() throws {
        try WebexRealtimeEventsSmoke.validateGrantedOAuthScopes(
            requestedScopes: ["spark:kms", "spark:all"],
            grantedScopes: ["spark:all", "spark:kms"]
        )
    }

    func testMissingRealtimeOAuthScopesThrowBeforeDeviceRegistration() {
        XCTAssertThrowsError(try WebexRealtimeEventsSmoke.validateGrantedOAuthScopes(
            requestedScopes: ["spark:all", "spark:kms"],
            grantedScopes: ["spark:people_read"]
        )) { error in
            XCTAssertEqual(
                String(describing: error),
                "OAuth token is missing realtime scopes. Required: spark:all spark:kms. Requested: spark:all spark:kms. Granted: spark:people_read. Update the Webex integration scopes and reauthorize."
            )
        }
    }

    func testDirectAccessTokenIsTrimmedAndOptional() {
        XCTAssertEqual(
            WebexRealtimeEventsSmoke.directAccessToken(from: ["WEBEX_ACCESS_TOKEN": "  token-value  "]),
            "token-value"
        )
        XCTAssertNil(WebexRealtimeEventsSmoke.directAccessToken(from: [:]))
        XCTAssertNil(WebexRealtimeEventsSmoke.directAccessToken(from: ["WEBEX_ACCESS_TOKEN": "   "]))
    }

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

    func testRedactorRemovesJSONEncodedSecretValuesAndKeepsNormalValues() {
        let raw = #"{"access_token":"abc123","refresh_token":"def456","client_secret":"shh","clientSecret":"camel","authorization":"Bearer hidden","token":"xyz","secret":"top","normal":"value"}"#
        let redacted = RealtimeSmokeRedactor.redact(raw)

        XCTAssertFalse(redacted.contains("abc123"))
        XCTAssertFalse(redacted.contains("def456"))
        XCTAssertFalse(redacted.contains("shh"))
        XCTAssertFalse(redacted.contains("camel"))
        XCTAssertFalse(redacted.contains("hidden"))
        XCTAssertFalse(redacted.contains(#""xyz""#))
        XCTAssertFalse(redacted.contains("top"))
        XCTAssertTrue(redacted.contains(#""access_token":"[REDACTED]""#))
        XCTAssertTrue(redacted.contains(#""refresh_token":"[REDACTED]""#))
        XCTAssertTrue(redacted.contains(#""client_secret":"[REDACTED]""#))
        XCTAssertTrue(redacted.contains(#""clientSecret":"[REDACTED]""#))
        XCTAssertTrue(redacted.contains(#""authorization":"[REDACTED]""#))
        XCTAssertTrue(redacted.contains(#""token":"[REDACTED]""#))
        XCTAssertTrue(redacted.contains(#""secret":"[REDACTED]""#))
        XCTAssertTrue(redacted.contains(#""normal":"value""#))
    }

    func testFormatsRealtimeDiagnosticReconnectReason() {
        let diagnostic = WebexRealtimeDiagnosticEvent.reconnectScheduled(
            attempt: 2,
            delay: 4,
            reason: .network("socket closed")
        )

        let line = WebexRealtimeEventsSmoke.format(diagnostic: diagnostic)

        XCTAssertTrue(line.contains("diagnostic=reconnectScheduled"))
        XCTAssertTrue(line.contains("attempt=2"))
        XCTAssertTrue(line.contains("delay=4.0"))
        XCTAssertTrue(line.contains("reason=Network error: socket closed"))
    }

    func testFormatsRealtimeDiagnosticMetadataWithoutPayload() {
        let metadata = WebexRealtimeEventMetadata(
            id: "mercury-frame-id",
            resource: "messages",
            event: "created",
            knownResource: .messages,
            knownEvent: .created,
            decodeStatus: .known,
            resourceID: "message-id",
            roomID: "room-id",
            actorID: "person-id",
            ackID: "mercury-frame-id",
            sourceEventType: "conversation.activity",
            activityVerb: "post",
            objectType: "comment"
        )

        let line = WebexRealtimeEventsSmoke.format(diagnostic: .eventDecoded(metadata))

        XCTAssertTrue(line.contains("diagnostic=eventDecoded"))
        XCTAssertTrue(line.contains("known=true"))
        XCTAssertTrue(line.contains("resource=messages"))
        XCTAssertTrue(line.contains("event=created"))
        XCTAssertTrue(line.contains("resourceID=message-id"))
        XCTAssertTrue(line.contains("ackID=mercury-frame-id"))
        XCTAssertTrue(line.contains("sourceEventType=conversation.activity"))
        XCTAssertTrue(line.contains("activityVerb=post"))
        XCTAssertTrue(line.contains("objectType=comment"))
        XCTAssertFalse(line.contains("payload="))
    }
}
