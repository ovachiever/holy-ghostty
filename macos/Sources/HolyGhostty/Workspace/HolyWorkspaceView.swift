import SwiftUI
import GhosttyKit
#if os(macOS)
import AppKit
#endif

private enum HolyWorkspaceLayout {
    static let rosterMinWidth: CGFloat = 180
    static let rosterDefaultWidth: CGFloat = 272
    static let rosterMaxWidth: CGFloat = 560
    static let detailMinimumVisibleWidth: CGFloat = 420
    static let splitHandleWidth: CGFloat = 8
    static let titlebarControlInset: CGFloat = 42
}

private struct HolyWorkspaceSplitHandle: View {
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(HolyGhosttyTheme.border.opacity(isHovering ? 0.9 : 0.65))

            Capsule(style: .continuous)
                .fill(HolyGhosttyTheme.textTertiary.opacity(isHovering ? 0.45 : 0))
                .frame(width: 3, height: 40)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

#if os(macOS)
private struct HolyWindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        HolyWindowDragRegionView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class HolyWindowDragRegionView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
#endif

struct HolyWorkspaceRootView: View {
    @EnvironmentObject private var ghostty: Ghostty.App
    @ObservedObject var store: HolyWorkspaceStore
    @State private var diffCompareSessionIDRaw: String?
    @AppStorage("holy.workspace.rosterWidth.v3") private var rosterWidthRaw = Double(HolyWorkspaceLayout.rosterDefaultWidth)
    @State private var rosterDragStartWidth: CGFloat?

    var body: some View {
        ZStack {
            HolyGhosttyBackdrop()
            workspaceContent
            if let selectedSession = store.selectedSession {
                TerminalCommandPaletteView(
                    surfaceView: selectedSession.surfaceView,
                    isPresented: $store.commandPaletteIsShowing,
                    ghosttyConfig: ghostty.config,
                    updateViewModel: (NSApp.delegate as? AppDelegate)?.updateViewModel
                ) { action in
                    performCommandPaletteAction(action, on: selectedSession.surfaceView)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .top)
        .clipped()
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
        .onChange(of: selectedSessionObjectIdentifier) { _ in focusSelectedSession() }
    }

    // MARK: - Helpers

    @ViewBuilder
    private var workspaceContent: some View {
        GeometryReader { geometry in
            standardContent
                .frame(
                    width: max(0, geometry.size.width),
                    height: max(0, geometry.size.height)
                )
                .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var standardContent: some View {
        GeometryReader { geometry in
            let rosterWidth = clampedRosterWidth(for: geometry.size.width)

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    HolySessionRosterView(
                        store: store,
                        titlebarInset: HolyWorkspaceLayout.titlebarControlInset,
                        paneLabelsBySessionID: store.paneLabelsBySessionID,
                        onPresentRemoteHosts: { store.presentRemoteHosts() },
                        onPresentHistory: { store.presentHistory() }
                    )
                    .frame(maxHeight: .infinity)

                    leftRailViewControls
                }
                .frame(width: rosterWidth)
                .frame(maxHeight: .infinity)
                .background(HolyGhosttyTheme.bgElevated)

                HolyWorkspaceSplitHandle()
                    .frame(width: HolyWorkspaceLayout.splitHandleWidth)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                let startWidth = rosterDragStartWidth ?? rosterWidth
                                rosterDragStartWidth = startWidth
                                setRosterWidth(startWidth + value.translation.width, availableWidth: geometry.size.width)
                            }
                            .onEnded { _ in
                                rosterDragStartWidth = nil
                            }
                    )

                mainWorkspaceContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: max(0, geometry.size.width), height: max(0, geometry.size.height))
            .clipped()
        }
    }

    private var mainWorkspaceContent: some View {
        VStack(spacing: 0) {
            primaryWorkspaceContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

            bottomSessionStatusRail
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HolyGhosttyTheme.bg)
    }

    @ViewBuilder
    private var primaryWorkspaceContent: some View {
        switch store.normalizedPaneLayout.kind {
        case .single:
            singlePaneContent
        case .splitRight:
            HSplitView {
                paneView(at: 0)
                paneView(at: 1)
            }
        case .splitDown:
            VSplitView {
                paneView(at: 0)
                paneView(at: 1)
            }
        case .quad:
            VSplitView {
                HSplitView {
                    paneView(at: 0)
                    paneView(at: 1)
                }

                HSplitView {
                    paneView(at: 2)
                    paneView(at: 3)
                }
            }
        }
    }

    private var bottomSessionStatusRail: some View {
        HStack(spacing: 7) {
            if let session = store.selectedSession {
                let state = statusRailState(for: session)
                statusRailPill(
                    symbol: state.symbolName,
                    text: statusRailTitle(for: session, state: state),
                    color: state.kind.holyColor
                )

                if let detail = statusRailDetail(for: session, stateTitle: state.title) {
                    Text(detail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(HolyGhosttyTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                ForEach(Array(sessionRiskStatusItems(for: session).enumerated()), id: \.offset) { entry in
                    statusRailPill(
                        symbol: entry.element.symbol,
                        text: entry.element.text,
                        color: entry.element.color
                    )
                }
            } else {
                statusRailPill(symbol: "circle", text: "Ready", color: HolyGhosttyTheme.textTertiary)
                Spacer(minLength: 0)
            }
        }
        .frame(height: 22)
        .padding(.horizontal, 10)
        .background(HolyGhosttyTheme.bgElevated.opacity(0.96))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(HolyGhosttyTheme.border)
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private var singlePaneContent: some View {
        if let session = store.visiblePaneSessions.first ?? store.selectedSession {
            paneSurface(for: session)
        } else {
            HolyGhosttyEmptyStateView(
                title: "No session selected",
                subtitle: "Start or attach a tmux session from the left rail.",
                symbol: "terminal"
            )
        }
    }

    private var leftRailViewControls: some View {
        HStack(spacing: 0) {
            if let selected = store.selectedSession {
                Text(selected.compactStatusText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(statusColor(for: selected.phase))
                    .lineLimit(1)
                    .frame(width: 70, alignment: .leading)
                    .help(selected.activityHelpText)

                Spacer(minLength: 16)
            }

            HStack(spacing: 3) {
                layoutControlButton(
                    title: "Single",
                    systemName: "rectangle",
                    isActive: store.normalizedPaneLayout.kind == .single
                ) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        store.showSinglePane()
                    }
                }

                layoutControlButton(
                    title: "Split Right",
                    systemName: "rectangle.split.2x1",
                    isActive: store.normalizedPaneLayout.kind == .splitRight
                ) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        store.splitPaneRight()
                    }
                }

                layoutControlButton(
                    title: "Split Down",
                    systemName: "rectangle.split.2x1",
                    rotation: .degrees(90),
                    isActive: store.normalizedPaneLayout.kind == .splitDown
                ) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        store.splitPaneDown()
                    }
                }

                layoutControlButton(
                    title: "Quad",
                    systemName: "square.grid.2x2",
                    isActive: store.normalizedPaneLayout.kind == .quad
                ) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        store.showQuadPaneLayout()
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(HolyGhosttyTheme.bgElevated)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(HolyGhosttyTheme.border)
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private func paneView(at index: Int) -> some View {
        let sessions = store.visiblePaneSessions
        if index < sessions.count {
            paneSurface(for: sessions[index])
        } else {
            HolyGhosttyEmptyStateView(
                title: "Empty pane",
                subtitle: "Select another session or start a new tmux session.",
                symbol: "rectangle.dashed"
            )
        }
    }

    private func paneSurface(for session: HolySession) -> some View {
        HolySessionDetailView(
            session: session,
            coordination: store.coordination(for: session),
            ghosttyApp: ghostty,
            showsSessionHeader: false,
            splitSurface: store.normalizedPaneLayout.kind != .single
        )
        .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
        .background(HolyGhosttyTheme.bg)
        .layoutPriority(1)
    }

    private func layoutControlButton(
        title: String,
        systemName: String,
        rotation: Angle = .zero,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .medium))
                .symbolVariant(isActive ? .fill : .none)
                .rotationEffect(rotation)
                .frame(width: 24, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isActive ? HolyGhosttyTheme.halo.opacity(0.14) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? HolyGhosttyTheme.halo : HolyGhosttyTheme.textSecondary)
        .help(title)
    }

    private var standardSessionDetail: some View {
        HolySessionDetailView(
            session: store.selectedSession,
            coordination: store.selectedSession.map(store.coordination(for:)) ?? .empty,
            ghosttyApp: ghostty,
            showsSessionHeader: false
        )
        .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
        .background(HolyGhosttyTheme.bg)
        .layoutPriority(1)
    }

    private var standardContextPanel: some View {
        HolyContextPanelView(
            session: store.selectedSession,
            coordination: store.selectedSession.map(store.coordination(for:)) ?? .empty,
            store: store
        )
        .frame(minWidth: 220, idealWidth: 280, maxWidth: 360, maxHeight: .infinity)
        .background(HolyGhosttyTheme.bgElevated)
    }

    private func clampedRosterWidth(for availableWidth: CGFloat) -> CGFloat {
        clampedRosterWidth(CGFloat(rosterWidthRaw), availableWidth: availableWidth)
    }

    private func clampedRosterWidth(_ proposedWidth: CGFloat, availableWidth: CGFloat) -> CGFloat {
        let windowConstrainedMax = max(
            HolyWorkspaceLayout.rosterMinWidth,
            availableWidth - HolyWorkspaceLayout.detailMinimumVisibleWidth
        )
        let maxWidth = min(HolyWorkspaceLayout.rosterMaxWidth, windowConstrainedMax)
        return min(max(proposedWidth, HolyWorkspaceLayout.rosterMinWidth), maxWidth)
    }

    private func setRosterWidth(_ proposedWidth: CGFloat, availableWidth: CGFloat) {
        rosterWidthRaw = Double(clampedRosterWidth(proposedWidth, availableWidth: availableWidth))
    }

    private var gridContent: some View {
        // Dormant: preserved for a later explicit agent/worktree comparison pass.
        // Level 1 uses direct terminal pane layouts instead of these old view modes.
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

    private var selectedSessionObjectIdentifier: ObjectIdentifier? {
        store.selectedSession.map(ObjectIdentifier.init)
    }

    private func focusSelectedSession() {
        guard let session = store.selectedSession else { return }
        Ghostty.moveFocus(to: session.surfaceView)
    }

    private func performCommandPaletteAction(_ action: String, on surfaceView: Ghostty.SurfaceView) {
        guard let surface = surfaceView.surface else { return }
        if !ghostty_surface_binding_action(surface, action, UInt(action.lengthOfBytes(using: .utf8))) {
            AppDelegate.logger.warning("action failed action=\(action)")
        }
    }

    private func select(_ session: HolySession) {
        store.selectSession(session.id)
        Ghostty.moveFocus(to: session.surfaceView)
    }

    private func promote(_ session: HolySession) {
        store.selectSession(session.id)
        Ghostty.moveFocus(to: session.surfaceView)
    }

    private func statusColor(for phase: HolySessionPhase) -> Color {
        guard let selected = store.selectedSession else { return HolyGhosttyTheme.textTertiary }

        switch phase {
        case .active:
            return HolyGhosttyTheme.textTertiary
        case .working:
            return statusRailState(for: selected).kind.holyColor
        case .waitingInput:
            return statusRailState(for: selected).kind.holyColor
        case .completed:
            return HolyAgentPalette.done
        case .failed:
            return HolyGhosttyTheme.danger
        }
    }

    private func statusRailState(for session: HolySession) -> HolySessionAttentionPresentation {
        store.attentionPresentation(for: session)
    }

    private func statusRailTitle(
        for session: HolySession,
        state: HolySessionAttentionPresentation
    ) -> String {
        switch state.kind {
        case .approvalNeeded, .planningQuestion, .newReply, .waitingQuiet, .sleepingReply, .dormantReply, .overdueReply, .staleReply:
            return "\(state.title) \(elapsedText(since: state.becameAvailableAt ?? session.activityAt))"
        default:
            return state.title
        }
    }

    private func statusRailDetail(for session: HolySession, stateTitle: String) -> String? {
        let telemetry = session.runtimeTelemetry
        let values: [String?]

        switch telemetry.activityKind {
        case .planningQuestion, .approval:
            values = [telemetry.detail, telemetry.nextStepHint, telemetry.headline]
        case .stalled, .looping, .failure:
            values = [telemetry.detail, telemetry.headline, telemetry.nextStepHint]
        case .swarming, .reading, .editing, .command, .progress:
            values = [telemetry.headline, telemetry.detail, telemetry.command, telemetry.filePath]
        case .completion:
            values = [telemetry.headline, telemetry.artifactSummary, telemetry.artifactPath]
        case .idle:
            values = [session.missionDisplay == "No mission defined" ? nil : session.missionDisplay]
        }

        return firstRailText(values, excluding: [stateTitle, session.compactStatusText])
    }

    private func sessionRiskStatusItems(
        for session: HolySession
    ) -> [(symbol: String, text: String, color: Color)] {
        let coordination = store.coordination(for: session)
        var items: [(symbol: String, text: String, color: Color)] = []

        if !coordination.overlappingFiles.isEmpty {
            items.append((
                "exclamationmark.triangle.fill",
                pluralized(count: coordination.overlappingFiles.count, singular: "overlapping file"),
                HolyGhosttyTheme.danger
            ))
        }

        if !coordination.sharedWorktreeSessionIDs.isEmpty {
            items.append((
                "link",
                "Same worktree with \(pluralized(count: coordination.sharedWorktreeSessionIDs.count, singular: "session"))",
                HolyGhosttyTheme.textSecondary
            ))
        }

        if coordination.hasSharedBranch {
            items.append((
                "arrow.triangle.branch",
                "Same branch with \(pluralized(count: coordination.sharedBranchSessionIDs.count, singular: "session"))",
                HolyGhosttyTheme.textSecondary
            ))
        }

        if session.hasBranchOwnershipDrift {
            items.append((
                "arrow.triangle.2.circlepath",
                "Branch drift",
                HolyGhosttyTheme.warning
            ))
        }

        return items
    }

    private func statusRailPill(symbol: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 12, height: 12)

            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(HolyGhosttyTheme.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(0.10))
        )
    }

    private func approvalLooksExplicit(for session: HolySession) -> Bool {
        guard session.runtimeTelemetry.activityKind == .approval else { return false }

        let evidence = [
            session.runtimeTelemetry.headline,
            session.runtimeTelemetry.detail,
            session.runtimeTelemetry.nextStepHint,
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: "\n")

        return [
            "approval",
            "approve",
            "confirm",
            "allow",
            "permission",
            "continue?",
            "[y/n]",
            "(y/n)",
        ].contains { evidence.contains($0) }
    }

    private func firstRailText(_ values: [String?], excluding excluded: [String] = []) -> String? {
        let excludedValues = Set(excluded.compactMap { normalizedRailText($0)?.lowercased() })

        for value in values {
            guard let text = normalizedRailText(value) else { continue }
            guard !excludedValues.contains(text.lowercased()) else { continue }
            return text
        }

        return nil
    }

    private func normalizedRailText(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func elapsedText(since date: Date) -> String {
        let seconds = max(0, Int(Date.now.timeIntervalSince(date)))
        if seconds < 60 { return "now" }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3_600)h" }
        return "\(seconds / 86_400)d"
    }

    private func pluralized(count: Int, singular: String) -> String {
        count == 1 ? "1 \(singular)" : "\(count) \(singular)s"
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
            return "\(store.sessions.count) sessions · selected: \(selected.title)"
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
        store.sessions
    }

    private var visibleGridSessions: [HolySession] {
        let limit = 4
        let sorted = orderedSessions
        return Array(sorted.prefix(limit))
    }

    private var diffCompareSessionID: UUID? {
        guard let diffCompareSessionIDRaw else { return nil }
        return UUID(uuidString: diffCompareSessionIDRaw)
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
                    .id(ObjectIdentifier(session))
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
                Text(session.displayLineTitle)
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
        case .planningQuestion:
            return HolyAgentPalette.planningQuestion
        case .stalled, .looping:
            return HolyGhosttyTheme.warning
        case .failure:
            return HolyGhosttyTheme.danger
        case .completion:
            return HolyGhosttyTheme.success
        case .swarming:
            return HolyAgentPalette.swarmGold
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
                showsSessionHeader: false,
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
