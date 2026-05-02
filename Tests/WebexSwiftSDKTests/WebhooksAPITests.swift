import XCTest
@testable import WebexSwiftSDK

final class WebhooksAPITests: XCTestCase {
    func testWebhookDecodesKnownFieldsAndPreservesUnknownEnums() throws {
        let json = Data("""
        {
          "id": "webhook-id",
          "name": "Messages",
          "targetUrl": "https://example.com/webex",
          "resource": "futureResource",
          "event": "futureEvent",
          "filter": "roomId=room-id",
          "secret": "secret-value",
          "status": "futureStatus",
          "created": "2026-05-01T18:01:02.123Z",
          "ownedBy": "futureOwner"
        }
        """.utf8)

        let webhook = try JSONDecoder().decode(WebexWebhook.self, from: json)

        XCTAssertEqual(webhook.id, "webhook-id")
        XCTAssertEqual(webhook.name, "Messages")
        XCTAssertEqual(webhook.targetURL, "https://example.com/webex")
        XCTAssertEqual(webhook.resource, .unknown("futureResource"))
        XCTAssertEqual(webhook.event, .unknown("futureEvent"))
        XCTAssertEqual(webhook.filter, "roomId=room-id")
        XCTAssertEqual(webhook.secret, "secret-value")
        XCTAssertEqual(webhook.status, .unknown("futureStatus"))
        XCTAssertEqual(iso8601(webhook.created), "2026-05-01T18:01:02Z")
        XCTAssertEqual(webhook.ownedBy, .unknown("futureOwner"))
    }

    func testWebhookNotificationDecodesMetadataAndBuildsStreamTrigger() throws {
        let json = Data("""
        {
          "id": "webhook-id",
          "name": "New message",
          "resource": "messages",
          "event": "created",
          "filter": "roomId=room-id",
          "orgId": "org-id",
          "createdBy": "creator-id",
          "appId": "app-id",
          "ownedBy": "creator",
          "status": "active",
          "actorId": "actor-id",
          "data": {
            "id": "message-id",
            "roomId": "room-id",
            "personId": "person-id",
            "created": "2026-05-01T18:01:02.123Z"
          }
        }
        """.utf8)

        let notification = try JSONDecoder().decode(WebexWebhookNotification.self, from: json)

        XCTAssertEqual(notification.id, "webhook-id")
        XCTAssertEqual(notification.resource, .messages)
        XCTAssertEqual(notification.event, .created)
        XCTAssertEqual(notification.orgID, "org-id")
        XCTAssertEqual(notification.createdBy, "creator-id")
        XCTAssertEqual(notification.appID, "app-id")
        XCTAssertEqual(notification.ownedBy, .creator)
        XCTAssertEqual(notification.status, .active)
        XCTAssertEqual(notification.actorID, "actor-id")
        XCTAssertEqual(notification.data?["id"], .string("message-id"))
        XCTAssertEqual(notification.data?["roomId"], .string("room-id"))

        let trigger = notification.streamTrigger()
        XCTAssertEqual(trigger.resource, "messages")
        XCTAssertEqual(trigger.event, "created")
        XCTAssertEqual(trigger.resourceID, "message-id")
        XCTAssertEqual(trigger.roomID, "room-id")
        XCTAssertEqual(trigger.actorID, "actor-id")
    }

    func testWebhookSignatureVerifierUsesCaseInsensitiveHeaderAndHMACSHA1() {
        let payload = Data("what do ya want for nothing?".utf8)
        let headers = [
            "x-spark-signature": "EFFCDF6AE5EB2FA2D27416D5F184DF9C259A7C79"
        ]

        XCTAssertEqual(
            WebexWebhookSignatureVerifier.signature(in: headers),
            "EFFCDF6AE5EB2FA2D27416D5F184DF9C259A7C79"
        )
        XCTAssertTrue(WebexWebhookSignatureVerifier.isValidSignature(
            "effcdf6ae5eb2fa2d27416d5f184df9c259a7c79",
            payload: payload,
            secret: "Jefe"
        ))
        XCTAssertTrue(WebexWebhookSignatureVerifier.isValidRequest(
            payload: payload,
            headers: headers,
            secret: "Jefe"
        ))
        XCTAssertFalse(WebexWebhookSignatureVerifier.isValidSignature(
            "0000000000000000000000000000000000000000",
            payload: payload,
            secret: "Jefe"
        ))
    }

    func testListWebhooksSendsParamsAndDecodesPage() async throws {
        let httpClient = MockWebhooksHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            headers: ["Link": #"<https://webexapis.com/v1/webhooks?cursor=next>; rel="next""#],
            body: #"{"items":[{"id":"webhook-1","name":"Messages","targetUrl":"https://example.com/hook","resource":"messages","event":"created","status":"active","ownedBy":"creator"}]}"#
        ))
        let api = makeAPI(httpClient: httpClient)

        let page = try await api.list(params: ListWebhooksParams(max: 25, ownedBy: .org))

        XCTAssertEqual(page.items.map(\.id), ["webhook-1"])
        XCTAssertEqual(page.items.first?.resource, .messages)
        XCTAssertEqual(page.nextPage?.url.absoluteString, "https://webexapis.com/v1/webhooks?cursor=next")
        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].url?.absoluteString, "https://webexapis.com/v1/webhooks?max=25&ownedBy=org")
        XCTAssertEqual(requests[0].httpMethod, "GET")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer webhooks-token")
    }

    func testListWebhooksNextPageUsesParsedWebexPageLink() async throws {
        let httpClient = MockWebhooksHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            headers: ["Link": #"<https://webexapis.com/v1/webhooks?cursor=second>; rel="next""#],
            body: #"{"items":[{"id":"webhook-1","name":"First","targetUrl":"https://example.com/first","resource":"messages","event":"created"}]}"#
        ))
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            body: #"{"items":[{"id":"webhook-2","name":"Second","targetUrl":"https://example.com/second","resource":"rooms","event":"updated"}]}"#
        ))
        let api = makeAPI(httpClient: httpClient)

        let firstPage = try await api.list(params: .init(max: 1))
        let nextPage = try XCTUnwrap(firstPage.nextPage)
        let secondPage = try await api.list(nextPage: nextPage)

        XCTAssertEqual(firstPage.items.map(\.id), ["webhook-1"])
        XCTAssertEqual(secondPage.items.map(\.id), ["webhook-2"])
        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, [
            "https://webexapis.com/v1/webhooks?max=1",
            "https://webexapis.com/v1/webhooks?cursor=second"
        ])
    }

    func testCreateWebhookPostsDocumentedFieldsAndDecodesWebhook() async throws {
        let httpClient = MockWebhooksHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            body: #"{"id":"created-webhook","name":"Messages","targetUrl":"https://example.com/hook","resource":"messages","event":"created","filter":"roomId=room-id","secret":"secret","status":"active","ownedBy":"org"}"#
        ))
        let api = makeAPI(httpClient: httpClient)

        let webhook = try await api.create(CreateWebhookRequest(
            name: "Messages",
            targetURL: "https://example.com/hook",
            resource: .messages,
            event: .created,
            filter: "roomId=room-id",
            secret: "secret",
            ownedBy: .org
        ))

        XCTAssertEqual(webhook.id, "created-webhook")
        let requests = await httpClient.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://webexapis.com/v1/webhooks")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["name", "targetUrl", "resource", "event", "filter", "secret", "ownedBy"])
        XCTAssertEqual(json["name"] as? String, "Messages")
        XCTAssertEqual(json["targetUrl"] as? String, "https://example.com/hook")
        XCTAssertEqual(json["resource"] as? String, "messages")
        XCTAssertEqual(json["event"] as? String, "created")
        XCTAssertEqual(json["filter"] as? String, "roomId=room-id")
        XCTAssertEqual(json["secret"] as? String, "secret")
        XCTAssertEqual(json["ownedBy"] as? String, "org")
    }

    func testGetUpdateAndDeleteWebhookPercentEncodePathSegment() async throws {
        let httpClient = MockWebhooksHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            body: #"{"id":"webhook/id+1","name":"Fetched","targetUrl":"https://example.com/fetched","resource":"rooms","event":"updated"}"#
        ))
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            body: #"{"id":"webhook/id+1","name":"Updated","targetUrl":"https://example.com/updated","resource":"rooms","event":"updated","status":"active","ownedBy":"org"}"#
        ))
        await httpClient.enqueue(response: httpResponse(statusCode: 204, body: ""))
        let api = makeAPI(httpClient: httpClient)

        let fetched = try await api.get(webhookID: "webhook/id+1")
        let updated = try await api.update(
            webhookID: "webhook/id+1",
            UpdateWebhookRequest(
                name: "Updated",
                targetURL: "https://example.com/updated",
                secret: "new-secret",
                ownedBy: .org,
                status: .active
            )
        )
        try await api.delete(webhookID: "webhook/id+1")

        XCTAssertEqual(fetched.name, "Fetched")
        XCTAssertEqual(updated.name, "Updated")
        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(requests.map { $0.httpMethod }, ["GET", "PUT", "DELETE"])
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, [
            "https://webexapis.com/v1/webhooks/webhook%2Fid+1",
            "https://webexapis.com/v1/webhooks/webhook%2Fid+1",
            "https://webexapis.com/v1/webhooks/webhook%2Fid+1"
        ])
        let updateBody = try XCTUnwrap(requests[1].httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: updateBody) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["name", "targetUrl", "secret", "ownedBy", "status"])
        XCTAssertEqual(json["name"] as? String, "Updated")
        XCTAssertEqual(json["targetUrl"] as? String, "https://example.com/updated")
        XCTAssertEqual(json["secret"] as? String, "new-secret")
        XCTAssertEqual(json["ownedBy"] as? String, "org")
        XCTAssertEqual(json["status"] as? String, "active")
    }

    func testInvalidWebhookIDValidationFailsBeforeHTTPWithoutLeakingRawID() async throws {
        let httpClient = MockWebhooksHTTPClient()
        let api = makeAPI(httpClient: httpClient)

        do {
            _ = try await api.get(webhookID: "   ")
            XCTFail("Expected invalid webhook ID to throw")
        } catch WebexSDKError.network(let message) {
            XCTAssertEqual(message, "Invalid Webex webhook ID")
            XCTAssertFalse(message.contains("   "))
        } catch {
            XCTFail("Expected WebexSDKError.network, got \(error)")
        }

        let requests = await httpClient.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testWebexClientExposesWebhooks() async throws {
        let accountID = WebexAccountID()
        let store = InMemoryWebexStore()
        let httpClient = MockWebhooksHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            body: #"{"items":[{"id":"webhook-from-client","name":"Client","targetUrl":"https://example.com/client","resource":"messages","event":"created"}]}"#
        ))
        let client = WebexClient(
            accountID: accountID,
            configuration: WebexIntegrationConfiguration(
                clientID: "client",
                clientSecret: "secret",
                redirectURI: URL(string: "myapp://oauth/webex")!,
                scopes: ["spark:messages_read"]
            ),
            tokenStore: store,
            httpClient: httpClient,
            initialAccessToken: AccessTokenState(
                value: "client-token",
                expiresAt: Date(timeIntervalSince1970: 1_000),
                tokenType: "Bearer"
            ),
            clock: { Date(timeIntervalSince1970: 0) }
        )

        let webhooks = try await client.webhooks.list()

        XCTAssertEqual(webhooks.items.map(\.id), ["webhook-from-client"])
    }

    private func iso8601(_ date: Date?) -> String? {
        guard let date else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

private func makeAPI(httpClient: HTTPClient) -> WebhooksAPI {
    WebhooksAPI(transport: WebexTransport(httpClient: httpClient) {
        AccessTokenState(
            value: "webhooks-token",
            expiresAt: Date(timeIntervalSince1970: 1_000),
            tokenType: "Bearer"
        )
    })
}

private func httpResponse(
    statusCode: Int,
    headers: [String: String] = [:],
    body: String
) -> HTTPResponse {
    HTTPResponse(
        data: Data(body.utf8),
        response: HTTPURLResponse(
            url: URL(string: "https://webexapis.com/v1/webhooks")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    )
}

private actor MockWebhooksHTTPClient: HTTPClient {
    private var responses: [HTTPResponse] = []
    private var requests: [URLRequest] = []

    func enqueue(response: HTTPResponse) {
        responses.append(response)
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else {
            throw WebexSDKError.network("Unexpected webhooks request")
        }

        return responses.removeFirst()
    }
}
