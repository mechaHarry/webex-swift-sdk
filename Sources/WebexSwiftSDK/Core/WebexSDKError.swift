import Foundation

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
    case webexAPI(statusCode: Int, trackingID: String?, message: String)
    case network(String)
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
