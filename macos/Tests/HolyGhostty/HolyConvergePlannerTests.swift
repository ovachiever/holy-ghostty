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

    @Test func discoveredUnknownSessionIsAttached() {
        let actions = HolyConvergePlanner.plan(
            roster: [],
            discovered: [found("\(host)|agent-do")],
            reachableHostKeys: [host]
        )
        #expect(actions == [.attachNew(matchKey: "\(host)|agent-do")])
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
