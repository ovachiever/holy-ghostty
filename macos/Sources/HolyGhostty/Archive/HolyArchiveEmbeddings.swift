import Foundation

enum HolyArchiveEmbeddingPurpose: Sendable {
    case document
    case query
}

protocol HolyArchiveEmbeddingProviding: Sendable {
    var id: String { get }
    var displayName: String { get }
    var model: String { get }
    var isAvailable: Bool { get }
    func embed(_ texts: [String], purpose: HolyArchiveEmbeddingPurpose) async throws -> [[Float]]
}

enum HolyArchiveEmbeddingError: LocalizedError {
    case unavailable(String)
    case invalidResponse(String)
    case requestFailed(provider: String, status: Int, detail: String)

    var errorDescription: String? {
        switch self {
        case let .unavailable(message): message
        case let .invalidResponse(message): "The embedding response was invalid: \(message)"
        case let .requestFailed(provider, status, detail):
            "\(provider) embeddings failed with HTTP \(status): \(detail)"
        }
    }
}

enum HolyArchiveEmbeddingProviderFactory {
    static func makeConfigured(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> (any HolyArchiveEmbeddingProviding)? {
        let provider = defaults.string(forKey: "holy.archive.embedding.provider")?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "openai"
        switch provider {
        case "none", "off", "disabled": return nil
        case "voyage":
            return HolyVoyageEmbeddingProvider(
                apiKey: environment["VOYAGE_API_KEY"],
                model: defaults.string(forKey: "holy.archive.embedding.voyage.model") ?? "voyage-3.5"
            )
        case "cohere":
            return HolyCohereEmbeddingProvider(
                apiKey: environment["COHERE_API_KEY"],
                model: defaults.string(forKey: "holy.archive.embedding.cohere.model") ?? "embed-v4.0"
            )
        default:
            return HolyOpenAIEmbeddingProvider(
                apiKey: environment["OPENAI_API_KEY"],
                model: defaults.string(forKey: "holy.intelligence.embed.model")
                    ?? HolyIntelligenceRole.embed.defaultModel
            )
        }
    }
}

struct HolyOpenAIEmbeddingProvider: HolyArchiveEmbeddingProviding {
    let id = "openai"
    let displayName = "OpenAI"
    let apiKey: String?
    let model: String
    let endpoint: URL

    init(
        apiKey: String?,
        model: String = "text-embedding-3-small",
        endpoint: URL = URL(string: "https://api.openai.com/v1/embeddings")!
    ) {
        self.apiKey = apiKey
        self.model = model
        self.endpoint = endpoint
    }

    var isAvailable: Bool { apiKey?.holyArchiveNilIfBlank != nil }

    func embed(_ texts: [String], purpose: HolyArchiveEmbeddingPurpose) async throws -> [[Float]] {
        guard let apiKey = apiKey?.holyArchiveNilIfBlank else {
            throw HolyArchiveEmbeddingError.unavailable("OPENAI_API_KEY is not set.")
        }
        let body: [String: Any] = [
            "model": model,
            "input": bounded(texts),
            "encoding_format": "float",
        ]
        let payload = try await HolyArchiveHTTP.postJSON(
            endpoint: endpoint,
            headers: ["Authorization": "Bearer \(apiKey)"],
            body: body,
            provider: displayName,
            timeout: 30
        )
        guard let rows = payload["data"] as? [[String: Any]] else {
            throw HolyArchiveEmbeddingError.invalidResponse("OpenAI data was missing.")
        }
        let sorted = rows.sorted { ($0["index"] as? NSNumber)?.intValue ?? 0 < ($1["index"] as? NSNumber)?.intValue ?? 0 }
        return try sorted.map { row in
            guard let values = row["embedding"] as? [NSNumber] else {
                throw HolyArchiveEmbeddingError.invalidResponse("OpenAI returned a non-float embedding.")
            }
            return values.map(\.floatValue)
        }
    }
}

struct HolyVoyageEmbeddingProvider: HolyArchiveEmbeddingProviding {
    let id = "voyage"
    let displayName = "Voyage AI"
    let apiKey: String?
    let model: String
    let endpoint: URL

    init(
        apiKey: String?,
        model: String = "voyage-3.5",
        endpoint: URL = URL(string: "https://api.voyageai.com/v1/embeddings")!
    ) {
        self.apiKey = apiKey
        self.model = model
        self.endpoint = endpoint
    }

    var isAvailable: Bool { apiKey?.holyArchiveNilIfBlank != nil }

    func embed(_ texts: [String], purpose: HolyArchiveEmbeddingPurpose) async throws -> [[Float]] {
        guard let apiKey = apiKey?.holyArchiveNilIfBlank else {
            throw HolyArchiveEmbeddingError.unavailable("VOYAGE_API_KEY is not set.")
        }
        let body: [String: Any] = [
            "model": model,
            "input": bounded(texts),
            "input_type": purpose == .query ? "query" : "document",
            "truncation": true,
        ]
        let payload = try await HolyArchiveHTTP.postJSON(
            endpoint: endpoint,
            headers: ["Authorization": "Bearer \(apiKey)"],
            body: body,
            provider: displayName,
            timeout: 30
        )
        guard let rows = payload["data"] as? [[String: Any]] else {
            throw HolyArchiveEmbeddingError.invalidResponse("Voyage data was missing.")
        }
        let sorted = rows.sorted { ($0["index"] as? NSNumber)?.intValue ?? 0 < ($1["index"] as? NSNumber)?.intValue ?? 0 }
        return try sorted.map { row in
            guard let values = row["embedding"] as? [NSNumber] else {
                throw HolyArchiveEmbeddingError.invalidResponse("Voyage returned a non-float embedding.")
            }
            return values.map(\.floatValue)
        }
    }
}

struct HolyCohereEmbeddingProvider: HolyArchiveEmbeddingProviding {
    let id = "cohere"
    let displayName = "Cohere"
    let apiKey: String?
    let model: String
    let endpoint: URL

    init(
        apiKey: String?,
        model: String = "embed-v4.0",
        endpoint: URL = URL(string: "https://api.cohere.com/v2/embed")!
    ) {
        self.apiKey = apiKey
        self.model = model
        self.endpoint = endpoint
    }

    var isAvailable: Bool { apiKey?.holyArchiveNilIfBlank != nil }

    func embed(_ texts: [String], purpose: HolyArchiveEmbeddingPurpose) async throws -> [[Float]] {
        guard let apiKey = apiKey?.holyArchiveNilIfBlank else {
            throw HolyArchiveEmbeddingError.unavailable("COHERE_API_KEY is not set.")
        }
        let body: [String: Any] = [
            "model": model,
            "texts": bounded(texts),
            "input_type": purpose == .query ? "search_query" : "search_document",
            "embedding_types": ["float"],
        ]
        let payload = try await HolyArchiveHTTP.postJSON(
            endpoint: endpoint,
            headers: ["Authorization": "Bearer \(apiKey)"],
            body: body,
            provider: displayName,
            timeout: 30
        )
        guard let embeddings = payload["embeddings"] as? [String: Any],
              let rows = embeddings["float"] as? [[NSNumber]] else {
            throw HolyArchiveEmbeddingError.invalidResponse("Cohere float embeddings were missing.")
        }
        return rows.map { $0.map(\.floatValue) }
    }
}

private func bounded(_ texts: [String]) -> [String] {
    texts.map { String($0.prefix(24_000)) }
}

private enum HolyArchiveHTTP {
    static func postJSON(
        endpoint: URL,
        headers: [String: String],
        body: [String: Any],
        provider: String,
        timeout: TimeInterval
    ) async throws -> [String: Any] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let (data, response) = try await URLSession(configuration: configuration).data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HolyArchiveEmbeddingError.invalidResponse("\(provider) returned no HTTP status.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = String(bytes: data.prefix(800), encoding: .utf8) ?? "Non-UTF-8 response"
            throw HolyArchiveEmbeddingError.requestFailed(provider: provider, status: http.statusCode, detail: detail)
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HolyArchiveEmbeddingError.invalidResponse("\(provider) returned a non-object payload.")
        }
        return object
    }
}
