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
    @Published var grep = ""
    @Published private(set) var state: HolyMannaStatePayload?
    @Published private(set) var estate: HolyMannaEstatePayload?
    @Published private(set) var boardFailure: String?
    @Published private(set) var estateFailure: String?
    @Published private(set) var isRefreshing = false
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

    private(set) var context = HolyMannaBoardContext(boardRoot: nil, remoteHost: nil)
    private let client: HolyMannaBoardClient
    private let digestService: any HolyMannaBoardDigesting
    private let usageAssessmentProvider: () -> HolyClaudeUsageAssessment
    private var refreshGeneration = UUID()
    private var refreshTask: Task<Void, Never>?
    private var digestTask: Task<Void, Never>?
    private var liveTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var digestCache: [String: HolyMannaDigestResult] = [:]

    init(
        client: HolyMannaBoardClient = .init(),
        digestService: any HolyMannaBoardDigesting = HolyMannaBoardDigestService.shared,
        usageAssessmentProvider: @escaping () -> HolyClaudeUsageAssessment = {
            .init(level: .normal, decidingBucket: nil, reason: nil)
        }
    ) {
        self.client = client
        self.digestService = digestService
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
        return HolyMannaBoardPresentation.sections(
            state: state,
            filter: boardFilter,
            track: trackFilter,
            grep: grep
        )
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
        startLiveRefresh()
    }

    func prepare(context: HolyMannaBoardContext) {
        let contextChanged = self.context != context
        self.context = context
        if contextChanged {
            // A different root is a different board: never show the old
            // board's rows under the new board's name while it reads.
            state = nil
            boardFailure = nil
            selectedItemID = nil
            selectedPeerID = nil
            digestText = nil
            digestFailure = nil
        }
        requestRefresh(force: contextChanged || state == nil)
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
        pendingMutation = nil
        digestTask?.cancel()
        liveTask?.cancel()
        liveTask = nil
    }

    /// The crumb's "estate": the table of every board, the board kept warm.
    func showEstate() {
        surface = .estate
        selectedSheet = .board
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
            digestTask?.cancel()
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
            context = next
            state = nil
            boardFailure = nil
            selectedItemID = nil
            selectedPeerID = nil
            digestText = nil
            digestFailure = nil
        }
        surface = .board
        selectedSheet = .board
        requestRefresh(force: true)
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

    // MARK: Refresh

    func requestRefresh(force: Bool = false) {
        if !force,
           let lastRefreshedAt,
           Date.now.timeIntervalSince(lastRefreshedAt) < 10 {
            return
        }
        refreshTask?.cancel()
        let generation = UUID()
        refreshGeneration = generation
        let context = context
        isRefreshing = true

        refreshTask = Task { [weak self] in
            guard let self else { return }
            async let stateResult = Self.capture { try await self.client.state(for: context) }
            async let estateResult = Self.capture { try await self.client.estate(for: context) }
            let results = await (stateResult, estateResult)
            guard !Task.isCancelled, self.refreshGeneration == generation else { return }
            self.apply(stateResult: results.0, estateResult: results.1, for: context)
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
                self.requestRefresh(force: true)
            } catch {
                self.isMutating = false
                self.activeMutation = nil
                guard self.context == context else { return }
                self.mutationFailure = error.localizedDescription
                self.showToast("refused: \(error.localizedDescription)")
                // Multi-step actions can fail after an earlier CLI verb
                // succeeded. Re-read canonical state instead of leaving a
                // stale pre-action picture on screen.
                self.requestRefresh(force: true)
            }
        }
    }

    func availableMutations(for item: HolyMannaBoardItem) -> [HolyMannaMutation] {
        var actions: [HolyMannaMutation] = []
        if item.kind == "dream" {
            actions += [.promote(item.id), .delete(item.id)]
        } else if item.status == "open", item.effective == "ready" {
            actions.append(.claim(item.id))
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

    private func apply(
        stateResult: Result<HolyMannaStatePayload, Error>,
        estateResult: Result<HolyMannaEstatePayload, Error>,
        for refreshed: HolyMannaBoardContext
    ) {
        switch stateResult {
        case let .success(payload):
            state = payload
            boardFailure = nil
            if selectedPeerID == nil, payload.item(id: selectedItemID) == nil {
                selectedItemID = payload.now.first?.id
                    ?? payload.next.first?.id
                    ?? payload.waves.first?.items.first?.id
            }
            if let selectedPeerID, payload.peer(id: selectedPeerID) == nil {
                self.selectedPeerID = nil
            }
            if isPresented {
                loadSelectedDigest()
            }
        case let .failure(error):
            boardFailure = error.localizedDescription
            // No usable board for this root: the estate is the honest
            // surface, with the failure printed on it. A transient failure
            // on a board already on screen keeps the board and reports.
            if state == nil || state?.root != refreshed.boardRoot {
                state = nil
                if isPresented {
                    surface = .estate
                }
            }
        }

        switch estateResult {
        case let .success(payload):
            estate = payload
            estateFailure = nil
        case let .failure(error):
            estateFailure = error.localizedDescription
        }

        isRefreshing = false
        lastRefreshedAt = .now
    }

    private func loadActorID() {
        guard actorID == nil else { return }
        Task { [weak self] in
            guard let self else { return }
            self.actorID = try? await self.client.actorIdentityLabel()
        }
    }

    private func loadSelectedDigest() {
        digestTask?.cancel()
        guard let item = selectedItem else {
            digestText = nil
            digestModel = nil
            digestFailure = nil
            isDigestLoading = false
            return
        }

        let hash = HolyMannaBoardDigestService.contentHash(for: item)
        if let cached = digestCache[hash] {
            applyDigest(cached)
            return
        }

        digestText = nil
        digestModel = nil
        digestFailure = nil
        isDigestLoading = true
        let usage = usageAssessmentProvider()
        let allowGeneration = usage.level < .critical
        let context = context
        digestTask = Task { [weak self] in
            guard let self else { return }
            do {
                let digest = try await self.digestService.digest(
                    for: item,
                    boardRoot: context.boardRoot,
                    allowGeneration: allowGeneration,
                    usageGuardReason: usage.reason
                )
                guard !Task.isCancelled,
                      self.selectedItemID == item.id,
                      self.context == context else { return }
                self.digestCache[hash] = digest
                self.applyDigest(digest)
            } catch {
                guard !Task.isCancelled,
                      self.selectedItemID == item.id,
                      self.context == context else { return }
                self.digestFailure = error.localizedDescription
                self.isDigestLoading = false
            }
        }
    }

    private func applyDigest(_ digest: HolyMannaDigestResult) {
        digestText = digest.text
        digestModel = digest.model
        digestWasCached = digest.wasCached
        digestFailure = nil
        isDigestLoading = false
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
