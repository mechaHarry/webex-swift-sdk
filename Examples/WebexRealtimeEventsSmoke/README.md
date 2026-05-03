# WebexRealtimeEventsSmoke

Interactive smoke test for Webex realtime websocket events through `WebexSwiftSDK`.

This example:

- creates a `WebexIntegrationConfiguration` from environment variables, or uses a direct `WEBEX_ACCESS_TOKEN`
- stores a new local account in `WebexClientRegistry` when running OAuth
- opens the Webex authorization URL in the default browser when running OAuth
- receives the OAuth redirect through the SDK-owned loopback listener when running OAuth
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

To isolate whether a WDM/Mercury failure is caused by OAuth integration token
class, run the same Swift realtime path with a developer personal access token
or bot token:

```bash
WEBEX_ACCESS_TOKEN="your-token" \
swift run WebexRealtimeEventsSmoke
```

When `WEBEX_ACCESS_TOKEN` is set, the smoke does not require
`WEBEX_CLIENT_ID`, `WEBEX_CLIENT_SECRET`, a redirect URI, browser auth, or a
Keychain record. The direct token is kept in memory for the process lifetime.

## Environment

Required for OAuth mode:

```bash
WEBEX_CLIENT_ID="your-client-id"
WEBEX_CLIENT_SECRET="your-client-secret"
```

For realtime WebSocket listening, the Webex JavaScript SDK documentation says
the token needs `spark:all` and `spark:kms`. Add those scopes to the Webex
integration before authorizing this smoke. If you previously authorized the
same integration with narrower scopes, reauthorize after updating the
integration scopes.

Optional:

```bash
WEBEX_ACCESS_TOKEN="developer-portal-personal-token-or-bot-token"
WEBEX_REDIRECT_URI="http://127.0.0.1:8282/callback"
WEBEX_SCOPES="spark:all spark:kms"
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

If device registration fails with HTTP 403 during `registeringDevice`, first
confirm that the integration has `spark:all` enabled and that the authorization
URL requested `spark:kms` as well. `spark:kms` is the encrypted-content scope
Webex includes for integrations; without it the SDK websocket listener can be
rejected before the socket opens.

The smoke prints both requested and granted OAuth scopes. If the token response
grants only a narrower scope such as `spark:people_read`, update the Webex
integration's allowed scopes, confirm `WEBEX_SCOPES` is not overriding the
default, and reauthorize with a fresh keychain service or deleted stored
account.

If OAuth mode still receives WDM HTTP 403 but direct `WEBEX_ACCESS_TOKEN` mode
registers a device, the Swift request path is working and Webex is rejecting
the OAuth integration token class for this internal realtime device route.

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
