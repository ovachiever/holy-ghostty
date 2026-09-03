import Foundation
import SQLite3

struct HolyArchiveLegacySummary: Equatable, Sendable {
    let sessionID: String
    let summary: String
    let contentHash: String
}

enum HolyArchiveLegacySummaryImporter {
    static func load(
        from urls: [URL] = defaultURLs
    ) -> [HolyArchiveLegacySummary] {
        var entries: [HolyArchiveLegacySummary] = []
        var seen = Set<String>()
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            for (sessionID, value) in object {
                guard seen.insert(sessionID).inserted,
                      let fields = value as? [String: Any],
                      let summary = (fields["summary"] as? String)?.holyArchiveNilIfBlank
                else { continue }
                entries.append(.init(
                    sessionID: sessionID,
                    summary: summary,
                    contentHash: fields["hash"] as? String ?? ""
                ))
            }
        }
        return entries
    }

    /// agent-sessions writes every summary it generates to the `summaries`
    /// table of its SQLite index (index/database.py); the JSON sidecars are
    /// the older caches it migrates from. Read-only, and an index without
    /// the table (an older agent-sessions) contributes nothing.
    static func load(fromDatabase url: URL) throws -> [HolyArchiveLegacySummary] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let database = try HolyDatabase.open(at: url, readOnly: true)
        let tables = try database.scalarInt64(
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'summaries';"
        )
        guard tables > 0 else { return [] }
        var entries: [HolyArchiveLegacySummary] = []
        try database.query(
            "SELECT session_id, summary, COALESCE(content_hash, '') FROM summaries WHERE summary IS NOT NULL AND TRIM(summary) <> '';"
        ) { statement in
            guard let id = sqlite3_column_text(statement, 0),
                  let summary = sqlite3_column_text(statement, 1) else { return }
            let hash = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            entries.append(.init(
                sessionID: String(cString: id),
                summary: String(cString: summary),
                contentHash: hash
            ))
        }
        return entries
    }

    static func migrate(
        repository: HolyArchiveRepository,
        from urls: [URL] = defaultURLs,
        databases: [URL] = defaultDatabaseURLs
    ) throws -> Int {
        var entries: [HolyArchiveLegacySummary] = []
        for database in databases {
            entries += try load(fromDatabase: database)
        }
        entries += load(from: urls)
        return try repository.importLegacySummaries(entries)
    }

    private static var defaultURLs: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".factory/session-summaries.json"),
            home.appendingPathComponent(".cache/agent-sessions/summaries.json"),
        ]
    }

    /// index/database.py DEFAULT_DB_PATH.
    private static var defaultDatabaseURLs: [URL] {
        [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/agent-sessions/sessions.db")]
    }
}

enum HolyArchiveChunker {
    static let targetTokens = 400
    static let summaryPreviewCharacters = 200

    static func chunks(
        session: HolyArchiveSession,
        messages: [HolyArchiveMessage],
        createdAt: Date = .now
    ) -> [HolyArchiveChunk] {
        var chunks: [HolyArchiveChunk] = []
        let tools = Array(Set(messages.flatMap(\.toolMentions))).sorted()
        let firstPrompt = messages.first {
            $0.role == .user && $0.content.holyArchiveNilIfBlank != nil
        }?.content ?? session.firstPrompt
        let firstPromptPreview = firstPrompt.count > summaryPreviewCharacters
            ? String(firstPrompt.prefix(summaryPreviewCharacters)) + "..."
            : firstPrompt
        let summary = """
        Project: \(session.projectName)
        Path: \(session.projectPath ?? "Unknown")
        Title: \(session.title)
        First prompt: \(firstPromptPreview)
        Tools used: \(tools.isEmpty ? "None" : tools.map { "agent-do \($0)" }.joined(separator: ", "))
        """
        chunks.append(.init(
            id: "\(session.id):summary",
            sessionID: session.id,
            messageID: nil,
            index: 0,
            type: .summary,
            content: summary,
            metadata: [
                "chunk_type": HolyArchiveChunkType.summary.rawValue,
                "session_id": session.id,
                "project_name": session.projectName,
                "harness": session.harness.rawValue,
                "tools": json(tools),
            ],
            embedding: nil,
            embeddingModel: nil,
            createdAt: createdAt
        ))

        var packed: [(messages: [HolyArchiveMessage], content: String)] = []
        var currentMessages: [HolyArchiveMessage] = []
        var currentLines: [String] = []
        var currentTokens = 0
        for message in messages {
            let rendered = "[\(message.role.rawValue)]: \(message.content)"
            let estimate = max(1, rendered.count / 4)
            if !currentMessages.isEmpty, currentTokens + estimate > targetTokens {
                packed.append((currentMessages, currentLines.joined(separator: "\n\n")))
                currentMessages = []
                currentLines = []
                currentTokens = 0
            }
            currentMessages.append(message)
            currentLines.append(rendered)
            currentTokens += estimate
        }
        if !currentMessages.isEmpty {
            packed.append((currentMessages, currentLines.joined(separator: "\n\n")))
        }

        for (offset, pack) in packed.enumerated() {
            chunks.append(.init(
                id: "\(session.id):turn:\(offset)",
                sessionID: session.id,
                messageID: pack.messages.first?.id,
                index: chunks.count,
                type: .turn,
                content: pack.content,
                metadata: [
                    "chunk_type": HolyArchiveChunkType.turn.rawValue,
                    "session_id": session.id,
                    "message_ids": json(pack.messages.map(\.id)),
                    "token_count": String(max(1, pack.content.count / 4)),
                ],
                embedding: nil,
                embeddingModel: nil,
                createdAt: createdAt
            ))
        }

        guard let regex = try? NSRegularExpression(
            pattern: #"agent-do\s+(\S+)(?:\s+(.+?))?$"#,
            options: [.anchorsMatchLines]
        ) else { return chunks }
        for message in messages {
            let range = NSRange(message.content.startIndex..<message.content.endIndex, in: message.content)
            for match in regex.matches(in: message.content, range: range) {
                guard match.numberOfRanges > 1,
                      let toolRange = Range(match.range(at: 1), in: message.content) else { continue }
                let tool = String(message.content[toolRange])
                let command: String
                if match.numberOfRanges > 2,
                   let commandRange = Range(match.range(at: 2), in: message.content) {
                    command = String(message.content[commandRange])
                } else {
                    command = ""
                }
                let lower = max(message.content.startIndex, message.content.index(
                    message.content.startIndex,
                    offsetBy: max(0, message.content.distance(from: message.content.startIndex, to: toolRange.lowerBound) - 200)
                ))
                let upperDistance = min(
                    message.content.count,
                    message.content.distance(from: message.content.startIndex, to: toolRange.upperBound) + 200
                )
                let upper = message.content.index(message.content.startIndex, offsetBy: upperDistance)
                let context = String(message.content[lower..<upper])
                chunks.append(.init(
                    id: "\(session.id):tool:\(chunks.count)",
                    sessionID: session.id,
                    messageID: message.id,
                    index: chunks.count,
                    type: .toolUsage,
                    content: "Tool: agent-do \(tool)\n"
                        + (command.isEmpty ? "" : "Command: \(command)\n")
                        + "Context: \(context.trimmingCharacters(in: .whitespacesAndNewlines))",
                    metadata: [
                        "chunk_type": HolyArchiveChunkType.toolUsage.rawValue,
                        "session_id": session.id,
                        "message_id": message.id,
                        "tool": "agent-do-\(tool)",
                        "command": command,
                    ],
                    embedding: nil,
                    embeddingModel: nil,
                    createdAt: createdAt
                ))
            }
        }
        return chunks
    }

    private static func json<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "[]" }
        return String(bytes: data, encoding: .utf8) ?? "[]"
    }
}

enum HolyArchiveTagger {
    private struct Pattern {
        let regex: NSRegularExpression
        let tag: (NSTextCheckingResult, String) -> String?
        let score: Double
        let once: Bool
    }

    static func tags(session: HolyArchiveSession, messages: [HolyArchiveMessage]) -> [String] {
        let corpus = ([session.title, session.firstPrompt, session.lastPrompt, session.lastResponse]
            + messages.map(\.content)).joined(separator: "\n")
        var scores: [String: Double] = [:]
        for pattern in patterns {
            let range = NSRange(corpus.startIndex..<corpus.endIndex, in: corpus)
            let matches = pattern.regex.matches(in: corpus, range: range)
            let selected = pattern.once ? Array(matches.prefix(1)) : matches
            for match in selected {
                guard let tag = pattern.tag(match, corpus)?.lowercased() else { continue }
                scores[tag, default: 0] += pattern.score
            }
        }
        scores["project:\(session.projectName.lowercased())", default: 0] += 0.5
        scores["harness:\(session.harness.rawValue)", default: 0] += 0.5
        return scores.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return $0.key < $1.key
        }.prefix(15).map(\.key)
    }

    private static let patterns: [Pattern] = {
        var result: [Pattern] = []
        func add(
            _ source: String,
            tag: String,
            score: Double,
            once: Bool = false,
            options: NSRegularExpression.Options = [.caseInsensitive]
        ) {
            guard let regex = try? NSRegularExpression(pattern: source, options: options) else { return }
            result.append(.init(regex: regex, tag: { _, _ in tag }, score: score, once: once))
        }
        if let regex = try? NSRegularExpression(pattern: #"\bagent-do\s+([A-Za-z0-9_-]+)"#, options: [.caseInsensitive]) {
            result.append(.init(regex: regex, tag: { match, text in
                guard let range = Range(match.range(at: 1), in: text) else { return nil }
                return "tool:agent-do-\(text[range])"
            }, score: 2, once: false))
        }
        let commandPatterns: [(String, String)] = [
            (#"\bgit\s+(?:commit|push|pull|rebase|merge|branch|checkout)\b"#, "tool:git"),
            (#"\bnpm\s+(?:install|run|test|build|start)\b"#, "tool:npm"),
            (#"\bdocker\s+(?:build|run|compose|push|pull)\b"#, "tool:docker"),
            (#"\b(?:pytest|python\s+-m\s+pytest)\b"#, "tool:pytest"),
            (#"\b(?:rg|ripgrep)\b"#, "tool:ripgrep"), (#"\blsp_[A-Za-z0-9_]+\b"#, "tool:lsp"),
            (#"\bast_grep\b"#, "tool:ast-grep"), (#"\bgrep\b"#, "tool:grep"),
            (#"\bfind\b"#, "tool:find"), (#"\bls\b"#, "tool:ls"), (#"\bcat\b"#, "tool:cat"),
            (#"\bsed\b"#, "tool:sed"), (#"\bawk\b"#, "tool:awk"), (#"\bjq\b"#, "tool:jq"),
            (#"\bcurl\b"#, "tool:curl"), (#"\bwget\b"#, "tool:wget"), (#"\b(?:vim|vi)\b"#, "tool:vim"),
            (#"\btmux\b"#, "tool:tmux"), (#"\b(?:vscode|code)\b"#, "tool:vscode"),
        ]
        for (source, tag) in commandPatterns { add(source, tag: tag, score: 2) }

        let activities: [(String, String)] = [
            (#"\b(?:fix|debug|troubleshoot|diagnose|trace|profile)\b"#, "debugging"),
            (#"\b(?:implement|add|create|build|write|develop)\b"#, "implementing"),
            (#"\b(?:refactor|restructure|reorganize|rewrite|clean|simplify)\b"#, "refactoring"),
            (#"\b(?:test|spec|coverage|assert|validate|verify)\b"#, "testing"),
            (#"\b(?:document|comment|explain|describe|annotate)\b"#, "documenting"),
            (#"\b(?:review|audit|analyze|inspect|examine)\b"#, "reviewing"),
            (#"\b(?:optimize|improve|enhance|speed|performance)\b"#, "optimizing"),
            (#"\b(?:deploy|release|publish|ship|launch)\b"#, "deploying"),
            (#"\b(?:migrate|upgrade|update|patch|version)\b"#, "migrating"),
            (#"\b(?:integrate|connect|link|bind|wire)\b"#, "integrating"),
        ]
        for (source, tag) in activities { add(source, tag: tag, score: 1.5, once: true) }

        let technologies: [(String, String)] = [
            ("react", "react"), ("vue", "vue"), ("angular", "angular"), ("svelte", "svelte"),
            ("next(?:js|\\.js)?", "nextjs"), ("nuxt", "nuxt"), ("astro", "astro"),
            ("python", "python"), ("javascript|\\bjs\\b", "javascript"),
            ("typescript|\\bts\\b", "typescript"), ("ruby", "ruby"), ("java", "java"),
            ("golang|\\bgo\\b", "go"), ("rust", "rust"), ("c\\+\\+|\\bcpp\\b", "cpp"),
            ("c#|csharp", "csharp"), ("php", "php"), ("postgres(?:ql)?", "postgres"),
            ("mysql", "mysql"), ("sqlite", "sqlite"), ("mongodb|mongo", "mongodb"),
            ("redis", "redis"), ("firebase", "firebase"), ("dynamodb", "dynamodb"),
            ("prisma", "prisma"), ("drizzle", "drizzle"), ("typeorm", "typeorm"),
            ("sqlalchemy", "sqlalchemy"), ("sequelize", "sequelize"), ("jest", "jest"),
            ("vitest", "vitest"), ("mocha", "mocha"), ("rspec", "rspec"),
            ("unittest", "unittest"), ("webpack", "webpack"), ("vite", "vite"),
            ("esbuild", "esbuild"), ("rollup", "rollup"), ("pnpm", "pnpm"), ("yarn", "yarn"),
            ("cloudflare", "cloudflare"), ("aws", "aws"), ("azure", "azure"), ("gcp|google\\s+cloud", "gcp"),
            ("vercel", "vercel"), ("netlify", "netlify"), ("heroku", "heroku"),
            ("docker", "docker"), ("kubernetes|k8s", "kubernetes"), ("express", "express"),
            ("fastapi", "fastapi"), ("django", "django"), ("rails", "rails"),
            ("flask", "flask"), ("hono", "hono"), ("fastify", "fastify"),
            ("graphql", "graphql"), ("rest", "rest"), ("git", "git"),
            ("ai|llm|gpt", "ai"), ("api", "api"), ("auth|authentication", "auth"),
            ("cache|caching", "caching"), ("search", "search"), ("index|indexing", "indexing"),
        ]
        for (source, tag) in technologies {
            add("\\b(?:\(source))\\b", tag: tag, score: 1)
        }
        return result
    }()
}

actor HolyArchiveIndexer {
    static let startupWindowHours = 48

    private let repository: HolyArchiveRepository
    private let registry: HolyArchiveProviderRegistry
    private let pacer: HolyArchiveWritePacer

    init(
        repository: HolyArchiveRepository,
        registry: HolyArchiveProviderRegistry = .init(),
        pacer: HolyArchiveWritePacer = .init()
    ) {
        self.repository = repository
        self.registry = registry
        self.pacer = pacer
    }

    func fullReindex(
        metadataOnly: Bool = false,
        progress: (@Sendable (HolyArchiveIndexProgress) async -> Void)? = nil
    ) async -> HolyArchiveIndexReceipt {
        let started = Date()
        var receipt = HolyArchiveIndexReceipt()
        var work: [(any HolyArchiveProviding, URL)] = []
        await progress?(.init(phase: .discovering, completed: 0, total: registry.availableProviders.count, detail: "Finding provider archives"))
        for provider in registry.availableProviders {
            do {
                work += try provider.discoverSessionFiles().map { (provider, $0) }
            } catch {
                receipt.failures.append("\(provider.harness.displayName) discovery: \(error.localizedDescription)")
            }
        }
        return await index(
            work: work,
            metadataOnly: metadataOnly,
            started: started,
            receipt: receipt,
            progress: progress
        )
    }

    func incrementalUpdate(
        maxAgeHours: Int? = nil,
        progress: (@Sendable (HolyArchiveIndexProgress) async -> Void)? = nil
    ) async -> HolyArchiveIndexReceipt {
        let started = Date()
        var receipt = HolyArchiveIndexReceipt()
        var work: [(any HolyArchiveProviding, URL)] = []
        let cutoff = maxAgeHours.map { Date.now.addingTimeInterval(TimeInterval(-$0 * 3600)) }
        for provider in registry.availableProviders {
            if cutoff != nil, !provider.harness.supportsFastDiscovery { continue }
            do {
                let files = try provider.discoverSessionFiles()
                let indexed = try repository.indexRows(harness: provider.harness)
                let byPath = Dictionary(
                    indexed.map { ($0.rawPath, $0) },
                    uniquingKeysWith: { _, latest in latest }
                )
                let byID = Dictionary(uniqueKeysWithValues: indexed.map { ($0.sessionID, $0) })
                let hasBacklog = files.count > indexed.count
                for file in files {
                    let mtime = try provider.modificationDate(for: file)
                    if let cutoff, !hasBacklog, mtime < cutoff { continue }
                    let known = byPath[file.path] ?? byID[file.deletingPathExtension().lastPathComponent]
                    if let known, mtime <= known.indexedAt { continue }
                    work.append((provider, file))
                }
            } catch {
                receipt.failures.append("\(provider.harness.displayName) update: \(error.localizedDescription)")
            }
        }
        return await index(
            work: work,
            metadataOnly: false,
            started: started,
            receipt: receipt,
            progress: progress
        )
    }

    func indexPaths(
        provider: any HolyArchiveProviding,
        paths: [URL],
        progress: (@Sendable (HolyArchiveIndexProgress) async -> Void)? = nil
    ) async -> HolyArchiveIndexReceipt {
        let indexed = (try? repository.indexRows(harness: provider.harness)) ?? []
        let byPath = Dictionary(
            indexed.map { ($0.rawPath, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        var work: [(any HolyArchiveProviding, URL)] = []
        var receipt = HolyArchiveIndexReceipt()
        for path in paths {
            do {
                let mtime = try provider.modificationDate(for: path)
                if let existing = byPath[path.path],
                   HolyArchiveFileTime.matches(mtime, existing.fileMTime) { continue }
                work.append((provider, path))
            } catch {
                receipt.failures.append("\(path.path): \(error.localizedDescription)")
            }
        }
        return await index(
            work: work,
            metadataOnly: false,
            started: .now,
            receipt: receipt,
            progress: progress
        )
    }

    private func index(
        work: [(any HolyArchiveProviding, URL)],
        metadataOnly: Bool,
        started: Date,
        receipt initialReceipt: HolyArchiveIndexReceipt,
        progress: (@Sendable (HolyArchiveIndexProgress) async -> Void)?
    ) async -> HolyArchiveIndexReceipt {
        var receipt = initialReceipt
        var parentLinks: [(String, String)] = []
        var rowsSinceCheckpoint = 0
        var completedAllWork = true
        let initialProgress = HolyArchiveIndexProgress(
            phase: .indexing,
            completed: 0,
            total: work.count,
            detail: work.isEmpty ? "No changed provider sessions" : "Preparing resumable ingest"
        )
        try? repository.saveIndexProgress(initialProgress)
        await progress?(initialProgress)
        for (position, item) in work.enumerated() {
            if Task.isCancelled {
                completedAllWork = false
                receipt.failures.append("Archive ingest paused after \(position) of \(work.count) sessions.")
                break
            }
            let (provider, path) = item
            await progress?(.init(
                phase: .indexing,
                completed: position,
                total: work.count,
                detail: "\(provider.harness.displayName): \(path.lastPathComponent)"
            ))
            do {
                guard var (session, messages) = try provider.parseSession(at: path) else { continue }
                messages = synthesizedMessages(for: session, ifEmpty: messages)
                messages = Self.storageMessages(sessionID: session.id, messages: messages)
                session.firstPrompt = Self.indexPreview(session.firstPrompt, prefixCount: 200)
                session.lastPrompt = Self.indexPreview(session.lastPrompt, prefixCount: 2_000)
                session.lastResponse = Self.indexPreview(session.lastResponse, prefixCount: 500)
                session.messageCount = messages.count
                session.turnCount = messages.filter { $0.role == .user }.count
                session.autoTags = HolyArchiveTagger.tags(session: session, messages: messages)
                session.resumeCommand = provider.resumeCommand(for: session)
                session.indexedAt = .now
                let chunks = metadataOnly ? [] : HolyArchiveChunker.chunks(session: session, messages: messages)
                let writtenRows = try await persist(
                    session: session,
                    messages: messages,
                    chunks: chunks,
                    metadataOnly: metadataOnly
                )
                rowsSinceCheckpoint += writtenRows
                if let parentID = session.parentID { parentLinks.append((session.id, parentID)) }
                receipt.sessionsIndexed += 1
                receipt.messagesIndexed += metadataOnly ? 0 : messages.count
                receipt.chunksCreated += chunks.count
                let storedProgress = HolyArchiveIndexProgress(
                    phase: .indexing,
                    completed: position + 1,
                    total: work.count,
                    detail: "\(provider.harness.displayName): \(path.lastPathComponent)"
                )
                try repository.saveIndexProgress(storedProgress)
                if rowsSinceCheckpoint >= pacer.budget.checkpointEveryRows {
                    try repository.checkpointWAL()
                    rowsSinceCheckpoint = 0
                }
            } catch {
                receipt.failures.append("\(provider.harness.displayName) \(path.lastPathComponent): \(error.localizedDescription)")
            }
        }
        do {
            for batch in Self.batches(parentLinks, maximumCount: pacer.budget.rowsPerTransaction) {
                try repository.applyParentLinks(batch.map { (childID: $0.0, parentID: $0.1) })
                await pacer.yield(afterWritingRows: batch.count)
            }
            receipt.projectsUpdated = try repository.replaceProjectStats()
        } catch {
            receipt.failures.append("Archive finishing: \(error.localizedDescription)")
        }
        await progress?(.init(phase: .finishing, completed: work.count, total: work.count, detail: "Archive ready"))
        if completedAllWork { try? repository.clearIndexProgress() }
        try? repository.checkpointWAL()
        receipt.elapsedMilliseconds = Date().timeIntervalSince(started) * 1000
        return receipt
    }

    private func persist(
        session: HolyArchiveSession,
        messages: [HolyArchiveMessage],
        chunks: [HolyArchiveChunk],
        metadataOnly: Bool
    ) async throws -> Int {
        if metadataOnly {
            try repository.replaceMetadata(session: session)
            await pacer.yield(afterWritingRows: 1)
            return 1
        }

        let token = try repository.beginReplacement(
            sessionID: session.id,
            expectedMessageCount: messages.count,
            expectedChunkCount: chunks.count
        )
        do {
            for batch in Self.batches(messages, maximumCount: pacer.budget.rowsPerTransaction) {
                try repository.stage(messages: batch, for: token)
                await pacer.yield(afterWritingRows: batch.count)
            }
            for batch in Self.batches(chunks, maximumCount: pacer.budget.rowsPerTransaction) {
                try repository.stage(chunks: batch, for: token)
                await pacer.yield(afterWritingRows: batch.count)
            }
            try repository.finishReplacement(session: session, token: token)
            await pacer.yield(afterWritingRows: 1 + messages.count + chunks.count)
            return 1 + messages.count + chunks.count
        } catch {
            try? repository.discardReplacement(token)
            throw error
        }
    }

    private func synthesizedMessages(
        for session: HolyArchiveSession,
        ifEmpty messages: [HolyArchiveMessage]
    ) -> [HolyArchiveMessage] {
        guard messages.isEmpty else { return messages }
        var result: [HolyArchiveMessage] = []
        if !session.firstPrompt.isEmpty {
            result.append(.init(
                id: "\(session.id):synthetic:user", sessionID: session.id, role: .user,
                content: session.firstPrompt, timestamp: session.createdAt, sequence: result.count
            ))
        }
        if !session.lastResponse.isEmpty {
            result.append(.init(
                id: "\(session.id):synthetic:assistant", sessionID: session.id, role: .assistant,
                content: session.lastResponse, timestamp: session.modifiedAt, sequence: result.count
            ))
        }
        return result
    }

    private static func indexPreview(_ value: String, prefixCount: Int) -> String {
        guard value.count > prefixCount else { return value }
        return String(value.prefix(prefixCount)) + "..."
    }

    /// Provider message IDs are only session-scoped in real stores. Forked
    /// Claude and Codex sessions can legitimately repeat them, while Archive's
    /// message primary key is global. Namespace by the stable owning session
    /// and sequence before chunk references are built.
    private static func storageMessages(
        sessionID: String,
        messages: [HolyArchiveMessage]
    ) -> [HolyArchiveMessage] {
        messages.enumerated().map { offset, message in
            .init(
                id: "\(sessionID):message:\(offset):\(message.id)",
                sessionID: sessionID,
                role: message.role,
                content: message.content,
                timestamp: message.timestamp,
                sequence: offset
            )
        }
    }

    fileprivate static func embeddingBatches(_ chunks: [HolyArchiveChunk]) -> [[HolyArchiveChunk]] {
        var batches: [[HolyArchiveChunk]] = []
        var current: [HolyArchiveChunk] = []
        var tokenEstimate = 0
        for chunk in chunks {
            let estimate = max(1, min(chunk.content.count, 24_000) / 3)
            if !current.isEmpty, current.count >= 100 || tokenEstimate + estimate > 250_000 {
                batches.append(current)
                current = []
                tokenEstimate = 0
            }
            current.append(chunk)
            tokenEstimate += estimate
        }
        if !current.isEmpty { batches.append(current) }
        return batches
    }

    private static func batches<Element>(
        _ values: [Element],
        maximumCount: Int
    ) -> [[Element]] {
        guard maximumCount > 0 else { return [] }
        return stride(from: 0, to: values.count, by: maximumCount).map { start in
            Array(values[start..<min(start + maximumCount, values.count)])
        }
    }
}

/// Semantic vectors are deliberately generated outside provider ingest. This
/// actor is the single embedding queue, rate-limits provider requests, and
/// commits each returned batch in one bounded Archive-only transaction.
actor HolyArchiveEmbeddingWorker {
    private let repository: HolyArchiveRepository
    private let embedder: (any HolyArchiveEmbeddingProviding)?
    private let pacer: HolyArchiveWritePacer
    private let minimumRequestIntervalNanoseconds: UInt64
    private var lastRequestAt: ContinuousClock.Instant?

    init(
        repository: HolyArchiveRepository,
        embedder: (any HolyArchiveEmbeddingProviding)? = HolyArchiveEmbeddingProviderFactory.makeConfigured(),
        pacer: HolyArchiveWritePacer = .init(),
        minimumRequestIntervalNanoseconds: UInt64 = 250_000_000
    ) {
        self.repository = repository
        self.embedder = embedder
        self.pacer = pacer
        self.minimumRequestIntervalNanoseconds = minimumRequestIntervalNanoseconds
    }

    func generateMissingEmbeddings(
        progress: (@Sendable (HolyArchiveIndexProgress) async -> Void)? = nil
    ) async -> HolyArchiveIndexReceipt {
        let started = Date()
        var receipt = HolyArchiveIndexReceipt()
        guard let embedder, embedder.isAvailable else {
            receipt.failures.append("Semantic indexing is unavailable because the selected embedding provider has no API key.")
            return receipt
        }
        do {
            let rows = try repository.chunksWithoutEmbeddings(limit: 100_000)
            await progress?(.init(
                phase: .embedding,
                completed: 0,
                total: rows.count,
                detail: "\(embedder.displayName) queue"
            ))
            var completed = 0
            var rowsSinceCheckpoint = 0
            for batch in HolyArchiveIndexer.embeddingBatches(rows) {
                if Task.isCancelled {
                    receipt.failures.append("Embedding queue paused after \(completed) of \(rows.count) chunks.")
                    break
                }
                do {
                    await waitForRequestBudget()
                    let vectors = try await embedder.embed(batch.map(\.content), purpose: .document)
                    guard vectors.count == batch.count else {
                        throw HolyArchiveEmbeddingError.invalidResponse(
                            "Expected \(batch.count) vectors, received \(vectors.count)."
                        )
                    }
                    let writes = zip(batch, vectors).map { row, vector in
                        HolyArchiveEmbeddingWrite(
                            chunkID: row.id,
                            embedding: vector,
                            model: embedder.model
                        )
                    }
                    try repository.storeEmbeddings(writes)
                    receipt.embeddingsCreated += writes.count
                    rowsSinceCheckpoint += writes.count
                    await pacer.yield(afterWritingRows: writes.count)
                    if rowsSinceCheckpoint >= pacer.budget.checkpointEveryRows {
                        try repository.checkpointWAL()
                        rowsSinceCheckpoint = 0
                    }
                } catch {
                    receipt.failures.append("Embedding batch at \(completed): \(error.localizedDescription)")
                }
                completed += batch.count
                await progress?(.init(
                    phase: .embedding,
                    completed: completed,
                    total: rows.count,
                    detail: "\(embedder.displayName) queue"
                ))
            }
            try? repository.checkpointWAL()
        } catch {
            receipt.failures.append("Embedding backfill: \(error.localizedDescription)")
        }
        receipt.elapsedMilliseconds = Date().timeIntervalSince(started) * 1_000
        return receipt
    }

    private func waitForRequestBudget() async {
        let clock = ContinuousClock()
        if let lastRequestAt {
            let deadline = lastRequestAt.advanced(by: .nanoseconds(Int64(minimumRequestIntervalNanoseconds)))
            if clock.now < deadline { try? await clock.sleep(until: deadline) }
        }
        lastRequestAt = clock.now
    }
}
