import Foundation

internal protocol WebexRealtimeConnectionSource: Sendable {
    var events: AsyncStream<WebexRealtimeEvent> { get }
    var states: AsyncStream<WebexRealtimeConnectionState> { get }

    func cancel()
}

public final class WebexRealtimeConnection: @unchecked Sendable {
    public let events: AsyncStream<WebexRealtimeEvent>
    public let states: AsyncStream<WebexRealtimeConnectionState>
    public let triggers: AsyncStream<WebexStreamTrigger>

    private let source: WebexRealtimeConnectionSource
    private let streamState = WebexRealtimeConnectionStreamState()

    internal init(source: WebexRealtimeConnectionSource) {
        self.source = source

        var eventContinuation: AsyncStream<WebexRealtimeEvent>.Continuation?
        var stateContinuation: AsyncStream<WebexRealtimeConnectionState>.Continuation?
        var triggerContinuation: AsyncStream<WebexStreamTrigger>.Continuation?

        self.events = AsyncStream { continuation in
            eventContinuation = continuation
        }
        self.states = AsyncStream { continuation in
            stateContinuation = continuation
        }
        self.triggers = AsyncStream { continuation in
            triggerContinuation = continuation
        }

        streamState.setContinuations(
            events: eventContinuation,
            states: stateContinuation,
            triggers: triggerContinuation
        )

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

    public func cancel() {
        source.cancel()
        streamState.cancel()
    }
}

private final class WebexRealtimeConnectionStreamState: @unchecked Sendable {
    private let lock = NSLock()
    private var eventContinuation: AsyncStream<WebexRealtimeEvent>.Continuation?
    private var stateContinuation: AsyncStream<WebexRealtimeConnectionState>.Continuation?
    private var triggerContinuation: AsyncStream<WebexStreamTrigger>.Continuation?
    private var eventTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?
    private var isFinished = false

    func setContinuations(
        events: AsyncStream<WebexRealtimeEvent>.Continuation?,
        states: AsyncStream<WebexRealtimeConnectionState>.Continuation?,
        triggers: AsyncStream<WebexStreamTrigger>.Continuation?
    ) {
        lock.withLock {
            eventContinuation = events
            stateContinuation = states
            triggerContinuation = triggers
        }
    }

    func setTasks(eventTask: Task<Void, Never>, stateTask: Task<Void, Never>) {
        lock.withLock {
            self.eventTask = eventTask
            self.stateTask = stateTask
        }
    }

    func yield(_ event: WebexRealtimeEvent) {
        lock.withLock {
            _ = eventContinuation?.yield(event)
        }
    }

    func yield(_ state: WebexRealtimeConnectionState) {
        lock.withLock {
            _ = stateContinuation?.yield(state)
        }
    }

    func yield(_ trigger: WebexStreamTrigger) {
        lock.withLock {
            _ = triggerContinuation?.yield(trigger)
        }
    }

    func finishEventsAndTriggers() {
        let continuations = lock.withLock {
            let continuations = (eventContinuation, triggerContinuation)
            eventContinuation = nil
            triggerContinuation = nil
            return continuations
        }

        continuations.0?.finish()
        continuations.1?.finish()
    }

    func finishStates() {
        let continuation = lock.withLock {
            let continuation = stateContinuation
            stateContinuation = nil
            return continuation
        }

        continuation?.finish()
    }

    func cancel() {
        let snapshot = lock.withLock {
            guard !isFinished else {
                return (nil as AsyncStream<WebexRealtimeEvent>.Continuation?,
                        nil as AsyncStream<WebexRealtimeConnectionState>.Continuation?,
                        nil as AsyncStream<WebexStreamTrigger>.Continuation?,
                        nil as Task<Void, Never>?,
                        nil as Task<Void, Never>?)
            }

            isFinished = true
            let snapshot = (eventContinuation, stateContinuation, triggerContinuation, eventTask, stateTask)
            eventContinuation = nil
            stateContinuation = nil
            triggerContinuation = nil
            eventTask = nil
            stateTask = nil
            return snapshot
        }

        snapshot.3?.cancel()
        snapshot.4?.cancel()
        snapshot.0?.finish()
        snapshot.1?.finish()
        snapshot.2?.finish()
    }
}
