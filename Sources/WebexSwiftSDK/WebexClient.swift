import Foundation

public struct WebexClient: Sendable {
    public let accountID: WebexAccountID
    public let people: PeopleAPI
    public let spaces: SpacesAPI

    public var rooms: RoomsAPI {
        spaces
    }

    private let tokenManager: TokenManager

    public init(
        accountID: WebexAccountID,
        configuration: WebexIntegrationConfiguration,
        tokenStore: WebexTokenStore,
        httpClient: HTTPClient = URLSessionHTTPClient(),
        initialAccessToken: AccessTokenState? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        let tokenManager = TokenManager(
            accountID: accountID,
            configuration: configuration,
            tokenStore: tokenStore,
            httpClient: httpClient,
            initialAccessToken: initialAccessToken,
            clock: clock
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
        self.spaces = SpacesAPI(transport: transport)
        self.tokenManager = tokenManager
    }
}
