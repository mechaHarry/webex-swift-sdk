import Foundation

public struct ListMembershipsQuery: Equatable, Sendable {
    public let roomID: String?
    public let personID: String?
    public let personEmail: String?
    public let max: Int?

    public init(
        roomID: String? = nil,
        personID: String? = nil,
        personEmail: String? = nil,
        max: Int? = nil
    ) {
        self.roomID = roomID
        self.personID = personID
        self.personEmail = personEmail
        self.max = max
    }

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let roomID {
            items.append(URLQueryItem(name: "roomId", value: roomID))
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

public struct WebexMembershipListPage: Equatable, Sendable {
    public let items: [WebexMembership]
    public let nextPage: WebexPageLink?

    public init(items: [WebexMembership], nextPage: WebexPageLink?) {
        self.items = items
        self.nextPage = nextPage
    }
}

public struct CreateMembershipRequest: Encodable, Equatable, Sendable {
    public let roomID: String
    public let personID: String?
    public let personEmail: String?
    public let isModerator: Bool?

    public init(roomID: String, personID: String, isModerator: Bool? = nil) {
        self.roomID = roomID
        self.personID = personID
        self.personEmail = nil
        self.isModerator = isModerator
    }

    public init(roomID: String, personEmail: String, isModerator: Bool? = nil) {
        self.roomID = roomID
        self.personID = nil
        self.personEmail = personEmail
        self.isModerator = isModerator
    }

    private enum CodingKeys: String, CodingKey {
        case roomID = "roomId"
        case personID = "personId"
        case personEmail
        case isModerator
    }
}

public struct UpdateMembershipRequest: Encodable, Equatable, Sendable {
    public let isModerator: Bool?
    public let isRoomHidden: Bool?

    public init(
        isModerator: Bool? = nil,
        isRoomHidden: Bool? = nil
    ) {
        self.isModerator = isModerator
        self.isRoomHidden = isRoomHidden
    }

    private enum CodingKeys: String, CodingKey {
        case isModerator
        case isRoomHidden
    }
}

public struct MembershipsAPI: Sendable {
    private let transport: WebexTransport

    public init(transport: WebexTransport) {
        self.transport = transport
    }

    public func list(query: ListMembershipsQuery = ListMembershipsQuery()) async throws -> WebexMembershipListPage {
        try await list(request: WebexRequest(
            path: "/v1/memberships",
            queryItems: query.queryItems
        ))
    }

    public func listAll(
        query: ListMembershipsQuery = ListMembershipsQuery(),
        maxPages: Int = 1_000
    ) async throws -> [WebexMembership] {
        guard maxPages > 0 else {
            throw WebexSDKError.network("Memberships pagination page cap must be greater than zero")
        }

        let firstRequest = WebexRequest(
            path: "/v1/memberships",
            queryItems: query.queryItems
        )
        var page = try await list(request: firstRequest)
        var pagesFetched = 1
        var seenPageRequests: Set<String> = [paginationRequestKey(firstRequest)]
        var memberships = page.items

        while let nextPage = page.nextPage {
            let nextRequest = nextPage.request

            guard pagesFetched < maxPages else {
                throw WebexSDKError.network("Memberships pagination page cap exceeded")
            }
            guard seenPageRequests.insert(paginationRequestKey(nextRequest)).inserted else {
                throw WebexSDKError.network("Repeated Memberships pagination link")
            }

            try Task.checkCancellation()
            page = try await list(request: nextRequest)
            pagesFetched += 1
            memberships.append(contentsOf: page.items)
        }

        return memberships
    }

    public func create(_ request: CreateMembershipRequest) async throws -> WebexMembership {
        let body = try JSONEncoder().encode(request)
        let data = try await transport.send(WebexRequest(
            method: "POST",
            path: "/v1/memberships",
            body: body
        ))
        return try JSONDecoder().decode(WebexMembership.self, from: data)
    }

    public func get(membershipID: String) async throws -> WebexMembership {
        let data = try await transport.send(WebexRequest(
            path: try membershipPath(membershipID),
            isPathPercentEncoded: true
        ))
        return try JSONDecoder().decode(WebexMembership.self, from: data)
    }

    public func update(
        membershipID: String,
        _ request: UpdateMembershipRequest
    ) async throws -> WebexMembership {
        let body = try JSONEncoder().encode(request)
        let data = try await transport.send(WebexRequest(
            method: "PUT",
            path: try membershipPath(membershipID),
            isPathPercentEncoded: true,
            body: body
        ))
        return try JSONDecoder().decode(WebexMembership.self, from: data)
    }

    public func delete(membershipID: String) async throws {
        _ = try await transport.send(WebexRequest(
            method: "DELETE",
            path: try membershipPath(membershipID),
            isPathPercentEncoded: true
        ))
    }

    private func list(request: WebexRequest) async throws -> WebexMembershipListPage {
        let response = try await transport.sendResponse(request)
        let envelope = try JSONDecoder().decode(WebexMembershipListEnvelope.self, from: response.data)
        return WebexMembershipListPage(
            items: envelope.items,
            nextPage: WebexPageLink.next(from: response.response)
        )
    }

    private func paginationRequestKey(_ request: WebexRequest) -> String {
        let normalizedPath = request.path.hasPrefix("/") ? request.path : "/\(request.path)"
        let queryKey = request.queryItems
            .map { item in
                "\(item.name.count):\(item.name)=\(item.value?.count ?? -1):\(item.value ?? "")"
            }
            .sorted()
            .joined(separator: "&")

        if queryKey.isEmpty {
            return "\(request.method.uppercased()) \(normalizedPath)"
        }

        return "\(request.method.uppercased()) \(normalizedPath)?\(queryKey)"
    }

    private func membershipPath(_ membershipID: String) throws -> String {
        let trimmedID = membershipID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            throw WebexSDKError.network("Invalid Webex membership ID")
        }

        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%")

        guard let encodedID = trimmedID.addingPercentEncoding(withAllowedCharacters: allowed),
              !encodedID.isEmpty else {
            throw WebexSDKError.network("Invalid Webex membership ID")
        }

        return "/v1/memberships/\(encodedID)"
    }
}

private struct WebexMembershipListEnvelope: Decodable {
    let items: [WebexMembership]
}
