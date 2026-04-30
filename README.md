# webex-swift-sdk

Swift-first macOS SDK for Webex Developer APIs.

## Current Scope

This package provides the OAuth and authenticated REST foundation:

- user-provided Webex integration credentials
- PKCE authorization request support
- Apple-native browser auth boundary
- SDK-owned loopback redirect listener on `127.0.0.1:8282`
- Keychain-backed credential and refresh-token storage
- memory-only access-token cache by default
- coordinated token refresh
- authenticated REST transport
- `people.me()` as the first typed Webex endpoint

## Example

```swift
import WebexSwiftSDK

let registry = WebexClientRegistry()
let accounts = try await registry.listAccounts()

for account in accounts {
    let client = try await registry.client(for: account.id)
    let person = try await client.people.me()
    print(person.displayName ?? person.id)
}
```

The host macOS app owns UI, account selection, and window-to-account routing. The SDK owns OAuth, token lifecycle, local secure storage, and authenticated Webex REST execution.

## Examples

- `Examples/WebexClientSmoke`: interactive OAuth smoke test that uses the SDK-owned loopback listener, stores a registry account, exchanges an authorization code, creates `WebexClient`, and calls `people.me()`.
