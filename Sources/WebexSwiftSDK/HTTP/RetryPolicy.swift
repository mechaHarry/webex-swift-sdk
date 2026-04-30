import Foundation

public struct RetryPolicy: Sendable {
    public let maxAttempts: Int
    public let baseDelay: TimeInterval
    public let jitter: TimeInterval
    /// Upper bound, in seconds, for computed retry delays and numeric Retry-After values.
    public let maximumDelay: TimeInterval

    public init(
        maxAttempts: Int = 3,
        baseDelay: TimeInterval = 0.5,
        jitter: TimeInterval = 0.25,
        maximumDelay: TimeInterval = 60
    ) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelay = Self.clampedNonnegative(baseDelay, fallback: 0)
        self.jitter = Self.clampedNonnegative(jitter, fallback: 0)
        self.maximumDelay = Self.clampedNonnegative(maximumDelay, fallback: 60)
    }

    public func delay(forAttempt attempt: Int) -> TimeInterval {
        let exponent = max(0, attempt - 1)
        let exponentialDelay = baseDelay * pow(2, Double(exponent))
        guard exponentialDelay.isFinite else {
            return maximumDelay
        }

        guard jitter > 0 else {
            return min(exponentialDelay, maximumDelay)
        }

        let delay = exponentialDelay + TimeInterval.random(in: 0...jitter)
        guard delay.isFinite else {
            return maximumDelay
        }

        return min(delay, maximumDelay)
    }

    public func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        for (key, value) in response.allHeaderFields {
            guard String(describing: key).caseInsensitiveCompare("Retry-After") == .orderedSame else {
                continue
            }

            guard let retryAfter = TimeInterval(String(describing: value)),
                  retryAfter.isFinite,
                  retryAfter >= 0 else {
                return nil
            }

            return min(retryAfter, maximumDelay)
        }

        return nil
    }

    private static func clampedNonnegative(_ value: TimeInterval, fallback: TimeInterval) -> TimeInterval {
        guard value.isFinite else {
            return fallback
        }

        return max(0, value)
    }
}
