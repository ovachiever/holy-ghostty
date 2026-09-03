import Foundation

/// How close a Claude.ai subscription window is to the cap that would kill
/// running work. Ordered so a snapshot's worst bucket decides the whole level.
/// `warn` only informs the user; `restrain` stops new spawns while the work in
/// hand continues; `critical` and `capped` wrap up now.
enum HolyClaudeUsageLevel: Int, Comparable, Codable, Sendable {
    case normal = 0
    case warn = 1
    case restrain = 2
    case critical = 3
    case capped = 4

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .normal: "Normal"
        case .warn: "Approaching cap"
        case .restrain: "No new spawns"
        case .critical: "Wrap up now"
        case .capped: "Capped"
        }
    }
}

/// One rate-limit window as Anthropic reports it for the signed-in account.
///
/// `key` is stable across polls (`session`, `weekly_all`,
/// `weekly_scoped:<model>`) so level transitions can be tracked per window.
struct HolyClaudeUsageBucket: Equatable, Identifiable, Sendable {
    let key: String
    let label: String
    let percent: Double?
    let severity: String?
    let resetsAt: Date?
    let windowSeconds: TimeInterval
    let isActive: Bool
    let ratePercentPerHour: Double?
    let etaFullAt: Date?

    var id: String { key }

    var shortLabel: String {
        switch key {
        case "session": return "5h"
        case "weekly_all": return "wk"
        default:
            if key.hasPrefix("weekly_scoped:") {
                return String(key.dropFirst("weekly_scoped:".count))
            }
            return key
        }
    }
}

struct HolyClaudeUsageAccount: Equatable, Sendable {
    var email: String?
    var accountUUID: String?
    var organization: String?
    var subscription: String?
    var tier: String?
    var tokenExpiresAt: Date?

    var displayName: String {
        email ?? accountUUID ?? "unknown account"
    }
}

/// The probe's normalized `latest.json`.
struct HolyClaudeUsageSnapshot: Equatable, Sendable {
    let fetchedAt: Date
    let account: HolyClaudeUsageAccount
    let buckets: [HolyClaudeUsageBucket]
    let extraUsageEnabled: Bool
    let error: String?
    /// Set when `buckets` were carried forward from an earlier successful
    /// probe because the latest one failed.
    let staleSince: Date?

    var isStale: Bool { staleSince != nil }

    func bucket(_ key: String) -> HolyClaudeUsageBucket? {
        buckets.first { $0.key == key }
    }
}

/// A running Claude session's own view of its 5-hour and weekly windows, as
/// written by Holy's status-line helper from Claude's `rate_limits` JSON.
/// This is the only source that stays accurate for a session whose account
/// differs from the one currently in the keychain.
struct HolyClaudeUsageSessionReading: Equatable, Identifiable, Sendable {
    let sessionID: String
    let observedAt: Date
    let paneID: String?
    let workingDirectory: String?
    let fiveHour: HolyClaudeUsageBucket?
    let sevenDay: HolyClaudeUsageBucket?

    var id: String { sessionID }

    var buckets: [HolyClaudeUsageBucket] {
        [fiveHour, sevenDay].compactMap { $0 }
    }
}

/// Thresholds that turn a usage number into an instruction. These are
/// preferences, not measurements: the cap itself is Anthropic's, the margin
/// Erik wants before it is his. Each default carries its reasoning so a
/// future change is a decision, not a guess.
struct HolyClaudeUsagePolicy: Equatable, Codable, Sendable {
    /// Percent of any window at which sessions tell the user about the limit
    /// and otherwise keep working as they were: switching accounts is the
    /// user's call, not the agent's. A quarter of a window is early enough to
    /// plan that switch without changing pace.
    var warnPercent: Double
    /// Percent at which new subagents, workflows, and long tasks stop while the
    /// work in hand continues; spawns are denied from here. One tenth of a
    /// window is the margin that lets a subagent-heavy swarm at >150k context
    /// finish its current step.
    var restrainPercent: Double
    /// Percent at which sessions must wrap up now and pause with a written
    /// note. One twentieth of a window is the margin between "commit and write
    /// the note" and "the API refuses the call".
    var criticalPercent: Double
    /// Minutes of projected time-to-cap (from the recent burn rate) that count
    /// as imminent regardless of percent. Long enough for a human to notice a
    /// notification and run /login on another account.
    var leadMinutes: Double
    /// Seconds between probes. The guard promises `leadMinutes` of warning, so
    /// sampling must be much finer than that; one minute keeps the meter within
    /// a minute of truth at the cost of a light request per minute.
    var pollSeconds: Double

    static let `default` = HolyClaudeUsagePolicy(
        warnPercent: 75,
        restrainPercent: 90,
        criticalPercent: 95,
        leadMinutes: 20,
        pollSeconds: 60
    )

    enum DefaultsKey {
        static let warnPercent = "holy.claudeUsage.warnPercent"
        static let restrainPercent = "holy.claudeUsage.restrainPercent"
        static let criticalPercent = "holy.claudeUsage.criticalPercent"
        static let leadMinutes = "holy.claudeUsage.leadMinutes"
        static let pollSeconds = "holy.claudeUsage.pollSeconds"
    }

    /// Reads overrides from `UserDefaults`; any key that is absent, zero, or
    /// out of order falls back to the default so a typo cannot silence the guard.
    static func fromUserDefaults(_ defaults: UserDefaults = .standard) -> HolyClaudeUsagePolicy {
        var policy = HolyClaudeUsagePolicy.default
        func override(_ key: String, into value: inout Double, valid: (Double) -> Bool) {
            guard defaults.object(forKey: key) != nil else { return }
            let candidate = defaults.double(forKey: key)
            if valid(candidate) { value = candidate }
        }
        override(DefaultsKey.warnPercent, into: &policy.warnPercent) { $0 > 0 && $0 < 100 }
        override(DefaultsKey.restrainPercent, into: &policy.restrainPercent) { $0 > 0 && $0 < 100 }
        override(DefaultsKey.criticalPercent, into: &policy.criticalPercent) { $0 > 0 && $0 <= 100 }
        override(DefaultsKey.leadMinutes, into: &policy.leadMinutes) { $0 > 0 }
        override(DefaultsKey.pollSeconds, into: &policy.pollSeconds) { $0 > 0 }
        if policy.restrainPercent < policy.warnPercent {
            policy.restrainPercent = policy.warnPercent
        }
        if policy.criticalPercent < policy.restrainPercent {
            policy.criticalPercent = policy.restrainPercent
        }
        return policy
    }

    /// The JSON the generated guard hook reads so both sides apply one policy.
    func policyFileJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self) + Data("\n".utf8)
    }

    private enum CodingKeys: String, CodingKey {
        case warnPercent = "warn_percent"
        case restrainPercent = "restrain_percent"
        case criticalPercent = "critical_percent"
        case leadMinutes = "lead_minutes"
        case pollSeconds = "poll_seconds"
    }
}

struct HolyClaudeUsageAssessment: Equatable, Sendable {
    let level: HolyClaudeUsageLevel
    /// The bucket that set the level, if any bucket reported a number.
    let decidingBucket: HolyClaudeUsageBucket?
    let reason: String?
}

/// The one place a usage number becomes a level. The generated guard hook
/// carries a Python mirror of exactly these rules; `HolyClaudeUsageGuardTests`
/// runs both against the same fixtures.
enum HolyClaudeUsageEvaluator {
    static func level(
        for bucket: HolyClaudeUsageBucket,
        policy: HolyClaudeUsagePolicy,
        now: Date
    ) -> (level: HolyClaudeUsageLevel, reason: String)? {
        guard let percent = bucket.percent else { return nil }
        let lead = policy.leadMinutes * 60
        if percent >= 100 {
            return (.capped, "\(bucket.label) is at \(formatPercent(percent))")
        }
        if percent >= policy.criticalPercent {
            return (.critical, "\(bucket.label) at \(formatPercent(percent))")
        }
        let remaining = bucket.etaFullAt?.timeIntervalSince(now)
        if let remaining, remaining <= lead {
            return (.critical, "\(bucket.label) at \(formatPercent(percent)), cap in ~\(formatMinutes(remaining)) at current pace")
        }
        if percent >= policy.restrainPercent {
            return (.restrain, "\(bucket.label) at \(formatPercent(percent))")
        }
        if let remaining, remaining <= lead * 2, percent >= policy.warnPercent / 2 {
            return (.warn, "\(bucket.label) at \(formatPercent(percent)), cap in ~\(formatMinutes(remaining)) at current pace")
        }
        if percent >= policy.warnPercent {
            return (.warn, "\(bucket.label) at \(formatPercent(percent))")
        }
        if let severity = bucket.severity?.lowercased(), severity != "normal", !severity.isEmpty {
            return (.warn, "\(bucket.label) reported severity \(severity) at \(formatPercent(percent))")
        }
        return (.normal, "\(bucket.label) at \(formatPercent(percent))")
    }

    static func assess(
        buckets: [HolyClaudeUsageBucket],
        policy: HolyClaudeUsagePolicy,
        now: Date
    ) -> HolyClaudeUsageAssessment {
        var worst: (level: HolyClaudeUsageLevel, bucket: HolyClaudeUsageBucket, reason: String)?
        for bucket in buckets {
            guard let verdict = level(for: bucket, policy: policy, now: now) else { continue }
            if worst == nil || verdict.level > worst!.level
                || (verdict.level == worst!.level && (bucket.percent ?? 0) > (worst!.bucket.percent ?? 0)) {
                worst = (verdict.level, bucket, verdict.reason)
            }
        }
        guard let worst else {
            return HolyClaudeUsageAssessment(level: .normal, decidingBucket: nil, reason: nil)
        }
        return HolyClaudeUsageAssessment(level: worst.level, decidingBucket: worst.bucket, reason: worst.reason)
    }

    static func formatPercent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    static func formatMinutes(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        return "\(minutes) min"
    }
}

enum HolyClaudeUsageSnapshotParserError: Error, Equatable {
    case notAnObject
    case unsupportedSchema(Int)
}

/// Decodes the probe's `latest.json` and the status-line helper's per-session
/// files. Tolerant of missing optional fields; strict about the schema number.
enum HolyClaudeUsageSnapshotParser {
    static let supportedSchema = 1

    static func parseSnapshot(_ data: Data) throws -> HolyClaudeUsageSnapshot {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HolyClaudeUsageSnapshotParserError.notAnObject
        }
        let schema = (object["schema"] as? NSNumber)?.intValue ?? 0
        guard schema == supportedSchema else {
            throw HolyClaudeUsageSnapshotParserError.unsupportedSchema(schema)
        }
        let accountObject = object["account"] as? [String: Any] ?? [:]
        let account = HolyClaudeUsageAccount(
            email: accountObject["email"] as? String,
            accountUUID: accountObject["account_uuid"] as? String,
            organization: accountObject["organization"] as? String,
            subscription: accountObject["subscription"] as? String,
            tier: accountObject["tier"] as? String,
            tokenExpiresAt: date(from: accountObject["token_expires_at"])
        )
        let buckets = (object["buckets"] as? [[String: Any]] ?? []).compactMap(bucket(from:))
        let extra = object["extra_usage"] as? [String: Any]
        return HolyClaudeUsageSnapshot(
            fetchedAt: date(from: object["fetched_at"]) ?? .distantPast,
            account: account,
            buckets: buckets,
            extraUsageEnabled: (extra?["enabled"] as? Bool) ?? false,
            error: object["error"] as? String,
            staleSince: date(from: object["stale_since"])
        )
    }

    static func parseSessionReading(_ data: Data) throws -> HolyClaudeUsageSessionReading {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HolyClaudeUsageSnapshotParserError.notAnObject
        }
        let sessionID = object["session_id"] as? String ?? ""
        func window(_ key: String, bucketKey: String, label: String, seconds: TimeInterval) -> HolyClaudeUsageBucket? {
            guard let entry = object[key] as? [String: Any],
                  let percent = number(entry["percent"]) else { return nil }
            return HolyClaudeUsageBucket(
                key: bucketKey,
                label: label,
                percent: percent,
                severity: nil,
                resetsAt: date(from: entry["resets_at"]),
                windowSeconds: seconds,
                isActive: true,
                ratePercentPerHour: nil,
                etaFullAt: nil
            )
        }
        return HolyClaudeUsageSessionReading(
            sessionID: sessionID,
            observedAt: date(from: object["t"]) ?? .distantPast,
            paneID: object["pane"] as? String,
            workingDirectory: object["cwd"] as? String,
            fiveHour: window("five_hour", bucketKey: "session", label: "Session (5h)", seconds: 5 * 60 * 60),
            sevenDay: window("seven_day", bucketKey: "weekly_all", label: "Week (all models)", seconds: 7 * 24 * 60 * 60)
        )
    }

    private static func bucket(from object: [String: Any]) -> HolyClaudeUsageBucket? {
        guard let key = object["key"] as? String else { return nil }
        return HolyClaudeUsageBucket(
            key: key,
            label: object["label"] as? String ?? key,
            percent: number(object["percent"]),
            severity: object["severity"] as? String,
            resetsAt: date(from: object["resets_at"]),
            windowSeconds: number(object["window_seconds"]) ?? 0,
            isActive: (object["is_active"] as? Bool) ?? false,
            ratePercentPerHour: number(object["rate_percent_per_hour"]),
            etaFullAt: date(from: object["eta_full_at"])
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber, !(value is Bool) {
            return number.doubleValue
        }
        return nil
    }

    private static func date(from value: Any?) -> Date? {
        guard let seconds = number(value) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
