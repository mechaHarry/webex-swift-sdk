# Webex People API v2.0.0 Design

Date: 2026-05-01
Branch: `agent/webex-people-api-v2.0.0`
Target tag after merge: `v2.0.0`

## Goal

Implement the read-focused Webex People API surface and use the same iteration to
clean up the SDK's public list API shape before it stabilizes.

The primary user workflow is a macOS app that lists memberships in a space, then
uses the official People API to query richer person details. The SDK should
expose Webex endpoints accurately and handle REST mechanics, but it should not
invent a Memberships-to-People orchestration layer.

Primary Webex sources:

- https://developer.webex.com/messaging/docs/api/v1/people
- https://developer.webex.com/messaging/docs/basics

## Scope

Implement these official People endpoints:

- `GET /v1/people`: list/search people.
- `GET /v1/people/{personId}`: get person details.
- `GET /v1/people/me`: get the authenticated user's details.

Do not implement People create, update, or delete in this iteration. Webex
recommends SCIM 2.0 for user management/provisioning, and admin write APIs are
not required for member drilldown.

## Public API Shape

Use `Params` for request parameter bags. `Query` reads like an action to SDK
users, while these values are only parameter containers.

Breaking renames:

- `ListSpacesQuery` becomes `ListSpacesParams`.
- `ListMembershipsQuery` becomes `ListMembershipsParams`.
- New People list parameters use `ListPeopleParams`.
- List methods use `params:` labels instead of `query:`.

No backwards compatibility aliases are needed because the SDK API is still under
active design.

## Pagination Shape

Webex pagination is not returned in JSON. It is returned in the HTTP `Link`
header with `rel="next"`. The SDK will continue parsing that header into
`WebexPageLink`, exposed as `page.nextPage`.

The SDK should not expose `listAll` as the normal public pattern. It encourages
UI clients to fetch more data than they need. Instead:

```swift
let firstPage = try await client.spaces.list(params: .init(max: 10))

if let nextPage = firstPage.nextPage {
    let secondPage = try await client.spaces.list(nextPage: nextPage)
}
```

The app controls when to fetch another page. It should not call again with a
larger `max` and slice locally, and it should not calculate the next page from a
resource ID. Webex owns the pagination cursor.

Apply this shape consistently:

- `spaces.list(params:)`
- `spaces.list(nextPage:)`
- `memberships.list(params:)`
- `memberships.list(nextPage:)`
- `people.list(params:)`
- `people.list(nextPage:)`

Remove existing `listAll` methods from Spaces and Memberships during this
breaking release. Smoke examples that need more than one page must loop
explicitly over `nextPage` with a local page cap.

## People Parameters

`ListPeopleParams` should mirror Webex's documented query parameters:

- `email`
- `displayName`
- `id`
- `orgID` encoded as `orgId`
- `roles`
- `callingData`
- `locationID` encoded as `locationId`
- `max`
- `excludeStatus`

The `id` value remains a raw comma-separated string because that is the official
REST parameter. Webex documents that it accepts up to 85 person IDs, but the SDK
will not add a custom `personIDs` array or client-side batch filter type. The
SDK should document the limit and surface Webex's server response directly.

`people.me(callingData:)` and `people.get(personID:callingData:)` should expose
the documented `callingData` query parameter.

## People Models

Expand `WebexPerson` to cover the read response fields documented by Webex:

- `id`
- `emails`
- `phoneNumbers`
- `extension`
- `locationID`
- `displayName`
- `nickName`
- `firstName`
- `lastName`
- `avatar`
- `orgID`
- `roles`
- `licenses`
- `department`
- `manager`
- `managerID`
- `title`
- `addresses`
- `created`
- `lastModified`
- `timezone`
- `lastActivity`
- `siteUrls`
- `sipAddresses`
- `xmppFederationJid`
- `status`
- `invitePending`
- `loginEnabled`
- `type`

Date fields should decode with the existing Webex date decoder. Unknown enum
values should be preserved instead of failing decoding, using the same
unknown-preserving style already used for spaces.

`WebexPersonListPage` should expose:

- `items: [WebexPerson]`
- `notFoundIDs: [String]?`, decoded from Webex's `notFoundIds`
- `nextPage: WebexPageLink?`, derived from the HTTP `Link` header

## Error And Security Behavior

People calls should use the existing authenticated transport so token refresh,
rate-limit backoff, status-code mapping, cancellation, and redaction stay
centralized.

Status handling must explicitly cover the documented Webex People response
codes: `200`, `400`, `401`, `403`, `404`, `405`, `409`, `410`, `415`, `423`,
`428`, `429`, `500`, `502`, `503`, and `504`.

Do not include access tokens, full pagination URLs, person emails, or person IDs
in SDK-generated error messages. Returned model values may contain PII because
that is the API's data contract, but error strings should stay redacted.

`WebexPageLink` should continue accepting only HTTPS links for
`webexapis.com`.

## Documentation

Add `.agents/docs/webex-people-api.md` with the official endpoint notes and
quirks:

- SCIM is preferred for provisioning.
- `spark:people_read` is required for normal read/search.
- `spark-admin:people_read` is required for org-wide listing.
- People write scopes exist but are out of scope for v2.0.0.
- Presence fields may be absent depending on org relationship and status
  sharing.
- Frequent presence polling through `/people` can trigger `429`.
- `callingData` requires Webex Calling licensing and admin context.
- `id` accepts comma-separated person IDs and may omit presence fields.
- Pagination comes from the `Link` header, not the JSON body.

Update README examples to use `params:` and caller-controlled pagination.

## Smoke Examples

Update existing smoke examples for breaking API changes:

- `Examples/WebexSpacesListSmoke` uses `spaces.list(params:)` and an explicit
  `nextPage` loop with the existing page-size and max-pages options.
- `Examples/WebexMembershipsListSmoke` uses `memberships.list(params:)` and an
  explicit `nextPage` loop with bounded pagination.

Add a People read smoke example:

- It should authenticate through the existing registry/loopback flow.
- It should call `people.me()`.
- It should call `people.get(personID:)` for the authenticated person.
- It should call `people.list(params:)` using either a user-supplied
  comma-separated `WEBEX_PEOPLE_IDS` value or the authenticated user's ID.
- It should print minimal, useful fields and avoid printing tokens or callback
  URLs.
- It should compile as part of verification.

## Tests

Every feature must have focused tests:

- People `me` sends `GET /v1/people/me`, encodes `callingData` when present,
  and decodes the expanded person model.
- People `get` safely percent-encodes the `personId` path segment and decodes
  the expanded model.
- People `list` sends all documented params with official wire names and
  decodes `items`, `notFoundIds`, and `Link` pagination.
- People `list(nextPage:)` follows only a parsed `WebexPageLink`.
- Existing Spaces and Memberships tests are updated from `Query`/`listAll` to
  `Params`/explicit `nextPage` pagination.
- README and smoke example API names compile.

Run at minimum:

- `swift test`
- `swift build`
- `swift build --package-path Examples/WebexClientSmoke`
- `swift build --package-path Examples/WebexSpacesListSmoke`
- `swift build --package-path Examples/WebexMembershipsListSmoke`
- `swift build --package-path Examples/WebexPeopleReadSmoke`
- `git diff --check`

## Open Decisions

None. The design intentionally keeps People read-focused, endpoint-faithful, and
caller-controlled for pagination.
