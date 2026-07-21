import Foundation
import Testing
@testable import Ghostty

private let holyAgentStateRealTmuxURL: URL? = {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-lc", "command -v tmux"]
    process.standardOutput = output
    process.standardError = Pipe()
    do {
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let path = String(
                data: output.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
              )?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty,
              FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    } catch {
        return nil
    }
}()

struct HolyAgentStateBridgeTests {
    @Test func claudeMergePreservesUnrelatedSettingsHooksAndHandlers() throws {
        let helperURL = URL(fileURLWithPath: "/tmp/Holy Ghostty/agent-state-hook.sh")
        let settings: [String: Any] = [
            "model": "opus",
            "permissions": ["defaultMode": "acceptEdits"],
            "hooks": [
                "Stop": [
                    [
                        "matcher": "custom",
                        "hooks": [
                            ["type": "command", "command": "touch /tmp/keep-me"],
                            ["type": "prompt", "prompt": "keep this too"],
                        ],
                    ],
                ],
                "PreCompact": [
                    [
                        "hooks": [
                            ["type": "command", "command": "backup-context"],
                        ],
                    ],
                ],
            ],
        ]

        let merged = try HolyAgentStateBridge.mergingClaudeSettings(
            settings,
            helperURL: helperURL
        )

        #expect(merged["model"] as? String == "opus")
        #expect((merged["permissions"] as? [String: Any])?["defaultMode"] as? String == "acceptEdits")
        let commands = hookCommands(in: merged)
        #expect(commands.contains("touch /tmp/keep-me"))
        #expect(commands.contains("backup-context"))
        #expect(commands.contains(where: { $0.contains(" claude working user-prompt") }))
        #expect(commands.contains(where: { $0.contains(" claude needs-user permission") }))
        #expect(commands.contains(where: { $0.contains(" claude finished idle-finished") }))
        #expect(commands.contains(where: { $0.contains(" claude ended session-ended") }))
        #expect(commands.contains(where: { $0.contains(" claude finished turn-finished") }))
        #expect(promptHandlers(in: merged).contains("keep this too"))
    }

    @Test func mergeIsIdempotentAndReplacesOnlyExactOwnedCommands() throws {
        let helperURL = URL(fileURLWithPath: "/tmp/Holy/agent-state-hook.sh")
        let customNearMatch = "echo '\(helperURL.path)' claude working user-prompt"
        let initial: [String: Any] = [
            "hooks": [
                "Stop": [
                    ["hooks": [["type": "command", "command": customNearMatch]]],
                ],
            ],
        ]

        let once = try HolyAgentStateBridge.mergingClaudeSettings(initial, helperURL: helperURL)
        let twice = try HolyAgentStateBridge.mergingClaudeSettings(once, helperURL: helperURL)

        #expect(try canonicalJSON(once) == canonicalJSON(twice))
        #expect(hookCommands(in: twice).contains(customNearMatch))
        let owned = hookCommands(in: twice).filter {
            HolyAgentStateBridge.isOwnedHookCommand(
                $0,
                helperURL: helperURL,
                source: HolyAgentStateSource.claude
            )
        }
        #expect(owned.count == 8)
    }

    @Test func generatedMappingsUseOnlyAuthoritativeHarnessEvents() throws {
        let helperURL = URL(fileURLWithPath: "/tmp/Holy/agent-state-hook.sh")
        let claude = try HolyAgentStateBridge.mergingClaudeSettings([:], helperURL: helperURL)
        let claudeCommands = hookCommands(in: claude)
        let claudeHooks = try #require(claude["hooks"] as? [String: Any])
        let codex = try HolyAgentStateBridge.mergingCodexHooks([:], helperURL: helperURL)
        let codexCommands = hookCommands(in: codex)

        #expect(claudeHooks["PreToolUse"] == nil)
        #expect(claudeHooks["PermissionRequest"] == nil)
        #expect(claudeHooks["Stop"] != nil)
        #expect(claudeCommands.contains(where: { $0.contains(" claude needs-user permission") }))
        #expect(claudeCommands.contains(where: { $0.contains(" claude finished idle-finished") }))
        #expect(claudeCommands.contains(where: { $0.contains(" claude failed turn-failed") }))
        #expect(claudeCommands.contains(where: { $0.contains(" claude finished turn-finished") }))
        #expect(!claudeCommands.contains(where: { $0.contains(" claude needs-user question") }))
        #expect((codex["hooks"] as? [String: Any])?["Stop"] == nil)
        #expect((codex["hooks"] as? [String: Any])?["PreToolUse"] == nil)
        #expect((codex["hooks"] as? [String: Any])?["PermissionRequest"] == nil)
        #expect(!codexCommands.contains(where: { $0.contains(" codex finished ") }))
        #expect(!codexCommands.contains(where: { $0.contains(" codex needs-user ") }))
        #expect(codexCommands.contains(where: { $0.contains(" codex working tool-complete") }))
    }

    // Revised contract (2026-07-21): Stop publishes finished. A parallel
    // sibling hook can block the stop, but that transient false finished
    // self-corrects on the next working envelope; the old idle_prompt-only
    // design left focused sessions permanently stuck on working because the
    // idle notification never fires while the terminal is watched.
    @Test func claudeStopPublishesFinishedAndPreservesForeignStopHooks() throws {
        let helperURL = URL(fileURLWithPath: "/tmp/Holy/agent-state-hook.sh")
        let customStop = "keep-my-blocking-stop-hook"
        let merged = try HolyAgentStateBridge.mergingClaudeSettings(
            [
                "hooks": [
                    "Stop": [["hooks": [["type": "command", "command": customStop]]]],
                ],
            ],
            helperURL: helperURL
        )
        let hooks = try #require(merged["hooks"] as? [String: Any])
        let stopGroups = try #require(hooks["Stop"] as? [[String: Any]])
        let notificationGroups = try #require(hooks["Notification"] as? [[String: Any]])

        let stopCommands = hookCommands(inGroups: stopGroups)
        #expect(stopCommands.contains(customStop))
        #expect(stopCommands.contains(where: { $0.contains(" claude finished turn-finished") }))
        // idle_prompt stays as the non-blocking confirmation path.
        let idleFinishGroups = notificationGroups.filter { $0["matcher"] as? String == "idle_prompt" }
        #expect(idleFinishGroups.count == 1)
        #expect(hookCommands(inGroups: idleFinishGroups).first?.contains(" claude finished idle-finished") == true)
    }

    // Watcher eye producer (mn-f4d77b): a ScheduleWakeup-matched PostToolUse
    // hook maintains @holy_watcher_v1 inline, reading only delaySeconds and
    // stop from the tool input. Ownership keys on the embedded marker so the
    // merge stays idempotent and uninstall strips it.
    @Test func claudeWatcherHookArmsTheWatcherRegisterInline() throws {
        let helperURL = URL(fileURLWithPath: "/tmp/Holy/agent-state-hook.sh")
        let merged = try HolyAgentStateBridge.mergingClaudeSettings([:], helperURL: helperURL)
        let hooks = try #require(merged["hooks"] as? [String: Any])
        let postToolGroups = try #require(hooks["PostToolUse"] as? [[String: Any]])

        let watcherGroups = postToolGroups.filter { $0["matcher"] as? String == "ScheduleWakeup" }
        #expect(watcherGroups.count == 1)
        let command = try #require(hookCommands(inGroups: watcherGroups).first)
        #expect(command.hasPrefix("/usr/bin/python3 -c "))
        #expect(command.contains("@holy_watcher_v1"))
        #expect(command.contains("delaySeconds"))
        #expect(HolyAgentStateBridge.isOwnedWatcherHookCommand(command))
        #expect(!HolyAgentStateBridge.isOwnedHookCommand(
            command,
            helperURL: helperURL,
            source: HolyAgentStateSource.claude
        ))

        // The inline program never reads the loop prompt.
        #expect(!command.contains("\"prompt\""))

        // Re-merging replaces rather than duplicates the watcher group.
        let twice = try HolyAgentStateBridge.mergingClaudeSettings(merged, helperURL: helperURL)
        let twiceGroups = try #require((twice["hooks"] as? [String: Any])?["PostToolUse"] as? [[String: Any]])
        #expect(twiceGroups.filter { $0["matcher"] as? String == "ScheduleWakeup" }.count == 1)
    }

    @Test func codexMergeLeavesTrustAndExistingHookIndexesAlone() throws {
        let helperURL = URL(fileURLWithPath: "/tmp/Holy/agent-state-hook.sh")
        let existingSessionStart: [[String: Any]] = [
            [
                "matcher": "startup|resume",
                "hooks": [
                    [
                        "type": "command",
                        "command": "existing-session-start",
                        "timeout": 10,
                    ],
                ],
            ],
        ]
        let root: [String: Any] = [
            "trust": ["must": "remain-external"],
            "hooks": ["SessionStart": existingSessionStart],
        ]

        let merged = try HolyAgentStateBridge.mergingCodexHooks(root, helperURL: helperURL)
        let hooks = try #require(merged["hooks"] as? [String: Any])
        let groups = try #require(hooks["SessionStart"] as? [[String: Any]])

        #expect((merged["trust"] as? [String: String])?["must"] == "remain-external")
        #expect(groups.count == 2)
        #expect(hookCommands(inGroups: [groups[0]]) == ["existing-session-start"])
        #expect(hookCommands(inGroups: [groups[1]]).first?.contains(" codex idle session-start") == true)
        #expect(merged["hookTrust"] == nil)
        #expect(!hookCommands(in: merged).contains(where: { $0.contains(" codex needs-user ") }))
    }

    @Test func codexMergeRemovesPriorOwnedStopButPreservesForeignStop() throws {
        let helperURL = URL(fileURLWithPath: "/tmp/Holy/agent-state-hook.sh")
        let previouslyInstalled = try HolyAgentStateBridge.mergingCodexHooks([:], helperURL: helperURL)
        var root = previouslyInstalled
        var hooks = try #require(root["hooks"] as? [String: Any])
        hooks["Stop"] = [
            [
                "hooks": [
                    [
                        "type": "command",
                        "command": "'\(helperURL.path)' codex finished turn-finished",
                    ],
                    ["type": "command", "command": "keep-foreign-stop"],
                ],
            ],
        ]
        root["hooks"] = hooks

        let merged = try HolyAgentStateBridge.mergingCodexHooks(root, helperURL: helperURL)
        let stop = ((merged["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]) ?? []
        #expect(hookCommands(inGroups: stop) == ["keep-foreign-stop"])
    }

    @Test func codexNotifyConfigurationPreservesBytesAndFailsClosedOnForeignValues() throws {
        let adapterURL = URL(fileURLWithPath: "/Users/me/Library/Application Support/Holy Ghostty/holy-codex-turn-complete.py")
        let original = #"""
        model = "gpt-5.4"
        developer_instructions = """
        The word notify = ["not a setting"] is harmless here.
        """

        [tui]
        notifications = ["agent-turn-complete"]

        [example]
        notify = ["a table-local value"]
        """# + "\n"

        let installed = try HolyAgentStateBridge.mergingCodexConfiguration(
            original,
            adapterURL: adapterURL
        )
        #expect(installed.hasSuffix(original))
        #expect(installed.contains(HolyAgentStateBridge.codexNotifyConfigurationMarker))
        #expect(try HolyAgentStateBridge.mergingCodexConfiguration(installed, adapterURL: adapterURL) == installed)
        #expect(try HolyAgentStateBridge.removingCodexConfiguration(installed, adapterURL: adapterURL) == original)

        let ownedOnly = try HolyAgentStateBridge.mergingCodexConfiguration("", adapterURL: adapterURL)
        let duplicated = ownedOnly + "notify = [\"second-notifier\"]\n"
        #expect(throws: HolyCodexNotifyConfigurationError.foreignNotify) {
            _ = try HolyAgentStateBridge.mergingCodexConfiguration(
                duplicated,
                adapterURL: adapterURL
            )
        }

        #expect(throws: HolyCodexNotifyConfigurationError.foreignNotify) {
            _ = try HolyAgentStateBridge.mergingCodexConfiguration(
                "notify = [\"terminal-notifier\"]\n",
                adapterURL: adapterURL
            )
        }
        #expect(throws: HolyCodexNotifyConfigurationError.foreignNotify) {
            _ = try HolyAgentStateBridge.mergingCodexConfiguration(
                "\"notify\" = [\"terminal-notifier\"]\n",
                adapterURL: adapterURL
            )
        }
        #expect(throws: HolyCodexNotifyConfigurationError.ambiguousNotify) {
            _ = try HolyAgentStateBridge.mergingCodexConfiguration(
                "notify = [\n  \"terminal-notifier\",\n]\n",
                adapterURL: adapterURL
            )
        }
        for namespace in ["notify.command = \"mine\"\n", "[notify.settings]\ncommand = \"mine\"\n"] {
            #expect(throws: HolyCodexNotifyConfigurationError.foreignNotify) {
                _ = try HolyAgentStateBridge.mergingCodexConfiguration(
                    namespace,
                    adapterURL: adapterURL
                )
            }
        }
    }

    @Test func codexNotifyAdapterForwardsOnlyCommittedStructuredIdentity() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-codex-notify-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let helperURL = root.appendingPathComponent("capture-helper.sh")
        let adapterURL = root.appendingPathComponent(HolyAgentStateBridge.codexNotifyAdapterFileName)
        let captureURL = root.appendingPathComponent("captured")
        let helper = #"""
        #!/bin/sh
        printf '%s\n' "$@" > "$HOLY_CAPTURE"
        """# + "\n"
        try Data(helper.utf8).write(to: helperURL)
        try Data(HolyAgentStateBridge.codexNotifyAdapter(helperURL: helperURL).utf8).write(to: adapterURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helperURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: adapterURL.path)

        let payload = try JSONSerialization.data(withJSONObject: [
            "type": "agent-turn-complete",
            "thread-id": "019f6280-5fc7-7093-a705-8d6f4916f911",
            "turn-id": "turn-42",
            "input-messages": ["TOP SECRET PROMPT"],
            "last-assistant-message": "TOP SECRET RESPONSE",
        ])
        let process = Process()
        process.executableURL = adapterURL
        process.arguments = [try #require(String(data: payload, encoding: .utf8))]
        var environment = ProcessInfo.processInfo.environment
        environment["HOLY_CAPTURE"] = captureURL.path
        process.environment = environment
        process.standardInput = Pipe()
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        let captured = try String(contentsOf: captureURL, encoding: .utf8)
        #expect(captured == "codex\nfinished\nturn-finished\n019f6280-5fc7-7093-a705-8d6f4916f911:turn-42\n")
        #expect(!captured.contains("TOP SECRET"))
        let adapter = try String(contentsOf: adapterURL, encoding: .utf8)
        #expect(HolyAgentStateBridge.isOwnedCodexNotifyAdapter(adapter, helperURL: helperURL))
        #expect(!HolyAgentStateBridge.isOwnedCodexNotifyAdapter(adapter + "# modified\n", helperURL: helperURL))
    }

    // Codex's documented agent-turn-complete payload carries turn-id (plus
    // message text) but NO thread-id — the adapter must accept the real
    // shape, or every Codex completion dies at validation (review finding #0).
    @Test func codexNotifyAdapterAcceptsRealPayloadWithoutThreadId() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-codex-notify-real-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let helperURL = root.appendingPathComponent("capture-helper.sh")
        let adapterURL = root.appendingPathComponent(HolyAgentStateBridge.codexNotifyAdapterFileName)
        let captureURL = root.appendingPathComponent("captured")
        let helper = #"""
        #!/bin/sh
        printf '%s\n' "$@" > "$HOLY_CAPTURE"
        """# + "\n"
        try Data(helper.utf8).write(to: helperURL)
        try Data(HolyAgentStateBridge.codexNotifyAdapter(helperURL: helperURL).utf8).write(to: adapterURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helperURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: adapterURL.path)

        let payload = try JSONSerialization.data(withJSONObject: [
            "type": "agent-turn-complete",
            "turn-id": "turn-42",
            "input-messages": ["TOP SECRET PROMPT"],
            "last-assistant-message": "TOP SECRET RESPONSE",
        ])
        let process = Process()
        process.executableURL = adapterURL
        process.arguments = [try #require(String(data: payload, encoding: .utf8))]
        var environment = ProcessInfo.processInfo.environment
        environment["HOLY_CAPTURE"] = captureURL.path
        process.environment = environment
        process.standardInput = Pipe()
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        let captured = try String(contentsOf: captureURL, encoding: .utf8)
        #expect(captured == "codex\nfinished\nturn-finished\nturn-42\n")
        #expect(!captured.contains("TOP SECRET"))
    }

    @Test func malformedHookShapesFailClosedInsteadOfDiscardingConfiguration() {
        let helperURL = URL(fileURLWithPath: "/tmp/Holy/agent-state-hook.sh")
        do {
            _ = try HolyAgentStateBridge.mergingClaudeSettings(
                ["hooks": ["Stop": "not-an-array"]],
                helperURL: helperURL
            )
            Issue.record("Expected malformed hooks to be rejected")
        } catch let error as HolyAgentStateBridgeError {
            #expect(error == .malformedHookGroups("Stop"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func generatedOpenCodePluginUsesStructuredEventsAndExactOwnership() {
        let helperURL = URL(fileURLWithPath: "/tmp/Holy \"Ghostty\"/agent-state-hook.sh")
        let plugin = HolyAgentStateBridge.openCodePlugin(helperURL: helperURL)

        #expect(plugin.hasPrefix(HolyAgentStateBridge.openCodePluginOwnershipMarker))
        #expect(plugin.contains(#"const helperPath = "/tmp/Holy \"Ghostty\"/agent-state-hook.sh""#))
        #expect(plugin.contains(#"case "session.status""#))
        #expect(plugin.contains(#"case "question.asked""#))
        #expect(plugin.contains(#"case "permission.asked""#))
        #expect(!plugin.contains(#""permission.ask":"#))
        #expect(plugin.contains("pendingTerminalError"))
        #expect(plugin.contains("sessionID !== activeSessionID"))
        #expect(!plugin.localizedCaseInsensitiveContains("screen scraping"))
        #expect(HolyAgentStateBridge.isOwnedOpenCodePlugin(plugin, helperURL: helperURL))
        #expect(!HolyAgentStateBridge.isOwnedOpenCodePlugin(plugin + "// custom\n", helperURL: helperURL))
        #expect(
            HolyAgentStateBridge.isOwnedOpenCodePlugin(
                "// Generated by Holy Ghostty. Owner: com.holyghostty.agent-state.v1\n// old generated body\n",
                helperURL: helperURL
            )
        )
        #expect(
            !HolyAgentStateBridge.isOwnedOpenCodePlugin(
                "// Generated by Holy Ghostty. Owner: com.holyghostty.agent-state.v999\n// future body\n",
                helperURL: helperURL
            )
        )
        #expect(HolyAgentStateBridge.isOwnedHelperScript(HolyAgentStateBridge.helperScript))
        #expect(!HolyAgentStateBridge.isOwnedHelperScript(HolyAgentStateBridge.helperScript + "# custom\n"))
    }

    @Test func adoptionStampUsesArgumentArrayAndRejectsUnsafeTargets() {
        #expect(
            HolyAgentStateBridge.tmuxOwnershipStampArguments(forTarget: "%42") == [
                "set-option",
                "-pq",
                "-t",
                "%42",
                "@holy_agent_state_owner_v1",
                "holy",
            ]
        )
        #expect(HolyAgentStateBridge.tmuxOwnershipStampArguments(forTarget: "session:1.0") != nil)
        #expect(HolyAgentStateBridge.tmuxOwnershipStampArguments(forTarget: "%") == nil)
        #expect(HolyAgentStateBridge.tmuxOwnershipStampArguments(forTarget: "%1;run-shell") == nil)

        // A session-name target must stamp SESSION scope: `-pq` against a
        // session resolves to only the active pane, leaving adopted agents in
        // other panes unmarked (review finding #1). Format expansion
        // `#{@option}` inherits pane→session, so session scope reaches every
        // pane's helper read.
        #expect(
            HolyAgentStateBridge.tmuxOwnershipStampArguments(forTarget: "holy-shell-30-shell-ABC") == [
                "set-option",
                "-q",
                "-t",
                "holy-shell-30-shell-ABC",
                "@holy_agent_state_owner_v1",
                "holy",
            ]
        )
    }

    @Test func remoteManifestIsCanonicalAndCarriesAllCurrentAdapters() throws {
        let helperURL = URL(fileURLWithPath: "/home/remote/.local/share/holy-ghostty/agent-state-hook.sh")
        let first = try HolyAgentStateBridge.remoteInstallationManifest(helperURL: helperURL)
        let second = try HolyAgentStateBridge.remoteInstallationManifest(helperURL: helperURL)
        #expect(first == second)
        #expect(String(bytes: first, encoding: .utf8)?.hasPrefix("{\"exactFiles\":") == true)

        let root = try #require(try JSONSerialization.jsonObject(with: first) as? [String: Any])
        #expect(root["protocolVersion"] as? Int == 1)
        #expect(root["generationVersion"] as? Int == HolyAgentStateBridge.generationVersion)
        #expect(
            root["lifecycleValues"] as? [String]
                == HolyAgentLifecycleState.allCases.map(\.rawValue)
        )
        let helper = try #require(root["helper"] as? [String: Any])
        #expect(helper["relativePath"] as? String == ".local/share/holy-ghostty/agent-state-hook.sh")
        #expect(helper["mode"] as? Int == 0o700)
        #expect(helper["content"] as? String == HolyAgentStateBridge.helperScript)
        #expect(helper["ownershipMarkerPrefix"] as? String == HolyAgentStateBridge.helperOwnershipMarkerPrefix)

        let documents = try #require(root["hookDocuments"] as? [[String: Any]])
        #expect(documents.compactMap { $0["id"] as? String } == ["claude", "codex"])
        #expect(documents.compactMap { $0["manualTrust"] as? Bool } == [false, true])
        #expect(documents.allSatisfy { $0["desiredRoot"] is [String: Any] })
        let guarded = try #require(root["guardedTextDocuments"] as? [[String: Any]])
        #expect(guarded.compactMap { $0["id"] as? String } == ["codex-notify-config"])
        #expect(guarded.first?["guardedTopLevelKey"] as? String == "notify")
        let files = try #require(root["exactFiles"] as? [[String: Any]])
        #expect(files.compactMap { $0["id"] as? String } == ["opencode", "codex-notify"])
        #expect(files.first?["mode"] as? Int == 0o600)
        #expect(
            files.first?["ownershipMarkerPrefix"] as? String
                == HolyAgentStateBridge.openCodePluginOwnershipMarkerPrefix
        )
        #expect(files[1]["mode"] as? Int == 0o700)
        #expect(files[1]["ownershipMarkerLine"] as? Int == 1)
        #expect(files[0]["acceptPriorGeneration"] as? Bool == true)
        #expect(files[1]["acceptPriorGeneration"] as? Bool == false)
        #expect(
            files[1]["content"] as? String
                == HolyAgentStateBridge.codexNotifyAdapter(helperURL: helperURL)
        )
    }

    @Test func generatedHelperEmitsParseableMetadataWithoutReadingHookStdin() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-agent-state-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let helperURL = root.appendingPathComponent("agent-state-hook.sh")
        let ttyURL = root.appendingPathComponent("tty-capture")
        let binURL = root.appendingPathComponent("bin", isDirectory: true)
        try Data(HolyAgentStateBridge.helperScript.utf8).write(to: helperURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: helperURL.path
        )
        try writeFakeTmux(in: binURL, holyRuntime: "codex")
        #expect(FileManager.default.createFile(atPath: ttyURL.path, contents: Data()))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            helperURL.path,
            "future-harness.v2",
            "needs-user",
            "permission",
            "session|with prompt text\n",
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(binURL.path):/usr/bin:/bin"
        environment["TMUX"] = "fake,1,0"
        environment["TMUX_PANE"] = "%1"
        environment["HOLY_AGENT_STATE_TTY"] = ttyURL.path
        process.environment = environment
        let stdin = Pipe()
        process.standardInput = stdin
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        stdin.fileHandleForWriting.write(Data(#"{"prompt":"TOP SECRET transcript text"}"#.utf8))
        try stdin.fileHandleForWriting.close()
        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        let sequence = try String(contentsOf: ttyURL, encoding: .utf8)
        let prefix = "\u{1B}Ptmux;\u{1B}\u{1B}]777;notify;\(HolyAgentStateTransport.notificationTitle);"
        let suffix = "\u{7}\u{1B}\\"
        #expect(sequence.hasPrefix(prefix))
        #expect(sequence.hasSuffix(suffix))
        let wire = String(sequence.dropFirst(prefix.count).dropLast(suffix.count))
        let envelope = try HolyAgentStateEnvelope(wireValue: wire)
        #expect(envelope.source == "future-harness.v2")
        #expect(envelope.lifecycle == .needsUser)
        #expect(envelope.sessionID == "sessionwithprompttext")
        #expect(envelope.reasonCode == "permission")
        #expect(!wire.contains("TOP SECRET"))
    }

    @Test func generatedHelperIsAQuietNoOpOutsideAHolyOwnedPane() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-agent-state-ownership-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let helperURL = root.appendingPathComponent("agent-state-hook.sh")
        let ttyURL = root.appendingPathComponent("tty-capture")
        let binURL = root.appendingPathComponent("bin", isDirectory: true)
        try Data(HolyAgentStateBridge.helperScript.utf8).write(to: helperURL, options: .atomic)
        try writeFakeTmux(in: binURL, holyRuntime: "")
        #expect(FileManager.default.createFile(atPath: ttyURL.path, contents: Data()))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [helperURL.path, "codex", "working", "user-prompt"]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(binURL.path):/usr/bin:/bin"
        environment["TMUX"] = "fake,1,0"
        environment["TMUX_PANE"] = "%1"
        environment["HOLY_AGENT_STATE_TTY"] = ttyURL.path
        process.environment = environment
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        #expect(try Data(contentsOf: ttyURL).isEmpty)
    }

    @Test func adoptedPaneMarkerPublishesAndLastFinishSurvivesLaterLifecycle() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-agent-state-finish-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let helperURL = root.appendingPathComponent("agent-state-hook.sh")
        let ttyURL = root.appendingPathComponent("tty-capture")
        let binURL = root.appendingPathComponent("bin", isDirectory: true)
        let stateURL = root.appendingPathComponent("tmux-state", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stateURL, withIntermediateDirectories: true)
        try Data(HolyAgentStateBridge.helperScript.utf8).write(to: helperURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helperURL.path)
        try writeFakeTmux(in: binURL, holyRuntime: "", holyOwner: "holy")
        #expect(FileManager.default.createFile(atPath: ttyURL.path, contents: Data()))

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(binURL.path):/usr/bin:/bin"
        environment["TMUX"] = "fake,1,0"
        environment["TMUX_PANE"] = "%1"
        environment["HOLY_AGENT_STATE_TTY"] = ttyURL.path
        environment["HOLY_FAKE_TMUX_STATE_DIR"] = stateURL.path

        #expect(try runHelper(helperURL, lifecycle: "finished", reason: "idle-finished", environment: environment) == 0)
        let lastFinishURL = stateURL.appendingPathComponent("holy_agent_last_finished_v1")
        let firstFinish = try String(contentsOf: lastFinishURL, encoding: .utf8)
        #expect(try HolyAgentStateEnvelope(wireValue: firstFinish).lifecycle == .finished)
        let firstCapture = try Data(contentsOf: ttyURL)

        // A repeated idle notification is the same still-current fact, not a
        // second reply. It must not mint another token or another OSC alert.
        #expect(try runHelper(helperURL, lifecycle: "finished", reason: "idle-finished", environment: environment) == 0)
        #expect(try String(contentsOf: lastFinishURL, encoding: .utf8) == firstFinish)
        #expect(try Data(contentsOf: ttyURL) == firstCapture)

        #expect(try runHelper(helperURL, lifecycle: "working", reason: "user-prompt", environment: environment) == 0)
        #expect(try String(contentsOf: lastFinishURL, encoding: .utf8) == firstFinish)
        #expect(try runHelper(helperURL, lifecycle: "ended", reason: "session-ended", environment: environment) == 0)
        #expect(try String(contentsOf: lastFinishURL, encoding: .utf8) == firstFinish)

        let latestURL = stateURL.appendingPathComponent("holy_agent_state_v1")
        let latest = try HolyAgentStateEnvelope(
            wireValue: String(contentsOf: latestURL, encoding: .utf8)
        )
        #expect(latest.lifecycle == .ended)
    }

    @Test func generatedHelperRequiresDurableStateBeforeReportingOrEmittingSuccess() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-agent-state-durability-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let helperURL = root.appendingPathComponent("agent-state-hook.sh")
        let ttyURL = root.appendingPathComponent("tty-capture")
        let binURL = root.appendingPathComponent("bin", isDirectory: true)
        let stateURL = root.appendingPathComponent("tmux-state", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stateURL, withIntermediateDirectories: true)
        try Data(HolyAgentStateBridge.helperScript.utf8).write(to: helperURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helperURL.path)
        try writeFakeTmux(in: binURL, holyRuntime: "codex")
        #expect(FileManager.default.createFile(atPath: ttyURL.path, contents: Data()))

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(binURL.path):/usr/bin:/bin"
        environment["TMUX"] = "fake,1,0"
        environment["TMUX_PANE"] = "%1"
        environment["HOLY_AGENT_STATE_TTY"] = ttyURL.path
        environment["HOLY_FAKE_TMUX_STATE_DIR"] = stateURL.path

        environment["HOLY_FAKE_TMUX_FAIL_OPTION"] = "@holy_agent_state_v1"
        #expect(try runHelper(
            helperURL,
            lifecycle: "working",
            reason: "user-prompt",
            environment: environment
        ) == 1)
        #expect(try Data(contentsOf: ttyURL).isEmpty)
        #expect(!FileManager.default.fileExists(
            atPath: stateURL.appendingPathComponent("holy_agent_state_v1").path
        ))

        environment["HOLY_FAKE_TMUX_FAIL_OPTION"] = "@holy_agent_last_finished_v1"
        #expect(try runHelper(
            helperURL,
            lifecycle: "finished",
            reason: "turn-finished",
            environment: environment
        ) == 1)
        let latestURL = stateURL.appendingPathComponent("holy_agent_state_v1")
        let finishURL = stateURL.appendingPathComponent("holy_agent_last_finished_v1")
        let committedLatest = try String(contentsOf: latestURL, encoding: .utf8)
        #expect(try HolyAgentStateEnvelope(wireValue: committedLatest).lifecycle == .finished)
        #expect(!FileManager.default.fileExists(atPath: finishURL.path))
        #expect(try Data(contentsOf: ttyURL).isEmpty)

        environment.removeValue(forKey: "HOLY_FAKE_TMUX_FAIL_OPTION")
        #expect(try runHelper(
            helperURL,
            lifecycle: "finished",
            reason: "turn-finished",
            environment: environment
        ) == 0)
        #expect(try String(contentsOf: latestURL, encoding: .utf8) == committedLatest)
        #expect(try String(contentsOf: finishURL, encoding: .utf8) == committedLatest)
        #expect(!(try Data(contentsOf: ttyURL)).isEmpty)
    }

    @Test(.enabled(if: holyAgentStateRealTmuxURL != nil))
    func dcsWrappedOSCTraversesRealTmuxFromHiddenPane() throws {
        let tmuxURL = try #require(holyAgentStateRealTmuxURL)

        // tmux's AF_UNIX socket path is bounded; macOS's per-user temporary
        // directory is already long enough that a descriptive leaf can exceed
        // it before the server starts.
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("has-\(UUID().uuidString.prefix(8))", isDirectory: true)
        let socketURL = root.appendingPathComponent("tmux.sock")
        let helperURL = root.appendingPathComponent("agent-state-hook.sh")
        let runnerURL = root.appendingPathComponent("producer.sh")
        let readyURL = root.appendingPathComponent("ready")
        let statusURL = root.appendingPathComponent("status")
        let captureURL = root.appendingPathComponent("typescript")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            _ = try? runCommand(
                tmuxURL,
                arguments: ["-S", socketURL.path, "kill-server"],
                environment: cleanTmuxEnvironment()
            )
            try? FileManager.default.removeItem(at: root)
        }
        try Data(HolyAgentStateBridge.helperScript.utf8).write(to: helperURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helperURL.path)
        let runner = #"""
        #!/bin/sh
        while [ ! -e "$HOLY_READY_FILE" ]; do sleep 0.02; done
        "$HOLY_HELPER" codex finished turn-finished real-tmux
        result=$?
        printf '%s' "$result" > "$HOLY_STATUS_FILE"
        sleep 0.2
        exit "$result"
        """# + "\n"
        try Data(runner.utf8).write(to: runnerURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: runnerURL.path)

        var serverEnvironment = cleanTmuxEnvironment()
        serverEnvironment["HOLY_READY_FILE"] = readyURL.path
        serverEnvironment["HOLY_HELPER"] = helperURL.path
        serverEnvironment["HOLY_STATUS_FILE"] = statusURL.path
        #expect(
            try runCommand(
                tmuxURL,
                arguments: [
                    "-S", socketURL.path,
                    "-f", "/dev/null",
                    "new-session", "-d",
                    "-s", "holy-state-test",
                    "-n", "visible",
                    "sleep 30",
                ],
                environment: serverEnvironment
            ).status == 0
        )
        #expect(
            try runCommand(
                tmuxURL,
                arguments: [
                    "-S", socketURL.path,
                    "new-window", "-d",
                    "-t", "holy-state-test",
                    "-n", "producer",
                    runnerURL.path,
                ],
                environment: serverEnvironment
            ).status == 0
        )
        let paneResult = try runCommand(
            tmuxURL,
            arguments: [
                "-S", socketURL.path,
                "display-message", "-p",
                "-t", "holy-state-test:producer",
                "#{pane_id}",
            ],
            environment: serverEnvironment
        )
        let paneID = paneResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(paneResult.status == 0)
        #expect(paneID.hasPrefix("%"))
        #expect(
            try runCommand(
                tmuxURL,
                arguments: [
                    "-S", socketURL.path,
                    "set-option", "-pq",
                    "-t", paneID,
                    "@holy_runtime", "codex",
                ],
                environment: serverEnvironment
            ).status == 0
        )

        let attach = Process()
        attach.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        attach.arguments = [
            "-q", "-F", captureURL.path,
            tmuxURL.path,
            "-S", socketURL.path,
            "attach-session", "-t", "holy-state-test:visible",
        ]
        attach.environment = cleanTmuxEnvironment()
        attach.standardInput = Pipe()
        attach.standardOutput = Pipe()
        attach.standardError = Pipe()
        try attach.run()

        let clientAttached = try waitUntil(timeout: 10) {
            let result = try runCommand(
                tmuxURL,
                arguments: ["-S", socketURL.path, "list-clients", "-F", "#{client_name}"],
                environment: serverEnvironment
            )
            return result.status == 0 && !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        #expect(clientAttached)
        guard clientAttached else {
            attach.terminate()
            return
        }
        #expect(FileManager.default.createFile(atPath: readyURL.path, contents: Data()))
        let producerFinished = try waitUntil(timeout: 10) {
            FileManager.default.fileExists(atPath: statusURL.path)
        }
        #expect(producerFinished)
        #expect(try String(contentsOf: statusURL, encoding: .utf8) == "0")

        _ = try runCommand(
            tmuxURL,
            arguments: ["-S", socketURL.path, "kill-server"],
            environment: serverEnvironment
        )
        let attachExited = waitForExit(attach, timeout: 10)
        #expect(attachExited)
        if !attachExited {
            attach.terminate()
        }

        let capture = try Data(contentsOf: captureURL)
        let rawOSCPrefix = Data(
            "\u{1B}]777;notify;\(HolyAgentStateTransport.notificationTitle);v1|codex|finished|".utf8
        )
        #expect(capture.range(of: rawOSCPrefix) != nil)
        #expect(capture.range(of: Data("|real-tmux|turn-finished\u{7}".utf8)) != nil)
    }

    @Test func generatedHelperRejectsUncontrolledSourceAndLifecycle() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-agent-state-invalid-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let helperURL = root.appendingPathComponent("agent-state-hook.sh")
        let ttyURL = root.appendingPathComponent("tty-capture")
        try Data(HolyAgentStateBridge.helperScript.utf8).write(to: helperURL, options: .atomic)
        #expect(FileManager.default.createFile(atPath: ttyURL.path, contents: Data()))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [helperURL.path, "bad;source", "thinking", "free prose"]
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "TMUX")
        environment.removeValue(forKey: "TMUX_PANE")
        environment["HOLY_AGENT_STATE_TTY"] = ttyURL.path
        process.environment = environment
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 64)
        #expect(try Data(contentsOf: ttyURL).isEmpty)
    }

    private func hookCommands(in root: [String: Any]) -> [String] {
        guard let hooks = root["hooks"] as? [String: Any] else { return [] }
        return hooks.values.flatMap { value -> [String] in
            guard let groups = value as? [[String: Any]] else { return [] }
            return hookCommands(inGroups: groups)
        }
    }

    private func hookCommands(inGroups groups: [[String: Any]]) -> [String] {
        groups.flatMap { group in
            (group["hooks"] as? [[String: Any]] ?? []).compactMap {
                $0["command"] as? String
            }
        }
    }

    private func promptHandlers(in root: [String: Any]) -> [String] {
        guard let hooks = root["hooks"] as? [String: Any] else { return [] }
        return hooks.values.flatMap { value -> [String] in
            guard let groups = value as? [[String: Any]] else { return [] }
            return groups.flatMap { group in
                (group["hooks"] as? [[String: Any]] ?? []).compactMap {
                    $0["prompt"] as? String
                }
            }
        }
    }

    private func canonicalJSON(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    private func writeFakeTmux(
        in directory: URL,
        holyRuntime: String,
        holyOwner: String = ""
    ) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let tmuxURL = directory.appendingPathComponent("tmux")
        let script = """
        #!/bin/sh
        last=""
        for argument in "$@"; do last=$argument; done
        case "$1" in
          display-message)
            case "$last" in
              '#{@holy_agent_state_owner_v1}') printf '%s\\n' '\(holyOwner)' ;;
              '#{@holy_runtime}') printf '%s\\n' '\(holyRuntime)' ;;
            esac
            ;;
          show-options)
            file="${HOLY_FAKE_TMUX_STATE_DIR:-}/"$(printf '%s' "$last" | sed 's/^@//')
            [ -n "${HOLY_FAKE_TMUX_STATE_DIR:-}" ] && [ -f "$file" ] && cat "$file"
            ;;
          set-option)
            option=""
            value=""
            while [ "$#" -gt 0 ]; do
              case "$1" in
                @*) option=$1; shift; value=${1:-}; break ;;
              esac
              shift
            done
            if [ -n "${HOLY_FAKE_TMUX_FAIL_OPTION:-}" ] \
              && [ "$option" = "$HOLY_FAKE_TMUX_FAIL_OPTION" ]; then
              exit 1
            fi
            if [ -n "${HOLY_FAKE_TMUX_STATE_DIR:-}" ] && [ -n "$option" ]; then
              printf '%s' "$value" > "$HOLY_FAKE_TMUX_STATE_DIR/$(printf '%s' "$option" | sed 's/^@//')"
            fi
            ;;
          *) exit 1 ;;
        esac
        """
        try Data(script.utf8).write(to: tmuxURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: tmuxURL.path
        )
    }

    private func runHelper(
        _ helperURL: URL,
        lifecycle: String,
        reason: String,
        environment: [String: String]
    ) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [helperURL.path, "claude", lifecycle, reason, "adopted-session"]
        process.environment = environment
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func cleanTmuxEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "TMUX")
        environment.removeValue(forKey: "TMUX_PANE")
        environment["TERM"] = "xterm-256color"
        return environment
    }

    private func runCommand(
        _ executableURL: URL,
        arguments: [String],
        environment: [String: String]
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(bytes: data, encoding: .utf8) ?? "")
    }

    private func waitUntil(
        timeout: TimeInterval,
        condition: () throws -> Bool
    ) throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if try condition() { return true }
            Thread.sleep(forTimeInterval: 0.025)
        } while Date() < deadline
        return try condition()
    }

    private func waitForExit(_ process: Process, timeout: TimeInterval) -> Bool {
        if !process.isRunning { return true }
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        if !process.isRunning { return true }
        return exited.wait(timeout: .now() + timeout) == .success
    }
}
