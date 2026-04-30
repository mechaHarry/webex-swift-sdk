# Webex Spaces API Design

Date: 2026-04-30
Branch: `agentic/webex-rooms-api-v1.1.0`
Target release after merge: `v1.1.0`

## Purpose

This iteration expands the SDK from OAuth plus People into a fuller Webex
Messaging resource client, starting with Spaces. Webex's REST API still names
the resource `/v1/rooms`, but Webex product language increasingly calls these
collaboration containers "spaces". The SDK should spare macOS apps from
manually translating that naming mismatch.

The first implementation priority is listing all spaces for an authenticated
account. After list behavior is correct, the same API group should cover create,
get, update, and delete. `meetingInfo` is explicitly out of scope because it is
EOL as of 2025-01-31.

## Public API Shape

`WebexClient` gains a preferred `spaces` API group and a compatibility `rooms`
alias:

```swift
let spaces = try await client.spaces.list(query: .init(max: 50))
let allSpaces = try await client.spaces.listAll(query: .init(type: .group))
let space = try await client.spaces.get(spaceID: id)
let created = try await client.spaces.create(.init(title: "Incident Review"))
let updated = try await client.spaces.update(spaceID: id, .init(title: "New Title"))
try await client.spaces.delete(spaceID: id)

let sameAPI = client.rooms
```

The SDK should expose modern names first:

- `SpacesAPI`
- `WebexSpace`
- `WebexSpaceType`
- `WebexSpaceSort`
- `ListSpacesQuery`
- `CreateSpaceRequest`
- `UpdateSpaceRequest`
- `WebexSpaceListPage`
- `WebexPartialResourceError`

Compatibility aliases can map Webex REST terminology to the same implementation:

```swift
public typealias RoomsAPI = SpacesAPI
public typealias WebexRoom = WebexSpace
public typealias ListRoomsQuery = ListSpacesQuery
```

The alias exists for developers copying from Webex docs. It should not fork
behavior or create a second implementation path.

## Endpoint Coverage

v1.1.0 covers:

- `GET /v1/rooms`
- `POST /v1/rooms`
- `GET /v1/rooms/{roomId}`
- `PUT /v1/rooms/{roomId}`
- `DELETE /v1/rooms/{roomId}`

v1.1.0 excludes:

- `GET /v1/rooms/{roomId}/meetingInfo`, because the endpoint is EOL.
- Memberships and Messages behavior, except where docs explain that those APIs
  own membership/content operations.

## Data Modeling

`WebexSpace` should model all currently known room/space fields as typed
properties while tolerating partial list records:

- `id`
- `title`
- `type`
- `isLocked`
- `teamId`
- `lastActivity`
- `creatorId`
- `created`
- `ownerId`
- `description`
- `isPublic`
- `isReadOnly`
- `isAnnouncementOnly`
- `classificationId`
- `madePublic`
- `errors`

`id` should be required when Webex returns a space item. Other fields should be
optional because list responses can include partial failures, permission effects,
tenant-policy differences, or fields unavailable on some room types.

Dates should decode to `Date` using Webex ISO8601 formats, including fractional
seconds. If implementation discovers unstable timestamp formats, use a small
SDK date decoding helper rather than ad hoc parsing inside `SpacesAPI`.

To stay forward-compatible, responses should preserve unknown JSON fields in an
explicit raw/additional-properties structure if this can be done without making
the typed model awkward. At minimum, decoders must ignore unknown fields safely.

## Listing And Pagination

List support is the first milestone.

`SpacesAPI.list(query:)` returns one page:

```swift
public struct WebexSpaceListPage: Sendable, Equatable {
    public let items: [WebexSpace]
    public let nextPage: WebexPageLink?
}
```

`SpacesAPI.listAll(query:)` follows `rel="next"` links until absent and returns
all accumulated items. It must keep cancellation responsive and bounded by the
transport's retry policy.

The SDK must implement Webex pagination semantics from the REST Basics page:

- Parse RFC5988 `Link` headers.
- Only rely on `rel="next"`.
- Do not require `first` or `prev`.
- Continue until no `next` link is present.
- Do not stop on an empty page when a next link exists.
- Respect `max`, while accepting that Webex may silently cap it per endpoint.

Because following `Link` requires response headers, `WebexTransport` needs an
internal response-returning API in addition to the current data-only `send`.
The existing `send(_:) -> Data` can remain for simple endpoints.

## Partial Resource Errors

Webex list responses can return HTTP `200 OK` while individual items contain an
`errors` object. The SDK must preserve those item errors:

```swift
public struct WebexPartialResourceError: Equatable, Decodable, Sendable {
    public let code: String
    public let reason: String
}
```

For room/space items, expose a dictionary keyed by field name where possible:

```swift
public let errors: [String: WebexPartialResourceError]?
```

The presence of per-item errors should not fail the whole page. Host apps can
then show degraded rows, retry later, or surface the specific field failure.

## Create, Get, Update, Delete

Create should require `title` for normal group spaces and allow optional fields
that are confirmed by official Webex references, such as `teamId`,
`classificationId`, `isLocked`, `isPublic`, `description`, and
`isAnnouncementOnly`.

Update should use an explicit request type rather than reusing the response
model. This avoids accidentally sending read-only fields back to Webex:

```swift
public struct UpdateSpaceRequest: Encodable, Sendable {
    public var title: String?
    public var teamId: String?
    public var classificationId: String?
    public var isLocked: Bool?
    public var isPublic: Bool?
    public var description: String?
    public var isAnnouncementOnly: Bool?
    public var isReadOnly: Bool?
}
```

Request builders should encode obvious Webex rules only when they are confirmed
and stable, such as public spaces requiring descriptions. Ambiguous rules,
license restrictions, compliance-officer-only behavior, org policy, and
tenant-specific limitations should be surfaced as structured Webex API errors.

Delete should treat successful no-body responses as success and return `Void`.
Docs and errors should explain that Webex may delete, archive, or remove the
current user depending on room/team/moderator rules.

## Status And Error Handling

The existing transport already preserves Webex status codes through
`WebexSDKError.webexAPI`, handles `429`, retries `5xx`, and retries one `401`
after invalidating the access token. v1.1.0 should make status meanings more
explicit without regressing existing callers.

Add a small public classification layer, for example:

```swift
public enum WebexAPIErrorKind: Equatable, Sendable {
    case badRequest
    case unauthorized
    case forbidden
    case notFound
    case methodNotAllowed
    case conflict
    case gone
    case unsupportedMediaType
    case locked(retryAfter: TimeInterval?)
    case preconditionRequired
    case rateLimited(retryAfter: TimeInterval?)
    case serverError
    case unexpected(statusCode: Int)
}
```

Expose it through computed properties on `WebexSDKError` or through a
non-breaking error context type. Do not remove existing error cases.

Transport retry rules should cover:

- transient network errors
- `429` with `Retry-After` when present
- `423` when retryable and `Retry-After` is present
- `500`, `502`, `503`, `504`

All error surfaces must continue to redact secrets and preserve Webex tracking
headers where available.

## Agent Documentation

This branch adds agent-facing notes under `.agents/docs`:

- Webex REST basics: pagination, rate limits, partial failures, return codes,
  attachments, markdown, and TLS/SNI notes.
- Spaces/Rooms notes: naming policy, endpoint scope, known fields, list-first
  priority, return-code mapping, and `meetingInfo` exclusion.

These notes are intentionally more operational than the design spec so future
agents can quickly recover Webex-specific behavior before editing code.

## Testing Strategy

Use test-driven development for implementation.

Focused tests:

- `WebexClient` exposes `spaces` and `rooms` aliasing the same API behavior.
- `SpacesAPI.list` sends `GET /v1/rooms` with typed query parameters.
- `SpacesAPI.list` decodes all known fields.
- List response decodes item-level `errors` without failing the whole page.
- Pagination parser extracts `rel="next"` from `Link`.
- `listAll` follows `next` through empty pages and stops only when absent.
- Create encodes only allowed request fields and decodes `201`.
- Get sends `GET /v1/rooms/{roomId}` with safe path handling.
- Update sends `PUT /v1/rooms/{roomId}` and excludes read-only response fields.
- Delete accepts success with no body.
- Error classification maps documented Webex status codes.
- Retry/backoff behavior continues to honor `429`, `Retry-After`, cancellation,
  and existing `5xx` behavior.
- `423` retry/classification behavior is covered.
- Malformed/failed decoding tests do not leak bearer tokens or secrets.

If live smoke examples are added later, they should start with safe read-only
list behavior before create/update/delete flows.

## Open Verification Items

Before implementation commits the final public request/response field set, verify
the exact current Rooms endpoint details against an official live Webex source:

- Webex Developer portal with dynamic endpoint tables.
- Official Webex Postman/OpenAPI export.

Specific items to confirm:

- Exact create and update request fields.
- Whether `isReadOnly`, `isAnnouncementOnly`, `classificationId`, `madePublic`,
  and `description` are returned for all tenants or only feature-enabled tenants.
- Exact list `sortBy` accepted values and default ordering.
- Exact endpoint-specific `max` cap.
- Required OAuth scopes for read and write operations.
- Any current public-space, announcement-mode, team-assignment, and compliance
  officer restrictions.
