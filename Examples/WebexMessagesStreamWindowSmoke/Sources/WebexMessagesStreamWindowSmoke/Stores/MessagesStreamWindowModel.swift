import Foundation
import Combine
import WebexSwiftSDK

@MainActor
final class MessagesStreamWindowModel: ObservableObject {
    typealias RuntimeFactory = @Sendable () async throws -> MessageStreamRuntime

    @Published private(set) var rows: [MessageRowModel] = []
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var revision: UInt64 = 0
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingNextPage = false
    @Published private(set) var hasMore = false
    @Published private(set) var capReached = false
    @Published private(set) var lastUpdatedText = "Never"
    @Published private(set) var lastErrorText: String?
    @Published private(set) var realtimeStatusText = "Realtime idle"

    private let runtimeFactory: RuntimeFactory
    private var runtime: MessageStreamRuntime?
    private var subscriptionTask: Task<Void, Never>?
    private var realtimeStateTask: Task<Void, Never>?

    init(runtimeFactory: @escaping RuntimeFactory) {
        self.runtimeFactory = runtimeFactory
    }

    deinit {
        subscriptionTask?.cancel()
        realtimeStateTask?.cancel()
        runtime?.cancel()
    }

    var canRefresh: Bool {
        runtime != nil && !isRefreshing
    }

    func start() async {
        guard runtime == nil else {
            return
        }

        phase = .authorizing
        do {
            let runtime = try await runtimeFactory()
            self.runtime = runtime
            subscribe(to: runtime.stream)
            subscribeToRealtimeStates(runtime.realtimeStates)
            phase = .ready
            await runtime.stream.refresh()
        } catch {
            phase = .failed(Self.safeDescription(for: error))
        }
    }

    func refresh() async {
        guard let runtime else {
            return
        }

        await runtime.stream.refresh()
    }

    private func subscribe(to stream: MessagesStream) {
        subscriptionTask?.cancel()
        subscriptionTask = Task { [weak self] in
            for await snapshot in stream.snapshots {
                self?.apply(snapshot)
            }
        }
    }

    private func subscribeToRealtimeStates(_ states: AsyncStream<WebexRealtimeConnectionState>?) {
        realtimeStateTask?.cancel()
        guard let states else {
            realtimeStatusText = "Realtime idle"
            return
        }

        realtimeStateTask = Task { [weak self] in
            for await state in states {
                self?.realtimeStatusText = Self.realtimeStatusText(for: state)
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

    private static func realtimeStatusText(for state: WebexRealtimeConnectionState) -> String {
        switch state {
        case .disconnected:
            return "Realtime disconnected"
        case .discovering:
            return "Realtime discovering"
        case .registeringDevice:
            return "Realtime registering device"
        case .connecting:
            return "Realtime connecting"
        case .authorizing:
            return "Realtime authorizing"
        case .connected:
            return "Realtime connected"
        case .reconnecting(let attempt, let delay):
            return "Realtime reconnecting \(attempt) in \(String(format: "%.1f", delay))s"
        case .failed(let error):
            return "Realtime failed: \(safeDescription(for: error))"
        }
    }

    enum Phase: Equatable {
        case idle
        case authorizing
        case ready
        case failed(String)
    }
}
