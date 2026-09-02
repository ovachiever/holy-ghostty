import AppKit
import Foundation
import OSLog

enum HolyArchiveSort: String, CaseIterable, Sendable {
    case relevance
    case newest
    case oldest

    var label: String {
        switch self {
        case .relevance: "by relevance"
        case .newest: "newest first"
        case .oldest: "oldest first"
        }
    }
}

enum HolyArchiveAnnotationMode: Sendable {
    case tag
    case note

    var kind: HolyArchiveAnnotation.Kind { self == .tag ? .tag : .note }
    var placeholder: String {
        self == .tag ? "Enter tag name (e.g. breakthrough)" : "Enter note text"
    }
}

enum HolyArchiveNavigationPane: Sendable {
    case parents
    case children
    case detail
}

@MainActor
final class HolyArchiveModeStore: ObservableObject {
    static let logger = Logger(subsystem: "org.holyghostty.app", category: "HolyArchive")
    static let maximumDisplayedSessions = 500

    @Published private(set) var isPresented = false
    @Published private(set) var sessions: [HolyArchiveSession] = []
    @Published private(set) var children: [HolyArchiveSession] = []
    @Published private(set) var annotations: [HolyArchiveAnnotation] = []
    @Published private(set) var transcript: [HolyArchiveMessage] = []
    @Published private(set) var recentChats: [HolyArchiveResearchChat] = []
    @Published private(set) var researchMessages: [HolyArchiveResearchMessage] = []
    @Published private(set) var indexProgress: HolyArchiveIndexProgress?
    @Published private(set) var lastIndexReceipt: HolyArchiveIndexReceipt?
    @Published private(set) var isLoading = false
    @Published private(set) var isIndexing = false
    @Published private(set) var isSearching = false
    @Published private(set) var isResearching = false
    @Published private(set) var isGeneratingTitle = false
    @Published private(set) var totalParentCount = 0
    @Published private(set) var childCountsByParentID: [String: Int] = [:]
    @Published private(set) var semanticStatus: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var selectedSearchResult: HolyArchiveSearchResult?
    @Published private(set) var findMatchCount = 0
    @Published private(set) var findMatchIndex = 0

    @Published var query = ""
    @Published var providerFilter: HolyArchiveHarness?
    @Published var sort: HolyArchiveSort = .relevance
    @Published var selectedSessionID: String?
    @Published var selectedChildID: String?
    @Published var transcriptIsPresented = false
    @Published var transcriptFindIsPresented = false
    @Published var transcriptFindQuery = ""
    @Published var annotationMode: HolyArchiveAnnotationMode?
    @Published var annotationDraft = ""
    @Published var chatIsPresented = false
    @Published var chatIsFullscreen = false
    @Published var chatHistoryIsPresented = false
    @Published var researchDraft = ""
    @Published var selectedChatID: String?
    @Published var researchModel: String
    @Published var reasoningEffort: String
    @Published var searchFocusNonce = 0
    @Published var researchFocusNonce = 0
    @Published var visibleTranscriptMessageID: String?
    @Published private(set) var navigationPane: HolyArchiveNavigationPane = .parents

    let registry: HolyArchiveProviderRegistry
    private let repository: HolyArchiveRepository?
    private let indexer: HolyArchiveIndexer?
    private let search: HolyArchiveHybridSearch?
    private let researchAgent: HolyArchiveResearchAgent?
    private let resumeHandler: @MainActor (HolyArchiveSession) -> Bool
    private var searchResponse: HolyArchiveSearchResponse?
    private var didPrepare = false
    private var loadGeneration = 0
    private var lastLeftNavigationPane: HolyArchiveNavigationPane = .parents

    init(
        registry: HolyArchiveProviderRegistry = .init(),
        databaseURL: URL = HolyDatabasePaths.databaseURL,
        resumeHandler: @escaping @MainActor (HolyArchiveSession) -> Bool
    ) {
        self.registry = registry
        self.resumeHandler = resumeHandler
        self.researchModel = UserDefaults.standard.string(forKey: "holy.intelligence.deep.model")
            ?? HolyIntelligenceRole.deep.defaultModel
        self.reasoningEffort = UserDefaults.standard.string(forKey: "holy.archive.research.effort") ?? "xhigh"
        do {
            let repository = try HolyArchiveRepository(databaseURL: databaseURL)
            let search = HolyArchiveHybridSearch(repository: repository)
            let tools = HolyArchiveResearchTools(
                repository: repository, search: search, registry: registry
            )
            self.repository = repository
            self.indexer = HolyArchiveIndexer(repository: repository, registry: registry)
            self.search = search
            self.researchAgent = HolyArchiveResearchAgent(repository: repository, tools: tools)
        } catch {
            repository = nil
            indexer = nil
            search = nil
            researchAgent = nil
            errorMessage = "Archive storage could not open: \(error.localizedDescription)"
        }
    }

    var availableHarnesses: [HolyArchiveHarness] {
        registry.availableProviders.map(\.harness)
    }

    var selectedParent: HolyArchiveSession? {
        guard let selectedSessionID else { return nil }
        return sessions.first { $0.id == selectedSessionID }
    }

    var selectedSession: HolyArchiveSession? {
        if let selectedChildID, let child = children.first(where: { $0.id == selectedChildID }) { return child }
        return selectedParent
    }

    var headerTitle: String {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Search: \(query) (\(sessions.count) sessions, \(matchingChildCount) child matches · \(sort.label))"
        }
        if let providerFilter {
            return "\(providerFilter.displayName) (\(totalParentCount) sessions)"
        }
        if totalParentCount > Self.maximumDisplayedSessions {
            return "All Sessions (\(sessions.count)/\(totalParentCount) newest first)"
        }
        return "All Sessions (\(totalParentCount))"
    }

    var matchingChildCount: Int {
        searchResponse?.matchingChildrenByParentID.values.reduce(0) { $0 + $1.count } ?? 0
    }

    /// True while the list shows search results rather than the newest sessions.
    var isSearchActive: Bool {
        searchResponse != nil
    }

    var childCountForSelectedParent: Int {
        selectedParent.flatMap { childCountsByParentID[$0.id] } ?? 0
    }

    func present() {
        isPresented = true
        if !didPrepare {
            didPrepare = true
            prepare()
        } else {
            refreshSessions()
        }
    }

    func dismiss() {
        isPresented = false
        chatIsFullscreen = false
    }

    func clearError() {
        errorMessage = nil
    }

    func toggle() {
        if isPresented { dismiss() } else { present() }
    }

    func prepare() {
        guard repository != nil else { return }
        isLoading = true
        statusMessage = "Loading indexed sessions..."
        refreshSessions()
        // Nothing to discover means nothing to index or migrate.
        // Auto-ingest is opt-in until archive writes stop contending with the
        // UI's database writer (see the P0 contention item): the initial
        // 79k-session ingest into the shared file starves session persistence
        // behind SQLite's single WAL writer and freezes the app.
        if !registry.availableProviders.isEmpty,
           UserDefaults.standard.bool(forKey: "holy.archive.autoIndex") {
            incrementalIndex()
        }
        refreshRecentChats()
    }

    func refreshSessions() {
        guard let repository else { return }
        loadGeneration += 1
        let generation = loadGeneration
        let filter = providerFilter
        let activeResponse = searchResponse
        Task {
            do {
                let loaded: [HolyArchiveSession]
                let total: Int
                if let activeResponse {
                    loaded = Self.sorted(activeResponse.results, by: sort).map(\.session)
                    total = loaded.count
                } else {
                    let query = HolyArchiveSearchQuery(
                        text: "", harness: filter, rawHarness: nil,
                        project: nil, after: nil, before: nil, tags: []
                    )
                    let all = try await Task.detached {
                        try repository.sessions(query: query, parentsOnly: true)
                    }.value
                    total = all.count
                    loaded = Array(all.prefix(Self.maximumDisplayedSessions))
                }
                let childCounts = try await Task.detached {
                    try repository.childCounts(parentIDs: loaded.map(\.id))
                }.value
                guard generation == loadGeneration else { return }
                sessions = loaded
                totalParentCount = total
                childCountsByParentID = childCounts
                isLoading = false
                statusMessage = nil
                if selectedSessionID.flatMap({ id in loaded.first { $0.id == id } }) == nil {
                    selectedSessionID = loaded.first?.id
                }
                selectParent(selectedSessionID)
            } catch {
                isLoading = false
                fail("Loading the archive failed", error)
            }
        }
    }

    func incrementalIndex() {
        guard let indexer, let repository, !isIndexing else { return }
        isIndexing = true
        statusMessage = "Checking for new sessions..."
        Task {
            var receipt = await indexer.incrementalUpdate(maxAgeHours: HolyArchiveIndexer.startupWindowHours) { progress in
                await MainActor.run { self.indexProgress = progress }
            }
            do {
                _ = try await Task.detached {
                    try HolyArchiveLegacySummaryImporter.migrate(repository: repository)
                }.value
            } catch {
                receipt.failures.append("Legacy title migration: \(error.localizedDescription)")
            }
            lastIndexReceipt = receipt
            indexProgress = nil
            isIndexing = false
            statusMessage = receipt.sessionsIndexed == 0
                ? "Archive is current."
                : "Indexed \(receipt.sessionsIndexed) new or changed sessions."
            if !receipt.failures.isEmpty {
                errorMessage = "Archive update completed with \(receipt.failures.count) failure(s): \(receipt.failures[0])"
            }
            await search?.invalidateCache()
            refreshSessions()
        }
    }

    func fullReindex() {
        guard let indexer, let repository, !isIndexing else { return }
        isIndexing = true
        statusMessage = "Rebuilding the native archive..."
        Task {
            var receipt = await indexer.fullReindex { progress in
                await MainActor.run { self.indexProgress = progress }
            }
            do {
                _ = try await Task.detached {
                    try HolyArchiveLegacySummaryImporter.migrate(repository: repository)
                }.value
            } catch {
                receipt.failures.append("Legacy title migration: \(error.localizedDescription)")
            }
            lastIndexReceipt = receipt
            indexProgress = nil
            isIndexing = false
            statusMessage = "Indexed \(receipt.sessionsIndexed) sessions, \(receipt.messagesIndexed) messages, and \(receipt.chunksCreated) chunks."
            if !receipt.failures.isEmpty {
                errorMessage = "Reindex completed with \(receipt.failures.count) failure(s): \(receipt.failures[0])"
            }
            await search?.invalidateCache()
            searchResponse = nil
            refreshSessions()
        }
    }

    func generateMissingEmbeddings() {
        guard let indexer, !isIndexing else { return }
        isIndexing = true
        Task {
            let receipt = await indexer.generateMissingEmbeddings { progress in
                await MainActor.run { self.indexProgress = progress }
            }
            lastIndexReceipt = receipt
            indexProgress = nil
            isIndexing = false
            statusMessage = "Generated \(receipt.embeddingsCreated) embeddings."
            errorMessage = receipt.failures.first
            await search?.invalidateCache()
        }
    }

    func performSearch() {
        guard let search, !isSearching else { return }
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            clearSearch()
            return
        }
        var effective = value
        if let providerFilter, HolyArchiveSearchParser.parse(value).harness == nil {
            effective += " harness:\"\(providerFilter.rawValue)\""
        }
        isSearching = true
        statusMessage = "Searching the archive..."
        Task {
            do {
                let response = try await search.search(effective, limit: 50)
                searchResponse = response
                semanticStatus = response.semanticStatus
                selectedSearchResult = response.results.first
                sort = .relevance
                isSearching = false
                statusMessage = response.results.isEmpty
                    ? "No sessions matched."
                    : "Found \(response.results.count) sessions in \(Int(response.elapsedMilliseconds)) ms."
                refreshSessions()
            } catch {
                isSearching = false
                fail("Search failed", error)
            }
        }
    }

    func clearSearch() {
        query = ""
        searchResponse = nil
        selectedSearchResult = nil
        semanticStatus = nil
        sort = .relevance
        refreshSessions()
    }

    func cycleProviderFilter() {
        let options: [HolyArchiveHarness?] = [nil] + availableHarnesses.map(Optional.some)
        let index = options.firstIndex { $0 == providerFilter } ?? 0
        providerFilter = options[(index + 1) % options.count]
        searchResponse = nil
        if query.holyArchiveNilIfBlank != nil { performSearch() } else { refreshSessions() }
    }

    func setProviderFilter(_ filter: HolyArchiveHarness?) {
        providerFilter = filter
        searchResponse = nil
        if query.holyArchiveNilIfBlank != nil { performSearch() } else { refreshSessions() }
    }

    func cycleSort() {
        guard searchResponse != nil else { return }
        let values = HolyArchiveSort.allCases
        let index = values.firstIndex(of: sort) ?? 0
        sort = values[(index + 1) % values.count]
        refreshSessions()
    }

    func selectParent(_ id: String?) {
        navigationPane = .parents
        lastLeftNavigationPane = .parents
        selectedSessionID = id
        selectedChildID = nil
        transcriptIsPresented = false
        transcriptFindIsPresented = false
        guard let id, let repository else {
            children = []
            annotations = []
            return
        }
        if let response = searchResponse {
            selectedSearchResult = response.results.first { $0.session.id == id }
            children = response.matchingChildrenByParentID[id] ?? []
        } else {
            selectedSearchResult = nil
            children = (try? repository.relatedChildren(of: id)) ?? []
        }
        reloadAnnotations()
    }

    func selectChild(_ id: String?) {
        navigationPane = .children
        lastLeftNavigationPane = .children
        selectedChildID = id
        transcriptIsPresented = false
        transcriptFindIsPresented = false
        reloadAnnotations()
    }

    func reloadAnnotations() {
        guard let id = selectedSession?.id, let repository else {
            annotations = []
            return
        }
        do {
            annotations = try repository.annotations(sessionID: id)
        } catch {
            fail("Loading annotations failed", error)
        }
    }

    func beginAnnotation(_ mode: HolyArchiveAnnotationMode) {
        guard selectedSession != nil else { return }
        annotationDraft = ""
        annotationMode = mode
    }

    func cancelAnnotation() {
        annotationDraft = ""
        annotationMode = nil
    }

    func saveAnnotation() {
        guard let repository, let session = selectedSession, let mode = annotationMode else { return }
        do {
            _ = try repository.addAnnotation(
                sessionID: session.id, kind: mode.kind, value: annotationDraft
            )
            statusMessage = "\(mode == .tag ? "Tag" : "Note") saved."
            cancelAnnotation()
            reloadAnnotations()
        } catch {
            fail("Saving the annotation failed", error)
        }
    }

    func deleteAnnotation(_ annotation: HolyArchiveAnnotation) {
        guard let repository else { return }
        do {
            try repository.deleteAnnotation(id: annotation.id)
            reloadAnnotations()
        } catch {
            fail("Deleting the annotation failed", error)
        }
    }

    func showTranscript() {
        guard let session = selectedSession, let repository else { return }
        transcriptIsPresented = true
        transcript = []
        visibleTranscriptMessageID = nil
        statusMessage = "Loading transcript..."
        let provider = registry.provider(for: session.harness)
        Task {
            do {
                var loaded = try await Task.detached {
                    try repository.messages(sessionID: session.id)
                }.value
                let nonEmpty = loaded.filter { $0.content.holyArchiveNilIfBlank != nil }.count
                if loaded.isEmpty || nonEmpty * 2 <= loaded.count,
                   let provider,
                   let parsed = try provider.parseSession(at: URL(fileURLWithPath: session.rawPath)) {
                    loaded = parsed.1
                }
                guard transcriptIsPresented, selectedSession?.id == session.id else { return }
                transcript = loaded
                statusMessage = loaded.isEmpty ? "No messages found." : nil
                recomputeFind()
            } catch {
                guard transcriptIsPresented else { return }
                fail("Loading the transcript failed", error)
            }
        }
    }

    func closeTranscript() {
        transcriptIsPresented = false
        transcriptFindIsPresented = false
        transcriptFindQuery = ""
        transcript = []
        visibleTranscriptMessageID = nil
        findMatchCount = 0
        findMatchIndex = 0
    }

    func showTranscriptFind() {
        guard transcriptIsPresented, !transcript.isEmpty else {
            statusMessage = "Transcript is still loading."
            return
        }
        transcriptFindIsPresented = true
        recomputeFind()
    }

    func recomputeFind() {
        let needle = transcriptFindQuery
        findMatchCount = transcript.reduce(0) {
            $0 + HolyArchiveTranscriptFind.ranges(of: needle, in: $1.content).count
        }
        findMatchIndex = findMatchCount == 0 ? 0 : min(findMatchIndex, findMatchCount - 1)
    }

    func nextFindMatch(_ direction: Int = 1) {
        guard findMatchCount > 0 else { return }
        findMatchIndex = (findMatchIndex + direction + findMatchCount) % findMatchCount
    }

    func copyResumeCommand() {
        guard let command = selectedSession?.resumeCommand else {
            errorMessage = "This provider has no safe native resume command."
            return
        }
        copy(command, success: "Resume command copied.")
    }

    func copyTranscript() {
        let rendered = transcript.map { "[\($0.role.rawValue.capitalized)]\n\($0.content)" }.joined(separator: "\n\n")
        guard !rendered.isEmpty else { return }
        copy(rendered, success: "Copied \(rendered.components(separatedBy: .newlines).count) transcript lines.")
    }

    func copyVisibleTranscriptMessage() {
        guard let message = visibleTranscriptMessageID.flatMap({ id in
            transcript.first { $0.id == id }
        }) ?? transcript.first else { return }
        copy(message.content, success: "Copied visible \(message.role.rawValue) message.")
    }

    func resumeSelected() {
        guard let session = selectedSession else { return }
        guard session.resumeCommand != nil, session.harness.runtime != nil else {
            errorMessage = "\(session.harness.displayName) does not expose a safe in-process resume target."
            return
        }
        if resumeHandler(session) {
            statusMessage = "Resumed \(session.shortID) in the roster."
            dismiss()
        } else {
            errorMessage = "Holy could not create the roster session. No alternate path was used."
        }
    }

    func generateTitle() {
        guard let session = selectedSession, let repository, !isGeneratingTitle else { return }
        isGeneratingTitle = true
        Task {
            do {
                let messages = try await Task.detached { try repository.messages(sessionID: session.id) }.value
                let transcript = Self.boundedTranscript(messages)
                let response = try await HolyIntelligenceRouter.shared.complete(
                    role: .fast,
                    prompt: """
                    Write a 6-8 word title for this coding session. Be specific about what was built or fixed. Use past tense and no punctuation at the end.

                    Examples:
                    - Added dark mode toggle to settings page
                    - Fixed auth token refresh race condition
                    - Built CSV export for analytics dashboard
                    - Debugged memory leak in worker pool

                    FULL SESSION TRANSCRIPT:
                    \(transcript)

                    Title:
                    """,
                    workingDirectory: session.projectPath
                )
                let title = Self.normalizedTitle(response.text)
                guard !title.isEmpty else { throw HolyIntelligenceError.emptyResponse }
                try repository.saveSummary(
                    sessionID: session.id, summary: title,
                    model: response.model, contentHash: session.contentHash
                )
                statusMessage = "Generated title: \(title)"
                isGeneratingTitle = false
                refreshSessions()
            } catch {
                isGeneratingTitle = false
                fail("Title generation failed", error)
            }
        }
    }

    func toggleChat() {
        if chatIsPresented {
            chatIsPresented = false
            chatIsFullscreen = false
        } else {
            chatIsPresented = true
            ensureChat()
        }
    }

    func showOrFocusChat() {
        if !chatIsPresented {
            chatIsPresented = true
            ensureChat()
        }
        researchFocusNonce += 1
    }

    func ensureChat() {
        if let selectedChatID { loadChat(selectedChatID); return }
        newChat()
    }

    func newChat() {
        guard let researchAgent else { return }
        Task {
            do {
                let chat = try await researchAgent.startChat(
                    model: researchModel,
                    reasoningEffort: reasoningEffort
                )
                selectedChatID = chat.id
                researchMessages = []
                researchDraft = ""
                chatHistoryIsPresented = false
                refreshRecentChats()
            } catch {
                fail("Creating a research chat failed", error)
            }
        }
    }

    func submitResearch() {
        guard let researchAgent, let chatID = selectedChatID, !isResearching else { return }
        let value = researchDraft.split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
        guard !value.isEmpty else { return }
        researchDraft = ""
        isResearching = true
        Task {
            _ = await researchAgent.runTurn(chatID: chatID, userText: value)
            isResearching = false
            loadChat(chatID)
            refreshRecentChats()
            if let repository, let chat = try? repository.chat(id: chatID) {
                selectedChatID = chat.id
            }
            if let answer = researchMessages.last(where: { $0.role == .assistant && $0.toolCallJSON == nil }),
               let id = HolyArchiveResearchAgent.pickRecommendedSession(
                    text: answer.content, citedIDs: answer.citedSessionIDs
               ) {
                selectRecommendedSession(id)
            }
        }
    }

    func loadChat(_ id: String) {
        guard let repository else { return }
        do {
            selectedChatID = id
            researchMessages = try repository.researchMessages(chatID: id)
            if let chat = try repository.chat(id: id) {
                researchModel = chat.model
                reasoningEffort = Self.effort(from: chat.metadataJSON)
            }
            chatHistoryIsPresented = false
        } catch {
            fail("Loading the research chat failed", error)
        }
    }

    func refreshRecentChats() {
        guard let repository else { return }
        do {
            recentChats = try repository.recentChats()
        } catch {
            fail("Loading recent chats failed", error)
        }
    }

    func deleteSelectedChat() {
        guard let repository, let selectedChatID else { return }
        do {
            try repository.deleteChat(id: selectedChatID)
            self.selectedChatID = nil
            researchMessages = []
            refreshRecentChats()
            newChat()
        } catch {
            fail("Deleting the chat failed", error)
        }
    }

    func copyResearchTranscript() {
        let visible = researchMessages.filter { $0.role == .user || ($0.role == .assistant && $0.toolCallJSON == nil) }
            .map { "\($0.role == .user ? "You" : "Assistant")\n\($0.content)" }
            .joined(separator: "\n\n")
        copy(visible, success: "Research transcript copied.")
    }

    func openCitation(_ id: String) {
        selectRecommendedSession(id)
        chatIsPresented = false
        chatIsFullscreen = false
    }

    func handleEscape() -> Bool {
        if transcriptFindIsPresented {
            transcriptFindIsPresented = false
            transcriptFindQuery = ""
            recomputeFind()
            return true
        }
        if chatIsFullscreen { chatIsFullscreen = false; return true }
        if chatIsPresented { chatIsPresented = false; return true }
        if annotationMode != nil { cancelAnnotation(); return true }
        if transcriptIsPresented { closeTranscript(); return true }
        if searchResponse != nil || query.holyArchiveNilIfBlank != nil { clearSearch(); return true }
        return false
    }

    func handleKeyEquivalent(_ event: NSEvent, textInputActive: Bool) -> Bool {
        guard event.type == .keyDown else { return false }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let characters = event.characters ?? ""
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])

        if event.keyCode == 53, flags.isEmpty {
            if !handleEscape() { dismiss() }
            return true
        }
        if flags == .control {
            switch key {
            case "t" where !chatIsPresented:
                beginAnnotation(.tag)
                return true
            case "n" where chatIsPresented:
                newChat()
                return true
            case "n":
                beginAnnotation(.note)
                return true
            case "r", "h":
                guard chatIsPresented else { break }
                refreshRecentChats()
                chatHistoryIsPresented.toggle()
                return true
            case "y" where chatIsPresented:
                copyResearchTranscript()
                return true
            default: break
            }
        }
        if transcriptFindIsPresented, textInputActive, flags.isEmpty {
            if event.keyCode == 125 { nextFindMatch(); return true }
            if event.keyCode == 126 { nextFindMatch(-1); return true }
        }
        if key == "z", flags.isEmpty, chatIsPresented {
            chatIsFullscreen.toggle()
            return true
        }
        if textInputActive { return false }
        if event.keyCode == 48 {
            if flags.isEmpty { switchListPane(); return true }
            if flags == .shift { toggleDetailPane(); return true }
        }
        if event.keyCode == 36, flags.isEmpty {
            copyResumeCommand()
            return true
        }
        if characters == "?" || (key == "/" && flags == .shift) {
            showOrFocusChat()
            return true
        }
        if key == "/", flags.isEmpty {
            if transcriptIsPresented { showTranscriptFind() } else {
                searchFocusNonce += 1
            }
            return true
        }
        if key == "n", transcriptFindIsPresented {
            nextFindMatch(flags.contains(.shift) ? -1 : 1)
            return true
        }
        guard flags.isEmpty else { return false }
        if !transcriptIsPresented {
            switch event.keyCode {
            case 125: return moveSelection(by: 1)
            case 126: return moveSelection(by: -1)
            case 115: return moveSelectionToBoundary(last: false)
            case 119: return moveSelectionToBoundary(last: true)
            case 116: return moveSelection(by: -10)
            case 121: return moveSelection(by: 10)
            default: break
            }
            if key == "j" { return moveSelection(by: 1) }
            if key == "k" { return moveSelection(by: -1) }
        }
        switch key {
        case "q": dismiss()
        case "r": resumeSelected()
        case "t": showTranscript()
        case "y", "a":
            guard transcriptIsPresented else { return false }
            copyTranscript()
        case "c" where transcriptIsPresented: copyVisibleTranscriptMessage()
        case "f": cycleProviderFilter()
        case "s": cycleSort()
        case "i": incrementalIndex()
        default: return false
        }
        return true
    }

    private func switchListPane() {
        guard !chatIsPresented else { return }
        if navigationPane == .children || children.isEmpty {
            selectParent(selectedSessionID ?? sessions.first?.id)
        } else {
            selectChild(selectedChildID ?? children.first?.id)
        }
    }

    private func toggleDetailPane() {
        if navigationPane == .detail {
            navigationPane = lastLeftNavigationPane
        } else {
            lastLeftNavigationPane = navigationPane
            navigationPane = .detail
        }
    }

    @discardableResult
    private func moveSelection(by offset: Int) -> Bool {
        guard navigationPane != .detail else { return false }
        let ids = navigationPane == .children ? children.map(\.id) : sessions.map(\.id)
        guard !ids.isEmpty else { return false }
        let selectedID = navigationPane == .children ? selectedChildID : selectedSessionID
        let current = selectedID.flatMap(ids.firstIndex(of:)) ?? 0
        let target = min(max(0, current + offset), ids.count - 1)
        if navigationPane == .children { selectChild(ids[target]) } else { selectParent(ids[target]) }
        return true
    }

    @discardableResult
    private func moveSelectionToBoundary(last: Bool) -> Bool {
        guard navigationPane != .detail else { return false }
        let ids = navigationPane == .children ? children.map(\.id) : sessions.map(\.id)
        guard let id = last ? ids.last : ids.first else { return false }
        if navigationPane == .children { selectChild(id) } else { selectParent(id) }
        return true
    }

    private func selectRecommendedSession(_ id: String) {
        guard let repository else { return }
        do {
            guard let session = try repository.session(id: id) else { return }
            let parentID = session.parentID ?? session.id
            guard let parent = session.isChild ? try repository.session(id: parentID) : session else { return }
            searchResponse = nil
            query = ""
            if let existing = sessions.firstIndex(where: { $0.id == parent.id }) {
                sessions[existing] = parent
            } else {
                sessions.insert(parent, at: 0)
                if sessions.count > Self.maximumDisplayedSessions { sessions.removeLast() }
            }
            selectedSessionID = parentID
            selectParent(parentID)
            if session.isChild { selectedChildID = session.id; reloadAnnotations() }
            statusMessage = "Selected \(session.shortID)."
        } catch {
            fail("Opening the cited session failed", error)
        }
    }

    private func copy(_ value: String, success: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let wrote = pasteboard.writeObjects([value as NSString])
        if wrote, pasteboard.string(forType: .string) == value {
            statusMessage = success
        } else {
            errorMessage = "Failed to copy to the macOS pasteboard."
        }
    }

    private func fail(_ prefix: String, _ error: Error) {
        errorMessage = "\(prefix): \(error.localizedDescription)"
        Self.logger.error("\(prefix, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }

    private static func sorted(
        _ results: [HolyArchiveSearchResult],
        by sort: HolyArchiveSort
    ) -> [HolyArchiveSearchResult] {
        switch sort {
        case .relevance: results.sorted { $0.score > $1.score }
        case .newest: results.sorted { $0.session.activityAt > $1.session.activityAt }
        case .oldest: results.sorted { $0.session.activityAt < $1.session.activityAt }
        }
    }

    private static func boundedTranscript(_ messages: [HolyArchiveMessage]) -> String {
        let full = messages
            .filter { ($0.role == .user || $0.role == .assistant) && !$0.content.isEmpty }
            .map { "[\($0.role == .user ? "USER" : "ASSISTANT")]: \($0.content)" }
            .joined(separator: "\n\n")
        guard full.count > 80_000 else { return full }
        return String(full.prefix(40_000))
            + "\n\n[... transcript truncated ...]\n\n"
            + String(full.suffix(40_000))
    }

    private static func normalizedTitle(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
        return String(normalized.prefix(80))
    }

    private static func effort(from json: String) -> String {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "xhigh" }
        return object["reasoning_effort"] as? String ?? "xhigh"
    }
}
