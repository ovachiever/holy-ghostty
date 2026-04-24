import SwiftUI
import UniformTypeIdentifiers

struct HolySessionRosterView: View {
    @ObservedObject var store: HolyWorkspaceStore
    var compact: Bool = false
    @State private var draggingSessionID: UUID?

    private var sessions: [HolySession] {
        store.sessions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if sessions.isEmpty {
                HolyGhosttyEmptyStateView(
                    title: "No sessions",
                    subtitle: "Press + to create one.",
                    symbol: "terminal"
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(sessions) { session in
                            HolyRosterRow(
                                session: session,
                                coordination: store.coordination(for: session),
                                isSelected: store.selectedSessionID == session.id,
                                compact: compact,
                                onSelect: { store.selectedSessionID = session.id },
                                onDuplicate: { store.duplicate(session.id) },
                                onArchive: { store.close(session) },
                                onRename: { store.rename(session, to: $0) },
                                dragProvider: {
                                    draggingSessionID = session.id
                                    return HolyRosterDrag.itemProvider(for: session.id)
                                }
                            )
                            .onDrop(
                                of: [HolyRosterDrag.type],
                                delegate: HolyRosterRowDropDelegate(
                                    targetSessionID: session.id,
                                    store: store,
                                    draggingSessionID: $draggingSessionID
                                )
                            )
                        }

                        Color.clear
                            .frame(height: 24)
                            .onDrop(
                                of: [HolyRosterDrag.type],
                                delegate: HolyRosterEndDropDelegate(
                                    store: store,
                                    draggingSessionID: $draggingSessionID
                                )
                            )
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .animation(.easeInOut(duration: 0.12), value: sessions.map(\.id))
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

// MARK: - Roster Reordering

private enum HolyRosterDrag {
    static let type = UTType.plainText

    static func itemProvider(for sessionID: UUID) -> NSItemProvider {
        NSItemProvider(object: "holy-session:\(sessionID.uuidString)" as NSString)
    }
}

private struct HolyRosterRowDropDelegate: DropDelegate {
    let targetSessionID: UUID
    let store: HolyWorkspaceStore
    @Binding var draggingSessionID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggingSessionID,
              draggingSessionID != targetSessionID else {
            return
        }

        store.moveSession(draggingSessionID, to: targetSessionID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        store.persistSessionOrder()
        draggingSessionID = nil
        return true
    }
}

private struct HolyRosterEndDropDelegate: DropDelegate {
    let store: HolyWorkspaceStore
    @Binding var draggingSessionID: UUID?

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggingSessionID else { return false }
        store.moveSessionToEnd(draggingSessionID)
        store.persistSessionOrder()
        self.draggingSessionID = nil
        return true
    }
}

// MARK: - Roster Row

private struct HolyRosterRow: View {
    @ObservedObject var session: HolySession
    let coordination: HolySessionCoordination
    let isSelected: Bool
    var compact: Bool = false
    let onSelect: () -> Void
    let onDuplicate: () -> Void
    let onArchive: () -> Void
    let onRename: (String) -> Void
    let dragProvider: () -> NSItemProvider

    @State private var isRenaming = false
    @State private var renameText = ""

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            HolyGhosttyStatusDot(color: attentionColor)

            if !compact && !isRenaming {
                dragHandle
            }

            if isRenaming {
                TextField("Session name", text: $renameText, onCommit: commitRename)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    displayLine

                    if needsAttentionLine {
                        Text(statusLine)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(attentionColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)

            if !compact && !isRenaming {
                Menu {
                    Button("Rename") { startRename() }
                    Button("Duplicate") {
                        onSelect()
                        onDuplicate()
                    }
                    Button("Archive") {
                        onSelect()
                        onArchive()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(HolyGhosttyTheme.textTertiary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .frame(width: 14, height: 14)
                .opacity(isSelected ? 1 : 0.5)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? HolyGhosttyTheme.bgSurface : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isSelected ? attentionColor.opacity(0.15) : Color.clear, lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onTapGesture(perform: onSelect)
    }

    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(isSelected ? HolyGhosttyTheme.textSecondary : HolyGhosttyTheme.textTertiary)
            .frame(width: 24, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.04 : 0.02))
            )
            .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .onDrag(dragProvider)
            .help("Drag to reorder")
    }

    // Stacked display: agent + project on top, concrete machine/session identity below.
    private var displayLine: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(rosterPrimaryTitle)
                .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.white : HolyGhosttyTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            Text(rosterSecondaryIdentity)
                .font(.system(size: 10, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? HolyGhosttyTheme.textSecondary : HolyGhosttyTheme.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rosterPrimaryTitle: String {
        let runtimeName = session.displayRuntime.displayName
        guard let project = session.displayProjectName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !project.isEmpty,
              !runtimeName.localizedCaseInsensitiveContains(project) else {
            return runtimeName
        }

        return "\(runtimeName) - \(project)"
    }

    private var rosterSecondaryIdentity: String {
        let launchSpec = session.record.launchSpec
        var parts: [String] = [
            launchSpec.transport.isRemote ? launchSpec.transport.destinationDisplayName : "Local"
        ]

        if let tmux = launchSpec.tmux {
            if let sessionName = tmux.sessionName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !sessionName.isEmpty {
                parts.append(sessionName)
            } else {
                let serverName = tmux.socketName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                parts.append(serverName.isEmpty ? "tmux" : serverName)
            }
        }

        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "/")
    }

    private var needsAttentionLine: Bool {
        switch coordination.attention {
        case .conflict, .failure, .needsInput:
            return true
        case .watch, .none, .done:
            return false
        }
    }

    private var statusLine: String {
        if coordination.hasBlockingConflict {
            return coordination.summary
        }
        return session.primarySignalHeadline
    }

    private func startRename() {
        renameText = session.title
        isRenaming = true
    }

    private func commitRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onRename(trimmed)
        }
        isRenaming = false
    }

    private var attentionColor: Color {
        switch coordination.attention {
        case .none:
            return phaseColor
        case .watch:
            return HolyGhosttyTheme.accent
        case .needsInput:
            return HolyGhosttyTheme.warning
        case .failure, .conflict:
            return HolyGhosttyTheme.danger
        case .done:
            return HolyGhosttyTheme.success
        }
    }

    private var phaseColor: Color {
        switch session.phase {
        case .active:    return HolyGhosttyTheme.success
        case .working:   return HolyGhosttyTheme.accent
        case .waitingInput: return HolyGhosttyTheme.warning
        case .completed: return HolyGhosttyTheme.success
        case .failed:    return HolyGhosttyTheme.danger
        }
    }
}
