import Foundation

/// Retry schedule for automatic repair of a dead remote pane. Three attempts
/// with growing delays, then silence until a wake or manual Sync resets it.
struct HolyRepairBackoff {
    static let delays: [TimeInterval] = [4, 10, 25]

    private var attemptsBySessionID: [UUID: Int] = [:]

    mutating func nextDelay(for sessionID: UUID) -> TimeInterval? {
        let attempt = attemptsBySessionID[sessionID, default: 0]
        guard attempt < Self.delays.count else { return nil }
        attemptsBySessionID[sessionID] = attempt + 1
        return Self.delays[attempt]
    }

    mutating func reset(_ sessionID: UUID) {
        attemptsBySessionID.removeValue(forKey: sessionID)
    }

    mutating func resetAll() {
        attemptsBySessionID.removeAll()
    }
}
