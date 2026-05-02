import Foundation

public enum WebexJSONValue: Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: WebexJSONValue])
    case array([WebexJSONValue])
    case null
}

extension WebexJSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
            return
        }

        if let object = try? container.decode([String: WebexJSONValue].self) {
            self = .object(object)
            return
        }

        if let array = try? container.decode([WebexJSONValue].self) {
            self = .array(array)
            return
        }

        if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
            return
        }

        if let number = try? container.decode(Double.self) {
            self = .number(number)
            return
        }

        if let string = try? container.decode(String.self) {
            self = .string(string)
            return
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported Webex JSON value"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}
