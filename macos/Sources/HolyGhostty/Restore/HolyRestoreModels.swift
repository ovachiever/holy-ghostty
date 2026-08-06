import Foundation

/// Cold-boot restore candidates split by boot event. `fresh` is the most
/// recent cold-boot batch — the sessions this reboot interrupted; `older`
/// is every earlier unrestored interruption. The split is the load-bearing
/// honesty of the whole surface: banners and preselection speak only for
/// `fresh`, while `older` stays reachable but never presumed wanted.
struct HolyCrashRestoreBatch: Equatable {
    var fresh: [HolyArchivedSession]
    var older: [HolyArchivedSession]

    static let empty = HolyCrashRestoreBatch(fresh: [], older: [])

    var isEmpty: Bool { fresh.isEmpty && older.isEmpty }
    var totalCount: Int { fresh.count + older.count }
}

/// What kind of restore a row can honestly offer. Derived from preflight
/// facts plus the resolve CLI's `confidence`, which is law: exact restores,
/// ambiguous asks the user to pick, none is only ever a labeled shell
/// recreate — never called a resume.
enum HolyRestoreRowState: Equatable, Sendable {
    /// Resolve returned confidence "exact": restore runs the exact resume
    /// command for this provider conversation id.
    case exactResume(providerSessionID: String)
    /// Resolve returned confidence "ambiguous": the user picks among
    /// candidates (first-prompt preview + end timestamp) before restoring.
    case ambiguous(candidates: [HolyRestoreResolveCandidate])
    /// A shell-runtime row: recreates cwd and the explicit command only.
    /// RAM, processes, PTY state, and scrollback are gone and never claimed.
    case shellOnly
    /// A provider row whose conversation could not be found (confidence
    /// "none"): offers a labeled shell-only recreate, never a resume.
    case missingHistory
    /// Remote sessions are out of scope for restore v1.
    case wrongHost
    /// The exact tmux identity is already live: the only correct action is
    /// adoption, never a duplicate create.
    case alreadyRestored
    /// Two rows (or a roster session) target the same tmux identity;
    /// restoring either would hijack or duplicate. User must resolve.
    case conflict(String)
    /// A precondition failed (missing cwd, missing executable, undetermined
    /// liveness, resolver unavailable). Retryable; never silently skipped.
    case blocked(String)

    var isActionable: Bool {
        switch self {
        case .exactResume, .ambiguous, .shellOnly, .missingHistory, .alreadyRestored:
            return true
        case .wrongHost, .conflict, .blocked:
            return false
        }
    }
}

/// Where a row is in its restore lifecycle. Orthogonal to the row state:
/// the state says what restore is possible, the phase says how far it got.
enum HolyRestoreRowPhase: Equatable, Sendable {
    case pending
    case preflighting
    case ready
    case restoring
    case restored(attached: Bool)
    case failed(String)
}

/// The post-restore identity confirmation verdict. Fail-closed asymmetric:
/// a positive contradiction (different id resolved for the same coordinates)
/// blocks; missing evidence is surfaced but never upgraded to a mismatch.
enum HolyRestoreIdentityConfirmation: Equatable, Sendable {
    case notApplicable
    case confirmed
    case mismatch(expected: String, resolved: String)
    case unverified(String)
}

/// The verified facts preflight gathered for one archived session. Pure data
/// so the row-state mapping is a total function testable without tmux, a
/// filesystem, or the resolve CLI.
struct HolyRestorePreflightContext: Equatable, Sendable {
    /// False when the session's transport is not local (restore v1).
    var hostSupported: Bool
    /// Whether the archived working directory exists on disk. Nil when the
    /// record carries no working directory at all.
    var workingDirectoryExists: Bool?
    var workingDirectory: String?
    /// Whether the provider executable resolves on PATH. Nil for shell rows,
    /// which use the login shell and need no provider binary.
    var executableAvailable: Bool?
    /// Resolve outcome for provider rows; nil for shell rows.
    var resolveOutcome: HolyRestoreResolveOutcome?
    /// Live probe of the exact persisted tmux identity; nil when the record
    /// carries no complete identity (nothing can be live under that name).
    var liveness: HolyTmuxLiveness?
    /// A roster session or a sibling restore row already owns this identity.
    var conflictReason: String?
}
