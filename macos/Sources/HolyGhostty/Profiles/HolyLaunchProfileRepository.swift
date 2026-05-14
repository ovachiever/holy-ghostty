import Foundation
import SQLite3

enum HolyLaunchProfileRepository {
    private static let defaultProfileIDKey = "default_launch_profile_id"

    static func loadState(remoteHosts: [HolyRemoteHostRecord]) -> HolyLaunchProfileState {
        do {
            let database = try HolyDatabase.openAppDatabase()
            let loadedProfiles = try loadProfiles(from: database)
            let loadedDefaultID: UUID? = try appStateValue(forKey: defaultProfileIDKey, in: database)
            let state = reconciledState(
                loadedProfiles: loadedProfiles,
                loadedDefaultID: loadedDefaultID,
                remoteHosts: remoteHosts
            )

            if state.profiles != loadedProfiles || state.defaultProfileID != loadedDefaultID {
                try save(state, in: database)
            }

            return state
        } catch {
            AppDelegate.logger.error("Holy Ghostty failed to load launch profiles: \(error.localizedDescription, privacy: .public)")
            let fallback = HolyLaunchProfile.localDefault()
            return .init(profiles: [fallback], defaultProfileID: fallback.id)
        }
    }

    static func save(_ state: HolyLaunchProfileState) {
        do {
            let database = try HolyDatabase.openAppDatabase()
            try save(state, in: database)
        } catch {
            AppDelegate.logger.error("Holy Ghostty failed to save launch profiles: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func reconciledState(
        loadedProfiles: [HolyLaunchProfile],
        loadedDefaultID: UUID?,
        remoteHosts: [HolyRemoteHostRecord]
    ) -> HolyLaunchProfileState {
        let profilesWereEmpty = loadedProfiles.isEmpty
        let normalizedRemoteHosts = remoteHosts
            .map { $0.normalized() }
            .filter { !$0.sshDestination.isEmpty }
        let remoteHostIDs = Set(normalizedRemoteHosts.map(\.id))
        var profiles = loadedProfiles.map(\.normalized)
        profiles.removeAll { profile in
            guard profile.sourceKind == .remoteHost else { return false }
            guard let sourceRemoteHostID = profile.sourceRemoteHostID else { return true }
            return !remoteHostIDs.contains(sourceRemoteHostID)
        }

        if !profiles.contains(where: { $0.sourceKind == .localDefault }) {
            profiles.insert(.localDefault(), at: 0)
        }

        for host in normalizedRemoteHosts {
            if let index = profiles.firstIndex(where: { $0.sourceKind == .remoteHost && $0.sourceRemoteHostID == host.id }) {
                let updated = profiles[index].updated(from: host).normalized
                if updated != profiles[index] {
                    profiles[index] = updated
                }
            } else {
                profiles.append(.remoteDefault(for: host))
            }
        }

        profiles = sortedProfiles(profiles)
        let validIDs = Set(profiles.map(\.id))
        let defaultProfileID: UUID?
        if let loadedDefaultID, validIDs.contains(loadedDefaultID) {
            defaultProfileID = loadedDefaultID
        } else if profilesWereEmpty,
                  normalizedRemoteHosts.count == 1,
                  let remoteProfile = profiles.first(where: { $0.sourceKind == .remoteHost }) {
            defaultProfileID = remoteProfile.id
        } else {
            defaultProfileID = profiles.first(where: { $0.sourceKind == .localDefault })?.id ?? profiles.first?.id
        }

        return .init(profiles: profiles, defaultProfileID: defaultProfileID)
    }

    private static func sortedProfiles(_ profiles: [HolyLaunchProfile]) -> [HolyLaunchProfile] {
        profiles.sorted { lhs, rhs in
            let lhsRank = sortRank(lhs)
            let rhsRank = sortRank(rhs)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }

            let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func sortRank(_ profile: HolyLaunchProfile) -> Int {
        switch profile.sourceKind {
        case .remoteHost: return 0
        case .localDefault: return 1
        case .manual: return 2
        }
    }

    private static func loadProfiles(from database: HolyDatabase) throws -> [HolyLaunchProfile] {
        let sql = """
        SELECT id, name, summary, source_kind, source_remote_host_id, launch_spec_json, created_at, updated_at
        FROM launch_profiles
        ORDER BY updated_at DESC, created_at DESC;
        """

        var profiles: [HolyLaunchProfile] = []
        try database.query(sql) { statement in
            let sourceKindRaw = try requiredText(statement, index: 3)
            guard let sourceKind = HolyLaunchProfileSourceKind(rawValue: sourceKindRaw) else {
                throw CocoaError(.coderInvalidValue)
            }

            let launchSpecJSON = try requiredText(statement, index: 5)
            profiles.append(
                .init(
                    id: try uuid(statement, index: 0),
                    name: try requiredText(statement, index: 1),
                    summary: text(statement, index: 2),
                    sourceKind: sourceKind,
                    sourceRemoteHostID: text(statement, index: 4).flatMap(UUID.init(uuidString:)),
                    launchSpec: try HolyPersistenceCoders.decodeJSON(HolySessionLaunchSpec.self, from: launchSpecJSON),
                    createdAt: try HolyPersistenceCoders.date(from: requiredText(statement, index: 6)),
                    updatedAt: try HolyPersistenceCoders.date(from: requiredText(statement, index: 7))
                )
            )
        }

        return profiles
    }

    private static func save(_ state: HolyLaunchProfileState, in database: HolyDatabase) throws {
        try database.withTransaction {
            try database.execute("DELETE FROM launch_profiles;")

            let sql = """
            INSERT INTO launch_profiles (
                id, name, summary, source_kind, source_remote_host_id,
                launch_spec_json, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """

            for profile in state.profiles.map(\.normalized) {
                try database.execute(sql, bindings: [
                    .text(profile.id.uuidString),
                    .text(profile.name),
                    binding(for: profile.summary),
                    .text(profile.sourceKind.rawValue),
                    profile.sourceRemoteHostID.map { .text($0.uuidString) } ?? .null,
                    .text(try HolyPersistenceCoders.encodeJSON(profile.launchSpec)),
                    .text(HolyPersistenceCoders.string(from: profile.createdAt)),
                    .text(HolyPersistenceCoders.string(from: profile.updatedAt)),
                ])
            }

            try upsertOptionalAppStateValue(state.defaultProfileID, forKey: defaultProfileIDKey, in: database)
        }
    }

    private static func upsertOptionalAppStateValue<T: Encodable>(
        _ value: T?,
        forKey key: String,
        in database: HolyDatabase
    ) throws {
        if let value {
            try upsertAppStateValue(value, forKey: key, in: database)
        } else {
            try database.execute(
                "DELETE FROM app_state WHERE key = ?;",
                bindings: [.text(key)]
            )
        }
    }

    private static func upsertAppStateValue<T: Encodable>(
        _ value: T,
        forKey key: String,
        in database: HolyDatabase
    ) throws {
        let sql = """
        INSERT INTO app_state (key, value_json, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET
            value_json = excluded.value_json,
            updated_at = excluded.updated_at;
        """

        try database.execute(sql, bindings: [
            .text(key),
            .text(try HolyPersistenceCoders.encodeJSON(value)),
            .text(HolyPersistenceCoders.string(from: .now)),
        ])
    }

    private static func appStateValue<T: Decodable>(
        forKey key: String,
        in database: HolyDatabase
    ) throws -> T? {
        let sql = """
        SELECT value_json
        FROM app_state
        WHERE key = ?
        LIMIT 1;
        """

        var value: T?
        try database.query(sql, bindings: [.text(key)]) { statement in
            value = try HolyPersistenceCoders.decodeJSON(T.self, from: requiredText(statement, index: 0))
        }

        return value
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
