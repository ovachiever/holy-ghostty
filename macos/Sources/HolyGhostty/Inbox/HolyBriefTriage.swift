import Foundation

/// Pure mapping from a brief payload to what the panel draws. No AppKit, no
/// engine, no clock reads beyond the caller-supplied `now` — a total
/// function testable against fixtures (the design doc's row law lives here).
enum HolyBriefTriage {
    /// The Needs-me drawer's row law: a thread earns the drawer only when
    /// the engine says a human is waited on; everything else is Library
    /// inventory. Suggestions are always attention (they exist only when a
    /// human decision is loaded).
    struct Triaged: Equatable, Sendable {
        var hero: HolyBriefThread?
        var needsMe: [HolyBriefThread]
        /// Attention the drawer does NOT show by default: beyond the display
        /// cap, or stale. One expandable count-row; never deleted, never
        /// silently dropped.
        var needsMeOverflow: [HolyBriefThread]
        var activity: [HolyBriefThread]
        var libraryThreadCount: Int
        var suggestionGroups: [SuggestionGroup]
        var sourceNotes: [SourceNote]
        var deltaThreadIDs: Set<String>
    }

    /// A stressed glance reads about six things (hero + five). The engine
    /// admitted 30 "needs you" PRs on first live contact (2026-08-11,
    /// Erik: "an absolute mess") — rank decides which few earn pixels;
    /// the rest are one count-row away, not gone.
    static let attentionDisplayLimit = 6

    /// Quiet aging: unpinned attention untouched this long stops occupying
    /// the drawer — a PR idle for over a week is inventory wearing an
    /// attention costume. Pins are exempt: explicit human curation outranks
    /// every automatic rule.
    static let staleAttentionAge: TimeInterval = 7 * 24 * 3600

    struct SuggestionGroup: Equatable, Sendable, Identifiable {
        let kind: String
        let title: String
        let suggestions: [HolyBriefSuggestion]
        var id: String { kind }
    }

    /// A degraded/absent source renders as a quiet header note — never as a
    /// fake content row (design principle 6).
    struct SourceNote: Equatable, Sendable, Identifiable {
        let source: String
        let status: String
        let reason: String
        var id: String { source }
    }

    /// Human titles for the suggestion kinds the reconcile grammar emits;
    /// unknown kinds pass through under their raw name rather than hiding.
    private static let suggestionKindTitles: [String: String] = [
        "landed_open": "Landed, still open",
        "dead_claim": "Dead claims",
        "blocker_desync": "Blockers resolved",
        "stale_dream": "Stale dreams",
        "doc_reference": "Dangling references",
        "prompt_pairing": "Prompt pairing",
    ]

    static func triage(_ payload: HolyBriefPayload, now: Date = .now) -> Triaged {
        let ranked = payload.threads.sorted { $0.rank.score > $1.rank.score }
        let attention = ranked.filter { $0.needsMe && !$0.snoozed }
        let pinnedExtras = ranked.filter { $0.pinned && !$0.needsMe }
        let deltaIDs = Set(payload.delta.threadIDs)

        // Activity: moved since the last look but not demanding a human —
        // rendered above the seam, compact, so change is visible without
        // masquerading as attention.
        let attentionIDs = Set((attention + pinnedExtras).map(\.id))
        let activity = ranked.filter {
            deltaIDs.contains($0.id) && !attentionIDs.contains($0.id)
        }

        // The drawer shows pins unconditionally, then fresh attention by
        // rank up to the cap; stale or over-cap attention becomes the
        // overflow count-row.
        var visible: [HolyBriefThread] = []
        var overflow: [HolyBriefThread] = []
        for thread in attention + pinnedExtras {
            if thread.pinned {
                visible.append(thread)
                continue
            }
            let isStale = thread.updatedAt.map {
                now.timeIntervalSince($0) > staleAttentionAge
            } ?? false
            if !isStale, visible.count < attentionDisplayLimit {
                visible.append(thread)
            } else {
                overflow.append(thread)
            }
        }

        let needsMe = visible
        let libraryCount = max(
            0,
            payload.threadsTotal - visible.count - overflow.count - activity.count
        )

        var groups: [SuggestionGroup] = []
        var byKind: [String: [HolyBriefSuggestion]] = [:]
        var kindOrder: [String] = []
        for suggestion in payload.suggestions {
            if byKind[suggestion.kind] == nil { kindOrder.append(suggestion.kind) }
            byKind[suggestion.kind, default: []].append(suggestion)
        }
        for kind in kindOrder {
            groups.append(SuggestionGroup(
                kind: kind,
                title: suggestionKindTitles[kind] ?? kind,
                suggestions: byKind[kind] ?? []
            ))
        }

        let notes = payload.sources
            .filter { $0.value.status != "ok" }
            .map { SourceNote(
                source: $0.key,
                status: $0.value.status,
                reason: $0.value.reason ?? $0.value.status
            ) }
            .sorted { $0.source < $1.source }

        return Triaged(
            hero: needsMe.first,
            needsMe: Array(needsMe.dropFirst()),
            needsMeOverflow: overflow,
            activity: activity,
            libraryThreadCount: libraryCount,
            suggestionGroups: groups,
            sourceNotes: notes,
            deltaThreadIDs: deltaIDs
        )
    }

    /// A command headed for a pane must arrive as ONE typed line the human
    /// then fires: strip every control character so nothing can auto-submit
    /// or smuggle escapes past the reading human (Second Chair covenant,
    /// same fence class as insertDraft's).
    static func typeableCommand(_ command: String) -> String {
        String(command.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
            .trimmingCharacters(in: .whitespaces)
    }

    /// Splits paragraph text into runs so receipt citations ("[r5]",
    /// "[r5, r6]") render de-emphasized instead of interrupting the read.
    enum ParagraphRun: Equatable, Sendable {
        case text(String)
        case citation(String)
    }

    static func paragraphRuns(_ text: String) -> [ParagraphRun] {
        var runs: [ParagraphRun] = []
        var remaining = Substring(text)
        while let open = remaining.firstIndex(of: "[") {
            guard let close = remaining[open...].firstIndex(of: "]") else { break }
            let inner = remaining[remaining.index(after: open)..<close]
            let isCitation = inner.split(separator: ",").allSatisfy { part in
                let token = part.trimmingCharacters(in: .whitespaces)
                return token.count >= 2 && token.hasPrefix("r")
                    && token.dropFirst().allSatisfy(\.isNumber)
            }
            if isCitation, !inner.isEmpty {
                if open > remaining.startIndex {
                    runs.append(.text(String(remaining[..<open])))
                }
                runs.append(.citation(String(remaining[open...close])))
                remaining = remaining[remaining.index(after: close)...]
            } else {
                let advance = remaining.index(after: open)
                runs.append(.text(String(remaining[..<advance])))
                remaining = remaining[advance...]
            }
        }
        if !remaining.isEmpty {
            runs.append(.text(String(remaining)))
        }
        return runs
    }
}
