# Webex REST API Basics Notes

Date captured: 2026-04-30

Primary source: https://developer.webex.com/messaging/docs/basics

These notes capture Webex REST API behavior that SDK work should treat as
platform-level assumptions. The Webex docs describe broad semantics, not every
endpoint limit or product-specific rule. Confirm endpoint-specific behavior
against the live Webex Developer portal, official Postman/OpenAPI export, and
smoke tests before locking public SDK behavior.

## Pagination

- Webex list endpoints can paginate long result sets.
- Pagination uses RFC5988 Web Linking through the HTTP `Link` response header.
- `rel="next"` is the only link relation guaranteed by Webex at this time.
- `first` and `prev` can appear, but SDK behavior must not require them.
- Continue paginating until no `rel="next"` link is present.
- A page can be empty even when a `Link` header was present on the prior page.
  Do not treat an empty `items` array as end-of-pagination by itself.
- The `max` query parameter controls page size for list endpoints.
- If the requested `max` exceeds an endpoint-specific cap, Webex returns only
  the endpoint cap. A `rel="next"` link appears if more results remain.
- SDK list helpers should expose both one-page and all-pages workflows:
  callers sometimes need pagination control, cancellation, or progress.

## Rate Limits And Backoff

- `429 Too Many Requests` means a rate limit was hit.
- Webex returns `Retry-After` on `429`; honor it when present.
- Webex says rate limits are fine-grained, overlapping, and too complex to
  document exactly.
- A broad rule from the docs is around 300 requests per minute for most REST
  APIs, while `/people` and `/messages` have dynamically adjusted higher quotas.
  Treat this as guidance, not a contract.
- Large workloads should avoid normal end-user accounts when possible.
- Bot accounts can have less restrictive limits, but content ownership rules can
  make bot accounts unsuitable for some messaging automation.
- Concurrent workloads sharing one authenticated user share that user's rate
  limits. Partition large workloads across separate users/accounts where the
  product and organization model allows it.
- SDK transport must use graceful backoff for retryable status codes and network
  failures. Preserve cancellation and avoid infinite retries.

## HTTP Status Codes

Common Webex status codes from the REST basics page:

- `200 OK`: successful request with body content.
- `201 Created`: successful creation.
- `202 Accepted`: request accepted for processing.
- `204 No Content`: successful request with no body.
- `400 Bad Request`: invalid request; response may explain the issue.
- `401 Unauthorized`: missing or incorrect authentication credentials.
- `403 Forbidden`: request understood, but refused or not allowed.
- `404 Not Found`: invalid URI, missing resource, or unsupported format for the
  requested method.
- `405 Method Not Allowed`: method unsupported for the resource.
- `409 Conflict`: conflicts with a system rule, such as adding a person to a
  room more than once.
- `410 Gone`: resource is no longer available.
- `415 Unsupported Media Type`: missing or unsupported media type.
- `423 Locked`: resource temporarily unavailable; `Retry-After` may be present.
- `428 Precondition Required`: file cannot be scanned for malware and requires
  explicit force-download behavior.
- `429 Too Many Requests`: rate limited; `Retry-After` should be present.
- `500 Internal Server Error`: Webex server error.
- `502 Bad Gateway`: invalid upstream response; try later.
- `503 Service Unavailable`: server overloaded; try later.
- `504 Gateway Timeout`: upstream timeout; if using `max`, try reducing it.

SDK implications:

- Preserve Webex tracking headers when available.
- Expose status code meaning explicitly enough for app code to distinguish auth,
  permission, missing resource, conflict, retryable, and unknown cases.
- Do not leak access tokens, refresh tokens, client secrets, authorization codes,
  PKCE verifiers, or callback URLs in error messages.
- Retry only bounded, documented-safe cases: transient network failures,
  `429`, retryable `423`, and `5xx`.

## Partial Failures In List Responses

- Some list endpoints can return HTTP `200 OK` while individual resources inside
  `items` contain an `errors` object.
- The errors object appears only when at least one resource could not be fully
  retrieved.
- Webex gives `kms_failure` as an example for an item whose encrypted field could
  not be retrieved because KMS failed or timed out.
- SDK list decoders must not fail the entire page only because one item contains
  per-field errors.
- Preserve per-item errors in the returned model so host apps can present a
  useful degraded state and optionally retry later.

## Message Attachments

These notes are for future Messages work, not Rooms/Spaces v1.1.0:

- Local file uploads use `multipart/form-data`, not JSON.
- Remote file attachments use a URL inside the JSON `files` parameter.
- The docs state the remote `files` JSON parameter currently takes one URL.
- Attachment file size is limited to 100 MB each.
- Webex clients preview common document and image types: Word, Excel,
  PowerPoint, PDF, JPEG, BMP, GIF, and PNG.
- File metadata can be checked with `HEAD` against the content URL with bearer
  auth.
- File download uses `GET` against the content URL with bearer auth.
- Anti-malware scanning can produce `423 Locked` with `Retry-After`, `410 Gone`
  for infected unavailable files, or `428 Precondition Required` for
  unscannable files. `allow=unscannable` is an explicit risk acceptance path.

## Message Formatting

These notes are for future Messages work:

- Webex supports a limited Markdown subset.
- To create paragraph breaks in JSON message bodies, use two newline characters.
- To create a single line break, end the line with two spaces followed by a
  newline.
- Supported constructs include bold, italic, links, ordered lists, unordered
  lists, nested lists, block quotes, inline code, fenced code blocks, and
  mentions.
- Mention syntaxes include person email, person ID, and group mentions such as
  `all`.

## TLS And SNI

- Webex requires TLS clients that support Server Name Indication.
- Never configure a client to ignore SSL/TLS validation errors.
- URLSession on supported Apple platforms satisfies this; do not add SDK escape
  hatches that disable trust validation.
