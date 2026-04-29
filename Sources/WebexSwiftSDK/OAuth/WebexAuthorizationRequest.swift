import Foundation

public struct WebexAuthorizationRequest: Equatable, Sendable {
    private static let authorizationEndpoint = URL(string: "https://webexapis.com/v1/authorize")!

    public let configuration: WebexIntegrationConfiguration
    public let state: String
    public let codeChallenge: String
    public let loginHint: String?
    public let prompt: String?

    public init(
        configuration: WebexIntegrationConfiguration,
        state: String,
        codeChallenge: String,
        loginHint: String? = nil,
        prompt: String? = nil
    ) {
        self.configuration = configuration
        self.state = state
        self.codeChallenge = codeChallenge
        self.loginHint = loginHint
        self.prompt = prompt
    }

    public func url() throws -> URL {
        guard var components = URLComponents(url: Self.authorizationEndpoint, resolvingAgainstBaseURL: false) else {
            throw WebexAuthorizationRequestError.invalidAuthorizationEndpoint
        }

        var queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI.absoluteString),
            URLQueryItem(name: "scope", value: configuration.scopeString),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        if let loginHint {
            queryItems.append(URLQueryItem(name: "login_hint", value: loginHint))
        }

        if let prompt {
            queryItems.append(URLQueryItem(name: "prompt", value: prompt))
        }

        components.queryItems = queryItems
        // URLComponents leaves literal "+" in query values; form-style decoders can read that as space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")

        guard let url = components.url else {
            throw WebexAuthorizationRequestError.failedToBuildAuthorizationURL
        }

        return url
    }
}

public enum WebexAuthorizationRequestError: Error, Equatable, Sendable {
    case invalidAuthorizationEndpoint
    case failedToBuildAuthorizationURL
}

extension WebexAuthorizationRequestError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidAuthorizationEndpoint:
            return "Invalid Webex authorization endpoint"
        case .failedToBuildAuthorizationURL:
            return "Failed to build Webex authorization URL"
        }
    }
}
