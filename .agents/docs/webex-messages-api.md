# Webex Messages API Notes

Captured: 2026-05-01

Official reference:

- https://developer.webex.com/messaging/docs/api/v1/messages
- https://developer.webex.com/messaging/docs/api/v1/messages/list-messages
- https://developer.webex.com/messaging/docs/api/v1/messages/create-a-message
- https://developer.webex.com/messaging/docs/api/v1/messages/get-message-details
- https://developer.webex.com/messaging/docs/api/v1/messages/edit-a-message
- https://developer.webex.com/messaging/docs/api/v1/messages/delete-a-message
- https://developer.webex.com/messaging/docs/basics

## Direction

Expose Messages as `client.messages` with the same REST-first shape as Spaces,
Memberships, and People:

- `messages.list(params:)` returns one page and exposes `nextPage`.
- `messages.list(nextPage:)` follows the parsed RFC5988 Webex `Link` URL.
- `messages.create(_:)`, `messages.get(messageID:)`, `messages.edit(messageID:_:)`,
  and `messages.delete(messageID:)` map directly to the documented endpoints.
- Do not add `listAll`, stream, cache, or message search helpers in this REST
  iteration.

## Endpoints

List messages:

- `GET /v1/messages`
- Required query: `roomId`
- Optional query: `parentId`, `mentionedPeople`, `before`,
  `beforeMessage`, `max`
- Sort order is descending by creation date.
- Long result sets use RFC5988 `Link` pagination.
- `mentionedPeople` is documented as an array in the embedded OpenAPI, but the
  text and ecosystem SDKs describe a single string value: `me` or the current
  caller's person ID. Expose the raw string and do not imply arbitrary batch
  lookup behavior.

Create message:

- `POST /v1/messages`
- JSON body fields: `roomId`, `parentId`, `toPersonId`, `toPersonEmail`,
  `text`, `markdown`, `files`, `attachments`
- `files` is an array for forward compatibility, but Webex currently allows
  one remote file URL per message.
- Local file upload uses `multipart/form-data`, not JSON. Defer local file
  upload support until the transport has a narrow multipart body API.
- Message `text` and `markdown` have a documented 7439 byte maximum. Let Webex
  enforce this limit so the SDK does not drift from server behavior.

Get message details:

- `GET /v1/messages/{messageId}`

Edit message:

- `PUT /v1/messages/{messageId}`
- Body fields: required `roomId`, optional `text`, optional `markdown`
- Webex currently does not support editing messages with files or attachments.
- Webex currently supports up to 10 edits per message.
- When editing markdown messages based on a prior `GET`, the `html` field must
  not be sent back.

Delete message:

- `DELETE /v1/messages/{messageId}`
- Success is `204 No Content`.

## Message Model

The response model should preserve all documented fields:

- `id`
- `parentId`
- `roomId`
- `roomType`
- `toPersonId`
- `toPersonEmail`
- `text`
- `markdown`
- `html`
- `files`
- `personId`
- `personEmail`
- `mentionedPeople`
- `mentionedGroups`
- `attachments`
- `created`
- `updated`
- `isVoiceClip`

`roomType` uses the same unknown-preserving enum shape as Spaces and
Memberships.

Attachments are intentionally broad. Webex cards use Adaptive Card JSON, and
the schema can expand independently of this SDK. Model attachment `content` as
JSON values instead of hard-coding every Adaptive Card field.

## Response Codes

The Messages endpoints document:

- `200 OK`
- `204 No Content` for delete
- `400 Bad Request`
- `401 Unauthorized`
- `403 Forbidden`
- `404 Not Found`
- `405 Method Not Allowed`
- `409 Conflict`
- `410 Gone`
- `415 Unsupported Media Type`
- `423 Locked`
- `428 Precondition Required`
- `429 Too Many Requests`
- `500 Internal Server Error`
- `502 Bad Gateway`
- `503 Service Unavailable`
- `504 Gateway Timeout`

Use the existing transport behavior for explicit `WebexAPIErrorKind` exposure,
retry/backoff, redaction, and retry-after handling.

## Security And Safety Notes

- Never log bearer tokens, client secrets, message body text, callback URLs, or
  attachment URLs from SDK-generated errors.
- Do not disable TLS validation.
- Do not pre-validate recipient/body combinations beyond obvious local path
  safety; Webex owns endpoint semantics and server-side validation.
- Adding local file upload later must avoid reading arbitrary file paths without
  an app/user controlled file selection path.

## Test Requirements

- Decode every documented message field, including arbitrary attachment JSON.
- Preserve unknown room type values.
- Reject malformed Webex timestamps.
- Verify list query construction and one-page pagination.
- Verify next-page requests use `WebexPageLink`.
- Verify create encodes JSON fields without adding `nil` keys.
- Verify get/edit/delete percent-encode message IDs.
- Verify `WebexClient` exposes `messages`.
- Verify invalid message IDs fail before HTTP without leaking raw input.
