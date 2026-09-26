import Foundation
import UserNotifications

/// The narrow slice of `UNUserNotificationCenter` the agent-alert retraction
/// path uses. Every call here is an XPC round trip into usernotificationsd
/// and one unified-log line, so the ledger below decides whether it is sent.
@MainActor
protocol HolyUserNotificationCenterClient: AnyObject {
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
    /// Identifiers of every pending request and delivered notification the
    /// center holds for this app. Asked once per launch, never per poll.
    func outstandingNotificationIdentifiers() async -> [String]
}

@MainActor
final class HolyLiveUserNotificationCenter: HolyUserNotificationCenterClient {
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func outstandingNotificationIdentifiers() async -> [String] {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        let delivered = await center.deliveredNotifications().map(\.request.identifier)
        return pending + delivered
    }
}

/// mn-3aeeef: the attention recompute used to retract an agent alert from
/// Notification Center on every poll for every acknowledged session, posted
/// or not (measured 2026-09-26: 2,304 log entries in 60 s, all
/// `com.apple.UserNotifications:Connections` remove calls across 14 ids).
///
/// The ledger remembers which agent-alert identifiers may still be pending or
/// delivered: those this process posted, plus those the center reported once
/// at launch (agent alerts deliberately survive relaunch). A retraction reaches
/// the center only for an identifier in that set, and then drops it, so a
/// repeated acknowledgement costs nothing.
@MainActor
final class HolyAgentNotificationLedger {
    private let center: HolyUserNotificationCenterClient
    private let identifierPrefix: String
    private var outstanding: Set<String> = []

    /// Non-nil while the one launch query is in flight. Retractions of ids the
    /// ledger does not know yet wait here until the center answers.
    private var seeding: SeedWindow?
    private var hasAskedCenter = false

    private struct SeedWindow {
        /// Unknown ids a retraction asked for; removed if the center has them.
        var awaitingSeed: Set<String> = []
        /// Known ids removed while the query ran; the older snapshot must not
        /// resurrect them.
        var retractedDuringSeed: Set<String> = []
    }

    init(
        center: HolyUserNotificationCenterClient? = nil,
        identifierPrefix: String = HolyAgentNotificationPolicy.requestIdentifierPrefix
    ) {
        self.center = center ?? HolyLiveUserNotificationCenter()
        self.identifierPrefix = identifierPrefix
    }

    /// True when a retraction for this identifier would reach the center.
    func isOutstanding(_ identifier: String) -> Bool {
        outstanding.contains(identifier)
    }

    /// Ask the center once which agent alerts survived the last run.
    func seedFromCenter() async {
        guard !hasAskedCenter else { return }
        hasAskedCenter = true
        seeding = SeedWindow()
        let reported = await center.outstandingNotificationIdentifiers()
        guard let window = seeding else { return }
        seeding = nil

        let seeded = Set(reported.filter { $0.hasPrefix(identifierPrefix) })
        outstanding.formUnion(seeded.subtracting(window.retractedDuringSeed))
        let owed = window.awaitingSeed.intersection(outstanding)
        retract(Array(owed))
    }

    /// Record a request handed to the center, before `add` completes, so a
    /// retraction racing the add still removes the pending form.
    func notePosting(_ identifier: String) {
        outstanding.insert(identifier)
        seeding?.retractedDuringSeed.remove(identifier)
        seeding?.awaitingSeed.remove(identifier)
    }

    /// The center refused the request: nothing is pending or delivered.
    func noteNotPosted(_ identifier: String) {
        outstanding.remove(identifier)
    }

    /// Remove the pending and delivered forms of every identifier this app
    /// may still have in Notification Center. Unknown identifiers are free.
    func retract(_ identifiers: [String]) {
        var known: [String] = []
        var seen: Set<String> = []
        for identifier in identifiers where seen.insert(identifier).inserted {
            if outstanding.remove(identifier) != nil {
                known.append(identifier)
                seeding?.retractedDuringSeed.insert(identifier)
            } else if seeding != nil {
                seeding?.awaitingSeed.insert(identifier)
            }
        }
        guard !known.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: known)
        center.removeDeliveredNotifications(withIdentifiers: known)
    }
}
