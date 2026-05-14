import Foundation

public typealias MessagesStream = WebexSnapshotStream<WebexMessage>
public typealias MembershipsStream = WebexSnapshotStream<WebexMembership>
public typealias TeamsStream = WebexSnapshotStream<WebexTeam>

public extension SpacesAPI {
    func stream(
        params: ListSpacesParams = ListSpacesParams(),
        pageLimit: Int? = nil
    ) -> SpacesStream {
        let baseStream = WebexSnapshotStream(
            pageLimit: pageLimit,
            id: { $0.id },
            loadFirstPage: {
                let page = try await list(params: params)
                return WebexStreamPage(items: page.items, nextPage: page.nextPage)
            },
            loadNextPage: { nextPage in
                let page = try await list(nextPage: nextPage)
                return WebexStreamPage(items: page.items, nextPage: page.nextPage)
            }
        )
        let teamsAPI = TeamsAPI(transport: transport)
        let peopleAPI = PeopleAPI(transport: transport)
        let membershipsAPI = MembershipsAPI(transport: transport)
        let dependencies = WebexSpaceEnrichmentCoordinator.Dependencies(
            getTeam: { teamID in
                try await teamsAPI.get(teamID: teamID)
            },
            getSelf: {
                try await peopleAPI.me()
            },
            listMemberships: { spaceID in
                try await membershipsAPI.list(params: ListMembershipsParams(roomID: spaceID)).items
            },
            getPerson: { personID in
                try await peopleAPI.get(personID: personID)
            }
        )
        return SpacesStream(
            baseStream: baseStream,
            enricher: WebexSpaceEnrichmentCoordinator(dependencies: dependencies)
        )
    }
}

public extension MessagesAPI {
    func stream(
        params: ListMessagesParams,
        pageLimit: Int? = nil
    ) -> MessagesStream {
        WebexSnapshotStream(
            pageLimit: pageLimit,
            id: { $0.id },
            loadFirstPage: {
                let page = try await list(params: params)
                return WebexStreamPage(items: page.items, nextPage: page.nextPage)
            },
            loadNextPage: { nextPage in
                let page = try await list(nextPage: nextPage)
                return WebexStreamPage(items: page.items, nextPage: page.nextPage)
            }
        )
    }

    func threadedStream(
        params: ListMessagesParams,
        pageLimit: Int? = nil
    ) -> MessagesThreadStream {
        MessagesThreadStream(flatStream: stream(params: params, pageLimit: pageLimit))
    }
}

public extension TeamsAPI {
    func stream(
        params: ListTeamsParams = ListTeamsParams(),
        pageLimit: Int? = nil
    ) -> TeamsStream {
        WebexSnapshotStream(
            pageLimit: pageLimit,
            id: { $0.id },
            loadFirstPage: {
                let page = try await list(params: params)
                return WebexStreamPage(items: page.items, nextPage: page.nextPage)
            },
            loadNextPage: { nextPage in
                let page = try await list(nextPage: nextPage)
                return WebexStreamPage(items: page.items, nextPage: page.nextPage)
            }
        )
    }
}

public extension MembershipsAPI {
    func stream(
        params: ListMembershipsParams = ListMembershipsParams(),
        pageLimit: Int? = nil
    ) -> MembershipsStream {
        WebexSnapshotStream(
            pageLimit: pageLimit,
            id: { $0.id },
            loadFirstPage: {
                let page = try await list(params: params)
                return WebexStreamPage(items: page.items, nextPage: page.nextPage)
            },
            loadNextPage: { nextPage in
                let page = try await list(nextPage: nextPage)
                return WebexStreamPage(items: page.items, nextPage: page.nextPage)
            }
        )
    }
}
