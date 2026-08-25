import Foundation

/// Everything the meter and the notifier need from one probe cycle.
struct HolyClaudeUsageReport: Equatable, Sendable {
    let snapshot: HolyClaudeUsageSnapshot?
    /// Sessions that reported their own windows through the status-line helper.
    let sessionReadings: [HolyClaudeUsageSessionReading]
    /// Last-known snapshot per account e-mail, newest first. Only the signed-in
    /// account is live; the rest are what they were when they were signed in.
    let knownAccounts: [HolyClaudeUsageSnapshot]
    let wrapUpRequest: HolyClaudeUsageBridge.WrapUpRequest?
    /// Set when the probe process itself could not run (missing helper,
    /// non-zero exit without a readable snapshot).
    let probeFailure: String?
    let observedAt: Date

    static let empty = HolyClaudeUsageReport(
        snapshot: nil,
        sessionReadings: [],
        knownAccounts: [],
        wrapUpRequest: nil,
        probeFailure: nil,
        observedAt: .distantPast
    )
}

/// Runs the generated probe on the policy's cadence and reads back the files
/// it writes. Holy never talks to the network itself: the probe is the only
/// process that holds the token, and it holds it for one request.
actor HolyClaudeUsageMonitor {
    typealias ReportHandler = @MainActor @Sendable (HolyClaudeUsageReport) -> Void

    private var loop: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var paths: HolyClaudeUsageBridgePaths?
    private var policy: HolyClaudeUsagePolicy = .default
    private var handler: ReportHandler?

    func start(
        paths: HolyClaudeUsageBridgePaths,
        policy: HolyClaudeUsagePolicy,
        onReport: @escaping ReportHandler
    ) {
        self.paths = paths
        self.policy = policy
        self.handler = onReport
        restartLoop()
    }

    func stop() {
        loop?.cancel()
        loop = nil
        handler = nil
    }

    /// Runs the probe now instead of waiting for the next tick.
    func refreshNow() {
        guard handler != nil else { return }
        restartLoop()
    }

    /// Reads the on-disk state without running the probe. Used right after a
    /// wrap-up request or cancel so the UI reflects it immediately.
    func readCurrent() async -> HolyClaudeUsageReport? {
        guard let paths else { return nil }
        return Self.read(paths: paths, probeFailure: nil, now: .now)
    }

    private func restartLoop() {
        loop?.cancel()
        generation &+= 1
        let myGeneration = generation
        guard let paths, let handler else { return }
        let policy = self.policy
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, await self.generation == myGeneration else { return }
                let failure = await Self.runProbe(paths: paths, deadline: policy.pollSeconds)
                if Task.isCancelled { return }
                let report = Self.read(paths: paths, probeFailure: failure, now: .now)
                await handler(report)
                try? await Task.sleep(nanoseconds: UInt64(policy.pollSeconds * 1_000_000_000))
            }
        }
    }

    /// Returns a failure description, or nil when the probe exited cleanly.
    /// A non-zero exit is not a failure by itself: the probe writes its own
    /// error into the snapshot and exits 1 so shells can tell, and the reader
    /// surfaces that error text.
    private static func runProbe(paths: HolyClaudeUsageBridgePaths, deadline: TimeInterval) async -> String? {
        guard FileManager.default.isExecutableFile(atPath: paths.probeURL.path) else {
            return "usage probe is not installed"
        }
        let process = Process()
        process.executableURL = paths.probeURL
        process.arguments = []
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["HOLY_USAGE_DIR": paths.usageDirectoryURL.path]
        ) { _, new in new }
        process.standardOutput = FileHandle.nullDevice
        let stderr = Pipe()
        process.standardError = stderr

        return await withCheckedContinuation { continuation in
            let once = HolyOnce()
            process.terminationHandler = { finished in
                let errorText = String(
                    data: stderr.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let result: String?
                if finished.terminationReason == .uncaughtSignal {
                    result = "usage probe was killed (signal \(finished.terminationStatus))"
                } else {
                    result = errorText.isEmpty ? nil : errorText
                }
                once.run { continuation.resume(returning: result) }
            }
            do {
                try process.run()
            } catch {
                once.run { continuation.resume(returning: "usage probe failed to launch: \(error.localizedDescription)") }
                return
            }
            Task.detached {
                try? await Task.sleep(nanoseconds: UInt64(deadline * 1_000_000_000))
                if process.isRunning {
                    process.terminate()
                }
            }
        }
    }

    static func read(paths: HolyClaudeUsageBridgePaths, probeFailure: String?, now: Date) -> HolyClaudeUsageReport {
        let fileManager = FileManager.default
        var snapshot: HolyClaudeUsageSnapshot?
        if let data = try? Data(contentsOf: paths.latestURL) {
            snapshot = try? HolyClaudeUsageSnapshotParser.parseSnapshot(data)
        }

        var readings: [HolyClaudeUsageSessionReading] = []
        if let names = try? fileManager.contentsOfDirectory(atPath: paths.sessionsDirectoryURL.path) {
            for name in names where name.hasSuffix(".json") {
                let url = paths.sessionsDirectoryURL.appendingPathComponent(name)
                guard let data = try? Data(contentsOf: url),
                      let reading = try? HolyClaudeUsageSnapshotParser.parseSessionReading(data),
                      !reading.buckets.isEmpty else { continue }
                // A reading whose windows have all reset says nothing current.
                let live = reading.buckets.contains { bucket in
                    guard let resetsAt = bucket.resetsAt else { return true }
                    return resetsAt > now
                }
                if live { readings.append(reading) }
            }
        }
        readings.sort { $0.observedAt > $1.observedAt }

        var accounts: [HolyClaudeUsageSnapshot] = []
        if let names = try? fileManager.contentsOfDirectory(atPath: paths.accountsDirectoryURL.path) {
            for name in names where name.hasSuffix(".json") {
                let url = paths.accountsDirectoryURL.appendingPathComponent(name)
                guard let data = try? Data(contentsOf: url),
                      let known = try? HolyClaudeUsageSnapshotParser.parseSnapshot(data) else { continue }
                accounts.append(known)
            }
        }
        accounts.sort { $0.fetchedAt > $1.fetchedAt }

        return HolyClaudeUsageReport(
            snapshot: snapshot,
            sessionReadings: readings,
            knownAccounts: accounts,
            wrapUpRequest: HolyClaudeUsageBridge.activeWrapUpRequest(paths: paths, now: now),
            probeFailure: probeFailure,
            observedAt: now
        )
    }
}

/// Guarantees a continuation is resumed exactly once across the termination
/// handler, the launch-failure path, and the deadline.
private final class HolyOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        body()
    }
}
