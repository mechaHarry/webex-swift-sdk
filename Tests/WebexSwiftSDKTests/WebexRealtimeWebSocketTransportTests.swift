import Foundation
import XCTest
@testable import WebexSwiftSDK

final class WebexRealtimeWebSocketTransportTests: XCTestCase {
    func testPreparedURLRequestsTextWireFormatAndKeepsExistingQueryItems() throws {
        let url = try XCTUnwrap(URL(string: "wss://mercury.example.com/mercury/device?existing=value&outboundWireFormat=binary"))

        let preparedURL = URLSessionWebSocketTransport.preparedURL(
            for: url,
            clientTimestamp: 1_777_424_100_000
        )

        let components = try XCTUnwrap(URLComponents(url: preparedURL, resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(components.scheme, "wss")
        XCTAssertEqual(components.host, "mercury.example.com")
        XCTAssertEqual(components.path, "/mercury/device")
        XCTAssertEqual(queryItems["existing"], "value")
        XCTAssertEqual(queryItems["outboundWireFormat"], "text")
        XCTAssertEqual(queryItems["bufferStates"], "true")
        XCTAssertEqual(queryItems["aliasHttpStatus"], "true")
        XCTAssertEqual(queryItems["clientTimestamp"], "1777424100000")
    }
}
