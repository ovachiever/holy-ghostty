import Foundation
import Testing
@testable import Ghostty

// Regression coverage for the converge key-construction path. These tests pin
// the two review fixes:
//   1. Roster and discovery must key a remote session from the SESSION's own
//      socket, so a live Holy session on socket "holy" under a host that saves
//      no socket ("auto") is never duplicated.
//   2. Hidden local shells (Holy's own generated bare shells, filtered out of
//      discovery) must never be archived.
@MainActor
struct HolyConvergeKeyTests {
    // (a) THE BUG: a remote Holy session runs on socket "holy" while its saved
    // host records no socket (defaults to "auto"). The roster keys from the
    // session's socket; discovery must key from the discovered session's socket
    // too. Both sides must agree, or the planner attaches a duplicate.
    @Test func remoteHolySessionRosterKeyMatchesDiscoveredKey() {
        let destination = "erik@studio"
        let sessionName = "holy-agent-do-1a2b3c4d"

        // Roster side: identity socket is the session's own socket ("holy").
        let rosterEntry = HolyWorkspaceStore.convergeRosterEntryForTesting(
            sessionID: UUID(),
            destination: destination,
            socketName: "holy",
            sessionName: sessionName,
            localProcessExited: false
        )

        // Discovery side: the session is found on the "holy" probe, so its
        // discovered socket is "holy" too. Mirror the roster construction.
        let discoveredHostKey = HolyWorkspaceStore.convergeHostKeyForTesting(
            destination: destination,
            socketName: "holy"
        )
        let discoveredMatchKey = HolyWorkspaceStore.convergeMatchKeyForTesting(
            hostKey: discoveredHostKey,
            sessionName: sessionName
        )

        #expect(rosterEntry.matchKey == discoveredMatchKey)

        // Guard the regression: keying the discovered side from the host's
        // recorded socket (nil -> "auto") is the original defect and must NOT
        // collide with the live session's key.
        let hostSocketHostKey = HolyWorkspaceStore.convergeHostKeyForTesting(
            destination: destination,
            socketName: nil
        )
        let hostSocketMatchKey = HolyWorkspaceStore.convergeMatchKeyForTesting(
            hostKey: hostSocketHostKey,
            sessionName: sessionName
        )
        #expect(hostSocketMatchKey != rosterEntry.matchKey)
    }

    // (b) Default-socket consistency: nil, empty, and whitespace-only sockets
    // all normalize to the same "auto" host key on both sides.
    @Test func defaultSocketNormalizesConsistently() {
        let destination = "erik@studio"
        let fromNil = HolyWorkspaceStore.convergeHostKeyForTesting(destination: destination, socketName: nil)
        let fromEmpty = HolyWorkspaceStore.convergeHostKeyForTesting(destination: destination, socketName: "")
        let fromBlank = HolyWorkspaceStore.convergeHostKeyForTesting(destination: destination, socketName: "   ")

        #expect(fromNil == "ssh|erik@studio|auto")
        #expect(fromNil == fromEmpty)
        #expect(fromNil == fromBlank)

        // Case-insensitive: an uppercased destination and socket collapse to the
        // same key the lowercased roster/discovery inputs produce.
        let mixedCase = HolyWorkspaceStore.convergeHostKeyForTesting(destination: "Erik@Studio", socketName: "HOLY")
        #expect(mixedCase == "ssh|erik@studio|holy")
    }

    // (c) A hidden local shell (generated "holy-shell-*" name) must be excluded
    // from archiving even when its socket is reachable and discovery cannot see
    // it. It keeps its matchKey (so a discovered twin can never duplicate it)
    // but drops its hostKey (so the planner never archives or repairs it).
    @Test func hiddenLocalShellIsExcludedFromArchiving() {
        let id = UUID()
        let entry = HolyWorkspaceStore.convergeRosterEntryForTesting(
            sessionID: id,
            destination: "local",
            socketName: "holy",
            sessionName: "holy-shell-9f8e7d6c",
            localProcessExited: false
        )

        #expect(entry.matchKey != nil)
        #expect(entry.hostKey == nil)

        // Cross-check against the locked planner: the socket is reachable and
        // discovery returns nothing, yet the hidden shell must survive.
        let actions = HolyConvergePlanner.plan(
            roster: [entry],
            discovered: [],
            reachableHostKeys: ["local|local|holy"]
        )
        #expect(actions.isEmpty)
    }

    // A normal (non-hidden) local session keeps its hostKey and is therefore
    // eligible for archiving when it truly vanishes.
    @Test func normalLocalSessionKeepsHostKey() {
        let entry = HolyWorkspaceStore.convergeRosterEntryForTesting(
            sessionID: UUID(),
            destination: "local",
            socketName: "holy",
            sessionName: "holy-recognition-oracle-claude-1a2b",
            localProcessExited: false
        )

        #expect(entry.hostKey == "local|local|holy")
        #expect(entry.matchKey == "local|local|holy|holy-recognition-oracle-claude-1a2b")
    }

    // (d) Probe coverage: converge marks reachable exactly the socket
    // namespaces the discovery service probes. A session on a socket the
    // service never probes must never look reachable, so it can never be
    // archived.
    @Test func reachabilityFollowsProbeCoverageNotFoundSockets() {
        let host = HolyRemoteHostRecord(sshDestination: "erik@studio") // records no socket
        let probed = HolyRemoteTmuxDiscoveryService.shared.probedSocketNames(for: host)

        let reachable = Set(probed.map {
            HolyWorkspaceStore.convergeHostKeyForTesting(destination: "erik@studio", socketName: $0)
        })

        // The service probes the default ("auto") and the managed "holy" socket.
        #expect(reachable.contains("ssh|erik@studio|auto"))
        #expect(reachable.contains("ssh|erik@studio|holy"))

        // A custom socket the service does not probe is not reachable.
        let unprobed = HolyWorkspaceStore.convergeHostKeyForTesting(destination: "erik@studio", socketName: "custom")
        #expect(!reachable.contains(unprobed))

        // The local sweep probes the same two namespaces.
        let localProbed = HolyRemoteTmuxDiscoveryService.shared.localProbedSocketNames
        let localReachable = Set(localProbed.map {
            HolyWorkspaceStore.convergeHostKeyForTesting(destination: "local", socketName: $0)
        })
        #expect(localReachable.contains("local|local|auto"))
        #expect(localReachable.contains("local|local|holy"))
    }

    // (e) Branch 3 of shouldHideFromDiscovery: a Holy-managed shell whose only
    // identity is a generic workspace directory. Its name is NOT "holy-shell-*"
    // (the old name-only roster check missed it), yet discovery hides it, so it
    // must never be archived even though its socket is probe-covered and
    // discovery returns nothing.
    @Test func genericWorkspaceShellIsExcludedFromArchiving() {
        let entry = HolyWorkspaceStore.convergeRosterEntryForTesting(
            sessionID: UUID(),
            destination: "local",
            socketName: "holy",
            sessionName: "holy-workspace-shell-4f3e2d1c",
            title: nil,
            workingDirectory: "/Users/erik/Custom Coding",
            runtime: .shell,
            localProcessExited: false
        )

        #expect(entry.matchKey != nil)
        #expect(entry.hostKey == nil)

        let actions = HolyConvergePlanner.plan(
            roster: [entry],
            discovered: [],
            reachableHostKeys: ["local|local|holy"]
        )
        #expect(actions.isEmpty)
    }

    // (f) Branch 2 of shouldHideFromDiscovery: a symbol-only shell title (an
    // agent status glyph on the live pane). Discovery hides it; converge keys
    // the roster from the live title, so it must be protected from archive.
    @Test func symbolOnlyShellTitleIsExcludedFromArchiving() {
        let entry = HolyWorkspaceStore.convergeRosterEntryForTesting(
            sessionID: UUID(),
            destination: "local",
            socketName: "holy",
            sessionName: "holy-agent-do-7a6b5c4d",
            title: "~",
            workingDirectory: nil,
            runtime: .shell,
            localProcessExited: false
        )

        #expect(entry.matchKey != nil)
        #expect(entry.hostKey == nil)

        let actions = HolyConvergePlanner.plan(
            roster: [entry],
            discovered: [],
            reachableHostKeys: ["local|local|holy"]
        )
        #expect(actions.isEmpty)
    }
}
