import Foundation

/// Thin box between the restore engine and the workspace store. The engine
/// owns this object strongly; the store reference inside is weak, so the
/// store → engine → adapter chain never cycles.
@MainActor
final class HolyWorkspaceRestoreAdapter: HolyRestoreWorkspaceAdapting {
    private weak var store: HolyWorkspaceStore?

    init(store: HolyWorkspaceStore) {
        self.store = store
    }

    var restoreCandidateArchives: [HolyArchivedSession] {
        store?.crashRestoreCandidates ?? []
    }

    func rosterOwnsSession(withHolyID id: UUID) -> Bool {
        store?.sessions.contains { $0.id == id } ?? false
    }

    func rosterOwnsTmuxSessionName(_ name: String) -> Bool {
        store?.sessions.contains {
            $0.record.launchSpec.tmux?.normalized.sessionName == name
        } ?? false
    }

    func persistPlannedLaunchSpec(archiveID: UUID, launchSpec: HolySessionLaunchSpec) {
        store?.updateArchivedSessionLaunchSpecForRestore(
            archiveID: archiveID,
            launchSpec: launchSpec
        )
    }

    func attachRestoredArchive(archiveID: UUID, launchSpec: HolySessionLaunchSpec) -> Bool {
        store?.attachRestoredArchivedSession(
            archiveID: archiveID,
            launchSpec: launchSpec
        ) ?? false
    }
}
