import Foundation
import OSLog

/// The panel's brain-stem: runs `agent-do brief holy --json` and publishes
/// the parsed payload. NOT an inbox-engine source — the brief is one
/// composite call whose payload the panel renders directly (answer line,
/// threads, suggestions); the engine keeps carrying the Library sources
/// (manna backlog, gh browse, alerts).
///
/// The call is expensive: the engine sweeps gh internally (15s bound), joins
/// five sources, and may voice the paragraph through a model. So refreshes
/// are serialized with coalescing (the per-source engine's rule, applied to
/// one feed) and throttled: a focus flap must not burn a model call.
@MainActor
final class HolyBriefFeed: ObservableObject {
    @Published private(set) var payload: HolyBriefPayload?
    @Published private(set) var failureReason: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var refreshedAt: Date?

    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mitchellh.ghostty",
        category: "HolyBriefFeed"
    )

    /// The engine's internal gh sweep is bounded at 15s and the model voice
    /// adds seconds; double the observed worst case before declaring broken.
    static let commandTimeout: TimeInterval = 120
    /// A brief older than this refetches when the panel opens; younger, the
    /// cached payload stands. Matches the engine's visible poll cadence so
    /// panel-open cannot double the subprocess load between polls.
    static let staleAfter: TimeInterval = HolyInboxEngine.visiblePollInterval

    /// Caller context resolved at refresh time by the store.
    struct Context: Equatable, Sendable {
        var focusedRepoSlug: String?
        var focusedBoardPath: String?
    }

    private let contextProvider: @Sendable () async -> Context
    private let binaryPathOverride: String?
    private var running = false
    private var pendingRequested = false

    init(
        contextProvider: @escaping @Sendable () async -> Context,
        binaryPathOverride: String? = nil
    ) {
        self.contextProvider = contextProvider
        self.binaryPathOverride = binaryPathOverride
    }

    /// Coalesced: a refresh in flight absorbs requests into one follow-up.
    func requestRefresh(force: Bool = false) {
        if running {
            pendingRequested = true
            return
        }
        if !force, let refreshedAt, Date.now.timeIntervalSince(refreshedAt) < Self.staleAfter {
            return
        }
        running = true
        isRefreshing = true
        Task { [weak self] in
            guard let self else { return }
            await self.runOnce()
            self.running = false
            if self.pendingRequested {
                self.pendingRequested = false
                self.requestRefresh(force: true)
            } else {
                self.isRefreshing = false
            }
        }
    }

    private func runOnce() async {
        let context = await contextProvider()
        guard let binaryPath = await resolvedBinaryPath() else {
            applyFailure("The \(HolyGitHubInboxSource.binaryName) CLI was not found on PATH.")
            return
        }

        var arguments = ["brief", "holy", "--json"]
        if let slug = context.focusedRepoSlug {
            arguments += ["--focused-repo", slug]
        }
        if let board = context.focusedBoardPath {
            arguments += ["--focused-board", board]
        }

        let result = await HolyRestoreProcessRunner.run(
            executablePath: binaryPath,
            arguments: arguments,
            timeout: Self.commandTimeout,
            environment: await HolyGitHubInboxSource.sharedSubprocessEnvironment.value
        )

        switch result {
        case let .failure(reason):
            Self.logger.error("brief holy failed: \(reason, privacy: .public)")
            applyFailure(reason)
        case let .success(output):
            guard output.exitCode == 0 else {
                let stderr = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                Self.logger.error(
                    "brief holy exited \(output.exitCode): \(stderr, privacy: .public)"
                )
                let lastLine = stderr
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .last { !$0.isEmpty }
                applyFailure(
                    "brief holy exited with status \(output.exitCode)."
                        + (lastLine.map { " \($0)" } ?? "")
                )
                return
            }
            guard let parsed = HolyBriefPayload.parse(Data(output.stdout.utf8)) else {
                // The one branch mn-b2e2e9 taught us to never leave dark.
                Self.logger.error(
                    "brief holy payload outside contract \(HolyBriefPayload.supportedContract); head: \(String(output.stdout.prefix(300)), privacy: .public)"
                )
                applyFailure("brief holy returned a payload outside the pinned contract.")
                return
            }
            payload = parsed
            failureReason = nil
            refreshedAt = .now
        }
    }

    private func applyFailure(_ reason: String) {
        // A stale brief beats a blank pane: keep the last payload and let
        // the view annotate its age alongside the failure.
        failureReason = reason
        refreshedAt = .now
    }

    private func resolvedBinaryPath() async -> String? {
        if let binaryPathOverride {
            return FileManager.default.isExecutableFile(atPath: binaryPathOverride)
                ? binaryPathOverride
                : nil
        }
        return await HolyGitHubInboxSource.sharedBinaryPath.value
    }
}
