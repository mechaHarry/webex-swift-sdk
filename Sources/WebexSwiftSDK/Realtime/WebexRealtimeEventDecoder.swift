import Foundation

struct WebexRealtimeEventDecoder: Sendable {
    func decode(_ data: Data) throws -> WebexRealtimeEvent {
        let rootValue: WebexJSONValue
        do {
            rootValue = try JSONDecoder().decode(WebexJSONValue.self, from: data)
        } catch {
            throw WebexSDKError.network("Invalid Webex realtime frame")
        }

        guard case .object(let root) = rootValue else {
            throw WebexSDKError.network("Invalid Webex realtime frame")
        }

        if let resource = root.stringValue(forKey: "resource"),
           let event = root.stringValue(forKey: "event") {
            return decodeJSSDKLikeEvent(root: root, resource: resource, event: event)
        }

        if let mercuryEvent = decodeMercuryConversationActivity(root: root) {
            return mercuryEvent
        }

        return WebexRealtimeEvent(
            id: root.stringValue(forKey: "id"),
            resource: "unknown",
            event: "unknown",
            decodeStatus: .unknownPayload,
            payload: root
        )
    }

    private func decodeJSSDKLikeEvent(
        root: [String: WebexJSONValue],
        resource: String,
        event: String
    ) -> WebexRealtimeEvent {
        let payload = root.objectValue(forKey: "data") ?? [:]
        let resourceID = payload.stringValue(forKey: "id")
        let roomID = payload.stringValue(forKey: "roomId")
        let actorID = payload.stringValue(forKey: "personId") ?? payload.stringValue(forKey: "actorId")
        let knownResource = WebexRealtimeResource(rawValue: resource)
        let knownEvent = WebexRealtimeEventName(rawValue: event)

        return WebexRealtimeEvent(
            id: root.stringValue(forKey: "id"),
            resource: resource,
            event: event,
            knownResource: knownResource,
            knownEvent: knownEvent,
            decodeStatus: decodeStatus(
                knownResource: knownResource,
                knownEvent: knownEvent,
                resourceID: resourceID
            ),
            resourceID: resourceID,
            roomID: roomID,
            actorID: actorID,
            payload: payload
        )
    }

    private func decodeMercuryConversationActivity(root: [String: WebexJSONValue]) -> WebexRealtimeEvent? {
        guard let data = root.objectValue(forKey: "data"),
              data.stringValue(forKey: "eventType") == "conversation.activity",
              let activity = data.objectValue(forKey: "activity") else {
            return nil
        }

        let verb = activity.stringValue(forKey: "verb") ?? "unknown"
        let event = mercuryEventName(forVerb: verb)
        let resourceID = activity.objectValue(forKey: "object")?.stringValue(forKey: "id")
            ?? activity.stringValue(forKey: "id")
        let activityID = activity.stringValue(forKey: "id")
        let roomID = activity.objectValue(forKey: "target")?.stringValue(forKey: "id")
        let actorID = activity.objectValue(forKey: "actor")?.stringValue(forKey: "id")
        let knownEvent = WebexRealtimeEventName(rawValue: event)

        return WebexRealtimeEvent(
            id: root.stringValue(forKey: "id"),
            resource: "messages",
            event: event,
            knownResource: .messages,
            knownEvent: knownEvent,
            decodeStatus: mercuryDecodeStatus(verb: verb, knownEvent: knownEvent, resourceID: resourceID),
            resourceID: resourceID,
            roomID: roomID,
            actorID: actorID,
            ackID: resourceID ?? activityID,
            payload: activity
        )
    }

    private func mercuryEventName(forVerb verb: String) -> String {
        switch verb {
        case "post":
            return WebexRealtimeEventName.created.rawValue
        case "update":
            return WebexRealtimeEventName.updated.rawValue
        case "delete":
            return WebexRealtimeEventName.deleted.rawValue
        default:
            return verb
        }
    }

    private func mercuryDecodeStatus(
        verb: String,
        knownEvent: WebexRealtimeEventName,
        resourceID: String?
    ) -> WebexRealtimeDecodeStatus {
        guard ["post", "update", "delete"].contains(verb) else {
            return .unknownEvent
        }

        return decodeStatus(knownResource: .messages, knownEvent: knownEvent, resourceID: resourceID)
    }

    private func decodeStatus(
        knownResource: WebexRealtimeResource,
        knownEvent: WebexRealtimeEventName,
        resourceID: String?
    ) -> WebexRealtimeDecodeStatus {
        guard isRecognizedResource(knownResource) else {
            return .unknownEvent
        }

        guard isSampleBackedEvent(knownResource: knownResource, knownEvent: knownEvent) else {
            return .unknownEvent
        }

        guard resourceID != nil else {
            return .unknownPayload
        }

        return .known
    }

    private func isRecognizedResource(_ resource: WebexRealtimeResource) -> Bool {
        switch resource {
        case .messages, .rooms, .spaces, .memberships, .attachmentActions:
            return true
        case .unknown:
            return false
        }
    }

    private func isSampleBackedEvent(
        knownResource: WebexRealtimeResource,
        knownEvent: WebexRealtimeEventName
    ) -> Bool {
        switch (knownResource, knownEvent) {
        case (.messages, .created),
             (.messages, .deleted),
             (.rooms, .created),
             (.rooms, .updated),
             (.spaces, .created),
             (.spaces, .updated),
             (.memberships, .created),
             (.memberships, .updated),
             (.memberships, .deleted),
             (.memberships, .seen),
             (.attachmentActions, .created):
            return true
        default:
            return false
        }
    }
}

private extension Dictionary where Key == String, Value == WebexJSONValue {
    func stringValue(forKey key: String) -> String? {
        guard case .string(let value) = self[key] else {
            return nil
        }

        return value
    }

    func objectValue(forKey key: String) -> [String: WebexJSONValue]? {
        guard case .object(let value) = self[key] else {
            return nil
        }

        return value
    }
}
