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
    func executableExists(_ name: String) async -> Bool
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
    var confirmation: HolyRestoreIdentityConfirmation
    var isSelected: Bool
    /// True when the row belongs to the most recent cold-boot batch. Older
    /// rows render collapsed, are never preselected, and are excluded from
    /// Restore All and the interrupted count.
    let isFresh: Bool
}

/// Orchestrates crash restore: plan from cold-boot archives, preflight each
/// row to a single verdict, create detached tmux sessions in bounded
/// batches, confirm provider identity, and adopt instead of duplicating on
/// every retry.
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

    private let resolver: any HolyRestoreResolving
    private let tmux: any HolyRestoreTmuxControlling
    private let environment: any HolyRestoreEnvironmentProbing
    // Held strongly: the engine owns its adapter's lifetime. Production
    // passes a thin box that references the store weakly, so no cycle.
    private let adapter: any HolyRestoreWorkspaceAdapting

    init(
        resolver: any HolyRestoreResolving,
        tmux: any HolyRestoreTmuxControlling,
        environment: any HolyRestoreEnvironmentProbing,
        adapter: any HolyRestoreWorkspaceAdapting
    ) {
        self.resolver = resolver
        self.tmux = tmux
        self.environment = environment
        self.adapter = adapter
    }

    var freshRows: [HolyRestoreRow] { rows.filter(\.isFresh) }

    var olderRows: [HolyRestoreRow] { rows.filter { !$0.isFresh } }

    /// The honest headline count: only this boot's interruptions.
    var interruptedCount: Int { freshRows.count }

    var olderCount: Int { olderRows.count }

    var selectedCount: Int { rows.filter(\.isSelected).count }

    // MARK: - Plan

    /// Rebuilds rows from the adapter's candidate batch: fresh rows first,
    /// older after. Fresh rows preselect only when the batch is small
    /// (`freshPreselectionLimit`); older rows never preselect. Records
    /// without a complete tmux identity get one generated and persisted
    /// immediately, so the identity is stable for idempotent retries and
    /// later cold boots.
    func buildPlan() {
        let batch = adapter.restoreCandidateBatch
        let preselectFresh = batch.fresh.count <= Self.freshPreselectionLimit
        rows = batch.fresh.map {
            plannedRow(from: $0, isFresh: true, isSelected: preselectFresh)
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
            confirmation: .notApplicable,
            isSelected: isSelected,
            isFresh: isFresh
        )
    }

    // MARK: - Preflight

    func runPreflight() async {
        guard !isPreflighting else { return }
        isPreflighting = true
        defer { isPreflighting = false }

        let conflictReasons = planConflictReasons()
        await runBounded(rowIDs: rows.map(\.id)) { [weak self] rowID in
            await self?.preflightOne(rowID: rowID, conflictReasons: conflictReasons)
        }
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

    private func preflightOne(rowID: UUID, conflictReasons: [UUID: String]) async {
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
            context.executableAvailable = await environment.executableExists(runtime.rawValue)
            if let workingDirectory,
               context.workingDirectoryExists == true,
               context.executableAvailable == true {
                context.resolveOutcome = await resolver.resolve(.init(
                    workingDirectory: workingDirectory,
                    harness: runtime.rawValue,
                    nearUnixSeconds: Int(row.archived.lastActivityAt.timeIntervalSince1970)
                ))
            }
        }

        let state = HolyRestorePreflight.rowState(runtime: runtime, context: context)
        updateRow(rowID) {
            $0.state = state
            $0.phase = .ready
        }
    }

    // MARK: - Restore

    /// Restores every fresh-batch row headless. Older interruptions restore
    /// only through explicit selection or per-row action — a bulk button
    /// must never quietly recreate weeks of history. Attach stays lazy:
    /// selected flows attach explicitly, everything else is adopted by
    /// converge or by the user when they are ready.
    func restoreAll() async {
        await restore(rowIDs: freshRows.map(\.id), attach: false)
    }

    /// Restores the selected rows and attaches each one as it verifies.
    func restoreSelected() async {
        await restore(rowIDs: rows.filter(\.isSelected).map(\.id), attach: true)
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

    /// Bulk selection for Select All / Select None. The caller passes the
    /// row ids currently visible (fresh, plus older when expanded), so the
    /// buttons act on what the user can see and nothing hidden.
    func setSelection(_ selected: Bool, rowIDs: [UUID]) {
        let targets = Set(rowIDs)
        for index in rows.indices where targets.contains(rows[index].id) {
            rows[index].isSelected = selected
        }
    }

    /// Resolves an ambiguous row to the candidate the user picked.
    func pickCandidate(rowID: UUID, candidateID: String) {
        guard let row = rows.first(where: { $0.id == rowID }),
              case let .ambiguous(candidates) = row.state,
              candidates.contains(where: { $0.id == candidateID }),
              HolyRestoreCommandBuilder.isSafeProviderSessionID(candidateID) else {
            return
        }
        updateRow(rowID) { $0.state = .exactResume(providerSessionID: candidateID) }
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

        guard let resumeCommand = HolyRestoreCommandBuilder.renderedResumeCommand(
            runtime: row.plannedLaunchSpec.runtime,
            providerSessionID: providerSessionID
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

        let confirmation = await confirmIdentity(expected: providerSessionID, row: row)
        updateRow(rowID) { $0.confirmation = confirmation }
        if case let .mismatch(expected, resolved) = confirmation {
            updateRow(rowID) {
                $0.phase = .failed(
                    "Identity confirmation mismatch: expected \(expected), the resolver now reports \(resolved). The session was left running; retry or inspect before attaching."
                )
            }
            return
        }

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
        updateRow(rowID) { $0.confirmation = .notApplicable }
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

    /// Post-restore identity confirmation. Asymmetric on purpose: a positive
    /// contradiction (the same coordinates now resolve to a different id)
    /// blocks; a resolver outage or an inconclusive re-resolve is surfaced
    /// as unverified but never invents a mismatch.
    private func confirmIdentity(
        expected: String,
        row: HolyRestoreRow
    ) async -> HolyRestoreIdentityConfirmation {
        guard let workingDirectory = resolvedWorkingDirectory(for: row) else {
            return .unverified("No working directory to re-resolve against.")
        }

        let outcome = await resolver.resolve(.init(
            workingDirectory: workingDirectory,
            harness: row.plannedLaunchSpec.runtime.rawValue,
            nearUnixSeconds: Int(row.archived.lastActivityAt.timeIntervalSince1970)
        ))

        switch outcome {
        case let .resolverUnavailable(reason):
            return .unverified(reason)
        case let .resolved(resolution):
            if let resolvedID = resolution.providerSessionID {
                return resolvedID == expected
                    ? .confirmed
                    : .mismatch(expected: expected, resolved: resolvedID)
            }
            return .unverified(
                "Re-resolve returned confidence \(resolution.confidence.rawValue) without an id."
            )
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

    func executableExists(_ name: String) async -> Bool {
        // Names come from HolySessionRuntime raw values, but stay defensive:
        // this string lands inside a login-shell command line.
        guard name.range(of: "^[a-z0-9-]{1,32}$", options: .regularExpression) != nil else {
            return false
        }
        let result = await HolyRestoreProcessRunner.run(
            executablePath: "/bin/zsh",
            arguments: ["-lc", "command -v \(name)"],
            timeout: 15
        )
        guard case let .success(output) = result else { return false }
        return output.exitCode == 0
    }
}
