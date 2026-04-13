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
                        coordinationSection(session)
                        gitSection(session)
                        outputSection(session)
                        launchSection(session)
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

    private func missionSection(_ session: HolySession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Mission")

            Text(session.missionDisplay)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(HolyGhosttyTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

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

    // MARK: - Coordination (only when there's something to report)

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

    // MARK: - Output Preview

    @ViewBuilder
    private func outputSection(_ session: HolySession) -> some View {
        if !session.preview.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("Output")

                Text(session.preview)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(HolyGhosttyTheme.textSecondary)
                    .lineLimit(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(HolyGhosttyTheme.bg)
                    )
            }
        }
    }

    // MARK: - Launch metadata (collapsed)

    private func launchSection(_ session: HolySession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Launch")

            contextRow("Runtime", session.runtime.displayName)
            contextRow("Owner", session.ownership.label)
            contextRow("Directory", session.workingDirectory ?? "Unassigned")

            if let command = session.record.launchSpec.command {
                contextRow("Command", command)
            }

            if session.commandTelemetry.runCount > 0 {
                contextRow("Runs", "\(session.commandTelemetry.runCount) (\(session.commandTelemetry.successCount) ok, \(session.commandTelemetry.failureCount) fail)")
            }
        }
    }

    // MARK: - Primitives

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(HolyGhosttyTheme.textTertiary)
            .textCase(.uppercase)
            .tracking(0.5)
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

    private func fileColor(_ category: HolyGitFileChangeCategory) -> Color {
        switch category {
        case .added, .copied:                        return HolyGhosttyTheme.success
        case .modified, .renamed, .typeChanged:      return HolyGhosttyTheme.accent
        case .deleted:                               return HolyGhosttyTheme.danger
        case .conflicted:                            return HolyGhosttyTheme.danger
        case .untracked, .unknown:                   return HolyGhosttyTheme.textTertiary
        }
    }
}
