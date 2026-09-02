import Foundation

enum HolyArchiveSearchParser {
    private static let modifierRegex = try? NSRegularExpression(
        pattern: #"(?:^|\s)(harness|project|after|before):(?:(\"[^\"]+\")|('[^']+')|(\S+))"#,
        options: [.caseInsensitive]
    )
    private static let tagRegex = try? NSRegularExpression(
        pattern: #"#tag:([^\s]+)"#,
        options: [.caseInsensitive]
    )

    static func parse(_ raw: String, now: Date = .now, calendar: Calendar = .current) -> HolyArchiveSearchQuery {
        var working = raw
        var harness: HolyArchiveHarness?
        var rawHarness: String?
        var project: String?
        var after: Date?
        var before: Date?
        var tags: [String] = []

        for match in (tagRegex?.matches(
            in: working,
            range: NSRange(working.startIndex..<working.endIndex, in: working)
        ) ?? []).reversed() {
            guard let whole = Range(match.range(at: 0), in: working),
                  let value = Range(match.range(at: 1), in: working) else { continue }
            tags.append(String(working[value]))
            working.removeSubrange(whole)
        }
        tags.reverse()

        let modifierMatches = modifierRegex?.matches(
            in: working,
            range: NSRange(working.startIndex..<working.endIndex, in: working)
        ) ?? []
        for match in modifierMatches {
            guard let keyRange = Range(match.range(at: 1), in: working) else { continue }
            let valueIndex = (2...4).first { match.range(at: $0).location != NSNotFound }
            guard let valueIndex,
                  let valueRange = Range(match.range(at: valueIndex), in: working) else { continue }
            let key = working[keyRange].lowercased()
            let value = stripQuotes(String(working[valueRange]))
            switch key {
            case "harness":
                let canonical = value.lowercased()
                rawHarness = canonical
                harness = HolyArchiveHarness(rawValue: canonical)
            case "project": project = value
            case "after": after = parseDate(value, now: now, calendar: calendar)
            case "before": before = parseDate(value, now: now, calendar: calendar)
            default: break
            }
        }
        for match in modifierMatches.reversed() {
            guard let whole = Range(match.range(at: 0), in: working) else { continue }
            working.removeSubrange(whole)
        }

        return .init(
            text: cleanNaturalLanguage(working),
            harness: harness,
            rawHarness: rawHarness,
            project: project,
            after: after,
            before: before,
            tags: tags
        )
    }

    static func parseDate(_ raw: String, now: Date = .now, calendar: Calendar = .current) -> Date? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let match = value.wholeMatch(of: /(\d+)([dhwm])/) {
            guard let amount = Int(match.1) else { return nil }
            let component: Calendar.Component
            let multiplier: Int
            switch match.2 {
            case "h": component = .hour; multiplier = 1
            case "d": component = .day; multiplier = 1
            case "w": component = .day; multiplier = 7
            case "m": component = .day; multiplier = 30
            default: return nil
            }
            return calendar.date(byAdding: component, value: -amount * multiplier, to: now)
        }
        if let date = HolyArchiveDate.parse(value) { return date }

        let formats = ["yyyy-MM-dd", "yyyy/MM/dd", "MM-dd", "MM/dd"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = format
            if let parsed = formatter.date(from: value) {
                if format.hasPrefix("MM") {
                    var components = calendar.dateComponents([.month, .day], from: parsed)
                    components.year = calendar.component(.year, from: now)
                    return calendar.date(from: components)
                }
                return parsed
            }
        }
        return nil
    }

    static func cleanNaturalLanguage(_ raw: String) -> String {
        var collapsed = raw.split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
        collapsed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        collapsed = collapsed.replacingOccurrences(
            of: #"(?i)\bplease\b[.?!]*$"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"(?i)^(?:please\s+)?(?:find|show|list|get|pull\s+up|look\s+up|look\s+for|search\s+for)\s+(?:me\s+)?(?:the\s+)?(?:sessions?|conversations?|chats?|threads?)\s+(?:where\s+)?(?:we\s+)?(?:were\s+)?(?:worked|work|working|talked|discussed|built|fixed|debugged|implemented|created|added|changed)\s+(?:(?:on|about|with|for)\s+)?(.+)$"#,
            #"(?i)^(?:which|what)\s+(?:sessions?|conversations?|chats?|threads?)\s+(?:did\s+)?(?:we\s+)?(?:worked|work|working|talk|talked|discuss|discussed|build|built|fix|fixed|debug|debugged|implement|implemented)\s+(?:(?:on|about|with|for)\s+)?(.+)$"#,
            #"(?i)^(?:sessions?|conversations?|chats?|threads?)\s+(?:where\s+)?(?:we\s+)?(?:were\s+)?(?:worked|work|working|talked|discussed|built|fixed|debugged|implemented|created|added|changed)\s+(?:(?:on|about|with|for)\s+)?(.+)$"#,
            #"(?i)^(?:where\s+)?(?:we\s+)?(?:were\s+)?(?:worked|work|working|talked|discussed|built|fixed|debugged|implemented|created|added|changed)\s+(?:on|about|with|for)\s+(.+)$"#,
            #"(?i)^(?:please\s+)?(?:find|show|list|get|pull\s+up|look\s+up|look\s+for|search\s+for)\s+(?:me\s+)?(?:the\s+)?(?:sessions?|conversations?|chats?|threads?)\s+(?:about|on|for|with)\s+(.+)$"#,
        ]
        for source in patterns {
            guard let regex = try? NSRegularExpression(pattern: source),
                  let match = regex.firstMatch(
                    in: collapsed,
                    range: NSRange(collapsed.startIndex..<collapsed.endIndex, in: collapsed)
                  ),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: collapsed) else { continue }
            return String(collapsed[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var result = collapsed
        let cleanup = [
            #"(?i)^(?:please\s+)?(?:find|show|list|get|pull\s+up|look\s+up|look\s+for|search\s+for)\s+(?:me\s+)?"#,
            #"(?i)^(?:the\s+)?(?:sessions?|conversations?|chats?|threads?)\s+(?:about|on|for|with)\s+"#,
        ]
        for source in cleanup {
            result = result.replacingOccurrences(of: source, with: "", options: .regularExpression)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripQuotes(_ value: String) -> String {
        guard value.count >= 2,
              let first = value.first,
              first == "\"" || first == "'",
              value.last == first else { return value }
        return String(value.dropFirst().dropLast())
    }
}

struct HolyArchiveSearchResponse: Equatable, Sendable {
    let query: HolyArchiveSearchQuery
    let results: [HolyArchiveSearchResult]
    let matchingChildrenByParentID: [String: [HolyArchiveSession]]
    let semanticStatus: String?
    let elapsedMilliseconds: Double
}

actor HolyArchiveHybridSearch {
    static let defaultFTSWeight = 0.3
    static let defaultSemanticWeight = 0.7
    static let minimumCosine = 0.35
    static let minimumCombinedScore = 0.2
    static let normalizationFloor = 0.5

    private let repository: HolyArchiveRepository
    private let embedder: (any HolyArchiveEmbeddingProviding)?
    private var cachedEmbeddings: [HolyArchiveEmbeddingRow]?

    init(
        repository: HolyArchiveRepository,
        embedder: (any HolyArchiveEmbeddingProviding)? = HolyArchiveEmbeddingProviderFactory.makeConfigured()
    ) {
        self.repository = repository
        self.embedder = embedder
    }

    var embeddingsAvailable: Bool { embedder?.isAvailable == true }

    func invalidateCache() {
        cachedEmbeddings = nil
    }

    func search(
        _ rawQuery: String,
        limit: Int = 50,
        ftsWeight: Double = defaultFTSWeight,
        semanticWeight: Double = defaultSemanticWeight
    ) async throws -> HolyArchiveSearchResponse {
        let started = Date()
        let query = HolyArchiveSearchParser.parse(rawQuery)
        let candidates = try repository.sessions(query: query)
        let candidateByID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        var semanticStatus: String?
        var rawResults: [HolyArchiveSearchResult]

        if query.isFiltersOnly {
            rawResults = candidates.map {
                .init(
                    session: $0, score: 1, keywordScore: nil, semanticScore: nil,
                    matchSnippet: nil, matchSource: .metadata
                )
            }
        } else {
            let fts = try repository.ftsMatches(query: query.text, filters: query)
            var semantic: [String: (score: Double, snippet: String)] = [:]
            if let embedder, embedder.isAvailable {
                do {
                    let vectors = try await embedder.embed([query.text], purpose: .query)
                    if let vector = vectors.first {
                        semantic = try semanticMatches(queryVector: vector, candidateIDs: Set(candidateByID.keys))
                    } else {
                        semanticStatus = "Semantic search returned no query vector. Keyword results remain available."
                    }
                } catch {
                    semanticStatus = "Semantic search unavailable: \(error.localizedDescription)"
                }
            } else {
                semanticStatus = "Semantic search is off because the selected embedding provider has no API key."
            }
            rawResults = Self.combine(
                candidates: candidateByID,
                fts: fts,
                semantic: semantic,
                ftsWeight: ftsWeight,
                semanticWeight: semanticWeight
            )
        }

        let propagated = try propagateChildren(rawResults)
        let sorted = propagated.parents
            .filter { $0.score >= Self.minimumCombinedScore }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.session.activityAt > $1.session.activityAt
            }
        let results = Array(sorted.prefix(max(0, limit)))
        let visibleIDs = Set(results.map(\.session.id))
        let matchingChildren = propagated.children.filter { visibleIDs.contains($0.key) }
        let elapsed = Date().timeIntervalSince(started) * 1000
        try repository.recordSearch(query: rawQuery, results: results, elapsedMilliseconds: elapsed)
        return .init(
            query: query,
            results: results,
            matchingChildrenByParentID: matchingChildren,
            semanticStatus: semanticStatus,
            elapsedMilliseconds: elapsed
        )
    }

    func searchFTSOnly(_ rawQuery: String, limit: Int = 50) throws -> HolyArchiveSearchResponse {
        let started = Date()
        let query = HolyArchiveSearchParser.parse(rawQuery)
        let candidates = try repository.sessions(query: query)
        let byID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        let fts = try repository.ftsMatches(query: query.text, filters: query)
        let normalized = Self.normalized(Dictionary(uniqueKeysWithValues: fts.map { ($0.sessionID, $0.score) }))
        let results = fts.compactMap { match -> HolyArchiveSearchResult? in
            guard let session = byID[match.sessionID] else { return nil }
            return .init(
                session: session, score: normalized[session.id] ?? 0,
                keywordScore: match.score, semanticScore: nil,
                matchSnippet: match.snippet, matchSource: match.source
            )
        }.sorted { $0.score > $1.score }
        let elapsed = Date().timeIntervalSince(started) * 1000
        try repository.recordSearch(query: rawQuery, results: results, elapsedMilliseconds: elapsed)
        return .init(query: query, results: Array(results.prefix(limit)), matchingChildrenByParentID: [:], semanticStatus: nil, elapsedMilliseconds: elapsed)
    }

    func searchSemanticOnly(_ rawQuery: String, limit: Int = 50) async throws -> HolyArchiveSearchResponse {
        let started = Date()
        let query = HolyArchiveSearchParser.parse(rawQuery)
        let candidates = try repository.sessions(query: query)
        let byID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        guard let embedder, embedder.isAvailable else {
            let elapsed = Date().timeIntervalSince(started) * 1000
            try repository.recordSearch(query: rawQuery, results: [], elapsedMilliseconds: elapsed)
            return .init(
                query: query, results: [], matchingChildrenByParentID: [:],
                semanticStatus: "Semantic search is off because the selected embedding provider has no API key.",
                elapsedMilliseconds: elapsed
            )
        }
        let vectors = try await embedder.embed([query.text], purpose: .query)
        let raw = try vectors.first.map { try semanticMatches(queryVector: $0, candidateIDs: Set(byID.keys)) } ?? [:]
        let normalized = Self.normalized(raw.mapValues(\.score))
        let results = raw.compactMap { id, match -> HolyArchiveSearchResult? in
            guard let session = byID[id] else { return nil }
            return .init(
                session: session, score: normalized[id] ?? 0, keywordScore: nil,
                semanticScore: match.score, matchSnippet: match.snippet, matchSource: .semantic
            )
        }.sorted { $0.score > $1.score }
        let elapsed = Date().timeIntervalSince(started) * 1000
        try repository.recordSearch(query: rawQuery, results: results, elapsedMilliseconds: elapsed)
        return .init(query: query, results: Array(results.prefix(limit)), matchingChildrenByParentID: [:], semanticStatus: nil, elapsedMilliseconds: elapsed)
    }

    private func semanticMatches(
        queryVector: [Float],
        candidateIDs: Set<String>
    ) throws -> [String: (score: Double, snippet: String)] {
        let rows: [HolyArchiveEmbeddingRow]
        if let cachedEmbeddings {
            rows = cachedEmbeddings
        } else {
            rows = try repository.embeddingRows()
            cachedEmbeddings = rows
        }
        let queryNorm = Self.norm(queryVector)
        guard queryNorm > 0 else { return [:] }
        var best: [String: (score: Double, snippet: String)] = [:]
        for row in rows where candidateIDs.contains(row.sessionID) && row.embedding.count == queryVector.count {
            let denominator = Self.norm(row.embedding) * queryNorm
            guard denominator > 0 else { continue }
            let dot = zip(row.embedding, queryVector).reduce(0.0) { $0 + Double($1.0) * Double($1.1) }
            let score = dot / denominator
            guard score >= Self.minimumCosine, score > (best[row.sessionID]?.score ?? -.infinity) else { continue }
            best[row.sessionID] = (score, HolyArchiveText.preview(row.content, limit: 1_200))
        }
        return best
    }

    private func propagateChildren(
        _ raw: [HolyArchiveSearchResult]
    ) throws -> (parents: [HolyArchiveSearchResult], children: [String: [HolyArchiveSession]]) {
        let byID = Dictionary(uniqueKeysWithValues: raw.map { ($0.session.id, $0) })
        var parents: [String: HolyArchiveSearchResult] = [:]
        var children: [String: [HolyArchiveSession]] = [:]
        var missingParentIDs = Set<String>()
        for result in raw {
            if result.session.isChild, let parentID = result.session.parentID {
                children[parentID, default: []].append(result.session)
                if byID[parentID] == nil { missingParentIDs.insert(parentID) }
            } else {
                parents[result.session.id] = result
            }
        }
        let loadedParents = try repository.sessions(ids: Array(missingParentIDs))
        let loadedByID = Dictionary(uniqueKeysWithValues: loadedParents.map { ($0.id, $0) })
        for result in raw where result.session.isChild {
            guard let parentID = result.session.parentID,
                  let parent = byID[parentID]?.session ?? loadedByID[parentID] else { continue }
            let projected = HolyArchiveSearchResult(
                session: parent,
                score: result.score,
                keywordScore: result.keywordScore,
                semanticScore: result.semanticScore,
                matchSnippet: result.matchSnippet,
                matchSource: result.matchSource
            )
            if projected.score > (parents[parentID]?.score ?? -.infinity) {
                parents[parentID] = projected
            }
        }
        return (Array(parents.values), children)
    }

    private static func combine(
        candidates: [String: HolyArchiveSession],
        fts: [HolyArchiveFTSMatch],
        semantic: [String: (score: Double, snippet: String)],
        ftsWeight: Double,
        semanticWeight: Double
    ) -> [HolyArchiveSearchResult] {
        let ftsByID = Dictionary(uniqueKeysWithValues: fts.map { ($0.sessionID, $0) })
        let ftsNormalized = normalized(ftsByID.mapValues(\.score))
        let semanticNormalized = normalized(semantic.mapValues(\.score))
        let ids = Set(ftsByID.keys).union(semantic.keys)
        return ids.compactMap { id in
            guard let session = candidates[id] else { return nil }
            let ftsMatch = ftsByID[id]
            let semanticMatch = semantic[id]
            let score: Double
            if let left = ftsNormalized[id], let right = semanticNormalized[id] {
                score = left * ftsWeight + right * semanticWeight
            } else if let left = ftsNormalized[id] {
                score = left * Self.normalizationFloor
            } else if let right = semanticNormalized[id] {
                score = right * Self.normalizationFloor
            } else {
                return nil
            }
            let semanticWins = (semanticNormalized[id] ?? -.infinity) > (ftsNormalized[id] ?? -.infinity)
            return .init(
                session: session,
                score: score,
                keywordScore: ftsMatch?.score,
                semanticScore: semanticMatch?.score,
                matchSnippet: semanticWins ? semanticMatch?.snippet : ftsMatch?.snippet,
                matchSource: semanticWins ? .semantic : (ftsMatch?.source ?? .semantic)
            )
        }
    }

    private static func normalized(_ values: [String: Double]) -> [String: Double] {
        guard let minimum = values.values.min(), let maximum = values.values.max() else { return [:] }
        if maximum == minimum { return values.mapValues { _ in 1 } }
        return values.mapValues {
            normalizationFloor + (($0 - minimum) / (maximum - minimum)) * (1 - normalizationFloor)
        }
    }

    private static func norm(_ vector: [Float]) -> Double {
        sqrt(vector.reduce(0.0) { $0 + Double($1) * Double($1) })
    }
}

enum HolyArchiveTranscriptFind {
    static func ranges(of needle: String, in haystack: String) -> [Range<String.Index>] {
        guard !needle.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var start = haystack.startIndex
        while start < haystack.endIndex,
              let range = haystack.range(
                of: needle,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: start..<haystack.endIndex,
                locale: Locale(identifier: "en_US_POSIX")
              ) {
            ranges.append(range)
            start = haystack.index(after: range.lowerBound)
        }
        return ranges
    }

    static func lineAndColumn(
        at index: String.Index,
        in text: String
    ) -> (line: Int, column: Int) {
        let prefix = text[..<index]
        let lines = prefix.split(separator: "\n", omittingEmptySubsequences: false)
        return (max(1, lines.count), (lines.last?.count ?? 0) + 1)
    }
}
