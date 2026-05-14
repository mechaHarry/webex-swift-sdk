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

    func testRowModelUsesSingularAdditionalFieldText() {
        let row = TeamSnapshotRowModel(
            team: WebexTeam(
                id: "team-1",
                additionalFields: ["color": .string("blue")]
            )
        )

        XCTAssertEqual(row.additionalFieldsText, "1 extra field")
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
