import Foundation

public enum WebexSpaceSort: String, Equatable, Sendable {
    case id
    case lastActivity = "lastactivity"
    case created
}

public struct ListSpacesParams: Equatable, Sendable {
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

public struct CreateSpaceRequest: Encodable, Equatable, Sendable {
    public let title: String
    public let teamID: String?
    public let classificationID: String?
    public let isLocked: Bool?
    public let isPublic: Bool?
    public let description: String?
    public let isAnnouncementOnly: Bool?

    public init(
        title: String,
        teamID: String? = nil,
        classificationID: String? = nil,
        isLocked: Bool? = nil,
        isPublic: Bool? = nil,
        description: String? = nil,
        isAnnouncementOnly: Bool? = nil
    ) {
        self.title = title
        self.teamID = teamID
        self.classificationID = classificationID
        self.isLocked = isLocked
        self.isPublic = isPublic
        self.description = description
        self.isAnnouncementOnly = isAnnouncementOnly
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case teamID = "teamId"
        case classificationID = "classificationId"
        case isLocked
        case isPublic
        case description
        case isAnnouncementOnly
    }
}

public struct UpdateSpaceRequest: Encodable, Equatable, Sendable {
    public let title: String?
    public let teamID: String?
    public let classificationID: String?
    public let isLocked: Bool?
    public let isPublic: Bool?
    public let description: String?
    public let isAnnouncementOnly: Bool?

    public init(
        title: String? = nil,
        teamID: String? = nil,
        classificationID: String? = nil,
        description: String? = nil,
        isLocked: Bool? = nil,
        isPublic: Bool? = nil,
        isAnnouncementOnly: Bool? = nil
    ) {
        self.title = title
        self.teamID = teamID
        self.classificationID = classificationID
        self.isLocked = isLocked
        self.isPublic = isPublic
        self.description = description
        self.isAnnouncementOnly = isAnnouncementOnly
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case teamID = "teamId"
        case classificationID = "classificationId"
        case isLocked
        case isPublic
        case description
        case isAnnouncementOnly
    }
}

public struct SpacesAPI: Sendable {
    private let transport: WebexTransport

    public init(transport: WebexTransport) {
        self.transport = transport
    }

    public func list(params: ListSpacesParams = ListSpacesParams()) async throws -> WebexSpaceListPage {
        try await list(request: WebexRequest(
            path: "/v1/rooms",
            queryItems: params.queryItems
        ))
    }

    public func list(nextPage: WebexPageLink) async throws -> WebexSpaceListPage {
        try await list(request: nextPage.request)
    }

    public func create(_ request: CreateSpaceRequest) async throws -> WebexSpace {
        let body = try JSONEncoder().encode(request)
        let data = try await transport.send(WebexRequest(
            method: "POST",
            path: "/v1/rooms",
            body: body
        ))
        return try JSONDecoder().decode(WebexSpace.self, from: data)
    }

    public func get(spaceID: String) async throws -> WebexSpace {
        let data = try await transport.send(WebexRequest(
            path: try spacePath(spaceID),
            isPathPercentEncoded: true
        ))
        return try JSONDecoder().decode(WebexSpace.self, from: data)
    }

    public func update(spaceID: String, _ request: UpdateSpaceRequest) async throws -> WebexSpace {
        let body = try JSONEncoder().encode(request)
        let data = try await transport.send(WebexRequest(
            method: "PUT",
            path: try spacePath(spaceID),
            isPathPercentEncoded: true,
            body: body
        ))
        return try JSONDecoder().decode(WebexSpace.self, from: data)
    }

    public func delete(spaceID: String) async throws {
        _ = try await transport.send(WebexRequest(
            method: "DELETE",
            path: try spacePath(spaceID),
            isPathPercentEncoded: true
        ))
    }

    private func list(request: WebexRequest) async throws -> WebexSpaceListPage {
        let response = try await transport.sendResponse(request)
        let envelope = try JSONDecoder().decode(WebexSpaceListEnvelope.self, from: response.data)
        return WebexSpaceListPage(
            items: envelope.items,
            nextPage: WebexPageLink.next(from: response.response)
        )
    }

    private func spacePath(_ spaceID: String) throws -> String {
        let trimmedID = spaceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            throw WebexSDKError.network("Invalid Webex space ID")
        }

        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%")

        guard let encodedID = trimmedID.addingPercentEncoding(withAllowedCharacters: allowed),
              !encodedID.isEmpty else {
            throw WebexSDKError.network("Invalid Webex space ID")
        }

        return "/v1/rooms/\(encodedID)"
    }
}

private struct WebexSpaceListEnvelope: Decodable {
    let items: [WebexSpace]
}

public typealias RoomsAPI = SpacesAPI
public typealias ListRoomsParams = ListSpacesParams
public typealias CreateRoomRequest = CreateSpaceRequest
public typealias UpdateRoomRequest = UpdateSpaceRequest
