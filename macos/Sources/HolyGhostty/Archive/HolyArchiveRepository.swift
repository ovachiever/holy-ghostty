import Foundation
import SQLite3

struct HolyArchiveFTSMatch: Equatable, Sendable {
    let sessionID: String
    let score: Double
    let snippet: String?
    let source: HolyArchiveMatchSource
}

struct HolyArchiveEmbeddingRow: Equatable, Sendable {
    let chunkID: String
    let sessionID: String
    let content: String
    let embedding: [Float]
}

struct HolyArchiveIndexRow: Equatable, Sendable {
    let sessionID: String
    let rawPath: String
    let fileMTime: Date
    let indexedAt: Date
}

struct HolyArchiveTagCount: Equatable, Sendable {
    let tag: String
    let count: Int
}

struct HolyArchiveReplacementToken: Equatable, Sendable {
    let ingestID: String
    let sessionID: String
    let expectedMessageCount: Int
    let expectedChunkCount: Int
}

struct HolyArchiveEmbeddingWrite: Equatable, Sendable {
    let chunkID: String
    let embedding: [Float]
    let model: String
}

/// The archive's only persistence boundary. Every operation opens a short-lived
/// FULLMUTEX connection to the independent Archive database, so Archive writes
/// cannot acquire the workspace database's single WAL-writer slot.
struct HolyArchiveRepository: Sendable {
    let databaseURL: URL

    init(databaseURL: URL = HolyDatabasePaths.archiveDatabaseURL) throws {
        self.databaseURL = databaseURL
        let database = try HolyDatabase.open(at: databaseURL)
        try HolyArchiveDatabaseMigrator.migrate(database)
    }

    func replace(
        session: HolyArchiveSession,
        messages: [HolyArchiveMessage],
        chunks: [HolyArchiveChunk],
        metadataOnly: Bool = false
    ) throws {
        if metadataOnly {
            try replaceMetadata(session: session)
            return
        }

        let token = try beginReplacement(
            sessionID: session.id,
            expectedMessageCount: messages.count,
            expectedChunkCount: chunks.count
        )
        do {
            for batch in messages.chunked(maxCount: 250) {
                try stage(messages: batch, for: token)
            }
            for batch in chunks.chunked(maxCount: 250) {
                try stage(chunks: batch, for: token)
            }
            try finishReplacement(session: session, token: token)
        } catch {
            try? discardReplacement(token)
            throw error
        }
    }

    func replaceMetadata(session: HolyArchiveSession) throws {
        let database = try open()
        try database.withTransaction { try upsert(session: session, in: database) }
    }

    func beginReplacement(
        sessionID: String,
        expectedMessageCount: Int,
        expectedChunkCount: Int
    ) throws -> HolyArchiveReplacementToken {
        let database = try open()
        try database.withTransaction {
            try database.execute(
                "DELETE FROM archive_staged_messages WHERE session_id = ?;",
                bindings: [.text(sessionID)]
            )
            try database.execute(
                "DELETE FROM archive_staged_chunks WHERE session_id = ?;",
                bindings: [.text(sessionID)]
            )
        }
        return .init(
            ingestID: UUID().uuidString,
            sessionID: sessionID,
            expectedMessageCount: expectedMessageCount,
            expectedChunkCount: expectedChunkCount
        )
    }

    func stage(messages: [HolyArchiveMessage], for token: HolyArchiveReplacementToken) throws {
        guard !messages.isEmpty else { return }
        let database = try open()
        try database.withTransaction {
            for message in messages {
                try insertStaged(message: message, ingestID: token.ingestID, in: database)
            }
        }
    }

    func stage(chunks: [HolyArchiveChunk], for token: HolyArchiveReplacementToken) throws {
        guard !chunks.isEmpty else { return }
        let database = try open()
        try database.withTransaction {
            for chunk in chunks {
                try insertStaged(chunk: chunk, ingestID: token.ingestID, in: database)
            }
        }
    }

    func finishReplacement(
        session: HolyArchiveSession,
        token: HolyArchiveReplacementToken
    ) throws {
        let database = try open()
        let stagedMessages = try database.scalarInt64(
            "SELECT COUNT(*) FROM archive_staged_messages WHERE ingest_id = '\(Self.sqlLiteral(token.ingestID))';"
        )
        let stagedChunks = try database.scalarInt64(
            "SELECT COUNT(*) FROM archive_staged_chunks WHERE ingest_id = '\(Self.sqlLiteral(token.ingestID))';"
        )
        guard stagedMessages == token.expectedMessageCount,
              stagedChunks == token.expectedChunkCount else {
            throw HolyArchiveRepositoryError.incompleteStaging(
                expectedMessages: token.expectedMessageCount,
                actualMessages: Int(stagedMessages),
                expectedChunks: token.expectedChunkCount,
                actualChunks: Int(stagedChunks)
            )
        }

        try database.withTransaction {
            try upsert(session: session, in: database)
            try database.execute(
                "DELETE FROM archive_messages WHERE session_id = ?;",
                bindings: [.text(session.id)]
            )
            try database.execute(
                "DELETE FROM archive_chunks WHERE session_id = ?;",
                bindings: [.text(session.id)]
            )
            try database.execute(
                """
                INSERT INTO archive_messages(
                    id, session_id, role, content, timestamp, sequence, has_code, tool_mentions_json
                )
                SELECT id, session_id, role, content, timestamp, sequence, has_code, tool_mentions_json
                FROM archive_staged_messages WHERE ingest_id = ? ORDER BY sequence;
                """,
                bindings: [.text(token.ingestID)]
            )
            try database.execute(
                """
                INSERT INTO archive_chunks(
                    id, session_id, message_id, chunk_index, chunk_type, content,
                    metadata_json, embedding, embedding_model, created_at
                )
                SELECT id, session_id, message_id, chunk_index, chunk_type, content,
                       metadata_json, embedding, embedding_model, created_at
                FROM archive_staged_chunks WHERE ingest_id = ? ORDER BY chunk_index;
                """,
                bindings: [.text(token.ingestID)]
            )
            try deleteStaging(token, in: database)
        }
    }

    func discardReplacement(_ token: HolyArchiveReplacementToken) throws {
        let database = try open()
        try database.withTransaction { try deleteStaging(token, in: database) }
    }

    func applyParentLinks(_ links: [(childID: String, parentID: String)]) throws {
        guard !links.isEmpty else { return }
        let database = try open()
        try database.withTransaction {
            for link in links {
                try database.execute(
                    """
                    UPDATE archive_sessions
                    SET parent_id = ?
                    WHERE id = ?
                      AND EXISTS (SELECT 1 FROM archive_sessions WHERE id = ?);
                    """,
                    bindings: [.text(link.parentID), .text(link.childID), .text(link.parentID)]
                )
            }
        }
    }

    func indexRows(harness: HolyArchiveHarness? = nil) throws -> [HolyArchiveIndexRow] {
        let database = try open(readOnly: true)
        let clause = harness == nil ? "" : " WHERE harness = ?"
        let bindings: [HolyDatabaseBinding] = harness.map { [.text($0.rawValue)] } ?? []
        var rows: [HolyArchiveIndexRow] = []
        try database.query(
            "SELECT id, raw_path, file_mtime, indexed_at FROM archive_sessions\(clause);",
            bindings: bindings
        ) { statement in
            rows.append(.init(
                sessionID: text(statement, 0),
                rawPath: text(statement, 1),
                fileMTime: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                indexedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
            ))
        }
        return rows
    }

    func sessions(
        query: HolyArchiveSearchQuery? = nil,
        parentsOnly: Bool = false,
        limit: Int = 100_000,
        offset: Int = 0
    ) throws -> [HolyArchiveSession] {
        let database = try open(readOnly: true)
        let filter = Self.filterSQL(query, tableAlias: "s")
        var clauses = filter.clauses
        var bindings = filter.bindings
        if parentsOnly { clauses.append("s.is_child = 0") }
        bindings.append(.int64(Int64(max(0, limit))))
        bindings.append(.int64(Int64(max(0, offset))))

        var rows: [HolyArchiveSession] = []
        try database.query(
            """
            SELECT \(Self.sessionColumns("s"))
            FROM archive_sessions s
            \(clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND "))
            ORDER BY COALESCE(s.timestamp_end, s.timestamp) DESC, s.id ASC
            LIMIT ? OFFSET ?;
            """,
            bindings: bindings
        ) { statement in
            rows.append(Self.session(from: statement))
        }
        return rows
    }

    func session(id: String) throws -> HolyArchiveSession? {
        let database = try open(readOnly: true)
        var result: HolyArchiveSession?
        try database.query(
            "SELECT \(Self.sessionColumns("s")) FROM archive_sessions s WHERE s.id = ? LIMIT 1;",
            bindings: [.text(id)]
        ) { statement in
            result = Self.session(from: statement)
        }
        return result
    }

    func sessions(ids: [String]) throws -> [HolyArchiveSession] {
        guard !ids.isEmpty else { return [] }
        let database = try open(readOnly: true)
        var result: [HolyArchiveSession] = []
        for batch in ids.chunked(maxCount: 500) {
            let placeholders = Array(repeating: "?", count: batch.count).joined(separator: ",")
            try database.query(
                "SELECT \(Self.sessionColumns("s")) FROM archive_sessions s WHERE s.id IN (\(placeholders));",
                bindings: batch.map(HolyDatabaseBinding.text)
            ) { statement in
                result.append(Self.session(from: statement))
            }
        }
        let byID = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    func children(of parentID: String) throws -> [HolyArchiveSession] {
        let database = try open(readOnly: true)
        var rows: [HolyArchiveSession] = []
        try database.query(
            """
            SELECT \(Self.sessionColumns("s"))
            FROM archive_sessions s
            WHERE s.parent_id = ?
            ORDER BY COALESCE(s.timestamp_end, s.timestamp), s.id;
            """,
            bindings: [.text(parentID)]
        ) { statement in
            rows.append(Self.session(from: statement))
        }
        return rows
    }

    /// Returns the children the archive UI associates with a parent. Explicit
    /// provider links are authoritative. Providers without parent IDs fall
    /// back to the source browser's harness, project, and activity window.
    func relatedChildren(of parentID: String) throws -> [HolyArchiveSession] {
        let database = try open(readOnly: true)
        guard let parent = try Self.session(id: parentID, database: database) else { return [] }
        let explicit = try Self.children(of: parent, database: database, explicitOnly: true)
        if !explicit.isEmpty { return explicit }
        return try Self.children(of: parent, database: database, explicitOnly: false)
    }

    func childCounts(parentIDs: [String]) throws -> [String: Int] {
        guard !parentIDs.isEmpty else { return [:] }
        let database = try open(readOnly: true)
        var counts: [String: Int] = [:]
        for parentID in parentIDs {
            guard let parent = try Self.session(id: parentID, database: database) else { continue }
            let explicit = try Self.children(of: parent, database: database, explicitOnly: true)
            if !explicit.isEmpty {
                counts[parentID] = explicit.count
            } else {
                counts[parentID] = try Self.children(
                    of: parent, database: database, explicitOnly: false
                ).count
            }
        }
        return counts
    }

    func resolveCandidates(
        projectPath: String,
        harness: HolyArchiveHarness,
        near: Date,
        window: TimeInterval = 48 * 60 * 60,
        limit: Int = 5
    ) throws -> [HolyArchiveSession] {
        let database = try open(readOnly: true)
        var rows: [HolyArchiveSession] = []
        try database.query(
            """
            SELECT \(Self.sessionColumns("s"))
            FROM archive_sessions s
            WHERE s.harness = ?
              AND s.project_path = ?
              AND s.is_child = 0
              AND ABS(COALESCE(s.timestamp_end, s.timestamp) - ?) <= ?
            ORDER BY
              ABS(COALESCE(s.timestamp_end, s.timestamp) - ?) ASC,
              COALESCE(s.timestamp_end, s.timestamp) DESC,
              s.id ASC
            LIMIT ?;
            """,
            bindings: [
                .text(harness.rawValue), .text(projectPath), .double(near.timeIntervalSince1970),
                .double(window), .double(near.timeIntervalSince1970), .int64(Int64(max(0, limit))),
            ]
        ) { statement in
            rows.append(Self.session(from: statement))
        }
        return rows
    }

    private static func session(
        id: String,
        database: HolyDatabase
    ) throws -> HolyArchiveSession? {
        var result: HolyArchiveSession?
        try database.query(
            "SELECT \(sessionColumns("s")) FROM archive_sessions s WHERE s.id = ? LIMIT 1;",
            bindings: [.text(id)]
        ) { statement in
            result = session(from: statement)
        }
        return result
    }

    private static func children(
        of parent: HolyArchiveSession,
        database: HolyDatabase,
        explicitOnly: Bool
    ) throws -> [HolyArchiveSession] {
        var rows: [HolyArchiveSession] = []
        if explicitOnly {
            try database.query(
                """
                SELECT \(sessionColumns("s"))
                FROM archive_sessions s
                WHERE s.parent_id = ?
                ORDER BY COALESCE(s.timestamp, s.timestamp_end), s.id;
                """,
                bindings: [.text(parent.id)]
            ) { statement in
                rows.append(session(from: statement))
            }
            return rows
        }

        guard let projectPath = parent.projectPath else { return [] }
        let window: TimeInterval = parent.harness == .opencode ? 24 * 60 * 60 : 2 * 60 * 60
        try database.query(
            """
            SELECT \(sessionColumns("s"))
            FROM archive_sessions s
            WHERE s.is_child = 1
              AND s.harness = ?
              AND s.project_path = ?
              AND ABS(COALESCE(s.timestamp_end, s.timestamp) - ?) < ?
            ORDER BY COALESCE(s.timestamp, s.timestamp_end), s.id;
            """,
            bindings: [
                .text(parent.harness.rawValue), .text(projectPath),
                .double(parent.activityAt.timeIntervalSince1970), .double(window),
            ]
        ) { statement in
            rows.append(session(from: statement))
        }
        return rows
    }

    func messages(
        sessionID: String,
        role: HolyArchiveMessageRole? = nil,
        last: Int? = nil,
        around query: String? = nil
    ) throws -> [HolyArchiveMessage] {
        let database = try open(readOnly: true)
        var clauses = ["session_id = ?"]
        var bindings: [HolyDatabaseBinding] = [.text(sessionID)]
        if let role {
            clauses.append("role = ?")
            bindings.append(.text(role.rawValue))
        }
        if let query = query?.holyArchiveNilIfBlank {
            clauses.append(
                "sequence IN (SELECT DISTINCT m2.sequence + offsets.value FROM archive_messages m2 JOIN (SELECT -4 value UNION ALL SELECT -3 UNION ALL SELECT -2 UNION ALL SELECT -1 UNION ALL SELECT 0 UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4) offsets WHERE m2.session_id = ? AND m2.content LIKE ? ESCAPE '\\')"
            )
            bindings.append(.text(sessionID))
            bindings.append(.text("%\(Self.likeEscaped(query))%"))
        }

        let orderAndLimit: String
        if let last {
            orderAndLimit = "ORDER BY sequence DESC LIMIT \(max(0, last))"
        } else {
            orderAndLimit = "ORDER BY sequence ASC"
        }
        var rows: [HolyArchiveMessage] = []
        try database.query(
            """
            SELECT id, session_id, role, content, timestamp, sequence
            FROM archive_messages
            WHERE \(clauses.joined(separator: " AND "))
            \(orderAndLimit);
            """,
            bindings: bindings
        ) { statement in
            rows.append(Self.message(from: statement))
        }
        return last == nil ? rows : rows.reversed()
    }

    func chunks(sessionID: String, type: HolyArchiveChunkType? = nil) throws -> [HolyArchiveChunk] {
        let database = try open(readOnly: true)
        var sql = """
        SELECT id, session_id, message_id, chunk_index, chunk_type, content,
               metadata_json, embedding, embedding_model, created_at
        FROM archive_chunks WHERE session_id = ?
        """
        var bindings: [HolyDatabaseBinding] = [.text(sessionID)]
        if let type {
            sql += " AND chunk_type = ?"
            bindings.append(.text(type.rawValue))
        }
        sql += " ORDER BY chunk_index, id;"
        var rows: [HolyArchiveChunk] = []
        try database.query(sql, bindings: bindings) { statement in
            rows.append(Self.chunk(from: statement))
        }
        return rows
    }

    func chunksWithoutEmbeddings(limit: Int = 100) throws -> [HolyArchiveChunk] {
        let database = try open(readOnly: true)
        var rows: [HolyArchiveChunk] = []
        try database.query(
            """
            SELECT id, session_id, message_id, chunk_index, chunk_type, content,
                   metadata_json, embedding, embedding_model, created_at
            FROM archive_chunks
            WHERE embedding IS NULL
            ORDER BY created_at, id
            LIMIT ?;
            """,
            bindings: [.int64(Int64(max(0, limit)))]
        ) { statement in
            rows.append(Self.chunk(from: statement))
        }
        return rows
    }

    func storeEmbedding(_ embedding: [Float], model: String, chunkID: String) throws {
        try storeEmbeddings([.init(chunkID: chunkID, embedding: embedding, model: model)])
    }

    func storeEmbeddings(_ writes: [HolyArchiveEmbeddingWrite]) throws {
        guard !writes.isEmpty else { return }
        let database = try open()
        try database.withTransaction {
            for write in writes {
                try database.execute(
                    "UPDATE archive_chunks SET embedding = ?, embedding_model = ? WHERE id = ?;",
                    bindings: [
                        .blob(Self.embeddingData(write.embedding)),
                        .text(write.model),
                        .text(write.chunkID),
                    ]
                )
            }
        }
    }

    func embeddingRows() throws -> [HolyArchiveEmbeddingRow] {
        let database = try open(readOnly: true)
        var rows: [HolyArchiveEmbeddingRow] = []
        try database.query(
            "SELECT id, session_id, content, embedding FROM archive_chunks WHERE embedding IS NOT NULL;"
        ) { statement in
            guard let data = blob(statement, 3), let embedding = Self.embedding(from: data) else { return }
            rows.append(.init(
                chunkID: text(statement, 0),
                sessionID: text(statement, 1),
                content: text(statement, 2),
                embedding: embedding
            ))
        }
        return rows
    }

    func ftsMatches(query: String, filters: HolyArchiveSearchQuery, limit: Int = 500) throws -> [HolyArchiveFTSMatch] {
        let fts = Self.ftsQuery(query)
        guard fts != "\"\"" else { return [] }
        let database = try open(readOnly: true)
        let filter = Self.filterSQL(filters, tableAlias: "s")
        let whereSuffix = filter.clauses.isEmpty ? "" : " AND " + filter.clauses.joined(separator: " AND ")
        var matchesByID: [String: HolyArchiveFTSMatch] = [:]

        var bindings: [HolyDatabaseBinding] = [.text(fts)] + filter.bindings
        bindings.append(.int64(Int64(max(1, limit))))
        try database.query(
            """
            SELECT s.id, MIN(f.rank)
            FROM archive_messages_fts f
            JOIN archive_messages m ON m.rowid = f.rowid
            JOIN archive_sessions s ON s.id = m.session_id
            WHERE archive_messages_fts MATCH ?\(whereSuffix)
            GROUP BY s.id
            ORDER BY MIN(f.rank)
            LIMIT ?;
            """,
            bindings: bindings
        ) { statement in
            let id = text(statement, 0)
            matchesByID[id] = .init(
                sessionID: id,
                score: Self.ftsScore(sqlite3_column_double(statement, 1)),
                snippet: nil,
                source: .keyword
            )
        }

        for id in Array(matchesByID.keys) {
            var snippet: String?
            try database.query(
                """
                SELECT snippet(archive_messages_fts, 0, '', '', '...', 24)
                FROM archive_messages_fts
                JOIN archive_messages m ON m.rowid = archive_messages_fts.rowid
                WHERE archive_messages_fts MATCH ? AND m.session_id = ?
                ORDER BY archive_messages_fts.rank
                LIMIT 1;
                """,
                bindings: [.text(fts), .text(id)]
            ) { statement in
                snippet = optionalText(statement, 0)
            }
            if let match = matchesByID[id] {
                matchesByID[id] = .init(
                    sessionID: id,
                    score: match.score,
                    snippet: snippet,
                    source: .keyword
                )
            }
        }

        bindings = [.text(fts)] + filter.bindings
        bindings.append(.int64(Int64(max(1, limit))))
        try database.query(
            """
            SELECT s.id, archive_sessions_fts.rank,
                   snippet(archive_sessions_fts, -1, '', '', '...', 24)
            FROM archive_sessions_fts
            JOIN archive_sessions s ON s.rowid = archive_sessions_fts.rowid
            WHERE archive_sessions_fts MATCH ?\(whereSuffix)
            ORDER BY archive_sessions_fts.rank
            LIMIT ?;
            """,
            bindings: bindings
        ) { statement in
            let id = text(statement, 0)
            let candidate = HolyArchiveFTSMatch(
                sessionID: id,
                score: Self.ftsScore(sqlite3_column_double(statement, 1)),
                snippet: optionalText(statement, 2),
                source: .metadata
            )
            if candidate.score > (matchesByID[id]?.score ?? -.infinity) {
                matchesByID[id] = candidate
            }
        }
        return Array(matchesByID.values)
    }

    func annotations(sessionID: String) throws -> [HolyArchiveAnnotation] {
        let database = try open(readOnly: true)
        var rows: [HolyArchiveAnnotation] = []
        try database.query(
            """
            SELECT id, session_id, timestamp, type, value, source
            FROM archive_annotations
            WHERE session_id = ?
            ORDER BY timestamp, id;
            """,
            bindings: [.text(sessionID)]
        ) { statement in
            guard let kind = HolyArchiveAnnotation.Kind(rawValue: text(statement, 3)) else { return }
            rows.append(.init(
                id: sqlite3_column_int64(statement, 0),
                sessionID: text(statement, 1),
                timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                kind: kind,
                value: text(statement, 4),
                source: text(statement, 5)
            ))
        }
        return rows
    }

    @discardableResult
    func addAnnotation(
        sessionID: String,
        kind: HolyArchiveAnnotation.Kind,
        value: String,
        source: String = "manual",
        timestamp: Date = .now
    ) throws -> HolyArchiveAnnotation {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw HolyArchiveRepositoryError.emptyAnnotation
        }
        let database = try open()
        try database.execute(
            """
            INSERT INTO archive_annotations(session_id, timestamp, type, value, source)
            VALUES (?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(sessionID), .double(timestamp.timeIntervalSince1970),
                .text(kind.rawValue), .text(normalized), .text(source),
            ]
        )
        return .init(
            id: database.lastInsertedRowID,
            sessionID: sessionID,
            timestamp: timestamp,
            kind: kind,
            value: normalized,
            source: source
        )
    }

    func deleteAnnotation(id: Int64) throws {
        let database = try open()
        try database.execute("DELETE FROM archive_annotations WHERE id = ?;", bindings: [.int64(id)])
    }

    func tagCounts(prefix: String? = nil) throws -> [HolyArchiveTagCount] {
        let database = try open(readOnly: true)
        var sql = """
        SELECT value, COUNT(*)
        FROM archive_annotations
        WHERE type = 'tag'
        """
        var bindings: [HolyDatabaseBinding] = []
        if let prefix = prefix?.holyArchiveNilIfBlank {
            sql += " AND value LIKE ? ESCAPE '\\' COLLATE NOCASE"
            bindings.append(.text("\(Self.likeEscaped(prefix))%"))
        }
        sql += " GROUP BY value COLLATE NOCASE ORDER BY COUNT(*) DESC, value COLLATE NOCASE;"
        var rows: [HolyArchiveTagCount] = []
        try database.query(sql, bindings: bindings) { statement in
            rows.append(.init(tag: text(statement, 0), count: Int(sqlite3_column_int64(statement, 1))))
        }
        return rows
    }

    func recordSearch(query: String, results: [HolyArchiveSearchResult], elapsedMilliseconds: Double) throws {
        let database = try open()
        try database.execute(
            """
            INSERT INTO archive_search_history(
                query, result_count, top_session_ids_json, search_time_ms, timestamp
            ) VALUES (?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(query), .int64(Int64(results.count)),
                .text(Self.json(Array(results.prefix(10).map(\.session.id)))),
                .double(elapsedMilliseconds), .double(Date.now.timeIntervalSince1970),
            ]
        )
    }

    func searchHistory(limit: Int = 20) throws -> [HolyArchiveSearchHistoryEntry] {
        let database = try open(readOnly: true)
        var rows: [HolyArchiveSearchHistoryEntry] = []
        try database.query(
            """
            SELECT id, query, result_count, top_session_ids_json, search_time_ms, timestamp
            FROM archive_search_history ORDER BY timestamp DESC LIMIT ?;
            """,
            bindings: [.int64(Int64(max(0, limit)))]
        ) { statement in
            rows.append(.init(
                id: sqlite3_column_int64(statement, 0),
                query: text(statement, 1),
                resultCount: Int(sqlite3_column_int64(statement, 2)),
                topSessionIDs: Self.strings(text(statement, 3)),
                searchTimeMilliseconds: sqlite3_column_double(statement, 4),
                timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
            ))
        }
        return rows
    }

    func replaceProjectStats() throws -> Int {
        let database = try open()
        let sessions = try sessions()
        let groups = Dictionary(grouping: sessions.compactMap { session -> (String, HolyArchiveSession)? in
            session.projectPath.map { ($0, session) }
        }, by: \.0)
        try database.withTransaction {
            try database.execute("DELETE FROM archive_project_stats;")
            for (path, pairs) in groups {
                let rows = pairs.map(\.1)
                let tagFrequencies = rows.flatMap(\.autoTags).reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
                let commonTags = tagFrequencies.sorted {
                    $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
                }.prefix(10).map(\.key)
                let harnessCounts = rows.reduce(into: [String: Int]()) { $0[$1.harness.rawValue, default: 0] += 1 }
                try database.execute(
                    """
                    INSERT INTO archive_project_stats(
                        project_path, project_name, total_sessions, parent_sessions, child_sessions,
                        first_session_time, last_session_time, harness_counts_json, total_messages,
                        common_tags_json, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                    """,
                    bindings: [
                        .text(path), .text(rows.first?.projectName ?? URL(fileURLWithPath: path).lastPathComponent),
                        .int64(Int64(rows.count)), .int64(Int64(rows.filter(\.isParent).count)),
                        .int64(Int64(rows.filter(\.isChild).count)),
                        Self.dateBinding(rows.map(\.createdAt).min()),
                        Self.dateBinding(rows.map(\.activityAt).max()),
                        .text(Self.json(harnessCounts)),
                        .int64(Int64(rows.reduce(0) { $0 + $1.messageCount })),
                        .text(Self.json(commonTags)), .double(Date.now.timeIntervalSince1970),
                    ]
                )
            }
        }
        return groups.count
    }

    func projects(
        after: Date? = nil,
        before: Date? = nil,
        harness: HolyArchiveHarness? = nil
    ) throws -> [HolyArchiveProject] {
        var query = HolyArchiveSearchQuery(
            text: "", harness: harness, rawHarness: nil,
            project: nil, after: after, before: before, tags: []
        )
        query.text = ""
        let rows = try sessions(query: query)
        let grouped = Dictionary(grouping: rows.compactMap { row -> (String, HolyArchiveSession)? in
            row.projectPath.map { ($0, row) }
        }, by: \.0)
        return grouped.map { path, pairs in
            let sessions = pairs.map(\.1)
            let tagCounts = sessions.flatMap(\.autoTags).reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
            return .init(
                path: path,
                name: sessions.first?.projectName ?? URL(fileURLWithPath: path).lastPathComponent,
                totalSessions: sessions.count,
                parentSessions: sessions.filter(\.isParent).count,
                childSessions: sessions.filter(\.isChild).count,
                firstSessionAt: sessions.map(\.createdAt).min(),
                lastSessionAt: sessions.map(\.activityAt).max(),
                harnesses: Array(Set(sessions.map(\.harness))).sorted { $0.rawValue < $1.rawValue },
                totalMessages: sessions.reduce(0) { $0 + $1.messageCount },
                commonTags: tagCounts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
                    .prefix(10).map(\.key)
            )
        }.sorted { $0.totalSessions == $1.totalSessions ? $0.name < $1.name : $0.totalSessions > $1.totalSessions }
    }

    func acquireReindexClaim(key: String, now: Date = .now, interval: TimeInterval = 120) throws -> Bool {
        let database = try open()
        let threshold = now.timeIntervalSince1970 - interval
        try database.execute(
            """
            INSERT INTO archive_index_meta(key, value, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
            WHERE archive_index_meta.updated_at <= ?;
            """,
            bindings: [
                .text(key), .text(String(now.timeIntervalSince1970)),
                .double(now.timeIntervalSince1970), .double(threshold),
            ]
        )
        return database.changedRowCount == 1
    }

    func saveSummary(sessionID: String, summary: String, model: String, contentHash: String) throws {
        let database = try open()
        try database.withTransaction {
            try database.execute(
                """
                INSERT INTO archive_summaries(session_id, summary, model, content_hash, created_at)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(session_id) DO UPDATE SET
                    summary = excluded.summary, model = excluded.model,
                    content_hash = excluded.content_hash, created_at = excluded.created_at;
                """,
                bindings: [
                    .text(sessionID), .text(summary), .text(model), .text(contentHash),
                    .double(Date.now.timeIntervalSince1970),
                ]
            )
            try database.execute(
                "UPDATE archive_sessions SET summary = ? WHERE id = ?;",
                bindings: [.text(summary), .text(sessionID)]
            )
        }
    }

    func importLegacySummaries(_ entries: [HolyArchiveLegacySummary]) throws -> Int {
        guard !entries.isEmpty else { return 0 }
        let database = try open()
        var imported = 0
        try database.withTransaction {
            for entry in entries {
                try database.execute(
                    """
                    INSERT OR IGNORE INTO archive_summaries(
                        session_id, summary, model, content_hash, created_at
                    )
                    SELECT ?, ?, 'gpt-5.5', ?, ?
                    WHERE EXISTS (
                        SELECT 1 FROM archive_sessions
                        WHERE id = ? AND (summary IS NULL OR TRIM(summary) = '')
                    );
                    """,
                    bindings: [
                        .text(entry.sessionID), .text(entry.summary), .text(entry.contentHash),
                        .double(Date.now.timeIntervalSince1970), .text(entry.sessionID),
                    ]
                )
                try database.execute(
                    """
                    UPDATE archive_sessions
                    SET summary = ?
                    WHERE id = ? AND (summary IS NULL OR TRIM(summary) = '');
                    """,
                    bindings: [.text(entry.summary), .text(entry.sessionID)]
                )
                imported += Int(database.changedRowCount)
            }
        }
        return imported
    }

    func chat(id: String) throws -> HolyArchiveResearchChat? {
        let database = try open(readOnly: true)
        var result: HolyArchiveResearchChat?
        try database.query(
            """
            SELECT id, title, created_at, updated_at, backend, model, state_json, metadata_json
            FROM archive_research_chats WHERE id = ? LIMIT 1;
            """,
            bindings: [.text(id)]
        ) { statement in result = Self.chat(from: statement) }
        return result
    }

    func recentChats(limit: Int = 20) throws -> [HolyArchiveResearchChat] {
        let database = try open(readOnly: true)
        var rows: [HolyArchiveResearchChat] = []
        try database.query(
            """
            SELECT id, title, created_at, updated_at, backend, model, state_json, metadata_json
            FROM archive_research_chats ORDER BY updated_at DESC LIMIT ?;
            """,
            bindings: [.int64(Int64(max(0, limit)))]
        ) { statement in rows.append(Self.chat(from: statement)) }
        return rows
    }

    func saveChat(_ chat: HolyArchiveResearchChat) throws {
        let database = try open()
        try database.execute(
            """
            INSERT INTO archive_research_chats(
                id, title, created_at, updated_at, backend, model, state_json, metadata_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title, updated_at = excluded.updated_at,
                backend = excluded.backend, model = excluded.model,
                state_json = excluded.state_json, metadata_json = excluded.metadata_json;
            """,
            bindings: [
                .text(chat.id), .text(chat.title), .double(chat.createdAt.timeIntervalSince1970),
                .double(chat.updatedAt.timeIntervalSince1970), .text(chat.backend), .text(chat.model),
                .text(chat.stateJSON), .text(chat.metadataJSON),
            ]
        )
    }

    func appendResearchMessage(
        chatID: String,
        role: HolyArchiveMessageRole,
        content: String,
        toolCallJSON: String? = nil,
        toolOutputJSON: String? = nil,
        citedSessionIDs: [String] = []
    ) throws -> HolyArchiveResearchMessage {
        let database = try open()
        let sequence = Int(try database.scalarInt64(
            "SELECT COALESCE(MAX(sequence), -1) + 1 FROM archive_research_messages WHERE chat_id = '\(Self.sqlLiteral(chatID))';"
        ))
        let createdAt = Date.now
        try database.execute(
            """
            INSERT INTO archive_research_messages(
                chat_id, sequence, role, content, tool_call_json,
                tool_output_json, cited_session_ids_json, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(chatID), .int64(Int64(sequence)), .text(role.rawValue), .text(content),
                toolCallJSON.map(HolyDatabaseBinding.text) ?? .null,
                toolOutputJSON.map(HolyDatabaseBinding.text) ?? .null,
                .text(Self.json(citedSessionIDs)), .double(createdAt.timeIntervalSince1970),
            ]
        )
        return .init(
            id: database.lastInsertedRowID,
            chatID: chatID,
            sequence: sequence,
            role: role,
            content: content,
            toolCallJSON: toolCallJSON,
            toolOutputJSON: toolOutputJSON,
            citedSessionIDs: citedSessionIDs,
            createdAt: createdAt
        )
    }

    func researchMessages(chatID: String) throws -> [HolyArchiveResearchMessage] {
        let database = try open(readOnly: true)
        var rows: [HolyArchiveResearchMessage] = []
        try database.query(
            """
            SELECT id, chat_id, sequence, role, content, tool_call_json,
                   tool_output_json, cited_session_ids_json, created_at
            FROM archive_research_messages WHERE chat_id = ? ORDER BY sequence;
            """,
            bindings: [.text(chatID)]
        ) { statement in
            guard let role = HolyArchiveMessageRole(rawValue: text(statement, 3)) else { return }
            rows.append(.init(
                id: sqlite3_column_int64(statement, 0), chatID: text(statement, 1),
                sequence: Int(sqlite3_column_int64(statement, 2)), role: role,
                content: text(statement, 4), toolCallJSON: optionalText(statement, 5),
                toolOutputJSON: optionalText(statement, 6), citedSessionIDs: Self.strings(text(statement, 7)),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 8))
            ))
        }
        return rows
    }

    func deleteChat(id: String) throws {
        let database = try open()
        try database.execute("DELETE FROM archive_research_chats WHERE id = ?;", bindings: [.text(id)])
    }

    func storedIndexProgress() throws -> HolyArchiveIndexProgress? {
        let database = try open(readOnly: true)
        var value: String?
        try database.query(
            "SELECT value FROM archive_index_meta WHERE key = 'ingest.progress' LIMIT 1;"
        ) { statement in value = optionalText(statement, 0) }
        guard let value, let data = value.data(using: .utf8) else { return nil }
        return try JSONDecoder().decode(HolyArchiveIndexProgress.self, from: data)
    }

    func saveIndexProgress(_ progress: HolyArchiveIndexProgress) throws {
        let data = try JSONEncoder().encode(progress)
        guard let value = String(data: data, encoding: .utf8) else { return }
        let database = try open()
        try database.execute(
            """
            INSERT INTO archive_index_meta(key, value, updated_at) VALUES ('ingest.progress', ?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at;
            """,
            bindings: [.text(value), .double(Date.now.timeIntervalSince1970)]
        )
    }

    func clearIndexProgress() throws {
        let database = try open()
        try database.execute("DELETE FROM archive_index_meta WHERE key = 'ingest.progress';")
    }

    func checkpointWAL() throws {
        let database = try open()
        try database.execute("PRAGMA wal_checkpoint(PASSIVE);")
    }

    private func open(readOnly: Bool = false) throws -> HolyDatabase {
        let database = try HolyDatabase.open(at: databaseURL, readOnly: readOnly)
        if !readOnly { try HolyArchiveDatabaseMigrator.configureWriter(database) }
        return database
    }

    private func upsert(session: HolyArchiveSession, in database: HolyDatabase) throws {
        try database.execute(
            """
            INSERT INTO archive_sessions(
                id, harness, raw_path, project_path, project_name, title,
                first_prompt_preview, last_prompt_preview, last_response_preview,
                timestamp, timestamp_end, is_child, child_type, parent_id, model,
                tool_calls_json, tokens_used, summary, content_hash, extra_json,
                resume_command, message_count, turn_count, file_mtime, indexed_at,
                auto_tags_json
            ) VALUES (
                ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                CASE WHEN EXISTS (SELECT 1 FROM archive_sessions WHERE id = ?) THEN ? ELSE NULL END,
                ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
            )
            ON CONFLICT(id) DO UPDATE SET
                harness = excluded.harness, raw_path = excluded.raw_path,
                project_path = excluded.project_path, project_name = excluded.project_name,
                title = excluded.title, first_prompt_preview = excluded.first_prompt_preview,
                last_prompt_preview = excluded.last_prompt_preview,
                last_response_preview = excluded.last_response_preview,
                timestamp = excluded.timestamp, timestamp_end = excluded.timestamp_end,
                is_child = excluded.is_child, child_type = excluded.child_type,
                parent_id = excluded.parent_id,
                model = excluded.model, tool_calls_json = excluded.tool_calls_json,
                tokens_used = excluded.tokens_used, summary = COALESCE(excluded.summary, archive_sessions.summary),
                content_hash = excluded.content_hash, extra_json = excluded.extra_json,
                resume_command = excluded.resume_command, message_count = excluded.message_count,
                turn_count = excluded.turn_count, file_mtime = excluded.file_mtime,
                indexed_at = excluded.indexed_at, auto_tags_json = excluded.auto_tags_json;
            """,
            bindings: [
                .text(session.id), .text(session.harness.rawValue), .text(session.rawPath),
                session.projectPath.map(HolyDatabaseBinding.text) ?? .null,
                .text(session.projectName), .text(session.title), .text(session.firstPrompt),
                .text(session.lastPrompt), .text(session.lastResponse),
                .double(session.createdAt.timeIntervalSince1970),
                Self.dateBinding(session.modifiedAt), .bool(session.isChild),
                session.childType.map(HolyDatabaseBinding.text) ?? .null,
                session.parentID.map(HolyDatabaseBinding.text) ?? .null,
                session.parentID.map(HolyDatabaseBinding.text) ?? .null,
                session.model.map(HolyDatabaseBinding.text) ?? .null,
                .text(Self.json(session.toolCalls)),
                session.tokensUsed.map { .int64(Int64($0)) } ?? .null,
                session.summary.map(HolyDatabaseBinding.text) ?? .null,
                .text(session.contentHash), .text(Self.json(session.extra)),
                session.resumeCommand.map(HolyDatabaseBinding.text) ?? .null,
                .int64(Int64(session.messageCount)), .int64(Int64(session.turnCount)),
                .double(session.fileMTime.timeIntervalSince1970),
                .double(session.indexedAt.timeIntervalSince1970), .text(Self.json(session.autoTags)),
            ]
        )
    }

    private func insertStaged(
        message: HolyArchiveMessage,
        ingestID: String,
        in database: HolyDatabase
    ) throws {
        try database.execute(
            """
            INSERT INTO archive_staged_messages(
                ingest_id, id, session_id, role, content, timestamp, sequence, has_code,
                tool_mentions_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(ingestID), .text(message.id), .text(message.sessionID), .text(message.role.rawValue),
                .text(message.content), Self.dateBinding(message.timestamp), .int64(Int64(message.sequence)),
                .bool(message.hasCode), .text(Self.json(message.toolMentions)),
            ]
        )
    }

    private func insertStaged(
        chunk: HolyArchiveChunk,
        ingestID: String,
        in database: HolyDatabase
    ) throws {
        try database.execute(
            """
            INSERT INTO archive_staged_chunks(
                ingest_id, id, session_id, message_id, chunk_index, chunk_type, content,
                metadata_json, embedding, embedding_model, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(ingestID), .text(chunk.id), .text(chunk.sessionID),
                chunk.messageID.map(HolyDatabaseBinding.text) ?? .null,
                .int64(Int64(chunk.index)), .text(chunk.type.rawValue), .text(chunk.content),
                .text(Self.json(chunk.metadata)),
                chunk.embedding.map { .blob(Self.embeddingData($0)) } ?? .null,
                chunk.embeddingModel.map(HolyDatabaseBinding.text) ?? .null,
                .double(chunk.createdAt.timeIntervalSince1970),
            ]
        )
    }

    private func deleteStaging(
        _ token: HolyArchiveReplacementToken,
        in database: HolyDatabase
    ) throws {
        try database.execute(
            "DELETE FROM archive_staged_messages WHERE ingest_id = ?;",
            bindings: [.text(token.ingestID)]
        )
        try database.execute(
            "DELETE FROM archive_staged_chunks WHERE ingest_id = ?;",
            bindings: [.text(token.ingestID)]
        )
    }

    private static let sessionColumns = { (alias: String) in
        """
        \(alias).id, \(alias).harness, \(alias).raw_path, \(alias).project_path,
        \(alias).project_name, \(alias).title, \(alias).first_prompt_preview,
        \(alias).last_prompt_preview, \(alias).last_response_preview,
        \(alias).timestamp, \(alias).timestamp_end, \(alias).is_child,
        \(alias).child_type, \(alias).parent_id, \(alias).model,
        \(alias).tool_calls_json, \(alias).tokens_used, \(alias).summary,
        \(alias).content_hash, \(alias).extra_json, \(alias).resume_command,
        \(alias).message_count, \(alias).turn_count, \(alias).file_mtime,
        \(alias).indexed_at, \(alias).auto_tags_json
        """
    }

    private static func session(from statement: OpaquePointer) -> HolyArchiveSession {
        let harness = HolyArchiveHarness(rawValue: text(statement, 1)) ?? .claudeCode
        return .init(
            id: text(statement, 0), harness: harness, rawPath: text(statement, 2),
            projectPath: optionalText(statement, 3), projectName: text(statement, 4),
            title: text(statement, 5), firstPrompt: text(statement, 6),
            lastPrompt: text(statement, 7), lastResponse: text(statement, 8),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 9)),
            modifiedAt: optionalDate(statement, 10), isChild: sqlite3_column_int(statement, 11) != 0,
            childType: optionalText(statement, 12), parentID: optionalText(statement, 13),
            model: optionalText(statement, 14), toolCalls: strings(text(statement, 15)),
            tokensUsed: optionalInt(statement, 16), summary: optionalText(statement, 17),
            contentHash: text(statement, 18), extra: dictionary(text(statement, 19)),
            resumeCommand: optionalText(statement, 20), messageCount: Int(sqlite3_column_int64(statement, 21)),
            turnCount: Int(sqlite3_column_int64(statement, 22)),
            fileMTime: Date(timeIntervalSince1970: sqlite3_column_double(statement, 23)),
            indexedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 24)),
            autoTags: strings(text(statement, 25))
        )
    }

    private static func message(from statement: OpaquePointer) -> HolyArchiveMessage {
        .init(
            id: text(statement, 0), sessionID: text(statement, 1),
            role: HolyArchiveMessageRole(rawValue: text(statement, 2)) ?? .unknown,
            content: text(statement, 3), timestamp: optionalDate(statement, 4),
            sequence: Int(sqlite3_column_int64(statement, 5))
        )
    }

    private static func chunk(from statement: OpaquePointer) -> HolyArchiveChunk {
        .init(
            id: text(statement, 0), sessionID: text(statement, 1),
            messageID: optionalText(statement, 2), index: Int(sqlite3_column_int64(statement, 3)),
            type: HolyArchiveChunkType(rawValue: text(statement, 4)) ?? .turn,
            content: text(statement, 5), metadata: dictionary(text(statement, 6)),
            embedding: blob(statement, 7).flatMap(embedding(from:)),
            embeddingModel: optionalText(statement, 8),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 9))
        )
    }

    private static func chat(from statement: OpaquePointer) -> HolyArchiveResearchChat {
        .init(
            id: text(statement, 0), title: text(statement, 1),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
            backend: text(statement, 4), model: text(statement, 5),
            stateJSON: text(statement, 6), metadataJSON: text(statement, 7)
        )
    }

    private static func filterSQL(
        _ query: HolyArchiveSearchQuery?,
        tableAlias: String
    ) -> (clauses: [String], bindings: [HolyDatabaseBinding]) {
        guard let query else { return ([], []) }
        var clauses: [String] = []
        var bindings: [HolyDatabaseBinding] = []
        if let harness = query.rawHarness ?? query.harness?.rawValue {
            clauses.append("\(tableAlias).harness = ?")
            bindings.append(.text(harness))
        }
        if let project = query.project?.holyArchiveNilIfBlank {
            clauses.append("(\(tableAlias).project_name LIKE ? ESCAPE '\\' COLLATE NOCASE OR \(tableAlias).project_path LIKE ? ESCAPE '\\' COLLATE NOCASE)")
            let pattern = "%\(likeEscaped(project))%"
            bindings += [.text(pattern), .text(pattern)]
        }
        if let after = query.after {
            clauses.append("COALESCE(\(tableAlias).timestamp_end, \(tableAlias).timestamp) >= ?")
            bindings.append(.double(after.timeIntervalSince1970))
        }
        if let before = query.before {
            clauses.append("COALESCE(\(tableAlias).timestamp_end, \(tableAlias).timestamp) <= ?")
            bindings.append(.double(before.timeIntervalSince1970))
        }
        for tag in query.tags {
            clauses.append("\(tableAlias).id IN (SELECT session_id FROM archive_annotations WHERE type = 'tag' AND value = ? COLLATE NOCASE)")
            bindings.append(.text(tag))
        }
        return (clauses, bindings)
    }

    static func embeddingData(_ values: [Float]) -> Data {
        values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func embedding(from data: Data) -> [Float]? {
        guard data.count.isMultiple(of: MemoryLayout<Float>.size) else { return nil }
        return data.withUnsafeBytes { raw in Array(raw.bindMemory(to: Float.self)) }
    }

    static func ftsQuery(_ value: String) -> String {
        let tokens = value.lowercased().matches(of: /[a-zA-Z0-9]+/).map { String($0.output) }
        let filtered = tokens.filter { !ftsStopWords.contains($0) }
        let chosen = filtered.count < 2 && tokens.count >= 2 ? tokens : filtered
        guard !chosen.isEmpty else { return "\"\"" }
        return chosen.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: " AND ")
    }

    private static let ftsStopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "has", "have", "he",
        "i", "in", "is", "it", "its", "me", "my", "of", "on", "or", "she", "that", "the",
        "they", "this", "to", "us", "was", "we", "what", "which", "who", "will", "with", "you",
        "do", "does", "did", "find", "how", "can", "use",
    ]

    private static func ftsScore(_ rank: Double) -> Double {
        1 / (1 + abs(rank))
    }

    private static func json<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "null" }
        return String(bytes: data, encoding: .utf8) ?? "null"
    }

    private static func strings(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    private static func dictionary(_ json: String) -> [String: String] {
        guard let data = json.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private static func dateBinding(_ date: Date?) -> HolyDatabaseBinding {
        date.map { .double($0.timeIntervalSince1970) } ?? .null
    }

    private static func likeEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private static func sqlLiteral(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }
}

enum HolyArchiveRepositoryError: LocalizedError {
    case emptyAnnotation
    case incompleteStaging(
        expectedMessages: Int,
        actualMessages: Int,
        expectedChunks: Int,
        actualChunks: Int
    )

    var errorDescription: String? {
        switch self {
        case .emptyAnnotation: "An archive annotation cannot be empty."
        case let .incompleteStaging(expectedMessages, actualMessages, expectedChunks, actualChunks):
            "Archive staging is incomplete: messages \(actualMessages)/\(expectedMessages), chunks \(actualChunks)/\(expectedChunks)."
        }
    }
}

private extension Array {
    func chunked(maxCount: Int) -> [[Element]] {
        guard maxCount > 0 else { return [] }
        return stride(from: 0, to: count, by: maxCount).map {
            Array(self[$0..<Swift.min($0 + maxCount, count)])
        }
    }
}

private func text(_ statement: OpaquePointer, _ column: Int32) -> String {
    optionalText(statement, column) ?? ""
}

private func optionalText(_ statement: OpaquePointer, _ column: Int32) -> String? {
    guard sqlite3_column_type(statement, column) != SQLITE_NULL,
          let value = sqlite3_column_text(statement, column) else { return nil }
    return String(cString: value)
}

private func optionalDate(_ statement: OpaquePointer, _ column: Int32) -> Date? {
    guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
    return Date(timeIntervalSince1970: sqlite3_column_double(statement, column))
}

private func optionalInt(_ statement: OpaquePointer, _ column: Int32) -> Int? {
    guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
    return Int(sqlite3_column_int64(statement, column))
}

private func blob(_ statement: OpaquePointer, _ column: Int32) -> Data? {
    guard sqlite3_column_type(statement, column) != SQLITE_NULL,
          let bytes = sqlite3_column_blob(statement, column) else { return nil }
    return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
}
