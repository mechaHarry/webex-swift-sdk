import AuthenticationServices
import Foundation

internal typealias OAuthWebAuthenticationSessionCompletion = (URL?, Error?) -> Void
internal typealias OAuthWebAuthenticationSessionFactory = @MainActor (
    _ authorizationURL: URL,
    _ callbackURLScheme: String,
    _ completion: @escaping OAuthWebAuthenticationSessionCompletion
) -> OAuthWebAuthenticationSession

@MainActor
internal protocol OAuthWebAuthenticationSession: AnyObject {
    var presentationContextProvider: ASWebAuthenticationPresentationContextProviding? { get set }
    var prefersEphemeralWebBrowserSession: Bool { get set }

    func start() -> Bool
    func cancel()
}

public final class ASWebAuthenticationSessionAdapter: NSObject, OAuthBrowserSession, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    private let anchorProvider: @MainActor () -> ASPresentationAnchor
    private let sessionFactory: OAuthWebAuthenticationSessionFactory

    @MainActor
    private var currentSession: OAuthWebAuthenticationSession?

    @MainActor
    internal var hasActiveSessionForTesting: Bool {
        currentSession != nil
    }

    public init(anchorProvider: @escaping @MainActor () -> ASPresentationAnchor) {
        self.anchorProvider = anchorProvider
        self.sessionFactory = { authorizationURL, callbackURLScheme, completion in
            SystemOAuthWebAuthenticationSession(
                authorizationURL: authorizationURL,
                callbackURLScheme: callbackURLScheme,
                completion: completion
            )
        }
    }

    internal init(
        anchorProvider: @escaping @MainActor () -> ASPresentationAnchor,
        sessionFactory: @escaping OAuthWebAuthenticationSessionFactory
    ) {
        self.anchorProvider = anchorProvider
        self.sessionFactory = sessionFactory
    }

    public func authenticate(
        authorizationURL: URL,
        callbackURLScheme: String,
        prefersEphemeralWebBrowserSession: Bool
    ) async throws -> URL {
        let cancellation = await MainActor.run {
            OAuthBrowserSessionCancellation()
        }

        return try await withTaskCancellationHandler {
            try await authenticateOnMainActor(
                authorizationURL: authorizationURL,
                callbackURLScheme: callbackURLScheme,
                prefersEphemeralWebBrowserSession: prefersEphemeralWebBrowserSession,
                cancellation: cancellation
            )
        } onCancel: {
            Task { @MainActor in
                cancellation.cancel()
            }
        }
    }

    @MainActor
    private func authenticateOnMainActor(
        authorizationURL: URL,
        callbackURLScheme: String,
        prefersEphemeralWebBrowserSession: Bool,
        cancellation: OAuthBrowserSessionCancellation
    ) async throws -> URL {
        guard currentSession == nil else {
            throw WebexSDKError.network("Authorization browser session already in progress")
        }

        try Task.checkCancellation()

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            var didResume = false
            var activeSession: OAuthWebAuthenticationSession?

            @MainActor
            func complete(_ result: Result<URL, Error>) {
                guard !didResume else {
                    return
                }

                didResume = true
                cancellation.clear()

                let completedSession = activeSession
                if let completedSession, currentSession === completedSession {
                    currentSession = nil
                }
                activeSession = nil

                switch result {
                case .success(let url):
                    continuation.resume(returning: url)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            let session = sessionFactory(
                authorizationURL,
                callbackURLScheme,
                { callbackURL, error in
                    Task { @MainActor in
                        if let callbackURL {
                            complete(.success(callbackURL))
                            return
                        }

                        if let error = error as? ASWebAuthenticationSessionError,
                           error.code == .canceledLogin {
                            complete(.failure(WebexSDKError.userCancelledAuthorization))
                            return
                        }

                        complete(.failure(error ?? WebexSDKError.network("Authorization browser session completed without a callback URL")))
                    }
                }
            )

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
            activeSession = session
            currentSession = session
            cancellation.install {
                complete(.failure(CancellationError()))
                session.cancel()
            }

            guard !didResume else {
                return
            }

            guard session.start() else {
                complete(.failure(WebexSDKError.network("Authorization browser session failed to start")))
                return
            }
        }
    }

    @MainActor
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchorProvider()
    }
}

@MainActor
private final class SystemOAuthWebAuthenticationSession: OAuthWebAuthenticationSession {
    private let session: ASWebAuthenticationSession

    var presentationContextProvider: ASWebAuthenticationPresentationContextProviding? {
        get {
            session.presentationContextProvider
        }
        set {
            session.presentationContextProvider = newValue
        }
    }

    var prefersEphemeralWebBrowserSession: Bool {
        get {
            session.prefersEphemeralWebBrowserSession
        }
        set {
            session.prefersEphemeralWebBrowserSession = newValue
        }
    }

    init(
        authorizationURL: URL,
        callbackURLScheme: String,
        completion: @escaping OAuthWebAuthenticationSessionCompletion
    ) {
        self.session = ASWebAuthenticationSession(
            url: authorizationURL,
            callbackURLScheme: callbackURLScheme,
            completionHandler: completion
        )
    }

    func start() -> Bool {
        session.start()
    }

    func cancel() {
        session.cancel()
    }
}

@MainActor
private final class OAuthBrowserSessionCancellation: @unchecked Sendable {
    private var handler: (() -> Void)?
    private var isCancelled = false

    func install(_ handler: @escaping () -> Void) {
        guard !isCancelled else {
            handler()
            return
        }

        self.handler = handler
    }

    func cancel() {
        isCancelled = true
        let handler = handler
        self.handler = nil
        handler?()
    }

    func clear() {
        handler = nil
    }
}
