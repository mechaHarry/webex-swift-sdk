# Enriched Spaces Snapshot Smoke Design

## Goal

Add a native macOS smoke app that visually demonstrates enriched `SpacesStream`
snapshots. The smoke should make it obvious that each `WebexSpace` item keeps
its original wire-faithful fields while also carrying SDK-derived enrichment
through ergonomic fields such as `item.enriched.teamName` and
`item.enriched.spaceAvatar`.

The smoke is snapshot-focused. It does not need a realtime WebSocket connection.
Production apps can still wire realtime events into `SpacesStream.refreshOnTriggers`
and receive the same enriched snapshots after those refreshes.

## Non-Goals

- Do not add direct REST follow-up calls in the UI or smoke app.
- Do not build a general-purpose spaces management app.
- Do not add realtime trigger setup to this smoke.
- Do not mutate spaces, teams, memberships, or people data.

## User Experience

Create a new native SwiftUI example named `WebexSpacesEnrichedSnapshotSmoke`.

The window uses a two-pane layout:

- Left pane: a list of spaces from the current snapshot.
- Right pane: selected-space detail split into wire data and enriched data.

The toolbar/header includes:

- `Refresh Spaces`: calls `SpacesStream.refresh()`.
- `Refresh Enrichment`: calls `SpacesStream.refreshEnrichment()`.
- `Load More`: calls `SpacesStream.loadNextPage()` when pagination allows.
- Snapshot status text: revision, last updated time, refresh/loading state, and
  pagination state.

Rows should be compact and scannable. Each row should show:

- title or a placeholder
- space type
- enrichment status
- team name when present
- avatar availability for direct spaces

The detail pane should show two clearly separated sections:

- Wire-faithful `WebexSpace` fields:
  - `id`
  - `title`
  - `type`
  - `teamID`
  - `isLocked`
  - `isReadOnly`
  - `isAnnouncementOnly`
  - `lastActivity`
  - `created`
- SDK-derived enriched fields:
  - `enriched.teamName`
  - `enriched.spaceAvatar`
  - `enriched.status`
  - `enriched.errors`

The UI should use native SwiftUI controls and system images. It should use
placeholders for missing fields rather than empty gaps.

## Architecture

Follow the existing window-smoke organization used by the message stream
examples:

- `EnrichedSpacesSmokeConfiguration`
  - Parses environment variables.
  - Builds `WebexIntegrationConfiguration`.
  - Builds `ListSpacesParams`.
- `EnrichedSpacesBootstrap`
  - Creates `URLSessionHTTPClient`, `KeychainWebexStore`, and
    `WebexClientRegistry`.
  - Authorizes and creates a `WebexClient`.
  - Creates `client.spaces.stream(params:pageLimit:)`.
- `EnrichedSpacesRuntime`
  - Holds the `SpacesStream`.
  - Exposes cancellation if needed by the window model.
- `EnrichedSpacesWindowModel`
  - Subscribes to `stream.snapshots`.
  - Maps snapshots to view models.
  - Exposes refresh, enrichment refresh, and load-more commands.
- `EnrichedSpaceRowModel`
  - Compact list-row representation.
- `EnrichedSpaceDetailModel`
  - Selected-space comparison data for wire and enriched fields.
- SwiftUI views
  - Main content view.
  - List row view.
  - Detail comparison view.

The SwiftUI layer should only consume `SpacesStream` snapshots through the
window model. It must not call `client.teams`, `client.people`, or
`client.memberships` directly.

## Environment

Required:

- `WEBEX_CLIENT_ID`
- `WEBEX_CLIENT_SECRET`

Optional:

- `WEBEX_REDIRECT_URI`
  - Defaults to `http://127.0.0.1:8282/oauth/callback`.
- `WEBEX_SCOPES`
  - Defaults to the REST scopes needed for base spaces and enrichment:
    `spark:rooms_read spark:memberships_read spark:people_read`.
  - If Webex requires a separate teams read scope for the current tenant, the
    smoke README should tell users to add it through `WEBEX_SCOPES`.
- `WEBEX_SPACES_PAGE_SIZE`
  - Defaults to `25`.
- `WEBEX_SPACES_STREAM_PAGE_LIMIT`
  - Defaults to `1`.
- `WEBEX_SPACES_TYPE`
  - Optional `direct` or `group` filter.
- `WEBEX_SPACES_TEAM_ID`
  - Optional team filter.
- `WEBEX_SPACES_SORT_BY`
  - Optional `id`, `lastactivity`, or `created`.
- `WEBEX_KEYCHAIN_SERVICE`
  - Defaults to `com.webex.swift-sdk.spaces-enriched-snapshot-smoke`.

## Data Flow

1. App starts and parses configuration.
2. Bootstrap authorizes and creates a `WebexClient`.
3. Bootstrap creates a `SpacesStream`.
4. Window model subscribes to `stream.snapshots`.
5. Window model calls `stream.refresh()` once after startup.
6. Each snapshot updates:
   - rows
   - selected detail
   - revision and update metadata
   - loading/refreshing flags
   - pagination state
   - snapshot-level error text
7. `Refresh Enrichment` calls `stream.refreshEnrichment()` without reloading the
   base spaces page.
8. Enrichment failures stay item-scoped and appear in the enriched section.

## Error Handling And Security

- Startup/configuration errors should show a concise native failure state.
- Snapshot-level errors should appear in a non-disruptive status area.
- Item enrichment errors should appear only in the selected item enriched pane.
- Error text must use SDK-safe descriptions and must not expose OAuth callback
  codes, access tokens, client secrets, or refresh tokens.
- Invalid environment values should not echo sensitive raw inputs.
- The window model should cancel subscription tasks in `deinit`.

## Testing

Add focused tests for the example target:

- Configuration requires credentials.
- Configuration defaults match the documented values.
- Configuration applies page size, page limit, scope, sort, type, team, redirect,
  and keychain overrides.
- Invalid environment values return safe errors.
- Row model maps wire fields and enrichment summary correctly.
- Detail model separates wire-faithful fields from enriched fields.
- Window model applies snapshots, preserves selection where possible, and exposes
  refresh/enrichment/load-more commands through an injectable runtime or stream
  boundary.

Run example-specific tests with:

```bash
cd Examples/WebexSpacesEnrichedSnapshotSmoke
swift test
```

Also run the root package tests after implementation:

```bash
swift test
```

## Documentation

Add an example README that explains:

- required Webex redirect URI
- required and optional environment variables
- default scopes
- what the window is proving
- how `Refresh Spaces` differs from `Refresh Enrichment`
- why realtime is not included in this smoke
- how an app can still use realtime triggers with enriched snapshots through
  `SpacesStream.refreshOnTriggers(...)`

Update the root README examples list with the new smoke app.
