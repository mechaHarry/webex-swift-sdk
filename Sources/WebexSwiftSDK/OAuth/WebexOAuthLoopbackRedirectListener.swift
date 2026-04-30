import Foundation
import Network

public enum WebexOAuthLoopbackRedirectListenerError: Error, Equatable, Sendable {
    case invalidRedirectURI(String)
    case listenerFailed(String)
    case invalidHTTPRequest
}

extension WebexOAuthLoopbackRedirectListenerError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidRedirectURI(let reason):
            return "Invalid loopback OAuth redirect URI: \(reason)"
        case .listenerFailed(let reason):
            return "Loopback OAuth listener failed: \(reason)"
        case .invalidHTTPRequest:
            return "Invalid loopback OAuth HTTP request"
        }
    }
}

protocol OAuthCallbackReceiver: Sendable {
    func receiveCallback() async throws -> URL
}

public final class WebexOAuthLoopbackRedirectListener: OAuthCallbackReceiver, @unchecked Sendable {
    public static let defaultRedirectURI = URL(string: "http://127.0.0.1:8282/oauth/callback")!

    private let redirectURI: URL
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var listener: NWListener?
    private var continuation: CheckedContinuation<URL, Error>?

    public init(redirectURI: URL = WebexOAuthLoopbackRedirectListener.defaultRedirectURI) {
        self.redirectURI = redirectURI
        self.queue = DispatchQueue(label: "com.webex.swift-sdk.oauth-loopback-listener")
    }

    init(redirectURI: URL, queue: DispatchQueue) {
        self.redirectURI = redirectURI
        self.queue = queue
    }

    public func receiveCallback() async throws -> URL {
        let validatedRedirect = try ValidatedLoopbackRedirect(redirectURI)
        try Task.checkCancellation()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                do {
                    try start(validatedRedirect: validatedRedirect, continuation: continuation)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            complete(.failure(CancellationError()))
        }
    }

    private func start(
        validatedRedirect: ValidatedLoopbackRedirect,
        continuation: CheckedContinuation<URL, Error>
    ) throws {
        let listener = try NWListener(
            using: .tcp,
            on: NWEndpoint.Port(rawValue: validatedRedirect.port)!
        )

        lock.lock()
        guard self.listener == nil, self.continuation == nil else {
            lock.unlock()
            listener.cancel()
            throw WebexOAuthLoopbackRedirectListenerError.listenerFailed("Listener is already active")
        }
        self.listener = listener
        self.continuation = continuation
        lock.unlock()

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let error):
                self?.complete(.failure(WebexOAuthLoopbackRedirectListenerError.listenerFailed(error.localizedDescription)))
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection, redirect: validatedRedirect)
        }
        listener.start(queue: queue)
    }

    private func handle(connection: NWConnection, redirect: ValidatedLoopbackRedirect) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, error in
            guard let self else {
                connection.cancel()
                return
            }

            if let error {
                self.sendResponse(status: 400, body: "Invalid OAuth callback request.", on: connection)
                self.complete(.failure(WebexOAuthLoopbackRedirectListenerError.listenerFailed(error.localizedDescription)))
                return
            }

            guard let data,
                  let request = String(data: data, encoding: .utf8),
                  let requestTarget = Self.requestTarget(from: request) else {
                self.sendResponse(status: 400, body: "Invalid OAuth callback request.", on: connection)
                return
            }

            guard let callbackURL = redirect.callbackURL(from: requestTarget) else {
                self.sendResponse(status: 404, body: "OAuth callback path not found.", on: connection)
                return
            }

            self.sendResponse(status: 200, body: "Webex authorization complete. You can close this window.", on: connection)
            self.complete(.success(callbackURL))
        }
    }

    private static func requestTarget(from request: String) -> String? {
        guard let requestLine = request.split(separator: "\r\n", maxSplits: 1).first else {
            return nil
        }

        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2, parts[0] == "GET" else {
            return nil
        }

        return String(parts[1])
    }

    private func sendResponse(status: Int, body: String, on connection: NWConnection) {
        let reason: String
        switch status {
        case 200:
            reason = "OK"
        case 404:
            reason = "Not Found"
        default:
            reason = "Bad Request"
        }

        let html = """
        <!doctype html><html><head><meta charset="utf-8"><title>Webex OAuth</title></head><body><p>\(body)</p></body></html>
        """
        let response = """
        HTTP/1.1 \(status) \(reason)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(Data(html.utf8).count)\r
        Connection: close\r
        \r
        \(html)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func complete(_ result: Result<URL, Error>) {
        lock.lock()
        let continuation = continuation
        let listener = listener
        self.continuation = nil
        self.listener = nil
        lock.unlock()

        listener?.cancel()
        switch result {
        case .success(let url):
            continuation?.resume(returning: url)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }
}

private struct ValidatedLoopbackRedirect: Sendable {
    let port: UInt16
    let path: String
    let baseURLString: String

    init(_ redirectURI: URL) throws {
        guard redirectURI.scheme == "http" else {
            throw WebexOAuthLoopbackRedirectListenerError.invalidRedirectURI("Loopback OAuth redirect URI must use http")
        }

        guard redirectURI.host == "127.0.0.1" else {
            throw WebexOAuthLoopbackRedirectListenerError.invalidRedirectURI("Loopback OAuth redirect URI must use host 127.0.0.1")
        }

        guard let port = redirectURI.port, port > 0, port <= Int(UInt16.max) else {
            throw WebexOAuthLoopbackRedirectListenerError.invalidRedirectURI("Loopback OAuth redirect URI must include an explicit port")
        }

        guard !redirectURI.path.isEmpty, redirectURI.path != "/" else {
            throw WebexOAuthLoopbackRedirectListenerError.invalidRedirectURI("Loopback OAuth redirect URI must include a callback path")
        }

        guard redirectURI.query == nil, redirectURI.fragment == nil else {
            throw WebexOAuthLoopbackRedirectListenerError.invalidRedirectURI("Loopback OAuth redirect URI must not include query or fragment")
        }

        self.port = UInt16(port)
        self.path = redirectURI.path
        self.baseURLString = "http://127.0.0.1:\(port)"
    }

    func callbackURL(from requestTarget: String) -> URL? {
        guard let components = URLComponents(string: requestTarget),
              components.path == path else {
            return nil
        }

        return URL(string: "\(baseURLString)\(requestTarget)")
    }
}
