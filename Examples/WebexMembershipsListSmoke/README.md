# WebexMembershipsListSmoke

Interactive OAuth smoke test for listing Webex Memberships through
`WebexSwiftSDK`.

This example is list-only. It does not create, update, moderate, or delete room
members.

## Run

Create a Webex integration whose redirect URI is:

```text
http://127.0.0.1:8282/oauth/callback
```

Then run:

```bash
cd Examples/WebexMembershipsListSmoke

WEBEX_CLIENT_ID="your-client-id" \
WEBEX_CLIENT_SECRET="your-client-secret" \
WEBEX_ROOM_ID="room-id-to-list" \
WEBEX_SCOPES="spark:memberships_read" \
swift run WebexMembershipsListSmoke
```

The SDK opens a temporary listener on `127.0.0.1:8282`, waits for the browser
redirect, then closes the listener after the callback is received.

## Options

Use these optional environment variables to bound the listing:

```bash
WEBEX_MEMBERSHIPS_PAGE_SIZE="100"
WEBEX_MEMBERSHIPS_MAX_PAGES="1000"
```

If the smoke reports `Memberships pagination page cap exceeded`, increase
`WEBEX_MEMBERSHIPS_MAX_PAGES` or lower `WEBEX_MEMBERSHIPS_PAGE_SIZE`.

If your Webex integration uses a different registered loopback URI, override it with:

```bash
WEBEX_REDIRECT_URI="http://127.0.0.1:8282/oauth/callback"
```

By default, the example stores credentials and refresh-token records under the Keychain service `com.webex.swift-sdk.memberships-list-smoke`. Override it per run with:

```bash
WEBEX_KEYCHAIN_SERVICE="com.example.webex-memberships-list-smoke.$USER"
```
