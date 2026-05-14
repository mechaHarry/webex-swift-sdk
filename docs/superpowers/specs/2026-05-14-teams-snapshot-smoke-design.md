# Teams Snapshot Smoke Design

## Goal

Add Teams snapshot stream support and a native macOS smoke app that displays all
parsed fields from a list of `WebexTeam` items in snapshot format. The smoke
should make it easy to inspect documented fields and any returned-but-
undocumented fields captured in `additionalFields`.

This answers two questions directly:

- Teams does not currently have a dedicated convenience snapshot stream. The
  generic `WebexSnapshotStream<Item>` can already represent teams, but this work
  will add the missing `TeamsAPI.stream(...)` helper.
- No live undocumented team fields have been discovered by this branch yet. The
  SDK now preserves them when Webex returns them; this smoke is the tool for
  observing actual tenant responses.

## Non-Goals

- Do not add typed write support for undocumented team fields such as color,
  description, archive, or lifecycle actions.
- Do not create, update, or delete teams from the smoke app.
- Do not add Team Memberships UI to this smoke.
- Do not add realtime WebSocket setup to this smoke. Realtime-triggered refresh
  can still be wired by applications using existing snapshot stream APIs.
- Do not infer undocumented field meanings. Show raw key/value data faithfully.

## Public API

Add a Teams snapshot stream convenience API beside the existing Spaces,
Messages, and Memberships stream helpers:

```swift
public typealias TeamsStream = WebexSnapshotStream<WebexTeam>

public extension TeamsAPI {
    func stream(
        params: ListTeamsParams = ListTeamsParams(),
        pageLimit: Int? = nil
    ) -> TeamsStream
}
```

The implementation should use:

- `TeamsAPI.list(params:)` for the first page
- `TeamsAPI.list(nextPage:)` for pagination
- `WebexStreamPage(items:nextPage:)`
- `id: { $0.id }` for item reconciliation

No enrichment layer is required. Teams already carry documented decoded fields
and `additionalFields` on each item.

## User Experience

Create a new native SwiftUI example named `WebexTeamsSnapshotSmoke`.

The window uses a two-pane layout:

- Left pane: teams from the current snapshot.
- Right pane: selected-team detail showing snapshot context and parsed team
  fields.

The toolbar/header includes:

- `Refresh Teams`: calls `TeamsStream.refresh()`.
- `Load More`: calls `TeamsStream.loadNextPage()` when pagination allows.
- Snapshot status text: revision, last updated time, refresh/loading state,
  pagination state, and snapshot-level error text when present.

Rows should be compact and scannable. Each row should show:

- team name or a placeholder
- short team ID
- created date when present
- count of captured `additionalFields`

The detail pane should show:

- Snapshot metadata for the selected item:
  - revision
  - last updated time
  - refresh/loading flags
  - pagination state
- Parsed `WebexTeam` fields:
  - `id`
  - `name`
  - `creatorID`
  - `created`
- Undocumented returned fields:
  - one row for each `additionalFields` key, sorted by key
  - values rendered as stable JSON-like text
  - a clear empty state when no additional fields were returned

The UI should use native SwiftUI controls and system images. Missing fields
should show explicit placeholders rather than blank gaps.

## Architecture

Follow the organization used by the existing native smoke apps:

- `TeamsSnapshotSmokeConfiguration`
  - Parses environment variables.
  - Builds `WebexIntegrationConfiguration`.
  - Builds `ListTeamsParams`.
- `TeamsSnapshotBootstrap`
  - Creates `URLSessionHTTPClient`, `KeychainWebexStore`, and
    `WebexClientRegistry`.
  - Authorizes and creates a `WebexClient`.
  - Creates `client.teams.stream(params:pageLimit:)`.
- `TeamsSnapshotRuntime`
  - Holds the `TeamsStream`.
  - Exposes stream commands used by the window model.
- `TeamsSnapshotWindowModel`
  - Subscribes to `stream.snapshots`.
  - Maps snapshots to row and detail view models.
  - Exposes refresh and load-more commands.
- `TeamSnapshotRowModel`
  - Compact row representation.
- `TeamSnapshotDetailModel`
  - Field-list representation for documented fields and `additionalFields`.
- SwiftUI views
  - App entry point.
  - Main content view.
  - Detail view.

The SwiftUI layer should only consume `TeamsStream` snapshots through the window
model. It should not call REST APIs directly.

## Environment

Required:

- `WEBEX_CLIENT_ID`
- `WEBEX_CLIENT_SECRET`

Optional:

- `WEBEX_REDIRECT_URI`
  - Defaults to `http://127.0.0.1:8282/oauth/callback`.
- `WEBEX_SCOPES`
  - Defaults to `spark:teams_read`.
- `WEBEX_TEAMS_PAGE_SIZE`
  - Defaults to `25`.
- `WEBEX_TEAMS_STREAM_PAGE_LIMIT`
  - Defaults to `1`.
- `WEBEX_KEYCHAIN_SERVICE`
  - Defaults to `com.webex.swift-sdk.teams-snapshot-smoke`.

No environment variable should echo secrets in thrown errors.

## Data Flow

1. App starts and parses configuration.
2. Bootstrap authorizes and creates a `WebexClient`.
3. Bootstrap creates `client.teams.stream(params:pageLimit:)`.
4. Window model subscribes to `stream.snapshots`.
5. Window model calls `stream.refresh()` once after startup.
6. Each snapshot updates:
   - team rows
   - selected-team detail
   - revision and update metadata
   - loading/refreshing flags
   - pagination state
   - snapshot-level error text
7. `Load More` requests the next Teams page when available and not capped.
8. `additionalFields` are rendered from the selected item without any mapped ID
   lookup or secondary REST call.

## Error Handling And Security

- Startup/configuration errors should show a concise native failure state.
- Snapshot-level errors should appear in a non-disruptive status area.
- Error text must use SDK-safe descriptions and must not expose OAuth callback
  codes, access tokens, client secrets, or refresh tokens.
- Invalid environment values should not echo sensitive raw inputs.
- The window model should cancel subscription tasks in `deinit`.
- API calls continue to use `WebexTransport` through `TeamsAPI`, preserving
  existing backoff, token refresh, HTTP classification, and redaction behavior.

## Testing

Add focused SDK tests:

- `TeamsAPI.stream` loads the first page into a `WebexStreamSnapshot<WebexTeam>`.
- `TeamsAPI.stream` loads the next page and reconciles items by `id`.
- The stream preserves `WebexTeam.additionalFields` on snapshot items.

Add focused example tests:

- Configuration requires credentials.
- Configuration defaults match the documented values.
- Configuration applies page size, page limit, scopes, redirect, and keychain
  overrides.
- Invalid environment values return safe errors.
- Row model maps name, ID, created date, and additional-field count.
- Detail model renders documented fields and sorted `additionalFields`.
- Window model applies snapshots, preserves selection where possible, and
  exposes refresh/load-more commands through an injectable runtime or stream
  boundary.

Run example-specific tests with:

```bash
cd Examples/WebexTeamsSnapshotSmoke
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
- default scope
- what the smoke proves
- how to inspect real returned undocumented fields through
  `additionalFields`
- that absence of `additionalFields` means Webex did not return extra team keys
  for that tenant/page, not that the SDK dropped them
- that realtime is not included in this smoke

Update the root README examples list with the new smoke app.
