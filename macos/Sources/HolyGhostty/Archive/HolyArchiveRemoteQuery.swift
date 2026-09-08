import Foundation

struct HolyArchiveRemoteHost: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let label: String
    let sshDestination: String
    let tmuxSocketName: String?

    init(_ host: HolyRemoteHostRecord) {
        let normalized = host.normalized()
        id = normalized.id
        label = normalized.displayTitle
        sshDestination = normalized.sshDestination
        tmuxSocketName = normalized.tmuxSocketName
    }

    init(id: UUID, label: String, sshDestination: String, tmuxSocketName: String? = nil) {
        self.id = id
        self.label = label
        self.sshDestination = sshDestination
        self.tmuxSocketName = tmuxSocketName
    }
}

struct HolyArchiveRemoteFilter: Codable, Equatable, Sendable {
    let harness: String?
    let project: String?
    let after: Double?
    let before: Double?
    let tags: [String]

    init(_ query: HolyArchiveSearchQuery) {
        harness = query.rawHarness ?? query.harness?.rawValue
        project = query.project?.holyArchiveNilIfBlank
        after = query.after?.timeIntervalSince1970
        before = query.before?.timeIntervalSince1970
        tags = query.tags
    }
}

struct HolyArchiveRemoteRequest: Codable, Equatable, Sendable {
    enum Operation: String, Codable, Hashable, Sendable {
        case parents
        case search
        case children
        case messages
        case annotations
    }

    let operation: Operation
    let filter: HolyArchiveRemoteFilter?
    let text: String?
    let ftsQuery: String?
    let semanticQueryVector: [Float]?
    let sessionID: String?
    let parentID: String?
    let limit: Int
    let offset: Int
    let ftsWeight: Double
    let semanticWeight: Double
    let minimumCosine: Double
    let minimumCombinedScore: Double
    let normalizationFloor: Double
    let supportedSchemaVersion: Int32
    let bundleIdentifiers: [String]

    static func parents(
        query: HolyArchiveSearchQuery,
        limit: Int,
        offset: Int = 0
    ) -> Self {
        base(
            operation: .parents,
            filter: .init(query),
            limit: limit,
            offset: offset
        )
    }

    static func search(
        query: HolyArchiveSearchQuery,
        semanticQueryVector: [Float]? = nil,
        limit: Int
    ) -> Self {
        base(
            operation: .search,
            filter: .init(query),
            text: query.text,
            ftsQuery: HolyArchiveRepository.ftsQuery(query.text),
            semanticQueryVector: semanticQueryVector,
            limit: limit
        )
    }

    static func children(parentID: String, limit: Int = 500) -> Self {
        base(operation: .children, parentID: parentID, limit: limit)
    }

    static func messages(sessionID: String, limit: Int = 250, offset: Int = 0) -> Self {
        base(
            operation: .messages,
            sessionID: sessionID,
            limit: limit,
            offset: offset
        )
    }

    static func annotations(sessionID: String, limit: Int = 500) -> Self {
        base(operation: .annotations, sessionID: sessionID, limit: limit)
    }

    private static func base(
        operation: Operation,
        filter: HolyArchiveRemoteFilter? = nil,
        text: String? = nil,
        ftsQuery: String? = nil,
        semanticQueryVector: [Float]? = nil,
        sessionID: String? = nil,
        parentID: String? = nil,
        limit: Int,
        offset: Int = 0
    ) -> Self {
        let currentBundle = Bundle.main.bundleIdentifier?.holyArchiveNilIfBlank
        let bundles = [currentBundle, "org.holyghostty.app", "com.mitchellh.ghostty"]
            .compactMap { $0 }
            .reduce(into: [String]()) { values, bundle in
                if !values.contains(bundle) { values.append(bundle) }
            }
        return .init(
            operation: operation,
            filter: filter,
            text: text,
            ftsQuery: ftsQuery,
            semanticQueryVector: semanticQueryVector,
            sessionID: sessionID,
            parentID: parentID,
            limit: min(max(1, limit), 500),
            offset: max(0, offset),
            ftsWeight: HolyArchiveHybridSearch.defaultFTSWeight,
            semanticWeight: HolyArchiveHybridSearch.defaultSemanticWeight,
            minimumCosine: HolyArchiveHybridSearch.minimumCosine,
            minimumCombinedScore: HolyArchiveHybridSearch.minimumCombinedScore,
            normalizationFloor: HolyArchiveHybridSearch.normalizationFloor,
            supportedSchemaVersion: HolyArchiveDatabaseSchema.currentUserVersion,
            bundleIdentifiers: bundles
        )
    }
}

struct HolyArchiveRemoteSession: Codable, Equatable, Sendable {
    let id: String
    let harness: String
    let rawPath: String
    let projectPath: String?
    let projectName: String
    let title: String
    let firstPrompt: String
    let lastPrompt: String
    let lastResponse: String
    let createdAt: Double
    let modifiedAt: Double?
    let isChild: Bool
    let childType: String?
    let parentID: String?
    let model: String?
    let toolCalls: [String]
    let tokensUsed: Int?
    let summary: String?
    let contentHash: String
    let extra: [String: String]
    let resumeCommand: String?
    let messageCount: Int
    let turnCount: Int
    let fileMTime: Double
    let indexedAt: Double
    let autoTags: [String]

    private enum CodingKeys: String, CodingKey {
        case id
        case harness
        case rawPath
        case projectPath
        case projectName
        case title
        case firstPrompt
        case lastPrompt
        case lastResponse
        case createdAt
        case modifiedAt
        case isChild
        case childType
        case parentID = "parentId"
        case model
        case toolCalls
        case tokensUsed
        case summary
        case contentHash
        case extra
        case resumeCommand
        case messageCount
        case turnCount
        case fileMTime
        case indexedAt
        case autoTags
    }
}

struct HolyArchiveRemoteMessage: Codable, Equatable, Sendable {
    let id: String
    let sessionID: String
    let role: String
    let content: String
    let timestamp: Double?
    let sequence: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "sessionId"
        case role
        case content
        case timestamp
        case sequence
    }
}

struct HolyArchiveRemoteAnnotation: Codable, Equatable, Sendable {
    let id: Int64
    let sessionID: String
    let timestamp: Double
    let kind: String
    let value: String
    let source: String

    private enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "sessionId"
        case timestamp
        case kind
        case value
        case source
    }
}

struct HolyArchiveRemoteMatch: Codable, Equatable, Sendable {
    let score: Double
    let keywordScore: Double?
    let semanticScore: Double?
    let snippet: String?
    let source: String
}

struct HolyArchiveRemotePage: Codable, Equatable, Sendable {
    let total: Int
    let sessions: [HolyArchiveRemoteSession]
    let messages: [HolyArchiveRemoteMessage]
    let annotations: [HolyArchiveRemoteAnnotation]
    let childCounts: [String: Int]
    let matches: [String: HolyArchiveRemoteMatch]
    let matchingChildren: [String: [HolyArchiveRemoteSession]]

    var rowCount: Int {
        max(1, sessions.count + messages.count + annotations.count)
    }
}

protocol HolyArchiveRemoteQuerying: Sendable {
    func query(_ request: HolyArchiveRemoteRequest, on host: HolyArchiveRemoteHost) async throws
        -> HolyArchiveRemotePage
}

enum HolyArchiveRemoteQueryError: LocalizedError, Equatable {
    case emptyDestination
    case launchFailed(String)
    case commandFailed(host: String, exitCode: Int32, detail: String)
    case oversizedResponse(host: String, bytes: Int)
    case invalidResponse(host: String, detail: String)

    var errorDescription: String? {
        switch self {
        case .emptyDestination:
            "The remote archive host has no SSH destination."
        case let .launchFailed(detail):
            "The managed SSH archive query could not launch: \(detail)"
        case let .commandFailed(host, exitCode, detail):
            "\(host) archive query exited \(exitCode): \(detail)"
        case let .oversizedResponse(host, bytes):
            "\(host) archive query returned \(bytes) bytes, above the 16 MB page limit."
        case let .invalidResponse(host, detail):
            "\(host) returned an invalid archive page: \(detail)"
        }
    }
}

struct HolyArchiveRemoteSSHQueryClient: HolyArchiveRemoteQuerying {
    static let maximumResponseBytes = 16 * 1_024 * 1_024

    private let transportManager: HolySSHTransportManager
    private let timeout: TimeInterval

    init(
        transportManager: HolySSHTransportManager = .shared,
        timeout: TimeInterval = 30
    ) {
        self.transportManager = transportManager
        self.timeout = timeout
    }

    func query(_ request: HolyArchiveRemoteRequest, on host: HolyArchiveRemoteHost) async throws
        -> HolyArchiveRemotePage {
        guard host.sshDestination.holyArchiveNilIfBlank != nil else {
            throw HolyArchiveRemoteQueryError.emptyDestination
        }
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        let requestData = try encoder.encode(request)
        let command = try transportCommand(for: host)
        let processResult = await HolyRestoreProcessRunner.run(
            executablePath: command.executablePath,
            arguments: command.arguments,
            timeout: timeout,
            stdinData: requestData
        )
        let output: HolyRestoreProcessOutput
        switch processResult {
        case let .success(value):
            output = value
        case let .failure(detail):
            throw HolyArchiveRemoteQueryError.launchFailed(detail)
        }
        guard output.exitCode == 0 else {
            let detail = output.stderr.holyArchiveNilIfBlank
                ?? output.stdout.holyArchiveNilIfBlank
                ?? "no diagnostic"
            throw HolyArchiveRemoteQueryError.commandFailed(
                host: host.label,
                exitCode: output.exitCode,
                detail: HolyArchiveText.preview(detail, limit: 800)
            )
        }
        let data = Data(output.stdout.utf8)
        guard data.count <= Self.maximumResponseBytes else {
            throw HolyArchiveRemoteQueryError.oversizedResponse(host: host.label, bytes: data.count)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(HolyArchiveRemotePage.self, from: data)
        } catch {
            throw HolyArchiveRemoteQueryError.invalidResponse(
                host: host.label,
                detail: error.localizedDescription
            )
        }
    }

    func transportCommand(for host: HolyArchiveRemoteHost) throws -> HolySSHTransportCommand {
        try transportManager.command(
            destination: host.sshDestination,
            purpose: .control,
            controlOperation: .metadata,
            remoteCommand: ["/usr/bin/env", "python3", "-c", Self.pythonProgram]
        )
    }

    // The program accepts only JSON over stdin, binds every SQLite value, opens
    // the database with mode=ro, and enables query_only before inspecting it.
    // It intentionally exposes no mutation operation.
    static let pythonProgram = #"""
import json
import math
import os
import sqlite3
import struct
import sys
import urllib.parse

SESSION_COLUMNS = """
s.id, s.harness, s.raw_path, s.project_path, s.project_name, s.title,
s.first_prompt_preview, s.last_prompt_preview, s.last_response_preview,
s.timestamp, s.timestamp_end, s.is_child, s.child_type, s.parent_id, s.model,
s.tool_calls_json, s.tokens_used, s.summary, s.content_hash, s.extra_json,
s.resume_command, s.message_count, s.turn_count, s.file_mtime, s.indexed_at,
s.auto_tags_json
"""

def blank_page():
    return {
        "total": 0,
        "sessions": [],
        "messages": [],
        "annotations": [],
        "child_counts": {},
        "matches": {},
        "matching_children": {},
    }

def json_array(value):
    try:
        parsed = json.loads(value or "[]")
        return [str(item) for item in parsed] if isinstance(parsed, list) else []
    except (TypeError, ValueError):
        return []

def json_dictionary(value):
    try:
        parsed = json.loads(value or "{}")
        if not isinstance(parsed, dict):
            return {}
        return {str(key): str(item) for key, item in parsed.items()}
    except (TypeError, ValueError):
        return {}

def session(row):
    return {
        "id": row["id"],
        "harness": row["harness"],
        "raw_path": row["raw_path"],
        "project_path": row["project_path"],
        "project_name": row["project_name"],
        "title": row["title"],
        "first_prompt": row["first_prompt_preview"],
        "last_prompt": row["last_prompt_preview"],
        "last_response": row["last_response_preview"],
        "created_at": row["timestamp"],
        "modified_at": row["timestamp_end"],
        "is_child": bool(row["is_child"]),
        "child_type": row["child_type"],
        "parent_id": row["parent_id"],
        "model": row["model"],
        "tool_calls": json_array(row["tool_calls_json"]),
        "tokens_used": row["tokens_used"],
        "summary": row["summary"],
        "content_hash": row["content_hash"],
        "extra": json_dictionary(row["extra_json"]),
        "resume_command": row["resume_command"],
        "message_count": row["message_count"],
        "turn_count": row["turn_count"],
        "file_m_time": row["file_mtime"],
        "indexed_at": row["indexed_at"],
        "auto_tags": json_array(row["auto_tags_json"]),
    }

def escape_like(value):
    return str(value).replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")

def filter_sql(filters):
    filters = filters or {}
    clauses = []
    parameters = []
    harness = filters.get("harness")
    if harness:
        clauses.append("s.harness = ?")
        parameters.append(harness)
    project = filters.get("project")
    if project:
        pattern = "%" + escape_like(project) + "%"
        clauses.append("(s.project_name LIKE ? ESCAPE '\\' COLLATE NOCASE OR s.project_path LIKE ? ESCAPE '\\' COLLATE NOCASE)")
        parameters.extend([pattern, pattern])
    after = filters.get("after")
    if after is not None:
        clauses.append("COALESCE(s.timestamp_end, s.timestamp) >= ?")
        parameters.append(float(after))
    before = filters.get("before")
    if before is not None:
        clauses.append("COALESCE(s.timestamp_end, s.timestamp) <= ?")
        parameters.append(float(before))
    for tag in filters.get("tags") or []:
        clauses.append("s.id IN (SELECT session_id FROM archive_annotations WHERE type = 'tag' AND value = ? COLLATE NOCASE)")
        parameters.append(tag)
    return clauses, parameters

def fetch_session(connection, session_id):
    return connection.execute(
        "SELECT " + SESSION_COLUMNS + " FROM archive_sessions s WHERE s.id = ? LIMIT 1",
        [session_id],
    ).fetchone()

def related_children(connection, parent):
    explicit = connection.execute(
        "SELECT " + SESSION_COLUMNS + " FROM archive_sessions s WHERE s.parent_id = ? "
        "ORDER BY COALESCE(s.timestamp, s.timestamp_end), s.id",
        [parent["id"]],
    ).fetchall()
    if explicit:
        return explicit
    if not parent["project_path"]:
        return []
    window = 24 * 60 * 60 if parent["harness"] == "opencode" else 2 * 60 * 60
    activity = parent["timestamp_end"] if parent["timestamp_end"] is not None else parent["timestamp"]
    return connection.execute(
        "SELECT " + SESSION_COLUMNS + " FROM archive_sessions s "
        "WHERE s.is_child = 1 AND s.harness = ? AND s.project_path = ? "
        "AND ABS(COALESCE(s.timestamp_end, s.timestamp) - ?) < ? "
        "ORDER BY COALESCE(s.timestamp, s.timestamp_end), s.id",
        [parent["harness"], parent["project_path"], activity, window],
    ).fetchall()

def child_counts(connection, parents):
    return {row["id"]: len(related_children(connection, row)) for row in parents}

def find_database(request):
    home = os.path.expanduser("~")
    for bundle in request.get("bundle_identifiers") or []:
        candidate = os.path.join(
            home,
            "Library",
            "Application Support",
            bundle,
            "HolyGhostty",
            "holy-archive.sqlite3",
        )
        if os.path.isfile(candidate):
            return candidate
    raise FileNotFoundError("holy-archive.sqlite3 was not found in a supported Holy container")

def open_database(path, supported_version):
    uri = "file:" + urllib.parse.quote(path, safe="/") + "?mode=ro"
    connection = sqlite3.connect(uri, uri=True, timeout=2.0)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA query_only = ON")
    version = int(connection.execute("PRAGMA user_version").fetchone()[0])
    if version > supported_version:
        connection.close()
        raise RuntimeError(
            "archive schema version %d is newer than this client supports (%d)"
            % (version, supported_version)
        )
    return connection

def parents_page(connection, request):
    page = blank_page()
    clauses, parameters = filter_sql(request.get("filter"))
    clauses.append("s.is_child = 0")
    where = " WHERE " + " AND ".join(clauses)
    page["total"] = int(connection.execute(
        "SELECT COUNT(*) FROM archive_sessions s" + where,
        parameters,
    ).fetchone()[0])
    rows = connection.execute(
        "SELECT " + SESSION_COLUMNS + " FROM archive_sessions s" + where
        + " ORDER BY COALESCE(s.timestamp_end, s.timestamp) DESC, s.id ASC LIMIT ? OFFSET ?",
        parameters + [request["limit"], request["offset"]],
    ).fetchall()
    page["sessions"] = [session(row) for row in rows]
    page["child_counts"] = child_counts(connection, rows)
    return page

def fts_matches(connection, request, clauses, parameters):
    fts_query = request.get("fts_query") or '""'
    if fts_query == '""':
        return {}
    suffix = (" AND " + " AND ".join(clauses)) if clauses else ""
    matches = {}
    message_rows = connection.execute(
        "SELECT s.id, archive_messages_fts.rank, "
        "snippet(archive_messages_fts, 0, '', '', '...', 24) AS snippet "
        "FROM archive_messages_fts "
        "JOIN archive_messages m ON m.rowid = archive_messages_fts.rowid "
        "JOIN archive_sessions s ON s.id = m.session_id "
        "WHERE archive_messages_fts MATCH ?" + suffix
        + " ORDER BY archive_messages_fts.rank LIMIT 1000",
        [fts_query] + parameters,
    ).fetchall()
    for row in message_rows:
        score = 1.0 / (1.0 + abs(float(row[1])))
        if row[0] not in matches or score > matches[row[0]]["raw_score"]:
            matches[row[0]] = {
                "raw_score": score,
                "snippet": row[2],
                "source": "keyword",
            }
    session_rows = connection.execute(
        "SELECT s.id, archive_sessions_fts.rank, "
        "snippet(archive_sessions_fts, -1, '', '', '...', 24) AS snippet "
        "FROM archive_sessions_fts "
        "JOIN archive_sessions s ON s.rowid = archive_sessions_fts.rowid "
        "WHERE archive_sessions_fts MATCH ?" + suffix
        + " ORDER BY archive_sessions_fts.rank LIMIT 1000",
        [fts_query] + parameters,
    ).fetchall()
    for row in session_rows:
        score = 1.0 / (1.0 + abs(float(row[1])))
        if row[0] not in matches or score > matches[row[0]]["raw_score"]:
            matches[row[0]] = {
                "raw_score": score,
                "snippet": row[2],
                "source": "keyword",
            }
    return matches

def like_matches(connection, request, clauses, parameters):
    text = request.get("text") or ""
    pattern = "%" + escape_like(text) + "%"
    search = "(" + " OR ".join([
        "s.first_prompt_preview LIKE ? ESCAPE '\\' COLLATE NOCASE",
        "s.last_prompt_preview LIKE ? ESCAPE '\\' COLLATE NOCASE",
        "s.last_response_preview LIKE ? ESCAPE '\\' COLLATE NOCASE",
        "s.project_name LIKE ? ESCAPE '\\' COLLATE NOCASE",
        "s.auto_tags_json LIKE ? ESCAPE '\\' COLLATE NOCASE",
        "s.id IN (SELECT session_id FROM archive_messages WHERE content LIKE ? ESCAPE '\\' COLLATE NOCASE)",
    ]) + ")"
    where_clauses = list(clauses) + [search]
    rows = connection.execute(
        "SELECT s.id FROM archive_sessions s WHERE " + " AND ".join(where_clauses)
        + " ORDER BY COALESCE(s.timestamp_end, s.timestamp) DESC LIMIT 1000",
        parameters + [pattern] * 6,
    ).fetchall()
    return {
        row[0]: {"raw_score": 1.0, "snippet": text, "source": "keyword"}
        for row in rows
    }

def semantic_matches(connection, request, clauses, parameters):
    query_vector = [float(value) for value in (request.get("semantic_query_vector") or [])]
    if not query_vector:
        return {}
    query_norm = math.sqrt(sum(value * value for value in query_vector))
    if query_norm <= 0:
        return {}
    suffix = (" AND " + " AND ".join(clauses)) if clauses else ""
    rows = connection.execute(
        "SELECT c.session_id, c.content, c.embedding FROM archive_chunks c "
        "JOIN archive_sessions s ON s.id = c.session_id "
        "WHERE c.embedding IS NOT NULL" + suffix,
        parameters,
    ).fetchall()
    minimum_cosine = float(request.get("minimum_cosine", 0.35))
    matches = {}
    expected_bytes = len(query_vector) * 4
    for row in rows:
        blob = bytes(row["embedding"])
        if len(blob) != expected_bytes:
            continue
        vector = struct.unpack("<%df" % len(query_vector), blob)
        vector_norm = math.sqrt(sum(value * value for value in vector))
        if vector_norm <= 0:
            continue
        score = sum(left * right for left, right in zip(vector, query_vector)) / (vector_norm * query_norm)
        if score < minimum_cosine:
            continue
        previous = matches.get(row["session_id"])
        if previous is not None and score <= previous["raw_score"]:
            continue
        matches[row["session_id"]] = {
            "raw_score": score,
            "snippet": str(row["content"] or "")[:1200],
            "source": "semantic",
        }
    return matches

def normalized_scores(matches, floor):
    if not matches:
        return {}
    values = [match["raw_score"] for match in matches.values()]
    minimum = min(values)
    maximum = max(values)
    if maximum == minimum:
        return {session_id: 1.0 for session_id in matches}
    return {
        session_id: floor + ((match["raw_score"] - minimum) / (maximum - minimum)) * (1.0 - floor)
        for session_id, match in matches.items()
    }

def combined_matches(keyword, semantic, request):
    floor = float(request.get("normalization_floor", 0.5))
    keyword_normalized = normalized_scores(keyword, floor)
    semantic_normalized = normalized_scores(semantic, floor)
    fts_weight = float(request.get("fts_weight", 0.3))
    semantic_weight = float(request.get("semantic_weight", 0.7))
    minimum_score = float(request.get("minimum_combined_score", 0.2))
    matches = {}
    for session_id in set(keyword).union(semantic):
        keyword_match = keyword.get(session_id)
        semantic_match = semantic.get(session_id)
        left = keyword_normalized.get(session_id)
        right = semantic_normalized.get(session_id)
        if left is not None and right is not None:
            score = left * fts_weight + right * semantic_weight
        elif left is not None:
            score = left * floor
        elif right is not None:
            score = right * floor
        else:
            continue
        if score < minimum_score:
            continue
        semantic_wins = (right if right is not None else float("-inf")) > (
            left if left is not None else float("-inf")
        )
        visible_match = semantic_match if semantic_wins else (keyword_match or semantic_match)
        matches[session_id] = {
            "score": score,
            "keyword_score": keyword_match["raw_score"] if keyword_match else None,
            "semantic_score": semantic_match["raw_score"] if semantic_match else None,
            "snippet": visible_match["snippet"] if visible_match else None,
            "source": visible_match["source"] if visible_match else "semantic",
        }
    return matches

def search_page(connection, request):
    page = blank_page()
    clauses, parameters = filter_sql(request.get("filter"))
    text = (request.get("text") or "").strip()
    if not text:
        where = (" WHERE " + " AND ".join(clauses)) if clauses else ""
        rows = connection.execute(
            "SELECT " + SESSION_COLUMNS + " FROM archive_sessions s" + where
            + " ORDER BY COALESCE(s.timestamp_end, s.timestamp) DESC, s.id ASC LIMIT 500",
            parameters,
        ).fetchall()
        matches = {
            row["id"]: {
                "score": 1.0,
                "keyword_score": None,
                "semantic_score": None,
                "snippet": None,
                "source": "metadata",
            }
            for row in rows
        }
    else:
        try:
            keyword = fts_matches(connection, request, clauses, parameters)
        except sqlite3.OperationalError:
            keyword = like_matches(connection, request, clauses, parameters)
        semantic = semantic_matches(connection, request, clauses, parameters)
        matches = combined_matches(keyword, semantic, request)
        if not matches:
            return page
        placeholders = ",".join("?" for _ in matches)
        rows = connection.execute(
            "SELECT " + SESSION_COLUMNS + " FROM archive_sessions s WHERE s.id IN (" + placeholders + ")",
            list(matches.keys()),
        ).fetchall()
    by_id = {row["id"]: row for row in rows}
    parent_matches = {}
    matching_children = {}
    parent_rows = {}
    for session_id, match in matches.items():
        row = by_id.get(session_id)
        if row is None:
            continue
        if bool(row["is_child"]) and row["parent_id"]:
            parent_id = row["parent_id"]
            matching_children.setdefault(parent_id, []).append(row)
            parent = by_id.get(parent_id) or fetch_session(connection, parent_id)
            if parent is None:
                continue
            parent_rows[parent_id] = parent
            if parent_id not in parent_matches or match["score"] > parent_matches[parent_id]["score"]:
                parent_matches[parent_id] = dict(match)
        else:
            parent_rows[session_id] = row
            if session_id not in parent_matches or match["score"] > parent_matches[session_id]["score"]:
                parent_matches[session_id] = dict(match)
    ordered_ids = sorted(
        parent_matches,
        key=lambda value: (
            -parent_matches[value]["score"],
            -(parent_rows[value]["timestamp_end"] or parent_rows[value]["timestamp"] or 0),
            value,
        ),
    )[:request["limit"]]
    visible = set(ordered_ids)
    page["total"] = len(parent_matches)
    page["sessions"] = [session(parent_rows[value]) for value in ordered_ids]
    page["matches"] = {value: parent_matches[value] for value in ordered_ids}
    page["matching_children"] = {
        value: [session(row) for row in matching_children.get(value, [])]
        for value in ordered_ids
        if matching_children.get(value)
    }
    page["child_counts"] = child_counts(connection, [parent_rows[value] for value in ordered_ids])
    return page

def children_page(connection, request):
    page = blank_page()
    parent = fetch_session(connection, request.get("parent_id"))
    if parent is None:
        return page
    rows = related_children(connection, parent)[:request["limit"]]
    page["total"] = len(rows)
    page["sessions"] = [session(row) for row in rows]
    return page

def messages_page(connection, request):
    page = blank_page()
    session_id = request.get("session_id")
    page["total"] = int(connection.execute(
        "SELECT COUNT(*) FROM archive_messages WHERE session_id = ?",
        [session_id],
    ).fetchone()[0])
    rows = connection.execute(
        "SELECT id, session_id, role, content, timestamp, sequence "
        "FROM archive_messages WHERE session_id = ? ORDER BY sequence ASC LIMIT ? OFFSET ?",
        [session_id, request["limit"], request["offset"]],
    ).fetchall()
    page["messages"] = [
        {
            "id": row["id"],
            "session_id": row["session_id"],
            "role": row["role"],
            "content": row["content"],
            "timestamp": row["timestamp"],
            "sequence": row["sequence"],
        }
        for row in rows
    ]
    return page

def annotations_page(connection, request):
    page = blank_page()
    rows = connection.execute(
        "SELECT id, session_id, timestamp, type, value, source "
        "FROM archive_annotations WHERE session_id = ? ORDER BY timestamp DESC, id DESC LIMIT ?",
        [request.get("session_id"), request["limit"]],
    ).fetchall()
    page["total"] = len(rows)
    page["annotations"] = [
        {
            "id": row["id"],
            "session_id": row["session_id"],
            "timestamp": row["timestamp"],
            "kind": row["type"],
            "value": row["value"],
            "source": row["source"],
        }
        for row in rows
    ]
    return page

def main():
    request = json.load(sys.stdin)
    database_path = find_database(request)
    connection = open_database(database_path, int(request["supported_schema_version"]))
    try:
        operation = request.get("operation")
        if operation == "parents":
            page = parents_page(connection, request)
        elif operation == "search":
            page = search_page(connection, request)
        elif operation == "children":
            page = children_page(connection, request)
        elif operation == "messages":
            page = messages_page(connection, request)
        elif operation == "annotations":
            page = annotations_page(connection, request)
        else:
            raise ValueError("unsupported archive operation")
    finally:
        connection.close()
    json.dump(page, sys.stdout, separators=(",", ":"), ensure_ascii=False)

main()
"""#
}
