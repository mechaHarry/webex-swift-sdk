import Combine
import Foundation
import WebexSwiftSDK

@MainActor
final class EnrichedSpacesWindowModel: ObservableObject {
    typealias RuntimeFactory = @Sendable () async throws -> EnrichedSpacesRuntime

    @Published private(set) var rows: [EnrichedSpaceRowModel] = []
    @Published private(set) var selectedDetail: EnrichedSpaceDetailModel?
    @Published private(set) var selectedSpaceID: String?
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var revision: UInt64 = 0
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingNextPage = false
    @Published private(set) var hasMore = false
    @Published private(set) var capReached = false
    @Published private(set) var lastUpdatedText = "Never"
    @Published private(set) var lastErrorText: String?

    private let runtimeFactory: RuntimeFactory
    private var runtime: EnrichedSpacesRuntime?
    private var subscriptionTask: Task<Void, Never>?
    private var currentSpaces: [WebexSpace] = []
    private var isStarting = false

    init(runtimeFactory: @escaping RuntimeFactory) {
        self.runtimeFactory = runtimeFactory
    }

    deinit {
        subscriptionTask?.cancel()
        runtime?.cancel()
    }

    var canRefresh: Bool {
        runtime != nil && !isRefreshing
    }

    var canRefreshEnrichment: Bool {
        runtime != nil && !currentSpaces.isEmpty
    }

    var canLoadMore: Bool {
        runtime != nil && hasMore && !capReached && !isLoadingNextPage
    }

    func start() async {
        guard runtime == nil, !isStarting else {
            return
        }

        isStarting = true
        defer {
            isStarting = false
        }

        phase = .authorizing
        do {
            let runtime = try await runtimeFactory()
            self.runtime = runtime
            subscribe(to: runtime.snapshots)
            phase = .ready
            await runtime.refresh()
        } catch {
            phase = .failed(Self.safeDescription(for: error))
        }
    }

    func refresh() async {
        await runtime?.refresh()
    }

    func refreshEnrichment() async {
        await runtime?.refreshEnrichment()
    }

    func loadNextPage() async {
        guard canLoadMore else {
            return
        }
        await runtime?.loadNextPage()
    }

    func select(spaceID: String?) {
        selectedSpaceID = spaceID
        updateSelectedDetail()
    }

    private func subscribe(to snapshots: AsyncStream<WebexStreamSnapshot<WebexSpace>>) {
        subscriptionTask?.cancel()
        subscriptionTask = Task { [weak self] in
            for await snapshot in snapshots {
                self?.apply(snapshot)
            }
        }
    }

    private func apply(_ snapshot: WebexStreamSnapshot<WebexSpace>) {
        currentSpaces = snapshot.items
        rows = snapshot.items.map(EnrichedSpaceRowModel.init)
        revision = snapshot.revision
        isRefreshing = snapshot.isRefreshing
        isLoadingNextPage = snapshot.isLoadingNextPage
        hasMore = snapshot.pagination.hasMore
        capReached = snapshot.pagination.capReached
        lastUpdatedText = Self.lastUpdatedText(from: snapshot.lastUpdatedAt)
        lastErrorText = snapshot.lastError.map(Self.safeDescription)

        if let selectedSpaceID,
           snapshot.items.contains(where: { $0.id == selectedSpaceID }) {
            self.selectedSpaceID = selectedSpaceID
        } else {
            selectedSpaceID = snapshot.items.first?.id
        }
        updateSelectedDetail()
    }

    private func updateSelectedDetail() {
        guard let selectedSpaceID,
              let selected = currentSpaces.first(where: { $0.id == selectedSpaceID }) else {
            selectedDetail = nil
            return
        }
        selectedDetail = EnrichedSpaceDetailModel(space: selected)
    }

    private static func lastUpdatedText(from date: Date?) -> String {
        guard let date else {
            return "Never"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private static func safeDescription(for error: Error) -> String {
        if case WebexSDKError.invalidAuthorizationCallback = error {
            return "Invalid authorization callback"
        }

        return String(describing: error)
    }

    enum Phase: Equatable {
        case idle
        case authorizing
        case ready
        case failed(String)
    }
}
