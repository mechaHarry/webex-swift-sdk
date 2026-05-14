# WebexSpacesEnrichedSnapshotSmoke

Native macOS SwiftUI smoke app for viewing Webex Spaces through an enriched
`SpacesStream` snapshot.

The window subscribes to `stream.snapshots` and displays each selected
`WebexSpace` as two groups of fields:

- wire-faithful fields decoded from `/v1/rooms`
- SDK-derived `enriched` fields such as `teamName`, `spaceAvatar`, status, and
  item-scoped enrichment errors

The UI never calls `client.teams`, `client.people`, or `client.memberships`
directly. Enrichment is produced by the `SpacesStream` before the snapshot
reaches the window model, so app code can use ergonomic fields such as
`item.enriched.spaceAvatar`.

## Required Webex Integration Settings

Configure the Webex integration redirect URI as:

```text
http://127.0.0.1:8282/oauth/callback
```

The default REST scopes are:

```text
spark:rooms_read spark:memberships_read spark:people_read
```

Some Webex tenants may require a separate teams read scope for team-name
enrichment. If team names fail with a scope error, add the required teams read
scope to `WEBEX_SCOPES`, update the Webex integration, and reauthorize.

## Run

```bash
cd Examples/WebexSpacesEnrichedSnapshotSmoke
cp source.sample.sh source.sh
# Edit source.sh with your Webex integration credentials.
source ./source.sh
swift run WebexSpacesEnrichedSnapshotSmoke
```

Optional environment variables:

- `WEBEX_REDIRECT_URI`: defaults to `http://127.0.0.1:8282/oauth/callback`
- `WEBEX_SCOPES`: defaults to `spark:rooms_read spark:memberships_read spark:people_read`
- `WEBEX_SPACES_PAGE_SIZE`: defaults to `25`
- `WEBEX_SPACES_STREAM_PAGE_LIMIT`: defaults to `1`
- `WEBEX_SPACES_TYPE`: optional `direct` or `group`
- `WEBEX_SPACES_TEAM_ID`: optional team filter
- `WEBEX_SPACES_SORT_BY`: optional `id`, `lastactivity`, or `created`
- `WEBEX_KEYCHAIN_SERVICE`: defaults to `com.webex.swift-sdk.spaces-enriched-snapshot-smoke`

The app opens Webex authorization in the default browser on first launch. Once
the SDK stores the refresh token in Keychain, future launches can refresh access
tokens through the SDK token lifecycle.

## Snapshot Controls

- `Refresh Spaces` calls `SpacesStream.refresh()` and reloads the base spaces
  page before enrichment runs.
- `Refresh Enrichment` calls `SpacesStream.refreshEnrichment()` and refreshes
  cached derived details for the current snapshot without reloading the base
  spaces page.
- `Load More` calls `SpacesStream.loadNextPage()` when pagination allows.

This smoke intentionally does not create a realtime WebSocket connection. A
production app can still connect realtime triggers to the same enriched stream:

```swift
let refreshTask = stream.refreshOnTriggers(connection.triggers)
```

Every refresh triggered that way emits the same enriched `WebexSpace` snapshots
shown by this smoke.
