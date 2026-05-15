import Foundation
import WebexSwiftSDK

struct FieldDisplay: Equatable, Identifiable {
    let name: String
    let value: String

    var id: String {
        name
    }
}

struct TeamSnapshotDetailModel: Equatable, Identifiable {
    let id: String
    let title: String
    let documentedFields: [FieldDisplay]
    let additionalFields: [FieldDisplay]

    var hasAdditionalFields: Bool {
        additionalFields != [Self.emptyAdditionalFieldsDisplay]
    }

    init(team: WebexTeam) {
        self.id = team.id
        self.title = Self.display(team.name, fallback: "(unnamed team)")
        self.documentedFields = [
            FieldDisplay(name: "id", value: team.id),
            FieldDisplay(name: "name", value: Self.optional(team.name)),
            FieldDisplay(name: "creatorID", value: Self.optional(team.creatorID)),
            FieldDisplay(name: "created", value: Self.iso8601(team.created))
        ]
        self.additionalFields = Self.additionalFields(team.additionalFields)
    }

    private static let emptyAdditionalFieldsDisplay = FieldDisplay(
        name: "additionalFields",
        value: "(none returned)"
    )

    private static func additionalFields(_ fields: [String: WebexJSONValue]) -> [FieldDisplay] {
        guard !fields.isEmpty else {
            return [emptyAdditionalFieldsDisplay]
        }

        return fields.keys.sorted().map { key in
            FieldDisplay(
                name: "additionalFields.\(key)",
                value: jsonText(fields[key] ?? .null)
            )
        }
    }

    private static func display(_ value: String?, fallback: String) -> String {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return fallback
        }
        return trimmed
    }

    private static func optional(_ value: String?) -> String {
        display(value, fallback: "(nil)")
    }

    private static func iso8601(_ date: Date?) -> String {
        guard let date else {
            return "(nil)"
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func jsonText(_ value: WebexJSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return "(unencodable)"
        }

        return text
    }
}
