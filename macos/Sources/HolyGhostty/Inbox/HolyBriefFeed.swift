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

    /// Caller context resolved at refresh time by the store. Both values are
    /// PATHS: the engine resolves --focused-repo as a filesystem path (a
    /// slug like "org/repo" gets treated as relative and dies — verified
    /// live 2026-08-11, every source degraded from the app's "/" cwd).
    /// For a remote session the paths are HOST-LOCAL by construction (they
    /// derive from the session's discovered cwd on that host).
    struct Context: Equatable, Sendable {
        var focusedRepoPath: String?
        var focusedBoardPath: String?
        /// SSH destination when the focused session's transport is remote:
        /// the estate (board, coord, sessions index, repos) lives where the
        /// session lives, so the brief executes THERE (mn-7fbb07). Nil for
        /// local sessions.
        var remoteHost: String?
    }

    /// The exact invocation for a context — pure, so the local/remote split
    /// is testable without a subprocess. Remote rides the same SSH shape as
    /// HolyRemoteTmuxDiscoveryService: BatchMode (never an interactive
    /// prompt), tight connect timeout, one `zsh -lc` so the REMOTE login
    /// shell resolves agent-do and its own ANTHROPIC_API_KEY. Credentials
    /// are never forwarded — each host owns its secrets.
    nonisolated static func invocation(
        for context: Context,
        localBinaryPath: String
    ) -> (executablePath: String, arguments: [String], usesLocalKey: Bool) {
        var briefArguments = ["brief", "holy", "--json"]
        if let repo = context.focusedRepoPath {
            briefArguments += ["--focused-repo", repo]
        }
        if let board = context.focusedBoardPath {
            briefArguments += ["--focused-board", board]
        }

        guard let remoteHost = context.remoteHost else {
            return (localBinaryPath, briefArguments, usesLocalKey: true)
        }

        let remoteCommand = (["agent-do"] + briefArguments.dropFirst(0))
            .map(posixQuote)
            .joined(separator: " ")
        return (
            "/usr/bin/ssh",
            [
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=5",
                "-o", "ServerAliveInterval=5",
                "-o", "ServerAliveCountMax=1",
                remoteHost,
                "zsh -lc \(posixQuote(remoteCommand))",
            ],
            usesLocalKey: false
        )
    }

    private nonisolated static func posixQuote(_ value: String) -> String {
        value.isEmpty
            ? "''"
            : "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
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

        // A remote brief needs no local agent-do; the remote login shell
        // resolves its own. Only the local path needs the binary probe.
        var localBinaryPath = ""
        if context.remoteHost == nil {
            guard let resolved = await resolvedBinaryPath() else {
                applyFailure("The \(HolyGitHubInboxSource.binaryName) CLI was not found on PATH.")
                return
            }
            localBinaryPath = resolved
        }

        let invocation = Self.invocation(for: context, localBinaryPath: localBinaryPath)
        // One line per refresh naming the rail: reading this beats guessing
        // which machine computed the estate (mn-7fbb07 diagnosis, 2026-08-11:
        // a local run with remote paths degrades exactly git+board+reconcile
        // while the machine-global sources survive).
        Self.logger.error(
            "brief invocation: \(context.remoteHost.map { "remote via \($0)" } ?? "local", privacy: .public) repo=\(context.focusedRepoPath ?? "none", privacy: .public)"
        )

        // The voice key overlays HERE and nowhere else — the brief is the
        // one subprocess that needs it (security review 2026-08-11). Local
        // runs only: a remote host resolves its own key from its own shell
        // or creds store; forwarding a local secret over SSH would leak it
        // to a machine that never asked for it.
        var environment = await HolyGitHubInboxSource.sharedSubprocessEnvironment.value
        if invocation.usesLocalKey,
           let voiceKey = await HolyGitHubInboxSource.anthropicKeyFromLoginShell.value {
            environment["ANTHROPIC_API_KEY"] = voiceKey
        }

        let result = await HolyRestoreProcessRunner.run(
            executablePath: invocation.executablePath,
            arguments: invocation.arguments,
            timeout: Self.commandTimeout,
            environment: environment,
            currentDirectoryPath: context.remoteHost == nil
                ? (context.focusedRepoPath
                    ?? FileManager.default.homeDirectoryForCurrentUser.path)
                : nil
        )

        switch result {
        case let .failure(reason):
            let located = context.remoteHost.map { "via \($0): \(reason)" } ?? reason
            Self.logger.error("brief holy failed \(located, privacy: .public)")
            applyFailure(located)
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
                let hostPrefix = context.remoteHost.map { "via \($0) " } ?? ""
                applyFailure(
                    "brief holy \(hostPrefix)exited with status \(output.exitCode)."
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
