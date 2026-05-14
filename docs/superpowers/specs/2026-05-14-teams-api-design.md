# Teams API Design

## Goal

Expand the current partial Teams support into a full documented Webex Messaging
Teams and Team Memberships SDK surface, while preserving wire-faithful unknown
fields returned by Webex so future or undocumented metadata can be observed
without inventing unsupported write operations.

Current SDK state: `client.teams.get(teamID:)` and `WebexTeam` exist only as the
minimum needed by Spaces enrichment. This branch will complete that API and add
Team Memberships.

## Source Of Truth

Implement the documented Webex Messaging APIs:

- Teams API: teams are created, listed, fetched, renamed through update, and
  deleted.
- Team Memberships API: team memberships are listed, created, fetched, updated,
  and deleted.
- Rooms API: team spaces are managed through existing Spaces/Rooms endpoints by
  using `teamId`. Webex documents that once a room is added to a team it cannot
  be moved.

Do not add public methods for team color, team description, archive, move-space,
or remove-space-from-team unless Webex exposes those as documented endpoint
fields. The first pass is documented behavior only.

## Public API Shape

### Teams

Extend `TeamsAPI` with:

- `list(params: ListTeamsParams = ListTeamsParams()) async throws -> WebexTeamListPage`
- `list(nextPage: WebexPageLink) async throws -> WebexTeamListPage`
- `create(_ request: CreateTeamRequest) async throws -> WebexTeam`
- `get(teamID: String) async throws -> WebexTeam`
- `update(teamID: String, _ request: UpdateTeamRequest) async throws -> WebexTeam`
- `delete(teamID: String) async throws`

Add models:

- `ListTeamsParams`
  - `max: Int?`
- `WebexTeamListPage`
  - `items: [WebexTeam]`
  - `nextPage: WebexPageLink?`
- `CreateTeamRequest`
  - `name: String`
- `UpdateTeamRequest`
  - `name: String`

Keep request models narrow and documented. Team name is the only documented
write field in this pass.

### Team Memberships

Add `TeamMembershipsAPI` and expose it on `WebexClient` as:

- `client.teamMemberships`

Methods:

- `list(params: ListTeamMembershipsParams = ListTeamMembershipsParams()) async throws -> WebexTeamMembershipListPage`
- `list(nextPage: WebexPageLink) async throws -> WebexTeamMembershipListPage`
- `create(_ request: CreateTeamMembershipRequest) async throws -> WebexTeamMembership`
- `get(teamMembershipID: String) async throws -> WebexTeamMembership`
- `update(teamMembershipID: String, _ request: UpdateTeamMembershipRequest) async throws -> WebexTeamMembership`
- `delete(teamMembershipID: String) async throws`

Add models:

- `ListTeamMembershipsParams`
  - `teamID: String?`
  - `personID: String?`
  - `personEmail: String?`
  - `max: Int?`
- `WebexTeamMembershipListPage`
  - `items: [WebexTeamMembership]`
  - `nextPage: WebexPageLink?`
- `CreateTeamMembershipRequest`
  - `teamID: String`
  - exactly one identity: `personID` or `personEmail`
  - `isModerator: Bool?`
- `UpdateTeamMembershipRequest`
  - `isModerator: Bool?`
- `WebexTeamMembership`
  - `id: String`
  - `teamID: String?`
  - `personID: String?`
  - `personEmail: String?`
  - `personDisplayName: String?`
  - `personOrgID: String?`
  - `isModerator: Bool?`
  - `created: Date?`
  - additional wire fields as described below

The exact identity constructors should match the existing room `CreateMembershipRequest`
style:

- `init(teamID: String, personID: String, isModerator: Bool? = nil)`
- `init(teamID: String, personEmail: String, isModerator: Bool? = nil)`

## Wire-Faithful Unknown Fields

Add unknown field capture to `WebexTeam` and `WebexTeamMembership`:

- `public let additionalFields: [String: WebexJSONValue]`

Decode the known fields normally, then decode the full object as
`[String: WebexJSONValue]` and remove known coding keys. The remaining keys stay
available to callers. This lets the SDK surface returned-but-undocumented fields
such as possible visual metadata, description-like fields, or lifecycle flags if
Webex returns them.

Do not encode `additionalFields` into typed create/update requests. Request
models should remain documented and intentional.

## Team Spaces

Do not add a separate Team Spaces API in this branch. The SDK already supports
the documented path:

- list spaces for a team with `client.spaces.list(params: .init(teamID: ...))`
- create a team space with `CreateSpaceRequest(title: ..., teamID: ...)`

Add README examples for these flows if the Teams section needs to point users to
team spaces. Do not add unsupported helpers for removing a space from a team or
moving a team space.

## Error Handling And Security

- Validate path IDs before HTTP just like `SpacesAPI` and `MembershipsAPI`.
- Invalid IDs must throw safe `WebexSDKError.network(...)` messages that do not
  echo raw user input.
- Use existing `WebexTransport` behavior for graceful backoff, token refresh,
  HTTP classification, and redacted errors.
- DELETE endpoints should discard response bodies and accept transport success.
- Pagination should use `sendResponse` plus `WebexPageLink.next(from:)`.

## Documentation

Update the root README with:

- Teams create/list/get/update/delete examples.
- Team Memberships list/create/get/update/delete examples.
- Team spaces guidance pointing to `client.spaces` with `teamID`.
- A note that unknown returned fields are available through
  `additionalFields`, but color/description/archive are not exposed as typed
  writes unless Webex documents them.

## Tests

Add focused XCTest coverage:

- `WebexTeam` decodes known fields and preserves unknown fields.
- Team list builds `/v1/teams` query items and parses pagination.
- Team create posts documented JSON.
- Team get/update/delete percent-encode path IDs.
- Invalid team IDs fail before HTTP without leaking input.
- `WebexTeamMembership` decodes known fields and preserves unknown fields.
- Team membership list builds `/v1/team/memberships` query items and parses
  pagination.
- Team membership create supports person ID and email constructors and encodes
  exactly one identity.
- Team membership get/update/delete percent-encode path IDs.
- Invalid team membership IDs fail before HTTP without leaking input.
- `WebexClient` exposes `teamMemberships`.
- Existing root `swift test` remains green.

## Out Of Scope

- No hidden/private endpoint writes.
- No public typed color/description/archive methods.
- No team-space move or remove-from-team operation.
- No UI smoke app for Teams in this branch.
