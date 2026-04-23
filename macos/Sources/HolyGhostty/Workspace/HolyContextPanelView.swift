import AppKit
import SwiftUI

struct HolyContextPanelView: View {
    let session: HolySession?
    let coordination: HolySessionCoordination
    @ObservedObject var store: HolyWorkspaceStore

    @State private var externalPeers: [HolyCoordPeer] = []
    @State private var externalPeerError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let session {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        missionSection(session)
                        runtimeSection(session)
                        budgetSection(session)
                        timelineSection(session)
                        coordinationSection(session)
                        gitSection(session)
                        verificationSection(session)
                        actionsSection(session)
                        launchSection(session)
                    }
                    .padding(12)
                }
                .scrollIndicators(.hidden)
                .task(id: session.id) {
                    await refreshExternalPeers()
                }
            } else {
                HolyGhosttyEmptyStateView(
                    title: "No context",
                    subtitle: "Select a session to inspect.",
                    symbol: "sidebar.left"
                )
                .frame(maxHeight: .infinity)
            }
        }
    }

    // MARK: - Mission

    @ViewBuilder
    private func missionSection(_ session: HolySession) -> some View {
        if let task = session.record.launchSpec.task {
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("Mission")

                Text(session.missionDisplay)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(HolyGhosttyTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                contextRow("Task", "\(task.sourceSummary) · \(task.title)")

                if !session.signals.isEmpty, let signal = session.signals.first {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(signalColor(signal.kind))
                            .frame(width: 5, height: 5)
                        Text(signal.headline)
                            .font(.system(size: 11))
                            .foregroundStyle(signalColor(signal.kind))
                            .lineLimit(2)
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    // MARK: - Coordination (only when there's something to report)

    @ViewBuilder
    private func runtimeSection(_ session: HolySession) -> some View {
        if session.runtimeTelemetry.isMeaningful {
            let telemetry = session.runtimeTelemetry

            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("Runtime")

                contextRow("Activity", telemetry.activityKind.displayName)

                if let headline = telemetry.headline, !headline.isEmpty {
                    contextRow("Headline", headline)
                }

                if let progressPercent = telemetry.progressPercent {
                    contextRow("Progress", "\(progressPercent)%")
                }

                if let command = telemetry.command, !command.isEmpty {
                    contextRow("Command", command)
                }

                if let filePath = telemetry.filePath, !filePath.isEmpty {
                    contextRow("File", filePath)
                }

                if let nextStepHint = telemetry.nextStepHint, !nextStepHint.isEmpty {
                    contextRow("Next Step", nextStepHint)
                }

                if let artifactSummary = telemetry.artifactSummary, !artifactSummary.isEmpty {
                    contextRow("Artifact", artifactSummary)
                }

                if let artifactPath = telemetry.artifactPath,
                   !artifactPath.isEmpty,
                   artifactPath != telemetry.filePath {
                    contextRow("Artifact Path", artifactPath)
                }

                if let stagnantSeconds = telemetry.stagnantSeconds, stagnantSeconds > 0 {
                    contextRow("Stagnant", "\(stagnantSeconds)s")
                }

                if let repeatedEvidenceCount = telemetry.repeatedEvidenceCount,
                   repeatedEvidenceCount > 1 {
                    contextRow("Repeats", "\(repeatedEvidenceCount)x")
                }

                if let evidence = telemetry.evidence ?? telemetry.detail, !evidence.isEmpty {
                    Text(evidence)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(HolyGhosttyTheme.textTertiary)
                        .lineLimit(3)
                        .padding(.top, 2)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(runtimeTint(for: telemetry.activityKind).opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(runtimeTint(for: telemetry.activityKind).opacity(0.15), lineWidth: 0.5)
            )
        }
    }

    @ViewBuilder
    private func budgetSection(_ session: HolySession) -> some View {
        if session.budget.isConfigured || session.budgetTelemetry.hasUsage {
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("Budget")

                contextRow("Status", session.budgetStatus.displayName)
                contextRow("Usage", session.budgetSummaryText)
                contextRow("Remaining", session.budgetRemainingText)

                if session.budgetTelemetry.hasUsage {
                    contextRow("Burn Rate", session.budgetBurnRateText)

                    if let evidence = session.budgetTelemetry.evidence, !evidence.isEmpty {
                        Text(evidence)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(HolyGhosttyTheme.textTertiary)
                            .lineLimit(3)
                            .padding(.top, 2)
                    }
                }

                if session.budget.isConfigured {
                    HolyBudgetIntelligenceSection(
                        sessionID: session.id,
                        runtime: session.runtime,
                        budget: session.budget,
                        refreshID: budgetRefreshID(for: session)
                    )
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(budgetTint(for: session).opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(budgetTint(for: session).opacity(0.15), lineWidth: 0.5)
            )
        }
    }

    private func timelineSection(_ session: HolySession) -> some View {
        HolySessionTimelineSection(
            sessionID: session.id,
            refreshID: timelineRefreshID(for: session)
        )
    }

    @ViewBuilder
    private func coordinationSection(_ session: HolySession) -> some View {
        let hasInternalIssues = coordination.hasBlockingConflict
            || coordination.hasSharedBranch
            || session.hasBranchOwnershipDrift
            || !coordination.overlappingFiles.isEmpty
        let hasExternalPeers = !externalPeers.isEmpty
        let hasIssues = hasInternalIssues || hasExternalPeers

        if hasIssues {
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("Coordination")

                if hasInternalIssues {
                    Text(coordination.summary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(coordination.hasBlockingConflict ? HolyGhosttyTheme.danger : HolyGhosttyTheme.warning)

                    if !coordination.sharedWorktreeSessionTitles.isEmpty {
                        contextRow("Shared worktree", coordination.sharedWorktreeSessionTitles.joined(separator: ", "))
                    }

                    if !coordination.sharedBranchSessionTitles.isEmpty {
                        contextRow("Shared branch", coordination.sharedBranchSessionTitles.joined(separator: ", "))
                    }

                    if !coordination.overlappingFiles.isEmpty {
                        contextRow("Overlapping files", coordination.overlappingFiles.prefix(5).joined(separator: "\n"))
                    }
                }

                if hasExternalPeers {
                    if hasInternalIssues {
                        Divider()
                            .padding(.vertical, 2)
                    }
                    contextRow("Peers", externalPeers.map { $0.displayLabel }.joined(separator: ", "))
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(coordinationAccent(hasInternalIssues: hasInternalIssues).opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(coordinationAccent(hasInternalIssues: hasInternalIssues).opacity(0.15),
                            lineWidth: 0.5)
            )
        }
    }

    private func coordinationAccent(hasInternalIssues: Bool) -> Color {
        if coordination.hasBlockingConflict {
            return HolyGhosttyTheme.danger
        }
        if hasInternalIssues {
            return HolyGhosttyTheme.warning
        }
        return HolyGhosttyTheme.accent
    }

    // MARK: - Risk

    @ViewBuilder
    private func gitSection(_ session: HolySession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Risk")

            if let git = session.gitSnapshot {
                contextRow("Branch", git.branchDisplayName)

                if git.syncStatusText != "Up to date" {
                    contextRow("Sync", git.syncStatusText)
                }

                if git.changedFiles.isEmpty {
                    Text("No uncommitted changes.")
                        .font(.system(size: 11))
                        .foregroundStyle(HolyGhosttyTheme.textTertiary)
                } else {
                    Text(Self.riskSummary(for: git.changedFiles))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(HolyGhosttyTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)

                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(git.changedFiles.enumerated()), id: \.offset) { _, change in
                                HStack(spacing: 6) {
                                    Text(change.category.displayName)
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(fileColor(change.category))
                                        .frame(width: 20, alignment: .leading)

                                    Text(change.path)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(HolyGhosttyTheme.textSecondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        Text("Files (\(git.changedFiles.count))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(HolyGhosttyTheme.textTertiary)
                    }
                }
            } else {
                Text("No repository detected")
                    .font(.system(size: 11))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
            }
        }
    }

    // MARK: - Risk classifier

    private enum HolyRiskCategory: CaseIterable {
        case project, deps, ci, scripts, config, tests, docs, source, other

        var summaryNoun: String {
            switch self {
            case .project: return "project"
            case .deps:    return "dependency"
            case .ci:      return "CI"
            case .scripts: return "script"
            case .config:  return "config"
            case .tests:   return "test"
            case .docs:    return "doc"
            case .source:  return "source"
            case .other:   return "other"
            }
        }
    }

    private static let highSignalRiskOrder: [HolyRiskCategory] = [
        .project, .deps, .ci, .scripts, .config
    ]

    private static func riskSummary(for files: [HolyGitFileChange]) -> String {
        let count = files.count
        let buckets = Dictionary(grouping: files, by: { riskCategory(for: $0.path) })
            .mapValues { $0.count }

        var parts: [String] = ["\(count) file\(count == 1 ? "" : "s") changed"]
        for bucket in highSignalRiskOrder {
            if let n = buckets[bucket], n > 0 {
                parts.append("\(n) \(bucket.summaryNoun) file\(n == 1 ? "" : "s")")
            }
        }
        return parts.joined(separator: ", ")
    }

    private static func riskCategory(for path: String) -> HolyRiskCategory {
        let lower = path.lowercased()

        if lower.contains(".xcodeproj/")
            || lower.hasSuffix("project.pbxproj")
            || lower.contains(".xcworkspace/")
            || lower.hasSuffix("package.swift")
            || lower.hasPrefix("build.zig")
            || lower.hasSuffix("/build.zig")
            || lower.hasSuffix("cmakelists.txt")
            || lower == "makefile"
            || lower.hasSuffix("/makefile") {
            return .project
        }

        if lower.hasSuffix("package.resolved")
            || lower.hasSuffix("cargo.toml") || lower.hasSuffix("cargo.lock")
            || lower.hasSuffix("package.json") || lower.hasSuffix("package-lock.json")
            || lower.hasSuffix("pnpm-lock.yaml") || lower.hasSuffix("yarn.lock")
            || lower.hasSuffix("go.mod") || lower.hasSuffix("go.sum")
            || lower.hasSuffix("pyproject.toml") || lower.hasSuffix("poetry.lock")
            || lower.hasSuffix("gemfile") || lower.hasSuffix("gemfile.lock")
            || (lower.contains("requirements") && lower.hasSuffix(".txt")) {
            return .deps
        }

        if lower.hasPrefix(".github/workflows/")
            || lower.hasPrefix(".circleci/")
            || lower == ".gitlab-ci.yml" {
            return .ci
        }

        if lower.hasPrefix("scripts/") || lower.hasSuffix(".sh") || lower.hasSuffix(".bash") {
            return .scripts
        }

        if lower.contains("/tests/") || lower.contains("/test/")
            || lower.contains("_test.") || lower.contains(".test.") {
            return .tests
        }

        if lower.hasPrefix("docs/") || lower.hasSuffix(".md") || lower.hasSuffix(".mdx") || lower.hasSuffix(".rst") {
            return .docs
        }

        if !lower.contains("/") && (lower.hasSuffix(".toml") || lower.hasSuffix(".yaml") || lower.hasSuffix(".yml") || lower.hasPrefix(".env")) {
            return .config
        }

        let sourceExts = [".swift", ".ts", ".tsx", ".js", ".jsx", ".py", ".go", ".rs",
                          ".zig", ".c", ".cc", ".cpp", ".cxx", ".h", ".hpp", ".m", ".mm",
                          ".rb", ".java", ".kt", ".cs"]
        if sourceExts.contains(where: { lower.hasSuffix($0) }) {
            return .source
        }
        return .other
    }

    // MARK: - Launch metadata (collapsed into Details)

    private func launchSection(_ session: HolySession) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                contextRow("Runtime", session.displayRuntime.displayName)
                contextRow("Owner", session.ownership.label)
                contextRow("Transport", session.record.launchSpec.transport.summaryText)
                contextRow("Directory", session.workingDirectory ?? "Unassigned")

                if session.record.launchSpec.transport.isRemote {
                    contextRow("Host", session.record.launchSpec.transport.destinationDisplayName)
                }

                if let tmux = session.record.launchSpec.tmux {
                    contextRow("Tmux", "\(tmux.serverLabel) · \(tmux.sessionDisplayName)")
                }

                if let task = session.record.launchSpec.task {
                    contextRow("Task Source", task.sourceSummary)
                }

                if let command = session.record.launchSpec.command {
                    contextRow("Command", command)
                }

                if session.commandTelemetry.runCount > 0 {
                    contextRow("Runs", "\(session.commandTelemetry.runCount) (\(session.commandTelemetry.successCount) ok, \(session.commandTelemetry.failureCount) fail)")
                }
            }
            .padding(.top, 6)
        } label: {
            sectionLabel("Details")
        }
    }

    // MARK: - Primitives

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(HolyGhosttyTheme.halo.opacity(0.55))
            .textCase(.uppercase)
            .tracking(0.6)
    }

    private func contextRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(key)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(HolyGhosttyTheme.textTertiary)
                .frame(width: 70, alignment: .trailing)

            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(HolyGhosttyTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func signalColor(_ kind: HolySessionSignalKind) -> Color {
        switch kind {
        case .failure:      return HolyGhosttyTheme.danger
        case .approval:     return HolyGhosttyTheme.warning
        case .completion:   return HolyGhosttyTheme.success
        case .coordination: return HolyGhosttyTheme.warning
        case .command:      return HolyGhosttyTheme.accent
        case .progress, .reading, .editing: return HolyGhosttyTheme.accent
        }
    }

    private func runtimeTint(for kind: HolySessionActivityKind) -> Color {
        switch kind {
        case .approval:
            return HolyGhosttyTheme.warning
        case .stalled, .looping:
            return HolyGhosttyTheme.warning
        case .failure:
            return HolyGhosttyTheme.danger
        case .completion:
            return HolyGhosttyTheme.success
        case .progress, .reading, .editing, .command:
            return HolyGhosttyTheme.accent
        case .idle:
            return HolyGhosttyTheme.textTertiary
        }
    }

    private func fileColor(_ category: HolyGitFileChangeCategory) -> Color {
        switch category {
        case .added, .copied:                        return HolyGhosttyTheme.success
        case .modified, .renamed, .typeChanged:      return HolyGhosttyTheme.accent
        case .deleted:                               return HolyGhosttyTheme.danger
        case .conflicted:                            return HolyGhosttyTheme.danger
        case .untracked, .unknown:                   return HolyGhosttyTheme.textTertiary
        }
    }

    private func budgetTint(for session: HolySession) -> Color {
        switch session.budgetStatus {
        case .none: return HolyGhosttyTheme.textTertiary
        case .healthy: return HolyGhosttyTheme.success
        case .warning: return HolyGhosttyTheme.warning
        case .exceeded: return HolyGhosttyTheme.danger
        }
    }

    private func timelineRefreshID(for session: HolySession) -> String {
        let runtimeUpdatedAt = session.runtimeTelemetry.lastUpdatedAt?.timeIntervalSince1970 ?? 0
        return "\(session.id.uuidString)-\(session.activityAt.timeIntervalSince1970)-\(runtimeUpdatedAt)-\(session.phase.rawValue)"
    }

    private func budgetRefreshID(for session: HolySession) -> String {
        let budgetUpdatedAt = session.budgetTelemetry.lastUpdatedAt?.timeIntervalSince1970 ?? 0
        return "\(session.id.uuidString)-\(session.activityAt.timeIntervalSince1970)-\(budgetUpdatedAt)-\(session.budgetStatus.rawValue)"
    }

    // MARK: - Verification

    @ViewBuilder
    private func verificationSection(_ session: HolySession) -> some View {
        let telemetry = session.commandTelemetry
        if telemetry.runCount > 0 {
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("Verification")

                HStack(spacing: 6) {
                    Circle()
                        .fill(verificationColor(for: telemetry))
                        .frame(width: 6, height: 6)
                    Text(telemetry.lastOutcomeText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(verificationColor(for: telemetry))
                }

                if telemetry.lastDurationNanoseconds != nil {
                    contextRow("Duration", telemetry.lastDurationText)
                }

                if let completedAt = telemetry.lastCompletedAt {
                    contextRow("When", Self.relativeTimeText(for: completedAt))
                }

                contextRow("Runs", "\(telemetry.runCount) (\(telemetry.successCount) ok, \(telemetry.failureCount) fail)")
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(verificationColor(for: telemetry).opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(verificationColor(for: telemetry).opacity(0.15), lineWidth: 0.5)
            )
        }
    }

    private func verificationColor(for telemetry: HolySessionCommandTelemetry) -> Color {
        guard let exitCode = telemetry.lastExitCode else {
            return HolyGhosttyTheme.textTertiary
        }
        return exitCode == 0 ? HolyGhosttyTheme.success : HolyGhosttyTheme.danger
    }

    private static func relativeTimeText(for date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        return "\(days)d ago"
    }

    // MARK: - Actions

    @ViewBuilder
    private func actionsSection(_ session: HolySession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Actions")

            VStack(spacing: 4) {
                actionButton("Copy handoff", systemImage: "doc.on.clipboard") {
                    copyHandoff(for: session)
                }
                actionButton("Copy diff", systemImage: "square.on.square") {
                    Task { await copyDiff(for: session) }
                }
                actionButton("Duplicate", systemImage: "plus.square.on.square") {
                    store.duplicate(session)
                }
                actionButton("Archive", systemImage: "archivebox", role: .destructive) {
                    store.archive(session)
                }
            }
        }
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 14, alignment: .center)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func copyHandoff(for session: HolySession) {
        let lines: [String] = [
            "Session: \(session.displayTitle)",
            "Runtime: \(session.displayRuntime.displayName)",
            "Phase: \(session.phase.rawValue)",
            "Directory: \(session.workingDirectory ?? "—")",
            session.gitSnapshot.map { "Branch: \($0.branchDisplayName)" } ?? "Branch: —",
            session.gitSnapshot.map { "Changes: \(Self.riskSummary(for: $0.changedFiles))" } ?? "",
            session.signals.first.map { "Signal: \($0.headline)" } ?? "",
        ].filter { !$0.isEmpty }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
    }

    private func copyDiff(for session: HolySession) async {
        guard let directory = session.workingDirectory, !directory.isEmpty else { return }
        let output = await Self.runSubprocess(
            executable: "/usr/bin/git",
            arguments: ["-C", directory, "diff", "--no-color"]
        )
        guard let text = output?.stdout, !text.isEmpty else { return }
        await MainActor.run {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
    }

    // MARK: - External peer probe (agent-do coord)

    private func refreshExternalPeers() async {
        let result = await Self.runSubprocess(
            executable: "/usr/bin/env",
            arguments: ["agent-do", "coord", "peers"],
            timeoutSeconds: 3
        )
        guard let result, result.exitCode == 0 else {
            await MainActor.run {
                externalPeers = []
                externalPeerError = result == nil ? "agent-do not available" : nil
            }
            return
        }
        let peers = HolyCoordPeer.parse(result.stdout)
        await MainActor.run {
            externalPeers = peers
            externalPeerError = nil
        }
    }

    fileprivate struct SubprocessOutput {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    fileprivate static func runSubprocess(
        executable: String,
        arguments: [String],
        timeoutSeconds: Double = 5
    ) async -> SubprocessOutput? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                let deadline = DispatchTime.now() + .milliseconds(Int(timeoutSeconds * 1000))
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    process.waitUntilExit()
                    group.leave()
                }
                if group.wait(timeout: deadline) == .timedOut {
                    process.terminate()
                    continuation.resume(returning: nil)
                    return
                }

                let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: SubprocessOutput(
                    stdout: stdout,
                    stderr: stderr,
                    exitCode: process.terminationStatus
                ))
            }
        }
    }
}

// MARK: - Coord peer model

struct HolyCoordPeer: Identifiable, Equatable {
    let id: String
    let label: String
    let detail: String?

    var displayLabel: String {
        if let detail, !detail.isEmpty {
            return "\(label) · \(detail)"
        }
        return label
    }

    /// Parses `agent-do coord peers` text output. Format is not formally documented
    /// across versions, so this is a tolerant line-wise parser: the first non-empty
    /// token becomes the ID/label, the rest of the line becomes detail. Header or
    /// empty-state lines that don't look like peer rows are skipped.
    static func parse(_ text: String) -> [HolyCoordPeer] {
        text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> HolyCoordPeer? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return nil }
                let lower = trimmed.lowercased()
                if lower.hasPrefix("no peers")
                    || lower.hasPrefix("peers:")
                    || lower.hasPrefix("#")
                    || lower.hasPrefix("active peers")
                    || lower.hasPrefix("---") {
                    return nil
                }
                let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                let head = String(parts[0])
                let tail = parts.count > 1
                    ? String(parts[1]).trimmingCharacters(in: .whitespaces)
                    : nil
                return HolyCoordPeer(id: head, label: head, detail: tail)
            }
    }
}

