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
    case surfaceOrphan(matchKey: String)
    case repair(sessionID: UUID)
    case archive(sessionID: UUID)
}

enum HolyConvergePlanner {
    static func plan(
        roster: [HolyConvergeRosterEntry],
        discovered: [HolyConvergeDiscoveredEntry],
        reachableHostKeys: Set<String>,
        adoptableMatchKeys: Set<String> = []
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
