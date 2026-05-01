# Webex Memberships API Design

Date: 2026-05-01
Branch: `agent/webex-memberships-api-v1.2.0`
Target release after merge: `v1.2.0`

## Purpose

This iteration adds a typed SDK surface for the Webex Messaging Memberships API.
Memberships describe a person's relationship to a room/space: listing room
participants, inviting someone to a space, changing moderator state, and
removing someone from a space.

The host macOS app should not hand-roll `/v1/memberships` requests. It should be
able to use `WebexClient` for account-scoped token lifecycle, authenticated
transport, pagination, Webex status handling, and safe request construction.

Compliance Officer behavior is intentionally out of scope for v1.2.0. The SDK
will document that Webex supports compliance-scoped membership reads/writes, but
this iteration focuses on normal user and bot membership management where the
authenticated account has access to the relevant room.

## Public API Shape

`WebexClient` gains a new `memberships` API group:

```swift
let page = try await client.memberships.list(query: .init(roomID: space.id, max: 100))
let allMembers = try await client.memberships.listAll(query: .init(roomID: space.id))
let created = try await client.memberships.create(.init(
    roomID: space.id,
    personEmail: "person@example.com"
))
let membership = try await client.memberships.get(membershipID: created.id)
let updated = try await client.memberships.update(
    membershipID: membership.id,
    .init(isModerator: true)
)
try await client.memberships.delete(membershipID: updated.id)
```

Primary types:

- `MembershipsAPI`
- `WebexMembership`
- `ListMembershipsQuery`
- `WebexMembershipListPage`
- `CreateMembershipRequest`
- `UpdateMembershipRequest`

Memberships are inherently tied to Webex's existing Rooms/Spaces terminology.
Public models should use Webex wire names where the field is a documented API
field, such as `roomID`, while README examples can say "space" in prose.

## Endpoint Coverage

v1.2.0 covers:

- `GET /v1/memberships`
- `POST /v1/memberships`
- `GET /v1/memberships/{membershipId}`
- `PUT /v1/memberships/{membershipId}`
- `DELETE /v1/memberships/{membershipId}`

v1.2.0 excludes:

- Compliance Officer-specific listing or mutation helpers.
- Team Memberships, Resource Group Memberships, SCIM Groups, and identity group
  membership APIs.
- Read-receipt or read-status behavior from mobile messaging SDKs. The public
  Webex REST Memberships endpoint is the scope for this iteration.
- Webhook event modeling for `memberships` resources. Webhooks should be a later
  API group.

## OAuth Scopes

Normal membership usage needs:

- `spark:memberships_read` for list and get.
- `spark:memberships_write` for create, update, and delete.

The SDK should not enforce scopes locally. OAuth configuration is caller-owned,
and Webex returns `401` or `403` when credentials are insufficient. Documentation
and smoke examples should show the right scopes so failures are easy to
diagnose.

Compliance scopes such as `spark-compliance:memberships_read` and
`spark-compliance:memberships_write` are acknowledged but not modeled as first-
class API flows in v1.2.0.

## Data Modeling

`WebexMembership` should model all known fields:

- `id`
- `roomId`
- `roomType`
- `personId`
- `personEmail`
- `personDisplayName`
- `personOrgId`
- `isModerator`
- `isMonitor`
- `isRoomHidden`
- `created`

`id` should be required for a decoded membership. Other fields should be optional
because Webex can vary fields across list/detail/create responses, room types,
product policy, or future service changes.

`roomType` should reuse `WebexSpaceType` if the wire values match `direct` and
`group`. This keeps room/space type semantics consistent across Spaces and
Memberships.

`created` should decode to `Date` through `WebexDateDecoding`, matching the
Spaces implementation. Decoders should ignore unknown fields safely.

`isMonitor` should be exposed as a nullable boolean because Webex responses and
legacy SDKs still show it. The SDK should not create special behavior around
monitoring bots in v1.2.0.

`isRoomHidden` should be exposed as a nullable boolean. It can appear in response
models and may be mutable through update semantics, but the SDK should not infer
UI behavior from it.

## Listing And Pagination

`MembershipsAPI.list(query:)` returns one page:

```swift
public struct WebexMembershipListPage: Sendable, Equatable {
    public let items: [WebexMembership]
    public let nextPage: WebexPageLink?
}
```

`MembershipsAPI.listAll(query:maxPages:)` follows `rel="next"` links until no
next page remains and returns all accumulated memberships.

List query fields:

- `roomID`: list memberships associated with a room.
- `personID`: filter memberships by person ID.
- `personEmail`: filter memberships by email address.
- `max`: page size.

The SDK should send only non-nil query items. It should not locally reject
combinations that Webex may support or refine over time, except for obviously
ambiguous identity creation payloads described below.

Pagination behavior should be shared conceptually with Spaces:

- Parse RFC5988 `Link` headers through `WebexPageLink`.
- Only follow `rel="next"`.
- Keep cancellation responsive between pages.
- Enforce `maxPages > 0`.
- Detect repeated pagination requests before refetching a page.
- Surface fixed, non-secret SDK-generated pagination error messages.

If Memberships pagination logic duplicates non-trivial code from Spaces, extract
a small internal helper only when it reduces real duplication without making API
files harder to understand. Avoid a broad generic pagination framework unless a
later paginated API group proves the pattern.

## Create

`CreateMembershipRequest` should encode:

- `roomId`: required.
- `personId`: set by the person-ID initializer.
- `personEmail`: set by the person-email initializer.
- `isModerator`: optional.

The public API should make invalid identity combinations unrepresentable by
offering two non-throwing initializers and no general public initializer that
accepts both optional identity fields:

```swift
public init(
    roomID: String,
    personID: String,
    isModerator: Bool? = nil
)

public init(
    roomID: String,
    personEmail: String,
    isModerator: Bool? = nil
)
```

This keeps ordinary call sites simple:

```swift
CreateMembershipRequest(roomID: roomID, personID: personID, isModerator: false)
CreateMembershipRequest(roomID: roomID, personEmail: email, isModerator: false)
```

Tests should prove each initializer encodes exactly one identity field. The
implementation does not need runtime checks for missing or duplicate identities
when the public API shape prevents those states.

Successful create responses decode to `WebexMembership`.

## Get, Update, Delete

`get(membershipID:)` sends `GET /v1/memberships/{membershipId}` and decodes
`WebexMembership`.

`UpdateMembershipRequest` should encode only mutable membership fields confirmed
for this endpoint:

- `isModerator`
- `isRoomHidden`

The update method sends `PUT /v1/memberships/{membershipId}` and decodes
`WebexMembership`. It should not send read-only fields such as person IDs, room
IDs, display names, organization IDs, `created`, or `isMonitor`.

`delete(membershipID:)` sends `DELETE /v1/memberships/{membershipId}` and
returns `Void` on successful no-content responses. Public docs should state that
Webex product permissions decide whether the authenticated account can remove
that member.

Path construction for membership IDs must match Spaces path safety:

- Trim whitespace and reject empty IDs.
- Percent-encode ID path segments.
- Mark encoded paths with `isPathPercentEncoded: true`.
- Never accept absolute URLs or scheme-relative paths as API paths.

## Error Handling And Security

Memberships should rely on `WebexTransport` for:

- Bearer token injection.
- Coordinated token refresh.
- `401` invalidation and retry.
- Retry/backoff for `429`, retryable `423`, transient network failures, and
  `5xx`.
- Webex status classification through `WebexAPIErrorKind`.
- Redaction of access tokens, refresh tokens, client secrets, authorization
  codes, callback URLs, and PKCE material.

SDK-generated validation errors should be short and fixed, for example:

- `Invalid Webex membership ID`
- `Create membership requires exactly one person identity`
- `Memberships pagination page cap exceeded`
- `Repeated Memberships pagination link`

Errors must not include membership IDs, person emails, tokens, authorization
headers, or full URLs unless those values came from Webex API structured fields
that are already intentionally exposed by existing error types. Prefer safe
messages for SDK validation paths.

## Documentation And Examples

README should add a concise Memberships section after Spaces:

```swift
let members = try await client.memberships.listAll(query: .init(roomID: spaceID))
let created = try await client.memberships.create(.init(
    roomID: spaceID,
    personEmail: "person@example.com"
))
let updated = try await client.memberships.update(
    membershipID: created.id,
    .init(isModerator: true)
)
try await client.memberships.delete(membershipID: updated.id)
```

`.agents/docs/webex-memberships-api.md` should capture endpoint notes, field
semantics, scope requirements, and out-of-scope compliance behavior so future
agents do not rediscover the same constraints.

Add an example smoke program only if it can avoid destructive surprises. A safe
first smoke should list memberships for a provided `WEBEX_ROOM_ID` and print
member metadata. Creating, moderating, or deleting members should be a separate
manual smoke or require explicit environment variables.

## Tests

Tests should cover:

- `WebexMembership` decodes all known fields and dates.
- Unknown `roomType` values are preserved via `WebexSpaceType.unknown`.
- `ListMembershipsQuery` sends `roomId`, `personId`, `personEmail`, and `max`.
- `list` decodes items and pagination headers.
- `listAll` follows multiple pages, handles empty pages, enforces `maxPages`,
  and rejects repeated next links before refetching.
- `create` encodes `roomId`, exactly one person identity, and optional
  `isModerator`.
- `CreateMembershipRequest` exposes no public initializer that can create a
  missing-identity or duplicate-identity request.
- `get`, `update`, and `delete` percent-encode membership ID path segments.
- `update` encodes only mutable fields.
- `delete` accepts successful no-body responses.
- `WebexClient` exposes `memberships`.
- SDK-generated errors do not leak tokens, emails, membership IDs, or URLs.

## Out Of Scope

- Compliance Officer convenience APIs.
- Team Memberships and Resource Group Memberships.
- Messages, read receipts, and read statuses.
- Webhook event resource modeling.
- Local caching of memberships.
- UI behavior for hidden rooms or moderator state.

## References

- Webex Memberships overview:
  https://developer.webex.com/messaging/docs/api/v1/memberships
- Webex OAuth scopes:
  https://developer.webex.com/docs/authentication
- Cisco membership response example:
  https://www.cisco.com/c/en/us/support/docs/cloud-systems-management/hybrid-cloud-platform-google-cloud/217874-configure-a-new-moderator-for-an-unmoder.html
- Existing SDK Spaces implementation and design:
  `Sources/WebexSwiftSDK/API/SpacesAPI.swift`
  `docs/superpowers/specs/2026-04-30-webex-spaces-api-design.md`
