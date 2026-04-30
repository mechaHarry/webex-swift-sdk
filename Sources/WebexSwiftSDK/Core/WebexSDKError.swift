import Foundation

public enum WebexAPIErrorKind: Equatable, Sendable {
    case badRequest
    case unauthorized
    case forbidden
    case notFound
    case methodNotAllowed
    case conflict
    case gone
    case unsupportedMediaType
    case locked(retryAfter: TimeInterval?)
    case preconditionRequired
    case rateLimited(retryAfter: TimeInterval?)
    case serverError
    case unexpected(statusCode: Int)
}

public enum WebexSDKError: Error, Equatable, Sendable {
    case invalidAccountID(String)
    case invalidAuthorizationCallback(String)
    case authorizationStateMismatch(expected: String, actual: String?)
    case userCancelledAuthorization
    case missingCredential(WebexAccountID)
    case missingRefreshToken(WebexAccountID)
    case reauthenticationRequired(WebexAccountID)
    case duplicateAccount(existing: WebexAccountID, reason: String)
    case tokenExchangeFailed(statusCode: Int, message: String, trackingID: String?)
    case rateLimited(retryAfter: TimeInterval?)
    case locked(retryAfter: TimeInterval?, trackingID: String?, message: String)
    case webexAPI(statusCode: Int, trackingID: String?, message: String)
    case network(String)
}

public extension WebexSDKError {
    var apiErrorKind: WebexAPIErrorKind? {
        switch self {
        case .tokenExchangeFailed(let statusCode, _, _),
             .webexAPI(let statusCode, _, _):
            return Self.apiErrorKind(for: statusCode)
        case .rateLimited(let retryAfter):
            return .rateLimited(retryAfter: retryAfter)
        case .locked(let retryAfter, _, _):
            return .locked(retryAfter: retryAfter)
        case .invalidAccountID,
             .invalidAuthorizationCallback,
             .authorizationStateMismatch,
             .userCancelledAuthorization,
             .missingCredential,
             .missingRefreshToken,
             .reauthenticationRequired,
             .duplicateAccount,
             .network:
            return nil
        }
    }

    private static func apiErrorKind(for statusCode: Int) -> WebexAPIErrorKind {
        switch statusCode {
        case 400:
            return .badRequest
        case 401:
            return .unauthorized
        case 403:
            return .forbidden
        case 404:
            return .notFound
        case 405:
            return .methodNotAllowed
        case 409:
            return .conflict
        case 410:
            return .gone
        case 415:
            return .unsupportedMediaType
        case 423:
            return .locked(retryAfter: nil)
        case 428:
            return .preconditionRequired
        case 429:
            return .rateLimited(retryAfter: nil)
        case 500...599:
            return .serverError
        default:
            return .unexpected(statusCode: statusCode)
        }
    }
}

extension WebexSDKError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidAccountID(let rawValue):
            return "Invalid Webex account ID: \(Redactor.redactSecrets(rawValue))"
        case .invalidAuthorizationCallback(let callback):
            return "Invalid authorization callback: \(Redactor.redactOAuthCallback(callback))"
        case .authorizationStateMismatch(_, let actual):
            if actual == nil {
                return "Authorization state mismatch: actual state was missing"
            }
            return "Authorization state mismatch"
        case .userCancelledAuthorization:
            return "User cancelled authorization"
        case .missingCredential(let accountID):
            return "Missing credential for account \(accountID)"
        case .missingRefreshToken(let accountID):
            return "Missing refresh token for account \(accountID)"
        case .reauthenticationRequired(let accountID):
            return "Reauthentication required for account \(accountID)"
        case .duplicateAccount(let existing, let reason):
            return "Duplicate account \(existing): \(Redactor.redactSecrets(reason))"
        case .tokenExchangeFailed(let statusCode, let message, let trackingID):
            return "Token exchange failed with status \(statusCode): \(Redactor.redactSecrets(message))\(trackingIDDescription(trackingID))"
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "Rate limited; retry after \(retryAfter) seconds"
            }
            return "Rate limited"
        case .locked(let retryAfter, let trackingID, let message):
            let retryDescription = retryAfter.map { "; retry after \($0) seconds" } ?? ""
            return "Webex API resource locked\(retryDescription): \(Redactor.redactSecrets(message))\(trackingIDDescription(trackingID))"
        case .webexAPI(let statusCode, let trackingID, let message):
            return "Webex API failed with status \(statusCode): \(Redactor.redactSecrets(message))\(trackingIDDescription(trackingID))"
        case .network(let message):
            return "Network error: \(Redactor.redactSecrets(message))"
        }
    }

    private func trackingIDDescription(_ trackingID: String?) -> String {
        guard let trackingID else {
            return ""
        }

        return " (tracking ID: \(trackingID))"
    }
}
