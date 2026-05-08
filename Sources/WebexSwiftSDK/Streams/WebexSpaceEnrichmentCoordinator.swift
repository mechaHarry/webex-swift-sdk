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

    private enum OtherPersonCache: Equatable, Sendable {
        case personID(String)
        case missing
    }

    private enum BatchLookup<Value: Sendable>: Sendable {
        case value(Value)
        case failure(WebexSpaceEnrichmentError)
    }

    private let dependencies: Dependencies
    private var teamNameByID: [String: String?] = [:]
    private var selfPersonID: String?
    private var otherPersonIDBySpaceID: [String: OtherPersonCache] = [:]
    private var spaceAvatarErrorBySpaceID: [String: WebexSpaceEnrichmentError] = [:]
    private var avatarByPersonID: [String: String?] = [:]

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func seedDirectSpaceAvatarCacheForTesting(
        spaceID: String,
        personID: String,
        avatar: String?,
        error: WebexSpaceEnrichmentError
    ) {
        otherPersonIDBySpaceID[spaceID] = .personID(personID)
        avatarByPersonID[personID] = avatar
        spaceAvatarErrorBySpaceID[spaceID] = error
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
                if let cachedError = spaceAvatarErrorBySpaceID[space.id] {
                    values.errors.append(cachedError)
                } else if case .personID(let otherPersonID) = otherPersonIDBySpaceID[space.id],
                          let cachedAvatar = avatarByPersonID[otherPersonID] {
                    values.spaceAvatar = cachedAvatar
                } else if otherPersonIDBySpaceID[space.id] == .missing {
                    values.errors.append(missingDirectSpaceParticipantError())
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
        forceRefresh: Bool,
        shouldCommitCache: @escaping @Sendable () async -> Bool = { true }
    ) async -> [WebexSpace] {
        var enriched: [WebexSpace] = []
        enriched.reserveCapacity(spaces.count)
        var batchTeamNameByID: [String: BatchLookup<String?>] = [:]
        var batchSelfPersonID: BatchLookup<String>?
        var batchAvatarByPersonID: [String: BatchLookup<String?>] = [:]

        for space in spaces {
            let applicable = applicableFields(for: space)
            guard !applicable.isEmpty else {
                enriched.append(space.replacingEnrichment(.empty))
                continue
            }

            var values = FieldValues()

            if applicable.contains(.teamName), let teamID = space.teamID {
                await resolveTeamName(
                    teamID: teamID,
                    forceRefresh: forceRefresh,
                    shouldCommitCache: shouldCommitCache,
                    batchTeamNameByID: &batchTeamNameByID,
                    values: &values
                )
            }

            if applicable.contains(.spaceAvatar) {
                await resolveSpaceAvatar(
                    spaceID: space.id,
                    forceRefresh: forceRefresh,
                    shouldCommitCache: shouldCommitCache,
                    batchSelfPersonID: &batchSelfPersonID,
                    batchAvatarByPersonID: &batchAvatarByPersonID,
                    values: &values
                )
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
        shouldCommitCache: @escaping @Sendable () async -> Bool,
        batchTeamNameByID: inout [String: BatchLookup<String?>],
        values: inout FieldValues
    ) async {
        if let lookup = batchTeamNameByID[teamID] {
            switch lookup {
            case .value(let teamName):
                values.teamName = teamName
            case .failure(let error):
                values.errors.append(error)
            }
            return
        }

        if !forceRefresh, let cached = teamNameByID[teamID] {
            values.teamName = cached
            return
        }

        do {
            let team = try await dependencies.getTeam(teamID)
            batchTeamNameByID[teamID] = .value(team.name)
            if await shouldCommitCache() {
                teamNameByID[teamID] = team.name
            }
            values.teamName = team.name
        } catch {
            let fieldError = teamNameError(from: error)
            batchTeamNameByID[teamID] = .failure(fieldError)
            values.errors.append(fieldError)
        }
    }

    private func resolveSpaceAvatar(
        spaceID: String,
        forceRefresh: Bool,
        shouldCommitCache: @escaping @Sendable () async -> Bool,
        batchSelfPersonID: inout BatchLookup<String>?,
        batchAvatarByPersonID: inout [String: BatchLookup<String?>],
        values: inout FieldValues
    ) async {
        do {
            let otherPersonID = try await otherPersonID(
                for: spaceID,
                forceRefresh: forceRefresh,
                shouldCommitCache: shouldCommitCache,
                batchSelfPersonID: &batchSelfPersonID
            )
            guard let otherPersonID else {
                let error = missingDirectSpaceParticipantError()
                if await shouldCommitCache() {
                    spaceAvatarErrorBySpaceID[spaceID] = error
                }
                values.errors.append(error)
                return
            }

            if let lookup = batchAvatarByPersonID[otherPersonID] {
                switch lookup {
                case .value(let avatar):
                    if await shouldCommitCache() {
                        spaceAvatarErrorBySpaceID[spaceID] = nil
                        avatarByPersonID[otherPersonID] = avatar
                    }
                    values.spaceAvatar = avatar
                case .failure(let error):
                    values.errors.append(error)
                }
                return
            }

            if !forceRefresh, let cached = avatarByPersonID[otherPersonID] {
                if await shouldCommitCache() {
                    spaceAvatarErrorBySpaceID[spaceID] = nil
                }
                values.spaceAvatar = cached
                return
            }

            do {
                let person = try await dependencies.getPerson(otherPersonID)
                batchAvatarByPersonID[otherPersonID] = .value(person.avatar)
                if await shouldCommitCache() {
                    spaceAvatarErrorBySpaceID[spaceID] = nil
                    avatarByPersonID[otherPersonID] = person.avatar
                }
                values.spaceAvatar = person.avatar
            } catch {
                let fieldError = spaceAvatarError(from: error)
                batchAvatarByPersonID[otherPersonID] = .failure(fieldError)
                values.errors.append(fieldError)
            }
        } catch {
            values.errors.append(spaceAvatarError(from: error))
        }
    }

    private func otherPersonID(
        for spaceID: String,
        forceRefresh: Bool,
        shouldCommitCache: @escaping @Sendable () async -> Bool,
        batchSelfPersonID: inout BatchLookup<String>?
    ) async throws -> String? {
        if !forceRefresh {
            switch otherPersonIDBySpaceID[spaceID] {
            case .personID(let cachedPersonID):
                return cachedPersonID
            case .missing:
                return nil
            case nil:
                break
            }
        }

        let selfID: String
        if !forceRefresh, let cachedSelfPersonID = selfPersonID {
            selfID = cachedSelfPersonID
        } else if let batchSelfPersonID {
            switch batchSelfPersonID {
            case .value(let cachedSelfPersonID):
                selfID = cachedSelfPersonID
            case .failure(let error):
                throw error.error
            }
        } else {
            let me: WebexPerson
            do {
                me = try await dependencies.getSelf()
            } catch {
                let fieldError = spaceAvatarError(from: error)
                batchSelfPersonID = .failure(fieldError)
                throw fieldError.error
            }
            batchSelfPersonID = .value(me.id)
            if await shouldCommitCache() {
                selfPersonID = me.id
            }
            selfID = me.id
        }

        let memberships = try await dependencies.listMemberships(spaceID)
        let otherPersonID = memberships
            .compactMap(\.personID)
            .first { $0 != selfID }

        if await shouldCommitCache() {
            if let otherPersonID {
                otherPersonIDBySpaceID[spaceID] = .personID(otherPersonID)
            } else {
                otherPersonIDBySpaceID[spaceID] = .missing
            }
        }
        return otherPersonID
    }

    private func teamNameError(from error: Error) -> WebexSpaceEnrichmentError {
        WebexSpaceEnrichmentError(
            field: .teamName,
            error: WebexStreamErrorRedactor.webexStreamError(from: error)
        )
    }

    private func spaceAvatarError(from error: Error) -> WebexSpaceEnrichmentError {
        WebexSpaceEnrichmentError(
            field: .spaceAvatar,
            error: WebexStreamErrorRedactor.webexStreamError(from: error)
        )
    }

    private func missingDirectSpaceParticipantError() -> WebexSpaceEnrichmentError {
        WebexSpaceEnrichmentError(
            field: .spaceAvatar,
            error: WebexStreamErrorRedactor.webexStreamError(
                from: WebexSDKError.network("Missing direct space participant")
            )
        )
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

        let failedFields = values.errors.count

        if failedFields == 0 {
            return .complete
        }

        if failedFields == applicableFields.count {
            return .failed
        }

        return .partial
    }
}
