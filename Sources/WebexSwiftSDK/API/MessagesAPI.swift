import Foundation

public struct ListMessagesParams: Equatable, Sendable {
    public let roomID: String
    public let parentID: String?
    public let mentionedPeople: String?
    public let before: String?
    public let beforeMessage: String?
    public let max: Int?

    public init(
        roomID: String,
        parentID: String? = nil,
        mentionedPeople: String? = nil,
        before: String? = nil,
        beforeMessage: String? = nil,
        max: Int? = nil
    ) {
        self.roomID = roomID
        self.parentID = parentID
        self.mentionedPeople = mentionedPeople
        self.before = before
        self.beforeMessage = beforeMessage
        self.max = max
    }

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "roomId", value: roomID)
        ]
        if let parentID {
            items.append(URLQueryItem(name: "parentId", value: parentID))
        }
        if let mentionedPeople {
            items.append(URLQueryItem(name: "mentionedPeople", value: mentionedPeople))
        }
        if let before {
            items.append(URLQueryItem(name: "before", value: before))
        }
        if let beforeMessage {
            items.append(URLQueryItem(name: "beforeMessage", value: beforeMessage))
        }
        if let max {
            items.append(URLQueryItem(name: "max", value: String(max)))
        }
        return items
    }
}

public struct WebexMessageListPage: Equatable, Sendable {
    public let items: [WebexMessage]
    public let nextPage: WebexPageLink?

    public init(items: [WebexMessage], nextPage: WebexPageLink?) {
        self.items = items
        self.nextPage = nextPage
    }
}

public struct CreateMessageRequest: Encodable, Equatable, Sendable {
    public let roomID: String?
    public let parentID: String?
    public let toPersonID: String?
    public let toPersonEmail: String?
    public let text: String?
    public let markdown: String?
    public let files: [String]?
    public let attachments: [WebexMessageAttachment]?

    public init(
        roomID: String? = nil,
        parentID: String? = nil,
        toPersonID: String? = nil,
        toPersonEmail: String? = nil,
        text: String? = nil,
        markdown: String? = nil,
        files: [String]? = nil,
        attachments: [WebexMessageAttachment]? = nil
    ) {
        self.roomID = roomID
        self.parentID = parentID
        self.toPersonID = toPersonID
        self.toPersonEmail = toPersonEmail
        self.text = text
        self.markdown = markdown
        self.files = files
        self.attachments = attachments
    }

    private enum CodingKeys: String, CodingKey {
        case roomID = "roomId"
        case parentID = "parentId"
        case toPersonID = "toPersonId"
        case toPersonEmail
        case text
        case markdown
        case files
        case attachments
    }
}

public struct EditMessageRequest: Encodable, Equatable, Sendable {
    public let roomID: String
    public let text: String?
    public let markdown: String?

    public init(
        roomID: String,
        text: String? = nil,
        markdown: String? = nil
    ) {
        self.roomID = roomID
        self.text = text
        self.markdown = markdown
    }

    private enum CodingKeys: String, CodingKey {
        case roomID = "roomId"
        case text
        case markdown
    }
}

public struct MessagesAPI: Sendable {
    private let transport: WebexTransport

    public init(transport: WebexTransport) {
        self.transport = transport
    }

    public func list(params: ListMessagesParams) async throws -> WebexMessageListPage {
        try await list(request: WebexRequest(
            path: "/v1/messages",
            queryItems: params.queryItems
        ))
    }

    public func list(nextPage: WebexPageLink) async throws -> WebexMessageListPage {
        try await list(request: nextPage.request)
    }

    public func create(_ request: CreateMessageRequest) async throws -> WebexMessage {
        let body = try JSONEncoder().encode(request)
        let data = try await transport.send(WebexRequest(
            method: "POST",
            path: "/v1/messages",
            body: body
        ))
        return try JSONDecoder().decode(WebexMessage.self, from: data)
    }

    public func get(messageID: String) async throws -> WebexMessage {
        let data = try await transport.send(WebexRequest(
            path: try messagePath(messageID),
            isPathPercentEncoded: true
        ))
        return try JSONDecoder().decode(WebexMessage.self, from: data)
    }

    public func edit(messageID: String, _ request: EditMessageRequest) async throws -> WebexMessage {
        let body = try JSONEncoder().encode(request)
        let data = try await transport.send(WebexRequest(
            method: "PUT",
            path: try messagePath(messageID),
            isPathPercentEncoded: true,
            body: body
        ))
        return try JSONDecoder().decode(WebexMessage.self, from: data)
    }

    public func delete(messageID: String) async throws {
        _ = try await transport.send(WebexRequest(
            method: "DELETE",
            path: try messagePath(messageID),
            isPathPercentEncoded: true
        ))
    }

    private func list(request: WebexRequest) async throws -> WebexMessageListPage {
        let response = try await transport.sendResponse(request)
        let envelope = try JSONDecoder().decode(WebexMessageListEnvelope.self, from: response.data)
        return WebexMessageListPage(
            items: envelope.items,
            nextPage: WebexPageLink.next(from: response.response)
        )
    }

    private func messagePath(_ messageID: String) throws -> String {
        let trimmedID = messageID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            throw WebexSDKError.network("Invalid Webex message ID")
        }

        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%")

        guard let encodedID = trimmedID.addingPercentEncoding(withAllowedCharacters: allowed),
              !encodedID.isEmpty else {
            throw WebexSDKError.network("Invalid Webex message ID")
        }

        return "/v1/messages/\(encodedID)"
    }
}

private struct WebexMessageListEnvelope: Decodable {
    let items: [WebexMessage]
}
