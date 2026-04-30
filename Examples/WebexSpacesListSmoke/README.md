# WebexSpacesListSmoke

Interactive OAuth smoke test for listing Webex Spaces through `WebexSwiftSDK`.

This example:

- creates a `WebexIntegrationConfiguration` from environment variables
- stores a new local account in `WebexClientRegistry`
- builds a PKCE authorization URL
- receives the OAuth redirect through the SDK-owned loopback listener
- exchanges the authorization code for tokens
- stores the refresh-token record in the registry store
- creates `WebexClient` with the initial access token in memory
- calls `spaces.listAll(...)` with a bounded page cap
- prints returned Spaces metadata without printing tokens, authorization codes, or client secrets

## Run

Create a Webex integration whose redirect URI is:

```text
http://127.0.0.1:8282/oauth/callback
```

Then run:

```bash
cd Examples/WebexSpacesListSmoke

WEBEX_CLIENT_ID="your-client-id" \
WEBEX_CLIENT_SECRET="your-client-secret" \
WEBEX_SCOPES="spark:rooms_read" \
swift run WebexSpacesListSmoke
```

The SDK opens a temporary listener on `127.0.0.1:8282`, waits for the browser redirect, then closes the listener after the callback is received.

## Options

Use these optional environment variables to bound and filter the listing:

```bash
WEBEX_SPACES_PAGE_SIZE="100"
WEBEX_SPACES_MAX_PAGES="1000"
WEBEX_SPACES_TYPE="group"
WEBEX_SPACES_SORT_BY="lastactivity"
WEBEX_SPACES_TEAM_ID="your-team-id"
```

If the smoke reports `Spaces pagination page cap exceeded`, increase
`WEBEX_SPACES_MAX_PAGES` or narrow the listing with `WEBEX_SPACES_TYPE` or
`WEBEX_SPACES_TEAM_ID`.

If your Webex integration uses a different registered loopback URI, override it with:

```bash
WEBEX_REDIRECT_URI="http://127.0.0.1:8282/oauth/callback"
```

By default, the example stores credentials and refresh-token records under the Keychain service `com.webex.swift-sdk.spaces-list-smoke`. Override it per run with:

```bash
WEBEX_KEYCHAIN_SERVICE="com.example.webex-spaces-list-smoke.$USER"
```
