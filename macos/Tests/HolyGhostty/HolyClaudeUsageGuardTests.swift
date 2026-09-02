import Foundation
import Testing
@testable import Ghostty

/// The guard has two halves that must agree: the Swift evaluator behind the
/// meter and notifications, and the Python mirror inside the generated hook.
/// These tests drive both from the same fixtures.
struct HolyClaudeUsageGuardTests {
    private let policy = HolyClaudeUsagePolicy.default
    private let now = Date(timeIntervalSince1970: 1_787_000_000)

    // MARK: - Evaluator

    @Test func percentThresholdsDecideLevels() {
        #expect(level(percent: 10) == .normal)
        #expect(level(percent: policy.warnPercent) == .warn)
        #expect(level(percent: policy.criticalPercent) == .critical)
        #expect(level(percent: 100) == .capped)
    }

    @Test func projectedCapInsideLeadWindowIsCritical() {
        let inside = bucket(percent: 60, etaFullAt: now.addingTimeInterval(policy.leadMinutes * 60 - 1))
        let nearlyInside = bucket(percent: 60, etaFullAt: now.addingTimeInterval(policy.leadMinutes * 60 * 2 - 1))
        let far = bucket(percent: 60, etaFullAt: now.addingTimeInterval(policy.leadMinutes * 60 * 5))
        #expect(HolyClaudeUsageEvaluator.level(for: inside, policy: policy, now: now)?.level == .critical)
        #expect(HolyClaudeUsageEvaluator.level(for: nearlyInside, policy: policy, now: now)?.level == .warn)
        #expect(HolyClaudeUsageEvaluator.level(for: far, policy: policy, now: now)?.level == .normal)
    }

    @Test func providerSeverityCountsAsWarning() {
        let bucket = bucket(percent: 20, severity: "warning")
        #expect(HolyClaudeUsageEvaluator.level(for: bucket, policy: policy, now: now)?.level == .warn)
    }

    @Test func assessmentPicksTheWorstBucket() {
        let buckets = [
            bucket(key: "session", percent: 30),
            bucket(key: "weekly_all", percent: policy.criticalPercent + 2),
            bucket(key: "weekly_scoped:Fable", percent: policy.warnPercent + 1),
        ]
        let assessment = HolyClaudeUsageEvaluator.assess(buckets: buckets, policy: policy, now: now)
        #expect(assessment.level == .critical)
        #expect(assessment.decidingBucket?.key == "weekly_all")
    }

    @Test func policyDefaultsSurviveBadOverrides() {
        let defaults = UserDefaults(suiteName: "holy.claudeUsage.tests.\(UUID().uuidString)")!
        defaults.set(0, forKey: HolyClaudeUsagePolicy.DefaultsKey.warnPercent)
        defaults.set(50, forKey: HolyClaudeUsagePolicy.DefaultsKey.criticalPercent)
        defaults.set(-3, forKey: HolyClaudeUsagePolicy.DefaultsKey.leadMinutes)
        let policy = HolyClaudeUsagePolicy.fromUserDefaults(defaults)
        #expect(policy.warnPercent == HolyClaudeUsagePolicy.default.warnPercent)
        // critical below warn is clamped up to warn rather than inverting the order.
        #expect(policy.criticalPercent == HolyClaudeUsagePolicy.default.warnPercent)
        #expect(policy.leadMinutes == HolyClaudeUsagePolicy.default.leadMinutes)
    }

    // MARK: - Parser

    @Test func parsesProbeSnapshotAndSessionReading() throws {
        let snapshot = try HolyClaudeUsageSnapshotParser.parseSnapshot(Data(latestJSON(percent: 42).utf8))
        #expect(snapshot.account.email == "erik@example.com")
        #expect(snapshot.buckets.count == 3)
        #expect(snapshot.bucket("weekly_scoped:Fable")?.label == "Week (Fable)")
        #expect(snapshot.bucket("session")?.percent == 42)
        #expect(snapshot.bucket("session")?.resetsAt == now.addingTimeInterval(3_600))
        #expect(!snapshot.isStale)

        let reading = try HolyClaudeUsageSnapshotParser.parseSessionReading(Data(sessionJSON(fiveHour: 88).utf8))
        #expect(reading.sessionID == "abc-123")
        #expect(reading.fiveHour?.percent == 88)
        #expect(reading.fiveHour?.key == "session")
        #expect(reading.sevenDay?.percent == 5)
        #expect(reading.workingDirectory == "/Users/erik/proj")
    }

    @Test func rejectsUnknownSchema() {
        let data = Data(#"{"schema": 99, "buckets": []}"#.utf8)
        #expect(throws: HolyClaudeUsageSnapshotParserError.unsupportedSchema(99)) {
            try HolyClaudeUsageSnapshotParser.parseSnapshot(data)
        }
    }

    // MARK: - Bridge install / remove

    @Test func installIsIdempotentAndRemovalPreservesForeignHooks() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.writeJSON([
            "model": "opus",
            "hooks": [
                "PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "keep-pre"]]]],
                "Stop": [["hooks": [["type": "command", "command": "keep-stop"]]]],
            ],
        ], to: fixture.paths.settingsURL)

        #expect(try HolyClaudeUsageBridge.install(paths: fixture.paths, policy: policy) == .installed)
        #expect(try HolyClaudeUsageBridge.installationState(paths: fixture.paths) == .installed)
        #expect(try HolyClaudeUsageBridge.install(paths: fixture.paths, policy: policy) == .alreadyInstalled)
        #expect(try String(contentsOf: fixture.paths.guardURL, encoding: .utf8) == HolyClaudeUsageBridge.guardScript)
        #expect(try String(contentsOf: fixture.paths.probeURL, encoding: .utf8) == HolyClaudeUsageBridge.probeScript)
        #expect(FileManager.default.fileExists(atPath: fixture.paths.policyURL.path))

        var settings = try fixture.readJSON(fixture.paths.settingsURL)
        #expect(settings["model"] as? String == "opus")
        let installedCommands = fixture.commands(in: settings)
        #expect(installedCommands.contains("keep-pre"))
        #expect(installedCommands.contains("keep-stop"))
        #expect(installedCommands.filter { $0.contains("claude-usage-guard.py") }.count == 2)

        // A policy change alone re-installs so the hook reads the new numbers.
        var tighter = policy
        tighter.warnPercent = 50
        #expect(try HolyClaudeUsageBridge.install(paths: fixture.paths, policy: tighter) == .installed)
        #expect(try HolyClaudeUsageBridge.policyIsCurrent(paths: fixture.paths, policy: tighter))

        #expect(try HolyClaudeUsageBridge.remove(paths: fixture.paths) == .removed)
        settings = try fixture.readJSON(fixture.paths.settingsURL)
        #expect(fixture.commands(in: settings) == ["keep-pre", "keep-stop"])
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.guardURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.probeURL.path))
        #expect(try HolyClaudeUsageBridge.installationState(paths: fixture.paths) == .notInstalled)
        #expect(try HolyClaudeUsageBridge.remove(paths: fixture.paths) == .notInstalled)
    }

    @Test func wrapUpRequestExpiresAndCancels() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try HolyClaudeUsageBridge.requestWrapUp(
            paths: fixture.paths,
            policy: policy,
            accountEmail: "erik@example.com",
            reason: "test",
            now: now
        )
        #expect(HolyClaudeUsageBridge.activeWrapUpRequest(paths: fixture.paths, now: now)?.reason == "test")
        #expect(HolyClaudeUsageBridge.activeWrapUpRequest(
            paths: fixture.paths,
            now: now.addingTimeInterval(policy.leadMinutes * 60 + 1)
        ) == nil)
        try HolyClaudeUsageBridge.cancelWrapUp(paths: fixture.paths)
        #expect(HolyClaudeUsageBridge.activeWrapUpRequest(paths: fixture.paths, now: now) == nil)
    }

    // MARK: - Generated guard hook (Python mirror)

    @Test func guardStaysSilentAtNormalUsage() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.installGuard(policy: policy)
        try fixture.write(latestJSON(percent: 10), to: fixture.paths.latestURL)
        let output = try fixture.runGuard(event: "PreToolUse", tool: "Bash", sessionID: "s1")
        #expect(output == nil)
    }

    @Test func guardWarnsOnceThenRemindsAfterHalfLead() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.installGuard(policy: policy)
        try fixture.write(latestJSON(percent: policy.warnPercent + 1), to: fixture.paths.latestURL)

        let first = try #require(try fixture.runGuard(event: "PreToolUse", tool: "Bash", sessionID: "s1"))
        let context = try #require(first["additionalContext"] as? String)
        #expect(context.contains("HOLY USAGE GUARD"))
        #expect(context.contains("approaching"))
        #expect(context.contains("Session (5h) 76%"))
        #expect(first["permissionDecision"] == nil)

        // Same level, immediately again: suppressed.
        #expect(try fixture.runGuard(event: "PreToolUse", tool: "Bash", sessionID: "s1") == nil)

        // Back-date the announcement past the reminder interval: announced again.
        let stateURL = fixture.paths.usageDirectoryURL
            .appendingPathComponent("guard-state", isDirectory: true)
            .appendingPathComponent("s1.json")
        let reminder = policy.leadMinutes * 60 / 2 + 1
        try fixture.write(
            #"{"level": "warn", "announced_at": \#(Date().timeIntervalSince1970 - reminder)}"#,
            to: stateURL
        )
        #expect(try fixture.runGuard(event: "PreToolUse", tool: "Bash", sessionID: "s1") != nil)
    }

    @Test func guardDeniesSubagentSpawnsAtCritical() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.installGuard(policy: policy)
        try fixture.write(latestJSON(percent: policy.criticalPercent + 3), to: fixture.paths.latestURL)

        let spawn = try #require(try fixture.runGuard(event: "PreToolUse", tool: "Agent", sessionID: "s2"))
        #expect(spawn["permissionDecision"] as? String == "deny")
        #expect((spawn["permissionDecisionReason"] as? String)?.contains("Subagent spawns are denied") == true)
        #expect((spawn["additionalContext"] as? String)?.contains("PAUSED (usage cap):") == true)

        // Every ordinary tool call carries the instruction at critical.
        let bash1 = try #require(try fixture.runGuard(event: "PreToolUse", tool: "Bash", sessionID: "s2"))
        let bash2 = try #require(try fixture.runGuard(event: "PreToolUse", tool: "Bash", sessionID: "s2"))
        #expect(bash1["permissionDecision"] == nil)
        #expect((bash1["additionalContext"] as? String)?.contains("IMMINENT") == true)
        #expect(bash2["additionalContext"] != nil)

        // A user prompt is never blocked, only informed.
        let prompt = try #require(try fixture.runGuard(event: "UserPromptSubmit", tool: nil, sessionID: "s2"))
        #expect(prompt["permissionDecision"] == nil)
        #expect(prompt["additionalContext"] != nil)
    }

    @Test func guardPrefersTheSessionsOwnReading() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.installGuard(policy: policy)
        // Machine-wide says calm; this session's own status line says it is
        // nearly capped (it runs under a different account).
        try fixture.write(latestJSON(percent: 5), to: fixture.paths.latestURL)
        try fixture.write(
            sessionJSON(fiveHour: policy.criticalPercent + 1, resetsAt: Date().addingTimeInterval(3_600)),
            to: fixture.paths.sessionsDirectoryURL.appendingPathComponent("abc-123.json")
        )
        let own = try #require(try fixture.runGuard(event: "PreToolUse", tool: "Bash", sessionID: "abc-123"))
        #expect((own["additionalContext"] as? String)?.contains("IMMINENT") == true)
        #expect(try fixture.runGuard(event: "PreToolUse", tool: "Bash", sessionID: "other") == nil)
    }

    @Test func guardHonorsWrapUpRequestUntilAccountChanges() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.installGuard(policy: policy)
        try fixture.write(latestJSON(percent: 5), to: fixture.paths.latestURL)
        try HolyClaudeUsageBridge.requestWrapUp(
            paths: fixture.paths,
            policy: policy,
            accountEmail: "erik@example.com",
            reason: "switching accounts"
        )
        let paused = try #require(try fixture.runGuard(event: "PreToolUse", tool: "Bash", sessionID: "s3"))
        #expect((paused["additionalContext"] as? String)?.contains("asked every session to pause") == true)
        let spawn = try #require(try fixture.runGuard(event: "PreToolUse", tool: "Task", sessionID: "s3"))
        #expect(spawn["permissionDecision"] as? String == "deny")

        // The keychain moved to another account: the request no longer applies.
        try fixture.write(latestJSON(percent: 5, email: "second@example.com"), to: fixture.paths.latestURL)
        #expect(try fixture.runGuard(event: "PreToolUse", tool: "Bash", sessionID: "s3") == nil)
    }

    @Test func guardDropsMachineSnapshotFromAPreviousAccount() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.installGuard(policy: policy)
        // The keychain (as Claude records it) has moved to a second account,
        // but the probe's last snapshot — critical — still belongs to the first.
        try fixture.write(
            #"{"oauthAccount": {"emailAddress": "second@example.com"}}"#,
            to: fixture.root.appendingPathComponent(".claude.json")
        )
        try fixture.write(latestJSON(percent: policy.criticalPercent + 5), to: fixture.paths.latestURL)

        // Someone else's headroom is not this account's emergency.
        #expect(try fixture.runGuard(event: "PreToolUse", tool: "Agent", sessionID: "s5") == nil)
        // And the guard asked the probe for a fresh read (forced through any backoff).
        #expect(FileManager.default.fileExists(
            atPath: fixture.paths.usageDirectoryURL.appendingPathComponent("refresh-requested").path
        ))

        // This session's own reading still counts, whichever account it came from.
        try fixture.write(
            sessionJSON(fiveHour: policy.criticalPercent + 1, resetsAt: Date().addingTimeInterval(3_600)),
            to: fixture.paths.sessionsDirectoryURL.appendingPathComponent("abc-123.json")
        )
        let own = try #require(try fixture.runGuard(event: "PreToolUse", tool: "Bash", sessionID: "abc-123"))
        #expect((own["additionalContext"] as? String)?.contains("second@example.com") == true)
    }

    @Test func guardMirrorsSwiftEvaluatorAcrossFixtures() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.installGuard(policy: policy)
        let cases: [(percent: Double, etaOffset: TimeInterval?, severity: String?)] = [
            (10, nil, nil),
            (policy.warnPercent - 0.5, nil, nil),
            (policy.warnPercent, nil, nil),
            (policy.criticalPercent - 0.5, nil, nil),
            (policy.criticalPercent, nil, nil),
            (100, nil, nil),
            (60, policy.leadMinutes * 60 - 5, nil),
            (60, policy.leadMinutes * 60 * 2 - 5, nil),
            (60, policy.leadMinutes * 60 * 3, nil),
            (20, nil, "warning"),
        ]
        for testCase in cases {
            let sessionID = "mirror-\(Int(testCase.percent))-\(Int(testCase.etaOffset ?? 0))-\(testCase.severity ?? "n")"
            let etaDate = testCase.etaOffset.map { Date().addingTimeInterval($0) }
            let swiftBucket = bucket(percent: testCase.percent, severity: testCase.severity, etaFullAt: etaDate)
            let swiftLevel = HolyClaudeUsageEvaluator.level(for: swiftBucket, policy: policy, now: Date())?.level ?? .normal
            try fixture.write(
                latestJSON(percent: testCase.percent, etaFullAt: etaDate, severity: testCase.severity, singleBucket: true),
                to: fixture.paths.latestURL
            )
            let output = try fixture.runGuard(event: "PreToolUse", tool: "Agent", sessionID: sessionID)
            let pythonLevel: HolyClaudeUsageLevel
            if output == nil {
                pythonLevel = .normal
            } else if output?["permissionDecision"] as? String == "deny" {
                let text = output?["additionalContext"] as? String ?? ""
                pythonLevel = text.contains("REACHED") ? .capped : .critical
            } else {
                pythonLevel = .warn
            }
            #expect(pythonLevel == swiftLevel, "percent \(testCase.percent) eta \(String(describing: testCase.etaOffset)) severity \(String(describing: testCase.severity))")
        }
    }

    @Test func probeComposesGreenBarSegmentMirroringLevels() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.installGuard(policy: policy)
        let harness = """
        import runpy, sys, time
        module = runpy.run_path(sys.argv[1], run_name="probe_test")
        now = time.time()
        buckets = [
            {"key": "session", "percent": 30.0},
            {"key": "weekly_all", "percent": \(policy.warnPercent + 1)},
            {"key": "weekly_scoped:Fable", "percent": \(policy.criticalPercent + 1)},
            {"key": "weekly_scoped:Fa#(whoami)%H;'`ble", "percent": 10.0},
        ]
        policy = {"warn_percent": \(policy.warnPercent), "critical_percent": \(policy.criticalPercent),
                  "lead_minutes": \(policy.leadMinutes), "poll_seconds": \(policy.pollSeconds)}
        print(module["compose_segment"](buckets, policy, now))
        print(module["compose_segment"]([], policy, now))
        print(module["compose_segment"](buckets, policy, now, stale_seconds=300, wrap_up=True))
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", harness, fixture.paths.probeURL.path]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()
        let output = String(
            data: stdout.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines.count >= 3)
        // Calm window stays plain; warn becomes a yellow chip; critical a red one.
        #expect(lines[0].contains("⌁ claude"))
        #expect(lines[0].contains("5h 30%%"))
        #expect(!lines[0].contains("bg=yellow,bold] 5h"))
        #expect(lines[0].contains("#[fg=black,bg=yellow,bold] wk \(Int(policy.warnPercent + 1))%% #[default]"))
        #expect(lines[0].contains("#[fg=white,bg=red,bold] Fable \(Int(policy.criticalPercent + 1))%% #[default]"))
        // A hostile scoped-model name from the API cannot smuggle tmux format
        // syntax into the #{E:...}-expanded option: #( would run a command.
        #expect(lines[0].contains("FawhoamiHble 10%%"))
        #expect(!lines[0].contains("#(whoami)"))
        #expect(!lines[0].contains("%H"))
        // No numbers, no segment: the green bar returns to stock.
        #expect(lines[1].isEmpty)
        // Wrap-up and staleness are visible in the bar itself.
        #expect(lines[2].contains("⏸ WRAP UP"))
        #expect(lines[2].contains("(stale 5m)"))
    }

    @Test func probeNormalizesCodexAndGroupsItsChips() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.installGuard(policy: policy)
        // A rollout tail in the codex snake_case shape, for the fallback path.
        let rolloutDir = fixture.root.appendingPathComponent(".codex-home/sessions/2026/09/02")
        try fixture.write(
            #"{"timestamp":"2026-09-02T12:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":41.0,"window_minutes":10080,"resets_at":1788786264},"secondary":null,"plan_type":"pro"}}}"#,
            to: rolloutDir.appendingPathComponent("rollout-2026-09-02T12-00-00-abc.jsonl")
        )
        let harness = """
        import runpy, sys, json, os, time
        module = runpy.run_path(sys.argv[1], run_name="probe_test")
        now = time.time()
        raw = {"rateLimitsByLimitId": {
            "codex": {"limitId": "codex", "limitName": None,
                      "primary": {"usedPercent": 8, "windowDurationMins": 10080, "resetsAt": 1788786264}},
            "codex_topmodel": {"limitId": "codex_topmodel", "limitName": "GPT-5.6-Sol",
                               "primary": {"usedPercent": 12, "windowDurationMins": 300, "resetsAt": 1788385515},
                               "secondary": {"usedPercent": 0, "windowDurationMins": 10080, "resetsAt": 1788972315}},
        }}
        buckets = module["normalize_codex"](raw)
        print(json.dumps(buckets))
        policy = {"warn_percent": \(policy.warnPercent), "critical_percent": \(policy.criticalPercent),
                  "lead_minutes": \(policy.leadMinutes), "poll_seconds": \(policy.pollSeconds)}
        claude = [{"key": "session", "label": "Session (5h)", "percent": 30.0}]
        print(module["compose_segment"](claude + buckets, policy, now, codex_resets=1))
        print(json.dumps(module["codex_fallback_buckets"](now)))
        print(module["compose_segment"](claude + buckets, policy, now))
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", harness, fixture.paths.probeURL.path]
        process.environment = [
            "HOLY_CODEX_HOME": fixture.root.appendingPathComponent(".codex-home").path,
            "PATH": "/usr/bin:/bin",
        ]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()
        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines.count >= 3)

        // Dynamic model naming: whatever limit ids arrive get buckets.
        let buckets = try #require(try JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [[String: Any]])
        let keys = buckets.compactMap { $0["key"] as? String }
        #expect(keys.contains("codex:codex:primary"))
        #expect(keys.contains("codex:codex_topmodel:primary"))
        #expect(keys.contains("codex:codex_topmodel:secondary"))
        let top = try #require(buckets.first { $0["key"] as? String == "codex:codex_topmodel:primary" })
        #expect(top["short"] as? String == "5.6-Sol 5h")
        #expect(top["label"] as? String == "Codex GPT-5.6-Sol (5h)")
        #expect(top["window_seconds"] as? Int == 300 * 60)

        // The bar groups by vendor and hides zero-percent model chips.
        #expect(lines[1].contains("⌁ claude"))
        #expect(lines[1].contains("⌁ codex"))
        #expect(lines[1].contains("wk 8%%"))
        #expect(lines[1].contains("5.6-Sol 5h 12%%"))
        #expect(!lines[1].contains("5.6-Sol wk"))
        #expect(lines[1].range(of: "⌁ claude")!.lowerBound < lines[1].range(of: "⌁ codex")!.lowerBound)

        // The rollout fallback parses the snake_case snapshot.
        let fallback = try #require(try JSONSerialization.jsonObject(with: Data(lines[2].utf8)) as? [[String: Any]])
        #expect(fallback.count == 1)
        #expect(fallback[0]["key"] as? String == "codex:codex:primary")
        #expect((fallback[0]["percent"] as? NSNumber)?.doubleValue == 41.0)

        // The banked reset-credit counter rides the codex group; without a
        // reported number it is absent, never a phantom zero.
        #expect(lines[1].contains("↻1"))
        #expect(lines.count >= 4)
        #expect(!lines[3].contains("↻"))
    }

    @Test func guardNeverActsOnCodexBuckets() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.installGuard(policy: policy)
        let resets = Int(Date().timeIntervalSince1970) + 3_600
        try fixture.write("""
        {"schema": 1, "fetched_at": \(Int(Date().timeIntervalSince1970)),
         "account": {"email": "erik@example.com"},
         "buckets": [
           {"key": "session", "label": "Session (5h)", "percent": 10, "severity": "normal", "resets_at": \(resets), "window_seconds": 18000, "is_active": true},
           {"key": "codex:codex:primary", "label": "Codex (week)", "percent": 99, "severity": null, "resets_at": \(resets), "window_seconds": 604800, "is_active": true}
         ],
         "extra_usage": {"enabled": false}, "error": null}
        """, to: fixture.paths.latestURL)
        // A capped codex window must not pause Claude work or deny spawns.
        #expect(try fixture.runGuard(event: "PreToolUse", tool: "Agent", sessionID: "s9") == nil)
        #expect(try fixture.runGuard(event: "PreToolUse", tool: "Bash", sessionID: "s9") == nil)
    }

    @Test func probeHonorsRateLimitBackoffWithoutTouchingTheNetwork() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.installGuard(policy: policy)
        let backoffUntil = Int(Date().timeIntervalSince1970) + Int(policy.pollSeconds) * 5
        let held = latestJSON(percent: 40).replacingOccurrences(
            of: "\"error\": null",
            with: "\"error\": null, \"backoff_until\": \(backoffUntil)"
        )
        try fixture.write(held, to: fixture.paths.latestURL)
        let before = try Data(contentsOf: fixture.paths.latestURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [fixture.paths.probeURL.path]
        process.environment = [
            "HOLY_USAGE_DIR": fixture.paths.usageDirectoryURL.path,
            "HOLY_TMUX_BIN": "/usr/bin/true",
            "HOME": fixture.root.path,
            "PATH": "/usr/bin:/bin",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        // Backoff means: exit nonzero, serve the held snapshot, write nothing.
        #expect(process.terminationStatus == 1)
        #expect(try Data(contentsOf: fixture.paths.latestURL) == before)
    }

    // MARK: - Helpers

    private func level(percent: Double) -> HolyClaudeUsageLevel? {
        HolyClaudeUsageEvaluator.level(for: bucket(percent: percent), policy: policy, now: now)?.level
    }

    private func bucket(
        key: String = "session",
        percent: Double,
        severity: String? = nil,
        etaFullAt: Date? = nil
    ) -> HolyClaudeUsageBucket {
        HolyClaudeUsageBucket(
            key: key,
            label: key == "session" ? "Session (5h)" : key,
            percent: percent,
            severity: severity,
            resetsAt: now.addingTimeInterval(3_600),
            windowSeconds: 5 * 3_600,
            isActive: true,
            ratePercentPerHour: nil,
            etaFullAt: etaFullAt
        )
    }

    private func latestJSON(
        percent: Double,
        email: String = "erik@example.com",
        etaFullAt: Date? = nil,
        severity: String? = nil,
        singleBucket: Bool = false
    ) -> String {
        let eta = etaFullAt.map { String(Int($0.timeIntervalSince1970)) } ?? "null"
        let sev = severity.map { "\"\($0)\"" } ?? "\"normal\""
        let resets = Int(now.timeIntervalSince1970) + 3_600
        let weekly = singleBucket ? "" : """
            ,{"key": "weekly_all", "label": "Week (all models)", "percent": 4, "severity": "normal", "resets_at": \(resets + 86_400), "window_seconds": 604800, "is_active": false, "rate_percent_per_hour": null, "eta_full_at": null},
            {"key": "weekly_scoped:Fable", "label": "Week (Fable)", "percent": 7, "severity": "normal", "resets_at": \(resets + 86_400), "window_seconds": 604800, "is_active": false, "rate_percent_per_hour": null, "eta_full_at": null}
            """
        return """
        {"schema": 1, "fetched_at": \(Int(Date().timeIntervalSince1970)),
         "account": {"email": "\(email)", "account_uuid": "u1", "organization": "org", "subscription": "max", "tier": "default_claude_max_20x", "token_expires_at": \(resets)},
         "buckets": [
           {"key": "session", "label": "Session (5h)", "percent": \(percent), "severity": \(sev), "resets_at": \(resets), "window_seconds": 18000, "is_active": true, "rate_percent_per_hour": 12.5, "eta_full_at": \(eta)}
           \(weekly)
         ],
         "extra_usage": {"enabled": false, "spend_limit_reached": false},
         "error": null}
        """
    }

    private func sessionJSON(fiveHour: Double, resetsAt: Date? = nil) -> String {
        let resets = Int((resetsAt ?? now.addingTimeInterval(3_600)).timeIntervalSince1970)
        return """
        {"t": \(Int(Date().timeIntervalSince1970)), "session_id": "abc-123", "pane": "%7", "cwd": "/Users/erik/proj",
         "five_hour": {"percent": \(fiveHour), "resets_at": \(resets)},
         "seven_day": {"percent": 5, "resets_at": \(resets + 86_400)}}
        """
    }

    private struct Fixture {
        let root: URL
        let paths: HolyClaudeUsageBridgePaths

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("holy-claude-usage-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            paths = HolyClaudeUsageBridgePaths(
                settingsURL: root.appendingPathComponent(".claude/settings.json"),
                probeURL: root.appendingPathComponent("Holy/claude-usage-probe.py"),
                guardURL: root.appendingPathComponent("Holy/claude-usage-guard.py"),
                usageDirectoryURL: root.appendingPathComponent("Holy/usage", isDirectory: true)
            )
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }

        func installGuard(policy: HolyClaudeUsagePolicy) throws {
            _ = try HolyClaudeUsageBridge.install(paths: paths, policy: policy)
        }

        func write(_ contents: String, to url: URL) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: url, options: .atomic)
        }

        func writeJSON(_ object: [String: Any], to url: URL) throws {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }

        func readJSON(_ url: URL) throws -> [String: Any] {
            let data = try Data(contentsOf: url)
            return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        }

        func commands(in settings: [String: Any]) -> [String] {
            guard let hooks = settings["hooks"] as? [String: Any] else { return [] }
            return hooks.keys.sorted().flatMap { event -> [String] in
                let groups = hooks[event] as? [[String: Any]] ?? []
                return groups.flatMap { group in
                    (group["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
                }
            }
        }

        /// Runs the generated hook exactly as Claude Code would: hook JSON on
        /// stdin, `hookSpecificOutput` JSON on stdout, or nothing.
        func runGuard(event: String, tool: String?, sessionID: String) throws -> [String: Any]? {
            var input: [String: Any] = ["hook_event_name": event, "session_id": sessionID, "cwd": "/tmp"]
            if let tool { input["tool_name"] = tool }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = [paths.guardURL.path]
            process.environment = ["HOLY_USAGE_DIR": paths.usageDirectoryURL.path, "HOME": root.path, "PATH": "/usr/bin:/bin"]
            let stdin = Pipe()
            let stdout = Pipe()
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = FileHandle.nullDevice
            try process.run()
            stdin.fileHandleForWriting.write(try JSONSerialization.data(withJSONObject: input))
            try stdin.fileHandleForWriting.close()
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
            guard !data.isEmpty else { return nil }
            let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            return try #require(object["hookSpecificOutput"] as? [String: Any])
        }
    }
}
