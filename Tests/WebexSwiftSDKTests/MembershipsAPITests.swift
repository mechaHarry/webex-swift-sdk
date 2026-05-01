import XCTest
@testable import WebexSwiftSDK

final class MembershipsAPITests: XCTestCase {
    func testMembershipDecodesKnownFields() throws {
        let json = Data("""
        {
          "id": "membership-id",
          "roomId": "room-id",
          "roomType": "group",
          "personId": "person-id",
          "personEmail": "person@example.com",
          "personDisplayName": "Ada Lovelace",
          "personOrgId": "org-id",
          "isModerator": true,
          "isMonitor": false,
          "isRoomHidden": true,
          "created": "2026-05-01T10:11:12.123Z"
        }
        """.utf8)

        let membership = try JSONDecoder().decode(WebexMembership.self, from: json)

        XCTAssertEqual(membership.id, "membership-id")
        XCTAssertEqual(membership.roomID, "room-id")
        XCTAssertEqual(membership.roomType, .group)
        XCTAssertEqual(membership.personID, "person-id")
        XCTAssertEqual(membership.personEmail, "person@example.com")
        XCTAssertEqual(membership.personDisplayName, "Ada Lovelace")
        XCTAssertEqual(membership.personOrgID, "org-id")
        XCTAssertEqual(membership.isModerator, true)
        XCTAssertEqual(membership.isMonitor, false)
        XCTAssertEqual(membership.isRoomHidden, true)
        XCTAssertEqual(iso8601(membership.created), "2026-05-01T10:11:12Z")
    }

    func testMembershipPreservesUnknownRoomType() throws {
        let json = Data(#"{"id":"membership-id","roomType":"future-room"}"#.utf8)

        let membership = try JSONDecoder().decode(WebexMembership.self, from: json)

        XCTAssertEqual(membership.roomType, .unknown("future-room"))
    }

    func testMembershipRejectsInvalidCreatedTimestamp() throws {
        let json = Data(#"{"id":"membership-id","created":"not-a-date"}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(WebexMembership.self, from: json)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted error, got \(error)")
            }

            XCTAssertEqual(context.debugDescription, "Invalid Webex timestamp")
        }
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
