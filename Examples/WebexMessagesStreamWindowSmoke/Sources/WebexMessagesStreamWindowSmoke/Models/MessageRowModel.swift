import Foundation
import WebexSwiftSDK

struct MessageRowModel: Identifiable, Equatable {
    let id: String
    let sender: String
    let body: String
    let contentSource: String
    let createdText: String
    let mentionedPeopleText: String
    let mentionedGroupsText: String

    init(message: WebexMessage) {
        self.id = message.id
        self.sender = message.personEmail
            ?? message.personID
            ?? message.toPersonEmail
            ?? message.toPersonID
            ?? "(unknown sender)"
        let content = Self.preferredContent(from: message)
        self.body = content.value
        self.contentSource = content.source
        self.createdText = Self.createdText(from: message.created)
        self.mentionedPeopleText = Self.joined(message.mentionedPeople)
        self.mentionedGroupsText = Self.joined(message.mentionedGroups)
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

    private static func joined(_ values: [String]?) -> String {
        guard let values, !values.isEmpty else {
            return "(none)"
        }

        return values.joined(separator: ", ")
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        return value
    }
}
