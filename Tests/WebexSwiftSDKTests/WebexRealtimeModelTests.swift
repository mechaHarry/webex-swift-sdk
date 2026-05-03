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
            ackID: "frame-id",
            payload: ["id": .string("message-id")]
        )

        let trigger = event.streamTrigger()

        XCTAssertEqual(trigger.resource, "messages")
        XCTAssertEqual(trigger.event, "created")
        XCTAssertEqual(trigger.resourceID, "message-id")
        XCTAssertEqual(trigger.roomID, "room-id")
        XCTAssertEqual(trigger.actorID, "actor-id")
    }

    func testRealtimeEventMetadataCopiesEventWithoutPayload() {
        let event = WebexRealtimeEvent(
            id: "frame-id",
            resource: "messages",
            event: "created",
            knownResource: .messages,
            knownEvent: .created,
            decodeStatus: .known,
            resourceID: "message-id",
            roomID: "room-id",
            actorID: "actor-id",
            ackID: "frame-id",
            sourceEventType: "conversation.activity",
            activityVerb: "post",
            objectType: "comment",
            payload: ["text": .string("message body")]
        )

        let metadata = WebexRealtimeEventMetadata(event: event)

        XCTAssertEqual(metadata.id, "frame-id")
        XCTAssertEqual(metadata.resource, "messages")
        XCTAssertEqual(metadata.event, "created")
        XCTAssertEqual(metadata.knownResource, .messages)
        XCTAssertEqual(metadata.knownEvent, .created)
        XCTAssertEqual(metadata.decodeStatus, .known)
        XCTAssertTrue(metadata.isKnown)
        XCTAssertEqual(metadata.resourceID, "message-id")
        XCTAssertEqual(metadata.roomID, "room-id")
        XCTAssertEqual(metadata.actorID, "actor-id")
        XCTAssertEqual(metadata.ackID, "frame-id")
        XCTAssertEqual(metadata.sourceEventType, "conversation.activity")
        XCTAssertEqual(metadata.activityVerb, "post")
        XCTAssertEqual(metadata.objectType, "comment")
    }

    func testRealtimeEventAllowsMissingID() {
        let event = WebexRealtimeEvent(
            resource: "futureResource",
            event: "renamed",
            decodeStatus: .unknownEvent,
            payload: ["value": .string("raw")]
        )

        XCTAssertNil(event.id)
        XCTAssertEqual(event.resource, "futureResource")
        XCTAssertEqual(event.event, "renamed")
        XCTAssertEqual(event.knownResource, .unknown("futureResource"))
        XCTAssertEqual(event.knownEvent, .unknown("renamed"))
        XCTAssertEqual(event.payload, ["value": .string("raw")])
    }

    func testDefaultOptionsExcludeSeenEvents() {
        let options = WebexRealtimeOptions(resources: [.messages, .memberships])

        XCTAssertEqual(options.resources, [.messages, .memberships])
        XCTAssertFalse(options.includeMembershipSeen)
        XCTAssertEqual(options.retryPolicy.maximumDelay, 240)
    }
}
