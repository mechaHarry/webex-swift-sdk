# Webex People API Notes

Date captured: 2026-05-01

Primary sources:

- https://developer.webex.com/messaging/docs/api/v1/people
- https://developer.webex.com/messaging/docs/basics

## v2.0.0 Scope

People support in v2.0.0 is read-focused only:

- `GET /v1/people`
- `GET /v1/people/{personId}`
- `GET /v1/people/me`

Do not implement create, update, or delete People APIs in v2.0.0. Webex
recommends SCIM 2.0 for user management, provisioning, and maintenance.

## Scopes

- `spark:people_read`: normal search and detail reads.
- `spark-admin:people_read`: org-wide listing.
- `spark-admin:people_write` plus `spark-admin:people_read`: write APIs, out
  of scope for v2.0.0.

The SDK does not enforce scopes locally. Webex returns `401` or `403` when the
token lacks permission.

## List Parameters

`ListPeopleParams` mirrors documented query parameters only:

- `email`
- `displayName`
- `id`
- `orgId`
- `roles`
- `callingData`
- `locationId`
- `max`
- `excludeStatus`

`id` is a comma-separated string. Webex documents support for up to 85 IDs. The
SDK passes it directly and does not add a custom `personIDs` collection
abstraction.

## Pagination

Pagination comes from the HTTP `Link` header with `rel="next"`.

Use `people.list(params:)` for one page. If `page.nextPage` is present, callers
can fetch the next page with `people.list(nextPage:)` only when they want
another page. Do not fetch all pages by default for UI views or smoke tests.

## Presence And Calling Notes

`status` and `lastActivity` may be absent depending on organization
relationship and status-sharing settings. Frequent presence polling through
`/people` can trigger `429` responses. Prefer explicit caller intent and
bounded refresh behavior.

`callingData` may require Webex Calling licensing and admin context.

## Safety

People data is PII. Do not include person IDs, emails, full pagination URLs, or
tokens in SDK-generated error messages.
