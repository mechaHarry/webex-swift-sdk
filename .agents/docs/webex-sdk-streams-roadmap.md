# Webex SDK Snapshot Streams Roadmap

Date captured: 2026-05-01

## Direction

The SDK should keep REST endpoint APIs wire-faithful and explicit. Public REST
groups should continue to mirror Webex endpoint behavior with request `Params`,
one-page `list(params:)` calls, and explicit `list(nextPage:)` pagination.

Snapshot Streams are a separate higher-level SDK layer for app/UI consumers that
need stable, refreshable state. A stream is not an endpoint-shaped helper and
must not hide full-collection fetches behind a name that looks like normal REST.
It owns local temporal state, reconciliation, and snapshot emission while still
using the endpoint-faithful REST APIs underneath.

## Why Streams Are Different From `listAll`

`listAll` was removed because it blurred the boundary between Webex REST
semantics and SDK convenience. Developers reading Webex docs would not see a
full-collection endpoint, and UI clients could accidentally request far more
data than needed.

A Snapshot Stream should be explicit about being stateful:

- it has a current snapshot
- it emits only reconciled snapshots
- it can refresh or load another page without clearing the current state
- it exposes pagination state instead of hiding pagination
- it can accept real-time invalidation triggers without changing the UI
  contract

## Delivery Order

1. Finish REST basics needed by a simple macOS client:
   - Spaces
   - Memberships
   - People
   - Messages
2. Add Snapshot Streams for the UI-critical groups:
   - `SpacesStream`
   - `MessagesStream`
   - `MembershipsStream`
3. Use the experimental native WebSocket realtime foundation now implemented:
   - `client.realtime.connect(options:)`
   - `WebexRealtimeConnection.events`
   - `WebexRealtimeConnection.triggers`
   - `WebexRealtimeConnection.states`
4. Keep webhooks as the official public `targetUrl` integration path.
5. Wire `connection.triggers` into existing streams in app examples.
6. Deprecate or disable cadenced polling once realtime triggers are reliable.
7. Continue REST coverage for broader API groups:
   - Attachments
   - Room Tabs
   - Teams
   - Team Memberships

## Stream Contract

Initial implementation status:

- `WebexSnapshotStream<Item>` owns local state and subscription fanout.
- `WebexStreamSnapshot<Item>` exposes items, revision, loading flags, last
  update time, last error, and pagination metadata.
- `WebexStreamPagination` exposes `hasMore`, `nextPage`, `pagesLoaded`,
  `pageLimit`, and `capReached`.
- `SpacesAPI.stream(params:pageLimit:)`, `MessagesAPI.stream(params:pageLimit:)`,
  and `MembershipsAPI.stream(params:pageLimit:)` adapt the existing endpoint
  wrappers without bypassing `WebexTransport`.
- Streams support explicit `refresh()`, `loadNextPage()`, and trigger-driven
  refresh hooks. They are snapshot/state streams, not pure realtime data
  sources.

A stream should expose immutable snapshots. The app/UI subscribes to snapshots
and redraws when a new snapshot is emitted.

Example shape:

```swift
for await snapshot in client.spaces.stream(params: .init(max: 20)).snapshots {
    await MainActor.run {
        model.spaces = snapshot.items
    }
}
```

Potential snapshot model:

```swift
public struct WebexStreamSnapshot<Item: Sendable>: Sendable {
    public let items: [Item]
    public let revision: UInt64
    public let lastUpdatedAt: Date?
    public let isRefreshing: Bool
    public let isLoadingNextPage: Bool
    public let lastError: WebexSDKError?
    public let pagination: WebexStreamPagination
}
```

Potential pagination model:

```swift
public struct WebexStreamPagination: Sendable {
    public let hasMore: Bool
    public let nextPage: WebexPageLink?
    public let pagesLoaded: Int
    public let pageLimit: Int?
    public let capReached: Bool
}
```

## Pagination Semantics

Do not overload the meaning of Webex `max`.

- `max: 20` means Webex page size: request up to 20 items per REST page.
- `pageLimit: 20` would mean stream safety cap: do not load more than 20 pages
  without explicit caller intent.

When the app first subscribes to a stream with `max: 20`, it may receive a
snapshot with 20 items and `pagination.hasMore == true`.

When the user scrolls near the bottom, the app can ask for more:

```swift
try await stream.loadNextPage()
```

The previous snapshot remains valid while the SDK fetches the next page. After
the new page is fetched and reconciled, the stream emits a new snapshot with the
combined state.

If all Webex pages have been consumed:

```swift
snapshot.pagination.hasMore == false
snapshot.pagination.nextPage == nil
```

If a configured page cap is reached while Webex still provides a next page:

```swift
snapshot.pagination.hasMore == true
snapshot.pagination.capReached == true
```

The SDK should expose that condition rather than silently hiding additional
remote data. If an app wants to go beyond the cap, it should make that explicit
by increasing the stream cap or calling an intentionally named API.

## Refresh And Reconciliation

While a stream refreshes, the old snapshot should remain usable. The stream
should not emit empty or partial arrays unless the actual reconciled state is
empty.

Basic reconciliation should handle:

- inserted items
- removed items
- updated items
- reordered items, according to the stream's configured sort semantics
- pagination reset when a refresh invalidates previous `nextPage` links

The stream should coalesce overlapping refresh requests and avoid concurrent
fetch stampedes.

## Trigger Sources

Streams should be designed around trigger injection from the start.

Initial implementation may support:

- manual refresh
- `loadNextPage()`
- `connection.triggers` from an experimental `WebexRealtimeConnection`
- webhook invalidation for public target URL-based integrations
- provisional cadenced polling only if needed for a usable early UI

Polling is not the strategic real-time design. Treat it as temporary and avoid
marketing or docs that call polling-backed streams "real-time".

These triggers should notify the stream to refresh or reconcile. They should not
be the UI-facing data contract by themselves.

The WebSocket implementation is the current experimental app-friendly realtime
foundation. It is receive-only, sample-backed, and not an official replacement
for documented REST endpoints. Webhooks remain relevant when an integration
needs Webex to deliver events to a public `targetUrl`.

## Naming

Use names that communicate state, not REST endpoint behavior:

- `SpacesStream`
- `MessagesStream`
- `MembershipsStream`
- `WebexStreamSnapshot`
- `WebexStreamPagination`

Avoid names that imply a hidden REST operation:

- `listAll`
- `queryAll`
- `listPages`
- generic iterable wrappers that look like Webex endpoint semantics

Even with WebSocket triggers available, describe this layer as "snapshot
streams" or "state streams", not "real-time streams".

## API Group Fit

Good initial stream candidates:

- Spaces: high-value for app sidebars and recent activity views.
- Messages: high-value once Messages REST support exists.
- Memberships: useful when scoped to a selected space.

Limited stream candidates:

- People: useful for local detail/search caches, but less central as a live list
  unless attached to memberships, messages, or search UI.

Not a stream candidate:

- OAuth/token lifecycle. Auth remains infrastructure used by streams and REST
  APIs, not a stream of domain data.

## Security And Backoff

Streams must use the existing authenticated REST transport and inherit its
retry/backoff behavior. They should not bypass `WebexTransport`.

Snapshots and errors must not expose tokens, authorization codes, refresh
tokens, client secrets, or full callback URLs. Domain data such as space titles,
person names, and message content should be treated as user data and only
emitted to the local app subscriber.

## Next Steps

1. Validate the live `Examples/WebexRealtimeEventsSmoke` flow with credentials.
2. Wire `connection.triggers` into Snapshot Streams in app examples.
3. Keep polling deprecated or temporary while realtime validation continues.
4. Continue broader REST group coverage after the stream trigger path is proven.
