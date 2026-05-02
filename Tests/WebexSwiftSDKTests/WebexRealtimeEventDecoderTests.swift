import XCTest
@testable import WebexSwiftSDK

final class WebexRealtimeEventDecoderTests: XCTestCase {
    func testDecodesJSSDKLikeMessageCreatedEvent() throws {
        let event = try WebexRealtimeEventDecoder().decode(jsonData("""
        {
          "id": "event-1",
          "resource": "messages",
          "event": "created",
          "data": {
            "id": "message-1",
            "roomId": "room-1",
            "personId": "person-1",
            "text": "hello"
          }
        }
        """))

        XCTAssertEqual(event.id, "event-1")
        XCTAssertEqual(event.resource, "messages")
        XCTAssertEqual(event.event, "created")
        XCTAssertEqual(event.knownResource, .messages)
        XCTAssertEqual(event.knownEvent, .created)
        XCTAssertEqual(event.decodeStatus, .known)
        XCTAssertEqual(event.resourceID, "message-1")
        XCTAssertEqual(event.roomID, "room-1")
        XCTAssertEqual(event.actorID, "person-1")
        XCTAssertEqual(event.payload["text"], .string("hello"))
    }

    func testPreservesUnknownEvent() throws {
        let event = try WebexRealtimeEventDecoder().decode(jsonData("""
        {
          "id": "event-2",
          "resource": "messages",
          "event": "updated",
          "data": {
            "id": "message-2",
            "roomId": "room-2",
            "actorId": "person-2"
          }
        }
        """))

        XCTAssertEqual(event.knownResource, .messages)
        XCTAssertEqual(event.knownEvent, .updated)
        XCTAssertEqual(event.decodeStatus, .unknownEvent)
        XCTAssertEqual(event.resourceID, "message-2")
        XCTAssertEqual(event.roomID, "room-2")
        XCTAssertEqual(event.actorID, "person-2")
    }

    func testMarksKnownEventWithUnexpectedPayloadAsUnknownPayload() throws {
        let event = try WebexRealtimeEventDecoder().decode(jsonData("""
        {
          "id": "event-3",
          "resource": "messages",
          "event": "created",
          "data": {
            "roomId": "room-3",
            "personId": "person-3"
          }
        }
        """))

        XCTAssertEqual(event.knownResource, .messages)
        XCTAssertEqual(event.knownEvent, .created)
        XCTAssertEqual(event.decodeStatus, .unknownPayload)
        XCTAssertNil(event.resourceID)
        XCTAssertEqual(event.roomID, "room-3")
        XCTAssertEqual(event.actorID, "person-3")
    }

    func testMapsMercuryConversationActivityPostToMessageCreated() throws {
        let event = try WebexRealtimeEventDecoder().decode(jsonData("""
        {
          "id": "mercury-1",
          "data": {
            "eventType": "conversation.activity",
            "activity": {
              "id": "activity-1",
              "verb": "post",
              "object": {
                "id": "message-4"
              },
              "target": {
                "id": "room-4"
              },
              "actor": {
                "id": "person-4"
              }
            }
          }
        }
        """))

        XCTAssertEqual(event.id, "mercury-1")
        XCTAssertEqual(event.resource, "messages")
        XCTAssertEqual(event.event, "created")
        XCTAssertEqual(event.knownResource, .messages)
        XCTAssertEqual(event.knownEvent, .created)
        XCTAssertEqual(event.decodeStatus, .known)
        XCTAssertEqual(event.resourceID, "message-4")
        XCTAssertEqual(event.roomID, "room-4")
        XCTAssertEqual(event.actorID, "person-4")
        XCTAssertEqual(event.ackID, "message-4")
    }

    func testTriggerAdapterUsesEventStreamTrigger() {
        let event = WebexRealtimeEvent(
            resource: "messages",
            event: "created",
            decodeStatus: .known,
            resourceID: "message-5",
            roomID: "room-5",
            actorID: "person-5"
        )

        XCTAssertEqual(WebexRealtimeTriggerAdapter.trigger(for: event), event.streamTrigger())
    }

    func testUnknownRootShapePreservesPayloadAsUnknownPayload() throws {
        let event = try WebexRealtimeEventDecoder().decode(jsonData("""
        {
          "id": "unknown-1",
          "unexpected": {
            "value": "kept"
          }
        }
        """))

        XCTAssertEqual(event.id, "unknown-1")
        XCTAssertEqual(event.resource, "unknown")
        XCTAssertEqual(event.event, "unknown")
        XCTAssertEqual(event.knownResource, .unknown("unknown"))
        XCTAssertEqual(event.knownEvent, .unknown("unknown"))
        XCTAssertEqual(event.decodeStatus, .unknownPayload)
        XCTAssertEqual(event.payload["unexpected"], .object(["value": .string("kept")]))
    }

    func testRejectsNonObjectRootWithSafeNetworkError() throws {
        XCTAssertThrowsError(try WebexRealtimeEventDecoder().decode(jsonData("""
        ["not", "an", "object"]
        """))) { error in
            XCTAssertEqual(error as? WebexSDKError, .network("Invalid Webex realtime frame"))
        }
    }
}

private func jsonData(_ string: String) throws -> Data {
    try XCTUnwrap(string.data(using: .utf8))
}
