import Foundation
import Testing
@testable import Ghostty

struct HolyHostStateMirrorTests {
    @Test func realHooksAndAcknowledgementsSurviveServerDeathAndAdoption() throws {
        let fixture = try HolyHostStateTestFixture()
        defer { fixture.stop() }
        try fixture.create()
        try fixture.hook(["codex", "working", "user-prompt", "conversation-123"])
        try fixture.hook(["codex", "finished", "turn-finished", "conversation-123:turn-1", "conversation-123"])
        let finish = try fixture.option("@holy_agent_last_finished_v1")
        let envelope = try HolyAgentStateEnvelope(wireValue: finish)
        let seen = try HolyAgentSeenState(wireValue: "v1|seen|\(envelope.occurredAtMilliseconds)|\(envelope.occurredAtMilliseconds + 1)")
        let update = try #require(HolyTmuxSessionMetadataUpdateCommand.command(
            for: fixture.spec, payload: .init(seenState: seen)
        ))
        try fixture.run(update.executableURL.path, update.arguments)
        let before = try fixture.registers()
        #expect(before.allSatisfy { !$0.isEmpty })
        // A fresh native connection proves this is disk state, independent of
        // the app's roster, its attention cache, and the tmux server process.
        let database = try HolyDatabase.open(at: fixture.database)
        #expect(try database.scalarInt64("SELECT COUNT(*) FROM host_indicator_state") == 5)
        fixture.stop()
        try fixture.create()
        #expect(try fixture.registers() == before)
        // Clear/adoption: lose every consumer cache and read the same host.
        let endpoint = HolyTmuxAgentStateEndpoint(hostID: UUID(), hostLabel: "fixture", location: .local, socketName: fixture.socket)
        let plan = try HolyTmuxAgentStateMonitor.commandPlan(for: endpoint)
        let output = try fixture.run(plan.executablePath, plan.arguments)
        let observations = try HolyTmuxAgentStateMonitor.parse(stdout: output, endpoint: endpoint, observedAt: .now)
        let observation = try #require(observations.values.first)
        #expect(observation.seenState == seen)
        #expect(observation.lastFinishedEnvelope?.wireValue == finish)
        #expect(observation.lastUsedEnvelope?.sessionID == "conversation-123")
        var record = HolySessionRecord(launchSpec: fixture.spec)
        #expect(record.captureHarnessSessionIdentity(from: try #require(observation.harnessIdentityEnvelope)))
        #expect(record.harnessSessionID == "conversation-123")
    }

    @Test func liveUnreadAndNewConversationWinOverSavedSeenAndIdentity() throws {
        let fixture = try HolyHostStateTestFixture()
        defer { fixture.stop() }
        try fixture.create()
        try fixture.hook(["codex", "working", "user-prompt", "old-conversation"])
        try fixture.tmux(["set-option", "-t", "fixture", "@holy_seen_v1", "v1|seen|10|11"])
        try fixture.mirror()
        try fixture.tmux(["set-option", "-t", "fixture", "@holy_seen_v1", "v1|unread||12"])
        try fixture.hook(["codex", "working", "user-prompt", "new-conversation"])
        try fixture.mirror()
        #expect(try fixture.option("@holy_seen_v1") == "v1|unread||12")
        fixture.stop()
        try fixture.create()
        #expect(try fixture.option("@holy_seen_v1") == "v1|unread||12")
        let identity = try HolyAgentStateEnvelope(wireValue: fixture.option("@holy_harness_identity_v1"))
        #expect(identity.sessionID == "new-conversation")
    }

    @Test func notifyWithoutThreadCannotInventOrEraseIdentity() throws {
        let fixture = try HolyHostStateTestFixture()
        defer { fixture.stop() }
        try fixture.create()
        try fixture.hook(["codex", "idle", "session-start", "real-thread"])
        let identity = try fixture.option("@holy_harness_identity_v1")
        try fixture.hook(["codex", "finished", "turn-finished", "turn-only"])
        #expect(try fixture.option("@holy_harness_identity_v1") == identity)
        #expect(try HolyAgentStateEnvelope(wireValue: fixture.option("@holy_agent_state_v1")).sessionID == "turn-only")
    }

}

/// Explicit opt-in acceptance, excluded from the ordinary focused suite. It
/// runs one real, read-only provider turn and never touches a live roster.
struct HolyCodexLiveAcceptanceTests {
    @MainActor
    @Test(.enabled(if: ProcessInfo.processInfo.environment["HOLY_LIVE_CODEX_ACCEPTANCE"] == "1"))
    func freshCodexConversationPersistsItsActualIdentity() async throws {
        let fixture = try HolyHostStateTestFixture()
        defer { fixture.stop() }
        let output = fixture.root.appendingPathComponent("codex.jsonl")
        let done = fixture.root.appendingPathComponent("exit-status")
        let adapter = fixture.root.appendingPathComponent("codex-notify.py")
        let notifyData = try JSONSerialization.data(withJSONObject: ["/usr/bin/python3", adapter.path], options: [.withoutEscapingSlashes])
        let notify = "notify=" + String(decoding: notifyData, as: UTF8.self)
        let discovery = await HolyRestoreEnvironmentProbe().discoverExecutable("codex", tmuxServerPath: nil)
        let executable = try #require(discovery.absolutePath)
        let argv = [executable, "exec", "--json", "--skip-git-repo-check", "-s", "read-only", "-C", fixture.root.path,
                    "-c", notify,
                    "This is an isolated Holy Ghostty identity acceptance probe. Do not use tools, inspect or change files, spawn agents, or continue project work. Reply exactly HOLY_CODEX_IDENTITY_ACCEPTED."]
        var spec = fixture.spec
        spec.command = argv.map(HolyHostStateMirror.quote).joined(separator: " ")
            + " > " + HolyHostStateMirror.quote(output.path) + " 2>&1; printf '%s' $? > " + HolyHostStateMirror.quote(done.path)
        try fixture.create(using: spec)
        let deadline = Date().addingTimeInterval(120)
        while !FileManager.default.fileExists(atPath: done.path), Date() < deadline {
            try await Task.sleep(for: .milliseconds(200))
        }
        let status = try String(contentsOf: done, encoding: .utf8)
        try #require(status == "0", "Real Codex failed; inspect \(output.path)")
        let records = try String(contentsOf: output, encoding: .utf8).split(separator: "\n").compactMap {
            try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
        }
        let started = try #require(records.first { $0["type"] as? String == "thread.started" })
        let actualThreadID = try #require(started["thread_id"] as? String)
        let endpoint = HolyTmuxAgentStateEndpoint(hostID: UUID(), hostLabel: "live fixture", location: .local, socketName: fixture.socket)
        let plan = try HolyTmuxAgentStateMonitor.commandPlan(for: endpoint)
        let snapshot = try HolyTmuxAgentStateMonitor.parse(
            stdout: fixture.run(plan.executablePath, plan.arguments), endpoint: endpoint, observedAt: .now
        )
        let identity = try #require(snapshot.values.first?.harnessIdentityEnvelope)
        try #require(identity.sessionID == actualThreadID)
        var record = HolySessionRecord(launchSpec: spec)
        let captured = record.captureHarnessSessionIdentity(from: identity)
        try #require(captured)
        let database = try HolyDatabase.open(at: fixture.database)
        try HolyDatabaseMigrator.migrate(database)
        try HolyWorkspaceDatabasePersistence.save(
            .init(sessions: [record], selectedSessionID: record.id),
            activeSessions: [], attentionBySessionID: [:], pendingEvents: [], in: database
        )
        let persisted = try #require(HolyWorkspaceDatabasePersistence.load(from: database)?.sessions.first)
        #expect(persisted.harnessSessionID == actualThreadID)
        try "thread_id=\(actualThreadID)\nholy_session_id=\(record.id)\ndatabase=\(fixture.database.path)\n".write(
            to: fixture.root.appendingPathComponent("identity-receipt.txt"), atomically: true, encoding: .utf8
        )
    }
}

private final class HolyHostStateTestFixture {
        let root: URL
        let database: URL
        let socket = "holy-state-test-" + UUID().uuidString
        let helper: URL
        var spec: HolySessionLaunchSpec {
            var value = HolySessionLaunchSpec.interactiveTmuxShell(title: "Fixture")
            value.runtime = .codex
            value.tmux = .init(socketName: socket, sessionName: "fixture", createIfMissing: true)
            value.command = "sleep 300"
            return value
        }

        init() throws {
            root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent(".dev/mn-reboot-recovery/fixtures/" + UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            database = root.appendingPathComponent("host.sqlite3")
            helper = root.appendingPathComponent("hook.sh")
            try HolyAgentStateBridge.helperScript.write(to: helper, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
            try HolyAgentStateBridge.codexNotifyAdapter(helperURL: helper).write(
                to: root.appendingPathComponent("codex-notify.py"), atomically: true, encoding: .utf8
            )
        }

        func create(using launchSpec: HolySessionLaunchSpec? = nil) throws {
            let command = try #require(HolyTmuxCommandBuilder.detachedCreateCommand(for: launchSpec ?? spec))
            try run(command.executablePath, command.arguments)
        }

        func stop() {
            _ = try? tmux(["kill-server"])
        }

        func hook(_ arguments: [String]) throws {
            let pane = try tmux(["display-message", "-p", "-t", "fixture", "#{pane_id}"])
            let address = try tmux(["display-message", "-p", "-t", "fixture", "#{socket_path},#{pid},0"])
            try run("/bin/sh", [helper.path] + arguments, extra: ["TMUX_PANE": pane, "TMUX": address])
        }

        func mirror() throws {
            try run("/bin/zsh", ["-lc", HolyHostStateMirror.command(tmuxPrefix: ["tmux", "-L", socket])])
        }

        func option(_ name: String) throws -> String {
            try tmux(["display-message", "-p", "-t", "fixture", "#{" + name + "}"])
        }

        func registers() throws -> [String] {
            try ["@holy_agent_state_v1", "@holy_agent_last_finished_v1", "@holy_agent_last_used_v1", "@holy_harness_identity_v1", "@holy_seen_v1"].map(option)
        }

        @discardableResult
        func tmux(_ arguments: [String]) throws -> String {
            try run("/bin/zsh", ["-lc", (["tmux", "-L", socket] + arguments).map(HolyHostStateMirror.quote).joined(separator: " ")])
        }

        @discardableResult
        func run(_ executable: String, _ arguments: [String], extra: [String: String] = [:]) throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            var environment = ProcessInfo.processInfo.environment
            environment.removeValue(forKey: "TMUX")
            environment.removeValue(forKey: "TMUX_PANE")
            environment["HOLY_HOST_STATE_DATABASE"] = database.path
            environment["HOLY_AGENT_STATE_TTY"] = root.appendingPathComponent("osc").path
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            environment.merge(extra) { _, new in new }
            process.environment = environment
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)
            #expect(process.terminationStatus == 0, "\(executable) failed: \(text)")
            return text
        }
    }
