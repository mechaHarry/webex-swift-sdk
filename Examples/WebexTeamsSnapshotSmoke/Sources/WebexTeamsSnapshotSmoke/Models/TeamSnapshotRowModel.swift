import Foundation
import WebexSwiftSDK

struct TeamSnapshotRowModel: Equatable, Identifiable {
    let id: String
    let title: String
    let shortID: String
    let createdText: String
    let additionalFieldsText: String

    init(team: WebexTeam) {
        self.id = team.id
        self.title = Self.display(team.name, fallback: "(unnamed team)")
        self.shortID = Self.shortID(team.id)
        self.createdText = Self.date(team.created)
        self.additionalFieldsText = "\(team.additionalFields.count) extra fields"
    }

    private static func display(_ value: String?, fallback: String) -> String {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return fallback
        }
        return trimmed
    }

    private static func shortID(_ id: String) -> String {
        guard id.count > 11 else {
            return id
        }

        return "\(id.prefix(8))..."
    }

    private static func date(_ date: Date?) -> String {
        guard let date else {
            return "(nil)"
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
