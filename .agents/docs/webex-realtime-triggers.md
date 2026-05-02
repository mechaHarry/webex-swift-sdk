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
let connection = try await client.realtime.connect(options: options)
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

The implementation is sample-backed and experimental. It uses U2C/WDM device
discovery, `URLSessionWebSocketTask`, authorization frames, ack frames,
reconnect/backoff, stale-device retry, auth retry, unknown event preservation,
unknown payload preservation, and trigger mapping.

Currently modeled realtime resources/events:

- `messages`
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
let connection = try await client.realtime.connect(options: options)

let task = messagesStream.refreshOnTriggers(connection.triggers) { trigger in
    trigger.resource == "messages" && trigger.roomID == selectedRoomID
}
```

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
- Verify `Examples/WebexRealtimeEventsSmoke` builds and can be used for live
  smoke validation when credentials are available.
