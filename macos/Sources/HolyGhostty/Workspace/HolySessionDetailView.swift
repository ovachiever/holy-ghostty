import SwiftUI
import GhosttyKit

struct HolySessionDetailView: View {
    let session: HolySession?
    let coordination: HolySessionCoordination
    let ghosttyApp: Ghostty.App?
    var focusMode: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let session {
                sessionHeader(session)

                HolyGhosttySurfaceFrame(halo: true) {
                    activeSurface(session: session)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)

                statusBar(session)
            } else {
                HolyGhosttyEmptyStateView(
                    title: "No session selected",
                    subtitle: "Create a session or choose one from the roster.",
                    symbol: "rectangle.stack.badge.plus"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Session Header (minimal: title + objective)

    private func sessionHeader(_ session: HolySession) -> some View {
        HStack(alignment: .center, spacing: 8) {
            HolyGhosttyStatusDot(color: attentionColor)

            Text(session.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(HolyGhosttyTheme.textPrimary)
                .lineLimit(1)

            if let objective = session.record.launchSpec.objective,
               !objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(objective)
                    .font(.system(size: 11))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            Text(coordination.attention.displayName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(attentionColor)
                .textCase(.uppercase)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Status Bar (thin footer with key metrics)

    private func statusBar(_ session: HolySession) -> some View {
        HStack(spacing: 16) {
            statusItem(session.statusText, color: phaseColor(for: session))
            statusItem(session.runtime.displayName, color: HolyGhosttyTheme.textTertiary)
            statusItem(session.ownership.branchDisplayName, color: branchColor(for: session))
            statusItem(session.changeSummaryText, color: changeColor(for: session))

            Spacer()

            Text(session.activityAt.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(HolyGhosttyTheme.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(HolyGhosttyTheme.bgElevated)
    }

    private func statusItem(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
    }

    // MARK: - Surface

    @ViewBuilder
    private func activeSurface(session: HolySession) -> some View {
        if let ghosttyApp {
            Ghostty.SurfaceWrapper(surfaceView: session.surfaceView)
                .environmentObject(ghosttyApp)
                .ghosttyLastFocusedSurface(Weak(session.surfaceView))
        } else {
            HolyGhosttyEmptyStateView(
                title: "Surface unavailable",
                subtitle: "No Ghostty app object injected.",
                symbol: "app.badge"
            )
        }
    }

    // MARK: - Colors

    private var attentionColor: Color {
        switch coordination.attention {
        case .none:       return phaseColor(for: session)
        case .watch:      return HolyGhosttyTheme.accent
        case .needsInput: return HolyGhosttyTheme.warning
        case .failure, .conflict: return HolyGhosttyTheme.danger
        case .done:       return HolyGhosttyTheme.success
        }
    }

    private func phaseColor(for session: HolySession?) -> Color {
        guard let session else { return HolyGhosttyTheme.textTertiary }
        switch session.phase {
        case .active:       return HolyGhosttyTheme.success
        case .working:      return HolyGhosttyTheme.accent
        case .waitingInput: return HolyGhosttyTheme.warning
        case .completed:    return HolyGhosttyTheme.success
        case .failed:       return HolyGhosttyTheme.danger
        }
    }

    private func branchColor(for session: HolySession) -> Color {
        if session.hasBranchOwnershipDrift { return HolyGhosttyTheme.warning }
        if session.gitSnapshot?.hasConflicts == true { return HolyGhosttyTheme.danger }
        return session.gitSnapshot == nil ? HolyGhosttyTheme.textTertiary : HolyGhosttyTheme.accentSoft
    }

    private func changeColor(for session: HolySession) -> Color {
        guard let gitSnapshot = session.gitSnapshot else { return HolyGhosttyTheme.textTertiary }
        if gitSnapshot.hasConflicts { return HolyGhosttyTheme.danger }
        return gitSnapshot.isClean ? HolyGhosttyTheme.success : HolyGhosttyTheme.warning
    }
}
