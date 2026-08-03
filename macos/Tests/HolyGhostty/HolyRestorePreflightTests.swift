import Foundation
import Testing
@testable import Ghostty

// Preflight is a total function from verified facts to a row state. The
// matrix below pins the precedence: host support, then identity conflicts,
// then live-duplicate adoption, then fail-closed liveness, then local
// preconditions, and only then the resolver's confidence verdict.
struct HolyRestorePreflightTests {
    private func context(
        hostSupported: Bool = true,
        workingDirectoryExists: Bool? = true,
        workingDirectory: String? = "/tmp/project",
        executableAvailable: Bool? = true,
        resolveOutcome: HolyRestoreResolveOutcome? = nil,
        liveness: HolyTmuxLiveness? = .absent,
        conflictReason: String? = nil
    ) -> HolyRestorePreflightContext {
        .init(
            hostSupported: hostSupported,
            workingDirectoryExists: workingDirectoryExists,
            workingDirectory: workingDirectory,
            executableAvailable: executableAvailable,
            resolveOutcome: resolveOutcome,
            liveness: liveness,
            conflictReason: conflictReason
        )
    }

    private func exactOutcome(id: String = "ae3d63af-1111") -> HolyRestoreResolveOutcome {
        .resolved(.init(
            matched: true,
            providerSessionID: id,
            harness: "claude-code",
            runtime: "claude",
            projectPath: "/tmp/project",
            resumeCommand: "claude --resume \(id)",
            confidence: .exact,
            candidates: []
        ))
    }

    private func unmatchedOutcome(
        confidence: HolyRestoreResolution.Confidence,
        candidates: [HolyRestoreResolveCandidate] = []
    ) -> HolyRestoreResolveOutcome {
        .resolved(.init(
            matched: false,
            providerSessionID: nil,
            harness: "claude-code",
            runtime: "claude",
            projectPath: "/tmp/project",
            resumeCommand: nil,
            confidence: confidence,
            candidates: candidates
        ))
    }

    // MARK: - Confidence is law

    @Test func exactConfidenceProducesExactResume() {
        let state = HolyRestorePreflight.rowState(
            runtime: .claude,
            context: context(resolveOutcome: exactOutcome(id: "abc-123"))
        )
        #expect(state == .exactResume(providerSessionID: "abc-123"))
    }

    @Test func ambiguousConfidenceCarriesCandidatesToThePicker() {
        let candidates: [HolyRestoreResolveCandidate] = [
            .init(id: "aaa", timestampEnd: 100, preview: "first"),
            .init(id: "bbb", timestampEnd: 200, preview: "second"),
        ]
        let state = HolyRestorePreflight.rowState(
            runtime: .claude,
            context: context(resolveOutcome: unmatchedOutcome(
                confidence: .ambiguous,
                candidates: candidates
            ))
        )
        #expect(state == .ambiguous(candidates: candidates))
    }

    @Test func noneConfidenceIsMissingHistoryNeverAResume() {
        let state = HolyRestorePreflight.rowState(
            runtime: .claude,
            context: context(resolveOutcome: unmatchedOutcome(confidence: .none))
        )
        #expect(state == .missingHistory)
    }

    @Test func resolverUnavailableBlocksInsteadOfGuessing() {
        let state = HolyRestorePreflight.rowState(
            runtime: .claude,
            context: context(resolveOutcome: .resolverUnavailable("CLI missing"))
        )
        #expect(state == .blocked("CLI missing"))
    }

    @Test func unsafeResolvedIDBlocksInsteadOfQuoting() {
        let state = HolyRestorePreflight.rowState(
            runtime: .claude,
            context: context(resolveOutcome: exactOutcome(id: "bad; rm -rf ~"))
        )
        guard case .blocked = state else {
            Issue.record("Expected blocked, got \(state)")
            return
        }
    }

    // MARK: - Shell rows

    @Test func shellRuntimeIsShellOnlyWithoutTouchingTheResolver() {
        let state = HolyRestorePreflight.rowState(
            runtime: .shell,
            context: context(executableAvailable: nil, resolveOutcome: nil)
        )
        #expect(state == .shellOnly)
    }

    @Test func shellRuntimeWithoutRecordedDirectoryIsStillShellOnly() {
        let state = HolyRestorePreflight.rowState(
            runtime: .shell,
            context: context(
                workingDirectoryExists: nil,
                workingDirectory: nil,
                executableAvailable: nil,
                resolveOutcome: nil
            )
        )
        #expect(state == .shellOnly)
    }

    // MARK: - Identity precedence

    @Test func liveIdentityMeansAdoptEvenWhenEverythingElseIsBroken() {
        let state = HolyRestorePreflight.rowState(
            runtime: .claude,
            context: context(
                workingDirectoryExists: false,
                executableAvailable: false,
                resolveOutcome: .resolverUnavailable("down"),
                liveness: .present
            )
        )
        #expect(state == .alreadyRestored)
    }

    @Test func undeterminedLivenessBlocksAndIsNeverTreatedAsAbsence() {
        let failure = HolyTmuxLifecycleFailure(
            stage: .probe,
            socketName: "holy",
            target: "=x",
            stderr: "probe broke",
            underlyingDescription: nil
        )
        let state = HolyRestorePreflight.rowState(
            runtime: .claude,
            context: context(
                resolveOutcome: exactOutcome(),
                liveness: .undetermined(failure)
            )
        )
        guard case let .blocked(reason) = state else {
            Issue.record("Expected blocked, got \(state)")
            return
        }
        #expect(reason.contains("probe broke"))
    }

    @Test func conflictOutranksRestoreButNotHostSupport() {
        let conflicted = HolyRestorePreflight.rowState(
            runtime: .claude,
            context: context(
                resolveOutcome: exactOutcome(),
                conflictReason: "duplicate identity"
            )
        )
        #expect(conflicted == .conflict("duplicate identity"))

        let remote = HolyRestorePreflight.rowState(
            runtime: .claude,
            context: context(
                hostSupported: false,
                resolveOutcome: exactOutcome(),
                conflictReason: "duplicate identity"
            )
        )
        #expect(remote == .wrongHost)
    }

    // MARK: - Local preconditions

    @Test func missingWorkingDirectoryBlocksProviderRows() {
        let state = HolyRestorePreflight.rowState(
            runtime: .claude,
            context: context(
                workingDirectoryExists: false,
                resolveOutcome: exactOutcome()
            )
        )
        guard case let .blocked(reason) = state else {
            Issue.record("Expected blocked, got \(state)")
            return
        }
        #expect(reason.contains("/tmp/project"))
    }

    @Test func providerRowWithoutAnyWorkingDirectoryIsBlocked() {
        let state = HolyRestorePreflight.rowState(
            runtime: .claude,
            context: context(
                workingDirectoryExists: nil,
                workingDirectory: nil,
                resolveOutcome: exactOutcome()
            )
        )
        guard case .blocked = state else {
            Issue.record("Expected blocked, got \(state)")
            return
        }
    }

    @Test func missingProviderExecutableBlocks() {
        let state = HolyRestorePreflight.rowState(
            runtime: .codex,
            context: context(
                executableAvailable: false,
                resolveOutcome: exactOutcome()
            )
        )
        guard case let .blocked(reason) = state else {
            Issue.record("Expected blocked, got \(state)")
            return
        }
        #expect(reason.contains("codex"))
    }

    @Test func remoteTransportIsWrongHost() {
        let state = HolyRestorePreflight.rowState(
            runtime: .claude,
            context: context(hostSupported: false, resolveOutcome: exactOutcome())
        )
        #expect(state == .wrongHost)
    }

    @Test func actionabilityMatchesRowSemantics() {
        #expect(HolyRestoreRowState.exactResume(providerSessionID: "x").isActionable)
        #expect(HolyRestoreRowState.shellOnly.isActionable)
        #expect(HolyRestoreRowState.missingHistory.isActionable)
        #expect(HolyRestoreRowState.alreadyRestored.isActionable)
        #expect(HolyRestoreRowState.ambiguous(candidates: []).isActionable)
        #expect(!HolyRestoreRowState.wrongHost.isActionable)
        #expect(!HolyRestoreRowState.conflict("x").isActionable)
        #expect(!HolyRestoreRowState.blocked("x").isActionable)
    }
}
