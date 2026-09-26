import AppKit
import Foundation
import GhosttyKit
import Testing
@testable import Ghostty

// Freshness keyed on reality (mn-3c4b23). After the 2026-09-26 kernel panic
// the sheet showed 5 fresh and 38 older rows in 11 groups while 39 sessions
// had been live; three live sessions appeared nowhere. The law under test:
// every session the app last saw live that is archived now was interrupted
// by the last shutdown, whatever its old interruption record says, and the
// kernel's boot identity — not an archive row — decides whether that
// shutdown was a reboot.

// MARK: - Fixtures

private let coldBootReason =
    "Saved layout — the holy tmux server was not running at launch (probably a macOS reboot). Relaunch from history to recreate."
private let validatorReason =
    "Recovery archived this session because its tmux session is no longer available: holy-x"

private let previousBoot = HolyBootIdentity(
    sessionUUID: "0F4B9E2A-PREVIOUS-BOOT",
    bootTime: Date(timeIntervalSince1970: 1_790_300_000)
)
/// kern.boottime measured on the panicked machine 2026-09-26: sec 1790421415.
private let panicBoot = HolyBootIdentity(
    sessionUUID: "40962879-B7EE-4F13-AF6E-E7266EF5E732",
    bootTime: Date(timeIntervalSince1970: 1_790_421_415)
)
private let launchAt = Date(timeIntervalSince1970: 1_790_440_000)
private let priorRelaunchAt = Date(timeIntervalSince1970: 1_790_280_000)

private func archived(
    source: UUID = UUID(),
    title: String = "Lane",
    archivedAt: Date,
    reason: String? = coldBootReason,
    bootBatchID: UUID? = nil,
    transport: HolySessionTransportSpec = .local
) -> HolyArchivedSession {
    var spec = HolySessionLaunchSpec.interactiveTmuxShell(title: title)
    spec.transport = transport
    return .init(
        sourceSessionID: source,
        record: .init(launchSpec: spec),
        phase: .completed,
        preview: "",
        signals: [],
        commandTelemetry: .empty,
        budgetTelemetry: .empty,
        runtimeTelemetry: .empty,
        gitSnapshot: nil,
        lastKnownWorkingDirectory: nil,
        lastActivityAt: archivedAt.addingTimeInterval(-600),
        archivedAt: archivedAt,
        recoveryReason: reason,
        recoveryBootBatchID: bootBatchID
    )
}

private func live(_ source: UUID, title: String = "Lane", isLocal: Bool = true) -> HolyRestoreLivenessLedger.LiveSession {
    .init(
        sourceSessionID: source,
        title: title,
        isLocal: isLocal,
        tmuxSocketName: "holy",
        tmuxSessionName: "holy-\(source.uuidString.prefix(8))"
    )
}

private func ledger(
    boot: HolyBootIdentity = previousBoot,
    recordedAt: Date = launchAt.addingTimeInterval(-3_600),
    live sessions: [HolyRestoreLivenessLedger.LiveSession],
    cleanExitAt: Date? = nil,
    lastInterruptionBatchID: UUID? = nil
) -> HolyRestoreLivenessLedger {
    .init(
        boot: boot,
        recordedAt: recordedAt,
        liveSessions: sessions,
        cleanExitAt: cleanExitAt,
        lastInterruptionBatchID: lastInterruptionBatchID
    )
}

// MARK: - Panic / clean quit / installer relaunch (pure)

struct HolyRestoreFreshnessReconcileTests {
    /// The 09-26 shape: the boot changed; 39 sessions were live. Some were
    /// swept by this launch (batch Y), some still carry the 09-24 installer
    /// relaunch's batch (they were readopted afterwards and never renewed),
    /// some were archived with no cold-boot reason at all (hidden), some by
    /// the validator without a batch. Every one of them is fresh under Y.
    @Test func panicMakesEverySessionLiveAtExitFreshUnderOneBatch() throws {
        let sweepBatch = UUID()
        let staleBatch = UUID()
        let swept = (0..<5).map { _ in UUID() }
        let stranded = (0..<27).map { _ in UUID() }
        let hidden = (0..<3).map { _ in UUID() }
        let validated = (0..<4).map { _ in UUID() }
        let deadSince0920 = UUID()

        var archives: [HolyArchivedSession] = []
        archives += swept.map { archived(source: $0, archivedAt: launchAt.addingTimeInterval(1), bootBatchID: sweepBatch) }
        archives += stranded.map { archived(source: $0, archivedAt: priorRelaunchAt, bootBatchID: staleBatch) }
        archives += hidden.map { archived(source: $0, title: "Egora", archivedAt: launchAt.addingTimeInterval(2), reason: nil) }
        archives += validated.map { archived(source: $0, archivedAt: launchAt.addingTimeInterval(3), reason: validatorReason) }
        archives.append(archived(source: deadSince0920, archivedAt: priorRelaunchAt.addingTimeInterval(-4 * 86_400), bootBatchID: UUID()))

        let liveAtExit = (swept + stranded + hidden + validated).map { live($0) }
        let result = HolyRestoreFreshness.reconcile(
            archivedSessions: archives,
            liveSessionIDs: [],
            ledger: ledger(live: liveAtExit),
            currentBoot: panicBoot,
            launchStartedAt: launchAt,
            now: launchAt.addingTimeInterval(5)
        )

        let shutdown = try #require(result.shutdown)
        #expect(shutdown.kind == .reboot)
        #expect(shutdown.liveAtExitCount == 39)
        #expect(shutdown.interruptedSourceSessionIDs.count == 39)
        #expect(shutdown.interruptionBatchID == sweepBatch)
        // The 5 swept rows already carried the batch; the other 34 were renewed.
        #expect(shutdown.renewedArchiveIDs.count == 34)

        let batch = HolyWorkspaceStore.crashRestoreBatch(
            from: result.archivedSessions,
            freshBatchID: shutdown.interruptionBatchID
        )
        #expect(batch.fresh.count == 39)
        #expect(Set(batch.fresh.map(\.sourceSessionID)) == Set(swept + stranded + hidden + validated))
        #expect(batch.older.map(\.sourceSessionID) == [deadSince0920])

        // The hidden rows now carry a cold-boot reason and the renewed rows
        // name the boot the kernel reported.
        let egora = try #require(result.archivedSessions.first { $0.sourceSessionID == hidden[0] })
        #expect(HolyWorkspaceStore.isCrashRestoreCandidate(egora))
        #expect(egora.recoveryReason?.contains("kern.boottime 1790421415") == true)
        #expect(egora.recoveryReason?.contains(panicBoot.sessionUUID!) == true)
        #expect(egora.archivedAt == launchAt.addingTimeInterval(5))
        // A validator reason survives as history, after the cold-boot prefix.
        let validatedRow = try #require(result.archivedSessions.first { $0.sourceSessionID == validated[0] })
        #expect(validatedRow.recoveryReason?.hasPrefix(HolySessionSupervisor.coldBootRecoveryReasonPrefix) == true)
        #expect(validatedRow.recoveryReason?.contains("Before this shutdown: \(validatorReason)") == true)
        // The sweep's own rows are untouched.
        let sweptRow = try #require(result.archivedSessions.first { $0.sourceSessionID == swept[0] })
        #expect(sweptRow.archivedAt == launchAt.addingTimeInterval(1))
        #expect(sweptRow.recoveryReason == coldBootReason)
    }

    /// Cmd-Q, tmux survives, relaunch: the ledger carries a clean exit under
    /// the same boot, every live session is live again, nothing is renewed,
    /// and the fresh section keeps naming the last real shutdown's batch.
    @Test func cleanQuitInterruptsNothingAndCarriesTheLastBatchForward() throws {
        let carried = UUID()
        let a = UUID(), b = UUID()
        let leftover = archived(source: UUID(), archivedAt: launchAt.addingTimeInterval(-7_200), bootBatchID: carried)
        let older = archived(source: UUID(), archivedAt: priorRelaunchAt, bootBatchID: UUID())

        let result = HolyRestoreFreshness.reconcile(
            archivedSessions: [leftover, older],
            liveSessionIDs: [a, b],
            ledger: ledger(
                live: [live(a), live(b)],
                cleanExitAt: launchAt.addingTimeInterval(-60),
                lastInterruptionBatchID: carried
            ),
            currentBoot: previousBoot,
            launchStartedAt: launchAt,
            now: launchAt
        )

        let shutdown = try #require(result.shutdown)
        #expect(shutdown.kind == .cleanQuit)
        #expect(shutdown.cleanExitAt == launchAt.addingTimeInterval(-60))
        #expect(shutdown.interruptedSourceSessionIDs.isEmpty)
        #expect(shutdown.renewedArchiveIDs.isEmpty)
        #expect(shutdown.interruptionBatchID == carried)
        #expect(result.archivedSessions == [leftover, older])
        #expect(!result.didChange)

        let batch = HolyWorkspaceStore.crashRestoreBatch(from: result.archivedSessions, freshBatchID: carried)
        #expect(batch.fresh.map(\.id) == [leftover.id])
        #expect(batch.older.map(\.id) == [older.id])
    }

    /// The installer's pkill: same boot, no clean exit on record. tmux kept
    /// most sessions, which are live again; one the validator archived (no
    /// batch id) was live at the kill and is now this launch's interruption.
    @Test func installerRelaunchRenewsOnlyWhatWasLiveAndIsGone() throws {
        let a = UUID(), b = UUID(), lost = UUID()
        let lostRow = archived(source: lost, archivedAt: launchAt.addingTimeInterval(1), reason: validatorReason)
        let unrelated = archived(source: UUID(), archivedAt: priorRelaunchAt, bootBatchID: UUID())

        let result = HolyRestoreFreshness.reconcile(
            archivedSessions: [lostRow, unrelated],
            liveSessionIDs: [a, b],
            ledger: ledger(live: [live(a), live(b), live(lost)]),
            currentBoot: previousBoot,
            launchStartedAt: launchAt,
            now: launchAt.addingTimeInterval(2)
        )

        let shutdown = try #require(result.shutdown)
        #expect(shutdown.kind == .appRelaunch)
        #expect(shutdown.interruptedSourceSessionIDs == [lost])
        #expect(shutdown.renewedArchiveIDs == [lostRow.id])
        let batchID = try #require(shutdown.interruptionBatchID)
        let renewed = try #require(result.archivedSessions.first { $0.sourceSessionID == lost })
        #expect(renewed.recoveryBootBatchID == batchID)
        #expect(renewed.recoveryReason?.contains("app relaunched without a clean quit") == true)
        #expect(renewed.recoveryReason?.contains("kern.boottime") == false)

        let batch = HolyWorkspaceStore.crashRestoreBatch(from: result.archivedSessions, freshBatchID: batchID)
        #expect(batch.fresh.map(\.sourceSessionID) == [lost])
        #expect(batch.older.map(\.id) == [unrelated.id])
    }

    @Test func withoutALedgerTheSweepsOwnLawStands() {
        let row = archived(archivedAt: launchAt, bootBatchID: UUID())
        let result = HolyRestoreFreshness.reconcile(
            archivedSessions: [row],
            liveSessionIDs: [],
            ledger: nil,
            currentBoot: panicBoot,
            launchStartedAt: launchAt
        )
        #expect(result.shutdown == nil)
        #expect(result.archivedSessions == [row])
        #expect(!result.didChange)
    }

    @Test func aSessionObservedLiveThisRunIsNeverRenewedEvenWhenArchivedLater() throws {
        let revived = UUID()
        // Live at launch, killed by the user three hours later: an archive
        // with no recovery reason, exactly as the roster's archive path
        // writes it. Not interrupted by any shutdown.
        let row = archived(source: revived, archivedAt: launchAt.addingTimeInterval(3 * 3_600), reason: nil)
        let result = HolyRestoreFreshness.reconcile(
            archivedSessions: [row],
            liveSessionIDs: [revived],
            ledger: ledger(live: [live(revived)]),
            currentBoot: panicBoot,
            launchStartedAt: launchAt,
            now: launchAt.addingTimeInterval(3 * 3_600 + 1)
        )
        let shutdown = try #require(result.shutdown)
        #expect(shutdown.kind == .reboot)
        #expect(shutdown.interruptedSourceSessionIDs.isEmpty)
        #expect(result.archivedSessions == [row])
    }

    @Test func remoteSessionsAreOutsideTheLocalLaw() throws {
        let remote = UUID()
        let row = archived(
            source: remote,
            archivedAt: launchAt,
            reason: nil,
            transport: .init(kind: .ssh, hostLabel: "MacBook", sshDestination: "erik@mb")
        )
        let result = HolyRestoreFreshness.reconcile(
            archivedSessions: [row],
            liveSessionIDs: [],
            ledger: ledger(live: [live(remote, isLocal: false)]),
            currentBoot: panicBoot,
            launchStartedAt: launchAt
        )
        let shutdown = try #require(result.shutdown)
        #expect(shutdown.liveAtExitCount == 0)
        #expect(shutdown.interruptedSourceSessionIDs.isEmpty)
        #expect(result.archivedSessions == [row])
    }

    /// Opening the sheet re-runs the law. The second pass must reuse the
    /// first pass's batch and change nothing already renewed.
    @Test func reconcileIsIdempotentAcrossAPreferredBatch() throws {
        let s1 = UUID(), s2 = UUID()
        let rows = [
            archived(source: s1, archivedAt: priorRelaunchAt, bootBatchID: UUID()),
            archived(source: s2, archivedAt: priorRelaunchAt, bootBatchID: UUID()),
        ]
        let first = HolyRestoreFreshness.reconcile(
            archivedSessions: rows,
            liveSessionIDs: [],
            ledger: ledger(live: [live(s1), live(s2)]),
            currentBoot: panicBoot,
            launchStartedAt: launchAt,
            now: launchAt
        )
        let firstBatch = try #require(first.shutdown?.interruptionBatchID)
        #expect(first.shutdown?.renewedArchiveIDs.count == 2)

        let second = HolyRestoreFreshness.reconcile(
            archivedSessions: first.archivedSessions,
            liveSessionIDs: [],
            ledger: ledger(live: [live(s1), live(s2)]),
            currentBoot: panicBoot,
            launchStartedAt: launchAt,
            preferredBatchID: firstBatch,
            now: launchAt.addingTimeInterval(300)
        )
        #expect(second.shutdown?.interruptionBatchID == firstBatch)
        #expect(second.shutdown?.renewedArchiveIDs.isEmpty == true)
        #expect(second.archivedSessions == first.archivedSessions)
    }

    @Test func aRebootWhereNothingWasLiveIsStillReportedAsAReboot() throws {
        let result = HolyRestoreFreshness.reconcile(
            archivedSessions: [],
            liveSessionIDs: [],
            ledger: ledger(live: []),
            currentBoot: panicBoot,
            launchStartedAt: launchAt
        )
        let shutdown = try #require(result.shutdown)
        #expect(shutdown.kind == .reboot)
        #expect(shutdown.interruptionBatchID == nil)
        #expect(shutdown.summary.hasPrefix("rebooted "))
    }

    @Test func freshSectionTitleNamesTheShutdown() {
        #expect(HolyRestoreSheet.freshSectionTitle(shutdown: nil) == "Interrupted by the last shutdown")
        let event = HolyRestoreShutdownEvent(
            kind: .appRelaunch,
            previousBoot: previousBoot,
            currentBoot: previousBoot,
            lastSeenLiveAt: launchAt,
            cleanExitAt: nil,
            liveAtExitCount: 3,
            interruptionBatchID: UUID(),
            interruptedSourceSessionIDs: [],
            renewedArchiveIDs: []
        )
        #expect(HolyRestoreSheet.freshSectionTitle(shutdown: event)
            == "Interrupted by the last shutdown · app relaunched without a clean quit")
    }
}

// MARK: - Batch scoping by a known shutdown

struct HolyRestoreFreshnessBatchScopingTests {
    @Test func aKnownBatchIsFreshEvenWhenEmptyAndNeverPromotesAnOlderGroup() {
        let known = UUID()
        let olderBatch = UUID()
        let rows = [
            archived(archivedAt: launchAt, bootBatchID: olderBatch),
            archived(archivedAt: launchAt.addingTimeInterval(-86_400), bootBatchID: olderBatch),
        ]

        let scoped = HolyWorkspaceStore.crashRestoreBatch(from: rows, freshBatchID: known)
        #expect(scoped.fresh.isEmpty)
        #expect(scoped.older.count == 2)

        // Without a known shutdown the newest-batch law still applies.
        let legacy = HolyWorkspaceStore.crashRestoreBatch(from: rows, freshBatchID: nil)
        #expect(legacy.fresh.count == 2)
        #expect(legacy == HolyWorkspaceStore.crashRestoreBatch(from: rows))
    }

    @Test func aNewerValidatorRowNeverStealsFreshFromTheKnownBatch() {
        let known = UUID()
        let rows = [
            archived(archivedAt: launchAt.addingTimeInterval(600), reason: validatorReason),
            archived(archivedAt: launchAt, bootBatchID: known),
        ]
        let scoped = HolyWorkspaceStore.crashRestoreBatch(from: rows, freshBatchID: known)
        #expect(scoped.fresh.map(\.recoveryBootBatchID) == [known])
        #expect(scoped.older.count == 1)
    }
}

// MARK: - Boot identity and the ledger file

struct HolyRestoreBootIdentityTests {
    @Test func theKernelAnswersOnThisMachine() {
        let boot = HolyBootIdentity.current()
        #expect(boot.isKnown)
        #expect(boot.sessionUUID != nil)
        #expect(boot.bootTime != nil)
        #expect(boot.isSameBoot(as: HolyBootIdentity.current()))
    }

    @Test func theSessionUUIDDecidesWhenBothSidesHaveIt() {
        let sameTimeOtherBoot = HolyBootIdentity(sessionUUID: "other", bootTime: previousBoot.bootTime)
        #expect(!previousBoot.isSameBoot(as: sameTimeOtherBoot))
        let shiftedClock = HolyBootIdentity(
            sessionUUID: previousBoot.sessionUUID,
            bootTime: previousBoot.bootTime?.addingTimeInterval(1)
        )
        #expect(previousBoot.isSameBoot(as: shiftedClock))
    }

    @Test func withoutAUUIDTheBootSecondDecidesAndUnknownIsNeverSame() {
        let a = HolyBootIdentity(sessionUUID: nil, bootTime: Date(timeIntervalSince1970: 1_790_421_415.2))
        let b = HolyBootIdentity(sessionUUID: nil, bootTime: Date(timeIntervalSince1970: 1_790_421_415.9))
        #expect(a.isSameBoot(as: b))
        #expect(!a.isSameBoot(as: HolyBootIdentity(sessionUUID: nil, bootTime: nil)))
        #expect(!HolyBootIdentity(sessionUUID: nil, bootTime: nil).isKnown)
    }
}

struct HolyRestoreLivenessLedgerFileTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-restore-ledger-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func ledgerRoundTripsExactlyThroughItsDurableFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = HolyRestoreLivenessLedgerStore.url(in: directory)
        #expect(HolyRestoreLivenessLedgerStore.load(from: url) == nil)

        let carried = UUID()
        let original = ledger(
            live: [live(UUID(), title: "Egora"), live(UUID(), title: "SubDub", isLocal: false)],
            cleanExitAt: launchAt,
            lastInterruptionBatchID: carried
        )
        try HolyRestoreLivenessLedgerStore.save(original, to: url)

        let loaded = try #require(HolyRestoreLivenessLedgerStore.load(from: url))
        #expect(loaded == original)
        #expect(loaded.version == HolyRestoreLivenessLedger.currentVersion)
        #expect(loaded.lastInterruptionBatchID == carried)
        // No temp file is left behind by the rename.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(leftovers == [HolyRestoreLivenessLedgerStore.filename])
    }

    @Test func aRewriteReplacesTheWholeFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = HolyRestoreLivenessLedgerStore.url(in: directory)
        try HolyRestoreLivenessLedgerStore.save(ledger(live: [live(UUID()), live(UUID())]), to: url)
        try HolyRestoreLivenessLedgerStore.save(ledger(live: []), to: url)
        #expect(HolyRestoreLivenessLedgerStore.load(from: url)?.liveSessions.isEmpty == true)
    }
}

// MARK: - Store wiring (app-hosted: needs a Ghostty.App for the supervisor)

@MainActor
@Suite(.serialized)
struct HolyRestoreFreshnessStoreTests {
    @Test func launchReconciliationRenewsLedgerLiveArchivesWritesTheLedgerAndKeepsRuns() async throws {
        let config = try TemporaryConfig("command = /bin/sleep 60\nshell-integration = none\n")
        let ghostty = Ghostty.App(configPath: config.temporaryFile.path)
        _ = try #require(ghostty.app)
        var saves = 0
        let supervisor = HolySessionSupervisor(
            ghostty: ghostty,
            seedDefaultSession: false,
            saveWorkspace: { _, _, _, _ in saves += 1 }
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-restore-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // The previous run: a different boot, two sessions live.
        let stranded = UUID(), hidden = UUID()
        try HolyRestoreLivenessLedgerStore.save(
            ledger(live: [live(stranded, title: "Yed Prior"), live(hidden, title: "Egora")]),
            to: HolyRestoreLivenessLedgerStore.url(in: directory)
        )

        let store = HolyWorkspaceStore(sessionSupervisor: supervisor, restoreStateDirectory: directory)
        let staleBatch = UUID()
        store.applySessionStoreStateForTesting(.init(
            sessions: [],
            savedTemplates: [],
            archivedSessions: [
                archived(source: stranded, title: "Yed Prior", archivedAt: priorRelaunchAt, bootBatchID: staleBatch),
                archived(source: hidden, title: "Egora", archivedAt: launchAt, reason: nil),
            ],
            selectedSessionID: nil,
            selectedArchivedSessionID: nil,
            paneLayout: .single
        ))
        #expect(store.lastShutdown == nil)
        #expect(store.crashRestoreBatch.fresh.count == 1)

        store.reconcileRestoreFreshnessAtLaunch(launchStartedAt: Date())

        let shutdown = try #require(store.lastShutdown)
        #expect(shutdown.kind == .reboot)
        #expect(Set(shutdown.interruptedSourceSessionIDs) == [stranded, hidden])
        #expect(shutdown.renewedArchiveIDs.count == 2)
        #expect(store.crashRestoreBatch.fresh.count == 2)
        #expect(store.crashRestoreBatch.older.isEmpty)
        #expect(store.archivedSessions.allSatisfy { $0.recoveryBootBatchID == shutdown.interruptionBatchID })

        // This boot's ledger replaced the previous one and carries the batch.
        let written = try #require(HolyRestoreLivenessLedgerStore.load(
            from: HolyRestoreLivenessLedgerStore.url(in: directory)
        ))
        #expect(written.boot.sessionUUID == HolyBootIdentity.current().sessionUUID)
        #expect(written.liveSessions.isEmpty)
        #expect(written.cleanExitAt == nil)
        #expect(written.lastInterruptionBatchID == shutdown.interruptionBatchID)

        // A second reconcile (the sheet opening) changes nothing.
        #expect(store.reconcileRestoreFreshness() == false)
        #expect(store.lastShutdown?.interruptionBatchID == shutdown.interruptionBatchID)

        // A restore run lands in the published list and on disk.
        let run = HolyRestoreRunRecord(
            startedAt: launchAt,
            finishedAt: launchAt.addingTimeInterval(4),
            trigger: .restoreAll,
            attach: false,
            rows: [
                .init(
                    archiveID: UUID(), sourceSessionID: stranded, title: "Yed Prior", runtime: "claude",
                    workingDirectory: "/tmp/yed", providerSessionID: "abc-123", outcome: .restored(attached: false)
                ),
            ]
        )
        store.recordRestoreRun(run)
        #expect(store.restoreRuns == [run])
        #expect(HolyRestoreRunLogStore.load(from: HolyRestoreRunLogStore.url(in: directory)) == [run])

        withExtendedLifetime(ghostty) {}
    }
}
