# WebexMessagesStreamWindowSmoke

Native macOS SwiftUI smoke app for viewing Webex Messages through a
`MessagesStream`.

The window subscribes to `stream.snapshots`, displays `MessageRowModel` values
derived from each snapshot, and keeps a Webex realtime connection open so
message created, updated, and deleted events for the configured room trigger
`stream.refresh()`. The Refresh button still calls `stream.refresh()` manually.
The UI never calls `client.messages.list(...)` directly.

## Required Webex Integration Settings

Configure the Webex integration redirect URI as:

```text
http://127.0.0.1:8282/oauth/callback
```

The integration needs realtime-capable OAuth scopes:

```text
spark:all spark:kms
```

If the integration previously granted only REST read scopes, update the Webex
integration scopes and use a fresh `WEBEX_KEYCHAIN_SERVICE` value or clear the
old Keychain token record before rerunning.

## Run

```bash
cd Examples/WebexMessagesStreamWindowSmoke
export WEBEX_CLIENT_ID="..."
export WEBEX_CLIENT_SECRET="..."
export WEBEX_ROOM_ID="..."
swift run WebexMessagesStreamWindowSmoke
```

Optional environment variables:

- `WEBEX_REDIRECT_URI`: defaults to `http://127.0.0.1:8282/oauth/callback`
- `WEBEX_SCOPES`: defaults to `spark:all spark:kms`
- `WEBEX_MESSAGES_PAGE_SIZE`: defaults to `25`
- `WEBEX_MESSAGES_STREAM_PAGE_LIMIT`: defaults to `1`
- `WEBEX_KEYCHAIN_SERVICE`: defaults to `com.webex.swift-sdk.messages-stream-window-smoke`

The app opens Webex authorization in the default browser on first launch. Once
the SDK stores the refresh token in Keychain, future launches can refresh access
tokens through the SDK token lifecycle.
