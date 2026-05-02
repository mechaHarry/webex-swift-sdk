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
- typed People, Spaces, Memberships, and Messages APIs

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
let page = try await client.spaces.list(params: .init(max: 50))
for space in page.items {
    print(space.id, space.title ?? "(untitled)")
}

if let nextPage = page.nextPage {
    let next = try await client.spaces.list(nextPage: nextPage)
    print("Fetched another \(next.items.count) spaces")
}

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

Use `spark:memberships_read` for list/get calls and `spark:memberships_write`
for create/update/delete calls.

```swift
let members = try await client.memberships.list(params: .init(roomID: spaceID, max: 50))
for member in members.items {
    print(member.id, member.personDisplayName ?? member.personEmail ?? "(unknown)")
}

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

## People

People reads are available through `client.people`. Use `spark:people_read` for
normal search/detail reads and `spark-admin:people_read` for org-wide listing.

```swift
let me = try await client.people.me()
let people = try await client.people.list(params: .init(id: me.id, excludeStatus: true))
print(people.items.first?.displayName ?? me.id)
```

## Messages

Messages are available through `client.messages`. Use `spark:messages_read` for
list/get calls and `spark:messages_write` for create/edit/delete calls.

```swift
let page = try await client.messages.list(params: .init(roomID: spaceID, max: 25))
for message in page.items {
    print(message.id, message.text ?? message.markdown ?? "(no text)")
}

if let nextPage = page.nextPage {
    let olderMessages = try await client.messages.list(nextPage: nextPage)
    print("Fetched another \(olderMessages.items.count) messages")
}

let created = try await client.messages.create(.init(
    roomID: spaceID,
    markdown: "**Status:** investigating"
))
let edited = try await client.messages.edit(
    messageID: created.id,
    .init(roomID: spaceID, markdown: "**Status:** resolved")
)
try await client.messages.delete(messageID: edited.id)
```

## Examples

- `Examples/WebexClientSmoke`: interactive OAuth smoke test that uses the SDK-owned loopback listener, stores a registry account, exchanges an authorization code, creates `WebexClient`, and calls `people.me()`.
- `Examples/WebexPeopleReadSmoke`: interactive OAuth smoke test that reads the current person and performs a bounded People list lookup.
- `Examples/WebexSpacesListSmoke`: interactive OAuth smoke test that lists Spaces with explicit bounded pagination.
- `Examples/WebexMembershipsListSmoke`: interactive OAuth smoke test that lists Memberships for `WEBEX_ROOM_ID` with explicit bounded pagination.
- `Examples/WebexMessagesListSmoke`: interactive OAuth smoke test that lists Messages for `WEBEX_ROOM_ID` with explicit bounded pagination.
