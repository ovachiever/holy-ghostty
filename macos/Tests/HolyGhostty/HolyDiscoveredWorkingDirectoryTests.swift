import Foundation
import Testing
@testable import Ghostty

// mn-a7baaa. Receipt: session_events 985BC829 seq 167 recorded
// "/Users/erik/Custom-Coding/⠸ Research Comprehensive App Security | Custom-Coding"
// as a session's working directory: discovery appended a Codex window title to
// a generic pane directory, and HolySession wrote it into the launch spec.

private let tmuxAvailableForWorkingDirectoryTests: Bool = {
    runWorkingDirectoryTestTmux(["-V"]) == 0
}()

/// Runs `tmux <arguments>` through a login zsh (so Homebrew's tmux is on PATH)
/// with every argument passed positionally, never re-quoted into a string.
@discardableResult
private func runWorkingDirectoryTestTmux(_ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-lc", "tmux \"$@\"", "tmux"] + arguments
    var environment = ProcessInfo.processInfo.environment
    environment.removeValue(forKey: "TMUX")
    environment.removeValue(forKey: "TMUX_PANE")
    process.environment = environment
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    } catch {
        return -1
    }
}

/// tmux reports `pane_current_path` from the kernel, which resolves /tmp to
/// /private/tmp on macOS; expectations use the same resolved spelling.
private func resolvedPath(_ path: String) -> String {
    guard let resolved = realpath(path, nil) else { return path }
    defer { free(resolved) }
    return String(cString: resolved)
}

/// A scratch tmux server on its own socket (never the live `holy` socket)
/// with one pane whose cwd is `/tmp/holy-a7baaa-<id>/Custom-Coding`, a
/// generic directory name that arms title-based inference.
private final class ScratchTmuxPane {
    let socketName: String
    let sessionName: String
    let root: String
    let paneDirectory: String

    init() throws {
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        socketName = "holy-a7baaa-\(suffix)"
        sessionName = "verify-\(suffix)"
        root = "/tmp/holy-a7baaa-\(suffix)"
        paneDirectory = root + "/Custom-Coding"
        try FileManager.default.createDirectory(atPath: paneDirectory, withIntermediateDirectories: true)
        let started = runWorkingDirectoryTestTmux([
            "-L", socketName, "new-session", "-d", "-s", sessionName, "-c", paneDirectory, "/bin/cat",
        ])
        try #require(started == 0)
    }

    func setPaneTitle(_ title: String) throws {
        try #require(runWorkingDirectoryTestTmux([
            "-L", socketName, "select-pane", "-t", sessionName, "-T", title,
        ]) == 0)
    }

    func discoveredWorkingDirectory() async throws -> String? {
        let sessions = try await HolyRemoteTmuxDiscoveryService.shared.discoverLocalSessionsThrowing(
            hostID: UUID(),
            hostLabel: "This Mac",
            tmuxSocketName: socketName,
            includeHiddenSessions: true
        )
        let session = try #require(sessions.first { $0.sessionName == sessionName })
        return session.workingDirectory
    }

    func tearDown() {
        runWorkingDirectoryTestTmux(["-L", socketName, "kill-server"])
        // kill-server leaves the socket file behind; remove this fixture's own.
        let socketFile = Process()
        socketFile.executableURL = URL(fileURLWithPath: "/bin/zsh")
        socketFile.arguments = ["-c", "rm -f -- \"${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/$1\"", "rm", socketName]
        try? socketFile.run()
        socketFile.waitUntilExit()
        try? FileManager.default.removeItem(atPath: root)
    }
}

@Suite(.serialized)
struct HolyDiscoveredWorkingDirectoryTests {
    // MARK: Deliverable 1: discovery never emits a path that does not exist

    @Test(.enabled(if: tmuxAvailableForWorkingDirectoryTests))
    func spinnerStatusTitleNeverBecomesPathMaterial() async throws {
        let pane = try ScratchTmuxPane()
        defer { pane.tearDown() }
        try pane.setPaneTitle("⠸ Research Comprehensive App Security | Custom-Coding")

        let discovered = try await pane.discoveredWorkingDirectory()

        #expect(discovered == resolvedPath(pane.paneDirectory))
    }

    @Test(.enabled(if: tmuxAvailableForWorkingDirectoryTests))
    func titleNarrowsGenericDirectoryOnlyToAnExistingChild() async throws {
        let pane = try ScratchTmuxPane()
        defer { pane.tearDown() }
        try pane.setPaneTitle("Research")

        // No Research child yet: the pane's real path stands.
        #expect(try await pane.discoveredWorkingDirectory() == resolvedPath(pane.paneDirectory))

        let research = pane.paneDirectory + "/Research"
        try FileManager.default.createDirectory(atPath: research, withIntermediateDirectories: true)

        #expect(try await pane.discoveredWorkingDirectory() == resolvedPath(research))
    }

    @Test(.enabled(if: tmuxAvailableForWorkingDirectoryTests))
    func pipeAndTraversalTitlesAreRejectedEvenWhenTheyNameADirectory() async throws {
        let pane = try ScratchTmuxPane()
        defer { pane.tearDown() }
        // A directory literally named like a status line must still not be
        // adopted: a pipe is never path material.
        let piped = "Research | Custom-Coding"
        try FileManager.default.createDirectory(
            atPath: pane.paneDirectory + "/" + piped,
            withIntermediateDirectories: true
        )
        try pane.setPaneTitle(piped)
        #expect(try await pane.discoveredWorkingDirectory() == resolvedPath(pane.paneDirectory))

        try pane.setPaneTitle("..")
        #expect(try await pane.discoveredWorkingDirectory() == resolvedPath(pane.paneDirectory))
    }

    // MARK: Deliverable 2: the launch spec keeps its creation directory

    @MainActor
    @Test func recordedDirectoryIsNeverOverwrittenAndMissingObservationIsDropped() {
        let resolution = HolySession.resolvedDiscoveredWorkingDirectory(
            recorded: "/work/created-here",
            discovered: "/work/Custom-Coding/⠸ Research | Custom-Coding",
            transport: .local,
            directoryExists: { _ in false }
        )
        #expect(resolution.launchSpec == nil)
        #expect(resolution.observed == nil)
    }

    @MainActor
    @Test func existingObservationIsRecordedWithoutTouchingTheLaunchSpec() {
        let resolution = HolySession.resolvedDiscoveredWorkingDirectory(
            recorded: "/work/created-here",
            discovered: "/work/moved-here",
            transport: .local,
            directoryExists: { $0 == "/work/moved-here" }
        )
        #expect(resolution.launchSpec == nil)
        #expect(resolution.observed == "/work/moved-here")
    }

    @MainActor
    @Test func blankLaunchSpecAdoptsOnlyAnExistingDirectory() {
        let missing = HolySession.resolvedDiscoveredWorkingDirectory(
            recorded: "  ",
            discovered: "/work/missing",
            transport: .local,
            directoryExists: { _ in false }
        )
        #expect(missing.launchSpec == nil)
        #expect(missing.observed == nil)

        let present = HolySession.resolvedDiscoveredWorkingDirectory(
            recorded: nil,
            discovered: "/work/present",
            transport: .local,
            directoryExists: { _ in true }
        )
        #expect(present.launchSpec == "/work/present")
        #expect(present.observed == "/work/present")
    }

    @MainActor
    @Test func remoteObservationTrustsTheHostSideProbe() {
        var transport = HolySessionTransportSpec()
        transport.kind = .ssh
        transport.sshDestination = "studio"
        let resolution = HolySession.resolvedDiscoveredWorkingDirectory(
            recorded: "/Users/remote/created-here",
            discovered: "/Users/remote/moved-here",
            transport: transport,
            directoryExists: { _ in
                Issue.record("remote directories are probed on the host, never locally")
                return false
            }
        )
        #expect(resolution.launchSpec == nil)
        #expect(resolution.observed == "/Users/remote/moved-here")
    }

    // MARK: Deliverable 2 end to end on a live HolySession

    @MainActor
    @Test func liveSessionKeepsCreationDirectoryAndRecordsExistingObservation() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-a7baaa-\(UUID().uuidString)")
        let created = root.appendingPathComponent("created").path
        let moved = root.appendingPathComponent("moved").path
        try FileManager.default.createDirectory(atPath: created, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let config = try TemporaryConfig("command = /bin/cat\nshell-integration = none\n")
        let ghostty = Ghostty.App(configPath: config.temporaryFile.path)
        let app = try #require(ghostty.app)

        var spec = HolySessionLaunchSpec.interactiveShell(title: "a7baaa")
        spec.workingDirectory = created
        let session = HolySession(record: .init(launchSpec: spec), app: app)

        var discovered = spec
        discovered.workingDirectory = moved

        // Y does not exist: X stands and nothing is observed.
        session.applyDiscoveredLaunchMetadata(from: discovered, refreshGitSnapshot: false)
        #expect(session.record.launchSpec.workingDirectory == created)
        #expect(session.observedWorkingDirectory == nil)

        // Y exists: X still stands, Y is observed and archived as last known.
        try FileManager.default.createDirectory(atPath: moved, withIntermediateDirectories: true)
        session.applyDiscoveredLaunchMetadata(from: discovered, refreshGitSnapshot: false)
        #expect(session.record.launchSpec.workingDirectory == created)
        #expect(session.observedWorkingDirectory == moved)
        #expect(session.archiveSnapshot().lastKnownWorkingDirectory == moved)
        #expect(session.archiveSnapshot().record.launchSpec.workingDirectory == created)
    }
}
