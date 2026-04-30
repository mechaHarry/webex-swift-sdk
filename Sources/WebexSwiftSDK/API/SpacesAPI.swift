import Foundation

public enum WebexSpaceSort: String, Equatable, Sendable {
    case id
    case lastActivity = "lastactivity"
    case created
}

public struct ListSpacesQuery: Equatable, Sendable {
    public let teamID: String?
    public let type: WebexSpaceType?
    public let sortBy: WebexSpaceSort?
    public let max: Int?

    public init(
        teamID: String? = nil,
        type: WebexSpaceType? = nil,
        sortBy: WebexSpaceSort? = nil,
        max: Int? = nil
    ) {
        self.teamID = teamID
        self.type = type
        self.sortBy = sortBy
        self.max = max
    }

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let teamID {
            items.append(URLQueryItem(name: "teamId", value: teamID))
        }
        if let type {
            items.append(URLQueryItem(name: "type", value: type.rawValue))
        }
        if let sortBy {
            items.append(URLQueryItem(name: "sortBy", value: sortBy.rawValue))
        }
        if let max {
            items.append(URLQueryItem(name: "max", value: String(max)))
        }
        return items
    }
}

public struct WebexSpaceListPage: Equatable, Sendable {
    public let items: [WebexSpace]
    public let nextPage: WebexPageLink?

    public init(items: [WebexSpace], nextPage: WebexPageLink?) {
        self.items = items
        self.nextPage = nextPage
    }
}

public struct SpacesAPI: Sendable {
    private let transport: WebexTransport

    public init(transport: WebexTransport) {
        self.transport = transport
    }

    public func list(query: ListSpacesQuery = ListSpacesQuery()) async throws -> WebexSpaceListPage {
        try await list(request: WebexRequest(
            path: "/v1/rooms",
            queryItems: query.queryItems
        ))
    }

    public func listAll(query: ListSpacesQuery = ListSpacesQuery()) async throws -> [WebexSpace] {
        var page = try await list(query: query)
        var spaces = page.items

        while let nextPage = page.nextPage {
            try Task.checkCancellation()
            page = try await list(request: nextPage.request)
            spaces.append(contentsOf: page.items)
        }

        return spaces
    }

    private func list(request: WebexRequest) async throws -> WebexSpaceListPage {
        let response = try await transport.sendResponse(request)
        let envelope = try JSONDecoder().decode(WebexSpaceListEnvelope.self, from: response.data)
        return WebexSpaceListPage(
            items: envelope.items,
            nextPage: WebexPageLink.next(from: response.response)
        )
    }
}

private struct WebexSpaceListEnvelope: Decodable {
    let items: [WebexSpace]
}

public typealias RoomsAPI = SpacesAPI
public typealias ListRoomsQuery = ListSpacesQuery
