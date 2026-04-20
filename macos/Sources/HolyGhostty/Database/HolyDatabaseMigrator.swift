import Foundation

enum HolyDatabaseMigrator {
    static func migrate(_ database: HolyDatabase) throws {
        let currentVersion = try database.userVersion()
        let supportedVersion = HolyDatabaseSchema.currentUserVersion

        guard currentVersion <= supportedVersion else {
            throw HolyDatabaseError.unsupportedSchemaVersion(
                found: currentVersion,
                supported: supportedVersion
            )
        }

        for migration in migrations where migration.version > currentVersion {
            try database.withTransaction {
                for statement in migration.statements {
                    try database.execute(statement)
                }
                try database.setUserVersion(migration.version)
            }
        }
    }

    private static let migrations: [HolyDatabaseMigration] = [
        .init(
            version: 1,
            label: "Initial Holy Ghostty schema",
            statements: schemaV1
        ),
        .init(
            version: 2,
            label: "Session budget telemetry projection",
            statements: schemaV2
        ),
        .init(
            version: 3,
            label: "Session runtime telemetry projection",
            statements: schemaV3
        ),
        .init(
            version: 4,
            label: "Budget intelligence ledger",
            statements: schemaV4
        ),
        .init(
            version: 5,
            label: "External task inbox",
            statements: schemaV5
        ),
        .init(
            version: 6,
            label: "Remote host registry",
            statements: schemaV6
        ),
    ]

    private static let schemaV1: [String] = [
        """
        CREATE TABLE IF NOT EXISTS app_state (
            key TEXT PRIMARY KEY,
            value_json TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        """,
        """
        CREATE TABLE IF NOT EXISTS sessions (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            runtime TEXT NOT NULL,
            mission TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            archived_at TEXT,
            launch_spec_json TEXT NOT NULL,
            ownership_json TEXT,
            working_directory TEXT,
            repository_root TEXT,
            worktree_path TEXT,
            branch_name TEXT,
            latest_preview_text TEXT,
            resume_metadata_json TEXT,
            preferred_command TEXT,
            latest_phase TEXT,
            latest_attention TEXT,
            latest_signal_json TEXT,
            latest_git_snapshot_id INTEGER,
            latest_command_telemetry_json TEXT
        );
        """,
        """
        CREATE TABLE IF NOT EXISTS session_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            sequence INTEGER NOT NULL,
            occurred_at TEXT NOT NULL,
            event_type TEXT NOT NULL,
            phase TEXT,
            attention TEXT,
            payload_json TEXT,
            FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
        );
        """,
        """
        CREATE TABLE IF NOT EXISTS git_snapshots (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            captured_at TEXT NOT NULL,
            repository_root TEXT,
            worktree_path TEXT,
            common_git_directory TEXT,
            branch TEXT,
            upstream_branch TEXT,
            is_detached_head INTEGER NOT NULL,
            ahead_count INTEGER NOT NULL,
            behind_count INTEGER NOT NULL,
            staged_count INTEGER NOT NULL,
            unstaged_count INTEGER NOT NULL,
            untracked_count INTEGER NOT NULL,
            conflicted_count INTEGER NOT NULL,
            changed_files_json TEXT NOT NULL,
            FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
        );
        """,
        """
        CREATE TABLE IF NOT EXISTS templates (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            summary TEXT,
            launch_spec_json TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        """,
        """
        CREATE TABLE IF NOT EXISTS alerts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT,
            session_event_id INTEGER,
            alert_type TEXT NOT NULL,
            severity TEXT NOT NULL,
            title TEXT NOT NULL,
            body TEXT NOT NULL,
            delivered_at TEXT NOT NULL,
            acknowledged_at TEXT,
            payload_json TEXT,
            FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE SET NULL,
            FOREIGN KEY (session_event_id) REFERENCES session_events(id) ON DELETE SET NULL
        );
        """,
        """
        CREATE TABLE IF NOT EXISTS annotations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            created_at TEXT NOT NULL,
            annotation_type TEXT NOT NULL,
            value TEXT NOT NULL,
            source TEXT NOT NULL,
            payload_json TEXT,
            FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
        );
        """,
        """
        CREATE UNIQUE INDEX IF NOT EXISTS session_events_session_sequence_idx
        ON session_events(session_id, sequence);
        """,
        """
        CREATE INDEX IF NOT EXISTS session_events_session_occurred_at_idx
        ON session_events(session_id, occurred_at);
        """,
        """
        CREATE INDEX IF NOT EXISTS session_events_event_type_occurred_at_idx
        ON session_events(event_type, occurred_at);
        """,
        """
        CREATE INDEX IF NOT EXISTS git_snapshots_session_captured_at_idx
        ON git_snapshots(session_id, captured_at);
        """,
        """
        CREATE INDEX IF NOT EXISTS sessions_archived_at_idx
        ON sessions(archived_at);
        """,
        """
        CREATE INDEX IF NOT EXISTS sessions_updated_at_idx
        ON sessions(updated_at);
        """,
        """
        CREATE INDEX IF NOT EXISTS alerts_delivered_at_idx
        ON alerts(delivered_at);
        """,
        """
        CREATE INDEX IF NOT EXISTS annotations_session_created_at_idx
        ON annotations(session_id, created_at);
        """,
        "DROP VIEW IF EXISTS agent_sessions_sessions_v1;",
        """
        CREATE VIEW agent_sessions_sessions_v1 AS
        SELECT
            sessions.id AS id,
            sessions.runtime AS harness,
            sessions.title AS title,
            COALESCE(sessions.worktree_path, sessions.working_directory, sessions.repository_root) AS project_path,
            NULL AS project_name,
            sessions.repository_root AS repository_root,
            sessions.worktree_path AS worktree_path,
            sessions.created_at AS created_at,
            sessions.updated_at AS updated_at,
            sessions.archived_at AS archived_at,
            sessions.latest_phase AS phase,
            sessions.latest_attention AS attention,
            sessions.latest_preview_text AS preview_text,
            NULL AS content_hash,
            sessions.launch_spec_json AS extra_json
        FROM sessions;
        """,
        "DROP VIEW IF EXISTS agent_sessions_resume_targets_v1;",
        """
        CREATE VIEW agent_sessions_resume_targets_v1 AS
        SELECT
            sessions.id AS session_id,
            sessions.runtime AS runtime,
            sessions.working_directory AS working_directory,
            sessions.repository_root AS repository_root,
            COALESCE(sessions.resume_metadata_json, '{}') AS resume_payload_json,
            sessions.preferred_command AS preferred_command,
            CASE
                WHEN sessions.archived_at IS NULL THEN 'active_session'
                ELSE 'archived_session'
            END AS resume_kind
        FROM sessions;
        """,
        "DROP VIEW IF EXISTS agent_sessions_events_v1;",
        """
        CREATE VIEW agent_sessions_events_v1 AS
        SELECT
            session_events.id AS event_id,
            session_events.session_id AS session_id,
            session_events.sequence AS sequence,
            session_events.occurred_at AS occurred_at,
            session_events.event_type AS event_type,
            session_events.phase AS phase,
            session_events.attention AS attention,
            session_events.payload_json AS payload_json
        FROM session_events;
        """,
        "DROP VIEW IF EXISTS agent_sessions_annotations_v1;",
        """
        CREATE VIEW agent_sessions_annotations_v1 AS
        SELECT
            annotations.id AS id,
            annotations.session_id AS session_id,
            annotations.created_at AS created_at,
            annotations.annotation_type AS annotation_type,
            annotations.value AS value,
            annotations.source AS source
        FROM annotations;
        """,
    ]

    private static let schemaV2: [String] = [
        """
        ALTER TABLE sessions
        ADD COLUMN latest_budget_json TEXT;
        """,
    ]

    private static let schemaV3: [String] = [
        """
        ALTER TABLE sessions
        ADD COLUMN latest_runtime_telemetry_json TEXT;
        """,
    ]

    private static let schemaV4: [String] = [
        """
        CREATE TABLE IF NOT EXISTS budget_samples (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            captured_at TEXT NOT NULL,
            runtime TEXT NOT NULL,
            source_task_id TEXT,
            total_tokens INTEGER,
            estimated_cost_usd REAL,
            budget_status TEXT NOT NULL,
            token_limit INTEGER,
            cost_limit_usd REAL,
            FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
        );
        """,
        """
        CREATE INDEX IF NOT EXISTS budget_samples_session_captured_at_idx
        ON budget_samples(session_id, captured_at);
        """,
        """
        CREATE INDEX IF NOT EXISTS budget_samples_runtime_captured_at_idx
        ON budget_samples(runtime, captured_at);
        """,
        """
        CREATE INDEX IF NOT EXISTS budget_samples_source_task_idx
        ON budget_samples(source_task_id, captured_at);
        """,
    ]

    private static let schemaV5: [String] = [
        """
        CREATE TABLE IF NOT EXISTS tasks (
            id TEXT PRIMARY KEY,
            source_kind TEXT NOT NULL,
            source_label TEXT NOT NULL,
            external_id TEXT,
            canonical_url TEXT,
            title TEXT NOT NULL,
            summary TEXT NOT NULL,
            preferred_runtime TEXT NOT NULL,
            preferred_working_directory TEXT,
            preferred_repository_root TEXT,
            preferred_command TEXT,
            preferred_initial_input TEXT,
            status TEXT NOT NULL,
            linked_session_id TEXT,
            linked_session_title TEXT,
            linked_session_phase TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            last_imported_at TEXT
        );
        """,
        """
        CREATE INDEX IF NOT EXISTS tasks_status_updated_at_idx
        ON tasks(status, updated_at);
        """,
        """
        CREATE INDEX IF NOT EXISTS tasks_linked_session_idx
        ON tasks(linked_session_id, updated_at);
        """,
    ]

    private static let schemaV6: [String] = [
        """
        CREATE TABLE IF NOT EXISTS remote_hosts (
            id TEXT PRIMARY KEY,
            label TEXT NOT NULL,
            ssh_destination TEXT NOT NULL,
            tmux_socket_name TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            last_discovered_at TEXT
        );
        """,
        """
        CREATE INDEX IF NOT EXISTS remote_hosts_updated_at_idx
        ON remote_hosts(updated_at, created_at);
        """,
    ]
}
