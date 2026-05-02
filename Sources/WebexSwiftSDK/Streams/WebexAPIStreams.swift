import Foundation

public typealias SpacesStream = WebexSnapshotStream<WebexSpace>
public typealias RoomsStream = SpacesStream
public typealias MessagesStream = WebexSnapshotStream<WebexMessage>
public typealias MembershipsStream = WebexSnapshotStream<WebexMembership>

public extension SpacesAPI {
    func stream(
        params: ListSpacesParams = ListSpacesParams(),
        pageLimit: Int? = nil
    ) -> SpacesStream {
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
