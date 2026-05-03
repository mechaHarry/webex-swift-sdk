# Webex Real-Time Trigger Notes

Captured: 2026-05-01

Official references:

- https://developer.webex.com/messaging/docs/api/v1/webhooks
- https://developer.webex.com/messaging/docs/api/guides/webhooks
- https://developer.webex.com/blog/using-websockets-with-the-webex-javascript-sdk

## Direction

Treat real-time inputs as trigger sources for SDK-owned state, not as a
replacement for REST endpoint models.

The SDK should keep endpoint wrappers wire-faithful:

- `client.webhooks.list(params:)` returns one documented page and exposes
  `nextPage`.
- `client.webhooks.list(nextPage:)` follows Webex pagination.
- `client.webhooks.create(_:)`, `get(webhookID:)`, `update(webhookID:_:)`, and
  `delete(webhookID:)` map directly to Webex Webhooks endpoints.
- Webhook notification payloads should be decoded, verified, and converted into
  stream invalidation triggers.
- Snapshot Streams should refresh through the existing authenticated REST APIs
  after a trigger, because REST remains the authoritative resource shape.

Native WebSocket trigger delivery now exists as an experimental Swift source,
but do not describe Snapshot Streams as pure real-time data sources until stream
reconciliation has been exercised in app examples.

## Webhooks API Shape

Webex documents Webhooks under `/v1/webhooks`.

List webhooks:

- `GET /v1/webhooks`
- Optional query: `max`, `ownedBy`
- `ownedBy` is documented for limiting to org-wide webhooks; the documented
  allowed value is `org`.
- Long result sets use RFC5988 `Link` pagination.

Create webhook:

- `POST /v1/webhooks`
- Required JSON fields: `name`, `targetUrl`, `resource`, `event`
- Optional JSON fields: `filter`, `secret`, `ownedBy`

Get webhook:

- `GET /v1/webhooks/{webhookId}`

Update webhook:

- `PUT /v1/webhooks/{webhookId}`
- Required JSON fields: `name`, `targetUrl`
- Optional JSON fields: `secret`, `ownedBy`, `status`
- The update `status` field is documented for reactivating disabled webhooks
  with `active`.

Delete webhook:

- `DELETE /v1/webhooks/{webhookId}`
- Success is `204 No Content`.

## Resource And Event Values

The embedded Webex reference currently lists these webhook resources:

- `attachmentActions`
- `dataSources`
- `memberships`
- `messages`
- `rooms`
- `meetings`
- `recordings`
- `convergedRecordings`
- `meetingParticipants`
- `meetingTranscripts`
- `telephony_calls`
- `telephony_conference`
- `telephony_mwi`
- `uc_counters`
- `serviceApp`
- `adminBatchJobs`

The guide also documents firehose webhooks:

- resource `all` plus event `all`
- single-resource firehose with a concrete resource and event `all`
- firehose support is called out for `memberships`, `messages`, and `rooms`

Known event values:

- `created`
- `updated`
- `deleted`
- `started`
- `ended`
- `joined`
- `left`
- `migrated`
- `authorized`
- `deauthorized`
- `statusChanged`
- `all`

Use unknown-preserving enums so the SDK does not break when Webex adds new
resources or events.

## Filters

Webhook `filter` is a raw query-string-like value. The guide says filters are
generally a subset of the list query params for the target resource and that
multiple filters are joined with `&`.

Examples:

```text
roomId=abc123
personEmail=person@example.com&roomId=abc123
```

Do not build restrictive filter types yet. Let Webex enforce endpoint semantics
so the SDK does not drift from the server.

## Security

Webhook `targetUrl` must be reachable by Webex over HTTP. A macOS app running
only on localhost is not a valid Webex webhook target unless another public
component forwards to it.

When `secret` is supplied during webhook creation, Webex sends an
`X-Spark-Signature` header containing an HMAC-SHA1 signature of the JSON
payload. The SDK should verify the raw request body bytes before trusting a
notification.

Implementation requirements:

- Do not log webhook secrets.
- Do not log raw notification payloads by default; payloads can contain IDs and
  metadata tied to people, rooms, and messages.
- Compare signatures without early-exit string comparison.
- Treat webhook notifications as untrusted input until signature validation
  succeeds when a secret is configured.
- Preserve the raw Webex `data` object as JSON values because payload fields
  can vary by resource.

## Delivery And Consistency

The guide says webhooks are sent as soon as possible and that the backing REST
resource may not be immediately synchronized in all cases. Therefore stream
trigger handling should be defensive:

- Use the webhook as an invalidation signal.
- Refresh through the corresponding REST API.
- Keep the current stream snapshot visible while refreshing.
- Let existing transport retry/backoff behavior handle 429, 423, and transient
  server failures.
- Avoid assuming the first REST read after a webhook always sees the final
  resource state.

## OAuth Relationship

The guide states that a valid OAuth token is required to create a webhook. It
also states that a webhook can continue to run as long as its target endpoint
keeps returning successful HTTP responses. This means:

- the SDK's OAuth lifecycle still matters for creating, listing, updating, and
  deleting webhook registrations;
- webhook delivery itself is an inbound HTTP concern owned by the app/backend
  that exposes the `targetUrl`;
- the SDK can provide verification, decoding, API wrappers, and stream trigger
  adapters, but it should not claim a localhost-only Webhook listener is a full
  Webex webhook solution.

## WebSocket Trigger Source

The SDK has experimental native Swift WebSocket realtime support. The public
entry point is:

```swift
let connection = client.realtime.connect(options: options)
```

`WebexRealtimeConnection` exposes:

- `events`
- `triggers`
- `states`
- `cancel()`

This support is receive-only. It listens for Webex events and maps them into
SDK models/triggers. It is not an official replacement for documented Webex
REST endpoints, and resource reads/writes should continue to use the REST API
groups.

The token used for WebSocket listening needs the SDK-listen scopes documented
by the Webex JavaScript SDK: `spark:all` plus `spark:kms`. Narrow REST read
scopes such as `spark:messages_read`, `spark:rooms_read`,
`spark:memberships_read`, and `spark:people_read` can still work for REST
calls but can fail WDM device registration with HTTP 403 before a socket opens.
After changing an integration's scopes, reauthorize so the access token actually
contains the new grants.

Live smoke validation proved that the SDK can connect end-to-end with both a
developer access token and an OAuth integration token when the OAuth token is
granted `spark:all spark:kms`. The important pitfall is scope negotiation:
requesting scopes in the authorization URL is not enough. Webex may return a
token with only the scopes allowed on the integration, for example
`spark:people_read`. Future SDK and app flows must compare requested scopes to
the token response's granted scopes and fail before WDM registration if the
granted token is missing realtime scopes.

For macOS apps, do not rely on shell environment variables for scopes. The app
should choose an explicit feature profile and pass those scopes into
`WebexIntegrationConfiguration`:

```swift
let configuration = WebexIntegrationConfiguration(
    clientID: userProvidedClientID,
    clientSecret: userProvidedClientSecret,
    redirectURI: URL(string: "http://127.0.0.1:8282/oauth/callback")!,
    scopes: ["spark:all", "spark:kms"],
    prefersEphemeralWebBrowserSession: false
)
```

Environment variables such as `WEBEX_SCOPES` are smoke-test conveniences only.
If direct `WEBEX_ACCESS_TOKEN` mode connects but OAuth mode fails WDM device
registration with 403, first inspect the granted OAuth scopes, then the Webex
integration's allowed scopes. Use a fresh keychain service or delete the stored
account when reauthorizing after scope changes.

U2C discovery follows the Webex JavaScript SDK shape: fetch the limited/preauth
catalog without authorization, use its `u2c` service link for the postauth
catalog when possible, and fall back to the limited catalog's `wdm` service link
if postauth U2C returns 401/403 for an integration token.

WDM device create can return a successful response shaped like:

```json
{
  "url": "https://wdm-a.wbx2.com/wdm/api/v1/devices/<device-id>",
  "webSocketUrl": "wss://...",
  "services": {
    "conversationServiceUrl": "https://..."
  }
}
```

Do not require a top-level `id` or `name` from WDM. The SDK should derive the
device ID from the final path component of `url` when `id` is absent and should
fall back to the requested SDK device name when `name` is absent. Diagnostic
errors may include compact redacted response previews, but must redact
`webSocketUrl`, tokens, and secret-like fields.

The implementation is sample-backed and experimental. It uses U2C/WDM device
discovery, `URLSessionWebSocketTask`, authorization frames, ack frames,
reconnect/backoff, stale-device retry, auth retry, unknown event preservation,
unknown payload preservation, and trigger mapping.

Mercury ACK identity is transport-level state. ACK frames must use the incoming
Mercury envelope/frame `id`, falling back to the activity id only when the
envelope id is absent. Do not ACK `activity.object.id` or another REST resource
id. The SDK should expose `resourceID` as the app-facing Webex message/space/etc.
identifier, but `ackID` is only the socket acknowledgment target. Live smoke
testing showed that conflating these can make Webex close the WebSocket after a
message event, which looks like an event-driven reconnect/backoff loop.

ACK is independent of app delivery. If the SDK decodes a Mercury event with an
`ackID`, it should ACK that frame even when `WebexRealtimeOptions` filters the
event out of `connection.events`. Filtering is an SDK/app subscription decision;
ACK is WebSocket protocol bookkeeping.

`WebexRealtimeOptions.diagnosticHandler` is the structured debug hook for this
experimental layer. It reports decoded event metadata, filtered-event
decisions, ACK success/failure, frame decode failure, and reconnect scheduling
reason without exposing raw payloads. The metadata should include Mercury source
fields such as `sourceEventType`, `activityVerb`, and `objectType` when present.
Use `WebexRealtimeEventsSmoke` first when live behavior is unclear; it enables
this hook and prints redacted diagnostics.

Known Mercury control frames such as `mercury.buffer_state` and
`mercury.registration_status` are internal protocol frames. Decode them as
known `resource=mercury` events so diagnostics are meaningful, but let the
default realtime resource filters suppress app-facing delivery.

Prepare the WDM `webSocketUrl` before opening the socket. Working Mercury
clients request text frames with `outboundWireFormat=text`, include
`bufferStates=true`, include `aliasHttpStatus=true`, and send a
`clientTimestamp` query value. If the SDK connects to the raw WDM URL, Webex can
send binary frames that the Swift JSON decoder cannot inspect, which presents as
`Webex realtime WebSocket received unsupported binary frame` followed by
reconnect/backoff.

Currently modeled realtime resources/events:

- `messages`
  - `created`
  - `updated`
  - `deleted`
- `rooms` / spaces
- `memberships`
- `attachmentActions`

Unknown resources and events must remain preserved so newer Webex event shapes
do not break decoding.

The smoke target is `Examples/WebexRealtimeEventsSmoke`. Raw unknown payload
printing is opt-in and must stay redacted by default.

The official 2025 Webex blog describes websocket listening through the Webex
JavaScript SDK, not a simple Webex REST endpoint. Keep the Swift support honest:
it is useful for app-friendly realtime triggers, but the protocol contract is
not documented as a general public REST replacement.

## Stream Integration

`WebexStreamTrigger` is intentionally small and source-agnostic:

- `resource`
- `event`
- `resourceID`
- `roomID`
- `actorID`

Webhook notifications can create a trigger from their metadata and `data`
object. Native WebSocket connections can provide the same trigger shape through
`connection.triggers`. Snapshot Streams accept an
`AsyncStream<WebexStreamTrigger>` and a predicate:

```swift
let connection = client.realtime.connect(options: options)

let task = messagesStream.refreshOnTriggers(connection.triggers) { trigger in
    trigger.resource == "messages" && trigger.roomID == selectedRoomID
}
```

Do not assume REST IDs and realtime IDs are byte-for-byte identical. In live
Mercury message events, `trigger.roomID` can be the underlying room UUID, while
REST list calls commonly use the public base64 Webex ID that decodes to a
`ciscospark://.../ROOM/<uuid>` URI. Stream predicates that filter a REST-backed
room by realtime room ID should compare canonical candidates: exact ID, decoded
URI, and terminal URI component.

The UI still subscribes to `stream.snapshots` and redraws only when a new
snapshot is emitted. The UI does not need to know whether the refresh came from
a button, webhook, WebSocket connection, or another trigger source.

Webhooks remain relevant for integrations that need Webex to call a public
`targetUrl`, server-side fanout, or official target URL-based delivery. The
WebSocket source is the current experimental app-friendly foundation for this
SDK iteration.

Cancel the returned `Task` when the owning app object or window closes.
Cancel the realtime `connection` when the app no longer needs event delivery.

## Test Requirements

- Decode webhook records with all documented fields.
- Preserve unknown resource, event, status, and owned-by values.
- Verify list query construction and one-page pagination.
- Verify next-page requests use `WebexPageLink`.
- Verify create/update encode exactly documented JSON fields and omit nils.
- Verify get/update/delete percent-encode webhook IDs.
- Verify invalid webhook IDs fail before HTTP without leaking raw input.
- Verify HMAC-SHA1 signature validation with a known vector.
- Verify case-insensitive `X-Spark-Signature` header lookup.
- Verify webhook notifications become stream triggers.
- Verify `WebexSnapshotStream.refreshOnTriggers` refreshes on matching
  triggers and ignores non-matching triggers.
- Verify realtime resource/event models preserve unknown values and payloads.
- Verify U2C/WDM device discovery and stale-device retry behavior.
- Verify WebSocket session authorization, ack frames, reconnect/backoff, and
  auth retry behavior.
- Verify realtime event decoding maps modeled resources into stream triggers.
- Verify unknown realtime payload printing is opt-in and redacted by default.
- Verify OAuth realtime smoke validates granted scopes before WDM device
  registration.
- Verify WDM device decoding accepts the live `url`-backed response shape and
  still rejects malformed responses without leaking tokens or socket URLs.
- Verify `Examples/WebexRealtimeEventsSmoke` builds and can be used for live
  smoke validation when credentials are available.
