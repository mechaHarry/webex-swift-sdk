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

    public func listAll(
        query: ListSpacesQuery = ListSpacesQuery(),
        maxPages: Int = 1_000
    ) async throws -> [WebexSpace] {
        guard maxPages > 0 else {
            throw WebexSDKError.network("Spaces pagination page cap must be greater than zero")
        }

        var page = try await list(query: query)
        var pagesFetched = 1
        var seenNextPageURLs: Set<URL> = []
        var spaces = page.items

        while let nextPage = page.nextPage {
            guard pagesFetched < maxPages else {
                throw WebexSDKError.network("Spaces pagination page cap exceeded")
            }
            guard seenNextPageURLs.insert(nextPage.url).inserted else {
                throw WebexSDKError.network("Repeated Spaces pagination link")
            }

            try Task.checkCancellation()
            page = try await list(request: nextPage.request)
            pagesFetched += 1
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
