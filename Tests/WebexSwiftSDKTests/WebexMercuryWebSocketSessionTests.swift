import Foundation
import XCTest
@testable import WebexSwiftSDK

final class WebexMercuryWebSocketSessionTests: XCTestCase {
    func testSendsAuthorizationFrameAfterConnect() async throws {
        let webSocket = FakeWebSocket()
        webSocket.enqueueReceive(.success(#"{"type":"event"}"#))
        webSocket.enqueueReceive(.failure(CancellationError()))
        let session = makeSession(webSocket: webSocket)

        try await session.connect()
        try await session.authorize()
        var iterator = session.frames().makeAsyncIterator()
        let frame = try await iterator.next()

        XCTAssertEqual(frame, #"{"type":"event"}"#)
        XCTAssertEqual(webSocket.connectCount(), 1)
        let sentTexts = webSocket.sentTexts()
        XCTAssertEqual(sentTexts.count, 1)
        let authorizationText = try XCTUnwrap(sentTexts.first)
        let authorizationObject = try decodeJSONObject(authorizationText)
        let data = try XCTUnwrap(authorizationObject["data"] as? [String: Any])
        XCTAssertFalse((authorizationObject["id"] as? String)?.isEmpty ?? true)
        XCTAssertEqual(authorizationObject["type"] as? String, "authorization")
        XCTAssertEqual(data["token"] as? String, "Bearer access-token")
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

    func testStreamTerminationCancelsSocket() async throws {
        let webSocket = FakeWebSocket()
        webSocket.enqueueReceive(.success(#"{"type":"event"}"#))
        let session = makeSession(webSocket: webSocket)

        let consumer = Task<String?, Error> {
            for try await frame in session.frames() {
                return frame
            }

            return nil
        }

        let frame = try await consumer.value

        XCTAssertEqual(frame, #"{"type":"event"}"#)
        try await eventually {
            webSocket.cancelCount() == 1
        }
    }

    func testStreamErrorDescriptionRedactsAccessTokenAndWebSocketURL() async throws {
        let webSocket = FakeWebSocket()
        webSocket.enqueueReceive(.failure(WebexSDKError.network("failed wss://mercury.example.com/socket?access_token=socket-secret secret access-token")))
        let session = makeSession(webSocket: webSocket)

        try await session.connect()
        try await session.authorize()
        do {
            for try await _ in session.frames() {}
            XCTFail("Expected stream failure")
        } catch {
            let description = String(describing: error)
            XCTAssertTrue(description.contains("[redacted]"))
            XCTAssertFalse(description.contains("access-token"))
            XCTAssertFalse(description.contains("socket-secret"))
            XCTAssertFalse(description.contains("mercury.example.com"))
            XCTAssertTrue(description.contains("wss://[redacted]"))
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

    private func decodeJSONObject(_ text: String) throws -> [String: Any] {
        let data = Data(text.utf8)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func eventually(
        timeout: Duration = .seconds(1),
        predicate: @escaping @Sendable () -> Bool
    ) async throws {
        let start = ContinuousClock.now

        while !predicate() {
            if start.duration(to: ContinuousClock.now) >= timeout {
                XCTFail("Condition was not satisfied before timeout")
                return
            }

            try await Task.sleep(for: .milliseconds(10))
        }
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

    func connectCount() -> Int {
        lock.withLock {
            connects
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
