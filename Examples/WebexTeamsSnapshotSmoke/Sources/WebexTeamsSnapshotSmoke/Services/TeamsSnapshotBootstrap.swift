import AppKit
import Foundation
import WebexSwiftSDK

enum TeamsSnapshotBootstrap {
    static func makeRuntime(configuration: TeamsSnapshotSmokeConfiguration) async throws -> TeamsSnapshotRuntime {
        let httpClient = URLSessionHTTPClient()
        let store = KeychainWebexStore(service: configuration.keychainService)
        let registry = WebexClientRegistry(store: store, httpClient: httpClient)
        let client = try await makeClient(
            registry: registry,
            configuration: configuration.integration,
            openAuthorizationURL: { authorizationURL in
                guard NSWorkspace.shared.open(authorizationURL) else {
                    throw TeamsSnapshotSmokeError.failedToOpenAuthorizationURL
                }
            }
        )

        let stream = client.teams.stream(
            params: configuration.listParams,
            pageLimit: configuration.pageLimit
        )

        return TeamsSnapshotRuntime(stream: stream)
    }

    static func makeClient(
        registry: WebexClientRegistry,
        configuration: WebexIntegrationConfiguration,
        openAuthorizationURL: @escaping @Sendable (URL) async throws -> Void
    ) async throws -> WebexClient {
        for account in try await registry.listAccounts() {
            do {
                return try await registry.client(for: account.id)
            } catch WebexSDKError.missingCredential {
                continue
            }
        }

        let authorized = try await registry.authorizeAndAddAccount(
            configuration: configuration,
            openAuthorizationURL: openAuthorizationURL
        )
        return authorized.client
    }
}
