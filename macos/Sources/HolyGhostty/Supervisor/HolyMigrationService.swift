import Foundation
import OSLog

enum HolyMigrationService {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mitchellh.ghostty",
        category: "HolyMigrationService"
    )

    @MainActor
    static func importLegacyWorkspaceIfNeeded() {
        do {
            guard try !HolyWorkspaceDatabasePersistence.hasInitializedWorkspace() else {
                return
            }

            let legacyURL = HolyDatabasePaths.legacyWorkspaceStateURL
            guard FileManager.default.fileExists(atPath: legacyURL.path) else {
                return
            }

            let snapshot = HolyWorkspacePersistence.load()
            let importedEvents =
                snapshot.sessions.map(HolySessionEventDraft.imported(record:))
                + snapshot.archivedSessions.map(HolySessionEventDraft.imported(archivedSession:))
            HolyWorkspaceDatabasePersistence.save(snapshot, pendingEvents: importedEvents)
            HolyWorkspaceDatabasePersistence.markLegacyImportCompleted()

            logger.notice("Imported Holy legacy workspace snapshot from \(legacyURL.path, privacy: .public)")
        } catch {
            logger.error("Failed to import Holy legacy workspace snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }
}
