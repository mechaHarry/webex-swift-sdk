# WebexRealtimeEventsSmoke

Interactive OAuth smoke test for Webex realtime websocket events through `WebexSwiftSDK`.

This example:

- creates a `WebexIntegrationConfiguration` from environment variables
- stores a new local account in `WebexClientRegistry`
- opens the Webex authorization URL in the default browser
- receives the OAuth redirect through the SDK-owned loopback listener
- starts `client.realtime.connect(options:)`
- prints connection states and realtime events until interrupted
- redacts token-like and secret-like values before printing unknown payloads

## Run

Create a Webex integration. If your integration uses the SDK default loopback redirect URI, register:

```text
http://127.0.0.1:8282/oauth/callback
```

If your integration is registered with this redirect URI instead, pass it with `WEBEX_REDIRECT_URI` when running:

```text
http://127.0.0.1:8282/callback
```

Then run:

```bash
cd Examples/WebexRealtimeEventsSmoke

WEBEX_CLIENT_ID="your-client-id" \
WEBEX_CLIENT_SECRET="your-client-secret" \
swift run WebexRealtimeEventsSmoke
```

The SDK opens a temporary listener on `127.0.0.1:8282`, waits for the browser redirect, connects to Webex realtime, then prints states and events until you press Ctrl-C.

## Environment

Required:

```bash
WEBEX_CLIENT_ID="your-client-id"
WEBEX_CLIENT_SECRET="your-client-secret"
```

Optional:

```bash
WEBEX_REDIRECT_URI="http://127.0.0.1:8282/callback"
WEBEX_SCOPES="spark:messages_read spark:rooms_read spark:memberships_read spark:people_read"
WEBEX_KEYCHAIN_SERVICE="com.example.webex-realtime-events-smoke.$USER"
WEBEX_REALTIME_RESOURCE="messages"
WEBEX_REALTIME_EVENT="created"
WEBEX_REALTIME_INCLUDE_SEEN="false"
WEBEX_REALTIME_PRINT_RAW_UNKNOWN="false"
```

`WEBEX_REALTIME_RESOURCE` is an exact resource filter. Leave it unset to use the SDK realtime defaults.

`WEBEX_REALTIME_EVENT` is an exact event-name filter. Leave it unset to use the SDK realtime defaults.

`WEBEX_REALTIME_INCLUDE_SEEN` accepts `true`, `1`, `yes`, `false`, `0`, or `no` case-insensitively. The default is `false`.

`WEBEX_REALTIME_PRINT_RAW_UNKNOWN` accepts the same boolean values. It only prints compact redacted payloads for unknown event or unknown payload decode statuses.

By default, the example stores credentials and refresh-token records under the Keychain service `com.webex.swift-sdk.realtime-events-smoke`.

## Suggested Checks

Start without realtime filters first:

```bash
swift run WebexRealtimeEventsSmoke
```

In a Webex space visible to the authenticated user:

- send a new message and check for a `messages:created` event
- edit that message and check for a `messages:updated` event
- delete that message and check for a `messages:deleted` event
- set `WEBEX_REALTIME_RESOURCE="memberships"` and `WEBEX_REALTIME_INCLUDE_SEEN="true"` if you need to inspect membership seen events

Do not enable raw unknown payload printing unless you are investigating decoder coverage. The smoke still redacts secrets, but raw payloads may contain workspace data.
