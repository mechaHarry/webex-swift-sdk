# Webex Spaces / Rooms API Notes

Date captured: 2026-04-30

Primary sources:

- https://developer.webex.com/messaging/docs/api/v1/rooms
- https://developer.webex.com/messaging/docs/basics
- https://developer.webex.com/blog/announcing-the-official-webex-postman-workspace

The Webex REST resource is still named `/v1/rooms`, but modern Webex product
language uses "spaces". In this SDK, prefer "Spaces" for public domain language
and keep "Rooms" as a compatibility alias for developers reading Webex REST
documentation.

## Scope For v1.1.0

Implement the core Rooms API as a Spaces API:

- `GET /v1/rooms`: list spaces.
- `POST /v1/rooms`: create a group/team/public space where supported.
- `GET /v1/rooms/{roomId}`: get one space by ID.
- `PUT /v1/rooms/{roomId}`: update one space by ID.
- `DELETE /v1/rooms/{roomId}`: delete/archive/remove according to Webex rules.

Do not implement `GET /v1/rooms/{roomId}/meetingInfo` in v1.1.0. The endpoint
is EOL as of 2025-01-31 and should be treated as legacy/deprecated.

## Naming Policy

- Preferred SDK API group: `client.spaces`.
- Compatibility alias: `client.rooms`.
- Preferred model names: `WebexSpace`, `WebexSpaceType`,
  `ListSpacesParams`, `CreateSpaceRequest`, `UpdateSpaceRequest`.
- Compatibility aliases can map room names to the same types:
  `WebexRoom = WebexSpace`, `RoomsAPI = SpacesAPI`.
- Public docs should say that "room" and "space" map to the same Webex REST
  object, and `/v1/rooms` is the wire contract.

## Known Endpoint Semantics

- Rooms/spaces are virtual collaboration places where users post messages and
  collaborate.
- The Rooms API manages the room/space resource itself: create, delete, and
  update properties such as title or public visibility.
- Team spaces are created by specifying `teamId` in the `POST` body.
- Once a room is added to a team, it cannot be freely moved; update semantics
  around `teamId` need careful live verification.
- Room membership management belongs to the Memberships API.
- Message/content posting belongs to the Messages API.
- 1:1 direct spaces are not created through the Rooms API; create a direct
  conversation by sending a message to a person through Messages.

## List Spaces First

List is the first priority for v1.1.0.

Likely query parameters to confirm against the official live reference/export:

- `teamId`: limit rooms to those associated with a team.
- `type`: filter by `direct` or `group`.
- `sortBy`: sort by `id`, `lastactivity`, or `created`.
- `max`: maximum items per page; endpoint may cap it.

List behavior:

- Default is rooms/spaces visible to the authenticated user.
- Long result sets paginate with RFC5988 `Link`.
- Use `spaces.list(params:)` for one Webex page. If `page.nextPage` is
  present, the host app can call `spaces.list(nextPage:)` when it wants the
  next page. Do not fetch every page by default for UI views.
- Return per-item partial errors rather than failing an entire list page.

## Space Fields To Model

Model all known fields as typed optional properties unless an endpoint response
proves the field is always present. List partial failures can omit normally
expected values.

Known room/space fields to confirm and cover:

- `id`: unique room/space identifier.
- `title`: user-facing space title. In direct spaces, this can be the other
  person's display name.
- `type`: `direct` or `group`.
- `isLocked`: moderated/locked state.
- `teamId`: team association, when present.
- `lastActivity`: timestamp of last activity.
- `creatorId`: person ID of the creator.
- `created`: creation timestamp.
- `ownerId`: organization owner ID.
- `description`: space description.
- `isPublic`: whether the space is discoverable within the org.
- `isReadOnly`: whether new information exchanges are disallowed.
- `isAnnouncementOnly`: announcement mode flag.
- `classificationId`: data classification/category ID.
- `madePublic`: timestamp when a space was made public, when present.
- `errors`: per-field/per-resource partial retrieval errors.

Date fields should decode Webex ISO8601 timestamps with fractional seconds when
possible. Preserve enough raw context to avoid dropping useful future fields.

## Request Rules To Encode

Encode obvious, documented-safe rules in request builders. Keep ambiguous or
tenant-policy-specific rules as server-side errors surfaced meaningfully.

Known rules and likely rules to verify:

- Create requires a title for normal group spaces.
- `teamId` at create time creates a team space.
- Public spaces require a description.
- Announcement-only mode requires the space to be locked.
- Some room features may depend on paid plans, compliance officer permissions,
  org policy, or admin capability.
- Removing a description may require a single-space string rather than empty or
  null in some Webex clients/SDKs; confirm before encoding.

## Return Code Handling

Use the Webex REST basics status meanings as the SDK baseline:

- Treat `200`, `201`, `202`, and `204` as success where endpoint-appropriate.
- `400`: malformed request or invalid field combination.
- `401`: authentication failure; token invalidation/refresh path should already
  have one retry before surfacing reauthentication or API failure.
- `403`: authenticated but not allowed, often permission/org policy.
- `404`: invalid URI or space not found.
- `405`: method unsupported.
- `409`: system-rule conflict.
- `410`: resource no longer available.
- `415`: unsupported/missing content type.
- `423`: temporarily locked; retry if `Retry-After` is present and retry budget
  remains, otherwise expose as locked/unavailable.
- `428`: precondition required, mostly relevant to file download flows but keep
  a generic explicit mapping.
- `429`: rate limited; honor `Retry-After`.
- `500`, `502`, `503`, `504`: retry with bounded backoff, then surface as Webex
  API/server failure with tracking ID if present.

The SDK should expose enough structured error context for apps to distinguish:

- bad request
- unauthorized/reauthentication required
- forbidden
- not found
- conflict
- gone
- unsupported media type
- locked with retry-after
- precondition required
- rate limited with retry-after
- retryable server failure exhausted
- unexpected status

## Implementation Verification Notes

- The Webex Developer endpoint pages can render sparse HTML without the dynamic
  endpoint tables in simple crawlers. During implementation, verify exact
  endpoint parameters, request bodies, response fields, scopes, and status codes
  against the live Webex Developer portal or official Postman/OpenAPI export.
- The official Webex Postman workspace is described by Webex as generated from
  their OpenAPI specification and can be used as a secondary official reference.
- Do not rely on third-party SDKs as source of truth. They are useful only for
  identifying fields to confirm against Webex.
