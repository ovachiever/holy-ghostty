import Foundation
import SwiftUI

struct HolyMannaBoardItemSection: Identifiable, Equatable, Sendable {
    let id: String
    let title: String?
    let items: [HolyMannaBoardItem]
}

@MainActor
final class HolyMannaBoardModeStore: ObservableObject {
    @Published private(set) var isPresented = false
    @Published var selectedSheet: HolyMannaBoardSheet = .now
    @Published private(set) var state: HolyMannaStatePayload?
    @Published private(set) var estate: HolyMannaEstatePayload?
    @Published private(set) var boardFailure: String?
    @Published private(set) var estateFailure: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshedAt: Date?
    @Published var selectedItemID: String?
    @Published private(set) var actorID: String?
    @Published var pendingMutation: HolyMannaMutation?
    @Published private(set) var isMutating = false
    @Published private(set) var mutationMessage: String?
    @Published private(set) var mutationFailure: String?
    @Published private(set) var digestText: String?
    @Published private(set) var digestModel: String?
    @Published private(set) var digestWasCached = false
    @Published private(set) var digestFailure: String?
    @Published private(set) var isDigestLoading = false

    private(set) var context = HolyMannaBoardContext(boardRoot: nil, remoteHost: nil)
    private let client: HolyMannaBoardClient
    private let digestService: any HolyMannaBoardDigesting
    private let usageAssessmentProvider: () -> HolyClaudeUsageAssessment
    private var refreshGeneration = UUID()
    private var refreshTask: Task<Void, Never>?
    private var digestTask: Task<Void, Never>?
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

    var selectedItem: HolyMannaBoardItem? {
        state?.item(id: selectedItemID)
    }

    var boardName: String {
        state?.name
            ?? context.boardRoot.map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? "Board"
    }

    var sortedEstateBoards: [HolyMannaEstateBoard] {
        (estate?.boards ?? [])
            .filter(\.exists)
            .sorted { lhs, rhs in
                if lhs.needsYou != rhs.needsYou { return lhs.needsYou > rhs.needsYou }
                if lhs.activeCount != rhs.activeCount { return lhs.activeCount > rhs.activeCount }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    var itemSections: [HolyMannaBoardItemSection] {
        guard let state else { return [] }
        switch selectedSheet {
        case .now:
            return [.init(id: "now", title: nil, items: state.now)]
        case .next:
            return [.init(id: "next", title: nil, items: state.next)]
        case .waves:
            return state.waves.map {
                .init(id: "wave:\($0.wave)", title: "Wave \($0.wave)", items: $0.items)
            }
        case .dreams:
            return [.init(id: "dreams", title: nil, items: state.dreams)]
        case .decisions:
            return [.init(id: "decisions", title: nil, items: state.decisions)]
        case .asks, .coordination:
            return []
        }
    }

    var sheetCount: Int {
        guard let state else { return 0 }
        switch selectedSheet {
        case .now: return state.now.count
        case .next: return state.next.count
        case .waves: return state.waves.reduce(0) { $0 + $1.items.count }
        case .asks: return state.asks.count
        case .coordination:
            return state.peers.count + state.coord.claims.count + state.coord.needs.count + state.coord.drops.count
        case .dreams: return state.dreams.count
        case .decisions: return state.decisions.count
        }
    }

    /// Badge-worthy board asks only. A ready backlog remains visible in the
    /// Asks sheet without turning routine availability into alarm noise.
    var humanAttentionAskCount: Int {
        state?.asks.filter { ask in
            ask.verb != "launch" && ask.kind != "document"
        }.count ?? 0
    }

    var humanAttentionPeerIDs: [String] {
        state?.peers.compactMap { peer in
            (peer.attention == "needs-user" || peer.attention == "failed") ? peer.agentID : nil
        } ?? []
    }

    func present(context: HolyMannaBoardContext) {
        isPresented = true
        prepare(context: context)
        loadSelectedDigest()
        mutationMessage = nil
        mutationFailure = nil
    }

    func prepare(context: HolyMannaBoardContext) {
        let contextChanged = self.context != context
        self.context = context
        if contextChanged {
            selectedItemID = nil
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
    }

    func selectSheet(_ sheet: HolyMannaBoardSheet) {
        selectedSheet = sheet
        if sheet != .asks && sheet != .coordination {
            let visibleIDs = Set(itemSections.flatMap(\.items).map(\.id))
            if !visibleIDs.contains(selectedItemID ?? "") {
                selectItem(itemSections.first?.items.first?.id)
            }
        }
    }

    func selectItem(_ id: String?) {
        selectedItemID = id
        loadSelectedDigest()
    }

    func selectEstateBoard(_ board: HolyMannaEstateBoard) {
        guard board.exists else { return }
        context = context.selecting(boardRoot: board.root)
        selectedItemID = nil
        digestText = nil
        digestFailure = nil
        requestRefresh(force: true)
    }

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
            self.apply(stateResult: results.0, estateResult: results.1)
        }
    }

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

    func confirmPendingMutation() {
        guard let mutation = pendingMutation, !isMutating else { return }
        pendingMutation = nil
        isMutating = true
        mutationFailure = nil
        mutationMessage = nil
        let context = context

        Task { [weak self] in
            guard let self else { return }
            do {
                let receipts = try await self.client.perform(mutation, in: context)
                self.isMutating = false
                guard self.context == context else { return }
                self.mutationMessage = receipts.count == 1
                    ? "\(mutation.label) completed."
                    : "\(mutation.label) completed in \(receipts.count) verified CLI steps."
                self.requestRefresh(force: true)
            } catch {
                self.isMutating = false
                guard self.context == context else { return }
                self.mutationFailure = error.localizedDescription
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

    private func apply(
        stateResult: Result<HolyMannaStatePayload, Error>,
        estateResult: Result<HolyMannaEstatePayload, Error>
    ) {
        switch stateResult {
        case let .success(payload):
            state = payload
            boardFailure = nil
            if payload.item(id: selectedItemID) == nil {
                selectedItemID = payload.now.first?.id
                    ?? payload.next.first?.id
                    ?? payload.waves.first?.items.first?.id
            }
            if isPresented {
                loadSelectedDigest()
            }
        case let .failure(error):
            boardFailure = error.localizedDescription
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
