import SwiftUI

struct HolySessionRosterView: View {
    @ObservedObject var store: HolyWorkspaceStore
    var compact: Bool = false

    private var sessions: [HolySession] {
        store.sessions.sorted { lhs, rhs in
            if lhs.id == store.selectedSessionID { return true }
            if rhs.id == store.selectedSessionID { return false }

            let lhsAttentionRank = store.coordination(for: lhs).attention.rosterRank
            let rhsAttentionRank = store.coordination(for: rhs).attention.rosterRank
            if lhsAttentionRank != rhsAttentionRank {
                return lhsAttentionRank < rhsAttentionRank
            }

            let lhsRank = lhs.phase.rosterRank
            let rhsRank = rhs.phase.rosterRank
            if lhsRank == rhsRank {
                return lhs.activityAt > rhs.activityAt
            }
            return lhsRank < rhsRank
        }
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
                                onDuplicate: { store.duplicate(session) },
                                onArchive: { store.close(session) }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                }
                .scrollIndicators(.hidden)
            }
        }
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

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            HolyGhosttyStatusDot(color: attentionColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.white : HolyGhosttyTheme.textPrimary)
                    .lineLimit(1)

                Text(statusLine)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(attentionColor.opacity(0.8))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if !compact {
                Menu {
                    Button("Duplicate", action: onDuplicate)
                    Button("Archive", action: onArchive)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(HolyGhosttyTheme.textTertiary)
                }
                .menuStyle(.borderlessButton)
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

    private var statusLine: String {
        if coordination.hasBlockingConflict {
            return coordination.summary
        }
        return session.primarySignalHeadline
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

// MARK: - Rank extensions

private extension HolySessionPhase {
    var rosterRank: Int {
        switch self {
        case .failed: return 0
        case .waitingInput: return 1
        case .working: return 2
        case .active: return 3
        case .completed: return 4
        }
    }
}

private extension HolySessionAttention {
    var rosterRank: Int {
        switch self {
        case .failure: return 0
        case .conflict: return 1
        case .needsInput: return 2
        case .watch: return 3
        case .none: return 4
        case .done: return 5
        }
    }
}
