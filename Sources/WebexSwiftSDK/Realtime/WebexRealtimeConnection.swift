import Foundation

internal protocol WebexRealtimeConnectionSource: Sendable {
    var events: AsyncStream<WebexRealtimeEvent> { get }
    var states: AsyncStream<WebexRealtimeConnectionState> { get }

    func cancel()
}

public final class WebexRealtimeConnection: @unchecked Sendable {
    public var events: AsyncStream<WebexRealtimeEvent> {
        streamState.eventStream()
    }

    public var states: AsyncStream<WebexRealtimeConnectionState> {
        streamState.stateStream()
    }

    public var triggers: AsyncStream<WebexStreamTrigger> {
        streamState.triggerStream()
    }

    private let source: WebexRealtimeConnectionSource
    private let streamState = WebexRealtimeConnectionStreamState()

    internal init(source: WebexRealtimeConnectionSource) {
        self.source = source

        let eventTask = Task { [source, streamState] in
            for await event in source.events {
                streamState.yield(event)
                streamState.yield(WebexRealtimeTriggerAdapter.trigger(for: event))
            }
            streamState.finishEventsAndTriggers()
        }

        let stateTask = Task { [source, streamState] in
            for await state in source.states {
                streamState.yield(state)
            }
            streamState.finishStates()
        }

        streamState.setTasks(eventTask: eventTask, stateTask: stateTask)
    }

    deinit {
        cancel()
    }

    public func cancel() {
        if streamState.cancel() {
            source.cancel()
        }
    }
}

private final class WebexRealtimeConnectionStreamState: @unchecked Sendable {
    private let lock = NSLock()
    private var eventContinuations: [UUID: AsyncStream<WebexRealtimeEvent>.Continuation] = [:]
    private var stateContinuations: [UUID: AsyncStream<WebexRealtimeConnectionState>.Continuation] = [:]
    private var triggerContinuations: [UUID: AsyncStream<WebexStreamTrigger>.Continuation] = [:]
    private var eventTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?
    private var isFinished = false

    func eventStream() -> AsyncStream<WebexRealtimeEvent> {
        AsyncStream { continuation in
            addEventContinuation(continuation)
        }
    }

    func stateStream() -> AsyncStream<WebexRealtimeConnectionState> {
        AsyncStream { continuation in
            addStateContinuation(continuation)
        }
    }

    func triggerStream() -> AsyncStream<WebexStreamTrigger> {
        AsyncStream { continuation in
            addTriggerContinuation(continuation)
        }
    }

    func setTasks(eventTask: Task<Void, Never>, stateTask: Task<Void, Never>) {
        lock.withLock {
            self.eventTask = eventTask
            self.stateTask = stateTask
        }
    }

    func yield(_ event: WebexRealtimeEvent) {
        let continuations = lock.withLock {
            Array(eventContinuations.values)
        }

        for continuation in continuations {
            continuation.yield(event)
        }
    }

    func yield(_ state: WebexRealtimeConnectionState) {
        let continuations = lock.withLock {
            Array(stateContinuations.values)
        }

        for continuation in continuations {
            continuation.yield(state)
        }
    }

    func yield(_ trigger: WebexStreamTrigger) {
        let continuations = lock.withLock {
            Array(triggerContinuations.values)
        }

        for continuation in continuations {
            continuation.yield(trigger)
        }
    }

    func finishEventsAndTriggers() {
        let continuations = lock.withLock {
            let continuations = (Array(eventContinuations.values), Array(triggerContinuations.values))
            eventContinuations.removeAll()
            triggerContinuations.removeAll()
            return continuations
        }

        continuations.0.forEach { $0.finish() }
        continuations.1.forEach { $0.finish() }
    }

    func finishStates() {
        let continuations = lock.withLock {
            let continuations = Array(stateContinuations.values)
            stateContinuations.removeAll()
            return continuations
        }

        continuations.forEach { $0.finish() }
    }

    func cancel() -> Bool {
        let snapshot = lock.withLock {
            guard !isFinished else {
                return ([] as [AsyncStream<WebexRealtimeEvent>.Continuation],
                        [] as [AsyncStream<WebexRealtimeConnectionState>.Continuation],
                        [] as [AsyncStream<WebexStreamTrigger>.Continuation],
                        nil as Task<Void, Never>?,
                        nil as Task<Void, Never>?)
            }

            isFinished = true
            let snapshot = (
                Array(eventContinuations.values),
                Array(stateContinuations.values),
                Array(triggerContinuations.values),
                eventTask,
                stateTask
            )
            eventContinuations.removeAll()
            stateContinuations.removeAll()
            triggerContinuations.removeAll()
            eventTask = nil
            stateTask = nil
            return snapshot
        }

        snapshot.3?.cancel()
        snapshot.4?.cancel()
        snapshot.0.forEach { $0.finish() }
        snapshot.1.forEach { $0.finish() }
        snapshot.2.forEach { $0.finish() }
        return snapshot.3 != nil || snapshot.4 != nil || !snapshot.0.isEmpty || !snapshot.1.isEmpty || !snapshot.2.isEmpty
    }

    private func addEventContinuation(_ continuation: AsyncStream<WebexRealtimeEvent>.Continuation) {
        let id = UUID()
        let shouldFinish = lock.withLock {
            guard !isFinished else {
                return true
            }

            eventContinuations[id] = continuation
            return false
        }
        continuation.onTermination = { [weak self] _ in
            self?.removeEventContinuation(id: id)
        }
        if shouldFinish {
            continuation.finish()
        }
    }

    private func addStateContinuation(_ continuation: AsyncStream<WebexRealtimeConnectionState>.Continuation) {
        let id = UUID()
        let shouldFinish = lock.withLock {
            guard !isFinished else {
                return true
            }

            stateContinuations[id] = continuation
            return false
        }
        continuation.onTermination = { [weak self] _ in
            self?.removeStateContinuation(id: id)
        }
        if shouldFinish {
            continuation.finish()
        }
    }

    private func addTriggerContinuation(_ continuation: AsyncStream<WebexStreamTrigger>.Continuation) {
        let id = UUID()
        let shouldFinish = lock.withLock {
            guard !isFinished else {
                return true
            }

            triggerContinuations[id] = continuation
            return false
        }
        continuation.onTermination = { [weak self] _ in
            self?.removeTriggerContinuation(id: id)
        }
        if shouldFinish {
            continuation.finish()
        }
    }

    private func removeEventContinuation(id: UUID) {
        lock.withLock {
            eventContinuations[id] = nil
        }
    }

    private func removeStateContinuation(id: UUID) {
        lock.withLock {
            stateContinuations[id] = nil
        }
    }

    private func removeTriggerContinuation(id: UUID) {
        lock.withLock {
            triggerContinuations[id] = nil
        }
    }
}
