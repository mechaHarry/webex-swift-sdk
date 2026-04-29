import XCTest
import WebexSwiftSDK

final class BootstrapTests: XCTestCase {
    func testPackageMarkerIsAvailable() {
        XCTAssertEqual(WebexSwiftSDK.name, "WebexSwiftSDK")
    }
}
