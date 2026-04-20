import SwiftUI
import GhosttyKit

private enum HolyWorkspaceDisplayMode: String {
    case standard
    case focus
    case grid
    case diff
}

struct HolyWorkspaceRootView: View {
    @EnvironmentObject private var ghostty: Ghostty.App
    @ObservedObject var store: HolyWorkspaceStore
    @SceneStorage("holy.workspace.displayMode") private var displayModeRaw = HolyWorkspaceDisplayMode.standard.rawValue
    @SceneStorage("holy.workspace.diffCompareSessionID") private var diffCompareSessionIDRaw: String?

    var body: some View {
        ZStack {
            HolyGhosttyBackdrop()

            VStack(spacing: 0) {
                header

                Rectangle()
                    .fill(HolyGhosttyTheme.border)
                    .frame(height: 0.5)

                workspaceContent
            }
        }
        .sheet(isPresented: $store.composerPresented) {
            HolyNewSessionSheet(
                draft: $store.draft,
                templates: store.availableTemplates,
                ownershipPreview: store.draftOwnershipPreview,
                launchGuardrail: store.draftLaunchGuardrail,
                isCheckingLaunchOwnership: store.draftLaunchGuardrailRefreshing,
                errorMessage: store.composerErrorMessage,
                isBusy: store.composerBusy,
                onApplyTemplate: { store.applyTemplateToDraft($0) },
                onDraftChanged: { store.refreshDraftLaunchGuardrail() },
                onSaveTemplate: { store.saveDraftAsTemplate() },
                onCreate: { store.createFromDraft() },
                onCancel: { store.composerPresented = false }
            )
            .frame(width: 560, height: 600)
        }
        .sheet(isPresented: $store.historyPresented) {
            HolySessionHistorySheet(store: store)
        }
        .sheet(isPresented: $store.tasksPresented) {
            HolyTaskInboxSheet(store: store)
        }
        .sheet(isPresented: $store.remoteHostsPresented) {
            HolyRemoteHostsSheet(store: store)
        }
        .onAppear(perform: focusSelectedSession)
        .onChange(of: store.selectedSessionID) { _ in focusSelectedSession() }
    }

    // MARK: - Header (thin bar: brand left, controls right)

    private var header: some View {
        HStack(spacing: 8) {
            Image("HolyGhosttyLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            Text("Holy Ghostty")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(HolyGhosttyTheme.halo)

            if !store.sessions.isEmpty {
                Text("\(store.sessions.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(HolyGhosttyTheme.bgSurface))
            }

            if conflictCount > 0 {
                HStack(spacing: 3) {
                    HolyGhosttyStatusDot(color: HolyGhosttyTheme.danger)
                    Text("\(conflictCount)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(HolyGhosttyTheme.danger)
                }
            }

            Button { store.presentComposer() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(HolyGhosttyActionButtonStyle())
            .keyboardShortcut("n", modifiers: [.command])

            Button { store.presentTasks() } label: {
                Image(systemName: "checklist")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(HolyGhosttyActionButtonStyle())
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Button { store.presentRemoteHosts() } label: {
                Image(systemName: "server.rack")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(HolyGhosttyActionButtonStyle())
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    toggleDisplayMode(.grid)
                }
            } label: {
                Image(systemName: displayMode == .grid ? "square.grid.2x2.fill" : "square.grid.2x2")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(HolyGhosttyActionButtonStyle())
            .keyboardShortcut("g", modifiers: [.command, .shift])

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    toggleDisplayMode(.diff)
                }
            } label: {
                Image(systemName: displayMode == .diff ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(HolyGhosttyActionButtonStyle())
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    toggleDisplayMode(.focus)
                }
            } label: {
                Image(systemName: displayMode == .focus ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(HolyGhosttyActionButtonStyle())
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Spacer()

            Menu {
                Section("Templates") {
                    templateSection(title: "Built-In", templates: store.builtInTemplates)

                    if !store.savedTemplates.isEmpty {
                        Divider()
                        templateSection(title: "Saved", templates: store.savedTemplates)
                    }
                }

                Divider()

                Button { store.presentTasks() } label: {
                    Label("Task Inbox", systemImage: "checklist")
                }

                Button { store.presentRemoteHosts() } label: {
                    Label("Remote Hosts", systemImage: "server.rack")
                }

                Button { store.presentHistory() } label: {
                    Label("Session History", systemImage: "clock")
                }

                if let selected = store.selectedSession {
                    Divider()
                    Button("Duplicate Session") { store.duplicate(selected) }
                    Button("Archive Session") { store.close(selected) }
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(HolyGhosttyActionButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .background(HolyGhosttyTheme.bgElevated)
    }

    // MARK: - Helpers

    @ViewBuilder
    private var workspaceContent: some View {
        switch displayMode {
        case .focus:
            HolySessionDetailView(
                session: store.selectedSession,
                coordination: store.selectedSession.map(store.coordination(for:)) ?? .empty,
                ghosttyApp: ghostty,
                focusMode: true
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(HolyGhosttyTheme.bg)
            .overlay(alignment: .topTrailing) {
                focusOverlay
                    .padding(.top, 12)
                    .padding(.trailing, 12)
            }
        case .grid:
            gridContent
        case .diff:
            diffContent
        case .standard:
            HSplitView {
                HolySessionRosterView(store: store)
                    .frame(minWidth: 220, idealWidth: 320, maxWidth: 440, maxHeight: .infinity)
                    .background(HolyGhosttyTheme.bgElevated)

                HolySessionDetailView(
                    session: store.selectedSession,
                    coordination: store.selectedSession.map(store.coordination(for:)) ?? .empty,
                    ghosttyApp: ghostty
                )
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                .background(HolyGhosttyTheme.bg)
                .layoutPriority(1)

                HolyContextPanelView(
                    session: store.selectedSession,
                    coordination: store.selectedSession.map(store.coordination(for:)) ?? .empty
                )
                .frame(minWidth: 220, idealWidth: 280, maxWidth: 360, maxHeight: .infinity)
                .background(HolyGhosttyTheme.bgElevated)
            }
        }
    }

    private var gridContent: some View {
        GeometryReader { geometry in
            let sessions = visibleGridSessions
            let columns = gridColumns(for: geometry.size.width, sessionCount: sessions.count)
            let tileHeight = gridTileHeight(
                totalHeight: geometry.size.height,
                sessionCount: sessions.count,
                columnCount: columns.count
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Grid Mode")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(HolyGhosttyTheme.halo)
                                .textCase(.uppercase)
                                .tracking(0.6)

                            Text(gridSummaryText)
                                .font(.system(size: 11))
                                .foregroundStyle(HolyGhosttyTheme.textSecondary)
                        }

                        Spacer()

                        if store.sessions.count > sessions.count {
                            Text("Showing \(sessions.count) of \(store.sessions.count)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(HolyGhosttyTheme.textTertiary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(sessions) { session in
                            HolySessionGridTile(
                                session: session,
                                coordination: store.coordination(for: session),
                                ghosttyApp: ghostty,
                                isSelected: store.selectedSessionID == session.id,
                                onSelect: { select(session) },
                                onPromote: { promote(session) }
                            )
                            .frame(height: tileHeight)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
            .scrollIndicators(.hidden)
            .background(HolyGhosttyTheme.bg)
        }
    }

    @ViewBuilder
    private var diffContent: some View {
        if let primarySession = store.selectedSession,
           let compareSession = resolvedComparisonSession(for: primarySession) {
            VStack(spacing: 0) {
                diffHeader(primary: primarySession, compare: compareSession)

                Rectangle()
                    .fill(HolyGhosttyTheme.border)
                    .frame(height: 0.5)

                HSplitView {
                    HolySessionDiffPane(
                        label: "Primary",
                        session: primarySession,
                        coordination: store.coordination(for: primarySession),
                        ghosttyApp: ghostty,
                        isPrimary: true,
                        onPromote: {}
                    )
                    .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)

                    HolySessionDiffPane(
                        label: "Compare",
                        session: compareSession,
                        coordination: store.coordination(for: compareSession),
                        ghosttyApp: ghostty,
                        isPrimary: false,
                        onPromote: { select(compareSession) }
                    )
                    .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                }

                diffComparisonStrip(primary: primarySession, compare: compareSession)
            }
            .background(HolyGhosttyTheme.bg)
        } else {
            HolyGhosttyEmptyStateView(
                title: "Diff mode needs two sessions",
                subtitle: "Create or relaunch another session to compare live work side by side.",
                symbol: "rectangle.split.2x1"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var focusOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Focus Mode")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(HolyGhosttyTheme.halo)
                .textCase(.uppercase)
                .tracking(0.6)

            Text(focusSummaryText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(HolyGhosttyTheme.textPrimary)

            if let runtimeSummary = store.selectedSession?.runtimeTelemetrySummaryText {
                Text(runtimeSummary)
                    .font(.system(size: 10))
                    .foregroundStyle(HolyGhosttyTheme.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(HolyGhosttyTheme.bgElevated.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(HolyGhosttyTheme.borderActive, lineWidth: 0.5)
        )
    }

    private func diffHeader(primary: HolySession, compare: HolySession) -> some View {
        let comparison = HolySessionDiffComparison(primary: primary, compare: compare)

        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Diff Mode")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(HolyGhosttyTheme.halo)
                    .textCase(.uppercase)
                    .tracking(0.6)

                Text("\(primary.title) vs \(compare.title)")
                    .font(.system(size: 11))
                    .foregroundStyle(HolyGhosttyTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            HolySessionDiffRiskBadge(risk: comparison.mergeRisk)

            Menu {
                ForEach(diffCandidates(for: primary)) { candidate in
                    Button(candidate.title) {
                        diffCompareSessionIDRaw = candidate.id.uuidString
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(compare.title)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
            }
            .buttonStyle(HolyGhosttyActionButtonStyle())

            Button("Swap") {
                diffCompareSessionIDRaw = primary.id.uuidString
                select(compare)
            }
            .buttonStyle(HolyGhosttyActionButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(HolyGhosttyTheme.bgElevated)
    }

    private func diffComparisonStrip(primary: HolySession, compare: HolySession) -> some View {
        let comparison = HolySessionDiffComparison(primary: primary, compare: compare)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Comparison")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(HolyGhosttyTheme.halo)
                    .textCase(.uppercase)
                    .tracking(0.6)

                Spacer()

                Text(comparison.overlapSummary)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(comparison.mergeRisk.color)
            }

            HStack(alignment: .top, spacing: 18) {
                diffMetric("Merge Risk", comparison.mergeRisk.title)
                diffMetric("Repository", comparison.repositorySummary)
                diffMetric("Worktree", comparison.worktreeSummary)
                diffMetric("Branch", comparison.branchSummary)
                diffMetric("Coordination", comparison.coordinationSummary)
                diffMetric("Primary", comparison.primaryFilesSummary)
                diffMetric("Compare", comparison.compareFilesSummary)
            }

            Text(comparison.mergeRisk.detail)
                .font(.system(size: 10))
                .foregroundStyle(HolyGhosttyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if comparison.hasFileBuckets {
                HStack(alignment: .top, spacing: 12) {
                    HolySessionDiffFileBucket(
                        title: "Overlap",
                        files: comparison.overlapFiles,
                        emptyState: "No overlapping files",
                        tint: comparison.overlapFiles.isEmpty ? HolyGhosttyTheme.textTertiary : HolyGhosttyTheme.warning
                    )

                    HolySessionDiffFileBucket(
                        title: "Primary Only",
                        files: comparison.primaryOnlyFiles,
                        emptyState: "No primary-only changes",
                        tint: HolyGhosttyTheme.accent
                    )

                    HolySessionDiffFileBucket(
                        title: "Compare Only",
                        files: comparison.compareOnlyFiles,
                        emptyState: "No compare-only changes",
                        tint: HolyGhosttyTheme.success
                    )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(HolyGhosttyTheme.bgElevated)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(HolyGhosttyTheme.border)
                .frame(height: 0.5)
        }
    }

    private func diffMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(HolyGhosttyTheme.textTertiary)
                .textCase(.uppercase)
                .tracking(0.5)

            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(HolyGhosttyTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func focusSelectedSession() {
        guard let session = store.selectedSession else { return }
        Ghostty.moveFocus(to: session.surfaceView)
    }

    private func select(_ session: HolySession) {
        store.selectedSessionID = session.id
        Ghostty.moveFocus(to: session.surfaceView)
    }

    private func promote(_ session: HolySession) {
        store.selectedSessionID = session.id
        withAnimation(.easeInOut(duration: 0.18)) {
            displayMode = .standard
        }
        Ghostty.moveFocus(to: session.surfaceView)
    }

    private var conflictCount: Int {
        store.coordinationBySessionID.values.filter(\.hasBlockingConflict).count
    }

    private var focusSummaryText: String {
        let working = store.sessions.filter { $0.phase == .working }.count
        let waiting = store.sessions.filter { $0.phase == .waitingInput }.count
        let done = store.sessions.filter { $0.phase == .completed }.count
        let failure = store.sessions.filter { $0.phase == .failed }.count

        var parts: [String] = []
        if working > 0 {
            parts.append("\(working) working")
        }
        if waiting > 0 {
            parts.append("\(waiting) waiting")
        }
        if done > 0 {
            parts.append("\(done) done")
        }
        if failure > 0 {
            parts.append("\(failure) failed")
        }

        if parts.isEmpty {
            return "\(store.sessions.count) active"
        }

        return parts.joined(separator: " · ")
    }

    private var gridSummaryText: String {
        if let selected = store.selectedSession {
            let attention = store.coordination(for: selected).attention.displayName
            return "\(store.sessions.count) sessions · selected: \(selected.title) · \(attention)"
        }

        return "\(store.sessions.count) sessions"
    }

    private func diffCandidates(for primary: HolySession) -> [HolySession] {
        orderedSessions.filter { $0.id != primary.id }
    }

    private func resolvedComparisonSession(for primary: HolySession) -> HolySession? {
        let candidates = diffCandidates(for: primary)
        guard !candidates.isEmpty else { return nil }

        if let diffCompareSessionID,
           let session = candidates.first(where: { $0.id == diffCompareSessionID }) {
            return session
        }

        return candidates.first
    }

    private var orderedSessions: [HolySession] {
        store.sessions.sorted { lhs, rhs in
            if lhs.id == store.selectedSessionID { return true }
            if rhs.id == store.selectedSessionID { return false }

            let lhsAttentionRank = attentionRank(store.coordination(for: lhs).attention)
            let rhsAttentionRank = attentionRank(store.coordination(for: rhs).attention)
            if lhsAttentionRank != rhsAttentionRank {
                return lhsAttentionRank < rhsAttentionRank
            }

            let lhsPhaseRank = phaseRank(lhs.phase)
            let rhsPhaseRank = phaseRank(rhs.phase)
            if lhsPhaseRank != rhsPhaseRank {
                return lhsPhaseRank < rhsPhaseRank
            }

            return lhs.activityAt > rhs.activityAt
        }
    }

    private var visibleGridSessions: [HolySession] {
        let limit = 4
        let sorted = orderedSessions
        guard sorted.count > limit,
              let selectedSession = store.selectedSession,
              !sorted.prefix(limit).contains(where: { $0.id == selectedSession.id }) else {
            return Array(sorted.prefix(limit))
        }

        var visible = Array(sorted.prefix(limit - 1))
        visible.append(selectedSession)
        return visible
    }

    private var displayMode: HolyWorkspaceDisplayMode {
        get { HolyWorkspaceDisplayMode(rawValue: displayModeRaw) ?? .standard }
        nonmutating set { displayModeRaw = newValue.rawValue }
    }

    private var diffCompareSessionID: UUID? {
        guard let diffCompareSessionIDRaw else { return nil }
        return UUID(uuidString: diffCompareSessionIDRaw)
    }

    private func toggleDisplayMode(_ mode: HolyWorkspaceDisplayMode) {
        displayMode = displayMode == mode ? .standard : mode
    }

    private func gridColumns(for width: CGFloat, sessionCount: Int) -> [GridItem] {
        let count = if width < 980 || sessionCount <= 1 {
            1
        } else {
            2
        }

        return Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: count)
    }

    private func gridTileHeight(totalHeight: CGFloat, sessionCount: Int, columnCount: Int) -> CGFloat {
        let rows = max(1, Int(ceil(Double(sessionCount) / Double(max(1, columnCount)))))
        let verticalChrome: CGFloat = 88
        let spacing: CGFloat = CGFloat(max(0, rows - 1)) * 12
        let available = max(260, totalHeight - verticalChrome - spacing)
        return max(260, available / CGFloat(rows))
    }

    private func attentionRank(_ attention: HolySessionAttention) -> Int {
        switch attention {
        case .failure:
            return 0
        case .conflict:
            return 1
        case .needsInput:
            return 2
        case .watch:
            return 3
        case .none:
            return 4
        case .done:
            return 5
        }
    }

    private func phaseRank(_ phase: HolySessionPhase) -> Int {
        switch phase {
        case .failed:
            return 0
        case .waitingInput:
            return 1
        case .working:
            return 2
        case .active:
            return 3
        case .completed:
            return 4
        }
    }

    @ViewBuilder
    private func templateSection(title: String, templates: [HolySessionTemplate]) -> some View {
        Section(title) {
            ForEach(templates) { template in
                Menu(template.name) {
                    Button("Launch Now") { store.launchTemplate(template) }
                    Button("Edit Before Launch") { store.presentComposer(using: template) }
                }
            }
        }
    }
}

private struct HolySessionGridTile: View {
    @ObservedObject var session: HolySession
    let coordination: HolySessionCoordination
    let ghosttyApp: Ghostty.App
    let isSelected: Bool
    let onSelect: () -> Void
    let onPromote: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            HolyGhosttySurfaceFrame(halo: isSelected) {
                Ghostty.SurfaceWrapper(surfaceView: session.surfaceView, isSplit: true)
                    .environmentObject(ghosttyApp)
                    .ghosttyLastFocusedSurface(Weak(session.surfaceView))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(HolyGhosttyTheme.bgElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? tileTint.opacity(0.35) : HolyGhosttyTheme.border, lineWidth: 0.7)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture(perform: onSelect)
        .onTapGesture(count: 2, perform: onPromote)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            HolyGhosttyStatusDot(color: tileTint)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HolyGhosttyTheme.textPrimary)
                    .lineLimit(1)

                Text(session.runtimeTelemetrySummaryText ?? session.primarySignalHeadline)
                    .font(.system(size: 10))
                    .foregroundStyle(HolyGhosttyTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Open", action: onPromote)
                .buttonStyle(HolyGhosttyActionButtonStyle())
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.bottom, 8)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            footerItem(session.statusText, color: tileTint)

            if let branch = session.gitSnapshot?.branchDisplayName {
                footerItem(branch, color: session.hasBranchOwnershipDrift ? HolyGhosttyTheme.warning : HolyGhosttyTheme.textSecondary)
            }

            if let runtimeSummary = session.runtimeTelemetrySummaryText {
                footerItem(runtimeSummary, color: runtimeColor(for: session.runtimeTelemetry.activityKind))
            }

            Spacer()
        }
        .padding(.top, 8)
    }

    private func footerItem(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
    }

    private var tileTint: Color {
        switch coordination.attention {
        case .none:
            return phaseColor(for: session.phase)
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

    private func phaseColor(for phase: HolySessionPhase) -> Color {
        switch phase {
        case .active:
            return HolyGhosttyTheme.success
        case .working:
            return HolyGhosttyTheme.accent
        case .waitingInput:
            return HolyGhosttyTheme.warning
        case .completed:
            return HolyGhosttyTheme.success
        case .failed:
            return HolyGhosttyTheme.danger
        }
    }

    private func runtimeColor(for kind: HolySessionActivityKind) -> Color {
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
}

private struct HolySessionDiffPane: View {
    let label: String
    @ObservedObject var session: HolySession
    let coordination: HolySessionCoordination
    let ghosttyApp: Ghostty.App
    let isPrimary: Bool
    let onPromote: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(HolyGhosttyTheme.halo)
                    .textCase(.uppercase)
                    .tracking(0.6)

                Spacer()

                if !isPrimary {
                    Button("Make Primary", action: onPromote)
                        .buttonStyle(HolyGhosttyActionButtonStyle())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(HolyGhosttyTheme.bgElevated)

            HolySessionDetailView(
                session: session,
                coordination: coordination,
                ghosttyApp: ghosttyApp,
                splitSurface: true
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(HolyGhosttyTheme.bg)
    }
}

@MainActor
private struct HolySessionDiffComparison {
    let primary: HolySession
    let compare: HolySession

    var primaryFiles: [String] {
        primary.gitSnapshot?.changedFiles.map(\.path) ?? []
    }

    var compareFiles: [String] {
        compare.gitSnapshot?.changedFiles.map(\.path) ?? []
    }

    var overlapFiles: [String] {
        Array(Set(primaryFiles).intersection(Set(compareFiles))).sorted()
    }

    var primaryOnlyFiles: [String] {
        Array(Set(primaryFiles).subtracting(Set(compareFiles))).sorted()
    }

    var compareOnlyFiles: [String] {
        Array(Set(compareFiles).subtracting(Set(primaryFiles))).sorted()
    }

    var repositorySummary: String {
        let primaryRepo = primary.repositoryName ?? "No repo"
        let compareRepo = compare.repositoryName ?? "No repo"
        return primaryRepo == compareRepo ? primaryRepo : "\(primaryRepo) / \(compareRepo)"
    }

    var worktreeSummary: String {
        switch (primary.ownership.worktreePath, compare.ownership.worktreePath) {
        case let (lhs?, rhs?) where lhs == rhs:
            return "Shared"
        case let (lhs?, rhs?):
            return "\(lastPath(lhs)) / \(lastPath(rhs))"
        case let (lhs?, nil):
            return "\(lastPath(lhs)) / none"
        case let (nil, rhs?):
            return "none / \(lastPath(rhs))"
        case (nil, nil):
            return "No worktree"
        }
    }

    var branchSummary: String {
        let primaryBranch = primary.observedBranchName ?? primary.branchDisplayName
        let compareBranch = compare.observedBranchName ?? compare.branchDisplayName
        return primaryBranch == compareBranch ? primaryBranch : "\(primaryBranch) / \(compareBranch)"
    }

    var overlapSummary: String {
        overlapFiles.isEmpty
            ? "No overlapping changed files"
            : overlapFiles.count == 1
                ? "1 overlapping changed file"
                : "\(overlapFiles.count) overlapping changed files"
    }

    var primaryFilesSummary: String {
        fileSummary(total: primaryFiles.count, unique: primaryOnlyFiles.count)
    }

    var compareFilesSummary: String {
        fileSummary(total: compareFiles.count, unique: compareOnlyFiles.count)
    }

    var coordinationSummary: String {
        if sharesWorktree {
            return "Shared worktree"
        }

        if !overlapFiles.isEmpty {
            return overlapSummary
        }

        if sharesBranch {
            return "Shared branch"
        }

        if primary.hasBranchOwnershipDrift || compare.hasBranchOwnershipDrift {
            return "Branch drift detected"
        }

        if hasComparableRepositories {
            return "No active overlap"
        }

        return "Limited git context"
    }

    var mergeRisk: HolySessionDiffRisk {
        if !hasComparableRepositories {
            return .limitedContext
        }

        if sharesWorktree || !overlapFiles.isEmpty || hasGitConflicts {
            return .critical
        }

        if sharesBranch || primary.hasBranchOwnershipDrift || compare.hasBranchOwnershipDrift {
            return .review
        }

        return .clear
    }

    var hasFileBuckets: Bool {
        !overlapFiles.isEmpty || !primaryOnlyFiles.isEmpty || !compareOnlyFiles.isEmpty
    }

    private var hasComparableRepositories: Bool {
        guard let primaryRepositoryRoot = normalized(primary.ownership.repositoryRoot ?? primary.gitSnapshot?.repositoryRoot),
              let compareRepositoryRoot = normalized(compare.ownership.repositoryRoot ?? compare.gitSnapshot?.repositoryRoot) else {
            return false
        }

        return primaryRepositoryRoot == compareRepositoryRoot
    }

    private var sharesWorktree: Bool {
        guard let primaryWorktreePath = normalized(primary.ownership.worktreePath),
              let compareWorktreePath = normalized(compare.ownership.worktreePath) else {
            return false
        }

        return primaryWorktreePath == compareWorktreePath
    }

    private var sharesBranch: Bool {
        guard hasComparableRepositories else { return false }

        let primaryBranch = primary.ownership.branchName ?? primary.observedBranchName
        let compareBranch = compare.ownership.branchName ?? compare.observedBranchName
        guard let primaryBranch, let compareBranch else { return false }
        return primaryBranch == compareBranch
    }

    private var hasGitConflicts: Bool {
        primary.gitSnapshot?.hasConflicts == true || compare.gitSnapshot?.hasConflicts == true
    }

    private func fileSummary(total: Int, unique: Int) -> String {
        switch (total, unique) {
        case (0, _):
            return "No changes"
        case let (total, unique) where unique == total:
            return total == 1 ? "1 file" : "\(total) files"
        default:
            return "\(total) files · \(unique) unique"
        }
    }

    private func normalized(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func lastPath(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

private enum HolySessionDiffRisk {
    case clear
    case review
    case critical
    case limitedContext

    var title: String {
        switch self {
        case .clear:
            return "Low"
        case .review:
            return "Review"
        case .critical:
            return "High"
        case .limitedContext:
            return "Limited"
        }
    }

    var detail: String {
        switch self {
        case .clear:
            return "These sessions appear to be working independently. Review diffs before merging, but there is no immediate overlap signal."
        case .review:
            return "These sessions share branch responsibility or ownership drift is present. Merge review is needed before combining their work."
        case .critical:
            return "These sessions have direct collision risk through a shared worktree, overlapping changed files, or git conflict state."
        case .limitedContext:
            return "Holy Ghostty cannot compare repository state cleanly yet because one or both sessions lack usable git context."
        }
    }

    var color: Color {
        switch self {
        case .clear:
            return HolyGhosttyTheme.success
        case .review:
            return HolyGhosttyTheme.warning
        case .critical:
            return HolyGhosttyTheme.danger
        case .limitedContext:
            return HolyGhosttyTheme.textTertiary
        }
    }
}

private struct HolySessionDiffRiskBadge: View {
    let risk: HolySessionDiffRisk

    var body: some View {
        HStack(spacing: 6) {
            HolyGhosttyStatusDot(color: risk.color)
            Text("Merge Risk: \(risk.title)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(risk.color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(risk.color.opacity(0.10))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(risk.color.opacity(0.20), lineWidth: 0.6)
        )
    }
}

private struct HolySessionDiffFileBucket: View {
    let title: String
    let files: [String]
    let emptyState: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Text(fileCountLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
            }

            if files.isEmpty {
                Text(emptyState)
                    .font(.system(size: 10))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(files.prefix(6).enumerated()), id: \.offset) { _, file in
                        Text(file)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(HolyGhosttyTheme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    if files.count > 6 {
                        Text("+\(files.count - 6) more")
                            .font(.system(size: 10))
                            .foregroundStyle(HolyGhosttyTheme.textTertiary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.14), lineWidth: 0.5)
        )
    }

    private var fileCountLabel: String {
        files.count == 1 ? "1 file" : "\(files.count) files"
    }
}
