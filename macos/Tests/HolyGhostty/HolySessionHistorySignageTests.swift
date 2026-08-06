import Foundation
import Testing
@testable import Ghostty

// Session History is where people land by accident after a crash. Its
// signage must say what the screen is, mark interrupted rows as such, and
// hand the user one obvious road into Crash Restore with honest counts.
struct HolySessionHistorySignageTests {
    private static let coldBootReason =
        "Saved layout — the holy tmux server was not running at launch (probably a macOS reboot). Relaunch from history to recreate."

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

    // MARK: - Crash-restore affordance

    @Test func affordanceAbsentWithoutCandidates() {
        #expect(HolySessionHistorySheet.crashRestoreAffordanceTitle(
            freshCount: 0, olderCount: 0
        ) == nil)
    }

    @Test func affordanceCarriesTheFreshCount() {
        #expect(HolySessionHistorySheet.crashRestoreAffordanceTitle(
            freshCount: 8, olderCount: 0
        ) == "Open Crash Restore (8 interrupted)")
    }

    @Test func affordanceNamesOlderInterruptionsSeparatelyNeverMerged() {
        #expect(HolySessionHistorySheet.crashRestoreAffordanceTitle(
            freshCount: 8, olderCount: 46
        ) == "Open Crash Restore (8 interrupted · 46 older)")
    }

    @Test func affordanceStaysReachableWhenOnlyOlderRowsRemain() {
        #expect(HolySessionHistorySheet.crashRestoreAffordanceTitle(
            freshCount: 0, olderCount: 12
        ) == "Open Crash Restore (12 older)")
    }

    // MARK: - Row recovery labels

    @Test func coldBootRowsAreLabeledInterrupted() {
        #expect(HolySessionHistorySheet.recoveryStateLabel(
            for: archived(recoveryReason: Self.coldBootReason)
        ) == "Interrupted")
    }

    @Test func otherRecoveryRowsAreLabeledNeedsRepair() {
        #expect(HolySessionHistorySheet.recoveryStateLabel(
            for: archived(recoveryReason: "Managed worktree was missing at launch.")
        ) == "Needs repair")
    }

    @Test func plainArchivesCarryNoRecoveryLabel() {
        #expect(HolySessionHistorySheet.recoveryStateLabel(
            for: archived(recoveryReason: nil)
        ) == nil)
    }
}
