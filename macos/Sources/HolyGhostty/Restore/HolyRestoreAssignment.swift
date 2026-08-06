import Foundation

/// The verdict global assignment hands one restore row. Mirrors the old
/// per-row confidence vocabulary deliberately: `exact` restores, `ambiguous`
/// opens the picker, `none` demotes to an honest shell-only recreate.
enum HolyRestoreAssignmentVerdict: Equatable, Sendable {
    case exact(providerSessionID: String)
    /// Sorted best-first for this row (nearest end timestamp first).
    case ambiguous(candidates: [HolyRestoreResolveCandidate])
    /// No candidate left for this row — shell-only demotion downstream.
    /// Deliberately NOT named `none`: in optional-typed positions (like a
    /// dictionary subscript assignment) a `.none` case silently resolves to
    /// Optional.none and deletes the entry instead of storing the verdict.
    case unmatched
}

/// Global unique assignment of resolver candidates to restore rows.
///
/// The design law: assignment is global, identity is the argv. Per-row
/// nearest-timestamp resolution collides by construction the moment two
/// rows share a working directory — a same-cwd swarm resolves every row to
/// the same "nearest" conversation (the e3565698 field failure). So each
/// row's candidates are weighed against every other row's, and a
/// conversation id is spent at most once across the whole sheet.
///
/// Algorithm, chosen for explainability over cleverness (N is dozens, tops):
/// 1. Greedy over all (row, candidate) pairs by ascending
///    |candidate.timestamp_end − row.lastActivity|; each row and each
///    candidate id used at most once. Ties break by row order, then
///    candidate id — stable and deterministic.
/// 2. One audit pass over the frozen greedy result: a row's choice is only
///    `exact` when no unclaimed competitor sits within
///    `nearTieToleranceSeconds` of the chosen distance. A near-tie means the
///    pick would be a guess, so the row demotes to `ambiguous` and the human
///    picks. The audit never cascades (released ids are not re-granted),
///    keeping every verdict explainable from the greedy snapshot alone.
/// 3. Rows left without any unclaimed candidate are `unmatched` — shell-only
///    demotion, never a fabricated resume.
enum HolyRestoreAssignment {
    /// A competitor within this many seconds of the chosen candidate's
    /// distance makes the choice a guess. Same-cwd swarm lanes end minutes
    /// apart, and the true match is normally within seconds; sixty seconds
    /// separates "clearly this conversation" from "could be either".
    static let nearTieToleranceSeconds = 60

    struct Row: Equatable, Sendable {
        /// The restore row's stable id (the archive id).
        let id: UUID
        /// The archived session's last-activity time, unix seconds.
        let lastActivityUnixSeconds: Int
        /// Every conversation the resolver considered plausible for this
        /// row's coordinates. Order is irrelevant here; distances are
        /// recomputed per row.
        let candidates: [HolyRestoreResolveCandidate]
    }

    /// Assigns candidates to rows. Row order matters only for tie-breaking:
    /// pass rows in sheet order so equal-distance conflicts resolve toward
    /// the row the user sees first.
    static func assign(rows: [Row]) -> [UUID: HolyRestoreAssignmentVerdict] {
        // Sanitize per row: drop ids outside the safe charset (they could
        // never be resumed) and duplicate ids within one row.
        let sanitized: [[HolyRestoreResolveCandidate]] = rows.map { row in
            var seen: Set<String> = []
            return row.candidates.filter {
                HolyRestoreCommandBuilder.isSafeProviderSessionID($0.id)
                    && seen.insert($0.id).inserted
            }
        }

        struct Pair {
            let rowIndex: Int
            let candidate: HolyRestoreResolveCandidate
            let distance: Int
        }

        var pairs: [Pair] = []
        for (rowIndex, candidates) in sanitized.enumerated() {
            for candidate in candidates {
                pairs.append(.init(
                    rowIndex: rowIndex,
                    candidate: candidate,
                    distance: abs(candidate.timestampEnd - rows[rowIndex].lastActivityUnixSeconds)
                ))
            }
        }
        pairs.sort { lhs, rhs in
            if lhs.distance != rhs.distance { return lhs.distance < rhs.distance }
            if lhs.rowIndex != rhs.rowIndex { return lhs.rowIndex < rhs.rowIndex }
            return lhs.candidate.id < rhs.candidate.id
        }

        // Greedy pass: best remaining pair wins, each side spent once.
        var chosenByRowIndex: [Int: (candidate: HolyRestoreResolveCandidate, distance: Int)] = [:]
        var claimedIDs: Set<String> = []
        for pair in pairs {
            guard chosenByRowIndex[pair.rowIndex] == nil,
                  !claimedIDs.contains(pair.candidate.id) else { continue }
            chosenByRowIndex[pair.rowIndex] = (pair.candidate, pair.distance)
            claimedIDs.insert(pair.candidate.id)
        }

        // Audit pass against the frozen greedy snapshot.
        var verdicts: [UUID: HolyRestoreAssignmentVerdict] = [:]
        for (rowIndex, row) in rows.enumerated() {
            guard let chosen = chosenByRowIndex[rowIndex] else {
                verdicts[row.id] = .unmatched
                continue
            }

            let nearTieCompetitors = sanitized[rowIndex].filter { candidate in
                candidate.id != chosen.candidate.id
                    && !claimedIDs.contains(candidate.id)
                    && abs(candidate.timestampEnd - row.lastActivityUnixSeconds) - chosen.distance
                    <= nearTieToleranceSeconds
            }

            if nearTieCompetitors.isEmpty {
                verdicts[row.id] = .exact(providerSessionID: chosen.candidate.id)
            } else {
                let pickerCandidates = ([chosen.candidate] + nearTieCompetitors).sorted {
                    let lhsDistance = abs($0.timestampEnd - row.lastActivityUnixSeconds)
                    let rhsDistance = abs($1.timestampEnd - row.lastActivityUnixSeconds)
                    if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
                    return $0.id < $1.id
                }
                verdicts[row.id] = .ambiguous(candidates: pickerCandidates)
            }
        }

        // The law this module exists for: two rows may never carry the same
        // conversation id. Greedy spends each id once, so this can only fire
        // on an implementation regression — fail loudly in debug.
        var exactIDs: Set<String> = []
        for verdict in verdicts.values {
            if case let .exact(id) = verdict {
                assert(
                    exactIDs.insert(id).inserted,
                    "Global assignment produced conversation id \(id) for two rows."
                )
            }
        }

        return verdicts
    }
}
