import Foundation
import SQLite3

enum HolyRemoteHostRepository {
    static func load() -> [HolyRemoteHostRecord] {
        do {
            let database = try HolyDatabase.openAppDatabase(readOnly: true)
            return try load(from: database)
        } catch {
            return []
        }
    }

    static func save(_ hosts: [HolyRemoteHostRecord]) {
        do {
            let database = try HolyDatabase.openAppDatabase()
            try save(hosts, in: database)
        } catch {
            AppDelegate.logger.error("Holy Ghostty failed to save remote hosts: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from database: HolyDatabase) throws -> [HolyRemoteHostRecord] {
        let sql = """
        SELECT id, label, ssh_destination, tmux_socket_name, created_at, updated_at, last_discovered_at
        FROM remote_hosts
        ORDER BY updated_at DESC, created_at DESC;
        """

        var hosts: [HolyRemoteHostRecord] = []
        try database.query(sql) { statement in
            hosts.append(
                .init(
                    id: try uuid(statement, index: 0),
                    label: try requiredText(statement, index: 1),
                    sshDestination: try requiredText(statement, index: 2),
                    tmuxSocketName: text(statement, index: 3),
                    createdAt: try HolyPersistenceCoders.date(from: requiredText(statement, index: 4)),
                    updatedAt: try HolyPersistenceCoders.date(from: requiredText(statement, index: 5)),
                    lastDiscoveredAt: try text(statement, index: 6).map(HolyPersistenceCoders.date(from:))
                )
            )
        }

        return hosts
    }

    private static func save(_ hosts: [HolyRemoteHostRecord], in database: HolyDatabase) throws {
        try database.withTransaction {
            try database.execute("DELETE FROM remote_hosts;")

            let sql = """
            INSERT INTO remote_hosts (
                id, label, ssh_destination, tmux_socket_name, created_at, updated_at, last_discovered_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?);
            """

            for host in hosts {
                let normalizedHost = host.normalized()
                try database.execute(sql, bindings: [
                    .text(normalizedHost.id.uuidString),
                    .text(normalizedHost.label),
                    .text(normalizedHost.sshDestination),
                    binding(for: normalizedHost.tmuxSocketName),
                    .text(HolyPersistenceCoders.string(from: normalizedHost.createdAt)),
                    .text(HolyPersistenceCoders.string(from: normalizedHost.updatedAt)),
                    normalizedHost.lastDiscoveredAt.map { .text(HolyPersistenceCoders.string(from: $0)) } ?? .null,
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
