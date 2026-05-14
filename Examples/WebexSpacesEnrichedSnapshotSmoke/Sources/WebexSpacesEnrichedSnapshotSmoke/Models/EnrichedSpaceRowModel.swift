import Foundation
import WebexSwiftSDK

struct EnrichedSpaceRowModel: Identifiable, Equatable {
    let id: String
    let title: String
    let typeText: String
    let enrichmentStatusText: String
    let enrichmentSummary: String
    let systemImageName: String

    init(space: WebexSpace) {
        self.id = space.id
        self.title = Self.display(space.title, fallback: "(untitled space)")
        self.typeText = space.type?.rawValue ?? "(nil)"
        self.enrichmentStatusText = Self.statusText(space.enriched.status)
        self.enrichmentSummary = Self.enrichmentSummary(for: space)
        self.systemImageName = space.type == .direct ? "person.crop.circle" : "rectangle.3.group"
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

    private static func enrichmentSummary(for space: WebexSpace) -> String {
        if !space.enriched.errors.isEmpty {
            let count = space.enriched.errors.count
            return count == 1 ? "1 enrichment error" : "\(count) enrichment errors"
        }

        if let teamName = displayOptional(space.enriched.teamName) {
            return teamName
        }

        if displayOptional(space.enriched.spaceAvatar) != nil {
            return "Avatar available"
        }

        switch space.enriched.status {
        case .empty:
            return "No enrichment"
        case .loading:
            return "Loading enrichment"
        case .complete:
            return "Enrichment complete"
        case .partial:
            return "Partial enrichment"
        case .failed:
            return "Enrichment failed"
        }
    }

    private static func display(_ value: String?, fallback: String) -> String {
        displayOptional(value) ?? fallback
    }

    private static func displayOptional(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
