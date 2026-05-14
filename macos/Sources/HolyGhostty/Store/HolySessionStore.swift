import Foundation

@MainActor
struct HolySessionStoreState {
    var sessions: [HolySession]
    var savedTemplates: [HolySessionTemplate]
    var archivedSessions: [HolyArchivedSession]
    var selectedSessionID: UUID?
    var selectedArchivedSessionID: UUID?
    var paneLayout: HolyPaneLayout = .single
    var attentionMetadata: [HolySessionAttentionMetadata] = []

    static let empty = Self(
        sessions: [],
        savedTemplates: [],
        archivedSessions: [],
        selectedSessionID: nil,
        selectedArchivedSessionID: nil,
        paneLayout: .single,
        attentionMetadata: []
    )

    var snapshot: HolyWorkspaceSnapshot {
        .init(
            sessions: sessions.map(\.record),
            selectedSessionID: selectedSessionID,
            templates: savedTemplates,
            archivedSessions: archivedSessions,
            paneLayout: paneLayout,
            attentionMetadata: attentionMetadata
        )
    }
}

struct HolySessionStoreMutationResult {
    let state: HolySessionStoreState
    let pendingEvents: [HolySessionEventDraft]
}
