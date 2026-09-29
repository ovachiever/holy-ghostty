import Foundation
import Testing
@testable import Ghostty

struct HolyConvergePlannerTests {
    private let host = "ssh|erik@studio|holy"

    private func roster(
        _ id: UUID,
        key: String?,
        hostKey: String? = "ssh|erik@studio|holy",
        exited: Bool = false
    ) -> HolyConvergeRosterEntry {
        HolyConvergeRosterEntry(sessionID: id, matchKey: key, hostKey: hostKey, localProcessExited: exited)
    }

    private func found(_ key: String, attached: Int = 1) -> HolyConvergeDiscoveredEntry {
        HolyConvergeDiscoveredEntry(matchKey: key, hostKey: host, attachedClientCount: attached)
    }

    @Test func discoveredUnknownSessionIsSurfacedWithoutAutomaticAttach() {
        let actions = HolyConvergePlanner.plan(
            roster: [],
            discovered: [found("\(host)|agent-do")],
            reachableHostKeys: [host]
        )
        #expect(actions == [.surfaceOrphan(matchKey: "\(host)|agent-do")])
    }

    @Test func discoveredArchivedSessionIsReadopted() {
        let key = "\(host)|agent-do"
        let actions = HolyConvergePlanner.plan(
            roster: [],
            discovered: [found(key)],
            reachableHostKeys: [host],
            adoptableMatchKeys: [key]
        )
        #expect(actions == [.adoptArchived(matchKey: key)])
    }

    @Test func provenNewHolySessionIsAdoptedWithoutLocalHistory() {
        let key = "\(host)|holy-new"
        #expect(HolyConvergePlanner.plan(
            roster: [], discovered: [found(key)], reachableHostKeys: [host],
            discoveredAdoptionMatchKeys: [key]
        ) == [.adoptDiscovered(matchKey: key)])
    }

    @Test func archivedIdentityWinsOverNewAdoptionAndRepeatedSyncDoesNothing() {
        let key = "\(host)|holy-new"
        #expect(HolyConvergePlanner.plan(
            roster: [], discovered: [found(key)], reachableHostKeys: [host],
            adoptableMatchKeys: [key], discoveredAdoptionMatchKeys: [key]
        ) == [.adoptArchived(matchKey: key)])
        #expect(HolyConvergePlanner.plan(
            roster: [roster(UUID(), key: key)], discovered: [found(key)], reachableHostKeys: [host],
            discoveredAdoptionMatchKeys: [key]
        ).isEmpty)
    }

    @Test func inferredMetadataDoesNotProveHolyOriginAndAmbiguousIdentityBlocksAdoption() {
        let ordinary = discovered("research")
        #expect(ordinary.isHolyManaged)
        #expect(!HolyConvergePlanner.canAdoptDiscovered(ordinary, knownLaunchSpecs: []))
        let holy = discovered("holy-research")
        #expect(HolyConvergePlanner.canAdoptDiscovered(holy, knownLaunchSpecs: []))
        var known = HolySessionLaunchSpec.interactiveTmuxShell(title: "Research")
        known.transport = .init(kind: .ssh, hostLabel: "Studio", sshDestination: "erik@studio")
        known.tmux = .init(socketName: "holy", sessionName: nil, createIfMissing: false)
        #expect(!HolyConvergePlanner.canAdoptDiscovered(holy, knownLaunchSpecs: [known]))
        known.tmux?.sessionName = "different"
        #expect(HolyConvergePlanner.canAdoptDiscovered(holy, knownLaunchSpecs: [known]))
    }

    @Test func reportAccountsForEveryDiscoveredIdentityAndNamesSkippedReasons() {
        var report = HolyConvergeReport(unreachableHosts: ["MacBook: timed out"])
        report.entries = [
            "a": .init(host: "Studio", session: "known", outcome: .attached),
            "b": .init(host: "Studio", session: "new", outcome: .adopted),
            "c": .init(host: "Studio", session: "repair", outcome: .repaired),
            "d": .init(host: "Studio", session: "healthy", outcome: .unchanged),
            "e": .init(host: "Studio", session: "ordinary", outcome: .skipped("not Holy-born")),
            "f": .init(host: "Studio", session: "ambiguous", outcome: .skipped("ambiguous saved identity")),
        ]
        #expect(report.entries.count == 6)
        #expect(report.summary == "Sync: attached 1, adopted 1, repaired 1, unchanged 1, skipped 2; 1 hosts unreachable")
        #expect(report.details.contains("Studio / new: adopted"))
        #expect(report.details.contains("ordinary: skipped: not Holy-born"))
        #expect(report.details.contains("ambiguous: skipped: ambiguous saved identity"))
        #expect(report.details.contains("Host unreachable: MacBook: timed out"))
    }

    private func discovered(_ name: String) -> HolyDiscoveredTmuxSession {
        .init(
            hostID: UUID(), hostLabel: "Studio", hostDestination: "erik@studio", tmuxSocketName: "holy",
            sessionName: name, title: "Research", runtimeRawValue: "codex", objective: nil,
            workingDirectory: "/work/research", bootstrapCommand: nil, taskTitle: nil, taskSource: nil,
            gitSummary: nil, attachedClientCount: 1, windowCount: 1, discoveredAt: .now
        )
    }

    @Test func duplicateDiscoveriesAttachOnce() {
        let actions = HolyConvergePlanner.plan(
            roster: [],
            discovered: [found("\(host)|agent-do"), found("\(host)|agent-do")],
            reachableHostKeys: [host]
        )
        #expect(actions.count == 1)
    }

    @Test func healthyPaneIsNeverTouched() {
        let id = UUID()
        let key = "\(host)|agent-do"
        let actions = HolyConvergePlanner.plan(
            roster: [roster(id, key: key)],
            discovered: [found(key, attached: 1)],
            reachableHostKeys: [host]
        )
        #expect(actions.isEmpty)
    }

    @Test func exitedPaneWithLiveRemoteSessionIsRepaired() {
        let id = UUID()
        let key = "\(host)|agent-do"
        let actions = HolyConvergePlanner.plan(
            roster: [roster(id, key: key, exited: true)],
            discovered: [found(key, attached: 0)],
            reachableHostKeys: [host]
        )
        #expect(actions == [.repair(sessionID: id)])
    }

    @Test func exitedPaneWithLiveLocalSessionIsRepaired() {
        let id = UUID()
        let localHost = "local|local|holy"
        let key = "\(localHost)|agent-do"
        let actions = HolyConvergePlanner.plan(
            roster: [roster(id, key: key, hostKey: localHost, exited: true)],
            discovered: [
                HolyConvergeDiscoveredEntry(
                    matchKey: key,
                    hostKey: localHost,
                    attachedClientCount: 0
                ),
            ],
            reachableHostKeys: [localHost]
        )
        #expect(actions == [.repair(sessionID: id)])
    }

    @Test func zombiePaneIsRepaired() {
        // Local process still running, but the remote session reports zero
        // attached clients: our TCP died without the process noticing.
        let id = UUID()
        let key = "\(host)|agent-do"
        let actions = HolyConvergePlanner.plan(
            roster: [roster(id, key: key, exited: false)],
            discovered: [found(key, attached: 0)],
            reachableHostKeys: [host]
        )
        #expect(actions == [.repair(sessionID: id)])
    }

    @Test func multiClientAttachmentMasksZombieUntilProcessExit() {
        // Another machine holds an attachment (count 1) while our pane is a
        // zombie. The planner must skip it now; the keepalive kills the local
        // process within ~60s and the pane-exit trigger repairs it.
        let id = UUID()
        let key = "\(host)|agent-do"
        let actions = HolyConvergePlanner.plan(
            roster: [roster(id, key: key, exited: false)],
            discovered: [found(key, attached: 1)],
            reachableHostKeys: [host]
        )
        #expect(actions.isEmpty)
    }

    @Test func vanishedSessionOnReachableHostIsArchived() {
        let id = UUID()
        let actions = HolyConvergePlanner.plan(
            roster: [roster(id, key: "\(host)|gone")],
            discovered: [],
            reachableHostKeys: [host]
        )
        #expect(actions == [.archive(sessionID: id)])
    }

    @Test func vanishedSessionOnUnreachableHostIsUntouched() {
        let id = UUID()
        let actions = HolyConvergePlanner.plan(
            roster: [roster(id, key: "\(host)|gone")],
            discovered: [],
            reachableHostKeys: []
        )
        #expect(actions.isEmpty)
    }

    @Test func nonTmuxSessionIsIgnored() {
        let actions = HolyConvergePlanner.plan(
            roster: [roster(UUID(), key: nil, hostKey: nil)],
            discovered: [],
            reachableHostKeys: [host]
        )
        #expect(actions.isEmpty)
    }
}
