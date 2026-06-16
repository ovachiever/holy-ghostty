import Foundation
import GhosttyKit

struct HolySessionPreviewStability {
    let repeatedEvidenceCount: Int
    let stagnantDuration: TimeInterval

    var stagnantSeconds: Int {
        max(0, Int(stagnantDuration.rounded()))
    }

    var isStalledCandidate: Bool {
        repeatedEvidenceCount >= 3 && stagnantDuration >= 20
    }

    var isLoopingCandidate: Bool {
        repeatedEvidenceCount >= 5 && stagnantDuration >= 45
    }
}

struct HolySessionRuntimeTelemetrySource {
    let runtime: HolySessionRuntime
    let surfaceView: Ghostty.SurfaceView
    let preview: String
    let signals: [HolySessionSignal]
    let phase: HolySessionPhase
    let stability: HolySessionPreviewStability
}

enum HolySessionRuntimeTelemetryParser {
    static func telemetry(
        from source: HolySessionRuntimeTelemetrySource,
        current: HolySessionRuntimeTelemetry
    ) -> HolySessionRuntimeTelemetry? {
        let evidence = lastMeaningfulLine(from: source.preview) ?? source.preview
        let primarySignal = source.signals.first
        let activeProgressReport = activeProgressReport(from: source.surfaceView.progressReport)
        let progressPercent = activeProgressReport?.progress.flatMap(Int.init)
        let command = extractCommand(from: evidence)
        let filePath = extractFilePath(from: evidence)
        let nextStepHint = extractNextStepHint(from: evidence)
        let artifact = extractArtifact(from: evidence)
        let stallKind = inferredStallKind(
            phase: source.phase,
            stability: source.stability,
            hasProgressReport: activeProgressReport != nil,
            primarySignal: primarySignal
        )
        let hasStructuredSignal = activeProgressReport != nil
            || primarySignal != nil
            || command != nil
            || nextStepHint != nil
            || artifact != nil
            || stallKind != nil

        guard hasStructuredSignal else {
            return current.isMeaningful ? .empty : nil
        }

        let activityKind = inferredActivityKind(
            primarySignal: primarySignal,
            evidence: evidence,
            hasProgressReport: activeProgressReport != nil,
            hasCommand: command != nil,
            hasFilePath: filePath != nil,
            stallKind: stallKind
        )
        let headline = primarySignal?.headline ?? generatedHeadline(
            runtime: source.runtime,
            activityKind: activityKind,
            progressPercent: progressPercent,
            stagnantSeconds: source.stability.stagnantSeconds
        )
        let detail = primarySignal?.detail ?? (evidence.isEmpty ? nil : evidence)

        let next = HolySessionRuntimeTelemetry(
            activityKind: activityKind,
            headline: headline,
            detail: detail,
            command: command,
            filePath: filePath,
            nextStepHint: nextStepHint,
            artifactSummary: artifact?.summary,
            artifactPath: artifact?.path,
            progressPercent: progressPercent,
            stagnantSeconds: stallKind == nil ? nil : source.stability.stagnantSeconds,
            repeatedEvidenceCount: stallKind == nil ? nil : source.stability.repeatedEvidenceCount,
            lastUpdatedAt: .now,
            evidence: evidence.isEmpty ? nil : evidence
        )

        if !next.isMeaningful {
            return nil
        }

        if matches(current, next) {
            return nil
        }

        return next
    }

    private static func activeProgressReport(
        from report: Ghostty.Action.ProgressReport?
    ) -> Ghostty.Action.ProgressReport? {
        guard let report else { return nil }
        switch report.state {
        case .set, .indeterminate:
            return report
        case .remove, .error, .pause:
            return nil
        }
    }

    private static func activityKind(for signal: HolySessionSignal) -> HolySessionActivityKind {
        switch signal.kind {
        case .approval:
            if isPlanningQuestionSignal(signal) {
                return .planningQuestion
            }
            return .approval
        case .progress:
            if isSwarmingSignal(signal) {
                return .swarming
            }
            return .progress
        case .reading:
            return .reading
        case .editing:
            return .editing
        case .command:
            return .command
        case .coordination:
            return .idle
        case .failure:
            return .failure
        case .completion:
            return .completion
        }
    }

    private static func inferredActivityKind(
        primarySignal: HolySessionSignal?,
        evidence: String,
        hasProgressReport: Bool,
        hasCommand: Bool,
        hasFilePath: Bool,
        stallKind: HolySessionActivityKind?
    ) -> HolySessionActivityKind {
        if let stallKind {
            return stallKind
        }

        if hasProgressReport {
            return .progress
        }

        if let primarySignal {
            return activityKind(for: primarySignal)
        }

        let lowerEvidence = evidence.lowercased()
        if editingMarkers.contains(where: lowerEvidence.contains), hasFilePath {
            return .editing
        }

        if readingMarkers.contains(where: lowerEvidence.contains), hasFilePath {
            return .reading
        }

        if hasCommand {
            return .command
        }

        return .idle
    }

    private static func generatedHeadline(
        runtime: HolySessionRuntime,
        activityKind: HolySessionActivityKind,
        progressPercent: Int?,
        stagnantSeconds: Int
    ) -> String? {
        switch activityKind {
        case .approval:
            return "\(runtime.displayName) needs approval"
        case .planningQuestion:
            return "\(runtime.displayName) has planning questions"
        case .progress:
            if let progressPercent {
                return "\(runtime.displayName) progress \(progressPercent)%"
            }
            return "\(runtime.displayName) is working"
        case .swarming:
            return "\(runtime.displayName) is coordinating a swarm"
        case .reading:
            return "\(runtime.displayName) is reading context"
        case .editing:
            return "\(runtime.displayName) is editing files"
        case .command:
            return "\(runtime.displayName) is running commands"
        case .stalled:
            return "\(runtime.displayName) may be stalled (\(stagnantSeconds)s unchanged)"
        case .looping:
            return "\(runtime.displayName) appears to be looping"
        case .failure:
            return "\(runtime.displayName) reported a failure"
        case .completion:
            return "\(runtime.displayName) completed"
        case .idle:
            return nil
        }
    }

    private static func isPlanningQuestionSignal(_ signal: HolySessionSignal) -> Bool {
        let evidence = "\(signal.headline)\n\(signal.detail)".lowercased()
        return evidence.contains("planning question")
            || evidence.contains("planning:")
            || evidence.contains("plan mode")
            || evidence.contains("how should ")
            || evidence.contains("enter to select")
    }

    private static func isSwarmingSignal(_ signal: HolySessionSignal) -> Bool {
        let evidence = "\(signal.headline)\n\(signal.detail)".lowercased()
        return evidence.contains("coordinating a swarm")
            || evidence.contains("background agents launched")
            || evidence.contains("teammates running")
            || evidence.contains("show teammates")
            || evidence.contains("agents working in parallel")
            || evidence.contains("build swarm")
            || evidence.contains("agent swarm")
    }

    private static func matches(
        _ lhs: HolySessionRuntimeTelemetry,
        _ rhs: HolySessionRuntimeTelemetry
    ) -> Bool {
        lhs.activityKind == rhs.activityKind
            && lhs.headline == rhs.headline
            && lhs.detail == rhs.detail
            && lhs.command == rhs.command
            && lhs.filePath == rhs.filePath
            && lhs.nextStepHint == rhs.nextStepHint
            && lhs.artifactSummary == rhs.artifactSummary
            && lhs.artifactPath == rhs.artifactPath
            && lhs.progressPercent == rhs.progressPercent
            && lhs.stagnantSeconds == rhs.stagnantSeconds
            && lhs.repeatedEvidenceCount == rhs.repeatedEvidenceCount
            && lhs.evidence == rhs.evidence
    }

    private static func inferredStallKind(
        phase: HolySessionPhase,
        stability: HolySessionPreviewStability,
        hasProgressReport: Bool,
        primarySignal: HolySessionSignal?
    ) -> HolySessionActivityKind? {
        guard phase == .working, !hasProgressReport else { return nil }
        if let primarySignal, isLiveWorkSignal(primarySignal) { return nil }

        if stability.isLoopingCandidate {
            return .looping
        }

        if stability.isStalledCandidate {
            return .stalled
        }

        return nil
    }

    private static func isLiveWorkSignal(_ signal: HolySessionSignal) -> Bool {
        switch signal.kind {
        case .progress, .reading, .editing, .command:
            return true
        case .coordination, .approval, .failure, .completion:
            return false
        }
    }

    private static let readingMarkers = [
        "reading ",
        "read file",
        "inspecting ",
        "reviewing ",
        "scanning ",
        "searching ",
    ]

    private static let editingMarkers = [
        "editing ",
        "writing ",
        "apply_patch",
        "patching ",
        "updated ",
        "modifying ",
    ]

    private struct HolyExtractedArtifact {
        let summary: String
        let path: String?
    }

    private static func extractCommand(from text: String) -> String? {
        // Agent TUIs (OpenCode, Claude, Codex) render a persistent status footer
        // that brands themselves with a version, e.g. "... ctrl+p commands - OpenCode 1.17.7".
        // That branding is chrome, not a command being run; extracting it as a command
        // marks an idle session as actively working. A real invocation ("opencode run")
        // is not followed by a version number, so it is unaffected.
        if isAgentStatusFooterLine(text) {
            return nil
        }

        let patterns = [
            #"(xcodebuild[^\n]*)"#,
            #"(zig build[^\n]*)"#,
            #"(swiftlint[^\n]*)"#,
            #"(git [^\n]*)"#,
            #"(pytest[^\n]*)"#,
            #"(npm [^\n]*)"#,
            #"(pnpm [^\n]*)"#,
            #"(yarn [^\n]*)"#,
            #"(claude[^\n]*)"#,
            #"(codex[^\n]*)"#,
            #"(opencode[^\n]*)"#,
            #"(bash[^\n]*)"#,
        ]

        for pattern in patterns {
            if let match = firstMatch(in: text, pattern: pattern) {
                return match.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return nil
    }

    private static func isAgentStatusFooterLine(_ text: String) -> Bool {
        text.range(
            of: #"\b(opencode|claude|codex)\s+v?\d+\.\d+"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func extractNextStepHint(from text: String) -> String? {
        let lowerText = text.lowercased()

        if lowerText.contains("press enter") {
            return "Press Enter to continue"
        }

        if lowerText.contains("[y/n]") || lowerText.contains("(y/n)") {
            return "Reply with y or n"
        }

        if lowerText.contains("approve") || lowerText.contains("approval") || lowerText.contains("confirm") {
            return "Review the prompt and confirm approval"
        }

        if lowerText.contains("continue?") {
            return "Confirm whether the agent should continue"
        }

        return nil
    }

    private static func extractArtifact(from text: String) -> HolyExtractedArtifact? {
        let lowerText = text.lowercased()
        let markers = [
            "created ",
            "wrote ",
            "saved ",
            "generated ",
            "updated ",
            "output ",
        ]

        guard markers.contains(where: lowerText.contains) else {
            return nil
        }

        let path = extractFilePath(from: text)
        let summary = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return nil }
        return .init(summary: summary, path: path)
    }

    private static func extractFilePath(from text: String) -> String? {
        let patterns = [
            #"([A-Za-z0-9._-]+(?:/[A-Za-z0-9._-]+)+)"#,
            #"((?:~|/)[A-Za-z0-9._/\-]+)"#,
        ]

        for pattern in patterns {
            if let match = firstMatch(in: text, pattern: pattern),
               !match.hasPrefix("http://"),
               !match.hasPrefix("https://") {
                return match
            }
        }

        return nil
    }

    private static func lastMeaningfulLine(from preview: String) -> String? {
        preview
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .last(where: { !$0.isEmpty && !isTerminalChromeLine($0) })
    }

    private static func isTerminalChromeLine(_ line: String) -> Bool {
        isTmuxStatusLine(line) || isSeparatorLine(line)
    }

    private static func isTmuxStatusLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[") else { return false }
        return trimmed.range(
            of: #"\b\d{1,2}:\d{2}\s+\d{2}-[A-Za-z]{3}-\d{2}\b"#,
            options: .regularExpression
        ) != nil
    }

    private static func isSeparatorLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else { return false }
        return trimmed.allSatisfy { "─━═- ".contains($0) }
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2,
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        return String(text[valueRange])
    }
}

#if DEBUG
extension HolySessionRuntimeTelemetryParser {
    static func extractCommandForTesting(from text: String) -> String? {
        extractCommand(from: text)
    }
}
#endif
