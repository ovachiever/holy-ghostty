import Foundation
import Testing
@testable import Ghostty

// Global unique assignment is the correctness core of crash restore after
// the e3565698 field failure: per-row nearest-timestamp resolution handed
// two same-cwd rows the same conversation. These tests pin the law (one
// conversation id per sheet, ever), the greedy ordering, the near-tie
// ambiguity demotion, and the shell-only demotion for rows left without a
// candidate.
struct HolyRestoreAssignmentTests {
    private func candidate(
        _ id: String,
        end: Int,
        preview: String = ""
    ) -> HolyRestoreResolveCandidate {
        .init(id: id, timestampEnd: end, preview: preview)
    }

    private func row(
        _ id: UUID,
        lastActivity: Int,
        candidates: [HolyRestoreResolveCandidate]
    ) -> HolyRestoreAssignment.Row {
        .init(id: id, lastActivityUnixSeconds: lastActivity, candidates: candidates)
    }

    private func exactIDs(
        _ verdicts: [UUID: HolyRestoreAssignmentVerdict]
    ) -> [String] {
        verdicts.values.compactMap {
            if case let .exact(id) = $0 { return id }
            return nil
        }
    }

    // MARK: - The uniqueness law

    @Test func twoRowsNeverCarryTheSameConversationID() {
        // Adversarial shape: both rows see the same candidate list and the
        // same conversation is nearest for both.
        let shared = [
            candidate("conv-close", end: 1_000),
            candidate("conv-far", end: 5_000),
        ]
        let rowA = UUID()
        let rowB = UUID()

        let verdicts = HolyRestoreAssignment.assign(rows: [
            row(rowA, lastActivity: 1_000, candidates: shared),
            row(rowB, lastActivity: 1_010, candidates: shared),
        ])

        let ids = exactIDs(verdicts)
        #expect(ids.count == Set(ids).count)
    }

    @Test func sameCwdSwarmPairsEachRowWithItsOwnConversation() {
        // The e3565698 scenario reduced to assignment terms: two lanes in
        // one cwd, two conversations minutes apart. Each row must get the
        // conversation whose end hugs its own last activity.
        let candidates = [
            candidate("e3565698-aaaa", end: 10_000),
            candidate("77aa4a02-bbbb", end: 9_880),
        ]
        let lane12 = UUID()
        let lane9 = UUID()

        let verdicts = HolyRestoreAssignment.assign(rows: [
            row(lane12, lastActivity: 10_000, candidates: candidates),
            row(lane9, lastActivity: 9_880, candidates: candidates),
        ])

        #expect(verdicts[lane12] == .exact(providerSessionID: "e3565698-aaaa"))
        #expect(verdicts[lane9] == .exact(providerSessionID: "77aa4a02-bbbb"))
    }

    @Test func consumedCompetitorsDoNotCreateAmbiguity() {
        // Both rows individually see two candidates 120s apart — a per-row
        // resolver would call each ambiguous. Global assignment consumes
        // each candidate, leaving no unclaimed competitor, so both rows are
        // decisively exact.
        let candidates = [
            candidate("first", end: 2_000),
            candidate("second", end: 1_880),
        ]
        let rowA = UUID()
        let rowB = UUID()

        let verdicts = HolyRestoreAssignment.assign(rows: [
            row(rowA, lastActivity: 2_000, candidates: candidates),
            row(rowB, lastActivity: 1_880, candidates: candidates),
        ])

        #expect(verdicts[rowA] == .exact(providerSessionID: "first"))
        #expect(verdicts[rowB] == .exact(providerSessionID: "second"))
    }

    // MARK: - Greedy ordering

    @Test func greedyPrefersTheGloballyClosestPairs() {
        // Row A is 10s from conv-x and 20s from conv-y; row B is 15s from
        // conv-x only. Greedy assigns (A, conv-x) first (closest pair), so
        // B is left to nothing even though B also wanted conv-x.
        let rowA = UUID()
        let rowB = UUID()

        let verdicts = HolyRestoreAssignment.assign(rows: [
            row(rowA, lastActivity: 1_000, candidates: [
                candidate("conv-x", end: 1_010),
                candidate("conv-y", end: 900),
            ]),
            row(rowB, lastActivity: 1_025, candidates: [
                candidate("conv-x", end: 1_010),
            ]),
        ])

        // conv-y is 100s from row A — outside the 60s near-tie tolerance of
        // A's 10s choice, so A is exact on conv-x, not ambiguous.
        #expect(verdicts[rowA] == .exact(providerSessionID: "conv-x"))
        #expect(verdicts[rowB] == HolyRestoreAssignmentVerdict.unmatched)
    }

    @Test func equalDistanceTieBreaksTowardTheEarlierRow() {
        // Both rows sit exactly 60s from the single candidate. The row
        // passed first (sheet order) wins; determinism is part of the law.
        let first = UUID()
        let second = UUID()

        let verdicts = HolyRestoreAssignment.assign(rows: [
            row(first, lastActivity: 1_060, candidates: [candidate("only", end: 1_000)]),
            row(second, lastActivity: 940, candidates: [candidate("only", end: 1_000)]),
        ])

        #expect(verdicts[first] == .exact(providerSessionID: "only"))
        #expect(verdicts[second] == HolyRestoreAssignmentVerdict.unmatched)
    }

    // MARK: - Ambiguity demotion

    @Test func unclaimedNearTieCompetitorsDemoteToAmbiguous() {
        // One row, two conversations ending 30s apart: picking the nearest
        // would be a guess, so the human picks. Both candidates surface,
        // best first.
        let only = UUID()
        let verdicts = HolyRestoreAssignment.assign(rows: [
            row(only, lastActivity: 1_000, candidates: [
                candidate("near", end: 990, preview: "near preview"),
                candidate("nearer", end: 1_000, preview: "nearer preview"),
            ]),
        ])

        #expect(verdicts[only] == .ambiguous(candidates: [
            candidate("nearer", end: 1_000, preview: "nearer preview"),
            candidate("near", end: 990, preview: "near preview"),
        ]))
    }

    @Test func competitorsBeyondTheToleranceDoNotDemote() {
        let only = UUID()
        let verdicts = HolyRestoreAssignment.assign(rows: [
            row(only, lastActivity: 1_000, candidates: [
                candidate("chosen", end: 995),
                candidate("distant", end: 1_000 - 5 - HolyRestoreAssignment.nearTieToleranceSeconds - 1),
            ]),
        ])

        #expect(verdicts[only] == .exact(providerSessionID: "chosen"))
    }

    // MARK: - Shell-only demotion

    @Test func rowsWithoutCandidatesAreNone() {
        let empty = UUID()
        let verdicts = HolyRestoreAssignment.assign(rows: [
            row(empty, lastActivity: 500, candidates: []),
        ])
        #expect(verdicts[empty] == HolyRestoreAssignmentVerdict.unmatched)
    }

    @Test func threeRowsTwoConversationsDemotesExactlyOne() {
        let rowA = UUID()
        let rowB = UUID()
        let rowC = UUID()
        let candidates = [
            candidate("one", end: 1_000),
            candidate("two", end: 2_000),
        ]

        let verdicts = HolyRestoreAssignment.assign(rows: [
            row(rowA, lastActivity: 1_000, candidates: candidates),
            row(rowB, lastActivity: 2_000, candidates: candidates),
            row(rowC, lastActivity: 3_000, candidates: candidates),
        ])

        #expect(verdicts[rowA] == .exact(providerSessionID: "one"))
        #expect(verdicts[rowB] == .exact(providerSessionID: "two"))
        #expect(verdicts[rowC] == HolyRestoreAssignmentVerdict.unmatched)
    }

    // MARK: - Sanitization

    @Test func unsafeCandidateIDsAreDroppedBeforeAssignment() {
        let only = UUID()
        let verdicts = HolyRestoreAssignment.assign(rows: [
            row(only, lastActivity: 1_000, candidates: [
                candidate("bad; rm -rf ~", end: 1_000),
                candidate("safe-id", end: 990),
            ]),
        ])
        #expect(verdicts[only] == .exact(providerSessionID: "safe-id"))
    }

    @Test func duplicateCandidateIDsWithinARowCollapse() {
        let only = UUID()
        let verdicts = HolyRestoreAssignment.assign(rows: [
            row(only, lastActivity: 1_000, candidates: [
                candidate("dup", end: 1_000),
                candidate("dup", end: 1_000),
            ]),
        ])
        // A duplicate of the chosen id must not masquerade as a near-tie
        // competitor and demote the row.
        #expect(verdicts[only] == .exact(providerSessionID: "dup"))
    }
}
