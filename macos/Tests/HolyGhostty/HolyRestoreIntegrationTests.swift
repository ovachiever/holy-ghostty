import Foundation
import Testing
@testable import Ghostty

// Real-tmux coverage for the restore engine's create/verify/adopt loop.
// Every test runs on its own disposable `-L` socket; nothing here can touch
// the default server or the managed `holy` server. The resolver contract
// itself is exercised against the installed agent-sessions binary when one
// is present, using a nonexistent cwd so the outcome shape is deterministic
// without depending on this machine's index contents.

private let tmuxAvailableForRestoreTests: Bool = {
    runRestoreTestShell("command -v tmux >/dev/null 2>&1") == 0
}()

@discardableResult
private func runRestoreTestShell(_ script: String) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-lc", script]
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    process.environment = HolyTmuxLifecycleService.scrubbedTmuxEnvironment(
        ProcessInfo.processInfo.environment
    )
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    } catch {
        return -1
    }
}

/// A disposable tmux server namespace. Destroys only its own socket's server.
private struct IsolatedRestoreTmuxServer {
    let socketName: String

    init() {
        let suffix = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .prefix(10)
            .lowercased()
        socketName = "holy-restore-drill-\(suffix)"
    }

    // The exact target must be single-quoted: an unquoted leading `=` is
    // zsh equals-expansion and errors out before tmux ever runs.
    func hasSession(_ sessionName: String) -> Bool {
        runRestoreTestShell("tmux -L \(socketName) has-session -t '=\(sessionName)' >/dev/null 2>&1") == 0
    }

    func paneCurrentPath(_ sessionName: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            "-lc",
            "tmux -L \(socketName) display-message -p -t '=\(sessionName):' '#{pane_current_path}'",
        ]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        process.environment = HolyTmuxLifecycleService.scrubbedTmuxEnvironment(
            ProcessInfo.processInfo.environment
        )
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(bytes: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func destroy() {
        runRestoreTestShell("tmux -L \(socketName) kill-server >/dev/null 2>&1 || true")
    }

    func identity(for sessionName: String) throws -> HolyTmuxLiveIdentity {
        try #require(HolyTmuxLiveIdentity(
            transport: .local,
            socketName: socketName,
            sessionName: sessionName
        ))
    }
}

struct HolyRestoreIntegrationTests {
    private func restoredSpec(
        socketName: String,
        sessionName: String,
        workingDirectory: String,
        command: String?
    ) -> HolySessionLaunchSpec {
        var spec = HolySessionLaunchSpec.interactiveTmuxShell(title: "Restore Drill")
        spec.runtime = .shell
        spec.command = command
        spec.workingDirectory = workingDirectory
        spec.tmux = .init(
            socketName: socketName,
            sessionName: sessionName,
            createIfMissing: true
        )
        return spec
    }

    @Test(.enabled(if: tmuxAvailableForRestoreTests))
    func detachedCreateProducesALiveVerifiableSessionInTheRequestedCwd() async throws {
        let server = IsolatedRestoreTmuxServer()
        defer { server.destroy() }
        let sessionName = "restore-int-create"
        let workingDirectory = FileManager.default.temporaryDirectory
            .standardizedFileURL.path
        let spec = restoredSpec(
            socketName: server.socketName,
            sessionName: sessionName,
            workingDirectory: workingDirectory,
            command: "printf 'HOLY_RESTORE_MARKER\\n'"
        )

        let service = HolyRestoreTmuxService()
        let createFailure = await service.createDetached(for: spec)
        #expect(createFailure == nil)

        let identity = try server.identity(for: sessionName)
        #expect(await service.liveness(for: identity) == .present)
        #expect(server.hasSession(sessionName))
        let panePath = try #require(server.paneCurrentPath(sessionName))
        // tmux reports the pane's resolved path (/private/tmp for /tmp).
        #expect(
            URL(fileURLWithPath: panePath).resolvingSymlinksInPath().path
                == URL(fileURLWithPath: workingDirectory).resolvingSymlinksInPath().path
        )
    }

    @Test(.enabled(if: tmuxAvailableForRestoreTests))
    func detachedCreateIsIdempotentAgainstALiveSession() async throws {
        let server = IsolatedRestoreTmuxServer()
        defer { server.destroy() }
        let sessionName = "restore-int-idempotent"
        let spec = restoredSpec(
            socketName: server.socketName,
            sessionName: sessionName,
            workingDirectory: FileManager.default.temporaryDirectory.path,
            command: "printf 'FIRST_CREATE\\n'"
        )

        let service = HolyRestoreTmuxService()
        #expect(await service.createDetached(for: spec) == nil)

        // Second create with a DIFFERENT command must be a no-op: the
        // has-session guard adopts the live session instead of recreating.
        var second = spec
        second.command = "printf 'SECOND_CREATE_WOULD_BE_A_BUG\\n'"
        #expect(await service.createDetached(for: second) == nil)

        let identity = try server.identity(for: sessionName)
        #expect(await service.liveness(for: identity) == .present)

        // Exactly one session with this name exists.
        let listStatus = runRestoreTestShell(
            "test \"$(tmux -L \(server.socketName) list-sessions -F '#{session_name}' | grep -cx '\(sessionName)')\" -eq 1"
        )
        #expect(listStatus == 0)
    }

    @Test(.enabled(if: tmuxAvailableForRestoreTests))
    func livenessReportsAbsenceForNeverCreatedIdentity() async throws {
        let server = IsolatedRestoreTmuxServer()
        defer { server.destroy() }
        // Boot the server with one unrelated session so the probe hits a
        // live server and still proves the exact name absent.
        _ = runRestoreTestShell("tmux -L \(server.socketName) new-session -d -s unrelated-anchor")

        let identity = try server.identity(for: "restore-int-missing")
        let service = HolyRestoreTmuxService()
        #expect(await service.liveness(for: identity) == .absent)
    }

    @Test(.enabled(if: tmuxAvailableForRestoreTests))
    func metadataAndOwnershipStampsSurviveOnTheDetachedSession() async throws {
        let server = IsolatedRestoreTmuxServer()
        defer { server.destroy() }
        let sessionName = "restore-int-metadata"
        var spec = restoredSpec(
            socketName: server.socketName,
            sessionName: sessionName,
            workingDirectory: FileManager.default.temporaryDirectory.path,
            command: nil
        )
        spec.runtime = .claude

        let service = HolyRestoreTmuxService()
        #expect(await service.createDetached(for: spec) == nil)

        let runtimeStatus = runRestoreTestShell(
            "test \"$(tmux -L \(server.socketName) show-options -qv -t '\(sessionName)' @holy_runtime)\" = claude"
        )
        #expect(runtimeStatus == 0)
        let ownerStatus = runRestoreTestShell(
            "test \"$(tmux -L \(server.socketName) show-options -qv -t '\(sessionName)' @holy_agent_state_owner_v1)\" = holy"
        )
        #expect(ownerStatus == 0)
    }

    // MARK: - Real resolver contract (skips when the CLI is not installed)

    private static let agentSessionsAvailable: Bool =
        runRestoreTestShell("command -v agent-sessions >/dev/null 2>&1") == 0
            || HolyAgentSessionsResolveClient.wellKnownBinaryPath() != nil

    /// Capability detection, not version sniffing: `resolve-batch --help`
    /// exits 0 only on builds where the subcommand landed. Until then the
    /// batch integration test skips and the app-side batch client is covered
    /// by the fixture tests against the pinned contract.
    private static let agentSessionsSupportsResolveBatch: Bool = {
        guard agentSessionsAvailable else { return false }
        if runRestoreTestShell(
            "command -v agent-sessions >/dev/null 2>&1 && agent-sessions resolve-batch --help >/dev/null 2>&1"
        ) == 0 {
            return true
        }
        guard let wellKnown = HolyAgentSessionsResolveClient.wellKnownBinaryPath() else {
            return false
        }
        return runRestoreTestShell("'\(wellKnown)' resolve-batch --help >/dev/null 2>&1") == 0
    }()

    @Test(.enabled(if: agentSessionsAvailable))
    func realResolverHonorsThePinnedContractForAnUnknownCwd() async throws {
        let client = HolyAgentSessionsResolveClient()
        let outcome = await client.resolve(.init(
            workingDirectory: "/nonexistent/holy-restore-integration-\(UUID().uuidString)",
            harness: "claude",
            nearUnixSeconds: 1_785_261_280
        ))

        guard case let .resolved(resolution) = outcome else {
            Issue.record("Expected a resolved contract payload, got \(outcome)")
            return
        }
        #expect(!resolution.matched)
        #expect(resolution.providerSessionID == nil)
        #expect(resolution.confidence == HolyRestoreResolution.Confidence.none)
        #expect(resolution.candidates.isEmpty)
    }

    @Test(.enabled(if: agentSessionsSupportsResolveBatch))
    func realResolveBatchHonorsThePinnedContractForUnknownCwds() async throws {
        let client = HolyAgentSessionsResolveClient()
        let unknownCwd = "/nonexistent/holy-restore-batch-\(UUID().uuidString)"
        let outcome = await client.resolveBatch([
            .init(cwd: unknownCwd, harness: "claude", near: 1_785_261_280),
        ])

        guard case let .resolved(results) = outcome else {
            Issue.record("Expected a resolved batch payload, got \(outcome)")
            return
        }
        // One result per request in request order; a directory that never
        // existed gets a full result (no error) with zero candidates, and
        // the echoed harness is the canonical name, not the input string.
        #expect(results.count == 1)
        #expect(results.first?.cwd == unknownCwd)
        #expect(results.first?.harness == "claude-code")
        #expect(results.first?.runtime == "claude")
        #expect(results.first?.candidates.isEmpty == true)
        #expect(results.first?.error == nil)
    }
}
