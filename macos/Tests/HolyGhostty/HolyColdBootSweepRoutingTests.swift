import Foundation
import Testing
@testable import Ghostty

// A dead local `holy` server is a cold boot: every local-managed record must
// route to the cold-boot sweep (restorable, batch-stamped), never to the
// per-session validator, which cannot distinguish "server dead" from "this
// one session vanished". The 2026-08-12 drill proved the failure mode: 12
// real sessions stamped unrestorable, a fresh batch holding only helper
// shells, and a banner that correctly — and disastrously — stayed silent.
struct HolyColdBootSweepRoutingTests {
    private func spec(
        transportKind: HolySessionTransportKind = .local,
        socketName: String? = HolySessionTmuxSpec.defaultSocketName,
        tmux: Bool = true
    ) -> HolySessionLaunchSpec {
        HolySessionLaunchSpec(
            runtime: .claude,
            title: "Holy Ghostty",
            transport: transportKind == .local
                ? .init(kind: .local, hostLabel: nil, sshDestination: nil)
                : .init(kind: .ssh, hostLabel: "studio", sshDestination: "erik@studio"),
            tmux: tmux
                ? .init(socketName: socketName, sessionName: "holy-session-1", createIfMissing: false)
                : nil,
            workingDirectory: nil,
            command: nil,
            initialInput: nil,
            waitAfterCommand: false,
            environment: [:]
        )
    }

    @Test func deadServerRoutesLocalManagedRecordsToTheSweep() {
        #expect(HolySessionSupervisor.belongsToColdBootSweep(
            spec(),
            localServerUnavailable: true
        ))
    }

    @Test func aliveServerNeverRoutesToTheSweep() {
        #expect(!HolySessionSupervisor.belongsToColdBootSweep(
            spec(),
            localServerUnavailable: false
        ))
    }

    @Test func remoteRecordsAreOutsideTheLocalSweep() {
        #expect(!HolySessionSupervisor.belongsToColdBootSweep(
            spec(transportKind: .ssh),
            localServerUnavailable: true
        ))
    }

    @Test func foreignSocketRecordsAreOutsideTheSweep() {
        #expect(!HolySessionSupervisor.belongsToColdBootSweep(
            spec(socketName: "default"),
            localServerUnavailable: true
        ))
    }

    @Test func recordsWithoutTmuxIdentityAreOutsideTheSweep() {
        #expect(!HolySessionSupervisor.belongsToColdBootSweep(
            spec(tmux: false),
            localServerUnavailable: true
        ))
    }
}
