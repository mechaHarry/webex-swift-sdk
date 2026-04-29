import Foundation

public struct WebexAccountID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init() {
        rawValue = UUID().uuidString.lowercased()
    }

    public init(rawValue: String) throws {
        guard let uuid = UUID(uuidString: rawValue) else {
            throw WebexSDKError.invalidAccountID(rawValue)
        }

        self.rawValue = uuid.uuidString.lowercased()
    }

    public var description: String {
        rawValue
    }
}

extension WebexAccountID: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        try self.init(rawValue: rawValue)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
