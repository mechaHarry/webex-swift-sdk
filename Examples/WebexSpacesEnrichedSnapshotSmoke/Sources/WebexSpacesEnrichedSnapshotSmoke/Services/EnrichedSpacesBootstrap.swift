import AppKit
import Foundation
import WebexSwiftSDK

enum EnrichedSpacesBootstrap {
    static func makeRuntime(configuration: EnrichedSpacesSmokeConfiguration) async throws -> EnrichedSpacesRuntime {
        let httpClient = URLSessionHTTPClient()
        let store = KeychainWebexStore(service: configuration.keychainService)
        let registry = WebexClientRegistry(store: store, httpClient: httpClient)
        let authorized = try await registry.authorizeAndAddAccount(
            configuration: configuration.integration,
            openAuthorizationURL: { authorizationURL in
                guard NSWorkspace.shared.open(authorizationURL) else {
                    throw EnrichedSpacesSmokeError.failedToOpenAuthorizationURL
                }
            }
        )

        let stream = authorized.client.spaces.stream(
            params: configuration.listParams,
            pageLimit: configuration.pageLimit
        )

        return EnrichedSpacesRuntime(stream: stream)
    }
}
