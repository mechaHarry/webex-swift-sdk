import XCTest
@testable import WebexMembershipsListSmoke

final class ListOptionsTests: XCTestCase {
    func testRequiresRoomIDAndDefaultsAvoidLowPageCaps() throws {
        XCTAssertThrowsError(try MembershipListOptions(environment: [:]))

        let options = try MembershipListOptions(environment: ["WEBEX_ROOM_ID": "room-id"])

        XCTAssertEqual(options.roomID, "room-id")
        XCTAssertEqual(options.pageSize, 100)
        XCTAssertEqual(options.maxPages, 1_000)
        XCTAssertEqual(options.query.roomID, "room-id")
        XCTAssertEqual(options.query.max, 100)
    }
}
