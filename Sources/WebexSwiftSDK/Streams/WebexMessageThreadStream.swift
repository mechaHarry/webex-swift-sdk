import Foundation

public struct WebexMessageThreadEntry: Equatable, Sendable {
    public let id: String
    public let message: WebexMessage?
    public let parentID: String?
    public let childIDs: [String]
    public let effectiveCreated: Date?
    public let isPlaceholderParent: Bool
    public let isDeletedTombstone: Bool

    public init(
        id: String,
        message: WebexMessage?,
        parentID: String?,
        childIDs: [String],
        effectiveCreated: Date?,
        isPlaceholderParent: Bool,
        isDeletedTombstone: Bool = false
    ) {
        self.id = id
        self.message = message
        self.parentID = parentID
        self.childIDs = childIDs
        self.effectiveCreated = effectiveCreated
        self.isPlaceholderParent = isPlaceholderParent
        self.isDeletedTombstone = isDeletedTombstone
    }
}

public struct WebexMessageThreadSnapshot: Equatable, Sendable {
    public let topLevelMessageIDs: [String]
    public let threadEntryByID: [String: WebexMessageThreadEntry]
    public let chronologicalMessageIDs: [String]
    public let revision: UInt64
    public let lastUpdatedAt: Date?
    public let isRefreshing: Bool
    public let isLoadingNextPage: Bool
    public let lastError: WebexSDKError?
    public let pagination: WebexStreamPagination

    public init(
        topLevelMessageIDs: [String],
        threadEntryByID: [String: WebexMessageThreadEntry],
        chronologicalMessageIDs: [String],
        revision: UInt64,
        lastUpdatedAt: Date?,
        isRefreshing: Bool,
        isLoadingNextPage: Bool,
        lastError: WebexSDKError?,
        pagination: WebexStreamPagination
    ) {
        self.topLevelMessageIDs = topLevelMessageIDs
        self.threadEntryByID = threadEntryByID
        self.chronologicalMessageIDs = chronologicalMessageIDs
        self.revision = revision
        self.lastUpdatedAt = lastUpdatedAt
        self.isRefreshing = isRefreshing
        self.isLoadingNextPage = isLoadingNextPage
        self.lastError = lastError
        self.pagination = pagination
    }

    public init(flatSnapshot: WebexStreamSnapshot<WebexMessage>) {
        self.init(flatSnapshot: flatSnapshot, deletedTombstones: [:])
    }

    fileprivate init(
        flatSnapshot: WebexStreamSnapshot<WebexMessage>,
        deletedTombstones: [String: WebexDeletedMessageTombstone]
    ) {
        let projection = WebexMessageThreadProjection(
            messages: flatSnapshot.items,
            deletedTombstones: deletedTombstones
        )
        self.init(
            topLevelMessageIDs: projection.topLevelMessageIDs,
            threadEntryByID: projection.threadEntryByID,
            chronologicalMessageIDs: projection.chronologicalMessageIDs,
            revision: flatSnapshot.revision,
            lastUpdatedAt: flatSnapshot.lastUpdatedAt,
            isRefreshing: flatSnapshot.isRefreshing,
            isLoadingNextPage: flatSnapshot.isLoadingNextPage,
            lastError: flatSnapshot.lastError,
            pagination: flatSnapshot.pagination
        )
    }
}

public final class MessagesThreadStream: @unchecked Sendable {
    private let flatStream: MessagesStream
    private let state = MessagesThreadStreamState()

    public var snapshots: AsyncStream<WebexMessageThreadSnapshot> {
        let flatSnapshots = flatStream.snapshots
        let state = state
        return AsyncStream { continuation in
            let task = Task {
                for await flatSnapshot in flatSnapshots {
                    guard !Task.isCancelled else {
                        continuation.finish()
                        return
                    }
                    continuation.yield(await state.threadSnapshot(from: flatSnapshot))
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    public init(flatStream: MessagesStream) {
        self.flatStream = flatStream
    }

    public func currentSnapshot() async -> WebexMessageThreadSnapshot {
        await state.threadSnapshot(from: await flatStream.currentSnapshot())
    }

    public func refresh() async {
        await flatStream.refresh()
    }

    public func loadNextPage() async {
        await flatStream.loadNextPage()
    }

    public func refreshOnTriggers(
        _ triggers: AsyncStream<WebexStreamTrigger>,
        where shouldRefresh: @escaping @Sendable (WebexStreamTrigger) -> Bool = { _ in true }
    ) -> Task<Void, Never> {
        Task { [weak self] in
            for await trigger in triggers {
                guard !Task.isCancelled else {
                    return
                }

                guard shouldRefresh(trigger) else {
                    continue
                }

                guard let self else {
                    return
                }

                if Self.isDeletedMessageTrigger(trigger) {
                    await state.recordDeletedMessage(
                        from: trigger,
                        flatSnapshot: await flatStream.currentSnapshot()
                    )
                }

                await flatStream.refresh()
            }
        }
    }

    private static func isDeletedMessageTrigger(_ trigger: WebexStreamTrigger) -> Bool {
        trigger.resource == WebexRealtimeResource.messages.rawValue
            && WebexRealtimeEventName(rawValue: trigger.event) == .deleted
    }
}

private actor MessagesThreadStreamState {
    private var deletedTombstones: [String: WebexDeletedMessageTombstone] = [:]

    func threadSnapshot(from flatSnapshot: WebexStreamSnapshot<WebexMessage>) -> WebexMessageThreadSnapshot {
        WebexMessageThreadSnapshot(
            flatSnapshot: flatSnapshot,
            deletedTombstones: deletedTombstones
        )
    }

    func recordDeletedMessage(
        from trigger: WebexStreamTrigger,
        flatSnapshot: WebexStreamSnapshot<WebexMessage>
    ) {
        guard let deletedResourceID = trigger.resourceID,
              let deletedMessage = flatSnapshot.items.first(where: { message in
                  WebexMessageIDMatcher.matches(message.id, deletedResourceID)
              }) else {
            return
        }

        deletedTombstones[deletedMessage.id] = WebexDeletedMessageTombstone(
            id: deletedMessage.id,
            parentID: deletedMessage.parentID,
            effectiveCreated: deletedMessage.created
        )
    }
}

private struct WebexDeletedMessageTombstone: Equatable, Sendable {
    let id: String
    let parentID: String?
    let effectiveCreated: Date?
}

private struct WebexMessageThreadProjection {
    let topLevelMessageIDs: [String]
    let threadEntryByID: [String: WebexMessageThreadEntry]
    let chronologicalMessageIDs: [String]

    init(
        messages: [WebexMessage],
        deletedTombstones: [String: WebexDeletedMessageTombstone] = [:]
    ) {
        var builder = Builder(
            messages: messages,
            deletedTombstones: deletedTombstones
        )
        builder.indexEntries()
        builder.attachParents()
        builder.cacheEffectiveCreatedDates()
        builder.sortChildren()

        self.topLevelMessageIDs = builder.topLevelMessageIDs
        self.threadEntryByID = builder.threadEntryByID
        self.chronologicalMessageIDs = builder.chronologicalMessageIDs
    }

    private struct Builder {
        private let messages: [WebexMessage]
        private let deletedTombstones: [String: WebexDeletedMessageTombstone]
        private var partialEntryByID: [String: PartialEntry] = [:]
        private var parentByID: [String: String] = [:]
        private var effectiveCreatedByID: [String: Date] = [:]
        private var indexedIDs: [String] = []

        init(
            messages: [WebexMessage],
            deletedTombstones: [String: WebexDeletedMessageTombstone]
        ) {
            self.messages = messages
            self.deletedTombstones = deletedTombstones
        }

        var topLevelMessageIDs: [String] {
            sortedTopLevelIDs()
        }

        var threadEntryByID: [String: WebexMessageThreadEntry] {
            finalEntries()
        }

        var chronologicalMessageIDs: [String] {
            sortedChronologicalMessageIDs()
        }

        mutating func indexEntries() {
            for message in messages {
                guard deletedTombstones[message.id] == nil else {
                    continue
                }

                partialEntryByID[message.id] = PartialEntry(
                    id: message.id,
                    message: message,
                    sourceParentID: message.parentID,
                    parentID: nil,
                    childIDs: [],
                    effectiveCreatedOverride: nil,
                    isPlaceholderParent: false,
                    isDeletedTombstone: false
                )
                indexedIDs.append(message.id)
            }

            for tombstone in deletedTombstones.values.sorted(by: compareTombstones) {
                partialEntryByID[tombstone.id] = PartialEntry(
                    id: tombstone.id,
                    message: nil,
                    sourceParentID: tombstone.parentID,
                    parentID: nil,
                    childIDs: [],
                    effectiveCreatedOverride: tombstone.effectiveCreated,
                    isPlaceholderParent: false,
                    isDeletedTombstone: true
                )
                indexedIDs.append(tombstone.id)
            }
        }

        mutating func attachParents() {
            for id in indexedIDs {
                guard let entry = partialEntryByID[id],
                      let parentID = normalizedParentID(entry.sourceParentID, childID: id) else {
                    continue
                }

                guard !wouldCreateCycle(childID: id, parentID: parentID) else {
                    continue
                }

                parentByID[id] = parentID
                if partialEntryByID[parentID] == nil {
                    partialEntryByID[parentID] = PartialEntry(
                        id: parentID,
                        message: nil,
                        sourceParentID: nil,
                        parentID: nil,
                        childIDs: [],
                        effectiveCreatedOverride: nil,
                        isPlaceholderParent: true,
                        isDeletedTombstone: false
                    )
                }

                var child = partialEntryByID[id]
                child?.parentID = parentID
                partialEntryByID[id] = child

                var parent = partialEntryByID[parentID]
                parent?.childIDs.append(id)
                partialEntryByID[parentID] = parent
            }
        }

        mutating func cacheEffectiveCreatedDates() {
            for id in partialEntryByID.keys {
                _ = effectiveCreated(for: id)
            }
        }

        mutating func sortChildren() {
            for id in partialEntryByID.keys {
                var entry = partialEntryByID[id]
                entry?.childIDs.sort { left, right in
                    compareIDs(left, right)
                }
                partialEntryByID[id] = entry
            }
        }

        private func sortedTopLevelIDs() -> [String] {
            partialEntryByID.keys
                .filter { partialEntryByID[$0]?.parentID == nil }
                .sorted { left, right in
                    compareIDs(left, right)
                }
        }

        private func sortedChronologicalMessageIDs() -> [String] {
            indexedIDs.uniqued().sorted { left, right in
                compareDates(
                    leftDate: effectiveCreatedByID[left],
                    leftID: left,
                    rightDate: effectiveCreatedByID[right],
                    rightID: right
                )
            }
        }

        private func finalEntries() -> [String: WebexMessageThreadEntry] {
            var entries: [String: WebexMessageThreadEntry] = [:]
            for id in partialEntryByID.keys {
                guard let partial = partialEntryByID[id] else {
                    continue
                }

                entries[id] = WebexMessageThreadEntry(
                    id: partial.id,
                    message: partial.message,
                    parentID: partial.parentID,
                    childIDs: partial.childIDs,
                    effectiveCreated: effectiveCreatedByID[id],
                    isPlaceholderParent: partial.isPlaceholderParent,
                    isDeletedTombstone: partial.isDeletedTombstone
                )
            }
            return entries
        }

        private func normalizedParentID(_ rawParentID: String?, childID: String) -> String? {
            guard let parentID = rawParentID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !parentID.isEmpty,
                  parentID != childID else {
                return nil
            }

            return parentID
        }

        private func wouldCreateCycle(childID: String, parentID: String) -> Bool {
            var visited = Set<String>([childID])
            var currentID = parentID

            while true {
                if currentID == childID {
                    return true
                }
                guard visited.insert(currentID).inserted else {
                    return true
                }
                guard let nextID = parentByID[currentID] else {
                    return false
                }
                currentID = nextID
            }
        }

        private func compareIDs(_ left: String, _ right: String) -> Bool {
            compareDates(
                leftDate: effectiveCreatedByID[left],
                leftID: left,
                rightDate: effectiveCreatedByID[right],
                rightID: right
            )
        }

        private func compareDates(
            leftDate: Date?,
            leftID: String,
            rightDate: Date?,
            rightID: String
        ) -> Bool {
            switch (leftDate, rightDate) {
            case (.some(let leftDate), .some(let rightDate)):
                if leftDate == rightDate {
                    return leftID < rightID
                }
                return leftDate < rightDate
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return leftID < rightID
            }
        }

        private mutating func effectiveCreated(for id: String) -> Date? {
            if let cached = effectiveCreatedByID[id] {
                return cached
            }

            guard let entry = partialEntryByID[id] else {
                return nil
            }

            if let created = entry.message?.created {
                effectiveCreatedByID[id] = created
                return created
            }

            if let created = entry.effectiveCreatedOverride {
                effectiveCreatedByID[id] = created
                return created
            }

            var descendantDates: [Date] = []
            for childID in entry.childIDs {
                if let created = effectiveCreated(for: childID) {
                    descendantDates.append(created)
                }
            }
            let effectiveCreated = descendantDates.min()
            if let effectiveCreated {
                effectiveCreatedByID[id] = effectiveCreated
            }
            return effectiveCreated
        }

        private func compareTombstones(
            _ left: WebexDeletedMessageTombstone,
            _ right: WebexDeletedMessageTombstone
        ) -> Bool {
            compareDates(
                leftDate: left.effectiveCreated,
                leftID: left.id,
                rightDate: right.effectiveCreated,
                rightID: right.id
            )
        }
    }

    private struct PartialEntry {
        let id: String
        let message: WebexMessage?
        let sourceParentID: String?
        var parentID: String?
        var childIDs: [String]
        let effectiveCreatedOverride: Date?
        let isPlaceholderParent: Bool
        let isDeletedTombstone: Bool
    }
}

private enum WebexMessageIDMatcher {
    static func matches(_ left: String, _ right: String) -> Bool {
        !idCandidates(left).isDisjoint(with: idCandidates(right))
    }

    private static func idCandidates(_ value: String) -> Set<String> {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        var candidates = Set([trimmed])
        guard let decoded = base64DecodedString(trimmed) else {
            return candidates
        }

        candidates.insert(decoded)
        if let terminalComponent = decoded.split(separator: "/").last {
            candidates.insert(String(terminalComponent))
        }
        return candidates
    }

    private static func base64DecodedString(_ value: String) -> String? {
        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - normalized.count % 4) % 4
        if padding > 0 {
            normalized.append(String(repeating: "=", count: padding))
        }

        guard let data = Data(base64Encoded: normalized),
              let decoded = String(data: data, encoding: .utf8),
              !decoded.isEmpty else {
            return nil
        }

        return decoded
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
