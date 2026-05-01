# Webex People API v2.0.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a v2.0.0 public SDK shape with endpoint-faithful People read APIs, `Params` naming, caller-controlled pagination, and updated smoke examples.

**Architecture:** Keep typed API groups backed by the existing authenticated `WebexTransport`. List endpoints return one Webex page plus SDK-parsed `nextPage` metadata derived from the HTTP `Link` header; callers decide when to fetch more. People models mirror documented REST fields without adding model-to-registry convenience mapping.

**Tech Stack:** Swift 5.9, SwiftPM, XCTest, Foundation `URLQueryItem`, existing `WebexTransport`, existing `WebexPageLink`, existing OAuth/registry/keychain primitives.

---

## File Structure

- Modify `Sources/WebexSwiftSDK/API/SpacesAPI.swift`
  - Rename `ListSpacesQuery` to `ListSpacesParams`.
  - Rename `list(query:)` to `list(params:)`.
  - Add `list(nextPage:)`.
  - Remove `listAll`.
  - Keep `RoomsAPI`, `WebexRoom`, and room request aliases; replace `ListRoomsQuery` with `ListRoomsParams`.
- Modify `Sources/WebexSwiftSDK/API/MembershipsAPI.swift`
  - Rename `ListMembershipsQuery` to `ListMembershipsParams`.
  - Rename `list(query:)` to `list(params:)`.
  - Add `list(nextPage:)`.
  - Remove `listAll`.
- Modify `Sources/WebexSwiftSDK/API/PeopleAPI.swift`
  - Expand `WebexPerson`.
  - Add read-only People support: `ListPeopleParams`, `WebexPersonListPage`, `people.list(params:)`, `people.list(nextPage:)`, `people.get(personID:callingData:)`, and `people.me(callingData:)`.
  - Remove `WebexPerson.metadata(verifiedAt:)`.
- Modify `Tests/WebexSwiftSDKTests/SpacesAPITests.swift`
  - Update names and replace `listAll` tests with explicit `nextPage` tests.
- Modify `Tests/WebexSwiftSDKTests/MembershipsAPITests.swift`
  - Update names and replace `listAll` tests with explicit `nextPage` tests.
- Modify `Tests/WebexSwiftSDKTests/PeopleAPITests.swift`
  - Cover expanded model decoding and read endpoints.
- Add `.agents/docs/webex-people-api.md`
  - Capture endpoint notes and current Webex quirks for future agents.
- Modify `.agents/docs/webex-spaces-rooms-api.md` and `.agents/docs/webex-memberships-api.md`
  - Update `Query`/`listAll` references to `Params`/caller-controlled pagination.
- Modify `README.md`
  - Update examples and describe `nextPage`.
- Modify `Examples/WebexClientSmoke/Sources/WebexClientSmoke/main.swift`
  - Replace `person.metadata(verifiedAt:)` with explicit `WebexAccountMetadata`.
- Modify `Examples/WebexSpacesListSmoke/Sources/WebexSpacesListSmoke/main.swift`
  - Use `ListSpacesParams`, `spaces.list(params:)`, and an explicit `nextPage` loop.
- Modify `Examples/WebexSpacesListSmoke/Tests/WebexSpacesListSmokeTests/ListOptionsTests.swift`
  - Update type names.
- Modify `Examples/WebexMembershipsListSmoke/Sources/WebexMembershipsListSmoke/main.swift`
  - Use `ListMembershipsParams`, `memberships.list(params:)`, and an explicit `nextPage` loop.
- Modify `Examples/WebexMembershipsListSmoke/Tests/WebexMembershipsListSmokeTests/ListOptionsTests.swift`
  - Update type names.
- Add `Examples/WebexPeopleReadSmoke/Package.swift`
- Add `Examples/WebexPeopleReadSmoke/README.md`
- Add `Examples/WebexPeopleReadSmoke/Sources/WebexPeopleReadSmoke/main.swift`
- Add `Examples/WebexPeopleReadSmoke/Tests/WebexPeopleReadSmokeTests/PeopleReadSmokeOptionsTests.swift`

---

### Task 1: Spaces Public List Shape

**Files:**
- Modify: `Sources/WebexSwiftSDK/API/SpacesAPI.swift`
- Modify: `Tests/WebexSwiftSDKTests/SpacesAPITests.swift`
- Modify: `.agents/docs/webex-spaces-rooms-api.md`

- [ ] **Step 1: Replace Spaces list API tests with Params and caller-controlled next-page tests**

In `Tests/WebexSwiftSDKTests/SpacesAPITests.swift`, update `testListSpacesSendsTypedQueryAndDecodesPage` to use the new names:

```swift
func testListSpacesSendsParamsAndDecodesPage() async throws {
    let httpClient = MockSpacesHTTPClient()
    await httpClient.enqueue(response: httpResponse(
        statusCode: 200,
        headers: ["Link": #"<https://webexapis.com/v1/rooms?cursor=next>; rel="next""#],
        body: #"{"items":[{"id":"space-1","title":"One","type":"group"}]}"#
    ))
    let api = makeAPI(httpClient: httpClient)

    let page = try await api.list(params: ListSpacesParams(
        teamID: "team-1",
        type: .group,
        sortBy: .lastActivity,
        max: 50
    ))

    XCTAssertEqual(page.items.map(\.id), ["space-1"])
    XCTAssertEqual(page.nextPage?.url.absoluteString, "https://webexapis.com/v1/rooms?cursor=next")
    let requests = await httpClient.recordedRequests()
    XCTAssertEqual(requests.count, 1)
    XCTAssertEqual(
        requests[0].url?.absoluteString,
        "https://webexapis.com/v1/rooms?teamId=team-1&type=group&sortBy=lastactivity&max=50"
    )
    XCTAssertEqual(requests[0].httpMethod, "GET")
    XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer spaces-token")
}
```

Delete the existing `testListAll...` methods in the same file and add this one-page-at-a-time pagination test:

```swift
func testListSpacesNextPageUsesParsedWebexPageLink() async throws {
    let httpClient = MockSpacesHTTPClient()
    await httpClient.enqueue(response: httpResponse(
        statusCode: 200,
        headers: ["Link": #"<https://webexapis.com/v1/rooms?cursor=second>; rel="next""#],
        body: #"{"items":[{"id":"space-1","title":"One"}]}"#
    ))
    await httpClient.enqueue(response: httpResponse(
        statusCode: 200,
        body: #"{"items":[{"id":"space-2","title":"Two"}]}"#
    ))
    let api = makeAPI(httpClient: httpClient)

    let firstPage = try await api.list(params: .init(max: 10))
    let nextPage = try XCTUnwrap(firstPage.nextPage)
    let secondPage = try await api.list(nextPage: nextPage)

    XCTAssertEqual(firstPage.items.map(\.id), ["space-1"])
    XCTAssertEqual(secondPage.items.map(\.id), ["space-2"])
    let requests = await httpClient.recordedRequests()
    XCTAssertEqual(requests.map { $0.url?.absoluteString }, [
        "https://webexapis.com/v1/rooms?max=10",
        "https://webexapis.com/v1/rooms?cursor=second"
    ])
}
```

Update `testWebexClientExposesSpacesAndRoomsAlias` so both calls use `list()` with the new default signature; no source change is needed if `list(params:)` has a default parameter.

- [ ] **Step 2: Run Spaces tests and confirm they fail on missing API names**

Run:

```bash
swift test --filter SpacesAPITests
```

Expected: build fails because `ListSpacesParams`, `list(params:)`, and `list(nextPage:)` do not exist yet, and references to removed `listAll` no longer compile.

- [ ] **Step 3: Implement the Spaces API rename and explicit next-page call**

In `Sources/WebexSwiftSDK/API/SpacesAPI.swift`, rename the parameter bag and replace the public list methods with:

```swift
public struct ListSpacesParams: Equatable, Sendable {
    public let teamID: String?
    public let type: WebexSpaceType?
    public let sortBy: WebexSpaceSort?
    public let max: Int?

    public init(
        teamID: String? = nil,
        type: WebexSpaceType? = nil,
        sortBy: WebexSpaceSort? = nil,
        max: Int? = nil
    ) {
        self.teamID = teamID
        self.type = type
        self.sortBy = sortBy
        self.max = max
    }

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let teamID {
            items.append(URLQueryItem(name: "teamId", value: teamID))
        }
        if let type {
            items.append(URLQueryItem(name: "type", value: type.rawValue))
        }
        if let sortBy {
            items.append(URLQueryItem(name: "sortBy", value: sortBy.rawValue))
        }
        if let max {
            items.append(URLQueryItem(name: "max", value: String(max)))
        }
        return items
    }
}
```

In `SpacesAPI`, replace `list(query:)` and remove `listAll`:

```swift
public func list(params: ListSpacesParams = ListSpacesParams()) async throws -> WebexSpaceListPage {
    try await list(request: WebexRequest(
        path: "/v1/rooms",
        queryItems: params.queryItems
    ))
}

public func list(nextPage: WebexPageLink) async throws -> WebexSpaceListPage {
    try await list(request: nextPage.request)
}
```

Delete `paginationRequestKey(_:)` from `SpacesAPI` if nothing else uses it after removing `listAll`.

At the bottom of the file, replace:

```swift
public typealias ListRoomsQuery = ListSpacesQuery
```

with:

```swift
public typealias ListRoomsParams = ListSpacesParams
```

- [ ] **Step 4: Update Spaces docs references**

In `.agents/docs/webex-spaces-rooms-api.md`, replace public API references:

```markdown
`ListSpacesParams`, `CreateSpaceRequest`, `UpdateSpaceRequest`.
```

Replace text that recommends `listAll` with caller-controlled pagination wording:

```markdown
Use `spaces.list(params:)` for one Webex page. If `page.nextPage` is present,
the host app can call `spaces.list(nextPage:)` when it wants the next page.
Do not fetch every page by default for UI views.
```

- [ ] **Step 5: Run Spaces tests and commit**

Run:

```bash
swift test --filter SpacesAPITests
```

Expected: all `SpacesAPITests` pass.

Commit:

```bash
git add Sources/WebexSwiftSDK/API/SpacesAPI.swift Tests/WebexSwiftSDKTests/SpacesAPITests.swift .agents/docs/webex-spaces-rooms-api.md
git commit -m "refactor: make Spaces pagination explicit"
```

---

### Task 2: Memberships Public List Shape

**Files:**
- Modify: `Sources/WebexSwiftSDK/API/MembershipsAPI.swift`
- Modify: `Tests/WebexSwiftSDKTests/MembershipsAPITests.swift`
- Modify: `.agents/docs/webex-memberships-api.md`

- [ ] **Step 1: Replace Memberships list API tests with Params and next-page tests**

In `Tests/WebexSwiftSDKTests/MembershipsAPITests.swift`, update `testListMembershipsSendsTypedQueryAndDecodesPage` to:

```swift
func testListMembershipsSendsParamsAndDecodesPage() async throws {
    let httpClient = MockMembershipsHTTPClient()
    await httpClient.enqueue(response: httpResponse(
        statusCode: 200,
        headers: ["Link": #"<https://webexapis.com/v1/memberships?cursor=next>; rel="next""#],
        body: #"{"items":[{"id":"membership-1","roomId":"room-1","personEmail":"user@example.com"}]}"#
    ))
    let api = makeAPI(httpClient: httpClient)

    let page = try await api.list(params: ListMembershipsParams(
        roomID: "room-1",
        personID: "person-1",
        personEmail: "user@example.com",
        max: 50
    ))

    XCTAssertEqual(page.items.map(\.id), ["membership-1"])
    XCTAssertEqual(page.nextPage?.url.absoluteString, "https://webexapis.com/v1/memberships?cursor=next")
    let requests = await httpClient.recordedRequests()
    XCTAssertEqual(requests.count, 1)
    XCTAssertEqual(
        requests[0].url?.absoluteString,
        "https://webexapis.com/v1/memberships?roomId=room-1&personId=person-1&personEmail=user@example.com&max=50"
    )
    XCTAssertEqual(requests[0].httpMethod, "GET")
    XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer memberships-token")
}
```

Delete the existing `testListAllMemberships...` methods and add:

```swift
func testListMembershipsNextPageUsesParsedWebexPageLink() async throws {
    let httpClient = MockMembershipsHTTPClient()
    await httpClient.enqueue(response: httpResponse(
        statusCode: 200,
        headers: ["Link": #"<https://webexapis.com/v1/memberships?cursor=second>; rel="next""#],
        body: #"{"items":[{"id":"membership-1"}]}"#
    ))
    await httpClient.enqueue(response: httpResponse(
        statusCode: 200,
        body: #"{"items":[{"id":"membership-2"}]}"#
    ))
    let api = makeAPI(httpClient: httpClient)

    let firstPage = try await api.list(params: .init(roomID: "room-1", max: 10))
    let nextPage = try XCTUnwrap(firstPage.nextPage)
    let secondPage = try await api.list(nextPage: nextPage)

    XCTAssertEqual(firstPage.items.map(\.id), ["membership-1"])
    XCTAssertEqual(secondPage.items.map(\.id), ["membership-2"])
    let requests = await httpClient.recordedRequests()
    XCTAssertEqual(requests.map { $0.url?.absoluteString }, [
        "https://webexapis.com/v1/memberships?roomId=room-1&max=10",
        "https://webexapis.com/v1/memberships?cursor=second"
    ])
}
```

Update `testWebexClientExposesMemberships` only if the method label changes are required by the compiler; `client.memberships.list()` should remain valid through the default parameter.

- [ ] **Step 2: Run Memberships tests and confirm they fail on missing API names**

Run:

```bash
swift test --filter MembershipsAPITests
```

Expected: build fails because `ListMembershipsParams`, `list(params:)`, and `list(nextPage:)` do not exist yet.

- [ ] **Step 3: Implement the Memberships API rename and explicit next-page call**

In `Sources/WebexSwiftSDK/API/MembershipsAPI.swift`, rename `ListMembershipsQuery` to:

```swift
public struct ListMembershipsParams: Equatable, Sendable {
    public let roomID: String?
    public let personID: String?
    public let personEmail: String?
    public let max: Int?

    public init(
        roomID: String? = nil,
        personID: String? = nil,
        personEmail: String? = nil,
        max: Int? = nil
    ) {
        self.roomID = roomID
        self.personID = personID
        self.personEmail = personEmail
        self.max = max
    }

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let roomID {
            items.append(URLQueryItem(name: "roomId", value: roomID))
        }
        if let personID {
            items.append(URLQueryItem(name: "personId", value: personID))
        }
        if let personEmail {
            items.append(URLQueryItem(name: "personEmail", value: personEmail))
        }
        if let max {
            items.append(URLQueryItem(name: "max", value: String(max)))
        }
        return items
    }
}
```

Replace public list methods with:

```swift
public func list(params: ListMembershipsParams = ListMembershipsParams()) async throws -> WebexMembershipListPage {
    try await list(request: WebexRequest(
        path: "/v1/memberships",
        queryItems: params.queryItems
    ))
}

public func list(nextPage: WebexPageLink) async throws -> WebexMembershipListPage {
    try await list(request: nextPage.request)
}
```

Remove `listAll` and remove `paginationRequestKey(_:)` if it is unused.

- [ ] **Step 4: Update Memberships docs references**

In `.agents/docs/webex-memberships-api.md`, replace `ListMembershipsQuery` with `ListMembershipsParams` and replace list-all guidance with:

```markdown
Use `memberships.list(params:)` for one Webex page. If `page.nextPage` is
present, call `memberships.list(nextPage:)` only when the app needs another
page.
```

- [ ] **Step 5: Run Memberships tests and commit**

Run:

```bash
swift test --filter MembershipsAPITests
```

Expected: all `MembershipsAPITests` pass.

Commit:

```bash
git add Sources/WebexSwiftSDK/API/MembershipsAPI.swift Tests/WebexSwiftSDKTests/MembershipsAPITests.swift .agents/docs/webex-memberships-api.md
git commit -m "refactor: make Memberships pagination explicit"
```

---

### Task 3: People Read API And Models

**Files:**
- Modify: `Sources/WebexSwiftSDK/API/PeopleAPI.swift`
- Modify: `Tests/WebexSwiftSDKTests/PeopleAPITests.swift`

- [ ] **Step 1: Replace People tests with read endpoint coverage**

In `Tests/WebexSwiftSDKTests/PeopleAPITests.swift`, remove the test that calls `person.metadata(verifiedAt:)`. Add tests with these names:

```swift
func testPersonDecodesExpandedReadFields() throws
func testPersonStatusPreservesUnknownValues() throws
func testPersonTypePreservesUnknownValues() throws
func testMeSendsPeopleMeRequestWithCallingDataAndDecodesPerson() async throws
func testGetPersonPercentEncodesPathAndCallingData() async throws
func testListPeopleSendsAllDocumentedParamsAndDecodesPage() async throws
func testListPeopleNextPageUsesParsedWebexPageLink() async throws
func testPersonIDValidationFailsBeforeHTTPWithoutLeakingID() async throws
```

Use this JSON in the expanded decode test:

```swift
let json = Data("""
{
  "id": "person-id",
  "emails": ["person@example.com"],
  "phoneNumbers": [{"type":"work","value":"+1 408 526 7209","primary":true}],
  "extension": "133",
  "locationId": "location-id",
  "displayName": "Ada Lovelace",
  "nickName": "Ada",
  "firstName": "Ada",
  "lastName": "Lovelace",
  "avatar": "https://example.com/avatar.png",
  "orgId": "org-id",
  "roles": ["role-id"],
  "licenses": ["license-id"],
  "department": "Engineering",
  "manager": "Grace Hopper",
  "managerId": "manager-id",
  "title": "Principal Engineer",
  "addresses": [{
    "type": "work",
    "country": "US",
    "locality": "Milpitas",
    "region": "California",
    "streetAddress": "1099 Bird Ave.",
    "postalCode": "99212"
  }],
  "created": "2015-10-18T14:26:16.000Z",
  "lastModified": "2016-10-18T14:26:16.000Z",
  "timezone": "America/Denver",
  "lastActivity": "2017-10-18T14:26:16.028Z",
  "siteUrls": ["mysite.webex.com#attendee"],
  "sipAddresses": [{"type":"personal-room","value":"person@example.webex.com","primary":false}],
  "xmppFederationJid": "person@example.com",
  "status": "active",
  "invitePending": "false",
  "loginEnabled": "true",
  "type": "person"
}
""".utf8)
```

Assert representative fields from every nested type:

```swift
let person = try JSONDecoder().decode(WebexPerson.self, from: json)
XCTAssertEqual(person.id, "person-id")
XCTAssertEqual(person.emails, ["person@example.com"])
XCTAssertEqual(person.phoneNumbers?.first?.type, .work)
XCTAssertEqual(person.extension, "133")
XCTAssertEqual(person.locationID, "location-id")
XCTAssertEqual(person.orgID, "org-id")
XCTAssertEqual(person.managerID, "manager-id")
XCTAssertEqual(person.addresses?.first?.postalCode, "99212")
XCTAssertEqual(iso8601(person.created), "2015-10-18T14:26:16Z")
XCTAssertEqual(iso8601(person.lastModified), "2016-10-18T14:26:16Z")
XCTAssertEqual(iso8601(person.lastActivity), "2017-10-18T14:26:16Z")
XCTAssertEqual(person.sipAddresses?.first?.type, .personalRoom)
XCTAssertEqual(person.status, .active)
XCTAssertEqual(person.invitePending, "false")
XCTAssertEqual(person.loginEnabled, "true")
XCTAssertEqual(person.type, .person)
```

For list params, assert the official wire names:

```swift
let page = try await api.list(params: ListPeopleParams(
    email: "person@example.com",
    displayName: "Ada",
    id: "person-1,person-2",
    orgID: "org-id",
    roles: "role-1,role-2",
    callingData: true,
    locationID: "location-id",
    max: 25,
    excludeStatus: true
))

XCTAssertEqual(page.items.map(\.id), ["person-1"])
XCTAssertEqual(page.notFoundIDs, ["missing-person"])
XCTAssertEqual(page.nextPage?.url.absoluteString, "https://webexapis.com/v1/people?cursor=next")
XCTAssertEqual(
    requests[0].url?.absoluteString,
    "https://webexapis.com/v1/people?email=person@example.com&displayName=Ada&id=person-1,person-2&orgId=org-id&roles=role-1,role-2&callingData=true&locationId=location-id&max=25&excludeStatus=true"
)
```

- [ ] **Step 2: Run People tests and confirm they fail on missing API names and fields**

Run:

```bash
swift test --filter PeopleAPITests
```

Expected: build fails because expanded People types and endpoint methods do not exist.

- [ ] **Step 3: Implement expanded People model types**

In `Sources/WebexSwiftSDK/API/PeopleAPI.swift`, replace the current `WebexPerson` definition with public nested model types and unknown-preserving enums. Use this shape:

```swift
public enum WebexPersonPhoneNumberType: Equatable, Sendable {
    case work
    case workExtension
    case mobile
    case fax
    case unknown(String)
}

public enum WebexPersonSIPAddressType: Equatable, Sendable {
    case personalRoom
    case enterprise
    case cloudCalling
    case unknown(String)
}

public enum WebexPersonStatus: Equatable, Sendable {
    case active
    case call
    case doNotDisturb
    case inactive
    case meeting
    case outOfOffice
    case pending
    case presenting
    case unknownStatus
    case unknown(String)
}

public enum WebexPersonType: Equatable, Sendable {
    case person
    case bot
    case appuser
    case unknown(String)
}
```

Implement `Codable` manually for each enum so raw Webex values round-trip:

```swift
extension WebexPersonStatus: Codable {
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "active": self = .active
        case "call": self = .call
        case "DoNotDisturb": self = .doNotDisturb
        case "inactive": self = .inactive
        case "meeting": self = .meeting
        case "OutOfOffice": self = .outOfOffice
        case "pending": self = .pending
        case "presenting": self = .presenting
        case "unknown": self = .unknownStatus
        default: self = .unknown(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var rawValue: String {
        switch self {
        case .active: return "active"
        case .call: return "call"
        case .doNotDisturb: return "DoNotDisturb"
        case .inactive: return "inactive"
        case .meeting: return "meeting"
        case .outOfOffice: return "OutOfOffice"
        case .pending: return "pending"
        case .presenting: return "presenting"
        case .unknownStatus: return "unknown"
        case .unknown(let value): return value
        }
    }
}
```

Use the same manual `Codable` structure for the other enums with these raw-value tables:

```swift
// WebexPersonPhoneNumberType
.work -> "work"
.workExtension -> "work_extension"
.mobile -> "mobile"
.fax -> "fax"
.unknown(value) -> value

// WebexPersonSIPAddressType
.personalRoom -> "personal-room"
.enterprise -> "enterprise"
.cloudCalling -> "cloud-calling"
.unknown(value) -> value

// WebexPersonType
.person -> "person"
.bot -> "bot"
.appuser -> "appuser"
.unknown(value) -> value
```

Add nested structs:

```swift
public struct WebexPersonPhoneNumber: Equatable, Codable, Sendable {
    public let type: WebexPersonPhoneNumberType?
    public let value: String?
    public let primary: Bool?

    public init(type: WebexPersonPhoneNumberType? = nil, value: String? = nil, primary: Bool? = nil) {
        self.type = type
        self.value = value
        self.primary = primary
    }
}

public struct WebexPersonAddress: Equatable, Codable, Sendable {
    public let type: String?
    public let country: String?
    public let locality: String?
    public let region: String?
    public let streetAddress: String?
    public let postalCode: String?

    public init(
        type: String? = nil,
        country: String? = nil,
        locality: String? = nil,
        region: String? = nil,
        streetAddress: String? = nil,
        postalCode: String? = nil
    ) {
        self.type = type
        self.country = country
        self.locality = locality
        self.region = region
        self.streetAddress = streetAddress
        self.postalCode = postalCode
    }
}

public struct WebexPersonSIPAddress: Equatable, Codable, Sendable {
    public let type: WebexPersonSIPAddressType?
    public let value: String?
    public let primary: Bool?

    public init(type: WebexPersonSIPAddressType? = nil, value: String? = nil, primary: Bool? = nil) {
        self.type = type
        self.value = value
        self.primary = primary
    }
}
```

Define `WebexPerson` with all read fields from the spec. Decode date fields with `WebexDateDecoding.decodeIfPresent`:

```swift
public struct WebexPerson: Equatable, Decodable, Sendable {
    public let id: String
    public let emails: [String]
    public let phoneNumbers: [WebexPersonPhoneNumber]?
    public let `extension`: String?
    public let locationID: String?
    public let displayName: String?
    public let nickName: String?
    public let firstName: String?
    public let lastName: String?
    public let avatar: String?
    public let orgID: String?
    public let roles: [String]?
    public let licenses: [String]?
    public let department: String?
    public let manager: String?
    public let managerID: String?
    public let title: String?
    public let addresses: [WebexPersonAddress]?
    public let created: Date?
    public let lastModified: Date?
    public let timezone: String?
    public let lastActivity: Date?
    public let siteUrls: [String]?
    public let sipAddresses: [WebexPersonSIPAddress]?
    public let xmppFederationJid: String?
    public let status: WebexPersonStatus?
    public let invitePending: String?
    public let loginEnabled: String?
    public let type: WebexPersonType?

    public init(
        id: String,
        emails: [String],
        phoneNumbers: [WebexPersonPhoneNumber]? = nil,
        `extension`: String? = nil,
        locationID: String? = nil,
        displayName: String? = nil,
        nickName: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        avatar: String? = nil,
        orgID: String? = nil,
        roles: [String]? = nil,
        licenses: [String]? = nil,
        department: String? = nil,
        manager: String? = nil,
        managerID: String? = nil,
        title: String? = nil,
        addresses: [WebexPersonAddress]? = nil,
        created: Date? = nil,
        lastModified: Date? = nil,
        timezone: String? = nil,
        lastActivity: Date? = nil,
        siteUrls: [String]? = nil,
        sipAddresses: [WebexPersonSIPAddress]? = nil,
        xmppFederationJid: String? = nil,
        status: WebexPersonStatus? = nil,
        invitePending: String? = nil,
        loginEnabled: String? = nil,
        type: WebexPersonType? = nil
    ) {
        self.id = id
        self.emails = emails
        self.phoneNumbers = phoneNumbers
        self.`extension` = `extension`
        self.locationID = locationID
        self.displayName = displayName
        self.nickName = nickName
        self.firstName = firstName
        self.lastName = lastName
        self.avatar = avatar
        self.orgID = orgID
        self.roles = roles
        self.licenses = licenses
        self.department = department
        self.manager = manager
        self.managerID = managerID
        self.title = title
        self.addresses = addresses
        self.created = created
        self.lastModified = lastModified
        self.timezone = timezone
        self.lastActivity = lastActivity
        self.siteUrls = siteUrls
        self.sipAddresses = sipAddresses
        self.xmppFederationJid = xmppFederationJid
        self.status = status
        self.invitePending = invitePending
        self.loginEnabled = loginEnabled
        self.type = type
    }
}
```

Use coding keys for all fields that need wire-name mapping:

```swift
private enum CodingKeys: String, CodingKey {
    case id
    case emails
    case phoneNumbers
    case `extension`
    case locationID = "locationId"
    case displayName
    case nickName
    case firstName
    case lastName
    case avatar
    case orgID = "orgId"
    case roles
    case licenses
    case department
    case manager
    case managerID = "managerId"
    case title
    case addresses
    case created
    case lastModified
    case timezone
    case lastActivity
    case siteUrls
    case sipAddresses
    case xmppFederationJid
    case status
    case invitePending
    case loginEnabled
    case type
}
```

In `init(from:)`, decode `id` and `emails` directly, decode optional fields with `decodeIfPresent`, and decode dates through:

```swift
self.created = try WebexDateDecoding.decodeIfPresent(from: container, forKey: .created)
self.lastModified = try WebexDateDecoding.decodeIfPresent(from: container, forKey: .lastModified)
self.lastActivity = try WebexDateDecoding.decodeIfPresent(from: container, forKey: .lastActivity)
```

Do not re-add `metadata(verifiedAt:)`.

- [ ] **Step 4: Implement People params, page, and read methods**

Add:

```swift
public struct ListPeopleParams: Equatable, Sendable {
    public let email: String?
    public let displayName: String?
    public let id: String?
    public let orgID: String?
    public let roles: String?
    public let callingData: Bool?
    public let locationID: String?
    public let max: Int?
    public let excludeStatus: Bool?

    public init(
        email: String? = nil,
        displayName: String? = nil,
        id: String? = nil,
        orgID: String? = nil,
        roles: String? = nil,
        callingData: Bool? = nil,
        locationID: String? = nil,
        max: Int? = nil,
        excludeStatus: Bool? = nil
    ) {
        self.email = email
        self.displayName = displayName
        self.id = id
        self.orgID = orgID
        self.roles = roles
        self.callingData = callingData
        self.locationID = locationID
        self.max = max
        self.excludeStatus = excludeStatus
    }

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let email {
            items.append(URLQueryItem(name: "email", value: email))
        }
        if let displayName {
            items.append(URLQueryItem(name: "displayName", value: displayName))
        }
        if let id {
            items.append(URLQueryItem(name: "id", value: id))
        }
        if let orgID {
            items.append(URLQueryItem(name: "orgId", value: orgID))
        }
        if let roles {
            items.append(URLQueryItem(name: "roles", value: roles))
        }
        if let callingData {
            items.append(URLQueryItem(name: "callingData", value: String(callingData)))
        }
        if let locationID {
            items.append(URLQueryItem(name: "locationId", value: locationID))
        }
        if let max {
            items.append(URLQueryItem(name: "max", value: String(max)))
        }
        if let excludeStatus {
            items.append(URLQueryItem(name: "excludeStatus", value: String(excludeStatus)))
        }
        return items
    }
}
```

Add:

```swift
public struct WebexPersonListPage: Equatable, Sendable {
    public let items: [WebexPerson]
    public let notFoundIDs: [String]?
    public let nextPage: WebexPageLink?

    public init(items: [WebexPerson], notFoundIDs: [String]?, nextPage: WebexPageLink?) {
        self.items = items
        self.notFoundIDs = notFoundIDs
        self.nextPage = nextPage
    }
}
```

Add public methods with this behavior:

```swift
public func me(callingData: Bool? = nil) async throws -> WebexPerson {
    let data = try await transport.send(WebexRequest(
        path: "/v1/people/me",
        queryItems: callingData.map { [URLQueryItem(name: "callingData", value: String($0))] } ?? []
    ))
    return try JSONDecoder().decode(WebexPerson.self, from: data)
}

public func get(personID: String, callingData: Bool? = nil) async throws -> WebexPerson {
    let data = try await transport.send(WebexRequest(
        path: try personPath(personID),
        isPathPercentEncoded: true,
        queryItems: callingData.map { [URLQueryItem(name: "callingData", value: String($0))] } ?? []
    ))
    return try JSONDecoder().decode(WebexPerson.self, from: data)
}

public func list(params: ListPeopleParams = ListPeopleParams()) async throws -> WebexPersonListPage {
    try await list(request: WebexRequest(
        path: "/v1/people",
        queryItems: params.queryItems
    ))
}

public func list(nextPage: WebexPageLink) async throws -> WebexPersonListPage {
    try await list(request: nextPage.request)
}
```

Add:

```swift
private struct WebexPersonListEnvelope: Decodable {
    let items: [WebexPerson]
    let notFoundIDs: [String]?

    private enum CodingKeys: String, CodingKey {
        case items
        case notFoundIDs = "notFoundIds"
    }
}
```

Use a private `list(request:)` that calls `transport.sendResponse`, decodes `WebexPersonListEnvelope`, and sets `nextPage: WebexPageLink.next(from: response.response)`.

Use a private `personPath(_:)` matching the existing space/membership path validation pattern, but with `"Invalid Webex person ID"`.

- [ ] **Step 5: Run People tests and commit**

Run:

```bash
swift test --filter PeopleAPITests
```

Expected: all `PeopleAPITests` pass.

Commit:

```bash
git add Sources/WebexSwiftSDK/API/PeopleAPI.swift Tests/WebexSwiftSDKTests/PeopleAPITests.swift
git commit -m "feat: add People read API"
```

---

### Task 4: Examples And Smoke Programs

**Files:**
- Modify: `Examples/WebexClientSmoke/Sources/WebexClientSmoke/main.swift`
- Modify: `Examples/WebexSpacesListSmoke/Sources/WebexSpacesListSmoke/main.swift`
- Modify: `Examples/WebexSpacesListSmoke/Tests/WebexSpacesListSmokeTests/ListOptionsTests.swift`
- Modify: `Examples/WebexMembershipsListSmoke/Sources/WebexMembershipsListSmoke/main.swift`
- Modify: `Examples/WebexMembershipsListSmoke/Tests/WebexMembershipsListSmokeTests/ListOptionsTests.swift`
- Add: `Examples/WebexPeopleReadSmoke/Package.swift`
- Add: `Examples/WebexPeopleReadSmoke/README.md`
- Add: `Examples/WebexPeopleReadSmoke/Sources/WebexPeopleReadSmoke/main.swift`
- Add: `Examples/WebexPeopleReadSmoke/Tests/WebexPeopleReadSmokeTests/PeopleReadSmokeOptionsTests.swift`

- [ ] **Step 1: Update WebexClientSmoke metadata mapping**

In `Examples/WebexClientSmoke/Sources/WebexClientSmoke/main.swift`, replace:

```swift
try await store.saveMetadata(person.metadata(verifiedAt: Date()), for: authorized.account.id)
```

with:

```swift
let metadata = WebexAccountMetadata(
    webexUserID: person.id,
    email: person.emails.first,
    displayName: person.displayName,
    organizationID: person.orgID,
    lastVerifiedAt: Date()
)
try await store.saveMetadata(metadata, for: authorized.account.id)
```

Update the `created` print because `created` is now `Date?`:

```swift
print("created: \(iso8601(person.created))")
```

Add the local `iso8601(_:)` helper used by the other smoke programs.

```swift
private static func iso8601(_ date: Date?) -> String {
    guard let date else {
        return "(nil)"
    }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
}
```

- [ ] **Step 2: Update Spaces smoke option types and pagination loop**

In `Examples/WebexSpacesListSmoke/Sources/WebexSpacesListSmoke/main.swift`, change `ListOptions.query` to:

```swift
let params: ListSpacesParams
```

Change initializer assignment to:

```swift
self.params = ListSpacesParams(
    teamID: Self.trimmedOptional(environment["WEBEX_SPACES_TEAM_ID"]),
    type: try Self.spaceType(environment["WEBEX_SPACES_TYPE"]),
    sortBy: try Self.sort(environment["WEBEX_SPACES_SORT_BY"]),
    max: pageSize
)
```

Replace the `listAll` call with:

```swift
let spaces = try await collectSpaces(
    client: authorized.client,
    params: listOptions.params,
    maxPages: listOptions.maxPages
)
```

Add this helper in the same file:

```swift
private static func collectSpaces(
    client: WebexClient,
    params: ListSpacesParams,
    maxPages: Int
) async throws -> [WebexSpace] {
    var page = try await client.spaces.list(params: params)
    var pagesFetched = 1
    var spaces = page.items

    while let nextPage = page.nextPage {
        guard pagesFetched < maxPages else {
            throw WebexSDKError.network("Spaces smoke page cap exceeded")
        }

        page = try await client.spaces.list(nextPage: nextPage)
        pagesFetched += 1
        spaces.append(contentsOf: page.items)
    }

    return spaces
}
```

Update the special catch at the top of the smoke program to match `"Spaces smoke page cap exceeded"`.

- [ ] **Step 3: Update Memberships smoke option types and pagination loop**

In `Examples/WebexMembershipsListSmoke/Sources/WebexMembershipsListSmoke/main.swift`, change `MembershipListOptions.query` to:

```swift
let params: ListMembershipsParams
```

Change initializer assignment to:

```swift
self.params = ListMembershipsParams(roomID: roomID, max: pageSize)
```

Replace the `listAll` call with:

```swift
let memberships = try await collectMemberships(
    client: authorized.client,
    params: listOptions.params,
    maxPages: listOptions.maxPages
)
```

Add:

```swift
private static func collectMemberships(
    client: WebexClient,
    params: ListMembershipsParams,
    maxPages: Int
) async throws -> [WebexMembership] {
    var page = try await client.memberships.list(params: params)
    var pagesFetched = 1
    var memberships = page.items

    while let nextPage = page.nextPage {
        guard pagesFetched < maxPages else {
            throw WebexSDKError.network("Memberships smoke page cap exceeded")
        }

        page = try await client.memberships.list(nextPage: nextPage)
        pagesFetched += 1
        memberships.append(contentsOf: page.items)
    }

    return memberships
}
```

Update the special catch to match `"Memberships smoke page cap exceeded"`.

- [ ] **Step 4: Update smoke tests for renamed option properties**

In both smoke test files under `Examples/WebexSpacesListSmoke/Tests` and `Examples/WebexMembershipsListSmoke/Tests`, replace `.query` expectations with `.params` and replace `ListSpacesQuery`/`ListMembershipsQuery` names with `ListSpacesParams`/`ListMembershipsParams`.

- [ ] **Step 5: Add People read smoke package**

Create `Examples/WebexPeopleReadSmoke/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "webex-people-read-smoke",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "WebexPeopleReadSmoke",
            dependencies: [
                .product(name: "WebexSwiftSDK", package: "webex-swift-sdk")
            ]
        ),
        .testTarget(
            name: "WebexPeopleReadSmokeTests",
            dependencies: ["WebexPeopleReadSmoke"]
        )
    ]
)
```

Create `Examples/WebexPeopleReadSmoke/Sources/WebexPeopleReadSmoke/main.swift` by adapting `WebexClientSmoke` with these behavior differences:

```swift
let me = try await authorized.client.people.me()
let metadata = WebexAccountMetadata(
    webexUserID: me.id,
    email: me.emails.first,
    displayName: me.displayName,
    organizationID: me.orgID,
    lastVerifiedAt: Date()
)
try await store.saveMetadata(metadata, for: authorized.account.id)

let person = try await authorized.client.people.get(personID: me.id)
let ids = PeopleReadOptions(environment: environment).peopleIDs ?? me.id
let page = try await authorized.client.people.list(params: .init(id: ids, max: 25, excludeStatus: true))
```

Print only `id`, `displayName`, `emails`, `orgID`, `created`, `lastModified`, `status`, `type`, `notFoundIDs`, and `nextPage != nil`. Do not print the authorization URL in this smoke; match Memberships smoke behavior and tell the user to verify browser defaults if opening fails.

Add `PeopleReadOptions`:

```swift
struct PeopleReadOptions {
    let peopleIDs: String?

    init(environment: [String: String]) {
        self.peopleIDs = Self.trimmedOptional(environment["WEBEX_PEOPLE_IDS"])
    }

    private static func trimmedOptional(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }
}
```

Create `Examples/WebexPeopleReadSmoke/Tests/WebexPeopleReadSmokeTests/PeopleReadSmokeOptionsTests.swift`:

```swift
import XCTest
@testable import WebexPeopleReadSmoke

final class PeopleReadSmokeOptionsTests: XCTestCase {
    func testPeopleIDsTrimWhitespace() {
        let options = PeopleReadOptions(environment: ["WEBEX_PEOPLE_IDS": " person-1,person-2 "])

        XCTAssertEqual(options.peopleIDs, "person-1,person-2")
    }

    func testPeopleIDsEmptyStringBecomesNil() {
        let options = PeopleReadOptions(environment: ["WEBEX_PEOPLE_IDS": "   "])

        XCTAssertNil(options.peopleIDs)
    }
}
```

Add `Examples/WebexPeopleReadSmoke/README.md` with:

```markdown
# WebexPeopleReadSmoke

Interactive OAuth smoke program for the SDK People read API.

Required environment:

- `WEBEX_CLIENT_ID`
- `WEBEX_CLIENT_SECRET`

Optional environment:

- `WEBEX_REDIRECT_URI`, default `http://127.0.0.1:8282/oauth/callback`
- `WEBEX_SCOPES`, default `spark:people_read`
- `WEBEX_KEYCHAIN_SERVICE`
- `WEBEX_PEOPLE_IDS`, comma-separated value passed directly to the official `/v1/people?id=` query parameter

Run:

```bash
swift run --package-path Examples/WebexPeopleReadSmoke WebexPeopleReadSmoke
```
```

- [ ] **Step 6: Build smoke examples and commit**

Run:

```bash
swift build --package-path Examples/WebexClientSmoke
swift test --package-path Examples/WebexSpacesListSmoke
swift test --package-path Examples/WebexMembershipsListSmoke
swift test --package-path Examples/WebexPeopleReadSmoke
```

Expected: all commands pass.

Commit:

```bash
git add Examples
git commit -m "test: update smoke examples for v2 API"
```

---

### Task 5: Documentation And README

**Files:**
- Add: `.agents/docs/webex-people-api.md`
- Modify: `README.md`

- [ ] **Step 1: Add People API agent docs**

Create `.agents/docs/webex-people-api.md`:

```markdown
# Webex People API Notes

Date captured: 2026-05-01

Primary sources:

- https://developer.webex.com/messaging/docs/api/v1/people
- https://developer.webex.com/messaging/docs/basics

## Scope For v2.0.0

Implement read-focused People API calls:

- `GET /v1/people`
- `GET /v1/people/{personId}`
- `GET /v1/people/me`

Do not implement create, update, or delete in v2.0.0. Webex recommends SCIM 2.0
for user management, provisioning, and maintenance.

## Scopes

- `spark:people_read`: normal search and detail reads.
- `spark-admin:people_read`: org-wide listing.
- `spark-admin:people_write` plus `spark-admin:people_read`: People write APIs,
  out of scope for v2.0.0.

## List Parameters

`ListPeopleParams` mirrors the documented query parameters:

- `email`
- `displayName`
- `id`
- `orgId`
- `roles`
- `callingData`
- `locationId`
- `max`
- `excludeStatus`

The `id` parameter is a comma-separated string. Webex documents support for up
to 85 IDs. The SDK passes this value as REST data and does not introduce a
custom ID collection abstraction.

## Pagination

Pagination comes from the HTTP `Link` header with `rel="next"`, not from the
JSON body. Use `people.list(params:)` for one page and `people.list(nextPage:)`
only when the caller wants the next page.

## Presence And Calling Notes

Presence fields such as `status` and `lastActivity` may be absent depending on
organization relationship and user status-sharing settings. Frequent presence
polling through `/people` can trigger `429`.

`callingData` can include Webex Calling details but requires Webex Calling
licensing and suitable admin context.

## Security Notes

People data contains PII. Do not include person IDs, emails, full pagination
URLs, or tokens in SDK-generated error messages.
```

- [ ] **Step 2: Update README public API examples**

In `README.md`, update the Spaces example:

```swift
let firstPage = try await client.spaces.list(params: .init(max: 10))
for space in firstPage.items {
    print(space.id, space.title ?? "(untitled)")
}

if let nextPage = firstPage.nextPage {
    let secondPage = try await client.spaces.list(nextPage: nextPage)
    print("loaded another page with \(secondPage.items.count) spaces")
}
```

Update Memberships:

```swift
let page = try await client.memberships.list(params: .init(roomID: spaceID, max: 50))
for member in page.items {
    print(member.personDisplayName ?? member.personID ?? "(unknown)")
}
```

Add People:

```swift
let me = try await client.people.me()
let people = try await client.people.list(params: .init(id: me.id, excludeStatus: true))
print(people.items.first?.displayName ?? me.id)
```

Update examples list to include `Examples/WebexPeopleReadSmoke`, and replace existing `listAll` mentions with explicit pagination wording.

- [ ] **Step 3: Run docs scan and commit**

Run:

```bash
rg -n "ListSpacesQuery|ListMembershipsQuery|listAll|query:" README.md .agents/docs
```

Expected: no hits in `README.md` or `.agents/docs` for old public API names, except historical design/plan files under `docs/superpowers` are not part of this command.

Commit:

```bash
git add README.md .agents/docs/webex-people-api.md .agents/docs/webex-spaces-rooms-api.md .agents/docs/webex-memberships-api.md
git commit -m "docs: document People read API"
```

---

### Task 6: Full Verification And Cleanup

**Files:**
- Verify all modified files.

- [ ] **Step 1: Search for removed public API names**

Run:

```bash
rg -n "ListSpacesQuery|ListMembershipsQuery|ListPeopleQuery|listAll|metadata\\(verifiedAt|personIDs" Sources Tests Examples README.md .agents/docs
```

Expected: no hits. Do not include `docs/superpowers` in this command because older specs and plans intentionally preserve historical context.

- [ ] **Step 2: Run package tests**

Run:

```bash
swift test
```

Expected: all non-skipped tests pass. Existing keychain integration tests may remain skipped if they are marked as expected skips.

- [ ] **Step 3: Run root build**

Run:

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 4: Build and test examples**

Run:

```bash
swift build --package-path Examples/WebexClientSmoke
swift test --package-path Examples/WebexSpacesListSmoke
swift test --package-path Examples/WebexMembershipsListSmoke
swift test --package-path Examples/WebexPeopleReadSmoke
```

Expected: all example builds/tests pass.

- [ ] **Step 5: Check whitespace**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 6: Review final diff**

Run:

```bash
git status --short
git diff --stat main...HEAD
```

Expected: only planned SDK, tests, docs, and example files are changed.

- [ ] **Step 7: Commit any final cleanup**

If Step 6 shows uncommitted planned changes, commit them:

```bash
git add Sources Tests Examples README.md .agents/docs
git commit -m "chore: verify People API v2"
```

If the worktree is clean, do not create an empty commit.
