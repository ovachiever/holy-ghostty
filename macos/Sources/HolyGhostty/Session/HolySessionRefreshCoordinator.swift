import Foundation

/// Drives derived-state polling for every live `HolySession` from a single shared
/// cadence instead of one `Timer` per session.
///
/// With large rosters, per-session timers each woke the main actor on the same ~1.25s
/// cadence, producing a synchronized burst of layout/AttributeGraph work that stalled the
/// main thread. This coordinator runs one loop, scans the current sessions on each tick,
/// and refreshes only those that are due — spending at most a bounded amount of work per
/// tick so the main thread is never blocked, even with dozens of sessions.
@MainActor
final class HolySessionRefreshCoordinator {
    /// How often the coordinator wakes to scan for due sessions. The per-session minimum
    /// interval (visible vs. background) still gates whether each session actually refreshes.
    private static let tickInterval: Duration = .milliseconds(1_250)

    /// Maximum number of sessions refreshed in a single tick. Bounds main-thread cost so a
    /// large roster cannot produce an unbounded burst. Remaining due sessions are picked up
    /// on the next tick via the round-robin cursor.
    private static let maxRefreshesPerTick = 6

    private let sessionsProvider: () -> [HolySession]
    private var loopTask: Task<Void, Never>?
    private var scanCursor = 0

    init(sessionsProvider: @escaping () -> [HolySession]) {
        self.sessionsProvider = sessionsProvider
    }

    deinit {
        loopTask?.cancel()
    }

    func start() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tickInterval)
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    private func tick() {
        let sessions = sessionsProvider()
        guard !sessions.isEmpty else {
            scanCursor = 0
            return
        }

        let now = Date()
        let count = sessions.count
        if scanCursor >= count {
            scanCursor = 0
        }

        var refreshed = 0
        var examined = 0
        var index = scanCursor

        // Round-robin from the cursor so background sessions are not starved when the
        // per-tick budget is reached before the whole roster is scanned.
        while examined < count && refreshed < Self.maxRefreshesPerTick {
            let session = sessions[index]
            if session.isDueForDerivedStateRefresh(at: now) {
                session.refreshDerivedStateIfNeeded()
                refreshed += 1
            }
            index = (index + 1) % count
            examined += 1
        }

        scanCursor = index
    }
}
