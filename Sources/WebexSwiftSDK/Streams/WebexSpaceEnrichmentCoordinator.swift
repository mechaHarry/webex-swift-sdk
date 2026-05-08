import Foundation

actor WebexSpaceEnrichmentCoordinator {
    struct Dependencies: Sendable {
        let getTeam: @Sendable (String) async throws -> WebexTeam
        let getSelf: @Sendable () async throws -> WebexPerson
        let listMemberships: @Sendable (String) async throws -> [WebexMembership]
        let getPerson: @Sendable (String) async throws -> WebexPerson
    }

    private struct FieldValues: Equatable, Sendable {
        var teamName: String?
        var spaceAvatar: String?
        var errors: [WebexSpaceEnrichmentError] = []
    }

    private let dependencies: Dependencies
    private var teamNameByID: [String: String?] = [:]
    private var selfPersonID: String?
    private var otherPersonIDBySpaceID: [String: String?] = [:]
    private var avatarByPersonID: [String: String?] = [:]

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func immediateItems(
        for spaces: [WebexSpace],
        forceRefresh: Bool
    ) -> [WebexSpace] {
        spaces.map { space in
            let applicable = applicableFields(for: space)
            guard !applicable.isEmpty else {
                return space.replacingEnrichment(.empty)
            }

            if forceRefresh {
                return space.replacingEnrichment(WebexSpaceEnrichment(status: .loading))
            }

            var values = FieldValues()
            var pending = false

            if applicable.contains(.teamName), let teamID = space.teamID {
                if let cached = teamNameByID[teamID] {
                    values.teamName = cached
                } else {
                    pending = true
                }
            }

            if applicable.contains(.spaceAvatar) {
                if let cachedOtherPersonID = otherPersonIDBySpaceID[space.id],
                   let otherPersonID = cachedOtherPersonID,
                   let cachedAvatar = avatarByPersonID[otherPersonID] {
                    values.spaceAvatar = cachedAvatar
                } else {
                    pending = true
                }
            }

            let status = status(
                applicableFields: applicable,
                values: values,
                hasPendingWork: pending
            )
            return space.replacingEnrichment(WebexSpaceEnrichment(
                teamName: values.teamName,
                spaceAvatar: values.spaceAvatar,
                status: status,
                errors: values.errors
            ))
        }
    }

    func enrichedItems(
        for spaces: [WebexSpace],
        forceRefresh: Bool
    ) async -> [WebexSpace] {
        var enriched: [WebexSpace] = []
        enriched.reserveCapacity(spaces.count)

        for space in spaces {
            let applicable = applicableFields(for: space)
            guard !applicable.isEmpty else {
                enriched.append(space.replacingEnrichment(.empty))
                continue
            }

            var values = FieldValues()

            if applicable.contains(.teamName), let teamID = space.teamID {
                await resolveTeamName(teamID: teamID, forceRefresh: forceRefresh, values: &values)
            }

            if applicable.contains(.spaceAvatar) {
                await resolveSpaceAvatar(spaceID: space.id, forceRefresh: forceRefresh, values: &values)
            }

            enriched.append(space.replacingEnrichment(WebexSpaceEnrichment(
                teamName: values.teamName,
                spaceAvatar: values.spaceAvatar,
                status: status(
                    applicableFields: applicable,
                    values: values,
                    hasPendingWork: false
                ),
                errors: values.errors
            )))
        }

        return enriched
    }

    private func resolveTeamName(
        teamID: String,
        forceRefresh: Bool,
        values: inout FieldValues
    ) async {
        if !forceRefresh, let cached = teamNameByID[teamID] {
            values.teamName = cached
            return
        }

        do {
            let team = try await dependencies.getTeam(teamID)
            teamNameByID[teamID] = team.name
            values.teamName = team.name
        } catch {
            values.errors.append(WebexSpaceEnrichmentError(
                field: .teamName,
                error: WebexStreamErrorRedactor.webexStreamError(from: error)
            ))
        }
    }

    private func resolveSpaceAvatar(
        spaceID: String,
        forceRefresh: Bool,
        values: inout FieldValues
    ) async {
        do {
            let otherPersonID = try await otherPersonID(for: spaceID, forceRefresh: forceRefresh)
            guard let otherPersonID else {
                values.errors.append(WebexSpaceEnrichmentError(
                    field: .spaceAvatar,
                    error: .network("Missing direct space participant")
                ))
                return
            }

            if !forceRefresh, let cached = avatarByPersonID[otherPersonID] {
                values.spaceAvatar = cached
                return
            }

            let person = try await dependencies.getPerson(otherPersonID)
            avatarByPersonID[otherPersonID] = person.avatar
            values.spaceAvatar = person.avatar
        } catch {
            values.errors.append(WebexSpaceEnrichmentError(
                field: .spaceAvatar,
                error: WebexStreamErrorRedactor.webexStreamError(from: error)
            ))
        }
    }

    private func otherPersonID(
        for spaceID: String,
        forceRefresh: Bool
    ) async throws -> String? {
        if !forceRefresh, let cached = otherPersonIDBySpaceID[spaceID] {
            return cached
        }

        let selfID: String
        if !forceRefresh, let cachedSelfPersonID = selfPersonID {
            selfID = cachedSelfPersonID
        } else {
            let me = try await dependencies.getSelf()
            selfPersonID = me.id
            selfID = me.id
        }

        let memberships = try await dependencies.listMemberships(spaceID)
        let otherPersonID = memberships
            .compactMap(\.personID)
            .first { $0 != selfID }

        otherPersonIDBySpaceID[spaceID] = otherPersonID
        return otherPersonID
    }

    private func applicableFields(for space: WebexSpace) -> Set<WebexSpaceEnrichmentField> {
        var fields: Set<WebexSpaceEnrichmentField> = []
        if space.teamID != nil {
            fields.insert(.teamName)
        }
        if space.type == .direct {
            fields.insert(.spaceAvatar)
        }
        return fields
    }

    private func status(
        applicableFields: Set<WebexSpaceEnrichmentField>,
        values: FieldValues,
        hasPendingWork: Bool
    ) -> WebexSpaceEnrichmentStatus {
        guard !applicableFields.isEmpty else {
            return .empty
        }

        if hasPendingWork {
            return .loading
        }

        let successfulFields = successfulFieldCount(values: values)
        let failedFields = values.errors.count

        if failedFields == 0 {
            return .complete
        }

        if successfulFields > 0 {
            return .partial
        }

        return .failed
    }

    private func successfulFieldCount(values: FieldValues) -> Int {
        var count = 0
        if values.teamName != nil {
            count += 1
        }
        if values.spaceAvatar != nil {
            count += 1
        }
        return count
    }
}
