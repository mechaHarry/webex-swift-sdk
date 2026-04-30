import Foundation

public struct AccessTokenState: Equatable, Sendable {
    public let value: String
    public let expiresAt: Date
    public let tokenType: String

    public init(value: String, expiresAt: Date, tokenType: String) {
        self.value = value
        self.expiresAt = expiresAt
        self.tokenType = tokenType
    }
}

extension AccessTokenState: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        redactedDescription
    }

    public var debugDescription: String {
        redactedDescription
    }

    private var redactedDescription: String {
        [
            "AccessTokenState(",
            "value: [redacted], ",
            "expiresAt: \(expiresAt), ",
            "tokenType: \(tokenType)",
            ")"
        ].joined()
    }
}

public struct WebexTokenResponse: Decodable, Equatable, Sendable {
    public let accessToken: String
    public let expiresIn: Int
    public let refreshToken: String
    public let refreshTokenExpiresIn: Int
    public let tokenType: String
    public let scope: String
    public let idToken: String?

    public init(
        accessToken: String,
        expiresIn: Int,
        refreshToken: String,
        refreshTokenExpiresIn: Int,
        tokenType: String,
        scope: String,
        idToken: String?
    ) {
        self.accessToken = accessToken
        self.expiresIn = expiresIn
        self.refreshToken = refreshToken
        self.refreshTokenExpiresIn = refreshTokenExpiresIn
        self.tokenType = tokenType
        self.scope = scope
        self.idToken = idToken
    }

    public func tokenRecord(receivedAt: Date) -> WebexTokenRecord {
        WebexTokenRecord(
            refreshToken: refreshToken,
            refreshTokenExpiresAt: receivedAt.addingTimeInterval(TimeInterval(refreshTokenExpiresIn)),
            lastAccessTokenExpiresAt: receivedAt.addingTimeInterval(TimeInterval(expiresIn)),
            grantedScopes: Self.normalizedScopes(scope),
            tokenType: tokenType,
            lastRefreshAt: receivedAt
        )
    }

    public func accessTokenState(receivedAt: Date) -> AccessTokenState {
        AccessTokenState(
            value: accessToken,
            expiresAt: receivedAt.addingTimeInterval(TimeInterval(expiresIn)),
            tokenType: tokenType
        )
    }

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case refreshTokenExpiresIn = "refresh_token_expires_in"
        case tokenType = "token_type"
        case scope
        case idToken = "id_token"
    }

    private static func normalizedScopes(_ scope: String) -> [String] {
        let scopes = scope
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
        return Array(Set(scopes)).sorted()
    }
}

extension WebexTokenResponse: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        redactedDescription
    }

    public var debugDescription: String {
        redactedDescription
    }

    private var redactedDescription: String {
        [
            "WebexTokenResponse(",
            "accessToken: [redacted], ",
            "expiresIn: \(expiresIn), ",
            "refreshToken: [redacted], ",
            "refreshTokenExpiresIn: \(refreshTokenExpiresIn), ",
            "tokenType: \(tokenType), ",
            "scope: \(scope), ",
            "idToken: \(idToken == nil ? "nil" : "[redacted]")",
            ")"
        ].joined()
    }
}

public enum WebexTokenEndpoint {
    public static let accessTokenURL = URL(string: "https://webexapis.com/v1/access_token")!
    private static let formAllowedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    public static func authorizationCodeRequest(
        configuration: WebexIntegrationConfiguration,
        code: String,
        codeVerifier: String
    ) throws -> URLRequest {
        formRequest(parameters: [
            ("grant_type", "authorization_code"),
            ("client_id", configuration.clientID),
            ("client_secret", configuration.clientSecret),
            ("code", code),
            ("redirect_uri", configuration.redirectURI.absoluteString),
            ("code_verifier", codeVerifier)
        ])
    }

    public static func refreshTokenRequest(
        configuration: WebexIntegrationConfiguration,
        refreshToken: String
    ) throws -> URLRequest {
        formRequest(parameters: [
            ("grant_type", "refresh_token"),
            ("client_id", configuration.clientID),
            ("client_secret", configuration.clientSecret),
            ("refresh_token", refreshToken)
        ])
    }

    private static func formRequest(parameters: [(String, String)]) -> URLRequest {
        var request = URLRequest(url: accessTokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(formEncodedBody(parameters).utf8)
        return request
    }

    private static func formEncodedBody(_ parameters: [(String, String)]) -> String {
        parameters
            .map { name, value in
                "\(formPercentEncoded(name))=\(formPercentEncoded(value))"
            }
            .joined(separator: "&")
    }

    private static func formPercentEncoded(_ value: String) -> String {
        return value.unicodeScalars
            .map { scalar in
                guard formAllowedCharacters.contains(scalar) else {
                    return String(scalar).utf8
                        .map { String(format: "%%%02X", $0) }
                        .joined()
                }

                return String(scalar)
            }
            .joined()
    }
}
