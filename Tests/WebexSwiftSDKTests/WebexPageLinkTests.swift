import XCTest
@testable import WebexSwiftSDK

final class WebexPageLinkTests: XCTestCase {
    func testExtractsNextLinkFromRFC5988Header() throws {
        let response = httpResponse(headers: [
            "Link": #"<https://webexapis.com/v1/rooms?max=2&cursor=abc>; rel="next""#
        ])

        let link = try XCTUnwrap(WebexPageLink.next(from: response))

        XCTAssertEqual(link.url.absoluteString, "https://webexapis.com/v1/rooms?max=2&cursor=abc")
        XCTAssertEqual(link.request.path, "/v1/rooms")
        XCTAssertEqual(link.request.queryItems, [
            URLQueryItem(name: "max", value: "2"),
            URLQueryItem(name: "cursor", value: "abc")
        ])
    }

    func testIgnoresFirstAndPrevWhenNextIsAbsent() {
        let response = httpResponse(headers: [
            "Link": #"<https://webexapis.com/v1/rooms?page=1>; rel="first", <https://webexapis.com/v1/rooms?page=0>; rel="prev""#
        ])

        XCTAssertNil(WebexPageLink.next(from: response))
    }

    func testFindsNextAmongMultipleRelationsAndHeaderCaseVariants() throws {
        let response = httpResponse(headers: [
            "link": #"<https://webexapis.com/v1/rooms?page=1>; rel="first", <https://webexapis.com/v1/rooms?page=2>; rel="next""#
        ])

        let link = try XCTUnwrap(WebexPageLink.next(from: response))

        XCTAssertEqual(link.url.absoluteString, "https://webexapis.com/v1/rooms?page=2")
    }

    func testRejectsNonWebexNextLink() {
        let response = httpResponse(headers: [
            "Link": #"<https://evil.example/v1/rooms?page=2>; rel="next""#
        ])

        XCTAssertNil(WebexPageLink.next(from: response))
    }

    private func httpResponse(headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://webexapis.com/v1/rooms")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }
}
