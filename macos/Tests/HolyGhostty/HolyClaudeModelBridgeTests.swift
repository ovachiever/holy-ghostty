import Foundation
import Testing
@testable import Ghostty

struct HolyClaudeModelBridgeTests {
    @Test func installsBridgeWithoutDiscardingOtherClaudeSettings() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let settingsURL = root.appendingPathComponent(".claude/settings.json")
        let helperURL = root.appendingPathComponent("Holy/claude-model-statusline.sh")
        try writeJSON(
            ["model": "opus", "permissions": ["defaultMode": "acceptEdits"]],
            to: settingsURL
        )

        let outcome = try HolyClaudeModelBridge.installIfSafe(
            settingsURL: settingsURL,
            helperURL: helperURL
        )

        #expect(outcome == .installed)
        let settings = try readJSON(at: settingsURL)
        #expect(settings["model"] as? String == "opus")
        #expect((settings["permissions"] as? [String: Any])?["defaultMode"] as? String == "acceptEdits")
        let statusLine = try #require(settings["statusLine"] as? [String: Any])
        #expect(statusLine["type"] as? String == "command")
        #expect((statusLine["command"] as? String)?.contains(helperURL.path) == true)
        #expect(statusLine["refreshInterval"] as? Int == 5)
        #expect(sessionEndCommands(in: settings) == ["'\(helperURL.path)'"])
        #expect(try String(contentsOf: helperURL, encoding: .utf8) == HolyClaudeModelBridge.helperScript)

        let permissions = try FileManager.default.attributesOfItem(atPath: helperURL.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o700)
        #expect(
            try HolyClaudeModelBridge.installIfSafe(
                settingsURL: settingsURL,
                helperURL: helperURL
            ) == .alreadyInstalled
        )
    }

    @Test func refusesToOverwriteAnExistingCustomStatusLine() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let settingsURL = root.appendingPathComponent(".claude/settings.json")
        let helperURL = root.appendingPathComponent("Holy/claude-model-statusline.sh")
        try writeJSON(
            [
                "statusLine": [
                    "type": "command",
                    "command": "tmux set-option @holy_model_label custom",
                ],
            ],
            to: settingsURL
        )

        let before = try Data(contentsOf: settingsURL)
        let outcome = try HolyClaudeModelBridge.installIfSafe(
            settingsURL: settingsURL,
            helperURL: helperURL
        )

        #expect(outcome == .skippedExistingStatusLine)
        #expect(try Data(contentsOf: settingsURL) == before)
        #expect(!FileManager.default.fileExists(atPath: helperURL.path))
    }

    @Test func removesOnlyOwnedBridgeAndPreservesOtherSettings() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let settingsURL = root.appendingPathComponent(".claude/settings.json")
        let helperURL = root.appendingPathComponent("Holy/claude-model-statusline.sh")
        try writeJSON(
            [
                "model": "opus",
                "theme": "dark",
                "hooks": [
                    "SessionEnd": [
                        [
                            "matcher": "clear",
                            "hooks": [
                                ["type": "command", "command": "touch /tmp/keep-existing-hook"],
                            ],
                        ],
                    ],
                ],
            ],
            to: settingsURL
        )
        _ = try HolyClaudeModelBridge.installIfSafe(
            settingsURL: settingsURL,
            helperURL: helperURL
        )

        #expect(
            try HolyClaudeModelBridge.installationState(
                settingsURL: settingsURL,
                helperURL: helperURL
            ) == .installed
        )
        #expect(
            try HolyClaudeModelBridge.removeIfOwned(
                settingsURL: settingsURL,
                helperURL: helperURL
            ) == .removed
        )

        let settings = try readJSON(at: settingsURL)
        #expect(settings["statusLine"] == nil)
        #expect(settings["model"] as? String == "opus")
        #expect(settings["theme"] as? String == "dark")
        #expect(sessionEndCommands(in: settings) == ["touch /tmp/keep-existing-hook"])
        #expect(!FileManager.default.fileExists(atPath: helperURL.path))
    }

    @Test func settingsSymlinkSurvivesAtomicUpdate() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let managedDirectory = root.appendingPathComponent("managed", isDirectory: true)
        let targetURL = managedDirectory.appendingPathComponent("settings.json")
        let settingsURL = root.appendingPathComponent(".claude/settings.json")
        let helperURL = root.appendingPathComponent("Holy/claude-model-statusline.sh")
        try writeJSON(["model": "opus"], to: targetURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: targetURL.path
        )
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            atPath: settingsURL.path,
            withDestinationPath: "../managed/settings.json"
        )

        _ = try HolyClaudeModelBridge.installIfSafe(
            settingsURL: settingsURL,
            helperURL: helperURL
        )

        #expect(
            try FileManager.default.destinationOfSymbolicLink(atPath: settingsURL.path)
                == "../managed/settings.json"
        )
        #expect((try readJSON(at: targetURL))["statusLine"] != nil)
        let permissions = try FileManager.default.attributesOfItem(
            atPath: targetURL.path
        )[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
    }

    @Test func failedTmuxCleanupDoesNotClaimBridgeRemoval() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let settingsURL = root.appendingPathComponent(".claude/settings.json")
        let helperURL = root.appendingPathComponent("Holy/claude-model-statusline.sh")
        try writeJSON(["model": "opus"], to: settingsURL)
        _ = try HolyClaudeModelBridge.installIfSafe(
            settingsURL: settingsURL,
            helperURL: helperURL
        )

        do {
            _ = try HolyClaudeModelBridge.deactivateIfOwned(
                settingsURL: settingsURL,
                helperURL: helperURL,
                setPublishingEnabled: { _, _ in true },
                clearOwnedLabels: { _ in false }
            )
            Issue.record("Expected failed tmux cleanup to block bridge removal")
        } catch let error as HolyClaudeModelBridgeError {
            #expect(error == .tmuxLabelCleanupFailed)
        }

        #expect(
            try HolyClaudeModelBridge.installationState(
                settingsURL: settingsURL,
                helperURL: helperURL
            ) == .installed
        )
        #expect(FileManager.default.fileExists(atPath: helperURL.path))
    }

    @Test func generatedHelperPrintsCurrentClaudeModelAndEffort() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let settingsURL = root.appendingPathComponent(".claude/settings.json")
        let helperURL = root.appendingPathComponent("Holy/claude-model-statusline.sh")
        _ = try HolyClaudeModelBridge.installIfSafe(
            settingsURL: settingsURL,
            helperURL: helperURL
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [helperURL.path]
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "TMUX")
        environment.removeValue(forKey: "TMUX_PANE")
        process.environment = environment
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()

        try process.run()
        input.fileHandleForWriting.write(
            Data(#"{"model":{"id":"claude-opus-4-8","display_name":"Opus 4.8"},"effort":{"level":"max"}}"#.utf8)
        )
        try input.fileHandleForWriting.close()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        let rendered = String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )
        #expect(rendered == "Model · Opus 4.8 · max\n")
    }

    @Test func generatedHelperWorksWithoutJQ() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let settingsURL = root.appendingPathComponent(".claude/settings.json")
        let helperURL = root.appendingPathComponent("Holy/claude-model-statusline.sh")
        let binURL = root.appendingPathComponent("bin", isDirectory: true)
        _ = try HolyClaudeModelBridge.installIfSafe(
            settingsURL: settingsURL,
            helperURL: helperURL
        )
        try FileManager.default.createDirectory(at: binURL, withIntermediateDirectories: true)
        for tool in ["cat": "/bin/cat", "tr": "/usr/bin/tr", "cut": "/usr/bin/cut"] {
            try FileManager.default.createSymbolicLink(
                atPath: binURL.appendingPathComponent(tool.key).path,
                withDestinationPath: tool.value
            )
        }

        let rendered = try runHelper(
            helperURL,
            json: #"{"model":{"id":"claude-opus-4-8"},"effort":{"level":"high"}}"#,
            environment: ["PATH": binURL.path]
        )

        #expect(rendered == "Model · claude-opus-4-8 · high\n")
    }

    @Test func generatedHelperPublishesPaneScopedTmuxLabel() throws {
        guard let tmuxPath = loginShellOutput("command -v tmux"), !tmuxPath.isEmpty else {
            return
        }

        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let settingsURL = root.appendingPathComponent(".claude/settings.json")
        let helperURL = root.appendingPathComponent("Holy/claude-model-statusline.sh")
        let lateHelperURL = root.appendingPathComponent("late-claude-model-statusline.sh")
        _ = try HolyClaudeModelBridge.installIfSafe(
            settingsURL: settingsURL,
            helperURL: helperURL
        )
        try Data(HolyClaudeModelBridge.helperScript.utf8).write(
            to: lateHelperURL,
            options: .atomic
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: lateHelperURL.path
        )

        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let socketName = "holy-claude-model-\(suffix)"
        let sessionName = "claude-\(suffix)"
        #expect(runLoginShell("tmux -L \(socketName) new-session -d -s \(sessionName)") == 0)
        defer {
            _ = runLoginShell("tmux -L \(socketName) kill-server >/dev/null 2>&1 || true")
        }
        let paneID = try #require(
            loginShellOutput("tmux -L \(socketName) display-message -p -t \(sessionName) '#{pane_id}'")
        )
        let socketPath = try #require(
            loginShellOutput("tmux -L \(socketName) display-message -p -t \(sessionName) '#{socket_path}'")
        )
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = URL(fileURLWithPath: tmuxPath).deletingLastPathComponent().path
            + ":/usr/bin:/bin"
        environment["TMUX"] = "\(socketPath),0,0"
        environment["TMUX_PANE"] = paneID
        #expect(
            HolyClaudeModelBridge.setTmuxPublishingEnabled(
                true,
                socketName: socketName
            )
        )

        _ = try runHelper(
            helperURL,
            json: #"{"model":{"display_name":"Opus 4.8"},"effort":{"level":"max"}}"#,
            environment: environment
        )

        #expect(
            loginShellOutput(
                "tmux -L \(socketName) show-options -pqv -t \(sessionName) @holy_model_label"
            ) == "Opus 4.8 · max"
        )

        _ = try runHelper(
            helperURL,
            json: #"{"hook_event_name":"SessionEnd","reason":"prompt_input_exit"}"#,
            environment: environment
        )
        #expect(
            loginShellOutput(
                "tmux -L \(socketName) display-message -p -t \(sessionName) '#{@holy_model_label}|#{@holy_model_source}'"
            ) == "|"
        )
        #expect(
            loginShellOutput(
                "tmux -L \(socketName) show-options -gqv @holy_claude_model_enabled"
            ) == "on"
        )

        // Republish so Disable still exercises owned-label cleanup in the
        // same integration test after the normal Claude-exit path.
        _ = try runHelper(
            helperURL,
            json: #"{"model":{"display_name":"Opus 4.8"},"effort":{"level":"max"}}"#,
            environment: environment
        )
        #expect(
            loginShellOutput(
                "tmux -L \(socketName) show-options -pqv -t \(sessionName) @holy_model_label"
            ) == "Opus 4.8 · max"
        )
        #expect(
            loginShellOutput(
                "tmux -L \(socketName) show-options -pqv -t \(sessionName) @holy_model_source"
            ) == "claude"
        )

        var launchSpec = HolySessionLaunchSpec.interactiveTmuxShell()
        launchSpec.tmux = .init(
            socketName: socketName,
            sessionName: sessionName,
            createIfMissing: false
        )
        let appYield = try #require(
            HolyTmuxModelLabelUpdateCommand.command(for: launchSpec, label: nil)
        )
        #expect(appYield.run())
        #expect(
            loginShellOutput(
                "tmux -L \(socketName) show-options -pqv -t \(sessionName) @holy_model_label"
            ) == "Opus 4.8 · max"
        )

        #expect(
            try HolyClaudeModelBridge.deactivateIfOwned(
                settingsURL: settingsURL,
                helperURL: helperURL,
                socketName: socketName
            ) == .removed
        )
        #expect(
            loginShellOutput(
                "tmux -L \(socketName) display-message -p -t \(sessionName) '#{@holy_model_label}|#{@holy_model_source}'"
            ) == "|"
        )
        #expect(
            loginShellOutput(
                "tmux -L \(socketName) show-options -gqv @holy_claude_model_enabled"
            ) == "off"
        )
        #expect((try readJSON(at: settingsURL))["statusLine"] == nil)
        #expect(!FileManager.default.fileExists(atPath: helperURL.path))

        // A helper invocation that reaches tmux after Disable's cleanup must
        // observe the server-side gate and remain unable to restore its label.
        _ = try runHelper(
            lateHelperURL,
            json: #"{"model":{"display_name":"Opus 4.8"},"effort":{"level":"max"}}"#,
            environment: environment
        )
        #expect(
            loginShellOutput(
                "tmux -L \(socketName) display-message -p -t \(sessionName) '#{@holy_model_label}|#{@holy_model_source}'"
            ) == "|"
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-claude-model-tests-\(UUID().uuidString)", isDirectory: true)
    }

    private func writeJSON(_ object: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])
            .write(to: url, options: .atomic)
    }

    private func readJSON(at url: URL) throws -> [String: Any] {
        try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }

    private func sessionEndCommands(in settings: [String: Any]) -> [String] {
        guard let hooks = settings["hooks"] as? [String: Any],
              let groups = hooks["SessionEnd"] as? [[String: Any]] else {
            return []
        }
        return groups.flatMap { group in
            (group["hooks"] as? [[String: Any]] ?? []).compactMap {
                $0["command"] as? String
            }
        }
    }

    private func runHelper(
        _ helperURL: URL,
        json: String,
        environment: [String: String]
    ) throws -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [helperURL.path]
        process.environment = environment
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        input.fileHandleForWriting.write(Data(json.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        return String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )
    }

    private func runLoginShell(_ script: String) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", script]
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

    private func loginShellOutput(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", script]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(
                data: output.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}
