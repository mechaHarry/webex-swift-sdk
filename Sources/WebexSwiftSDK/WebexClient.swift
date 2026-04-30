import Foundation

public struct WebexClient: Sendable {
    public let accountID: WebexAccountID
    public let people: PeopleAPI

    private let tokenManager: TokenManager

    public init(
        accountID: WebexAccountID,
        configuration: WebexIntegrationConfiguration,
        tokenStore: WebexTokenStore,
        httpClient: HTTPClient = URLSessionHTTPClient()
    ) {
        let tokenManager = TokenManager(
            accountID: accountID,
            configuration: configuration,
            tokenStore: tokenStore,
            httpClient: httpClient
        )
        let transport = WebexTransport(
            httpClient: httpClient,
            accessTokenProvider: {
                try await tokenManager.validAccessToken()
            },
            tokenInvalidator: {
                await tokenManager.invalidateAccessToken()
            }
        )

        self.accountID = accountID
        self.people = PeopleAPI(transport: transport)
        self.tokenManager = tokenManager
    }
}
