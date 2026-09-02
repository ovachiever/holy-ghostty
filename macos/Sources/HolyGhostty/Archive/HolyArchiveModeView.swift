import AppKit
import SwiftUI

private enum HolyArchivePalette {
    static let background = Color(red: 0.039, green: 0.039, blue: 0.051)
    static let raisedInk = Color(red: 0.071, green: 0.071, blue: 0.090)
    static let paper = Color(red: 0.847, green: 0.851, blue: 0.824)
    static let metadata = Color(red: 0.553, green: 0.576, blue: 0.612)
    static let gold = Color(red: 0.878, green: 0.749, blue: 0.349)
    static let rule = Color.white.opacity(0.085)
    static let danger = Color(red: 0.95, green: 0.43, blue: 0.39)

    static func provider(_ harness: HolyArchiveHarness) -> Color {
        switch harness {
        case .claudeCode: Color(red: 0.84, green: 0.48, blue: 0.30)
        case .codex: Color(red: 0.38, green: 0.76, blue: 0.60)
        case .droid: Color(red: 0.48, green: 0.66, blue: 0.92)
        case .cursor: Color(red: 0.72, green: 0.63, blue: 0.92)
        case .opencode: Color(red: 0.45, green: 0.78, blue: 0.84)
        }
    }
}

struct HolyArchiveModeView: View {
    @ObservedObject var store: HolyArchiveModeStore
    let onDismiss: () -> Void
    @FocusState private var searchFocused: Bool
    @FocusState private var researchFocused: Bool
    @State private var annotationSheetPresented = false

    var body: some View {
        ZStack {
            HolyArchivePalette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                masthead
                filterBar
                Divider().overlay(HolyArchivePalette.rule)
                archiveBody
                statusBar
            }
            if store.chatIsPresented, store.chatIsFullscreen {
                researchPanel
                    .background(HolyArchivePalette.background)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .foregroundStyle(HolyArchivePalette.paper)
        .font(.system(size: 12))
        .sheet(isPresented: $annotationSheetPresented) { annotationSheet }
        .alert(
            "Archive needs attention",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) { store.clearError() }
        } message: {
            Text(store.errorMessage ?? "Unknown archive error.")
        }
        .onChange(of: store.annotationMode) { mode in annotationSheetPresented = mode != nil }
        .onChange(of: annotationSheetPresented) { if !$0 { store.cancelAnnotation() } }
        .onChange(of: store.searchFocusNonce) { _ in searchFocused = true }
        .onChange(of: store.researchFocusNonce) { _ in researchFocused = true }
    }

    private var masthead: some View {
        HStack(spacing: 14) {
            Button(action: onDismiss) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(HolyArchivePalette.metadata)
            .help("Return to workspace (Escape)")

            VStack(alignment: .leading, spacing: 1) {
                Text("ARCHIVE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2.4)
                    .foregroundStyle(HolyArchivePalette.gold)
                Text("Conversations across every harness")
                    .font(.system(size: 11))
                    .foregroundStyle(HolyArchivePalette.metadata)
            }

            Spacer(minLength: 20)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(searchFocused ? HolyArchivePalette.gold : HolyArchivePalette.metadata)
                TextField(
                    "Search, or use harness: project: after: before: #tag:",
                    text: $store.query
                )
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .font(.system(size: 12, design: .monospaced))
                .onSubmit { store.performSearch() }
                if !store.query.isEmpty {
                    Button { store.clearSearch() } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(HolyArchivePalette.metadata)
                }
            }
            .padding(.horizontal, 10)
            .frame(width: 510, height: 30)
            .background(HolyArchivePalette.raisedInk)
            .overlay(Rectangle().stroke(searchFocused ? HolyArchivePalette.gold.opacity(0.55) : HolyArchivePalette.rule))

            Button { store.toggleChat() } label: {
                Label("Research", systemImage: "text.magnifyingglass")
            }
            .buttonStyle(HolyArchiveTextButtonStyle(accented: store.chatIsPresented))
            .help("Archive researcher (?)")

            Menu {
                Button("Incremental update") { store.incrementalIndex() }
                Button("Full reindex") { store.fullReindex() }
                Button("Generate missing embeddings") { store.generateMissingEmbeddings() }
            } label: {
                Image(systemName: store.isIndexing ? "arrow.triangle.2.circlepath" : "ellipsis")
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .disabled(store.isIndexing)
            .help("Archive maintenance")
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.top, 27)
        .padding(.bottom, 10)
        .background(HolyArchivePalette.background)
    }

    @ViewBuilder
    private var filterBar: some View {
        if store.availableHarnesses.count > 1 {
            HStack(spacing: 16) {
                Text("FILTER")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(HolyArchivePalette.metadata)
                providerFilter(label: "All", harness: nil)
                ForEach(store.availableHarnesses) { harness in
                    providerFilter(label: harness.displayName, harness: harness)
                }
                Spacer()
                Text("\(store.totalParentCount.formatted()) sessions")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(HolyArchivePalette.metadata)
            }
            .padding(.horizontal, 18)
            .frame(height: 34)
        }
    }

    private func providerFilter(label: String, harness: HolyArchiveHarness?) -> some View {
        let active = store.providerFilter == harness
        return Button { store.setProviderFilter(harness) } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(active ? (harness.map(HolyArchivePalette.provider) ?? HolyArchivePalette.gold) : .clear)
                    .overlay(Circle().stroke(harness.map(HolyArchivePalette.provider) ?? HolyArchivePalette.metadata, lineWidth: 1))
                    .frame(width: 7, height: 7)
                if let harness { Image(systemName: harness.icon).font(.system(size: 9)) }
                Text(label)
                    .font(.system(size: 10, weight: active ? .semibold : .regular, design: .monospaced))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? HolyArchivePalette.paper : HolyArchivePalette.metadata)
    }

    private var archiveBody: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                leftColumn
                    .frame(width: geometry.size.width * 0.55)
                Rectangle().fill(HolyArchivePalette.rule).frame(width: 1)
                detailColumn
                    .frame(width: max(0, geometry.size.width * 0.45 - 1))
            }
        }
    }

    private var leftColumn: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                sectionHeader(store.headerTitle) {
                    if store.isSearching { ProgressView().controlSize(.small) }
                    if store.query.holyArchiveNilIfBlank != nil {
                        Button(store.sort.label) { store.cycleSort() }
                            .buttonStyle(.plain)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(HolyArchivePalette.metadata)
                    }
                }
                parentList
                    .frame(height: geometry.size.height * (store.chatIsPresented ? 0.48 : 0.60) - 30)
                Rectangle().fill(HolyArchivePalette.rule).frame(height: 1)
                if store.chatIsPresented {
                    researchPanel
                } else {
                    childPane
                }
            }
        }
    }

    private var parentList: some View {
        Group {
            if store.sessions.isEmpty, !store.isLoading {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(store.sessions) { session in
                                HolyArchiveSessionRow(
                                    session: session,
                                    childCount: childCount(for: session),
                                    selected: store.selectedSessionID == session.id
                                )
                                .id(session.id)
                                .contentShape(Rectangle())
                                .onTapGesture { store.selectParent(session.id) }
                                .contextMenu {
                                    Button("Copy resume command") {
                                        store.selectParent(session.id)
                                        store.copyResumeCommand()
                                    }
                                    Button("Resume in roster") {
                                        store.selectParent(session.id)
                                        store.resumeSelected()
                                    }
                                    Button("Open transcript") {
                                        store.selectParent(session.id)
                                        store.showTranscript()
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: store.selectedSessionID) { id in
                        if let id { withAnimation(.easeOut(duration: 0.14)) { proxy.scrollTo(id, anchor: .center) } }
                    }
                }
            }
        }
        .background(HolyArchivePalette.background)
    }

    private var childPane: some View {
        VStack(spacing: 0) {
            sectionHeader(
                store.query.holyArchiveNilIfBlank == nil
                    ? "Sub-agents (\(store.children.count))"
                    : "Matching Sub-agents (\(store.children.count))"
            ) {
                if store.children.isEmpty {
                    Text("explicit lineage only")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(HolyArchivePalette.metadata.opacity(0.65))
                }
            }
            if store.children.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                    Text("No explicit child sessions")
                }
                .foregroundStyle(HolyArchivePalette.metadata.opacity(0.55))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.children) { child in
                            HStack(spacing: 10) {
                                Text(child.extra["selected"] == "true" ? "★" : "  ")
                                    .foregroundStyle(HolyArchivePalette.gold)
                                Text(child.childType ?? "sub-agent")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(HolyArchivePalette.provider(child.harness))
                                    .frame(width: 118, alignment: .leading)
                                Rectangle().fill(HolyArchivePalette.rule).frame(width: 1, height: 19)
                                Text(child.firstPrompt.holyArchiveNilIfBlank ?? "(no prompt)")
                                    .lineLimit(2)
                                    .foregroundStyle(HolyArchivePalette.paper.opacity(0.8))
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(store.selectedChildID == child.id ? HolyArchivePalette.raisedInk : .clear)
                            .overlay(alignment: .leading) {
                                if store.selectedChildID == child.id {
                                    Rectangle().fill(HolyArchivePalette.gold).frame(width: 2)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { store.selectChild(child.id) }
                        }
                    }
                }
            }
        }
    }

    private var detailColumn: some View {
        Group {
            if store.transcriptIsPresented {
                transcriptView
            } else if let session = store.selectedSession {
                sessionDetail(session)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 26, weight: .ultraLight))
                    Text("Select a conversation")
                }
                .foregroundStyle(HolyArchivePalette.metadata)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(HolyArchivePalette.background)
    }

    private func sessionDetail(_ session: HolyArchiveSession) -> some View {
        VStack(spacing: 0) {
            sectionHeader("Session Details") {
                Button { store.generateTitle() } label: {
                    Label(store.isGeneratingTitle ? "Naming..." : "Name", systemImage: "sparkles")
                }
                .buttonStyle(.plain)
                .foregroundStyle(HolyArchivePalette.metadata)
                .disabled(store.isGeneratingTitle)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    detailLedger(session)
                    if !store.annotations.isEmpty { annotationLedger }
                    if let match = store.selectedSearchResult { matchLedger(match) }
                    excerpt("First Prompt", session.firstPrompt, limit: 2_000)
                    excerpt("Last Response", session.lastResponse, limit: session.isChild ? 1_000 : 2_000)
                    resumeLedger(session)
                }
            }
            detailActionBar(session)
        }
    }

    private func detailLedger(_ session: HolyArchiveSession) -> some View {
        VStack(spacing: 0) {
            ledgerRow("Harness") {
                Label(session.harness.displayName, systemImage: session.harness.icon)
                    .foregroundStyle(HolyArchivePalette.provider(session.harness))
            }
            ledgerRow("Type") {
                Text(session.isChild ? "SUB-AGENT · \(session.childType ?? "unknown")" : "PARENT SESSION · \(childCount(for: session)) sub-agents")
            }
            ledgerRow("Title") { Text(String(session.displayTitle.prefix(50))) }
            ledgerRow("Path") { Text(session.projectPath ?? "Unknown").textSelection(.enabled) }
            ledgerRow("Date") { Text(Self.longDate(session.activityAt)) }
            ledgerRow("Model") { Text(session.model ?? "Unknown") }
            ledgerRow("Session ID") {
                Text(session.id).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
            }
        }
    }

    private var annotationLedger: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ANNOTATIONS")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(HolyArchivePalette.metadata)
            let tags = store.annotations.filter { $0.kind == .tag }
            if !tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(tags) { tag in
                        Text("[\(tag.value)]")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(HolyArchivePalette.provider(store.selectedSession?.harness ?? .codex))
                            .contextMenu { Button("Delete tag", role: .destructive) { store.deleteAnnotation(tag) } }
                    }
                }
            }
            ForEach(store.annotations.filter { $0.kind == .note }) { note in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(Self.shortDate(note.timestamp))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(HolyArchivePalette.metadata)
                    Text(note.value).textSelection(.enabled)
                }
                .contextMenu { Button("Delete note", role: .destructive) { store.deleteAnnotation(note) } }
            }
        }
        .padding(16)
        .overlay(alignment: .bottom) { Rectangle().fill(HolyArchivePalette.rule).frame(height: 1) }
    }

    private func matchLedger(_ match: HolyArchiveSearchResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SEARCH MATCH")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.1)
                    .foregroundStyle(HolyArchivePalette.metadata)
                Spacer()
                Text("\(match.matchSource.rawValue) · \(match.score.formatted(.number.precision(.fractionLength(2))))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(HolyArchivePalette.gold)
            }
            Text(match.matchSnippet ?? "Matched indexed metadata.")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(HolyArchivePalette.paper.opacity(0.82))
                .textSelection(.enabled)
        }
        .padding(16)
        .background(HolyArchivePalette.gold.opacity(0.035))
        .overlay(alignment: .bottom) { Rectangle().fill(HolyArchivePalette.rule).frame(height: 1) }
    }

    private func excerpt(_ title: String, _ text: String, limit: Int) -> some View {
        let truncated = text.count > limit
        let value = String(text.prefix(limit)) + (truncated ? "\n... (truncated)" : "")
        return VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(HolyArchivePalette.metadata)
            Text(value.holyArchiveNilIfBlank ?? "(empty)")
                .font(.system(size: 12))
                .lineSpacing(3)
                .foregroundStyle(HolyArchivePalette.paper.opacity(0.88))
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .overlay(alignment: .bottom) { Rectangle().fill(HolyArchivePalette.rule).frame(height: 1) }
    }

    private func resumeLedger(_ session: HolyArchiveSession) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("RESUME COMMAND")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(HolyArchivePalette.metadata)
            Text(session.resumeCommand ?? "No safe resume command for this provider.")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(session.resumeCommand == nil ? HolyArchivePalette.metadata : HolyArchivePalette.paper)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.09, green: 0.16, blue: 0.27))
        }
        .padding(16)
    }

    private func detailActionBar(_ session: HolyArchiveSession) -> some View {
        HStack(spacing: 16) {
            Button("Copy command") { store.copyResumeCommand() }
                .disabled(session.resumeCommand == nil)
            Button("Resume in roster") { store.resumeSelected() }
                .disabled(session.resumeCommand == nil || session.harness.runtime == nil)
            Button("Transcript") { store.showTranscript() }
            Spacer()
            Button("Tag") {
                store.beginAnnotation(.tag)
                annotationSheetPresented = true
            }
            Button("Note") {
                store.beginAnnotation(.note)
                annotationSheetPresented = true
            }
        }
        .buttonStyle(HolyArchiveTextButtonStyle())
        .padding(.horizontal, 14)
        .frame(height: 42)
        .overlay(alignment: .top) { Rectangle().fill(HolyArchivePalette.rule).frame(height: 1) }
    }

    private var transcriptView: some View {
        VStack(spacing: 0) {
            sectionHeader("Transcript · \(store.selectedSession?.shortID ?? "")") {
                Button("Copy all") { store.copyTranscript() }.buttonStyle(.plain)
                Button("Find") { store.showTranscriptFind() }.buttonStyle(.plain)
                Button("Done") { store.closeTranscript() }.buttonStyle(.plain)
            }
            if store.transcriptFindIsPresented {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    TextField("Find in transcript", text: $store.transcriptFindQuery)
                        .textFieldStyle(.plain)
                        .onChange(of: store.transcriptFindQuery) { _ in store.recomputeFind() }
                        .onSubmit { store.nextFindMatch() }
                    Text(store.findMatchCount == 0 ? "no matches" : "\(store.findMatchIndex + 1)/\(store.findMatchCount)")
                        .font(.system(size: 9, design: .monospaced))
                    Button { store.nextFindMatch(-1) } label: { Image(systemName: "chevron.up") }
                    Button { store.nextFindMatch() } label: { Image(systemName: "chevron.down") }
                    Button { store.transcriptFindIsPresented = false } label: { Image(systemName: "xmark") }
                }
                .buttonStyle(.plain)
                .foregroundStyle(HolyArchivePalette.metadata)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(HolyArchivePalette.raisedInk)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        transcriptHeader
                        ForEach(Array(store.transcript.enumerated()), id: \.element.id) { index, message in
                            HolyArchiveTranscriptMessageView(
                                index: index + 1,
                                message: message,
                                find: store.transcriptFindQuery
                            )
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
                        Text("END OF TRANSCRIPT")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1.2)
                            .foregroundStyle(HolyArchivePalette.metadata)
                            .padding(18)
                    }
                }
                .coordinateSpace(name: "archive-transcript")
                .onPreferenceChange(HolyArchiveTranscriptFramePreferenceKey.self) { frames in
                    store.visibleTranscriptMessageID = frames
                        .filter { $0.value.maxY > 0 }
                        .min { left, right in
                            max(0, left.value.minY) < max(0, right.value.minY)
                        }?.key
                }
                .onChange(of: store.findMatchIndex) { _ in
                    if let id = transcriptTargetMessageID {
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
    }

    private var transcriptHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Session: \(store.selectedSession?.id ?? "Unknown")")
            Text("Path: \(store.selectedSession?.projectPath ?? "Unknown")")
            Text("Messages: \(store.transcript.count)")
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(HolyArchivePalette.metadata)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(HolyArchivePalette.rule).frame(height: 1) }
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

    private var researchPanel: some View {
        VStack(spacing: 0) {
            sectionHeader("Research \(store.selectedChatID == nil ? "(new)" : "")") {
                if store.isResearching {
                    ProgressView().controlSize(.small)
                    Text("thinking...")
                }
                Button { store.chatIsFullscreen.toggle() } label: {
                    Image(systemName: store.chatIsFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.plain)
                Button { store.toggleChat() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
            }
            if store.chatHistoryIsPresented { chatHistory }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(store.researchMessages) { message in
                            HolyArchiveResearchMessageView(message: message, onCitation: store.openCitation)
                                .id(message.id)
                        }
                        if store.researchMessages.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Ask across the archive")
                                    .font(.system(size: 15, weight: .medium))
                                Text("The researcher can scope projects and tags, search content, read full messages, follow pagination, and return exact citations with resume commands.")
                                    .foregroundStyle(HolyArchivePalette.metadata)
                                    .lineSpacing(3)
                            }
                            .padding(16)
                        }
                    }
                }
                .onChange(of: store.researchMessages.count) { _ in
                    if let id = store.researchMessages.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            chatControls
            HStack(spacing: 8) {
                TextField("Ask the archive researcher", text: $store.researchDraft)
                    .textFieldStyle(.plain)
                    .focused($researchFocused)
                    .onSubmit { store.submitResearch() }
                    .disabled(store.isResearching)
                Button("Send") { store.submitResearch() }
                    .buttonStyle(HolyArchiveTextButtonStyle(accented: true))
                    .disabled(store.isResearching || store.researchDraft.holyArchiveNilIfBlank == nil)
            }
            .padding(10)
            .background(HolyArchivePalette.raisedInk)
        }
    }

    private var chatControls: some View {
        HStack(spacing: 12) {
            Button("Copy") { store.copyResearchTranscript() }
            Button("New") { store.newChat() }
            Button("Recent") {
                store.refreshRecentChats()
                store.chatHistoryIsPresented.toggle()
            }
            Button("Delete", role: .destructive) { store.deleteSelectedChat() }
                .disabled(store.selectedChatID == nil)
            Spacer()
            TextField("Model", text: $store.researchModel)
                .textFieldStyle(.plain)
                .font(.system(size: 9, design: .monospaced))
                .frame(width: 90)
                .onChange(of: store.researchModel) { UserDefaults.standard.set($0, forKey: "holy.intelligence.deep.model") }
            Picker("", selection: $store.reasoningEffort) {
                ForEach(["low", "medium", "high", "xhigh"], id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(width: 72)
            .onChange(of: store.reasoningEffort) { UserDefaults.standard.set($0, forKey: "holy.archive.research.effort") }
        }
        .buttonStyle(.plain)
        .font(.system(size: 9, design: .monospaced))
        .foregroundStyle(HolyArchivePalette.metadata)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .overlay(alignment: .top) { Rectangle().fill(HolyArchivePalette.rule).frame(height: 1) }
    }

    private var chatHistory: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.recentChats) { chat in
                    Button { store.loadChat(chat.id) } label: {
                        HStack {
                            Text(chat.title).lineLimit(1)
                            Spacer()
                            Text(Self.shortDate(chat.updatedAt))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(HolyArchivePalette.metadata)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 150)
        .background(HolyArchivePalette.raisedInk)
        .overlay(Rectangle().stroke(HolyArchivePalette.rule))
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            if let progress = store.indexProgress {
                ProgressView(value: Double(progress.completed), total: Double(max(1, progress.total)))
                    .progressViewStyle(.linear)
                    .frame(width: 120)
                Text("\(progress.phase.rawValue): \(progress.detail)")
            } else if let status = store.statusMessage {
                Text(status)
            } else {
                Text("Return copy · R resume · T transcript · / search · ? research · Esc back")
            }
            if let semantic = store.semanticStatus {
                Rectangle().fill(HolyArchivePalette.rule).frame(width: 1, height: 12)
                Text(semantic).lineLimit(1)
            }
            Spacer()
            Text("HOLY DB · NATIVE")
                .tracking(1)
                .foregroundStyle(HolyArchivePalette.gold.opacity(0.72))
        }
        .font(.system(size: 9, design: .monospaced))
        .foregroundStyle(HolyArchivePalette.metadata)
        .padding(.horizontal, 14)
        .frame(height: 28)
        .overlay(alignment: .top) { Rectangle().fill(HolyArchivePalette.rule).frame(height: 1) }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("No sessions found")
                .font(.system(size: 17, weight: .medium))
            ForEach(store.registry.providers, id: \.harness) { provider in
                HStack(spacing: 8) {
                    Image(systemName: provider.harness.icon)
                        .foregroundStyle(HolyArchivePalette.provider(provider.harness))
                    Text(provider.harness.displayName)
                    Text(provider.sessionsDirectory.path)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(HolyArchivePalette.metadata)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: provider.isAvailable ? "checkmark.circle" : "xmark.circle")
                        .foregroundStyle(provider.isAvailable ? HolyArchivePalette.gold : HolyArchivePalette.metadata)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var annotationSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(store.annotationMode == .tag ? "Tag this session" : "Add a session note")
                .font(.system(size: 17, weight: .semibold))
            TextField(store.annotationMode?.placeholder ?? "Annotation", text: $store.annotationDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    store.saveAnnotation()
                    annotationSheetPresented = false
                }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { annotationSheetPresented = false }
                Button("Save") {
                    store.saveAnnotation()
                    annotationSheetPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(store.annotationDraft.holyArchiveNilIfBlank == nil)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func sectionHeader<Trailing: View>(
        _ title: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.05)
                .lineLimit(1)
            Spacer(minLength: 8)
            trailing()
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(HolyArchivePalette.metadata)
        }
        .foregroundStyle(HolyArchivePalette.metadata)
        .padding(.horizontal, 13)
        .frame(height: 30)
        .background(HolyArchivePalette.raisedInk.opacity(0.65))
        .overlay(alignment: .bottom) { Rectangle().fill(HolyArchivePalette.rule).frame(height: 1) }
    }

    private func ledgerRow<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(HolyArchivePalette.metadata)
                .frame(width: 82, alignment: .leading)
            content()
                .font(.system(size: 11))
                .foregroundStyle(HolyArchivePalette.paper)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) { Rectangle().fill(HolyArchivePalette.rule.opacity(0.55)).frame(height: 1) }
    }

    private func childCount(for session: HolyArchiveSession) -> Int {
        store.childCountsByParentID[session.id] ?? 0
    }

    private static func longDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

private struct HolyArchiveTranscriptFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private struct HolyArchiveSessionRow: View {
    let session: HolyArchiveSession
    let childCount: Int
    let selected: Bool
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 9) {
            Text(date)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(HolyArchivePalette.metadata)
                .frame(width: 74, alignment: .leading)
            Rectangle().fill(HolyArchivePalette.rule).frame(width: 1, height: 25)
            Image(systemName: session.harness.icon)
                .font(.system(size: 10))
                .foregroundStyle(HolyArchivePalette.provider(session.harness))
                .frame(width: 12)
            Text(String(session.projectName.prefix(12)))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(HolyArchivePalette.provider(session.harness).opacity(0.88))
                .frame(width: 86, alignment: .leading)
            Rectangle().fill(HolyArchivePalette.rule).frame(width: 1, height: 25)
            if childCount > 0 {
                Text("(\(childCount))")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(HolyArchivePalette.gold)
            }
            Text(session.displayTitle.replacingOccurrences(of: "\n", with: " "))
                .font(.system(size: 11, weight: session.summary == nil ? .regular : .semibold))
                .foregroundStyle(session.summary == nil ? HolyArchivePalette.paper.opacity(0.67) : HolyArchivePalette.paper)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(selected ? HolyArchivePalette.raisedInk : (hovered ? Color.white.opacity(0.025) : .clear))
        .overlay(alignment: .leading) {
            if selected { Rectangle().fill(HolyArchivePalette.gold).frame(width: 2) }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(HolyArchivePalette.rule.opacity(0.45)).frame(height: 1) }
        .onHover { hovered = $0 }
    }

    private var date: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: session.activityAt)
    }
}

private struct HolyArchiveTranscriptMessageView: View {
    let index: Int
    let message: HolyArchiveMessage
    let find: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("[\(index)]")
                Text(message.role.rawValue.uppercased())
                    .foregroundStyle(roleColor)
                Rectangle().fill(HolyArchivePalette.rule).frame(height: 1)
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            Text(highlighted)
                .font(.system(size: 12, design: .monospaced))
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .overlay(alignment: .bottom) { Rectangle().fill(HolyArchivePalette.rule).frame(height: 1) }
    }

    private var roleColor: Color {
        switch message.role {
        case .user: Color(red: 0.45, green: 0.82, blue: 0.57)
        case .assistant: Color(red: 0.82, green: 0.55, blue: 0.86)
        case .tool: Color(red: 0.50, green: 0.72, blue: 0.92)
        default: HolyArchivePalette.metadata
        }
    }

    private var highlighted: AttributedString {
        var result = AttributedString(message.content)
        guard !find.isEmpty else { return result }
        for range in HolyArchiveTranscriptFind.ranges(of: find, in: message.content) {
            guard let lower = AttributedString.Index(range.lowerBound, within: result),
                  let upper = AttributedString.Index(range.upperBound, within: result) else { continue }
            result[lower..<upper].backgroundColor = NSColor.systemYellow.withAlphaComponent(0.28)
            result[lower..<upper].foregroundColor = NSColor.white
        }
        return result
    }
}

private struct HolyArchiveResearchMessageView: View {
    let message: HolyArchiveResearchMessage
    let onCitation: (String) -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if message.toolCallJSON != nil || message.role == .tool {
                DisclosureGroup(isExpanded: $expanded) {
                    Text(message.content)
                        .font(.system(size: 9, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.top, 6)
                } label: {
                    Text(message.role == .tool ? "TOOL OUTPUT" : "TOOL CALL")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(HolyArchivePalette.metadata)
                }
                .contextMenu { Button("Copy") { copy(message.content) } }
            } else {
                Text(message.role == .user ? "YOU" : "ASSISTANT")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(message.role == .user ? HolyArchivePalette.gold : HolyArchivePalette.metadata)
                Text(message.content)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                if !message.citedSessionIDs.isEmpty {
                    HStack(spacing: 7) {
                        Text("REFS")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(HolyArchivePalette.metadata)
                        ForEach(message.citedSessionIDs, id: \.self) { id in
                            Button(String(id.prefix(8))) { onCitation(id) }
                                .buttonStyle(.plain)
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(HolyArchivePalette.gold)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(message.role == .user ? HolyArchivePalette.gold.opacity(0.025) : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(HolyArchivePalette.rule.opacity(0.55)).frame(height: 1) }
        .contextMenu { Button("Copy") { copy(message.content) } }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

private struct HolyArchiveTextButtonStyle: ButtonStyle {
    var accented = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(accented ? HolyArchivePalette.background : HolyArchivePalette.metadata)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(accented ? HolyArchivePalette.gold.opacity(configuration.isPressed ? 0.75 : 0.92) : HolyArchivePalette.raisedInk)
            .overlay(Rectangle().stroke(accented ? HolyArchivePalette.gold : HolyArchivePalette.rule))
    }
}
