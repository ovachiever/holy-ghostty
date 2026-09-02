import Foundation
import Testing
@testable import Ghostty

struct HolyMannaBoardTests {
    @Test func canonicalStateAndEstateContractsDecodeWithoutLegacyList() async throws {
        let recorder = HolyMannaInvocationRecorder()
        let client = HolyMannaBoardClient { invocation, _ in
            await recorder.append(invocation)
            let payload = invocation.displayCommand.contains("estate")
                ? HolyMannaBoardFixtures.estate
                : HolyMannaBoardFixtures.state
            return .init(stdout: payload, stderr: "", exitCode: 0)
        }
        let context = HolyMannaBoardContext(
            boardRoot: "/srv/holy-ghostty",
            remoteHost: "builder@example.com"
        )

        let state = try await client.state(for: context)
        let estate = try await client.estate(for: context)
        let invocations = await recorder.values

        #expect(state.name == "holy-ghostty")
        #expect(state.now.map(\.id) == ["mn-live001"])
        #expect(state.coord.drops.first?.paths == [".handoff/live.md"])
        #expect(state.asks.map(\.verb) == ["grant", "close"])
        #expect(estate.boards.first?.needsYou == 1)
        #expect(estate.totals.needsYou == 1)
        #expect(invocations.count == 2)
        #expect(invocations[0].displayCommand == "builder@example.com: agent-do manna state --json")
        #expect(invocations[1].displayCommand == "builder@example.com: agent-do manna estate --json")
        #expect(invocations.allSatisfy { !$0.displayCommand.contains("manna list") })
    }

    @Test func remoteHostCannotSmuggleSSHFlags() throws {
        let context = HolyMannaBoardContext(
            boardRoot: "/srv/holy-ghostty",
            remoteHost: "builder@[2001:db8::1]"
        )
        let invocation = try HolyMannaBoardClient.remoteInvocation(
            arguments: ["manna", "state", "--json"],
            context: context,
            needsBoardRoot: true,
            identity: nil
        )

        let destinationIndex = try #require(invocation.arguments.firstIndex(of: "builder@[2001:db8::1]"))
        #expect(invocation.arguments[destinationIndex - 1] == "--")
        #expect(invocation.executablePath == "/usr/bin/ssh")

        #expect(throws: HolyMannaBoardClientError.launchFailed("invalid remote host")) {
            _ = try HolyMannaBoardClient.remoteInvocation(
                arguments: ["manna", "state", "--json"],
                context: .init(
                    boardRoot: "/srv/holy-ghostty",
                    remoteHost: "-oProxyCommand=touch /tmp/pwned"
                ),
                needsBoardRoot: true,
                identity: nil
            )
        }
    }

    @Test func remoteMutationsUseHolyProofOnStdinAndNeverRetry() async throws {
        let directory = try temporaryDirectory(named: "holy-board-identity")
        defer { try? FileManager.default.removeItem(at: directory) }
        let identityStore = HolyMannaActorIdentityStore(
            fileURL: directory.appendingPathComponent("manna-actor.json")
        )
        let identity = try await identityStore.identity()
        let recorder = HolyMannaInvocationRecorder()
        let client = HolyMannaBoardClient(identityStore: identityStore) { invocation, _ in
            await recorder.append(invocation)
            return .init(stdout: "{\"success\":true}\n", stderr: "", exitCode: 0)
        }

        let receipts = try await client.perform(
            .close("mn-live001"),
            in: .init(boardRoot: "/srv/holy-ghostty", remoteHost: "builder@example.com")
        )
        let invocations = await recorder.values

        #expect(receipts.count == 2)
        #expect(invocations.count == 2)
        #expect(invocations[0].stdin.flatMap { String(bytes: $0, encoding: .utf8) }?.contains(identity.token) == true)
        #expect(invocations[1].stdin.flatMap { String(bytes: $0, encoding: .utf8) }?.contains(identity.token) == true)
        #expect(invocations.allSatisfy { !$0.arguments.joined().contains(identity.token) })
        #expect(invocations.allSatisfy { !$0.displayCommand.contains(identity.token) })
        #expect(
            invocations[0].stdin
                .flatMap { String(bytes: $0, encoding: .utf8) }?
                .contains("'manna' 'claim' 'mn-live001'") == true
        )
        #expect(
            invocations[1].stdin
                .flatMap { String(bytes: $0, encoding: .utf8) }?
                .contains("'manna' 'done' 'mn-live001'") == true
        )
    }

    @Test func holyActorIdentityIsStableAndPrivate() async throws {
        let directory = try temporaryDirectory(named: "holy-board-identity")
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("manna-actor.json")
        let firstStore = HolyMannaActorIdentityStore(fileURL: fileURL)
        let secondStore = HolyMannaActorIdentityStore(fileURL: fileURL)

        let first = try await firstStore.identity()
        let second = try await secondStore.identity()
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)

        #expect(first == second)
        #expect(first.isValid)
        #expect(attributes[.posixPermissions] as? Int == 0o600)
        #expect(!(try String(contentsOf: fileURL, encoding: .utf8)).contains("CODEX_THREAD_ID"))
    }

    @Test func attentionBadgeDeduplicatesJoinedPeersButCountsIdentitylessSessions() {
        let count = HolyAttentionBadgeCounter.count(
            github: 2,
            boardAsks: 3,
            boardPeerIDs: ["codex-019f62805fc77093", "claude-aaaaaaaaaaaa"],
            sessionIDs: [
                "019f6280-5fc7-7093-a705-8d6f4916f911",
                "019f62805fc77093a7058d6f4916f911",
                nil,
            ]
        )

        // 2 GitHub + 1 non-peer Board ask + 1 joined harness + 1
        // identityless session + 1 unmatched peer. The compact duplicate is
        // the same harness identity, not a second demand on the human.
        #expect(count == 6)
    }

    @Test func digestHashChangesOnlyWhenMeaningfulItemContentChanges() throws {
        let first = try HolyMannaBoardFixtures.item(
            description: "Build the native Board.",
            blockerStatus: "open"
        )
        let same = try HolyMannaBoardFixtures.item(
            description: "Build the native Board.",
            blockerStatus: "open"
        )
        let changed = try HolyMannaBoardFixtures.item(
            description: "Build and verify the native Board.",
            blockerStatus: "open"
        )
        let blockerChanged = try HolyMannaBoardFixtures.item(
            description: "Build the native Board.",
            blockerStatus: "done"
        )

        #expect(HolyMannaBoardDigestService.contentHash(for: first).count == 64)
        #expect(HolyMannaBoardDigestService.contentHash(for: first) == HolyMannaBoardDigestService.contentHash(for: same))
        #expect(HolyMannaBoardDigestService.contentHash(for: first) != HolyMannaBoardDigestService.contentHash(for: changed))
        #expect(HolyMannaBoardDigestService.contentHash(for: first) != HolyMannaBoardDigestService.contentHash(for: blockerChanged))
    }

    @Test @MainActor func backgroundBoardPreloadDoesNotStartAnAIDigest() async throws {
        let directory = try temporaryDirectory(named: "holy-board-preload")
        defer { try? FileManager.default.removeItem(at: directory) }
        let digestRecorder = HolyMannaDigestRecorder()
        let client = HolyMannaBoardClient(
            identityStore: HolyMannaActorIdentityStore(
                fileURL: directory.appendingPathComponent("manna-actor.json")
            )
        ) { invocation, _ in
            .init(
                stdout: invocation.displayCommand.contains("estate")
                    ? HolyMannaBoardFixtures.estate
                    : HolyMannaBoardFixtures.state,
                stderr: "",
                exitCode: 0
            )
        }
        let store = HolyMannaBoardModeStore(
            client: client,
            digestService: digestRecorder
        )

        store.prepare(context: .init(
            boardRoot: "/srv/holy-ghostty",
            remoteHost: "builder@example.com"
        ))
        for _ in 0 ..< 400 where store.state == nil {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let digestCallCount = await digestRecorder.callCount

        #expect(store.state != nil)
        #expect(!store.isPresented)
        #expect(!store.isDigestLoading)
        #expect(digestCallCount == 0)
    }

    @Test func databaseMigrationCreatesBoundedDigestCacheSurface() throws {
        let directory = try temporaryDirectory(named: "holy-board-database")
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try HolyDatabase.open(at: directory.appendingPathComponent("holy.sqlite3"))

        try HolyDatabaseMigrator.migrate(database)

        #expect(try database.userVersion() == HolyDatabaseSchema.currentUserVersion)
        #expect(
            try database.scalarInt64(
                "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'board_digest_cache';"
            ) == 1
        )
        #expect(
            try database.scalarInt64(
                "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = 'board_digest_cache_last_used_at_idx';"
            ) == 1
        )
    }

    @Test func mutationCommandsMapOnlyToRealMannaVerbsAndGateDeletion() {
        #expect(HolyMannaMutation.close("mn-live001").commands == [
            ["manna", "claim", "mn-live001"],
            ["manna", "done", "mn-live001"],
        ])
        #expect(HolyMannaMutation.fix.commands == [["manna", "reconcile", "--fix", "--json"]])
        #expect(HolyMannaMutation.delete("mn-live001").isDestructive)
        #expect(!HolyMannaMutation.claim("mn-live001").isDestructive)
    }

    private func temporaryDirectory(named prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private actor HolyMannaInvocationRecorder {
    private(set) var values: [HolyMannaProcessInvocation] = []

    func append(_ invocation: HolyMannaProcessInvocation) {
        values.append(invocation)
    }
}

private actor HolyMannaDigestRecorder: HolyMannaBoardDigesting {
    private(set) var callCount = 0

    func digest(
        for item: HolyMannaBoardItem,
        boardRoot: String?,
        allowGeneration: Bool,
        usageGuardReason: String?
    ) async throws -> HolyMannaDigestResult {
        callCount += 1
        return .init(
            text: "Unexpected digest",
            contentHash: HolyMannaBoardDigestService.contentHash(for: item),
            model: "test",
            wasCached: false
        )
    }
}

private enum HolyMannaBoardFixtures {
    static let state = """
    {
      "success": true,
      "generated_at": "2026-09-01T16:00:00Z",
      "name": "holy-ghostty",
      "root": "/srv/holy-ghostty",
      "total": 1,
      "counts": {"now": 1},
      "status_counts": {"in_progress": 1},
      "now": [\(itemJSON(description: "Build the native Board."))],
      "next": [],
      "waves": [],
      "dreams": [],
      "decisions": [],
      "tracks": [{
        "id": "mn-track01",
        "title": "Holy cockpit",
        "status": "active",
        "items": [\(itemJSON(description: "Build the native Board."))]
      }],
      "peers": [{
        "agent_id": "codex-019f62805fc77093",
        "alias": null,
        "runtime": "codex",
        "status": "active",
        "attention": "needs-user",
        "age": "0s ago",
        "age_seconds": 0,
        "goal": "build Board",
        "mode": "writer",
        "phase": "building",
        "role": null,
        "paths": ["macos/Sources/HolyGhostty/Board"],
        "holding": [{"id": "mn-live001", "title": "Native Board"}],
        "pulse": {
          "status": "needs-user",
          "activity": "waiting",
          "latest_prompt": "Approve the final action",
          "updated_at": "2026-09-01T16:00:00Z",
          "turns": 4
        }
      }],
      "attention": {"needs-user": 1},
      "coord": {
        "claims": [{
          "path": "macos/Sources/HolyGhostty/Board",
          "owner": "codex-019f62805fc77093",
          "owner_alias": null,
          "owner_status": "active",
          "reason": "native Board",
          "strength": "soft",
          "updated_at": "2026-09-01T16:00:00Z",
          "stale": false,
          "contended": false
        }],
        "contention": [],
        "needs": [{"key": "build-green", "why": "compile", "owner": "codex", "updated_at": null}],
        "drops": [{
          "path": ".handoff/live.md",
          "note": "ready",
          "owner": "codex-019f62805fc77093",
          "created_at": "2026-09-01T16:00:00Z"
        }]
      },
      "drift": {
        "present": true,
        "source": "reconcile",
        "count": 1,
        "generated_at": "2026-09-01T16:00:00Z",
        "kinds": {"landed_open": 1},
        "findings": [{
          "kind": "landed_open",
          "issue_id": "mn-live001",
          "detail": "landed but open",
          "evidence": "abc123",
          "proposed_fix": "claim and close"
        }]
      },
      "git": {"branch": "main", "head": "abc123", "dirty_paths": 1, "is_repo": true},
      "board": {
        "board_id": "mb-live",
        "workflow": "strict",
        "path": ".manna/issues.jsonl",
        "handoff_dir": ".handoff",
        "order_count": 1,
        "issues_modified_at": "2026-09-01T16:00:00Z"
      }
    }
    """

    static let estate = """
    {
      "generated_at": "2026-09-01T16:00:00Z",
      "boards": [{
        "name": "holy-ghostty",
        "root": "/srv/holy-ghostty",
        "exists": true,
        "total": 1,
        "status_counts": {"active": 1},
        "dreams": 0,
        "decisions": 0,
        "drift_count": 1,
        "drift_generated_at": "2026-09-01T16:00:00Z",
        "latest_update": "2026-09-01T16:00:00Z",
        "coord": {
          "attention": {"needs-user": 1},
          "needs_you": 1,
          "working": 0,
          "here": 1,
          "gone": 0
        },
        "slug": "holy-ghostty",
        "url": "manna://holy-ghostty"
      }],
      "count": 1,
      "registry": "/Users/erik/.manna/registry.yaml",
      "totals": {"needs_you": 1, "working": 0, "here": 1},
      "building": 1
    }
    """

    static func item(
        description: String,
        blockerStatus: String? = nil
    ) throws -> HolyMannaBoardItem {
        try JSONDecoder().decode(
            HolyMannaBoardItem.self,
            from: Data(itemJSON(description: description, blockerStatus: blockerStatus).utf8)
        )
    }

    private static func itemJSON(
        description: String,
        blockerStatus: String? = nil
    ) -> String {
        let encodedData = (try? JSONEncoder().encode(description)) ?? Data("\"\"".utf8)
        let encodedDescription = String(bytes: encodedData, encoding: .utf8) ?? "\"\""
        let blockedBy = blockerStatus == nil ? "[]" : "[\"mn-blocker1\"]"
        let blockers = blockerStatus.map { status in
            "{\"id\":\"mn-blocker1\",\"status\":\"\(status)\",\"title\":\"Land prerequisite\"}"
        } ?? ""
        return """
        {
          "id": "mn-live001",
          "title": "Native Board",
          "title_plain": "Native Board",
          "description": \(encodedDescription),
          "status": "in_progress",
          "effective": "active",
          "kind": "item",
          "order": 0,
          "decision": false,
          "blocked_by": \(blockedBy),
          "blockers": [\(blockers)],
          "dependents": [],
          "claimant": {
            "label": "codex-019f62805fc77093",
            "liveness": "present",
            "attention": "needs-user",
            "runtime": "codex",
            "age": "0s ago",
            "goal": "build Board",
            "pulse": null
          },
          "commits": [{"sha": "abc123", "at": "2026-09-01T16:00:00Z", "subject": "feat: Board"}],
          "claimed_by": "holy-0123456789abcdef",
          "claimed_at": "2026-09-01T15:00:00Z",
          "created_at": "2026-09-01T14:00:00Z",
          "updated_at": "2026-09-01T16:00:00Z",
          "track": "mn-track01",
          "track_title": "Holy cockpit",
          "prompt": ".handoff/live.md",
          "handoff_digest": "sha256:live",
          "handoff_exists": true,
          "source": ".manna/issues.jsonl"
        }
        """
    }
}

struct HolyMannaTrackDecodeRegressionTests {
    // The core emits a synthetic "(no track)" bucket (id: null, status: null)
    // on any board with untracked items; the state decode must survive it.
    @Test func noTrackBucketWithNullIdentityDecodes() throws {
        let json = """
        [{"id": null, "status": null, "title": "(no track)", "items": []},
         {"id": "mn-9a97cc", "status": "open", "title": "TRACK: One Ledger, Two Faces", "items": []}]
        """
        let tracks = try JSONDecoder().decode([HolyMannaTrack].self, from: Data(json.utf8))
        #expect(tracks[0].trackID == nil)
        #expect(tracks[0].status == nil)
        #expect(tracks[0].id == "(no track)")
        #expect(tracks[1].id == "mn-9a97cc")
    }
}
