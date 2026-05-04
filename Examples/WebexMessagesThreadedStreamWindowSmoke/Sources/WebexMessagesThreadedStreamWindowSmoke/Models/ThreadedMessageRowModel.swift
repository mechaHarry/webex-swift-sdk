import Foundation
import WebexSwiftSDK

struct ThreadedMessageRowModel: Identifiable, Equatable {
    let id: String
    let depth: Int
    let parentText: String
    let sender: String
    let body: String
    let contentSource: String
    let createdText: String
    let childCount: Int
    let childCountText: String
    let isPlaceholderParent: Bool

    init(entry: WebexMessageThreadEntry, depth: Int) {
        self.id = entry.id
        self.depth = depth
        self.parentText = entry.parentID ?? "(top-level)"
        self.childCount = entry.childIDs.count
        self.childCountText = Self.childCountText(for: entry.childIDs.count)
        self.isPlaceholderParent = entry.isPlaceholderParent

        if entry.isDeletedTombstone {
            self.sender = "(deleted message)"
            self.body = "(message deleted)"
            self.contentSource = "deleted"
            self.createdText = Self.createdText(from: entry.effectiveCreated)
        } else if let message = entry.message {
            self.sender = message.personEmail
                ?? message.personID
                ?? message.toPersonEmail
                ?? message.toPersonID
                ?? "(unknown sender)"
            let content = Self.preferredContent(from: message)
            self.body = content.value
            self.contentSource = content.source
            self.createdText = Self.createdText(from: message.created ?? entry.effectiveCreated)
        } else {
            self.sender = "(placeholder parent)"
            self.body = "(parent message unavailable)"
            self.contentSource = "placeholder"
            self.createdText = Self.createdText(from: entry.effectiveCreated)
        }
    }

    static func rows(from snapshot: WebexMessageThreadSnapshot) -> [ThreadedMessageRowModel] {
        var rows: [ThreadedMessageRowModel] = []
        var visited = Set<String>()

        func appendRows(startingAt id: String, depth: Int) {
            guard visited.insert(id).inserted,
                  let entry = snapshot.threadEntryByID[id] else {
                return
            }

            rows.append(ThreadedMessageRowModel(entry: entry, depth: depth))
            for childID in entry.childIDs {
                appendRows(startingAt: childID, depth: depth + 1)
            }
        }

        for id in snapshot.topLevelMessageIDs.reversed() {
            appendRows(startingAt: id, depth: 0)
        }

        for id in snapshot.chronologicalMessageIDs.reversed() where !visited.contains(id) {
            appendRows(startingAt: id, depth: 0)
        }

        return rows
    }

    private static func preferredContent(from message: WebexMessage) -> (source: String, value: String) {
        if let text = nonEmpty(message.text) {
            return ("text", text)
        }
        if let markdown = nonEmpty(message.markdown) {
            return ("markdown", markdown)
        }
        if let html = nonEmpty(message.html) {
            return ("html", html)
        }

        return ("empty", "(no text)")
    }

    private static func createdText(from date: Date?) -> String {
        guard let date else {
            return "(unknown time)"
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func childCountText(for count: Int) -> String {
        count == 1 ? "1 child" : "\(count) children"
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        return value
    }
}
