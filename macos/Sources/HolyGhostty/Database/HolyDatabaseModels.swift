import Foundation

enum HolyDatabaseSchema {
    static let filename = "holy-ghostty.sqlite3"
    static let currentUserVersion: Int32 = 12
    static let busyTimeoutMilliseconds: Int32 = 5_000
}

enum HolyDatabaseTable: String, CaseIterable, Hashable {
    case appState = "app_state"
    case sessions = "sessions"
    case sessionEvents = "session_events"
    case gitSnapshots = "git_snapshots"
    case budgetSamples = "budget_samples"
    case templates = "templates"
    case tasks = "tasks"
    case remoteHosts = "remote_hosts"
    case launchProfiles = "launch_profiles"
    case alerts = "alerts"
    case annotations = "annotations"
    case boardDigestCache = "board_digest_cache"
    case archiveIndexMeta = "archive_index_meta"
    case archiveSessions = "archive_sessions"
    case archiveMessages = "archive_messages"
    case archiveChunks = "archive_chunks"
    case archiveSearchHistory = "archive_search_history"
    case archiveProjectStats = "archive_project_stats"
    case archiveSummaries = "archive_summaries"
    case archiveAnnotations = "archive_annotations"
    case archiveResearchChats = "archive_research_chats"
    case archiveResearchMessages = "archive_research_messages"
}

struct HolyDatabaseMigration {
    let version: Int32
    let label: String
    let statements: [String]
}

enum HolyDatabaseBinding {
    case null
    case text(String)
    case int(Int32)
    case int64(Int64)
    case double(Double)
    case bool(Bool)
    case blob(Data)
}
