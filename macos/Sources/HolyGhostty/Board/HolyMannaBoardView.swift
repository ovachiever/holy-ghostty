import AppKit
import SwiftUI

private typealias Palette = HolyMannaBoardPalette
private typealias Metrics = HolyMannaBoardMetrics
private typealias Present = HolyMannaBoardPresentation

/// The Escape key's virtual code (kVK_Escape).
private let escapeKeyCode: UInt16 = 53
/// index.js SPIN: the honest-loading spinner frames, one every 120 ms.
private let spinnerFrames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
private let spinnerInterval: TimeInterval = 0.12
/// app.js refreshes the "updated Ns ago" label once a second.
private let clockInterval: TimeInterval = 1

/// Board mode: the manna serve web cockpit, native. One continuous ledger
/// (now · next · waiting), an inspector on the right, the estate table when
/// no board is focused. Every rule of the layout comes from the page's
/// styles.css / app.js by way of HolyMannaBoardPresentation.
struct HolyMannaBoardView: View {
    @ObservedObject var store: HolyMannaBoardModeStore
    let onDismiss: () -> Void
    let onFocusPeer: (String) -> Bool

    @AppStorage("holy.board.inspectorWidth.v1") private var storedInspectorWidth = Double(Metrics.inspectorDefaultWidth)
    @AppStorage("holy.board.summaryOpen.v1") private var summaryOpen = true
    @FocusState private var grepFocused: Bool
    @State private var inspectorDragStartWidth: CGFloat?
    @State private var resizerHovered = false
    @State private var hoveredRowID: String?
    @State private var copiedLabel: String?
    @State private var copiedResetTask: Task<Void, Never>?
    @State private var keyMonitor: Any?
    @State private var buildingSince: Date?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if store.surface == .estate {
                        estateSurface(width: geometry.size.width)
                    } else {
                        boardSurface(width: geometry.size.width)
                    }
                }
                toast
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg)
        .font(mono())
        .foregroundStyle(Palette.text)
        .onExitCommand(perform: onDismiss)
        .confirmationDialog(
            store.pendingMutation?.confirmationTitle ?? "Confirm Manna action",
            isPresented: Binding(
                get: { store.pendingMutation != nil },
                set: { if !$0 { store.pendingMutation = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let mutation = store.pendingMutation {
                Button(mutation.label, role: mutation.isDestructive ? .destructive : nil) {
                    store.confirmPendingMutation()
                }
            }
            Button("Cancel", role: .cancel) {
                store.pendingMutation = nil
            }
        } message: {
            Text(store.pendingMutation?.confirmationDetail ?? "")
        }
        .onAppear(perform: installKeyMonitor)
        .onDisappear(perform: removeKeyMonitor)
        .onChange(of: store.grepFocusRequest) { _ in
            grepFocused = true
        }
        .onChange(of: grepFocused) { focused in
            store.isGrepFocused = focused
        }
    }

    // MARK: - Layout arithmetic

    /// The page centers its cockpit at 1440px; Holy fills the pane column
    /// edge to edge, like the terminal it stands in for (Erik, 2026-09-02).
    private func pagePadding(_ width: CGFloat) -> CGFloat {
        Metrics.s4
    }

    private func showsInspector(_ width: CGFloat) -> Bool {
        width > Metrics.compactBreakpoint
    }

    private func inspectorWidth(_ width: CGFloat) -> CGFloat {
        if width <= Metrics.narrowBreakpoint { return Metrics.inspectorNarrowWidth }
        return min(Metrics.inspectorMaximumWidth, max(Metrics.inspectorMinimumWidth, CGFloat(storedInspectorWidth)))
    }

    private func mono(_ size: CGFloat = Metrics.bodySize, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: - Board surface

    private func boardSurface(width: CGFloat) -> some View {
        let showsInspector = showsInspector(width)
        let inspectorWidth = inspectorWidth(width)
        return VStack(spacing: 0) {
            boardTopbar(width: width, inspectorWidth: inspectorWidth, showsInspector: showsInspector)
            HStack(spacing: 0) {
                sheet
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showsInspector {
                    resizer(currentWidth: inspectorWidth)
                    inspector
                        .frame(width: inspectorWidth)
                        .frame(maxHeight: .infinity)
                        .background(Palette.surface)
                }
            }
            .padding(.horizontal, pagePadding(width))
            strip(width: width)
        }
    }

    private func boardTopbar(width: CGFloat, inspectorWidth: CGFloat, showsInspector: Bool) -> some View {
        HStack(spacing: Metrics.s4) {
            crumb
            tabs.fixedSize()
            grepField
            Spacer(minLength: 0)
            topbarRight
                .frame(width: showsInspector ? inspectorWidth : nil, alignment: .trailing)
                .padding(.leading, showsInspector ? Metrics.s4 : 0)
        }
        .padding(.horizontal, pagePadding(width))
        .frame(height: Metrics.topbarHeight)
        .padding(.top, Metrics.titlebarInset)
        .background(Palette.surface)
        .overlay(alignment: .bottom) { rule }
    }

    /// `terminal › estate › board`: the outermost crumb is the way out. The
    /// page has no such link because a browser tab is its own exit.
    private var crumb: some View {
        HStack(spacing: 0) {
            terminalCrumb
            separator("›")
            linkButton("estate") { store.showEstate() }
            separator("›")
            Text(store.boardName)
                .fontWeight(.semibold)
                .foregroundStyle(Palette.text)
                .help(store.context.boardRoot ?? "")
            if let host = store.context.remoteHost {
                Text("via \(host)")
                    .foregroundStyle(Palette.blue)
                    .padding(.leading, Metrics.s2)
            }
        }
        .foregroundStyle(Palette.muted)
        .lineLimit(1)
        .fixedSize()
    }

    private var terminalCrumb: some View {
        linkButton("‹ terminal") { onDismiss() }
            .help("Return to the terminal (Escape)")
            .accessibilityLabel("Return to terminal")
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(HolyMannaBoardSheet.tabs) { sheet in
                let active = store.selectedSheet == sheet
                Button {
                    store.selectSheet(sheet)
                } label: {
                    HStack(spacing: Metrics.s1) {
                        Text(sheet.title)
                        if let badge = badge(for: sheet) {
                            Text(badge).foregroundStyle(Palette.amber)
                        }
                    }
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
        }
    }

    private func badge(for sheet: HolyMannaBoardSheet) -> String? {
        guard let state = store.state else { return nil }
        let count: Int = switch sheet {
        case .asks: state.asks.count
        case .coordination: state.attentionCount
        default: 0
        }
        return count > 0 ? String(count) : nil
    }

    private var grepField: some View {
        TextField("grep · ⌘F", text: $store.grep)
            .textFieldStyle(.plain)
            .focused($grepFocused)
            .padding(.horizontal, Metrics.s2)
            // The page fixes the bar at 400px; here it yields down to half
            // that when the crumb and tabs need the room, so the right
            // cluster and the inspector never leave the window.
            .frame(
                minWidth: Metrics.grepFieldWidth / 2,
                idealWidth: Metrics.grepFieldWidth,
                maxWidth: Metrics.grepFieldWidth,
                minHeight: Metrics.grepFieldHeight,
                maxHeight: Metrics.grepFieldHeight
            )
            .background(Palette.surface)
            .overlay(Rectangle().stroke(grepFocused ? Palette.blue : Palette.line, lineWidth: 1))
            .padding(.leading, Metrics.s6 - Metrics.s4)
    }

    /// updated Ns ago | ● live | refresh — the mark is lit only while the
    /// board is being kept current and its last read landed.
    private var topbarRight: some View {
        TimelineView(.periodic(from: .now, by: clockInterval)) { timeline in
            HStack(spacing: Metrics.s1) {
                Text(Present.updatedLabel(since: store.lastRefreshedAt, now: timeline.date))
                separator("|")
                Text(store.isLive ? "●" : "○")
                    .foregroundStyle(store.isLive ? Palette.green : Palette.faint)
                Text(Present.connectionLabel(
                    isLive: store.isLive,
                    isRefreshing: store.isRefreshing,
                    hasState: store.state != nil,
                    failed: store.boardFailure != nil
                ))
                separator("|")
                if store.isRefreshing {
                    Text("reading…").foregroundStyle(Palette.faint)
                } else {
                    linkButton("refresh") { store.requestRefresh(force: true) }
                }
            }
            .foregroundStyle(Palette.muted)
            .lineLimit(1)
        }
    }

    // MARK: - Sheet

    private var sheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch store.selectedSheet {
                case .board: boardSheet
                case .asks: inboxSheet
                case .coordination: coordinationSheet
                case .debug: debugSheet
                }
            }
            .padding(.trailing, Metrics.s4)
            .padding(.bottom, Metrics.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var boardSheet: some View {
        chips
        if let state = store.state {
            let sections = store.boardSections
            let showsAge = store.boardFilter == .recent
            let columns = Present.boardColumns(for: sections.flatMap(\.items), showsAge: showsAge)
            let dimFallback = state.all.contains { !Present.isFallbackText($0) }
            boardColumnHeader(columns, showsAge: showsAge)
            ForEach(sections) { section in
                sheetHead(section.prompt, count: String(section.items.count))
                if section.items.isEmpty {
                    emptyLine(section.emptyText)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                            itemRow(item, index: index, columns: columns, showsAge: showsAge, dimFallback: dimFallback)
                        }
                    }
                }
            }
        } else {
            buildingLine(store.boardFailure ?? "reading the board…", failed: store.boardFailure != nil)
        }
    }

    private var chips: some View {
        HStack(spacing: Metrics.s2) {
            ForEach(HolyMannaBoardFilter.allCases) { filter in
                Button {
                    store.selectFilter(filter)
                } label: {
                    chipLabel(filter.rawValue, active: store.boardFilter == filter)
                }
                .buttonStyle(.plain)
            }
            trackPicker
            Spacer(minLength: 0)
        }
        .padding(.top, Metrics.s2)
        .padding(.bottom, Metrics.s1)
    }

    private func chipLabel(_ text: String, active: Bool) -> some View {
        Text(text)
            .foregroundStyle(active ? Palette.text : Palette.muted)
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

    private var trackPicker: some View {
        let tracks = store.state?.tracks ?? []
        let selectedTitle = tracks.first { ($0.trackID ?? Present.untrackedFilter) == store.trackFilter }
            .map { Present.shortTrack($0.title) }
        return Menu {
            Button("every track") { store.trackFilter = nil }
            Divider()
            ForEach(tracks) { track in
                Button(Present.shortTrack(track.title)) {
                    store.trackFilter = track.trackID ?? Present.untrackedFilter
                }
            }
        } label: {
            chipLabel(selectedTitle.map { "\($0) ▾" } ?? "track ▾", active: store.trackFilter != nil)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func boardColumnHeader(_ columns: HolyMannaBoardColumnWidths, showsAge: Bool) -> some View {
        HStack(spacing: Metrics.columnGap) {
            Color.clear.frame(width: Metrics.stripeColumnWidth)
            columnLabel("id").frame(width: columns.id, alignment: .leading)
            columnLabel("digest").frame(maxWidth: .infinity, alignment: .leading)
            columnLabel("track").frame(width: columns.track, alignment: .leading)
            columnLabel("state").frame(width: columns.state, alignment: .leading)
            columnLabel(showsAge ? "age" : "#").frame(width: columns.priority, alignment: .trailing)
        }
        .frame(height: Metrics.columnHeaderHeight)
        .overlay(alignment: .bottom) { rule }
    }

    /// One ledger line: stripe · id · digest · track · state · #.
    private func itemRow(
        _ item: HolyMannaBoardItem,
        index: Int,
        columns: HolyMannaBoardColumnWidths,
        showsAge: Bool,
        dimFallback: Bool
    ) -> some View {
        let selected = store.selectedItemID == item.id && store.selectedPeerID == nil
        let cell = Present.stateCell(for: item)
        return HStack(alignment: .center, spacing: Metrics.columnGap) {
            stripe(Present.stripeClass(for: item))
            Text(item.id)
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
                .frame(width: columns.id, alignment: .leading)
            Text(Present.rowText(item))
                .foregroundStyle(dimFallback && Present.isFallbackText(item) ? Palette.muted : Palette.text)
                .lineSpacing(Metrics.bodySize * (Metrics.digestLineHeight - 1))
                .padding(.vertical, Metrics.s1)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(Present.shortTrack(item.trackTitle))
                .foregroundStyle(Palette.faint)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: columns.track, alignment: .leading)
                .help(item.trackTitle ?? "")
            stateText(cell)
                .frame(width: columns.state, alignment: .leading)
                .help(cell.plain)
            Text(showsAge ? Present.ago(item.updatedAt) : Present.priorityText(item))
                .foregroundStyle(Palette.faint)
                .lineLimit(1)
                .frame(width: columns.priority, alignment: .trailing)
        }
        .frame(minHeight: Metrics.rowHeight)
        .background(rowBackground(selected: selected, hovered: hoveredRowID == item.id, even: index % 2 == 1))
        .overlay(alignment: .leading) {
            if selected {
                Rectangle().fill(Palette.select).frame(width: Metrics.selectionEdgeWidth)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { store.selectItem(item.id) }
        .onHover { hovering in setHover(item.id, hovering) }
        .help(item.title)
    }

    /// The state word in caps, tracked; blocker ids after " · " in their own case.
    private func stateText(_ cell: HolyMannaStateCell) -> some View {
        var text = Text(cell.word.uppercased()).tracking(Metrics.pillTracking)
        if let keepCase = cell.keepCase {
            text = text + Text(" · ") + Text(keepCase)
        }
        return text
            .foregroundStyle(Palette.wordColor(forClass: cell.cls))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    // MARK: - Inbox sheet

    @ViewBuilder
    private var inboxSheet: some View {
        let rows = store.inboxRows
        sheetHead("manna inbox", count: String(rows.count))
        if store.state == nil {
            buildingLine(store.boardFailure ?? "reading the board…", failed: store.boardFailure != nil)
        } else {
            let columns = Present.inboxColumns(for: rows)
            HStack(spacing: Metrics.columnGap) {
                Color.clear.frame(width: Metrics.stripeColumnWidth)
                columnLabel("kind").frame(width: columns.kind, alignment: .leading)
                columnLabel("ask").frame(maxWidth: .infinity, alignment: .leading)
                columnLabel("verb").frame(width: columns.verb, alignment: .trailing)
            }
            .frame(height: Metrics.columnHeaderHeight)
            .overlay(alignment: .bottom) { rule }
            if rows.isEmpty {
                emptyLine("Nothing is waiting on you.")
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    inboxRow(row, index: index, columns: columns)
                }
            }
        }
    }

    private func inboxRow(_ row: HolyMannaInboxRowModel, index: Int, columns: HolyMannaInboxColumnWidths) -> some View {
        HStack(alignment: .center, spacing: Metrics.columnGap) {
            stripe(row.cls)
            Text(row.kind)
                .foregroundStyle(Palette.faint)
                .lineLimit(1)
                .frame(width: columns.kind, alignment: .leading)
            Text(row.text)
                .foregroundStyle(Palette.text)
                .lineSpacing(Metrics.bodySize * (Metrics.digestLineHeight - 1))
                .padding(.vertical, Metrics.s1)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            verbCell(row)
                .frame(width: columns.verb, alignment: .trailing)
        }
        .frame(minHeight: Metrics.rowHeight)
        .background(rowBackground(selected: false, hovered: hoveredRowID == row.id, even: index % 2 == 1))
        .contentShape(Rectangle())
        .onTapGesture { store.follow(row.ask.target) }
        .onHover { hovering in setHover(row.id, hovering) }
    }

    /// The verb is the button. A dream offers promote / delete; a plain ask
    /// is a colored word that follows its target.
    @ViewBuilder
    private func verbCell(_ row: HolyMannaInboxRowModel) -> some View {
        let color = Palette.wordColor(forClass: row.cls)
        if row.ask.kind == "dream", let id = row.ask.itemID {
            if isWorking(.promote(id)) || isWorking(.delete(id)) {
                pill("working…", color: Palette.muted)
            } else {
                HStack(spacing: Metrics.s3) {
                    verbButton("promote", color: Palette.green) { store.requestMutation(.promote(id)) }
                    verbButton("delete", color: Palette.red) { store.requestMutation(.delete(id)) }
                }
            }
        } else if let action = row.ask.action {
            if isWorking(action) {
                pill("working…", color: Palette.muted)
            } else {
                verbButton(row.verb, color: color) { store.requestMutation(action) }
            }
        } else {
            pill(row.verb, color: color)
        }
    }

    private func isWorking(_ mutation: HolyMannaMutation) -> Bool {
        store.activeMutation == mutation
    }

    private func verbButton(_ verb: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            pill(verb, color: color)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.isMutating)
    }

    private func pill(_ word: String, color: Color) -> some View {
        Text(word.uppercased())
            .tracking(Metrics.pillTracking)
            .foregroundStyle(color)
            .lineLimit(1)
    }

    // MARK: - Coordination sheet

    @ViewBuilder
    private var coordinationSheet: some View {
        if let state = store.state {
            let peers = state.peers.filter { Present.peerMatches($0, grep: store.grep) }
            let needs = peers.filter { $0.attention == "needs-user" || $0.attention == "failed" }
            let here = peers.filter { $0.attention != "gone" && !needs.contains($0) }
            let gone = peers.filter { $0.attention == "gone" }
            let claims = state.coord.claims.filter { Present.claimMatches($0, grep: store.grep) }
            let drops = state.coord.drops

            peerSection("coord needs you", peers: needs, empty: "Nobody is waiting on you.")
            peerSection("coord peers", peers: here, empty: "No live sessions.")

            sheetHead("coord claims", count: String(claims.count))
            let claimColumns = Present.claimColumns(for: claims)
            HStack(spacing: Metrics.columnGap) {
                Color.clear.frame(width: Metrics.stripeColumnWidth)
                columnLabel("path").frame(maxWidth: .infinity, alignment: .leading)
                columnLabel("owner").frame(width: claimColumns.owner, alignment: .leading)
                columnLabel("state").frame(width: claimColumns.state, alignment: .leading)
                columnLabel("age").frame(width: claimColumns.age, alignment: .trailing)
            }
            .frame(height: Metrics.columnHeaderHeight)
            .overlay(alignment: .bottom) { rule }
            if claims.isEmpty {
                emptyLine("No advisory claims.")
            } else {
                ForEach(Array(claims.enumerated()), id: \.element.id) { index, claim in
                    claimRow(claim, index: index, columns: claimColumns)
                }
            }

            sheetHead("coord drops", count: String(drops.count))
            let dropColumns = Present.dropColumns(for: drops)
            HStack(spacing: Metrics.columnGap) {
                Color.clear.frame(width: Metrics.stripeColumnWidth)
                columnLabel("from → for").frame(width: dropColumns.from, alignment: .leading)
                columnLabel("drop").frame(maxWidth: .infinity, alignment: .leading)
                columnLabel("age").frame(width: dropColumns.age, alignment: .trailing)
            }
            .frame(height: Metrics.columnHeaderHeight)
            .overlay(alignment: .bottom) { rule }
            if drops.isEmpty {
                emptyLine("No drops waiting.")
            } else {
                ForEach(Array(drops.enumerated()), id: \.element.id) { index, drop in
                    dropRow(drop, index: index, columns: dropColumns)
                }
            }

            if !state.coord.needs.isEmpty {
                sheetHead("coord needs", count: String(state.coord.needs.count))
                ForEach(Array(state.coord.needs.enumerated()), id: \.element.id) { index, need in
                    needRow(need, index: index)
                }
            }

            if !gone.isEmpty {
                peerSection("coord gone", peers: gone, empty: "")
            }
        } else {
            buildingLine(store.boardFailure ?? "still reading coordination…", failed: store.boardFailure != nil)
        }
    }

    @ViewBuilder
    private func peerSection(_ prompt: String, peers: [HolyMannaPeer], empty: String) -> some View {
        sheetHead(prompt, count: String(peers.count))
        let columns = Present.peerColumns(for: peers)
        HStack(spacing: Metrics.columnGap) {
            Color.clear.frame(width: Metrics.stripeColumnWidth)
            columnLabel("session").frame(width: columns.session, alignment: .leading)
            columnLabel("focus").frame(maxWidth: .infinity, alignment: .leading)
            columnLabel("holding").frame(width: columns.holding, alignment: .leading)
            columnLabel("state").frame(width: columns.state, alignment: .leading)
            columnLabel("age").frame(width: columns.age, alignment: .trailing)
        }
        .frame(height: Metrics.columnHeaderHeight)
        .overlay(alignment: .bottom) { rule }
        if peers.isEmpty {
            emptyLine(empty)
        } else {
            ForEach(Array(peers.enumerated()), id: \.element.id) { index, peer in
                peerRow(peer, index: index, columns: columns)
            }
        }
    }

    private func peerRow(_ peer: HolyMannaPeer, index: Int, columns: HolyMannaPeerColumnWidths) -> some View {
        let selected = store.selectedPeerID == peer.agentID
        return HStack(alignment: .center, spacing: Metrics.columnGap) {
            stripe(peer.attention)
            Text(peer.displayName)
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
                .frame(width: columns.session, alignment: .leading)
                .help(peer.agentID)
            flowingText(
                Present.peerFocusText(peer).map { Text($0).foregroundColor(Palette.text) }
                    ?? Text("no focus declared").foregroundColor(Palette.faint),
                sub: peer.pulse?.activity
            )
            HStack(spacing: Metrics.s1) {
                ForEach(peer.holding) { held in
                    linkButton(held.id) { store.follow(.item(held.id)) }
                        .help(held.title)
                }
            }
            .lineLimit(1)
            .frame(width: columns.holding, alignment: .leading)
            pill(Present.attention(peer.attention), color: Palette.wordColor(forClass: peer.attention))
                .frame(width: columns.state, alignment: .leading)
            Text(peer.age ?? "")
                .foregroundStyle(Palette.faint)
                .lineLimit(1)
                .frame(width: columns.age, alignment: .trailing)
        }
        .frame(minHeight: Metrics.rowHeight)
        .background(rowBackground(selected: selected, hovered: hoveredRowID == peer.agentID, even: index % 2 == 1))
        .overlay(alignment: .leading) {
            if selected {
                Rectangle().fill(Palette.select).frame(width: Metrics.selectionEdgeWidth)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { store.selectPeer(peer.agentID) }
        .onHover { hovering in setHover(peer.agentID, hovering) }
    }

    private func claimRow(_ claim: HolyMannaCoordClaim, index: Int, columns: HolyMannaClaimColumnWidths) -> some View {
        let cell = Present.claimStateCell(claim)
        return HStack(alignment: .center, spacing: Metrics.columnGap) {
            stripe(Present.claimStripeClass(claim))
            flowingText(Text(claim.path).foregroundColor(Palette.text), sub: claim.reason)
                .help(claim.path)
            Text(claim.ownerAlias ?? claim.owner)
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
                .frame(width: columns.owner, alignment: .leading)
                .help(claim.owner)
            stateText(cell)
                .frame(width: columns.state, alignment: .leading)
            Text(Present.ago(claim.updatedAt))
                .foregroundStyle(Palette.faint)
                .lineLimit(1)
                .frame(width: columns.age, alignment: .trailing)
        }
        .frame(minHeight: Metrics.rowHeight)
        .background(rowBackground(selected: false, hovered: false, even: index % 2 == 1))
    }

    private func dropRow(_ drop: HolyMannaCoordDrop, index: Int, columns: HolyMannaDropColumnWidths) -> some View {
        HStack(alignment: .center, spacing: Metrics.columnGap) {
            stripe("muted")
            Text(Present.dropFromText(drop))
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
                .frame(width: columns.from, alignment: .leading)
            flowingText(Text(drop.paths.joined(separator: ", ")).foregroundColor(Palette.text), sub: drop.note)
            Text(Present.ago(drop.createdAt))
                .foregroundStyle(Palette.faint)
                .lineLimit(1)
                .frame(width: columns.age, alignment: .trailing)
        }
        .frame(minHeight: Metrics.rowHeight)
        .background(rowBackground(selected: false, hovered: false, even: index % 2 == 1))
    }

    private func needRow(_ need: HolyMannaCoordNeed, index: Int) -> some View {
        HStack(alignment: .center, spacing: Metrics.columnGap) {
            stripe("decision")
            flowingText(
                Text(need.key).foregroundColor(Palette.text),
                sub: [need.why, need.owner.map { "from \($0)" }].compactMap { $0 }.joined(separator: " · ")
            )
        }
        .frame(minHeight: Metrics.rowHeight)
        .background(rowBackground(selected: false, hovered: false, even: index % 2 == 1))
    }

    // MARK: - Debug sheet

    @ViewBuilder
    private var debugSheet: some View {
        if let state = store.state {
            let drift = state.drift
            sheetHead("manna debug", count: "")
            Grid(alignment: .topLeading, horizontalSpacing: Metrics.s3, verticalSpacing: Metrics.s1) {
                let driftLine = drift.source == "reconcile"
                    ? "\(drift.count) live · " + (drift.kinds.isEmpty
                        ? "clean"
                        : drift.kinds.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
                    : "\(drift.count) from file"
                debugRow("drift", driftLine)
                debugRow(
                    "board",
                    "\(state.total) rows · workflow \(state.board.workflow ?? "unknown")"
                        + (state.board.boardID.map { " · \($0)" } ?? "")
                        + " · \(state.board.orderCount ?? 0) in handoff order · issues written \(Present.ago(state.board.issuesModifiedAt)) ago"
                )
                debugRow(
                    "repo",
                    state.git.isRepo
                        ? "\(state.git.branch ?? "(detached)") / HEAD \(state.git.head ?? "?") / \(state.git.dirtyPaths) dirty"
                        : "not a git repository"
                )
                debugRow("coord", "\(state.peers.count) rows")
                debugRow("root", state.root)
                debugRow("actor", store.actorID ?? "not yet minted")
            }
            .padding(.vertical, Metrics.s2)

            let findings = drift.findings.filter { finding in
                let needle = store.grep.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !needle.isEmpty else { return true }
                return "\(finding.kind) \(finding.issueID ?? "") \(finding.detail ?? "") \(finding.evidence ?? "") \(finding.proposedFix ?? "")"
                    .lowercased().contains(needle)
            }
            sheetHead("manna reconcile", count: String(findings.count))
            if findings.isEmpty {
                emptyLine("No findings.")
            } else {
                ForEach(Array(findings.enumerated()), id: \.offset) { index, finding in
                    HStack(alignment: .center, spacing: Metrics.columnGap) {
                        stripe("decision")
                        Text(finding.kind).foregroundStyle(Palette.faint).lineLimit(1)
                        if let issueID = finding.issueID {
                            linkButton(issueID) { store.follow(.item(issueID)) }
                        }
                        flowingText(
                            Text(finding.detail ?? "").foregroundColor(Palette.text)
                                + Text(finding.evidence.map { " (\($0))" } ?? "").foregroundColor(Palette.faint),
                            sub: finding.proposedFix.map { "fix: \($0)" },
                            subOnNewLine: true
                        )
                    }
                    .frame(minHeight: Metrics.rowHeight)
                    .background(rowBackground(selected: false, hovered: false, even: index % 2 == 1))
                }
            }
        } else {
            buildingLine(store.boardFailure ?? "reading the board…", failed: store.boardFailure != nil)
        }
    }

    private func debugRow(_ key: String, _ value: String) -> some View {
        GridRow {
            Text(key)
                .foregroundStyle(Palette.muted)
                .frame(width: Metrics.debugLabelWidth, alignment: .leading)
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        if let peer = store.selectedPeer {
            inspectorScroll { peerInspector(peer) }
        } else if let item = store.selectedItem {
            inspectorScroll { itemInspector(item) }
        } else if store.selectedPeerID != nil {
            emptyLine("that session is no longer on the board").padding(Metrics.s4)
        } else if store.selectedItemID != nil, store.state != nil {
            emptyLine("that item is no longer on the board").padding(Metrics.s4)
        } else {
            emptyLine("select a row").padding(Metrics.s4)
        }
    }

    /// The action row rides the bottom (margin-top: auto) when the content is
    /// short and scrolls with it when it is long.
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

    @ViewBuilder
    private func itemInspector(_ item: HolyMannaBoardItem) -> some View {
        HStack(spacing: Metrics.s2) {
            Text(item.id)
            pill(Present.label(item.effective), color: Palette.wordColor(forClass: item.effective))
            if let order = item.order {
                Text("#\(order + 1)")
            }
            if item.kind != "item" {
                Text(item.kind)
            }
        }
        .foregroundStyle(Palette.muted)
        .lineLimit(1)

        summaryBlock

        Text(item.title)
            .font(mono(Metrics.headingSize, weight: .semibold))
            .lineSpacing(Metrics.headingSize * 0.4)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)

        if let digest = item.digest, !digest.isEmpty {
            Text(digest)
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }

        if let description = item.description, !description.isEmpty {
            Text(description)
                .foregroundStyle(Palette.muted)
                .lineSpacing(Metrics.bodySize * (Metrics.bodyLineHeight - 1))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }

        itemMeta(item)

        Spacer(minLength: 0)

        VStack(alignment: .leading, spacing: Metrics.s2) {
            HolyMannaFlowLayout(spacing: Metrics.s3) {
                Text("copy:").foregroundStyle(Palette.muted)
                if item.prompt?.isEmpty == false {
                    copyButton("handoff") { store.handoffCopy(for: item) }
                }
                copyButton("id") { (item.id, item.id) }
                copyButton("show cmd") {
                    ("agent-do manna show \(item.id)", "agent-do manna show \(item.id)")
                }
            }
            let mutations = store.availableMutations(for: item)
            if !mutations.isEmpty {
                HolyMannaFlowLayout(spacing: Metrics.s3) {
                    Text("act:").foregroundStyle(Palette.muted)
                    ForEach(mutations) { mutation in
                        Button {
                            store.requestMutation(mutation)
                        } label: {
                            Text("[\(mutation.verb)]")
                                .foregroundStyle(mutation.isDestructive || mutation.verb == "abandon" ? Palette.red : Palette.green)
                        }
                        .buttonStyle(.plain)
                        .disabled(store.isMutating)
                        .help(mutation.confirmationTitle)
                    }
                }
            }
        }
        .padding(.top, Metrics.s2)
        .overlay(alignment: .top) { rule }
    }

    /// AI summary: set apart between two rules, labeled for what it is,
    /// collapsible, its open state remembered.
    private var summaryBlock: some View {
        VStack(alignment: .leading, spacing: Metrics.s2) {
            Button {
                summaryOpen.toggle()
            } label: {
                columnLabel(summaryOpen ? "▾ AI summary" : "▸ AI summary")
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if summaryOpen {
                Group {
                    if store.isDigestLoading {
                        Text("writing…").foregroundStyle(Palette.faint)
                    } else if let digest = store.digestText {
                        VStack(alignment: .leading, spacing: Metrics.s2) {
                            ForEach(Array(digest.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                                Text(paragraph)
                                    .foregroundStyle(Palette.text)
                                    .lineSpacing(Metrics.bodySize * 0.5)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                            if let model = store.digestModel {
                                Text("\(model)\(store.digestWasCached ? " · cached" : "")")
                                    .foregroundStyle(Palette.faint)
                            }
                        }
                    } else {
                        Text(store.digestFailure ?? "no summary")
                            .foregroundStyle(Palette.faint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.vertical, Metrics.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { rule }
        .overlay(alignment: .bottom) { rule }
    }

    private func itemMeta(_ item: HolyMannaBoardItem) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: Metrics.s2, verticalSpacing: Metrics.s1) {
            metaRow("track") {
                metaValue(Present.shortTrack(item.trackTitle).isEmpty ? "—" : Present.shortTrack(item.trackTitle))
            }
            if let createdAt = item.createdAt {
                metaRow("filed") {
                    (Text(Present.formatDate(createdAt)).foregroundColor(Palette.text)
                        + Text(" \(Present.ago(createdAt)) ago").foregroundColor(Palette.faint))
                        .fontWeight(.medium)
                }
            }
            metaRow("touched") {
                (Text(Present.formatDate(item.updatedAt)).foregroundColor(Palette.text)
                    + Text(" \(Present.ago(item.updatedAt)) ago").foregroundColor(Palette.faint))
                    .fontWeight(.medium)
            }
            if let source = item.source, !source.isEmpty {
                metaRow("source") { metaValue(source) }
            }
            if let claimant = item.claimant {
                metaRow("claimed by") {
                    claimantText(claimant)
                        .fontWeight(.medium)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !item.blockers.isEmpty {
                metaRow("waits on") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(item.blockers) { blocker in
                            let cls = blocker.status == "blocked" ? "waiting" : blocker.status
                            (Text(blocker.id).foregroundColor(Palette.blue)
                                + Text(" \(Present.label(cls)) ").foregroundColor(Palette.wordColor(forClass: cls))
                                + Text(blocker.title).foregroundColor(Palette.text))
                                .fontWeight(.medium)
                                .fixedSize(horizontal: false, vertical: true)
                                .contentShape(Rectangle())
                                .onTapGesture { store.selectItem(blocker.id) }
                                .help("open \(blocker.id)")
                        }
                    }
                }
            }
            if !item.dependents.isEmpty {
                metaRow("unblocks") {
                    HolyMannaFlowLayout(spacing: Metrics.s1) {
                        ForEach(item.dependents, id: \.self) { dependent in
                            linkButton(dependent) { store.selectItem(dependent) }
                        }
                    }
                    .fontWeight(.medium)
                }
            }
            metaRow("commits") {
                if item.commits.isEmpty {
                    Text("none yet").foregroundStyle(Palette.faint)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(item.commits) { commit in
                            (Text(commit.sha).foregroundColor(Palette.amber)
                                + Text(" \(Present.clip(commit.subject, Metrics.commitSubjectCharacters)) ").foregroundColor(Palette.text)
                                + Text(Present.ago(commit.at)).foregroundColor(Palette.faint))
                                .fontWeight(.medium)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if let prompt = item.prompt, !prompt.isEmpty {
                metaRow("handoff") {
                    Text(prompt).foregroundStyle(Palette.faint).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func metaRow<Value: View>(_ label: String, @ViewBuilder value: () -> Value) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(Palette.muted)
                .frame(width: Metrics.metaLabelWidth, alignment: .leading)
            value()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metaValue(_ text: String) -> some View {
        Text(text)
            .fontWeight(.medium)
            .foregroundStyle(Palette.text)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    @ViewBuilder
    private func peerInspector(_ peer: HolyMannaPeer) -> some View {
        HStack(spacing: Metrics.s2) {
            pill(Present.attention(peer.attention), color: Palette.wordColor(forClass: peer.attention))
            Text([peer.runtime, peer.role].compactMap { $0 }.joined(separator: " · "))
        }
        .foregroundStyle(Palette.muted)
        .lineLimit(1)

        Text(peer.displayName)
            .font(mono(Metrics.headingSize, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)

        if let goal = peer.goal, !goal.isEmpty {
            Text(goal).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
        }
        if let prompt = peer.pulse?.latestPrompt, !prompt.isEmpty {
            Text("“\(prompt)”")
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }

        Grid(alignment: .topLeading, horizontalSpacing: Metrics.s2, verticalSpacing: Metrics.s1) {
            metaRow("session") { metaValue(peer.agentID) }
            metaRow("liveness") {
                (Text(peer.status).foregroundColor(Palette.wordColor(forClass: peer.status))
                    + Text(" \(peer.age ?? "")").foregroundColor(Palette.text))
                    .fontWeight(.medium)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let pulse = peer.pulse, let status = pulse.status {
                metaRow("pulse") {
                    (Text(status).foregroundColor(Palette.text)
                        + Text(pulse.activity.map { " · \($0)" } ?? "").foregroundColor(Palette.text)
                        + Text(pulse.updatedAt.map { " \(Present.ago($0)) ago" } ?? "").foregroundColor(Palette.faint))
                        .fontWeight(.medium)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !peer.holding.isEmpty {
                metaRow("holding") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(peer.holding) { held in
                            (Text(held.id).foregroundColor(Palette.blue)
                                + Text(" \(held.title)").foregroundColor(Palette.text))
                                .fontWeight(.medium)
                                .fixedSize(horizontal: false, vertical: true)
                                .contentShape(Rectangle())
                                .onTapGesture { store.follow(.item(held.id)) }
                                .help("open \(held.id)")
                        }
                    }
                }
            }
            if !peer.paths.isEmpty {
                metaRow("paths") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(peer.paths, id: \.self) { path in
                            metaValue(path)
                        }
                    }
                }
            }
        }

        Spacer(minLength: 0)

        VStack(alignment: .leading, spacing: Metrics.s2) {
            HolyMannaFlowLayout(spacing: Metrics.s3) {
                Text("copy:").foregroundStyle(Palette.muted)
                copyButton("session") { (peer.agentID, peer.agentID) }
                copyButton("pulse cmd") {
                    ("agent-do coord pulse show \(peer.agentID)", "pulse cmd")
                }
            }
            HolyMannaFlowLayout(spacing: Metrics.s3) {
                Text("act:").foregroundStyle(Palette.muted)
                Button {
                    focusPeer(peer.agentID)
                } label: {
                    Text("[focus session]").foregroundStyle(Palette.green)
                }
                .buttonStyle(.plain)
                .help("Focus the Holy session joined by harness identity")
            }
        }
        .padding(.top, Metrics.s2)
        .overlay(alignment: .top) { rule }
    }

    // MARK: - Resizer, strip, toast

    private func resizer(currentWidth: CGFloat) -> some View {
        Rectangle()
            .fill(resizerHovered || inspectorDragStartWidth != nil ? Palette.lineStrong : Color.clear)
            .frame(width: Metrics.resizerWidth)
            .overlay(alignment: .leading) { Rectangle().fill(Palette.line).frame(width: 1) }
            .contentShape(Rectangle())
            .onHover { resizerHovered = $0 }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = inspectorDragStartWidth ?? currentWidth
                        inspectorDragStartWidth = start
                        let proposed = start - value.translation.width
                        storedInspectorWidth = Double(
                            min(Metrics.inspectorMaximumWidth, max(Metrics.inspectorMinimumWidth, proposed.rounded()))
                        )
                    }
                    .onEnded { _ in
                        inspectorDragStartWidth = nil
                    }
            )
            .onTapGesture(count: 2) {
                storedInspectorWidth = Double(Metrics.inspectorDefaultWidth)
            }
            .help("drag · double-click to reset")
    }

    /// The strip speaks only when something is off; silence is the health signal.
    private func strip(width: CGFloat) -> some View {
        HStack(spacing: Metrics.s4) {
            if let root = store.context.boardRoot {
                Text(root)
                    .foregroundStyle(Palette.faint)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(-1)
                    .help(root)
            }
            Spacer(minLength: 0)
            if let state = store.state {
                if store.selectedSheet == .coordination {
                    Text("\(state.peers.filter { $0.attention != "gone" }.count) here")
                    Text("\(state.git.dirtyPaths) dirty")
                } else {
                    if state.drift.source != "reconcile", !state.drift.present {
                        Text("reconcile unavailable").foregroundStyle(Palette.red)
                    }
                    if state.drift.count > 0 {
                        Text("drift \(state.drift.count)").foregroundStyle(Palette.amber)
                    }
                }
            }
            if let failure = store.mutationFailure ?? (store.state != nil ? store.boardFailure : nil) {
                Text(failure)
                    .foregroundStyle(Palette.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(failure)
                if store.mutationFailure != nil {
                    linkButton("dismiss") { store.clearNotice() }
                }
            }
            Button {
                store.selectSheet(store.selectedSheet == .debug ? .board : .debug)
            } label: {
                Text(store.selectedSheet == .debug ? "debug ▾" : "debug ▸")
                    .foregroundStyle(Palette.muted)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Palette.muted)
        .lineLimit(1)
        .padding(.horizontal, pagePadding(width))
        .frame(height: Metrics.stripHeight)
        .background(Palette.surface)
        .overlay(alignment: .top) { rule }
    }

    @ViewBuilder
    private var toast: some View {
        if let toast = store.toast {
            Text(toast)
                .foregroundStyle(Palette.text)
                .lineLimit(2)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Palette.raised)
                .overlay(Rectangle().stroke(Palette.lineStrong, lineWidth: 1))
                .padding(.trailing, Metrics.s4)
                .padding(.bottom, Metrics.stripHeight + Metrics.s3)
                .transition(.opacity)
        }
    }

    // MARK: - Estate surface

    private func estateSurface(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Metrics.s4) {
                HStack(spacing: 0) {
                    terminalCrumb
                    separator("›")
                    Text("estate")
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.text)
                }
                .lineLimit(1)
                .fixedSize()
                Spacer(minLength: 0)
                topbarRight
            }
            .padding(.horizontal, pagePadding(width))
            .frame(height: Metrics.topbarHeight)
            .padding(.top, Metrics.titlebarInset)
            .background(Palette.surface)
            .overlay(alignment: .bottom) { rule }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    let boards = store.sortedEstateBoards
                    sheetHead("manna serve --status", count: String(boards.count))
                    estateTotals
                    estateNote
                    if store.estate == nil {
                        buildingLine(store.estateFailure ?? "reading the estate…", failed: store.estateFailure != nil)
                    } else if let failure = store.estateFailure {
                        Text(failure).foregroundStyle(Palette.red).padding(.vertical, Metrics.s2)
                    }
                    if !boards.isEmpty {
                        estateTable(boards)
                    } else if store.estate != nil {
                        emptyLine("No boards registered yet.")
                    }
                }
                .padding(.horizontal, pagePadding(width))
                .padding(.bottom, Metrics.s5)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: Metrics.s4) {
                Spacer(minLength: 0)
                Text("[estate]")
                Text(store.estate?.registry ?? "")
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(Palette.muted)
            .padding(.horizontal, pagePadding(width))
            .frame(height: Metrics.stripHeight)
            .background(Palette.surface)
            .overlay(alignment: .top) { rule }
        }
    }

    @ViewBuilder
    private var estateTotals: some View {
        if let totals = store.estate?.totals {
            HStack(spacing: Metrics.s4) {
                (Text(String(totals.needsYou)).fontWeight(.semibold).foregroundColor(totals.needsYou > 0 ? Palette.amber : Palette.faint)
                    + Text(" need you").foregroundColor(Palette.muted))
                (Text(String(totals.working)).fontWeight(.semibold).foregroundColor(Palette.blue)
                    + Text(" working").foregroundColor(Palette.muted))
                (Text(String(totals.here)).fontWeight(.semibold).foregroundColor(Palette.text)
                    + Text(" sessions here").foregroundColor(Palette.muted))
            }
            .padding(.top, Metrics.s1)
            .padding(.horizontal, Metrics.s2)
            .padding(.bottom, Metrics.s2)
        }
    }

    /// Why the estate is on screen when a session was focused: the honest
    /// reason, with the directory that was tried.
    @ViewBuilder
    private var estateNote: some View {
        if store.context.boardRoot == nil {
            Text("the focused session has no repository or working directory · pick a board")
                .foregroundStyle(Palette.faint)
                .padding(.horizontal, Metrics.s2)
                .padding(.bottom, Metrics.s2)
        } else if let failure = store.boardFailure, store.state == nil {
            Text(failure)
                .foregroundStyle(Palette.amber)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Metrics.s2)
                .padding(.bottom, Metrics.s2)
        }
    }

    /// index.html's `table.boards`: full width, cells nowrap, numbers
    /// right; count columns fit their widest cell and the board name takes
    /// the rest of the measure.
    private func estateTable(_ boards: [HolyMannaEstateBoard]) -> some View {
        let widths = Present.estateColumns(for: boards)
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                columnLabel("board")
                    .padding(.horizontal, Metrics.s2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                estateHeader("needs you", width: widths.needsYou)
                estateHeader("working", width: widths.working)
                estateHeader("here", width: widths.here)
                estateHeader("active", width: widths.active)
                estateHeader("ready", width: widths.ready)
                estateHeader("blocked", width: widths.blocked)
                estateHeader("decision", width: widths.decision)
                estateHeader("dream", width: widths.dream)
                estateHeader("done", width: widths.done)
                estateHeader("drift", width: widths.drift)
                columnLabel("updated")
                    .padding(.horizontal, Metrics.s2)
                    .frame(width: widths.updated, alignment: .leading)
            }
            .padding(.vertical, Metrics.s1)
            .overlay(alignment: .bottom) { rule }
            ForEach(Array(boards.enumerated()), id: \.element.id) { index, board in
                estateRow(board, index: index, widths: widths)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func estateHeader(_ label: String, width: CGFloat) -> some View {
        columnLabel(label)
            .padding(.horizontal, Metrics.s2)
            .frame(width: width, alignment: .trailing)
    }

    private func estateRow(_ board: HolyMannaEstateBoard, index: Int, widths: HolyMannaEstateColumnWidths) -> some View {
        let coord: HolyMannaEstateCoord? = board.exists ? board.coord : nil
        return HStack(spacing: 0) {
            HStack(spacing: Metrics.s1) {
                Text(board.slug)
                    .foregroundStyle(board.exists ? Palette.blue : Palette.faint)
                if !board.exists {
                    Text("(missing)").foregroundStyle(Palette.faint)
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, Metrics.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(board.root)
            estateCell(coord?.needsYou, cls: "needs-user", width: widths.needsYou)
            estateCell(coord?.working, cls: "working", width: widths.working)
            estateCell(coord?.here, cls: "text", width: widths.here)
            estateCell(Present.estateStatusCount(board, "active", "in_progress"), cls: "active", width: widths.active)
            estateCell(Present.estateStatusCount(board, "ready", "open"), cls: "ready", width: widths.ready)
            estateCell(Present.estateStatusCount(board, "blocked"), cls: "waiting", width: widths.blocked)
            estateCell(board.exists ? board.decisions : nil, cls: "decision", width: widths.decision)
            estateCell(board.exists ? board.dreams : nil, cls: "dream", width: widths.dream)
            estateCell(Present.estateStatusCount(board, "done"), cls: "done", width: widths.done)
            estateCell(board.exists ? board.driftCount : nil, cls: "decision", width: widths.drift)
            Text(Present.formatDate(board.latestUpdate))
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .padding(.horizontal, Metrics.s2)
                .frame(width: widths.updated, alignment: .leading)
        }
        .frame(minHeight: Metrics.rowHeight)
        .background(rowBackground(selected: false, hovered: hoveredRowID == board.root, even: index % 2 == 1))
        .contentShape(Rectangle())
        .onTapGesture { store.selectEstateBoard(board) }
        .onHover { hovering in setHover(board.root, hovering) }
    }

    private func estateCell(_ count: Int?, cls: String, width: CGFloat) -> some View {
        let lit = (count ?? 0) > 0
        let color = cls == "text" ? Palette.text : Palette.wordColor(forClass: cls)
        return Text(Present.estateCellText(count))
            .foregroundStyle(lit ? color : Palette.faint)
            .lineLimit(1)
            .padding(.horizontal, Metrics.s2)
            .frame(width: width, alignment: .trailing)
    }

    // MARK: - Shared chrome

    private var rule: some View {
        Rectangle().fill(Palette.line).frame(height: 1)
    }

    private func separator(_ glyph: String) -> some View {
        Text(glyph)
            .foregroundStyle(Palette.faint)
            .padding(.horizontal, Metrics.s1)
    }

    private func linkButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .foregroundStyle(Palette.blue)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// `[label]` in link blue; `[copied]` in green for a moment after a press.
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

    /// `$ manna now 1`: the prompt in bold with a green `$ ` as chrome, the count faint.
    private func sheetHead(_ prompt: String, count: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s2) {
            (Text("$ ").foregroundColor(Palette.green)
                + Text(prompt).fontWeight(.semibold).foregroundColor(Palette.text))
            Text(count).foregroundStyle(Palette.faint)
        }
        .padding(.top, Metrics.s3)
        .padding(.bottom, Metrics.s1)
    }

    private func columnLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .tracking(Metrics.pillTracking)
            .foregroundStyle(Palette.faint)
            .lineLimit(1)
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(Palette.faint)
            .padding(Metrics.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Honest loading: a working line with a spinner and the seconds spent.
    private func buildingLine(_ text: String, failed: Bool) -> some View {
        TimelineView(.periodic(from: .now, by: spinnerInterval)) { timeline in
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s2) {
                if failed {
                    Text("○").foregroundStyle(Palette.red)
                } else {
                    let frame = Int(timeline.date.timeIntervalSinceReferenceDate / spinnerInterval) % spinnerFrames.count
                    Text(spinnerFrames[frame]).foregroundStyle(Palette.green)
                }
                Text(text)
                    .foregroundStyle(failed ? Palette.amber : Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if !failed, let since = buildingSince {
                    Text("· \(Int(timeline.date.timeIntervalSince(since)))s").foregroundStyle(Palette.faint)
                }
            }
            .padding(.vertical, Metrics.s2)
        }
        .onAppear { buildingSince = Date() }
        .onDisappear { buildingSince = nil }
    }

    /// A flex cell's text as one paragraph: the main text, then the
    /// page's `.sub` in faint, inline or on its own line. One Text wraps as
    /// prose; a row of Texts wraps each piece separately.
    private func flowingText(_ main: Text, sub: String?, subOnNewLine: Bool = false) -> some View {
        let subText: Text
        if let sub, !sub.isEmpty {
            subText = Text(subOnNewLine ? "\n" : "  ").foregroundColor(Palette.faint)
                + Text(sub).foregroundColor(Palette.faint)
        } else {
            subText = Text("")
        }
        return (main + subText)
            .lineSpacing(Metrics.bodySize * (Metrics.digestLineHeight - 1))
            .padding(.vertical, Metrics.s1)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `label attention · activity` with the goal faint on a second line.
    private func claimantText(_ claimant: HolyMannaClaimant) -> Text {
        let activity = claimant.pulse?.activity.flatMap { $0.isEmpty ? nil : $0 }
        let goal = claimant.goal.flatMap { $0.isEmpty ? nil : $0 }
        return Text(claimant.label).foregroundColor(Palette.text)
            + Text(" ")
            + Text(Present.attention(claimant.attention))
                .foregroundColor(Palette.wordColor(forClass: claimant.attention))
            + Text(activity.map { " · \($0)" } ?? "").foregroundColor(Palette.text)
            + Text(goal.map { "\n\($0)" } ?? "").foregroundColor(Palette.faint)
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

    // MARK: - Actions

    private func copy(_ text: String, note: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        store.showToast("copied \(note)")
        copiedLabel = label
        copiedResetTask?.cancel()
        copiedResetTask = Task {
            try? await Task.sleep(for: .seconds(Metrics.copiedFlashSeconds))
            guard !Task.isCancelled else { return }
            copiedLabel = nil
        }
    }

    private func focusPeer(_ identity: String) {
        if onFocusPeer(identity) {
            onDismiss()
        } else {
            store.showToast("no unique Holy session proves the harness identity \(identity)")
        }
    }

    /// ⌘F and "/" take the grep field; Escape inside it clears the filter
    /// instead of leaving the board. Everything else passes through, so the
    /// window's own Escape handling still returns to the terminal.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard store.isPresented else { return event }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let key = event.charactersIgnoringModifiers ?? ""
            if key.lowercased() == "f", flags == .command {
                store.requestGrepFocus()
                return nil
            }
            if key == "/", flags.isEmpty, !store.isGrepFocused {
                store.requestGrepFocus()
                return nil
            }
            if event.keyCode == escapeKeyCode, flags.isEmpty, store.isGrepFocused {
                grepFocused = false
                _ = store.consumeEscape()
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }
}


/// Left-to-right, wrapping: the inspector's bracketed verbs never break
/// inside a bracket when the column is narrow.
struct HolyMannaFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        return place(in: width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = place(in: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let origin = layout.origins[index]
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }

    private func place(in width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing / 2
                lineHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + lineHeight), origins)
    }
}
