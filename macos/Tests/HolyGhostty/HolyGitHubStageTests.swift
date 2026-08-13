import Foundation
import Testing
@testable import Ghostty

// Stage enrichment (sweep stage_contract 1). Fixture below is pinned from
// the SPEC in .dev/session-prompts/11-GH-STAGE-AWARENESS.md; the closing
// law of mn-1b2271 requires re-pinning it from a live `gh inbox --json`
// run once the agent-do side (mn-bbbeac) lands. The mapping itself is
// engine-owned: Holy renders next_action verbatim and never re-derives it.
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
