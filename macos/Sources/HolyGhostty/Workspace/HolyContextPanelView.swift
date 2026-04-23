import SwiftUI

struct HolyContextPanelView: View {
    let session: HolySession?
    let coordination: HolySessionCoordination

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let session {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        missionSection(session)
                        runtimeSection(session)
                        budgetSection(session)
                        timelineSection(session)
                        coordinationSection(session)
                        gitSection(session)
                        launchSection(session)
                        emptyRailFallback(session)
                    }
                    .padding(12)
                }
                .scrollIndicators(.hidden)
            } else {
                HolyGhosttyEmptyStateView(
                    title: "No context",
                    subtitle: "Select a session to inspect.",
                    symbol: "sidebar.left"
                )
                .frame(maxHeight: .infinity)
            }
        }
    }

    // MARK: - Mission

    @ViewBuilder
    private func missionSection(_ session: HolySession) -> some View {
        if let task = session.record.launchSpec.task {
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("Mission")

                Text(session.missionDisplay)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(HolyGhosttyTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                contextRow("Task", "\(task.sourceSummary) · \(task.title)")

                if !session.signals.isEmpty, let signal = session.signals.first {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(signalColor(signal.kind))
                            .frame(width: 5, height: 5)
                        Text(signal.headline)
                            .font(.system(size: 11))
                            .foregroundStyle(signalColor(signal.kind))
                            .lineLimit(2)
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    // MARK: - Coordination (only when there's something to report)

    @ViewBuilder
    private func runtimeSection(_ session: HolySession) -> some View {
        if session.runtimeTelemetry.isMeaningful {
            let telemetry = session.runtimeTelemetry

            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("Runtime")

                contextRow("Activity", telemetry.activityKind.displayName)

                if let headline = telemetry.headline, !headline.isEmpty {
                    contextRow("Headline", headline)
                }

                if let progressPercent = telemetry.progressPercent {
                    contextRow("Progress", "\(progressPercent)%")
                }

                if let command = telemetry.command, !command.isEmpty {
                    contextRow("Command", command)
                }

                if let filePath = telemetry.filePath, !filePath.isEmpty {
                    contextRow("File", filePath)
                }

                if let nextStepHint = telemetry.nextStepHint, !nextStepHint.isEmpty {
                    contextRow("Next Step", nextStepHint)
                }

                if let artifactSummary = telemetry.artifactSummary, !artifactSummary.isEmpty {
                    contextRow("Artifact", artifactSummary)
                }

                if let artifactPath = telemetry.artifactPath,
                   !artifactPath.isEmpty,
                   artifactPath != telemetry.filePath {
                    contextRow("Artifact Path", artifactPath)
                }

                if let stagnantSeconds = telemetry.stagnantSeconds, stagnantSeconds > 0 {
                    contextRow("Stagnant", "\(stagnantSeconds)s")
                }

                if let repeatedEvidenceCount = telemetry.repeatedEvidenceCount,
                   repeatedEvidenceCount > 1 {
                    contextRow("Repeats", "\(repeatedEvidenceCount)x")
                }

                if let evidence = telemetry.evidence ?? telemetry.detail, !evidence.isEmpty {
                    Text(evidence)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(HolyGhosttyTheme.textTertiary)
                        .lineLimit(3)
                        .padding(.top, 2)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(runtimeTint(for: telemetry.activityKind).opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(runtimeTint(for: telemetry.activityKind).opacity(0.15), lineWidth: 0.5)
            )
        }
    }

    @ViewBuilder
    private func budgetSection(_ session: HolySession) -> some View {
        if session.budget.isConfigured || session.budgetTelemetry.hasUsage {
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("Budget")

                contextRow("Status", session.budgetStatus.displayName)
                contextRow("Usage", session.budgetSummaryText)
                contextRow("Remaining", session.budgetRemainingText)

                if session.budgetTelemetry.hasUsage {
                    contextRow("Burn Rate", session.budgetBurnRateText)

                    if let evidence = session.budgetTelemetry.evidence, !evidence.isEmpty {
                        Text(evidence)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(HolyGhosttyTheme.textTertiary)
                            .lineLimit(3)
                            .padding(.top, 2)
                    }
                }

                if session.budget.isConfigured {
                    HolyBudgetIntelligenceSection(
                        sessionID: session.id,
                        runtime: session.runtime,
                        budget: session.budget,
                        refreshID: budgetRefreshID(for: session)
                    )
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(budgetTint(for: session).opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(budgetTint(for: session).opacity(0.15), lineWidth: 0.5)
            )
        }
    }

    private func timelineSection(_ session: HolySession) -> some View {
        HolySessionTimelineSection(
            sessionID: session.id,
            refreshID: timelineRefreshID(for: session)
        )
    }

    @ViewBuilder
    private func coordinationSection(_ session: HolySession) -> some View {
        let hasIssues = coordination.hasBlockingConflict
            || coordination.hasSharedBranch
            || session.hasBranchOwnershipDrift
            || !coordination.overlappingFiles.isEmpty

        if hasIssues {
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("Coordination")

                Text(coordination.summary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(coordination.hasBlockingConflict ? HolyGhosttyTheme.danger : HolyGhosttyTheme.warning)

                if !coordination.sharedWorktreeSessionTitles.isEmpty {
                    contextRow("Shared worktree", coordination.sharedWorktreeSessionTitles.joined(separator: ", "))
                }

                if !coordination.sharedBranchSessionTitles.isEmpty {
                    contextRow("Shared branch", coordination.sharedBranchSessionTitles.joined(separator: ", "))
                }

                if !coordination.overlappingFiles.isEmpty {
                    contextRow("Overlapping files", coordination.overlappingFiles.prefix(5).joined(separator: "\n"))
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(coordination.hasBlockingConflict
                          ? HolyGhosttyTheme.danger.opacity(0.06)
                          : HolyGhosttyTheme.warning.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(coordination.hasBlockingConflict
                            ? HolyGhosttyTheme.danger.opacity(0.15)
                            : HolyGhosttyTheme.warning.opacity(0.15),
                            lineWidth: 0.5)
            )
        }
    }

    // MARK: - Git

    @ViewBuilder
    private func gitSection(_ session: HolySession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Repository")

            if let git = session.gitSnapshot {
                contextRow("Branch", git.branchDisplayName)
                contextRow("Changes", git.changeSummaryText)

                if git.syncStatusText != "Up to date" {
                    contextRow("Sync", git.syncStatusText)
                }

                if !git.changedFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(git.changedFiles.prefix(8).enumerated()), id: \.offset) { _, change in
                            HStack(spacing: 6) {
                                Text(change.category.displayName)
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(fileColor(change.category))
                                    .frame(width: 20, alignment: .leading)

                                Text(change.path)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(HolyGhosttyTheme.textSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }

                        if git.changedFiles.count > 8 {
                            Text("+\(git.changedFiles.count - 8) more")
                                .font(.system(size: 10))
                                .foregroundStyle(HolyGhosttyTheme.textTertiary)
                        }
                    }
                    .padding(.top, 2)
                }
            } else {
                Text("No repository detected")
                    .font(.system(size: 11))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
            }
        }
    }

    // MARK: - Launch metadata (collapsed into Details)

    private func launchSection(_ session: HolySession) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                contextRow("Runtime", session.displayRuntime.displayName)
                contextRow("Owner", session.ownership.label)
                contextRow("Transport", session.record.launchSpec.transport.summaryText)
                contextRow("Directory", session.workingDirectory ?? "Unassigned")

                if session.record.launchSpec.transport.isRemote {
                    contextRow("Host", session.record.launchSpec.transport.destinationDisplayName)
                }

                if let tmux = session.record.launchSpec.tmux {
                    contextRow("Tmux", "\(tmux.serverLabel) · \(tmux.sessionDisplayName)")
                }

                if let task = session.record.launchSpec.task {
                    contextRow("Task Source", task.sourceSummary)
                }

                if let command = session.record.launchSpec.command {
                    contextRow("Command", command)
                }

                if session.commandTelemetry.runCount > 0 {
                    contextRow("Runs", "\(session.commandTelemetry.runCount) (\(session.commandTelemetry.successCount) ok, \(session.commandTelemetry.failureCount) fail)")
                }
            }
            .padding(.top, 6)
        } label: {
            sectionLabel("Details")
        }
    }

    // MARK: - Empty-rail fallback

    @ViewBuilder
    private func emptyRailFallback(_ session: HolySession) -> some View {
        if shouldShowEmptyFallback(session) {
            Text("No external context yet.")
                .font(.system(size: 11))
                .foregroundStyle(HolyGhosttyTheme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        }
    }

    private func shouldShowEmptyFallback(_ session: HolySession) -> Bool {
        let hasMission = session.record.launchSpec.task != nil
        let hasRuntime = session.runtimeTelemetry.isMeaningful
        let hasBudget = session.budget.isConfigured || session.budgetTelemetry.hasUsage
        let hasCoordination = coordination.hasBlockingConflict
            || coordination.hasSharedBranch
            || session.hasBranchOwnershipDrift
            || !coordination.overlappingFiles.isEmpty
        let hasGit = session.gitSnapshot != nil
        return !(hasMission || hasRuntime || hasBudget || hasCoordination || hasGit)
    }

    // MARK: - Primitives

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(HolyGhosttyTheme.halo.opacity(0.55))
            .textCase(.uppercase)
            .tracking(0.6)
    }

    private func contextRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(key)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(HolyGhosttyTheme.textTertiary)
                .frame(width: 70, alignment: .trailing)

            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(HolyGhosttyTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func signalColor(_ kind: HolySessionSignalKind) -> Color {
        switch kind {
        case .failure:      return HolyGhosttyTheme.danger
        case .approval:     return HolyGhosttyTheme.warning
        case .completion:   return HolyGhosttyTheme.success
        case .coordination: return HolyGhosttyTheme.warning
        case .command:      return HolyGhosttyTheme.accent
        case .progress, .reading, .editing: return HolyGhosttyTheme.accent
        }
    }

    private func runtimeTint(for kind: HolySessionActivityKind) -> Color {
        switch kind {
        case .approval:
            return HolyGhosttyTheme.warning
        case .stalled, .looping:
            return HolyGhosttyTheme.warning
        case .failure:
            return HolyGhosttyTheme.danger
        case .completion:
            return HolyGhosttyTheme.success
        case .progress, .reading, .editing, .command:
            return HolyGhosttyTheme.accent
        case .idle:
            return HolyGhosttyTheme.textTertiary
        }
    }

    private func fileColor(_ category: HolyGitFileChangeCategory) -> Color {
        switch category {
        case .added, .copied:                        return HolyGhosttyTheme.success
        case .modified, .renamed, .typeChanged:      return HolyGhosttyTheme.accent
        case .deleted:                               return HolyGhosttyTheme.danger
        case .conflicted:                            return HolyGhosttyTheme.danger
        case .untracked, .unknown:                   return HolyGhosttyTheme.textTertiary
        }
    }

    private func budgetTint(for session: HolySession) -> Color {
        switch session.budgetStatus {
        case .none: return HolyGhosttyTheme.textTertiary
        case .healthy: return HolyGhosttyTheme.success
        case .warning: return HolyGhosttyTheme.warning
        case .exceeded: return HolyGhosttyTheme.danger
        }
    }

    private func timelineRefreshID(for session: HolySession) -> String {
        let runtimeUpdatedAt = session.runtimeTelemetry.lastUpdatedAt?.timeIntervalSince1970 ?? 0
        return "\(session.id.uuidString)-\(session.activityAt.timeIntervalSince1970)-\(runtimeUpdatedAt)-\(session.phase.rawValue)"
    }

    private func budgetRefreshID(for session: HolySession) -> String {
        let budgetUpdatedAt = session.budgetTelemetry.lastUpdatedAt?.timeIntervalSince1970 ?? 0
        return "\(session.id.uuidString)-\(session.activityAt.timeIntervalSince1970)-\(budgetUpdatedAt)-\(session.budgetStatus.rawValue)"
    }
}
