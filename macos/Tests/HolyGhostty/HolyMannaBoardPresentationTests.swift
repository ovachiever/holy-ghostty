import Foundation
import Testing
@testable import Ghostty

/// The web cockpit's rendering rules (app.js / index.js), checked against
/// the native transcription in HolyMannaBoardPresentation.
struct HolyMannaBoardPresentationTests {
    typealias Present = HolyMannaBoardPresentation

    @Test func stateWordsMatchTheWebLabels() {
        #expect(Present.label("active") == "in progress")
        #expect(Present.label("waiting") == "blocked")
        #expect(Present.label("ready") == "ready")
        #expect(Present.label("in_progress") == "in progress")
        #expect(Present.label(nil) == "")
        #expect(Present.attention("needs-user") == "needs you")
        #expect(Present.attention("gone") == "gone")
    }

    @Test func blockedRowsCarryTheirShortBlockerIdsInRed() throws {
        let blocked = try PresentationFixtures.item(
            id: "mn-404dd7",
            effective: "waiting",
            status: "blocked",
            blockers: ["mn-90b694", "mn-807f18"]
        )
        let cell = Present.stateCell(for: blocked)
        #expect(cell.word == "blocked")
        #expect(cell.keepCase == "90b694, 807f18")
        #expect(cell.cls == "waiting")
        #expect(cell.plain == "blocked · 90b694, 807f18")
        #expect(Present.stripeClass(for: blocked) == "waiting")
    }

    @Test func claimantPulseOverridesTheStateWithNeedsYou() throws {
        let waiting = try PresentationFixtures.item(id: "mn-1", effective: "active", status: "in_progress", claimantAttention: "needs-user")
        let working = try PresentationFixtures.item(id: "mn-2", effective: "active", status: "in_progress", claimantAttention: "working")
        let readyButAsking = try PresentationFixtures.item(id: "mn-3", effective: "ready", status: "open", claimantAttention: "needs-user")

        #expect(Present.needsYou(waiting))
        #expect(Present.stateCell(for: waiting) == .init(word: "needs you", keepCase: nil, cls: "needs-user"))
        #expect(Present.stripeClass(for: waiting) == "needs-user")
        #expect(Present.stateCell(for: working) == .init(word: "in progress", keepCase: nil, cls: "active"))
        // Only an in-progress row can need you; a ready row is nobody's yet.
        #expect(!Present.needsYou(readyButAsking))
    }

    @Test func shortTrackDropsTagsPrefixesAndParentheticals() {
        #expect(Present.shortTrack("[TRACK] Agentic Work OS (program)") == "Agentic Work OS")
        #expect(Present.shortTrack("TRACK: One Ledger, Two Faces — Holy as the AIO agentic surface") == "One Ledger, Two Faces — Holy as the AIO agentic surface")
        #expect(Present.shortTrack("  track : Harness ") == "Harness")
        #expect(Present.shortTrack("Companion / Second Chair") == "Companion / Second Chair")
        #expect(Present.shortTrack(nil) == "")
    }

    @Test func rowTextPrefersTheDigestAndFallsBackToTheTitle() throws {
        let digested = try PresentationFixtures.item(id: "mn-1", title: "Native Board", digest: "Build the ledger view")
        let plain = try PresentationFixtures.item(id: "mn-2", title: "Native Board")
        let blank = try PresentationFixtures.item(id: "mn-3", title: "Native Board", digest: "   ")
        #expect(Present.rowText(digested) == "Build the ledger view")
        #expect(!Present.isFallbackText(digested))
        #expect(Present.rowText(plain) == "Native Board")
        #expect(Present.isFallbackText(plain))
        #expect(Present.rowText(blank) == "Native Board")
        #expect(Present.isFallbackText(blank))
        #expect(Present.priorityText(try PresentationFixtures.item(id: "mn-4", order: 27)) == "#28")
        #expect(Present.priorityText(plain) == "")
    }

    @Test func clipCollapsesWhitespaceAndEndsWithAnEllipsis() {
        #expect(Present.clip("  a   b \n c ", 80) == "a b c")
        #expect(Present.clip("abcdefghij", 5) == "abcd…")
        #expect(Present.clip(nil, 5) == "")
        #expect(Present.shortID("mn-abc123") == "abc123")
        #expect(Present.shortID("codex-1") == "codex-1")
    }

    @Test func grepMatchesAcrossIdTitleDigestTrackClaimantAndDescription() throws {
        let item = try PresentationFixtures.item(
            id: "mn-cbaf37",
            title: "Audit Stage 0",
            description: "Read-only architecture research",
            claimantAttention: "idle",
            claimantLabel: "codex-01a02afe94d27b52",
            track: "mn-track01",
            trackTitle: "Agentic Work OS",
            digest: "Adjudicate provenance layers"
        )
        #expect(Present.matches(item, grep: ""))
        #expect(Present.matches(item, grep: "CBAF37"))
        #expect(Present.matches(item, grep: "stage 0"))
        #expect(Present.matches(item, grep: "provenance"))
        #expect(Present.matches(item, grep: "agentic work"))
        #expect(Present.matches(item, grep: "codex-01a02"))
        #expect(Present.matches(item, grep: "read-only"))
        #expect(!Present.matches(item, grep: "harness"))

        #expect(Present.trackMatches(item, track: nil))
        #expect(Present.trackMatches(item, track: ""))
        #expect(Present.trackMatches(item, track: "mn-track01"))
        #expect(!Present.trackMatches(item, track: "mn-other"))
        #expect(!Present.trackMatches(item, track: Present.untrackedFilter))
        let untracked = try PresentationFixtures.item(id: "mn-1")
        #expect(Present.trackMatches(untracked, track: Present.untrackedFilter))
    }

    @Test func liveFilterIsOneContinuousScrollOfNowNextWaiting() throws {
        let state = try PresentationFixtures.state()
        let live = Present.sections(state: state, filter: .live, track: nil, grep: "")
        #expect(live.map(\.prompt) == ["manna now", "manna next", "manna waiting"])
        #expect(live[0].items.map(\.id) == ["mn-now1"])
        #expect(live[1].items.map(\.id) == ["mn-next1", "mn-next2"])
        // Waiting flattens every wave and then the unlayered rows.
        #expect(live[2].items.map(\.id) == ["mn-wave1a", "mn-wave2a", "mn-unlayered"])
        #expect(live.map(\.emptyText) == ["nothing claimed", "nothing is ready", "nothing is blocked"])
        #expect(live.allSatisfy { !$0.showsAge })
    }

    @Test func doneRecentAndDreamsReadTheWholeBoard() throws {
        let state = try PresentationFixtures.state()
        let done = Present.sections(state: state, filter: .done, track: nil, grep: "")
        #expect(done.map(\.prompt) == ["manna done"])
        #expect(done[0].items.map(\.id) == ["mn-done-new", "mn-done-old"])
        #expect(done[0].emptyText == "nothing done yet")

        let recent = Present.sections(state: state, filter: .recent, track: nil, grep: "")
        #expect(recent[0].showsAge)
        #expect(recent[0].items.first?.id == "mn-done-new")
        #expect(recent[0].items.count == state.all.count)

        let dreams = Present.sections(state: state, filter: .dreams, track: nil, grep: "")
        #expect(dreams.map(\.prompt) == ["manna dreams"])
        #expect(dreams[0].items.map(\.id) == ["mn-dream1"])

        let all = Present.sections(state: state, filter: .all, track: nil, grep: "")
        #expect(all.map(\.id) == ["now", "next", "waiting", "dreams", "done"])

        let grepped = Present.sections(state: state, filter: .live, track: nil, grep: "next2")
        #expect(grepped[1].items.map(\.id) == ["mn-next2"])
        #expect(grepped[0].items.isEmpty)
        let tracked = Present.sections(state: state, filter: .live, track: "mn-track01", grep: "")
        #expect(tracked.flatMap(\.items).map(\.id) == ["mn-now1"])
    }

    @Test func inboxRowsAreRankedByVerbAndColoredByKind() throws {
        let state = try PresentationFixtures.state()
        let rows = Present.inboxRows(state: state, grep: "")
        #expect(rows.map(\.verb) == ["grant", "close", "read", "launch"])
        #expect(rows.map(\.kind) == ["peer", "landed", "drop", "ready"])
        #expect(rows.map(\.cls) == ["needs-user", "decision", "muted", "ready"])
        #expect(rows[0].text == "codex-peer · “Approve the final action”")
        #expect(rows[1].text.hasSuffix(" · landed in abc123, still open"))
        #expect(rows[2].text == ".handoff/live.md · ready · from codex-peer")
        #expect(rows[3].text == "Next one · priority #1")
        #expect(Present.inboxRows(state: state, grep: "landed").map(\.verb) == ["close"])
        #expect(Present.kindLabel("document") == "doc")
        #expect(Present.kindLabel("repair") == "repairs")
        #expect(Present.kindLabel("failed") == "peer")
    }

    @Test func datesRenderLikeThePage() throws {
        let chicago = try #require(TimeZone(identifier: "America/Chicago"))
        #expect(Present.formatDate("2026-09-02T11:50:00Z", timeZone: chicago) == "Sep 2, 6:50 AM")
        #expect(Present.formatDate("2026-09-01T18:19:32.703098Z", timeZone: chicago) == "Sep 1, 1:19 PM")
        #expect(Present.formatDate("2026-09-02T09:24:00-05:00", timeZone: chicago) == "Sep 2, 9:24 AM")
        #expect(Present.formatDate(nil) == "—")
        #expect(Present.formatDate("") == "—")
        #expect(Present.formatDate("yesterday") == "yesterday")

        let now = try #require(Present.parseDate("2026-09-02T12:00:00Z"))
        #expect(Present.ago("2026-09-02T11:59:40Z", now: now) == "now")
        #expect(Present.ago("2026-09-02T11:55:00Z", now: now) == "5m")
        #expect(Present.ago("2026-09-02T09:00:00Z", now: now) == "3h")
        #expect(Present.ago("2026-08-23T12:00:00Z", now: now) == "10d")
        #expect(Present.ago(nil, now: now) == "never")

        #expect(Present.updatedLabel(since: nil) == "waiting for state")
        #expect(Present.updatedLabel(since: now.addingTimeInterval(-1), now: now) == "updated now")
        #expect(Present.updatedLabel(since: now.addingTimeInterval(-5), now: now) == "updated 5s ago")
        #expect(Present.updatedLabel(since: now.addingTimeInterval(-125), now: now) == "updated 2m ago")
    }

    @Test func estateRowsFollowServeOrderAndCellsAreHonest() throws {
        let quiet = try PresentationFixtures.board(name: "quiet", needsYou: 0, working: 0, latestUpdate: "2026-09-02T10:00:00Z")
        let asking = try PresentationFixtures.board(name: "asking", needsYou: 1, working: 0, latestUpdate: "2026-08-01T10:00:00Z")
        let busy = try PresentationFixtures.board(name: "busy", needsYou: 0, working: 2, latestUpdate: "2026-08-15T10:00:00Z")
        let fresher = try PresentationFixtures.board(name: "fresher", needsYou: 0, working: 0, latestUpdate: "2026-09-02T11:00:00Z")
        let missing = try PresentationFixtures.board(name: "missing", needsYou: 0, working: 0, latestUpdate: "2026-09-03T00:00:00Z", exists: false)

        let ordered = Present.estateRows([quiet, missing, asking, fresher, busy])
        #expect(ordered.map(\.name) == ["asking", "busy", "fresher", "quiet", "missing"])

        #expect(Present.estateCellText(nil) == "…")
        #expect(Present.estateCellText(0) == "·")
        #expect(Present.estateCellText(27) == "27")
        // status_counts is a census: an absent key on a living board is zero.
        #expect(Present.estateStatusCount(quiet, "blocked") == 0)
        #expect(Present.estateStatusCount(quiet, "active", "in_progress") == 2)
        #expect(Present.estateStatusCount(missing, "active") == nil)

        // Count columns fit their widest cell (floored by the header); the
        // date column fits its widest date.
        let widths = Present.estateColumns(for: [quiet, missing])
        #expect(widths.needsYou >= HolyMannaBoardMetrics.columnWidth(contentCharacters: 1, headerCharacters: "needs you".count))
        #expect(widths.updated >= HolyMannaBoardMetrics.columnWidth(contentCharacters: "Sep 2, 10:00 AM".count, headerCharacters: "updated".count))
        #expect(widths.here > widths.done || widths.here == widths.done)
    }

    @Test func fixedColumnsFitTheirWidestCellAndNeverCollapseUnderTheirHeader() throws {
        let short = try PresentationFixtures.item(id: "mn-1", order: 0)
        let wide = try PresentationFixtures.item(
            id: "mn-404dd7",
            effective: "waiting",
            status: "blocked",
            blockers: ["mn-90b694", "mn-807f18", "mn-d2d67b"],
            trackTitle: "A very long track title that goes past thirty characters",
            order: 101
        )
        let advance = HolyMannaBoardMetrics.charAdvance
        #expect(advance > 0)
        let narrow = Present.boardColumns(for: [short], showsAge: false)
        let broad = Present.boardColumns(for: [short, wide], showsAge: false)
        #expect(broad.id > narrow.id)
        #expect(broad.state > narrow.state)
        #expect(broad.track > narrow.track)
        // Clipped at the page's ceilings; the full text rides the tooltip.
        #expect(broad.track <= HolyMannaBoardMetrics.columnWidth(contentCharacters: HolyMannaBoardMetrics.trackColumnMaxCharacters, headerCharacters: 5))
        #expect(broad.state <= HolyMannaBoardMetrics.columnWidth(contentCharacters: HolyMannaBoardMetrics.stateColumnMaxCharacters, headerCharacters: 5, tracked: true))
        // The header is the floor: an empty column never collapses.
        let empty = Present.boardColumns(for: [], showsAge: false)
        #expect(empty.track >= CGFloat("track".count) * advance)
        #expect(HolyMannaBoardMetrics.columnWidth(contentCharacters: 0, headerCharacters: 2) > 0)
    }

    @Test func connectionWordsAreHonest() {
        #expect(Present.connectionLabel(isLive: true, isRefreshing: false, hasState: true, failed: false) == "live")
        #expect(Present.connectionLabel(isLive: false, isRefreshing: true, hasState: false, failed: false) == "reading")
        #expect(Present.connectionLabel(isLive: false, isRefreshing: false, hasState: true, failed: true) == "stale")
        #expect(Present.connectionLabel(isLive: false, isRefreshing: false, hasState: true, failed: false) == "paused")
    }
}

private enum PresentationFixtures {
    static func item(
        id: String,
        title: String = "Row",
        effective: String = "ready",
        status: String = "open",
        description: String? = nil,
        blockers: [String] = [],
        claimantAttention: String? = nil,
        claimantLabel: String = "codex-peer",
        track: String? = nil,
        trackTitle: String? = nil,
        order: Int? = nil,
        updatedAt: String = "2026-09-01T16:00:00Z",
        digest: String? = nil,
        kind: String = "item"
    ) throws -> HolyMannaBoardItem {
        try JSONDecoder().decode(
            HolyMannaBoardItem.self,
            from: Data(itemJSON(
                id: id, title: title, effective: effective, status: status, description: description,
                blockers: blockers, claimantAttention: claimantAttention, claimantLabel: claimantLabel,
                track: track, trackTitle: trackTitle, order: order, updatedAt: updatedAt, digest: digest, kind: kind
            ).utf8)
        )
    }

    static func itemJSON(
        id: String,
        title: String = "Row",
        effective: String = "ready",
        status: String = "open",
        description: String? = nil,
        blockers: [String] = [],
        claimantAttention: String? = nil,
        claimantLabel: String = "codex-peer",
        track: String? = nil,
        trackTitle: String? = nil,
        order: Int? = nil,
        updatedAt: String = "2026-09-01T16:00:00Z",
        digest: String? = nil,
        kind: String = "item"
    ) -> String {
        func quoted(_ value: String?) -> String {
            guard let value else { return "null" }
            let data = (try? JSONEncoder().encode(value)) ?? Data("\"\"".utf8)
            return String(bytes: data, encoding: .utf8) ?? "\"\""
        }
        let blockerJSON = blockers.map { "{\"id\":\"\($0)\",\"status\":\"open\",\"title\":\"Blocker \($0)\"}" }.joined(separator: ",")
        let claimant = claimantAttention.map {
            "{\"label\":\(quoted(claimantLabel)),\"liveness\":\"present\",\"attention\":\"\($0)\",\"runtime\":\"codex\",\"age\":\"1m ago\",\"goal\":null,\"pulse\":null}"
        } ?? "null"
        return """
        {
          "id": \(quoted(id)),
          "title": \(quoted(title)),
          "title_plain": \(quoted(title)),
          "description": \(quoted(description)),
          "status": \(quoted(status)),
          "effective": \(quoted(effective)),
          "kind": \(quoted(kind)),
          "order": \(order.map(String.init) ?? "null"),
          "decision": false,
          "blocked_by": [\(blockers.map { "\"\($0)\"" }.joined(separator: ","))],
          "blockers": [\(blockerJSON)],
          "dependents": [],
          "claimant": \(claimant),
          "commits": [],
          "claimed_by": null,
          "claimed_at": null,
          "created_at": "2026-08-22T14:26:00Z",
          "updated_at": \(quoted(updatedAt)),
          "track": \(quoted(track)),
          "track_title": \(quoted(trackTitle)),
          "prompt": null,
          "handoff_digest": null,
          "handoff_exists": null,
          "source": null,
          "digest": \(quoted(digest))
        }
        """
    }

    static func state() throws -> HolyMannaStatePayload {
        let now = itemJSON(id: "mn-now1", title: "Now one", effective: "active", status: "in_progress", track: "mn-track01", trackTitle: "Holy cockpit", order: 5, updatedAt: "2026-09-01T12:00:00Z")
        let next1 = itemJSON(id: "mn-next1", title: "Next one", order: 0, updatedAt: "2026-09-01T11:00:00Z")
        let next2 = itemJSON(id: "mn-next2", title: "Next two", order: 1, updatedAt: "2026-09-01T10:00:00Z")
        let wave1 = itemJSON(id: "mn-wave1a", effective: "waiting", status: "blocked", blockers: ["mn-next1"], updatedAt: "2026-09-01T09:00:00Z")
        let wave2 = itemJSON(id: "mn-wave2a", effective: "waiting", status: "blocked", blockers: ["mn-wave1a"], updatedAt: "2026-09-01T08:00:00Z")
        let unlayered = itemJSON(id: "mn-unlayered", effective: "waiting", status: "blocked", blockers: ["mn-ghost"], updatedAt: "2026-09-01T07:00:00Z")
        let dream = itemJSON(id: "mn-dream1", title: "A dream", effective: "dream", status: "open", updatedAt: "2026-08-30T07:00:00Z", kind: "dream")
        let doneNew = itemJSON(id: "mn-done-new", title: "Done recently", effective: "done", status: "done", updatedAt: "2026-09-02T07:00:00Z")
        let doneOld = itemJSON(id: "mn-done-old", title: "Done long ago", effective: "done", status: "done", updatedAt: "2026-08-01T07:00:00Z")
        let json = """
        {
          "success": true,
          "generated_at": "2026-09-02T12:00:00Z",
          "name": "fixture",
          "root": "/srv/fixture",
          "total": 9,
          "counts": {},
          "status_counts": {},
          "now": [\(now)],
          "next": [\(next1), \(next2)],
          "waves": [{"wave": 1, "items": [\(wave1)]}, {"wave": 2, "items": [\(wave2)]}],
          "unlayered": [\(unlayered)],
          "dreams": [\(dream)],
          "decisions": [],
          "tracks": [{"id": "mn-track01", "title": "Holy cockpit", "status": "active", "items": []}],
          "all": [\(now), \(next1), \(next2), \(wave1), \(wave2), \(unlayered), \(dream), \(doneNew), \(doneOld)],
          "peers": [{
            "agent_id": "codex-peer", "alias": null, "runtime": "codex", "status": "active",
            "attention": "needs-user", "age": "0s ago", "age_seconds": 0, "goal": "build", "mode": "writer",
            "phase": "building", "role": null, "paths": [], "holding": [],
            "pulse": {"status": "needs-user", "activity": "waiting", "latest_prompt": "Approve the final action", "updated_at": "2026-09-02T12:00:00Z", "turns": 1}
          }],
          "attention": {"needs-user": 1},
          "coord": {
            "claims": [], "contention": [], "needs": [],
            "drops": [{"path": ".handoff/live.md", "note": "ready", "owner": "codex-peer", "for": "any", "created_at": "2026-09-02T11:00:00Z"}]
          },
          "drift": {
            "present": true, "source": "reconcile", "count": 1, "generated_at": "2026-09-02T12:00:00Z",
            "kinds": {"landed_open": 1},
            "findings": [{"kind": "landed_open", "issue_id": "mn-now1", "detail": "landed but open", "evidence": "abc123", "proposed_fix": "close"}]
          },
          "git": {"branch": "main", "head": "abc123", "dirty_paths": 0, "is_repo": true},
          "board": {"board_id": "mb-fixture", "workflow": "strict", "path": ".manna/issues.jsonl", "handoff_dir": ".handoff", "order_count": 3, "issues_modified_at": "2026-09-02T12:00:00Z"}
        }
        """
        return try JSONDecoder().decode(HolyMannaStatePayload.self, from: Data(json.utf8))
    }

    static func board(
        name: String,
        needsYou: Int,
        working: Int,
        latestUpdate: String,
        exists: Bool = true
    ) throws -> HolyMannaEstateBoard {
        let json = """
        {
          "name": "\(name)", "root": "/srv/\(name)", "exists": \(exists), "total": 3,
          "status_counts": {"active": 2, "ready": 1},
          "dreams": 0, "decisions": 0, "drift_count": 0, "drift_generated_at": null,
          "latest_update": "\(latestUpdate)",
          "coord": {"attention": {}, "needs_you": \(needsYou), "working": \(working), "here": 1, "gone": 0},
          "slug": "\(name)", "url": "/\(name)"
        }
        """
        return try JSONDecoder().decode(HolyMannaEstateBoard.self, from: Data(json.utf8))
    }
}
