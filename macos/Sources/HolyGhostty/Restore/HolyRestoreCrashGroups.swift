import Foundation

/// Identity of one crash event on the restore surface.
///
/// Rows stamped by a cold-boot sweep share that sweep's boot-batch id; rows
/// persisted before the marker existed have only wall-clock proximity, so a
/// legacy cluster is identified by its anchor — the newest `archivedAt`
/// inside the cluster.
enum HolyRestoreCrashGroupKey: Hashable, Sendable {
    case stamped(UUID)
    case legacyCluster(anchor: Date)
}

/// Which section of the sheet a crash's rows live under. `fresh` is the
/// newest batch (the existing fresh section IS that crash); every earlier
/// crash is an `older` group. Lineage ticks speak in these ids so the
/// dual-membership flip Erik reserved stays a render change: the membership
/// map already names every section a source session appears in.
enum HolyRestoreCrashSectionID: Hashable, Sendable {
    case fresh
    case older(HolyRestoreCrashGroupKey)
}

/// One crash event's archived sessions, newest first.
struct HolyRestoreCrashGroup: Equatable, Identifiable {
    let key: HolyRestoreCrashGroupKey
    let newestArchivedAt: Date
    let sessions: [HolyArchivedSession]

    var id: HolyRestoreCrashGroupKey { key }
}

/// Partitions archived sessions into crash events. Same law as the store's
/// fresh/older split, generalized to every batch: stamped rows group by
/// exact boot-batch id; legacy unstamped rows cluster within
/// `HolyWorkspaceStore.legacyColdBootClusterWindow` of a fixed anchor — the
/// cluster's newest member, never a rolling neighbor, so a slow drizzle of
/// rows cannot chain two distinct reboots into one event.
enum HolyRestoreCrashGrouping {
    /// Groups ordered newest first. Deterministic for any input order: the
    /// sessions are totally ordered (archivedAt desc, then id) before
    /// clustering, and group ties break on the newest member's id.
    static func groups(from sessions: [HolyArchivedSession]) -> [HolyRestoreCrashGroup] {
        let sorted = sessions.sorted {
            if $0.archivedAt != $1.archivedAt { return $0.archivedAt > $1.archivedAt }
            return $0.id.uuidString < $1.id.uuidString
        }

        var stampedSessions: [UUID: [HolyArchivedSession]] = [:]
        var stampedOrder: [UUID] = []
        var legacyClusters: [[HolyArchivedSession]] = []

        for session in sorted {
            if let batchID = session.recoveryBootBatchID {
                if stampedSessions[batchID] == nil { stampedOrder.append(batchID) }
                stampedSessions[batchID, default: []].append(session)
                continue
            }
            if let clusterIndex = legacyClusters.indices.last,
               let anchor = legacyClusters[clusterIndex].first?.archivedAt,
               session.archivedAt >= anchor
                   .addingTimeInterval(-HolyWorkspaceStore.legacyColdBootClusterWindow) {
                legacyClusters[clusterIndex].append(session)
            } else {
                legacyClusters.append([session])
            }
        }

        var groups: [HolyRestoreCrashGroup] = stampedOrder.compactMap { batchID in
            guard let members = stampedSessions[batchID], let newest = members.first else {
                return nil
            }
            return .init(
                key: .stamped(batchID),
                newestArchivedAt: newest.archivedAt,
                sessions: members
            )
        }
        groups += legacyClusters.compactMap { members in
            guard let newest = members.first else { return nil }
            return .init(
                key: .legacyCluster(anchor: newest.archivedAt),
                newestArchivedAt: newest.archivedAt,
                sessions: members
            )
        }

        groups.sort {
            if $0.newestArchivedAt != $1.newestArchivedAt {
                return $0.newestArchivedAt > $1.newestArchivedAt
            }
            let lhs = $0.sessions.first?.id.uuidString ?? ""
            let rhs = $1.sessions.first?.id.uuidString ?? ""
            return lhs < rhs
        }
        return groups
    }
}
