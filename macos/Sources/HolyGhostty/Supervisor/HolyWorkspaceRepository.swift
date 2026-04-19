import Foundation

@MainActor
enum HolyWorkspaceRepository {
    static func loadSnapshot() -> HolyWorkspaceSnapshot {
        var restoredSnapshot = HolyWorkspaceDatabasePersistence.load()
        if restoredSnapshot == nil {
            HolyMigrationService.importLegacyWorkspaceIfNeeded()
            restoredSnapshot = HolyWorkspaceDatabasePersistence.load()
        }

        return restoredSnapshot ?? HolyWorkspacePersistence.load()
    }

    static func save(
        snapshot: HolyWorkspaceSnapshot,
        activeSessions: [HolySession],
        attentionBySessionID: [UUID: HolySessionAttention],
        pendingEvents: [HolySessionEventDraft]
    ) {
        HolyWorkspaceDatabasePersistence.save(
            snapshot,
            activeSessions: activeSessions,
            attentionBySessionID: attentionBySessionID,
            pendingEvents: pendingEvents
        )
        HolyWorkspacePersistence.save(snapshot)
    }
}
