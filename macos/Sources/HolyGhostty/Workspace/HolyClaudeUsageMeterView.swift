import SwiftUI

/// Machine-wide Claude usage meter: one bar per window the signed-in account
/// reports, colored by how close it is to the cap. The full form is a
/// centered band in the sidebar footer, just above the view controls; the
/// compact form is a percent capsule in the collapsed rail. Clicking opens
/// the details popover with reset times, burn-rate ETA, the last-known
/// numbers for every account Holy has seen, and the wrap-up switch.
struct HolyClaudeUsageMeterView: View {
    @ObservedObject var store: HolyWorkspaceStore
    var compact: Bool = false

    @State private var showingDetails = false

    var body: some View {
        if store.claudeUsageGuardInstalled {
            if compact {
                meterButton(arrowEdge: .trailing) { compactBody }
            } else {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(HolyGhosttyTheme.border)
                        .frame(height: 0.5)
                    meterButton(arrowEdge: .top) { fullBody }
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                }
                .background(HolyGhosttyTheme.bgElevated)
            }
        }
    }

    private func meterButton(
        arrowEdge: Edge,
        @ViewBuilder label: () -> some View
    ) -> some View {
        Button {
            showingDetails.toggle()
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .help(helpText)
        .popover(isPresented: $showingDetails, arrowEdge: arrowEdge) {
            HolyClaudeUsageDetailView(store: store)
        }
    }

    private var report: HolyClaudeUsageReport { store.claudeUsage }
    private var assessment: HolyClaudeUsageAssessment { store.claudeUsageAssessment }
    private var buckets: [HolyClaudeUsageBucket] { report.snapshot?.buckets ?? [] }

    private var fullBody: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(HolyClaudeUsagePalette.color(for: assessment.level))
                .frame(width: 6, height: 6)
            if buckets.isEmpty {
                Text(report.snapshot?.error ?? report.probeFailure ?? "usage: waiting for first probe")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
                    .lineLimit(1)
            } else {
                ForEach(buckets) { bucket in
                    bar(for: bucket)
                }
            }
            if report.wrapUpRequest != nil {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(HolyGhosttyTheme.danger)
                    .help("Wrap-up requested: every session pauses on its next tool call")
            }
            if report.snapshot?.isStale == true {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(HolyGhosttyTheme.warning)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(HolyGhosttyTheme.bg.opacity(0.84))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(borderColor, lineWidth: 0.5)
        )
        .contentShape(Capsule(style: .continuous))
    }

    private var compactBody: some View {
        let worst = assessment.decidingBucket
        return Text(worst?.percent.map { HolyClaudeUsageEvaluator.formatPercent($0) } ?? "—")
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(HolyClaudeUsagePalette.color(for: assessment.level))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(width: 24, height: 18)
            .background(
                Capsule(style: .continuous)
                    .fill(HolyGhosttyTheme.bg.opacity(0.84))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(borderColor, lineWidth: 0.5)
            )
            .contentShape(Capsule(style: .continuous))
    }

    private func bar(for bucket: HolyClaudeUsageBucket) -> some View {
        let level = HolyClaudeUsageEvaluator.level(
            for: bucket,
            policy: store.claudeUsagePolicy,
            now: store.attentionClock
        )?.level ?? .normal
        let fraction = min(max((bucket.percent ?? 0) / 100, 0), 1)
        return HStack(spacing: 3) {
            Text(bucket.shortLabel)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(HolyGhosttyTheme.textSecondary)
                .lineLimit(1)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(HolyGhosttyTheme.borderActive)
                    Capsule(style: .continuous)
                        .fill(HolyClaudeUsagePalette.color(for: level))
                        .frame(width: max(2, proxy.size.width * fraction))
                }
            }
            .frame(width: 26, height: 4)
            Text(bucket.percent.map { HolyClaudeUsageEvaluator.formatPercent($0) } ?? "—")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(HolyClaudeUsagePalette.color(for: level))
                .lineLimit(1)
        }
    }

    private var borderColor: Color {
        switch assessment.level {
        case .normal: HolyGhosttyTheme.borderActive
        case .warn: HolyGhosttyTheme.warning.opacity(0.6)
        case .critical, .capped: HolyGhosttyTheme.danger.opacity(0.8)
        }
    }

    private var helpText: String {
        var lines: [String] = []
        if let snapshot = report.snapshot {
            lines.append("Claude usage · \(snapshot.account.displayName)")
            for bucket in snapshot.buckets {
                lines.append(HolyClaudeUsageFormatting.line(for: bucket, now: store.attentionClock))
            }
            if let error = snapshot.error {
                lines.append("probe: \(error)")
            }
        } else if let failure = report.probeFailure {
            lines.append("Claude usage probe: \(failure)")
        } else {
            lines.append("Claude usage: waiting for the first probe")
        }
        lines.append("Click for details, other accounts, and the wrap-up switch.")
        return lines.joined(separator: "\n")
    }
}

/// The popover behind the meter.
struct HolyClaudeUsageDetailView: View {
    @ObservedObject var store: HolyWorkspaceStore

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
