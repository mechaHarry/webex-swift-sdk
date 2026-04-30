import Foundation

public struct OAuthAuthorizationCode: Equatable, Sendable {
    public let code: String
    public let state: String
}

extension OAuthAuthorizationCode: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "OAuthAuthorizationCode(code: [redacted], state: \(state))"
    }

    public var debugDescription: String {
        description
    }
}

public enum OAuthCallbackParser {
    public static func parse(callbackURL: URL, expectedState: String) throws -> OAuthAuthorizationCode {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw WebexSDKError.invalidAuthorizationCallback(callbackURL.absoluteString)
        }

        let queryItems = components.queryItems ?? []
        let state = queryItems.firstValue(named: "state")

        guard state == expectedState else {
            throw WebexSDKError.authorizationStateMismatch(expected: expectedState, actual: state)
        }

        if queryItems.firstValue(named: "error") != nil {
            throw WebexSDKError.invalidAuthorizationCallback("OAuth authorization error callback")
        }

        guard let code = queryItems.firstValue(named: "code"), !code.isEmpty else {
            throw WebexSDKError.invalidAuthorizationCallback(callbackURL.absoluteString)
        }

        return OAuthAuthorizationCode(code: code, state: expectedState)
    }
}

private extension Array where Element == URLQueryItem {
    func firstValue(named name: String) -> String? {
        first { $0.name == name }?.value
    }
}
