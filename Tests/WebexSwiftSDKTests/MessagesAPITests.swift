import XCTest
@testable import WebexSwiftSDK

final class MessagesAPITests: XCTestCase {
    func testMessageDecodesKnownFieldsAndAttachmentJSON() throws {
        let json = Data("""
        {
          "id": "message-id",
          "parentId": "parent-message-id",
          "roomId": "room-id",
          "roomType": "group",
          "toPersonId": "recipient-id",
          "toPersonEmail": "recipient@example.com",
          "text": "Plain text",
          "markdown": "**Plain text**",
          "html": "<p><strong>Plain text</strong></p>",
          "files": ["https://webexapis.com/v1/contents/file-id"],
          "personId": "author-id",
          "personEmail": "author@example.com",
          "mentionedPeople": ["person-1", "person-2"],
          "mentionedGroups": ["all"],
          "attachments": [
            {
              "contentType": "application/vnd.microsoft.card.adaptive",
              "content": {
                "type": "AdaptiveCard",
                "version": "1.2",
                "body": [
                  {
                    "type": "TextBlock",
                    "text": "Hello",
                    "wrap": true
                  }
                ],
                "actions": [
                  {
                    "type": "Action.OpenUrl",
                    "title": "Open",
                    "url": "https://example.com"
                  }
                ]
              }
            }
          ],
          "created": "2026-05-01T18:01:02.123Z",
          "updated": "2026-05-01T19:03:04Z",
          "isVoiceClip": true
        }
        """.utf8)

        let message = try JSONDecoder().decode(WebexMessage.self, from: json)

        XCTAssertEqual(message.id, "message-id")
        XCTAssertEqual(message.parentID, "parent-message-id")
        XCTAssertEqual(message.roomID, "room-id")
        XCTAssertEqual(message.roomType, .group)
        XCTAssertEqual(message.toPersonID, "recipient-id")
        XCTAssertEqual(message.toPersonEmail, "recipient@example.com")
        XCTAssertEqual(message.text, "Plain text")
        XCTAssertEqual(message.markdown, "**Plain text**")
        XCTAssertEqual(message.html, "<p><strong>Plain text</strong></p>")
        XCTAssertEqual(message.files, ["https://webexapis.com/v1/contents/file-id"])
        XCTAssertEqual(message.personID, "author-id")
        XCTAssertEqual(message.personEmail, "author@example.com")
        XCTAssertEqual(message.mentionedPeople, ["person-1", "person-2"])
        XCTAssertEqual(message.mentionedGroups, ["all"])
        XCTAssertEqual(message.isVoiceClip, true)
        XCTAssertEqual(iso8601(message.created), "2026-05-01T18:01:02Z")
        XCTAssertEqual(iso8601(message.updated), "2026-05-01T19:03:04Z")

        let attachment = try XCTUnwrap(message.attachments?.first)
        XCTAssertEqual(attachment.contentType, "application/vnd.microsoft.card.adaptive")
        let content = try XCTUnwrap(attachment.content)
        XCTAssertEqual(content["type"], .string("AdaptiveCard"))
        XCTAssertEqual(content["version"], .string("1.2"))
        guard case .array(let body)? = content["body"],
              case .object(let textBlock)? = body.first else {
            return XCTFail("Expected Adaptive Card body JSON")
        }
        XCTAssertEqual(textBlock["type"], .string("TextBlock"))
        XCTAssertEqual(textBlock["text"], .string("Hello"))
        XCTAssertEqual(textBlock["wrap"], .bool(true))
    }

    func testMessagePreservesUnknownRoomType() throws {
        let json = Data(#"{"id":"message-id","roomType":"future-room"}"#.utf8)

        let message = try JSONDecoder().decode(WebexMessage.self, from: json)

        XCTAssertEqual(message.roomType, .unknown("future-room"))
    }

    func testMessageRejectsInvalidTimestamp() throws {
        let json = Data(#"{"id":"message-id","created":"not-a-date"}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(WebexMessage.self, from: json)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted error, got \(error)")
            }

            XCTAssertEqual(context.debugDescription, "Invalid Webex timestamp")
        }
    }

    func testListMessagesSendsParamsAndDecodesPage() async throws {
        let httpClient = MockMessagesHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            headers: ["Link": #"<https://webexapis.com/v1/messages?cursor=next>; rel="next""#],
            body: #"{"items":[{"id":"message-1","roomId":"room-1","text":"Hello"}]}"#
        ))
        let api = makeAPI(httpClient: httpClient)

        let page = try await api.list(params: ListMessagesParams(
            roomID: "room-1",
            parentID: "parent-1",
            mentionedPeople: "me",
            before: "2026-05-01T00:00:00Z",
            beforeMessage: "message-before",
            max: 50
        ))

        XCTAssertEqual(page.items.map(\.id), ["message-1"])
        XCTAssertEqual(page.nextPage?.url.absoluteString, "https://webexapis.com/v1/messages?cursor=next")
        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(
            requests[0].url?.absoluteString,
            "https://webexapis.com/v1/messages?roomId=room-1&parentId=parent-1&mentionedPeople=me&before=2026-05-01T00:00:00Z&beforeMessage=message-before&max=50"
        )
        XCTAssertEqual(requests[0].httpMethod, "GET")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer messages-token")
    }

    func testListMessagesNextPageUsesParsedWebexPageLink() async throws {
        let httpClient = MockMessagesHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            headers: ["Link": #"<https://webexapis.com/v1/messages?cursor=second>; rel="next""#],
            body: #"{"items":[{"id":"message-1"}]}"#
        ))
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            body: #"{"items":[{"id":"message-2"}]}"#
        ))
        let api = makeAPI(httpClient: httpClient)

        let firstPage = try await api.list(params: .init(roomID: "room-1", max: 10))
        let nextPage = try XCTUnwrap(firstPage.nextPage)
        let secondPage = try await api.list(nextPage: nextPage)

        XCTAssertEqual(firstPage.items.map(\.id), ["message-1"])
        XCTAssertEqual(secondPage.items.map(\.id), ["message-2"])
        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, [
            "https://webexapis.com/v1/messages?roomId=room-1&max=10",
            "https://webexapis.com/v1/messages?cursor=second"
        ])
    }

    func testCreateMessagePostsJSONAndDecodesCreatedMessage() async throws {
        let httpClient = MockMessagesHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            body: #"{"id":"created-message","roomId":"room-id","text":"Plain"}"#
        ))
        let api = makeAPI(httpClient: httpClient)

        let message = try await api.create(CreateMessageRequest(
            roomID: "room-id",
            parentID: "parent-id",
            toPersonID: "person-id",
            toPersonEmail: "person@example.com",
            text: "Plain",
            markdown: "**Plain**",
            files: ["https://example.com/file.png"],
            attachments: [
                WebexMessageAttachment(
                    contentType: "application/vnd.microsoft.card.adaptive",
                    content: [
                        "type": .string("AdaptiveCard"),
                        "version": .string("1.2")
                    ]
                )
            ]
        ))

        XCTAssertEqual(message.id, "created-message")
        let requests = await httpClient.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://webexapis.com/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["roomId"] as? String, "room-id")
        XCTAssertEqual(json["parentId"] as? String, "parent-id")
        XCTAssertEqual(json["toPersonId"] as? String, "person-id")
        XCTAssertEqual(json["toPersonEmail"] as? String, "person@example.com")
        XCTAssertEqual(json["text"] as? String, "Plain")
        XCTAssertEqual(json["markdown"] as? String, "**Plain**")
        XCTAssertEqual(json["files"] as? [String], ["https://example.com/file.png"])
        let attachments = try XCTUnwrap(json["attachments"] as? [[String: Any]])
        XCTAssertEqual(attachments.first?["contentType"] as? String, "application/vnd.microsoft.card.adaptive")
        let content = try XCTUnwrap(attachments.first?["content"] as? [String: Any])
        XCTAssertEqual(content["type"] as? String, "AdaptiveCard")
        XCTAssertEqual(content["version"] as? String, "1.2")
    }

    func testGetMessagePercentEncodesPathSegment() async throws {
        let httpClient = MockMessagesHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            body: #"{"id":"message/id+1","text":"Encoded"}"#
        ))
        let api = makeAPI(httpClient: httpClient)

        let message = try await api.get(messageID: "message/id+1")

        XCTAssertEqual(message.id, "message/id+1")
        let requests = await httpClient.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://webexapis.com/v1/messages/message%2Fid+1")
    }

    func testEditMessagePutsDocumentedFields() async throws {
        let httpClient = MockMessagesHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            body: #"{"id":"message-id","roomId":"room-id","markdown":"**Updated**"}"#
        ))
        let api = makeAPI(httpClient: httpClient)

        let message = try await api.edit(
            messageID: "message-id",
            EditMessageRequest(roomID: "room-id", text: "Updated", markdown: "**Updated**")
        )

        XCTAssertEqual(message.markdown, "**Updated**")
        let requests = await httpClient.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.absoluteString, "https://webexapis.com/v1/messages/message-id")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["roomId", "text", "markdown"])
        XCTAssertEqual(json["roomId"] as? String, "room-id")
        XCTAssertEqual(json["text"] as? String, "Updated")
        XCTAssertEqual(json["markdown"] as? String, "**Updated**")
        XCTAssertNil(json["html"])
        XCTAssertNil(json["attachments"])
        XCTAssertNil(json["files"])
    }

    func testDeleteMessageSendsDeleteAndAcceptsNoContent() async throws {
        let httpClient = MockMessagesHTTPClient()
        await httpClient.enqueue(response: httpResponse(statusCode: 204, body: ""))
        let api = makeAPI(httpClient: httpClient)

        try await api.delete(messageID: "message-id")

        let requests = await httpClient.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.absoluteString, "https://webexapis.com/v1/messages/message-id")
    }

    func testInvalidMessageIDValidationFailsBeforeHTTPWithoutLeakingRawID() async throws {
        let httpClient = MockMessagesHTTPClient()
        let api = makeAPI(httpClient: httpClient)

        do {
            _ = try await api.get(messageID: "   ")
            XCTFail("Expected invalid message ID to throw")
        } catch WebexSDKError.network(let message) {
            XCTAssertEqual(message, "Invalid Webex message ID")
            XCTAssertFalse(message.contains("   "))
        } catch {
            XCTFail("Expected WebexSDKError.network, got \(error)")
        }

        let requests = await httpClient.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testWebexClientExposesMessages() async throws {
        let accountID = WebexAccountID()
        let store = InMemoryWebexStore()
        let httpClient = MockMessagesHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            body: #"{"items":[{"id":"message-from-client"}]}"#
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

        let messages = try await client.messages.list(params: .init(roomID: "room-id"))

        XCTAssertEqual(messages.items.map(\.id), ["message-from-client"])
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

private func makeAPI(httpClient: HTTPClient) -> MessagesAPI {
    MessagesAPI(transport: WebexTransport(httpClient: httpClient) {
        AccessTokenState(
            value: "messages-token",
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
            url: URL(string: "https://webexapis.com/v1/messages")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    )
}

private actor MockMessagesHTTPClient: HTTPClient {
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
            throw WebexSDKError.network("Unexpected messages request")
        }

        return responses.removeFirst()
    }
}
