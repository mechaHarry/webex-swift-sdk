import Foundation

public struct ListWebhooksParams: Equatable, Sendable {
    public let max: Int?
    public let ownedBy: WebexWebhookOwnedBy?

    public init(
        max: Int? = nil,
        ownedBy: WebexWebhookOwnedBy? = nil
    ) {
        self.max = max
        self.ownedBy = ownedBy
    }

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let max {
            items.append(URLQueryItem(name: "max", value: String(max)))
        }
        if let ownedBy {
            items.append(URLQueryItem(name: "ownedBy", value: ownedBy.rawValue))
        }
        return items
    }
}

public struct WebexWebhookListPage: Equatable, Sendable {
    public let items: [WebexWebhook]
    public let nextPage: WebexPageLink?

    public init(items: [WebexWebhook], nextPage: WebexPageLink?) {
        self.items = items
        self.nextPage = nextPage
    }
}

public struct CreateWebhookRequest: Encodable, Equatable, Sendable {
    public let name: String
    public let targetURL: String
    public let resource: WebexWebhookResource
    public let event: WebexWebhookEvent
    public let filter: String?
    public let secret: String?
    public let ownedBy: WebexWebhookOwnedBy?

    public init(
        name: String,
        targetURL: String,
        resource: WebexWebhookResource,
        event: WebexWebhookEvent,
        filter: String? = nil,
        secret: String? = nil,
        ownedBy: WebexWebhookOwnedBy? = nil
    ) {
        self.name = name
        self.targetURL = targetURL
        self.resource = resource
        self.event = event
        self.filter = filter
        self.secret = secret
        self.ownedBy = ownedBy
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case targetURL = "targetUrl"
        case resource
        case event
        case filter
        case secret
        case ownedBy
    }
}

public struct UpdateWebhookRequest: Encodable, Equatable, Sendable {
    public let name: String
    public let targetURL: String
    public let secret: String?
    public let ownedBy: WebexWebhookOwnedBy?
    public let status: WebexWebhookStatus?

    public init(
        name: String,
        targetURL: String,
        secret: String? = nil,
        ownedBy: WebexWebhookOwnedBy? = nil,
        status: WebexWebhookStatus? = nil
    ) {
        self.name = name
        self.targetURL = targetURL
        self.secret = secret
        self.ownedBy = ownedBy
        self.status = status
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case targetURL = "targetUrl"
        case secret
        case ownedBy
        case status
    }
}

public struct WebhooksAPI: Sendable {
    private let transport: WebexTransport

    public init(transport: WebexTransport) {
        self.transport = transport
    }

    public func list(params: ListWebhooksParams = ListWebhooksParams()) async throws -> WebexWebhookListPage {
        try await list(request: WebexRequest(
            path: "/v1/webhooks",
            queryItems: params.queryItems
        ))
    }

    public func list(nextPage: WebexPageLink) async throws -> WebexWebhookListPage {
        try await list(request: nextPage.request)
    }

    public func create(_ request: CreateWebhookRequest) async throws -> WebexWebhook {
        let body = try JSONEncoder().encode(request)
        let data = try await transport.send(WebexRequest(
            method: "POST",
            path: "/v1/webhooks",
            body: body
        ))
        return try JSONDecoder().decode(WebexWebhook.self, from: data)
    }

    public func get(webhookID: String) async throws -> WebexWebhook {
        let data = try await transport.send(WebexRequest(
            path: try webhookPath(webhookID),
            isPathPercentEncoded: true
        ))
        return try JSONDecoder().decode(WebexWebhook.self, from: data)
    }

    public func update(webhookID: String, _ request: UpdateWebhookRequest) async throws -> WebexWebhook {
        let body = try JSONEncoder().encode(request)
        let data = try await transport.send(WebexRequest(
            method: "PUT",
            path: try webhookPath(webhookID),
            isPathPercentEncoded: true,
            body: body
        ))
        return try JSONDecoder().decode(WebexWebhook.self, from: data)
    }

    public func delete(webhookID: String) async throws {
        _ = try await transport.send(WebexRequest(
            method: "DELETE",
            path: try webhookPath(webhookID),
            isPathPercentEncoded: true
        ))
    }

    private func list(request: WebexRequest) async throws -> WebexWebhookListPage {
        let response = try await transport.sendResponse(request)
        let envelope = try JSONDecoder().decode(WebexWebhookListEnvelope.self, from: response.data)
        return WebexWebhookListPage(
            items: envelope.items,
            nextPage: WebexPageLink.next(from: response.response)
        )
    }

    private func webhookPath(_ webhookID: String) throws -> String {
        let trimmedID = webhookID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            throw WebexSDKError.network("Invalid Webex webhook ID")
        }

        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%")

        guard let encodedID = trimmedID.addingPercentEncoding(withAllowedCharacters: allowed),
              !encodedID.isEmpty else {
            throw WebexSDKError.network("Invalid Webex webhook ID")
        }

        return "/v1/webhooks/\(encodedID)"
    }
}

private struct WebexWebhookListEnvelope: Decodable {
    let items: [WebexWebhook]
}
