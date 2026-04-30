import XCTest
@testable import WebexSpacesListSmoke

final class ListOptionsTests: XCTestCase {
    func testDefaultsAvoidLowPageCapsForLargeAccounts() throws {
        let options = try ListOptions(environment: [:])

        XCTAssertEqual(options.pageSize, 100)
        XCTAssertEqual(options.maxPages, 1_000)
        XCTAssertEqual(options.query.max, 100)
    }
}
