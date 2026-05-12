import SwiftUI
import GhosttyKit

struct HolySessionDetailView: View {
    let session: HolySession?
    let coordination: HolySessionCoordination
    let ghosttyApp: Ghostty.App?
    var focusMode: Bool = false
    var splitSurface: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let session {
                sessionHeader(session)

                HolyGhosttySurfaceFrame(halo: true) {
                    activeSurface(session: session)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
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
            HolyGhosttyStatusDot(color: phaseColor(for: session))

            Text(session.displayLineTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(HolyGhosttyTheme.textPrimary)
                .lineLimit(1)

            if let subtitle = headerSubtitle(for: session) {
                Text("—")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)

                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HolyGhosttyTheme.textPrimary)
                    .lineLimit(1)
            }

            Spacer()

            if let headerStatus = headerStatus(for: session) {
                Text(headerStatus.text)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(headerStatus.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func headerSubtitle(for session: HolySession) -> String? {
        var parts: [String] = [session.displayRuntime.displayName]
        let launchSpec = session.record.launchSpec

        if launchSpec.transport.isRemote {
            parts.append(launchSpec.transport.summaryText)
        }

        if let tmux = launchSpec.tmux,
           let sessionName = tmux.sessionName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sessionName.isEmpty,
           !session.displayLineTitle.localizedCaseInsensitiveContains(sessionName) {
            parts.append("tmux \(sessionName)")
        }

        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    // MARK: - Header Status

    // MARK: - Surface

    @ViewBuilder
    private func activeSurface(session: HolySession) -> some View {
        if let ghosttyApp {
            Ghostty.SurfaceWrapper(surfaceView: session.surfaceView, isSplit: splitSurface)
                .environmentObject(ghosttyApp)
                .ghosttyLastFocusedSurface(Weak(session.surfaceView))
                .id(session.id)
        } else {
            HolyGhosttyEmptyStateView(
                title: "Surface unavailable",
                subtitle: "No Ghostty app object injected.",
                symbol: "app.badge"
            )
        }
    }

    // MARK: - Colors

    private func headerStatus(for session: HolySession) -> (text: String, color: Color)? {
        if let runtimeSummary = session.runtimeTelemetrySummaryText {
            return (runtimeSummary, runtimeColor(for: session.runtimeTelemetry.activityKind))
        }

        if let coordinationSummary = coordinationStatusText(for: session) {
            return (coordinationSummary, coordinationStatusColor(for: session))
        }

        if let git = session.gitSnapshot, !git.isClean {
            return (session.changeSummaryText, changeColor(for: session))
        }

        if session.budget.isConfigured || session.budgetTelemetry.hasUsage {
            return (session.budgetSummaryText, budgetColor(for: session))
        }

        return (session.statusText, phaseColor(for: session))
    }

    private func coordinationStatusText(for session: HolySession) -> String? {
        if !coordination.overlappingFiles.isEmpty {
            let count = coordination.overlappingFiles.count
            return count == 1 ? "1 overlapping file" : "\(count) overlapping files"
        }

        if !coordination.sharedWorktreeSessionIDs.isEmpty {
            let count = coordination.sharedWorktreeSessionIDs.count
            return count == 1 ? "same worktree as 1 session" : "same worktree as \(count) sessions"
        }

        if coordination.hasSharedBranch {
            let count = coordination.sharedBranchSessionIDs.count
            return count == 1 ? "same branch as 1 session" : "same branch as \(count) sessions"
        }

        if session.hasBranchOwnershipDrift {
            return "branch drift"
        }

        return nil
    }

    private func coordinationStatusColor(for session: HolySession) -> Color {
        if !coordination.overlappingFiles.isEmpty || session.hasBranchOwnershipDrift {
            return HolyGhosttyTheme.warning
        }

        return HolyGhosttyTheme.textTertiary
    }

    private func phaseColor(for session: HolySession?) -> Color {
        guard let session else { return HolyGhosttyTheme.textTertiary }
        switch session.phase {
        case .active:
            return HolyGhosttyTheme.textTertiary
        case .working:
            return HolyAgentPalette.workingBlue
        case .waitingInput:
            return HolyWaitingFreshness(age: Date.now.timeIntervalSince(session.activityAt)).color
        case .completed:
            return HolyAgentPalette.done
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

    private func budgetColor(for session: HolySession) -> Color {
        switch session.budgetStatus {
        case .none:
            return HolyGhosttyTheme.textTertiary
        case .healthy:
            return HolyGhosttyTheme.success
        case .warning:
            return HolyGhosttyTheme.warning
        case .exceeded:
            return HolyGhosttyTheme.danger
        }
    }

    private func runtimeColor(for kind: HolySessionActivityKind) -> Color {
        switch kind {
        case .approval:
            guard let session else { return HolyAgentPalette.agingWait }
            return HolyWaitingFreshness(age: Date.now.timeIntervalSince(session.activityAt)).color
        case .stalled, .looping:
            return HolyAgentPalette.stalled
        case .failure:
            return HolyGhosttyTheme.danger
        case .completion:
            return HolyAgentPalette.done
        case .progress, .reading, .editing, .command:
            return HolyAgentPalette.workingBlue
        case .idle:
            return HolyGhosttyTheme.textTertiary
        }
    }
}
