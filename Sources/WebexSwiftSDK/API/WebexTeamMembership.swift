import Foundation

public struct WebexTeamMembership: Equatable, Decodable, Sendable {
    public let id: String
    public let teamID: String?
    public let personID: String?
    public let personEmail: String?
    public let personDisplayName: String?
    public let personOrgID: String?
    public let isModerator: Bool?
    public let created: Date?
    public let additionalFields: [String: WebexJSONValue]

    public init(
        id: String,
        teamID: String? = nil,
        personID: String? = nil,
        personEmail: String? = nil,
        personDisplayName: String? = nil,
        personOrgID: String? = nil,
        isModerator: Bool? = nil,
        created: Date? = nil,
        additionalFields: [String: WebexJSONValue] = [:]
    ) {
        self.id = id
        self.teamID = teamID
        self.personID = personID
        self.personEmail = personEmail
        self.personDisplayName = personDisplayName
        self.personOrgID = personOrgID
        self.isModerator = isModerator
        self.created = created
        self.additionalFields = additionalFields
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case teamID = "teamId"
        case personID = "personId"
        case personEmail
        case personDisplayName
        case personOrgID = "personOrgId"
        case isModerator
        case created
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.teamID = try container.decodeIfPresent(String.self, forKey: .teamID)
        self.personID = try container.decodeIfPresent(String.self, forKey: .personID)
        self.personEmail = try container.decodeIfPresent(String.self, forKey: .personEmail)
        self.personDisplayName = try container.decodeIfPresent(String.self, forKey: .personDisplayName)
        self.personOrgID = try container.decodeIfPresent(String.self, forKey: .personOrgID)
        self.isModerator = try container.decodeIfPresent(Bool.self, forKey: .isModerator)
        self.created = try WebexDateDecoding.decodeIfPresent(from: container, forKey: .created)
        self.additionalFields = try WebexAdditionalFields.decode(
            from: decoder,
            excluding: Set(CodingKeys.allCases.map(\.rawValue))
        )
    }
}
