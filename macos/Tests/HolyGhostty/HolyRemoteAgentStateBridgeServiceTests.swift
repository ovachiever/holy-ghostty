import Foundation
import Testing
@testable import Ghostty

struct HolyRemoteAgentStateBridgeServiceTests {
    @Test func commandPlanKeepsDestinationOutOfRemoteShellSource() throws {
        let destination = "builder@[2001:db8::1]"
        let plan = try HolyRemoteAgentStateBridgeService.commandPlanForTesting(
            destination: destination
        )

        #expect(plan.executablePath == "/usr/bin/ssh")
        #expect(plan.arguments.contains(destination))
        #expect(plan.arguments[plan.arguments.count - 2] == destination)
        #expect(!plan.arguments.last!.contains(destination))
        #expect(plan.arguments.contains("BatchMode=yes"))
        #expect(plan.arguments.contains("ConnectTimeout=5"))

        #expect(throws: HolyRemoteAgentStateBridgeServiceError.invalidDestination) {
            _ = try HolyRemoteAgentStateBridgeService.commandPlanForTesting(
                destination: "-oProxyCommand=touch-owned"
            )
        }
        #expect(throws: HolyRemoteAgentStateBridgeServiceError.invalidDestination) {
            _ = try HolyRemoteAgentStateBridgeService.commandPlanForTesting(
                destination: "host\ncommand"
            )
        }
    }

    @Test func remoteTransactionPreservesUnrelatedSettingsWithoutReturningThem() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let secret = "TOP-SECRET-REMOTE-VALUE"
        try fixture.writeJSON([
            "model": "opus",
            "env": ["PRIVATE_TOKEN": secret],
            "hooks": [
                "Stop": [["hooks": [["type": "command", "command": "keep-claude-hook"]]]],
            ],
        ], to: fixture.claudeURL)
        try fixture.writeJSON([
            "trust": ["external": true],
            "hooks": [
                "Stop": [["hooks": [["type": "command", "command": "keep-codex-hook"]]]],
            ],
        ], to: fixture.codexURL)
        let originalCodexConfig = "# \(secret) stays remote\nmodel = \"gpt-5.4\"\n\n[tui]\nnotifications = true\n"
        try fixture.write(originalCodexConfig, to: fixture.codexConfigURL)

        let before = try await HolyRemoteAgentStateBridgeService.runTransactionForTesting(
            action: .inspect,
            home: fixture.home
        )
        #expect(before.result.state == .notInstalled)

        let installed = try await HolyRemoteAgentStateBridgeService.runTransactionForTesting(
            action: .install,
            home: fixture.home
        )
        #expect(installed.result.state == .installed)
        #expect(installed.result.manualTrustHarnesses == ["codex"])
        let responseText = try #require(String(bytes: installed.stdout, encoding: .utf8))
        #expect(!responseText.contains(secret))
        #expect(!responseText.contains("keep-claude-hook"))

        let claude = try fixture.readJSON(fixture.claudeURL)
        let codex = try fixture.readJSON(fixture.codexURL)
        #expect((claude["env"] as? [String: String])?["PRIVATE_TOKEN"] == secret)
        #expect(fixture.commands(in: claude).contains("keep-claude-hook"))
        #expect(fixture.commands(in: codex).contains("keep-codex-hook"))
        #expect((codex["trust"] as? [String: Bool])?["external"] == true)
        #expect(FileManager.default.fileExists(atPath: fixture.helperURL.path))
        #expect(FileManager.default.fileExists(atPath: fixture.openCodeURL.path))
        #expect(FileManager.default.fileExists(atPath: fixture.codexNotifyAdapterURL.path))
        let installedCodexConfig = try String(contentsOf: fixture.codexConfigURL, encoding: .utf8)
        #expect(installedCodexConfig.hasSuffix(originalCodexConfig))
        #expect(installedCodexConfig.contains(HolyAgentStateBridge.codexNotifyConfigurationMarker))

        let repeated = try await HolyRemoteAgentStateBridgeService.runTransactionForTesting(
            action: .install,
            home: fixture.home
        )
        #expect(repeated.result.state == .installed)
        let inspected = try await HolyRemoteAgentStateBridgeService.runTransactionForTesting(
            action: .inspect,
            home: fixture.home
        )
        #expect(inspected.result.state == .installed)

        let removed = try await HolyRemoteAgentStateBridgeService.runTransactionForTesting(
            action: .remove,
            home: fixture.home
        )
        #expect(removed.result.state == .notInstalled)
        let remainingClaude = try fixture.readJSON(fixture.claudeURL)
        let remainingCodex = try fixture.readJSON(fixture.codexURL)
        #expect(fixture.commands(in: remainingClaude) == ["keep-claude-hook"])
        #expect(fixture.commands(in: remainingCodex) == ["keep-codex-hook"])
        #expect((remainingClaude["env"] as? [String: String])?["PRIVATE_TOKEN"] == secret)
        #expect(try String(contentsOf: fixture.codexConfigURL, encoding: .utf8) == originalCodexConfig)
        #expect(!FileManager.default.fileExists(atPath: fixture.helperURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.openCodeURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.codexNotifyAdapterURL.path))
    }

    @Test func malformedRemoteJSONFailsClosedBeforeWritingOwnedFiles() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.write("not-json\n", to: fixture.claudeURL)
        try fixture.writeJSON(["keep": true], to: fixture.codexURL)
        let claudeBefore = try Data(contentsOf: fixture.claudeURL)
        let codexBefore = try Data(contentsOf: fixture.codexURL)

        let result = try await HolyRemoteAgentStateBridgeService.runTransactionForTesting(
            action: .install,
            home: fixture.home
        )

        guard case .blocked = result.result.state else {
            Issue.record("Malformed remote JSON must block installation")
            return
        }
        #expect(try Data(contentsOf: fixture.claudeURL) == claudeBefore)
        #expect(try Data(contentsOf: fixture.codexURL) == codexBefore)
        #expect(!FileManager.default.fileExists(atPath: fixture.helperURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.openCodeURL.path))
    }

    @Test func removalFromEmptyHostDoesNotCreateConfigurationFiles() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let result = try await HolyRemoteAgentStateBridgeService.runTransactionForTesting(
            action: .remove,
            home: fixture.home
        )

        #expect(result.result.state == .notInstalled)
        #expect(!FileManager.default.fileExists(atPath: fixture.claudeURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.codexURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.codexConfigURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.helperURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.openCodeURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.codexNotifyAdapterURL.path))
    }

    @Test func installThenRemoveOnEmptyHostLeavesNoOwnedArtifacts() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let installed = try await HolyRemoteAgentStateBridgeService.runTransactionForTesting(
            action: .install,
            home: fixture.home
        )
        #expect(installed.result.state == .installed)

        let removed = try await HolyRemoteAgentStateBridgeService.runTransactionForTesting(
            action: .remove,
            home: fixture.home
        )
        #expect(removed.result.state == .notInstalled)
        #expect(!FileManager.default.fileExists(atPath: fixture.codexConfigURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.helperURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.openCodeURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.codexNotifyAdapterURL.path))
    }

    @Test func foreignRemoteCodexNotifyFailsClosedWithoutLeakingOrMutating() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let secret = "REMOTE-NOTIFIER-SECRET"
        let config = "notify = [\"/usr/local/bin/\(secret)\"]\n\n[tui]\nnotifications = true\n"
        try fixture.write(config, to: fixture.codexConfigURL)

        let result = try await HolyRemoteAgentStateBridgeService.runTransactionForTesting(
            action: .install,
            home: fixture.home
        )

        guard case let .blocked(message) = result.result.state else {
            Issue.record("A foreign remote Codex notifier must block installation")
            return
        }
        #expect(message.contains("already has a different value"))
        let response = try #require(String(bytes: result.stdout, encoding: .utf8))
        #expect(!response.contains(secret))
        #expect(try String(contentsOf: fixture.codexConfigURL, encoding: .utf8) == config)
        #expect(!FileManager.default.fileExists(atPath: fixture.helperURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.codexNotifyAdapterURL.path))
    }

    @Test func multilineRemoteCodexNotifyFailsClosedWithoutMutation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let config = "notify = [\n  \"terminal-notifier\",\n]\n"
        try fixture.write(config, to: fixture.codexConfigURL)

        let result = try await HolyRemoteAgentStateBridgeService.runTransactionForTesting(
            action: .install,
            home: fixture.home
        )

        guard case .blocked = result.result.state else {
            Issue.record("A multiline remote Codex notifier must block installation")
            return
        }
        #expect(try String(contentsOf: fixture.codexConfigURL, encoding: .utf8) == config)
        #expect(!FileManager.default.fileExists(atPath: fixture.helperURL.path))
    }

    @Test func foreignExactFileBlocksBeforeAnyRemoteMutation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeJSON(["model": "keep"], to: fixture.claudeURL)
        try fixture.write("// user-owned plugin\n", to: fixture.openCodeURL)
        let claudeBefore = try Data(contentsOf: fixture.claudeURL)
        let pluginBefore = try Data(contentsOf: fixture.openCodeURL)

        let result = try await HolyRemoteAgentStateBridgeService.runTransactionForTesting(
            action: .install,
            home: fixture.home
        )

        guard case .blocked = result.result.state else {
            Issue.record("A foreign exact-file target must block installation")
            return
        }
        #expect(try Data(contentsOf: fixture.claudeURL) == claudeBefore)
        #expect(try Data(contentsOf: fixture.openCodeURL) == pluginBefore)
        #expect(!FileManager.default.fileExists(atPath: fixture.helperURL.path))
    }

    @Test func failedMultiFileWriteRollsBackEveryCompletedMutation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeJSON(["claude": "original"], to: fixture.claudeURL)
        try fixture.writeJSON(["codex": "original"], to: fixture.codexURL)
        let claudeBefore = try Data(contentsOf: fixture.claudeURL)
        let codexBefore = try Data(contentsOf: fixture.codexURL)

        let result = try await HolyRemoteAgentStateBridgeService.runTransactionForTesting(
            action: .install,
            home: fixture.home,
            failAt: 3
        )

        guard case .blocked = result.result.state else {
            Issue.record("Injected write failure must be reported as blocked")
            return
        }
        #expect(try Data(contentsOf: fixture.claudeURL) == claudeBefore)
        #expect(try Data(contentsOf: fixture.codexURL) == codexBefore)
        #expect(!FileManager.default.fileExists(atPath: fixture.helperURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.openCodeURL.path))
    }

    @Test func symlinkOutsideRemoteHomeFailsClosed() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let outside = fixture.root.appendingPathComponent("outside.json")
        try Data("{\"outside\":true}\n".utf8).write(to: outside)
        try FileManager.default.createDirectory(
            at: fixture.claudeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: fixture.claudeURL,
            withDestinationURL: outside
        )
        let outsideBefore = try Data(contentsOf: outside)

        let result = try await HolyRemoteAgentStateBridgeService.runTransactionForTesting(
            action: .install,
            home: fixture.home
        )

        guard case .blocked = result.result.state else {
            Issue.record("A symlink escaping the remote home must block installation")
            return
        }
        #expect(try Data(contentsOf: outside) == outsideBefore)
        #expect(!FileManager.default.fileExists(atPath: fixture.helperURL.path))
    }
}

private final class Fixture {
    let root: URL
    let home: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-remote-agent-state-tests-\(UUID().uuidString)", isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    var claudeURL: URL {
        home.appendingPathComponent(".claude/settings.json")
    }

    var codexURL: URL {
        home.appendingPathComponent(".codex/hooks.json")
    }

    var codexConfigURL: URL {
        home.appendingPathComponent(".codex/config.toml")
    }

    var helperURL: URL {
        home.appendingPathComponent(".local/share/holy-ghostty/agent-state-hook.sh")
    }

    var openCodeURL: URL {
        home.appendingPathComponent(".config/opencode/plugins/holy-agent-state.ts")
    }

    var codexNotifyAdapterURL: URL {
        home.appendingPathComponent(
            ".local/share/holy-ghostty/\(HolyAgentStateBridge.codexNotifyAdapterFileName)"
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func writeJSON(_ value: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    func write(_ value: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(value.utf8).write(to: url)
    }

    func readJSON(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func commands(in root: [String: Any]) -> [String] {
        guard let hooks = root["hooks"] as? [String: Any] else { return [] }
        return hooks.keys.sorted().flatMap { event -> [String] in
            guard let groups = hooks[event] as? [[String: Any]] else { return [] }
            return groups.flatMap { group in
                (group["hooks"] as? [[String: Any]] ?? []).compactMap {
                    $0["command"] as? String
                }
            }
        }
    }
}
