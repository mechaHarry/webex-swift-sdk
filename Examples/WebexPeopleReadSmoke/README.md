# WebexPeopleReadSmoke

Interactive OAuth smoke test for reading Webex People through `WebexSwiftSDK`.

This example is read-only. It calls `people.me()`, reads that same person with
`people.get(personID:)`, then lists people by ID with `people.list(params:)`.

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
WEBEX_PEOPLE_IDS="person-id-1,person-id-2"
WEBEX_REDIRECT_URI="http://127.0.0.1:8282/oauth/callback"
WEBEX_KEYCHAIN_SERVICE="com.example.webex-people-read-smoke.$USER"
```

If `WEBEX_PEOPLE_IDS` is omitted or blank, the smoke lists the signed-in user ID
returned by `people.me()`.

By default, the example stores credentials and refresh-token records under the
Keychain service `com.webex.swift-sdk.people-read-smoke`.
