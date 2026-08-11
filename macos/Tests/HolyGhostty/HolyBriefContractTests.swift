import Foundation
import Testing
@testable import Ghostty

// The brief holy contract, version 1, pinned from the live capture of
// 2026-08-11 (.dev/brief-holy-capture-2026-08-11.json). The inline fixture
// reproduces its exact key set; the live-file test re-verifies the real
// capture whenever it is present on disk.
struct HolyBriefContractTests {
    /// A trimmed but shape-faithful contract-1 payload: one attention
    /// thread (synthetic — the capture's degraded morning had none), one
    /// calm session thread, two suggestions, a degraded source.
    static let fixture = """
    {
      "annotations": [
        {"kind": "source", "reason": "timeout after 15.0s: agent-gh inbox --json", "source": "github", "status": "degraded"}
      ],
      "caller": {"focused_board": "/tmp/repo", "focused_repo": "ovachiever/holy-ghostty", "peek": false, "since": null},
      "contract": 1,
      "delta": {"count": 1, "mode": "read_state", "since": "2026-08-11T15:55:55Z", "thread_ids": ["session-aaaa"]},
      "generated_at": "2026-08-11T15:56:29Z",
      "paragraph": {"mode": "model", "model": "anthropic/claude-haiku-4-5-20251001", "receipts": ["r1"], "text": "One PR waits on you [r1]. Nothing else moved [r2, r3]."},
      "ranking": {"journal_observations": 0, "mode": "heuristic"},
      "read_state": {"last_brief_at": "2026-08-11T15:56:29Z", "pins": 0, "snoozes": 0},
      "receipts": {
        "r1": {"detail": "review requested", "kind": "github", "ref": "ovachiever/agent-do#23"}
      },
      "sources": {
        "coord": {"fetched_at": "2026-08-11T15:56:11Z", "origin": "live", "status": "ok"},
        "github": {"fetched_at": "2026-08-11T15:56:26Z", "origin": "live", "reason": "timeout after 15.0s", "status": "degraded"}
      },
      "suggestions": [
        {"argv": ["agent-do", "manna", "done", "mn-9a6145"], "command": "agent-do manna done mn-9a6145", "id": "s1", "issue_id": "mn-9a6145", "kind": "landed_open", "label": "Close mn-9a6145", "receipts": ["r1"]},
        {"argv": ["agent-do", "manna", "show", "mn-569b91"], "command": "agent-do manna show mn-569b91", "id": "s2", "issue_id": "mn-569b91", "kind": "blocker_desync", "label": "remove resolved blockers", "receipts": ["r1"]}
      ],
      "suggestions_total": 2,
      "threads": [
        {"claimable": false, "fingerprint": "aa", "id": "pr-agent-do-23", "kind": "pr", "last_commit": null, "manna": null, "needs_me": true, "pinned": false, "pr": {"number": 23}, "rank": {"reasons": ["review requested (+2.00)"], "score": 2.0}, "receipts": ["r1"], "session": null, "snoozed": false, "title": "Review agent-ci triage verb", "updated_at": "2026-08-11T15:00:00Z", "why": []},
        {"claimable": false, "fingerprint": "bb", "id": "session-aaaa", "kind": "session", "last_commit": null, "manna": null, "needs_me": false, "pinned": false, "pr": null, "rank": {"reasons": ["updated 0h ago (+1.00)"], "score": 1.0}, "receipts": [], "session": {"agent_id": "session-aaaa", "goal": "build the panel", "last_seen": "2026-08-11T15:56:11Z", "phase": "building", "status": "active"}, "snoozed": false, "title": "build the panel", "updated_at": "2026-08-11T15:56:11Z", "why": []}
      ],
      "threads_total": 4
    }
    """

    @Test func contractOneParsesWithEveryPinnedField() throws {
        let payload = try #require(HolyBriefPayload.parse(Data(Self.fixture.utf8)))
        #expect(payload.contract == 1)
        #expect(payload.paragraph.mode == "model")
        #expect(payload.threads.count == 2)
        #expect(payload.threadsTotal == 4)
        #expect(payload.suggestions.count == 2)
        #expect(payload.delta.threadIDs == ["session-aaaa"])
        #expect(payload.sources["github"]?.status == "degraded")
        #expect(payload.receipts["r1"]?.ref == "ovachiever/agent-do#23")
        #expect(payload.caller?.focusedRepo == "ovachiever/holy-ghostty")

        let pr = payload.threads[0]
        #expect(pr.needsMe)
        #expect(pr.hasPR)
        #expect(!pr.hasManna)
        let session = payload.threads[1]
        #expect(session.session?.goal == "build the panel")
        #expect(!session.hasPR)
    }

    @Test func unknownContractVersionFailsClosed() {
        let bumped = Self.fixture.replacingOccurrences(
            of: "\"contract\": 1",
            with: "\"contract\": 2"
        )
        #expect(HolyBriefPayload.parse(Data(bumped.utf8)) == nil)
    }

    @Test func missingTopLevelKeyFailsClosed() {
        let broken = Self.fixture.replacingOccurrences(
            of: "\"threads_total\": 4",
            with: "\"threads_totally\": 4"
        )
        #expect(HolyBriefPayload.parse(Data(broken.utf8)) == nil)
    }

    /// The real capture stays parseable for as long as it sits in .dev —
    /// the canonical drift alarm between engine and renderer.
    @Test func liveCaptureParsesWhenPresent() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/HolyGhostty
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // macos
            .appendingPathComponent(".dev/brief-holy-capture-2026-08-11.json")
        guard let data = try? Data(contentsOf: url) else { return }
        let payload = try #require(HolyBriefPayload.parse(data))
        #expect(payload.contract == 1)
        #expect(payload.suggestionsTotal == 16)
    }
}

// The row law and the covenant fences, as pure functions.
struct HolyBriefTriageTests {
    private func payload() throws -> HolyBriefPayload {
        try #require(HolyBriefPayload.parse(Data(HolyBriefContractTests.fixture.utf8)))
    }

    @Test func needsMeThreadsLeadAndCalmThreadsStayOut() throws {
        let triaged = HolyBriefTriage.triage(try payload())
        #expect(triaged.hero?.id == "pr-agent-do-23")
        #expect(triaged.needsMe.isEmpty)
        // The calm session moved since last look: activity, not attention.
        #expect(triaged.activity.map(\.id) == ["session-aaaa"])
        // threads_total 4 minus 1 attention minus 1 activity.
        #expect(triaged.libraryThreadCount == 2)
    }

    @Test func suggestionsGroupByKindInArrivalOrder() throws {
        let triaged = HolyBriefTriage.triage(try payload())
        #expect(triaged.suggestionGroups.map(\.kind) == ["landed_open", "blocker_desync"])
        #expect(triaged.suggestionGroups[0].title == "Landed, still open")
    }

    @Test func degradedSourcesBecomeNotesNeverRows() throws {
        let triaged = HolyBriefTriage.triage(try payload())
        #expect(triaged.sourceNotes.map(\.source) == ["github"])
        #expect(triaged.sourceNotes[0].reason.contains("timeout"))
    }

    @Test func snoozedThreadsNeverReachTheAttentionDrawer() throws {
        let snoozed = HolyBriefContractTests.fixture.replacingOccurrences(
            of: "\"needs_me\": true, \"pinned\": false, \"pr\": {\"number\": 23}, \"rank\": {\"reasons\": [\"review requested (+2.00)\"], \"score\": 2.0}, \"receipts\": [\"r1\"], \"session\": null, \"snoozed\": false",
            with: "\"needs_me\": true, \"pinned\": false, \"pr\": {\"number\": 23}, \"rank\": {\"reasons\": [\"review requested (+2.00)\"], \"score\": 2.0}, \"receipts\": [\"r1\"], \"session\": null, \"snoozed\": true"
        )
        let payload = try #require(HolyBriefPayload.parse(Data(snoozed.utf8)))
        let triaged = HolyBriefTriage.triage(payload)
        #expect(triaged.hero == nil)
    }

    // MARK: Covenant fences

    @Test func typedCommandsLoseEveryControlCharacter() {
        #expect(HolyBriefTriage.typeableCommand("agent-do manna done mn-1\n") == "agent-do manna done mn-1")
        #expect(HolyBriefTriage.typeableCommand("evil\r\nrm -rf ~") == "evilrm -rf ~")
        #expect(HolyBriefTriage.typeableCommand("tab\there") == "tabhere")
        #expect(HolyBriefTriage.typeableCommand("  spaced  ") == "spaced")
    }

    @Test func spawnURLTypesTheCommandWithoutANewline() throws {
        let url = try #require(HolyBriefSpawn.typedCommandURL(
            command: "agent-do manna done mn-9a6145\n",
            title: "brief · mn-9a6145",
            workingDirectory: "/tmp/repo"
        ))
        let spec = try #require(HolyAutomationURLParser.launchSpec(from: url))
        #expect(spec.initialInput == "agent-do manna done mn-9a6145")
        #expect(spec.command == nil)
        #expect(spec.workingDirectory == "/tmp/repo")
        #expect(spec.runtime == .shell)
    }

    @Test func askURLShellQuotesTheQuestion() throws {
        let url = try #require(HolyBriefSpawn.askURL(
            question: "what's stuck in aldebaran?",
            workingDirectory: nil
        ))
        let spec = try #require(HolyAutomationURLParser.launchSpec(from: url))
        #expect(spec.initialInput == "agent-do brief ask 'what'\"'\"'s stuck in aldebaran?'")
        #expect(spec.command == nil)
    }

    // MARK: Paragraph citations

    @Test func citationRunsSplitFromProse() {
        let runs = HolyBriefTriage.paragraphRuns("One PR waits [r1]. Done [r2, r3].")
        #expect(runs == [
            .text("One PR waits "),
            .citation("[r1]"),
            .text(". Done "),
            .citation("[r2, r3]"),
            .text("."),
        ])
    }

    @Test func bracketedProseIsNotACitation() {
        let runs = HolyBriefTriage.paragraphRuns("See [the docs] now")
        #expect(runs.allSatisfy {
            if case .citation = $0 { return false }
            return true
        })
    }
}
