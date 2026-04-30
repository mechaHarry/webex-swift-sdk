import XCTest
@testable import WebexSwiftSDK

final class SpacesAPITests: XCTestCase {
    func testSpaceDecodesKnownFieldsAndPartialErrors() throws {
        let json = Data("""
        {
          "id": "space-id",
          "title": "Incident Review",
          "type": "group",
          "isLocked": true,
          "teamId": "team-id",
          "lastActivity": "2026-04-30T18:01:02.123Z",
          "creatorId": "creator-id",
          "created": "2026-04-29T17:00:00Z",
          "ownerId": "owner-id",
          "description": "Postmortem space",
          "isPublic": true,
          "isReadOnly": false,
          "isAnnouncementOnly": true,
          "classificationId": "classification-id",
          "madePublic": "2026-04-30T19:00:00.000Z",
          "errors": {
            "title": {
              "code": "kms_failure",
              "reason": "Could not decrypt title"
            }
          }
        }
        """.utf8)

        let space = try JSONDecoder().decode(WebexSpace.self, from: json)

        XCTAssertEqual(space.id, "space-id")
        XCTAssertEqual(space.title, "Incident Review")
        XCTAssertEqual(space.type, .group)
        XCTAssertEqual(space.isLocked, true)
        XCTAssertEqual(space.teamID, "team-id")
        XCTAssertEqual(space.creatorID, "creator-id")
        XCTAssertEqual(space.ownerID, "owner-id")
        XCTAssertEqual(space.description, "Postmortem space")
        XCTAssertEqual(space.isPublic, true)
        XCTAssertEqual(space.isReadOnly, false)
        XCTAssertEqual(space.isAnnouncementOnly, true)
        XCTAssertEqual(space.classificationID, "classification-id")
        XCTAssertEqual(space.errors?["title"], WebexPartialResourceError(code: "kms_failure", reason: "Could not decrypt title"))
        XCTAssertEqual(iso8601(space.lastActivity), "2026-04-30T18:01:02Z")
        XCTAssertEqual(iso8601(space.created), "2026-04-29T17:00:00Z")
        XCTAssertEqual(iso8601(space.madePublic), "2026-04-30T19:00:00Z")
    }

    func testSpaceTypePreservesUnknownValues() throws {
        let json = Data(#"{"id":"space-id","type":"future-type"}"#.utf8)

        let space = try JSONDecoder().decode(WebexSpace.self, from: json)

        XCTAssertEqual(space.type, .unknown("future-type"))
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
