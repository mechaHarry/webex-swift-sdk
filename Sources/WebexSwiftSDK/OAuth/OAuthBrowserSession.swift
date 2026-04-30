import Foundation

public protocol OAuthBrowserSession: AnyObject, Sendable {
    func authenticate(
        authorizationURL: URL,
        callbackURLScheme: String,
        prefersEphemeralWebBrowserSession: Bool
    ) async throws -> URL
}
