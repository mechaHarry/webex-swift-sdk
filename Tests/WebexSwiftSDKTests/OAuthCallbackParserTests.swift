import AuthenticationServices
import XCTest
@testable import WebexSwiftSDK

final class OAuthCallbackParserTests: XCTestCase {
    func testParsesAuthorizationCodeWhenStateMatches() throws {
        let callback = URL(string: "myapp://oauth/webex?code=abc123&state=state123")!

        let result = try OAuthCallbackParser.parse(callbackURL: callback, expectedState: "state123")

        XCTAssertEqual(result.code, "abc123")
        XCTAssertEqual(result.state, "state123")
    }

    func testThrowsWhenStateDoesNotMatch() {
        let callback = URL(string: "myapp://oauth/webex?code=abc123&state=wrong")!

        XCTAssertThrowsError(try OAuthCallbackParser.parse(callbackURL: callback, expectedState: "expected")) { error in
            XCTAssertEqual(error as? WebexSDKError, .authorizationStateMismatch(expected: "expected", actual: "wrong"))
        }
    }

    func testThrowsWhenCodeIsMissing() {
        let callback = URL(string: "myapp://oauth/webex?state=state123")!

        XCTAssertThrowsError(try OAuthCallbackParser.parse(callbackURL: callback, expectedState: "state123"))
    }

    func testThrowsWhenCodeIsEmpty() {
        let callback = URL(string: "myapp://oauth/webex?code=&state=state123")!

        XCTAssertThrowsError(try OAuthCallbackParser.parse(callbackURL: callback, expectedState: "state123"))
    }

    func testErrorCallbackThrowsWithoutLeakingCallbackDetails() {
        let callback = URL(string: "myapp://oauth/webex?error=access_denied&state=state123")!

        XCTAssertThrowsError(try OAuthCallbackParser.parse(callbackURL: callback, expectedState: "state123")) { error in
            let description = String(describing: error)

            XCTAssertFalse(description.contains("access_denied"))
            XCTAssertFalse(description.contains(callback.absoluteString))
            XCTAssertTrue(description.contains("Invalid authorization callback"))
        }
    }

    func testMissingStateDoesNotExposeAuthorizationCode() {
        let callback = URL(string: "myapp://oauth/webex?code=auth-code")!

        XCTAssertThrowsError(try OAuthCallbackParser.parse(callbackURL: callback, expectedState: "state123")) { error in
            XCTAssertEqual(error as? WebexSDKError, .authorizationStateMismatch(expected: "state123", actual: nil))
            XCTAssertFalse(String(describing: error).contains("auth-code"))
        }
    }

    func testAuthorizationCodeDescriptionsRedactCode() {
        let authorizationCode = OAuthAuthorizationCode(code: "secret-code", state: "state123")

        let description = String(describing: authorizationCode)
        let debugDescription = String(reflecting: authorizationCode)

        XCTAssertFalse(description.contains("secret-code"))
        XCTAssertFalse(debugDescription.contains("secret-code"))
        XCTAssertTrue(description.contains("[redacted]"))
        XCTAssertTrue(debugDescription.contains("[redacted]"))
        XCTAssertTrue(description.contains("state123"))
        XCTAssertTrue(debugDescription.contains("state123"))
    }
}

@MainActor
final class ASWebAuthenticationSessionAdapterTests: XCTestCase {
    func testRejectsOverlappingAuthenticationAndKeepsFirstSessionActive() async throws {
        let factory = FakeOAuthWebAuthenticationSessionFactory()
        let adapter = makeAdapter(factory: factory)
        let callbackURL = URL(string: "myapp://oauth/webex?code=first&state=state")!

        let firstTask = Task {
            try await adapter.authenticate(
                authorizationURL: URL(string: "https://webexapis.com/v1/authorize")!,
                callbackURLScheme: "myapp",
                prefersEphemeralWebBrowserSession: true
            )
        }

        await waitForStartedSessionCount(1, in: factory)

        await XCTAssertThrowsErrorAsync(
            try await adapter.authenticate(
                authorizationURL: URL(string: "https://webexapis.com/v1/authorize")!,
                callbackURLScheme: "myapp",
                prefersEphemeralWebBrowserSession: false
            )
        ) { error in
            XCTAssertEqual(error as? WebexSDKError, .network("Authorization browser session already in progress"))
        }
        XCTAssertEqual(factory.sessions.count, 1)

        factory.sessions[0].complete(callbackURL: callbackURL)

        let result = try await firstTask.value
        XCTAssertEqual(result, callbackURL)
    }

    func testCancellingAuthenticationCancelsSessionAndClearsActiveState() async throws {
        let factory = FakeOAuthWebAuthenticationSessionFactory()
        let adapter = makeAdapter(factory: factory)
        let callbackURL = URL(string: "myapp://oauth/webex?code=second&state=state")!

        let task = Task {
            try await adapter.authenticate(
                authorizationURL: URL(string: "https://webexapis.com/v1/authorize")!,
                callbackURLScheme: "myapp",
                prefersEphemeralWebBrowserSession: true
            )
        }

        await waitForStartedSessionCount(1, in: factory)
        task.cancel()

        await XCTAssertThrowsErrorAsync(try await task.value) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(factory.sessions[0].cancelCallCount, 1)
        XCTAssertFalse(adapter.hasActiveSessionForTesting)

        let secondTask = Task {
            try await adapter.authenticate(
                authorizationURL: URL(string: "https://webexapis.com/v1/authorize")!,
                callbackURLScheme: "myapp",
                prefersEphemeralWebBrowserSession: false
            )
        }

        await waitForStartedSessionCount(2, in: factory)
        factory.sessions[1].complete(callbackURL: callbackURL)

        let result = try await secondTask.value
        XCTAssertEqual(result, callbackURL)
    }

    func testStaleCompletionDoesNotClearNewerActiveSession() async throws {
        let factory = FakeOAuthWebAuthenticationSessionFactory()
        let adapter = makeAdapter(factory: factory)
        let secondCallbackURL = URL(string: "myapp://oauth/webex?code=second&state=state")!

        let firstTask = Task {
            try await adapter.authenticate(
                authorizationURL: URL(string: "https://webexapis.com/v1/authorize")!,
                callbackURLScheme: "myapp",
                prefersEphemeralWebBrowserSession: true
            )
        }

        await waitForStartedSessionCount(1, in: factory)
        firstTask.cancel()
        await XCTAssertThrowsErrorAsync(try await firstTask.value) { error in
            XCTAssertTrue(error is CancellationError)
        }

        let secondTask = Task {
            try await adapter.authenticate(
                authorizationURL: URL(string: "https://webexapis.com/v1/authorize")!,
                callbackURLScheme: "myapp",
                prefersEphemeralWebBrowserSession: false
            )
        }

        await waitForStartedSessionCount(2, in: factory)
        factory.sessions[0].complete(callbackURL: URL(string: "myapp://oauth/webex?code=stale&state=state")!)
        await Task.yield()

        XCTAssertTrue(adapter.hasActiveSessionForTesting)

        factory.sessions[1].complete(callbackURL: secondCallbackURL)

        let result = try await secondTask.value
        XCTAssertEqual(result, secondCallbackURL)
    }

    func testNormalCompletionReleasesSessionCapture() async throws {
        let factory = FakeOAuthWebAuthenticationSessionFactory()
        let adapter = makeAdapter(factory: factory)
        let callbackURL = URL(string: "myapp://oauth/webex?code=first&state=state")!

        let task = Task {
            try await adapter.authenticate(
                authorizationURL: URL(string: "https://webexapis.com/v1/authorize")!,
                callbackURLScheme: "myapp",
                prefersEphemeralWebBrowserSession: true
            )
        }

        await waitForStartedSessionCount(1, in: factory)
        let releasedSession = WeakReference(factory.sessions[0])

        factory.sessions[0].complete(callbackURL: callbackURL)

        let result = try await task.value
        XCTAssertEqual(result, callbackURL)
        factory.removeAllSessions()
        await Task.yield()

        XCTAssertNil(releasedSession.value)
    }

    func testCancellationReleasesSessionCapture() async {
        let factory = FakeOAuthWebAuthenticationSessionFactory()
        let adapter = makeAdapter(factory: factory)

        let task = Task {
            try await adapter.authenticate(
                authorizationURL: URL(string: "https://webexapis.com/v1/authorize")!,
                callbackURLScheme: "myapp",
                prefersEphemeralWebBrowserSession: true
            )
        }

        await waitForStartedSessionCount(1, in: factory)
        let releasedSession = WeakReference(factory.sessions[0])
        task.cancel()

        await XCTAssertThrowsErrorAsync(try await task.value) { error in
            XCTAssertTrue(error is CancellationError)
        }
        factory.removeAllSessions()
        await Task.yield()

        XCTAssertNil(releasedSession.value)
    }

    func testStartFailureReleasesSessionCapture() async {
        let factory = FakeOAuthWebAuthenticationSessionFactory(startResults: [false])
        let adapter = makeAdapter(factory: factory)

        await XCTAssertThrowsErrorAsync(
            try await adapter.authenticate(
                authorizationURL: URL(string: "https://webexapis.com/v1/authorize")!,
                callbackURLScheme: "myapp",
                prefersEphemeralWebBrowserSession: true
            )
        ) { error in
            XCTAssertEqual(error as? WebexSDKError, .network("Authorization browser session failed to start"))
        }

        let releasedSession = WeakReference(factory.sessions[0])
        factory.removeAllSessions()
        await Task.yield()

        XCTAssertNil(releasedSession.value)
    }

    private func makeAdapter(factory: FakeOAuthWebAuthenticationSessionFactory) -> ASWebAuthenticationSessionAdapter {
        ASWebAuthenticationSessionAdapter(
            anchorProvider: { ASPresentationAnchor() },
            sessionFactory: factory.makeSession
        )
    }

    private func waitForStartedSessionCount(
        _ expectedCount: Int,
        in factory: FakeOAuthWebAuthenticationSessionFactory,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<100 {
            if factory.sessions.count >= expectedCount,
               factory.sessions.prefix(expectedCount).allSatisfy({ $0.startCallCount > 0 }) {
                return
            }

            await Task.yield()
        }

        XCTFail("Timed out waiting for \(expectedCount) started session(s)", file: file, line: line)
    }
}

@MainActor
private final class FakeOAuthWebAuthenticationSessionFactory {
    private(set) var sessions: [FakeOAuthWebAuthenticationSession] = []
    private var startResults: [Bool]

    init(startResults: [Bool] = []) {
        self.startResults = startResults
    }

    func makeSession(
        authorizationURL: URL,
        callbackURLScheme: String,
        completion: @escaping (URL?, Error?) -> Void
    ) -> OAuthWebAuthenticationSession {
        let startResult = startResults.isEmpty ? true : startResults.removeFirst()
        let session = FakeOAuthWebAuthenticationSession(startResult: startResult, completion: completion)
        sessions.append(session)
        return session
    }

    func removeAllSessions() {
        sessions.removeAll()
    }
}

@MainActor
private final class FakeOAuthWebAuthenticationSession: OAuthWebAuthenticationSession {
    var presentationContextProvider: ASWebAuthenticationPresentationContextProviding?
    var prefersEphemeralWebBrowserSession = false
    private(set) var startCallCount = 0
    private(set) var cancelCallCount = 0

    private let startResult: Bool
    private let completion: (URL?, Error?) -> Void

    init(startResult: Bool = true, completion: @escaping (URL?, Error?) -> Void) {
        self.startResult = startResult
        self.completion = completion
    }

    func start() -> Bool {
        startCallCount += 1
        return startResult
    }

    func cancel() {
        cancelCallCount += 1
    }

    func complete(callbackURL: URL) {
        completion(callbackURL, nil)
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}

@MainActor
private final class WeakReference<T: AnyObject> {
    weak var value: T?

    init(_ value: T) {
        self.value = value
    }
}
