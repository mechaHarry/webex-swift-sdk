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
            additionalFields: [
                "avatar": .string("https://example.com/group-space.png"),
                "theme": .object(["color": .string("blue")])
            ],
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
            FieldDisplay(name: "created", value: "1970-01-01T00:00:00Z"),
            FieldDisplay(name: "additionalFields.avatar", value: "\"https://example.com/group-space.png\""),
            FieldDisplay(name: "additionalFields.theme", value: #"{"color":"blue"}"#)
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
