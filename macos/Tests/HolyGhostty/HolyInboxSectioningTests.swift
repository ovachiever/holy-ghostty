import Foundation
import Testing
@testable import Ghostty

// Sectioning is the admission law of the GitHub inbox: every reason
// combination lands in exactly one section, bot authors collapse to one
// digest per repo, and the focused session's repo sorts first because what
// Erik is looking at outranks what he is not.
struct HolyInboxSectioningTests {
    private func item(
        repo: String = "org/repo",
        number: Int = 1,
        reasons: [String],
        author: String = "human",
        draft: Bool = false,
        title: String = "A PR",
        updatedAt: String = "2026-08-03T12:00:00Z"
    ) -> HolyGitHubInboxItem {
        HolyGitHubInboxItem(
            author: author,
            comments: 0,
            draft: draft,
            labels: [],
            number: number,
            reasons: reasons,
            ref: "\(repo)#\(number)",
            repo: repo,
            state: "open",
            title: title,
            updatedAt: ISO8601DateFormatter().date(from: updatedAt),
            url: "https://github.com/\(repo)/pull/\(number)"
        )
    }

    private func sections(
        _ items: [HolyGitHubInboxItem],
        focusedRepoSlug: String? = nil
    ) -> [HolyInboxSection] {
        HolyGitHubInboxSectioner.sections(items: items, focusedRepoSlug: focusedRepoSlug)
    }

    private func section(_ id: String, in sections: [HolyInboxSection]) -> HolyInboxSection? {
        sections.first { $0.id == id }
    }

    // MARK: - Admission per reason combination

    @Test func reviewRequestedLandsInNeedsYourReview() {
        let all = sections([item(reasons: ["review_requested"])])
        let review = section("gh.review", in: all)
        #expect(review?.rows.count == 1)
        #expect(review?.countsTowardBadge == true)
        #expect(review?.collapsedByDefault == false)
    }

    @Test func reviewRequestedWinsOverMaintainerReasons() {
        // A row carrying review_requested + maintainer_review_stale (live
        // combination) belongs to "Needs your review", nowhere else.
        let all = sections([
            item(reasons: ["review_requested", "maintainer_review_stale"]),
        ])
        #expect(section("gh.review", in: all)?.rows.count == 1)
        #expect(section("gh.maintainer", in: all) == nil)
    }

    @Test func maintainerReasonsWithoutReviewRequestedLandInMaintainerSection() {
        let all = sections([
            item(number: 1, reasons: ["maintainer_unreviewed"]),
            item(number: 2, reasons: ["maintainer_review_stale"]),
        ])
        let maintainer = section("gh.maintainer", in: all)
        #expect(maintainer?.rows.count == 2)
        #expect(maintainer?.countsTowardBadge == false)
    }

    @Test func authoredOpenLandsInYoursCollapsedByDefault() {
        let all = sections([item(reasons: ["authored_open"], author: "ovachiever")])
        let yours = section("gh.authored", in: all)
        #expect(yours?.rows.count == 1)
        #expect(yours?.collapsedByDefault == true)
        #expect(yours?.countsTowardBadge == false)
    }

    @Test func changesRequestedOnAuthoredWorkIsDirectAttention() {
        let all = sections([item(
            reasons: ["authored_open", "authored_changes_requested"],
            author: "ovachiever"
        )])
        let changes = section("gh.authored_changes", in: all)
        #expect(changes?.rows.count == 1)
        #expect(changes?.collapsedByDefault == false)
        #expect(changes?.countsTowardBadge == true)
        #expect(changes?.rows[0].chips.contains(
            HolyInboxChip("changes requested", emphasis: .attention)
        ) == true)
        #expect(section("gh.authored", in: all) == nil)
    }

    @Test func unknownReasonsLandInOtherSectionNotDropped() {
        // A future CLI reason must surface honestly, not vanish.
        let all = sections([item(reasons: ["mystery_reason"])])
        let other = section("gh.other", in: all)
        #expect(other?.rows.count == 1)
        #expect(other?.countsTowardBadge == false)
    }

    @Test func emptySectionsAreOmitted() {
        let all = sections([item(reasons: ["review_requested"])])
        #expect(all.map(\.id) == ["gh.review"])
    }

    // MARK: - Bot collapse

    @Test func botAuthorCollapsesToOneDigestRowPerRepo() {
        let all = sections([
            item(repo: "org/palantir", number: 1, reasons: ["review_requested", "bot_author"], author: "dependabot[bot]"),
            item(repo: "org/palantir", number: 2, reasons: ["bot_author"], author: "dependabot[bot]"),
            item(repo: "org/other", number: 3, reasons: ["bot_author"], author: "renovate[bot]"),
        ])

        // bot_author wins over every other reason: no bot rows leak upward.
        #expect(section("gh.review", in: all) == nil)

        let bots = section("gh.bots", in: all)
        #expect(bots?.rows.count == 2)
        #expect(bots?.collapsedByDefault == true)
        #expect(bots?.countsTowardBadge == false)

        let palantir = bots?.rows.first { $0.id == "gh.bots:org/palantir" }
        #expect(palantir?.title == "2 dependabot PRs — palantir")
        #expect(palantir?.children.count == 2)

        let other = bots?.rows.first { $0.id == "gh.bots:org/other" }
        #expect(other?.title == "1 renovate PR — other")
    }

    @Test func mixedBotAuthorsDigestAsBotPRs() {
        let all = sections([
            item(repo: "org/mixed", number: 1, reasons: ["bot_author"], author: "dependabot[bot]"),
            item(repo: "org/mixed", number: 2, reasons: ["bot_author"], author: "renovate[bot]"),
        ])
        let digest = section("gh.bots", in: all)?.rows.first
        #expect(digest?.title == "2 bot PRs — mixed")
    }

    // MARK: - Row shape

    @Test func rowCarriesStableIDLinkChipsAndDraftMarker() {
        let all = sections([
            item(
                repo: "org/repo",
                number: 7,
                reasons: ["review_requested"],
                author: "alice",
                draft: true,
                title: "Fix the flux"
            ),
        ])
        let row = section("gh.review", in: all)?.rows.first
        #expect(row?.id == "gh:org/repo#7")
        #expect(row?.title == "Fix the flux")
        #expect(row?.action == .openURL(URL(string: "https://github.com/org/repo/pull/7")!))
        #expect(row?.acknowledgeable == false)
        #expect(row?.chips.contains(HolyInboxChip("draft", emphasis: .neutral)) == true)
        #expect(row?.chips.contains(HolyInboxChip("review requested", emphasis: .attention)) == true)
        #expect(row?.subtitle?.contains("org/repo#7") == true)
        #expect(row?.subtitle?.contains("alice") == true)
    }

    // MARK: - Ordering

    @Test func focusedRepoSortsFirstThenNewestUpdated() {
        let all = sections(
            [
                item(repo: "org/elsewhere", number: 1, reasons: ["review_requested"], updatedAt: "2026-08-03T10:00:00Z"),
                item(repo: "org/focused", number: 2, reasons: ["review_requested"], updatedAt: "2026-08-01T10:00:00Z"),
                item(repo: "org/elsewhere", number: 3, reasons: ["review_requested"], updatedAt: "2026-08-02T10:00:00Z"),
            ],
            focusedRepoSlug: "org/focused"
        )

        let ids = section("gh.review", in: all)?.rows.map(\.id)
        // Focused repo first despite being oldest; the rest newest-first.
        #expect(ids == ["gh:org/focused#2", "gh:org/elsewhere#1", "gh:org/elsewhere#3"])
    }

    @Test func crossRepoRowsAreNeverFilteredByFocus() {
        let all = sections(
            [
                item(repo: "org/elsewhere", number: 1, reasons: ["review_requested"]),
            ],
            focusedRepoSlug: "org/focused"
        )
        #expect(section("gh.review", in: all)?.rows.count == 1)
    }

    // MARK: - Degraded snapshot

    @Test func degradedSnapshotIsOneQuietRowNeverInventedEmptiness() {
        let snapshot = HolyGitHubInboxSource.degradedSnapshot(detail: "agent-do not found on PATH")
        #expect(snapshot.sections.count == 1)

        let degraded = snapshot.sections[0]
        #expect(degraded.countsTowardBadge == false)
        #expect(degraded.rows.count == 1)
        #expect(degraded.rows[0].isDegraded == true)
        #expect(degraded.rows[0].title == "GitHub inbox unavailable")
        #expect(degraded.rows[0].subtitle == "agent-do not found on PATH")
    }
}
