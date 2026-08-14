import Foundation
import Testing
@testable import Ghostty

// Cold-boot sweep membership has two doors, both proven by real losses:
// a DEAD server (2026-08-12 drill — every session looks individually
// missing), and a live server YOUNGER than the record's last activity
// (2026-08-14 real crash — a manual resume rebooted the server before
// Holy's first launch, and asking the 13-minute-old server about
// yesterday's sessions filed all 12 as unrestorable). A session present
// on the live server is never swept; an unknown server birth stays with
// the validator.
struct HolyColdBootSweepRoutingTests {
    private static let serverBirth = Date(timeIntervalSince1970: 1_786_721_512)

    private func record(
        transportKind: HolySessionTransportKind = .local,
        socketName: String? = HolySessionTmuxSpec.defaultSocketName,
        tmux: Bool = true,
        updatedAt: Date = serverBirth.addingTimeInterval(-3_600)
    ) -> HolySessionRecord {
        let spec = HolySessionLaunchSpec(
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
        return .init(
            id: UUID(),
            launchSpec: spec,
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
    }

    @Test func deadServerSweepsLocalManagedRecords() {
        #expect(HolySessionSupervisor.belongsToColdBootSweep(
            record: record(),
            localServerUnavailable: true,
            sessionPresentOnServer: false,
            serverStartedAt: nil
        ))
    }

    @Test func absentSessionOlderThanTheLiveServerIsSwept() {
        // The 2026-08-14 crash shape: session last alive before the boot,
        // server born minutes ago by a manual resume.
        #expect(HolySessionSupervisor.belongsToColdBootSweep(
            record: record(updatedAt: Self.serverBirth.addingTimeInterval(-3_600)),
            localServerUnavailable: false,
            sessionPresentOnServer: false,
            serverStartedAt: Self.serverBirth
        ))
    }

    @Test func absentSessionYoungerThanTheServerStaysWithTheValidator() {
        // The session was seen alive AFTER the server started, then
        // vanished — that is a genuine individual disappearance.
        #expect(!HolySessionSupervisor.belongsToColdBootSweep(
            record: record(updatedAt: Self.serverBirth.addingTimeInterval(600)),
            localServerUnavailable: false,
            sessionPresentOnServer: false,
            serverStartedAt: Self.serverBirth
        ))
    }

    @Test func presentSessionIsNeverSwept() {
        #expect(!HolySessionSupervisor.belongsToColdBootSweep(
            record: record(updatedAt: Self.serverBirth.addingTimeInterval(-3_600)),
            localServerUnavailable: false,
            sessionPresentOnServer: true,
            serverStartedAt: Self.serverBirth
        ))
    }

    @Test func unknownServerBirthStaysWithTheValidator() {
        #expect(!HolySessionSupervisor.belongsToColdBootSweep(
            record: record(),
            localServerUnavailable: false,
            sessionPresentOnServer: false,
            serverStartedAt: nil
        ))
    }

    @Test func remoteRecordsAreOutsideTheLocalSweep() {
        #expect(!HolySessionSupervisor.belongsToColdBootSweep(
            record: record(transportKind: .ssh),
            localServerUnavailable: true,
            sessionPresentOnServer: false,
            serverStartedAt: nil
        ))
    }

    @Test func foreignSocketRecordsAreOutsideTheSweep() {
        #expect(!HolySessionSupervisor.belongsToColdBootSweep(
            record: record(socketName: "default"),
            localServerUnavailable: true,
            sessionPresentOnServer: false,
            serverStartedAt: nil
        ))
    }

    @Test func recordsWithoutTmuxIdentityAreOutsideTheSweep() {
        #expect(!HolySessionSupervisor.belongsToColdBootSweep(
            record: record(tmux: false),
            localServerUnavailable: true,
            sessionPresentOnServer: false,
            serverStartedAt: nil
        ))
    }
}
