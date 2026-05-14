import AppKit
import Foundation
import WebexSwiftSDK

enum TeamsSnapshotBootstrap {
    static func makeRuntime(configuration: TeamsSnapshotSmokeConfiguration) async throws -> TeamsSnapshotRuntime {
        let httpClient = URLSessionHTTPClient()
        let store = KeychainWebexStore(service: configuration.keychainService)
        let registry = WebexClientRegistry(store: store, httpClient: httpClient)
        let authorized = try await registry.authorizeAndAddAccount(
            configuration: configuration.integration,
            openAuthorizationURL: { authorizationURL in
                guard NSWorkspace.shared.open(authorizationURL) else {
                    throw TeamsSnapshotSmokeError.failedToOpenAuthorizationURL
                }
            }
        )

        let stream = authorized.client.teams.stream(
            params: configuration.listParams,
            pageLimit: configuration.pageLimit
        )

        return TeamsSnapshotRuntime(stream: stream)
    }
}
