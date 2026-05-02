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

    func testDecodesKnownJSSDKLikeRoomEvents() throws {
        for eventName in ["created", "updated"] {
            let event = try decodeJSSDKLikeEvent(
                resource: "rooms",
                event: eventName,
                resourceID: "room-\(eventName)"
            )

            XCTAssertEqual(event.resource, "rooms")
            XCTAssertEqual(event.event, eventName)
            XCTAssertEqual(event.knownResource, .rooms)
            XCTAssertEqual(event.knownEvent, WebexRealtimeEventName(rawValue: eventName))
            XCTAssertEqual(event.decodeStatus, .known)
            XCTAssertEqual(event.resourceID, "room-\(eventName)")
        }
    }

    func testDecodesKnownJSSDKLikeMembershipEvents() throws {
        for eventName in ["created", "updated", "deleted", "seen"] {
            let event = try decodeJSSDKLikeEvent(
                resource: "memberships",
                event: eventName,
                resourceID: "membership-\(eventName)"
            )

            XCTAssertEqual(event.resource, "memberships")
            XCTAssertEqual(event.event, eventName)
            XCTAssertEqual(event.knownResource, .memberships)
            XCTAssertEqual(event.knownEvent, WebexRealtimeEventName(rawValue: eventName))
            XCTAssertEqual(event.decodeStatus, .known)
            XCTAssertEqual(event.resourceID, "membership-\(eventName)")
        }
    }

    func testDecodesKnownJSSDKLikeAttachmentActionCreatedEvent() throws {
        let event = try decodeJSSDKLikeEvent(
            resource: "attachmentActions",
            event: "created",
            resourceID: "attachment-action-1"
        )

        XCTAssertEqual(event.resource, "attachmentActions")
        XCTAssertEqual(event.event, "created")
        XCTAssertEqual(event.knownResource, .attachmentActions)
        XCTAssertEqual(event.knownEvent, .created)
        XCTAssertEqual(event.decodeStatus, .known)
        XCTAssertEqual(event.resourceID, "attachment-action-1")
    }

    func testMarksUnknownJSSDKLikeResourceAsUnknownEvent() throws {
        let event = try decodeJSSDKLikeEvent(
            resource: "futureResource",
            event: "created",
            resourceID: "future-1"
        )

        XCTAssertEqual(event.resource, "futureResource")
        XCTAssertEqual(event.event, "created")
        XCTAssertEqual(event.knownResource, .unknown("futureResource"))
        XCTAssertEqual(event.knownEvent, .created)
        XCTAssertEqual(event.decodeStatus, .unknownEvent)
        XCTAssertEqual(event.resourceID, "future-1")
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

    func testMapsMercuryConversationActivityUpdateToMessageUpdatedUnknownEvent() throws {
        let event = try decodeMercuryConversationActivity(
            verb: "update",
            activityID: "activity-update",
            objectID: "message-update"
        )

        XCTAssertEqual(event.resource, "messages")
        XCTAssertEqual(event.event, "updated")
        XCTAssertEqual(event.knownResource, .messages)
        XCTAssertEqual(event.knownEvent, .updated)
        XCTAssertEqual(event.decodeStatus, .unknownEvent)
        XCTAssertEqual(event.resourceID, "message-update")
        XCTAssertEqual(event.ackID, "message-update")
    }

    func testMapsMercuryConversationActivityDeleteToMessageDeleted() throws {
        let event = try decodeMercuryConversationActivity(
            verb: "delete",
            activityID: "activity-delete",
            objectID: "message-delete"
        )

        XCTAssertEqual(event.resource, "messages")
        XCTAssertEqual(event.event, "deleted")
        XCTAssertEqual(event.knownResource, .messages)
        XCTAssertEqual(event.knownEvent, .deleted)
        XCTAssertEqual(event.decodeStatus, .known)
        XCTAssertEqual(event.resourceID, "message-delete")
        XCTAssertEqual(event.ackID, "message-delete")
    }

    func testMapsMercuryConversationActivityUnsupportedVerbToUnknownEvent() throws {
        let event = try decodeMercuryConversationActivity(
            verb: "share",
            activityID: "activity-share",
            objectID: "message-share"
        )

        XCTAssertEqual(event.resource, "messages")
        XCTAssertEqual(event.event, "share")
        XCTAssertEqual(event.knownResource, .messages)
        XCTAssertEqual(event.knownEvent, .unknown("share"))
        XCTAssertEqual(event.decodeStatus, .unknownEvent)
        XCTAssertEqual(event.resourceID, "message-share")
        XCTAssertEqual(event.ackID, "message-share")
    }

    func testMercuryConversationActivityFallsBackToActivityIDForResourceAndAckID() throws {
        let event = try decodeMercuryConversationActivity(
            verb: "post",
            activityID: "activity-fallback",
            objectID: nil
        )

        XCTAssertEqual(event.resource, "messages")
        XCTAssertEqual(event.event, "created")
        XCTAssertEqual(event.decodeStatus, .known)
        XCTAssertEqual(event.resourceID, "activity-fallback")
        XCTAssertEqual(event.ackID, "activity-fallback")
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

private func decodeJSSDKLikeEvent(
    resource: String,
    event: String,
    resourceID: String
) throws -> WebexRealtimeEvent {
    try WebexRealtimeEventDecoder().decode(jsonData("""
    {
      "id": "event-\(resource)-\(event)",
      "resource": "\(resource)",
      "event": "\(event)",
      "data": {
        "id": "\(resourceID)",
        "roomId": "room-\(resourceID)",
        "personId": "person-\(resourceID)"
      }
    }
    """))
}

private func decodeMercuryConversationActivity(
    verb: String,
    activityID: String,
    objectID: String?
) throws -> WebexRealtimeEvent {
    let objectJSON = objectID.map { #"""
          "object": {
            "id": "\#($0)"
          },
    """# } ?? ""

    return try WebexRealtimeEventDecoder().decode(jsonData("""
    {
      "id": "mercury-\(verb)",
      "data": {
        "eventType": "conversation.activity",
        "activity": {
          "id": "\(activityID)",
          "verb": "\(verb)",
    \(objectJSON)
          "target": {
            "id": "room-\(activityID)"
          },
          "actor": {
            "id": "person-\(activityID)"
          }
        }
      }
    }
    """))
}
