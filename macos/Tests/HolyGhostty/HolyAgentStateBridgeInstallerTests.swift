import Foundation
import Testing
@testable import Ghostty

struct HolyAgentStateBridgeInstallerTests {
    @Test func installIsIdempotentAndRemovalPreservesUnrelatedConfiguration() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeJSON([
            "theme": "dark",
            "hooks": [
                "Stop": [["hooks": [["type": "command", "command": "keep-claude-hook"]]]],
            ],
        ], to: fixture.paths.claudeSettingsURL)
        try fixture.writeJSON([
            "trust": ["external": true],
            "hooks": [
                "Stop": [["hooks": [["type": "command", "command": "keep-codex-hook"]]]],
            ],
        ], to: fixture.paths.codexHooksURL)
        let originalCodexConfig = "# keep this comment\nmodel = \"gpt-5.4\"\n\n[tui]\nnotifications = true\n"
        try fixture.write(originalCodexConfig, to: fixture.paths.codexConfigURL)

        #expect(try HolyAgentStateBridgeInstaller.install(paths: fixture.paths) == .installed)
        #expect(try HolyAgentStateBridgeInstaller.installationState(paths: fixture.paths) == .installed)
        #expect(try HolyAgentStateBridgeInstaller.install(paths: fixture.paths) == .alreadyInstalled)
        #expect(try String(contentsOf: fixture.paths.helperURL, encoding: .utf8) == HolyAgentStateBridge.helperScript)
        #expect(
            try String(contentsOf: fixture.paths.openCodePluginURL, encoding: .utf8)
                == HolyAgentStateBridge.openCodePlugin(helperURL: fixture.paths.helperURL)
        )
        #expect(
            try String(contentsOf: fixture.paths.codexNotifyAdapterURL, encoding: .utf8)
                == HolyAgentStateBridge.codexNotifyAdapter(helperURL: fixture.paths.helperURL)
        )
        #expect(
            try String(contentsOf: fixture.paths.codexConfigURL, encoding: .utf8)
                == HolyAgentStateBridge.mergingCodexConfiguration(
                    originalCodexConfig,
                    adapterURL: fixture.paths.codexNotifyAdapterURL
                )
        )

        var claude = try fixture.readJSON(fixture.paths.claudeSettingsURL)
        var codex = try fixture.readJSON(fixture.paths.codexHooksURL)
        #expect(fixture.commands(in: claude).contains("keep-claude-hook"))
        #expect(fixture.commands(in: codex).contains("keep-codex-hook"))
        #expect((codex["trust"] as? [String: Bool])?["external"] == true)

        try HolyAgentStateBridgeInstaller.remove(paths: fixture.paths)

        claude = try fixture.readJSON(fixture.paths.claudeSettingsURL)
        codex = try fixture.readJSON(fixture.paths.codexHooksURL)
        #expect(fixture.commands(in: claude) == ["keep-claude-hook"])
        #expect(fixture.commands(in: codex) == ["keep-codex-hook"])
        #expect((codex["trust"] as? [String: Bool])?["external"] == true)
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.helperURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.openCodePluginURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.codexNotifyAdapterURL.path))
        #expect(try String(contentsOf: fixture.paths.codexConfigURL, encoding: .utf8) == originalCodexConfig)
    }

    @Test func foreignCodexNotifyBlocksBeforeAnyFileChanges() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let foreign = "# user notifier\nnotify = [\"terminal-notifier\"]\n"
        try fixture.write(foreign, to: fixture.paths.codexConfigURL)

        let state = try HolyAgentStateBridgeInstaller.installationState(paths: fixture.paths)
        guard case let .blocked(message) = state else {
            Issue.record("A foreign top-level Codex notifier must block installation")
            return
        }
        #expect(message.contains("will not overwrite or chain"))
        #expect(throws: HolyCodexNotifyConfigurationError.foreignNotify) {
            _ = try HolyAgentStateBridgeInstaller.install(paths: fixture.paths)
        }
        #expect(try String(contentsOf: fixture.paths.codexConfigURL, encoding: .utf8) == foreign)
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.helperURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.codexNotifyAdapterURL.path))
    }

    @Test func foreignCodexNotifyAdapterBlocksBeforeAnyFileChanges() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.write("#!/bin/sh\n# mine\n", to: fixture.paths.codexNotifyAdapterURL)

        #expect(
            try HolyAgentStateBridgeInstaller.installationState(paths: fixture.paths)
                == .blocked(HolyAgentStateBridgeInstallerError.foreignCodexNotifyAdapter.localizedDescription)
        )
        #expect(throws: HolyAgentStateBridgeInstallerError.self) {
            _ = try HolyAgentStateBridgeInstaller.install(paths: fixture.paths)
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.helperURL.path))
        #expect(try String(contentsOf: fixture.paths.codexNotifyAdapterURL, encoding: .utf8) == "#!/bin/sh\n# mine\n")
    }

    @Test func foreignOpenCodePluginBlocksBeforeAnyFileChanges() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(
            at: fixture.paths.openCodePluginURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("// mine\n".utf8).write(to: fixture.paths.openCodePluginURL)

        #expect(
            try HolyAgentStateBridgeInstaller.installationState(paths: fixture.paths)
                == .blocked(HolyAgentStateBridgeInstallerError.foreignOpenCodePlugin.localizedDescription)
        )
        do {
            _ = try HolyAgentStateBridgeInstaller.install(paths: fixture.paths)
            Issue.record("Expected a foreign plugin to block installation")
        } catch is HolyAgentStateBridgeInstallerError {
            // Expected.
        }

        #expect(!FileManager.default.fileExists(atPath: fixture.paths.helperURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.claudeSettingsURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.codexHooksURL.path))
        #expect(try String(contentsOf: fixture.paths.openCodePluginURL, encoding: .utf8) == "// mine\n")
    }

    @Test func priorHolyGenerationUpgradesAndCanBeRemoved() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let priorHelper = """
        #!/bin/sh
        # Generated by Holy Ghostty. Owner: com.holyghostty.agent-state.v1
        exit 0

        """
        let priorPlugin = """
        // Generated by Holy Ghostty. Owner: com.holyghostty.agent-state.v1
        // previous generated plugin

        """
        try fixture.write(priorHelper, to: fixture.paths.helperURL)
        try fixture.write(priorPlugin, to: fixture.paths.openCodePluginURL)

        #expect(try HolyAgentStateBridgeInstaller.installationState(paths: fixture.paths) == .notInstalled)
        #expect(try HolyAgentStateBridgeInstaller.install(paths: fixture.paths) == .installed)
        #expect(try String(contentsOf: fixture.paths.helperURL, encoding: .utf8) == HolyAgentStateBridge.helperScript)
        #expect(
            try String(contentsOf: fixture.paths.openCodePluginURL, encoding: .utf8)
                == HolyAgentStateBridge.openCodePlugin(helperURL: fixture.paths.helperURL)
        )

        try HolyAgentStateBridgeInstaller.remove(paths: fixture.paths)
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.helperURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.openCodePluginURL.path))

        try fixture.write(priorHelper, to: fixture.paths.helperURL)
        try fixture.write(priorPlugin, to: fixture.paths.openCodePluginURL)
        try HolyAgentStateBridgeInstaller.remove(paths: fixture.paths)
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.helperURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.openCodePluginURL.path))
    }

    @Test func modifiedCurrentAndFutureMarkersFailClosed() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let modifiedCurrentHelper = HolyAgentStateBridge.helperScript + "# user change\n"
        try fixture.write(modifiedCurrentHelper, to: fixture.paths.helperURL)

        #expect(
            try HolyAgentStateBridgeInstaller.installationState(paths: fixture.paths)
                == .blocked(HolyAgentStateBridgeInstallerError.foreignHelper.localizedDescription)
        )
        try FileManager.default.removeItem(at: fixture.paths.helperURL)
        let futurePlugin = """
        // Generated by Holy Ghostty. Owner: com.holyghostty.agent-state.v999
        // unknown future format

        """
        try fixture.write(futurePlugin, to: fixture.paths.openCodePluginURL)
        #expect(
            try HolyAgentStateBridgeInstaller.installationState(paths: fixture.paths)
                == .blocked(HolyAgentStateBridgeInstallerError.foreignOpenCodePlugin.localizedDescription)
        )
    }

    private final class Fixture {
        let root: URL
        let paths: HolyAgentStateBridgePaths

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("holy-agent-installer-tests-\(UUID().uuidString)", isDirectory: true)
            paths = .init(
                helperURL: root.appendingPathComponent("support/agent-state-hook.sh"),
                claudeSettingsURL: root.appendingPathComponent("home/.claude/settings.json"),
                codexHooksURL: root.appendingPathComponent("home/.codex/hooks.json"),
                codexConfigURL: root.appendingPathComponent("home/.codex/config.toml"),
                codexNotifyAdapterURL: root.appendingPathComponent("support/holy-codex-turn-complete.py"),
                openCodePluginURL: root.appendingPathComponent("home/.config/opencode/plugins/holy-agent-state.ts")
            )
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
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
            return hooks.values.flatMap { value -> [String] in
                guard let groups = value as? [[String: Any]] else { return [] }
                return groups.flatMap { group in
                    (group["hooks"] as? [[String: Any]] ?? []).compactMap {
                        $0["command"] as? String
                    }
                }
            }
        }
    }
}
