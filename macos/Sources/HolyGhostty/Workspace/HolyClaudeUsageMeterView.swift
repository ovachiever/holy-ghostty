import SwiftUI

/// The Claude usage details sheet: reset times, burn-rate ETA, the
/// last-known numbers for every account Holy has seen, and the wrap-up
/// switch. The live numbers themselves render in the tmux green bar
/// (centred, via the @holy_usage_v1 server option the probe publishes);
/// this view is reached from the roster's … menu as "Claude Usage…".
struct HolyClaudeUsageDetailView: View {
    @ObservedObject var store: HolyWorkspaceStore
    var showsClose: Bool = false

    private var report: HolyClaudeUsageReport { store.claudeUsage }
    private var now: Date { store.attentionClock }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider().overlay(HolyGhosttyTheme.border)
            windows
            if !report.sessionReadings.isEmpty {
                Divider().overlay(HolyGhosttyTheme.border)
                sessions
            }
            if report.knownAccounts.count > 1 || (report.knownAccounts.first?.account.email != report.snapshot?.account.email) {
                Divider().overlay(HolyGhosttyTheme.border)
                accounts
            }
            Divider().overlay(HolyGhosttyTheme.border)
            actions
        }
        .padding(12)
        .frame(width: 360)
        .background(HolyGhosttyTheme.bgElevated)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle()
                    .fill(HolyClaudeUsagePalette.color(for: store.claudeUsageAssessment.level))
                    .frame(width: 8, height: 8)
                Text("Claude usage · \(store.claudeUsageAssessment.level.title)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(HolyGhosttyTheme.textPrimary)
                Spacer()
                if let fetched = report.snapshot?.fetchedAt, fetched > .distantPast {
                    Text("as of \(HolyClaudeUsageFormatting.relative(fetched, now: now))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(HolyGhosttyTheme.textTertiary)
                }
            }
            if let snapshot = report.snapshot {
                Text([snapshot.account.displayName, snapshot.account.tier].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(HolyGhosttyTheme.textSecondary)
                    .lineLimit(1)
                if let error = snapshot.error {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(HolyGhosttyTheme.warning)
                        .lineLimit(2)
                }
            } else if let failure = report.probeFailure {
                Text(failure)
                    .font(.system(size: 10))
                    .foregroundStyle(HolyGhosttyTheme.warning)
                    .lineLimit(2)
            }
            if let reason = store.claudeUsageAssessment.reason, store.claudeUsageAssessment.level > .normal {
                Text(reason)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(HolyClaudeUsagePalette.color(for: store.claudeUsageAssessment.level))
            }
        }
    }

    private var windows: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(report.snapshot?.buckets ?? []) { bucket in
                bucketRow(bucket)
            }
            if (report.snapshot?.buckets ?? []).isEmpty {
                Text("No windows reported yet.")
                    .font(.system(size: 10))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
            }
        }
    }

    private func bucketRow(_ bucket: HolyClaudeUsageBucket) -> some View {
        let level = HolyClaudeUsageEvaluator.level(for: bucket, policy: store.claudeUsagePolicy, now: now)?.level ?? .normal
        let fraction = min(max((bucket.percent ?? 0) / 100, 0), 1)
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(bucket.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(HolyGhosttyTheme.textPrimary)
                Spacer()
                Text(bucket.percent.map { HolyClaudeUsageEvaluator.formatPercent($0) } ?? "—")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(HolyClaudeUsagePalette.color(for: level))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous).fill(HolyGhosttyTheme.borderActive)
                    Capsule(style: .continuous)
                        .fill(HolyClaudeUsagePalette.color(for: level))
                        .frame(width: max(2, proxy.size.width * fraction))
                    // Threshold ticks so the margin is visible, not remembered.
                    ForEach([store.claudeUsagePolicy.warnPercent, store.claudeUsagePolicy.criticalPercent], id: \.self) { mark in
                        Rectangle()
                            .fill(HolyGhosttyTheme.textTertiary)
                            .frame(width: 1, height: 6)
                            .offset(x: proxy.size.width * mark / 100)
                    }
                }
            }
            .frame(height: 6)
            Text(HolyClaudeUsageFormatting.detail(for: bucket, now: now))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(HolyGhosttyTheme.textSecondary)
                .lineLimit(2)
        }
    }

    private var sessions: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sessions reporting their own windows")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(HolyGhosttyTheme.textSecondary)
            ForEach(report.sessionReadings) { reading in
                HStack(spacing: 6) {
                    Text(reading.workingDirectory.map { ($0 as NSString).lastPathComponent } ?? reading.sessionID.prefix(8).description)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(HolyGhosttyTheme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    ForEach(reading.buckets) { bucket in
                        let level = HolyClaudeUsageEvaluator.level(for: bucket, policy: store.claudeUsagePolicy, now: now)?.level ?? .normal
                        Text("\(bucket.shortLabel) \(bucket.percent.map { HolyClaudeUsageEvaluator.formatPercent($0) } ?? "—")")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(HolyClaudeUsagePalette.color(for: level))
                    }
                }
            }
        }
    }

    private var accounts: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Accounts Holy has seen (last known)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(HolyGhosttyTheme.textSecondary)
            ForEach(report.knownAccounts, id: \.account.displayName) { known in
                let isCurrent = known.account.email == report.snapshot?.account.email
                HStack(spacing: 6) {
                    Text(known.account.displayName)
                        .font(.system(size: 10, weight: isCurrent ? .semibold : .regular, design: .monospaced))
                        .foregroundStyle(isCurrent ? HolyGhosttyTheme.halo : HolyGhosttyTheme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    ForEach(known.buckets) { bucket in
                        Text("\(bucket.shortLabel) \(bucket.percent.map { HolyClaudeUsageEvaluator.formatPercent($0) } ?? "—")")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(HolyGhosttyTheme.textSecondary)
                    }
                    Text(HolyClaudeUsageFormatting.relative(known.fetchedAt, now: now))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(HolyGhosttyTheme.textTertiary)
                }
            }
            Text("Only the signed-in account is live. Run /login in any Claude session to switch; the meter follows the keychain.")
                .font(.system(size: 9))
                .foregroundStyle(HolyGhosttyTheme.textTertiary)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                store.refreshClaudeUsageNow()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if showsClose {
                Button("Close") {
                    store.claudeUsagePresented = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
            }

            Spacer()

            if report.wrapUpRequest != nil {
                Button {
                    store.cancelClaudeWrapUp()
                } label: {
                    Label("Cancel wrap-up", systemImage: "play.circle")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(HolyGhosttyTheme.success)
            } else {
                Button {
                    store.requestClaudeWrapUp()
                } label: {
                    Label("Wrap up all sessions", systemImage: "pause.circle")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(HolyGhosttyTheme.danger)
                .help("Every running Claude session is told, on its next tool call, to checkpoint and pause with a PAUSED note. Lasts \(Int(store.claudeUsagePolicy.leadMinutes)) minutes or until the keychain account changes.")
            }
        }
    }
}

enum HolyClaudeUsagePalette {
    static func color(for level: HolyClaudeUsageLevel) -> Color {
        switch level {
        case .normal: HolyGhosttyTheme.success
        case .warn: HolyGhosttyTheme.warning
        case .restrain: HolyGhosttyTheme.warning
        case .critical: HolyGhosttyTheme.danger
        case .capped: HolyGhosttyTheme.danger
        }
    }
}

enum HolyClaudeUsageFormatting {
    static func line(for bucket: HolyClaudeUsageBucket, now: Date) -> String {
        "\(bucket.label): \(bucket.percent.map { HolyClaudeUsageEvaluator.formatPercent($0) } ?? "—") · \(detail(for: bucket, now: now))"
    }

    static func detail(for bucket: HolyClaudeUsageBucket, now: Date) -> String {
        var parts: [String] = []
        if let resetsAt = bucket.resetsAt {
            parts.append("resets \(clock(resetsAt, now: now))")
        }
        if let rate = bucket.ratePercentPerHour, rate > 0 {
            parts.append(String(format: "%.1f%%/h", rate))
        }
        if let eta = bucket.etaFullAt, eta > now {
            parts.append("cap in ~\(HolyClaudeUsageEvaluator.formatMinutes(eta.timeIntervalSince(now)))")
        }
        if let severity = bucket.severity, severity.lowercased() != "normal" {
            parts.append("severity \(severity)")
        }
        return parts.isEmpty ? "no reset time reported" : parts.joined(separator: " · ")
    }

    static func clock(_ date: Date, now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        let sameDay = Calendar.autoupdatingCurrent.isDate(date, inSameDayAs: now)
        formatter.dateFormat = sameDay ? "h:mma" : "EEE h:mma"
        return formatter.string(from: date).lowercased()
    }

    static func relative(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 90 { return "\(max(0, Int(seconds)))s ago" }
        if seconds < 90 * 60 { return "\(Int(seconds / 60))m ago" }
        if seconds < 36 * 60 * 60 { return "\(Int(seconds / 3600))h ago" }
        return "\(Int(seconds / 86400))d ago"
    }
}
