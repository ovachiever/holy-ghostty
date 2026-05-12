import Foundation

@MainActor
struct HolySessionStoreState {
    var sessions: [HolySession]
    var savedTemplates: [HolySessionTemplate]
    var archivedSessions: [HolyArchivedSession]
    var selectedSessionID: UUID?
    var selectedArchivedSessionID: UUID?
    var paneLayout: HolyPaneLayout = .single

    static let empty = Self(
        sessions: [],
        savedTemplates: [],
        archivedSessions: [],
        selectedSessionID: nil,
        selectedArchivedSessionID: nil,
        paneLayout: .single
    )

    var snapshot: HolyWorkspaceSnapshot {
        .init(
            sessions: sessions.map(\.record),
            selectedSessionID: selectedSessionID,
            templates: savedTemplates,
            archivedSessions: archivedSessions,
            paneLayout: paneLayout
        )
    }
}

struct HolySessionStoreMutationResult {
    let state: HolySessionStoreState
    let pendingEvents: [HolySessionEventDraft]
}
