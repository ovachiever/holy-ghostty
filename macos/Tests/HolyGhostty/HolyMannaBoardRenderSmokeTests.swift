import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Ghostty

/// Draws the board faces offscreen and writes PNGs, so the layout can be
/// looked at without launching the app. With no environment it renders a
/// small fixture; TEST_RUNNER_HOLY_BOARD_RENDER_STATE_JSON and
/// TEST_RUNNER_HOLY_BOARD_RENDER_ESTATE_JSON point it at captured
/// `manna state --json` / `manna estate --json` files, and
/// TEST_RUNNER_HOLY_BOARD_RENDER_DIR chooses where the PNGs land.
struct HolyMannaBoardRenderSmokeTests {
    @Test @MainActor func everyFaceRendersOffscreen() async throws {
        let environment = ProcessInfo.processInfo.environment
        let stateJSON = try environment["HOLY_BOARD_RENDER_STATE_JSON"]
            .map { try String(contentsOfFile: $0, encoding: .utf8) }
            ?? RenderFixtures.state
        let estateJSON = try environment["HOLY_BOARD_RENDER_ESTATE_JSON"]
            .map { try String(contentsOfFile: $0, encoding: .utf8) }
            ?? RenderFixtures.estate
        let outputDirectory = URL(fileURLWithPath: environment["HOLY_BOARD_RENDER_DIR"]
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("holy-board-render").path)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let client = HolyMannaBoardClient { invocation, _ in
            .init(
                stdout: invocation.displayCommand.contains("estate") ? estateJSON : stateJSON,
                stderr: "",
                exitCode: 0
            )
        }
        let store = HolyMannaBoardModeStore(client: client, digestService: RenderDigestStub())
        store.present(context: .init(boardRoot: "/srv/render", remoteHost: "render@example.com"))
        for _ in 0 ..< 400 where store.state == nil {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let state = try #require(store.state)
        // Pick the busiest-looking row so the inspector has something to show.
        store.selectItem(state.now.first?.id ?? state.next.first?.id)
        for _ in 0 ..< 100 where store.isDigestLoading {
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        var written: [String] = []
        // ImageRenderer skips AppKit-backed views (ScrollView, TextField,
        // Menu), so the faces are drawn through a hosting view in a window
        // that is never ordered on screen.
        func render(_ name: String, width: CGFloat = 1480, height: CGFloat = 900) async throws {
            let view = HolyMannaBoardView(store: store, onDismiss: {}, onFocusPeer: { _ in false })
            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
            let window = NSWindow(
                contentRect: hosting.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            // Two turns of the main loop let SwiftUI settle its layout.
            try await Task.sleep(nanoseconds: 150_000_000)
            hosting.layoutSubtreeIfNeeded()
            let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            let url = outputDirectory.appendingPathComponent("\(name).png")
            try png.write(to: url)
            #expect(png.count > 1_000, "\(name) rendered nothing")
            written.append(url.path)
            window.contentView = nil
        }

        try await render("board-live")
        try await render("board-live-wide", width: 2560, height: 1400)
        store.selectFilter(.done)
        try await render("board-done")
        store.selectFilter(.live)
        store.selectSheet(.asks)
        try await render("inbox")
        store.selectSheet(.coordination)
        if let peer = state.peers.first {
            store.selectPeer(peer.agentID)
        }
        try await render("coordination")
        store.selectSheet(.debug)
        try await render("debug")
        store.showEstate()
        try await render("estate")
        store.dismiss()

        print("HOLY_BOARD_RENDER wrote:\n" + written.joined(separator: "\n"))
        #expect(written.count == 7)
    }
}

private actor RenderDigestStub: HolyMannaBoardDigesting {
    func presentations(
        for items: [HolyMannaBoardItem],
        context: HolyMannaBoardContext,
        allowGeneration: Bool
    ) async throws -> [HolyMannaPresentationResult] {
        items.map { item in
            .init(
                itemID: item.id,
                digest: item.digest ?? "Render \(item.titlePlain)",
                summary: item.summary ?? "We're rebuilding the native board so it reads like the web cockpit: one ledger, an inspector, the estate table. Done means Erik's side-by-side pass finds no delta that matters.",
                contentHash: HolyMannaBoardDigestService.contentHash(for: item),
                model: "render-stub",
                wasCached: true
            )
        }
    }
}

private enum RenderFixtures {
    static let state = """
    {
      "success": true,
      "generated_at": "2026-09-02T14:00:00Z",
      "name": "render",
      "root": "/srv/render",
      "total": 4,
      "counts": {"active": 1, "ready": 2, "waiting": 1},
      "status_counts": {"in_progress": 1, "open": 2, "blocked": 1},
      "now": [\(item("mn-cbaf37", "Audit Stage 0 and adjudicate missing provenance protocol layers", "active", "in_progress", 27, blockers: [], attention: "needs-user"))],
      "next": [\(item("mn-90b694", "Add gh issue verbs (create/assign/label/list/close/comment) to gh tool", "ready", "open", 0)), \(item("mn-807f18", "Set up workspace with atomic gh issue claim and canonical branch names", "ready", "open", 1))],
      "waves": [{"wave": 1, "items": [\(item("mn-404dd7", "Run policy engine locally and in CI with scope isolation and self-repair", "waiting", "blocked", 3, blockers: ["mn-90b694", "mn-807f18"]))]}],
      "unlayered": [],
      "dreams": [],
      "decisions": [],
      "tracks": [{"id": "mn-track01", "title": "TRACK: Agentic Work OS", "status": "active", "items": []}],
      "all": [\(item("mn-cbaf37", "Audit Stage 0 and adjudicate missing provenance protocol layers", "active", "in_progress", 27, blockers: [], attention: "needs-user")), \(item("mn-90b694", "Add gh issue verbs (create/assign/label/list/close/comment) to gh tool", "ready", "open", 0)), \(item("mn-807f18", "Set up workspace with atomic gh issue claim and canonical branch names", "ready", "open", 1)), \(item("mn-404dd7", "Run policy engine locally and in CI with scope isolation and self-repair", "waiting", "blocked", 3, blockers: ["mn-90b694", "mn-807f18"])), \(item("mn-0ld001", "Ship the first cut of the estate table", "done", "done", nil))],
      "peers": [{
        "agent_id": "codex-01a02afe94d27b52", "alias": null, "runtime": "codex", "status": "active",
        "attention": "needs-user", "age": "2m ago", "age_seconds": 120, "goal": "adjudicate provenance layers", "mode": "writer",
        "phase": "building", "role": null, "paths": ["tools/agent-gh"], "holding": [{"id": "mn-cbaf37", "title": "Audit Stage 0"}],
        "pulse": {"status": "needs-user", "activity": "waiting", "latest_prompt": "Approve the Stage 1 packet?", "updated_at": "2026-09-02T13:58:00Z", "turns": 12}
      }, {
        "agent_id": "session-76c4ae07f5c1", "alias": null, "runtime": "claude", "status": "active",
        "attention": "working", "age": "10s ago", "age_seconds": 10, "goal": "mn-330752: rebuild native Board presentation", "mode": "writer",
        "phase": "building", "role": null, "paths": ["macos/Sources/HolyGhostty/Board"], "holding": [],
        "pulse": {"status": "working", "activity": "Bash", "latest_prompt": null, "updated_at": "2026-09-02T13:59:50Z", "turns": 40}
      }],
      "attention": {"needs-user": 1, "working": 1},
      "coord": {
        "claims": [{"path": "macos/Sources/HolyGhostty/Board", "owner": "session-76c4ae07f5c1", "owner_alias": null, "owner_status": "active", "reason": "board rebuild", "strength": "soft", "updated_at": "2026-09-02T13:50:00Z", "stale": false, "contended": false}],
        "contention": [],
        "needs": [],
        "drops": [{"path": "macos/Sources/HolyGhostty/Board", "note": "Live-pass finding: decode the envelope first", "owner": "session-17a022e17710", "for": "codex-01a05db1d2107933", "created_at": "2026-09-02T14:01:00Z"}]
      },
      "drift": {"present": true, "source": "reconcile", "count": 2, "generated_at": "2026-09-02T14:00:00Z", "kinds": {"landed_open": 1, "handoff_presentation": 1},
        "findings": [{"kind": "landed_open", "issue_id": "mn-0ld001", "detail": "landed but open", "evidence": "84ccd303d", "proposed_fix": "claim and close"}, {"kind": "handoff_presentation", "issue_id": null, "detail": "filename behind priority", "evidence": null, "proposed_fix": "manna sync"}]},
      "git": {"branch": "main", "head": "84ccd303d", "dirty_paths": 6, "is_repo": true},
      "board": {"board_id": "mb-render", "workflow": "strict", "path": ".manna/issues.jsonl", "handoff_dir": ".handoff", "order_count": 4, "issues_modified_at": "2026-09-02T13:00:00Z"}
    }
    """

    static let estate = """
    {
      "generated_at": "2026-09-02T14:00:00Z",
      "boards": [
        {"name": "agent-do", "root": "/srv/agent-do", "exists": true, "total": 140, "status_counts": {"active": 1, "ready": 30, "blocked": 7, "done": 90}, "dreams": 9, "decisions": 0, "drift_count": 27, "drift_generated_at": null, "latest_update": "2026-09-02T11:50:00Z", "coord": {"attention": {}, "needs_you": 1, "working": 0, "here": 9, "gone": 2}, "slug": "agent-do", "url": "/agent-do"},
        {"name": "holy-ghostty", "root": "/srv/render", "exists": true, "total": 101, "status_counts": {"active": 2, "ready": 51, "blocked": 19, "done": 22}, "dreams": 3, "decisions": 0, "drift_count": 53, "drift_generated_at": null, "latest_update": "2026-09-01T18:19:32Z", "coord": {"attention": {}, "needs_you": 1, "working": 1, "here": 16, "gone": 6}, "slug": "holy-ghostty", "url": "/holy-ghostty"},
        {"name": "substack-writings", "root": "/srv/substack", "exists": true, "total": 3, "status_counts": {"done": 2}, "dreams": 1, "decisions": 0, "drift_count": 0, "drift_generated_at": null, "latest_update": "2026-09-01T04:05:00Z", "coord": {"attention": {}, "needs_you": 0, "working": 0, "here": 9, "gone": 0}, "slug": "substack-writings", "url": "/substack-writings"},
        {"name": "fritsch-food", "root": "/srv/fritsch-food", "exists": false, "total": 0, "status_counts": {}, "dreams": 0, "decisions": 0, "drift_count": 0, "drift_generated_at": null, "latest_update": null, "coord": {"attention": {}, "needs_you": 0, "working": 0, "here": 7, "gone": 0}, "slug": "fritsch-food", "url": "/fritsch-food"}
      ],
      "count": 4,
      "registry": "/Users/erik/.agent-do/manna/serve/boards.json",
      "totals": {"needs_you": 2, "working": 1, "here": 41},
      "building": 0
    }
    """

    static func item(
        _ id: String,
        _ title: String,
        _ effective: String,
        _ status: String,
        _ order: Int?,
        blockers: [String] = [],
        attention: String? = nil
    ) -> String {
        let blockerJSON = blockers.map { "{\"id\":\"\($0)\",\"status\":\"open\",\"title\":\"Blocker \($0)\"}" }.joined(separator: ",")
        let claimant = attention.map {
            "{\"label\":\"codex-01a02afe94d27b52\",\"liveness\":\"present\",\"attention\":\"\($0)\",\"runtime\":\"codex\",\"age\":\"2m ago\",\"goal\":\"adjudicate provenance layers\",\"pulse\":{\"status\":\"\($0)\",\"activity\":\"waiting\",\"latest_prompt\":\"Approve the Stage 1 packet?\",\"updated_at\":\"2026-09-02T13:58:00Z\",\"turns\":12}}"
        } ?? "null"
        return """
        {
          "id": "\(id)", "title": "\(title)", "title_plain": "\(title)",
          "description": "Read-only architecture research using landed Stage 0 as the incumbent baseline. Verify which candidate invariants Stage 0 closes, partially closes, or leaves open.",
          "status": "\(status)", "effective": "\(effective)", "kind": "item",
          "order": \(order.map(String.init) ?? "null"), "decision": false,
          "blocked_by": [\(blockers.map { "\"\($0)\"" }.joined(separator: ","))], "blockers": [\(blockerJSON)], "dependents": [],
          "claimant": \(claimant),
          "commits": [{"sha": "84ccd303d", "at": "2026-09-02T14:24:00Z", "subject": "fix(board): survive the core's synthetic '(no track)' bucket"}],
          "claimed_by": null, "claimed_at": null,
          "created_at": "2026-08-22T19:26:00Z", "updated_at": "2026-08-22T19:42:00Z",
          "track": "mn-track01", "track_title": "TRACK: Agentic Work OS",
          "prompt": ".handoff/mn-cbaf37-research-audit-landed-stage-0.md", "handoff_digest": null, "handoff_exists": true,
          "source": "Erik conversation 2026-08-22; supersedes the unexecuted pre-Stage-0 research prompt"
        }
        """
    }
}
