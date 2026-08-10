import Foundation

/// tmux side effects the engine needs, behind a seam so the orchestration
/// logic is testable without a server. The production implementation defers
/// to the sanctioned lifecycle primitives — it never reimplements liveness.
protocol HolyRestoreTmuxControlling: Sendable {
    func liveness(for identity: HolyTmuxLiveIdentity) async -> HolyTmuxLiveness
    /// Creates the session detached. Returns nil on success, or a
    /// human-readable failure reason.
    func createDetached(for launchSpec: HolySessionLaunchSpec) async -> String?
}

protocol HolyRestoreEnvironmentProbing: Sendable {
    func directoryExists(_ path: String) -> Bool
    /// An invocable path for the named executable, or nil when none exists.
    /// Production returns an absolute path so the resume command survives the
    /// login-shell PATH of a Dock launch; tests may return the bare name.
    func resolveExecutable(_ name: String) async -> String?
}

/// The slice of workspace state the engine reads and writes. The store
/// conforms; tests use a fake. Adoption goes through the supervisor's
/// readopt path so Holy UUIDs, notes, titles, and pins survive restore.
@MainActor
protocol HolyRestoreWorkspaceAdapting: AnyObject {
    /// Cold-boot candidates split into the most recent boot event (`fresh`)
    /// and every earlier unrestored interruption (`older`).
    var restoreCandidateBatch: HolyCrashRestoreBatch { get }
    func rosterOwnsSession(withHolyID id: UUID) -> Bool
    func rosterOwnsTmuxSessionName(_ name: String) -> Bool
    /// Persists a planned or restored launch spec back onto the archived
    /// record so identities stay stable across retries and app relaunches.
    func persistPlannedLaunchSpec(archiveID: UUID, launchSpec: HolySessionLaunchSpec)
    /// Readopts the archived session with an attach-only spec. Returns
    /// whether adoption succeeded.
    func attachRestoredArchive(archiveID: UUID, launchSpec: HolySessionLaunchSpec) -> Bool
    /// Deletes archived records outright, through the same removal path
    /// Session History uses. Restore never invents a second way to delete.
    func deleteArchives(archiveIDs: [UUID])
}

struct HolyRestoreRow: Identifiable, Equatable {
    /// The archive id; stable across retries.
    let id: UUID
    var archived: HolyArchivedSession
    /// The exact spec restore will create: persisted identity (generated
    /// once when missing), original command until restore swaps in the
    /// resolved resume command.
    var plannedLaunchSpec: HolySessionLaunchSpec
    var state: HolyRestoreRowState
    var phase: HolyRestoreRowPhase
    var isSelected: Bool
    /// True when the row belongs to the most recent cold-boot batch. Older
    /// rows render collapsed, are never preselected, and are excluded from
    /// Restore All and the interrupted count.
    let isFresh: Bool

    /// True when the archived title carries Holy's machine-generated
    /// adoption suffix — almost always a sub-agent's helper shell rather
    /// than a session a human named and would miss. Provenance heuristic;
    /// see `HolyRestoreProvenance` for what it costs when it is wrong.
    var isHelperSession: Bool {
        HolyRestoreProvenance.isHelperSessionTitle(archived.title)
    }

    /// Longest note the row renders. Past this the line stops being a clue
    /// and starts being a paragraph competing with the title.
    static let noteDisplayLimit = 90

    /// The session note as one capped line, or nil when there is none.
    ///
    /// The note is the only human-authored clue that tells two rows in the
    /// same directory running the same runtime apart, so the row shows it.
    /// Newlines collapse to spaces and the tail is cut, because a note is
    /// usually written front-loaded: "rebasing the auth branch, do not kill".
    var noteDisplay: String? {
        guard let raw = archived.record.launchSpec.note else { return nil }
        let flattened = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !flattened.isEmpty else { return nil }
        guard flattened.count > Self.noteDisplayLimit else { return flattened }
        return String(flattened.prefix(Self.noteDisplayLimit - 1)) + "…"
    }
}

/// Orchestrates crash restore: plan from cold-boot archives, preflight local
/// facts per row, resolve every provider row's conversation through ONE
/// batch call with globally unique assignment, create detached tmux
/// sessions in bounded batches, and adopt instead of duplicating on every
/// retry. The identity guarantee is the argv: restore launches
/// `claude --resume <exact id>` as an argument array, and a provider that
/// accepts it has resumed exactly that conversation — no post-restore
/// re-resolve exists, because re-resolving near "now" against a forked
/// session file can only lie in both directions.
@MainActor
final class HolyRestoreEngine: ObservableObject {
    static let maxConcurrentRestores = 4
    /// Fresh batches at or under this size open fully selected — one glance,
    /// one click. Bigger batches open with nothing selected, so no stressed
    /// human ever faces "Restore Selected (54)" as the default.
    static let freshPreselectionLimit = 12

    @Published private(set) var rows: [HolyRestoreRow] = []
    @Published private(set) var isPreflighting = false
    @Published private(set) var isRestoring = false

    private let batchResolver: any HolyRestoreBatchResolving
    private let tmux: any HolyRestoreTmuxControlling
    private let environment: any HolyRestoreEnvironmentProbing
    // Held strongly: the engine owns its adapter's lifetime. Production
    // passes a thin box that references the store weakly, so no cycle.
    private let adapter: any HolyRestoreWorkspaceAdapting

    init(
        batchResolver: any HolyRestoreBatchResolving,
        tmux: any HolyRestoreTmuxControlling,
        environment: any HolyRestoreEnvironmentProbing,
        adapter: any HolyRestoreWorkspaceAdapting
    ) {
        self.batchResolver = batchResolver
        self.tmux = tmux
        self.environment = environment
        self.adapter = adapter
    }

    var freshRows: [HolyRestoreRow] { rows.filter(\.isFresh) }

    var olderRows: [HolyRestoreRow] { rows.filter { !$0.isFresh } }

    /// Fresh rows split by provenance. Parents render first; helpers group
    /// under their own disclosure so a swarm's scaffolding never buries the
    /// three sessions the human actually lost.
    var freshParentRows: [HolyRestoreRow] { freshRows.filter { !$0.isHelperSession } }

    var freshHelperRows: [HolyRestoreRow] { freshRows.filter(\.isHelperSession) }

    var olderParentRows: [HolyRestoreRow] { olderRows.filter { !$0.isHelperSession } }

    var olderHelperRows: [HolyRestoreRow] { olderRows.filter(\.isHelperSession) }

    // MARK: - Crash groups

    /// One crash event inside the older section: its rows split by
    /// provenance, plus the recency rank that names its hue. The fresh
    /// section is rank 0 by definition — it IS the newest crash — so older
    /// sections rank from 1, ordered by their newest archive time. Rank is
    /// pure data: no disclosure state feeds it, so a batch keeps its color
    /// whether it is open or shut.
    struct OlderCrashSection: Equatable, Identifiable {
        let key: HolyRestoreCrashGroupKey
        let rank: Int
        let newestArchivedAt: Date
        let parentRows: [HolyRestoreRow]
        let helperRows: [HolyRestoreRow]

        var id: HolyRestoreCrashGroupKey { key }
        var sectionID: HolyRestoreCrashSectionID { .older(key) }
        var totalCount: Int { parentRows.count + helperRows.count }
    }

    /// The recency rank of the fresh section, fixed by definition.
    static let freshCrashRank = 0

    /// The older rows partitioned per crash event, newest crash first.
    /// Freshness itself is never re-derived here — the adapter's fresh/older
    /// split stays the single authority; this only subdivides `older`.
    var olderCrashSections: [OlderCrashSection] {
        let groups = HolyRestoreCrashGrouping.groups(from: olderRows.map(\.archived))
        let rowsByID = Dictionary(uniqueKeysWithValues: olderRows.map { ($0.id, $0) })
        return groups.enumerated().map { index, group in
            let groupRows = group.sessions.compactMap { rowsByID[$0.id] }
            return OlderCrashSection(
                key: group.key,
                rank: index + 1,
                newestArchivedAt: group.newestArchivedAt,
                parentRows: groupRows.filter { !$0.isHelperSession },
                helperRows: groupRows.filter(\.isHelperSession)
            )
        }
    }

    // MARK: - Lineage

    /// A row's presence in a crash OTHER than its own: the same Holy session
    /// (by `sourceSessionID`) also left an archive in that crash. Membership
    /// stays singular — the row belongs to its own batch; the tick is
    /// information about a sibling archive, never dual membership.
    struct LineageTick: Equatable, Identifiable {
        let sectionID: HolyRestoreCrashSectionID
        /// The other crash's recency rank, which is also its hue.
        let rank: Int
        /// The other crash's newest archive time, for a relative-time tooltip.
        let occurredAt: Date

        var id: HolyRestoreCrashSectionID { sectionID }
    }

    /// Every section each source session has an archive in. Kept as its own
    /// map, not fused into row building, so flipping ticks to true dual
    /// membership later is a render change: the memberships are already here.
    var crashLineageBySourceSession: [UUID: Set<HolyRestoreCrashSectionID>] {
        var memberships: [UUID: Set<HolyRestoreCrashSectionID>] = [:]
        for row in freshRows {
            memberships[row.archived.sourceSessionID, default: []].insert(.fresh)
        }
        for section in olderCrashSections {
            for row in section.parentRows + section.helperRows {
                memberships[row.archived.sourceSessionID, default: []]
                    .insert(section.sectionID)
            }
        }
        return memberships
    }

    /// The ticks a row renders: every OTHER crash holding an archive of the
    /// same source session, sorted newest crash first. Empty for the common
    /// row that died exactly once.
    func lineageTicks(for row: HolyRestoreRow) -> [LineageTick] {
        let memberships = crashLineageBySourceSession[row.archived.sourceSessionID] ?? []
        guard memberships.count > 1 else { return [] }

        let ownSectionID: HolyRestoreCrashSectionID = row.isFresh
            ? .fresh
            : olderCrashSections
                .first { section in
                    (section.parentRows + section.helperRows).contains { $0.id == row.id }
                }
                .map(\.sectionID) ?? .fresh

        var facts: [HolyRestoreCrashSectionID: (rank: Int, occurredAt: Date)] = [:]
        if let freshNewest = freshRows.map(\.archived.archivedAt).max() {
            facts[.fresh] = (Self.freshCrashRank, freshNewest)
        }
        for section in olderCrashSections {
            facts[section.sectionID] = (section.rank, section.newestArchivedAt)
        }

        return memberships
            .filter { $0 != ownSectionID }
            .compactMap { sectionID in
                facts[sectionID].map {
                    LineageTick(sectionID: sectionID, rank: $0.rank, occurredAt: $0.occurredAt)
                }
            }
            .sorted { $0.rank < $1.rank }
    }

    /// The honest headline count: this boot's interruptions, parents only.
    ///
    /// A helper shell is scaffolding a sub-agent run created and the crash
    /// took with it; counting forty of them as "forty sessions interrupted"
    /// makes a stressed human brace for work that was never theirs. Same
    /// dishonesty the fresh/older split already removed once. Helpers stay
    /// restorable — by explicit selection, never by a bulk button.
    var interruptedCount: Int { freshParentRows.count }

    /// Named separately so the header can itemize instead of hiding them.
    var freshHelperCount: Int { freshHelperRows.count }

    /// Every older row, parents and helpers. Unlike the fresh count this one
    /// labels a container ("Older interruptions (51)") whose contents are
    /// itemized one level down, so the total is the honest number here.
    var olderCount: Int { olderRows.count }

    var selectedCount: Int { rows.filter(\.isSelected).count }

    /// The ids Select All / Select None may touch, given which disclosures
    /// the sheet currently has open.
    ///
    /// The law lives here, not in the view, so it can be checked without
    /// rendering anything: a bulk button acts on exactly what the user can
    /// see. Rows behind a shut disclosure — older interruptions, helper
    /// shells — are not selectable by a button the user cannot see them
    /// under.
    func visibleRowIDs(
        freshHelpersExpanded: Bool,
        expandedOlderGroups: Set<HolyRestoreCrashGroupKey>,
        expandedOlderHelperGroups: Set<HolyRestoreCrashGroupKey>
    ) -> [UUID] {
        var ids = freshParentRows.map(\.id)
        if freshHelpersExpanded {
            ids += freshHelperRows.map(\.id)
        }
        for section in olderCrashSections where expandedOlderGroups.contains(section.key) {
            ids += section.parentRows.map(\.id)
            if expandedOlderHelperGroups.contains(section.key) {
                ids += section.helperRows.map(\.id)
            }
        }
        return ids
    }

    /// The pre-crash-sections projection of the same law: one switch for the
    /// whole older region, one for all its helper disclosures. Delegates to
    /// the per-group law with every group in the named state.
    func visibleRowIDs(
        olderExpanded: Bool,
        freshHelpersExpanded: Bool,
        olderHelpersExpanded: Bool
    ) -> [UUID] {
        let allKeys = Set(olderCrashSections.map(\.key))
        return visibleRowIDs(
            freshHelpersExpanded: freshHelpersExpanded,
            expandedOlderGroups: olderExpanded ? allKeys : [],
            expandedOlderHelperGroups: olderHelpersExpanded ? allKeys : []
        )
    }

    // MARK: - Plan

    /// Rebuilds rows from the adapter's candidate batch: fresh rows first,
    /// older after. Fresh PARENT rows preselect only when there are few of
    /// them (`freshPreselectionLimit`); helper shells and older rows never
    /// preselect at any batch size. Records without a complete tmux identity
    /// get one generated and persisted immediately, so the identity is
    /// stable for idempotent retries and later cold boots.
    ///
    /// The limit counts parents because parents are the only rows it can be
    /// about: it exists so nobody opens this sheet facing
    /// "Restore Selected (54)", and helpers contribute zero to that number.
    func buildPlan() {
        let batch = adapter.restoreCandidateBatch
        let preselectFresh = batch.freshParentCount <= Self.freshPreselectionLimit
        rows = batch.fresh.map {
            let isHelper = HolyRestoreProvenance.isHelperSessionTitle($0.title)
            return plannedRow(
                from: $0,
                isFresh: true,
                isSelected: preselectFresh && !isHelper
            )
        } + batch.older.map {
            plannedRow(from: $0, isFresh: false, isSelected: false)
        }
    }

    private func plannedRow(
        from archived: HolyArchivedSession,
        isFresh: Bool,
        isSelected: Bool
    ) -> HolyRestoreRow {
        var planned = archived.record.launchSpec
        if planned.tmux == nil {
            planned.tmux = .holyManagedDefault
        }
        if planned.tmux?.normalized.sessionName == nil {
            planned = HolyTmuxCommandBuilder.realizedLaunchSpec(planned)
            adapter.persistPlannedLaunchSpec(archiveID: archived.id, launchSpec: planned)
        }

        return HolyRestoreRow(
            id: archived.id,
            archived: archived,
            plannedLaunchSpec: planned,
            state: .blocked("Preflight has not run yet."),
            phase: .pending,
            isSelected: isSelected,
            isFresh: isFresh
        )
    }

    // MARK: - Preflight

    /// Two-stage preflight. Stage one gathers local facts per row (tmux
    /// liveness, cwd, provider executable) with bounded concurrency; every
    /// row that needs no conversation resolution reaches its final verdict
    /// there and is immediately restorable — a slow resolver never holds the
    /// whole sheet hostage. Stage two ships every remaining question as ONE
    /// resolve-batch subprocess call and assigns candidates to rows
    /// globally, each conversation id spent at most once.
    func runPreflight() async {
        guard !isPreflighting else { return }
        isPreflighting = true
        defer { isPreflighting = false }

        pendingResolutions.removeAll()
        let conflictReasons = planConflictReasons()
        await runBounded(rowIDs: rows.map(\.id)) { [weak self] rowID in
            await self?.preflightLocalFacts(rowID: rowID, conflictReasons: conflictReasons)
        }
        await resolvePendingRowsInOneBatch()
        pendingResolutions.removeAll()
    }

    /// Identity collisions visible from the plan itself: two rows targeting
    /// the same tmux session name, or a roster session (with a different
    /// Holy UUID) already owning a row's name.
    private func planConflictReasons() -> [UUID: String] {
        var rowIDsBySessionName: [String: [UUID]] = [:]
        for row in rows {
            guard let sessionName = row.plannedLaunchSpec.tmux?.normalized.sessionName else { continue }
            rowIDsBySessionName[sessionName, default: []].append(row.id)
        }

        var reasons: [UUID: String] = [:]
        for (sessionName, rowIDs) in rowIDsBySessionName {
            if rowIDs.count > 1 {
                for rowID in rowIDs {
                    reasons[rowID] = "Another interrupted session targets the same tmux identity (\(sessionName))."
                }
                continue
            }
            if let rowID = rowIDs.first,
               let row = rows.first(where: { $0.id == rowID }),
               adapter.rosterOwnsTmuxSessionName(sessionName),
               !adapter.rosterOwnsSession(withHolyID: row.archived.sourceSessionID) {
                reasons[rowID] = "A different roster session already owns tmux identity \(sessionName)."
            }
        }
        return reasons
    }

    /// One row's question awaiting the batch resolver, with the local facts
    /// already gathered so the final verdict is a pure mapping.
    private struct PendingResolution {
        let rowID: UUID
        let workingDirectory: String
        let harness: String
        let nearUnixSeconds: Int
        var context: HolyRestorePreflightContext
    }

    private var pendingResolutions: [UUID: PendingResolution] = [:]

    private func preflightLocalFacts(rowID: UUID, conflictReasons: [UUID: String]) async {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
        let row = rows[index]
        updateRow(rowID) { $0.phase = .preflighting }

        // A roster session with this Holy UUID means restore already
        // happened (revival or an earlier adoption). Nothing to probe.
        if adapter.rosterOwnsSession(withHolyID: row.archived.sourceSessionID) {
            updateRow(rowID) {
                $0.state = .alreadyRestored
                $0.phase = .ready
            }
            return
        }

        let spec = row.plannedLaunchSpec
        let runtime = spec.runtime
        let workingDirectory = resolvedWorkingDirectory(for: row)

        var context = HolyRestorePreflightContext(
            hostSupported: !spec.transport.normalized.isRemote,
            workingDirectoryExists: workingDirectory.map(environment.directoryExists),
            workingDirectory: workingDirectory,
            executableAvailable: nil,
            resolveOutcome: nil,
            liveness: nil,
            conflictReason: conflictReasons[rowID]
        )

        if context.hostSupported, let identity = HolyTmuxLiveIdentity(exactLaunchSpec: spec) {
            context.liveness = await tmux.liveness(for: identity)
        }

        if runtime != .shell {
            context.executableAvailable = await environment.resolveExecutable(runtime.rawValue) != nil
        }

        // Only provider rows that pass every local gate go to the resolver;
        // everything else already has its final verdict in the local facts.
        let needsResolution = runtime != .shell
            && context.hostSupported
            && context.conflictReason == nil
            && (context.liveness == .absent || context.liveness == nil)
            && context.workingDirectoryExists == true
            && context.executableAvailable == true
            && workingDirectory != nil

        if needsResolution, let workingDirectory {
            // The row keeps phase .preflighting (rendered "Checking…") and a
            // blocked state, so a mid-preflight Restore skips it honestly.
            pendingResolutions[rowID] = .init(
                rowID: rowID,
                workingDirectory: workingDirectory,
                harness: runtime.rawValue,
                nearUnixSeconds: Int(row.archived.lastActivityAt.timeIntervalSince1970),
                context: context
            )
            return
        }

        let state = HolyRestorePreflight.rowState(runtime: runtime, context: context)
        updateRow(rowID) {
            $0.state = state
            $0.phase = .ready
        }
    }

    /// Stage two: one resolve-batch call for every pending row, then global
    /// unique assignment. On resolver failure every pending row degrades to
    /// a retryable blocked state — nothing restores blind.
    private func resolvePendingRowsInOneBatch() async {
        // Sheet order, so assignment tie-breaks favor the row the user sees
        // first and the result is deterministic across runs.
        let pending = rows.compactMap { pendingResolutions[$0.id] }
        guard !pending.isEmpty else { return }

        let outcome = await batchResolver.resolveBatch(pending.map {
            .init(cwd: $0.workingDirectory, harness: $0.harness, near: $0.nearUnixSeconds)
        })

        switch outcome {
        case let .resolverUnavailable(reason):
            for item in pending {
                finalizePendingRow(item, resolveOutcome: .resolverUnavailable(reason))
            }
        case let .resolved(results):
            // POSITIONAL pairing is the contract: results[i] answers
            // requests[i], duplicates included. Coordinates cannot key the
            // match — the CLI canonicalizes the echoed harness ("claude" in,
            // "claude-code" out), and two same-cwd rows are two distinct
            // questions. A count mismatch is a contract violation, and
            // fail-closed beats guessing which row lost its answer.
            guard results.count == pending.count else {
                let reason = "resolve-batch returned \(results.count) results for \(pending.count) requests."
                for item in pending {
                    finalizePendingRow(item, resolveOutcome: .resolverUnavailable(reason))
                }
                return
            }

            // Rows whose result carries a per-request error are blocked
            // (retryable), never demoted to shell-only: "the resolver could
            // not answer" is not "no history exists".
            var assignmentRows: [HolyRestoreAssignment.Row] = []
            var errorsByRowID: [UUID: String] = [:]
            for (item, result) in zip(pending, results) {
                if let error = result.error {
                    errorsByRowID[item.rowID] = error
                    continue
                }
                assignmentRows.append(.init(
                    id: item.rowID,
                    lastActivityUnixSeconds: item.nearUnixSeconds,
                    candidates: result.candidates
                ))
            }

            let verdicts = HolyRestoreAssignment.assign(rows: assignmentRows)

            for item in pending {
                if let error = errorsByRowID[item.rowID] {
                    finalizePendingRow(item, resolveOutcome: .resolverUnavailable(error))
                    continue
                }
                finalizePendingRow(
                    item,
                    resolveOutcome: .resolved(resolution(
                        for: verdicts[item.rowID] ?? .unmatched,
                        item: item
                    ))
                )
            }
            assertUniqueExactAssignments()
        }
    }

    private func finalizePendingRow(
        _ item: PendingResolution,
        resolveOutcome: HolyRestoreResolveOutcome
    ) {
        guard let row = rows.first(where: { $0.id == item.rowID }) else { return }
        var context = item.context
        context.resolveOutcome = resolveOutcome
        let state = HolyRestorePreflight.rowState(
            runtime: row.plannedLaunchSpec.runtime,
            context: context
        )
        updateRow(item.rowID) {
            $0.state = state
            $0.phase = .ready
        }
    }

    /// Bridges an assignment verdict back into the resolve-outcome shape the
    /// preflight matrix speaks, so the precedence law and its tests stay one
    /// total function.
    private func resolution(
        for verdict: HolyRestoreAssignmentVerdict,
        item: PendingResolution
    ) -> HolyRestoreResolution {
        switch verdict {
        case let .exact(providerSessionID):
            return .init(
                matched: true,
                providerSessionID: providerSessionID,
                harness: item.harness,
                runtime: item.harness,
                projectPath: item.workingDirectory,
                resumeCommand: nil,
                confidence: .exact,
                candidates: []
            )
        case let .ambiguous(candidates):
            return .init(
                matched: false,
                providerSessionID: nil,
                harness: item.harness,
                runtime: item.harness,
                projectPath: item.workingDirectory,
                resumeCommand: nil,
                confidence: .ambiguous,
                candidates: candidates
            )
        case .unmatched:
            return .init(
                matched: false,
                providerSessionID: nil,
                harness: item.harness,
                runtime: item.harness,
                projectPath: item.workingDirectory,
                resumeCommand: nil,
                confidence: .none,
                candidates: []
            )
        }
    }

    /// Debug backstop for the uniqueness law. The assignment algorithm and
    /// the pickCandidate guard enforce it structurally; this catches any
    /// future regression the moment it happens instead of in Erik's roster.
    private func assertUniqueExactAssignments() {
        var seen: Set<String> = []
        for row in rows {
            if case let .exactResume(id) = row.state {
                assert(
                    seen.insert(id).inserted,
                    "Two restore rows carry the same conversation id (\(id))."
                )
            }
        }
    }

    // MARK: - Restore

    /// Restores every fresh-batch PARENT row headless. Older interruptions
    /// and helper shells restore only through explicit selection or a
    /// per-row action — a bulk button must never quietly recreate weeks of
    /// history, nor forty empty scaffolding shells whose scrollback is gone
    /// either way. Attach stays lazy: selected flows attach explicitly,
    /// everything else is adopted by converge or by the user when they are
    /// ready.
    func restoreAll() async {
        await restore(rowIDs: freshParentRows.map(\.id), attach: false)
    }

    /// Restores the selected rows and attaches each one as it verifies.
    func restoreSelected() async {
        await restore(rowIDs: rows.filter(\.isSelected).map(\.id), attach: true)
    }

    /// The older crash group currently mid-restore, so its header can show
    /// progress in place. Nil the moment the batch settles.
    @Published private(set) var restoringCrashGroupKey: HolyRestoreCrashGroupKey?

    /// Restores one older crash's PARENT rows headless — the same scope law
    /// as Restore All, applied to exactly that batch. Helper shells stay out
    /// of every bulk path; they restore only by explicit selection or a
    /// per-row action.
    func restoreCrashGroup(key: HolyRestoreCrashGroupKey) async {
        guard let section = olderCrashSections.first(where: { $0.key == key }),
              !section.parentRows.isEmpty else {
            return
        }
        restoringCrashGroupKey = key
        defer { restoringCrashGroupKey = nil }
        await restore(rowIDs: section.parentRows.map(\.id), attach: false)
    }

    func retry(rowID: UUID) async {
        await restore(rowIDs: [rowID], attach: false)
    }

    /// Restores (or adopts, when already live/restored) one row and attaches
    /// its surface. The lazy-attach path for headless rows.
    func attach(rowID: UUID) async {
        await restore(rowIDs: [rowID], attach: true)
    }

    func setSelected(_ selected: Bool, rowID: UUID) {
        updateRow(rowID) { $0.isSelected = selected }
    }

    /// Deletes every older archived record and drops those rows from the
    /// sheet. This boot's interruptions are untouched — the one thing the
    /// surface exists to protect is never in range of this button.
    ///
    /// Deletion goes through the adapter's archive-removal path, the same
    /// one Session History uses; nothing here knows how records are stored.
    /// Returns how many records were removed, so the caller can confirm what
    /// it just did rather than assume.
    @discardableResult
    func clearOlderInterruptions() -> Int {
        let archiveIDs = olderRows.map(\.id)
        guard !archiveIDs.isEmpty else { return 0 }
        adapter.deleteArchives(archiveIDs: archiveIDs)
        rows.removeAll { !$0.isFresh }
        return archiveIDs.count
    }

    /// Bulk selection for Select All / Select None. The caller passes the
    /// row ids currently visible (fresh, plus older when expanded), so the
    /// buttons act on what the user can see and nothing hidden.
    func setSelection(_ selected: Bool, rowIDs: [UUID]) {
        let targets = Set(rowIDs)
        for index in rows.indices where targets.contains(rows[index].id) {
            rows[index].isSelected = selected
        }
    }

    /// Resolves an ambiguous row to the candidate the user picked. The
    /// uniqueness law holds here too: a conversation id another row already
    /// carries (two ambiguous rows can list the same unclaimed candidate)
    /// can never be picked into a duplicate.
    func pickCandidate(rowID: UUID, candidateID: String) {
        guard let row = rows.first(where: { $0.id == rowID }),
              case let .ambiguous(candidates) = row.state,
              candidates.contains(where: { $0.id == candidateID }),
              HolyRestoreCommandBuilder.isSafeProviderSessionID(candidateID),
              !rows.contains(where: {
                  $0.id != rowID && $0.state == .exactResume(providerSessionID: candidateID)
              }) else {
            return
        }
        updateRow(rowID) { $0.state = .exactResume(providerSessionID: candidateID) }
        assertUniqueExactAssignments()
    }

    private func restore(rowIDs: [UUID], attach: Bool) async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }

        await runBounded(rowIDs: rowIDs) { [weak self] rowID in
            await self?.restoreOne(rowID: rowID, attach: attach)
        }
    }

    private func restoreOne(rowID: UUID, attach: Bool) async {
        guard let row = rows.first(where: { $0.id == rowID }) else { return }

        switch row.state {
        case .ambiguous, .conflict, .blocked, .wrongHost:
            return
        case .alreadyRestored:
            adopt(rowID: rowID, attach: attach)
        case let .exactResume(providerSessionID):
            await restoreExact(rowID: rowID, providerSessionID: providerSessionID, attach: attach)
        case .shellOnly:
            await recreate(rowID: rowID, demoteToShell: false, attach: attach)
        case .missingHistory:
            await recreate(rowID: rowID, demoteToShell: true, attach: attach)
        }
    }

    private func restoreExact(rowID: UUID, providerSessionID: String, attach: Bool) async {
        guard let row = rows.first(where: { $0.id == rowID }) else { return }
        updateRow(rowID) { $0.phase = .restoring }

        // Re-resolve at launch time: the command executes under the same
        // login-shell PATH that blinds the preflight probe, so the argv must
        // carry the absolute path, not a name the pane's shell may not find.
        // A nil here after preflight passed is a race; the bare name keeps
        // the failure visible in the pane instead of inventing a block.
        let executablePath = await environment.resolveExecutable(
            row.plannedLaunchSpec.runtime.rawValue
        )
        guard let resumeCommand = HolyRestoreCommandBuilder.renderedResumeCommand(
            runtime: row.plannedLaunchSpec.runtime,
            providerSessionID: providerSessionID,
            executablePath: executablePath
        ) else {
            updateRow(rowID) {
                $0.phase = .failed("No exact resume command exists for this runtime and id.")
            }
            return
        }

        var spec = row.plannedLaunchSpec
        spec.command = resumeCommand
        spec.initialInput = nil
        if let workingDirectory = resolvedWorkingDirectory(for: row) {
            spec.workingDirectory = workingDirectory
        }

        guard await createIfAbsent(rowID: rowID, spec: spec) else { return }

        // No post-restore re-resolve: the identity guarantee is the argv.
        // We launched `--resume <exact id>` as an argument array; a provider
        // that accepted it resumed that conversation, and `--resume` forks a
        // NEW session file, so re-resolving near "now" would contradict even
        // a perfectly correct restore.
        adopt(rowID: rowID, attach: attach)
    }

    private func recreate(rowID: UUID, demoteToShell: Bool, attach: Bool) async {
        guard let row = rows.first(where: { $0.id == rowID }) else { return }
        updateRow(rowID) { $0.phase = .restoring }

        var spec = row.plannedLaunchSpec
        if demoteToShell {
            // No history means no honest provider relaunch: replaying
            // `claude` would open a fresh conversation while the row claims
            // restore. Recreate a labeled shell in the cwd instead.
            spec.runtime = .shell
            spec.command = nil
        }
        spec.initialInput = nil
        if let workingDirectory = resolvedWorkingDirectory(for: row) {
            spec.workingDirectory = workingDirectory
        }

        guard await createIfAbsent(rowID: rowID, spec: spec) else { return }
        adopt(rowID: rowID, attach: attach)
    }

    /// Creates the exact identity unless it is already live (idempotency:
    /// retries adopt, never duplicate), then proves the session exists by
    /// inventory before reporting success.
    private func createIfAbsent(rowID: UUID, spec: HolySessionLaunchSpec) async -> Bool {
        guard let identity = HolyTmuxLiveIdentity(exactLaunchSpec: spec) else {
            updateRow(rowID) {
                $0.phase = .failed("The restored session has no complete tmux identity.")
            }
            return false
        }

        adapter.persistPlannedLaunchSpec(archiveID: rowID, launchSpec: spec)
        updateRow(rowID) { $0.plannedLaunchSpec = spec }

        switch await tmux.liveness(for: identity) {
        case .present:
            return true
        case let .undetermined(failure):
            updateRow(rowID) { $0.phase = .failed(failure.message) }
            return false
        case .absent:
            break
        }

        if let createFailure = await tmux.createDetached(for: spec) {
            updateRow(rowID) { $0.phase = .failed(createFailure) }
            return false
        }

        switch await tmux.liveness(for: identity) {
        case .present:
            return true
        case .absent:
            updateRow(rowID) {
                $0.phase = .failed("tmux did not report the restored session after creation.")
            }
            return false
        case let .undetermined(failure):
            updateRow(rowID) { $0.phase = .failed(failure.message) }
            return false
        }
    }

    private func adopt(rowID: UUID, attach: Bool) {
        guard let row = rows.first(where: { $0.id == rowID }) else { return }
        // A roster session with this Holy UUID means adoption already
        // happened (the archive row is retired); re-adopting would fail.
        if adapter.rosterOwnsSession(withHolyID: row.archived.sourceSessionID) {
            updateRow(rowID) { $0.phase = .restored(attached: true) }
            return
        }
        guard attach else {
            updateRow(rowID) { $0.phase = .restored(attached: false) }
            return
        }

        var attachSpec = row.plannedLaunchSpec
        attachSpec.tmux?.createIfMissing = false
        let attached = adapter.attachRestoredArchive(
            archiveID: rowID,
            launchSpec: attachSpec
        )
        updateRow(rowID) {
            $0.phase = attached
                ? .restored(attached: true)
                : .failed("The restored tmux session is live but could not be adopted into the roster.")
        }
    }

    // MARK: - Helpers

    private func resolvedWorkingDirectory(for row: HolyRestoreRow) -> String? {
        let candidate = row.archived.lastKnownWorkingDirectory
            ?? row.plannedLaunchSpec.workingDirectory
        guard let candidate = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
              !candidate.isEmpty else {
            return nil
        }
        return candidate
    }

    private func updateRow(_ rowID: UUID, _ mutate: (inout HolyRestoreRow) -> Void) {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
        mutate(&rows[index])
    }

    /// Runs one async operation per row id with at most
    /// `maxConcurrentRestores` in flight.
    private func runBounded(
        rowIDs: [UUID],
        _ operation: @escaping @Sendable (UUID) async -> Void
    ) async {
        await withTaskGroup(of: Void.self) { group in
            var nextIndex = 0
            while nextIndex < rowIDs.count, nextIndex < Self.maxConcurrentRestores {
                let rowID = rowIDs[nextIndex]
                group.addTask { await operation(rowID) }
                nextIndex += 1
            }
            while await group.next() != nil {
                guard nextIndex < rowIDs.count else { continue }
                let rowID = rowIDs[nextIndex]
                group.addTask { await operation(rowID) }
                nextIndex += 1
            }
        }
    }
}

// MARK: - Production services

/// Real tmux control built on the sanctioned lifecycle primitives and the
/// detached-create script. Never synthesizes identity, never attaches.
struct HolyRestoreTmuxService: HolyRestoreTmuxControlling {
    static let createTimeout: TimeInterval = 20

    func liveness(for identity: HolyTmuxLiveIdentity) async -> HolyTmuxLiveness {
        await HolyTmuxLifecycleService.verifyLiveIdentity(identity)
    }

    func createDetached(for launchSpec: HolySessionLaunchSpec) async -> String? {
        guard let command = HolyTmuxCommandBuilder.detachedCreateCommand(for: launchSpec) else {
            return "The session has no complete local tmux identity to create."
        }

        let result = await HolyRestoreProcessRunner.run(
            executablePath: command.executablePath,
            arguments: command.arguments,
            timeout: Self.createTimeout,
            environment: HolyTmuxLifecycleService.scrubbedTmuxEnvironment(
                ProcessInfo.processInfo.environment
            )
        )

        switch result {
        case let .failure(reason):
            return reason
        case let .success(output):
            guard output.exitCode == 0 else {
                let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return detail.isEmpty
                    ? "tmux session creation exited with status \(output.exitCode)."
                    : detail
            }
            return nil
        }
    }
}

struct HolyRestoreEnvironmentProbe: HolyRestoreEnvironmentProbing {
    func directoryExists(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// Same bound the resolver client's PATH probe uses: a login shell that
    /// hasn't produced `command -v` output in 15s is wedged on rc files or a
    /// network mount, and preflight must not hang the sheet behind it.
    private static let pathProbeTimeoutSeconds: TimeInterval = 15

    func resolveExecutable(_ name: String) async -> String? {
        // Names come from HolySessionRuntime raw values, but stay defensive:
        // this string lands inside a login-shell command line.
        guard name.range(of: "^[a-z0-9-]{1,32}$", options: .regularExpression) != nil else {
            return nil
        }
        // A Dock launch gets a login non-interactive shell: .zprofile loads,
        // .zshrc never does. `command -v` here sees homebrew (claude) but not
        // nvm-installed codex or the ~/.opencode/bin opencode, and the same
        // PATH governs the restored pane — hence absolute paths everywhere.
        let result = await HolyRestoreProcessRunner.run(
            executablePath: "/bin/zsh",
            arguments: ["-lc", "command -v \(name)"],
            timeout: Self.pathProbeTimeoutSeconds
        )
        if case let .success(output) = result, output.exitCode == 0 {
            let path = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            // Builtins/aliases can answer `command -v` with a non-path word;
            // only an absolute executable path is worth baking into argv.
            if path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return Self.wellKnownExecutablePath(name)
    }

    /// The install locations of the managers that only initialize in .zshrc,
    /// plus the resolver client's original four. Each entry names the real
    /// installer that produces it; extend only with a concrete sighting.
    static func wellKnownExecutablePath(_ name: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates = [
            "\(home)/.pyenv/shims/\(name)",     // pyenv
            "\(home)/.local/bin/\(name)",       // pipx / uv / user installs
            "/opt/homebrew/bin/\(name)",        // homebrew (Apple Silicon)
            "/usr/local/bin/\(name)",           // homebrew (Intel) / manual
            "\(home)/.opencode/bin/\(name)",    // opencode self-installer
            "\(home)/.bun/bin/\(name)",         // bun global installs
            "\(home)/.volta/bin/\(name)",       // volta shims
        ]
        if let nvmBin = newestNvmBinDirectory(home: home) {
            candidates.append("\(nvmBin)/\(name)")
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// nvm keeps one bin directory per node version and selects between them
    /// in .zshrc, which a login shell never runs. The newest version is the
    /// best stand-in for "what nvm would have picked".
    private static func newestNvmBinDirectory(home: String) -> String? {
        let versionsRoot = "\(home)/.nvm/versions/node"
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: versionsRoot) else {
            return nil
        }
        let best = entries
            .filter { $0.hasPrefix("v") }
            .compactMap { entry -> (components: [Int], name: String)? in
                let numbers = entry.dropFirst().split(separator: ".").compactMap { Int($0) }
                guard !numbers.isEmpty else { return nil }
                return (numbers, entry)
            }
            .max { lhs, rhs in
                lhs.components.lexicographicallyPrecedes(rhs.components)
            }
        guard let best else { return nil }
        return "\(versionsRoot)/\(best.name)/bin"
    }
}
