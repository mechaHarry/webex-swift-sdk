import XCTest
@testable import WebexSwiftSDK

final class WebexRealtimeModelTests: XCTestCase {
    func testResourceAndEventPreserveUnknownRawValues() {
        XCTAssertEqual(WebexRealtimeResource.messages.rawValue, "messages")
        XCTAssertEqual(WebexRealtimeResource.spaces.rawValue, "rooms")
        XCTAssertEqual(WebexRealtimeResource.rooms.rawValue, "rooms")
        XCTAssertEqual(WebexRealtimeResource.unknown("future").rawValue, "future")

        XCTAssertEqual(WebexRealtimeEventName.created.rawValue, "created")
        XCTAssertEqual(WebexRealtimeEventName.seen.rawValue, "seen")
        XCTAssertEqual(WebexRealtimeEventName.unknown("renamed").rawValue, "renamed")
    }

    func testRealtimeEventBuildsStreamTrigger() {
        let event = WebexRealtimeEvent(
            id: "event-id",
            resource: "messages",
            event: "created",
            knownResource: .messages,
            knownEvent: .created,
            decodeStatus: .known,
            resourceID: "message-id",
            roomID: "room-id",
            actorID: "actor-id",
            ackID: "message-id",
            payload: ["id": .string("message-id")]
        )

        let trigger = event.streamTrigger()

        XCTAssertEqual(trigger.resource, "messages")
        XCTAssertEqual(trigger.event, "created")
        XCTAssertEqual(trigger.resourceID, "message-id")
        XCTAssertEqual(trigger.roomID, "room-id")
        XCTAssertEqual(trigger.actorID, "actor-id")
    }

    func testDefaultOptionsExcludeSeenEvents() {
        let options = WebexRealtimeOptions(resources: [.messages, .memberships])

        XCTAssertEqual(options.resources, [.messages, .memberships])
        XCTAssertFalse(options.includeMembershipSeen)
        XCTAssertEqual(options.retryPolicy.maximumDelay, 240)
    }
}
