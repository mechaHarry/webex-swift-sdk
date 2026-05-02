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

Do not describe this SDK layer as fully real-time until trigger delivery,
signature verification, and stream reconciliation have been exercised in an app
or smoke target.

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

## Websocket Notes

The official 2025 Webex blog describes websocket listening through the Webex
JavaScript SDK, not a simple Webex REST endpoint. It says websocket listeners
can be created for memberships, rooms, messages, and attachment actions with
SDK resource `listen()` and `on()` methods, and that this avoids the public
`targetUrl` requirement of webhooks.

For this Swift SDK, do not assume those JavaScript SDK internals are directly
portable. Future work should research whether Webex exposes a documented,
supported websocket protocol or Swift-friendly transport contract. Until then,
webhooks are the first concrete trigger source for this package.

## Stream Integration

`WebexStreamTrigger` is intentionally small and source-agnostic:

- `resource`
- `event`
- `resourceID`
- `roomID`
- `actorID`

Webhook notifications can create a trigger from their metadata and `data`
object. Snapshot Streams accept an `AsyncStream<WebexStreamTrigger>` and a
predicate:

```swift
let task = messagesStream.refreshOnTriggers(webhookTriggers) { trigger in
    trigger.resource == "messages" && trigger.roomID == selectedRoomID
}
```

The UI still subscribes to `stream.snapshots` and redraws only when a new
snapshot is emitted. The UI does not need to know whether the refresh came from
a button, webhook, future websocket listener, or another trigger source.

Cancel the returned `Task` when the owning app object or window closes.

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
