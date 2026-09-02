import AppKit
import Foundation
import UserNotifications

/// The store's side of the Claude usage guard: runs the monitor while the
/// guard is installed, publishes each report, and raises a notification when
/// any window crosses a level for the first time.
extension HolyWorkspaceStore {
    func startClaudeUsageMonitoringIfInstalled() {
        let paths = HolyClaudeUsageBridgePaths.currentUser()
        let installed = HolyClaudeUsageBridge.currentUserInstallationState() == .installed
        claudeUsageGuardInstalled = installed
        let monitor = claudeUsageMonitor
        guard installed else {
            Task { await monitor.stop() }
            claudeUsage = .empty
            claudeUsageAssessment = .init(level: .normal, decidingBucket: nil, reason: nil)
            return
        }

        let policy = HolyClaudeUsagePolicy.fromUserDefaults()
        claudeUsagePolicy = policy
        // The guard hook reads the same file, so both sides apply one policy.
        try? HolyClaudeUsageBridge.writePolicy(policy, paths: paths)
        Task { [weak self] in
            await monitor.start(paths: paths, policy: policy) { [weak self] report in
                self?.applyClaudeUsageReport(report)
            }
            _ = self
        }
    }

    func refreshClaudeUsageNow() {
        let monitor = claudeUsageMonitor
        Task { await monitor.refreshNow() }
    }

    func requestClaudeWrapUp() {
        let paths = HolyClaudeUsageBridgePaths.currentUser()
        do {
            try HolyClaudeUsageBridge.requestWrapUp(
                paths: paths,
                policy: claudeUsagePolicy,
                accountEmail: claudeUsage.snapshot?.account.email,
                reason: "user asked all sessions to pause before switching accounts"
            )
        } catch {
            AppDelegate.logger.error(
                "Holy Claude usage wrap-up request failed: \(error.localizedDescription, privacy: .public)"
            )
        }
        reloadClaudeUsageFromDisk()
    }

    func cancelClaudeWrapUp() {
        let paths = HolyClaudeUsageBridgePaths.currentUser()
        do {
            try HolyClaudeUsageBridge.cancelWrapUp(paths: paths)
        } catch {
            AppDelegate.logger.error(
                "Holy Claude usage wrap-up cancel failed: \(error.localizedDescription, privacy: .public)"
            )
        }
        reloadClaudeUsageFromDisk()
    }

    private func reloadClaudeUsageFromDisk() {
        let monitor = claudeUsageMonitor
        Task { [weak self] in
            guard let report = await monitor.readCurrent() else { return }
            self?.applyClaudeUsageReport(report)
        }
    }

    func applyClaudeUsageReport(_ report: HolyClaudeUsageReport) {
        let now = report.observedAt
        claudeUsage = report
        let buckets = report.snapshot?.buckets ?? []
        let assessment = HolyClaudeUsageEvaluator.assess(buckets: buckets, policy: claudeUsagePolicy, now: now)
        claudeUsageAssessment = assessment
        notifyClaudeUsageTransitions(buckets: buckets, account: report.snapshot?.account, now: now)
    }

    /// One notification per bucket per upward level crossing; a downward
    /// crossing (a reset, or a switched account) clears the record so the
    /// next climb announces again. Identifiers are per bucket and level so a
    /// repeat replaces rather than stacks.
    private func notifyClaudeUsageTransitions(
        buckets: [HolyClaudeUsageBucket],
        account: HolyClaudeUsageAccount?,
        now: Date
    ) {
        var announced = claudeUsageAnnouncedLevelByBucket
        for bucket in buckets {
            guard let verdict = HolyClaudeUsageEvaluator.level(for: bucket, policy: claudeUsagePolicy, now: now) else {
                continue
            }
            let previous = announced[bucket.key] ?? .normal
            if verdict.level > previous {
                announced[bucket.key] = verdict.level
                deliverClaudeUsageNotification(
                    level: verdict.level,
                    reason: verdict.reason,
                    bucket: bucket,
                    account: account,
                    now: now
                )
            } else if verdict.level < previous {
                announced[bucket.key] = verdict.level
            }
        }
        for key in announced.keys where !buckets.contains(where: { $0.key == key }) {
            announced.removeValue(forKey: key)
        }
        claudeUsageAnnouncedLevelByBucket = announced
    }

    private func deliverClaudeUsageNotification(
        level: HolyClaudeUsageLevel,
        reason: String,
        bucket: HolyClaudeUsageBucket,
        account: HolyClaudeUsageAccount?,
        now: Date
    ) {
        let isCodex = bucket.key.hasPrefix("codex:")
        let vendor = isCodex ? "Codex" : "Claude"
        let title: String
        switch level {
        case .normal:
            return
        case .warn:
            title = "\(vendor) usage approaching cap"
        case .critical:
            title = isCodex
                ? "Codex usage cap imminent"
                : "Claude usage cap imminent — switch accounts"
            NSApp.requestUserAttention(.criticalRequest)
        case .capped:
            title = isCodex
                ? "Codex usage capped"
                : "Claude usage capped — workers will die"
            NSApp.requestUserAttention(.criticalRequest)
        }
        var bodyParts = [reason]
        bodyParts.append(HolyClaudeUsageFormatting.detail(for: bucket, now: now))
        if !isCodex, let email = account?.email {
            bodyParts.append("account \(email)")
        }
        // The guard hook speaks only to Claude sessions; codex lanes get the
        // human, not an injected instruction.
        bodyParts.append(isCodex
            ? "Codex lanes will hit this wall on their own; wind them down or spend a reset credit."
            : (level >= .critical
                ? "Sessions are being told to pause with a note. Run /login on an account with headroom."
                : "Sessions are being told to checkpoint. Consider switching accounts before the cap."))
        let body = bodyParts.joined(separator: " · ")

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["holyClaudeUsage": true]
        let identifier = "holy.claude-usage.\(bucket.key).\(level.rawValue)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                break
            case .notDetermined:
                guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            case .denied:
                return
            @unknown default:
                return
            }
            do {
                try await center.add(request)
            } catch {
                AppDelegate.logger.error(
                    "Holy Claude usage notification failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }
}
