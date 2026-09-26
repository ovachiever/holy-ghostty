import Foundation

/// How the previous run of the app ended, decided from the liveness ledger
/// and the kernel — never from what an archive row happens to say.
enum HolyRestoreShutdownKind: String, Codable, Equatable, Sendable {
    /// The boot identity changed: a kernel panic, a power loss, or a
    /// deliberate restart. Every local tmux session died with the machine.
    case reboot
    /// Same boot, and the app recorded its own orderly exit. tmux survived
    /// the app; sessions still there are live, not interrupted.
    case cleanQuit
    /// Same boot, no orderly exit on record: the installer's kill, an app
    /// crash, or a force quit. tmux normally survived; anything missing now
    /// was lost somewhere the app could not watch.
    case appRelaunch

    var displayName: String {
        switch self {
        case .reboot: return "rebooted"
        case .cleanQuit: return "quit cleanly"
        case .appRelaunch: return "app relaunched without a clean quit"
        }
    }
}

/// The last shutdown as reconciled at launch: what kind it was, what the
/// app last saw live, and which archive rows it interrupted.
struct HolyRestoreShutdownEvent: Equatable, Sendable {
    let kind: HolyRestoreShutdownKind
    let previousBoot: HolyBootIdentity
    let currentBoot: HolyBootIdentity
    /// When the ledger was last written before the shutdown — the last
    /// moment the app can vouch the live set for.
    let lastSeenLiveAt: Date
    let cleanExitAt: Date?
    /// How many local sessions the ledger listed as live.
    let liveAtExitCount: Int
    /// The batch every session interrupted by the last shutdown carries.
    /// Carried forward from the ledger when this shutdown itself interrupted
    /// nothing, so the fresh section keeps naming the last real event.
    let interruptionBatchID: UUID?
    /// Sessions the ledger saw live that are archived now, in ledger order.
    let interruptedSourceSessionIDs: [UUID]
    /// Archives whose interruption record this launch rewrote (they were
    /// stranded in an older group or carried no cold-boot reason at all).
    let renewedArchiveIDs: [UUID]

    /// "rebooted Sep 26, 2026 at 6:16 AM" — for the fresh section header.
    var summary: String {
        switch kind {
        case .reboot:
            guard let bootTime = currentBoot.bootTime else { return kind.displayName }
            return "\(kind.displayName) \(bootTime.formatted(date: .abbreviated, time: .shortened))"
        case .cleanQuit:
            guard let cleanExitAt else { return kind.displayName }
            return "\(kind.displayName) \(cleanExitAt.formatted(date: .abbreviated, time: .shortened))"
        case .appRelaunch:
            return kind.displayName
        }
    }
}

/// Freshness keyed on reality. The supervisor's cold-boot sweep still stamps
/// what it can see; this law corrects the rows it cannot: a session the app
/// last saw live that is archived now was interrupted by the last shutdown,
/// whatever its previous interruption record says.
enum HolyRestoreFreshness {
    struct Reconciliation: Equatable {
        var archivedSessions: [HolyArchivedSession]
        var shutdown: HolyRestoreShutdownEvent?

        var didChange: Bool { !(shutdown?.renewedArchiveIDs.isEmpty ?? true) }
    }

    /// - Parameters:
    ///   - archivedSessions: the archive as restored (and possibly already
    ///     swept) at this launch.
    ///   - liveSessionIDs: every session observed live in THIS run so far.
    ///     A session live now was not interrupted, however it got here.
    ///   - ledger: the previous run's ledger, or nil on the first launch
    ///     after this build shipped — then the sweep's own batch law stands.
    ///   - launchStartedAt: rows archived at or after this instant were
    ///     swept by this launch and define its batch id when one exists.
    ///   - preferredBatchID: the batch a previous reconciliation of this same
    ///     launch already chose, so a re-run never mints a second id.
    static func reconcile(
        archivedSessions: [HolyArchivedSession],
        liveSessionIDs: Set<UUID>,
        ledger: HolyRestoreLivenessLedger?,
        currentBoot: HolyBootIdentity,
        launchStartedAt: Date,
        preferredBatchID: UUID? = nil,
        now: Date = .now
    ) -> Reconciliation {
        guard let ledger else {
            return .init(archivedSessions: archivedSessions, shutdown: nil)
        }

        let kind: HolyRestoreShutdownKind
        if ledger.boot.isKnown, currentBoot.isKnown, !currentBoot.isSameBoot(as: ledger.boot) {
            kind = .reboot
        } else if ledger.cleanExitAt != nil {
            kind = .cleanQuit
        } else {
            kind = .appRelaunch
        }

        let liveAtExit = ledger.liveSessions.filter(\.isLocal)
        let archivesBySource = Dictionary(
            archivedSessions.map { ($0.sourceSessionID, $0) },
            uniquingKeysWith: { newest, other in newest.archivedAt >= other.archivedAt ? newest : other }
        )
        let interrupted = liveAtExit.filter { live in
            !liveSessionIDs.contains(live.sourceSessionID)
                && archivesBySource[live.sourceSessionID]?.record.launchSpec.transport.kind == .local
        }
        let interruptedIDs = interrupted.map(\.sourceSessionID)

        let batchID: UUID?
        if interruptedIDs.isEmpty {
            batchID = ledger.lastInterruptionBatchID
        } else {
            batchID = preferredBatchID
                ?? launchSweepBatchID(in: archivedSessions, launchStartedAt: launchStartedAt)
                ?? UUID()
        }

        var renewed: [UUID] = []
        var reconciled = archivedSessions
        if let batchID, !interruptedIDs.isEmpty {
            let targets = Set(interruptedIDs)
            for index in reconciled.indices where targets.contains(reconciled[index].sourceSessionID) {
                let archived = reconciled[index]
                let alreadyInBatch = archived.recoveryBootBatchID == batchID
                    && HolyWorkspaceStore.isCrashRestoreCandidate(archived)
                if alreadyInBatch { continue }
                reconciled[index].recoveryBootBatchID = batchID
                reconciled[index].recoveryReason = renewedRecoveryReason(
                    kind: kind,
                    currentBoot: currentBoot,
                    lastSeenLiveAt: ledger.recordedAt,
                    previousReason: archived.recoveryReason
                )
                // The row joins this launch's batch at this launch's time,
                // the same convention the sweep uses; the conversation's
                // own anchor (`lastActivityAt`) is untouched.
                reconciled[index].archivedAt = now
                reconciled[index].record.updatedAt = now
                renewed.append(archived.id)
            }
        }

        let shutdown = HolyRestoreShutdownEvent(
            kind: kind,
            previousBoot: ledger.boot,
            currentBoot: currentBoot,
            lastSeenLiveAt: ledger.recordedAt,
            cleanExitAt: ledger.cleanExitAt,
            liveAtExitCount: liveAtExit.count,
            interruptionBatchID: batchID,
            interruptedSourceSessionIDs: interruptedIDs,
            renewedArchiveIDs: renewed
        )
        return .init(archivedSessions: reconciled, shutdown: shutdown)
    }

    /// The batch id the supervisor's sweep stamped at this launch, if it
    /// swept anything: the newest cold-boot candidate archived at or after
    /// the launch instant.
    static func launchSweepBatchID(
        in archivedSessions: [HolyArchivedSession],
        launchStartedAt: Date
    ) -> UUID? {
        archivedSessions
            .filter { $0.archivedAt >= launchStartedAt && HolyWorkspaceStore.isCrashRestoreCandidate($0) }
            .sorted { $0.archivedAt > $1.archivedAt }
            .compactMap(\.recoveryBootBatchID)
            .first
    }

    /// The renewed reason keeps the cold-boot prefix (the classifier every
    /// build has keyed on) and then says what actually happened.
    static func renewedRecoveryReason(
        kind: HolyRestoreShutdownKind,
        currentBoot: HolyBootIdentity,
        lastSeenLiveAt: Date,
        previousReason: String?
    ) -> String {
        var parts = [
            "\(HolySessionSupervisor.coldBootRecoveryReasonPrefix); "
                + "interrupted by the last shutdown (\(kind.displayName)).",
        ]
        if kind == .reboot, let bootTime = currentBoot.bootTime {
            let epoch = Int(bootTime.timeIntervalSince1970)
            var boot = "Boot at \(bootTime.formatted(date: .abbreviated, time: .standard)) (kern.boottime \(epoch)"
            if let uuid = currentBoot.sessionUUID {
                boot += ", kern.bootsessionuuid \(uuid)"
            }
            parts.append(boot + ").")
        }
        parts.append(
            "Last seen live \(lastSeenLiveAt.formatted(date: .abbreviated, time: .shortened))."
        )
        if let previousReason,
           !previousReason.hasPrefix(HolySessionSupervisor.coldBootRecoveryReasonPrefix) {
            parts.append("Before this shutdown: \(previousReason)")
        }
        return parts.joined(separator: " ")
    }
}
