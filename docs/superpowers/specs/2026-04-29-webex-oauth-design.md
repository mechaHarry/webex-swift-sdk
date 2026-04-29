# Webex OAuth 2.0 Auth Design

Date: 2026-04-29

## Purpose

This design defines the first authentication and REST ownership boundary for `webex-swift-sdk`. The SDK is a Swift-based library for macOS apps that need to authenticate users against Webex Developer APIs and continue making API calls without repeatedly sending users through browser consent.

The SDK must be Swift-first, Webex-aware, and Apple-native. It must not use Node.js, Python, a browser-side helper runtime, or an embedded web server unless a future Webex redirect constraint makes that unavoidable. It must keep UI and data responsibilities isolated: host apps collect user input and render Webex data, while the SDK owns OAuth, token lifecycle, secure local persistence, and authenticated REST calls.

## Product Model

The SDK and consuming macOS apps are intended to be distributed publicly. They must not compile in a shared Webex `client_id` or `client_secret`.

Each user provides their own Webex integration credentials during setup:

- `client_id`
- `client_secret`
- redirect URI
- scopes

The SDK accepts those credentials at runtime, stores them locally if requested, and uses them to authenticate and refresh tokens. A production backend token service is outside the scope of this SDK because the app vendor is not expected to own a single shared Webex integration secret.

## Account And Client Ownership

The SDK generates a stable local `WebexAccountID` for each saved account. This ID is the primary storage key and should be independent of mutable Webex or user properties.

The SDK stores mutable metadata beside the local account ID:

- client ID
- credential fingerprint or version
- redirect URI
- requested and granted scopes
- Webex user ID or OIDC subject, when available
- email and display name, when available
- organization hints, when available
- last verified date
- credential created and updated dates

The SDK exposes two layers:

- `WebexClient`: an isolated instance that owns one account's auth lifecycle and REST transport.
- `WebexClientRegistry`: an optional managed layer that persists account records, creates stable local account IDs, loads clients by UUID, updates credentials, removes accounts, triggers reauthorization, and detects duplicate or suspicious records.

The registry does not choose an active account. The consuming macOS app owns window routing, instance mapping, active account selection, and any global default account policy.

Normal app startup should look conceptually like this:

```swift
let registry = WebexClientRegistry(storage: .keychain())
let accounts = try await registry.listAccounts()

var clients: [WebexAccountID: WebexClient] = [:]

for account in accounts {
    clients[account.id] = try await registry.client(for: account.id)
}
```

A simpler app or test can still create a bare client directly:

```swift
let client = WebexClient(
    accountID: WebexAccountID(),
    configuration: configuration,
    storage: .keychain(namespace: "com.example.webex.account")
)
```

REST calls do not require an account ID because the identity is scoped by the `WebexClient` instance.

## Duplicate Detection

The local UUID is the canonical identity. Webex-side values are mutable signals, not primary keys.

Duplicate detection should be confidence-based:

- exact same local account ID: same account
- same client ID plus same Webex user ID or OIDC subject: likely duplicate
- same email only: possible duplicate; warn but allow
- changed client secret for same local account: update credential metadata and refresh or reauthorize as needed
- changed client ID: treat as a new integration unless the user explicitly links it to an existing local account

Before the first OAuth flow completes, the SDK may not know the Webex user ID or OIDC subject. It should detect only obvious pre-auth duplicates, then perform stronger duplicate checks after successful identity discovery.

## Native OAuth Presentation

The SDK core uses an `OAuthBrowserSession` abstraction with Apple-native implementations.

`ASWebAuthenticationSession` is the default implementation because it works outside SwiftUI and can be used by SwiftUI, AppKit, menu bar apps, background coordinators, and tests. A SwiftUI `WebAuthenticationSession` implementation should also be supported for host apps that want auth launched from SwiftUI environment context.

Both implementations are native Apple AuthenticationServices surfaces. Neither requires Node.js, Python, custom browser automation, or a local helper server.

The OAuth flow should use:

- authorization code flow
- PKCE S256
- per-attempt `state`
- callback URL validation
- optional `login_hint` and account selection parameters when the host app asks for them
- configurable normal or ephemeral browser session preference

PKCE protects the authorization code flow, but it does not make a locally stored client secret impossible to extract. The SDK therefore treats the user-provided client secret as sensitive local user data and must never log, expose, or transmit it except to Webex token endpoints.

## Token Lifecycle

The SDK owns token exchange, refresh, expiry tracking, and reauthorization signaling.

Runtime lifecycle:

1. The app asks the registry for a client by local account UUID, or constructs a bare client.
2. The client loads credential and token state from storage.
3. Before each REST call, the client asks `TokenManager` for a valid access token.
4. If the access token is fresh, the request uses it.
5. If the token is near expiry, the SDK refreshes using the refresh token, client ID, and client secret.
6. If refresh succeeds, the SDK atomically stores the latest refresh token and token metadata, then updates the in-memory access-token cache.
7. If refresh fails with transient network or server errors, the SDK retries with exponential backoff and jitter.
8. If the refresh token is expired, revoked, malformed, invalid, or missing, the SDK surfaces `reauthenticationRequired(accountID:)`.
9. The host app decides when and how to show reauthorization UI.

Only one refresh should run per account at a time. Concurrent REST calls that discover a near-expired token should await the same refresh task instead of issuing parallel refresh requests.

The SDK should store expiry as absolute dates derived from `expires_in` and `refresh_token_expires_in`, not only as relative durations. It should refresh before expiry using a configurable safety margin.

Webex controls token lifetimes. The SDK may request the correct scopes and refresh early, but it must not imply it can force longer token lifetimes than Webex grants. Webex documentation describes access tokens with `expires_in`, refresh tokens with `refresh_token_expires_in`, and refresh responses that renew the refresh token lifetime.

## REST API Ownership

The SDK owns authenticated REST execution, not only token vending.

A `WebexClient` represents one local account UUID and exposes typed API groups over Webex REST resources:

```swift
try await client.messages.list(query: .init())
try await client.rooms.list(query: .init())
try await client.people.me()
```

Each request follows one transport path:

1. Build a typed Webex request.
2. Ask `TokenManager` for a valid access token.
3. Attach `Authorization: Bearer <access_token>`.
4. Send with `URLSession`.
5. Decode success or Webex error payload.
6. If the response is a `401` invalid token, attempt one coordinated refresh and retry once.
7. For `429`, `5xx`, and transient network failures, retry with exponential backoff, jitter, and respect for `Retry-After` when present.
8. Surface typed SDK errors with Webex `trackingId` preserved when available.

The Mac app should not manually attach tokens, refresh tokens, or parse Webex auth failures. It receives typed results and typed failures such as:

```swift
WebexSDKError.reauthenticationRequired(accountID)
WebexSDKError.rateLimited(retryAfter)
WebexSDKError.webexAPI(statusCode, trackingID, message)
WebexSDKError.network(underlying)
```

## Storage

Default persistence is Keychain-backed and namespaced by local account UUID.

Storage should be split by purpose:

- Credential record: client ID, client secret, redirect URI, scopes, credential fingerprint or version, created and updated dates.
- Token record: refresh token, refresh token expiry timestamp, last access token expiry timestamp, granted scopes, token type, last refresh date.
- Metadata record: display email, Webex or OIDC identifiers, organization hints, last successful identity check.

The SDK should expose storage protocols for tests and advanced host apps:

```swift
protocol WebexCredentialStore {
    func loadCredential(for accountID: WebexAccountID) async throws -> WebexCredentialRecord?
    func saveCredential(_ record: WebexCredentialRecord, for accountID: WebexAccountID) async throws
    func deleteCredential(for accountID: WebexAccountID) async throws
}

protocol WebexTokenStore {
    func loadTokenRecord(for accountID: WebexAccountID) async throws -> WebexTokenRecord?
    func saveTokenRecord(_ record: WebexTokenRecord, for accountID: WebexAccountID) async throws
    func deleteTokenRecord(for accountID: WebexAccountID) async throws
}

protocol WebexAccountMetadataStore {
    func loadMetadata(for accountID: WebexAccountID) async throws -> WebexAccountMetadata?
    func saveMetadata(_ metadata: WebexAccountMetadata, for accountID: WebexAccountID) async throws
    func deleteMetadata(for accountID: WebexAccountID) async throws
}
```

Access tokens should be cached in memory by default. Persisting access tokens should require an explicit storage policy so stricter host apps can keep the durable secret surface limited to credentials, refresh tokens, and metadata.

Account removal APIs must delete SDK-owned Keychain records for that local UUID. Credential update APIs must preserve the local account UUID and mutable history unless the user explicitly removes the account.

## Security Rules

The SDK must:

- never log client secrets, access tokens, refresh tokens, auth codes, PKCE verifiers, or full callback URLs
- redact sensitive values from errors and debug output
- keep access tokens memory-only by default and require an explicit opt-in policy for access-token persistence
- use atomic Keychain updates when replacing refresh tokens
- distinguish missing credentials, missing refresh token, invalid refresh token, revoked token, user-cancelled auth, and network failure
- support opt-in sanitized request/response debugging
- keep Webex `trackingId` values in errors for supportability

## Testing

The first implementation plan should include tests for:

- PKCE verifier and S256 challenge generation
- authorization URL construction
- state validation
- callback parsing
- user cancellation
- token expiry calculations
- refresh safety margin behavior
- refresh coalescing under concurrent requests
- backoff and jitter behavior
- Keychain storage via a test double
- optional integration-style Keychain coverage behind a local flag
- REST retry behavior for `401`, `429`, `5xx`, malformed Webex errors, and transient network failures
- duplicate detection heuristics using mutable metadata
- credential update without account ID churn
- redaction of secrets in logs and errors

## Out Of Scope For First Implementation

The first implementation should not include:

- a production backend token service
- a Node.js, Python, or browser automation auth helper
- Webex device authorization flow
- webhook hosting
- every Webex REST resource
- UI screens for credential entry or account management
- global active-account policy inside the SDK registry

## References

- Webex Integrations and Authorization: https://developer.webex.com/messaging/docs/api/guides/integrations-and-authorization
- Webex Login with Webex: https://developer.webex.com/create/docs/login-with-webex
- Apple ASWebAuthenticationSession: https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession
- Apple WebAuthenticationSession: https://developer.apple.com/documentation/authenticationservices/webauthenticationsession
- Apple Keychain Services: https://developer.apple.com/documentation/security/keychain-services
