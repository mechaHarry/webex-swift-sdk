import Foundation
import WebexSwiftSDK

struct FieldDisplay: Equatable, Identifiable {
    let name: String
    let value: String

    var id: String {
        name
    }
}

struct EnrichedSpaceDetailModel: Equatable, Identifiable {
    let id: String
    let title: String
    let wireFields: [FieldDisplay]
    let enrichedFields: [FieldDisplay]

    init(space: WebexSpace) {
        self.id = space.id
        self.title = Self.display(space.title, fallback: "(untitled space)")
        self.wireFields = [
            FieldDisplay(name: "id", value: space.id),
            FieldDisplay(name: "title", value: Self.optional(space.title)),
            FieldDisplay(name: "type", value: space.type?.rawValue ?? "(nil)"),
            FieldDisplay(name: "teamID", value: Self.optional(space.teamID)),
            FieldDisplay(name: "isLocked", value: Self.optionalBool(space.isLocked)),
            FieldDisplay(name: "isReadOnly", value: Self.optionalBool(space.isReadOnly)),
            FieldDisplay(name: "isAnnouncementOnly", value: Self.optionalBool(space.isAnnouncementOnly)),
            FieldDisplay(name: "lastActivity", value: Self.iso8601(space.lastActivity)),
            FieldDisplay(name: "created", value: Self.iso8601(space.created))
        ]
        self.enrichedFields = [
            FieldDisplay(name: "enriched.teamName", value: Self.optional(space.enriched.teamName)),
            FieldDisplay(name: "enriched.spaceAvatar", value: Self.optional(space.enriched.spaceAvatar)),
            FieldDisplay(name: "enriched.status", value: Self.statusText(space.enriched.status)),
            FieldDisplay(name: "enriched.errors", value: Self.errors(space.enriched.errors))
        ]
    }

    private static func statusText(_ status: WebexSpaceEnrichmentStatus) -> String {
        switch status {
        case .empty:
            return "empty"
        case .loading:
            return "loading"
        case .partial:
            return "partial"
        case .complete:
            return "complete"
        case .failed:
            return "failed"
        }
    }

    private static func fieldText(_ field: WebexSpaceEnrichmentField) -> String {
        switch field {
        case .teamName:
            return "teamName"
        case .spaceAvatar:
            return "spaceAvatar"
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

    private static func optionalBool(_ value: Bool?) -> String {
        guard let value else {
            return "(nil)"
        }
        return String(value)
    }

    private static func iso8601(_ date: Date?) -> String {
        guard let date else {
            return "(nil)"
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func errors(_ errors: [WebexSpaceEnrichmentError]) -> String {
        guard !errors.isEmpty else {
            return "[]"
        }

        return errors
            .map { "\(fieldText($0.field)): \($0.error)" }
            .joined(separator: "\n")
    }
}
