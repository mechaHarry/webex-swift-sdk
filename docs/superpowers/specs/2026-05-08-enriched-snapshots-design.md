# Webex Enriched Snapshots Design

Date: 2026-05-08

## Purpose

Snapshot streams are the SDK layer for app-facing state. They already own
pagination, refresh, reconciliation, and realtime-trigger invalidation while
keeping REST API wrappers wire-faithful. This design extends the spaces snapshot
stream with item-level enrichment: details that are not returned by the original
spaces list call, but are useful for UI rows and can be derived through bounded
follow-up REST calls.

The first concrete enrichments are:

- `teamName`: the team display name for spaces with `teamId`.
- `spaceAvatar`: the other person's avatar for direct spaces.

The UI should be able to read these values directly from each snapshot item:

```swift
space.enriched.teamName
space.enriched.spaceAvatar
```

The UI should not need a separate ID lookup map, and direct REST calls should
not perform hidden enrichment work.

## Existing Baseline

- `WebexSnapshotStream<Item>` owns generic stream state and emits
  `WebexStreamSnapshot<Item>` values.
- `SpacesAPI.stream(params:pageLimit:)` currently adapts `SpacesAPI.list`
  into a generic snapshot stream.
- `WebexSpace` mirrors the Webex `/v1/rooms` response and includes `teamID`,
  `type`, `title`, timestamps, and partial resource `errors`.
- `PeopleAPI` already supports `me()` and `get(personID:)`.
- `MembershipsAPI` already supports `list(params:)`, including filtering by
  `roomID`.
- The SDK does not yet include a Teams API group.

## Public API Shape

`WebexSpace` gains an SDK-owned enrichment field:

```swift
public struct WebexSpace: Equatable, Decodable, Sendable {
    public let id: String
    public let title: String?
    public let type: WebexSpaceType?
    public let teamID: String?
    public let enriched: WebexSpaceEnrichment
}
```

`enriched` is not a Webex REST field. The `WebexSpace` decoder initializes it to
`.empty`, and the direct REST functions leave it empty:

```swift
try await client.spaces.list(...)
try await client.spaces.get(...)
```

The spaces stream enriches by default:

```swift
let stream = client.spaces.stream(params: .init(sortBy: .lastActivity, max: 50))
for await snapshot in stream.snapshots {
    let avatar = snapshot.items.first?.enriched.spaceAvatar
}
```

`SpacesStream` becomes a named type instead of a typealias so it can expose
enrichment controls:

```swift
public final class SpacesStream: Sendable {
    public var snapshots: AsyncStream<WebexStreamSnapshot<WebexSpace>> { get }

    public func currentSnapshot() async -> WebexStreamSnapshot<WebexSpace>
    public func refresh() async
    public func loadNextPage() async
    public func refreshEnrichment() async
    public func refreshOnTriggers(
        _ triggers: AsyncStream<WebexStreamTrigger>,
        where shouldRefresh: @escaping @Sendable (WebexStreamTrigger) -> Bool
    ) -> Task<Void, Never>
}
```

`refresh()` reloads the base spaces list, emits a base snapshot promptly, and
then schedules enrichment. `refreshEnrichment()` does not reload spaces. It
invalidates or bypasses enrichment cache entries for the currently loaded items,
runs enrichment again, and emits a new snapshot when item enrichment changes.

`RoomsStream` remains an alias to `SpacesStream`. `MessagesStream` and
`MembershipsStream` can remain generic stream typealiases in this version.

## Enrichment Models

`WebexSpaceEnrichment` is compact and field-oriented:

```swift
public struct WebexSpaceEnrichment: Equatable, Sendable {
    public let teamName: String?
    public let spaceAvatar: String?
    public let status: WebexSpaceEnrichmentStatus
    public let errors: [WebexSpaceEnrichmentError]
}

public enum WebexSpaceEnrichmentStatus: Equatable, Sendable {
    case empty
    case loading
    case partial
    case complete
    case failed
}

public enum WebexSpaceEnrichmentField: Equatable, Sendable {
    case teamName
    case spaceAvatar
}

public struct WebexSpaceEnrichmentError: Equatable, Sendable {
    public let field: WebexSpaceEnrichmentField
    public let error: WebexSDKError
}
```

Status semantics:

- `.empty`: no enrichment applies or no enrichment has been attempted.
- `.loading`: at least one applicable enrichment field is being fetched.
- `.partial`: at least one applicable field succeeded and at least one failed.
- `.complete`: all applicable enrichment fields succeeded or resolved to a
  known absent value.
- `.failed`: all applicable enrichment fields failed.

For group spaces without `teamID`, `teamName` does not apply. For group spaces,
`spaceAvatar` does not apply in this version because the Rooms API does not
provide a room avatar source. For direct spaces, `spaceAvatar` applies and is
resolved from the other person's People avatar.

## Teams API

The first enrichment requires a Teams API group:

```swift
public struct WebexTeam: Equatable, Decodable, Sendable {
    public let id: String
    public let name: String?
    public let creatorID: String?
    public let created: Date?
}

public struct TeamsAPI: Sendable {
    public func get(teamID: String) async throws -> WebexTeam
}
```

`TeamsAPI` follows the existing REST wrapper pattern:

- Use `WebexTransport`.
- Percent-encode path IDs.
- Decode Webex timestamps with `WebexDateDecoding`.
- Surface Webex errors through the existing transport error mapping.
- Add `client.teams` to `WebexClient`.

List, create, update, and delete team operations are outside this design. The
enrichment only needs `GET /v1/teams/{teamId}`.

## Data Flow

The spaces stream is a projection over the existing base stream:

```text
Spaces REST list/get page
        |
        v
Base WebexSnapshotStream<WebexSpace>
        |
        v
SpacesStream enrichment coordinator
        |
        v
WebexStreamSnapshot<WebexSpace> with item.enriched values
```

For each base spaces snapshot:

1. Build an immediate stream snapshot from the base items, keeping
   `snapshot.lastError`, pagination, loading flags, revision, and timestamps
   from the base stream.
2. Apply cached enrichment synchronously where available. For applicable
   uncached fields, set item enrichment status to `.loading`. For fields that
   do not apply, keep the field nil without adding an error.
3. Emit that immediate snapshot without waiting for remote enrichment calls.
4. Extract unique lookup keys:
   - `teamID` for team names.
   - direct `space.id` for membership lookup.
   - other-person `personID` for avatar lookup.
5. Start missing lookups with bounded concurrency.
6. Apply resolved enrichment by copying each `WebexSpace` with updated
   `enriched`.
7. Emit a follow-up snapshot when any enriched field, status, or field error
   changes.

The stream preserves the current base snapshot while enrichment runs. Slow or
failed enrichment calls must not clear `snapshot.items`.

## Direct Space Avatar Flow

Direct-space `spaceAvatar` uses accurate follow-up lookups:

```text
direct WebexSpace
        |
        v
memberships.list(roomID: space.id)
        |
        v
people.me() or cached self person ID
        |
        v
choose non-self membership.personID
        |
        v
people.get(personID:)
        |
        v
WebexPerson.avatar
```

The self person ID should be cached per `SpacesStream` instance. Memberships
and people results should also be cached by room ID and person ID. If a direct
space does not expose enough membership/person information to identify the
other person, `spaceAvatar` resolves to nil with a field error describing the
missing prerequisite.

## Cache Policy

The enrichment cache is in-memory and stream-owned in this version. It is not a
new persistent store and is not shared across app launches.

Cache entries should be keyed by the source identifier that controls the value:

- team name by `teamID`
- self person by current authenticated account for the stream instance
- direct-space other-person ID by `space.id`
- person avatar by `personID`

Normal refreshes and page loads reuse cached values. `refreshEnrichment()`
bypasses or invalidates cache entries for currently loaded items, reruns the
follow-up requests, and emits a snapshot if enrichment changes.

The cache may store known-absent values such as a person with no avatar. It may
also store field failures briefly within the stream instance to avoid a tight
failure loop during a single enrichment pass, but manual refresh must be able to
retry them.

## Error Handling And Backoff

All enrichment REST calls must go through the existing public API groups and
`WebexTransport`. That preserves:

- authenticated requests
- token refresh and invalidation
- graceful retry/backoff for retryable failures
- `Retry-After` handling
- cancellation
- error redaction

Base stream errors remain on `snapshot.lastError`. Enrichment errors stay on
the affected item:

```swift
space.enriched.errors
```

This keeps the UI able to show loaded spaces while displaying placeholders or a
retry affordance for enrichment fields that failed.

## Concurrency And Cancellation

The enrichment coordinator should be an actor or actor-backed type. It owns the
cache, tracks the latest base snapshot generation, and ignores stale enrichment
results from older generations.

Follow-up REST calls must be bounded. The implementation can use a small
internal async semaphore or structured task scheduling to prevent refreshes from
issuing one request per visible item at once. This matters because direct-space
avatars can require multiple calls per space.

When a newer base snapshot arrives, older in-flight enrichment work should be
cancelled where practical or ignored when it completes. When the stream
terminates, enrichment work should stop.

## Security And Privacy

Enrichment must not leak tokens, authorization callbacks, or raw transport
internals in errors. Any stored error must be a redacted `WebexSDKError`.

Avatar URLs and team names are user-visible Webex profile/team data. They
should live only in memory in this version. The design does not introduce a
persistent cache, filesystem writes, or cross-account sharing.

## Testing Requirements

Unit tests should cover:

- `TeamsAPI.get(teamID:)` decodes known fields.
- `TeamsAPI.get(teamID:)` percent-encodes path IDs.
- `WebexClient` exposes `teams`.
- `WebexSpace` decodes REST JSON with `enriched == .empty`.
- Direct `spaces.list` and `spaces.get` return empty enrichment without hidden
  Teams, Memberships, or People calls.
- `SpacesStream` emits a base snapshot before enrichment completes.
- `SpacesStream` emits an enriched follow-up snapshot for `teamName`.
- `teamName` lookup is cached across ordinary refreshes.
- `spaceAvatar` for direct spaces lists memberships, excludes `people.me().id`,
  fetches the other person, and uses `WebexPerson.avatar`.
- Enrichment failures are attached to `space.enriched.errors` and do not set
  `snapshot.lastError`.
- `refreshEnrichment()` bypasses or invalidates cache for loaded items and
  emits refreshed enrichment data.
- Stale enrichment results from older snapshots do not overwrite newer
  snapshots.
- Bounded concurrency can be verified at the enrichment dependency boundary.

Smoke or integration tests can later validate live team and direct-space avatar
behavior, but the first implementation should be covered with deterministic
unit tests using mock HTTP clients.

## Non-Goals

- No hidden enrichment work in direct REST methods such as `spaces.list` or
  `spaces.get`.
- No enrichment for `MessagesStream`, `MembershipsStream`, or
  `MessagesThreadStream` in this version.
- No SDK-wide persistent enrichment cache.
- No group-space avatar lookup unless Webex exposes a documented source.
- No Teams list/create/update/delete coverage unless requested separately.
- No UI refresh button implementation in the SDK; the SDK exposes
  `refreshEnrichment()` so clients can wire their own controls.
