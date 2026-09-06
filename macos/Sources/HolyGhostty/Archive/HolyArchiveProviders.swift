import CryptoKit
import Foundation
import SQLite3

struct HolyArchiveProviderRegistry: Sendable {
    let providers: [any HolyArchiveProviding]

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        providers = [
            HolyClaudeArchiveProvider(homeDirectory: homeDirectory),
            HolyCodexArchiveProvider(homeDirectory: homeDirectory),
            HolyDroidArchiveProvider(homeDirectory: homeDirectory),
            HolyCursorArchiveProvider(homeDirectory: homeDirectory),
            HolyOpenCodeArchiveProvider(homeDirectory: homeDirectory),
        ]
    }

    init(providers: [any HolyArchiveProviding]) {
        self.providers = providers
    }

    func provider(for harness: HolyArchiveHarness) -> (any HolyArchiveProviding)? {
        providers.first { $0.harness == harness }
    }

    var availableProviders: [any HolyArchiveProviding] {
        providers.filter(\.isAvailable)
    }
}

/// A project label is derived only from provider evidence about where the
/// session ran. Harness stores are archives, not projects, and `/` carries no
/// useful identity. Keeping the path and label in one value prevents search,
/// grouping, and presentation from disagreeing about the same session.
struct HolyArchiveProjectIdentity: Equatable, Sendable {
    static let missingName = "(no project)"

    let path: String?
    let name: String

    init(candidatePath: String?, homeDirectory: URL) {
        guard let raw = candidatePath?.holyArchiveNilIfBlank,
              raw.hasPrefix("/")
        else {
            path = nil
            name = Self.missingName
            return
        }

        let resolved = URL(fileURLWithPath: raw).standardizedFileURL.path
        guard resolved != "/", !Self.isHarnessStorage(resolved, homeDirectory: homeDirectory) else {
            path = nil
            name = Self.missingName
            return
        }

        path = resolved
        name = URL(fileURLWithPath: resolved).lastPathComponent.holyArchiveNilIfBlank
            ?? Self.missingName
    }

    private static func isHarnessStorage(_ path: String, homeDirectory: URL) -> Bool {
        let home = homeDirectory.standardizedFileURL.path
        guard path.hasPrefix(home + "/") else { return false }

        let relative = String(path.dropFirst(home.count + 1))
        let components = relative.split(separator: "/").map(String.init)
        guard let first = components.first else { return true }
        if first == ".codex" || first == ".claude" || first.hasPrefix(".claude-")
            || first == ".factory" {
            return true
        }
        if components.starts(with: [".cache", "opensession"])
            || components.starts(with: [".local", "share", "opencode"])
            || components.starts(with: ["Library", "Application Support", "Cursor"])
            || components.starts(with: ["Documents", "Codex"]) {
            return true
        }
        return false
    }
}

// MARK: - Claude Code

struct HolyClaudeArchiveProvider: HolyArchiveProviding {
    let harness = HolyArchiveHarness.claudeCode
    let homeDirectory: URL

    var sessionsDirectory: URL {
        homeDirectory.appendingPathComponent(".claude/projects", isDirectory: true)
    }

    func discoverSessionFiles() throws -> [URL] {
        try allSessionDirectories().flatMap { root in
            try HolyArchiveFiles.childDirectories(of: root).flatMap { project in
                try HolyArchiveFiles.files(in: project, extension: "jsonl")
            }
        }
    }

    func discoverSessionFiles(forProjectPath projectPath: String) throws -> [URL]? {
        let encoded = Self.encodeProjectPath(projectPath)
        return try allSessionDirectories().flatMap { root in
            let directory = root.appendingPathComponent(encoded, isDirectory: true)
            guard FileManager.default.fileExists(atPath: directory.path) else { return [URL]() }
            return try HolyArchiveFiles.files(in: directory, extension: "jsonl")
        }
    }

    func parseSession(at url: URL) throws -> (HolyArchiveSession, [HolyArchiveMessage])? {
        let rows = try HolyArchiveJSON.lines(at: url)
        let fileMTime = try modificationDate(for: url)
        var sessionID = url.deletingPathExtension().lastPathComponent
        var cwd: String?
        var version: String?
        var branch: String?
        var model: String?
        var sidechain = false
        var messages: [HolyArchiveMessage] = []
        var taskInvocations: [[String: Any]] = []

        for row in rows {
            let type = row.string("type")
            if type == "file-history-snapshot" || type == "progress" { continue }
            guard type == "user" || type == "assistant" else { continue }

            if type == "user" {
                cwd = cwd ?? row.string("cwd")
                version = version ?? row.string("version")
                branch = branch ?? row.string("gitBranch")
                sessionID = row.string("sessionId")?.holyArchiveNilIfBlank ?? sessionID
                sidechain = sidechain || row.bool("isSidechain")
            }

            let message = row.dictionary("message") ?? [:]
            let role = HolyArchiveJSON.role(message.string("role") ?? type)
            if role == .assistant, model == nil {
                model = message.string("model")?.holyArchiveNilIfBlank
            }
            let content = HolyArchiveJSON.messageContent(
                message["content"],
                includeToolResults: role != .user
            )
            guard !content.isEmpty,
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<system-reminder>")
            else { continue }
            messages.append(.init(
                id: row.string("uuid") ?? "\(sessionID)_\(messages.count)",
                sessionID: sessionID,
                role: role,
                content: content,
                timestamp: HolyArchiveDate.parse(row["timestamp"]),
                sequence: messages.count
            ))

            if role == .assistant, let blocks = message["content"] as? [[String: Any]] {
                for block in blocks where block.string("name") == "Task" {
                    let input = block.dictionary("input") ?? [:]
                    guard let childType = input.string("subagent_type")?.holyArchiveNilIfBlank else { continue }
                    taskInvocations.append([
                        "subagent_type": childType,
                        "timestamp": row["timestamp"] as Any,
                        "description": input.string("description") ?? "",
                    ])
                }
            }
        }

        guard !messages.isEmpty else { return nil }
        let projectDirectory = url.deletingLastPathComponent().lastPathComponent
        let project = HolyArchiveProjectIdentity(candidatePath: cwd, homeDirectory: homeDirectory)
        let firstPrompt = HolyArchiveText.firstRealPrompt(in: messages)
        var childType: String?
        var isChild = sidechain
        if sidechain {
            childType = "sidechain"
        } else if let detected = Self.workerType(prompt: firstPrompt, projectDirectory: projectDirectory) {
            isChild = true
            childType = detected
        }
        let lastPrompt = HolyArchiveText.lastRealPrompt(in: messages)
        let lastResponse = HolyArchiveText.lastRealResponse(in: messages)
        let createdAt = messages.compactMap(\.timestamp).min() ?? fileMTime
        let extra = [
            "version": version ?? "",
            "git_branch": branch ?? "",
            "task_invocations": HolyArchiveJSON.string(taskInvocations) ?? "[]",
        ]
        var session = HolyArchiveSession(
            id: sessionID,
            harness: harness,
            rawPath: url.path,
            projectPath: project.path,
            projectName: project.name,
            title: firstPrompt.holyArchiveFirstLine.map { HolyArchiveText.preview($0, limit: 80) } ?? "Claude Code Session",
            firstPrompt: firstPrompt,
            lastPrompt: lastPrompt,
            lastResponse: lastResponse,
            createdAt: createdAt,
            modifiedAt: fileMTime,
            isChild: isChild,
            childType: childType,
            parentID: nil,
            model: model,
            toolCalls: [],
            tokensUsed: nil,
            summary: nil,
            contentHash: HolyArchiveContentHash.make(firstPrompt: firstPrompt, lastResponse: lastResponse),
            extra: extra,
            resumeCommand: nil,
            messageCount: messages.count,
            turnCount: messages.filter { $0.role == .user }.count,
            fileMTime: fileMTime,
            indexedAt: .now,
            autoTags: []
        )
        session.resumeCommand = resumeCommand(for: session)
        return (session, messages)
    }

    func resumeCommand(for session: HolyArchiveSession) -> String? {
        let components = URL(fileURLWithPath: session.rawPath).pathComponents
        guard let alternate = components.first(where: { $0.hasPrefix(".claude-") }) else {
            return "claude --resume \(session.id)"
        }
        let suffix = alternate.dropFirst(".claude-".count)
        let commandFile = homeDirectory
            .appendingPathComponent(alternate, isDirectory: true)
            .appendingPathComponent(".resume-cmd")
        if let command = try? String(contentsOf: commandFile, encoding: .utf8).holyArchiveNilIfBlank {
            return "\(command) --resume \(session.id)"
        }
        return "claude-\(suffix) --resume \(session.id)"
    }

    static func encodeProjectPath(_ path: String) -> String {
        path.replacingOccurrences(of: #"[^a-zA-Z0-9]"#, with: "-", options: .regularExpression)
    }

    private func allSessionDirectories() throws -> [URL] {
        var roots = [sessionsDirectory]
        let children = try FileManager.default.contentsOfDirectory(
            at: homeDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
        for child in children where child.lastPathComponent.hasPrefix(".claude-") {
            let projects = child.appendingPathComponent("projects", isDirectory: true)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: projects.path, isDirectory: &isDirectory), isDirectory.boolValue {
                roots.append(projects)
            }
        }
        return roots
    }

    private static func workerType(prompt: String, projectDirectory: String) -> String? {
        if let automated = HolyArchiveText.automatedSessionType(prompt) { return automated }
        let lower = String(prompt.prefix(800)).lowercased()
        let path = projectDirectory.lowercased()
        if lower.trimmingCharacters(in: .whitespacesAndNewlines) == "warmup" { return "warmup" }
        if lower.contains("torus loop") { return "torus-loop" }
        if lower.contains("autopilot") && (lower.contains("no human review") || lower.contains("no questions")) {
            return "autopilot"
        }
        if lower.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("@")
            && (lower.contains("@spirit.md") || lower.contains("@wheel.md")) {
            return "torus-orchestrated"
        }
        if path.contains("merkabah-workers") { return numberedWorker("merkabah", in: path) }
        if path.contains("torusv3-workers") || lower.contains("# worker prompt") && lower.contains("torusv3") {
            return numberedWorker("torusv3", in: path)
        }
        if lower.contains("# worker prompt") && lower.contains("one task") {
            return "torusv3-worker"
        }
        if path.contains("ophanim")
            || lower.contains("@vision.md") && lower.contains("@altar.json")
            || lower.contains("# wings.md") && lower.contains("one task") {
            return "ophanim-worker"
        }
        if prompt.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("# Worker Prompt") {
            return "worker"
        }
        if lower.contains("subagent_type") {
            if let match = lower.firstMatch(#"subagent_type[\"\s:]+([a-zA-Z0-9_-]+)"#, group: 1) {
                return match
            }
            return "task-subagent"
        }
        return nil
    }

    private static func numberedWorker(_ family: String, in value: String) -> String {
        value.firstMatch(#"worker-(\d+)"#, group: 1).map { "\(family)-worker-\($0)" }
            ?? "\(family)-worker"
    }
}

// MARK: - Codex

struct HolyCodexArchiveProvider: HolyArchiveProviding {
    private struct ChildContext {
        let isChild: Bool
        let parentID: String?
        let childType: String?
        let nickname: String?
    }

    let harness = HolyArchiveHarness.codex
    let homeDirectory: URL

    var sessionsDirectory: URL {
        homeDirectory.appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    func discoverSessionFiles() throws -> [URL] {
        try HolyArchiveFiles.recursiveFiles(in: sessionsDirectory, extension: "jsonl")
    }

    func discoverSessionFiles(forProjectPath projectPath: String) throws -> [URL]? {
        // Codex's date tree cannot be narrowed by cwd without reading rows.
        nil
    }

    func parseSession(at url: URL) throws -> (HolyArchiveSession, [HolyArchiveMessage])? {
        let rows = try HolyArchiveJSON.lines(at: url)
        let fileMTime = try modificationDate(for: url)
        let pathStem = url.deletingPathExtension().lastPathComponent
        var sessionMeta: [String: Any] = [:]
        var metaLocked = false
        var eventMessages: [HolyArchiveMessage] = []
        var fallbackMessages: [HolyArchiveMessage] = []
        var tools = Set<String>()
        var model: String?
        var turnCWD: String?
        var timestamps: [Date] = []

        for row in rows {
            if let timestamp = HolyArchiveDate.parse(row["timestamp"]) { timestamps.append(timestamp) }
            switch row.string("type") {
            case "session_meta":
                guard !metaLocked, let payload = row.dictionary("payload") else { continue }
                if payload.string("id") == pathStem {
                    sessionMeta = payload
                    metaLocked = true
                } else if sessionMeta.isEmpty {
                    sessionMeta = payload
                }
            case "turn_context":
                let payload = row.dictionary("payload")
                model = model ?? payload?.string("model")
                turnCWD = turnCWD ?? payload?.string("cwd")?.holyArchiveNilIfBlank
            case "event_msg":
                guard let payload = row.dictionary("payload"),
                      let role = Self.eventRole(payload.string("type")),
                      let content = HolyArchiveJSON.firstString(in: payload, keys: ["text", "content", "message", "delta"])?
                        .holyArchiveNilIfBlank
                else { continue }
                eventMessages.append(.init(
                    id: payload.string("id") ?? "\(pathStem)_event_\(eventMessages.count)",
                    sessionID: pathStem,
                    role: role,
                    content: content,
                    timestamp: HolyArchiveDate.parse(row["timestamp"] ?? payload["timestamp"]),
                    sequence: eventMessages.count
                ))
            case "response_item":
                guard let payload = row.dictionary("payload") else { continue }
                if payload.string("type") == "function_call", let name = payload.string("name") {
                    tools.insert(name)
                }
                guard payload.string("type") == "message",
                      let role = Self.responseRole(payload.string("role"))
                else { continue }
                let content = HolyArchiveJSON.responseItemContent(payload["content"], role: role)
                guard !content.isEmpty else { continue }
                fallbackMessages.append(.init(
                    id: payload.string("id") ?? "\(pathStem)_response_\(fallbackMessages.count)",
                    sessionID: pathStem,
                    role: role,
                    content: content,
                    timestamp: HolyArchiveDate.parse(row["timestamp"] ?? payload["timestamp"]),
                    sequence: fallbackMessages.count
                ))
            default:
                continue
            }
        }

        let sessionID = sessionMeta.string("id") ?? pathStem
        var messages = eventMessages.isEmpty ? fallbackMessages : eventMessages
        messages = messages.enumerated().map { offset, message in
            .init(
                id: message.id,
                sessionID: sessionID,
                role: message.role,
                content: message.content,
                timestamp: message.timestamp,
                sequence: offset
            )
        }
        guard !messages.isEmpty || !sessionMeta.isEmpty else { return nil }
        let project = HolyArchiveProjectIdentity(
            candidatePath: sessionMeta.string("cwd")?.holyArchiveNilIfBlank ?? turnCWD,
            homeDirectory: homeDirectory
        )
        let firstPrompt = HolyArchiveText.firstRealPrompt(in: messages)
        let lastPrompt = HolyArchiveText.lastRealPrompt(in: messages)
        let lastResponse = HolyArchiveText.lastRealResponse(in: messages)
        let child = Self.childContext(from: sessionMeta)
        let threadName = sessionTitles()[sessionID]
        let createdAt = HolyArchiveDate.parse(sessionMeta["timestamp"])
            ?? messages.compactMap(\.timestamp).min()
            ?? timestamps.min()
            ?? fileMTime
        let modifiedAt = timestamps.max() ?? messages.compactMap(\.timestamp).max() ?? fileMTime
        var session = HolyArchiveSession(
            id: sessionID,
            harness: harness,
            rawPath: url.path,
            projectPath: project.path,
            projectName: project.name,
            title: threadName?.holyArchiveNilIfBlank
                ?? firstPrompt.holyArchiveFirstLine.map { HolyArchiveText.preview($0, limit: 80) }
                ?? "Codex Session",
            firstPrompt: firstPrompt,
            lastPrompt: lastPrompt,
            lastResponse: lastResponse,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            isChild: child.isChild,
            childType: child.childType,
            parentID: child.parentID,
            model: model,
            toolCalls: tools.sorted(),
            tokensUsed: nil,
            summary: nil,
            contentHash: HolyArchiveContentHash.make(firstPrompt: firstPrompt, lastResponse: lastResponse),
            extra: [
                "originator": sessionMeta.string("originator") ?? "",
                "cli_version": sessionMeta.string("cli_version") ?? "",
                "model_provider": sessionMeta.string("model_provider") ?? "",
                "agent_nickname": child.nickname ?? "",
                "thread_name": threadName ?? "",
            ],
            resumeCommand: nil,
            messageCount: messages.count,
            turnCount: messages.filter { $0.role == .user }.count,
            fileMTime: fileMTime,
            indexedAt: .now,
            autoTags: []
        )
        session.resumeCommand = resumeCommand(for: session)
        return (session, messages)
    }

    func resumeCommand(for session: HolyArchiveSession) -> String? {
        "codex resume \(session.id)"
    }

    private func sessionTitles() -> [String: String] {
        let url = homeDirectory.appendingPathComponent(".codex/session_index.jsonl")
        guard let rows = try? HolyArchiveJSON.lines(at: url) else { return [:] }
        var result: [String: String] = [:]
        for row in rows {
            guard let id = row.string("id") ?? row.string("thread_id"),
                  let title = row.string("thread_name")?.holyArchiveNilIfBlank
            else { continue }
            result[id] = title
        }
        return result
    }

    private static func eventRole(_ type: String?) -> HolyArchiveMessageRole? {
        switch type {
        case "user_message": .user
        case "agent_message": .assistant
        default: nil
        }
    }

    private static func responseRole(_ role: String?) -> HolyArchiveMessageRole? {
        switch role {
        case "user": .user
        case "assistant": .assistant
        default: nil
        }
    }

    private static func childContext(from meta: [String: Any]) -> ChildContext {
        let source = meta.dictionary("source")
        let subagent = source?.dictionary("subagent")
        let spawn = subagent?.dictionary("thread_spawn")
        let parent = spawn?.string("parent_thread_id")
            ?? subagent?.string("parent_thread_id")
            ?? meta.string("parent_thread_id")
            ?? meta.string("forked_from_id")
        let nickname = spawn?.string("agent_nickname")
            ?? subagent?.string("agent_nickname")
            ?? meta.string("agent_nickname")
        let role = spawn?.string("agent_role")
            ?? subagent?.string("agent_role")
            ?? meta.string("agent_role")
        let isChild = subagent != nil || parent != nil || nickname != nil || role != nil
        return .init(
            isChild: isChild,
            parentID: parent,
            childType: isChild ? role ?? nickname ?? "subagent" : nil,
            nickname: nickname
        )
    }
}

// MARK: - Factory Droid

struct HolyDroidArchiveProvider: HolyArchiveProviding {
    let harness = HolyArchiveHarness.droid
    let homeDirectory: URL

    var sessionsDirectory: URL {
        homeDirectory.appendingPathComponent(".factory/sessions", isDirectory: true)
    }

    func discoverSessionFiles() throws -> [URL] {
        try HolyArchiveFiles.childDirectories(of: sessionsDirectory).flatMap {
            try HolyArchiveFiles.files(in: $0, extension: "jsonl")
        }
    }

    func parseSession(at url: URL) throws -> (HolyArchiveSession, [HolyArchiveMessage])? {
        let rows = try HolyArchiveJSON.lines(at: url)
        let fileMTime = try modificationDate(for: url)
        let sessionID = url.deletingPathExtension().lastPathComponent
        var title = "Untitled Session"
        var cwd: String?
        var model: String?
        var isChild = false
        var childType: String?
        var messages: [HolyArchiveMessage] = []
        var taskInvocations: [[String: Any]] = []

        let settings = url.deletingPathExtension().appendingPathExtension("settings.json")
        if let object = try? HolyArchiveJSON.object(at: settings) {
            model = object.string("model")
        }

        for row in rows {
            if row.string("type") == "session_start" {
                title = HolyArchiveText.preview(
                    row.string("title") ?? row.string("sessionTitle") ?? title,
                    limit: 80
                )
                cwd = row.string("cwd") ?? cwd
                if title.hasPrefix("# Task Tool Invocation") {
                    isChild = true
                    childType = title.firstMatch(#"Subagent type: ([a-zA-Z0-9_-]+)"#, group: 1)
                        ?? "task-subagent"
                }
                continue
            }
            guard row.string("type") == "message",
                  let message = row.dictionary("message") else { continue }
            let role = HolyArchiveJSON.role(message.string("role"))
            guard role == .user || role == .assistant else { continue }
            let content = HolyArchiveJSON.messageContent(message["content"], includeToolResults: role != .user)
            guard !content.isEmpty,
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<system-reminder>")
            else { continue }
            messages.append(.init(
                id: row.string("uuid") ?? "\(sessionID)_\(messages.count)",
                sessionID: sessionID,
                role: role,
                content: content,
                timestamp: HolyArchiveDate.parse(row["timestamp"]),
                sequence: messages.count
            ))
            if role == .assistant, let blocks = message["content"] as? [[String: Any]] {
                for block in blocks where block.string("name") == "Task" {
                    let input = block.dictionary("input") ?? [:]
                    guard let type = input.string("subagent_type") else { continue }
                    taskInvocations.append([
                        "subagent_type": type,
                        "timestamp": row["timestamp"] as Any,
                        "description": input.string("description") ?? "",
                    ])
                }
            }
        }

        guard !messages.isEmpty else { return nil }
        let project = HolyArchiveProjectIdentity(candidatePath: cwd, homeDirectory: homeDirectory)
        let firstPrompt = HolyArchiveText.firstRealPrompt(in: messages)
        if !isChild, let automated = HolyArchiveText.automatedSessionType(firstPrompt) {
            isChild = true
            childType = automated
        }
        let lastPrompt = HolyArchiveText.lastRealPrompt(in: messages)
        let lastResponse = HolyArchiveText.lastRealResponse(in: messages)
        var session = HolyArchiveSession(
            id: sessionID,
            harness: harness,
            rawPath: url.path,
            projectPath: project.path,
            projectName: project.name,
            title: title,
            firstPrompt: firstPrompt,
            lastPrompt: lastPrompt,
            lastResponse: lastResponse,
            createdAt: messages.compactMap(\.timestamp).min() ?? fileMTime,
            modifiedAt: fileMTime,
            isChild: isChild,
            childType: childType,
            parentID: nil,
            model: model,
            toolCalls: [],
            tokensUsed: nil,
            summary: nil,
            contentHash: HolyArchiveContentHash.make(firstPrompt: firstPrompt, lastResponse: lastResponse),
            extra: [
                "settings_path": settings.path,
                "task_invocations": HolyArchiveJSON.string(taskInvocations) ?? "[]",
            ],
            resumeCommand: nil,
            messageCount: messages.count,
            turnCount: messages.filter { $0.role == .user }.count,
            fileMTime: fileMTime,
            indexedAt: .now,
            autoTags: []
        )
        session.resumeCommand = resumeCommand(for: session)
        return (session, messages)
    }

    func resumeCommand(for session: HolyArchiveSession) -> String? {
        "droid --resume \(session.id)"
    }
}

// MARK: - Cursor

struct HolyCursorArchiveProvider: HolyArchiveProviding {
    let harness = HolyArchiveHarness.cursor
    let homeDirectory: URL

    var sessionsDirectory: URL {
        homeDirectory.appendingPathComponent("Library/Application Support/Cursor", isDirectory: true)
    }

    private var databaseURL: URL {
        sessionsDirectory.appendingPathComponent("User/globalStorage/state.vscdb")
    }

    func discoverSessionFiles() throws -> [URL] {
        try HolyArchiveForeignSQLite.withReadOnlyDatabase(at: databaseURL, allowsCopyFallback: true) { database in
            let sql = "SELECT key FROM cursorDiskKV WHERE key LIKE 'backgroundComposerModalInputData:%';"
            return try HolyArchiveForeignSQLite.strings(database, sql: sql).compactMap { key in
                key.split(separator: ":", maxSplits: 1).last.map { id in
                    sessionsDirectory
                        .appendingPathComponent("sessions", isDirectory: true)
                        .appendingPathComponent("\(id).cursor")
                }
            }
        }
    }

    func modificationDate(for url: URL) throws -> Date {
        let writeAheadLog = URL(fileURLWithPath: databaseURL.path + "-wal")
        return try HolyArchiveFiles.newestModificationDate(for: [databaseURL, writeAheadLog])
    }

    func parseSession(at url: URL) throws -> (HolyArchiveSession, [HolyArchiveMessage])? {
        let id = url.deletingPathExtension().lastPathComponent
        let stamp = try modificationDate(for: url)
        return try HolyArchiveForeignSQLite.withReadOnlyDatabase(at: databaseURL, allowsCopyFallback: true) { database in
            guard let inputData = try HolyArchiveForeignSQLite.value(
                database,
                sql: "SELECT value FROM cursorDiskKV WHERE key = ? LIMIT 1;",
                text: "backgroundComposerModalInputData:\(id)"
            ),
            let input = HolyArchiveJSON.object(from: inputData)
            else { return nil }
            let composer = input.dictionary("composerData") ?? input
            let richText = composer["richText"] ?? input["richText"]
            let firstPrompt = Self.lexicalText(richText)
            guard !firstPrompt.isEmpty else { return nil }
            let detailsData = try HolyArchiveForeignSQLite.value(
                database,
                sql: "SELECT value FROM cursorDiskKV WHERE key = ? LIMIT 1;",
                text: "bcCachedDetails:\(id)"
            )
            let details = detailsData.flatMap(HolyArchiveJSON.object(from:)) ?? [:]
            let referencedPath = Self.referencedFilePath(in: richText)
                ?? HolyArchiveJSON.findFirstString(key: "fsPath", in: input)
            let projectPath = referencedPath.map(Self.projectRoot(for:))
            let lastResponse = HolyArchiveJSON.firstString(in: details, keys: ["lastResponse", "last_response"]) ?? ""
            let model = HolyArchiveJSON.firstString(in: details, keys: ["model", "modelName"])
            var messages = [HolyArchiveMessage(
                id: "\(id)_0",
                sessionID: id,
                role: .user,
                content: firstPrompt,
                timestamp: stamp,
                sequence: 0
            )]
            if !lastResponse.isEmpty {
                messages.append(.init(
                    id: "\(id)_1",
                    sessionID: id,
                    role: .assistant,
                    content: lastResponse,
                    timestamp: stamp,
                    sequence: 1
                ))
            }
            let automated = HolyArchiveText.automatedSessionType(firstPrompt)
            let project = HolyArchiveProjectIdentity(
                candidatePath: projectPath,
                homeDirectory: homeDirectory
            )
            let session = HolyArchiveSession(
                id: id,
                harness: harness,
                rawPath: url.path,
                projectPath: project.path,
                projectName: project.name,
                title: HolyArchiveText.preview(firstPrompt.holyArchiveFirstLine ?? "Cursor Session", limit: 80),
                firstPrompt: firstPrompt,
                lastPrompt: firstPrompt,
                lastResponse: HolyArchiveText.preview(lastResponse, limit: 2_000),
                createdAt: stamp,
                modifiedAt: stamp,
                isChild: automated != nil,
                childType: automated,
                parentID: nil,
                model: model,
                toolCalls: [],
                tokensUsed: nil,
                summary: nil,
                contentHash: HolyArchiveContentHash.make(firstPrompt: firstPrompt, lastResponse: lastResponse),
                extra: [:],
                // Cursor does not expose a safe executable resume command.
                // Nil fixes the legacy pseudo-command being exec'd as "#".
                resumeCommand: nil,
                messageCount: messages.count,
                turnCount: 1,
                fileMTime: stamp,
                indexedAt: .now,
                autoTags: []
            )
            return (session, messages)
        }
    }

    func resumeCommand(for session: HolyArchiveSession) -> String? { nil }

    private static func projectRoot(for referencedPath: String) -> String {
        let file = URL(fileURLWithPath: referencedPath).standardizedFileURL
        var candidate = file.deletingLastPathComponent()
        let fileManager = FileManager.default
        while candidate.path != "/" {
            if fileManager.fileExists(atPath: candidate.appendingPathComponent(".git").path)
                || fileManager.fileExists(atPath: candidate.appendingPathComponent("package.json").path) {
                return candidate.path
            }
            candidate.deleteLastPathComponent()
        }
        return file.deletingLastPathComponent().path
    }

    private static func referencedFilePath(in value: Any?) -> String? {
        if let raw = value as? String,
           let data = raw.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) {
            return HolyArchiveJSON.findFirstString(key: "fsPath", in: object)
        }
        guard let value else { return nil }
        return HolyArchiveJSON.findFirstString(key: "fsPath", in: value)
    }

    private static func lexicalText(_ value: Any?) -> String {
        let root: Any?
        if let raw = value as? String,
           let data = raw.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) {
            root = object
        } else {
            root = value
        }
        var parts: [String] = []
        func walk(_ node: Any?) {
            if let dictionary = node as? [String: Any] {
                if let text = dictionary["text"] as? String { parts.append(text) }
                if let mention = dictionary["name"] as? String,
                   dictionary["type"] as? String == "mention" { parts.append("@\(mention)") }
                if let children = dictionary["children"] as? [Any] { children.forEach(walk) }
                if let nested = dictionary["root"] { walk(nested) }
            } else if let array = node as? [Any] {
                array.forEach(walk)
            }
        }
        walk(root)
        return parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - OpenCode

struct HolyOpenCodeArchiveProvider: HolyArchiveProviding {
    private struct SessionDraft {
        let id: String
        let url: URL
        let messages: [HolyArchiveMessage]
        let projectPath: String?
        let model: String?
        let agent: String?
        let parentID: String?
        let title: String?
        let createdAt: Date
        let modifiedAt: Date
    }

    let harness = HolyArchiveHarness.opencode
    let homeDirectory: URL

    var sessionsDirectory: URL {
        homeDirectory.appendingPathComponent(".local/share/opencode", isDirectory: true)
    }

    private var databaseURL: URL { sessionsDirectory.appendingPathComponent("opencode.db") }
    private var storageDirectory: URL { sessionsDirectory.appendingPathComponent("storage", isDirectory: true) }
    private var messageDirectory: URL { storageDirectory.appendingPathComponent("message", isDirectory: true) }
    private var partDirectory: URL { storageDirectory.appendingPathComponent("part", isDirectory: true) }
    private var sessionMetadataDirectory: URL { storageDirectory.appendingPathComponent("session", isDirectory: true) }
    private var virtualDirectory: URL { storageDirectory.appendingPathComponent("sessions", isDirectory: true) }

    func discoverSessionFiles() throws -> [URL] {
        var ids = Set<String>()
        if FileManager.default.fileExists(atPath: databaseURL.path) {
            ids.formUnion(try databaseSessionTimes().keys)
        }
        if FileManager.default.fileExists(atPath: messageDirectory.path) {
            ids.formUnion(try HolyArchiveFiles.childDirectories(of: messageDirectory)
                .map(\.lastPathComponent)
                .filter { $0.hasPrefix("ses_") })
        }
        return ids.sorted().map { virtualDirectory.appendingPathComponent("\($0).opencode") }
    }

    func modificationDate(for url: URL) throws -> Date {
        let id = url.deletingPathExtension().lastPathComponent
        if let milliseconds = try databaseSessionTimes()[id] {
            return Date(timeIntervalSince1970: milliseconds / 1_000)
        }
        let directory = messageDirectory.appendingPathComponent(id, isDirectory: true)
        return try HolyArchiveFiles.newestModificationDate(
            for: HolyArchiveFiles.files(in: directory, extension: "json")
        )
    }

    func parseSession(at url: URL) throws -> (HolyArchiveSession, [HolyArchiveMessage])? {
        let id = url.deletingPathExtension().lastPathComponent
        if try databaseSessionTimes()[id] != nil {
            return try parseDatabaseSession(id: id, virtualURL: url)
        }
        return try parseLegacySession(id: id, virtualURL: url)
    }

    func resumeCommand(for session: HolyArchiveSession) -> String? {
        "opencode --session \(session.id)"
    }

    private func databaseSessionTimes() throws -> [String: Double] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return [:] }
        do {
            return try HolyArchiveForeignSQLite.withReadOnlyDatabase(at: databaseURL) { database in
                var result: [String: Double] = [:]
                try HolyArchiveForeignSQLite.query(database, sql: "SELECT id, time_updated FROM session;") { statement in
                    guard let id = HolyArchiveForeignSQLite.text(statement, 0) else { return }
                    result[id] = sqlite3_column_double(statement, 1)
                }
                return result
            }
        } catch {
            // The legacy file tree remains useful while the live database is
            // briefly locked or mid-migration.
            return [:]
        }
    }

    private func parseDatabaseSession(
        id: String,
        virtualURL: URL
    ) throws -> (HolyArchiveSession, [HolyArchiveMessage])? {
        try HolyArchiveForeignSQLite.withReadOnlyDatabase(at: databaseURL) { database in
            var metadata: [String: Any]?
            try HolyArchiveForeignSQLite.query(
                database,
                sql: "SELECT parent_id, directory, title, model, agent, time_created, time_updated FROM session WHERE id = ?;",
                text: id
            ) { statement in
                metadata = [
                    "parent_id": HolyArchiveForeignSQLite.text(statement, 0) as Any,
                    "directory": HolyArchiveForeignSQLite.text(statement, 1) as Any,
                    "title": HolyArchiveForeignSQLite.text(statement, 2) as Any,
                    "model": HolyArchiveForeignSQLite.text(statement, 3) as Any,
                    "agent": HolyArchiveForeignSQLite.text(statement, 4) as Any,
                    "time_created": sqlite3_column_double(statement, 5),
                    "time_updated": sqlite3_column_double(statement, 6),
                ]
            }
            guard let metadata else { return nil }
            var partTexts: [String: [String]] = [:]
            try HolyArchiveForeignSQLite.query(
                database,
                sql: "SELECT message_id, data FROM part WHERE session_id = ? ORDER BY time_created, id;",
                text: id
            ) { statement in
                guard let messageID = HolyArchiveForeignSQLite.text(statement, 0),
                      let data = HolyArchiveForeignSQLite.text(statement, 1)?.data(using: .utf8),
                      let part = HolyArchiveJSON.object(from: data),
                      part.string("type") == "text",
                      let text = part.string("text")?.holyArchiveNilIfBlank
                else { return }
                partTexts[messageID, default: []].append(text)
            }
            var messages: [HolyArchiveMessage] = []
            var observedModel: String?
            var observedAgent: String?
            try HolyArchiveForeignSQLite.query(
                database,
                sql: "SELECT id, time_created, data FROM message WHERE session_id = ? ORDER BY time_created, id;",
                text: id
            ) { statement in
                guard let messageID = HolyArchiveForeignSQLite.text(statement, 0),
                      let raw = HolyArchiveForeignSQLite.text(statement, 2)?.data(using: .utf8),
                      let message = HolyArchiveJSON.object(from: raw)
                else { return }
                let role = HolyArchiveJSON.role(message.string("role"))
                if role == .assistant {
                    observedModel = Self.modelID(message["model"]) ?? message.string("modelID") ?? observedModel
                    observedAgent = message.string("agent") ?? observedAgent
                }
                let content = partTexts[messageID, default: []].joined(separator: "\n")
                guard !content.isEmpty else { return }
                messages.append(.init(
                    id: messageID,
                    sessionID: id,
                    role: role,
                    content: content,
                    timestamp: HolyArchiveDate.parse(sqlite3_column_double(statement, 1)),
                    sequence: messages.count
                ))
            }
            guard !messages.isEmpty else { return nil }
            let created = Date(timeIntervalSince1970: (metadata["time_created"] as? Double ?? 0) / 1_000)
            let modified = Date(timeIntervalSince1970: (metadata["time_updated"] as? Double ?? 0) / 1_000)
            return finish(.init(
                id: id,
                url: virtualURL,
                messages: messages,
                projectPath: metadata["directory"] as? String,
                model: Self.modelID(metadata["model"]) ?? observedModel,
                agent: metadata["agent"] as? String ?? observedAgent,
                parentID: metadata["parent_id"] as? String,
                title: metadata["title"] as? String,
                createdAt: created,
                modifiedAt: modified
            ))
        }
    }

    private func parseLegacySession(
        id: String,
        virtualURL: URL
    ) throws -> (HolyArchiveSession, [HolyArchiveMessage])? {
        let directory = messageDirectory.appendingPathComponent(id, isDirectory: true)
        let files = try HolyArchiveFiles.files(in: directory, extension: "json").sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !files.isEmpty else { return nil }
        var messages: [HolyArchiveMessage] = []
        var projectPath: String?
        var model: String?
        var agent: String?
        for file in files {
            guard let row = try? HolyArchiveJSON.object(at: file),
                  let messageID = row.string("id") else { continue }
            let path = row.dictionary("path")
            projectPath = path?.string("root") ?? path?.string("cwd") ?? projectPath
            let role = HolyArchiveJSON.role(row.string("role"))
            if role == .assistant {
                model = row.string("modelID") ?? model
                agent = row.string("agent") ?? agent
            }
            let content = try legacyPartContent(messageID: messageID)
            guard !content.isEmpty else { continue }
            let time = row.dictionary("time")
            messages.append(.init(
                id: messageID,
                sessionID: id,
                role: role,
                content: content,
                timestamp: HolyArchiveDate.parse(time?["created"]),
                sequence: messages.count
            ))
        }
        guard !messages.isEmpty else { return nil }
        let metadata = try legacyMetadata(sessionID: id)
        projectPath = metadata?.string("directory") ?? projectPath
        return finish(.init(
            id: id,
            url: virtualURL,
            messages: messages,
            projectPath: projectPath,
            model: model,
            agent: agent,
            parentID: metadata?.string("parentID"),
            title: metadata?.string("title"),
            createdAt: messages.compactMap(\.timestamp).min() ?? .now,
            modifiedAt: try modificationDate(for: virtualURL)
        ))
    }

    private func finish(
        _ draft: SessionDraft
    ) -> (HolyArchiveSession, [HolyArchiveMessage]) {
        let id = draft.id
        let url = draft.url
        let messages = draft.messages
        let projectPath = draft.projectPath
        let model = draft.model
        let agent = draft.agent
        let parentID = draft.parentID
        let title = draft.title
        let createdAt = draft.createdAt
        let modifiedAt = draft.modifiedAt
        let firstPrompt = HolyArchiveText.firstRealPrompt(in: messages)
        let lastPrompt = HolyArchiveText.lastRealPrompt(in: messages)
        let lastResponse = HolyArchiveText.lastRealResponse(in: messages)
        var isChild = parentID?.holyArchiveNilIfBlank != nil
        var childType = isChild ? Self.childType(for: firstPrompt) : nil
        if !isChild, let automated = HolyArchiveText.automatedSessionType(firstPrompt) {
            isChild = true
            childType = automated
        }
        let project = HolyArchiveProjectIdentity(
            candidatePath: projectPath,
            homeDirectory: homeDirectory
        )
        let resolvedTitle = title?.holyArchiveNilIfBlank
            ?? firstPrompt.split(separator: "\n").prefix(5)
                .map(String.init)
                .first(where: { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("<") })
                .map { HolyArchiveText.preview($0, limit: 80) }
            ?? "OpenCode Session"
        var session = HolyArchiveSession(
            id: id,
            harness: harness,
            rawPath: url.path,
            projectPath: project.path,
            projectName: project.name,
            title: resolvedTitle,
            firstPrompt: firstPrompt,
            lastPrompt: lastPrompt,
            lastResponse: lastResponse,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            isChild: isChild,
            childType: childType,
            parentID: parentID,
            model: model,
            toolCalls: [],
            tokensUsed: nil,
            summary: nil,
            contentHash: HolyArchiveContentHash.make(firstPrompt: firstPrompt, lastResponse: lastResponse),
            extra: ["agent": agent ?? ""],
            resumeCommand: nil,
            messageCount: messages.count,
            turnCount: messages.filter { $0.role == .user }.count,
            fileMTime: modifiedAt,
            indexedAt: .now,
            autoTags: []
        )
        session.resumeCommand = resumeCommand(for: session)
        return (session, messages)
    }

    private static func modelID(_ value: Any?) -> String? {
        if let value = value as? String {
            guard let data = value.data(using: .utf8),
                  let object = HolyArchiveJSON.object(from: data) else { return value }
            return object.string("id") ?? object.string("modelID")
        }
        if let object = value as? [String: Any] {
            return object.string("id") ?? object.string("modelID")
        }
        return nil
    }

    private static func childType(for prompt: String) -> String {
        let upper = String(prompt.prefix(500)).uppercased()
        if upper.contains("PROMETHEUS") { return "prometheus" }
        if upper.contains("SINGLE TASK ONLY") { return "single-task" }
        if upper.contains("OH-MY-OPENCODE") { return "oh-my-opencode" }
        if upper.contains("FILE-ANALYSIS") || prompt.hasPrefix("Analyze this file") { return "file-analysis" }
        return "worker"
    }

    private func legacyPartContent(messageID: String) throws -> String {
        let directory = partDirectory.appendingPathComponent(messageID, isDirectory: true)
        return try HolyArchiveFiles.files(in: directory, extension: "json")
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? HolyArchiveJSON.object(at: $0) }
            .filter { $0.string("type") == "text" }
            .compactMap { $0.string("text") }
            .joined(separator: "\n")
    }

    private func legacyMetadata(sessionID: String) throws -> [String: Any]? {
        for directory in try HolyArchiveFiles.childDirectories(of: sessionMetadataDirectory) {
            let candidate = directory.appendingPathComponent("\(sessionID).json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try? HolyArchiveJSON.object(at: candidate)
            }
        }
        return nil
    }
}

// MARK: - Shared provider helpers

enum HolyArchiveContentHash {
    static func make(firstPrompt: String, lastResponse: String) -> String {
        let input = String(firstPrompt.prefix(500)) + "|" + String(lastResponse.prefix(500))
        let digest = Insecure.MD5.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(12).description
    }
}

private enum HolyArchiveFiles {
    static func childDirectories(of url: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsPackageDescendants]
        ).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    static func files(in url: URL, extension fileExtension: String) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsPackageDescendants]
        ).filter { $0.pathExtension.lowercased() == fileExtension.lowercased() }
    }

    static func recursiveFiles(in url: URL, extension fileExtension: String) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsPackageDescendants]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == fileExtension.lowercased() }
            .sorted { $0.path < $1.path }
    }

    static func newestModificationDate(for urls: [URL]) throws -> Date {
        let dates = urls.compactMap {
            try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
        guard let newest = dates.max() else {
            throw CocoaError(.fileNoSuchFile)
        }
        return newest
    }
}

private enum HolyArchiveJSON {
    static func object(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let object = object(from: data) else { throw CocoaError(.fileReadCorruptFile) }
        return object
    }

    static func object(from data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func lines(at url: URL) throws -> [[String: Any]] {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let value = String(data: data, encoding: .utf8) else { return [] }
        return value.split(separator: "\n").compactMap { line in
            object(from: Data(line.utf8))
        }
    }

    static func string(_ object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func role(_ value: String?) -> HolyArchiveMessageRole {
        HolyArchiveMessageRole(rawValue: value ?? "") ?? .unknown
    }

    static func firstString(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    static func messageContent(_ value: Any?, includeToolResults: Bool) -> String {
        if let string = value as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<system-reminder>")
                ? ""
                : string
        }
        guard let blocks = value as? [Any] else {
            return value.map { String(describing: $0) } ?? ""
        }
        return blocks.compactMap { block -> String? in
            if let string = block as? String { return string }
            guard let object = block as? [String: Any] else { return nil }
            if object.string("type") == "text",
               let text = object.string("text"),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<system-reminder>") {
                return text
            }
            if includeToolResults, object.string("type") == "tool_result" {
                let content = String(describing: object["content"] ?? "")
                return "(tool_result: \(String(content.prefix(50)))...)"
            }
            return nil
        }.joined(separator: " ")
    }

    static func responseItemContent(_ value: Any?, role: HolyArchiveMessageRole) -> String {
        guard let blocks = value as? [[String: Any]] else { return messageContent(value, includeToolResults: role != .user) }
        let desired = role == .user ? "input_text" : "output_text"
        return blocks.compactMap { block in
            guard block.string("type") == desired || block.string("type") == "text" else { return nil }
            return block.string("text")
        }.joined(separator: "\n")
    }

    static func findFirstString(key: String, in value: Any) -> String? {
        if let object = value as? [String: Any] {
            if let result = object[key] as? String { return result }
            for nested in object.values {
                if let result = findFirstString(key: key, in: nested) { return result }
            }
        } else if let array = value as? [Any] {
            for nested in array {
                if let result = findFirstString(key: key, in: nested) { return result }
            }
        }
        return nil
    }
}

private extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? { self[key] as? String }
    func bool(_ key: String) -> Bool { self[key] as? Bool ?? false }
    func dictionary(_ key: String) -> [String: Any]? { self[key] as? [String: Any] }
}

private extension String {
    func firstMatch(_ pattern: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: self,
                range: NSRange(startIndex..<endIndex, in: self)
              ),
              group < match.numberOfRanges,
              let range = Range(match.range(at: group), in: self)
        else { return nil }
        return String(self[range])
    }
}

private enum HolyArchiveForeignSQLite {
    static func withReadOnlyDatabase<T>(
        at url: URL,
        allowsCopyFallback: Bool = false,
        _ body: (OpaquePointer) throws -> T
    ) throws -> T {
        do {
            return try withOpenDatabase(at: url, body)
        } catch {
            guard allowsCopyFallback else { throw error }
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("holy-archive-\(UUID().uuidString).vscdb")
            try FileManager.default.copyItem(at: url, to: copy)
            defer { try? FileManager.default.removeItem(at: copy) }
            return try withOpenDatabase(at: copy, body)
        }
    }

    static func query(
        _ database: OpaquePointer,
        sql: String,
        text binding: String? = nil,
        row: (OpaquePointer) throws -> Void
    ) throws {
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepared == SQLITE_OK, let statement else { throw error(database) }
        defer { sqlite3_finalize(statement) }
        if let binding {
            guard sqlite3_bind_text(statement, 1, binding, -1, sqliteTransientDestructorArchive) == SQLITE_OK else {
                throw error(database)
            }
        }
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: try row(statement)
            case SQLITE_DONE: return
            default: throw error(database)
            }
        }
    }

    static func strings(_ database: OpaquePointer, sql: String) throws -> [String] {
        var result: [String] = []
        try query(database, sql: sql) { statement in
            if let value = text(statement, 0) { result.append(value) }
        }
        return result
    }

    static func value(
        _ database: OpaquePointer,
        sql: String,
        text binding: String
    ) throws -> Data? {
        var result: Data?
        try query(database, sql: sql, text: binding) { statement in
            guard result == nil else { return }
            let count = Int(sqlite3_column_bytes(statement, 0))
            guard count > 0, let bytes = sqlite3_column_blob(statement, 0) else { return }
            result = Data(bytes: bytes, count: count)
        }
        return result
    }

    static func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        sqlite3_column_text(statement, index).map { String(cString: $0) }
    }

    private static func withOpenDatabase<T>(
        at url: URL,
        _ body: (OpaquePointer) throws -> T
    ) throws -> T {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let database else {
            if let database { sqlite3_close_v2(database) }
            throw CocoaError(.fileReadUnknown)
        }
        defer { sqlite3_close_v2(database) }
        return try body(database)
    }

    private static func error(_ database: OpaquePointer) -> Error {
        NSError(
            domain: "HolyArchiveSQLite",
            code: Int(sqlite3_errcode(database)),
            userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))]
        )
    }
}

private let sqliteTransientDestructorArchive = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
