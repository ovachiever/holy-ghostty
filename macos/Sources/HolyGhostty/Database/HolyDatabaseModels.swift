import Foundation

enum HolyDatabaseSchema {
    static let filename = "holy-ghostty.sqlite3"
    static let currentUserVersion: Int32 = 5
    static let busyTimeoutMilliseconds: Int32 = 5_000
}

enum HolyDatabaseTable: String, CaseIterable {
    case appState = "app_state"
    case sessions = "sessions"
    case sessionEvents = "session_events"
    case gitSnapshots = "git_snapshots"
    case budgetSamples = "budget_samples"
    case templates = "templates"
    case tasks = "tasks"
    case alerts = "alerts"
    case annotations = "annotations"
}

enum HolyDatabaseCompatibilityView: String, CaseIterable {
    case agentSessionsSessionsV1 = "agent_sessions_sessions_v1"
    case agentSessionsResumeTargetsV1 = "agent_sessions_resume_targets_v1"
    case agentSessionsEventsV1 = "agent_sessions_events_v1"
    case agentSessionsAnnotationsV1 = "agent_sessions_annotations_v1"
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
}
