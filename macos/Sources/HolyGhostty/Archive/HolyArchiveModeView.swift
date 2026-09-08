import AppKit
import SwiftUI

private typealias Palette = HolyMannaBoardPalette
private typealias Metrics = HolyMannaBoardMetrics
private typealias Present = HolyArchivePresentation
private typealias Board = HolyMannaBoardPresentation

/// index.js SPIN, one frame every 120 ms.
private let spinnerFrames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
private let spinnerInterval: TimeInterval = 0.12

/// Archive mode: the agent-sessions browser, native, in the board cockpit's
/// dress. What it does follows the TUI (agent_sessions/app.py); how it looks
/// follows the board, so Holy's two faces read as one design.
struct HolyArchiveModeView: View {
    @ObservedObject var store: HolyArchiveModeStore
    let onDismiss: () -> Void

    @AppStorage("holy.archive.inspectorWidth.v1") private var storedInspectorWidth = Double(HolyArchiveMetrics.inspectorDefaultWidth)
    @AppStorage("holy.archive.columns.v1") private var columnOverridesJSON = ""
    @FocusState private var searchFocused: Bool
    @FocusState private var researchFocused: Bool
    @FocusState private var findFocused: Bool
    @State private var columnDragPreview: HolyLedgerColumnDragSnapshot?
    @State private var inspectorDragSession: HolyLedgerInspectorDragSession?
    @State private var resizerHovered = false
    @State private var compactInspectorPresented = false
    @State private var hoveredRowID: String?
    @State private var copiedLabel: String?
    @State private var copiedResetTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let showsInlineInspector = HolyLedgerResponsiveLayout.showsInlineInspector(windowWidth: width)
                && !store.chatIsFullscreen
            let showsCompactToggle = !HolyLedgerResponsiveLayout.showsInlineInspector(windowWidth: width)
                && !store.chatIsFullscreen
            let inspectorWidth = inspectorWidth(width)
            VStack(spacing: 0) {
                topbar(
                    width: width,
                    inspectorWidth: inspectorWidth,
                    showsInspector: showsInlineInspector,
                    showsCompactToggle: showsCompactToggle
                )
                ZStack(alignment: .trailing) {
                    HStack(spacing: 0) {
                        sheetColumn(windowWidth: width)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if showsInlineInspector {
                            resizer(currentWidth: inspectorWidth, windowWidth: width)
                            inspector
                                .frame(width: inspectorWidth)
                                .frame(maxHeight: .infinity)
                                .background(Palette.surface)
                        }
                    }
                    if showsCompactToggle, compactInspectorPresented {
                        inspector
                            .frame(width: HolyLedgerResponsiveLayout.compactInspectorWidth(
                                windowWidth: width,
                                pagePadding: pagePadding(width)
                            ))
                            .frame(maxHeight: .infinity)
                            .background(Palette.surface)
                            .overlay(alignment: .leading) {
                                Rectangle().fill(Palette.line).frame(width: 1)
                            }
                            .transition(.move(edge: .trailing))
                    }
                }
                .padding(.horizontal, pagePadding(width))
                strip(width: width)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg)
        .font(mono())
        .foregroundStyle(Palette.text)
        .onChange(of: store.searchFocusNonce) { _ in searchFocused = true }
        .onChange(of: store.researchFocusNonce) { _ in researchFocused = true }
        .onChange(of: store.annotationMode) { mode in
            if mode != nil { searchFocused = true }
        }
        .onChange(of: store.transcriptFindIsPresented) { presented in
            if presented { findFocused = true }
        }
    }

    // MARK: - Layout arithmetic

    /// The page centers its cockpit at 1440px; Holy fills the pane column
    /// edge to edge, like the terminal it stands in for (Erik, 2026-09-02).
    private func pagePadding(_ width: CGFloat) -> CGFloat {
        Metrics.s4
    }

    private func inspectorWidth(_ width: CGFloat) -> CGFloat {
        if let inspectorDragSession {
            return inspectorDragSession.currentWidth
        }
        return HolyLedgerResponsiveLayout.inspectorWidth(
            windowWidth: width,
            persistedWidth: CGFloat(storedInspectorWidth)
        )
    }

    private func mono(_ size: CGFloat = Metrics.bodySize, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: - Topbar

    private func topbar(
        width: CGFloat,
        inspectorWidth: CGFloat,
        showsInspector: Bool,
        showsCompactToggle: Bool
    ) -> some View {
        HStack(spacing: Metrics.s4) {
            HStack(spacing: 0) {
                linkButton("‹ terminal") { onDismiss() }
                    .help("Return to the terminal (Escape)")
                separator("›")
                Text("archive")
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.text)
            }
            .foregroundStyle(Palette.muted)
            .lineLimit(1)
            .fixedSize()
            tabs.fixedSize()
            searchField
            Spacer(minLength: 0)
            HStack(spacing: Metrics.s2) {
                if showsCompactToggle {
                    Button {
                        compactInspectorPresented.toggle()
                    } label: {
                        Text(compactInspectorPresented ? "[list]" : "[detail]")
                            .foregroundStyle(Palette.blue)
                    }
                    .buttonStyle(.plain)
                    .help(compactInspectorPresented ? "close detail" : "show detail")
                }
                topbarRight
            }
            .frame(width: showsInspector ? inspectorWidth : nil, alignment: .trailing)
            .padding(.leading, showsInspector ? Metrics.s4 : 0)
        }
        .padding(.horizontal, pagePadding(width))
        .frame(height: Metrics.topbarHeight)
        .padding(.top, Metrics.titlebarInset)
        .background(Palette.surface)
        .overlay(alignment: .bottom) { rule }
    }

    /// sessions | research — the TUI's `?` opens the researcher; here it is
    /// also a tab beside the crumb.
    private var tabs: some View {
        HStack(spacing: 0) {
            tab("sessions", active: !store.chatIsPresented) {
                if store.chatIsPresented { store.toggleChat() }
            }
            tab("research", active: store.chatIsPresented) {
                store.showOrFocusChat()
            }
        }
    }

    private func tab(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .foregroundStyle(active ? Palette.text : Palette.muted)
                .padding(.horizontal, Metrics.s3)
                .frame(height: Metrics.topbarHeight)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(active ? Palette.text : Color.clear).frame(height: 2)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The search bar doubles as the annotation input, as the TUI's does:
    /// Ctrl+T / Ctrl+N swap its placeholder and its submit.
    private var searchField: some View {
        let annotating = store.annotationMode != nil
        let placeholder = store.annotationMode?.placeholder
            ?? "search · / · harness: project: after: before: #tag:"
        return TextField(placeholder, text: annotating ? $store.annotationDraft : $store.query)
            .textFieldStyle(.plain)
            .focused($searchFocused)
            .onSubmit {
                if annotating { store.saveAnnotation() } else { store.performSearch() }
            }
            .padding(.horizontal, Metrics.s2)
            .frame(
                minWidth: Metrics.grepFieldWidth / 2,
                idealWidth: Metrics.grepFieldWidth,
                maxWidth: Metrics.grepFieldWidth,
                minHeight: Metrics.grepFieldHeight,
                maxHeight: Metrics.grepFieldHeight
            )
            .background(Palette.surface)
            .overlay(Rectangle().stroke(
                annotating ? Palette.amber : (searchFocused ? Palette.blue : Palette.line),
                lineWidth: 1
            ))
            .padding(.leading, Metrics.s6 - Metrics.s4)
    }

    /// N sessions | ● indexed | reindex ▾ — the mark spins while the archive
    /// is being read.
    private var topbarRight: some View {
        HStack(spacing: Metrics.s1) {
            Text("\(store.totalParentCount) sessions")
            separator("|")
            if store.isIndexing {
                spinner
                Text("indexing")
            } else {
                Text("●").foregroundStyle(Palette.green)
                Text("indexed")
            }
            separator("|")
            Menu {
                Button("incremental update") { store.incrementalIndex() }
                Button("full reindex") { store.fullReindex() }
                Button("generate missing embeddings") { store.generateMissingEmbeddings() }
            } label: {
                Text("reindex ▾").foregroundStyle(store.isIndexing ? Palette.faint : Palette.blue)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(store.isIndexing)
        }
        .foregroundStyle(Palette.muted)
        .lineLimit(1)
    }

    private var spinner: some View {
        TimelineView(.periodic(from: .now, by: spinnerInterval)) { timeline in
            let frame = Int(timeline.date.timeIntervalSinceReferenceDate / spinnerInterval) % spinnerFrames.count
            Text(spinnerFrames[frame]).foregroundStyle(Palette.green)
        }
    }

    // MARK: - Sheet column

    @ViewBuilder
    private func sheetColumn(windowWidth: CGFloat) -> some View {
        if store.chatIsPresented {
            researchSheet
        } else {
            sessionsSheet(windowWidth: windowWidth)
        }
    }

    private func sessionsSheet(windowWidth: CGFloat) -> some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                chips
                sessionList(
                    availableWidth: max(0, geometry.size.width - Metrics.s4),
                    windowWidth: windowWidth
                )
                    .frame(maxHeight: .infinity)
                rule
                childrenPane
                    .frame(height: store.children.isEmpty
                        ? nil
                        : geometry.size.height * HolyArchiveMetrics.childPaneFraction)
            }
            .padding(.trailing, Metrics.s4)
        }
    }

    /// app.py filter bar: `[●All] [○🧠Claude Code] …`, hidden with a single
    /// provider; the sort chip appears in search mode (`s` cycles it).
    private var chips: some View {
        HStack(spacing: Metrics.s2) {
            if store.availableHarnesses.count > 1 {
                filterChip("all", harness: nil)
                ForEach(store.availableHarnesses) { harness in
                    filterChip(harness.displayName.lowercased(), harness: harness)
                }
            }
            if store.isSearchActive {
                Button { store.cycleSort() } label: {
                    chipLabel("\(store.sort.label) ▾", active: true, dot: nil)
                }
                .buttonStyle(.plain)
                .help("cycle the sort (s)")
            }
            Spacer(minLength: 0)
        }
        .padding(.top, Metrics.s2)
        .padding(.bottom, Metrics.s1)
    }

    private func filterChip(_ label: String, harness: HolyArchiveHarness?) -> some View {
        let active = store.providerFilter == harness
        let color = harness.map { Palette.wordColor(forClass: Present.colorClass(for: $0)) } ?? Palette.text
        return Button {
            store.setProviderFilter(harness)
        } label: {
            chipLabel(label, active: active, dot: active ? color : Palette.faint)
        }
        .buttonStyle(.plain)
        .help("filter by harness (f cycles)")
    }

    private func chipLabel(_ text: String, active: Bool, dot: Color?) -> some View {
        HStack(spacing: Metrics.s1) {
            if let dot {
                Text(active ? "●" : "○").foregroundStyle(dot)
            }
            Text(text).foregroundStyle(active ? Palette.text : Palette.muted)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: Metrics.chipRadius, style: .continuous)
                .fill(active ? Palette.raised : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.chipRadius, style: .continuous)
                .stroke(active ? Palette.lineStrong : Palette.line, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func sessionList(availableWidth: CGFloat, windowWidth: CGFloat) -> some View {
        let head = Present.listHead(
            query: store.query,
            filter: store.providerFilter,
            shown: store.sessions.count,
            total: store.isSearchActive ? store.sessions.count : store.totalParentCount,
            sort: store.sort,
            matchingChildren: store.matchingChildCount
        )
        let showsProject = HolyLedgerResponsiveLayout.showsSecondaryColumn(windowWidth: windowWidth)
        let fitted = Present.columns(for: store.sessions, childCounts: store.childCountsByParentID)
        let overrides = HolyLedgerColumnOverrides(json: columnOverridesJSON)
        let fixedColumns = [
            HolyLedgerFixedColumn(
                id: "date",
                fittedWidth: fitted.date,
                minimumWidth: fitted.date
            ),
            HolyLedgerFixedColumn(
                id: "harness",
                fittedWidth: fitted.harness,
                minimumWidth: fitted.harness
            ),
            showsProject ? HolyLedgerFixedColumn(
                id: "project",
                fittedWidth: fitted.project,
                minimumWidth: Metrics.columnWidth(
                    contentCharacters: HolyLedgerColumnGrip.minimumCharacters,
                    headerCharacters: "project".count
                )
            ) : nil,
            HolyLedgerFixedColumn(
                id: "sub",
                fittedWidth: fitted.children,
                minimumWidth: fitted.children
            ),
        ].compactMap { $0 }
        let columns = HolyLedgerResponsiveLayout.columns(
            availableWidth: columnDragPreview?.availableWidth ?? availableWidth,
            gap: Metrics.columnGap,
            stripeWidth: Metrics.stripeColumnWidth,
            minimumFlexibleWidth: Metrics.columnWidth(
                contentCharacters: Metrics.digestFloorCharacters,
                headerCharacters: "summary".count
            ),
            fixedColumns: fixedColumns,
            overrides: overrides,
            transientWidths: columnDragPreview?.widths,
            transientFlexibleWidth: columnDragPreview?.widths["summary"]
        )
        let columnOrder = HolyLedgerColumnBoundaries.archiveOrder(showsProject: showsProject)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Metrics.columnGap) {
                Color.clear.frame(width: Metrics.stripeColumnWidth)
                resizableHeader(
                    "date",
                    columns: columns,
                    boundary: HolyLedgerColumnBoundaries.archive(column: "date", showsProject: showsProject),
                    columnOrder: columnOrder
                )
                resizableHeader(
                    "source",
                    columnID: "harness",
                    columns: columns,
                    boundary: HolyLedgerColumnBoundaries.archive(column: "harness", showsProject: showsProject),
                    columnOrder: columnOrder
                )
                if showsProject {
                    resizableHeader(
                        "project",
                        columns: columns,
                        boundary: HolyLedgerColumnBoundaries.archive(column: "project", showsProject: showsProject),
                        columnOrder: columnOrder
                    )
                }
                columnLabel("summary").frame(width: columns.flexibleWidth, alignment: .leading)
                resizableHeader(
                    "sub",
                    columns: columns,
                    boundary: HolyLedgerColumnBoundaries.archive(column: "sub", showsProject: showsProject),
                    columnOrder: columnOrder,
                    alignment: .trailing
                )
            }
            .frame(height: Metrics.columnHeaderHeight)
            .overlay(alignment: .bottom) { rule }
            .task(id: columns.discardedStoredWidths ? columnOverridesJSON : "") {
                if columnDragPreview == nil, columns.discardedStoredWidths {
                    columnOverridesJSON = ""
                }
            }
            sheetHead(head.prompt, count: head.count) {
                if store.isSearching { spinner }
            }
            if store.sessions.isEmpty {
                if store.isLoading {
                    buildingLine("loading indexed sessions…")
                } else if store.isSearchActive {
                    emptyLine("no sessions matched")
                } else {
                    emptyState
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(store.sessions.enumerated()), id: \.element.id) { index, session in
                                sessionRow(
                                    session,
                                    index: index,
                                    columns: columns,
                                    showsProject: showsProject
                                )
                                    .id(session.id)
                            }
                        }
                    }
                    .onChange(of: store.selectedSessionID) { id in
                        if let id { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
    }

    /// widgets.py ParentSessionItem: date · icon · project[:12] · (n) · description.
    private func sessionRow(
        _ session: HolyArchiveSession,
        index: Int,
        columns: HolyLedgerResolvedColumns,
        showsProject: Bool
    ) -> some View {
        let selected = store.selectedSessionID == session.id && store.selectedChildID == nil
        let row = Present.rowText(for: session)
        let cls = Present.colorClass(for: session.harness)
        let children = store.childCountsByParentID[session.id] ?? 0
        return HStack(alignment: .center, spacing: Metrics.columnGap) {
            stripe(cls)
            Text(Present.dateStamp(session.activityAt))
                .foregroundStyle(Palette.faint)
                .lineLimit(1)
                .frame(width: columns.width("date"), alignment: .leading)
            Text(Present.sourceLabel(for: session))
                .foregroundStyle(Palette.wordColor(forClass: cls))
                .lineLimit(1)
                .frame(width: columns.width("harness"), alignment: .leading)
            if showsProject {
                Text(Present.projectLabel(session))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: columns.width("project"), alignment: .leading)
                    .help(session.projectPath ?? session.projectName)
            }
            Text(row.text)
                .foregroundStyle(row.isFallback ? Palette.muted : Palette.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: columns.flexibleWidth, alignment: .leading)
            Text(Present.childCountText(children))
                .foregroundStyle(children > 0 ? Palette.amber : Palette.faint)
                .lineLimit(1)
                .frame(width: columns.width("sub"), alignment: .trailing)
        }
        .frame(minHeight: Metrics.rowHeight)
        .background(rowBackground(selected: selected, hovered: hoveredRowID == session.id, even: index % 2 == 1))
        .overlay(alignment: .leading) {
            if selected { Rectangle().fill(Palette.select).frame(width: Metrics.selectionEdgeWidth) }
        }
        .contentShape(Rectangle())
        .onTapGesture { store.selectParent(session.id) }
        .onHover { hovering in setHover(session.id, hovering) }
        .contextMenu {
            Button("copy resume command") {
                store.selectParent(session.id)
                store.copyResumeCommand()
            }
            .disabled(session.isRemoteArchiveSession)
            Button("resume in roster") {
                store.selectParent(session.id)
                store.resumeSelected()
            }
            Button("open transcript") {
                store.selectParent(session.id)
                store.showTranscript()
            }
        }
    }

    /// widgets.py SubagentSessionItem: ★ · child_type · first prompt.
    private var childrenPane: some View {
        let head = Present.childrenHead(searching: store.isSearchActive, count: store.children.count)
        let columns = Present.childColumns(for: store.children)
        return VStack(alignment: .leading, spacing: 0) {
            sheetHead(head.prompt, count: head.count) {
                if store.children.isEmpty {
                    Text("explicit lineage only").foregroundStyle(Palette.faint)
                }
            }
            if store.children.isEmpty {
                emptyLine("no explicit child sessions")
            } else {
                HStack(spacing: Metrics.columnGap) {
                    Color.clear.frame(width: Metrics.stripeColumnWidth)
                    columnLabel("type").frame(width: columns.type, alignment: .leading)
                    columnLabel("first prompt").frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: Metrics.columnHeaderHeight)
                .overlay(alignment: .bottom) { rule }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(store.children.enumerated()), id: \.element.id) { index, child in
                            childRow(child, index: index, columns: columns)
                        }
                    }
                }
            }
        }
    }

    private func childRow(_ child: HolyArchiveSession, index: Int, columns: HolyArchiveChildColumnWidths) -> some View {
        let selected = store.selectedChildID == child.id
        let highlighted = child.extra["selected"] == "true"
        return HStack(alignment: .center, spacing: Metrics.columnGap) {
            stripe(highlighted ? "decision" : Present.colorClass(for: child.harness))
            Text(child.childType ?? "sub-agent")
                .foregroundStyle(Palette.blue)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: columns.type, alignment: .leading)
            Text(Present.flatten(HolyArchiveText.firstRealLine(in: child.firstPrompt) ?? "(no prompt)"))
                .foregroundStyle(Palette.text)
                .lineLimit(2)
                .padding(.vertical, Metrics.s1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: Metrics.rowHeight)
        .background(rowBackground(selected: selected, hovered: hoveredRowID == child.id, even: index % 2 == 1))
        .overlay(alignment: .leading) {
            if selected { Rectangle().fill(Palette.select).frame(width: Metrics.selectionEdgeWidth) }
        }
        .contentShape(Rectangle())
        .onTapGesture { store.selectChild(child.id) }
        .onHover { hovering in setHover(child.id, hovering) }
    }

    /// app.py: "No sessions found!" plus every checked provider's directory.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Metrics.s1) {
            emptyLine("no sessions found")
            ForEach(store.registry.providers, id: \.harness) { provider in
                HStack(spacing: Metrics.columnGap) {
                    stripe(Present.colorClass(for: provider.harness))
                    Text(Present.shortLabel(for: provider.harness))
                        .foregroundStyle(Palette.wordColor(forClass: Present.colorClass(for: provider.harness)))
                    Text(provider.sessionsDirectory.path)
                        .foregroundStyle(Palette.faint)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(provider.isAvailable ? "present" : "absent")
                        .foregroundStyle(provider.isAvailable ? Palette.green : Palette.faint)
                }
                .frame(minHeight: Metrics.rowHeight)
            }
        }
    }

    // MARK: - Research sheet

    private var researchSheet: some View {
        VStack(spacing: 0) {
            sheetHead("agent-sessions chat", count: store.selectedChatID == nil ? "new" : "") {
                if store.isResearching {
                    spinner
                    Text("thinking…").foregroundStyle(Palette.faint)
                }
                Spacer(minLength: 0)
                HolyMannaFlowLayout(spacing: Metrics.s3) {
                    linkButton("[copy]") { store.copyResearchTranscript() }
                    linkButton("[new]") { store.newChat() }
                    linkButton("[recent]") {
                        store.refreshRecentChats()
                        store.chatHistoryIsPresented.toggle()
                    }
                    Button { store.deleteSelectedChat() } label: {
                        Text("[delete]").foregroundStyle(store.selectedChatID == nil ? Palette.faint : Palette.red)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.selectedChatID == nil)
                    linkButton(store.chatIsFullscreen ? "[windowed]" : "[fullscreen]") {
                        store.chatIsFullscreen.toggle()
                    }
                }
            }
            if store.chatHistoryIsPresented {
                chatHistory
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if store.researchMessages.isEmpty {
                            VStack(alignment: .leading, spacing: Metrics.s2) {
                                Text("ask across the archive").foregroundStyle(Palette.text)
                                Text("The researcher can scope projects and tags, search content, read full messages, follow pagination, and return exact citations with resume commands.")
                                    .foregroundStyle(Palette.muted)
                                    .lineSpacing(Metrics.bodySize * (Metrics.bodyLineHeight - 1))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, Metrics.s3)
                        }
                        ForEach(store.researchMessages) { message in
                            HolyArchiveResearchMessageView(message: message, onCitation: store.openCitation)
                                .id(message.id)
                        }
                    }
                }
                .onChange(of: store.researchMessages.count) { _ in
                    if let id = store.researchMessages.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            HStack(spacing: Metrics.s3) {
                Text("model").foregroundStyle(Palette.muted)
                TextField("model", text: $store.researchModel)
                    .textFieldStyle(.plain)
                    .frame(width: Metrics.columnWidth(contentCharacters: 24, headerCharacters: 5))
                    .onChange(of: store.researchModel) { UserDefaults.standard.set($0, forKey: "holy.intelligence.deep.model") }
                Text("effort").foregroundStyle(Palette.muted)
                Picker("", selection: $store.reasoningEffort) {
                    ForEach(["low", "medium", "high", "xhigh"], id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .onChange(of: store.reasoningEffort) { UserDefaults.standard.set($0, forKey: "holy.archive.research.effort") }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Metrics.s2)
            .overlay(alignment: .top) { rule }
            HStack(spacing: Metrics.s2) {
                TextField("ask the archive researcher", text: $store.researchDraft)
                    .textFieldStyle(.plain)
                    .focused($researchFocused)
                    .onSubmit { store.submitResearch() }
                    .disabled(store.isResearching)
                    .padding(.horizontal, Metrics.s2)
                    .frame(height: Metrics.grepFieldHeight)
                    .background(Palette.surface)
                    .overlay(Rectangle().stroke(researchFocused ? Palette.blue : Palette.line, lineWidth: 1))
                Button {
                    store.submitResearch()
                } label: {
                    Text("[send]").foregroundStyle(
                        store.isResearching || store.researchDraft.holyArchiveNilIfBlank == nil ? Palette.faint : Palette.green
                    )
                }
                .buttonStyle(.plain)
                .disabled(store.isResearching || store.researchDraft.holyArchiveNilIfBlank == nil)
            }
            .padding(.vertical, Metrics.s2)
        }
        .padding(.trailing, Metrics.s4)
    }

    private var chatHistory: some View {
        VStack(spacing: 0) {
            ForEach(Array(store.recentChats.enumerated()), id: \.element.id) { index, chat in
                HStack(spacing: Metrics.columnGap) {
                    stripe(store.selectedChatID == chat.id ? "active" : "muted")
                    Text(chat.title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Text(Present.dateStamp(chat.updatedAt)).foregroundStyle(Palette.faint)
                }
                .frame(minHeight: Metrics.rowHeight)
                .background(rowBackground(selected: store.selectedChatID == chat.id, hovered: false, even: index % 2 == 1))
                .contentShape(Rectangle())
                .onTapGesture { store.loadChat(chat.id) }
            }
        }
        .overlay(alignment: .bottom) { rule }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        if store.transcriptIsPresented {
            transcriptView
        } else if let session = store.selectedSession {
            inspectorScroll { sessionDetail(session) }
        } else {
            emptyLine("select a session").padding(Metrics.s4)
        }
    }

    private func inspectorScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let body = content()
        return GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Metrics.s3) {
                    body
                }
                .padding(Metrics.s4)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .topLeading)
            }
        }
    }

    /// widgets.py SessionDetailPanel.show_session, section by section.
    @ViewBuilder
    private func sessionDetail(_ session: HolyArchiveSession) -> some View {
        let cls = Present.colorClass(for: session.harness)
        let childCount = session.isChild ? 0 : store.childCountForSelectedParent
        HStack(spacing: Metrics.s2) {
            pill(session.harness.displayName, color: Palette.wordColor(forClass: cls))
            Text(Present.typeLine(for: session, childCount: childCount)).foregroundStyle(Palette.muted)
        }
        .lineLimit(1)

        Text(Present.rowText(for: session).text)
            .font(mono(Metrics.headingSize, weight: .semibold))
            .lineSpacing(Metrics.headingSize * 0.4)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)

        Grid(alignment: .topLeading, horizontalSpacing: Metrics.s2, verticalSpacing: Metrics.s1) {
            metaRow("harness") {
                Text(session.harness.displayName).fontWeight(.medium).foregroundStyle(Palette.wordColor(forClass: cls))
            }
            metaRow("host") { metaValue(Present.sourceDetail(for: session)) }
            metaRow("type") { metaValue(Present.typeLine(for: session, childCount: childCount)) }
            metaRow("title") { metaValue(Present.detailTitle(for: session)) }
            metaRow("path") { metaValue(session.projectPath ?? "Unknown") }
            metaRow("date") { metaValue(Present.longDate(session.modifiedAt)) }
            metaRow("model") {
                Text(session.model ?? "Unknown").fontWeight(.medium).foregroundStyle(Palette.amber)
            }
            metaRow("session id") { metaValue(session.providerSessionID) }
            let tags = store.annotations.filter { $0.kind == .tag }
            if !tags.isEmpty {
                metaRow("tags") {
                    HolyMannaFlowLayout(spacing: Metrics.s2) {
                        ForEach(tags) { tag in
                            Text("[\(tag.value)]")
                                .foregroundStyle(Palette.blue)
                                .contextMenu {
                                    Button("delete tag", role: .destructive) { store.deleteAnnotation(tag) }
                                        .disabled(session.isRemoteArchiveSession)
                                }
                        }
                    }
                }
            }
            let notes = store.annotations.filter { $0.kind == .note }
            if !notes.isEmpty {
                metaRow("notes") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(notes) { note in
                            (Text(Present.dateStamp(note.timestamp)).foregroundColor(Palette.faint)
                                + Text(" \(note.value)").foregroundColor(Palette.text))
                                .fontWeight(.medium)
                                .fixedSize(horizontal: false, vertical: true)
                                .contextMenu {
                                    Button("delete note", role: .destructive) { store.deleteAnnotation(note) }
                                        .disabled(session.isRemoteArchiveSession)
                                }
                        }
                    }
                }
            }
        }

        if store.isSearchActive, let match = store.selectedSearchResult {
            VStack(alignment: .leading, spacing: Metrics.s2) {
                HStack(spacing: Metrics.s2) {
                    columnLabel("search match")
                    Text("\(match.matchSource.rawValue) · \(match.score.formatted(.number.precision(.fractionLength(2))))")
                        .foregroundStyle(Palette.amber)
                }
                Text(match.matchSnippet ?? "matched indexed metadata")
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(.vertical, Metrics.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { rule }
            .overlay(alignment: .bottom) { rule }
        }

        excerptBlock(
            "first prompt",
            Present.excerpt(session.firstPrompt, limit: HolyArchiveMetrics.promptCharacters, empty: "(no prompt found)")
        )
        excerptBlock(
            "last response",
            Present.excerpt(session.lastResponse, limit: Present.responseLimit(for: session), empty: "(no response found)")
        )

        VStack(alignment: .leading, spacing: Metrics.s2) {
            columnLabel(session.isRemoteArchiveSession ? "resume on \(session.archiveSource.hostLabel)" : "resume command")
            Text(session.resumeCommand ?? "no safe resume command for this provider")
                .foregroundStyle(session.resumeCommand == nil ? Palette.faint : Palette.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Metrics.s2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.raised)
            Text(
                session.isRemoteArchiveSession
                    ? "r resume on \(session.archiveSource.hostLabel) · tab panes"
                    : "enter copy · r resume · tab panes"
            )
            .foregroundStyle(Palette.faint)
        }

        Spacer(minLength: 0)

        VStack(alignment: .leading, spacing: Metrics.s2) {
            HolyMannaFlowLayout(spacing: Metrics.s3) {
                Text("copy:").foregroundStyle(Palette.muted)
                if let command = session.resumeCommand, !session.isRemoteArchiveSession {
                    copyButton("command") { (command, "resume command") }
                }
                copyButton("id") { (session.providerSessionID, session.providerSessionID) }
                if let path = session.projectPath {
                    copyButton("path") { (path, path) }
                }
            }
            HolyMannaFlowLayout(spacing: Metrics.s3) {
                Text("act:").foregroundStyle(Palette.muted)
                actButton("resume", enabled: session.resumeCommand != nil && session.harness.runtime != nil) {
                    store.resumeSelected()
                }
                actButton("transcript", enabled: true) { store.showTranscript() }
                actButton(
                    store.isGeneratingTitle ? "naming…" : "name",
                    enabled: !store.isGeneratingTitle && !session.isRemoteArchiveSession
                ) {
                    store.generateTitle()
                }
                actButton("tag", enabled: !session.isRemoteArchiveSession) { store.beginAnnotation(.tag) }
                actButton("note", enabled: !session.isRemoteArchiveSession) { store.beginAnnotation(.note) }
            }
        }
        .padding(.top, Metrics.s2)
        .overlay(alignment: .top) { rule }
    }

    private func excerptBlock(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: Metrics.s2) {
            columnLabel(label)
            Text(text)
                .foregroundStyle(text.hasPrefix("(") ? Palette.faint : Palette.text)
                .lineSpacing(Metrics.bodySize * (Metrics.bodyLineHeight - 1))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.vertical, Metrics.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { rule }
    }

    // MARK: - Transcript

    private var transcriptView: some View {
        VStack(spacing: 0) {
            HolyMannaFlowLayout(spacing: Metrics.s3) {
                (Text("$ ").foregroundColor(Palette.green)
                    + Text("agent-sessions transcript").fontWeight(.semibold).foregroundColor(Palette.text)
                    + Text(" \(store.transcript.count)").foregroundColor(Palette.faint))
                linkButton("[copy all]") { store.copyTranscript() }
                linkButton("[find]") { store.showTranscriptFind() }
                linkButton("[done]") { store.closeTranscript() }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Metrics.s4)
            .padding(.top, Metrics.s3)
            .padding(.bottom, Metrics.s1)
            if store.transcriptFindIsPresented {
                HStack(spacing: Metrics.s2) {
                    TextField("find in transcript", text: $store.transcriptFindQuery)
                        .textFieldStyle(.plain)
                        .focused($findFocused)
                        .onChange(of: store.transcriptFindQuery) { _ in store.recomputeFind() }
                        .onSubmit { store.nextFindMatch() }
                        .padding(.horizontal, Metrics.s2)
                        .frame(height: Metrics.grepFieldHeight)
                        .background(Palette.surface)
                        .overlay(Rectangle().stroke(findFocused ? Palette.blue : Palette.line, lineWidth: 1))
                    Text(store.findMatchCount == 0 ? "no matches" : "\(store.findMatchIndex + 1)/\(store.findMatchCount)")
                        .foregroundStyle(Palette.faint)
                        .lineLimit(1)
                    linkButton("[↑]") { store.nextFindMatch(-1) }
                    linkButton("[↓]") { store.nextFindMatch() }
                    linkButton("[×]") {
                        store.transcriptFindIsPresented = false
                        store.transcriptFindQuery = ""
                        store.recomputeFind()
                    }
                }
                .padding(.horizontal, Metrics.s4)
                .padding(.vertical, Metrics.s1)
            }
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("session  \(store.selectedSession?.id ?? "unknown")")
                            Text("path     \(store.selectedSession?.projectPath ?? "unknown")")
                            Text("messages \(store.transcript.count)")
                            if store.transcript.isEmpty {
                                Text(store.statusMessage == "Loading transcript..." ? "loading…" : "(no messages found)")
                            }
                        }
                        .foregroundStyle(Palette.faint)
                        .padding(.vertical, Metrics.s2)
                        .overlay(alignment: .bottom) { rule }
                        ForEach(Array(store.transcript.enumerated()), id: \.element.id) { index, message in
                            HolyArchiveTranscriptMessageView(index: index + 1, message: message, find: store.transcriptFindQuery)
                                .id(message.id)
                                .background {
                                    GeometryReader { geometry in
                                        Color.clear.preference(
                                            key: HolyArchiveTranscriptFramePreferenceKey.self,
                                            value: [message.id: geometry.frame(in: .named("archive-transcript"))]
                                        )
                                    }
                                }
                        }
                        if !store.transcript.isEmpty {
                            Text("━ end of transcript ━  \(Present.transcriptLegend)")
                                .foregroundStyle(Palette.faint)
                                .padding(.vertical, Metrics.s3)
                        }
                    }
                    .padding(.horizontal, Metrics.s4)
                }
                .coordinateSpace(name: "archive-transcript")
                .onPreferenceChange(HolyArchiveTranscriptFramePreferenceKey.self) { frames in
                    store.visibleTranscriptMessageID = frames
                        .filter { $0.value.maxY > 0 }
                        .min { left, right in max(0, left.value.minY) < max(0, right.value.minY) }?
                        .key
                }
                .onChange(of: store.findMatchIndex) { _ in
                    if let id = transcriptTargetMessageID {
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
    }

    private var transcriptTargetMessageID: String? {
        guard store.findMatchCount > 0 else { return nil }
        var remaining = store.findMatchIndex
        for message in store.transcript {
            let count = HolyArchiveTranscriptFind.ranges(of: store.transcriptFindQuery, in: message.content).count
            if remaining < count { return message.id }
            remaining -= count
        }
        return nil
    }

    // MARK: - Resizer and strip

    private func resizer(currentWidth: CGFloat, windowWidth: CGFloat) -> some View {
        Rectangle()
            .fill(resizerHovered || inspectorDragSession != nil ? Palette.lineStrong : Color.clear)
            .frame(width: Metrics.resizerWidth)
            .overlay(alignment: .leading) { Rectangle().fill(Palette.line).frame(width: 1) }
            .contentShape(Rectangle())
            .onHover { resizerHovered = $0 }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        var session = inspectorDragSession ?? HolyLedgerInspectorDragSession(
                            startingWidth: currentWidth,
                            bounds: HolyLedgerResponsiveLayout.inspectorWidthBounds(windowWidth: windowWidth),
                            startingPointerX: value.startLocation.x
                        )
                        if session.update(pointerX: value.location.x) != nil {
                            inspectorDragSession = session
                        } else if inspectorDragSession == nil {
                            inspectorDragSession = session
                        }
                    }
                    .onEnded { value in
                        guard var session = inspectorDragSession else { return }
                        if let committed = session.finish(pointerX: value.location.x),
                           abs(CGFloat(storedInspectorWidth) - committed)
                            >= HolyLedgerInspectorDragSession.writeEpsilon {
                            storedInspectorWidth = Double(committed)
                        }
                        inspectorDragSession = nil
                    }
            )
            .onTapGesture(count: 2) {
                inspectorDragSession = nil
                let defaultWidth = Double(HolyArchiveMetrics.inspectorDefaultWidth)
                if storedInspectorWidth != defaultWidth {
                    storedInspectorWidth = defaultWidth
                }
            }
            .help("drag · double-click to reset")
    }

    /// Status on the left (indexing, the TUI's toasts, errors), the key
    /// legend on the right.
    private func strip(width: CGFloat) -> some View {
        HStack(spacing: Metrics.s4) {
            if let progress = store.indexProgress {
                spinner
                Text("\(progress.phase.rawValue) \(progress.completed)/\(max(progress.total, progress.completed)) · \(progress.detail)")
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if let error = store.errorMessage {
                Text(error).foregroundStyle(Palette.red).lineLimit(1).truncationMode(.middle).help(error)
                linkButton("dismiss") { store.clearError() }
            } else if let status = store.statusMessage {
                Text(status).lineLimit(1).truncationMode(.middle)
            }
            if let semantic = store.semanticStatus {
                Text(semantic).foregroundStyle(Palette.faint).lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(
                store.transcriptIsPresented
                    ? Present.transcriptLegend
                    : (store.selectedSession?.isRemoteArchiveSession == true
                        ? Present.remoteKeyLegend
                        : Present.keyLegend)
            )
                .foregroundStyle(Palette.faint)
                .lineLimit(1)
                .layoutPriority(-1)
        }
        .foregroundStyle(Palette.muted)
        .padding(.horizontal, pagePadding(width))
        .frame(height: Metrics.stripHeight)
        .background(Palette.surface)
        .overlay(alignment: .top) { rule }
    }

    // MARK: - Shared chrome

    private var rule: some View {
        Rectangle().fill(Palette.line).frame(height: 1)
    }

    private func separator(_ glyph: String) -> some View {
        Text(glyph).foregroundStyle(Palette.faint).padding(.horizontal, Metrics.s1)
    }

    private func linkButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).foregroundStyle(Palette.blue).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func actButton(_ verb: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("[\(verb)]").foregroundStyle(enabled ? Palette.green : Palette.faint).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func copyButton(_ label: String, payload: @escaping () -> (text: String, note: String)?) -> some View {
        let copied = copiedLabel == label
        return Button {
            guard let payload = payload() else { return }
            copy(payload.text, note: payload.note, label: label)
        } label: {
            Text(copied ? "[copied]" : "[\(label)]")
                .foregroundStyle(copied ? Palette.green : Palette.blue)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sheetHead<Trailing: View>(_ prompt: String, count: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s2) {
            (Text("$ ").foregroundColor(Palette.green)
                + Text(prompt).fontWeight(.semibold).foregroundColor(Palette.text))
            Text(count).foregroundStyle(Palette.faint)
            trailing()
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Metrics.s3)
        .padding(.bottom, Metrics.s1)
    }

    private func columnLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .tracking(Metrics.pillTracking)
            .foregroundStyle(Palette.faint)
            .lineLimit(1)
    }

    /// A column header whose grip trades width only between its two neighbors.
    private func resizableHeader(
        _ label: String,
        columnID: String? = nil,
        columns: HolyLedgerResolvedColumns,
        boundary: HolyLedgerColumnBoundary,
        columnOrder: [String],
        alignment: Alignment = .leading
    ) -> some View {
        let column = columnID ?? label
        let flexibleColumn = "summary"
        return columnLabel(label)
            .frame(width: columns.width(column), alignment: alignment)
            .overlay(alignment: boundary.gripOnLeadingEdge ? .leading : .trailing) {
                HolyLedgerColumnGrip(
                    boundary: boundary,
                    currentWidths: columns.widths(includingFlexibleColumn: flexibleColumn),
                    minimumWidths: boundary.columns.reduce(into: [:]) { result, boundaryColumn in
                        if boundaryColumn == flexibleColumn {
                            result[boundaryColumn] = columns.minimumFlexibleWidth
                        } else {
                            result[boundaryColumn] = HolyMannaBoardMetrics.columnWidth(
                                contentCharacters: HolyLedgerColumnGrip.minimumCharacters,
                                headerCharacters: boundaryColumn.count
                            )
                        }
                    },
                    columnOrder: columnOrder,
                    columnGap: Metrics.columnGap,
                    availableWidth: columns.availableWidth,
                    onPreview: { preview in
                        if columnDragPreview != preview {
                            columnDragPreview = preview
                        }
                    },
                    onCommit: { commit in
                        var overrides = HolyLedgerColumnOverrides(json: columnOverridesJSON)
                        for resizedColumn in boundary.columns where resizedColumn != flexibleColumn {
                            guard let newWidth = commit.widths[resizedColumn] else { continue }
                            overrides.set(
                                resizedColumn,
                                width: newWidth,
                                availableWidth: commit.availableWidth
                            )
                        }
                        let persisted = overrides.json
                        if columnOverridesJSON != persisted {
                            columnOverridesJSON = persisted
                        }
                        columnDragPreview = nil
                    },
                    onEnd: { columnDragPreview = nil },
                    onReset: { resetColumns in
                        columnDragPreview = nil
                        var overrides = HolyLedgerColumnOverrides(json: columnOverridesJSON)
                        for resetColumn in resetColumns where resetColumn != flexibleColumn {
                            overrides.reset(resetColumn)
                        }
                        columnOverridesJSON = overrides.json
                    }
                )
                .offset(
                    x: (Metrics.columnGap / 2 + HolyLedgerColumnGrip.width / 2)
                        * (boundary.gripOnLeadingEdge ? -1 : 1)
                )
            }
    }

    private func pill(_ word: String, color: Color) -> some View {
        Text(word.uppercased()).tracking(Metrics.pillTracking).foregroundStyle(color).lineLimit(1)
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(Palette.faint)
            .padding(Metrics.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func buildingLine(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s2) {
            spinner
            Text(text).foregroundStyle(Palette.muted)
        }
        .padding(.vertical, Metrics.s2)
    }

    private func metaRow<Value: View>(_ label: String, @ViewBuilder value: () -> Value) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(Palette.muted)
                .frame(width: Metrics.metaLabelWidth, alignment: .leading)
            value().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metaValue(_ text: String) -> some View {
        Text(text)
            .fontWeight(.medium)
            .foregroundStyle(Palette.text)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private func stripe(_ cls: String) -> some View {
        Rectangle()
            .fill(Palette.stripeColor(forClass: cls))
            .frame(width: Metrics.stripeWidth, height: Metrics.stripeHeight)
            .frame(width: Metrics.stripeColumnWidth, alignment: .leading)
    }

    private func rowBackground(selected: Bool, hovered: Bool, even: Bool) -> Color {
        if selected || hovered { return Palette.raised }
        return even ? Palette.zebra : Color.clear
    }

    private func setHover(_ id: String, _ hovering: Bool) {
        if hovering {
            hoveredRowID = id
        } else if hoveredRowID == id {
            hoveredRowID = nil
        }
    }

    private func copy(_ text: String, note: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedLabel = label
        copiedResetTask?.cancel()
        copiedResetTask = Task {
            try? await Task.sleep(for: .seconds(Metrics.copiedFlashSeconds))
            guard !Task.isCancelled else { return }
            copiedLabel = nil
        }
    }
}

private struct HolyArchiveTranscriptFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

/// widgets.py build_message_text: `[i] User` green, `Assistant` magenta,
/// the body in a gutter; here the gutter is the cockpit's rule.
private struct HolyArchiveTranscriptMessageView: View {
    let index: Int
    let message: HolyArchiveMessage
    let find: String

    var body: some View {
        VStack(alignment: .leading, spacing: HolyMannaBoardMetrics.s1) {
            HStack(spacing: HolyMannaBoardMetrics.s2) {
                Text("[\(index)]").foregroundStyle(HolyMannaBoardPalette.faint)
                Text(message.role.rawValue.uppercased())
                    .tracking(HolyMannaBoardMetrics.pillTracking)
                    .foregroundStyle(roleColor)
                Rectangle().fill(HolyMannaBoardPalette.line).frame(height: 1)
            }
            Text(highlighted)
                .lineSpacing(HolyMannaBoardMetrics.bodySize * (HolyMannaBoardMetrics.bodyLineHeight - 1))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, HolyMannaBoardMetrics.s2)
    }

    private var roleColor: Color {
        switch message.role {
        case .user: HolyMannaBoardPalette.green
        case .assistant: HolyMannaBoardPalette.violet
        case .tool: HolyMannaBoardPalette.blue
        default: HolyMannaBoardPalette.muted
        }
    }

    private var highlighted: AttributedString {
        var result = AttributedString(message.content)
        guard !find.isEmpty else { return result }
        for range in HolyArchiveTranscriptFind.ranges(of: find, in: message.content) {
            guard let lower = AttributedString.Index(range.lowerBound, within: result),
                  let upper = AttributedString.Index(range.upperBound, within: result) else { continue }
            result[lower..<upper].backgroundColor = NSColor(HolyMannaBoardPalette.select).withAlphaComponent(0.35)
            result[lower..<upper].foregroundColor = NSColor.white
        }
        return result
    }
}

/// chat_widgets.py: your turns, the researcher's answers, tool calls folded.
private struct HolyArchiveResearchMessageView: View {
    let message: HolyArchiveResearchMessage
    let onCitation: (String) -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: HolyMannaBoardMetrics.s1) {
            if message.toolCallJSON != nil || message.role == .tool {
                Button {
                    expanded.toggle()
                } label: {
                    Text((expanded ? "▾ " : "▸ ") + (message.role == .tool ? "TOOL OUTPUT" : "TOOL CALL"))
                        .tracking(HolyMannaBoardMetrics.pillTracking)
                        .foregroundStyle(HolyMannaBoardPalette.faint)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if expanded {
                    Text(message.content)
                        .foregroundStyle(HolyMannaBoardPalette.muted)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(message.role == .user ? "YOU" : "ASSISTANT")
                    .tracking(HolyMannaBoardMetrics.pillTracking)
                    .foregroundStyle(message.role == .user ? HolyMannaBoardPalette.amber : HolyMannaBoardPalette.faint)
                Text(message.content)
                    .foregroundStyle(HolyMannaBoardPalette.text)
                    .lineSpacing(HolyMannaBoardMetrics.bodySize * (HolyMannaBoardMetrics.bodyLineHeight - 1))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if !message.citedSessionIDs.isEmpty {
                    HolyMannaFlowLayout(spacing: HolyMannaBoardMetrics.s2) {
                        Text("refs:").foregroundStyle(HolyMannaBoardPalette.muted)
                        ForEach(message.citedSessionIDs, id: \.self) { id in
                            Button {
                                onCitation(id)
                            } label: {
                                Text("[\(String(id.prefix(8)))]").foregroundStyle(HolyMannaBoardPalette.blue)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.vertical, HolyMannaBoardMetrics.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(HolyMannaBoardPalette.line).frame(height: 1) }
        .contextMenu {
            Button("copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.content, forType: .string)
            }
        }
    }
}
