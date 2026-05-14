# Enriched Spaces Snapshot Smoke Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS smoke app that visually compares wire-faithful `WebexSpace` fields with SDK-derived `WebexSpace.enriched` fields from `SpacesStream` snapshots.

**Architecture:** Add a new SwiftPM example package under `Examples/WebexSpacesEnrichedSnapshotSmoke`. Follow the existing message stream window smoke pattern: configuration and bootstrap create a `SpacesStream`, a main-actor window model subscribes to snapshots and maps them into row/detail view models, and SwiftUI renders a two-pane native window with refresh, enrichment refresh, and pagination controls.

**Tech Stack:** Swift 5.9, SwiftPM, SwiftUI/AppKit on macOS 13+, XCTest, `WebexSwiftSDK`, `SpacesStream`, `WebexStreamSnapshot<WebexSpace>`.

---

### Task 1: Example Package And Configuration

**Files:**
- Create: `Examples/WebexSpacesEnrichedSnapshotSmoke/Package.swift`
- Create: `Examples/WebexSpacesEnrichedSnapshotSmoke/Sources/WebexSpacesEnrichedSnapshotSmoke/Models/EnrichedSpacesSmokeConfiguration.swift`
- Create: `Examples/WebexSpacesEnrichedSnapshotSmoke/Tests/WebexSpacesEnrichedSnapshotSmokeTests/EnrichedSpacesSmokeConfigurationTests.swift`

- [ ] **Step 1: Create the example package manifest**

Create `Examples/WebexSpacesEnrichedSnapshotSmoke/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "webex-spaces-enriched-snapshot-smoke",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "WebexSpacesEnrichedSnapshotSmoke",
            dependencies: [
                .product(name: "WebexSwiftSDK", package: "webex-swift-sdk")
            ]
        ),
        .testTarget(
            name: "WebexSpacesEnrichedSnapshotSmokeTests",
            dependencies: ["WebexSpacesEnrichedSnapshotSmoke"]
        )
    ]
)
```

- [ ] **Step 2: Write failing configuration tests**

Create `Examples/WebexSpacesEnrichedSnapshotSmoke/Tests/WebexSpacesEnrichedSnapshotSmokeTests/EnrichedSpacesSmokeConfigurationTests.swift`:

```swift
import XCTest
import WebexSwiftSDK
@testable import WebexSpacesEnrichedSnapshotSmoke

final class EnrichedSpacesSmokeConfigurationTests: XCTestCase {
    func testConfigurationRequiresCredentials() {
        XCTAssertThrowsError(try EnrichedSpacesSmokeConfiguration(environment: [:])) { error in
            XCTAssertEqual(error as? EnrichedSpacesSmokeError, .missingEnvironment("WEBEX_CLIENT_ID"))
        }
    }

    func testConfigurationDefaultsToLoopbackRestScopesAndSinglePageStream() throws {
        let configuration = try EnrichedSpacesSmokeConfiguration(environment: [
            "WEBEX_CLIENT_ID": "client-id",
            "WEBEX_CLIENT_SECRET": "client-secret"
        ])

        XCTAssertEqual(configuration.integration.clientID, "client-id")
        XCTAssertEqual(configuration.integration.clientSecret, "client-secret")
        XCTAssertEqual(configuration.integration.redirectURI.absoluteString, "http://127.0.0.1:8282/oauth/callback")
        XCTAssertEqual(configuration.integration.scopes, [
            "spark:rooms_read",
            "spark:memberships_read",
            "spark:people_read"
        ])
        XCTAssertEqual(configuration.pageSize, 25)
        XCTAssertEqual(configuration.pageLimit, 1)
        XCTAssertEqual(configuration.keychainService, "com.webex.swift-sdk.spaces-enriched-snapshot-smoke")
        XCTAssertNil(configuration.listParams.teamID)
        XCTAssertNil(configuration.listParams.type)
        XCTAssertNil(configuration.listParams.sortBy)
        XCTAssertEqual(configuration.listParams.max, 25)
    }

    func testConfigurationAppliesOverrides() throws {
        let configuration = try EnrichedSpacesSmokeConfiguration(environment: [
            "WEBEX_CLIENT_ID": "client-id",
            "WEBEX_CLIENT_SECRET": "client-secret",
            "WEBEX_REDIRECT_URI": "http://127.0.0.1:8282/oauth/callback",
            "WEBEX_SCOPES": "spark:rooms_read spark:memberships_read spark:people_read spark:teams_read",
            "WEBEX_SPACES_PAGE_SIZE": "10",
            "WEBEX_SPACES_STREAM_PAGE_LIMIT": "3",
            "WEBEX_SPACES_TYPE": "direct",
            "WEBEX_SPACES_TEAM_ID": "team-id",
            "WEBEX_SPACES_SORT_BY": "lastactivity",
            "WEBEX_KEYCHAIN_SERVICE": "custom.service"
        ])

        XCTAssertEqual(configuration.integration.scopes, [
            "spark:rooms_read",
            "spark:memberships_read",
            "spark:people_read",
            "spark:teams_read"
        ])
        XCTAssertEqual(configuration.pageSize, 10)
        XCTAssertEqual(configuration.pageLimit, 3)
        XCTAssertEqual(configuration.keychainService, "custom.service")
        XCTAssertEqual(configuration.listParams.teamID, "team-id")
        XCTAssertEqual(configuration.listParams.type, .direct)
        XCTAssertEqual(configuration.listParams.sortBy, .lastActivity)
        XCTAssertEqual(configuration.listParams.max, 10)
    }

    func testInvalidEnvironmentValuesUseSafeErrors() {
        let redirectURI = "http://[::1/oauth/callback"
        XCTAssertThrowsError(try EnrichedSpacesSmokeConfiguration(environment: [
            "WEBEX_CLIENT_ID": "client-id",
            "WEBEX_CLIENT_SECRET": "client-secret",
            "WEBEX_REDIRECT_URI": redirectURI
        ])) { error in
            let description = String(describing: error)
            XCTAssertEqual(description, "Invalid WEBEX_REDIRECT_URI")
            XCTAssertFalse(description.contains(redirectURI))
        }

        XCTAssertThrowsError(try EnrichedSpacesSmokeConfiguration(environment: [
            "WEBEX_CLIENT_ID": "client-id",
            "WEBEX_CLIENT_SECRET": "client-secret",
            "WEBEX_SPACES_PAGE_SIZE": "0"
        ])) { error in
            XCTAssertEqual(
                String(describing: error),
                "WEBEX_SPACES_PAGE_SIZE must be an integer between 1 and 1000; received 0"
            )
        }

        XCTAssertThrowsError(try EnrichedSpacesSmokeConfiguration(environment: [
            "WEBEX_CLIENT_ID": "client-id",
            "WEBEX_CLIENT_SECRET": "client-secret",
            "WEBEX_SPACES_TYPE": "team"
        ])) { error in
            XCTAssertEqual(
                String(describing: error),
                "WEBEX_SPACES_TYPE must be direct or group; received team"
            )
        }

        XCTAssertThrowsError(try EnrichedSpacesSmokeConfiguration(environment: [
            "WEBEX_CLIENT_ID": "client-id",
            "WEBEX_CLIENT_SECRET": "client-secret",
            "WEBEX_SPACES_SORT_BY": "updated"
        ])) { error in
            XCTAssertEqual(
                String(describing: error),
                "WEBEX_SPACES_SORT_BY must be id, lastactivity, or created; received updated"
            )
        }
    }
}
```

- [ ] **Step 3: Run configuration tests and verify they fail**

Run:

```bash
cd Examples/WebexSpacesEnrichedSnapshotSmoke
swift test --filter EnrichedSpacesSmokeConfigurationTests
```

Expected: compile failure because `EnrichedSpacesSmokeConfiguration` and `EnrichedSpacesSmokeError` do not exist.

- [ ] **Step 4: Implement configuration and safe errors**

Create `Examples/WebexSpacesEnrichedSnapshotSmoke/Sources/WebexSpacesEnrichedSnapshotSmoke/Models/EnrichedSpacesSmokeConfiguration.swift`:

```swift
import Foundation
import WebexSwiftSDK

struct EnrichedSpacesSmokeConfiguration: Equatable {
    let integration: WebexIntegrationConfiguration
    let pageSize: Int
    let pageLimit: Int
    let keychainService: String
    let listParams: ListSpacesParams

    init(environment: [String: String]) throws {
        let clientID = try Self.required("WEBEX_CLIENT_ID", environment: environment)
        let clientSecret = try Self.required("WEBEX_CLIENT_SECRET", environment: environment)
        self.pageSize = try Self.integer(
            named: "WEBEX_SPACES_PAGE_SIZE",
            defaultValue: 25,
            minimum: 1,
            maximum: 1_000,
            environment: environment
        )
        self.pageLimit = try Self.integer(
            named: "WEBEX_SPACES_STREAM_PAGE_LIMIT",
            defaultValue: 1,
            minimum: 1,
            maximum: 1_000,
            environment: environment
        )
        self.keychainService = environment["WEBEX_KEYCHAIN_SERVICE"] ?? "com.webex.swift-sdk.spaces-enriched-snapshot-smoke"

        let redirectURIString = environment["WEBEX_REDIRECT_URI"] ?? WebexOAuthLoopbackRedirectListener.defaultRedirectURI.absoluteString
        guard let redirectURI = URL(string: redirectURIString) else {
            throw EnrichedSpacesSmokeError.invalidRedirectURI
        }

        let scopes = (environment["WEBEX_SCOPES"] ?? "spark:rooms_read spark:memberships_read spark:people_read")
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map(String.init)

        self.integration = WebexIntegrationConfiguration(
            clientID: clientID,
            clientSecret: clientSecret,
            redirectURI: redirectURI,
            scopes: scopes,
            prefersEphemeralWebBrowserSession: false
        )

        self.listParams = ListSpacesParams(
            teamID: Self.trimmedOptional(environment["WEBEX_SPACES_TEAM_ID"]),
            type: try Self.spaceType(environment["WEBEX_SPACES_TYPE"]),
            sortBy: try Self.sort(environment["WEBEX_SPACES_SORT_BY"]),
            max: pageSize
        )
    }

    private static func required(
        _ name: String,
        environment: [String: String]
    ) throws -> String {
        guard let value = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            throw EnrichedSpacesSmokeError.missingEnvironment(name)
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
        guard let value = Int(rawValue),
              value >= minimum,
              value <= maximum else {
            throw EnrichedSpacesSmokeError.invalidInteger(
                name: name,
                value: rawValue,
                minimum: minimum,
                maximum: maximum
            )
        }
        return value
    }

    private static func spaceType(_ rawValue: String?) throws -> WebexSpaceType? {
        guard let value = trimmedOptional(rawValue) else {
            return nil
        }

        switch value.lowercased() {
        case "direct":
            return .direct
        case "group":
            return .group
        default:
            throw EnrichedSpacesSmokeError.invalidSpaceType(value)
        }
    }

    private static func sort(_ rawValue: String?) throws -> WebexSpaceSort? {
        guard let value = trimmedOptional(rawValue) else {
            return nil
        }

        switch value.lowercased() {
        case "id":
            return .id
        case "lastactivity", "last_activity", "last-activity":
            return .lastActivity
        case "created":
            return .created
        default:
            throw EnrichedSpacesSmokeError.invalidSort(value)
        }
    }

    private static func trimmedOptional(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

enum EnrichedSpacesSmokeError: Error, Equatable, CustomStringConvertible {
    case missingEnvironment(String)
    case invalidRedirectURI
    case invalidInteger(name: String, value: String, minimum: Int, maximum: Int)
    case invalidSpaceType(String)
    case invalidSort(String)
    case failedToOpenAuthorizationURL

    var description: String {
        switch self {
        case .missingEnvironment(let name):
            return "Missing required environment variable \(name)"
        case .invalidRedirectURI:
            return "Invalid WEBEX_REDIRECT_URI"
        case .invalidInteger(let name, let value, let minimum, let maximum):
            return "\(name) must be an integer between \(minimum) and \(maximum); received \(value)"
        case .invalidSpaceType(let value):
            return "WEBEX_SPACES_TYPE must be direct or group; received \(value)"
        case .invalidSort(let value):
            return "WEBEX_SPACES_SORT_BY must be id, lastactivity, or created; received \(value)"
        case .failedToOpenAuthorizationURL:
            return "Failed to open the Webex authorization URL"
        }
    }
}
```

- [ ] **Step 5: Run configuration tests and verify they pass**

Run:

```bash
cd Examples/WebexSpacesEnrichedSnapshotSmoke
swift test --filter EnrichedSpacesSmokeConfigurationTests
```

Expected: all `EnrichedSpacesSmokeConfigurationTests` pass.

- [ ] **Step 6: Commit package and configuration**

Run:

```bash
git add Examples/WebexSpacesEnrichedSnapshotSmoke/Package.swift \
  Examples/WebexSpacesEnrichedSnapshotSmoke/Sources/WebexSpacesEnrichedSnapshotSmoke/Models/EnrichedSpacesSmokeConfiguration.swift \
  Examples/WebexSpacesEnrichedSnapshotSmoke/Tests/WebexSpacesEnrichedSnapshotSmokeTests/EnrichedSpacesSmokeConfigurationTests.swift
git commit -m "feat: add enriched spaces smoke config"
```

Expected: commit succeeds.

### Task 2: Row And Detail View Models

**Files:**
- Create: `Examples/WebexSpacesEnrichedSnapshotSmoke/Sources/WebexSpacesEnrichedSnapshotSmoke/Models/EnrichedSpaceRowModel.swift`
- Create: `Examples/WebexSpacesEnrichedSnapshotSmoke/Sources/WebexSpacesEnrichedSnapshotSmoke/Models/EnrichedSpaceDetailModel.swift`
- Create: `Examples/WebexSpacesEnrichedSnapshotSmoke/Tests/WebexSpacesEnrichedSnapshotSmokeTests/EnrichedSpaceViewModelTests.swift`

- [ ] **Step 1: Write failing row/detail model tests**

Create `Examples/WebexSpacesEnrichedSnapshotSmoke/Tests/WebexSpacesEnrichedSnapshotSmokeTests/EnrichedSpaceViewModelTests.swift`:

```swift
import XCTest
import WebexSwiftSDK
@testable import WebexSpacesEnrichedSnapshotSmoke

final class EnrichedSpaceViewModelTests: XCTestCase {
    func testRowModelSummarizesWireAndEnrichedFields() {
        let row = EnrichedSpaceRowModel(space: WebexSpace(
            id: "space-1",
            title: "Incident Review",
            type: .group,
            teamID: "team-1",
            enriched: WebexSpaceEnrichment(
                teamName: "Platform Team",
                status: .complete
            )
        ))

        XCTAssertEqual(row.id, "space-1")
        XCTAssertEqual(row.title, "Incident Review")
        XCTAssertEqual(row.typeText, "group")
        XCTAssertEqual(row.enrichmentStatusText, "complete")
        XCTAssertEqual(row.enrichmentSummary, "Platform Team")
        XCTAssertEqual(row.systemImageName, "rectangle.3.group")
    }

    func testRowModelUsesAvatarSummaryForDirectSpaces() {
        let row = EnrichedSpaceRowModel(space: WebexSpace(
            id: "direct-1",
            title: nil,
            type: .direct,
            enriched: WebexSpaceEnrichment(
                spaceAvatar: "https://example.com/avatar.png",
                status: .complete
            )
        ))

        XCTAssertEqual(row.title, "(untitled space)")
        XCTAssertEqual(row.typeText, "direct")
        XCTAssertEqual(row.enrichmentSummary, "Avatar available")
        XCTAssertEqual(row.systemImageName, "person.crop.circle")
    }

    func testRowModelSurfacesFailedEnrichment() {
        let row = EnrichedSpaceRowModel(space: WebexSpace(
            id: "space-1",
            title: "Team Space",
            type: .group,
            enriched: WebexSpaceEnrichment(
                status: .failed,
                errors: [
                    WebexSpaceEnrichmentError(field: .teamName, error: .network("team unavailable"))
                ]
            )
        ))

        XCTAssertEqual(row.enrichmentStatusText, "failed")
        XCTAssertEqual(row.enrichmentSummary, "1 enrichment error")
    }

    func testDetailModelSeparatesWireAndEnrichedFields() {
        let date = Date(timeIntervalSince1970: 0)
        let detail = EnrichedSpaceDetailModel(space: WebexSpace(
            id: "space-1",
            title: "Incident Review",
            type: .group,
            isLocked: false,
            teamID: "team-1",
            lastActivity: date,
            created: date,
            isReadOnly: true,
            isAnnouncementOnly: false,
            enriched: WebexSpaceEnrichment(
                teamName: "Platform Team",
                spaceAvatar: nil,
                status: .complete
            )
        ))

        XCTAssertEqual(detail.id, "space-1")
        XCTAssertEqual(detail.title, "Incident Review")
        XCTAssertEqual(detail.wireFields, [
            FieldDisplay(name: "id", value: "space-1"),
            FieldDisplay(name: "title", value: "Incident Review"),
            FieldDisplay(name: "type", value: "group"),
            FieldDisplay(name: "teamID", value: "team-1"),
            FieldDisplay(name: "isLocked", value: "false"),
            FieldDisplay(name: "isReadOnly", value: "true"),
            FieldDisplay(name: "isAnnouncementOnly", value: "false"),
            FieldDisplay(name: "lastActivity", value: "1970-01-01T00:00:00Z"),
            FieldDisplay(name: "created", value: "1970-01-01T00:00:00Z")
        ])
        XCTAssertEqual(detail.enrichedFields, [
            FieldDisplay(name: "enriched.teamName", value: "Platform Team"),
            FieldDisplay(name: "enriched.spaceAvatar", value: "(nil)"),
            FieldDisplay(name: "enriched.status", value: "complete"),
            FieldDisplay(name: "enriched.errors", value: "[]")
        ])
    }

    func testDetailModelFormatsEnrichmentErrorsSafely() {
        let detail = EnrichedSpaceDetailModel(space: WebexSpace(
            id: "space-1",
            title: "Incident Review",
            type: .group,
            enriched: WebexSpaceEnrichment(
                status: .failed,
                errors: [
                    WebexSpaceEnrichmentError(field: .teamName, error: .network("callback code=[redacted]"))
                ]
            )
        ))

        XCTAssertEqual(
            detail.enrichedFields.last,
            FieldDisplay(name: "enriched.errors", value: "teamName: Network error: callback code=[redacted]")
        )
    }
}
```

- [ ] **Step 2: Run row/detail tests and verify they fail**

Run:

```bash
cd Examples/WebexSpacesEnrichedSnapshotSmoke
swift test --filter EnrichedSpaceViewModelTests
```

Expected: compile failure for missing `EnrichedSpaceRowModel`, `EnrichedSpaceDetailModel`, and `FieldDisplay`.

- [ ] **Step 3: Implement row model**

Create `Examples/WebexSpacesEnrichedSnapshotSmoke/Sources/WebexSpacesEnrichedSnapshotSmoke/Models/EnrichedSpaceRowModel.swift`:

```swift
import Foundation
import WebexSwiftSDK

struct EnrichedSpaceRowModel: Identifiable, Equatable {
    let id: String
    let title: String
    let typeText: String
    let enrichmentStatusText: String
    let enrichmentSummary: String
    let systemImageName: String

    init(space: WebexSpace) {
        self.id = space.id
        self.title = Self.display(space.title, fallback: "(untitled space)")
        self.typeText = space.type?.rawValue ?? "(nil)"
        self.enrichmentStatusText = Self.statusText(space.enriched.status)
        self.enrichmentSummary = Self.enrichmentSummary(for: space)
        self.systemImageName = space.type == .direct ? "person.crop.circle" : "rectangle.3.group"
    }

    private static func statusText(_ status: WebexSpaceEnrichmentStatus) -> String {
        switch status {
        case .empty:
            return "empty"
        case .loading:
            return "loading"
        case .partial:
            return "partial"
        case .complete:
            return "complete"
        case .failed:
            return "failed"
        }
    }

    private static func enrichmentSummary(for space: WebexSpace) -> String {
        if !space.enriched.errors.isEmpty {
            let count = space.enriched.errors.count
            return count == 1 ? "1 enrichment error" : "\(count) enrichment errors"
        }

        if let teamName = displayOptional(space.enriched.teamName) {
            return teamName
        }

        if displayOptional(space.enriched.spaceAvatar) != nil {
            return "Avatar available"
        }

        switch space.enriched.status {
        case .empty:
            return "No enrichment"
        case .loading:
            return "Loading enrichment"
        case .complete:
            return "Enrichment complete"
        case .partial:
            return "Partial enrichment"
        case .failed:
            return "Enrichment failed"
        }
    }

    private static func display(_ value: String?, fallback: String) -> String {
        displayOptional(value) ?? fallback
    }

    private static func displayOptional(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
```

- [ ] **Step 4: Implement detail model**

Create `Examples/WebexSpacesEnrichedSnapshotSmoke/Sources/WebexSpacesEnrichedSnapshotSmoke/Models/EnrichedSpaceDetailModel.swift`:

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

struct EnrichedSpaceDetailModel: Equatable, Identifiable {
    let id: String
    let title: String
    let wireFields: [FieldDisplay]
    let enrichedFields: [FieldDisplay]

    init(space: WebexSpace) {
        self.id = space.id
        self.title = Self.display(space.title, fallback: "(untitled space)")
        self.wireFields = [
            FieldDisplay(name: "id", value: space.id),
            FieldDisplay(name: "title", value: Self.optional(space.title)),
            FieldDisplay(name: "type", value: space.type?.rawValue ?? "(nil)"),
            FieldDisplay(name: "teamID", value: Self.optional(space.teamID)),
            FieldDisplay(name: "isLocked", value: Self.optionalBool(space.isLocked)),
            FieldDisplay(name: "isReadOnly", value: Self.optionalBool(space.isReadOnly)),
            FieldDisplay(name: "isAnnouncementOnly", value: Self.optionalBool(space.isAnnouncementOnly)),
            FieldDisplay(name: "lastActivity", value: Self.iso8601(space.lastActivity)),
            FieldDisplay(name: "created", value: Self.iso8601(space.created))
        ]
        self.enrichedFields = [
            FieldDisplay(name: "enriched.teamName", value: Self.optional(space.enriched.teamName)),
            FieldDisplay(name: "enriched.spaceAvatar", value: Self.optional(space.enriched.spaceAvatar)),
            FieldDisplay(name: "enriched.status", value: Self.statusText(space.enriched.status)),
            FieldDisplay(name: "enriched.errors", value: Self.errors(space.enriched.errors))
        ]
    }

    private static func statusText(_ status: WebexSpaceEnrichmentStatus) -> String {
        switch status {
        case .empty:
            return "empty"
        case .loading:
            return "loading"
        case .partial:
            return "partial"
        case .complete:
            return "complete"
        case .failed:
            return "failed"
        }
    }

    private static func fieldText(_ field: WebexSpaceEnrichmentField) -> String {
        switch field {
        case .teamName:
            return "teamName"
        case .spaceAvatar:
            return "spaceAvatar"
        }
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

    private static func optionalBool(_ value: Bool?) -> String {
        guard let value else {
            return "(nil)"
        }
        return String(value)
    }

    private static func iso8601(_ date: Date?) -> String {
        guard let date else {
            return "(nil)"
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func errors(_ errors: [WebexSpaceEnrichmentError]) -> String {
        guard !errors.isEmpty else {
            return "[]"
        }

        return errors
            .map { "\(fieldText($0.field)): \($0.error)" }
            .joined(separator: "\n")
    }
}
```

- [ ] **Step 5: Run row/detail tests and verify they pass**

Run:

```bash
cd Examples/WebexSpacesEnrichedSnapshotSmoke
swift test --filter EnrichedSpaceViewModelTests
```

Expected: all `EnrichedSpaceViewModelTests` pass.

- [ ] **Step 6: Commit view models**

Run:

```bash
git add Examples/WebexSpacesEnrichedSnapshotSmoke/Sources/WebexSpacesEnrichedSnapshotSmoke/Models/EnrichedSpaceRowModel.swift \
  Examples/WebexSpacesEnrichedSnapshotSmoke/Sources/WebexSpacesEnrichedSnapshotSmoke/Models/EnrichedSpaceDetailModel.swift \
  Examples/WebexSpacesEnrichedSnapshotSmoke/Tests/WebexSpacesEnrichedSnapshotSmokeTests/EnrichedSpaceViewModelTests.swift
git commit -m "feat: map enriched spaces for smoke"
```

Expected: commit succeeds.

### Task 3: Runtime And Window Model

**Files:**
- Create: `Examples/WebexSpacesEnrichedSnapshotSmoke/Sources/WebexSpacesEnrichedSnapshotSmoke/Services/EnrichedSpacesRuntime.swift`
- Create: `Examples/WebexSpacesEnrichedSnapshotSmoke/Sources/WebexSpacesEnrichedSnapshotSmoke/Stores/EnrichedSpacesWindowModel.swift`
- Create: `Examples/WebexSpacesEnrichedSnapshotSmoke/Tests/WebexSpacesEnrichedSnapshotSmokeTests/EnrichedSpacesWindowModelTests.swift`

- [ ] **Step 1: Write failing window model tests**

Create `Examples/WebexSpacesEnrichedSnapshotSmoke/Tests/WebexSpacesEnrichedSnapshotSmokeTests/EnrichedSpacesWindowModelTests.swift`:

```swift
import Foundation
import XCTest
import WebexSwiftSDK
@testable import WebexSpacesEnrichedSnapshotSmoke

@MainActor
final class EnrichedSpacesWindowModelTests: XCTestCase {
    func testStartSubscribesToStreamAndPublishesSnapshotRowsAndDetail() async throws {
        let stream = SpacesStreamTestDriver()
        let model = EnrichedSpacesWindowModel(runtimeFactory: {
            EnrichedSpacesRuntime(
                snapshots: stream.snapshots,
                currentSnapshot: { await stream.currentSnapshot() },
                refresh: { await stream.refresh() },
                refreshEnrichment: { await stream.refreshEnrichment() },
                loadNextPage: { await stream.loadNextPage() }
            )
        })

        await model.start()
        stream.yield(snapshot(items: [
            WebexSpace(
                id: "space-1",
                title: "Incident Review",
                type: .group,
                teamID: "team-1",
                enriched: WebexSpaceEnrichment(teamName: "Platform Team", status: .complete)
            )
        ], revision: 1))
        await waitUntil { model.rows.count == 1 }

        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.rows.map(\.id), ["space-1"])
        XCTAssertEqual(model.rows.first?.enrichmentSummary, "Platform Team")
        XCTAssertEqual(model.selectedSpaceID, "space-1")
        XCTAssertEqual(model.selectedDetail?.title, "Incident Review")
        XCTAssertEqual(model.revision, 1)
        XCTAssertFalse(model.isRefreshing)
        XCTAssertTrue(model.canRefresh)
        XCTAssertFalse(model.canLoadMore)
    }

    func testSelectionIsPreservedWhenSnapshotStillContainsSelectedSpace() async throws {
        let stream = SpacesStreamTestDriver()
        let model = EnrichedSpacesWindowModel(runtimeFactory: {
            EnrichedSpacesRuntime(
                snapshots: stream.snapshots,
                currentSnapshot: { await stream.currentSnapshot() },
                refresh: { await stream.refresh() },
                refreshEnrichment: { await stream.refreshEnrichment() },
                loadNextPage: { await stream.loadNextPage() }
            )
        })

        await model.start()
        stream.yield(snapshot(items: [
            WebexSpace(id: "space-1", title: "One", type: .group),
            WebexSpace(id: "space-2", title: "Two", type: .direct)
        ], revision: 1))
        await waitUntil { model.rows.count == 2 }

        model.select(spaceID: "space-2")
        stream.yield(snapshot(items: [
            WebexSpace(id: "space-2", title: "Two Updated", type: .direct),
            WebexSpace(id: "space-3", title: "Three", type: .group)
        ], revision: 2))
        await waitUntil { model.selectedDetail?.title == "Two Updated" }

        XCTAssertEqual(model.selectedSpaceID, "space-2")
    }

    func testCommandsCallRuntimeActions() async {
        let runtime = RecordingEnrichedSpacesRuntime()
        let model = EnrichedSpacesWindowModel(runtimeFactory: { runtime.runtime })

        await model.start()
        await model.refresh()
        await model.refreshEnrichment()
        await model.loadNextPage()

        XCTAssertEqual(runtime.refreshCount, 2)
        XCTAssertEqual(runtime.refreshEnrichmentCount, 1)
        XCTAssertEqual(runtime.loadNextPageCount, 1)
    }

    func testStartFailurePublishesSafeError() async {
        let model = EnrichedSpacesWindowModel(runtimeFactory: {
            throw WebexSDKError.invalidAuthorizationCallback("http://127.0.0.1:8282/oauth/callback?code=secret")
        })

        await model.start()

        XCTAssertEqual(model.phase, .failed("Invalid authorization callback"))
    }
}

private func snapshot(
    items: [WebexSpace],
    revision: UInt64,
    isRefreshing: Bool = false,
    isLoadingNextPage: Bool = false,
    lastError: WebexSDKError? = nil,
    hasMore: Bool = false
) -> WebexStreamSnapshot<WebexSpace> {
    WebexStreamSnapshot(
        items: items,
        revision: revision,
        lastUpdatedAt: Date(timeIntervalSince1970: 0),
        isRefreshing: isRefreshing,
        isLoadingNextPage: isLoadingNextPage,
        lastError: lastError,
        pagination: WebexStreamPagination(
            hasMore: hasMore,
            nextPage: hasMore ? WebexPageLink(url: URL(string: "https://webexapis.com/v1/rooms?cursor=next")!) : nil,
            pagesLoaded: 1,
            pageLimit: 1,
            capReached: false
        )
    )
}

@MainActor
private func waitUntil(
    timeout: TimeInterval = 1,
    predicate: @MainActor @escaping () -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !predicate(), Date() < deadline {
        await Task.yield()
    }
}

private final class SpacesStreamTestDriver: @unchecked Sendable {
    let snapshots: AsyncStream<WebexStreamSnapshot<WebexSpace>>

    private let lock = NSLock()
    private var continuation: AsyncStream<WebexStreamSnapshot<WebexSpace>>.Continuation?
    private var current = snapshot(items: [], revision: 0)
    private(set) var refreshCount = 0
    private(set) var refreshEnrichmentCount = 0
    private(set) var loadNextPageCount = 0

    init() {
        var continuation: AsyncStream<WebexStreamSnapshot<WebexSpace>>.Continuation?
        self.snapshots = AsyncStream { streamContinuation in
            continuation = streamContinuation
            streamContinuation.yield(snapshot(items: [], revision: 0))
        }
        self.continuation = continuation
    }

    func yield(_ snapshot: WebexStreamSnapshot<WebexSpace>) {
        lock.withLock {
            current = snapshot
            continuation?.yield(snapshot)
        }
    }

    func currentSnapshot() async -> WebexStreamSnapshot<WebexSpace> {
        lock.withLock { current }
    }

    func refresh() async {
        lock.withLock {
            refreshCount += 1
        }
    }

    func refreshEnrichment() async {
        lock.withLock {
            refreshEnrichmentCount += 1
        }
    }

    func loadNextPage() async {
        lock.withLock {
            loadNextPageCount += 1
        }
    }
}

private final class RecordingEnrichedSpacesRuntime: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var refreshCount = 0
    private(set) var refreshEnrichmentCount = 0
    private(set) var loadNextPageCount = 0

    var runtime: EnrichedSpacesRuntime {
        EnrichedSpacesRuntime(
            snapshots: AsyncStream { $0.yield(snapshot(items: [], revision: 0)) },
            currentSnapshot: { snapshot(items: [], revision: 0) },
            refresh: { [self] in lock.withLock { refreshCount += 1 } },
            refreshEnrichment: { [self] in lock.withLock { refreshEnrichmentCount += 1 } },
            loadNextPage: { [self] in lock.withLock { loadNextPageCount += 1 } }
        )
    }
}
```

- [ ] **Step 2: Run window model tests and verify they fail**

Run:

```bash
cd Examples/WebexSpacesEnrichedSnapshotSmoke
swift test --filter EnrichedSpacesWindowModelTests
```

Expected: compile failure for missing `EnrichedSpacesRuntime` and `EnrichedSpacesWindowModel`.

- [ ] **Step 3: Implement runtime command boundary**

Create `Examples/WebexSpacesEnrichedSnapshotSmoke/Sources/WebexSpacesEnrichedSnapshotSmoke/Services/EnrichedSpacesRuntime.swift`:

```swift
import Foundation
import WebexSwiftSDK

final class EnrichedSpacesRuntime: @unchecked Sendable {
    let snapshots: AsyncStream<WebexStreamSnapshot<WebexSpace>>
    let currentSnapshot: @Sendable () async -> WebexStreamSnapshot<WebexSpace>
    let refresh: @Sendable () async -> Void
    let refreshEnrichment: @Sendable () async -> Void
    let loadNextPage: @Sendable () async -> Void

    private let lock = NSLock()
    private var cancelHandler: (@Sendable () -> Void)?

    init(
        stream: SpacesStream,
        cancel: @escaping @Sendable () -> Void = {}
    ) {
        self.snapshots = stream.snapshots
        self.currentSnapshot = {
            await stream.currentSnapshot()
        }
        self.refresh = {
            await stream.refresh()
        }
        self.refreshEnrichment = {
            await stream.refreshEnrichment()
        }
        self.loadNextPage = {
            await stream.loadNextPage()
        }
        self.cancelHandler = cancel
    }

    init(
        snapshots: AsyncStream<WebexStreamSnapshot<WebexSpace>>,
        currentSnapshot: @escaping @Sendable () async -> WebexStreamSnapshot<WebexSpace>,
        refresh: @escaping @Sendable () async -> Void,
        refreshEnrichment: @escaping @Sendable () async -> Void,
        loadNextPage: @escaping @Sendable () async -> Void,
        cancel: @escaping @Sendable () -> Void = {}
    ) {
        self.snapshots = snapshots
        self.currentSnapshot = currentSnapshot
        self.refresh = refresh
        self.refreshEnrichment = refreshEnrichment
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

Create `Examples/WebexSpacesEnrichedSnapshotSmoke/Sources/WebexSpacesEnrichedSnapshotSmoke/Stores/EnrichedSpacesWindowModel.swift`:

```swift
import Combine
import Foundation
import WebexSwiftSDK

@MainActor
final class EnrichedSpacesWindowModel: ObservableObject {
    typealias RuntimeFactory = @Sendable () async throws -> EnrichedSpacesRuntime

    @Published private(set) var rows: [EnrichedSpaceRowModel] = []
    @Published private(set) var selectedDetail: EnrichedSpaceDetailModel?
    @Published private(set) var selectedSpaceID: String?
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var revision: UInt64 = 0
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingNextPage = false
    @Published private(set) var hasMore = false
    @Published private(set) var capReached = false
    @Published private(set) var lastUpdatedText = "Never"
    @Published private(set) var lastErrorText: String?

    private let runtimeFactory: RuntimeFactory
    private var runtime: EnrichedSpacesRuntime?
    private var subscriptionTask: Task<Void, Never>?
    private var currentSpaces: [WebexSpace] = []

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

    var canRefreshEnrichment: Bool {
        runtime != nil && !currentSpaces.isEmpty
    }

    var canLoadMore: Bool {
        runtime != nil && hasMore && !capReached && !isLoadingNextPage
    }

    func start() async {
        guard runtime == nil else {
            return
        }

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

    func refreshEnrichment() async {
        await runtime?.refreshEnrichment()
    }

    func loadNextPage() async {
        guard canLoadMore else {
            return
        }
        await runtime?.loadNextPage()
    }

    func select(spaceID: String?) {
        selectedSpaceID = spaceID
        updateSelectedDetail()
    }

    private func subscribe(to snapshots: AsyncStream<WebexStreamSnapshot<WebexSpace>>) {
        subscriptionTask?.cancel()
        subscriptionTask = Task { [weak self] in
            for await snapshot in snapshots {
                self?.apply(snapshot)
            }
        }
    }

    private func apply(_ snapshot: WebexStreamSnapshot<WebexSpace>) {
        currentSpaces = snapshot.items
        rows = snapshot.items.map(EnrichedSpaceRowModel.init)
        revision = snapshot.revision
        isRefreshing = snapshot.isRefreshing
        isLoadingNextPage = snapshot.isLoadingNextPage
        hasMore = snapshot.pagination.hasMore
        capReached = snapshot.pagination.capReached
        lastUpdatedText = Self.lastUpdatedText(from: snapshot.lastUpdatedAt)
        lastErrorText = snapshot.lastError.map(Self.safeDescription)

        if let selectedSpaceID,
           snapshot.items.contains(where: { $0.id == selectedSpaceID }) {
            self.selectedSpaceID = selectedSpaceID
        } else {
            selectedSpaceID = snapshot.items.first?.id
        }
        updateSelectedDetail()
    }

    private func updateSelectedDetail() {
        guard let selectedSpaceID,
              let selected = currentSpaces.first(where: { $0.id == selectedSpaceID }) else {
            selectedDetail = nil
            return
        }
        selectedDetail = EnrichedSpaceDetailModel(space: selected)
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

- [ ] **Step 5: Run window model tests and verify they pass**

Run:

```bash
cd Examples/WebexSpacesEnrichedSnapshotSmoke
swift test --filter EnrichedSpacesWindowModelTests
```

Expected: all `EnrichedSpacesWindowModelTests` pass.

- [ ] **Step 6: Commit runtime and window model**

Run:

```bash
git add Examples/WebexSpacesEnrichedSnapshotSmoke/Sources/WebexSpacesEnrichedSnapshotSmoke/Services/EnrichedSpacesRuntime.swift \
  Examples/WebexSpacesEnrichedSnapshotSmoke/Sources/WebexSpacesEnrichedSnapshotSmoke/Stores/EnrichedSpacesWindowModel.swift \
  Examples/WebexSpacesEnrichedSnapshotSmoke/Tests/WebexSpacesEnrichedSnapshotSmokeTests/EnrichedSpacesWindowModelTests.swift
git commit -m "feat: drive enriched spaces smoke state"
```

Expected: commit succeeds.

### Task 4: Bootstrap, SwiftUI App, And Views

**Files:**
- Create: `Examples/WebexSpacesEnrichedSnapshotSmoke/Sources/WebexSpacesEnrichedSnapshotSmoke/Services/EnrichedSpacesBootstrap.swift`
- Create: `Examples/WebexSpacesEnrichedSnapshotSmoke/Sources/WebexSpacesEnrichedSnapshotSmoke/App/WebexSpacesEnrichedSnapshotSmokeApp.swift`
- Create: `Examples/WebexSpacesEnrichedSnapshotSmoke/Sources/WebexSpacesEnrichedSnapshotSmoke/Views/EnrichedSpacesContentView.swift`
- Create: `Examples/WebexSpacesEnrichedSnapshotSmoke/Sources/WebexSpacesEnrichedSnapshotSmoke/Views/EnrichedSpaceDetailView.swift`

- [ ] **Step 1: Implement bootstrap**

Create `Examples/WebexSpacesEnrichedSnapshotSmoke/Sources/WebexSpacesEnrichedSnapshotSmoke/Services/EnrichedSpacesBootstrap.swift`:

```swift
import AppKit
import Foundation
import WebexSwiftSDK

enum EnrichedSpacesBootstrap {
    static func makeRuntime(configuration: EnrichedSpacesSmokeConfiguration) async throws -> EnrichedSpacesRuntime {
        let httpClient = URLSessionHTTPClient()
        let store = KeychainWebexStore(service: configuration.keychainService)
        let registry = WebexClientRegistry(store: store, httpClient: httpClient)
        let authorized = try await registry.authorizeAndAddAccount(
            configuration: configuration.integration,
            openAuthorizationURL: { authorizationURL in
                guard NSWorkspace.shared.open(authorizationURL) else {
                    throw EnrichedSpacesSmokeError.failedToOpenAuthorizationURL
                }
            }
        )

        let stream = authorized.client.spaces.stream(
            params: configuration.listParams,
            pageLimit: configuration.pageLimit
        )

        return EnrichedSpacesRuntime(stream: stream)
    }
}
```

- [ ] **Step 2: Implement app entrypoint**

Create `Examples/WebexSpacesEnrichedSnapshotSmoke/Sources/WebexSpacesEnrichedSnapshotSmoke/App/WebexSpacesEnrichedSnapshotSmokeApp.swift`:

```swift
import SwiftUI
import WebexSwiftSDK

@main
struct WebexSpacesEnrichedSnapshotSmokeApp: App {
    @StateObject private var model: EnrichedSpacesWindowModel

    init() {
        do {
            let configuration = try EnrichedSpacesSmokeConfiguration(environment: ProcessInfo.processInfo.environment)
            _model = StateObject(wrappedValue: EnrichedSpacesWindowModel(
                runtimeFactory: {
                    try await EnrichedSpacesBootstrap.makeRuntime(configuration: configuration)
                }
            ))
        } catch {
            let startupFailure = String(describing: error)
            _model = StateObject(wrappedValue: EnrichedSpacesWindowModel(
                runtimeFactory: {
                    throw WebexSDKError.network(startupFailure)
                }
            ))
        }
    }

    var body: some Scene {
        WindowGroup {
            EnrichedSpacesContentView(model: model)
                .frame(minWidth: 980, minHeight: 620)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh Spaces") {
                    Task {
                        await model.refresh()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!model.canRefresh)

                Button("Refresh Enrichment") {
                    Task {
                        await model.refreshEnrichment()
                    }
                }
                .keyboardShortcut("e", modifiers: [.command])
                .disabled(!model.canRefreshEnrichment)
            }
        }
    }
}
```

- [ ] **Step 3: Implement content view**

Create `Examples/WebexSpacesEnrichedSnapshotSmoke/Sources/WebexSpacesEnrichedSnapshotSmoke/Views/EnrichedSpacesContentView.swift`:

```swift
import SwiftUI

struct EnrichedSpacesContentView: View {
    @ObservedObject var model: EnrichedSpacesWindowModel

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

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Enriched Spaces")
                    .font(.title2)
                    .fontWeight(.semibold)

                HStack(spacing: 12) {
                    statusLabel
                    Text("Revision \(model.revision)")
                    Text("Updated \(model.lastUpdatedText)")
                    if model.hasMore {
                        Text(model.capReached ? "More pages capped" : "More pages available")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task {
                    await model.refresh()
                }
            } label: {
                Label("Refresh Spaces", systemImage: "arrow.clockwise")
            }
            .disabled(!model.canRefresh)

            Button {
                Task {
                    await model.refreshEnrichment()
                }
            } label: {
                Label("Refresh Enrichment", systemImage: "sparkles")
            }
            .disabled(!model.canRefreshEnrichment)

            Button {
                Task {
                    await model.loadNextPage()
                }
            } label: {
                Label("Load More", systemImage: "arrow.down.circle")
            }
            .disabled(!model.canLoadMore)
        }
        .padding()
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
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            if model.rows.isEmpty, model.isRefreshing {
                ProgressView("Loading spaces")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.rows.isEmpty {
                Text("No spaces")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NavigationSplitView {
                    List(selection: Binding(
                        get: { model.selectedSpaceID },
                        set: { model.select(spaceID: $0) }
                    )) {
                        ForEach(model.rows) { row in
                            EnrichedSpaceRowView(row: row)
                                .tag(row.id)
                        }
                    }
                    .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 420)
                } detail: {
                    EnrichedSpaceDetailView(detail: model.selectedDetail)
                }
                .overlay(alignment: .bottomLeading) {
                    if let error = model.lastErrorText {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .padding()
                    }
                }
            }
        }
    }

    private var statusLabel: some View {
        Group {
            if model.isRefreshing {
                Label("Refreshing spaces", systemImage: "arrow.triangle.2.circlepath")
            } else if model.isLoadingNextPage {
                Label("Loading page", systemImage: "arrow.down")
            } else {
                Label("Ready", systemImage: "checkmark.circle")
            }
        }
    }
}

private struct EnrichedSpaceRowView: View {
    let row: EnrichedSpaceRowModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: row.systemImageName)
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(row.typeText)
                    Text(row.enrichmentStatusText)
                    Text(row.enrichmentSummary)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}
```

- [ ] **Step 4: Implement detail view**

Create `Examples/WebexSpacesEnrichedSnapshotSmoke/Sources/WebexSpacesEnrichedSnapshotSmoke/Views/EnrichedSpaceDetailView.swift`:

```swift
import SwiftUI

struct EnrichedSpaceDetailView: View {
    let detail: EnrichedSpaceDetailModel?

    var body: some View {
        Group {
            if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(detail.title)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .textSelection(.enabled)

                        HStack(alignment: .top, spacing: 16) {
                            fieldSection(
                                title: "Wire-faithful WebexSpace",
                                systemImage: "network",
                                fields: detail.wireFields
                            )
                            fieldSection(
                                title: "SDK-derived enriched",
                                systemImage: "sparkles",
                                fields: detail.enrichedFields
                            )
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("Select a space")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func fieldSection(
        title: String,
        systemImage: String,
        fields: [FieldDisplay]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            ForEach(fields) { field in
                VStack(alignment: .leading, spacing: 3) {
                    Text(field.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(field.value)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(4)
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
```

- [ ] **Step 5: Build the example app**

Run:

```bash
cd Examples/WebexSpacesEnrichedSnapshotSmoke
swift build
```

Expected: build succeeds.

- [ ] **Step 6: Run example tests**

Run:

```bash
cd Examples/WebexSpacesEnrichedSnapshotSmoke
swift test
```

Expected: all example tests pass.

- [ ] **Step 7: Commit bootstrap and UI**

Run:

```bash
git add Examples/WebexSpacesEnrichedSnapshotSmoke/Sources/WebexSpacesEnrichedSnapshotSmoke/Services/EnrichedSpacesBootstrap.swift \
  Examples/WebexSpacesEnrichedSnapshotSmoke/Sources/WebexSpacesEnrichedSnapshotSmoke/App/WebexSpacesEnrichedSnapshotSmokeApp.swift \
  Examples/WebexSpacesEnrichedSnapshotSmoke/Sources/WebexSpacesEnrichedSnapshotSmoke/Views/EnrichedSpacesContentView.swift \
  Examples/WebexSpacesEnrichedSnapshotSmoke/Sources/WebexSpacesEnrichedSnapshotSmoke/Views/EnrichedSpaceDetailView.swift
git commit -m "feat: add enriched spaces smoke window"
```

Expected: commit succeeds.

### Task 5: Documentation And Root README Link

**Files:**
- Create: `Examples/WebexSpacesEnrichedSnapshotSmoke/README.md`
- Modify: `README.md`

- [ ] **Step 1: Add example README**

Create `Examples/WebexSpacesEnrichedSnapshotSmoke/README.md`:

```markdown
# WebexSpacesEnrichedSnapshotSmoke

Native macOS SwiftUI smoke app for viewing Webex Spaces through an enriched
`SpacesStream`.

The window subscribes to `stream.snapshots` and shows each `WebexSpace` item in
two columns:

- wire-faithful fields decoded from `/v1/rooms`
- SDK-derived `enriched` fields such as `teamName`, `spaceAvatar`, status, and
  item-scoped enrichment errors

The UI never calls `client.teams`, `client.people`, or `client.memberships`
directly. Those follow-up REST calls belong to the stream enrichment layer.

This smoke is snapshot-only. Apps that need realtime can connect Webex realtime
events separately and pass those triggers to `SpacesStream.refreshOnTriggers`.
The snapshots emitted after those refreshes carry the same enriched data shown
here.

## Required Webex Integration Settings

Configure the Webex integration redirect URI as:

```text
http://127.0.0.1:8282/oauth/callback
```

Default REST scopes:

```text
spark:rooms_read spark:memberships_read spark:people_read
```

If your Webex tenant requires a separate team read scope for team details, add
that scope through `WEBEX_SCOPES`.

## Run

```bash
cd Examples/WebexSpacesEnrichedSnapshotSmoke
export WEBEX_CLIENT_ID="..."
export WEBEX_CLIENT_SECRET="..."
swift run WebexSpacesEnrichedSnapshotSmoke
```

Optional environment variables:

- `WEBEX_REDIRECT_URI`: defaults to `http://127.0.0.1:8282/oauth/callback`
- `WEBEX_SCOPES`: defaults to `spark:rooms_read spark:memberships_read spark:people_read`
- `WEBEX_SPACES_PAGE_SIZE`: defaults to `25`
- `WEBEX_SPACES_STREAM_PAGE_LIMIT`: defaults to `1`
- `WEBEX_SPACES_TYPE`: optional `direct` or `group`
- `WEBEX_SPACES_TEAM_ID`: optional team id filter
- `WEBEX_SPACES_SORT_BY`: optional `id`, `lastactivity`, or `created`
- `WEBEX_KEYCHAIN_SERVICE`: defaults to `com.webex.swift-sdk.spaces-enriched-snapshot-smoke`

## Controls

- `Refresh Spaces`: reloads the base spaces page and then enriches the snapshot.
- `Refresh Enrichment`: refreshes cached enrichment details without reloading the
  base spaces page.
- `Load More`: loads the next spaces page when pagination allows.

The app opens Webex authorization in the default browser on first launch. Once
the SDK stores the refresh token in Keychain, future launches can refresh access
tokens through the SDK token lifecycle.
```

- [ ] **Step 2: Update root README examples list**

Modify the `## Examples` list in `README.md` by adding this bullet:

```markdown
- `Examples/WebexSpacesEnrichedSnapshotSmoke`: native macOS smoke app that shows
  wire-faithful spaces data alongside SDK-derived enriched snapshot fields.
```

- [ ] **Step 3: Run documentation checks**

Run:

```bash
git diff --check
```

Expected: no output and exit code 0.

- [ ] **Step 4: Commit documentation**

Run:

```bash
git add Examples/WebexSpacesEnrichedSnapshotSmoke/README.md README.md
git commit -m "docs: add enriched spaces smoke readme"
```

Expected: commit succeeds.

### Task 6: Final Verification

**Files:**
- No planned source files.

- [ ] **Step 1: Run example tests**

Run:

```bash
cd Examples/WebexSpacesEnrichedSnapshotSmoke
swift test
```

Expected: all example tests pass.

- [ ] **Step 2: Build example app**

Run:

```bash
cd Examples/WebexSpacesEnrichedSnapshotSmoke
swift build
```

Expected: build succeeds.

- [ ] **Step 3: Run root package tests**

Run from repo root:

```bash
swift test
```

Expected: root SDK tests pass. Keychain integration tests may be skipped unless `WEBEX_SDK_RUN_KEYCHAIN_TESTS=1` is set.

- [ ] **Step 4: Run whitespace check**

Run from repo root:

```bash
git diff --check
```

Expected: no output and exit code 0.

- [ ] **Step 5: Inspect git status**

Run:

```bash
git status --short --branch
```

Expected: branch is `agent/enriched-snapshots` and the worktree is clean.
