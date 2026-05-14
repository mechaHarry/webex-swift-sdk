import Foundation

public struct ListTeamsParams: Equatable, Sendable {
    public let max: Int?

    public init(max: Int? = nil) {
        self.max = max
    }

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let max {
            items.append(URLQueryItem(name: "max", value: String(max)))
        }
        return items
    }
}

public struct WebexTeamListPage: Equatable, Sendable {
    public let items: [WebexTeam]
    public let nextPage: WebexPageLink?

    public init(items: [WebexTeam], nextPage: WebexPageLink?) {
        self.items = items
        self.nextPage = nextPage
    }
}

public struct CreateTeamRequest: Encodable, Equatable, Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

public struct UpdateTeamRequest: Encodable, Equatable, Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

public struct TeamsAPI: Sendable {
    private let transport: WebexTransport

    public init(transport: WebexTransport) {
        self.transport = transport
    }

    public func list(params: ListTeamsParams = ListTeamsParams()) async throws -> WebexTeamListPage {
        try await list(request: WebexRequest(
            path: "/v1/teams",
            queryItems: params.queryItems
        ))
    }

    public func list(nextPage: WebexPageLink) async throws -> WebexTeamListPage {
        try await list(request: nextPage.request)
    }

    public func create(_ request: CreateTeamRequest) async throws -> WebexTeam {
        let body = try JSONEncoder().encode(request)
        let data = try await transport.send(WebexRequest(
            method: "POST",
            path: "/v1/teams",
            body: body
        ))
        return try JSONDecoder().decode(WebexTeam.self, from: data)
    }

    public func get(teamID: String) async throws -> WebexTeam {
        let data = try await transport.send(WebexRequest(
            path: try teamPath(teamID),
            isPathPercentEncoded: true
        ))
        return try JSONDecoder().decode(WebexTeam.self, from: data)
    }

    public func update(teamID: String, _ request: UpdateTeamRequest) async throws -> WebexTeam {
        let body = try JSONEncoder().encode(request)
        let data = try await transport.send(WebexRequest(
            method: "PUT",
            path: try teamPath(teamID),
            isPathPercentEncoded: true,
            body: body
        ))
        return try JSONDecoder().decode(WebexTeam.self, from: data)
    }

    public func delete(teamID: String) async throws {
        _ = try await transport.send(WebexRequest(
            method: "DELETE",
            path: try teamPath(teamID),
            isPathPercentEncoded: true
        ))
    }

    private func list(request: WebexRequest) async throws -> WebexTeamListPage {
        let response = try await transport.sendResponse(request)
        let envelope = try JSONDecoder().decode(WebexTeamListEnvelope.self, from: response.data)
        return WebexTeamListPage(
            items: envelope.items,
            nextPage: WebexPageLink.next(from: response.response)
        )
    }

    private func teamPath(_ teamID: String) throws -> String {
        let trimmedID = teamID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            throw WebexSDKError.network("Invalid Webex team ID")
        }

        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%")

        guard let encodedID = trimmedID.addingPercentEncoding(withAllowedCharacters: allowed),
              !encodedID.isEmpty else {
            throw WebexSDKError.network("Invalid Webex team ID")
        }

        return "/v1/teams/\(encodedID)"
    }
}

private struct WebexTeamListEnvelope: Decodable {
    let items: [WebexTeam]
}
