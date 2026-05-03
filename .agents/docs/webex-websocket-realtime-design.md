# Webex WebSocket Realtime Design

## Status

Approved design for the v2.4.0 Webex realtime iteration. This document is intentionally a design/spec, not an implementation plan.

## Goal

Add native Swift WebSocket support to the SDK so macOS apps can receive baseline realtime Webex activity without hosting a public webhook target URL.

The first implementation is receive-only for realtime events. SDK writes and detail fetches remain REST API calls. WebSocket events act as realtime signals and payload previews; REST remains the canonical API shape for fetching complete resource state.

## Sources Reviewed

- Webex JS SDK browser socket sample: listens for messages, rooms, memberships, and attachment actions through `listen()`/`on()`.
- WebexSamples Hookbuster: demonstrates local WebSocket-to-HTTP forwarding for apps that cannot expose public webhook URLs.
- `fbradyirl/webex_bot`: proves non-JavaScript Webex WebSocket handling by discovering WDM through U2C, registering a desktop device, connecting to `webSocketUrl`, sending an authorization frame, receiving activity envelopes, and sending ack frames.
- WebexPythonSDK: REST-focused; no useful WebSocket implementation found for this design.

## Language And Runtime Choice

Implement this in pure Swift using Apple/Foundation networking:

- `URLSession` for U2C/WDM HTTP calls.
- `URLSessionWebSocketTask` for WebSocket transport.
- `AsyncStream` for event, trigger, and connection state output.

Do not embed JavaScript, run Node.js, run Python, or ship a bridge process for this iteration. The Python example shows the WebSocket protocol can be implemented with ordinary HTTP and WebSocket primitives, so a Swift SDK should own this natively.

## Architecture

Public app-facing API uses `realtime` terminology. Internal implementation may use Webex protocol terms like Mercury and WDM where helpful.

Components:

- `WebexClient.realtime`
  - Entry point for authenticated realtime listening.
- `WebexRealtimeClient`
  - High-level surface that creates live realtime connections.
- `WebexRealtimeConnection`
  - Cancellable live connection.
  - Exposes `events`, `triggers`, and `states` streams.
- `WebexRealtimeEvent`
  - Rich event value representing what Webex sent.
  - Preserves raw resource/event strings and payload fields.
- `WebexRealtimeConnectionState`
  - Emits lifecycle states: disconnected, discovering, registering device, connecting, authorizing, connected, reconnecting, failed.
- `WebexMercuryDeviceService`
  - Discovers WDM through U2C.
  - Fetches the unauthenticated limited/preauth U2C catalog first.
  - Uses the limited catalog's `u2c` service link for the authenticated postauth catalog.
  - Falls back to the limited catalog's `wdm` service link if postauth catalog returns 401/403.
  - Reuses an in-memory SDK-owned device while valid.
  - Creates/registers a WDM device directly when no cached device is valid.
- `WebexMercuryWebSocketSession`
  - Owns the `URLSessionWebSocketTask`, authorization frame, receive loop, ack frames, and cancellation.
- `WebexRealtimeTriggerAdapter`
  - Converts realtime events into lightweight `WebexStreamTrigger` values used by Snapshot Streams.

The realtime layer sits beside the existing REST APIs. It should not be implemented inside `MessagesAPI`, `SpacesAPI`, or other REST API clients.

## Data Flow

Startup flow:

1. App calls `client.realtime.connect(options:)`.
2. Realtime client asks the existing token manager for a fresh access token.
3. Device service calls the limited U2C catalog endpoint without authorization.
4. Device service uses the limited catalog's `u2c` URL for the authorized postauth catalog when possible.
5. Device service extracts WDM from postauth catalog, or from limited catalog if postauth returns 401/403.
6. Device service reuses its in-memory cached device if it matches the requested device name.
7. If no usable cached device exists, device service creates one with a desktop/native SDK identity.
8. Device service returns the WDM-provided `webSocketUrl`.
9. WebSocket session connects to the `wss://` URL with `URLSessionWebSocketTask`.
10. After connection, session sends an authorization frame:

   ```json
   {
     "id": "uuid",
     "type": "authorization",
     "data": {
       "token": "Bearer <access token>"
     }
   }
   ```

9. Incoming text frames decode into a raw Mercury envelope first.
10. Known event shapes normalize into `WebexRealtimeEvent`.
11. Unknown resource/event/payload shapes are preserved and emitted instead of dropped.
12. `WebexRealtimeConnection.events` emits rich event values.
13. `WebexRealtimeConnection.triggers` maps those events into `WebexStreamTrigger` values.
14. Snapshot Streams may call `refreshOnTriggers(connection.triggers, where:)` to refresh only for matching realtime signals.

## Public API Shape

Use one live connection type:

```swift
let connection = client.realtime.connect(
    options: WebexRealtimeOptions(resources: [.messages, .spaces, .memberships])
)

Task {
    for await state in connection.states {
        print(state)
    }
}

Task {
    for await event in connection.events {
        print(event.resource, event.event, event.decodeStatus)
    }
}

let stream = client.messages.stream(params: .init(roomID: roomID, max: 25))

let refreshTask = stream.refreshOnTriggers(connection.triggers) { trigger in
    trigger.resource == "messages" && trigger.roomID == roomID
}
```

`WebexRealtimeConnection`:

- `events: AsyncStream<WebexRealtimeEvent>`
- `triggers: AsyncStream<WebexStreamTrigger>`
- `states: AsyncStream<WebexRealtimeConnectionState>`
- `cancel()`

`WebexRealtimeEvent` is a single rich event value. `WebexStreamTrigger` is a simplified refresh signal. The connection exposes both streams so apps can inspect raw realtime behavior and Snapshot Streams can refresh without knowing protocol details.

## Options

`WebexRealtimeOptions` will include:

- Selected resources/events.
- Whether to include noisy `memberships:seen` events.
- Reconnect/backoff configuration.
- Device identity override for tests and diagnostics.

Known resources will include:

- `messages`
- `spaces` with `rooms` alias support
- `memberships`
- `attachmentActions`

Unknown resources must be represented without failing decode.

## Event Handling Policy

Do not hardcode sample-backed event names as the full truth.

The SDK will:

- Decode and expose any resource/event string Webex sends.
- Provide known typed conveniences for sample-backed events:
  - `messages`: `created`, `deleted`
  - `rooms` / `spaces`: `created`, `updated`
  - `memberships`: `created`, `updated`, `deleted`, optional `seen`
  - `attachmentActions`: `created`
- Preserve events like `messages:updated`, `rooms:deleted`, or `spaces:deleted` if Webex sends them.
- Mark unknown event names as unknown while still emitting realtime events and stream triggers.
- Mark known resource/event pairs with missing or unexpected payload fields as unknown payloads.

This keeps the SDK faithful to live Webex behavior without pretending undocumented events are guaranteed.

## Decode Status

`WebexRealtimeEvent` will expose a decode status:

- `.known`
  - Resource/event and payload shape are understood well enough to map useful IDs.
- `.unknownEvent`
  - Resource or event name is not yet modeled.
- `.unknownPayload`
  - Resource/event is recognized, but payload shape is missing or differs from expected fields.

Unknown statuses must not fail the connection. They are observability signals for SDK iteration.

## Device Registration

Initial implementation will cache WDM device registration in memory for the live `WebexClient`.

Do not persist device registration yet. Persist only if smoke testing proves repeated registration is slow, unstable, or rate-limited.

Device identity will be SDK-owned and recognizable, for example:

- `deviceType`: `WEB`
- `model`: `webex-swift-sdk`
- `localizedModel`: `webex-swift-sdk`
- `name`: stable SDK device name scoped enough to avoid collisions
- `systemName`: `WEBEX_SWIFT_SDK`
- `systemVersion`: initial SDK version string

WDM create requests should include `includeUpstreamServices=all`, a
`trackingid` header prefixed with `webex-swift-sdk_`, a `User-Agent` prefixed
with `webex-swift-sdk/`, and `Content-Type: application/json;charset=utf-8`.
This keeps the native Swift implementation closer to the Webex JavaScript SDK
and Webex bot request shape than a bare REST-style JSON POST, and avoids
presenting third-party OAuth integrations as first-party desktop devices.

Live WDM create responses may not include `id` or `name`. A successful response
can include `url`, `webSocketUrl`, and a large `services` object. The device
adapter must accept that shape by deriving the device ID from the final path
component of `url` when `id` is absent, and by falling back to the requested SDK
device name when WDM omits `name`. `webSocketUrl` remains required and must be
`wss://`.

If WebSocket handshake returns 404, treat device registration as stale: discard device info, re-register, and retry up to a small cap before failing.

## Backoff And Error Handling

All API call code must gracefully back off.

U2C/WDM HTTP calls:

- Limited/preauth U2C catalog is unauthenticated.
- Postauth U2C catalog uses the access token and may be forbidden for some integration tokens.
- If postauth U2C returns 401/403, fall back to the limited catalog's WDM link.
- Retry transient network errors, 429, and 5xx with the SDK retry policy.
- Respect `Retry-After` when present.
- Redact tokens, socket URLs, and payloads from thrown/logged errors.
- Decode failures for successful U2C/WDM HTTP responses are deterministic
  diagnostics, not reconnect candidates. Report operation, HTTP status,
  missing/mismatched field path, and a compact redacted body preview.

WebSocket lifecycle:

- Reconnect after abnormal disconnects with exponential backoff.
- Default max backoff will be capped, with 240 seconds as a reasonable upper bound based on the Python example.
- 401/403 will invalidate the access token, refresh once, and reconnect.
- If token refresh fails, emit failed or reauthentication-required state.
- Cancellation will close the WebSocket and finish all streams.

Connection states allow macOS apps to show native UI status without parsing error strings.

## OAuth Scope Negotiation

Realtime WebSocket listening needs an OAuth token granted `spark:all` and
`spark:kms`. It is not enough for the SDK or app to request those scopes in the
authorization URL; the Webex token response is the authority. If the integration
is only configured for narrower scopes, Webex can return a token whose granted
scope is only something like `spark:people_read`, and WDM device registration
will fail with HTTP 403 even though REST People calls work.

The SDK should preserve granted scopes from token responses and examples/apps
should validate that the granted token covers the feature being started. For
macOS apps, scopes should be explicit in `WebexIntegrationConfiguration`,
selected from feature profiles such as:

- REST People read: `spark:people_read`
- Messages/Spaces REST screens: the corresponding documented REST read/write
  scopes
- Experimental realtime listener: `spark:all spark:kms`

Shell variables such as `WEBEX_SCOPES` are only for examples and smoke tests.
Production SwiftUI/AppKit clients should set scopes directly in Swift, then
surface a clear user-facing setup error when the Webex integration grants less
than the selected feature profile requires.

## Security

Security requirements:

- Never log access tokens, refresh tokens, auth frames, `webSocketUrl`, or raw event payloads by default.
- Only the realtime smoke may print raw unknown payloads, and only behind an explicit opt-in flag.
- Require `wss://` for WebSocket URLs.
- Use existing redaction utilities for public error descriptions.
- Avoid strong reference cycles between connection, task, session, and stream continuations.
- Make cancellation deterministic so long-running WebSocket tasks do not leak after windows close or accounts are removed.

## Snapshot Streams Integration

The realtime layer integrates with existing Snapshot Streams through `WebexStreamTrigger`.

Example behavior:

- A `messages:created` event for room A triggers refresh for a messages stream scoped to room A.
- A `messages:created` event for room B should not refresh room A's stream.
- A `rooms:updated` or `spaces:updated` event can refresh a spaces stream.
- Unknown events can still trigger refresh if their resource and IDs are present.

The app/UI should not need to know how to reconnect sockets or poll REST APIs. It subscribes to stream snapshots and connection states.

## Realtime Events Smoke

Add a committed smoke example:

`Examples/WebexRealtimeEventsSmoke`

Purpose:

- Authenticate like the existing examples.
- Start the realtime listener.
- Print connection state changes.
- Print every event as it arrives.
- Highlight unknown events and unknown payloads so the SDK can be iterated safely.

Required output fields:

- timestamp
- connection state
- resource/event
- decode status
- resource ID
- room/space ID
- actor/person ID
- compact redacted unknown payload when explicitly enabled

Required environment flags:

- `WEBEX_REALTIME_RESOURCE`
- `WEBEX_REALTIME_EVENT`
- `WEBEX_REALTIME_INCLUDE_SEEN`
- `WEBEX_REALTIME_PRINT_RAW_UNKNOWN`

Known events print normally. Unknown event names print `UNKNOWN EVENT`. Known resource/event pairs with unexpected payload shape print `UNKNOWN PAYLOAD`.

## Tests

Every feature requires strict tests.

Unit tests will cover:

- U2C catalog parsing.
- Limited U2C fallback when postauth U2C is forbidden.
- WDM service URL extraction.
- In-memory WDM device reuse.
- WDM device creation request shape.
- Stale device 404 handling.
- Live WDM device response shape where `url` replaces `id` and `name` is
  omitted.
- WebSocket authorization frame encoding.
- Ack frame encoding.
- Known event decoding.
- Unknown event preservation.
- Unknown payload marking.
- Trigger mapping from realtime event to `WebexStreamTrigger`.
- Connection cancellation finishing streams.
- Reconnect/backoff behavior with fake sleeper.
- 401/403 token invalidation and single refresh retry.
- Redaction of access tokens, auth frames, socket URLs, and unknown payloads.
- Realtime OAuth examples validate granted scopes before WDM registration and
  print requested/granted scopes for diagnosis.

Use mock HTTP and mock WebSocket transport protocols. Unit tests must not require live Webex.

Smoke tests/examples may require live Webex credentials and should document their environment variables clearly.

## Non-Goals For First Iteration

- Sending messages or mutating Webex data over WebSocket.
- Replacing REST APIs with WebSocket APIs.
- Persisting WDM device registration.
- Supporting compliance-officer-only APIs.
- Claiming full official Webex WebSocket protocol support.
- Embedding JavaScript or bundling a helper runtime.

## Open Risks

- The protocol is not officially documented as a Swift/API contract, so payload shape may drift.
- The authorization and ack frame details are based on working open-source examples.
- Resource/event coverage may be broader than samples show; unknown preservation and the realtime smoke are required to handle this safely.
- Device registration lifetime and cleanup semantics may need refinement after live smoke testing.

## Implementation Sequence Preview

The implementation plan will proceed in this order:

1. Add realtime model types and options.
2. Add mockable WDM/U2C device service.
3. Add mockable WebSocket session transport.
4. Add event decoder and trigger mapper.
5. Add `WebexClient.realtime`.
6. Add `WebexRealtimeEventsSmoke`.
7. Update `.agents/docs` roadmap with realtime status and follow-up gaps.

Do not start this implementation until the written spec is reviewed and approved.
