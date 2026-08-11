import SwiftUI

// MARK: - Spawn plumbing (typed commands, human Enter)

/// Builders for the automation URLs the brief rows open. Every command
/// arrives in a fresh shell as TYPED input with no newline — the pane waits
/// for the human's Enter (Second Chair covenant; same mechanism as the manna
/// triage rows).
enum HolyBriefSpawn {
    static func typedCommandURL(
        command: String,
        title: String,
        workingDirectory: String?
    ) -> URL? {
        let typeable = HolyBriefTriage.typeableCommand(command)
        guard !typeable.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = HolyAutomationURLParser.scheme
        components.host = "spawn"
        var items = [
            URLQueryItem(name: "runtime", value: "shell"),
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "initialInput", value: typeable),
        ]
        if let workingDirectory {
            items.insert(URLQueryItem(name: "workingDirectory", value: workingDirectory), at: 1)
        }
        components.queryItems = items
        // "+" survives URLComponents literally but the automation parser
        // reads it back as a space (form-encoding convention) — encode it.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }

    /// The lens's question mode: `agent-do brief ask "<question>"` typed
    /// into a shell. Quotes inside the question are shell-quoted so the
    /// typed line survives the human's Enter as one argument.
    static func askURL(question: String, workingDirectory: String?) -> URL? {
        let cleaned = HolyBriefTriage.typeableCommand(question)
        guard !cleaned.isEmpty else { return nil }
        let quoted = "'" + cleaned.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
        return typedCommandURL(
            command: "agent-do brief ask \(quoted)",
            title: "brief ask",
            workingDirectory: workingDirectory
        )
    }
}

// MARK: - Answer line

/// The panel's headline: ONE mechanically honest state sentence, dominant,
/// with room. The voiced paragraph was removed from the resting surface —
/// it restated the headline's counts in system vocabulary (critique round
/// 2); it returns only when the engine's v2 insight field carries meaning
/// beyond the counts (mn-43932b). Degradation lives inside the sentence
/// itself; the full source detail rides hover.
struct HolyBriefStateHeaderView: View {
    let sentence: String
    let failureReason: String?
    let sourceNotes: [HolyBriefTriage.SourceNote]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(sentence)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(HolyGhosttyTheme.textPrimary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .help(sourceNotes.isEmpty
                    ? ""
                    : sourceNotes.map { "\($0.source): \($0.reason)" }.joined(separator: "\n"))

            if let failureReason {
                Text(failureReason)
                    .font(.system(size: 10))
                    .foregroundStyle(HolyGhosttyTheme.warning)
                    .lineLimit(2)
                    .help(failureReason)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

// MARK: - Thread rows

/// Rank decides pixels: hero for the top attention thread, standard for the
/// rest, compact for activity above the seam.
enum HolyBriefThreadDensity {
    case hero
    case standard
    case compact
}

struct HolyBriefThreadRowView: View {
    let thread: HolyBriefThread
    let density: HolyBriefThreadDensity
    let isNewSinceLastLook: Bool
    /// The focused project's display name — the scope word for `.here` rows.
    let focusedProjectName: String?
    let onOpen: (() -> Void)?

    @State private var isHovering = false

    /// One monochrome glyph lane, differentiating by KIND once, quietly.
    private var glyphName: String {
        if thread.hasPR { return "arrow.triangle.branch" }
        if thread.kind == "session" { return "terminal" }
        if thread.hasManna { return "checkmark.circle" }
        return "circle.dotted"
    }

    private var scope: HolyBriefTriage.Scope { HolyBriefTriage.scope(of: thread) }

    private var scopeWord: String {
        scope == .everywhere ? "Everywhere" : (focusedProjectName ?? "This project")
    }

    private var titleSize: CGFloat {
        switch density {
        case .hero: return 14
        case .standard: return 13
        case .compact: return 12
        }
    }

    var body: some View {
        Button {
            onOpen?()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: glyphName)
                    .font(.system(size: density == .hero ? 12 : 10, weight: .medium))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
                    .frame(width: 16, alignment: .center)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: density == .hero ? 4 : 2) {
                    HStack(spacing: 6) {
                        if isNewSinceLastLook {
                            Circle()
                                .fill(HolyGhosttyTheme.accent)
                                .frame(width: 5, height: 5)
                                .help("Moved since you last looked")
                        }
                        Text(HolyBriefTriage.sanitizedTitle(thread.title))
                            .font(.system(
                                size: titleSize,
                                weight: density == .hero ? .semibold : .medium
                            ))
                            .foregroundStyle(HolyGhosttyTheme.textPrimary)
                            .lineLimit(density == .compact ? 1 : 2)
                            .help(thread.title)
                    }

                    if density != .compact {
                        Text(metadataLine)
                            .font(.system(size: 11))
                            .foregroundStyle(HolyGhosttyTheme.textSecondary)
                            .lineLimit(1)
                            .help(thread.rank.reasons.joined(separator: "\n"))
                    }
                }

                Spacer(minLength: 4)

                if let updatedAt = thread.updatedAt {
                    Text(HolyBriefTriage.compactAge(
                        HolyInboxRowView.relativeTime(from: updatedAt)
                    ))
                    .font(.system(size: 11))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, density == .hero ? 8 : (density == .compact ? 3 : 5))
            .background(isHovering ? HolyGhosttyTheme.bg.opacity(0.6) : Color.clear)
            // The amber rail marks RANK, not scope (critique round 2: as a
            // scope cue it read as selection). Exactly one row in the panel
            // carries it — the NEXT item. Scope lives in words.
            .overlay(alignment: .leading) {
                if density == .hero {
                    Rectangle()
                        .fill(HolyGhosttyTheme.halo.opacity(0.75))
                        .frame(width: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    /// Row anatomy line two: [scope] · [why it waits], in operator words.
    private var metadataLine: String {
        var parts = [scopeWord]
        if let why = thread.why.first {
            parts.append(HolyBriefTriage.humanizedReason(why))
        } else if let session = thread.session {
            if session.status == "active", session.phase != nil {
                parts.append("Agent \(session.phase ?? "active")")
            } else if thread.needsMe {
                parts.append("Claimed, but no agent is active")
            } else if let status = session.status {
                parts.append(status)
            }
        } else if let reason = thread.rank.reasons.first {
            parts.append(HolyBriefTriage.humanizedReason(reason))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Suggestion rows

/// A loaded verb. The row shows the label; the affordance opens a shell with
/// the exact command typed and waiting. Nothing here executes anything.
struct HolyBriefSuggestionRowView: View {
    let suggestion: HolyBriefSuggestion
    let workingDirectory: String?

    @State private var isHovering = false

    var body: some View {
        Button {
            guard let url = HolyBriefSpawn.typedCommandURL(
                command: suggestion.command,
                title: "brief · \(suggestion.issueID ?? suggestion.kind)",
                workingDirectory: workingDirectory
            ) else { return }
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #endif
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "return")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 1) {
                    Text(suggestion.label)
                        .font(.system(size: 10.5))
                        .foregroundStyle(HolyGhosttyTheme.textPrimary)
                        .lineLimit(2)
                    Text(suggestion.command)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(HolyGhosttyTheme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(isHovering ? HolyGhosttyTheme.bg.opacity(0.6) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Opens a shell with this command typed — you press Enter")
    }
}
