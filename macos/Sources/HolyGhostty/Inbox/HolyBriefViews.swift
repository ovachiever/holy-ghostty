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

/// The panel's first element: the paragraph, grounded. Citations render
/// de-emphasized; the grounding mode and age are visible so a model voice is
/// never mistaken for ground truth, nor counts for a voice.
struct HolyBriefAnswerLineView: View {
    let paragraph: HolyBriefParagraph
    let generatedAt: Date?
    let failureReason: String?
    let sourceNotes: [HolyBriefTriage.SourceNote]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            paragraphText
                .font(.system(size: 11.5))
                .foregroundStyle(HolyGhosttyTheme.textPrimary)
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            HStack(spacing: 6) {
                Text(groundingLabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
                if let generatedAt {
                    Text("· \(HolyInboxRowView.relativeTime(from: generatedAt))")
                        .font(.system(size: 9))
                        .foregroundStyle(HolyGhosttyTheme.textTertiary)
                }
                ForEach(sourceNotes) { note in
                    Text("· \(note.source) \(note.status)")
                        .font(.system(size: 9))
                        .foregroundStyle(HolyGhosttyTheme.warning.opacity(0.85))
                        .help(note.reason)
                }
            }

            if let failureReason {
                Text(failureReason)
                    .font(.system(size: 9))
                    .foregroundStyle(HolyGhosttyTheme.warning)
                    .lineLimit(2)
                    .help(failureReason)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var groundingLabel: String {
        paragraph.mode == "model" ? "voiced" : "counts"
    }

    private var paragraphText: Text {
        HolyBriefTriage.paragraphRuns(paragraph.text).reduce(Text("")) { total, run in
            switch run {
            case let .text(value):
                return total + Text(value)
            case let .citation(value):
                return total + Text(value)
                    .font(.system(size: 8.5))
                    .foregroundColor(HolyGhosttyTheme.textTertiary)
            }
        }
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
    let onOpen: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        Button {
            onOpen?()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: density == .hero ? 4 : 2) {
                    HStack(spacing: 6) {
                        if isNewSinceLastLook {
                            Circle()
                                .fill(HolyGhosttyTheme.accent)
                                .frame(width: 5, height: 5)
                                .help("Moved since you last looked")
                        }
                        Text(thread.title)
                            .font(.system(
                                size: density == .hero ? 12.5 : 11,
                                weight: density == .hero ? .semibold : .medium
                            ))
                            .foregroundStyle(HolyGhosttyTheme.textPrimary)
                            .lineLimit(density == .compact ? 1 : 2)
                    }

                    if density != .compact {
                        HStack(spacing: 6) {
                            if let session = thread.session {
                                Text(sessionLine(session))
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(HolyGhosttyTheme.textSecondary)
                                    .lineLimit(1)
                            }
                            if density == .hero, let reason = thread.rank.reasons.first {
                                Text(reason)
                                    .font(.system(size: 9))
                                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
                                    .lineLimit(1)
                                    .help(thread.rank.reasons.joined(separator: "\n"))
                            }
                        }
                    }
                }

                Spacer(minLength: 4)

                if let updatedAt = thread.updatedAt {
                    Text(HolyInboxRowView.relativeTime(from: updatedAt))
                        .font(.system(size: 9))
                        .foregroundStyle(HolyGhosttyTheme.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, density == .hero ? 8 : (density == .compact ? 3 : 5))
            .background(
                isHovering ? HolyGhosttyTheme.bg.opacity(0.6) : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private func sessionLine(_ session: HolyBriefThreadSession) -> String {
        var parts: [String] = []
        if let status = session.status { parts.append(status) }
        if let phase = session.phase, phase != session.status { parts.append(phase) }
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
