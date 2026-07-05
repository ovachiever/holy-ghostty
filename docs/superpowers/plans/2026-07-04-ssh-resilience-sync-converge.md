# SSH Resilience + Sync Converge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remote SSH/tmux sessions stop dying silently: keepalive flags detect dead panes, a converge engine (Sync button + system wake + pane-exit backoff) repairs only what is broken, and a power assertion keeps the Mac awake (display off) while remote sessions are attached.

**Architecture:** One pure diff engine (`HolyConvergePlanner`) buckets roster-vs-discovery into attach/repair/archive actions; `HolyWorkspaceStore` orchestrates the sweep and applies actions through the existing `launchRemoteTmuxSessions`/`reattach`/`archive` paths. Three triggers fire the same engine: the Sync button, `NSWorkspace.didWakeNotification` (+4s settle), and a per-session pane-death notification with backoff. A small `HolyPowerAssertionManager` holds `PreventUserIdleSystemSleep` while remote sessions are attached.

**Tech Stack:** Swift 5 / SwiftUI / AppKit, IOKit.pwr_mgt, Swift Testing (`import Testing`), xcodebuild with the GhosttyTests target.

**Spec:** `docs/superpowers/specs/2026-07-04-ssh-resilience-sync-converge-design.md`

## Global Constraints

- App installs use `./scripts/install-holy-ghostty.sh ReleaseLocal` ONLY (the script hard-rejects other configs, exit 64). Never install Debug.
- The Swift module is named `Ghostty` — tests use `@testable import Ghostty`.
- Test command (run from repo root; substitute the test class):
  `cd macos && env -i HOME="$HOME" PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin" xcodebuild -project Ghostty.xcodeproj -scheme Ghostty -configuration Debug -destination 'platform=macOS,arch=arm64' -only-testing:GhosttyTests/<ClassName> test 2>&1 | grep -E "Test case|BUILD|error:"`
- New source/test files are ASCII-only.
- `HolyWorkspaceStore` is `@MainActor`; test structs that touch it or `HolySession` need `@MainActor` (see `HolySessionLiveStatusTests.swift` for the pattern).
- Production types stay `private`/file-private where they are; tests reach them through `#if DEBUG` static helpers (established pattern: `HolySession.inferredRuntimeForTesting`, `HolySessionRuntimeTelemetryParser.extractCommandForTesting`).
- No new dependencies. `import IOKit.pwr_mgt` is a system framework already linkable from the app target.
- SwiftLint runs on every build — no force unwraps, no new warnings.
- Commit after every task with a Conventional Commit message and trailer `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: Keepalive flags on the remote attach command

**Files:**
- Modify: `macos/Sources/HolyGhostty/Tmux/HolyTmuxCommandBuilder.swift:121-124` (`remoteLaunchWrapper`)
- Create: `macos/Tests/HolyGhostty/HolyTmuxCommandFlagTests.swift`

**Interfaces:**
- Consumes: `HolyTmuxCommandBuilder.remoteLaunchWrapper(destination:localScript:)` (private; exposed via new DEBUG helper).
- Produces: `HolyTmuxCommandBuilder.remoteLaunchWrapperForTesting(destination:localScript:) -> String` (DEBUG only). Attach ssh now carries `ServerAliveInterval=15, ServerAliveCountMax=4, TCPKeepAlive=no, ConnectTimeout=8`.

- [ ] **Step 1: Write the failing test**

Create `macos/Tests/HolyGhostty/HolyTmuxCommandFlagTests.swift`:

```swift
import Testing
@testable import Ghostty

struct HolyTmuxCommandFlagTests {
    // The long-lived attach ssh needs keepalives so post-sleep zombie panes
    // are detected in ~60s instead of never, and a bounded connect timeout
    // so reattach attempts fail fast instead of hanging on kernel TCP.
    @Test func remoteAttachWrapperCarriesKeepaliveFlags() {
        let wrapper = HolyTmuxCommandBuilder.remoteLaunchWrapperForTesting(
            destination: "erik@example-host",
            localScript: "exec tmux attach -t demo"
        )
        #expect(wrapper.contains("ServerAliveInterval=15"))
        #expect(wrapper.contains("ServerAliveCountMax=4"))
        #expect(wrapper.contains("TCPKeepAlive=no"))
        #expect(wrapper.contains("ConnectTimeout=8"))
        #expect(!wrapper.contains("BatchMode"))
    }
}
```

- [ ] **Step 2: Add the DEBUG helper (so the test compiles), run test to verify it fails**

At the bottom of `HolyTmuxCommandBuilder.swift`:

```swift
#if DEBUG
extension HolyTmuxCommandBuilder {
    static func remoteLaunchWrapperForTesting(destination: String, localScript: String) -> String {
        remoteLaunchWrapper(destination: destination, localScript: localScript)
    }
}
#endif
```

Run: the Global Constraints test command with `HolyTmuxCommandFlagTests`.
Expected: `remoteAttachWrapperCarriesKeepaliveFlags` FAILS (flags not present yet).

- [ ] **Step 3: Add the flags**

In `remoteLaunchWrapper` (line ~122), replace:

```swift
let sshCommand = shellCommand(["ssh", "-tt", destination, shellCommand(["zsh", "-lc", localScript])])
```

with:

```swift
let sshCommand = shellCommand([
    "ssh", "-tt",
    "-o", "ServerAliveInterval=15",
    "-o", "ServerAliveCountMax=4",
    "-o", "TCPKeepAlive=no",
    "-o", "ConnectTimeout=8",
    destination,
    shellCommand(["zsh", "-lc", localScript]),
])
```

No BatchMode: the pane is visible and interactive auth must stay possible (spec, Layer 2).

- [ ] **Step 4: Run test to verify it passes**

Run: same command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/HolyGhostty/Tmux/HolyTmuxCommandBuilder.swift macos/Tests/HolyGhostty/HolyTmuxCommandFlagTests.swift
git commit -m "feat(macos): add keepalive and connect-timeout flags to remote attach ssh"
```

---

### Task 2: Fail-fast flags on the detach command

**Files:**
- Modify: `macos/Sources/HolyGhostty/Workspace/HolyWorkspaceStore.swift:2777-2800` (`HolyTmuxClientDetachCommand`)
- Test: `macos/Tests/HolyGhostty/HolyTmuxCommandFlagTests.swift` (extend)

**Interfaces:**
- Consumes: file-private `HolyTmuxClientDetachCommand` in `HolyWorkspaceStore.swift`.
- Produces: `HolyTmuxClientDetachCommand.make(destination:socketName:sessionName:) -> Self` (file-private core), and `HolyWorkspaceStore.detachCommandArgumentsForTesting(destination:socketName:sessionName:) -> [String]` (DEBUG only). Detach ssh now carries `ConnectTimeout=5, BatchMode=yes`.

- [ ] **Step 1: Write the failing test**

Append to `HolyTmuxCommandFlagTests.swift`:

```swift
    // Detach commands are headless; without ConnectTimeout+BatchMode one
    // unreachable host stalls Sync for the full kernel TCP timeout per
    // session (the old minutes-long hang).
    @MainActor
    @Test func detachCommandFailsFast() {
        let arguments = HolyWorkspaceStore.detachCommandArgumentsForTesting(
            destination: "erik@example-host",
            socketName: "holy",
            sessionName: "demo"
        )
        #expect(arguments.contains("ConnectTimeout=5"))
        #expect(arguments.contains("BatchMode=yes"))
        #expect(arguments.first == "ssh")
    }
```

- [ ] **Step 2: Refactor command construction + add DEBUG helper, run test to verify it fails**

In `HolyTmuxClientDetachCommand`, split `command(for:)` so the argument assembly is a testable core. Replace the `return Self(...)` tail of `command(for:)` with a call to the new core:

```swift
        return make(destination: destination, socketName: tmux.socketName?.holyTerminatorTrimmed.nilIfEmpty, sessionName: sessionName)
    }

    static func make(destination: String, socketName: String?, sessionName: String) -> Self {
        var tmuxArguments = ["tmux"]
        if let socketName {
            tmuxArguments += ["-L", socketName]
        }
        tmuxArguments += ["detach-client", "-s", sessionName]

        return Self(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["ssh", destination, "zsh", "-lc", shellCommand(tmuxArguments)]
        )
    }
```

(The original `var tmuxArguments` block moves into `make`; `command(for:)` keeps only the spec parsing/guards.)

At the bottom of `HolyWorkspaceStore.swift`:

```swift
#if DEBUG
extension HolyWorkspaceStore {
    static func detachCommandArgumentsForTesting(
        destination: String,
        socketName: String?,
        sessionName: String
    ) -> [String] {
        HolyTmuxClientDetachCommand.make(
            destination: destination,
            socketName: socketName,
            sessionName: sessionName
        ).arguments
    }
}
#endif
```

Run: test command with `HolyTmuxCommandFlagTests`. Expected: `detachCommandFailsFast` FAILS (no flags yet).

- [ ] **Step 3: Add the flags in `make`**

```swift
            arguments: [
                "ssh",
                "-o", "ConnectTimeout=5",
                "-o", "BatchMode=yes",
                destination,
                "zsh", "-lc", shellCommand(tmuxArguments),
            ]
```

- [ ] **Step 4: Run tests to verify both pass**

Run: same command. Expected: both tests PASS.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/HolyGhostty/Workspace/HolyWorkspaceStore.swift macos/Tests/HolyGhostty/HolyTmuxCommandFlagTests.swift
git commit -m "fix(macos): fail-fast flags on tmux detach ssh commands"
```

---

### Task 3: Converge planner (pure diff engine)

**Files:**
- Create: `macos/Sources/HolyGhostty/Workspace/HolyConvergePlanner.swift`
- Create: `macos/Tests/HolyGhostty/HolyConvergePlannerTests.swift`

**Interfaces:**
- Consumes: nothing (pure value types).
- Produces (Task 4 depends on these exact names):
  - `struct HolyConvergeRosterEntry { let sessionID: UUID; let matchKey: String?; let hostKey: String?; let localProcessExited: Bool }`
  - `struct HolyConvergeDiscoveredEntry { let matchKey: String; let hostKey: String; let attachedClientCount: Int }`
  - `enum HolyConvergeAction: Equatable { case attachNew(matchKey: String); case repair(sessionID: UUID); case archive(sessionID: UUID) }`
  - `enum HolyConvergePlanner { static func plan(roster:discovered:reachableHostKeys:) -> [HolyConvergeAction] }`

- [ ] **Step 1: Write the failing tests**

Create `macos/Tests/HolyGhostty/HolyConvergePlannerTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail to compile**

Run: test command with `HolyConvergePlannerTests`.
Expected: build FAILS — `HolyConvergePlanner` not defined.

- [ ] **Step 3: Implement the planner**

Create `macos/Sources/HolyGhostty/Workspace/HolyConvergePlanner.swift`:

```swift
import Foundation

/// Inputs and pure diff logic for roster convergence. The store snapshots
/// roster + discovery state into these value types; the planner never touches
/// live sessions, so every bucketing rule is unit-testable.
struct HolyConvergeRosterEntry: Equatable {
    let sessionID: UUID
    /// Stable identity: "<scheme>|<destination>|<socket>|<session-name>",
    /// nil when the session is not tmux-backed.
    let matchKey: String?
    /// "<scheme>|<destination>|<socket>" — reachability is judged per host.
    let hostKey: String?
    let localProcessExited: Bool
}

struct HolyConvergeDiscoveredEntry: Equatable {
    let matchKey: String
    let hostKey: String
    let attachedClientCount: Int
}

enum HolyConvergeAction: Equatable {
    case attachNew(matchKey: String)
    case repair(sessionID: UUID)
    case archive(sessionID: UUID)
}

enum HolyConvergePlanner {
    static func plan(
        roster: [HolyConvergeRosterEntry],
        discovered: [HolyConvergeDiscoveredEntry],
        reachableHostKeys: Set<String>
    ) -> [HolyConvergeAction] {
        var actions: [HolyConvergeAction] = []
        let discoveredByKey = Dictionary(
            discovered.map { ($0.matchKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let rosterKeys = Set(roster.compactMap(\.matchKey))
        var attachedKeys: Set<String> = []

        for entry in discovered
        where !rosterKeys.contains(entry.matchKey) && attachedKeys.insert(entry.matchKey).inserted {
            actions.append(.attachNew(matchKey: entry.matchKey))
        }

        for entry in roster {
            guard let matchKey = entry.matchKey, let hostKey = entry.hostKey else { continue }

            if let discoveredEntry = discoveredByKey[matchKey] {
                // Dead = our process exited, or it runs while the remote
                // session shows zero clients (zombie). A nonzero count with a
                // live local process might be another machine's client, but
                // then the keepalive resolves it within ~60s via pane exit.
                let zombie = !entry.localProcessExited && discoveredEntry.attachedClientCount == 0
                if entry.localProcessExited || zombie {
                    actions.append(.repair(sessionID: entry.sessionID))
                }
            } else if reachableHostKeys.contains(hostKey) {
                actions.append(.archive(sessionID: entry.sessionID))
            }
        }

        return actions
    }
}
```

- [ ] **Step 4: Run tests to verify all nine pass**

Run: same command. Expected: 9 PASS.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/HolyGhostty/Workspace/HolyConvergePlanner.swift macos/Tests/HolyGhostty/HolyConvergePlannerTests.swift
git commit -m "feat(macos): pure converge planner for roster/discovery diff"
```

---

### Task 4: Store orchestration — sweep, apply, single-flight gate

**Files:**
- Modify: `macos/Sources/HolyGhostty/Workspace/HolyWorkspaceStore.swift` — add converge state + `convergeRoster(reason:)`; rewire `reattachAllSessions()` (line 573)
- Test: `macos/Tests/HolyGhostty/HolyConvergeGateTests.swift` (create)

**Interfaces:**
- Consumes: `HolyConvergePlanner.plan(roster:discovered:reachableHostKeys:)` (Task 3); existing `HolyRemoteTmuxDiscoveryService.shared.discoverSessionsThrowing(for:)` / `discoverLocalSessionsThrowing(hostID:hostLabel:)`; existing `launchRemoteTmuxSessions(_:on:keepHostsOpen:)` (store:1067), `launchLocalTmuxSessions(_:keepHostsOpen:)` (store:1046), `reattach(_:)` (store:547), `archive(_:)`, `activeRemoteTmuxDiscoveryHosts()` (store:1724), file-private `HolyRemoteTmuxSessionKey` (store:2747).
- Produces (Tasks 6 and 7 depend on these):
  - `enum HolyConvergeReason: String { case manual, wake, paneExit }`
  - `@Published private(set) var isConverging: Bool`
  - `func convergeRoster(reason: HolyConvergeReason)`
  - `static func shouldStartConverge(now:lastStartedAt:isRunning:reason:) -> Bool`
  - `reattachAllSessions()` now delegates to `convergeRoster(reason: .manual)`.

- [ ] **Step 1: Write the failing gate tests**

Create `macos/Tests/HolyGhostty/HolyConvergeGateTests.swift`:

```swift
import Foundation
import Testing
@testable import Ghostty

@MainActor
struct HolyConvergeGateTests {
    @Test func neverStartsWhileRunning() {
        #expect(!HolyWorkspaceStore.shouldStartConverge(
            now: Date(timeIntervalSince1970: 100),
            lastStartedAt: Date(timeIntervalSince1970: 0),
            isRunning: true,
            reason: .manual
        ))
    }

    @Test func manualBypassesDebounce() {
        #expect(HolyWorkspaceStore.shouldStartConverge(
            now: Date(timeIntervalSince1970: 5),
            lastStartedAt: Date(timeIntervalSince1970: 0),
            isRunning: false,
            reason: .manual
        ))
    }

    @Test func wakeWithinDebounceWindowIsSkipped() {
        #expect(!HolyWorkspaceStore.shouldStartConverge(
            now: Date(timeIntervalSince1970: 5),
            lastStartedAt: Date(timeIntervalSince1970: 0),
            isRunning: false,
            reason: .wake
        ))
    }

    @Test func wakeAfterDebounceWindowRuns() {
        #expect(HolyWorkspaceStore.shouldStartConverge(
            now: Date(timeIntervalSince1970: 11),
            lastStartedAt: Date(timeIntervalSince1970: 0),
            isRunning: false,
            reason: .wake
        ))
    }

    @Test func firstRunAlwaysAllowed() {
        #expect(HolyWorkspaceStore.shouldStartConverge(
            now: Date(),
            lastStartedAt: nil,
            isRunning: false,
            reason: .wake
        ))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail to compile**

Run: test command with `HolyConvergeGateTests`. Expected: build FAILS — `shouldStartConverge` not defined.

- [ ] **Step 3: Implement gate + converge orchestration**

In `HolyWorkspaceStore.swift`, near the other `@Published` state (top of class):

```swift
    @Published private(set) var isConverging = false
    private var lastConvergeStartedAt: Date?
```

Add alongside the other nested/file types:

```swift
enum HolyConvergeReason: String {
    case manual
    case wake
    case paneExit
}
```

Add to the store (near `reattachAllSessions`):

```swift
    static func shouldStartConverge(
        now: Date,
        lastStartedAt: Date?,
        isRunning: Bool,
        reason: HolyConvergeReason
    ) -> Bool {
        if isRunning { return false }
        if reason == .manual { return true }
        guard let lastStartedAt else { return true }
        return now.timeIntervalSince(lastStartedAt) >= 10
    }

    func convergeRoster(reason: HolyConvergeReason) {
        guard Self.shouldStartConverge(
            now: Date(),
            lastStartedAt: lastConvergeStartedAt,
            isRunning: isConverging,
            reason: reason
        ) else { return }

        isConverging = true
        lastConvergeStartedAt = Date()

        // Snapshot roster identity on the main actor.
        let rosterEntries: [HolyConvergeRosterEntry] = sessions.map { session in
            let spec = session.record.launchSpec
            if let key = HolyRemoteTmuxSessionKey(launchSpec: spec) {
                let hostKey = Self.convergeHostKey(destination: key.sshDestination, socketName: key.tmuxSocketName)
                return HolyConvergeRosterEntry(
                    sessionID: session.id,
                    matchKey: "\(hostKey)|\(key.tmuxSessionName)",
                    hostKey: hostKey,
                    localProcessExited: session.surfaceView.processExited
                )
            }
            let realized = HolyTmuxCommandBuilder.realizedLaunchSpec(spec)
            if !realized.transport.isRemote,
               let tmux = realized.tmux?.normalized,
               let name = tmux.sessionName?.nilIfBlank {
                let hostKey = Self.convergeHostKey(destination: "local", socketName: tmux.socketName?.nilIfBlank)
                return HolyConvergeRosterEntry(
                    sessionID: session.id,
                    matchKey: "\(hostKey)|\(name)",
                    hostKey: hostKey,
                    localProcessExited: session.surfaceView.processExited
                )
            }
            return HolyConvergeRosterEntry(sessionID: session.id, matchKey: nil, hostKey: nil, localProcessExited: false)
        }

        // Hosts to sweep: every saved remote host plus hosts inferable from
        // live roster records (covers sessions on unsaved hosts).
        var hostsByKey: [String: HolyRemoteHostRecord] = [:]
        for host in remoteHosts + activeRemoteTmuxDiscoveryHosts() {
            let normalized = host.normalized()
            let key = Self.convergeHostKey(
                destination: normalized.sshDestination,
                socketName: normalized.tmuxSocketName?.nilIfBlank
            )
            if hostsByKey[key] == nil { hostsByKey[key] = host }
        }
        let remoteSweep = hostsByKey

        Task { [weak self] in
            var discoveredEntries: [HolyConvergeDiscoveredEntry] = []
            var reachable: Set<String> = []
            var discoveredByMatchKey: [String: (session: HolyDiscoveredTmuxSession, host: HolyRemoteHostRecord?)] = [:]

            await withTaskGroup(of: (String, HolyRemoteHostRecord?, [HolyDiscoveredTmuxSession])?.self) { group in
                for (hostKey, host) in remoteSweep {
                    group.addTask {
                        do {
                            let sessions = try await HolyRemoteTmuxDiscoveryService.shared.discoverSessionsThrowing(for: host)
                            return (hostKey, host, sessions)
                        } catch {
                            return nil // unreachable: leave its records untouched
                        }
                    }
                }
                group.addTask {
                    let localHostKey = Self.convergeHostKey(destination: "local", socketName: nil)
                    do {
                        let sessions = try HolyRemoteTmuxDiscoveryService.shared.discoverLocalSessionsThrowing(
                            hostID: UUID(),
                            hostLabel: "This Mac"
                        )
                        return (localHostKey, nil, sessions)
                    } catch {
                        return nil
                    }
                }

                for await result in group {
                    guard let (hostKey, host, sessions) = result else { continue }
                    reachable.insert(hostKey)
                    for discovered in sessions {
                        let entryHostKey: String
                        if host == nil {
                            entryHostKey = Self.convergeHostKey(
                                destination: "local",
                                socketName: discovered.tmuxSocketName?.nilIfBlank
                            )
                            reachable.insert(entryHostKey)
                        } else {
                            entryHostKey = hostKey
                        }
                        let matchKey = "\(entryHostKey)|\(discovered.sessionName)"
                        discoveredEntries.append(HolyConvergeDiscoveredEntry(
                            matchKey: matchKey,
                            hostKey: entryHostKey,
                            attachedClientCount: discovered.attachedClientCount
                        ))
                        if discoveredByMatchKey[matchKey] == nil {
                            discoveredByMatchKey[matchKey] = (discovered, host)
                        }
                    }
                }
            }

            let actions = HolyConvergePlanner.plan(
                roster: rosterEntries,
                discovered: discoveredEntries,
                reachableHostKeys: reachable
            )

            await MainActor.run {
                guard let self else { return }
                self.applyConvergeActions(actions, discoveredByMatchKey: discoveredByMatchKey)
                self.isConverging = false
            }
        }
    }

    private func applyConvergeActions(
        _ actions: [HolyConvergeAction],
        discoveredByMatchKey: [String: (session: HolyDiscoveredTmuxSession, host: HolyRemoteHostRecord?)]
    ) {
        for action in actions {
            switch action {
            case let .attachNew(matchKey):
                guard let found = discoveredByMatchKey[matchKey],
                      !found.session.shouldHideFromDiscovery else { break }
                if let host = found.host {
                    launchRemoteTmuxSessions([found.session], on: host, keepHostsOpen: true)
                } else {
                    launchLocalTmuxSessions([found.session], keepHostsOpen: true)
                }
            case let .repair(sessionID):
                if let session = sessions.first(where: { $0.id == sessionID }) {
                    reattach(session)
                }
            case let .archive(sessionID):
                if let session = sessions.first(where: { $0.id == sessionID }) {
                    archive(session)
                }
            }
        }
    }

    private static func convergeHostKey(destination: String, socketName: String?) -> String {
        let scheme = destination == "local" ? "local" : "ssh"
        return [scheme, destination.lowercased(), socketName?.lowercased() ?? "auto"].joined(separator: "|")
    }
```

Rewire `reattachAllSessions()` (store:573) — replace its entire body with:

```swift
    func reattachAllSessions() {
        convergeRoster(reason: .manual)
    }
```

Note: `discoverSessionsThrowing` is already called with `try await` from a `Task` in `refreshRemoteSessions` (store:1016) — copy that call shape exactly. `shouldHideFromDiscovery` filtering mirrors the Hosts sheet lists, and critically prevents converge from re-attaching Holy's own managed local shells as duplicates.

- [ ] **Step 4: Run gate tests + planner tests + full build**

Run: test command with `HolyConvergeGateTests`, then with `HolyConvergePlannerTests`.
Expected: all PASS, no compile errors in the store.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/HolyGhostty/Workspace/HolyWorkspaceStore.swift macos/Tests/HolyGhostty/HolyConvergeGateTests.swift
git commit -m "feat(macos): converge-to-truth engine replaces record-driven Sync"
```

---

### Task 5: Power assertion manager + keep-awake preference

**Files:**
- Create: `macos/Sources/HolyGhostty/App/HolyPowerAssertionManager.swift`
- Create: `macos/Tests/HolyGhostty/HolyPowerAssertionManagerTests.swift`
- Modify: `macos/Sources/HolyGhostty/Workspace/HolyWorkspaceStore.swift` — preference + lifecycle wiring

**Interfaces:**
- Consumes: `IOPMAssertionCreateWithName` / `IOPMAssertionRelease` (IOKit.pwr_mgt), injected for tests.
- Produces (Task 7 depends on the store property):
  - `final class HolyPowerAssertionManager { init(create:release:); func setActive(_ Bool) }`
  - `HolyWorkspaceStore.keepAwakeWhileRemoteAttached: Bool` (`@Published`, persisted to `UserDefaults` key `"HolyKeepAwakeWhileRemoteAttached"`, default `true`)
  - store calls `updatePowerAssertion()` from `applySessionStoreState` and after converge apply.

Spec deviation, intentional: the preference lives in `UserDefaults`, not the app-state DB — keep-awake is a per-machine preference, not workspace state (the same roster on the MacBook should be allowed a different battery policy).

- [ ] **Step 1: Write the failing tests**

Create `macos/Tests/HolyGhostty/HolyPowerAssertionManagerTests.swift`:

```swift
import Foundation
import Testing
@testable import Ghostty

@MainActor
struct HolyPowerAssertionManagerTests {
    private final class Recorder {
        var created = 0
        var released: [UInt32] = []
        var failCreate = false
    }

    private func makeManager(_ recorder: Recorder) -> HolyPowerAssertionManager {
        HolyPowerAssertionManager(
            create: { _ in
                if recorder.failCreate { return nil }
                recorder.created += 1
                return UInt32(recorder.created)
            },
            release: { recorder.released.append($0) }
        )
    }

    @Test func activateCreatesExactlyOneAssertion() {
        let recorder = Recorder()
        let manager = makeManager(recorder)
        manager.setActive(true)
        manager.setActive(true)
        #expect(recorder.created == 1)
    }

    @Test func deactivateReleasesTheAssertion() {
        let recorder = Recorder()
        let manager = makeManager(recorder)
        manager.setActive(true)
        manager.setActive(false)
        #expect(recorder.released == [1])
        manager.setActive(false)
        #expect(recorder.released == [1])
    }

    @Test func reactivateCreatesANewAssertion() {
        let recorder = Recorder()
        let manager = makeManager(recorder)
        manager.setActive(true)
        manager.setActive(false)
        manager.setActive(true)
        #expect(recorder.created == 2)
        #expect(recorder.released == [1])
    }

    @Test func failedCreateRetriesOnNextActivate() {
        let recorder = Recorder()
        recorder.failCreate = true
        let manager = makeManager(recorder)
        manager.setActive(true)
        #expect(recorder.created == 0)
        recorder.failCreate = false
        manager.setActive(true)
        #expect(recorder.created == 1)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail to compile**

Run: test command with `HolyPowerAssertionManagerTests`. Expected: build FAILS — type not defined.

- [ ] **Step 3: Implement the manager**

Create `macos/Sources/HolyGhostty/App/HolyPowerAssertionManager.swift`:

```swift
import Foundation
import IOKit.pwr_mgt

/// Holds a single PreventUserIdleSystemSleep assertion while remote sessions
/// are attached: the display may sleep, the system may not, so SSH stays up.
/// Injectable create/release keep the IOPM calls out of unit tests.
@MainActor
final class HolyPowerAssertionManager {
    private let create: (String) -> UInt32?
    private let release: (UInt32) -> Void
    private var activeAssertionID: UInt32?

    init(
        create: @escaping (String) -> UInt32? = HolyPowerAssertionManager.systemCreate,
        release: @escaping (UInt32) -> Void = HolyPowerAssertionManager.systemRelease
    ) {
        self.create = create
        self.release = release
    }

    func setActive(_ active: Bool) {
        if active {
            guard activeAssertionID == nil else { return }
            activeAssertionID = create("Holy Ghostty is keeping remote SSH sessions attached")
        } else if let id = activeAssertionID {
            release(id)
            activeAssertionID = nil
        }
    }

    private static func systemCreate(reason: String) -> UInt32? {
        var assertionID = IOPMAssertionID(0)
        let status = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )
        return status == kIOReturnSuccess ? assertionID : nil
    }

    private static func systemRelease(assertionID: UInt32) {
        IOPMAssertionRelease(assertionID)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: same command. Expected: 4 PASS.

- [ ] **Step 5: Wire the store**

In `HolyWorkspaceStore.swift`:

```swift
    private static let keepAwakeDefaultsKey = "HolyKeepAwakeWhileRemoteAttached"
    private let powerAssertionManager = HolyPowerAssertionManager()

    @Published var keepAwakeWhileRemoteAttached: Bool = UserDefaults.standard.object(
        forKey: HolyWorkspaceStore.keepAwakeDefaultsKey
    ) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(keepAwakeWhileRemoteAttached, forKey: Self.keepAwakeDefaultsKey)
            updatePowerAssertion()
        }
    }

    private func updatePowerAssertion() {
        let hasRemoteSessions = sessions.contains { canReattachSession($0) }
        powerAssertionManager.setActive(keepAwakeWhileRemoteAttached && hasRemoteSessions)
    }
```

Call `updatePowerAssertion()` at the end of `applySessionStoreState(...)` (the choke point every roster mutation flows through) and at the end of `applyConvergeActions(...)`.

- [ ] **Step 6: Build + run all tests so far, commit**

Run: test command with each of `HolyPowerAssertionManagerTests`, `HolyConvergeGateTests`. Expected: PASS.

```bash
git add macos/Sources/HolyGhostty/App/HolyPowerAssertionManager.swift macos/Tests/HolyGhostty/HolyPowerAssertionManagerTests.swift macos/Sources/HolyGhostty/Workspace/HolyWorkspaceStore.swift
git commit -m "feat(macos): keep-awake power assertion while remote sessions attached"
```

---

### Task 6: Wake observer + pane-exit trigger with backoff

**Files:**
- Modify: `macos/Sources/HolyGhostty/Session/HolySession.swift:568` (phase-transition hook)
- Modify: `macos/Sources/HolyGhostty/App/HolyWorkspaceWindowController.swift` (wake observer, follow the `addObserver` pattern at line 71)
- Modify: `macos/Sources/HolyGhostty/Workspace/HolyWorkspaceStore.swift` (backoff scheduling + notification subscription)
- Create: `macos/Sources/HolyGhostty/Workspace/HolyRepairBackoff.swift`
- Create: `macos/Tests/HolyGhostty/HolyRepairBackoffTests.swift`

**Interfaces:**
- Consumes: `convergeRoster(reason:)` and `reattach(_:)` (Task 4 / existing).
- Produces:
  - `struct HolyRepairBackoff { mutating func nextDelay(for: UUID) -> TimeInterval?; mutating func reset(_ UUID); mutating func resetAll() }` — delays `[4, 10, 25]`, then `nil`.
  - `Notification.Name.holyRemoteSessionPaneDied` posted by `HolySession` with `userInfo: ["sessionID": UUID]`.
  - `HolyWorkspaceStore.convergeOnSystemWake()` — resets backoff, converges with `.wake`.

- [ ] **Step 1: Write the failing backoff tests**

Create `macos/Tests/HolyGhostty/HolyRepairBackoffTests.swift`:

```swift
import Foundation
import Testing
@testable import Ghostty

struct HolyRepairBackoffTests {
    @Test func delaysFollowScheduleThenStop() {
        var backoff = HolyRepairBackoff()
        let id = UUID()
        #expect(backoff.nextDelay(for: id) == 4)
        #expect(backoff.nextDelay(for: id) == 10)
        #expect(backoff.nextDelay(for: id) == 25)
        #expect(backoff.nextDelay(for: id) == nil)
    }

    @Test func sessionsBackOffIndependently() {
        var backoff = HolyRepairBackoff()
        let first = UUID()
        let second = UUID()
        #expect(backoff.nextDelay(for: first) == 4)
        #expect(backoff.nextDelay(for: second) == 4)
    }

    @Test func resetAllRestoresTheSchedule() {
        var backoff = HolyRepairBackoff()
        let id = UUID()
        _ = backoff.nextDelay(for: id)
        _ = backoff.nextDelay(for: id)
        backoff.resetAll()
        #expect(backoff.nextDelay(for: id) == 4)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail to compile**

Run: test command with `HolyRepairBackoffTests`. Expected: build FAILS.

- [ ] **Step 3: Implement backoff**

Create `macos/Sources/HolyGhostty/Workspace/HolyRepairBackoff.swift`:

```swift
import Foundation

/// Retry schedule for automatic repair of a dead remote pane. Three attempts
/// with growing delays, then silence until a wake or manual Sync resets it.
struct HolyRepairBackoff {
    static let delays: [TimeInterval] = [4, 10, 25]

    private var attemptsBySessionID: [UUID: Int] = [:]

    mutating func nextDelay(for sessionID: UUID) -> TimeInterval? {
        let attempt = attemptsBySessionID[sessionID, default: 0]
        guard attempt < Self.delays.count else { return nil }
        attemptsBySessionID[sessionID] = attempt + 1
        return Self.delays[attempt]
    }

    mutating func reset(_ sessionID: UUID) {
        attemptsBySessionID.removeValue(forKey: sessionID)
    }

    mutating func resetAll() {
        attemptsBySessionID.removeAll()
    }
}
```

Run: same command. Expected: 3 PASS.

- [ ] **Step 4: Post pane-death from HolySession**

In `HolySession.swift`, the phase assignment at line 565-567 currently reads:

```swift
        if phase != nextPhase {
            phase = nextPhase
        }
```

Replace with:

```swift
        if phase != nextPhase {
            let previousPhase = phase
            phase = nextPhase
            notifyIfRemotePaneDied(previousPhase: previousPhase, nextPhase: nextPhase)
        }
```

Add to `HolySession` (near other private helpers), plus the name at file bottom:

```swift
    private func notifyIfRemotePaneDied(previousPhase: HolySessionPhase, nextPhase: HolySessionPhase) {
        guard nextPhase == .completed || nextPhase == .failed,
              previousPhase != .completed, previousPhase != .failed,
              record.launchSpec.transport.isRemote,
              record.launchSpec.tmux?.sessionName?.isEmpty == false else {
            return
        }

        NotificationCenter.default.post(
            name: .holyRemoteSessionPaneDied,
            object: nil,
            userInfo: ["sessionID": id]
        )
    }
```

```swift
extension Notification.Name {
    static let holyRemoteSessionPaneDied = Notification.Name("holyRemoteSessionPaneDied")
}
```

(If `transport.isRemote` is inaccessible from this file, use `record.launchSpec.transport.kind == .ssh` — both exist; `isRemote` is used in `HolyTmuxCommandBuilder.swift:99`.)

- [ ] **Step 5: Store — subscribe and schedule repairs**

In `HolyWorkspaceStore` (init/bind area — where other Combine subscriptions live):

```swift
        NotificationCenter.default.publisher(for: .holyRemoteSessionPaneDied)
            .compactMap { $0.userInfo?["sessionID"] as? UUID }
            .sink { [weak self] sessionID in
                self?.scheduleRepair(sessionID: sessionID)
            }
            .store(in: &cancellables)
```

And the scheduling + wake entry point:

```swift
    private var repairBackoff = HolyRepairBackoff()

    private func scheduleRepair(sessionID: UUID) {
        guard let delay = repairBackoff.nextDelay(for: sessionID) else { return }

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await MainActor.run {
                guard let self,
                      let session = self.sessions.first(where: { $0.id == sessionID }),
                      session.surfaceView.processExited,
                      self.canReattachSession(session) else { return }
                self.reattach(session)
            }
        }
    }

    func convergeOnSystemWake() {
        repairBackoff.resetAll()
        convergeRoster(reason: .wake)
    }
```

Also add `repairBackoff.resetAll()` as the first line of the `reason == .manual` path — simplest: at the top of `convergeRoster(reason:)` add:

```swift
        if reason == .manual { repairBackoff.resetAll() }
```

(If the store has no `cancellables` set, it does — `HolySession.bind()` uses one; check the store for an existing `Set<AnyCancellable>` and reuse it; if none exists, add `private var cancellables: Set<AnyCancellable> = []` and `import Combine` is already present.)

- [ ] **Step 6: Wake observer in the window controller**

In `HolyWorkspaceWindowController` where observers are registered (pattern at line 71):

```swift
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(holySystemDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
```

And the handler + teardown (deinit near line 84 currently removes from `NotificationCenter.default`; add the workspace center too):

```swift
    @objc private func holySystemDidWake(_ notification: Notification) {
        Task { @MainActor [weak self] in
            // Tailscale and Wi-Fi need a moment after wake before SSH works.
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            self?.workspaceStore.convergeOnSystemWake()
        }
    }
```

```swift
        NSWorkspace.shared.notificationCenter.removeObserver(self)
```

- [ ] **Step 7: Build + run all new tests, commit**

Run: test command with `HolyRepairBackoffTests`; then a plain build of the scheme to confirm the session/store/controller edits compile.
Expected: PASS / BUILD SUCCEEDED.

```bash
git add macos/Sources/HolyGhostty/Workspace/HolyRepairBackoff.swift macos/Tests/HolyGhostty/HolyRepairBackoffTests.swift macos/Sources/HolyGhostty/Session/HolySession.swift macos/Sources/HolyGhostty/Workspace/HolyWorkspaceStore.swift macos/Sources/HolyGhostty/App/HolyWorkspaceWindowController.swift
git commit -m "feat(macos): self-heal remote panes on wake and pane exit"
```

---

### Task 7: UI — Sync progress state + keep-awake toggle

**Files:**
- Modify: `macos/Sources/HolyGhostty/Workspace/HolySessionRosterView.swift:364-370` (Sync button) and the overflow `Menu` (label `ellipsis.circle`, ~line 219-310)

**Interfaces:**
- Consumes: `store.isConverging`, `store.keepAwakeWhileRemoteAttached` (Tasks 4-5). `reattachAllSessions()` already routes to converge — the button action does not change.

- [ ] **Step 1: Update the Sync button**

Replace (roster ~line 364):

```swift
                rosterActionButton(
                    title: "Sync",
                    symbol: "arrow.triangle.2.circlepath",
                    help: "Refresh and reconnect tmux sessions in this roster",
                    action: { store.reattachAllSessions() }
                )
                .disabled(!store.hasReattachableSessions)
```

with:

```swift
                rosterActionButton(
                    title: store.isConverging ? "Syncing" : "Sync",
                    symbol: "arrow.triangle.2.circlepath",
                    help: "Converge the roster with live tmux sessions: attach new, repair dead, never touch healthy panes",
                    action: { store.reattachAllSessions() }
                )
                .disabled(store.isConverging)
```

(The old `hasReattachableSessions` gate is intentionally dropped: converge is useful with an empty roster — it discovers and attaches new sessions.)

- [ ] **Step 2: Add the keep-awake toggle to the overflow menu**

Inside the `Menu { ... }` whose label is `Image(systemName: "ellipsis.circle")` (~line 219), add at the end of the menu content, separated with a `Divider()`:

```swift
                Divider()

                Toggle(
                    "Keep Mac Awake While Remote Sessions Attached",
                    isOn: Binding(
                        get: { store.keepAwakeWhileRemoteAttached },
                        set: { store.keepAwakeWhileRemoteAttached = $0 }
                    )
                )
```

- [ ] **Step 3: Build, verify, commit**

Run: plain scheme build (test command minus `-only-testing` and with `build` instead of `test`).
Expected: BUILD SUCCEEDED, no new SwiftLint warnings.

```bash
git add macos/Sources/HolyGhostty/Workspace/HolySessionRosterView.swift
git commit -m "feat(macos): sync progress state and keep-awake toggle"
```

---

### Task 8: Full test pass, install, manual verification

**Files:** none new.

- [ ] **Step 1: Run the complete new + existing test set**

Run the Global Constraints test command once per class:
`HolyTmuxCommandFlagTests`, `HolyConvergePlannerTests`, `HolyConvergeGateTests`, `HolyPowerAssertionManagerTests`, `HolyRepairBackoffTests`, `HolyPaneLayoutTests`, `HolySessionLiveStatusTests`, `HolySessionRuntimeInferenceTests`, `HolySessionTelemetryCommandTests`.
Expected: every class PASSES.

- [ ] **Step 2: Install and relaunch**

```bash
rm -rf "macos/build/ReleaseLocal/Holy Ghostty.app"
./scripts/install-holy-ghostty.sh ReleaseLocal
osascript -e 'tell application "Holy Ghostty" to quit' 2>/dev/null; pkill -f '/Applications/Holy Ghostty.app/Contents/MacOS/holy-ghostty' 2>/dev/null
open "/Applications/Holy Ghostty.app"
ps aux | grep "Holy Ghostty.app/Contents/MacOS/holy-ghostty" | grep -v grep
```

Expected: BUILD SUCCEEDED, signed with Apple Development identity, new PID running.

- [ ] **Step 3: Manual verification checklist (user-assisted where sleep is involved)**

- Sync with one host asleep: press Sync → completes in seconds (not minutes), healthy panes untouched, button shows "Syncing" while running.
- Assertion live: with ≥1 remote session attached, `pmset -g assertions | grep -i "Holy Ghostty"` shows PreventUserIdleSystemSleep. Toggle off in the overflow menu → assertion disappears.
- Attach flags live: `ps aux | grep "ssh -tt"` shows `ServerAliveInterval=15` on remote panes (new panes only — existing panes keep old commands until repaired).
- Lid-close self-heal: close lid ~1 min, open → within ~5-10s dead remote panes re-attach without manual action.
- New-session discovery: create a tmux session on a host outside Holy → Sync → it appears in the roster.

- [ ] **Step 4: Final commit if any fixups, report results with evidence**

---

## Self-Review Notes

- **Spec coverage:** L2 attach flags (Task 1), detach fail-fast (Task 2), diff buckets incl. zombie corroboration + multi-client masking + unreachable-untouched + auto-archive (Task 3), sweep/single-flight/debounce/manual trigger + identity-preserving repair via existing `reattach` (Task 4), L1 assertion + toggle + default-on (Task 5), wake trigger with settle + debounce reset + pane-exit backoff [4,10,25] (Task 6), Sync progress + toggle UI (Task 7), manual sleep scenarios (Task 8). No uncovered spec section.
- **Deviations from spec, both deliberate:** keep-awake preference in `UserDefaults` instead of the app-state DB (device-local policy, documented in Task 5); Sync in-progress state is a disabled "Syncing" button rather than a spinner (rosterActionButton has no spinner affordance; YAGNI).
- **Type consistency:** `HolyConvergeAction`/`plan(roster:discovered:reachableHostKeys:)` identical in Tasks 3-4; `convergeRoster(reason:)`/`isConverging` identical in Tasks 4, 6, 7; `keepAwakeWhileRemoteAttached` identical in Tasks 5, 7; backoff delays `[4,10,25]` consistent between Task 6 code and tests.
- **Known execution risks called out in-plan:** exact `HolySessionLaunchSpec`/transport accessor names verified against source (`isRemote` builder:99, `kind == .ssh` store:1729); `discoverSessionsThrowing` call shape copied from store:1016; if the store lacks a `cancellables` set, Task 6 Step 5 adds one.
