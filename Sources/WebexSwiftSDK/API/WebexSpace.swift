import Foundation

public struct WebexPartialResourceError: Equatable, Decodable, Sendable {
    public let code: String
    public let reason: String

    public init(code: String, reason: String) {
        self.code = code
        self.reason = reason
    }
}

public enum WebexSpaceType: Equatable, Sendable {
    case direct
    case group
    case unknown(String)
}

extension WebexSpaceType: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        switch value {
        case "direct":
            self = .direct
        case "group":
            self = .group
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
        case .direct:
            return "direct"
        case .group:
            return "group"
        case .unknown(let value):
            return value
        }
    }
}

public struct WebexSpace: Equatable, Decodable, Sendable {
    public let id: String
    public let title: String?
    public let type: WebexSpaceType?
    public let isLocked: Bool?
    public let teamID: String?
    public let lastActivity: Date?
    public let creatorID: String?
    public let created: Date?
    public let ownerID: String?
    public let description: String?
    public let isPublic: Bool?
    public let isReadOnly: Bool?
    public let isAnnouncementOnly: Bool?
    public let classificationID: String?
    public let madePublic: Date?
    public let errors: [String: WebexPartialResourceError]?

    public init(
        id: String,
        title: String? = nil,
        type: WebexSpaceType? = nil,
        isLocked: Bool? = nil,
        teamID: String? = nil,
        lastActivity: Date? = nil,
        creatorID: String? = nil,
        created: Date? = nil,
        ownerID: String? = nil,
        description: String? = nil,
        isPublic: Bool? = nil,
        isReadOnly: Bool? = nil,
        isAnnouncementOnly: Bool? = nil,
        classificationID: String? = nil,
        madePublic: Date? = nil,
        errors: [String: WebexPartialResourceError]? = nil
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.isLocked = isLocked
        self.teamID = teamID
        self.lastActivity = lastActivity
        self.creatorID = creatorID
        self.created = created
        self.ownerID = ownerID
        self.description = description
        self.isPublic = isPublic
        self.isReadOnly = isReadOnly
        self.isAnnouncementOnly = isAnnouncementOnly
        self.classificationID = classificationID
        self.madePublic = madePublic
        self.errors = errors
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case type
        case isLocked
        case teamID = "teamId"
        case lastActivity
        case creatorID = "creatorId"
        case created
        case ownerID = "ownerId"
        case description
        case isPublic
        case isReadOnly
        case isAnnouncementOnly
        case classificationID = "classificationId"
        case madePublic
        case errors
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.type = try container.decodeIfPresent(WebexSpaceType.self, forKey: .type)
        self.isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked)
        self.teamID = try container.decodeIfPresent(String.self, forKey: .teamID)
        self.lastActivity = try WebexDateDecoding.decodeIfPresent(from: container, forKey: .lastActivity)
        self.creatorID = try container.decodeIfPresent(String.self, forKey: .creatorID)
        self.created = try WebexDateDecoding.decodeIfPresent(from: container, forKey: .created)
        self.ownerID = try container.decodeIfPresent(String.self, forKey: .ownerID)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.isPublic = try container.decodeIfPresent(Bool.self, forKey: .isPublic)
        self.isReadOnly = try container.decodeIfPresent(Bool.self, forKey: .isReadOnly)
        self.isAnnouncementOnly = try container.decodeIfPresent(Bool.self, forKey: .isAnnouncementOnly)
        self.classificationID = try container.decodeIfPresent(String.self, forKey: .classificationID)
        self.madePublic = try WebexDateDecoding.decodeIfPresent(from: container, forKey: .madePublic)
        self.errors = try container.decodeIfPresent([String: WebexPartialResourceError].self, forKey: .errors)
    }
}

public typealias WebexRoom = WebexSpace
