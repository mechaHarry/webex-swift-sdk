import Foundation

enum WebexStreamErrorRedactor {
    static func webexStreamError(from error: Error) -> WebexSDKError {
        switch error {
        case let sdkError as WebexSDKError:
            return redacted(sdkError)
        default:
            return .network(Redactor.redactOAuthCallback(error.localizedDescription))
        }
    }

    static func redacted(_ error: WebexSDKError) -> WebexSDKError {
        switch error {
        case .invalidAccountID(let rawValue):
            return .invalidAccountID(Redactor.redactSecrets(rawValue))
        case .invalidAuthorizationCallback(let callback):
            return .invalidAuthorizationCallback(Redactor.redactOAuthCallback(callback))
        case .authorizationStateMismatch,
             .userCancelledAuthorization,
             .missingCredential,
             .missingRefreshToken,
             .reauthenticationRequired,
             .rateLimited:
            return error
        case .duplicateAccount(let existing, let reason):
            return .duplicateAccount(existing: existing, reason: Redactor.redactSecrets(reason))
        case .tokenExchangeFailed(let statusCode, let message, let trackingID):
            return .tokenExchangeFailed(
                statusCode: statusCode,
                message: Redactor.redactSecrets(message),
                trackingID: trackingID.map(Redactor.redactSecrets)
            )
        case .locked(let retryAfter, let trackingID, let message):
            return .locked(
                retryAfter: retryAfter,
                trackingID: trackingID.map(Redactor.redactSecrets),
                message: Redactor.redactSecrets(message)
            )
        case .webexAPI(let statusCode, let trackingID, let message):
            return .webexAPI(
                statusCode: statusCode,
                trackingID: trackingID.map(Redactor.redactSecrets),
                message: Redactor.redactSecrets(message)
            )
        case .network(let message):
            return .network(Redactor.redactOAuthCallback(message))
        }
    }
}
