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
- typed People, Spaces, and Memberships APIs

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

## Spaces

Webex's REST API still uses `/v1/rooms`, while modern product language calls
these collaboration containers spaces. The SDK exposes `client.spaces` as the
preferred interface and `client.rooms` as a compatibility alias.

```swift
let page = try await client.spaces.list(query: .init(max: 50))
for space in page.items {
    print(space.id, space.title ?? "(untitled)")
}

let allSpaces = try await client.spaces.listAll(query: .init(type: .group))
let created = try await client.spaces.create(.init(title: "Incident Review"))
let updated = try await client.spaces.update(
    spaceID: created.id,
    .init(title: "Incident Review - Closed")
)
try await client.spaces.delete(spaceID: updated.id)
```

For developers following Webex's endpoint reference, `client.rooms` maps to the
same implementation as `client.spaces`.

## Memberships

Memberships manage who belongs to a Webex space and whether a member is a
moderator.

```swift
let members = try await client.memberships.listAll(query: .init(roomID: spaceID))
let created = try await client.memberships.create(.init(
    roomID: spaceID,
    personEmail: "person@example.com"
))
let updated = try await client.memberships.update(
    membershipID: created.id,
    .init(isModerator: true)
)
try await client.memberships.delete(membershipID: updated.id)
```

## Examples

- `Examples/WebexClientSmoke`: interactive OAuth smoke test that uses the SDK-owned loopback listener, stores a registry account, exchanges an authorization code, creates `WebexClient`, and calls `people.me()`.
- `Examples/WebexSpacesListSmoke`: interactive OAuth smoke test that lists Spaces with `client.spaces.listAll(...)` using bounded pagination.
- `Examples/WebexMembershipsListSmoke`: interactive OAuth smoke test that lists Memberships for `WEBEX_ROOM_ID` with `client.memberships.listAll(...)` using bounded pagination.
