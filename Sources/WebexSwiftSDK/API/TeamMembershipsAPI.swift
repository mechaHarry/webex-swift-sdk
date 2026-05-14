import Foundation

public struct ListTeamMembershipsParams: Equatable, Sendable {
    public let teamID: String?
    public let personID: String?
    public let personEmail: String?
    public let max: Int?

    public init(
        teamID: String? = nil,
        personID: String? = nil,
        personEmail: String? = nil,
        max: Int? = nil
    ) {
        self.teamID = teamID
        self.personID = personID
        self.personEmail = personEmail
        self.max = max
    }

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let teamID {
            items.append(URLQueryItem(name: "teamId", value: teamID))
        }
        if let personID {
            items.append(URLQueryItem(name: "personId", value: personID))
        }
        if let personEmail {
            items.append(URLQueryItem(name: "personEmail", value: personEmail))
        }
        if let max {
            items.append(URLQueryItem(name: "max", value: String(max)))
        }
        return items
    }
}

public struct WebexTeamMembershipListPage: Equatable, Sendable {
    public let items: [WebexTeamMembership]
    public let nextPage: WebexPageLink?

    public init(items: [WebexTeamMembership], nextPage: WebexPageLink?) {
        self.items = items
        self.nextPage = nextPage
    }
}

public struct CreateTeamMembershipRequest: Encodable, Equatable, Sendable {
    public let teamID: String
    public let personID: String?
    public let personEmail: String?
    public let isModerator: Bool?

    public init(teamID: String, personID: String, isModerator: Bool? = nil) {
        self.teamID = teamID
        self.personID = personID
        self.personEmail = nil
        self.isModerator = isModerator
    }

    public init(teamID: String, personEmail: String, isModerator: Bool? = nil) {
        self.teamID = teamID
        self.personID = nil
        self.personEmail = personEmail
        self.isModerator = isModerator
    }

    private enum CodingKeys: String, CodingKey {
        case teamID = "teamId"
        case personID = "personId"
        case personEmail
        case isModerator
    }
}

public struct UpdateTeamMembershipRequest: Encodable, Equatable, Sendable {
    public let isModerator: Bool

    public init(isModerator: Bool) {
        self.isModerator = isModerator
    }
}

public struct TeamMembershipsAPI: Sendable {
    private let transport: WebexTransport

    public init(transport: WebexTransport) {
        self.transport = transport
    }

    public func list(
        params: ListTeamMembershipsParams = ListTeamMembershipsParams()
    ) async throws -> WebexTeamMembershipListPage {
        try await list(request: WebexRequest(
            path: "/v1/team/memberships",
            queryItems: params.queryItems
        ))
    }

    public func list(nextPage: WebexPageLink) async throws -> WebexTeamMembershipListPage {
        try await list(request: nextPage.request)
    }

    public func create(_ request: CreateTeamMembershipRequest) async throws -> WebexTeamMembership {
        let body = try JSONEncoder().encode(request)
        let data = try await transport.send(WebexRequest(
            method: "POST",
            path: "/v1/team/memberships",
            body: body
        ))
        return try JSONDecoder().decode(WebexTeamMembership.self, from: data)
    }

    public func get(teamMembershipID: String) async throws -> WebexTeamMembership {
        let data = try await transport.send(WebexRequest(
            path: try teamMembershipPath(teamMembershipID),
            isPathPercentEncoded: true
        ))
        return try JSONDecoder().decode(WebexTeamMembership.self, from: data)
    }

    public func update(
        teamMembershipID: String,
        _ request: UpdateTeamMembershipRequest
    ) async throws -> WebexTeamMembership {
        let body = try JSONEncoder().encode(request)
        let data = try await transport.send(WebexRequest(
            method: "PUT",
            path: try teamMembershipPath(teamMembershipID),
            isPathPercentEncoded: true,
            body: body
        ))
        return try JSONDecoder().decode(WebexTeamMembership.self, from: data)
    }

    public func delete(teamMembershipID: String) async throws {
        _ = try await transport.send(WebexRequest(
            method: "DELETE",
            path: try teamMembershipPath(teamMembershipID),
            isPathPercentEncoded: true
        ))
    }

    private func list(request: WebexRequest) async throws -> WebexTeamMembershipListPage {
        let response = try await transport.sendResponse(request)
        let envelope = try JSONDecoder().decode(WebexTeamMembershipListEnvelope.self, from: response.data)
        return WebexTeamMembershipListPage(
            items: envelope.items,
            nextPage: WebexPageLink.next(from: response.response)
        )
    }

    private func teamMembershipPath(_ teamMembershipID: String) throws -> String {
        let trimmedID = teamMembershipID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            throw WebexSDKError.network("Invalid Webex team membership ID")
        }

        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%")

        guard let encodedID = trimmedID.addingPercentEncoding(withAllowedCharacters: allowed),
              !encodedID.isEmpty else {
            throw WebexSDKError.network("Invalid Webex team membership ID")
        }

        return "/v1/team/memberships/\(encodedID)"
    }
}

private struct WebexTeamMembershipListEnvelope: Decodable {
    let items: [WebexTeamMembership]
}
