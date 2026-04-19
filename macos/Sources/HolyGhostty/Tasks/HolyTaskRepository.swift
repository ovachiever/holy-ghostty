import Foundation
import SQLite3

enum HolyTaskRepository {
    static func load() -> [HolyExternalTaskRecord] {
        do {
            let database = try HolyDatabase.openAppDatabase(readOnly: true)
            return try load(from: database)
        } catch {
            return []
        }
    }

    static func save(_ tasks: [HolyExternalTaskRecord]) {
        do {
            let database = try HolyDatabase.openAppDatabase()
            try save(tasks, in: database)
        } catch {
            AppDelegate.logger.error("Holy Ghostty failed to save tasks: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from database: HolyDatabase) throws -> [HolyExternalTaskRecord] {
        let sql = """
        SELECT id, source_kind, source_label, external_id, canonical_url, title, summary,
               preferred_runtime, preferred_working_directory, preferred_repository_root,
               preferred_command, preferred_initial_input, status, linked_session_id,
               linked_session_title, linked_session_phase, created_at, updated_at, last_imported_at
        FROM tasks
        ORDER BY updated_at DESC, created_at DESC;
        """

        var tasks: [HolyExternalTaskRecord] = []
        try database.query(sql) { statement in
            let id = try uuid(statement, index: 0)
            let sourceKindRaw = try requiredText(statement, index: 1)
            guard let sourceKind = HolyTaskSourceKind(rawValue: sourceKindRaw) else {
                throw CocoaError(.coderInvalidValue)
            }

            let runtimeRaw = try requiredText(statement, index: 7)
            guard let runtime = HolySessionRuntime(rawValue: runtimeRaw) else {
                throw CocoaError(.coderInvalidValue)
            }

            let statusRaw = try requiredText(statement, index: 12)
            guard let status = HolyExternalTaskStatus(rawValue: statusRaw) else {
                throw CocoaError(.coderInvalidValue)
            }

            let linkedSessionPhase = text(statement, index: 15).flatMap(HolySessionPhase.init(rawValue:))

            tasks.append(
                .init(
                    id: id,
                    sourceKind: sourceKind,
                    sourceLabel: try requiredText(statement, index: 2),
                    externalID: text(statement, index: 3),
                    canonicalURL: text(statement, index: 4),
                    title: try requiredText(statement, index: 5),
                    summary: text(statement, index: 6) ?? "",
                    preferredRuntime: runtime,
                    preferredWorkingDirectory: text(statement, index: 8),
                    preferredRepositoryRoot: text(statement, index: 9),
                    preferredCommand: text(statement, index: 10),
                    preferredInitialInput: text(statement, index: 11),
                    status: status,
                    linkedSessionID: text(statement, index: 13).flatMap(UUID.init(uuidString:)),
                    linkedSessionTitle: text(statement, index: 14),
                    linkedSessionPhase: linkedSessionPhase,
                    createdAt: try HolyPersistenceCoders.date(from: requiredText(statement, index: 16)),
                    updatedAt: try HolyPersistenceCoders.date(from: requiredText(statement, index: 17)),
                    lastImportedAt: try text(statement, index: 18).map(HolyPersistenceCoders.date(from:))
                )
            )
        }

        return tasks
    }

    private static func save(_ tasks: [HolyExternalTaskRecord], in database: HolyDatabase) throws {
        try database.withTransaction {
            try database.execute("DELETE FROM tasks;")

            let sql = """
            INSERT INTO tasks (
                id, source_kind, source_label, external_id, canonical_url, title, summary,
                preferred_runtime, preferred_working_directory, preferred_repository_root,
                preferred_command, preferred_initial_input, status, linked_session_id,
                linked_session_title, linked_session_phase, created_at, updated_at, last_imported_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

            for task in tasks {
                let normalizedTask = task.normalized()
                try database.execute(sql, bindings: [
                    .text(normalizedTask.id.uuidString),
                    .text(normalizedTask.sourceKind.rawValue),
                    .text(normalizedTask.sourceLabel),
                    binding(for: normalizedTask.externalID),
                    binding(for: normalizedTask.canonicalURL),
                    .text(normalizedTask.title),
                    .text(normalizedTask.summary),
                    .text(normalizedTask.preferredRuntime.rawValue),
                    binding(for: normalizedTask.preferredWorkingDirectory),
                    binding(for: normalizedTask.preferredRepositoryRoot),
                    binding(for: normalizedTask.preferredCommand),
                    binding(for: normalizedTask.preferredInitialInput),
                    .text(normalizedTask.status.rawValue),
                    normalizedTask.linkedSessionID.map { .text($0.uuidString) } ?? .null,
                    binding(for: normalizedTask.linkedSessionTitle),
                    binding(for: normalizedTask.linkedSessionPhase?.rawValue),
                    .text(HolyPersistenceCoders.string(from: normalizedTask.createdAt)),
                    .text(HolyPersistenceCoders.string(from: normalizedTask.updatedAt)),
                    normalizedTask.lastImportedAt.map { .text(HolyPersistenceCoders.string(from: $0)) } ?? .null,
                ])
            }
        }
    }

    private static func binding(for string: String?) -> HolyDatabaseBinding {
        guard let string else { return .null }
        return .text(string)
    }

    private static func requiredText(_ statement: OpaquePointer, index: Int32) throws -> String {
        guard let value = sqlite3_column_text(statement, index) else {
            throw CocoaError(.coderValueNotFound)
        }
        return String(cString: value)
    }

    private static func text(_ statement: OpaquePointer, index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }

    private static func uuid(_ statement: OpaquePointer, index: Int32) throws -> UUID {
        let value = try requiredText(statement, index: index)
        guard let uuid = UUID(uuidString: value) else {
            throw CocoaError(.coderInvalidValue)
        }
        return uuid
    }
}
