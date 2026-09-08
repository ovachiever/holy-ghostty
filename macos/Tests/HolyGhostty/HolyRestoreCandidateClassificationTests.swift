import Foundation
import Testing
@testable import Ghostty

// Crash-restore candidacy is a prefix match on the supervisor's cold-boot
// recovery reason, local transport only. The prefix is pinned: rows written
// by earlier builds carry the full prose and must keep classifying.
struct HolyRestoreCandidateClassificationTests {
    private func archived(
        transport: HolySessionTransportSpec = .local,
        recoveryReason: String?
    ) -> HolyArchivedSession {
        var spec = HolySessionLaunchSpec.interactiveTmuxShell(title: "Row")
        spec.transport = transport
        return .init(
            sourceSessionID: UUID(),
            record: .init(launchSpec: spec),
            phase: .completed,
            preview: "",
            signals: [],
            commandTelemetry: .empty,
            budgetTelemetry: .empty,
            runtimeTelemetry: .empty,
            gitSnapshot: nil,
            lastKnownWorkingDirectory: nil,
            lastActivityAt: .now,
            recoveryReason: recoveryReason
        )
    }

    @Test func legacyPersistedColdBootRowsStillClassify() {
        // The exact prose stamped by builds before the prefix constant.
        let legacy = archived(recoveryReason:
            "Saved layout — the holy tmux server was not running at launch (probably a macOS reboot). Relaunch from history to recreate."
        )
        #expect(HolyWorkspaceStore.isCrashRestoreCandidate(legacy))
    }

    @Test func missingTmuxRecoveriesRemainVisibleWithoutProviderIdentity() {
        for reason in [
            "Recovery archived this session because its tmux session is no longer available: local tmux socket `holy` session `codex`.",
            "Recovery archived this session because Holy could not inspect its tmux server for local tmux: unavailable",
        ] {
            let row = archived(recoveryReason: reason)
            #expect(row.record.harnessSessionID == nil)
            #expect(HolyWorkspaceStore.isCrashRestoreCandidate(row))
        }
    }

    @Test func plainArchivesAndOtherRecoveriesDoNotClassify() {
        #expect(!HolyWorkspaceStore.isCrashRestoreCandidate(
            archived(recoveryReason: nil)
        ))
        #expect(!HolyWorkspaceStore.isCrashRestoreCandidate(
            archived(recoveryReason: "Managed worktree was missing at launch.")
        ))
    }

    @Test func remoteRowsNeverClassifyForLocalRestore() {
        let remote = archived(
            transport: .init(kind: .ssh, hostLabel: "MacBook", sshDestination: "erik@mb"),
            recoveryReason: HolySessionSupervisor.coldBootRecoveryReasonPrefix
        )
        #expect(!HolyWorkspaceStore.isCrashRestoreCandidate(remote))
    }

    @Test func supervisorPrefixMatchesWhatColdBootWrites() {
        #expect(HolySessionSupervisor.coldBootRecoveryReasonPrefix
            .hasPrefix("Saved layout — the holy tmux server was not running at launch"))
    }
}
