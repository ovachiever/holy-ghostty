import Foundation

enum HolyPersistenceCoders {
    static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let data = try jsonEncoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.coderInvalidValue)
        }
        return string
    }

    static func decodeJSON<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        let data = Data(string.utf8)
        return try jsonDecoder.decode(T.self, from: data)
    }

    static func string(from date: Date) -> String {
        timestampFormatter.string(from: date)
    }

    static func date(from string: String) throws -> Date {
        if let date = timestampFormatter.date(from: string) {
            return date
        }

        let fallback = ISO8601DateFormatter()
        guard let date = fallback.date(from: string) else {
            throw CocoaError(.coderInvalidValue)
        }

        return date
    }
}
