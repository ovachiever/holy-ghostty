import Foundation
import Testing
@testable import Ghostty

// Stage enrichment (sweep stage_contract 1, spec in
// .dev/session-prompts/11-GH-STAGE-AWARENESS.md). The synthetic builders
// below drive the behavioral matrix; `pinnedLiveFixture` is four rows
// VERBATIM from a live `agent-do gh inbox --json` run on 2026-08-13
// (38 items, stage_contract 1, mn-bbbeac working tree) — the re-pin the
// closing law of mn-1b2271 requires. The mapping itself is engine-owned:
// Holy renders next_action verbatim and never re-derives it.
struct HolyGitHubStageTests {
    static func item(
        author: String = "ovachiever",
        number: Int = 88,
        repo: String = "Versova-Intelligence-Division/vms.io",
        reasons: [String] = ["authored_open"],
        draft: Bool = false,
        nextActionJSON: String = "null"
    ) -> String {
        """
        {
          "author": "\(author)",
          "comments": 0,
          "draft": \(draft),
          "labels": [],
          "number": \(number),
          "reasons": [\(reasons.map { "\"\($0)\"" }.joined(separator: ", "))],
          "ref": "\(repo)#\(number)",
          "repo": "\(repo)",
          "state": "open",
          "title": "PR \(number)",
          "updated_at": "2026-08-13T15:00:00Z",
          "url": "https://github.com/\(repo)/pull/\(number)",
          "review_decision": "APPROVED",
          "merge_state": "CLEAN",
          "checks": {"passed": 3, "failed": 0, "pending": 0, "total": 3},
          "review_requests": 0,
          "next_action": \(nextActionJSON)
        }
        """
    }

    static func payload(_ items: [String]) -> Data {
        Data("""
        {"count": \(items.count), "items": [\(items.joined(separator: ","))],
         "sweep": {"stage_contract": 1}, "total": \(items.count)}
        """.utf8)
    }

    static let mergeAction =
        #"{"verb": "Merge", "detail": "approved, checks green", "yours": true, "command": "agent-do gh merge 88"}"#
    static let awaitingAction =
        #"{"verb": "Awaiting review", "detail": "no review yet", "yours": false, "command": null}"#

    // MARK: - Decode

    @Test func enrichedItemDecodesEveryStageField() throws {
        let payload = try #require(HolyGitHubInboxPayload.parse(
            Self.payload([Self.item(nextActionJSON: Self.mergeAction)])
        ))
        let item = try #require(payload.items.first)
        #expect(item.reviewDecision == "APPROVED")
        #expect(item.mergeState == "CLEAN")
        #expect(item.checks == .init(passed: 3, failed: 0, pending: 0, total: 3))
        #expect(item.reviewRequests == 0)
        #expect(item.nextAction == .init(
            verb: "Merge",
            detail: "approved, checks green",
            yours: true,
            command: "agent-do gh merge 88"
        ))
    }

    @Test func legacyPayloadDecodesWithNilStageFields() throws {
        let payload = try #require(HolyGitHubInboxPayload.parse(
            Data(HolyInboxSourceTests.pinnedFixture.utf8)
        ))
        for item in payload.items {
            #expect(item.nextAction == nil)
            #expect(item.checks == nil)
        }
    }

    @Test func malformedNextActionDegradesTheFieldNotThePayload() throws {
        let payload = try #require(HolyGitHubInboxPayload.parse(
            Self.payload([Self.item(nextActionJSON: #"{"verb": 7}"#)])
        ))
        #expect(payload.items.first?.nextAction == nil)
    }

    // MARK: - Sectioning

    private func decoded(_ items: [String]) throws -> [HolyGitHubInboxItem] {
        try #require(HolyGitHubInboxPayload.parse(Self.payload(items))).items
    }

    @Test func stageModeSplitsByWhoseMoveAndBadgesOnlyYours() throws {
        let sections = HolyGitHubInboxSectioner.sections(
            items: try decoded([
                Self.item(number: 88, nextActionJSON: Self.mergeAction),
                Self.item(number: 89, nextActionJSON: Self.awaitingAction),
            ]),
            focusedRepoSlug: nil
        )

        #expect(sections.map(\.id) == ["gh.your_move", "gh.waiting"])
        let yourMove = try #require(sections.first)
        #expect(yourMove.title == "Your move")
        #expect(yourMove.countsTowardBadge)
        #expect(yourMove.rows.first?.stage == .init(
            verb: "Merge", detail: "approved, checks green", yours: true
        ))
        let waiting = sections[1]
        #expect(!waiting.countsTowardBadge)
        #expect(waiting.collapsedByDefault)
    }

    @Test func legacySweepKeepsReasonSections() throws {
        let sections = HolyGitHubInboxSectioner.sections(
            items: try decoded([
                Self.item(number: 90, reasons: ["review_requested"]),
            ]),
            focusedRepoSlug: nil
        )
        #expect(sections.map(\.id) == ["gh.review"])
        #expect(sections.first?.rows.first?.stage == nil)
    }

    @Test func stageRestatedReasonChipsAreSuppressed() throws {
        let reviewAction =
            #"{"verb": "Review", "detail": "your review requested", "yours": true, "command": "agent-do gh pr 91"}"#
        let sections = HolyGitHubInboxSectioner.sections(
            items: try decoded([
                Self.item(
                    author: "ctyrrell-versova",
                    number: 91,
                    reasons: ["review_requested"],
                    nextActionJSON: reviewAction
                ),
            ]),
            focusedRepoSlug: nil
        )
        let row = try #require(sections.first?.rows.first)
        #expect(row.chips.isEmpty)
        #expect(row.stage?.verb == "Review")
    }

    // MARK: - Loaded command

    @Test func commandSpawnsOnlyWithAnHonestWorkingDirectory() throws {
        let items = try decoded([Self.item(nextActionJSON: Self.mergeAction)])

        let focused = HolyGitHubInboxSectioner.sections(
            items: items,
            focusedRepoSlug: "Versova-Intelligence-Division/vms.io",
            focusedRepoPath: "/Users/erik/Custom-Coding/vms.io"
        )
        let url = try #require(focused.first?.rows.first?.commandSpawnURL)
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.contains(.init(name: "initialInput", value: "agent-do gh merge 88")))
        #expect(query.contains(.init(
            name: "workingDirectory", value: "/Users/erik/Custom-Coding/vms.io"
        )))

        let elsewhere = HolyGitHubInboxSectioner.sections(
            items: items,
            focusedRepoSlug: "ovachiever/agent-do",
            focusedRepoPath: "/Users/erik/Custom-Coding/agent-do"
        )
        #expect(elsewhere.first?.rows.first?.commandSpawnURL == nil)

        let pathless = HolyGitHubInboxSectioner.sections(
            items: items,
            focusedRepoSlug: "Versova-Intelligence-Division/vms.io"
        )
        #expect(pathless.first?.rows.first?.commandSpawnURL == nil)
    }

    // MARK: - Pinned live capture (2026-08-13)

    static let pinnedLiveFixture = """
    {
      "count": 4,
      "items": [
        {
          "author": "ovachiever",
          "checks": {"failed": 0, "passed": 3, "pending": 0, "total": 3},
          "comments": 3,
          "draft": false,
          "labels": [],
          "merge_state": "CLEAN",
          "next_action": {
            "command": "agent-do gh merge 89",
            "detail": "approved, checks green",
            "verb": "Merge",
            "yours": true
          },
          "number": 89,
          "reasons": ["authored_open"],
          "ref": "Versova-Intelligence-Division/vms.io#89",
          "repo": "Versova-Intelligence-Division/vms.io",
          "review_decision": "APPROVED",
          "review_requests": 0,
          "state": "open",
          "title": "Campaign 03: platform glue — Traction Report, global search, inbox fixes, projects parity, home/directory",
          "updated_at": "2026-08-13T18:49:52Z",
          "url": "https://github.com/Versova-Intelligence-Division/vms.io/pull/89"
        },
        {
          "author": "ctyrrell-versova",
          "checks": {"failed": 0, "passed": 4, "pending": 0, "total": 4},
          "comments": 1,
          "draft": false,
          "labels": [],
          "merge_state": "CLEAN",
          "next_action": {
            "command": "agent-do gh pr 23",
            "detail": "your review requested",
            "verb": "Review",
            "yours": true
          },
          "number": 23,
          "reasons": ["review_requested", "maintainer_review_stale"],
          "ref": "ovachiever/agent-do#23",
          "repo": "ovachiever/agent-do",
          "review_decision": "CHANGES_REQUESTED",
          "review_requests": 1,
          "state": "open",
          "title": "feat(agent-ci): triage verb - deterministic failure classification for failed runs",
          "updated_at": "2026-07-29T17:04:59Z",
          "url": "https://github.com/ovachiever/agent-do/pull/23"
        },
        {
          "author": "ovachiever",
          "checks": {"failed": 0, "passed": 4, "pending": 0, "total": 4},
          "comments": 2,
          "draft": true,
          "labels": [],
          "merge_state": "CLEAN",
          "next_action": {
            "command": null,
            "detail": "still being written",
            "verb": "Draft",
            "yours": false
          },
          "number": 2,
          "reasons": ["authored_open"],
          "ref": "ovachiever/IAMthat.vision#2",
          "repo": "ovachiever/IAMthat.vision",
          "review_decision": null,
          "review_requests": 0,
          "state": "open",
          "title": "fix(security): upgrade Next.js and add CI",
          "updated_at": "2026-07-09T21:15:57Z",
          "url": "https://github.com/ovachiever/IAMthat.vision/pull/2"
        },
        {
          "author": "dependabot",
          "checks": {"failed": 0, "passed": 3, "pending": 0, "total": 3},
          "comments": 1,
          "draft": false,
          "labels": [],
          "merge_state": "CLEAN",
          "next_action": null,
          "number": 94,
          "reasons": ["maintainer_unreviewed", "bot_author"],
          "ref": "Versova-Intelligence-Division/vms.io#94",
          "repo": "Versova-Intelligence-Division/vms.io",
          "review_decision": null,
          "review_requests": 0,
          "state": "open",
          "title": "chore(deps): bump pnpm/action-setup from 6.0.9 to 6.0.10",
          "updated_at": "2026-08-10T22:15:12Z",
          "url": "https://github.com/Versova-Intelligence-Division/vms.io/pull/94"
        }
      ],
      "sweep": {
        "path": "graphql",
        "portfolio": {"patterns": 0, "prs_classified": 0, "repos_swept": 0, "waiting_on_author": 0},
        "prs_classified": 32,
        "repos_swept": 139,
        "skipped_no_role": 0,
        "stage_contract": 1,
        "unswept": [],
        "waiting_on_author": 3
      },
      "total": 38
    }
    """

    @Test func pinnedLiveCaptureDecodesAndSections() throws {
        let payload = try #require(HolyGitHubInboxPayload.parse(
            Data(Self.pinnedLiveFixture.utf8)
        ))
        #expect(payload.items.count == 4)

        let merge = try #require(payload.items.first)
        #expect(merge.reviewDecision == "APPROVED")
        #expect(merge.mergeState == "CLEAN")
        #expect(merge.checks == .init(passed: 3, failed: 0, pending: 0, total: 3))
        #expect(merge.nextAction == .init(
            verb: "Merge",
            detail: "approved, checks green",
            yours: true,
            command: "agent-do gh merge 89"
        ))

        let sections = HolyGitHubInboxSectioner.sections(
            items: payload.items,
            focusedRepoSlug: "Versova-Intelligence-Division/vms.io",
            focusedRepoPath: "/Users/erik/Custom-Coding/vms.io"
        )
        #expect(sections.map(\.id) == ["gh.your_move", "gh.waiting", "gh.bots"])
        let yourMove = try #require(sections.first)
        #expect(yourMove.rows.count == 2)
        #expect(yourMove.rows.first?.stage?.verb == "Merge")
        // The Merge row is in the focused repo: its command loads.
        #expect(yourMove.rows.first?.commandSpawnURL != nil)
        // The Review row is another repo: no honest cwd, no button.
        #expect(yourMove.rows.last?.commandSpawnURL == nil)
    }

    @Test func botRowsStayInTheDigestEvenWhenEnriched() throws {
        let sections = HolyGitHubInboxSectioner.sections(
            items: try decoded([
                Self.item(
                    author: "dependabot[bot]",
                    number: 92,
                    reasons: ["bot_author"],
                    nextActionJSON: Self.awaitingAction
                ),
                Self.item(number: 88, nextActionJSON: Self.mergeAction),
            ]),
            focusedRepoSlug: nil
        )
        #expect(sections.contains { $0.id == "gh.your_move" })
        #expect(sections.contains { $0.id == "gh.bots" })
    }
}
