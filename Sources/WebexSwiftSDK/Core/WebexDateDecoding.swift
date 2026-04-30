import Foundation

enum WebexDateDecoding {
    private static let parser = WebexDateParser()

    static func decodeIfPresent<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> Date? {
        guard let value = try container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }

        if let date = parse(value) {
            return date
        }

        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "Invalid Webex timestamp"
        )
    }

    private static func parse(_ value: String) -> Date? {
        parser.date(from: value)
    }
}

private final class WebexDateParser: @unchecked Sendable {
    private let lock = NSLock()
    private let fractionalFormatter: ISO8601DateFormatter
    private let formatter: ISO8601DateFormatter

    init() {
        self.fractionalFormatter = ISO8601DateFormatter()
        self.fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        self.formatter = ISO8601DateFormatter()
        self.formatter.formatOptions = [.withInternetDateTime]
    }

    func date(from value: String) -> Date? {
        lock.lock()
        defer {
            lock.unlock()
        }

        return fractionalFormatter.date(from: value) ?? formatter.date(from: value)
    }
}
