# webex-swift-sdk

Swift-first macOS SDK for Webex Developer APIs.

## Current Scope

This package provides the OAuth and authenticated REST foundation:

- user-provided Webex integration credentials
- PKCE authorization request support
- Apple-native browser auth boundary
- SDK-owned loopback redirect listener on `127.0.0.1:8282`
- automatic Keychain-backed credential and refresh-token storage
- memory-only access-token cache by default
- coordinated token refresh
- authenticated REST transport
- typed People, Spaces, Memberships, and Messages APIs
- snapshot streams for Spaces, Memberships, and Messages
- experimental receive-only realtime WebSocket events and stream triggers

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

## Snapshot Streams

Snapshot streams are a stateful SDK layer over the wire-faithful REST APIs. They
keep the previous snapshot visible while a refresh or next-page load is running,
then emit a reconciled snapshot when the SDK has new data. They are not
documented as real-time streams until Webex push/event triggers are implemented.

```swift
let stream = client.spaces.stream(
    params: .init(sortBy: .lastActivity, max: 20),
    pageLimit: 5
)

Task {
    for await snapshot in stream.snapshots {
        print(snapshot.items.map(\.title))
        print("refreshing:", snapshot.isRefreshing)
        print("has more:", snapshot.pagination.hasMore)
    }
}

await stream.refresh()

let snapshot = await stream.currentSnapshot()
if snapshot.pagination.hasMore, !snapshot.pagination.capReached {
    await stream.loadNextPage()
}
```

The `max` parameter remains the Webex REST page size. The stream `pageLimit`
is only a local safety cap for how many pages explicit `loadNextPage()` calls
may accumulate before the stream reports `pagination.capReached`.

Space streams enrich each `WebexSpace` item with SDK-derived details such as
`item.enriched.teamName` and `item.enriched.spaceAvatar`. Direct REST calls
remain wire-faithful: `client.spaces.list` and `client.spaces.get` do not make
follow-up enrichment calls and decode `space.enriched == .empty`. Use
`await stream.refreshEnrichment()` to refresh cached enrichment details without
reloading the base spaces page.

Migration note: `SpacesStream` is now a named stream wrapper instead of an alias
to `WebexSnapshotStream<WebexSpace>`, and `RoomsStream` aliases `SpacesStream`.
Existing client code that consumes `stream.snapshots`, `currentSnapshot()`,
`refresh()`, `loadNextPage()`, or `refreshOnTriggers` can keep those calls. Code
that constructed `WebexSnapshotStream<WebexSpace>` directly or accepted that
concrete generic type should accept `SpacesStream`/`RoomsStream` instead.

## Realtime

Realtime support is an experimental Swift-native WebSocket listener exposed
through `client.realtime`. It is receive-only: use REST APIs for writes and
detail fetches, and use realtime events as triggers for refreshing SDK Snapshot
Streams or app state.

```swift
let connection = client.realtime.connect()

Task {
    for await state in connection.states {
        print(state)
    }
}

Task {
    for await event in connection.events {
        print(event.resource, event.event, event.decodeStatus)
    }
}
```

For realtime OAuth, the Webex token must be granted `spark:all` and
`spark:kms`. A host macOS app should set those scopes directly in
`WebexIntegrationConfiguration`; shell variables such as `WEBEX_SCOPES` are
only for examples.

```swift
let configuration = WebexIntegrationConfiguration(
    clientID: userProvidedClientID,
    clientSecret: userProvidedClientSecret,
    redirectURI: URL(string: "http://127.0.0.1:8282/oauth/callback")!,
    scopes: ["spark:all", "spark:kms"],
    prefersEphemeralWebBrowserSession: false
)
```

The token response's granted scopes are authoritative. If Webex grants only a
narrow REST scope such as `spark:people_read`, REST People calls can still work
while realtime WDM device registration fails with HTTP 403. After changing
integration scopes in Webex, reauthorize so the new grants are present in the
stored token record.

Realtime event ACKs use the Mercury frame id, while event `resourceID` remains
the REST resource id that apps use for follow-up API calls. The
`WebexRealtimeEventsSmoke` output includes both fields for protocol debugging.
The smoke also enables `WebexRealtimeOptions.diagnosticHandler`, so it prints
decoded event metadata, filtered-event decisions, ACK failures, frame decode
failures, and reconnect reasons without dumping raw payloads by default. These
diagnostics include Mercury source metadata such as `sourceEventType`,
`activityVerb`, and `objectType` when available.
The WebSocket transport prepares the WDM URL with text wire-format query
parameters before connecting; using the raw WDM URL can make Webex send binary
frames that the JSON event layer cannot decode.

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

## Teams

Teams are available through `client.teams`. Use the documented Teams API for
creating, listing, fetching, renaming, and deleting teams.

```swift
let team = try await client.teams.create(.init(name: "Incident Response"))
let teams = try await client.teams.list(params: .init(max: 25))

let renamed = try await client.teams.update(
    teamID: team.id,
    .init(name: "Incident Response - Archive")
)

try await client.teams.delete(teamID: renamed.id)
```

Team memberships are available through `client.teamMemberships`:

```swift
let member = try await client.teamMemberships.create(.init(
    teamID: team.id,
    personEmail: "person@example.com",
    isModerator: true
))

let members = try await client.teamMemberships.list(params: .init(teamID: team.id, max: 50))
let updatedMember = try await client.teamMemberships.update(
    teamMembershipID: member.id,
    .init(isModerator: false)
)
try await client.teamMemberships.delete(teamMembershipID: updatedMember.id)
```

Team spaces use the existing Spaces API. List spaces for a team with
`ListSpacesParams(teamID:)` or create a team space by setting `teamID` in
`CreateSpaceRequest`. Webex does not document moving a space between teams or
removing a space from a team after creation.

```swift
let teamSpaces = try await client.spaces.list(params: .init(teamID: team.id, max: 25))
let newTeamSpace = try await client.spaces.create(.init(
    title: "Incident Review",
    teamID: team.id
))
```

`WebexTeam` and `WebexTeamMembership` preserve returned-but-undocumented JSON
fields in `additionalFields`. This is useful for inspecting wire-faithful
metadata such as future visual or lifecycle fields, but the SDK only exposes
documented team writes as typed request properties.

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
- `Examples/WebexMessagesStreamWindowSmoke`: native SwiftUI smoke window that subscribes to `MessagesStream` snapshots and auto-refreshes the stream from realtime message triggers.
- `Examples/WebexSpacesEnrichedSnapshotSmoke`: native SwiftUI smoke window that compares wire-faithful Spaces snapshot fields with SDK-derived `item.enriched` fields.
- `Examples/WebexRealtimeEventsSmoke`: interactive OAuth or direct-token smoke test that connects to Webex realtime, validates granted realtime scopes in OAuth mode, and prints connection states/events.
