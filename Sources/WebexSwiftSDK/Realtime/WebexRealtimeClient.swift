import Foundation

public struct WebexRealtimeClient: Sendable {
    public let accountID: WebexAccountID

    private let httpClient: HTTPClient
    private let accessTokenProvider: @Sendable () async throws -> AccessTokenState
    private let tokenInvalidator: @Sendable () async -> Void

    internal init(
        accountID: WebexAccountID,
        httpClient: HTTPClient,
        accessTokenProvider: @escaping @Sendable () async throws -> AccessTokenState,
        tokenInvalidator: @escaping @Sendable () async -> Void
    ) {
        self.accountID = accountID
        self.httpClient = httpClient
        self.accessTokenProvider = accessTokenProvider
        self.tokenInvalidator = tokenInvalidator
    }

    public func connect(options: WebexRealtimeOptions = WebexRealtimeOptions()) -> WebexRealtimeConnection {
        let source = WebexRealtimeLiveConnectionSource(
            httpClient: httpClient,
            accessTokenProvider: accessTokenProvider,
            tokenInvalidator: tokenInvalidator,
            options: options
        )
        source.start()
        return WebexRealtimeConnection(source: source)
    }
}

internal final class WebexRealtimeLiveConnectionSource: WebexRealtimeConnectionSource, @unchecked Sendable {
    internal let events: AsyncStream<WebexRealtimeEvent>
    internal let states: AsyncStream<WebexRealtimeConnectionState>

    private let httpClient: HTTPClient
    private let accessTokenProvider: @Sendable () async throws -> AccessTokenState
    private let tokenInvalidator: @Sendable () async -> Void
    private let options: WebexRealtimeOptions
    private let deviceServiceFactory: @Sendable (
        HTTPClient,
        @escaping @Sendable () async throws -> AccessTokenState,
        RetryPolicy,
        @escaping @Sendable (TimeInterval) async throws -> Void
    ) -> WebexMercuryDeviceProviding
    private let webSocketFactory: @Sendable (URL) -> WebexRealtimeWebSocket
    private let sessionFactory: @Sendable (
        WebexRealtimeWebSocket,
        @escaping @Sendable () async throws -> AccessTokenState
    ) -> WebexMercurySession
    private let sleeper: @Sendable (TimeInterval) async throws -> Void
    private let streamState: WebexRealtimeLiveConnectionStreamState

    internal init(
        httpClient: HTTPClient,
        accessTokenProvider: @escaping @Sendable () async throws -> AccessTokenState,
        tokenInvalidator: @escaping @Sendable () async -> Void,
        options: WebexRealtimeOptions,
        deviceServiceFactory: @escaping @Sendable (
            HTTPClient,
            @escaping @Sendable () async throws -> AccessTokenState,
            RetryPolicy,
            @escaping @Sendable (TimeInterval) async throws -> Void
        ) -> WebexMercuryDeviceProviding = { httpClient, accessTokenProvider, retryPolicy, sleeper in
            WebexMercuryDeviceService(
                httpClient: httpClient,
                accessTokenProvider: accessTokenProvider,
                retryPolicy: retryPolicy,
                sleeper: sleeper
            )
        },
        webSocketFactory: @escaping @Sendable (URL) -> WebexRealtimeWebSocket = { url in
            URLSessionWebSocketTransport(url: url)
        },
        sessionFactory: @escaping @Sendable (
            WebexRealtimeWebSocket,
            @escaping @Sendable () async throws -> AccessTokenState
        ) -> WebexMercurySession = { webSocket, accessTokenProvider in
            WebexMercuryWebSocketSession(webSocket: webSocket, accessTokenProvider: accessTokenProvider)
        },
        sleeper: @escaping @Sendable (TimeInterval) async throws -> Void = { delay in
            guard delay > 0, delay.isFinite else {
                return
            }

            let nanoseconds = delay * 1_000_000_000
            guard nanoseconds.isFinite, nanoseconds < Double(UInt64.max) else {
                return
            }

            try await Task.sleep(nanoseconds: UInt64(nanoseconds.rounded(.down)))
        }
    ) {
        self.httpClient = httpClient
        self.accessTokenProvider = accessTokenProvider
        self.tokenInvalidator = tokenInvalidator
        self.options = options
        self.deviceServiceFactory = deviceServiceFactory
        self.webSocketFactory = webSocketFactory
        self.sessionFactory = sessionFactory
        self.sleeper = sleeper

        var eventContinuation: AsyncStream<WebexRealtimeEvent>.Continuation?
        var stateContinuation: AsyncStream<WebexRealtimeConnectionState>.Continuation?
        self.events = AsyncStream { continuation in
            eventContinuation = continuation
        }
        self.states = AsyncStream { continuation in
            stateContinuation = continuation
        }
        self.streamState = WebexRealtimeLiveConnectionStreamState(
            events: eventContinuation,
            states: stateContinuation
        )
    }

    internal func start() {
        let task = Task { [self] in
            await run()
        }

        if !streamState.setTaskIfNeeded(task) {
            task.cancel()
        }
    }

    internal func cancel() {
        streamState.cancel()
    }

    internal static func shouldYield(_ event: WebexRealtimeEvent, options: WebexRealtimeOptions) -> Bool {
        if !options.resources.isEmpty, !options.resources.contains(event.knownResource) {
            return false
        }

        if !options.events.isEmpty, !options.events.contains(event.knownEvent) {
            return false
        }

        if event.knownResource == .memberships,
           event.knownEvent == .seen,
           !options.includeMembershipSeen {
            return false
        }

        return true
    }

    private func run() async {
        let deviceService = deviceServiceFactory(
            httpClient,
            accessTokenProvider,
            options.retryPolicy,
            sleeper
        )
        var retryAttempt = 1
        var staleDeviceRefreshAttempts = 0
        var didInvalidateToken = false

        while true {
            do {
                try await connectOnce(deviceService: deviceService)
                streamState.finish()
                return
            } catch is CancellationError {
                streamState.finish()
                return
            } catch let error as WebexSDKError {
                streamState.cancelActiveConnection()

                if isStaleDevice(error: error), staleDeviceRefreshAttempts < 3 {
                    staleDeviceRefreshAttempts += 1
                    await deviceService.invalidateCachedDevice()
                    guard canAttemptConnectionAgain(after: retryAttempt) else {
                        streamState.yield(.failed(error))
                        streamState.finish()
                        return
                    }

                    retryAttempt += 1
                    continue
                }

                if isAuthFailure(error: error), !didInvalidateToken {
                    didInvalidateToken = true
                    await tokenInvalidator()
                    guard canAttemptConnectionAgain(after: retryAttempt) else {
                        streamState.yield(.failed(error))
                        streamState.finish()
                        return
                    }

                    retryAttempt += 1
                    continue
                }

                guard shouldRetryConnection(error: error, attempt: retryAttempt) else {
                    streamState.yield(.failed(error))
                    streamState.finish()
                    return
                }

                let delay = retryDelay(for: error, attempt: retryAttempt)
                streamState.yield(.reconnecting(attempt: retryAttempt, delay: delay))
                do {
                    try await sleeper(delay)
                } catch is CancellationError {
                    streamState.finish()
                    return
                } catch {
                    streamState.yield(.failed(.network("Realtime reconnect sleep failed: \(Redactor.redactSecrets(error.localizedDescription))")))
                    streamState.finish()
                    return
                }
                retryAttempt += 1
            } catch {
                streamState.cancelActiveConnection()
                let sdkError = WebexSDKError.network("Webex realtime connection failed: \(Redactor.redactSecrets(error.localizedDescription))")

                guard shouldRetryConnection(error: sdkError, attempt: retryAttempt) else {
                    streamState.yield(.failed(sdkError))
                    streamState.finish()
                    return
                }

                let delay = retryDelay(for: sdkError, attempt: retryAttempt)
                streamState.yield(.reconnecting(attempt: retryAttempt, delay: delay))
                do {
                    try await sleeper(delay)
                } catch is CancellationError {
                    streamState.finish()
                    return
                } catch {
                    streamState.yield(.failed(.network("Realtime reconnect sleep failed: \(Redactor.redactSecrets(error.localizedDescription))")))
                    streamState.finish()
                    return
                }
                retryAttempt += 1
            }
        }
    }

    private func connectOnce(deviceService: WebexMercuryDeviceProviding) async throws {
        do {
            try Task.checkCancellation()
            streamState.yield(.discovering)

            streamState.yield(.registeringDevice)
            let device = try await deviceService.device(options: options)

            try Task.checkCancellation()
            streamState.yield(.connecting)
            let webSocket = webSocketFactory(device.webSocketURL)
            let session = sessionFactory(webSocket, accessTokenProvider)
            streamState.setActive(webSocket: webSocket, session: session)

            streamState.yield(.authorizing)
            let frames = session.frames()
            streamState.yield(.connected)

            let decoder = WebexRealtimeEventDecoder()
            for try await frame in frames {
                try Task.checkCancellation()
                let event = try decoder.decode(Data(frame.utf8))
                guard Self.shouldYield(event, options: options) else {
                    continue
                }

                streamState.yield(event)
                if let ackID = event.ackID {
                    try await session.ack(messageID: ackID)
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as WebexSDKError {
            throw error
        } catch {
            throw WebexSDKError.network("Webex realtime connection failed: \(Redactor.redactSecrets(error.localizedDescription))")
        }
    }

    private func shouldRetryConnection(error: WebexSDKError, attempt: Int) -> Bool {
        guard canAttemptConnectionAgain(after: attempt) else {
            return false
        }

        if case .network = error {
            return true
        }

        switch error.apiErrorKind {
        case .rateLimited, .locked, .serverError:
            return true
        case .badRequest,
             .unauthorized,
             .forbidden,
             .notFound,
             .methodNotAllowed,
             .conflict,
             .gone,
             .unsupportedMediaType,
             .preconditionRequired,
             .unexpected,
             nil:
            return false
        }
    }

    private func canAttemptConnectionAgain(after attempt: Int) -> Bool {
        attempt < options.retryPolicy.maxAttempts
    }

    private func retryDelay(for error: WebexSDKError, attempt: Int) -> TimeInterval {
        switch error.apiErrorKind {
        case .rateLimited(let retryAfter), .locked(let retryAfter):
            return retryAfter ?? options.retryPolicy.delay(forAttempt: attempt)
        case .badRequest,
             .unauthorized,
             .forbidden,
             .notFound,
             .methodNotAllowed,
             .conflict,
             .gone,
             .unsupportedMediaType,
             .preconditionRequired,
             .serverError,
             .unexpected,
             nil:
            return options.retryPolicy.delay(forAttempt: attempt)
        }
    }

    private func isStaleDevice(error: WebexSDKError) -> Bool {
        error.apiErrorKind == .notFound
    }

    private func isAuthFailure(error: WebexSDKError) -> Bool {
        error.apiErrorKind == .unauthorized || error.apiErrorKind == .forbidden
    }
}

internal protocol WebexMercuryDeviceProviding: Sendable {
    func device(options: WebexRealtimeOptions) async throws -> WebexMercuryDevice
    func invalidateCachedDevice() async
}

extension WebexMercuryDeviceService: WebexMercuryDeviceProviding {}

internal protocol WebexMercurySession: Sendable {
    func frames() -> AsyncThrowingStream<String, Error>
    func ack(messageID: String) async throws
    func cancel()
}

extension WebexMercuryWebSocketSession: WebexMercurySession {}

private final class WebexRealtimeLiveConnectionStreamState: @unchecked Sendable {
    private let lock = NSLock()
    private var eventContinuation: AsyncStream<WebexRealtimeEvent>.Continuation?
    private var stateContinuation: AsyncStream<WebexRealtimeConnectionState>.Continuation?
    private var task: Task<Void, Never>?
    private var activeWebSocket: WebexRealtimeWebSocket?
    private var activeSession: WebexMercurySession?
    private var isFinished = false

    init(
        events: AsyncStream<WebexRealtimeEvent>.Continuation?,
        states: AsyncStream<WebexRealtimeConnectionState>.Continuation?
    ) {
        self.eventContinuation = events
        self.stateContinuation = states
    }

    func setTaskIfNeeded(_ task: Task<Void, Never>) -> Bool {
        lock.withLock {
            guard self.task == nil, !isFinished else {
                return false
            }

            self.task = task
            return true
        }
    }

    func setActive(webSocket: WebexRealtimeWebSocket, session: WebexMercurySession) {
        lock.withLock {
            activeWebSocket = webSocket
            activeSession = session
        }
    }

    func cancelActiveConnection() {
        let snapshot = lock.withLock {
            let snapshot = (activeSession, activeWebSocket)
            activeSession = nil
            activeWebSocket = nil
            return snapshot
        }
        snapshot.0?.cancel()
        snapshot.1?.cancel()
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

    func cancel() {
        let snapshot = finishSnapshot()
        snapshot.task?.cancel()
        snapshot.session?.cancel()
        snapshot.webSocket?.cancel()
        snapshot.events?.finish()
        snapshot.states?.finish()
    }

    func finish() {
        let snapshot = finishSnapshot()
        snapshot.session?.cancel()
        snapshot.webSocket?.cancel()
        snapshot.events?.finish()
        snapshot.states?.finish()
    }

    private func finishSnapshot() -> (
        events: AsyncStream<WebexRealtimeEvent>.Continuation?,
        states: AsyncStream<WebexRealtimeConnectionState>.Continuation?,
        task: Task<Void, Never>?,
        session: WebexMercurySession?,
        webSocket: WebexRealtimeWebSocket?
    ) {
        lock.withLock {
            guard !isFinished else {
                return (nil, nil, nil, nil, nil)
            }

            isFinished = true
            let snapshot = (eventContinuation, stateContinuation, task, activeSession, activeWebSocket)
            eventContinuation = nil
            stateContinuation = nil
            task = nil
            activeSession = nil
            activeWebSocket = nil
            return snapshot
        }
    }
}
