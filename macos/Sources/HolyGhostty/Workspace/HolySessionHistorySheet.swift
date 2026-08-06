import SwiftUI

struct HolySessionHistorySheet: View {
    @ObservedObject var store: HolyWorkspaceStore
    @State private var searchText: String = ""

    // MARK: - Signage (pure, testable)

    /// Title for the sheet-top crash-restore affordance; nil when there is
    /// nothing to restore. Counts mirror the banner's honesty: fresh batch
    /// first, older interruptions named separately, never merged.
    static func crashRestoreAffordanceTitle(freshCount: Int, olderCount: Int) -> String? {
        guard freshCount + olderCount > 0 else { return nil }
        guard freshCount > 0 else {
            return "Open Session Restore (\(olderCount) older)"
        }
        return olderCount > 0
            ? "Open Session Restore (\(freshCount) interrupted · \(olderCount) older)"
            : "Open Session Restore (\(freshCount) interrupted)"
    }

    /// Recovery-state label for a history row; nil for plain archives.
    /// Cold-boot rows are restorable interruptions; every other recovery
    /// reason means the workspace needs repair before a relaunch.
    static func recoveryStateLabel(for archived: HolyArchivedSession) -> String? {
        guard archived.recoveryReason != nil else { return nil }
        return HolyWorkspaceStore.isCrashRestoreCandidate(archived)
            ? "Interrupted"
            : "Needs repair"
    }

    private var filteredArchivedSessions: [HolyArchivedSession] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.archivedSessions }

        let lowercasedQuery = query.lowercased()
        return store.archivedSessions.filter { archived in
            [
                archived.title,
                archived.missionDisplay,
                archived.preview,
                archived.ownership.summary,
                archived.gitSnapshot?.repositoryName,
                archived.gitSnapshot?.branchDisplayName,
                archived.ownership.branchDisplayName,
                archived.workingDirectoryDisplay,
            ]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(lowercasedQuery) }
        }
    }

    private var selectedArchivedSession: HolyArchivedSession? {
        guard let id = store.selectedArchivedSessionID else {
            return filteredArchivedSessions.first
        }
        return filteredArchivedSessions.first { $0.id == id } ?? filteredArchivedSessions.first
    }

    var body: some View {
        ZStack {
            HolyGhosttyBackdrop()

            VStack(spacing: 0) {
                header

                Rectangle()
                    .fill(HolyGhosttyTheme.border)
                    .frame(height: 0.5)

                crashRestoreCallout

                HSplitView {
                    historyList
                        .frame(minWidth: 260, idealWidth: 320, maxWidth: 400, maxHeight: .infinity)
                        .background(HolyGhosttyTheme.bgElevated)

                    historyDetail
                        .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                        .layoutPriority(1)
                }
            }
        }
        .frame(minWidth: 1000, minHeight: 680)
        .onAppear(perform: ensureSelection)
        .onChange(of: filteredArchivedSessions.map(\.id)) { _ in ensureSelection() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Text("Session History")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(HolyGhosttyTheme.halo)

                Text("\(store.archivedSessions.count) archived")
                    .font(.system(size: 11))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)

                Spacer()

                Button("Done") { store.historyPresented = false }
                    .buttonStyle(HolyGhosttyActionButtonStyle())
            }

            Text("Where sessions land after leaving the roster. Select a row to inspect, relaunch, or delete it.")
                .font(.system(size: 11))
                .foregroundStyle(HolyGhosttyTheme.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(HolyGhosttyTheme.bgElevated)
    }

    /// One prominent path from the place people land by accident to the
    /// surface that actually restores: shown only while cold-boot archives
    /// exist, styled like the workspace banner so the pattern reads as the
    /// same event.
    @ViewBuilder
    private var crashRestoreCallout: some View {
        let batch = store.crashRestoreBatch
        if let title = Self.crashRestoreAffordanceTitle(
            freshCount: batch.fresh.count,
            olderCount: batch.older.count
        ) {
            HStack(spacing: 10) {
                Image(systemName: "bolt.trianglebadge.exclamationmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HolyGhosttyTheme.warning)

                Text("Interrupted sessions resume their exact conversations in Session Restore.")
                    .font(.system(size: 11))
                    .foregroundStyle(HolyGhosttyTheme.textPrimary)

                Spacer()

                Button(title) {
                    store.historyPresented = false
                    store.presentRestore()
                }
                .buttonStyle(HolyGhosttyProminentButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(HolyGhosttyTheme.warning.opacity(0.10))
            .background(HolyGhosttyTheme.bgElevated)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(HolyGhosttyTheme.border)
                    .frame(height: 0.5)
            }
        }
    }

    // MARK: - List

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(HolyGhosttyTheme.bgSurface)
                )
                .padding(.horizontal, 10)
                .padding(.top, 10)

            if filteredArchivedSessions.isEmpty {
                HolyGhosttyEmptyStateView(
                    title: store.archivedSessions.isEmpty ? "No archives" : "No matches",
                    subtitle: store.archivedSessions.isEmpty
                        ? "Archived sessions appear here."
                        : "Try different terms.",
                    symbol: "archivebox"
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredArchivedSessions) { archived in
                            HistoryRow(
                                archived: archived,
                                isSelected: archived.id == selectedArchivedSession?.id,
                                onSelect: { store.selectedArchivedSessionID = archived.id }
                            )
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    // MARK: - Detail

    private var historyDetail: some View {
        Group {
            if let archived = selectedArchivedSession {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(archived.title)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(HolyGhosttyTheme.textPrimary)

                            Text(archived.missionDisplay)
                                .font(.system(size: 12))
                                .foregroundStyle(HolyGhosttyTheme.textSecondary)
                        }

                        actionBar(for: archived)
                        metadataSection(for: archived)
                        recoverySection(for: archived)

                        if let git = archived.gitSnapshot {
                            gitSection(for: git)
                        }

                        if archived.runtimeTelemetry.isMeaningful
                            || !archived.signals.isEmpty
                            || archived.commandTelemetry.runCount > 0
                            || archived.budgetTelemetry.hasUsage {
                            telemetrySection(for: archived)
                        }

                        timelineSection(for: archived)

                        if !archived.preview.isEmpty {
                            outputSection(for: archived)
                        }

                        ownershipSection(for: archived)
                    }
                    .padding(16)
                }
                .scrollIndicators(.hidden)
            } else {
                HolyGhosttyEmptyStateView(
                    title: "No session selected",
                    subtitle: "Choose from the archive.",
                    symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Detail Sections

    private func actionBar(for archived: HolyArchivedSession) -> some View {
        HStack(spacing: 6) {
            Button {
                store.relaunch(archived)
                store.historyPresented = false
            } label: {
                // Cold-boot rows route into the restore engine, so the
                // button says where the click actually goes.
                Label(
                    HolyWorkspaceStore.isCrashRestoreCandidate(archived)
                        ? "Open Session Restore"
                        : archived.relaunchActionTitle,
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(HolyGhosttyActionButtonStyle())

            Button {
                store.presentComposer(using: archived)
                store.historyPresented = false
            } label: {
                Label("Edit Launch", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(HolyGhosttyActionButtonStyle())

            Button("Delete") { store.deleteArchive(archived) }
                .buttonStyle(HolyGhosttyActionButtonStyle())

            Spacer()
        }
    }

    private func metadataSection(for archived: HolyArchivedSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            detailSectionLabel("Details")
            detailRow("Phase", archived.phase.displayName, color: phaseColor(for: archived.phase))
            detailRow("Runtime", archived.runtime.displayName)
            detailRow("Archived", archived.archivedAt.formatted(date: .abbreviated, time: .shortened))
            detailRow("Last Activity", archived.lastActivityAt.formatted(date: .abbreviated, time: .shortened))
            detailRow("Directory", archived.workingDirectoryDisplay)

            if let command = archived.record.launchSpec.command {
                detailRow("Command", command)
            }
        }
    }

    @ViewBuilder
    private func recoverySection(for archived: HolyArchivedSession) -> some View {
        if let recoveryReason = archived.recoveryReason {
            VStack(alignment: .leading, spacing: 6) {
                detailSectionLabel("Recovery")
                detailRow("Reason", recoveryReason)

                if let cleanupSummary = archived.recoveryCleanupSummary {
                    detailRow("Cleanup", cleanupSummary)
                }

                if let suggestedAction = archived.recoverySuggestedAction {
                    detailRow("Next Step", suggestedAction)
                }
            }
        }
    }

    private func gitSection(for snapshot: HolyGitSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            detailSectionLabel("Repository")
            detailRow("Branch", snapshot.branchDisplayName)
            detailRow("Changes", snapshot.changeSummaryText)
            detailRow("Sync", snapshot.syncStatusText)

            if !snapshot.changedFiles.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(snapshot.changedFiles.prefix(10).enumerated()), id: \.offset) { _, change in
                        HStack(spacing: 6) {
                            Text(change.category.displayName)
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(fileColor(change.category))
                                .frame(width: 20, alignment: .leading)
                            Text(change.path)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(HolyGhosttyTheme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.leading, 78)
            }
        }
    }

    private func telemetrySection(for archived: HolyArchivedSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            detailSectionLabel("Telemetry")

            if archived.runtimeTelemetry.isMeaningful {
                detailRow("Activity", archived.runtimeTelemetry.activityKind.displayName)

                if let headline = archived.runtimeTelemetry.headline, !headline.isEmpty {
                    detailRow("Runtime", headline)
                }

                if let progressPercent = archived.runtimeTelemetry.progressPercent {
                    detailRow("Progress", "\(progressPercent)%")
                }

                if let command = archived.runtimeTelemetry.command, !command.isEmpty {
                    detailRow("Command", command)
                }

                if let filePath = archived.runtimeTelemetry.filePath, !filePath.isEmpty {
                    detailRow("File", filePath)
                }

                if let nextStepHint = archived.runtimeTelemetry.nextStepHint, !nextStepHint.isEmpty {
                    detailRow("Next", nextStepHint)
                }

                if let artifactSummary = archived.runtimeTelemetry.artifactSummary, !artifactSummary.isEmpty {
                    detailRow("Artifact", artifactSummary)
                }

                if let artifactPath = archived.runtimeTelemetry.artifactPath,
                   !artifactPath.isEmpty,
                   artifactPath != archived.runtimeTelemetry.filePath {
                    detailRow("Artifact Path", artifactPath)
                }

                if let stagnantSeconds = archived.runtimeTelemetry.stagnantSeconds, stagnantSeconds > 0 {
                    detailRow("Stagnant", "\(stagnantSeconds)s")
                }

                if let repeatedEvidenceCount = archived.runtimeTelemetry.repeatedEvidenceCount,
                   repeatedEvidenceCount > 1 {
                    detailRow("Repeats", "\(repeatedEvidenceCount)x")
                }
            }

            if !archived.signals.isEmpty {
                ForEach(Array(archived.signals.prefix(3).enumerated()), id: \.offset) { _, signal in
                    detailRow(signal.kind.displayName, signal.headline)
                }
            }

            if archived.commandTelemetry.runCount > 0 {
                detailRow("Runs", "\(archived.commandTelemetry.runCount) (\(archived.commandTelemetry.successCount) ok)")
                detailRow("Last", archived.commandTelemetry.lastOutcomeText)
            }

            if archived.budgetTelemetry.hasUsage {
                if let totalTokens = archived.budgetTelemetry.resolvedTotalTokens {
                    detailRow("Tokens", formattedTokenCount(totalTokens))
                }

                if let estimatedCostUSD = archived.budgetTelemetry.estimatedCostUSD {
                    detailRow("Cost", String(format: "$%.2f", estimatedCostUSD))
                }
            }
        }
    }

    private func timelineSection(for archived: HolyArchivedSession) -> some View {
        HolySessionTimelineSection(
            sessionID: archived.sourceSessionID,
            refreshID: timelineRefreshID(for: archived),
            limit: 12
        )
    }

    private func outputSection(for archived: HolyArchivedSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            detailSectionLabel("Output")

            Text(archived.preview)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(HolyGhosttyTheme.textSecondary)
                .lineLimit(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(HolyGhosttyTheme.bg)
                )
        }
    }

    private func ownershipSection(for archived: HolyArchivedSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            detailSectionLabel("Ownership")
            detailRow("Source", archived.ownership.source.displayName)
            detailRow("Summary", archived.ownership.summary)
            detailRow("Reserved", archived.ownership.branchDisplayName)
            detailRow("Observed", archived.branchDisplayName)
        }
    }

    // MARK: - Primitives

    private func detailSectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(HolyGhosttyTheme.textTertiary)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.bottom, 2)
    }

    private func detailRow(_ key: String, _ value: String, color: Color = HolyGhosttyTheme.textPrimary) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(key)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(HolyGhosttyTheme.textTertiary)
                .frame(width: 70, alignment: .trailing)

            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func formattedTokenCount(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    private func timelineRefreshID(for archived: HolyArchivedSession) -> String {
        let runtimeUpdatedAt = archived.runtimeTelemetry.lastUpdatedAt?.timeIntervalSince1970 ?? 0
        return [
            archived.sourceSessionID.uuidString,
            String(archived.archivedAt.timeIntervalSince1970),
            String(archived.lastActivityAt.timeIntervalSince1970),
            String(runtimeUpdatedAt),
            archived.phase.rawValue,
        ].joined(separator: "-")
    }

    private func ensureSelection() {
        guard let first = filteredArchivedSessions.first else {
            store.selectedArchivedSessionID = nil
            return
        }
        guard let id = store.selectedArchivedSessionID else {
            store.selectedArchivedSessionID = first.id
            return
        }
        if !filteredArchivedSessions.contains(where: { $0.id == id }) {
            store.selectedArchivedSessionID = first.id
        }
    }

    private func phaseColor(for phase: HolySessionPhase) -> Color {
        switch phase {
        case .active:       return HolyGhosttyTheme.success
        case .working:      return HolyGhosttyTheme.accent
        case .waitingInput: return HolyGhosttyTheme.warning
        case .completed:    return HolyGhosttyTheme.success
        case .failed:       return HolyGhosttyTheme.danger
        }
    }

    private func fileColor(_ category: HolyGitFileChangeCategory) -> Color {
        switch category {
        case .added, .copied:                   return HolyGhosttyTheme.success
        case .modified, .renamed, .typeChanged: return HolyGhosttyTheme.accent
        case .deleted:                          return HolyGhosttyTheme.danger
        case .conflicted:                       return HolyGhosttyTheme.danger
        case .untracked, .unknown:              return HolyGhosttyTheme.textTertiary
        }
    }
}

// MARK: - History Row

private struct HistoryRow: View {
    let archived: HolyArchivedSession
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            HolyGhosttyStatusDot(color: phaseColor)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(archived.title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.white : HolyGhosttyTheme.textPrimary)
                        .lineLimit(1)

                    if let recoveryLabel = HolySessionHistorySheet.recoveryStateLabel(for: archived) {
                        Text(recoveryLabel)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(recoveryLabel == "Interrupted"
                                ? HolyGhosttyTheme.warning
                                : HolyGhosttyTheme.danger)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule(style: .continuous)
                                    .fill((recoveryLabel == "Interrupted"
                                        ? HolyGhosttyTheme.warning
                                        : HolyGhosttyTheme.danger).opacity(0.12))
                            )
                    }
                }

                Text(archived.primarySignal?.headline ?? archived.phase.displayName)
                    .font(.system(size: 10))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(archived.archivedAt.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(HolyGhosttyTheme.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? HolyGhosttyTheme.bgSurface : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onTapGesture(perform: onSelect)
    }

    private var phaseColor: Color {
        switch archived.phase {
        case .active:       return HolyGhosttyTheme.success
        case .working:      return HolyGhosttyTheme.accent
        case .waitingInput: return HolyGhosttyTheme.warning
        case .completed:    return HolyGhosttyTheme.success
        case .failed:       return HolyGhosttyTheme.danger
        }
    }
}
