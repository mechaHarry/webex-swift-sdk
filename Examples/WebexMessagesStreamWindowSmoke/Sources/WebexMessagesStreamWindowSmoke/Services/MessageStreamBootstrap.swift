import AppKit
import Foundation
import WebexSwiftSDK

enum MessageStreamBootstrap {
    static func makeStream(configuration: StreamSmokeConfiguration) async throws -> MessagesStream {
        let httpClient = URLSessionHTTPClient()
        let store = KeychainWebexStore(service: configuration.keychainService)
        let registry = WebexClientRegistry(store: store, httpClient: httpClient)
        let authorized = try await registry.authorizeAndAddAccount(
            configuration: configuration.integration,
            openAuthorizationURL: { authorizationURL in
                guard NSWorkspace.shared.open(authorizationURL) else {
                    throw StreamSmokeError.failedToOpenAuthorizationURL
                }
            }
        )

        return authorized.client.messages.stream(
            params: configuration.listParams,
            pageLimit: configuration.pageLimit
        )
    }
}
