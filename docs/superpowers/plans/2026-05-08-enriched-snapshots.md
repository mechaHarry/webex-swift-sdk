# Enriched Snapshots Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add spaces snapshot enrichment so `snapshot.items` contains `WebexSpace` values with item-level `enriched.teamName`, `enriched.spaceAvatar`, status, and field errors.

**Architecture:** Keep REST wrappers wire-faithful: direct `spaces.list` and `spaces.get` decode `WebexSpace.enriched == .empty` and perform no hidden follow-up calls. Convert `SpacesStream` from a typealias into a wrapper around `WebexSnapshotStream<WebexSpace>` that emits immediate loading/cached enrichment state, then pushes a follow-up snapshot after bounded, cached Teams/Memberships/People lookups. Add `TeamsAPI.get(teamID:)` as the first Teams REST surface because `teamName` depends on it.

**Tech Stack:** Swift 5.9, SwiftPM, XCTest, `AsyncStream`, actors, existing `WebexTransport`, existing API wrappers, existing stream primitives.

---

### Task 1: Teams API Foundation

**Files:**
- Create: `Sources/WebexSwiftSDK/API/WebexTeam.swift`
- Create: `Sources/WebexSwiftSDK/API/TeamsAPI.swift`
- Modify: `Sources/WebexSwiftSDK/WebexClient.swift`
- Create: `Tests/WebexSwiftSDKTests/TeamsAPITests.swift`

- [ ] **Step 1: Write failing Teams API tests**

Create `Tests/WebexSwiftSDKTests/TeamsAPITests.swift` with these tests and helpers:

```swift
import XCTest
@testable import WebexSwiftSDK

final class TeamsAPITests: XCTestCase {
    func testTeamDecodesKnownFields() throws {
        let json = Data("""
        {
          "id": "team-id",
          "name": "Platform Team",
          "creatorId": "creator-id",
          "created": "2026-05-08T10:11:12.123Z"
        }
        """.utf8)

        let team = try JSONDecoder().decode(WebexTeam.self, from: json)

        XCTAssertEqual(team.id, "team-id")
        XCTAssertEqual(team.name, "Platform Team")
        XCTAssertEqual(team.creatorID, "creator-id")
        XCTAssertEqual(iso8601(team.created), "2026-05-08T10:11:12Z")
    }

    func testGetTeamPercentEncodesPathSegment() async throws {
        let httpClient = MockTeamsHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            body: #"{"id":"team/id with spaces","name":"Encoded Team"}"#
        ))
        let api = makeAPI(httpClient: httpClient)

        let team = try await api.get(teamID: "team/id with spaces")

        XCTAssertEqual(team.id, "team/id with spaces")
        XCTAssertEqual(team.name, "Encoded Team")
        let requests = await httpClient.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://webexapis.com/v1/teams/team%2Fid%20with%20spaces"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer teams-token")
    }

    func testInvalidTeamIDValidationFailsBeforeHTTPWithoutLeakingRawID() async throws {
        let httpClient = MockTeamsHTTPClient()
        let api = makeAPI(httpClient: httpClient)

        do {
            _ = try await api.get(teamID: "   ")
            XCTFail("Expected invalid team ID")
        } catch WebexSDKError.network(let message) {
            XCTAssertEqual(message, "Invalid Webex team ID")
            XCTAssertFalse(message.contains("   "))
        } catch {
            XCTFail("Expected network error, got \(error)")
        }

        let requests = await httpClient.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testWebexClientExposesTeamsAPI() async throws {
        let accountID = WebexAccountID()
        let store = InMemoryWebexStore()
        let httpClient = MockTeamsHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            body: #"{"id":"team-id","name":"Client Team"}"#
        ))
        let client = WebexClient(
            accountID: accountID,
            configuration: WebexIntegrationConfiguration(
                clientID: "client",
                clientSecret: "secret",
                redirectURI: URL(string: "myapp://oauth/webex")!,
                scopes: ["spark:rooms_read"]
            ),
            tokenStore: store,
            httpClient: httpClient,
            initialAccessToken: AccessTokenState(
                value: "client-token",
                expiresAt: Date(timeIntervalSince1970: 1_000),
                tokenType: "Bearer"
            ),
            clock: { Date(timeIntervalSince1970: 0) }
        )

        let team = try await client.teams.get(teamID: "team-id")

        XCTAssertEqual(team.name, "Client Team")
        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(requests.first?.url?.absoluteString, "https://webexapis.com/v1/teams/team-id")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer client-token")
    }

    private func iso8601(_ date: Date?) -> String? {
        guard let date else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

private func makeAPI(httpClient: HTTPClient) -> TeamsAPI {
    TeamsAPI(transport: WebexTransport(httpClient: httpClient) {
        AccessTokenState(
            value: "teams-token",
            expiresAt: Date(timeIntervalSince1970: 1_000),
            tokenType: "Bearer"
        )
    })
}

private func httpResponse(
    statusCode: Int,
    headers: [String: String] = [:],
    body: String
) -> HTTPResponse {
    HTTPResponse(
        data: Data(body.utf8),
        response: HTTPURLResponse(
            url: URL(string: "https://webexapis.com/v1/teams")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    )
}

private actor MockTeamsHTTPClient: HTTPClient {
    private var responses: [HTTPResponse] = []
    private var requests: [URLRequest] = []

    func enqueue(response: HTTPResponse) {
        responses.append(response)
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else {
            throw WebexSDKError.network("Unexpected teams request")
        }

        return responses.removeFirst()
    }
}
```

- [ ] **Step 2: Run Teams API tests and verify they fail**

Run:

```bash
swift test --filter TeamsAPITests
```

Expected: compile failure mentioning missing `WebexTeam`, `TeamsAPI`, or `WebexClient.teams`.

- [ ] **Step 3: Implement `WebexTeam`**

Create `Sources/WebexSwiftSDK/API/WebexTeam.swift`:

```swift
import Foundation

public struct WebexTeam: Equatable, Decodable, Sendable {
    public let id: String
    public let name: String?
    public let creatorID: String?
    public let created: Date?

    public init(
        id: String,
        name: String? = nil,
        creatorID: String? = nil,
        created: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.creatorID = creatorID
        self.created = created
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case creatorID = "creatorId"
        case created
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.creatorID = try container.decodeIfPresent(String.self, forKey: .creatorID)
        self.created = try WebexDateDecoding.decodeIfPresent(from: container, forKey: .created)
    }
}
```

- [ ] **Step 4: Implement `TeamsAPI.get(teamID:)`**

Create `Sources/WebexSwiftSDK/API/TeamsAPI.swift`:

```swift
import Foundation

public struct TeamsAPI: Sendable {
    private let transport: WebexTransport

    public init(transport: WebexTransport) {
        self.transport = transport
    }

    public func get(teamID: String) async throws -> WebexTeam {
        let data = try await transport.send(WebexRequest(
            path: try teamPath(teamID),
            isPathPercentEncoded: true
        ))
        return try JSONDecoder().decode(WebexTeam.self, from: data)
    }

    private func teamPath(_ teamID: String) throws -> String {
        let trimmedID = teamID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            throw WebexSDKError.network("Invalid Webex team ID")
        }

        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%")

        guard let encodedID = trimmedID.addingPercentEncoding(withAllowedCharacters: allowed),
              !encodedID.isEmpty else {
            throw WebexSDKError.network("Invalid Webex team ID")
        }

        return "/v1/teams/\(encodedID)"
    }
}
```

- [ ] **Step 5: Expose `teams` from `WebexClient`**

Modify `Sources/WebexSwiftSDK/WebexClient.swift`:

```swift
public struct WebexClient: Sendable {
    public let accountID: WebexAccountID
    public let people: PeopleAPI
    public let spaces: SpacesAPI
    public let memberships: MembershipsAPI
    public let messages: MessagesAPI
    public let teams: TeamsAPI
    public let webhooks: WebhooksAPI
    public let realtime: WebexRealtimeClient
```

In the initializer, create and assign the API group after the shared `transport` is created:

```swift
self.accountID = accountID
self.people = PeopleAPI(transport: transport)
self.spaces = SpacesAPI(transport: transport)
self.memberships = MembershipsAPI(transport: transport)
self.messages = MessagesAPI(transport: transport)
self.teams = TeamsAPI(transport: transport)
self.webhooks = WebhooksAPI(transport: transport)
```

- [ ] **Step 6: Run Teams API tests and verify they pass**

Run:

```bash
swift test --filter TeamsAPITests
```

Expected: all `TeamsAPITests` pass.

- [ ] **Step 7: Commit Teams API foundation**

Run:

```bash
git add Sources/WebexSwiftSDK/API/WebexTeam.swift Sources/WebexSwiftSDK/API/TeamsAPI.swift Sources/WebexSwiftSDK/WebexClient.swift Tests/WebexSwiftSDKTests/TeamsAPITests.swift
git commit -m "feat: add teams api"
```

Expected: commit succeeds.

### Task 2: Space Enrichment Models And Safe Item Mutation

**Files:**
- Modify: `Sources/WebexSwiftSDK/API/WebexSpace.swift`
- Modify: `Sources/WebexSwiftSDK/Streams/WebexSnapshotStream.swift`
- Create: `Sources/WebexSwiftSDK/Streams/WebexStreamErrorRedactor.swift`
- Modify: `Tests/WebexSwiftSDKTests/SpacesAPITests.swift`
- Modify: `Tests/WebexSwiftSDKTests/WebexSnapshotStreamTests.swift`

- [ ] **Step 1: Write failing `WebexSpace` enrichment decoding test**

In `Tests/WebexSwiftSDKTests/SpacesAPITests.swift`, add this test inside `SpacesAPITests`:

```swift
func testSpaceDecodesWithEmptyEnrichment() throws {
    let json = Data("""
    {
      "id": "space-id",
      "title": "General",
      "type": "group",
      "teamId": "team-id"
    }
    """.utf8)

    let space = try JSONDecoder().decode(WebexSpace.self, from: json)

    XCTAssertEqual(space.id, "space-id")
    XCTAssertEqual(space.enriched, .empty)
    XCTAssertNil(space.enriched.teamName)
    XCTAssertNil(space.enriched.spaceAvatar)
    XCTAssertEqual(space.enriched.status, .empty)
    XCTAssertEqual(space.enriched.errors, [])
}
```

- [ ] **Step 2: Write failing generic stream item replacement test**

In `Tests/WebexSwiftSDKTests/WebexSnapshotStreamTests.swift`, add:

```swift
func testReplaceItemsEmitsSnapshotWithoutChangingPagination() async throws {
    let nextPage = WebexPageLink(url: URL(string: "https://webexapis.com/v1/rooms?cursor=next")!)
    let loader = ControllableStreamPageLoader()
    let stream = WebexSnapshotStream<StreamTestItem>(
        pageLimit: 3,
        id: { $0.id },
        loadFirstPage: { try await loader.loadFirstPage() },
        loadNextPage: { try await loader.loadNextPage($0) }
    )

    var iterator = stream.snapshots.makeAsyncIterator()
    _ = await iterator.next()

    let refresh = Task { await stream.refresh() }
    _ = await iterator.next()
    await loader.succeedFirstPage(
        items: [.init(id: "item-1", value: "Base")],
        nextPage: nextPage
    )
    await refresh.value
    _ = try await nextSnapshot(from: &iterator)

    await stream.replaceItems(
        [.init(id: "item-1", value: "Enriched")],
        incrementRevision: true
    )

    let replaced = try await nextSnapshot(from: &iterator)
    XCTAssertEqual(replaced.items, [.init(id: "item-1", value: "Enriched")])
    XCTAssertEqual(replaced.revision, 2)
    XCTAssertEqual(replaced.pagination.nextPage, nextPage)
    XCTAssertEqual(replaced.pagination.pagesLoaded, 1)
    XCTAssertFalse(replaced.isRefreshing)
    XCTAssertFalse(replaced.isLoadingNextPage)
}
```

- [ ] **Step 3: Run focused tests and verify they fail**

Run:

```bash
swift test --filter SpacesAPITests/testSpaceDecodesWithEmptyEnrichment
swift test --filter WebexSnapshotStreamTests/testReplaceItemsEmitsSnapshotWithoutChangingPagination
```

Expected: compile failure for missing `WebexSpace.enriched`, `WebexSpaceEnrichment`, or `WebexSnapshotStream.replaceItems`.

- [ ] **Step 4: Add enrichment models to `WebexSpace.swift`**

In `Sources/WebexSwiftSDK/API/WebexSpace.swift`, add these public types above `WebexSpace`:

```swift
public enum WebexSpaceEnrichmentStatus: Equatable, Sendable {
    case empty
    case loading
    case partial
    case complete
    case failed
}

public enum WebexSpaceEnrichmentField: Equatable, Sendable {
    case teamName
    case spaceAvatar
}

public struct WebexSpaceEnrichmentError: Equatable, Sendable {
    public let field: WebexSpaceEnrichmentField
    public let error: WebexSDKError

    public init(field: WebexSpaceEnrichmentField, error: WebexSDKError) {
        self.field = field
        self.error = error
    }
}

public struct WebexSpaceEnrichment: Equatable, Sendable {
    public static let empty = WebexSpaceEnrichment()

    public let teamName: String?
    public let spaceAvatar: String?
    public let status: WebexSpaceEnrichmentStatus
    public let errors: [WebexSpaceEnrichmentError]

    public init(
        teamName: String? = nil,
        spaceAvatar: String? = nil,
        status: WebexSpaceEnrichmentStatus = .empty,
        errors: [WebexSpaceEnrichmentError] = []
    ) {
        self.teamName = teamName
        self.spaceAvatar = spaceAvatar
        self.status = status
        self.errors = errors
    }
}
```

Modify `WebexSpace` so it has the property and initializer argument:

```swift
public let enriched: WebexSpaceEnrichment
```

Add the initializer parameter:

```swift
enriched: WebexSpaceEnrichment = .empty
```

Assign it in the initializer:

```swift
self.enriched = enriched
```

In `init(from decoder:)`, assign the SDK-owned default after decoding REST fields:

```swift
self.enriched = .empty
```

Add a copy helper at the end of `WebexSpace`:

```swift
func replacingEnrichment(_ enrichment: WebexSpaceEnrichment) -> WebexSpace {
    WebexSpace(
        id: id,
        title: title,
        type: type,
        isLocked: isLocked,
        teamID: teamID,
        lastActivity: lastActivity,
        creatorID: creatorID,
        created: created,
        ownerID: ownerID,
        description: description,
        isPublic: isPublic,
        isReadOnly: isReadOnly,
        isAnnouncementOnly: isAnnouncementOnly,
        classificationID: classificationID,
        madePublic: madePublic,
        errors: errors,
        enriched: enrichment
    )
}
```

- [ ] **Step 5: Add shared stream error redactor**

Create `Sources/WebexSwiftSDK/Streams/WebexStreamErrorRedactor.swift`:

```swift
import Foundation

enum WebexStreamErrorRedactor {
    static func webexStreamError(from error: Error) -> WebexSDKError {
        switch error {
        case let sdkError as WebexSDKError:
            return redacted(sdkError)
        default:
            return .network(Redactor.redactOAuthCallback(error.localizedDescription))
        }
    }

    static func redacted(_ error: WebexSDKError) -> WebexSDKError {
        switch error {
        case .invalidAccountID(let rawValue):
            return .invalidAccountID(Redactor.redactSecrets(rawValue))
        case .invalidAuthorizationCallback(let callback):
            return .invalidAuthorizationCallback(Redactor.redactOAuthCallback(callback))
        case .authorizationStateMismatch,
             .userCancelledAuthorization,
             .missingCredential,
             .missingRefreshToken,
             .reauthenticationRequired,
             .rateLimited:
            return error
        case .duplicateAccount(let existing, let reason):
            return .duplicateAccount(existing: existing, reason: Redactor.redactSecrets(reason))
        case .tokenExchangeFailed(let statusCode, let message, let trackingID):
            return .tokenExchangeFailed(
                statusCode: statusCode,
                message: Redactor.redactSecrets(message),
                trackingID: trackingID.map(Redactor.redactSecrets)
            )
        case .locked(let retryAfter, let trackingID, let message):
            return .locked(
                retryAfter: retryAfter,
                trackingID: trackingID.map(Redactor.redactSecrets),
                message: Redactor.redactSecrets(message)
            )
        case .webexAPI(let statusCode, let trackingID, let message):
            return .webexAPI(
                statusCode: statusCode,
                trackingID: trackingID.map(Redactor.redactSecrets),
                message: Redactor.redactSecrets(message)
            )
        case .network(let message):
            return .network(Redactor.redactOAuthCallback(message))
        }
    }
}
```

- [ ] **Step 6: Add internal item replacement to `WebexSnapshotStream`**

In `Sources/WebexSwiftSDK/Streams/WebexSnapshotStream.swift`, add this internal method to `WebexSnapshotStream`:

```swift
func replaceItems(
    _ items: [Item],
    incrementRevision: Bool = true
) async {
    await state.replaceItems(items, incrementRevision: incrementRevision)
}
```

Add this method to `WebexSnapshotStreamState`:

```swift
func replaceItems(
    _ newItems: [Item],
    incrementRevision: Bool
) {
    items = newItems
    if incrementRevision {
        revision += 1
    }
    emitSnapshot()
}
```

Replace the private `webexStreamError(from:)` implementation with:

```swift
private static func webexStreamError(from error: Error) -> WebexSDKError {
    WebexStreamErrorRedactor.webexStreamError(from: error)
}
```

Remove the old private `redacted(_:)` helper from `WebexSnapshotStreamState` after the call site is changed.

- [ ] **Step 7: Run focused tests and verify they pass**

Run:

```bash
swift test --filter SpacesAPITests/testSpaceDecodesWithEmptyEnrichment
swift test --filter WebexSnapshotStreamTests/testReplaceItemsEmitsSnapshotWithoutChangingPagination
swift test --filter WebexSnapshotStreamTests/testRefreshFailurePreservesExistingItemsAndPublishesRedactedError
```

Expected: all three tests pass.

- [ ] **Step 8: Commit enrichment models and stream mutation**

Run:

```bash
git add Sources/WebexSwiftSDK/API/WebexSpace.swift Sources/WebexSwiftSDK/Streams/WebexSnapshotStream.swift Sources/WebexSwiftSDK/Streams/WebexStreamErrorRedactor.swift Tests/WebexSwiftSDKTests/SpacesAPITests.swift Tests/WebexSwiftSDKTests/WebexSnapshotStreamTests.swift
git commit -m "feat: add space enrichment model"
```

Expected: commit succeeds.

### Task 3: Space Enrichment Coordinator

**Files:**
- Create: `Sources/WebexSwiftSDK/Streams/WebexSpaceEnrichmentCoordinator.swift`
- Create: `Tests/WebexSwiftSDKTests/WebexSpaceEnrichmentCoordinatorTests.swift`

- [ ] **Step 1: Write failing coordinator tests**

Create `Tests/WebexSwiftSDKTests/WebexSpaceEnrichmentCoordinatorTests.swift`:

```swift
import XCTest
@testable import WebexSwiftSDK

final class WebexSpaceEnrichmentCoordinatorTests: XCTestCase {
    func testImmediateItemsMarkApplicableUncachedFieldsLoading() async {
        let dependencies = RecordingSpaceEnrichmentDependencies()
        let coordinator = WebexSpaceEnrichmentCoordinator(dependencies: dependencies.makeDependencies())
        let spaces = [
            space(id: "team-space", type: .group, teamID: "team-1"),
            space(id: "direct-space", type: .direct)
        ]

        let immediate = await coordinator.immediateItems(for: spaces, forceRefresh: false)

        XCTAssertEqual(immediate[0].enriched.status, .loading)
        XCTAssertNil(immediate[0].enriched.teamName)
        XCTAssertEqual(immediate[0].enriched.errors, [])
        XCTAssertEqual(immediate[1].enriched.status, .loading)
        XCTAssertNil(immediate[1].enriched.spaceAvatar)
        XCTAssertEqual(immediate[1].enriched.errors, [])
    }

    func testEnrichesTeamNameAndCachesAcrossOrdinaryRefreshes() async {
        let dependencies = RecordingSpaceEnrichmentDependencies()
        dependencies.teamByID["team-1"] = WebexTeam(id: "team-1", name: "Platform")
        let coordinator = WebexSpaceEnrichmentCoordinator(dependencies: dependencies.makeDependencies())
        let spaces = [space(id: "team-space", type: .group, teamID: "team-1")]

        let first = await coordinator.enrichedItems(for: spaces, forceRefresh: false)
        let second = await coordinator.enrichedItems(for: spaces, forceRefresh: false)

        XCTAssertEqual(first[0].enriched.teamName, "Platform")
        XCTAssertEqual(first[0].enriched.status, .complete)
        XCTAssertEqual(second[0].enriched.teamName, "Platform")
        XCTAssertEqual(dependencies.teamRequests, ["team-1"])
    }

    func testForceRefreshBypassesCachedTeamName() async {
        let dependencies = RecordingSpaceEnrichmentDependencies()
        dependencies.teamByID["team-1"] = WebexTeam(id: "team-1", name: "Old")
        let coordinator = WebexSpaceEnrichmentCoordinator(dependencies: dependencies.makeDependencies())
        let spaces = [space(id: "team-space", type: .group, teamID: "team-1")]

        let first = await coordinator.enrichedItems(for: spaces, forceRefresh: false)
        dependencies.teamByID["team-1"] = WebexTeam(id: "team-1", name: "New")
        let second = await coordinator.enrichedItems(for: spaces, forceRefresh: true)

        XCTAssertEqual(first[0].enriched.teamName, "Old")
        XCTAssertEqual(second[0].enriched.teamName, "New")
        XCTAssertEqual(dependencies.teamRequests, ["team-1", "team-1"])
    }

    func testDirectSpaceAvatarUsesOtherPersonAvatar() async {
        let dependencies = RecordingSpaceEnrichmentDependencies()
        dependencies.selfPerson = person(id: "self", avatar: "https://example.com/self.png")
        dependencies.membershipsByRoomID["direct-space"] = [
            WebexMembership(id: "m-self", roomID: "direct-space", personID: "self"),
            WebexMembership(id: "m-other", roomID: "direct-space", personID: "other")
        ]
        dependencies.personByID["other"] = person(id: "other", avatar: "https://example.com/other.png")
        let coordinator = WebexSpaceEnrichmentCoordinator(dependencies: dependencies.makeDependencies())

        let enriched = await coordinator.enrichedItems(
            for: [space(id: "direct-space", type: .direct)],
            forceRefresh: false
        )

        XCTAssertEqual(enriched[0].enriched.spaceAvatar, "https://example.com/other.png")
        XCTAssertEqual(enriched[0].enriched.status, .complete)
        XCTAssertEqual(dependencies.meRequests, 1)
        XCTAssertEqual(dependencies.membershipRequests, ["direct-space"])
        XCTAssertEqual(dependencies.personRequests, ["other"])
    }

    func testDirectSpaceAvatarFailureIsFieldScopedAndRedacted() async {
        let dependencies = RecordingSpaceEnrichmentDependencies()
        dependencies.selfPerson = person(id: "self", avatar: nil)
        dependencies.membershipsByRoomID["direct-space"] = [
            WebexMembership(id: "m-self", roomID: "direct-space", personID: "self"),
            WebexMembership(id: "m-other", roomID: "direct-space", personID: "other")
        ]
        dependencies.personErrorByID["other"] = .network("callback code=secret-code")
        let coordinator = WebexSpaceEnrichmentCoordinator(dependencies: dependencies.makeDependencies())

        let enriched = await coordinator.enrichedItems(
            for: [space(id: "direct-space", type: .direct)],
            forceRefresh: false
        )

        XCTAssertNil(enriched[0].enriched.spaceAvatar)
        XCTAssertEqual(enriched[0].enriched.status, .failed)
        XCTAssertEqual(enriched[0].enriched.errors.count, 1)
        XCTAssertEqual(enriched[0].enriched.errors.first?.field, .spaceAvatar)
        XCTAssertEqual(enriched[0].enriched.errors.first?.error, .network("callback code=[redacted]"))
    }

    func testGroupSpaceWithoutTeamHasEmptyEnrichment() async {
        let dependencies = RecordingSpaceEnrichmentDependencies()
        let coordinator = WebexSpaceEnrichmentCoordinator(dependencies: dependencies.makeDependencies())

        let enriched = await coordinator.enrichedItems(
            for: [space(id: "plain-group", type: .group)],
            forceRefresh: false
        )

        XCTAssertEqual(enriched[0].enriched, .empty)
        XCTAssertEqual(dependencies.teamRequests, [])
        XCTAssertEqual(dependencies.membershipRequests, [])
        XCTAssertEqual(dependencies.personRequests, [])
    }
}

private func space(
    id: String,
    type: WebexSpaceType?,
    teamID: String? = nil
) -> WebexSpace {
    WebexSpace(
        id: id,
        title: id,
        type: type,
        teamID: teamID
    )
}

private func person(id: String, avatar: String?) -> WebexPerson {
    WebexPerson(
        id: id,
        emails: ["\(id)@example.com"],
        avatar: avatar
    )
}

private final class RecordingSpaceEnrichmentDependencies: @unchecked Sendable {
    var teamByID: [String: WebexTeam] = [:]
    var teamErrorByID: [String: WebexSDKError] = [:]
    var selfPerson = person(id: "self", avatar: nil)
    var meError: WebexSDKError?
    var membershipsByRoomID: [String: [WebexMembership]] = [:]
    var membershipsErrorByRoomID: [String: WebexSDKError] = [:]
    var personByID: [String: WebexPerson] = [:]
    var personErrorByID: [String: WebexSDKError] = [:]

    private(set) var teamRequests: [String] = []
    private(set) var meRequests = 0
    private(set) var membershipRequests: [String] = []
    private(set) var personRequests: [String] = []

    func makeDependencies() -> WebexSpaceEnrichmentCoordinator.Dependencies {
        WebexSpaceEnrichmentCoordinator.Dependencies(
            getTeam: { [self] teamID in
                teamRequests.append(teamID)
                if let error = teamErrorByID[teamID] {
                    throw error
                }
                return teamByID[teamID] ?? WebexTeam(id: teamID)
            },
            getSelf: { [self] in
                meRequests += 1
                if let meError {
                    throw meError
                }
                return selfPerson
            },
            listMemberships: { [self] roomID in
                membershipRequests.append(roomID)
                if let error = membershipsErrorByRoomID[roomID] {
                    throw error
                }
                return membershipsByRoomID[roomID] ?? []
            },
            getPerson: { [self] personID in
                personRequests.append(personID)
                if let error = personErrorByID[personID] {
                    throw error
                }
                return personByID[personID] ?? person(id: personID, avatar: nil)
            }
        )
    }
}
```

- [ ] **Step 2: Run coordinator tests and verify they fail**

Run:

```bash
swift test --filter WebexSpaceEnrichmentCoordinatorTests
```

Expected: compile failure for missing `WebexSpaceEnrichmentCoordinator`.

- [ ] **Step 3: Implement coordinator dependencies and cache**

Create `Sources/WebexSwiftSDK/Streams/WebexSpaceEnrichmentCoordinator.swift` with this structure:

```swift
import Foundation

actor WebexSpaceEnrichmentCoordinator {
    struct Dependencies: Sendable {
        let getTeam: @Sendable (String) async throws -> WebexTeam
        let getSelf: @Sendable () async throws -> WebexPerson
        let listMemberships: @Sendable (String) async throws -> [WebexMembership]
        let getPerson: @Sendable (String) async throws -> WebexPerson
    }

    private struct FieldValues: Equatable, Sendable {
        var teamName: String?
        var spaceAvatar: String?
        var errors: [WebexSpaceEnrichmentError] = []
    }

    private let dependencies: Dependencies
    private var teamNameByID: [String: String?] = [:]
    private var selfPersonID: String?
    private var otherPersonIDBySpaceID: [String: String?] = [:]
    private var avatarByPersonID: [String: String?] = [:]

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }
```

- [ ] **Step 4: Implement immediate cached/loading enrichment**

Add this method inside `WebexSpaceEnrichmentCoordinator`:

```swift
func immediateItems(
    for spaces: [WebexSpace],
    forceRefresh: Bool
) -> [WebexSpace] {
    spaces.map { space in
        let applicable = applicableFields(for: space)
        guard !applicable.isEmpty else {
            return space.replacingEnrichment(.empty)
        }

        if forceRefresh {
            return space.replacingEnrichment(WebexSpaceEnrichment(status: .loading))
        }

        var values = FieldValues()
        var pending = false

        if applicable.contains(.teamName), let teamID = space.teamID {
            if let cached = teamNameByID[teamID] {
                values.teamName = cached
            } else {
                pending = true
            }
        }

        if applicable.contains(.spaceAvatar) {
            if let cachedOtherPersonID = otherPersonIDBySpaceID[space.id],
               let otherPersonID = cachedOtherPersonID,
               let cachedAvatar = avatarByPersonID[otherPersonID] {
                values.spaceAvatar = cachedAvatar
            } else {
                pending = true
            }
        }

        let status = status(
            applicableFields: applicable,
            values: values,
            hasPendingWork: pending
        )
        return space.replacingEnrichment(WebexSpaceEnrichment(
            teamName: values.teamName,
            spaceAvatar: values.spaceAvatar,
            status: status,
            errors: values.errors
        ))
    }
}
```

- [ ] **Step 5: Implement final enrichment resolution**

Add:

```swift
func enrichedItems(
    for spaces: [WebexSpace],
    forceRefresh: Bool
) async -> [WebexSpace] {
    var enriched: [WebexSpace] = []
    enriched.reserveCapacity(spaces.count)

    for space in spaces {
        let applicable = applicableFields(for: space)
        guard !applicable.isEmpty else {
            enriched.append(space.replacingEnrichment(.empty))
            continue
        }

        var values = FieldValues()

        if applicable.contains(.teamName), let teamID = space.teamID {
            await resolveTeamName(teamID: teamID, forceRefresh: forceRefresh, values: &values)
        }

        if applicable.contains(.spaceAvatar) {
            await resolveSpaceAvatar(spaceID: space.id, forceRefresh: forceRefresh, values: &values)
        }

        enriched.append(space.replacingEnrichment(WebexSpaceEnrichment(
            teamName: values.teamName,
            spaceAvatar: values.spaceAvatar,
            status: status(
                applicableFields: applicable,
                values: values,
                hasPendingWork: false
            ),
            errors: values.errors
        )))
    }

    return enriched
}
```

- [ ] **Step 6: Implement field resolvers**

Add:

```swift
private func resolveTeamName(
    teamID: String,
    forceRefresh: Bool,
    values: inout FieldValues
) async {
    if !forceRefresh, let cached = teamNameByID[teamID] {
        values.teamName = cached
        return
    }

    do {
        let team = try await dependencies.getTeam(teamID)
        teamNameByID[teamID] = team.name
        values.teamName = team.name
    } catch {
        values.errors.append(WebexSpaceEnrichmentError(
            field: .teamName,
            error: WebexStreamErrorRedactor.webexStreamError(from: error)
        ))
    }
}

private func resolveSpaceAvatar(
    spaceID: String,
    forceRefresh: Bool,
    values: inout FieldValues
) async {
    do {
        let otherPersonID = try await otherPersonID(for: spaceID, forceRefresh: forceRefresh)
        guard let otherPersonID else {
            values.errors.append(WebexSpaceEnrichmentError(
                field: .spaceAvatar,
                error: .network("Missing direct space participant")
            ))
            return
        }

        if !forceRefresh, let cached = avatarByPersonID[otherPersonID] {
            values.spaceAvatar = cached
            return
        }

        let person = try await dependencies.getPerson(otherPersonID)
        avatarByPersonID[otherPersonID] = person.avatar
        values.spaceAvatar = person.avatar
    } catch {
        values.errors.append(WebexSpaceEnrichmentError(
            field: .spaceAvatar,
            error: WebexStreamErrorRedactor.webexStreamError(from: error)
        ))
    }
}

private func otherPersonID(
    for spaceID: String,
    forceRefresh: Bool
) async throws -> String? {
    if !forceRefresh, let cached = otherPersonIDBySpaceID[spaceID] {
        return cached
    }

    let selfID: String
    if !forceRefresh, let cachedSelfPersonID = selfPersonID {
        selfID = cachedSelfPersonID
    } else {
        let me = try await dependencies.getSelf()
        selfPersonID = me.id
        selfID = me.id
    }

    let memberships = try await dependencies.listMemberships(spaceID)
    let otherPersonID = memberships
        .compactMap(\.personID)
        .first { $0 != selfID }

    otherPersonIDBySpaceID[spaceID] = otherPersonID
    return otherPersonID
}
```

- [ ] **Step 7: Implement status helpers**

Add:

```swift
private func applicableFields(for space: WebexSpace) -> Set<WebexSpaceEnrichmentField> {
    var fields: Set<WebexSpaceEnrichmentField> = []
    if space.teamID != nil {
        fields.insert(.teamName)
    }
    if space.type == .direct {
        fields.insert(.spaceAvatar)
    }
    return fields
}

private func status(
    applicableFields: Set<WebexSpaceEnrichmentField>,
    values: FieldValues,
    hasPendingWork: Bool
) -> WebexSpaceEnrichmentStatus {
    guard !applicableFields.isEmpty else {
        return .empty
    }

    if hasPendingWork {
        return .loading
    }

    let successfulFields = successfulFieldCount(values: values)
    let failedFields = values.errors.count

    if failedFields == 0 {
        return .complete
    }

    if successfulFields > 0 {
        return .partial
    }

    return .failed
}

private func successfulFieldCount(values: FieldValues) -> Int {
    var count = 0
    if values.teamName != nil {
        count += 1
    }
    if values.spaceAvatar != nil {
        count += 1
    }
    return count
}
```

- [ ] **Step 8: Run coordinator tests and verify they pass**

Run:

```bash
swift test --filter WebexSpaceEnrichmentCoordinatorTests
```

Expected: all coordinator tests pass.

- [ ] **Step 9: Commit coordinator**

Run:

```bash
git add Sources/WebexSwiftSDK/Streams/WebexSpaceEnrichmentCoordinator.swift Tests/WebexSwiftSDKTests/WebexSpaceEnrichmentCoordinatorTests.swift
git commit -m "feat: enrich space details"
```

Expected: commit succeeds.

### Task 4: SpacesStream Wrapper And API Adapter

**Files:**
- Create: `Sources/WebexSwiftSDK/Streams/SpacesStream.swift`
- Modify: `Sources/WebexSwiftSDK/Streams/WebexAPIStreams.swift`
- Modify: `Sources/WebexSwiftSDK/API/SpacesAPI.swift`
- Modify: `Tests/WebexSwiftSDKTests/WebexAPIStreamAdapterTests.swift`
- Create: `Tests/WebexSwiftSDKTests/SpacesStreamTests.swift`

- [ ] **Step 1: Write failing direct `SpacesStream` tests**

Create `Tests/WebexSwiftSDKTests/SpacesStreamTests.swift`:

```swift
import XCTest
@testable import WebexSwiftSDK

final class SpacesStreamTests: XCTestCase {
    func testRefreshEmitsLoadingThenResolvedEnrichment() async throws {
        let loader = ControllableSpacesPageLoader()
        let dependencies = RecordingSpacesStreamDependencies()
        dependencies.teamByID["team-1"] = WebexTeam(id: "team-1", name: "Platform")
        let stream = SpacesStream(
            baseStream: WebexSnapshotStream<WebexSpace>(
                id: { $0.id },
                loadFirstPage: { try await loader.loadFirstPage() },
                loadNextPage: { try await loader.loadNextPage($0) }
            ),
            enricher: WebexSpaceEnrichmentCoordinator(dependencies: dependencies.makeDependencies())
        )

        var iterator = stream.snapshots.makeAsyncIterator()
        _ = try await nextSnapshot(from: &iterator)

        let refresh = Task { await stream.refresh() }
        _ = try await nextSnapshot(from: &iterator)
        await loader.succeedFirstPage(items: [
            WebexSpace(id: "space-1", title: "General", type: .group, teamID: "team-1")
        ])

        let loading = try await nextSnapshot(from: &iterator)
        XCTAssertEqual(loading.items[0].enriched.status, .loading)
        XCTAssertNil(loading.items[0].enriched.teamName)

        await refresh.value
        let enriched = try await nextSnapshot(from: &iterator)
        XCTAssertEqual(enriched.items[0].enriched.teamName, "Platform")
        XCTAssertEqual(enriched.items[0].enriched.status, .complete)
        XCTAssertNil(enriched.lastError)
    }

    func testRefreshEnrichmentDoesNotReloadBaseSpaces() async throws {
        let loader = ControllableSpacesPageLoader()
        let dependencies = RecordingSpacesStreamDependencies()
        dependencies.teamByID["team-1"] = WebexTeam(id: "team-1", name: "Old")
        let stream = SpacesStream(
            baseStream: WebexSnapshotStream<WebexSpace>(
                id: { $0.id },
                loadFirstPage: { try await loader.loadFirstPage() },
                loadNextPage: { try await loader.loadNextPage($0) }
            ),
            enricher: WebexSpaceEnrichmentCoordinator(dependencies: dependencies.makeDependencies())
        )

        var iterator = stream.snapshots.makeAsyncIterator()
        _ = try await nextSnapshot(from: &iterator)

        let refresh = Task { await stream.refresh() }
        _ = try await nextSnapshot(from: &iterator)
        await loader.succeedFirstPage(items: [
            WebexSpace(id: "space-1", title: "General", type: .group, teamID: "team-1")
        ])
        _ = try await nextSnapshot(from: &iterator)
        await refresh.value
        _ = try await nextSnapshot(from: &iterator)

        dependencies.teamByID["team-1"] = WebexTeam(id: "team-1", name: "New")
        await stream.refreshEnrichment()

        let loading = try await nextSnapshot(from: &iterator)
        XCTAssertEqual(loading.items[0].enriched.status, .loading)
        let refreshed = try await nextSnapshot(from: &iterator)
        XCTAssertEqual(refreshed.items[0].enriched.teamName, "New")
        XCTAssertEqual(await loader.firstPageCallCountValue(), 1)
        XCTAssertEqual(dependencies.teamRequests, ["team-1", "team-1"])
    }
}

private func nextSnapshot(
    from iterator: inout AsyncStream<WebexStreamSnapshot<WebexSpace>>.Iterator
) async throws -> WebexStreamSnapshot<WebexSpace> {
    let snapshot = await iterator.next()
    return try XCTUnwrap(snapshot)
}

private actor ControllableSpacesPageLoader {
    private(set) var firstPageCallCount = 0
    private var firstPageContinuations: [CheckedContinuation<WebexStreamPage<WebexSpace>, Error>] = []

    func loadFirstPage() async throws -> WebexStreamPage<WebexSpace> {
        firstPageCallCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            firstPageContinuations.append(continuation)
        }
    }

    func loadNextPage(_ nextPage: WebexPageLink) async throws -> WebexStreamPage<WebexSpace> {
        WebexStreamPage(items: [], nextPage: nil)
    }

    func succeedFirstPage(items: [WebexSpace]) {
        firstPageContinuations.removeFirst().resume(returning: WebexStreamPage(
            items: items,
            nextPage: nil
        ))
    }

    func firstPageCallCountValue() -> Int {
        firstPageCallCount
    }
}

private final class RecordingSpacesStreamDependencies: @unchecked Sendable {
    var teamByID: [String: WebexTeam] = [:]
    private(set) var teamRequests: [String] = []

    func makeDependencies() -> WebexSpaceEnrichmentCoordinator.Dependencies {
        WebexSpaceEnrichmentCoordinator.Dependencies(
            getTeam: { [self] teamID in
                teamRequests.append(teamID)
                return teamByID[teamID] ?? WebexTeam(id: teamID)
            },
            getSelf: {
                WebexPerson(id: "self", emails: ["self@example.com"])
            },
            listMemberships: { _ in [] },
            getPerson: { personID in
                WebexPerson(id: personID, emails: ["\(personID)@example.com"])
            }
        )
    }
}
```

- [ ] **Step 2: Add failing API adapter test for enriched spaces stream**

In `Tests/WebexSwiftSDKTests/WebexAPIStreamAdapterTests.swift`, add:

```swift
func testSpacesStreamEnrichesTeamNameAndDirectSpaceAvatar() async throws {
    let httpClient = StreamAdapterHTTPClient()
    await httpClient.enqueue(
        json: #"{"items":[{"id":"team-space","title":"Team Space","type":"group","teamId":"team-1"},{"id":"direct-space","title":"Direct","type":"direct"}]}"#
    )
    await httpClient.enqueue(json: #"{"id":"team-1","name":"Platform Team"}"#)
    await httpClient.enqueue(json: #"{"id":"self","emails":["self@example.com"]}"#)
    await httpClient.enqueue(json: #"{"items":[{"id":"m-self","roomId":"direct-space","personId":"self"},{"id":"m-other","roomId":"direct-space","personId":"other"}]}"#)
    await httpClient.enqueue(json: #"{"id":"other","emails":["other@example.com"],"avatar":"https://example.com/other.png"}"#)

    let stream = makeSpacesAPI(httpClient: httpClient)
        .stream(params: .init(sortBy: .lastActivity, max: 2), pageLimit: 1)

    await stream.refresh()

    let snapshot = await stream.currentSnapshot()
    XCTAssertEqual(snapshot.items.first(where: { $0.id == "team-space" })?.enriched.teamName, "Platform Team")
    XCTAssertEqual(snapshot.items.first(where: { $0.id == "direct-space" })?.enriched.spaceAvatar, "https://example.com/other.png")
    XCTAssertEqual(snapshot.items.map(\.enriched.status), [.complete, .complete])

    let requestURLs = await httpClient.requestURLs
    XCTAssertEqual(requestURLs, [
        "https://webexapis.com/v1/rooms?sortBy=lastactivity&max=2",
        "https://webexapis.com/v1/teams/team-1",
        "https://webexapis.com/v1/people/me",
        "https://webexapis.com/v1/memberships?roomId=direct-space",
        "https://webexapis.com/v1/people/other"
    ])
}
```

- [ ] **Step 3: Run stream tests and verify they fail**

Run:

```bash
swift test --filter SpacesStreamTests
swift test --filter WebexAPIStreamAdapterTests/testSpacesStreamEnrichesTeamNameAndDirectSpaceAvatar
```

Expected: compile failure for missing named `SpacesStream` or failing assertion because `SpacesAPI.stream` still returns the generic stream.

- [ ] **Step 4: Allow stream adapters to construct sibling APIs**

In `Sources/WebexSwiftSDK/API/SpacesAPI.swift`, change:

```swift
private let transport: WebexTransport
```

to:

```swift
let transport: WebexTransport
```

Keep `public init(transport:)` unchanged.

- [ ] **Step 5: Implement named `SpacesStream`**

Create `Sources/WebexSwiftSDK/Streams/SpacesStream.swift`:

```swift
import Foundation

public final class SpacesStream: @unchecked Sendable {
    private let baseStream: WebexSnapshotStream<WebexSpace>
    private let enricher: WebexSpaceEnrichmentCoordinator
    private let generation = SpacesStreamGeneration()

    public var snapshots: AsyncStream<WebexStreamSnapshot<WebexSpace>> {
        baseStream.snapshots
    }

    init(
        baseStream: WebexSnapshotStream<WebexSpace>,
        enricher: WebexSpaceEnrichmentCoordinator
    ) {
        self.baseStream = baseStream
        self.enricher = enricher
    }

    public func currentSnapshot() async -> WebexStreamSnapshot<WebexSpace> {
        await baseStream.currentSnapshot()
    }

    public func refresh() async {
        await baseStream.refresh()
        await runEnrichment(forceRefresh: false)
    }

    public func loadNextPage() async {
        await baseStream.loadNextPage()
        await runEnrichment(forceRefresh: false)
    }

    public func refreshEnrichment() async {
        await runEnrichment(forceRefresh: true)
    }

    public func refreshOnTriggers(
        _ triggers: AsyncStream<WebexStreamTrigger>,
        where shouldRefresh: @escaping @Sendable (WebexStreamTrigger) -> Bool = { _ in true }
    ) -> Task<Void, Never> {
        Task { [weak self] in
            for await trigger in triggers {
                guard !Task.isCancelled else {
                    return
                }

                guard shouldRefresh(trigger) else {
                    continue
                }

                guard let self else {
                    return
                }

                await self.refresh()
            }
        }
    }

    private func runEnrichment(forceRefresh: Bool) async {
        let generationID = await generation.next()
        let snapshot = await baseStream.currentSnapshot()
        let loadingItems = await enricher.immediateItems(
            for: snapshot.items,
            forceRefresh: forceRefresh
        )
        guard await generation.isCurrent(generationID) else {
            return
        }

        await baseStream.replaceItems(loadingItems, incrementRevision: false)

        let enrichedItems = await enricher.enrichedItems(
            for: snapshot.items,
            forceRefresh: forceRefresh
        )
        guard await generation.isCurrent(generationID) else {
            return
        }

        if enrichedItems != loadingItems {
            await baseStream.replaceItems(enrichedItems, incrementRevision: true)
        }
    }
}

private actor SpacesStreamGeneration {
    private var value: UInt64 = 0

    func next() -> UInt64 {
        value += 1
        return value
    }

    func isCurrent(_ candidate: UInt64) -> Bool {
        value == candidate
    }
}

public typealias RoomsStream = SpacesStream
```

- [ ] **Step 6: Update stream API adapter**

Modify `Sources/WebexSwiftSDK/Streams/WebexAPIStreams.swift`:

Remove:

```swift
public typealias SpacesStream = WebexSnapshotStream<WebexSpace>
public typealias RoomsStream = SpacesStream
```

Replace the `SpacesAPI.stream(params:pageLimit:)` body with:

```swift
func stream(
    params: ListSpacesParams = ListSpacesParams(),
    pageLimit: Int? = nil
) -> SpacesStream {
    let baseStream = WebexSnapshotStream(
        pageLimit: pageLimit,
        id: { $0.id },
        loadFirstPage: {
            let page = try await list(params: params)
            return WebexStreamPage(items: page.items, nextPage: page.nextPage)
        },
        loadNextPage: { nextPage in
            let page = try await list(nextPage: nextPage)
            return WebexStreamPage(items: page.items, nextPage: page.nextPage)
        }
    )
    let teams = TeamsAPI(transport: transport)
    let people = PeopleAPI(transport: transport)
    let memberships = MembershipsAPI(transport: transport)
    let enricher = WebexSpaceEnrichmentCoordinator(dependencies: .init(
        getTeam: { teamID in
            try await teams.get(teamID: teamID)
        },
        getSelf: {
            try await people.me()
        },
        listMemberships: { roomID in
            let page = try await memberships.list(params: .init(roomID: roomID))
            return page.items
        },
        getPerson: { personID in
            try await people.get(personID: personID)
        }
    ))
    return SpacesStream(baseStream: baseStream, enricher: enricher)
}
```

Leave these aliases unchanged:

```swift
public typealias MessagesStream = WebexSnapshotStream<WebexMessage>
public typealias MembershipsStream = WebexSnapshotStream<WebexMembership>
```

- [ ] **Step 7: Run stream tests and adapter tests**

Run:

```bash
swift test --filter SpacesStreamTests
swift test --filter WebexAPIStreamAdapterTests/testSpacesStreamUsesSpacesListAndNextPage
swift test --filter WebexAPIStreamAdapterTests/testSpacesStreamEnrichesTeamNameAndDirectSpaceAvatar
```

Expected: all listed tests pass.

- [ ] **Step 8: Commit SpacesStream wrapper**

Run:

```bash
git add Sources/WebexSwiftSDK/Streams/SpacesStream.swift Sources/WebexSwiftSDK/Streams/WebexAPIStreams.swift Sources/WebexSwiftSDK/API/SpacesAPI.swift Tests/WebexSwiftSDKTests/SpacesStreamTests.swift Tests/WebexSwiftSDKTests/WebexAPIStreamAdapterTests.swift
git commit -m "feat: enrich spaces stream"
```

Expected: commit succeeds.

### Task 5: Enrichment Failure, Direct REST, And Stale Result Coverage

**Files:**
- Modify: `Tests/WebexSwiftSDKTests/WebexAPIStreamAdapterTests.swift`
- Modify: `Tests/WebexSwiftSDKTests/SpacesStreamTests.swift`
- Modify: `Sources/WebexSwiftSDK/Streams/SpacesStream.swift`
- Modify: `Sources/WebexSwiftSDK/Streams/WebexSpaceEnrichmentCoordinator.swift`

- [ ] **Step 1: Add direct REST no-hidden-call tests**

In `Tests/WebexSwiftSDKTests/WebexAPIStreamAdapterTests.swift`, add:

```swift
func testSpacesListReturnsEmptyEnrichmentWithoutFollowUpCalls() async throws {
    let httpClient = StreamAdapterHTTPClient()
    await httpClient.enqueue(
        json: #"{"items":[{"id":"team-space","title":"Team Space","type":"group","teamId":"team-1"}]}"#
    )

    let page = try await makeSpacesAPI(httpClient: httpClient)
        .list(params: .init(sortBy: .lastActivity, max: 1))

    XCTAssertEqual(page.items.first?.enriched, .empty)
    let requestURLs = await httpClient.requestURLs
    XCTAssertEqual(requestURLs, [
        "https://webexapis.com/v1/rooms?sortBy=lastactivity&max=1"
    ])
}

func testSpacesGetReturnsEmptyEnrichmentWithoutFollowUpCalls() async throws {
    let httpClient = StreamAdapterHTTPClient()
    await httpClient.enqueue(
        json: #"{"id":"team-space","title":"Team Space","type":"group","teamId":"team-1"}"#
    )

    let space = try await makeSpacesAPI(httpClient: httpClient)
        .get(spaceID: "team-space")

    XCTAssertEqual(space.enriched, .empty)
    let requestURLs = await httpClient.requestURLs
    XCTAssertEqual(requestURLs, [
        "https://webexapis.com/v1/rooms/team-space"
    ])
}
```

- [ ] **Step 2: Add stream enrichment failure test**

In `Tests/WebexSwiftSDKTests/WebexAPIStreamAdapterTests.swift`, add:

```swift
func testSpacesStreamEnrichmentFailureStaysOnItemAndDoesNotSetSnapshotLastError() async throws {
    let httpClient = StreamAdapterHTTPClient()
    await httpClient.enqueue(
        json: #"{"items":[{"id":"team-space","title":"Team Space","type":"group","teamId":"team-1"}]}"#
    )
    await httpClient.enqueue(
        json: #"{"message":"team lookup failed secret-access-token"}"#,
        statusCode: 500
    )
    await httpClient.enqueue(
        json: #"{"message":"team lookup failed secret-access-token"}"#,
        statusCode: 500
    )
    await httpClient.enqueue(
        json: #"{"message":"team lookup failed secret-access-token"}"#,
        statusCode: 500
    )

    let stream = makeSpacesAPI(httpClient: httpClient)
        .stream(params: .init(max: 1), pageLimit: 1)

    await stream.refresh()

    let snapshot = await stream.currentSnapshot()
    let space = try XCTUnwrap(snapshot.items.first)
    XCTAssertNil(snapshot.lastError)
    XCTAssertEqual(space.enriched.status, .failed)
    XCTAssertEqual(space.enriched.errors.first?.field, .teamName)
    XCTAssertFalse(String(describing: space.enriched.errors.first?.error).contains("secret-access-token"))
}
```

- [ ] **Step 3: Add stale enrichment result test**

In `Tests/WebexSwiftSDKTests/SpacesStreamTests.swift`, add a test with a slow first enrichment result and a fast second refresh:

```swift
func testStaleEnrichmentResultDoesNotOverwriteNewerSnapshot() async throws {
    let loader = ControllableSpacesPageLoader()
    let dependencies = PausedSpacesStreamDependencies()
    let stream = SpacesStream(
        baseStream: WebexSnapshotStream<WebexSpace>(
            id: { $0.id },
            loadFirstPage: { try await loader.loadFirstPage() },
            loadNextPage: { try await loader.loadNextPage($0) }
        ),
        enricher: WebexSpaceEnrichmentCoordinator(dependencies: dependencies.makeDependencies())
    )

    var iterator = stream.snapshots.makeAsyncIterator()
    _ = try await nextSnapshot(from: &iterator)

    let firstRefresh = Task { await stream.refresh() }
    _ = try await nextSnapshot(from: &iterator)
    await loader.succeedFirstPage(items: [
        WebexSpace(id: "space-1", title: "Old", type: .group, teamID: "team-old")
    ])
    _ = try await nextSnapshot(from: &iterator)
    await dependencies.waitForTeamRequest("team-old")

    let secondRefresh = Task { await stream.refresh() }
    _ = try await nextSnapshot(from: &iterator)
    await loader.succeedFirstPage(items: [
        WebexSpace(id: "space-1", title: "New", type: .group, teamID: "team-new")
    ])
    _ = try await nextSnapshot(from: &iterator)
    await dependencies.waitForTeamRequest("team-new")
    await dependencies.resumeTeamRequest(teamID: "team-new", team: WebexTeam(id: "team-new", name: "New Team"))
    await secondRefresh.value
    let newEnriched = try await nextSnapshot(from: &iterator)
    XCTAssertEqual(newEnriched.items.first?.title, "New")
    XCTAssertEqual(newEnriched.items.first?.enriched.teamName, "New Team")

    await dependencies.resumeTeamRequest(teamID: "team-old", team: WebexTeam(id: "team-old", name: "Old Team"))
    await firstRefresh.value
    let current = await stream.currentSnapshot()
    XCTAssertEqual(current.items.first?.title, "New")
    XCTAssertEqual(current.items.first?.enriched.teamName, "New Team")
}
```

Add the helper actor below the existing helpers in `SpacesStreamTests.swift`:

```swift
private actor PausedSpacesStreamDependencies {
    private var continuationsByTeamID: [String: CheckedContinuation<WebexTeam, Error>] = [:]
    private var waitersByTeamID: [String: [CheckedContinuation<Void, Never>]] = [:]

    func makeDependencies() -> WebexSpaceEnrichmentCoordinator.Dependencies {
        WebexSpaceEnrichmentCoordinator.Dependencies(
            getTeam: { teamID in
                try await self.getTeam(teamID: teamID)
            },
            getSelf: {
                WebexPerson(id: "self", emails: ["self@example.com"])
            },
            listMemberships: { _ in [] },
            getPerson: { personID in
                WebexPerson(id: personID, emails: ["\(personID)@example.com"])
            }
        )
    }

    func getTeam(teamID: String) async throws -> WebexTeam {
        waitersByTeamID[teamID]?.forEach { $0.resume() }
        waitersByTeamID[teamID] = nil

        return try await withCheckedThrowingContinuation { continuation in
            continuationsByTeamID[teamID] = continuation
        }
    }

    func waitForTeamRequest(_ teamID: String) async {
        if continuationsByTeamID[teamID] != nil {
            return
        }

        await withCheckedContinuation { continuation in
            waitersByTeamID[teamID, default: []].append(continuation)
        }
    }

    func resumeTeamRequest(teamID: String, team: WebexTeam) {
        continuationsByTeamID.removeValue(forKey: teamID)?.resume(returning: team)
    }
}
```

- [ ] **Step 4: Run the new tests**

Run:

```bash
swift test --filter WebexAPIStreamAdapterTests/testSpacesListReturnsEmptyEnrichmentWithoutFollowUpCalls
swift test --filter WebexAPIStreamAdapterTests/testSpacesGetReturnsEmptyEnrichmentWithoutFollowUpCalls
swift test --filter WebexAPIStreamAdapterTests/testSpacesStreamEnrichmentFailureStaysOnItemAndDoesNotSetSnapshotLastError
swift test --filter SpacesStreamTests/testStaleEnrichmentResultDoesNotOverwriteNewerSnapshot
```

Expected: all four tests compile. Direct REST tests pass with one recorded rooms request each. The enrichment failure test passes with three queued `500` responses, matching the default retry budget. The stale-result test passes when `SpacesStream` uses the generation guard from Task 4.

- [ ] **Step 5: Confirm failure handling and stale generation code**

Keep three `500` responses in the failure test because `RetryPolicy.maxAttempts` defaults to 3. Ensure `SpacesStream.runEnrichment(forceRefresh:)` calls `generation.next()` before reading the current snapshot and checks `generation.isCurrent(_:)` before every `replaceItems` call:

```swift
private func runEnrichment(forceRefresh: Bool) async {
    let generationID = await generation.next()
    let snapshot = await baseStream.currentSnapshot()
    let loadingItems = await enricher.immediateItems(
        for: snapshot.items,
        forceRefresh: forceRefresh
    )
    guard await generation.isCurrent(generationID) else {
        return
    }

    await baseStream.replaceItems(loadingItems, incrementRevision: false)

    let enrichedItems = await enricher.enrichedItems(
        for: snapshot.items,
        forceRefresh: forceRefresh
    )
    guard await generation.isCurrent(generationID) else {
        return
    }

    if enrichedItems != loadingItems {
        await baseStream.replaceItems(enrichedItems, incrementRevision: true)
    }
}
```

Ensure `WebexSpaceEnrichmentCoordinator` wraps every caught error with:

```swift
WebexStreamErrorRedactor.webexStreamError(from: error)
```

- [ ] **Step 6: Run the coverage tests again**

Run:

```bash
swift test --filter WebexAPIStreamAdapterTests/testSpacesListReturnsEmptyEnrichmentWithoutFollowUpCalls
swift test --filter WebexAPIStreamAdapterTests/testSpacesGetReturnsEmptyEnrichmentWithoutFollowUpCalls
swift test --filter WebexAPIStreamAdapterTests/testSpacesStreamEnrichmentFailureStaysOnItemAndDoesNotSetSnapshotLastError
swift test --filter SpacesStreamTests/testStaleEnrichmentResultDoesNotOverwriteNewerSnapshot
```

Expected: all four tests pass.

- [ ] **Step 7: Commit coverage fixes**

Run:

```bash
git add Sources/WebexSwiftSDK/Streams/SpacesStream.swift Sources/WebexSwiftSDK/Streams/WebexSpaceEnrichmentCoordinator.swift Tests/WebexSwiftSDKTests/WebexAPIStreamAdapterTests.swift Tests/WebexSwiftSDKTests/SpacesStreamTests.swift
git commit -m "test: cover space enrichment edge cases"
```

Expected: commit succeeds.

### Task 6: Final Verification

**Files:**
- No planned source files.

- [ ] **Step 1: Run full root test suite**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 2: Run diff hygiene check**

Run:

```bash
git diff --check
```

Expected: no whitespace errors.

- [ ] **Step 3: Inspect final status**

Run:

```bash
git status --short --branch
```

Expected: branch is `agent/enriched-snapshots`; only expected untracked local build/cache files such as `.swiftpm/` may remain.

- [ ] **Step 4: Summarize implementation**

Report:

- Teams API files and tests added.
- `WebexSpace.enriched` behavior for direct REST calls.
- Spaces stream enrichment behavior and `refreshEnrichment()`.
- Test commands and results.
