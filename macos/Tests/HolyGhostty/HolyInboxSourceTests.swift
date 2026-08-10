import Foundation
import Testing
@testable import Ghostty

// The `agent-do gh inbox --json` contract is pinned from a live invocation on
// 2026-08-03 (this machine, this session): top-level {count, items, sweep,
// total}; each item carries author, comments, draft, labels, number, reasons
// (string array), ref ("org/repo#n"), repo ("org/repo"), state, title,
// updated_at (ISO8601 Z), url (full PR URL). The decoder must read every item
// field, tolerate the top-level keys it does not use, and collapse malformed
// payloads into nil so the source degrades instead of guessing.
struct HolyInboxSourceTests {
    /// Two items verbatim from the live 2026-08-03 run (titles shortened),
    /// plus the live top-level `sweep`/`total` keys the decoder must ignore.
    static let pinnedFixture = """
    {
      "count": 2,
      "items": [
        {
          "author": "ctyrrell-versova",
          "comments": 1,
          "draft": true,
          "labels": [],
          "number": 19,
          "reasons": ["review_requested", "maintainer_unreviewed"],
          "ref": "Versova-Intelligence-Division/versova-research#19",
          "repo": "Versova-Intelligence-Division/versova-research",
          "state": "open",
          "title": "release: promote staging to main",
          "updated_at": "2026-08-03T20:42:21Z",
          "url": "https://github.com/Versova-Intelligence-Division/versova-research/pull/19"
        },
        {
          "author": "ovachiever",
          "comments": 3,
          "draft": false,
          "labels": ["enhancement"],
          "number": 88,
          "reasons": ["authored_open"],
          "ref": "Versova-Intelligence-Division/vms.io#88",
          "repo": "Versova-Intelligence-Division/vms.io",
          "state": "open",
          "title": "Campaign 06: connected automation",
          "updated_at": "2026-08-03T19:35:11Z",
          "url": "https://github.com/Versova-Intelligence-Division/vms.io/pull/88"
        }
      ],
      "sweep": {
        "portfolio": {"patterns": 0, "prs_classified": 0, "repos_swept": 0, "waiting_on_author": 0},
        "prs_classified": 50,
        "repos_swept": 139,
        "unswept": [],
        "waiting_on_author": 3
      },
      "total": 55
    }
    """

    @Test func pinnedFixtureDecodesEveryItemField() throws {
        let payload = try #require(
            HolyGitHubInboxPayload.parse(Data(Self.pinnedFixture.utf8))
        )

        #expect(payload.count == 2)
        #expect(payload.items.count == 2)

        let first = payload.items[0]
        #expect(first.author == "ctyrrell-versova")
        #expect(first.comments == 1)
        #expect(first.draft == true)
        #expect(first.labels.isEmpty)
        #expect(first.number == 19)
        #expect(first.reasons == ["review_requested", "maintainer_unreviewed"])
        #expect(first.ref == "Versova-Intelligence-Division/versova-research#19")
        #expect(first.repo == "Versova-Intelligence-Division/versova-research")
        #expect(first.state == "open")
        #expect(first.title == "release: promote staging to main")
        #expect(first.url == "https://github.com/Versova-Intelligence-Division/versova-research/pull/19")

        let expectedDate = ISO8601DateFormatter().date(from: "2026-08-03T20:42:21Z")
        #expect(first.updatedAt == expectedDate)

        let second = payload.items[1]
        #expect(second.draft == false)
        #expect(second.labels == ["enhancement"])
        #expect(second.reasons == ["authored_open"])
    }

    @Test func malformedPayloadParsesToNil() {
        #expect(HolyGitHubInboxPayload.parse(Data("not json".utf8)) == nil)
        #expect(HolyGitHubInboxPayload.parse(Data("{\"items\": 4}".utf8)) == nil)
        #expect(HolyGitHubInboxPayload.parse(Data()) == nil)
    }

    @Test func unknownLabelShapesDegradeToEmptyLabelsNotFailure() throws {
        // Labels were `[]` in every live row; if the CLI ever ships label
        // objects instead of strings, the row must survive without them.
        let json = """
        {"count": 1, "items": [{
          "author": "a", "comments": 0, "draft": false,
          "labels": [{"name": "bug"}], "number": 1,
          "reasons": ["authored_open"], "ref": "o/r#1", "repo": "o/r",
          "state": "open", "title": "t",
          "updated_at": "2026-08-03T00:00:00Z", "url": "https://github.com/o/r/pull/1"
        }]}
        """
        let payload = try #require(HolyGitHubInboxPayload.parse(Data(json.utf8)))
        #expect(payload.items[0].labels.isEmpty)
    }

    @Test func maintainerSweepNullCommentCountDecodesAsUnknown() throws {
        // Live 2026-08-10 maintainer rows come from REST and intentionally
        // carry `comments: null`; rejecting one used to blank all 38 rows as
        // "outside the pinned contract".
        let json = """
        {"count": 1, "items": [{
          "author": "alice", "comments": null, "draft": false,
          "labels": [], "number": 27,
          "reasons": ["maintainer_unreviewed"],
          "ref": "o/r#27", "repo": "o/r", "state": "open", "title": "t",
          "updated_at": "2026-08-10T00:00:00Z", "url": "https://github.com/o/r/pull/27"
        }]}
        """
        let payload = try #require(HolyGitHubInboxPayload.parse(Data(json.utf8)))
        #expect(payload.items[0].comments == nil)
    }

    @Test func missingCommentFieldStillViolatesThePinnedContract() {
        let json = """
        {"count": 1, "items": [{
          "author": "alice", "draft": false, "labels": [], "number": 27,
          "reasons": ["maintainer_unreviewed"],
          "ref": "o/r#27", "repo": "o/r", "state": "open", "title": "t",
          "updated_at": "2026-08-10T00:00:00Z", "url": "https://github.com/o/r/pull/27"
        }]}
        """
        #expect(HolyGitHubInboxPayload.parse(Data(json.utf8)) == nil)
    }

    // MARK: - Invocation contract

    @Test func inboxArgumentsMatchPinnedInvocation() {
        #expect(HolyGitHubInboxSource.inboxArguments(limit: 50) == [
            "gh", "inbox", "--json", "--limit", "50",
        ])
    }
}
