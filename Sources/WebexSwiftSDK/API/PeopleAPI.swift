import Foundation

public struct WebexPerson: Equatable, Decodable, Sendable {
    public let id: String
    public let emails: [String]
    public let displayName: String?
    public let orgID: String?
    public let created: String?

    public init(
        id: String,
        emails: [String],
        displayName: String?,
        orgID: String?,
        created: String?
    ) {
        self.id = id
        self.emails = emails
        self.displayName = displayName
        self.orgID = orgID
        self.created = created
    }

    public func metadata(verifiedAt: Date) -> WebexAccountMetadata {
        WebexAccountMetadata(
            webexUserID: id,
            email: emails.first,
            displayName: displayName,
            organizationID: orgID,
            lastVerifiedAt: verifiedAt
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case emails
        case displayName
        case orgID = "orgId"
        case created
    }
}

public struct PeopleAPI: Sendable {
    private let transport: WebexTransport

    public init(transport: WebexTransport) {
        self.transport = transport
    }

    public func me() async throws -> WebexPerson {
        let data = try await transport.send(WebexRequest(path: "/v1/people/me"))
        return try JSONDecoder().decode(WebexPerson.self, from: data)
    }
}
