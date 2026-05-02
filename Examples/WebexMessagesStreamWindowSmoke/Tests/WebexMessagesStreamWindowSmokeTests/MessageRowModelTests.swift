import XCTest
import WebexSwiftSDK
@testable import WebexMessagesStreamWindowSmoke

final class MessageRowModelTests: XCTestCase {
    func testMessageRowPrefersTextAndPreservesMentionMetadata() {
        let row = MessageRowModel(message: WebexMessage(
            id: "message-1",
            text: "Hello Harrison",
            markdown: "**Hello Harrison**",
            html: "<p>Hello Harrison</p>",
            personEmail: "sender@example.com",
            mentionedPeople: ["person-1", "person-2"],
            mentionedGroups: ["all"],
            created: Date(timeIntervalSince1970: 0)
        ))

        XCTAssertEqual(row.id, "message-1")
        XCTAssertEqual(row.sender, "sender@example.com")
        XCTAssertEqual(row.body, "Hello Harrison")
        XCTAssertEqual(row.contentSource, "text")
        XCTAssertEqual(row.createdText, "1970-01-01T00:00:00Z")
        XCTAssertEqual(row.mentionedPeopleText, "person-1, person-2")
        XCTAssertEqual(row.mentionedGroupsText, "all")
    }

    func testMessageRowFallsBackToMarkdownThenHTML() {
        let markdownRow = MessageRowModel(message: WebexMessage(
            id: "message-1",
            text: " ",
            markdown: "**Markdown**",
            html: "<p>HTML</p>",
            personID: "person-id"
        ))

        XCTAssertEqual(markdownRow.sender, "person-id")
        XCTAssertEqual(markdownRow.body, "**Markdown**")
        XCTAssertEqual(markdownRow.contentSource, "markdown")

        let htmlRow = MessageRowModel(message: WebexMessage(
            id: "message-2",
            text: nil,
            markdown: "",
            html: "<p>HTML</p>"
        ))

        XCTAssertEqual(htmlRow.sender, "(unknown sender)")
        XCTAssertEqual(htmlRow.body, "<p>HTML</p>")
        XCTAssertEqual(htmlRow.contentSource, "html")
    }
}
