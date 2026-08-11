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

    // MARK: Panel-v2 language (adopted critique, 2026-08-11)

    /// Scope in words, never color alone. "Everywhere" = cross-project
    /// GitHub attention; anything else belongs to the focused project.
    /// The words Global/Local/Session are banned — they already mean other
    /// things in a multi-machine terminal.
    enum Scope: Equatable, Sendable {
        case everywhere
        case here
    }

    /// INTERIM rule until contract 2: scope is really repo-membership (a PR
    /// on the focused repo is HERE), but only the engine knows each PR's
    /// repo — client-side, PR threads read as elsewhere and everything
    /// board/session-anchored as here. Corrected engine-side in mn-43932b.
    static func scope(of thread: HolyBriefThread) -> Scope {
        thread.kind == "pr" || thread.hasPR ? .everywhere : .here
    }

    /// Engine states are not interface language: translate the classifier
    /// vocabulary that leaks through `why`/reasons into operator phrases.
    /// Unknown strings pass through untouched — mistranslation is worse
    /// than jargon.
    static func humanizedReason(_ raw: String) -> String {
        let lowered = raw.lowercased()
        if lowered.contains("claimed"), lowered.contains("no live session") {
            return "Claimed, but no agent is active"
        }
        if lowered.contains("review_requested") || lowered.contains("maintainer_unreview")
            || lowered.contains("maintainer_review_stale") {
            return "Review requested"
        }
        if lowered.contains("authored_changes_requested") {
            return "Changes requested on your work"
        }
        if lowered.contains("landed_open") {
            return "Its code already landed"
        }
        if lowered.contains("blocker_desync") {
            return "Its blocker is resolved"
        }
        return raw
    }

    /// "18h", never "18h ago" — the age column already communicates time.
    static func compactAge(_ relative: String) -> String {
        relative.hasSuffix(" ago") ? String(relative.dropLast(4)) : relative
    }

    /// Deterministic client-side cleanup of machine titles: leading bracket
    /// tags and conventional-commit prefixes carry zero decision value on a
    /// row surface (rule: strip [TAGS], `chore(deps):` and kin; never touch
    /// the remaining words — noun compression is the engine's job, with the
    /// original preserved in disclosure).
    static func sanitizedTitle(_ raw: String) -> String {
        var title = raw.trimmingCharacters(in: .whitespaces)
        while title.hasPrefix("["), let close = title.firstIndex(of: "]") {
            title = String(title[title.index(after: close)...])
                .trimmingCharacters(in: .whitespaces)
        }
        let commitPrefix = #"^(feat|fix|chore|docs|refactor|perf|test|build|ci|style|release|merge|debug)(\([^)]*\))?!?:\s*"#
        if let range = title.range(of: commitPrefix, options: .regularExpression) {
            title = String(title[range.upperBound...])
        }
        let cleaned = title.trimmingCharacters(in: .whitespaces)
        // A title that was ALL tags falls back to the raw original —
        // an empty row surface would hide work.
        return cleaned.isEmpty ? raw : cleaned
    }

    /// The one state sentence, mechanically honest per the adopted table:
    /// healthy+empty, degraded+empty, healthy+attention, degraded+attention
    /// each get their own truthful shape.
    static func stateSentence(
        hereCount: Int,
        elsewhereCount: Int,
        impairedSources: [String]
    ) -> String {
        let impaired = impairedSources.map(displayName(forSource:))
        let degradedSuffix: String
        switch impaired.count {
        case 0: degradedSuffix = ""
        case 1: degradedSuffix = " \(impaired[0]) is currently unreadable."
        default:
            degradedSuffix = " \(impaired.joined(separator: " and ")) are currently unreadable."
        }

        if hereCount == 0, elsewhereCount == 0 {
            return impaired.isEmpty
                ? "Nothing needs you."
                : "Nothing known needs you." + degradedSuffix
        }

        var parts: [String] = []
        if hereCount > 0 {
            let known = impaired.isEmpty ? "" : "known "
            parts.append("\(hereCount) \(known)decision\(hereCount == 1 ? "" : "s") here.")
        }
        if elsewhereCount > 0 {
            parts.append("\(elsewhereCount) review\(elsewhereCount == 1 ? "" : "s") elsewhere.")
        }
        return parts.joined(separator: " ") + degradedSuffix
    }

    private static func displayName(forSource source: String) -> String {
        switch source {
        case "github": return "GitHub"
        case "manna": return "The board"
        case "coord": return "Coordination"
        case "sessions": return "The session index"
        case "reconcile": return "Board reconcile"
        case "git": return "Git"
        default: return source
        }
    }

    /// Housekeeping bundles speak operator, not classifier: "11 finished
    /// tasks ready to close", never "LANDED_OPEN".
    static func bundleLabel(kind: String, count: Int) -> String {
        let plural = count == 1 ? "" : "s"
        switch kind {
        case "landed_open":
            return "\(count) finished task\(plural) ready to close"
        case "dead_claim":
            return "\(count) abandoned claim\(plural) ready to release"
        case "blocker_desync":
            return "\(count) resolved blocker\(plural) ready to clear"
        case "stale_dream":
            return "\(count) parked dream\(plural) awaiting a decision"
        case "doc_reference":
            return "\(count) dangling reference\(plural) to tidy"
        case "prompt_pairing":
            return "\(count) prompt link\(plural) to repair"
        default:
            return "\(count) \(kind) item\(plural)"
        }
    }

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
