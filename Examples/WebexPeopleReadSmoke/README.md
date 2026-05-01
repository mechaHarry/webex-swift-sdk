# WebexPeopleReadSmoke

Interactive OAuth smoke test for reading Webex People through `WebexSwiftSDK`.

This example is read-only. It calls `people.me()`, reads that same person with
`people.get(personID:)`, then lists people by display name with
`people.list(params:)`. The default display name filter is `Harrison`.

## Run

Create a Webex integration whose redirect URI is:

```text
http://127.0.0.1:8282/oauth/callback
```

Then run:

```bash
cd Examples/WebexPeopleReadSmoke

WEBEX_CLIENT_ID="your-client-id" \
WEBEX_CLIENT_SECRET="your-client-secret" \
WEBEX_SCOPES="spark:people_read" \
swift run WebexPeopleReadSmoke
```

The SDK opens a temporary listener on `127.0.0.1:8282`, waits for the browser
redirect, then closes the listener after the callback is received.

## Options

Use these optional environment variables to adjust the smoke:

```bash
WEBEX_PEOPLE_DISPLAY_NAME="Harrison"
WEBEX_REDIRECT_URI="http://127.0.0.1:8282/oauth/callback"
WEBEX_KEYCHAIN_SERVICE="com.example.webex-people-read-smoke.$USER"
```

If `WEBEX_PEOPLE_DISPLAY_NAME` is omitted or blank, the smoke lists people with
`displayName=Harrison`.

By default, the example stores credentials and refresh-token records under the
Keychain service `com.webex.swift-sdk.people-read-smoke`.
