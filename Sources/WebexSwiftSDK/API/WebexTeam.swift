import Foundation

public struct WebexTeam: Equatable, Decodable, Sendable {
    public let id: String
    public let name: String?
    public let creatorID: String?
    public let created: Date?

    public init(
        id: String,
        name: String? = nil,
        creatorID: String? = nil,
        created: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.creatorID = creatorID
        self.created = created
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case creatorID = "creatorId"
        case created
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.creatorID = try container.decodeIfPresent(String.self, forKey: .creatorID)
        self.created = try WebexDateDecoding.decodeIfPresent(from: container, forKey: .created)
    }
}
