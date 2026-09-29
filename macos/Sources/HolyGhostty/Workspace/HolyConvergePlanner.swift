import Foundation

/// Inputs and pure diff logic for roster convergence. The store snapshots
/// roster + discovery state into these value types; the planner never touches
/// live sessions, so every bucketing rule is unit-testable.
struct HolyConvergeRosterEntry: Equatable {
    let sessionID: UUID
    /// Stable identity: "<scheme>|<destination>|<socket>|<session-name>",
    /// nil when the session is not tmux-backed.
    let matchKey: String?
    /// "<scheme>|<destination>|<socket>" - reachability is judged per host.
    let hostKey: String?
    let localProcessExited: Bool
}

struct HolyConvergeDiscoveredEntry: Equatable {
    let matchKey: String
    let hostKey: String
    let attachedClientCount: Int
}

enum HolyConvergeAction: Equatable {
    case adoptArchived(matchKey: String)
    case adoptDiscovered(matchKey: String)
    case surfaceOrphan(matchKey: String)
    case repair(sessionID: UUID)
    case archive(sessionID: UUID)
}

enum HolyConvergePlanner {
    static func canAdoptDiscovered(
        _ session: HolyDiscoveredTmuxSession,
        knownLaunchSpecs: [HolySessionLaunchSpec]
    ) -> Bool {
        session.hasHolyProvenance && !knownLaunchSpecs.contains {
            HolyTmuxIdentityResolver.couldRefer(launchSpec: $0, to: session)
        }
    }

    static func plan(
        roster: [HolyConvergeRosterEntry],
        discovered: [HolyConvergeDiscoveredEntry],
        reachableHostKeys: Set<String>,
        adoptableMatchKeys: Set<String> = [],
        discoveredAdoptionMatchKeys: Set<String> = []
    ) -> [HolyConvergeAction] {
        var actions: [HolyConvergeAction] = []
        let discoveredByKey = Dictionary(
            discovered.map { ($0.matchKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let rosterKeys = Set(roster.compactMap(\.matchKey))
        var attachedKeys: Set<String> = []

        for entry in discovered
        where !rosterKeys.contains(entry.matchKey) && attachedKeys.insert(entry.matchKey).inserted {
            if adoptableMatchKeys.contains(entry.matchKey) {
                actions.append(.adoptArchived(matchKey: entry.matchKey))
            } else if discoveredAdoptionMatchKeys.contains(entry.matchKey) {
                actions.append(.adoptDiscovered(matchKey: entry.matchKey))
            } else {
                actions.append(.surfaceOrphan(matchKey: entry.matchKey))
            }
        }

        for entry in roster {
            guard let matchKey = entry.matchKey, let hostKey = entry.hostKey else { continue }

            if let discoveredEntry = discoveredByKey[matchKey] {
                // Dead = our process exited, or it runs while the remote
                // session shows zero clients (zombie). A nonzero count with a
                // live local process might be another machine's client, but
                // then the keepalive resolves it within ~60s via pane exit.
                let zombie = !entry.localProcessExited && discoveredEntry.attachedClientCount == 0
                if entry.localProcessExited || zombie {
                    actions.append(.repair(sessionID: entry.sessionID))
                }
            } else if reachableHostKeys.contains(hostKey) {
                actions.append(.archive(sessionID: entry.sessionID))
            }
        }

        return actions
    }
}

struct HolyConvergeReport: Equatable {
    enum Outcome: Equatable {
        case attached
        case adopted
        case repaired
        case unchanged
        case skipped(String)

        var description: String {
            switch self {
            case .attached: return "attached from history"
            case .adopted: return "adopted"
            case .repaired: return "repaired"
            case .unchanged: return "already attached"
            case let .skipped(reason): return "skipped: \(reason)"
            }
        }
    }

    struct Entry: Equatable {
        let host: String
        let session: String
        var outcome: Outcome
    }

    var entries: [String: Entry] = [:]
    var unreachableHosts: [String] = []
    var archivedCount = 0

    var summary: String {
        let outcomes = entries.values.map(\.outcome)
        let attached = outcomes.filter { $0 == .attached }.count
        let adopted = outcomes.filter { $0 == .adopted }.count
        let repaired = outcomes.filter { $0 == .repaired }.count
        let unchanged = outcomes.filter { $0 == .unchanged }.count
        let skipped = outcomes.filter { if case .skipped = $0 { return true }; return false }.count
        var text = "Sync: attached \(attached), adopted \(adopted), repaired \(repaired), unchanged \(unchanged), skipped \(skipped)"
        if archivedCount > 0 { text += ", archived \(archivedCount)" }
        if !unreachableHosts.isEmpty { text += "; \(unreachableHosts.count) hosts unreachable" }
        return text
    }

    var details: String {
        let rows = entries.values.sorted {
            ($0.host, $0.session) < ($1.host, $1.session)
        }.map { "\($0.host) / \($0.session): \($0.outcome.description)" }
        return ([summary] + rows + unreachableHosts.sorted().map { "Host unreachable: \($0)" }).joined(separator: "\n")
    }
}
