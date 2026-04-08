import Foundation

extension JSONDecoder.KeyDecodingStrategy {
    nonisolated static var convertFromPascalCase: JSONDecoder.KeyDecodingStrategy {
        .custom { codingKeys in
            let key = codingKeys.last!.stringValue
            guard !key.isEmpty else { return codingKeys.last! }

            let firstChar = key.prefix(1).lowercased()
            let remaining = key.dropFirst()
            let camelCase = firstChar + remaining

            return AnyCodingKey(stringValue: camelCase)
        }
    }
}

private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
