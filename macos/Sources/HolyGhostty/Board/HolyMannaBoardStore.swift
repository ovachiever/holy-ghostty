import Foundation
import SwiftUI

/// Which face the board mode shows: the estate table (every registered
/// board) or one board's cockpit.
enum HolyMannaBoardSurface: Equatable, Sendable {
    case estate
    case board
}

@MainActor
final class HolyMannaBoardModeStore: ObservableObject {
    @Published private(set) var isPresented = false
    @Published private(set) var surface: HolyMannaBoardSurface = .board
    @Published var selectedSheet: HolyMannaBoardSheet = .board
    @Published var boardFilter: HolyMannaBoardFilter = .live
    /// A track id, `HolyMannaBoardPresentation.untrackedFilter`, or nil for every track.
    @Published var trackFilter: String?
    @Published var grep = "" { didSet { if grep != oldValue { clearAnswer() } } }
    @Published private(set) var state: HolyMannaStatePayload?
    @Published private(set) var estate: HolyMannaEstatePayload?
    @Published private(set) var boardFailure: String?
    @Published private(set) var estateFailure: String?
    /// A read of the focused board is in flight (the topbar's "reading…").
    @Published private(set) var isRefreshing = false
    @Published private(set) var isEstateRefreshing = false
    /// When the surface on screen last landed a read: the board's own stamp
    /// on the board, the estate's on the estate.
    @Published private(set) var lastRefreshedAt: Date?
    @Published var selectedItemID: String?
    @Published var selectedPeerID: String?
    @Published private(set) var actorID: String?
    @Published var pendingMutation: HolyMannaMutation?
    @Published private(set) var activeMutation: HolyMannaMutation?
    @Published private(set) var isMutating = false
    @Published private(set) var mutationMessage: String?
    @Published private(set) var mutationFailure: String?
    @Published private(set) var toast: String?
    @Published private(set) var digestText: String?
    @Published private(set) var digestModel: String?
    @Published private(set) var digestWasCached = false
    @Published private(set) var digestFailure: String?
    @Published private(set) var isDigestLoading = false
    /// Incremented when a key (⌘F, /) asks the grep field to take focus.
    @Published private(set) var grepFocusRequest = 0
    /// Mirrored from the view so key handling knows whether "/" is typing.
    @Published var isGrepFocused = false

    @Published private(set) var answer: HolyMannaBoardAnswer?
    @Published private(set) var askFailure: HolyMannaAskError?
    @Published private(set) var isAsking = false
    @Published var deepModel: String {
        didSet {
            UserDefaults.standard.set(deepModel, forKey: "holy.intelligence.deep.model")
            clearAnswer()
        }
    }
    @Published var workerRuntime: HolySessionRuntime {
        didSet {
            UserDefaults.standard.set(workerRuntime.rawValue, forKey: "holy.board.worker.runtime")
            workerModel = UserDefaults.standard.string(forKey: "holy.board.worker.\(workerRuntime.rawValue).model") ?? ""
        }
    }
    @Published var workerModel: String {
        didSet { UserDefaults.standard.set(workerModel, forKey: "holy.board.worker.\(workerRuntime.rawValue).model") }
    }
    @Published var pendingDispatch: HolyMannaWorkerDispatch?
    @Published private(set) var isDispatching = false
    @Published private(set) var dispatchNotice: String?
    private let asker: any HolyMannaBoardAsking
    private let askTimeout: Duration
    private let workerLauncher: (@MainActor (HolySessionLaunchSpec) throws -> UUID)?
    private var askTask: Task<Void, Never>?
    private var askDeadline: Task<Void, Never>?
    private var askGeneration = UUID()
    private var askingHash: String?

    private(set) var context = HolyMannaBoardContext(boardRoot: nil, remoteHost: nil)
    private let client: HolyMannaBoardClient
    private let prewarmer: any HolyMannaBoardPrewarming
    private let usageAssessmentProvider: () -> HolyClaudeUsageAssessment
    /// Every board read that lands is kept, keyed by host and root, so a
    /// board seen once shows instantly and refreshes behind its own rows.
    private var stateCache: [String: HolyMannaStatePayload] = [:]
    private var stateRefreshedAt: [String: Date] = [:]
    private var stateReadsInFlight: Set<String> = []
    private var estateRefreshedAt: Date?
    private var estateReadInFlight = false
    private var liveTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var digestCache: [String: HolyMannaPresentationResult] = [:]
    private var digestFailures: [String: String] = [:]

    init(
        client: HolyMannaBoardClient = .init(),
        asker: any HolyMannaBoardAsking = HolyMannaBoardAskService.shared,
        askTimeout: Duration = .seconds(60),
        workerLauncher: (@MainActor (HolySessionLaunchSpec) throws -> UUID)? = nil,
        digestService: any HolyMannaBoardDigesting = HolyMannaBoardDigestService.shared,
        prewarmer: (any HolyMannaBoardPrewarming)? = nil,
        usageAssessmentProvider: @escaping () -> HolyClaudeUsageAssessment = {
            .init(level: .normal, decidingBucket: nil, reason: nil)
        }
    ) {
        self.asker = asker
        self.askTimeout = askTimeout
        self.workerLauncher = workerLauncher
        self.deepModel = UserDefaults.standard.string(forKey: "holy.intelligence.deep.model") ?? "opus"
        let runtime = HolySessionRuntime(rawValue: UserDefaults.standard.string(forKey: "holy.board.worker.runtime") ?? "codex") ?? .codex
        self.workerRuntime = runtime
        self.workerModel = UserDefaults.standard.string(forKey: "holy.board.worker.\(runtime.rawValue).model") ?? ""
        self.client = client
        self.prewarmer = prewarmer ?? HolyMannaBoardPrewarmer(
            client: client,
            digestService: digestService
        )
        self.usageAssessmentProvider = usageAssessmentProvider
    }

    // MARK: Derived

    var selectedItem: HolyMannaBoardItem? {
        state?.item(id: selectedItemID)
    }

    var selectedPeer: HolyMannaPeer? {
        state?.peer(id: selectedPeerID)
    }

    var boardName: String {
        state?.name
            ?? context.boardRoot.map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? "board"
    }

    /// The estate in serve's order; missing boards trail, dimmed.
    var sortedEstateBoards: [HolyMannaEstateBoard] {
        HolyMannaBoardPresentation.estateRows(estate?.boards ?? [])
    }

    var boardSections: [HolyMannaBoardSectionModel] {
        guard let state else { return [] }
        var sections = HolyMannaBoardPresentation.sections(
            state: state,
            filter: boardFilter,
            track: trackFilter,
            grep: answer == nil ? grep : ""
        )
        if let answer {
            let cited = Set(answer.citedIDs)
            if !cited.isEmpty {
                sections = sections.map {
                    .init(id: $0.id, prompt: $0.prompt, items: $0.items.filter { cited.contains($0.id) },
                          emptyText: $0.emptyText, showsAge: $0.showsAge)
                }
            }
            sections.insert(.init(id: "cited", prompt: "manna cited",
                                  items: answer.citedIDs.compactMap { state.item(id: $0) },
                                  emptyText: "no board items cited", showsAge: false), at: 0)
        }
        return sections
    }

    var inboxRows: [HolyMannaInboxRowModel] {
        guard let state else { return [] }
        return HolyMannaBoardPresentation.inboxRows(state: state, grep: grep)
    }

    /// True while the board is being re-read on the visible cadence and its
    /// last read landed: the topbar's lit mark.
    var isLive: Bool {
        liveTask != nil && state != nil && boardFailure == nil
    }

    /// Badge-worthy board asks only. A ready backlog remains visible in the
    /// inbox without turning routine availability into alarm noise.
    var humanAttentionAskCount: Int {
        state?.asks.filter { ask in
            ask.verb != "launch" && ask.kind != "document" && ask.kind != "drop"
        }.count ?? 0
    }

    var humanAttentionPeerIDs: [String] {
        state?.peers.compactMap { peer in
            (peer.attention == "needs-user" || peer.attention == "failed") ? peer.agentID : nil
        } ?? []
    }

    // MARK: Presentation lifecycle

    func present(context: HolyMannaBoardContext) {
        isPresented = true
        surface = context.boardRoot == nil ? .estate : .board
        prepare(context: context)
        loadSelectedDigest()
        mutationMessage = nil
        mutationFailure = nil
        if surface == .estate {
            requestEstateRefresh(force: estate == nil)
        }
        startLiveRefresh()
    }

    func prepare(context: HolyMannaBoardContext) {
        let contextChanged = self.context != context
        self.context = context
        if contextChanged {
            clearAnswer()
            pendingDispatch = nil
            dispatchNotice = nil
            // A different root is a different board: show what was last
            // read for it, at once, and never the old board's rows under
            // the new board's name.
            state = stateCache[Self.cacheKey(context)]
            boardFailure = nil
            selectedPeerID = nil
            selectedItemID = nil
            digestText = nil
            digestFailure = nil
            lastRefreshedAt = stateRefreshedAt[Self.cacheKey(context)]
            if let state {
                selectedItemID = Self.defaultSelection(in: state)
            }
            // A session chosen while the board is on screen is a request
            // for that session's board; the estate returns only if it has none.
            if isPresented {
                surface = context.boardRoot == nil ? .estate : .board
                loadSelectedDigest()
            }
        }
        requestStateRefresh(force: contextChanged || state == nil)
        loadActorID()
    }

    func toggle(context: HolyMannaBoardContext) {
        if isPresented {
            dismiss()
        } else {
            present(context: context)
        }
    }

    func dismiss() {
        isPresented = false
        clearAnswer()
        pendingDispatch = nil
        pendingMutation = nil
        liveTask?.cancel()
        liveTask = nil
    }

    /// The crumb's "estate": the table of every board, the board kept warm.
    func showEstate() {
        surface = .estate
        selectedSheet = .board
        lastRefreshedAt = estateRefreshedAt
        requestEstateRefresh(force: estate == nil)
    }

    func selectSheet(_ sheet: HolyMannaBoardSheet) {
        selectedSheet = sheet
    }

    func selectFilter(_ filter: HolyMannaBoardFilter) {
        boardFilter = filter
    }

    func selectItem(_ id: String?) {
        selectedItemID = id
        if id != nil {
            selectedPeerID = nil
        }
        loadSelectedDigest()
    }

    func selectPeer(_ id: String?) {
        selectedPeerID = id
        if id != nil {
            selectedItemID = nil
            isDigestLoading = false
        }
    }

    /// Follow an inbox row to what it is about.
    func follow(_ target: HolyMannaAsk.Target) {
        switch target {
        case let .item(id):
            selectedSheet = .board
            selectItem(id)
        case let .peer(id):
            selectedSheet = .coordination
            selectPeer(id)
        case let .sheet(sheet):
            selectedSheet = sheet
        }
    }

    func selectEstateBoard(_ board: HolyMannaEstateBoard) {
        guard board.exists else { return }
        let next = context.selecting(boardRoot: board.root)
        if next != context {
            clearAnswer()
            pendingDispatch = nil
            dispatchNotice = nil
            context = next
            state = stateCache[Self.cacheKey(next)]
            boardFailure = nil
            selectedPeerID = nil
            selectedItemID = state.flatMap(Self.defaultSelection)
            digestText = nil
            digestFailure = nil
        }
        surface = .board
        selectedSheet = .board
        lastRefreshedAt = stateRefreshedAt[Self.cacheKey(context)]
        loadSelectedDigest()
        requestStateRefresh(force: state == nil)
    }

    // MARK: Keys

    func requestGrepFocus() {
        grepFocusRequest += 1
    }

    /// Escape while the grep field has focus clears the filter instead of
    /// leaving the board. Returns true when it consumed the key.
    func consumeEscape() -> Bool {
        guard isGrepFocused else { return false }
        grep = ""
        isGrepFocused = false
        return true
    }

    // MARK: Read-only questions and worker dispatch

    func clearAnswer() {
        askGeneration = UUID()
        askTask?.cancel()
        askDeadline?.cancel()
        askTask = nil
        askDeadline = nil
        answer = nil
        askFailure = nil
        isAsking = false
        askingHash = nil
    }

    /// Only Enter calls this. Editing grep never invokes a model.
    func submitQuestion() {
        clearAnswer()
        guard let state, boardFailure == nil, surface == .board else {
            askFailure = .unavailable("Read a board before asking a question.")
            return
        }
        let model = deepModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let request: HolyMannaBoardQuestion
        do {
            request = try HolyMannaBoardQuestion(question: grep, state: state, context: context,
                                                model: model.isEmpty ? "opus" : model)
        } catch {
            askFailure = .unavailable(error.localizedDescription)
            return
        }
        guard !request.question.isEmpty else { return }
        selectedSheet = .board
        isAsking = true
        askingHash = request.contentHash
        let generation = askGeneration
        askDeadline = Task { [weak self, askTimeout] in
            do { try await Task.sleep(for: askTimeout) } catch { return }
            guard let self, self.askGeneration == generation, self.isAsking else { return }
            self.clearAnswer()
            self.askFailure = .timedOut
        }
        askTask = Task { [weak self, asker] in
            do {
                let result = try await asker.answer(request)
                guard let self, self.askGeneration == generation else { return }
                self.askDeadline?.cancel()
                self.answer = result
                self.isAsking = false
                self.askingHash = nil
            } catch {
                guard let self, self.askGeneration == generation else { return }
                self.askDeadline?.cancel()
                self.isAsking = false
                self.askingHash = nil
                if case HolyMannaBoardClientError.timedOut = error {
                    self.askFailure = .timedOut
                } else if (error as NSError).code == NSURLErrorTimedOut {
                    self.askFailure = .timedOut
                } else {
                    self.askFailure = error as? HolyMannaAskError ?? .unavailable(error.localizedDescription)
                }
            }
        }
    }

    func workerRefusal(for item: HolyMannaBoardItem) -> String? {
        if let reason = HolyMannaWorkerDispatch.refusal(for: item, context: context) { return reason }
        if isDispatching { return "A worker is being opened." }
        if workerLauncher == nil { return "Worker launching is unavailable in this window." }
        if boardFailure != nil { return "Refresh the board before starting a worker." }
        return nil
    }

    func requestWorker(_ item: HolyMannaBoardItem) {
        if let reason = workerRefusal(for: item) { dispatchNotice = reason; return }
        pendingDispatch = .init(item: item, context: context,
                                profile: .init(runtime: workerRuntime, model: workerModel))
        dispatchNotice = nil
    }

    func confirmWorker() {
        guard let request = pendingDispatch, !isDispatching, let workerLauncher else { return }
        pendingDispatch = nil
        guard context == request.context else { return }
        isDispatching = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isDispatching = false }
            do {
                // A confirmation is permission for this exact item/handoff, not a
                // stale claim. Read canonical state again; never mutate it here.
                let fresh = try await self.client.state(for: request.context)
                guard self.context == request.context else { return }
                guard fresh.root == request.context.boardRoot,
                      let item = fresh.item(id: request.item.id) else {
                    throw HolyMannaAskError.unavailable("The item is no longer on this board.")
                }
                if let reason = HolyMannaWorkerDispatch.refusal(for: item, context: request.context) {
                    throw HolyMannaAskError.unavailable(reason)
                }
                guard item.prompt == request.item.prompt, item.handoffDigest == request.item.handoffDigest else {
                    throw HolyMannaAskError.unavailable("The handoff changed. Refresh and confirm the new work order.")
                }
                let launch = try request.launchSpec()
                _ = try workerLauncher(launch)
                self.dispatchNotice = "Worker session opened for \(item.id). Its claim is pending."
                self.requestStateRefresh(force: true)
            } catch {
                guard self.context == request.context else { return }
                self.dispatchNotice = "Worker not started: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Refresh

    /// The refresh button: the face on screen, and the estate only when it
    /// is the face on screen (its read costs far more than a board's).
    func requestRefresh(force: Bool = false) {
        requestStateRefresh(force: force)
        if surface == .estate {
            requestEstateRefresh(force: force)
        }
    }

    /// Read the focused board. A read already running for the same root is
    /// left to finish; a finished read is always kept, so switching away
    /// and back never throws work away or spawns a second CLI.
    func requestStateRefresh(force: Bool = false) {
        let context = context
        guard context.boardRoot != nil else {
            isRefreshing = false
            return
        }
        let key = Self.cacheKey(context)
        if !force,
           let refreshedAt = stateRefreshedAt[key],
           Date.now.timeIntervalSince(refreshedAt) < 10 {
            return
        }
        guard stateReadsInFlight.insert(key).inserted else {
            if key == Self.cacheKey(self.context) { isRefreshing = true }
            return
        }
        isRefreshing = true
        let client = self.client

        Task { [weak self] in
            let result = await Self.capture { [client] in try await client.state(for: context) }
            guard let self else { return }
            self.stateReadsInFlight.remove(key)
            self.applyState(result, for: context, key: key)
        }
    }

    func requestEstateRefresh(force: Bool = false) {
        if !force,
           let estateRefreshedAt,
           Date.now.timeIntervalSince(estateRefreshedAt) < 10 {
            return
        }
        guard !estateReadInFlight else { return }
        estateReadInFlight = true
        isEstateRefreshing = true
        let context = context
        let client = self.client

        Task { [weak self] in
            let result = await Self.capture { [client] in try await client.estate(for: context) }
            guard let self else { return }
            self.estateReadInFlight = false
            self.applyEstate(result)
        }
    }

    /// While the board is on screen it re-reads on the same cadence a
    /// visible inbox panel polls at; the topbar's mark is lit only then.
    private func startLiveRefresh() {
        liveTask?.cancel()
        let interval = HolyInboxEngine.pollInterval(panelVisible: true)
        liveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self, self.isPresented else { return }
                self.requestRefresh(force: true)
            }
        }
    }

    static func cacheKey(_ context: HolyMannaBoardContext) -> String {
        "\(context.remoteHost ?? "local"):\(context.boardRoot ?? "")"
    }

    private static func defaultSelection(in payload: HolyMannaStatePayload) -> String? {
        payload.now.first?.id
            ?? payload.next.first?.id
            ?? payload.waves.first?.items.first?.id
    }

    // MARK: Mutations

    func requestMutation(_ mutation: HolyMannaMutation) {
        guard !isMutating else { return }
        pendingMutation = mutation
        mutationFailure = nil
        mutationMessage = nil
    }

    func clearNotice() {
        mutationMessage = nil
        mutationFailure = nil
    }

    func showToast(_ text: String) {
        toastTask?.cancel()
        toast = text
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(HolyMannaBoardMetrics.toastSeconds))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func confirmPendingMutation() {
        guard let mutation = pendingMutation, !isMutating else { return }
        pendingMutation = nil
        isMutating = true
        activeMutation = mutation
        mutationFailure = nil
        mutationMessage = nil
        let context = context

        Task { [weak self] in
            guard let self else { return }
            do {
                let receipts = try await self.client.perform(mutation, in: context)
                self.isMutating = false
                self.activeMutation = nil
                guard self.context == context else { return }
                let message = receipts.count == 1
                    ? "\(mutation.label) completed."
                    : "\(mutation.label) completed in \(receipts.count) verified CLI steps."
                self.mutationMessage = message
                self.showToast(message)
                self.requestStateRefresh(force: true)
            } catch {
                self.isMutating = false
                self.activeMutation = nil
                guard self.context == context else { return }
                self.mutationFailure = error.localizedDescription
                self.showToast("refused: \(error.localizedDescription)")
                // Multi-step actions can fail after an earlier CLI verb
                // succeeded. Re-read canonical state instead of leaving a
                // stale pre-action picture on screen.
                self.requestStateRefresh(force: true)
            }
        }
    }

    func availableMutations(for item: HolyMannaBoardItem) -> [HolyMannaMutation] {
        var actions: [HolyMannaMutation] = []
        if item.kind == "dream" {
            actions += [.promote(item.id), .delete(item.id)]
        } else if item.status == "in_progress", item.claimedBy == actorID {
            actions += [.done(item.id), .abandon(item.id)]
        }

        actions += item.blockers.compactMap { blocker in
            blocker.status == "done"
                ? .unblock(issueID: item.id, blockerID: blocker.id)
                : nil
        }
        return actions
    }

    /// The handoff document for an item, read from the board's own tree; a
    /// remote board yields only the path.
    func handoffCopy(for item: HolyMannaBoardItem) -> (text: String, note: String)? {
        guard let prompt = item.prompt, !prompt.isEmpty else { return nil }
        guard context.remoteHost == nil, let root = context.boardRoot else {
            return (prompt, "handoff path \(prompt)")
        }
        let url = prompt.hasPrefix("/")
            ? URL(fileURLWithPath: prompt)
            : URL(fileURLWithPath: root).appendingPathComponent(prompt)
        guard let data = FileManager.default.contents(atPath: url.path),
              let content = String(data: data, encoding: .utf8),
              !content.isEmpty else {
            return (prompt, "handoff path \(prompt)")
        }
        return (content, "handoff \(prompt) (\(content.count) chars)")
    }

    // MARK: Apply

    private func applyState(
        _ result: Result<HolyMannaStatePayload, Error>,
        for refreshed: HolyMannaBoardContext,
        key: String
    ) {
        let isCurrent = key == Self.cacheKey(context)
        switch result {
        case let .success(payload):
            stateCache[key] = payload
            stateRefreshedAt[key] = .now
            scheduleFocusedWarm(payload, context: refreshed)
            guard isCurrent else { return }
            if let hash = askingHash ?? answer?.contentHash,
               hash != HolyMannaBoardQuestion.contentHash(payload) {
                clearAnswer()
            }
            state = payload
            boardFailure = nil
            lastRefreshedAt = stateRefreshedAt[key]
            if selectedPeerID == nil, payload.item(id: selectedItemID) == nil {
                selectedItemID = Self.defaultSelection(in: payload)
            }
            if let selectedPeerID, payload.peer(id: selectedPeerID) == nil {
                self.selectedPeerID = nil
            }
            if isPresented {
                loadSelectedDigest()
            }
            if estate == nil {
                requestEstateRefresh()
            }
        case let .failure(error):
            guard isCurrent else { return }
            boardFailure = error.localizedDescription
            // No usable board for this root: the estate is the honest
            // surface, with the failure printed on it. A transient failure
            // on a board already on screen keeps the board and reports.
            if state == nil || state?.root != refreshed.boardRoot {
                state = nil
                stateCache[key] = nil
                if isPresented {
                    surface = .estate
                    requestEstateRefresh(force: estate == nil)
                }
            }
        }
        isRefreshing = false
    }

    private func applyEstate(_ result: Result<HolyMannaEstatePayload, Error>) {
        switch result {
        case let .success(payload):
            estate = payload
            estateFailure = nil
            estateRefreshedAt = .now
            scheduleEstateWarm(payload)
            if surface == .estate {
                lastRefreshedAt = estateRefreshedAt
            }
        case let .failure(error):
            estateFailure = error.localizedDescription
        }
        isEstateRefreshing = false
    }

    private func loadActorID() {
        guard actorID == nil else { return }
        Task { [weak self] in
            guard let self else { return }
            self.actorID = try? await self.client.actorIdentityLabel()
        }
    }

    private func loadSelectedDigest() {
        guard let item = selectedItem else {
            digestText = nil
            digestModel = nil
            digestFailure = nil
            isDigestLoading = false
            return
        }

        if let presentation = presentation(for: item),
           let summary = presentation.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            applyDigest(presentation)
            return
        }

        digestText = nil
        digestModel = nil
        digestFailure = digestFailures[Self.failureKey(context: context, itemID: item.id)]
        isDigestLoading = digestFailure == nil
    }

    private func applyDigest(_ presentation: HolyMannaPresentationResult) {
        digestText = presentation.summary
        digestModel = presentation.model
        digestWasCached = presentation.wasCached
        digestFailure = nil
        isDigestLoading = false
    }

    func presentationDigest(for item: HolyMannaBoardItem) -> String? {
        Self.nonblank(presentation(for: item)?.digest)
    }

    func hasPresentationDigest(for item: HolyMannaBoardItem) -> Bool {
        presentationDigest(for: item) != nil
    }

    private func presentation(for item: HolyMannaBoardItem) -> HolyMannaPresentationResult? {
        let contentHash = HolyMannaBoardDigestService.contentHash(for: item)
        let cached = digestCache[Self.presentationKey(
            context: context,
            itemID: item.id,
            contentHash: contentHash
        )]
        let digest = Self.nonblank(item.digest)
            ?? cached?.digest
        let summary = Self.nonblank(item.summary)
            ?? cached?.summary
        guard digest != nil || summary != nil else { return nil }
        return .init(
            itemID: item.id,
            digest: digest,
            summary: summary,
            contentHash: contentHash,
            model: (item.digest != nil || item.summary != nil) ? "manna-state-cache" : cached?.model ?? "cache",
            wasCached: cached?.wasCached ?? true
        )
    }

    private func scheduleFocusedWarm(
        _ payload: HolyMannaStatePayload,
        context: HolyMannaBoardContext
    ) {
        let usage = usageAssessmentProvider()
        let estate = estate
        let prewarmer = prewarmer
        let sink = warmSink()
        Task {
            await prewarmer.enqueueFocused(
                payload,
                context: context,
                allowGeneration: usage.level < .restrain,
                usageGuardReason: usage.reason,
                sink: sink
            )
            if let estate {
                await prewarmer.enqueueEstate(
                    estate,
                    baseContext: context,
                    focusedRoot: context.boardRoot,
                    allowGeneration: usage.level < .restrain,
                    usageGuardReason: usage.reason,
                    sink: sink
                )
            }
        }
    }

    private func scheduleEstateWarm(_ payload: HolyMannaEstatePayload) {
        let usage = usageAssessmentProvider()
        let prewarmer = prewarmer
        let context = context
        let sink = warmSink()
        Task {
            await prewarmer.enqueueEstate(
                payload,
                baseContext: context,
                focusedRoot: context.boardRoot,
                allowGeneration: usage.level < .restrain,
                usageGuardReason: usage.reason,
                sink: sink
            )
        }
    }

    private func warmSink() -> HolyMannaWarmSink {
        { [weak self] event in
            self?.applyWarmEvent(event)
        }
    }

    private func applyWarmEvent(_ event: HolyMannaWarmEvent) {
        switch event {
        case let .resolved(context, results):
            for result in results {
                digestCache[Self.presentationKey(
                    context: context,
                    itemID: result.itemID,
                    contentHash: result.contentHash
                )] = result
                digestFailures[Self.failureKey(context: context, itemID: result.itemID)] = nil
            }
        case let .failed(context, itemIDs, message):
            for itemID in itemIDs {
                digestFailures[Self.failureKey(context: context, itemID: itemID)] = message
            }
        }
        if case let .resolved(eventContext, _) = event,
           eventContext == context {
            loadSelectedDigest()
        } else if case let .failed(eventContext, itemIDs, _) = event,
                  eventContext == context,
                  let selectedItemID,
                  itemIDs.contains(selectedItemID) {
            loadSelectedDigest()
        }
    }

    private static func presentationKey(
        context: HolyMannaBoardContext,
        itemID: String,
        contentHash: String
    ) -> String {
        "\(cacheKey(context)):\(itemID):\(contentHash)"
    }

    private static func failureKey(context: HolyMannaBoardContext, itemID: String) -> String {
        "\(cacheKey(context)):\(itemID)"
    }

    private static func nonblank(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func capture<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async -> Result<Value, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }
}

enum HolyAttentionBadgeCounter {
    /// Deduplicate session and board-peer attention through the same harness
    /// identity law the roster and Manna claimant join use. Non-peer board
    /// asks and GitHub attention remain independent facts.
    static func count(
        github: Int,
        boardAsks: Int,
        boardPeerIDs: [String],
        sessionIDs: [String?]
    ) -> Int {
        var unmatchedPeerIDs = boardPeerIDs
        var distinctSessionIDs: [String] = []
        var identitylessSessionCount = 0
        for sessionID in sessionIDs {
            guard let sessionID,
                  !sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                identitylessSessionCount += 1
                continue
            }
            guard !distinctSessionIDs.contains(where: {
                HolyHarnessSessionIdentity.matches(sessionID, $0)
            }) else { continue }
            distinctSessionIDs.append(sessionID)
        }

        for sessionID in distinctSessionIDs {
            if let index = unmatchedPeerIDs.firstIndex(where: {
                HolyHarnessSessionIdentity.matches(sessionID, $0)
            }) {
                unmatchedPeerIDs.remove(at: index)
            }
        }

        let peerAskCount = boardPeerIDs.count
        let nonPeerBoardAsks = max(0, boardAsks - peerAskCount)
        return max(0, github)
            + nonPeerBoardAsks
            + distinctSessionIDs.count
            + identitylessSessionCount
            + unmatchedPeerIDs.count
    }
}
