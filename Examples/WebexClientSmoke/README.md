# WebexClientSmoke

Interactive OAuth smoke test for `WebexSwiftSDK`.

This example:

- creates a `WebexIntegrationConfiguration` from environment variables
- stores a new local account in `WebexClientRegistry`
- builds a PKCE authorization URL
- exchanges the pasted OAuth redirect callback for tokens
- stores the refresh-token record in the registry store
- creates `WebexClient` from the registry
- calls `people.me()` and prints the returned profile fields

It does not print raw access tokens, refresh tokens, authorization codes, or client secrets.

## Run

Create a Webex integration whose redirect URI exactly matches `WEBEX_REDIRECT_URI`, then run:

```bash
cd Examples/WebexClientSmoke

WEBEX_CLIENT_ID="your-client-id" \
WEBEX_CLIENT_SECRET="your-client-secret" \
WEBEX_REDIRECT_URI="your-registered-redirect-uri" \
WEBEX_SCOPES="spark:people_read" \
swift run WebexClientSmoke
```

When the browser redirects, paste the full redirect URL back into the terminal.

By default, the example stores credentials and refresh-token records under the Keychain service `com.webex.swift-sdk.smoke`. Override it per run with:

```bash
WEBEX_KEYCHAIN_SERVICE="com.example.webex-smoke.$USER"
```
