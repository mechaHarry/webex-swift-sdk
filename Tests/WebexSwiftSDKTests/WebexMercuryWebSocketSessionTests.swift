import Foundation
import XCTest
@testable import WebexSwiftSDK

final class WebexMercuryWebSocketSessionTests: XCTestCase {
    func testSendsAuthorizationFrameAfterConnect() async throws {
        let webSocket = FakeWebSocket()
        webSocket.enqueueReceive(.success(#"{"type":"event"}"#))
        webSocket.enqueueReceive(.failure(CancellationError()))
        let session = makeSession(webSocket: webSocket)

        var iterator = session.frames().makeAsyncIterator()
        let frame = try await iterator.next()

        XCTAssertEqual(frame, #"{"type":"event"}"#)
        let sentTexts = webSocket.sentTexts()
        XCTAssertEqual(sentTexts.count, 1)
        let authorizationText = try XCTUnwrap(sentTexts.first)
        XCTAssertTrue(authorizationText.contains(#""type":"authorization""#))
        XCTAssertTrue(authorizationText.contains(#""token":"Bearer access-token""#))
    }

    func testAckFrameUsesMessageID() async throws {
        let webSocket = FakeWebSocket()
        let session = makeSession(webSocket: webSocket)

        try await session.ack(messageID: "message-id")

        XCTAssertEqual(webSocket.sentTexts(), [#"{"messageId":"message-id","type":"ack"}"#])
    }

    func testCancelClosesSocket() {
        let webSocket = FakeWebSocket()
        let session = makeSession(webSocket: webSocket)

        session.cancel()

        XCTAssertEqual(webSocket.cancelCount(), 1)
    }

    func testStreamErrorDescriptionRedactsAccessToken() async throws {
        let webSocket = FakeWebSocket()
        webSocket.enqueueReceive(.failure(WebexSDKError.network("secret access-token")))
        let session = makeSession(webSocket: webSocket)

        do {
            for try await _ in session.frames() {}
            XCTFail("Expected stream failure")
        } catch {
            let description = String(describing: error)
            XCTAssertTrue(description.contains("[redacted]"))
            XCTAssertFalse(description.contains("access-token"))
        }
    }

    private func makeSession(webSocket: FakeWebSocket) -> WebexMercuryWebSocketSession {
        WebexMercuryWebSocketSession(
            webSocket: webSocket,
            accessTokenProvider: {
                AccessTokenState(
                    value: "access-token",
                    expiresAt: Date(timeIntervalSince1970: 1_000),
                    tokenType: "Bearer"
                )
            }
        )
    }
}

private final class FakeWebSocket: WebexRealtimeWebSocket, @unchecked Sendable {
    private let lock = NSLock()
    private var receiveResults: [Result<String, Error>] = []
    private var sent: [String] = []
    private var cancels = 0
    private var connects = 0

    func enqueueReceive(_ result: Result<String, Error>) {
        lock.withLock {
            receiveResults.append(result)
        }
    }

    func sentTexts() -> [String] {
        lock.withLock {
            sent
        }
    }

    func cancelCount() -> Int {
        lock.withLock {
            cancels
        }
    }

    func connect() async throws {
        lock.withLock {
            connects += 1
        }
    }

    func send(text: String) async throws {
        lock.withLock {
            sent.append(text)
        }
    }

    func receiveText() async throws -> String {
        try lock.withLock {
            guard !receiveResults.isEmpty else {
                throw CancellationError()
            }

            return try receiveResults.removeFirst().get()
        }
    }

    func cancel() {
        lock.withLock {
            cancels += 1
        }
    }
}
