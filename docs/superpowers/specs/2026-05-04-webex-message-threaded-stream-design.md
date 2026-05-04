# Webex Message Threaded Stream Design

Date: 2026-05-04

## Purpose

Webex messages are not only a flat chronological list. A message may reference
another message through `parentId`, which means consumers need both chronological
message order and parent/child thread structure. The SDK should own the durable
data projection because `parentId`, deleted or inaccessible parents,
pagination, refresh, and realtime invalidation are Webex data semantics. The
macOS app should own visual state such as expansion, selection, indentation, and
scroll position.

This design adds an optional threaded variant for realtime consumption while
preserving the current flat `MessagesStream`.

## Existing Baseline

- `ListMessagesParams` already exposes Webex `parentId`.
- `WebexMessage` already preserves the documented `parentId` response field.
- `MessagesStream` currently emits flat `WebexStreamSnapshot<WebexMessage>`
  values and supports manual refresh, explicit pagination, and realtime trigger
  refresh through `refreshOnTriggers`.
- The flat stream remains useful for simple chronological views and for
  endpoint-shaped REST semantics.

## Public API Shape

Keep the current flat stream:

```swift
let flat = client.messages.stream(params: .init(roomID: roomID, max: 50))
```

Add a threaded variant:

```swift
let threaded = client.messages.threadedStream(params: .init(roomID: roomID, max: 50))
```

The threaded stream emits immutable snapshots:

```swift
public struct WebexMessageThreadSnapshot: Sendable {
    public let topLevelMessageIDs: [String]
    public let threadEntryByID: [String: WebexMessageThreadEntry]
    public let chronologicalMessageIDs: [String]
    public let revision: UInt64
    public let lastUpdatedAt: Date?
    public let isRefreshing: Bool
    public let isLoadingNextPage: Bool
    public let lastError: WebexSDKError?
    public let pagination: WebexStreamPagination
}
```

Each entry is normalized around Webex message IDs:

```swift
public struct WebexMessageThreadEntry: Sendable {
    public let id: String
    public let message: WebexMessage?
    public let parentID: String?
    public let childIDs: [String]
    public let effectiveCreated: Date?
    public let isPlaceholderParent: Bool
}
```

`threadEntryByID` is the single authoritative lookup index. There is no separate
public `messageByID` because `entry.message` already contains the loaded
`WebexMessage`. There is no separate public `childrenByParentID` because
`threadEntryByID[parentID]?.childIDs` provides O(1) parent lookup and then the
expected O(k) traversal of that parent's children.

## Naming Semantics

Public naming should align with Webex REST semantics:

- Use `parentID` because Webex exposes `parentId`.
- Use `childIDs` for messages that reference a parent.
- Use `topLevelMessageIDs` for entries with no known loaded parent in the
  current snapshot.
- Avoid public names such as `root` and `node` unless they are internal
  implementation details. A top-level entry may be a normal message with no
  parent, or a placeholder parent created because its children reference an ID
  that is not loaded.

## Placeholder Parents

When a loaded message references a `parentId` that is not present in the current
snapshot, the SDK creates a placeholder parent entry:

- `id` is the referenced parent ID.
- `message` is `nil`.
- `parentID` is `nil` because the SDK cannot infer a higher parent without the
  parent message record.
- `childIDs` contains the loaded children in chronological order.
- `isPlaceholderParent` is `true`.
- `effectiveCreated` is inherited from the least-recent descendant with a known
  timestamp.

This covers deleted parents, inaccessible parents, and parents not loaded due to
pagination. The SDK should not label the parent as deleted; it only knows that
the parent message content is absent from the current data set.

If a later refresh or page load includes the real parent message, the placeholder
entry is replaced by a normal entry with `message != nil` while preserving its
children.

The first implementation should not issue hidden `messages.get(parentID:)`
requests to hydrate missing parents. Hidden parent hydration can multiply REST
traffic and surprise app authors. A future explicit option may add that behavior
with bounded concurrency and clear error reporting.

## Ordering

The threaded projection should provide stable chronological ordering. In this
design, chronological means least-recent to most-recent by effective timestamp:

- `chronologicalMessageIDs` contains loaded real message IDs only.
- `topLevelMessageIDs` contains visible top-level thread entry IDs.
- `childIDs` on each entry are ordered by `effectiveCreated`.
- Real message entries use `message.created` as `effectiveCreated`.
- Placeholder parents use the least-recent known descendant timestamp as
  `effectiveCreated`.
- Ties are broken by ID for deterministic snapshots.

The existing flat `MessagesStream` remains the source for apps that need the
raw loaded message order. The threaded projection is allowed to sort by
timestamps so the parent/child structure remains stable across refreshes and
pagination.

## Construction Algorithm

For each flat `WebexStreamSnapshot<WebexMessage>`:

1. Index loaded messages by ID.
2. Create an entry for every loaded message.
3. Read every loaded `parentId` and create placeholder parent entries for
   referenced IDs that are absent.
4. Attach every message or placeholder to its known parent entry when possible.
5. Compute `effectiveCreated` bottom-up. Placeholder parents inherit the
   least-recent descendant timestamp.
6. Sort `topLevelMessageIDs`, `childIDs`, and `chronologicalMessageIDs`.
7. Emit one immutable `WebexMessageThreadSnapshot` with copied stream metadata:
   revision, update flags, last error, and pagination.

The implementation must guard against malformed data such as self-parenting or
cycles. If a cycle is detected, break the cycle deterministically and keep all
entries addressable through `threadEntryByID`.

## Data Flow

The threaded stream should be a projection over the flat stream rather than a
separate REST implementation:

```text
Messages REST + realtime triggers
        |
        v
MessagesStream: WebexStreamSnapshot<WebexMessage>
        |
        v
Thread projection builder
        |
        v
WebexMessageThreadSnapshot
```

Realtime still enters through `WebexRealtimeConnection.triggers`. A matching
trigger refreshes the underlying flat stream, and the threaded projection emits
after the flat stream emits a reconciled snapshot. The app subscribes to either
flat or threaded snapshots depending on its view.

## Ownership Boundary

The SDK owns:

- parent/child indexing
- placeholder parent materialization
- O(1) entry lookup
- recursive arbitrary-depth thread construction
- effective timestamp computation
- snapshot emission from flat stream state
- pagination and refresh metadata forwarding

The macOS app owns:

- expanded or collapsed thread state
- selected message state
- scroll position
- visual indentation
- rendering policy for placeholder parents
- filtering or hiding placeholder parents in a specific view

## Error Handling And Safety

- Building a threaded snapshot should not throw for ordinary partial data.
- Missing parents become placeholder entries.
- Missing timestamps produce `effectiveCreated == nil`; nil values sort after
  known timestamps with ID tie-breaking.
- Cycles and self-parenting are treated as malformed remote data and broken
  deterministically without dropping entries.
- Snapshot errors from the underlying stream are forwarded through `lastError`.
- SDK-generated errors must continue to redact tokens, secrets, callback URLs,
  and transport internals.

## Performance

Thread snapshot construction is O(n log n) for sorting loaded entries and O(n)
for indexing and linking. Runtime lookup is O(1) by message ID through
`threadEntryByID`. Child traversal is O(k) for k children, which is unavoidable
for rendering those children.

The snapshot should avoid redundant public maps. `threadEntryByID` owns the
loaded message reference and the child list. This keeps memory use predictable
and avoids conflicting sources of truth.

## Testing Requirements

Unit tests should cover:

- flat top-level messages with no parents
- one-level replies
- arbitrary-depth nesting
- placeholder parent creation when the parent message is missing
- replacement of a placeholder when the real parent arrives later
- ordering of placeholder parents by least-recent descendant timestamp
- deterministic tie-breaking by ID
- O(1) lookup shape through `threadEntryByID`
- pagination metadata forwarding from the flat snapshot
- refresh/loading/error metadata forwarding
- cycle and self-parent handling without infinite recursion
- realtime-trigger integration through the existing flat stream refresh path

## Non-Goals

- No replacement of `MessagesStream`.
- No hidden full-history fetching.
- No hidden parent hydration through `messages.get` in the first version.
- No app UI state such as expansion, selection, unread separators, or scroll
  anchoring.
- No persistence or cross-launch cache.
