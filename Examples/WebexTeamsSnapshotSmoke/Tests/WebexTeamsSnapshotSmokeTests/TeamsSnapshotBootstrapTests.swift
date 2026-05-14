import Foundation
import XCTest
import WebexSwiftSDK
@testable import WebexTeamsSnapshotSmoke

final class TeamsSnapshotBootstrapTests: XCTestCase {
    func testMakeClientReusesExistingRegistryAccountWithoutOpeningAuthorizationURL() async throws {
        let store = InMemoryWebexStore()
        let registry = WebexClientRegistry(store: store, httpClient: BootstrapHTTPClient())
        let account = try await registry.addAccount(
            configuration: configuration(clientID: "stored-client")
        )
        let opener = AuthorizationOpenProbe()

        let client = try await TeamsSnapshotBootstrap.makeClient(
            registry: registry,
            configuration: configuration(clientID: "new-client"),
            openAuthorizationURL: { url in
                await opener.open(url)
            }
        )

        XCTAssertEqual(client.accountID, account.id)
        let openedAuthorizationURL = await opener.wasOpened()
        XCTAssertFalse(openedAuthorizationURL)
    }

    private func configuration(clientID: String) -> WebexIntegrationConfiguration {
        WebexIntegrationConfiguration(
            clientID: clientID,
            clientSecret: "client-secret",
            redirectURI: URL(string: "http://127.0.0.1:8282/oauth/callback")!,
            scopes: ["spark:teams_read"],
            prefersEphemeralWebBrowserSession: false
        )
    }
}

private actor AuthorizationOpenProbe {
    private var openedURL: URL?

    func open(_ url: URL) {
        self.openedURL = url
    }

    func wasOpened() -> Bool {
        openedURL != nil
    }
}

private actor BootstrapHTTPClient: HTTPClient {
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        throw WebexSDKError.network("Unexpected bootstrap HTTP request")
    }
}
