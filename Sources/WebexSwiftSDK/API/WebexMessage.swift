import Foundation

public struct WebexMessageAttachment: Equatable, Codable, Sendable {
    public let contentType: String?
    public let content: [String: WebexJSONValue]?

    public init(
        contentType: String? = nil,
        content: [String: WebexJSONValue]? = nil
    ) {
        self.contentType = contentType
        self.content = content
    }
}

public struct WebexMessage: Equatable, Decodable, Sendable {
    public let id: String
    public let parentID: String?
    public let roomID: String?
    public let roomType: WebexSpaceType?
    public let toPersonID: String?
    public let toPersonEmail: String?
    public let text: String?
    public let markdown: String?
    public let html: String?
    public let files: [String]?
    public let personID: String?
    public let personEmail: String?
    public let mentionedPeople: [String]?
    public let mentionedGroups: [String]?
    public let attachments: [WebexMessageAttachment]?
    public let created: Date?
    public let updated: Date?
    public let isVoiceClip: Bool?
    public let additionalFields: [String: WebexJSONValue]

    public init(
        id: String,
        parentID: String? = nil,
        roomID: String? = nil,
        roomType: WebexSpaceType? = nil,
        toPersonID: String? = nil,
        toPersonEmail: String? = nil,
        text: String? = nil,
        markdown: String? = nil,
        html: String? = nil,
        files: [String]? = nil,
        personID: String? = nil,
        personEmail: String? = nil,
        mentionedPeople: [String]? = nil,
        mentionedGroups: [String]? = nil,
        attachments: [WebexMessageAttachment]? = nil,
        created: Date? = nil,
        updated: Date? = nil,
        isVoiceClip: Bool? = nil,
        additionalFields: [String: WebexJSONValue] = [:]
    ) {
        self.id = id
        self.parentID = parentID
        self.roomID = roomID
        self.roomType = roomType
        self.toPersonID = toPersonID
        self.toPersonEmail = toPersonEmail
        self.text = text
        self.markdown = markdown
        self.html = html
        self.files = files
        self.personID = personID
        self.personEmail = personEmail
        self.mentionedPeople = mentionedPeople
        self.mentionedGroups = mentionedGroups
        self.attachments = attachments
        self.created = created
        self.updated = updated
        self.isVoiceClip = isVoiceClip
        self.additionalFields = additionalFields
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case parentID = "parentId"
        case roomID = "roomId"
        case roomType
        case toPersonID = "toPersonId"
        case toPersonEmail
        case text
        case markdown
        case html
        case files
        case personID = "personId"
        case personEmail
        case mentionedPeople
        case mentionedGroups
        case attachments
        case created
        case updated
        case isVoiceClip
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.parentID = try container.decodeIfPresent(String.self, forKey: .parentID)
        self.roomID = try container.decodeIfPresent(String.self, forKey: .roomID)
        self.roomType = try container.decodeIfPresent(WebexSpaceType.self, forKey: .roomType)
        self.toPersonID = try container.decodeIfPresent(String.self, forKey: .toPersonID)
        self.toPersonEmail = try container.decodeIfPresent(String.self, forKey: .toPersonEmail)
        self.text = try container.decodeIfPresent(String.self, forKey: .text)
        self.markdown = try container.decodeIfPresent(String.self, forKey: .markdown)
        self.html = try container.decodeIfPresent(String.self, forKey: .html)
        self.files = try container.decodeIfPresent([String].self, forKey: .files)
        self.personID = try container.decodeIfPresent(String.self, forKey: .personID)
        self.personEmail = try container.decodeIfPresent(String.self, forKey: .personEmail)
        self.mentionedPeople = try container.decodeIfPresent([String].self, forKey: .mentionedPeople)
        self.mentionedGroups = try container.decodeIfPresent([String].self, forKey: .mentionedGroups)
        self.attachments = try container.decodeIfPresent([WebexMessageAttachment].self, forKey: .attachments)
        self.created = try WebexDateDecoding.decodeIfPresent(from: container, forKey: .created)
        self.updated = try WebexDateDecoding.decodeIfPresent(from: container, forKey: .updated)
        self.isVoiceClip = try container.decodeIfPresent(Bool.self, forKey: .isVoiceClip)
        self.additionalFields = try WebexAdditionalFields.decode(
            from: decoder,
            excluding: Set(CodingKeys.allCases.map(\.rawValue))
        )
    }
}
