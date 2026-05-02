# WebexMessagesListSmoke

Interactive OAuth smoke test for listing Webex Messages through `WebexSwiftSDK`.

This example:

- creates a `WebexIntegrationConfiguration` from environment variables
- stores a new local account in `WebexClientRegistry`
- builds a PKCE authorization URL
- receives the OAuth redirect through the SDK-owned loopback listener
- exchanges the authorization code for tokens
- creates `WebexClient` with the initial access token in memory
- calls `messages.list(params:)` for `WEBEX_ROOM_ID`
- follows `page.nextPage` only up to the explicit page cap
- exits successfully when the cap is reached and prints `hasMore: true`
- prints returned message metadata and bounded content previews

## Run

Create a Webex integration whose redirect URI is:

```text
http://127.0.0.1:8282/oauth/callback
```

Then run:

```bash
cd Examples/WebexMessagesListSmoke

WEBEX_CLIENT_ID="your-client-id" \
WEBEX_CLIENT_SECRET="your-client-secret" \
WEBEX_SCOPES="spark:messages_read" \
WEBEX_ROOM_ID="your-room-id" \
swift run WebexMessagesListSmoke
```

The SDK opens a temporary listener on `127.0.0.1:8282`, waits for the browser redirect, then closes the listener after the callback is received.

## Options

Use these optional environment variables to bound and filter the listing:

```bash
WEBEX_MESSAGES_PAGE_SIZE="25"
WEBEX_MESSAGES_MAX_PAGES="1"
WEBEX_MESSAGES_PARENT_ID="parent-message-id"
WEBEX_MESSAGES_MENTIONED_PEOPLE="me"
WEBEX_MESSAGES_BEFORE="2026-05-01T00:00:00Z"
WEBEX_MESSAGES_BEFORE_MESSAGE="message-id"
```

The default page cap is one page so active rooms do not accidentally dump large
message histories. If the smoke prints `hasMore: true`, increase
`WEBEX_MESSAGES_MAX_PAGES` to fetch older pages or narrow the listing with the
filters above.

If your Webex integration uses a different registered loopback URI, override it with:

```bash
WEBEX_REDIRECT_URI="http://127.0.0.1:8282/oauth/callback"
```

By default, the example stores credentials and refresh-token records under the Keychain service `com.webex.swift-sdk.messages-list-smoke`. Override it per run with:

```bash
WEBEX_KEYCHAIN_SERVICE="com.example.webex-messages-list-smoke.$USER"
```
