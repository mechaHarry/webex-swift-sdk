import Foundation

struct WebexAnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

enum WebexAdditionalFields {
    static func decode(
        from decoder: Decoder,
        excluding excludedKeys: Set<String>
    ) throws -> [String: WebexJSONValue] {
        let container = try decoder.container(keyedBy: WebexAnyCodingKey.self)
        var fields: [String: WebexJSONValue] = [:]

        for key in container.allKeys where !excludedKeys.contains(key.stringValue) {
            fields[key.stringValue] = try container.decode(WebexJSONValue.self, forKey: key)
        }

        return fields
    }
}
