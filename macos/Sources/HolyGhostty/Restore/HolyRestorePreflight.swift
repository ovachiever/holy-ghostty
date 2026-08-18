import Foundation

/// Maps preflight facts to the one row state they support. A total, pure
/// function: every archived session gets exactly one verdict, and every
/// verdict names its evidence. Precedence is deliberate law:
///
/// 1. Unsupported host — nothing below can even be probed reliably in v1.
/// 2. Identity conflict — restoring would hijack or duplicate a target.
/// 3. Live identity — adoption is the only correct action; everything else
///    (broken cwd, dead resolver) is irrelevant while the session lives.
/// 4. Undetermined liveness — fail-closed; unknown is never absence.
/// 5. Local preconditions — cwd, provider executable.
/// 6. The resolver's confidence verdict — exact / ambiguous / none.
enum HolyRestorePreflight {
    static func rowState(
        runtime: HolySessionRuntime,
        context: HolyRestorePreflightContext
    ) -> HolyRestoreRowState {
        guard context.hostSupported else {
            return .wrongHost
        }

        if let conflictReason = context.conflictReason {
            return .conflict(conflictReason)
        }

        switch context.liveness {
        case .present:
            return .alreadyRestored
        case let .undetermined(failure):
            return .blocked(failure.message)
        case .absent, nil:
            break
        }

        if runtime == .shell {
            // Shell rows never consult the resolver; a vanished cwd is still
            // a blocker because recreating "the same shell" elsewhere lies.
            if context.workingDirectoryExists == false {
                return .blocked(missingDirectoryReason(context.workingDirectory))
            }
            return .shellOnly
        }

        if context.workingDirectoryExists == false {
            return .blocked(missingDirectoryReason(context.workingDirectory))
        }
        guard context.workingDirectory?.isEmpty == false else {
            return .blocked(
                "No working directory was recorded for this session, so its conversation cannot be resolved."
            )
        }
        if context.executable == .missing {
            // Name what was searched. The old message said "on PATH" and meant
            // the app's login-shell PATH, which is neither the PATH the
            // restored pane runs under nor anywhere a version manager installs.
            return .blocked(
                "The \(runtime.rawValue) executable was not found on the tmux server's PATH "
                    + "or in known tool directories."
            )
        }

        switch context.resolveOutcome {
        case nil:
            return .blocked("The conversation resolver has not run yet.")
        case let .resolverUnavailable(reason):
            return .blocked(reason)
        case let .resolved(resolution):
            switch resolution.confidence {
            case .exact:
                guard let providerSessionID = resolution.providerSessionID,
                      HolyRestoreCommandBuilder.isSafeProviderSessionID(providerSessionID) else {
                    return .blocked(
                        "The resolver returned a provider session id outside the allowed character set."
                    )
                }
                return .exactResume(providerSessionID: providerSessionID)
            case .ambiguous:
                return .ambiguous(candidates: resolution.candidates)
            case .none:
                return .missingHistory
            }
        }
    }

    private static func missingDirectoryReason(_ workingDirectory: String?) -> String {
        if let workingDirectory, !workingDirectory.isEmpty {
            return "The working directory \(workingDirectory) no longer exists."
        }
        return "The recorded working directory no longer exists."
    }
}
