import XCTest
import WebexSwiftSDK
@testable import WebexMessagesThreadedStreamWindowSmoke

final class ThreadedMessageRowModelTests: XCTestCase {
    func testRowsDisplayNewestFirstWhilePreservingThreadIndentationAndPlaceholderParents() {
        let snapshot = WebexMessageThreadSnapshot(
            topLevelMessageIDs: ["deleted-parent", "parent"],
            threadEntryByID: [
                "deleted-parent": WebexMessageThreadEntry(
                    id: "deleted-parent",
                    message: nil,
                    parentID: nil,
                    childIDs: ["orphan-child"],
                    effectiveCreated: date(5),
                    isPlaceholderParent: true
                ),
                "orphan-child": WebexMessageThreadEntry(
                    id: "orphan-child",
                    message: message(id: "orphan-child", parentID: "deleted-parent", text: "Orphan reply", created: 5),
                    parentID: "deleted-parent",
                    childIDs: [],
                    effectiveCreated: date(5),
                    isPlaceholderParent: false
                ),
                "parent": WebexMessageThreadEntry(
                    id: "parent",
                    message: message(id: "parent", text: "Parent", created: 10),
                    parentID: nil,
                    childIDs: ["child-older", "deleted-child", "child-newer"],
                    effectiveCreated: date(10),
                    isPlaceholderParent: false
                ),
                "child-older": WebexMessageThreadEntry(
                    id: "child-older",
                    message: message(id: "child-older", parentID: "parent", text: "Older child", created: 15),
                    parentID: "parent",
                    childIDs: [],
                    effectiveCreated: date(15),
                    isPlaceholderParent: false
                ),
                "deleted-child": WebexMessageThreadEntry(
                    id: "deleted-child",
                    message: nil,
                    parentID: "parent",
                    childIDs: [],
                    effectiveCreated: date(18),
                    isPlaceholderParent: false,
                    isDeletedTombstone: true
                ),
                "child-newer": WebexMessageThreadEntry(
                    id: "child-newer",
                    message: message(id: "child-newer", parentID: "parent", text: "Newer child", created: 20),
                    parentID: "parent",
                    childIDs: [],
                    effectiveCreated: date(20),
                    isPlaceholderParent: false
                )
            ],
            chronologicalMessageIDs: ["orphan-child", "parent", "child-older", "deleted-child", "child-newer"],
            revision: 3,
            lastUpdatedAt: nil,
            isRefreshing: false,
            isLoadingNextPage: false,
            lastError: nil,
            pagination: WebexStreamPagination(
                hasMore: false,
                nextPage: nil,
                pagesLoaded: 1,
                pageLimit: 1,
                capReached: false
            )
        )

        let rows = ThreadedMessageRowModel.rows(from: snapshot)

        XCTAssertEqual(rows.map(\.id), ["parent", "child-older", "deleted-child", "child-newer", "deleted-parent", "orphan-child"])
        XCTAssertEqual(rows.map(\.depth), [0, 1, 1, 1, 0, 1])
        XCTAssertEqual(rows[0].childCountText, "3 children")
        XCTAssertEqual(rows[1].body, "Older child")
        XCTAssertEqual(rows[1].parentText, "parent")
        XCTAssertEqual(rows[2].body, "(message deleted)")
        XCTAssertEqual(rows[2].sender, "(deleted message)")
        XCTAssertEqual(rows[2].contentSource, "deleted")
        XCTAssertEqual(rows[3].body, "Newer child")
        XCTAssertEqual(rows[4].body, "(parent message unavailable)")
        XCTAssertEqual(rows[4].sender, "(placeholder parent)")
        XCTAssertEqual(rows[4].childCountText, "1 child")
        XCTAssertEqual(rows[5].parentText, "deleted-parent")
        XCTAssertEqual(rows[5].body, "Orphan reply")
    }
}

private func message(
    id: String,
    parentID: String? = nil,
    text: String,
    created seconds: TimeInterval
) -> WebexMessage {
    WebexMessage(
        id: id,
        parentID: parentID,
        text: text,
        personEmail: "\(id)@example.com",
        created: date(seconds)
    )
}

private func date(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: seconds)
}
