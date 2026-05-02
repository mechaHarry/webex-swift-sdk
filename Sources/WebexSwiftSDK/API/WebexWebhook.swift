import CryptoKit
import Foundation

public enum WebexWebhookResource: Equatable, Sendable {
    case all
    case attachmentActions
    case dataSources
    case memberships
    case messages
    case rooms
    case meetings
    case recordings
    case convergedRecordings
    case meetingParticipants
    case meetingTranscripts
    case telephonyCalls
    case telephonyConference
    case telephonyMWI
    case ucCounters
    case serviceApp
    case adminBatchJobs
    case unknown(String)
}

extension WebexWebhookResource: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        switch value {
        case "all":
            self = .all
        case "attachmentActions":
            self = .attachmentActions
        case "dataSources":
            self = .dataSources
        case "memberships":
            self = .memberships
        case "messages":
            self = .messages
        case "rooms":
            self = .rooms
        case "meetings":
            self = .meetings
        case "recordings":
            self = .recordings
        case "convergedRecordings":
            self = .convergedRecordings
        case "meetingParticipants":
            self = .meetingParticipants
        case "meetingTranscripts":
            self = .meetingTranscripts
        case "telephony_calls":
            self = .telephonyCalls
        case "telephony_conference":
            self = .telephonyConference
        case "telephony_mwi":
            self = .telephonyMWI
        case "uc_counters":
            self = .ucCounters
        case "serviceApp":
            self = .serviceApp
        case "adminBatchJobs":
            self = .adminBatchJobs
        default:
            self = .unknown(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var rawValue: String {
        switch self {
        case .all:
            return "all"
        case .attachmentActions:
            return "attachmentActions"
        case .dataSources:
            return "dataSources"
        case .memberships:
            return "memberships"
        case .messages:
            return "messages"
        case .rooms:
            return "rooms"
        case .meetings:
            return "meetings"
        case .recordings:
            return "recordings"
        case .convergedRecordings:
            return "convergedRecordings"
        case .meetingParticipants:
            return "meetingParticipants"
        case .meetingTranscripts:
            return "meetingTranscripts"
        case .telephonyCalls:
            return "telephony_calls"
        case .telephonyConference:
            return "telephony_conference"
        case .telephonyMWI:
            return "telephony_mwi"
        case .ucCounters:
            return "uc_counters"
        case .serviceApp:
            return "serviceApp"
        case .adminBatchJobs:
            return "adminBatchJobs"
        case .unknown(let value):
            return value
        }
    }
}

public enum WebexWebhookEvent: Equatable, Sendable {
    case all
    case created
    case updated
    case deleted
    case started
    case ended
    case joined
    case left
    case migrated
    case authorized
    case deauthorized
    case statusChanged
    case unknown(String)
}

extension WebexWebhookEvent: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        switch value {
        case "all":
            self = .all
        case "created":
            self = .created
        case "updated":
            self = .updated
        case "deleted":
            self = .deleted
        case "started":
            self = .started
        case "ended":
            self = .ended
        case "joined":
            self = .joined
        case "left":
            self = .left
        case "migrated":
            self = .migrated
        case "authorized":
            self = .authorized
        case "deauthorized":
            self = .deauthorized
        case "statusChanged":
            self = .statusChanged
        default:
            self = .unknown(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var rawValue: String {
        switch self {
        case .all:
            return "all"
        case .created:
            return "created"
        case .updated:
            return "updated"
        case .deleted:
            return "deleted"
        case .started:
            return "started"
        case .ended:
            return "ended"
        case .joined:
            return "joined"
        case .left:
            return "left"
        case .migrated:
            return "migrated"
        case .authorized:
            return "authorized"
        case .deauthorized:
            return "deauthorized"
        case .statusChanged:
            return "statusChanged"
        case .unknown(let value):
            return value
        }
    }
}

public enum WebexWebhookStatus: Equatable, Sendable {
    case active
    case inactive
    case unknown(String)
}

extension WebexWebhookStatus: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        switch value {
        case "active":
            self = .active
        case "inactive":
            self = .inactive
        default:
            self = .unknown(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var rawValue: String {
        switch self {
        case .active:
            return "active"
        case .inactive:
            return "inactive"
        case .unknown(let value):
            return value
        }
    }
}

public enum WebexWebhookOwnedBy: Equatable, Sendable {
    case creator
    case org
    case unknown(String)
}

extension WebexWebhookOwnedBy: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        switch value {
        case "creator":
            self = .creator
        case "org":
            self = .org
        default:
            self = .unknown(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var rawValue: String {
        switch self {
        case .creator:
            return "creator"
        case .org:
            return "org"
        case .unknown(let value):
            return value
        }
    }
}

public struct WebexWebhook: Equatable, Decodable, Sendable {
    public let id: String
    public let name: String?
    public let targetURL: String?
    public let resource: WebexWebhookResource?
    public let event: WebexWebhookEvent?
    public let filter: String?
    public let secret: String?
    public let status: WebexWebhookStatus?
    public let created: Date?
    public let ownedBy: WebexWebhookOwnedBy?

    public init(
        id: String,
        name: String? = nil,
        targetURL: String? = nil,
        resource: WebexWebhookResource? = nil,
        event: WebexWebhookEvent? = nil,
        filter: String? = nil,
        secret: String? = nil,
        status: WebexWebhookStatus? = nil,
        created: Date? = nil,
        ownedBy: WebexWebhookOwnedBy? = nil
    ) {
        self.id = id
        self.name = name
        self.targetURL = targetURL
        self.resource = resource
        self.event = event
        self.filter = filter
        self.secret = secret
        self.status = status
        self.created = created
        self.ownedBy = ownedBy
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case targetURL = "targetUrl"
        case resource
        case event
        case filter
        case secret
        case status
        case created
        case ownedBy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.targetURL = try container.decodeIfPresent(String.self, forKey: .targetURL)
        self.resource = try container.decodeIfPresent(WebexWebhookResource.self, forKey: .resource)
        self.event = try container.decodeIfPresent(WebexWebhookEvent.self, forKey: .event)
        self.filter = try container.decodeIfPresent(String.self, forKey: .filter)
        self.secret = try container.decodeIfPresent(String.self, forKey: .secret)
        self.status = try container.decodeIfPresent(WebexWebhookStatus.self, forKey: .status)
        self.created = try WebexDateDecoding.decodeIfPresent(from: container, forKey: .created)
        self.ownedBy = try container.decodeIfPresent(WebexWebhookOwnedBy.self, forKey: .ownedBy)
    }
}

public struct WebexWebhookNotification: Equatable, Decodable, Sendable {
    public let id: String
    public let name: String?
    public let resource: WebexWebhookResource
    public let event: WebexWebhookEvent
    public let filter: String?
    public let orgID: String?
    public let createdBy: String?
    public let appID: String?
    public let ownedBy: WebexWebhookOwnedBy?
    public let status: WebexWebhookStatus?
    public let actorID: String?
    public let data: [String: WebexJSONValue]?

    public init(
        id: String,
        name: String? = nil,
        resource: WebexWebhookResource,
        event: WebexWebhookEvent,
        filter: String? = nil,
        orgID: String? = nil,
        createdBy: String? = nil,
        appID: String? = nil,
        ownedBy: WebexWebhookOwnedBy? = nil,
        status: WebexWebhookStatus? = nil,
        actorID: String? = nil,
        data: [String: WebexJSONValue]? = nil
    ) {
        self.id = id
        self.name = name
        self.resource = resource
        self.event = event
        self.filter = filter
        self.orgID = orgID
        self.createdBy = createdBy
        self.appID = appID
        self.ownedBy = ownedBy
        self.status = status
        self.actorID = actorID
        self.data = data
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case resource
        case event
        case filter
        case orgID = "orgId"
        case createdBy
        case appID = "appId"
        case ownedBy
        case status
        case actorID = "actorId"
        case data
    }

    public func streamTrigger() -> WebexStreamTrigger {
        WebexStreamTrigger(
            resource: resource.rawValue,
            event: event.rawValue,
            resourceID: data?["id"]?.stringValue,
            roomID: data?["roomId"]?.stringValue,
            actorID: actorID
        )
    }
}

public enum WebexWebhookSignatureVerifier {
    public static func signature(in headers: [String: String]) -> String? {
        for (name, value) in headers where name.caseInsensitiveCompare("X-Spark-Signature") == .orderedSame {
            return value
        }

        return nil
    }

    public static func isValidRequest(
        payload: Data,
        headers: [String: String],
        secret: String
    ) -> Bool {
        guard let signature = signature(in: headers) else {
            return false
        }

        return isValidSignature(signature, payload: payload, secret: secret)
    }

    public static func isValidSignature(
        _ signature: String,
        payload: Data,
        secret: String
    ) -> Bool {
        let expected = hmacSHA1Hex(payload: payload, secret: secret)
        let received = normalizedSignature(signature)

        guard expected.utf8.count == received.utf8.count else {
            return false
        }

        var difference: UInt8 = 0
        for (expectedByte, receivedByte) in zip(expected.utf8, received.utf8) {
            difference |= expectedByte ^ receivedByte
        }

        return difference == 0
    }

    private static func hmacSHA1Hex(payload: Data, secret: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let digest = HMAC<Insecure.SHA1>.authenticationCode(for: payload, using: key)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func normalizedSignature(_ signature: String) -> String {
        let trimmed = signature.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("sha1=") {
            return String(trimmed.dropFirst("sha1=".count))
        }

        return trimmed
    }
}

private extension WebexJSONValue {
    var stringValue: String? {
        guard case .string(let value) = self else {
            return nil
        }

        return value
    }
}
