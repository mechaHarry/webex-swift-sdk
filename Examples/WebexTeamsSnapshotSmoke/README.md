# WebexTeamsSnapshotSmoke

Native macOS SwiftUI smoke app for viewing Webex Teams through `TeamsStream`
snapshots.

The window subscribes to `stream.snapshots` and displays each selected
`WebexTeam` as parsed documented fields and returned-but-undocumented
`additionalFields`.

Empty `additionalFields` means Webex did not return extra team keys for that
tenant and page. It does not mean the SDK dropped returned fields.

Realtime is intentionally not included in this smoke. The app only exercises
OAuth, `client.teams.stream`, snapshot refresh, pagination, and visual field
inspection.

## Required Webex Integration Settings

Configure the Webex integration redirect URI as:

```text
http://127.0.0.1:8282/oauth/callback
```

The default REST scope is:

```text
spark:teams_read
```

## Run

```bash
cd Examples/WebexTeamsSnapshotSmoke
cp source.sample.sh source.sh
# Edit source.sh with your Webex integration credentials.
source ./source.sh
swift run WebexTeamsSnapshotSmoke
```

Optional environment variables:

- `WEBEX_REDIRECT_URI`: defaults to `http://127.0.0.1:8282/oauth/callback`
- `WEBEX_SCOPES`: defaults to `spark:teams_read`
- `WEBEX_TEAMS_PAGE_SIZE`: defaults to `25`
- `WEBEX_TEAMS_STREAM_PAGE_LIMIT`: defaults to `1`
- `WEBEX_KEYCHAIN_SERVICE`: defaults to `com.webex.swift-sdk.teams-snapshot-smoke`

The app opens Webex authorization in the default browser on first launch. Once
the SDK stores the refresh token in Keychain, future launches can refresh access
tokens through the SDK token lifecycle.

## Snapshot Controls

- `Refresh Teams` calls `TeamsStream.refresh()` and reloads the teams page.
- `Load More` calls `TeamsStream.loadNextPage()` when pagination allows.
