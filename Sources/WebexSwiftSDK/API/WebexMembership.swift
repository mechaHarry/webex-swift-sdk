import Foundation

public struct WebexMembership: Equatable, Decodable, Sendable {
    public let id: String
    public let roomID: String?
    public let roomType: WebexSpaceType?
    public let personID: String?
    public let personEmail: String?
    public let personDisplayName: String?
    public let personOrgID: String?
    public let isModerator: Bool?
    public let isMonitor: Bool?
    public let isRoomHidden: Bool?
    public let created: Date?

    public init(
        id: String,
        roomID: String? = nil,
        roomType: WebexSpaceType? = nil,
        personID: String? = nil,
        personEmail: String? = nil,
        personDisplayName: String? = nil,
        personOrgID: String? = nil,
        isModerator: Bool? = nil,
        isMonitor: Bool? = nil,
        isRoomHidden: Bool? = nil,
        created: Date? = nil
    ) {
        self.id = id
        self.roomID = roomID
        self.roomType = roomType
        self.personID = personID
        self.personEmail = personEmail
        self.personDisplayName = personDisplayName
        self.personOrgID = personOrgID
        self.isModerator = isModerator
        self.isMonitor = isMonitor
        self.isRoomHidden = isRoomHidden
        self.created = created
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case roomID = "roomId"
        case roomType
        case personID = "personId"
        case personEmail
        case personDisplayName
        case personOrgID = "personOrgId"
        case isModerator
        case isMonitor
        case isRoomHidden
        case created
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.roomID = try container.decodeIfPresent(String.self, forKey: .roomID)
        self.roomType = try container.decodeIfPresent(WebexSpaceType.self, forKey: .roomType)
        self.personID = try container.decodeIfPresent(String.self, forKey: .personID)
        self.personEmail = try container.decodeIfPresent(String.self, forKey: .personEmail)
        self.personDisplayName = try container.decodeIfPresent(String.self, forKey: .personDisplayName)
        self.personOrgID = try container.decodeIfPresent(String.self, forKey: .personOrgID)
        self.isModerator = try container.decodeIfPresent(Bool.self, forKey: .isModerator)
        self.isMonitor = try container.decodeIfPresent(Bool.self, forKey: .isMonitor)
        self.isRoomHidden = try container.decodeIfPresent(Bool.self, forKey: .isRoomHidden)
        self.created = try WebexDateDecoding.decodeIfPresent(from: container, forKey: .created)
    }
}
