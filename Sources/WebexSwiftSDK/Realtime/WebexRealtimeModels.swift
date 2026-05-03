import Foundation

public enum WebexRealtimeResource: Hashable, Sendable {
    case messages
    case spaces
    case rooms
    case memberships
    case attachmentActions
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .messages:
            return "messages"
        case .spaces, .rooms:
            return "rooms"
        case .memberships:
            return "memberships"
        case .attachmentActions:
            return "attachmentActions"
        case .unknown(let value):
            return value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "messages":
            self = .messages
        case "spaces":
            self = .spaces
        case "rooms":
            self = .rooms
        case "memberships":
            self = .memberships
        case "attachmentActions":
            self = .attachmentActions
        default:
            self = .unknown(rawValue)
        }
    }
}

public enum WebexRealtimeEventName: Hashable, Sendable {
    case created
    case updated
    case deleted
    case seen
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .created:
            return "created"
        case .updated:
            return "updated"
        case .deleted:
            return "deleted"
        case .seen:
            return "seen"
        case .unknown(let value):
            return value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "created":
            self = .created
        case "updated":
            self = .updated
        case "deleted":
            self = .deleted
        case "seen":
            self = .seen
        default:
            self = .unknown(rawValue)
        }
    }
}

public enum WebexRealtimeDecodeStatus: Equatable, Sendable {
    case known
    case unknownEvent
    case unknownPayload
}

public enum WebexRealtimeConnectionState: Equatable, Sendable {
    case disconnected
    case discovering
    case registeringDevice
    case connecting
    case authorizing
    case connected
    case reconnecting(attempt: Int, delay: TimeInterval)
    case failed(WebexSDKError)
}

public struct WebexRealtimeEventMetadata: Equatable, Sendable {
    public let id: String?
    public let resource: String
    public let event: String
    public let knownResource: WebexRealtimeResource
    public let knownEvent: WebexRealtimeEventName
    public let decodeStatus: WebexRealtimeDecodeStatus
    public let resourceID: String?
    public let roomID: String?
    public let actorID: String?
    public let ackID: String?
    public let sourceEventType: String?
    public let activityVerb: String?
    public let objectType: String?

    public var isKnown: Bool {
        decodeStatus == .known
    }

    public init(
        id: String? = nil,
        resource: String,
        event: String,
        knownResource: WebexRealtimeResource,
        knownEvent: WebexRealtimeEventName,
        decodeStatus: WebexRealtimeDecodeStatus,
        resourceID: String? = nil,
        roomID: String? = nil,
        actorID: String? = nil,
        ackID: String? = nil,
        sourceEventType: String? = nil,
        activityVerb: String? = nil,
        objectType: String? = nil
    ) {
        self.id = id
        self.resource = resource
        self.event = event
        self.knownResource = knownResource
        self.knownEvent = knownEvent
        self.decodeStatus = decodeStatus
        self.resourceID = resourceID
        self.roomID = roomID
        self.actorID = actorID
        self.ackID = ackID
        self.sourceEventType = sourceEventType
        self.activityVerb = activityVerb
        self.objectType = objectType
    }

    public init(event: WebexRealtimeEvent) {
        self.init(
            id: event.id,
            resource: event.resource,
            event: event.event,
            knownResource: event.knownResource,
            knownEvent: event.knownEvent,
            decodeStatus: event.decodeStatus,
            resourceID: event.resourceID,
            roomID: event.roomID,
            actorID: event.actorID,
            ackID: event.ackID,
            sourceEventType: event.sourceEventType,
            activityVerb: event.activityVerb,
            objectType: event.objectType
        )
    }
}

public enum WebexRealtimeDiagnosticEvent: Equatable, Sendable {
    case eventDecoded(WebexRealtimeEventMetadata)
    case eventFilteredOut(WebexRealtimeEventMetadata)
    case ackSucceeded(WebexRealtimeEventMetadata)
    case ackFailed(WebexRealtimeEventMetadata, error: WebexSDKError)
    case frameDecodeFailed(error: WebexSDKError)
    case reconnectScheduled(attempt: Int, delay: TimeInterval, reason: WebexSDKError)
}

public struct WebexRealtimeOptions: Sendable {
    public let resources: [WebexRealtimeResource]
    public let events: [WebexRealtimeEventName]
    public let includeMembershipSeen: Bool
    public let retryPolicy: RetryPolicy
    public let deviceName: String
    public let diagnosticHandler: (@Sendable (WebexRealtimeDiagnosticEvent) -> Void)?

    public init(
        resources: [WebexRealtimeResource] = [.messages, .spaces, .memberships, .attachmentActions],
        events: [WebexRealtimeEventName] = [],
        includeMembershipSeen: Bool = false,
        retryPolicy: RetryPolicy = RetryPolicy(maxAttempts: 5, baseDelay: 1, jitter: 0.25, maximumDelay: 240),
        deviceName: String = "webex-swift-sdk",
        diagnosticHandler: (@Sendable (WebexRealtimeDiagnosticEvent) -> Void)? = nil
    ) {
        self.resources = resources
        self.events = events
        self.includeMembershipSeen = includeMembershipSeen
        self.retryPolicy = retryPolicy
        self.deviceName = deviceName
        self.diagnosticHandler = diagnosticHandler
    }
}

public struct WebexRealtimeEvent: Equatable, Sendable {
    public let id: String?
    public let resource: String
    public let event: String
    public let knownResource: WebexRealtimeResource
    public let knownEvent: WebexRealtimeEventName
    public let decodeStatus: WebexRealtimeDecodeStatus
    public let resourceID: String?
    public let roomID: String?
    public let actorID: String?
    public let ackID: String?
    public let sourceEventType: String?
    public let activityVerb: String?
    public let objectType: String?
    public let payload: [String: WebexJSONValue]

    public init(
        id: String? = nil,
        resource: String,
        event: String,
        knownResource: WebexRealtimeResource? = nil,
        knownEvent: WebexRealtimeEventName? = nil,
        decodeStatus: WebexRealtimeDecodeStatus,
        resourceID: String? = nil,
        roomID: String? = nil,
        actorID: String? = nil,
        ackID: String? = nil,
        sourceEventType: String? = nil,
        activityVerb: String? = nil,
        objectType: String? = nil,
        payload: [String: WebexJSONValue] = [:]
    ) {
        self.id = id
        self.resource = resource
        self.event = event
        self.knownResource = knownResource ?? WebexRealtimeResource(rawValue: resource)
        self.knownEvent = knownEvent ?? WebexRealtimeEventName(rawValue: event)
        self.decodeStatus = decodeStatus
        self.resourceID = resourceID
        self.roomID = roomID
        self.actorID = actorID
        self.ackID = ackID
        self.sourceEventType = sourceEventType
        self.activityVerb = activityVerb
        self.objectType = objectType
        self.payload = payload
    }

    public func streamTrigger() -> WebexStreamTrigger {
        WebexStreamTrigger(
            resource: resource,
            event: event,
            resourceID: resourceID,
            roomID: roomID,
            actorID: actorID
        )
    }
}
