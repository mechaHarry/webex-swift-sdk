import Foundation
import Combine
import WebexSwiftSDK

@MainActor
final class MessagesStreamWindowModel: ObservableObject {
    typealias StreamFactory = @Sendable () async throws -> MessagesStream

    @Published private(set) var rows: [MessageRowModel] = []
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var revision: UInt64 = 0
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingNextPage = false
    @Published private(set) var hasMore = false
    @Published private(set) var capReached = false
    @Published private(set) var lastUpdatedText = "Never"
    @Published private(set) var lastErrorText: String?

    private let streamFactory: StreamFactory
    private var stream: MessagesStream?
    private var subscriptionTask: Task<Void, Never>?

    init(streamFactory: @escaping StreamFactory) {
        self.streamFactory = streamFactory
    }

    deinit {
        subscriptionTask?.cancel()
    }

    var canRefresh: Bool {
        stream != nil && !isRefreshing
    }

    func start() async {
        guard stream == nil else {
            return
        }

        phase = .authorizing
        do {
            let stream = try await streamFactory()
            self.stream = stream
            subscribe(to: stream)
            phase = .ready
            await stream.refresh()
        } catch {
            phase = .failed(Self.safeDescription(for: error))
        }
    }

    func refresh() async {
        guard let stream else {
            return
        }

        await stream.refresh()
    }

    private func subscribe(to stream: MessagesStream) {
        subscriptionTask?.cancel()
        subscriptionTask = Task { [weak self] in
            for await snapshot in stream.snapshots {
                self?.apply(snapshot)
            }
        }
    }

    private func apply(_ snapshot: WebexStreamSnapshot<WebexMessage>) {
        rows = snapshot.items.map(MessageRowModel.init)
        revision = snapshot.revision
        isRefreshing = snapshot.isRefreshing
        isLoadingNextPage = snapshot.isLoadingNextPage
        hasMore = snapshot.pagination.hasMore
        capReached = snapshot.pagination.capReached
        lastUpdatedText = Self.lastUpdatedText(from: snapshot.lastUpdatedAt)
        lastErrorText = snapshot.lastError.map(Self.safeDescription)
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
