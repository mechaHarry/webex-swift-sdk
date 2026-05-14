# Teams Snapshot Smoke Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `TeamsAPI.stream(...)` and a native macOS smoke app that displays all parsed `WebexTeam` snapshot fields, including live `additionalFields`.

**Architecture:** Extend the existing generic `WebexSnapshotStream` pattern to Teams with no enrichment layer. Build a SwiftUI example that mirrors the existing native smoke app structure: configuration, bootstrap/runtime, observable window model, row/detail display models, and views. Keep all REST access inside SDK stream/runtime boundaries so UI code consumes snapshots only.

**Tech Stack:** Swift 5.9, SwiftPM, XCTest, SwiftUI/AppKit on macOS, existing `WebexTransport`, `WebexSnapshotStream`, `WebexClientRegistry`, and OAuth loopback helpers.

---

## File Structure

- Modify `Sources/WebexSwiftSDK/Streams/WebexAPIStreams.swift`: add `TeamsStream` and `TeamsAPI.stream`.
- Modify `Tests/WebexSwiftSDKTests/TeamsAPITests.swift`: add Teams stream tests.
- Create `Examples/WebexTeamsSnapshotSmoke/Package.swift`: standalone smoke package.
- Create `Examples/WebexTeamsSnapshotSmoke/source.sample.sh`: minimal environment sample.
- Create `Examples/WebexTeamsSnapshotSmoke/README.md`: run instructions and what the smoke proves.
- Create `Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/App/WebexTeamsSnapshotSmokeApp.swift`: native app entry.
- Create `Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/Models/TeamsSnapshotSmokeConfiguration.swift`: environment parsing.
- Create `Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/Models/TeamSnapshotRowModel.swift`: compact row view model.
- Create `Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/Models/TeamSnapshotDetailModel.swift`: parsed field and additional-field display model.
- Create `Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/Services/TeamsSnapshotBootstrap.swift`: auth/client/stream bootstrap.
- Create `Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/Services/TeamsSnapshotRuntime.swift`: testable stream command wrapper.
- Create `Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/Stores/TeamsSnapshotWindowModel.swift`: snapshot subscription and UI state.
- Create `Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/Views/TeamsSnapshotContentView.swift`: main two-pane UI.
- Create `Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/Views/TeamSnapshotDetailView.swift`: selected-team field UI.
- Create `Examples/WebexTeamsSnapshotSmoke/Tests/WebexTeamsSnapshotSmokeTests/TeamsSnapshotSmokeConfigurationTests.swift`: config tests.
- Create `Examples/WebexTeamsSnapshotSmoke/Tests/WebexTeamsSnapshotSmokeTests/TeamSnapshotViewModelTests.swift`: row/detail tests.
- Create `Examples/WebexTeamsSnapshotSmoke/Tests/WebexTeamsSnapshotSmokeTests/TeamsSnapshotWindowModelTests.swift`: window model tests.
- Modify `README.md`: add the new smoke app to the examples list.

---

### Task 1: Teams Snapshot Stream API

**Files:**
- Modify: `Sources/WebexSwiftSDK/Streams/WebexAPIStreams.swift`
- Modify: `Tests/WebexSwiftSDKTests/TeamsAPITests.swift`

- [ ] **Step 1: Add failing Teams stream tests**

Append these tests to `Tests/WebexSwiftSDKTests/TeamsAPITests.swift` before the private helpers:

```swift
    func testTeamsStreamRefreshLoadsFirstPageAndPreservesAdditionalFields() async throws {
        let httpClient = MockTeamsHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            headers: [
                "Link": #"<https://webexapis.com/v1/teams?cursor=next>; rel="next""#
            ],
            body: """
            {
              "items": [
                {
                  "id": "team-1",
                  "name": "Platform",
                  "creatorId": "creator-1",
                  "created": "2026-05-14T10:11:12.123Z",
                  "color": "blue"
                }
              ]
            }
            """
        ))
        let api = makeAPI(httpClient: httpClient)
        let stream = api.stream(params: ListTeamsParams(max: 1), pageLimit: 2)
        var iterator = stream.snapshots.makeAsyncIterator()

        _ = try await nextTeamSnapshot(from: &iterator)
        await stream.refresh()
        _ = try await nextTeamSnapshot(from: &iterator) { $0.isRefreshing }
        let loaded = try await nextTeamSnapshot(from: &iterator) { !$0.isRefreshing && $0.revision == 1 }

        XCTAssertEqual(loaded.items.map(\.id), ["team-1"])
        XCTAssertEqual(loaded.items.first?.name, "Platform")
        XCTAssertEqual(loaded.items.first?.additionalFields["color"], .string("blue"))
        XCTAssertEqual(loaded.pagination.hasMore, true)
        XCTAssertEqual(loaded.pagination.pageLimit, 2)
        let request = try XCTUnwrap(await httpClient.recordedRequests().first)
        XCTAssertEqual(request.url?.absoluteString, "https://webexapis.com/v1/teams?max=1")
    }

    func testTeamsStreamLoadNextPageAppendsUniqueTeamsByID() async throws {
        let httpClient = MockTeamsHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            headers: [
                "Link": #"<https://webexapis.com/v1/teams?cursor=next>; rel="next""#
            ],
            body: #"{"items":[{"id":"team-1","name":"Original"}]}"#
        ))
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            body: #"{"items":[{"id":"team-1","name":"Updated"},{"id":"team-2","name":"Second"}]}"#
        ))
        let api = makeAPI(httpClient: httpClient)
        let stream = api.stream(params: ListTeamsParams(max: 1), pageLimit: 2)
        var iterator = stream.snapshots.makeAsyncIterator()

        _ = try await nextTeamSnapshot(from: &iterator)
        await stream.refresh()
        _ = try await nextTeamSnapshot(from: &iterator) { $0.isRefreshing }
        _ = try await nextTeamSnapshot(from: &iterator) { !$0.isRefreshing && $0.revision == 1 }
        await stream.loadNextPage()
        _ = try await nextTeamSnapshot(from: &iterator) { $0.isLoadingNextPage }
        let loaded = try await nextTeamSnapshot(from: &iterator) { !$0.isLoadingNextPage && $0.revision == 2 }

        XCTAssertEqual(loaded.items.map(\.id), ["team-1", "team-2"])
        XCTAssertEqual(loaded.items.first?.name, "Updated")
        XCTAssertEqual(loaded.pagination.hasMore, false)
        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, [
            "https://webexapis.com/v1/teams?max=1",
            "https://webexapis.com/v1/teams?cursor=next"
        ])
    }
```

Add these private helpers near the existing test helpers:

```swift
private func nextTeamSnapshot(
    from iterator: inout AsyncStream<WebexStreamSnapshot<WebexTeam>>.Iterator,
    matching predicate: (WebexStreamSnapshot<WebexTeam>) -> Bool = { _ in true }
) async throws -> WebexStreamSnapshot<WebexTeam> {
    for _ in 0..<10 {
        if let snapshot = await iterator.next(), predicate(snapshot) {
            return snapshot
        }
    }
    XCTFail("Timed out waiting for matching teams stream snapshot")
    return try XCTUnwrap(await iterator.next())
}
```

- [ ] **Step 2: Run the stream tests and verify they fail**

Run:

```bash
swift test --filter TeamsAPITests/testTeamsStream
```

Expected: compile failure because `TeamsAPI.stream` and `TeamsStream` do not exist.

- [ ] **Step 3: Implement `TeamsStream`**

Modify `Sources/WebexSwiftSDK/Streams/WebexAPIStreams.swift`:

```swift
public typealias TeamsStream = WebexSnapshotStream<WebexTeam>
```

Add this extension after the `SpacesAPI` extension and before `MessagesAPI`:

```swift
public extension TeamsAPI {
    func stream(
        params: ListTeamsParams = ListTeamsParams(),
        pageLimit: Int? = nil
    ) -> TeamsStream {
        WebexSnapshotStream(
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
    }
}
```

- [ ] **Step 4: Run Teams tests**

Run:

```bash
swift test --filter TeamsAPITests
```

Expected: all Teams tests pass.

- [ ] **Step 5: Commit Teams stream support**

Run:

```bash
git add Sources/WebexSwiftSDK/Streams/WebexAPIStreams.swift Tests/WebexSwiftSDKTests/TeamsAPITests.swift
git commit -m "feat: add teams snapshot stream"
```

Expected: commit succeeds.

---

### Task 2: Teams Smoke Package And Configuration

**Files:**
- Create: `Examples/WebexTeamsSnapshotSmoke/Package.swift`
- Create: `Examples/WebexTeamsSnapshotSmoke/source.sample.sh`
- Create: `Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/Models/TeamsSnapshotSmokeConfiguration.swift`
- Create: `Examples/WebexTeamsSnapshotSmoke/Tests/WebexTeamsSnapshotSmokeTests/TeamsSnapshotSmokeConfigurationTests.swift`

- [ ] **Step 1: Create package skeleton**

Create `Examples/WebexTeamsSnapshotSmoke/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "webex-teams-snapshot-smoke",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "WebexTeamsSnapshotSmoke",
            dependencies: [
                .product(name: "WebexSwiftSDK", package: "webex-swift-sdk")
            ]
        ),
        .testTarget(
            name: "WebexTeamsSnapshotSmokeTests",
            dependencies: ["WebexTeamsSnapshotSmoke"]
        )
    ]
)
```

Create `Examples/WebexTeamsSnapshotSmoke/source.sample.sh`:

```bash
#!/usr/bin/env bash

export WEBEX_CLIENT_ID="replace-me"
export WEBEX_CLIENT_SECRET="replace-me"
export WEBEX_REDIRECT_URI="http://127.0.0.1:8282/oauth/callback"
export WEBEX_SCOPES="spark:teams_read"
export WEBEX_TEAMS_PAGE_SIZE="25"
export WEBEX_TEAMS_STREAM_PAGE_LIMIT="1"
export WEBEX_KEYCHAIN_SERVICE="com.webex.swift-sdk.teams-snapshot-smoke"
```

- [ ] **Step 2: Write failing configuration tests**

Create `Examples/WebexTeamsSnapshotSmoke/Tests/WebexTeamsSnapshotSmokeTests/TeamsSnapshotSmokeConfigurationTests.swift`:

```swift
import XCTest
import WebexSwiftSDK
@testable import WebexTeamsSnapshotSmoke

final class TeamsSnapshotSmokeConfigurationTests: XCTestCase {
    func testConfigurationRequiresCredentials() {
        XCTAssertThrowsError(try TeamsSnapshotSmokeConfiguration(environment: [:])) { error in
            XCTAssertEqual(error as? TeamsSnapshotSmokeError, .missingEnvironment("WEBEX_CLIENT_ID"))
        }
    }

    func testConfigurationDefaultsToTeamsReadAndSinglePageStream() throws {
        let configuration = try TeamsSnapshotSmokeConfiguration(environment: [
            "WEBEX_CLIENT_ID": "client-id",
            "WEBEX_CLIENT_SECRET": "client-secret"
        ])

        XCTAssertEqual(configuration.integration.clientID, "client-id")
        XCTAssertEqual(configuration.integration.clientSecret, "client-secret")
        XCTAssertEqual(configuration.integration.redirectURI.absoluteString, "http://127.0.0.1:8282/oauth/callback")
        XCTAssertEqual(configuration.integration.scopes, ["spark:teams_read"])
        XCTAssertEqual(configuration.pageSize, 25)
        XCTAssertEqual(configuration.pageLimit, 1)
        XCTAssertEqual(configuration.keychainService, "com.webex.swift-sdk.teams-snapshot-smoke")
        XCTAssertEqual(configuration.listParams.max, 25)
    }

    func testConfigurationAppliesOverrides() throws {
        let configuration = try TeamsSnapshotSmokeConfiguration(environment: [
            "WEBEX_CLIENT_ID": "client-id",
            "WEBEX_CLIENT_SECRET": "client-secret",
            "WEBEX_REDIRECT_URI": "http://127.0.0.1:8282/oauth/callback",
            "WEBEX_SCOPES": "spark:teams_read,spark:teams_write",
            "WEBEX_TEAMS_PAGE_SIZE": "10",
            "WEBEX_TEAMS_STREAM_PAGE_LIMIT": "3",
            "WEBEX_KEYCHAIN_SERVICE": "custom.service"
        ])

        XCTAssertEqual(configuration.integration.scopes, ["spark:teams_read", "spark:teams_write"])
        XCTAssertEqual(configuration.pageSize, 10)
        XCTAssertEqual(configuration.pageLimit, 3)
        XCTAssertEqual(configuration.keychainService, "custom.service")
        XCTAssertEqual(configuration.listParams.max, 10)
    }

    func testInvalidEnvironmentValuesUseSafeErrors() {
        let redirectURI = "http://[::1/oauth/callback"
        XCTAssertThrowsError(try TeamsSnapshotSmokeConfiguration(environment: [
            "WEBEX_CLIENT_ID": "client-id",
            "WEBEX_CLIENT_SECRET": "client-secret",
            "WEBEX_REDIRECT_URI": redirectURI
        ])) { error in
            let description = String(describing: error)
            XCTAssertEqual(description, "Invalid WEBEX_REDIRECT_URI")
            XCTAssertFalse(description.contains(redirectURI))
        }

        XCTAssertThrowsError(try TeamsSnapshotSmokeConfiguration(environment: [
            "WEBEX_CLIENT_ID": "client-id",
            "WEBEX_CLIENT_SECRET": "client-secret",
            "WEBEX_TEAMS_PAGE_SIZE": "0"
        ])) { error in
            XCTAssertEqual(
                String(describing: error),
                "WEBEX_TEAMS_PAGE_SIZE must be an integer between 1 and 1000; received 0"
            )
        }
    }
}
```

- [ ] **Step 3: Run configuration tests and verify they fail**

Run:

```bash
cd Examples/WebexTeamsSnapshotSmoke
swift test --filter TeamsSnapshotSmokeConfigurationTests
```

Expected: compile failure because `TeamsSnapshotSmokeConfiguration` does not exist.

- [ ] **Step 4: Implement configuration**

Create `Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/Models/TeamsSnapshotSmokeConfiguration.swift`:

```swift
import Foundation
import WebexSwiftSDK

struct TeamsSnapshotSmokeConfiguration: Equatable {
    let integration: WebexIntegrationConfiguration
    let pageSize: Int
    let pageLimit: Int
    let keychainService: String
    let listParams: ListTeamsParams

    init(environment: [String: String]) throws {
        let clientID = try Self.required("WEBEX_CLIENT_ID", environment: environment)
        let clientSecret = try Self.required("WEBEX_CLIENT_SECRET", environment: environment)
        self.pageSize = try Self.integer(
            named: "WEBEX_TEAMS_PAGE_SIZE",
            defaultValue: 25,
            minimum: 1,
            maximum: 1_000,
            environment: environment
        )
        self.pageLimit = try Self.integer(
            named: "WEBEX_TEAMS_STREAM_PAGE_LIMIT",
            defaultValue: 1,
            minimum: 1,
            maximum: 1_000,
            environment: environment
        )
        self.keychainService = environment["WEBEX_KEYCHAIN_SERVICE"] ?? "com.webex.swift-sdk.teams-snapshot-smoke"

        let redirectURIString = environment["WEBEX_REDIRECT_URI"] ?? WebexOAuthLoopbackRedirectListener.defaultRedirectURI.absoluteString
        guard let redirectURI = URL(string: redirectURIString) else {
            throw TeamsSnapshotSmokeError.invalidRedirectURI
        }

        let scopes = (environment["WEBEX_SCOPES"] ?? "spark:teams_read")
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map(String.init)

        self.integration = WebexIntegrationConfiguration(
            clientID: clientID,
            clientSecret: clientSecret,
            redirectURI: redirectURI,
            scopes: scopes,
            prefersEphemeralWebBrowserSession: false
        )
        self.listParams = ListTeamsParams(max: pageSize)
    }

    private static func required(_ name: String, environment: [String: String]) throws -> String {
        guard let value = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            throw TeamsSnapshotSmokeError.missingEnvironment(name)
        }
        return value
    }

    private static func integer(
        named name: String,
        defaultValue: Int,
        minimum: Int,
        maximum: Int,
        environment: [String: String]
    ) throws -> Int {
        guard let rawValue = trimmedOptional(environment[name]) else {
            return defaultValue
        }
        guard let value = Int(rawValue), value >= minimum, value <= maximum else {
            throw TeamsSnapshotSmokeError.invalidInteger(
                name: name,
                value: rawValue,
                minimum: minimum,
                maximum: maximum
            )
        }
        return value
    }

    private static func trimmedOptional(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

enum TeamsSnapshotSmokeError: Error, Equatable, CustomStringConvertible {
    case missingEnvironment(String)
    case invalidRedirectURI
    case invalidInteger(name: String, value: String, minimum: Int, maximum: Int)
    case failedToOpenAuthorizationURL

    var description: String {
        switch self {
        case .missingEnvironment(let name):
            return "Missing required environment variable \(name)"
        case .invalidRedirectURI:
            return "Invalid WEBEX_REDIRECT_URI"
        case .invalidInteger(let name, let value, let minimum, let maximum):
            return "\(name) must be an integer between \(minimum) and \(maximum); received \(value)"
        case .failedToOpenAuthorizationURL:
            return "Failed to open the Webex authorization URL"
        }
    }
}
```

- [ ] **Step 5: Run configuration tests**

Run:

```bash
cd Examples/WebexTeamsSnapshotSmoke
swift test --filter TeamsSnapshotSmokeConfigurationTests
```

Expected: configuration tests pass.

- [ ] **Step 6: Commit package and configuration**

Run:

```bash
git add Examples/WebexTeamsSnapshotSmoke/Package.swift Examples/WebexTeamsSnapshotSmoke/source.sample.sh Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/Models/TeamsSnapshotSmokeConfiguration.swift Examples/WebexTeamsSnapshotSmoke/Tests/WebexTeamsSnapshotSmokeTests/TeamsSnapshotSmokeConfigurationTests.swift
git commit -m "feat: add teams snapshot smoke configuration"
```

Expected: commit succeeds.

---

### Task 3: Teams Smoke Row And Detail Models

**Files:**
- Create: `Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/Models/TeamSnapshotRowModel.swift`
- Create: `Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/Models/TeamSnapshotDetailModel.swift`
- Create: `Examples/WebexTeamsSnapshotSmoke/Tests/WebexTeamsSnapshotSmokeTests/TeamSnapshotViewModelTests.swift`

- [ ] **Step 1: Write failing row/detail model tests**

Create `Examples/WebexTeamsSnapshotSmoke/Tests/WebexTeamsSnapshotSmokeTests/TeamSnapshotViewModelTests.swift`:

```swift
import XCTest
import WebexSwiftSDK
@testable import WebexTeamsSnapshotSmoke

final class TeamSnapshotViewModelTests: XCTestCase {
    func testRowModelSummarizesTeam() {
        let team = WebexTeam(
            id: "team-1234567890",
            name: "Platform",
            created: Date(timeIntervalSince1970: 1_768_348_800),
            additionalFields: [
                "color": .string("blue"),
                "archived": .bool(false)
            ]
        )

        let row = TeamSnapshotRowModel(team: team)

        XCTAssertEqual(row.id, "team-1234567890")
        XCTAssertEqual(row.title, "Platform")
        XCTAssertEqual(row.shortID, "team-123...")
        XCTAssertEqual(row.createdText, "2026-01-14")
        XCTAssertEqual(row.additionalFieldsText, "2 extra fields")
    }

    func testRowModelUsesPlaceholders() {
        let row = TeamSnapshotRowModel(team: WebexTeam(id: "short", name: nil))

        XCTAssertEqual(row.title, "(unnamed team)")
        XCTAssertEqual(row.shortID, "short")
        XCTAssertEqual(row.createdText, "(nil)")
        XCTAssertEqual(row.additionalFieldsText, "0 extra fields")
    }

    func testDetailModelRendersDocumentedAndAdditionalFieldsSortedByKey() {
        let team = WebexTeam(
            id: "team-1",
            name: "Platform",
            creatorID: "creator-1",
            created: Date(timeIntervalSince1970: 1_768_348_800),
            additionalFields: [
                "nested": .object(["flag": .bool(true)]),
                "archived": .bool(false),
                "color": .string("blue")
            ]
        )

        let detail = TeamSnapshotDetailModel(team: team)

        XCTAssertEqual(detail.id, "team-1")
        XCTAssertEqual(detail.title, "Platform")
        XCTAssertEqual(detail.documentedFields.map(\.name), ["id", "name", "creatorID", "created"])
        XCTAssertEqual(detail.documentedFields.map(\.value), [
            "team-1",
            "Platform",
            "creator-1",
            "2026-01-14T00:00:00Z"
        ])
        XCTAssertEqual(detail.additionalFields.map(\.name), [
            "additionalFields.archived",
            "additionalFields.color",
            "additionalFields.nested"
        ])
        XCTAssertEqual(detail.additionalFields.map(\.value), [
            "false",
            #""blue""#,
            #"{"flag":true}"#
        ])
        XCTAssertTrue(detail.hasAdditionalFields)
    }

    func testDetailModelShowsEmptyAdditionalFieldsState() {
        let detail = TeamSnapshotDetailModel(team: WebexTeam(id: "team-1"))

        XCTAssertEqual(detail.title, "(unnamed team)")
        XCTAssertEqual(detail.additionalFields, [
            FieldDisplay(name: "additionalFields", value: "(none returned)")
        ])
        XCTAssertFalse(detail.hasAdditionalFields)
    }
}
```

- [ ] **Step 2: Run view model tests and verify they fail**

Run:

```bash
cd Examples/WebexTeamsSnapshotSmoke
swift test --filter TeamSnapshotViewModelTests
```

Expected: compile failure because row/detail models do not exist.

- [ ] **Step 3: Implement row model**

Create `Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/Models/TeamSnapshotRowModel.swift`:

```swift
import Foundation
import WebexSwiftSDK

struct TeamSnapshotRowModel: Equatable, Identifiable {
    let id: String
    let title: String
    let shortID: String
    let createdText: String
    let additionalFieldsText: String

    init(team: WebexTeam) {
        self.id = team.id
        self.title = Self.display(team.name, fallback: "(unnamed team)")
        self.shortID = team.id.count > 11 ? "\(team.id.prefix(8))..." : team.id
        self.createdText = Self.date(team.created)
        self.additionalFieldsText = "\(team.additionalFields.count) extra fields"
    }

    private static func display(_ value: String?, fallback: String) -> String {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return fallback
        }
        return trimmed
    }

    private static func date(_ date: Date?) -> String {
        guard let date else {
            return "(nil)"
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
```

- [ ] **Step 4: Implement detail model**

Create `Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/Models/TeamSnapshotDetailModel.swift`:

```swift
import Foundation
import WebexSwiftSDK

struct FieldDisplay: Equatable, Identifiable {
    let name: String
    let value: String

    var id: String {
        name
    }
}

struct TeamSnapshotDetailModel: Equatable, Identifiable {
    let id: String
    let title: String
    let documentedFields: [FieldDisplay]
    let additionalFields: [FieldDisplay]

    var hasAdditionalFields: Bool {
        !(additionalFields.count == 1 && additionalFields.first?.name == "additionalFields")
    }

    init(team: WebexTeam) {
        self.id = team.id
        self.title = Self.display(team.name, fallback: "(unnamed team)")
        self.documentedFields = [
            FieldDisplay(name: "id", value: team.id),
            FieldDisplay(name: "name", value: Self.optional(team.name)),
            FieldDisplay(name: "creatorID", value: Self.optional(team.creatorID)),
            FieldDisplay(name: "created", value: Self.iso8601(team.created))
        ]

        let extraFields = team.additionalFields
            .sorted { $0.key < $1.key }
            .map { key, value in
                FieldDisplay(name: "additionalFields.\(key)", value: Self.jsonText(value))
            }
        self.additionalFields = extraFields.isEmpty
            ? [FieldDisplay(name: "additionalFields", value: "(none returned)")]
            : extraFields
    }

    private static func display(_ value: String?, fallback: String) -> String {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return fallback
        }
        return trimmed
    }

    private static func optional(_ value: String?) -> String {
        display(value, fallback: "(nil)")
    }

    private static func iso8601(_ date: Date?) -> String {
        guard let date else {
            return "(nil)"
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func jsonText(_ value: WebexJSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return String(describing: value)
        }
        return text
    }
}
```

- [ ] **Step 5: Run view model tests**

Run:

```bash
cd Examples/WebexTeamsSnapshotSmoke
swift test --filter TeamSnapshotViewModelTests
```

Expected: row/detail tests pass.

- [ ] **Step 6: Commit row/detail models**

Run:

```bash
git add Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/Models/TeamSnapshotRowModel.swift Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/Models/TeamSnapshotDetailModel.swift Examples/WebexTeamsSnapshotSmoke/Tests/WebexTeamsSnapshotSmokeTests/TeamSnapshotViewModelTests.swift
git commit -m "feat: display teams snapshot fields"
```

Expected: commit succeeds.

---

### Task 4: Teams Smoke Runtime And Window Model

**Files:**
- Create: `Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/Services/TeamsSnapshotRuntime.swift`
- Create: `Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/Stores/TeamsSnapshotWindowModel.swift`
- Create: `Examples/WebexTeamsSnapshotSmoke/Tests/WebexTeamsSnapshotSmokeTests/TeamsSnapshotWindowModelTests.swift`

- [ ] **Step 1: Write failing window model tests**

Create `Examples/WebexTeamsSnapshotSmoke/Tests/WebexTeamsSnapshotSmokeTests/TeamsSnapshotWindowModelTests.swift`:

```swift
import XCTest
import WebexSwiftSDK
@testable import WebexTeamsSnapshotSmoke

@MainActor
final class TeamsSnapshotWindowModelTests: XCTestCase {
    func testStartSubscribesRefreshesAndMapsSnapshot() async throws {
        let harness = TeamsRuntimeHarness()
        let model = TeamsSnapshotWindowModel(runtimeFactory: { harness.runtime })

        await model.start()
        await harness.send(WebexStreamSnapshot(
            items: [
                WebexTeam(id: "team-1", name: "Platform", additionalFields: ["color": .string("blue")])
            ],
            revision: 1,
            lastUpdatedAt: Date(timeIntervalSince1970: 1_768_305_600),
            isRefreshing: false,
            isLoadingNextPage: false,
            lastError: nil,
            pagination: WebexStreamPagination(
                hasMore: true,
                nextPage: nil,
                pagesLoaded: 1,
                pageLimit: 2,
                capReached: false
            )
        ))

        XCTAssertEqual(harness.refreshCount, 1)
        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.rows.map(\.id), ["team-1"])
        XCTAssertEqual(model.selectedTeamID, "team-1")
        XCTAssertEqual(model.selectedDetail?.additionalFields.first?.name, "additionalFields.color")
        XCTAssertEqual(model.revision, 1)
        XCTAssertEqual(model.hasMore, true)
        XCTAssertEqual(model.capReached, false)
        XCTAssertNil(model.lastErrorText)
    }

    func testSelectionIsPreservedWhenTeamStillExists() async throws {
        let harness = TeamsRuntimeHarness()
        let model = TeamsSnapshotWindowModel(runtimeFactory: { harness.runtime })
        await model.start()
        await harness.send(snapshot(ids: ["team-1", "team-2"]))
        model.select(teamID: "team-2")

        await harness.send(snapshot(ids: ["team-2", "team-3"]))

        XCTAssertEqual(model.selectedTeamID, "team-2")
        XCTAssertEqual(model.selectedDetail?.id, "team-2")
    }

    func testCommandsForwardToRuntimeAndRespectLoadMoreState() async throws {
        let harness = TeamsRuntimeHarness()
        let model = TeamsSnapshotWindowModel(runtimeFactory: { harness.runtime })
        await model.start()
        await harness.send(snapshot(ids: ["team-1"], hasMore: true, capReached: false))

        await model.refresh()
        await model.loadNextPage()

        XCTAssertEqual(harness.refreshCount, 2)
        XCTAssertEqual(harness.loadNextPageCount, 1)
    }

    func testStartFailureUsesSafeErrorText() async {
        let model = TeamsSnapshotWindowModel(runtimeFactory: {
            throw WebexSDKError.invalidAuthorizationCallback("code=secret")
        })

        await model.start()

        XCTAssertEqual(model.phase, .failed("Invalid authorization callback"))
    }
}

private final class TeamsRuntimeHarness: @unchecked Sendable {
    private let continuation: AsyncStream<WebexStreamSnapshot<WebexTeam>>.Continuation
    let runtime: TeamsSnapshotRuntime
    private(set) var refreshCount = 0
    private(set) var loadNextPageCount = 0

    init() {
        var capturedContinuation: AsyncStream<WebexStreamSnapshot<WebexTeam>>.Continuation!
        let stream = AsyncStream<WebexStreamSnapshot<WebexTeam>> { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation
        self.runtime = TeamsSnapshotRuntime(
            snapshots: stream,
            currentSnapshot: {
                WebexStreamSnapshot(
                    items: [],
                    revision: 0,
                    lastUpdatedAt: nil,
                    isRefreshing: false,
                    isLoadingNextPage: false,
                    lastError: nil,
                    pagination: WebexStreamPagination(
                        hasMore: false,
                        nextPage: nil,
                        pagesLoaded: 0,
                        pageLimit: nil,
                        capReached: false
                    )
                )
            },
            refresh: {},
            loadNextPage: {}
        )
        self.runtime.refresh = { [weak self] in
            self?.refreshCount += 1
        }
        self.runtime.loadNextPage = { [weak self] in
            self?.loadNextPageCount += 1
        }
    }

    func send(_ snapshot: WebexStreamSnapshot<WebexTeam>) async {
        continuation.yield(snapshot)
        await Task.yield()
    }

    func send(snapshot ids: [String], hasMore: Bool = false, capReached: Bool = false) async {
        await send(WebexStreamSnapshot(
            items: ids.map { WebexTeam(id: $0, name: $0) },
            revision: UInt64(ids.count),
            lastUpdatedAt: nil,
            isRefreshing: false,
            isLoadingNextPage: false,
            lastError: nil,
            pagination: WebexStreamPagination(
                hasMore: hasMore,
                nextPage: nil,
                pagesLoaded: capReached ? 2 : 1,
                pageLimit: 2,
                capReached: capReached
            )
        ))
    }
}
```

- [ ] **Step 2: Run window model tests and verify they fail**

Run:

```bash
cd Examples/WebexTeamsSnapshotSmoke
swift test --filter TeamsSnapshotWindowModelTests
```

Expected: compile failure because runtime and window model do not exist.

- [ ] **Step 3: Implement runtime**

Create `Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/Services/TeamsSnapshotRuntime.swift`:

```swift
import Foundation
import WebexSwiftSDK

final class TeamsSnapshotRuntime: @unchecked Sendable {
    let snapshots: AsyncStream<WebexStreamSnapshot<WebexTeam>>
    let currentSnapshot: @Sendable () async -> WebexStreamSnapshot<WebexTeam>
    var refresh: @Sendable () async -> Void
    var loadNextPage: @Sendable () async -> Void

    private let lock = NSLock()
    private var cancelHandler: (@Sendable () -> Void)?

    init(stream: TeamsStream, cancel: @escaping @Sendable () -> Void = {}) {
        self.snapshots = stream.snapshots
        self.currentSnapshot = {
            await stream.currentSnapshot()
        }
        self.refresh = {
            await stream.refresh()
        }
        self.loadNextPage = {
            await stream.loadNextPage()
        }
        self.cancelHandler = cancel
    }

    init(
        snapshots: AsyncStream<WebexStreamSnapshot<WebexTeam>>,
        currentSnapshot: @escaping @Sendable () async -> WebexStreamSnapshot<WebexTeam>,
        refresh: @escaping @Sendable () async -> Void,
        loadNextPage: @escaping @Sendable () async -> Void,
        cancel: @escaping @Sendable () -> Void = {}
    ) {
        self.snapshots = snapshots
        self.currentSnapshot = currentSnapshot
        self.refresh = refresh
        self.loadNextPage = loadNextPage
        self.cancelHandler = cancel
    }

    deinit {
        cancel()
    }

    func cancel() {
        let handler = lock.withLock {
            let handler = cancelHandler
            cancelHandler = nil
            return handler
        }
        handler?()
    }
}
```

- [ ] **Step 4: Implement window model**

Create `Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/Stores/TeamsSnapshotWindowModel.swift`:

```swift
import Combine
import Foundation
import WebexSwiftSDK

@MainActor
final class TeamsSnapshotWindowModel: ObservableObject {
    typealias RuntimeFactory = @Sendable () async throws -> TeamsSnapshotRuntime

    @Published private(set) var rows: [TeamSnapshotRowModel] = []
    @Published private(set) var selectedDetail: TeamSnapshotDetailModel?
    @Published private(set) var selectedTeamID: String?
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var revision: UInt64 = 0
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingNextPage = false
    @Published private(set) var hasMore = false
    @Published private(set) var capReached = false
    @Published private(set) var lastUpdatedText = "Never"
    @Published private(set) var lastErrorText: String?

    private let runtimeFactory: RuntimeFactory
    private var runtime: TeamsSnapshotRuntime?
    private var subscriptionTask: Task<Void, Never>?
    private var currentTeams: [WebexTeam] = []
    private var isStarting = false

    init(runtimeFactory: @escaping RuntimeFactory) {
        self.runtimeFactory = runtimeFactory
    }

    deinit {
        subscriptionTask?.cancel()
        runtime?.cancel()
    }

    var canRefresh: Bool {
        runtime != nil && !isRefreshing
    }

    var canLoadMore: Bool {
        runtime != nil && hasMore && !capReached && !isLoadingNextPage
    }

    func start() async {
        guard runtime == nil, !isStarting else {
            return
        }
        isStarting = true
        defer { isStarting = false }

        phase = .authorizing
        do {
            let runtime = try await runtimeFactory()
            self.runtime = runtime
            subscribe(to: runtime.snapshots)
            phase = .ready
            await runtime.refresh()
        } catch {
            phase = .failed(Self.safeDescription(for: error))
        }
    }

    func refresh() async {
        await runtime?.refresh()
    }

    func loadNextPage() async {
        guard canLoadMore else {
            return
        }
        await runtime?.loadNextPage()
    }

    func select(teamID: String?) {
        selectedTeamID = teamID
        updateSelectedDetail()
    }

    private func subscribe(to snapshots: AsyncStream<WebexStreamSnapshot<WebexTeam>>) {
        subscriptionTask?.cancel()
        subscriptionTask = Task { [weak self] in
            for await snapshot in snapshots {
                self?.apply(snapshot)
            }
        }
    }

    private func apply(_ snapshot: WebexStreamSnapshot<WebexTeam>) {
        currentTeams = snapshot.items
        rows = snapshot.items.map(TeamSnapshotRowModel.init)
        revision = snapshot.revision
        isRefreshing = snapshot.isRefreshing
        isLoadingNextPage = snapshot.isLoadingNextPage
        hasMore = snapshot.pagination.hasMore
        capReached = snapshot.pagination.capReached
        lastUpdatedText = Self.lastUpdatedText(from: snapshot.lastUpdatedAt)
        lastErrorText = snapshot.lastError.map(Self.safeDescription)

        if let selectedTeamID,
           snapshot.items.contains(where: { $0.id == selectedTeamID }) {
            self.selectedTeamID = selectedTeamID
        } else {
            selectedTeamID = snapshot.items.first?.id
        }
        updateSelectedDetail()
    }

    private func updateSelectedDetail() {
        guard let selectedTeamID,
              let selected = currentTeams.first(where: { $0.id == selectedTeamID }) else {
            selectedDetail = nil
            return
        }
        selectedDetail = TeamSnapshotDetailModel(team: selected)
    }

    private static func lastUpdatedText(from date: Date?) -> String {
        guard let date else {
            return "Never"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private static func safeDescription(for error: Error) -> String {
        if case WebexSDKError.invalidAuthorizationCallback = error {
            return "Invalid authorization callback"
        }
        return String(describing: error)
    }

    enum Phase: Equatable {
        case idle
        case authorizing
        case ready
        case failed(String)
    }
}
```

- [ ] **Step 5: Run window model tests**

Run:

```bash
cd Examples/WebexTeamsSnapshotSmoke
swift test --filter TeamsSnapshotWindowModelTests
```

Expected: window model tests pass.

- [ ] **Step 6: Commit runtime/window model**

Run:

```bash
git add Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/Services/TeamsSnapshotRuntime.swift Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/Stores/TeamsSnapshotWindowModel.swift Examples/WebexTeamsSnapshotSmoke/Tests/WebexTeamsSnapshotSmokeTests/TeamsSnapshotWindowModelTests.swift
git commit -m "feat: manage teams snapshot smoke state"
```

Expected: commit succeeds.

---

### Task 5: Teams Smoke App, Bootstrap, Views, And Docs

**Files:**
- Create: `Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/App/WebexTeamsSnapshotSmokeApp.swift`
- Create: `Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/Services/TeamsSnapshotBootstrap.swift`
- Create: `Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/Views/TeamsSnapshotContentView.swift`
- Create: `Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/Views/TeamSnapshotDetailView.swift`
- Create: `Examples/WebexTeamsSnapshotSmoke/README.md`
- Modify: `README.md`

- [ ] **Step 1: Implement bootstrap**

Create `Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/Services/TeamsSnapshotBootstrap.swift`:

```swift
import AppKit
import Foundation
import WebexSwiftSDK

enum TeamsSnapshotBootstrap {
    static func makeRuntime(configuration: TeamsSnapshotSmokeConfiguration) async throws -> TeamsSnapshotRuntime {
        let httpClient = URLSessionHTTPClient()
        let store = KeychainWebexStore(service: configuration.keychainService)
        let registry = WebexClientRegistry(store: store, httpClient: httpClient)
        let authorized = try await registry.authorizeAndAddAccount(
            configuration: configuration.integration,
            openAuthorizationURL: { authorizationURL in
                guard NSWorkspace.shared.open(authorizationURL) else {
                    throw TeamsSnapshotSmokeError.failedToOpenAuthorizationURL
                }
            }
        )

        let stream = authorized.client.teams.stream(
            params: configuration.listParams,
            pageLimit: configuration.pageLimit
        )
        return TeamsSnapshotRuntime(stream: stream)
    }
}
```

- [ ] **Step 2: Implement app entry**

Create `Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/App/WebexTeamsSnapshotSmokeApp.swift`:

```swift
import SwiftUI
import WebexSwiftSDK

@main
struct WebexTeamsSnapshotSmokeApp: App {
    @StateObject private var model: TeamsSnapshotWindowModel

    init() {
        do {
            let configuration = try TeamsSnapshotSmokeConfiguration(environment: ProcessInfo.processInfo.environment)
            _model = StateObject(wrappedValue: TeamsSnapshotWindowModel(
                runtimeFactory: {
                    try await TeamsSnapshotBootstrap.makeRuntime(configuration: configuration)
                }
            ))
        } catch {
            let startupFailure = String(describing: error)
            _model = StateObject(wrappedValue: TeamsSnapshotWindowModel(
                runtimeFactory: {
                    throw WebexSDKError.network(startupFailure)
                }
            ))
        }
    }

    var body: some Scene {
        WindowGroup("Webex Teams Snapshot Smoke") {
            TeamsSnapshotContentView(model: model)
                .frame(minWidth: 920, minHeight: 560)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh Teams") {
                    Task {
                        await model.refresh()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!model.canRefresh)

                Button("Load More") {
                    Task {
                        await model.loadNextPage()
                    }
                }
                .keyboardShortcut("l", modifiers: [.command])
                .disabled(!model.canLoadMore)
            }
        }
    }
}
```

- [ ] **Step 3: Implement detail view**

Create `Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/Views/TeamSnapshotDetailView.swift`:

```swift
import SwiftUI

struct TeamSnapshotDetailView: View {
    let detail: TeamSnapshotDetailModel?

    var body: some View {
        Group {
            if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(detail.title)
                            .font(.title2)
                            .fontWeight(.semibold)
                        fieldsSection("Parsed WebexTeam fields", fields: detail.documentedFields)
                        fieldsSection("additionalFields", fields: detail.additionalFields)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "person.3.sequence")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No Team Selected")
                        .font(.headline)
                    Text("Refresh Teams to load a snapshot.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func fieldsSection(_ title: String, fields: [FieldDisplay]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                ForEach(fields) { field in
                    GridRow {
                        Text(field.name)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Text(field.value)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 4: Implement content view**

Create `Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/Views/TeamsSnapshotContentView.swift`:

```swift
import SwiftUI

struct TeamsSnapshotContentView: View {
    @ObservedObject var model: TeamsSnapshotWindowModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .task {
            await model.start()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle, .authorizing:
            ProgressView("Opening Webex")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            if model.rows.isEmpty, model.isRefreshing {
                ProgressView("Loading teams")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.rows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.3.sequence")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No Teams")
                        .font(.headline)
                    Text("Refresh Teams to load a snapshot.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NavigationSplitView {
                    List(model.rows, selection: selectionBinding) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.title)
                                .font(.headline)
                                .lineLimit(1)
                            HStack {
                                Label(row.shortID, systemImage: "number")
                                Label(row.createdText, systemImage: "calendar")
                                Label(row.additionalFieldsText, systemImage: "curlybraces")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .navigationTitle("Teams")
                } detail: {
                    TeamSnapshotDetailView(detail: model.selectedDetail)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Teams Snapshot")
                    .font(.title2)
                    .fontWeight(.semibold)
                statusBar
            }
            Spacer()
            Button {
                Task { await model.refresh() }
            } label: {
                Label("Refresh Teams", systemImage: "arrow.clockwise")
            }
            .disabled(!model.canRefresh)

            Button {
                Task { await model.loadNextPage() }
            } label: {
                Label("Load More", systemImage: "arrow.down.circle")
            }
            .disabled(!model.canLoadMore)
        }
        .padding()
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { model.selectedTeamID },
            set: { model.select(teamID: $0) }
        )
    }

    private var statusBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text("Revision \(model.revision)")
                Text("Updated \(model.lastUpdatedText)")
                if model.isRefreshing {
                    Label("Refreshing", systemImage: "arrow.triangle.2.circlepath")
                }
                if model.isLoadingNextPage {
                    Label("Loading page", systemImage: "ellipsis")
                }
                Text(model.hasMore ? "More pages" : "End")
                if model.capReached {
                    Text("Page cap reached")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let lastErrorText = model.lastErrorText {
                Text(lastErrorText)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

- [ ] **Step 5: Add example README**

Create `Examples/WebexTeamsSnapshotSmoke/README.md`:

```markdown
# WebexTeamsSnapshotSmoke

Native macOS SwiftUI smoke app for viewing Webex Teams through a `TeamsStream`
snapshot.

The window subscribes to `stream.snapshots` and displays each selected
`WebexTeam` as:

- parsed documented fields from `/v1/teams`
- returned-but-undocumented fields preserved in `additionalFields`

If `additionalFields` is empty, Webex did not return extra team keys for that
tenant/page. The SDK did not drop them.

## Required Webex Integration Settings

Configure the Webex integration redirect URI as:

```text
http://127.0.0.1:8282/oauth/callback
```

The default REST scope is:

```text
spark:teams_read
```

## Run

```bash
cd Examples/WebexTeamsSnapshotSmoke
cp source.sample.sh source.sh
# Edit source.sh with your Webex integration credentials.
source ./source.sh
swift run WebexTeamsSnapshotSmoke
```

Optional environment variables:

- `WEBEX_REDIRECT_URI`: defaults to `http://127.0.0.1:8282/oauth/callback`
- `WEBEX_SCOPES`: defaults to `spark:teams_read`
- `WEBEX_TEAMS_PAGE_SIZE`: defaults to `25`
- `WEBEX_TEAMS_STREAM_PAGE_LIMIT`: defaults to `1`
- `WEBEX_KEYCHAIN_SERVICE`: defaults to `com.webex.swift-sdk.teams-snapshot-smoke`

The app opens Webex authorization in the default browser on first launch. Once
the SDK stores the refresh token in Keychain, future launches can refresh access
tokens through the SDK token lifecycle.

## Snapshot Controls

- `Refresh Teams` calls `TeamsStream.refresh()`.
- `Load More` calls `TeamsStream.loadNextPage()` when pagination allows.

This smoke intentionally does not create a realtime WebSocket connection. A
production app can still connect realtime triggers to snapshot refresh APIs.
```

- [ ] **Step 6: Update root README examples list**

Modify the examples list in `README.md` by adding:

```markdown
- `Examples/WebexTeamsSnapshotSmoke`: native SwiftUI smoke window that displays `TeamsStream` snapshots and surfaces returned `WebexTeam.additionalFields` visually.
```

- [ ] **Step 7: Run example tests and build**

Run:

```bash
cd Examples/WebexTeamsSnapshotSmoke
swift test
swift build
```

Expected: tests and build pass.

- [ ] **Step 8: Commit app and docs**

Run:

```bash
git add Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/App/WebexTeamsSnapshotSmokeApp.swift Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/Services/TeamsSnapshotBootstrap.swift Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/Views/TeamsSnapshotContentView.swift Examples/WebexTeamsSnapshotSmoke/Sources/WebexTeamsSnapshotSmoke/Views/TeamSnapshotDetailView.swift Examples/WebexTeamsSnapshotSmoke/README.md README.md
git commit -m "feat: add teams snapshot smoke app"
```

Expected: commit succeeds.

---

### Task 6: Final Verification

**Files:**
- No code changes expected.

- [ ] **Step 1: Run root tests**

Run:

```bash
swift test
```

Expected: all tests pass. Existing skipped keychain integration tests are acceptable if they match baseline behavior.

- [ ] **Step 2: Run example tests**

Run:

```bash
cd Examples/WebexTeamsSnapshotSmoke
swift test
```

Expected: all Teams snapshot smoke tests pass.

- [ ] **Step 3: Build the example**

Run:

```bash
cd Examples/WebexTeamsSnapshotSmoke
swift build
```

Expected: the `WebexTeamsSnapshotSmoke` executable builds.

- [ ] **Step 4: Check whitespace**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 5: Inspect status**

Run:

```bash
git status --short --branch
```

Expected: clean `teams-api` branch.

- [ ] **Step 6: Review recent commits**

Run:

```bash
git log --oneline --decorate -12
```

Expected: recent commits include:

- `docs: design teams snapshot smoke`
- `feat: add teams snapshot stream`
- `feat: add teams snapshot smoke configuration`
- `feat: display teams snapshot fields`
- `feat: manage teams snapshot smoke state`
- `feat: add teams snapshot smoke app`
