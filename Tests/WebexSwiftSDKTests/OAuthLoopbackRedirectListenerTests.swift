import XCTest
@testable import WebexSwiftSDK

final class OAuthLoopbackRedirectListenerTests: XCTestCase {
    func testDefaultRedirectURIUses127LoopbackAndPort8282() {
        XCTAssertEqual(
            WebexOAuthLoopbackRedirectListener.defaultRedirectURI,
            URL(string: "http://127.0.0.1:8282/oauth/callback")!
        )
    }

    func testReceivesValidLoopbackCallbackAndReturnsBrowserSuccess() async throws {
        let port = UInt16.random(in: 20_000...60_000)
        let redirectURI = URL(string: "http://127.0.0.1:\(port)/oauth/callback")!
        let listener = WebexOAuthLoopbackRedirectListener(redirectURI: redirectURI)

        async let callback = listener.receiveCallback()
        let response = try await sendLoopbackRequest(
            URL(string: "http://127.0.0.1:\(port)/oauth/callback?code=code-1&state=state-1")!
        )
        let receivedCallback = try await callback

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(
            receivedCallback.absoluteString,
            "http://127.0.0.1:\(port)/oauth/callback?code=code-1&state=state-1"
        )
    }

    func testWrongPathDoesNotCompleteListenerBeforeValidCallback() async throws {
        let port = UInt16.random(in: 20_000...60_000)
        let redirectURI = URL(string: "http://127.0.0.1:\(port)/oauth/callback")!
        let listener = WebexOAuthLoopbackRedirectListener(redirectURI: redirectURI)

        async let callback = listener.receiveCallback()
        let wrongPathResponse = try await sendLoopbackRequest(
            URL(string: "http://127.0.0.1:\(port)/wrong?code=wrong&state=state-1")!
        )
        let validResponse = try await sendLoopbackRequest(
            URL(string: "http://127.0.0.1:\(port)/oauth/callback?code=code-1&state=state-1")!
        )
        let receivedCallback = try await callback

        XCTAssertEqual(wrongPathResponse.statusCode, 404)
        XCTAssertEqual(validResponse.statusCode, 200)
        XCTAssertEqual(
            receivedCallback.absoluteString,
            "http://127.0.0.1:\(port)/oauth/callback?code=code-1&state=state-1"
        )
    }

    func testRejectsNon127RedirectURI() async throws {
        let listener = WebexOAuthLoopbackRedirectListener(
            redirectURI: URL(string: "http://localhost:8282/oauth/callback")!
        )

        do {
            _ = try await listener.receiveCallback()
            XCTFail("Expected invalid redirect URI")
        } catch let error as WebexOAuthLoopbackRedirectListenerError {
            XCTAssertEqual(
                error,
                .invalidRedirectURI("Loopback OAuth redirect URI must use host 127.0.0.1")
            )
        }
    }

    func testCancellationClosesListenerWithoutCallback() async throws {
        let port = UInt16.random(in: 20_000...60_000)
        let redirectURI = URL(string: "http://127.0.0.1:\(port)/oauth/callback")!
        let listener = WebexOAuthLoopbackRedirectListener(redirectURI: redirectURI)

        let task = Task {
            try await listener.receiveCallback()
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    private func sendLoopbackRequest(_ url: URL) async throws -> HTTPURLResponse {
        var lastError: Error?
        for _ in 0..<20 {
            do {
                let (_, response) = try await URLSession.shared.data(from: url)
                return try XCTUnwrap(response as? HTTPURLResponse)
            } catch {
                lastError = error
                try await Task.sleep(nanoseconds: 25_000_000)
            }
        }

        throw try XCTUnwrap(lastError)
    }
}
