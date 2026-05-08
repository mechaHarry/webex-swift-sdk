import XCTest
@testable import WebexSwiftSDK

final class WebexSpaceEnrichmentCoordinatorTests: XCTestCase {
    func testImmediateItemsMarkApplicableUncachedFieldsLoading() async {
        let dependencies = RecordingSpaceEnrichmentDependencies()
        let coordinator = WebexSpaceEnrichmentCoordinator(dependencies: dependencies.makeDependencies())
        let spaces = [
            space(id: "team-space", type: .group, teamID: "team-1"),
            space(id: "direct-space", type: .direct)
        ]

        let immediate = await coordinator.immediateItems(for: spaces, forceRefresh: false)

        XCTAssertEqual(immediate[0].enriched.status, .loading)
        XCTAssertNil(immediate[0].enriched.teamName)
        XCTAssertEqual(immediate[0].enriched.errors, [])
        XCTAssertEqual(immediate[1].enriched.status, .loading)
        XCTAssertNil(immediate[1].enriched.spaceAvatar)
        XCTAssertEqual(immediate[1].enriched.errors, [])
    }

    func testEnrichesTeamNameAndCachesAcrossOrdinaryRefreshes() async {
        let dependencies = RecordingSpaceEnrichmentDependencies()
        dependencies.teamByID["team-1"] = WebexTeam(id: "team-1", name: "Platform")
        let coordinator = WebexSpaceEnrichmentCoordinator(dependencies: dependencies.makeDependencies())
        let spaces = [space(id: "team-space", type: .group, teamID: "team-1")]

        let first = await coordinator.enrichedItems(for: spaces, forceRefresh: false)
        let second = await coordinator.enrichedItems(for: spaces, forceRefresh: false)

        XCTAssertEqual(first[0].enriched.teamName, "Platform")
        XCTAssertEqual(first[0].enriched.status, .complete)
        XCTAssertEqual(second[0].enriched.teamName, "Platform")
        XCTAssertEqual(dependencies.teamRequests, ["team-1"])
    }

    func testForceRefreshBypassesCachedTeamName() async {
        let dependencies = RecordingSpaceEnrichmentDependencies()
        dependencies.teamByID["team-1"] = WebexTeam(id: "team-1", name: "Old")
        let coordinator = WebexSpaceEnrichmentCoordinator(dependencies: dependencies.makeDependencies())
        let spaces = [space(id: "team-space", type: .group, teamID: "team-1")]

        let first = await coordinator.enrichedItems(for: spaces, forceRefresh: false)
        dependencies.teamByID["team-1"] = WebexTeam(id: "team-1", name: "New")
        let second = await coordinator.enrichedItems(for: spaces, forceRefresh: true)

        XCTAssertEqual(first[0].enriched.teamName, "Old")
        XCTAssertEqual(second[0].enriched.teamName, "New")
        XCTAssertEqual(dependencies.teamRequests, ["team-1", "team-1"])
    }

    func testDirectSpaceAvatarUsesOtherPersonAvatar() async {
        let dependencies = RecordingSpaceEnrichmentDependencies()
        dependencies.selfPerson = person(id: "self", avatar: "https://example.com/self.png")
        dependencies.membershipsByRoomID["direct-space"] = [
            WebexMembership(id: "m-self", roomID: "direct-space", personID: "self"),
            WebexMembership(id: "m-other", roomID: "direct-space", personID: "other")
        ]
        dependencies.personByID["other"] = person(id: "other", avatar: "https://example.com/other.png")
        let coordinator = WebexSpaceEnrichmentCoordinator(dependencies: dependencies.makeDependencies())

        let enriched = await coordinator.enrichedItems(
            for: [space(id: "direct-space", type: .direct)],
            forceRefresh: false
        )

        XCTAssertEqual(enriched[0].enriched.spaceAvatar, "https://example.com/other.png")
        XCTAssertEqual(enriched[0].enriched.status, .complete)
        XCTAssertEqual(dependencies.meRequests, 1)
        XCTAssertEqual(dependencies.membershipRequests, ["direct-space"])
        XCTAssertEqual(dependencies.personRequests, ["other"])
    }

    func testDirectSpaceAvatarFailureIsFieldScopedAndRedacted() async {
        let dependencies = RecordingSpaceEnrichmentDependencies()
        dependencies.selfPerson = person(id: "self", avatar: nil)
        dependencies.membershipsByRoomID["direct-space"] = [
            WebexMembership(id: "m-self", roomID: "direct-space", personID: "self"),
            WebexMembership(id: "m-other", roomID: "direct-space", personID: "other")
        ]
        dependencies.personErrorByID["other"] = .network("callback code=secret-code")
        let coordinator = WebexSpaceEnrichmentCoordinator(dependencies: dependencies.makeDependencies())

        let enriched = await coordinator.enrichedItems(
            for: [space(id: "direct-space", type: .direct)],
            forceRefresh: false
        )

        XCTAssertNil(enriched[0].enriched.spaceAvatar)
        XCTAssertEqual(enriched[0].enriched.status, .failed)
        XCTAssertEqual(enriched[0].enriched.errors.count, 1)
        XCTAssertEqual(enriched[0].enriched.errors.first?.field, .spaceAvatar)
        XCTAssertEqual(enriched[0].enriched.errors.first?.error, .network("callback code=[redacted]"))
    }

    func testGroupSpaceWithoutTeamHasEmptyEnrichment() async {
        let dependencies = RecordingSpaceEnrichmentDependencies()
        let coordinator = WebexSpaceEnrichmentCoordinator(dependencies: dependencies.makeDependencies())

        let enriched = await coordinator.enrichedItems(
            for: [space(id: "plain-group", type: .group)],
            forceRefresh: false
        )

        XCTAssertEqual(enriched[0].enriched, .empty)
        XCTAssertEqual(dependencies.teamRequests, [])
        XCTAssertEqual(dependencies.membershipRequests, [])
        XCTAssertEqual(dependencies.personRequests, [])
    }
}

private func space(
    id: String,
    type: WebexSpaceType?,
    teamID: String? = nil
) -> WebexSpace {
    WebexSpace(
        id: id,
        title: id,
        type: type,
        teamID: teamID
    )
}

private func person(id: String, avatar: String?) -> WebexPerson {
    WebexPerson(
        id: id,
        emails: ["\(id)@example.com"],
        avatar: avatar
    )
}

private final class RecordingSpaceEnrichmentDependencies: @unchecked Sendable {
    var teamByID: [String: WebexTeam] = [:]
    var teamErrorByID: [String: WebexSDKError] = [:]
    var selfPerson = person(id: "self", avatar: nil)
    var meError: WebexSDKError?
    var membershipsByRoomID: [String: [WebexMembership]] = [:]
    var membershipsErrorByRoomID: [String: WebexSDKError] = [:]
    var personByID: [String: WebexPerson] = [:]
    var personErrorByID: [String: WebexSDKError] = [:]

    private(set) var teamRequests: [String] = []
    private(set) var meRequests = 0
    private(set) var membershipRequests: [String] = []
    private(set) var personRequests: [String] = []

    func makeDependencies() -> WebexSpaceEnrichmentCoordinator.Dependencies {
        WebexSpaceEnrichmentCoordinator.Dependencies(
            getTeam: { [self] teamID in
                teamRequests.append(teamID)
                if let error = teamErrorByID[teamID] {
                    throw error
                }
                return teamByID[teamID] ?? WebexTeam(id: teamID)
            },
            getSelf: { [self] in
                meRequests += 1
                if let meError {
                    throw meError
                }
                return selfPerson
            },
            listMemberships: { [self] roomID in
                membershipRequests.append(roomID)
                if let error = membershipsErrorByRoomID[roomID] {
                    throw error
                }
                return membershipsByRoomID[roomID] ?? []
            },
            getPerson: { [self] personID in
                personRequests.append(personID)
                if let error = personErrorByID[personID] {
                    throw error
                }
                return personByID[personID] ?? person(id: personID, avatar: nil)
            }
        )
    }
}
