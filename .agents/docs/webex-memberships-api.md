# Webex Memberships API Notes

Date captured: 2026-05-01

Primary source: https://developer.webex.com/messaging/docs/api/v1/memberships

Memberships represent a person's relationship to a Webex room/space.

## v1.2.0 Scope

- `GET /v1/memberships`
- `POST /v1/memberships`
- `GET /v1/memberships/{membershipId}`
- `PUT /v1/memberships/{membershipId}`
- `DELETE /v1/memberships/{membershipId}`

Compliance Officer convenience flows are out of scope for v1.2.0.

Use `memberships.list(params:)` for one Webex page. If `page.nextPage` is
present, call `memberships.list(nextPage:)` only when the app needs another
page.

## Normal Scopes

- `spark:memberships_read`: list and get.
- `spark:memberships_write`: create, update, delete.

The SDK does not enforce scopes locally. Webex returns `401` or `403` when the
token lacks permission.

## Fields

Known response fields:

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

`roomType` uses the same known values as Spaces: `direct` and `group`.

## Safety

- List smoke tests are safe when scoped by `WEBEX_ROOM_ID`.
- Create/update/delete smoke tests can alter real rooms and should require
  explicit environment variables in a separate example.
- Do not include person emails, membership IDs, tokens, or full pagination URLs
  in SDK-generated error messages.
