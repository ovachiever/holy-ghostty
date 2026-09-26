import Foundation
import OSLog

/// Statement-and-row accounting for every Archive database write, bucketed by
/// wall-clock minute and keyed by table and verb, so a steady write rate can
/// be attributed to a table instead of to the process. The per-minute log
/// line is off by default and turned on with
/// `defaults write org.holyghostty.app holy.archive.writeAccounting -bool true`
/// (unified log, subsystem = bundle identifier, category HolyArchiveWrites).
/// Every write statement in HolyArchiveRepository reports here, so a test can
/// assert exactly which rows a refresh touched and on which thread.
final class HolyArchiveWriteAccounting: @unchecked Sendable {
    static let defaultsKey = "holy.archive.writeAccounting"
    static let logCategory = "HolyArchiveWrites"

    static let shared = HolyArchiveWriteAccounting(
        isEnabled: { UserDefaults.standard.bool(forKey: HolyArchiveWriteAccounting.defaultsKey) }
    )

    enum Verb: String, Sendable, CaseIterable {
        case insert
        case update
        case delete
        case checkpoint
    }

    struct Key: Hashable, Sendable {
        let table: String
        let verb: Verb
    }

    struct Totals: Equatable, Sendable {
        var statements = 0
        var rows = 0
        /// Statements that ran while `Thread.isMainThread` was true. The
        /// restore path's contract is that this stays zero.
        var mainThreadStatements = 0

        mutating func add(rows: Int, onMainThread: Bool) {
            statements += 1
            self.rows += max(0, rows)
            if onMainThread { mainThreadStatements += 1 }
        }
    }

    struct Snapshot: Equatable, Sendable {
        var byKey: [Key: Totals] = [:]

        func totals(table: String, verb: Verb) -> Totals {
            byKey[Key(table: table, verb: verb)] ?? Totals()
        }

        func rows(table: String, verb: Verb) -> Int {
            totals(table: table, verb: verb).rows
        }

        func rows(table: String) -> Int {
            byKey.filter { $0.key.table == table }.values.reduce(0) { $0 + $1.rows }
        }

        func statements(table: String) -> Int {
            byKey.filter { $0.key.table == table }.values.reduce(0) { $0 + $1.statements }
        }

        var statements: Int { byKey.values.reduce(0) { $0 + $1.statements } }
        var rows: Int { byKey.values.reduce(0) { $0 + $1.rows } }
        var mainThreadStatements: Int { byKey.values.reduce(0) { $0 + $1.mainThreadStatements } }
    }

    typealias EnabledProvider = @Sendable () -> Bool
    typealias Clock = @Sendable () -> Date
    typealias Sink = @Sendable (String) -> Void

    /// The bucket width is the unit named in the log line, a minute.
    private static let secondsPerMinute: TimeInterval = 60

    private let lock = NSLock()
    private let isEnabled: EnabledProvider
    private let now: Clock
    private let sink: Sink
    private var cumulative: [Key: Totals] = [:]
    private var minuteBucket: [Key: Totals] = [:]
    private var minuteStart: Date?

    init(
        isEnabled: @escaping EnabledProvider,
        now: @escaping Clock = { .now },
        sink: Sink? = nil
    ) {
        self.isEnabled = isEnabled
        self.now = now
        if let sink {
            self.sink = sink
        } else {
            let logger = Logger(
                subsystem: Bundle.main.bundleIdentifier ?? "com.mitchellh.ghostty",
                category: Self.logCategory
            )
            self.sink = { line in logger.notice("\(line, privacy: .public)") }
        }
    }

    func record(table: String, verb: Verb, rows: Int) {
        guard isEnabled() else { return }
        let onMainThread = Thread.isMainThread
        let stamp = now()
        let key = Key(table: table, verb: verb)
        lock.lock()
        defer { lock.unlock() }
        rollMinuteLocked(at: stamp)
        cumulative[key, default: Totals()].add(rows: rows, onMainThread: onMainThread)
        minuteBucket[key, default: Totals()].add(rows: rows, onMainThread: onMainThread)
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(byKey: cumulative)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        cumulative = [:]
        minuteBucket = [:]
        minuteStart = nil
    }

    /// Emits the open minute bucket now instead of at the next rollover.
    func flush() {
        lock.lock()
        defer { lock.unlock() }
        emitLocked()
    }

    private func rollMinuteLocked(at stamp: Date) {
        let seconds = stamp.timeIntervalSince1970
        let start = Date(timeIntervalSince1970: (seconds / Self.secondsPerMinute).rounded(.down) * Self.secondsPerMinute)
        if let minuteStart, minuteStart == start { return }
        emitLocked()
        minuteStart = start
        minuteBucket = [:]
    }

    private func emitLocked() {
        guard let minuteStart, !minuteBucket.isEmpty else { return }
        sink(Self.line(for: minuteBucket, minuteStart: minuteStart))
        minuteBucket = [:]
    }

    static func line(for bucket: [Key: Totals], minuteStart: Date) -> String {
        let formatter = ISO8601DateFormatter()
        let entries = bucket.sorted { lhs, rhs in
            if lhs.value.rows != rhs.value.rows { return lhs.value.rows > rhs.value.rows }
            if lhs.key.table != rhs.key.table { return lhs.key.table < rhs.key.table }
            return lhs.key.verb.rawValue < rhs.key.verb.rawValue
        }.map { key, totals in
            var entry = "\(key.table) \(key.verb.rawValue) statements=\(totals.statements) rows=\(totals.rows)"
            if totals.mainThreadStatements > 0 {
                entry += " main_thread_statements=\(totals.mainThreadStatements)"
            }
            return entry
        }
        return "archive writes minute=\(formatter.string(from: minuteStart)) " + entries.joined(separator: "; ")
    }
}
