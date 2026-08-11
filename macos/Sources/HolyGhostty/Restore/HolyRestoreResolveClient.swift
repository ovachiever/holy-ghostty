import Foundation

/// One resolve question: which provider conversation was running in this
/// working directory around this time? Mirrors the pinned agent-sessions
/// `resolve` contract (05-RESOLVE-CLI.md) exactly; the id that comes back is
/// data, never shell source.
struct HolyRestoreResolveQuery: Equatable, Sendable {
    let workingDirectory: String
    /// Holy's runtime raw value (`claude`/`codex`/`opencode`), passed through
    /// as `--harness` per the contract.
    let harness: String
    /// The archived session's last-activity time. The index stores unix
    /// SECONDS; a millisecond epoch here would silently miss every window.
    let nearUnixSeconds: Int
    var windowSeconds: Int?
    var limit: Int?

    var arguments: [String] {
        var arguments = [
            "resolve",
            "--cwd", workingDirectory,
            "--harness", harness,
            "--near", String(nearUnixSeconds),
        ]
        if let windowSeconds {
            arguments += ["--window", String(windowSeconds)]
        }
        if let limit {
            arguments += ["--limit", String(limit)]
        }
        // Non-negotiable: a single resolve must never trigger a full 2.5GB
        // reindex. Post-reboot, concurrent implicit reindexes starved four of
        // Erik's rows into 90-second timeouts; batch resolution owns reindex
        // scoping, single resolves are lookups only.
        arguments.append("--no-reindex")
        arguments.append("--json")
        return arguments
    }
}

struct HolyRestoreResolveCandidate: Equatable, Sendable, Identifiable {
    let id: String
    let timestampEnd: Int
    let preview: String
}

/// A successfully parsed resolve payload. `confidence` is law: "exact"
/// restores, "ambiguous" opens the candidate picker, "none" offers an honest
/// shell-only recreate.
struct HolyRestoreResolution: Equatable, Sendable {
    enum Confidence: String, Sendable {
        case exact
        case ambiguous
        case none
    }

    let matched: Bool
    let providerSessionID: String?
    let harness: String?
    let runtime: String?
    let projectPath: String?
    let resumeCommand: String?
    let confidence: Confidence
    let candidates: [HolyRestoreResolveCandidate]

    /// Parses the single JSON object the CLI prints to stdout. Fail-closed:
    /// any shape outside the pinned contract (unknown confidence, matched
    /// without an id, non-object payload) returns nil so callers degrade to
    /// resolver-unavailable instead of restoring a guess.
    static func parse(_ data: Data) -> HolyRestoreResolution? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let confidence = Confidence(rawValue: payload.confidence) else {
            return nil
        }
        if payload.matched, payload.id?.isEmpty != false {
            return nil
        }

        return .init(
            matched: payload.matched,
            providerSessionID: payload.id,
            harness: payload.harness,
            runtime: payload.runtime,
            projectPath: payload.projectPath,
            resumeCommand: payload.resumeCommand,
            confidence: confidence,
            candidates: (payload.candidates ?? []).map {
                .init(id: $0.id, timestampEnd: $0.timestampEnd, preview: $0.preview ?? "")
            }
        )
    }

    private struct Payload: Decodable {
        let matched: Bool
        let id: String?
        let harness: String?
        let runtime: String?
        let projectPath: String?
        let resumeCommand: String?
        let confidence: String
        let candidates: [CandidatePayload]?

        enum CodingKeys: String, CodingKey {
            case matched
            case id
            case harness
            case runtime
            case projectPath = "project_path"
            case resumeCommand = "resume_command"
            case confidence
            case candidates
        }
    }

    private struct CandidatePayload: Decodable {
        let id: String
        let timestampEnd: Int
        let preview: String?

        enum CodingKeys: String, CodingKey {
            case id
            case timestampEnd = "timestamp_end"
            case preview
        }
    }
}

enum HolyRestoreResolveOutcome: Equatable, Sendable {
    case resolved(HolyRestoreResolution)
    /// The CLI is missing, crashed, timed out, or violated the contract.
    /// Rows degrade to a retryable blocked state; nothing restores blind.
    case resolverUnavailable(String)
}

protocol HolyRestoreResolving: Sendable {
    func resolve(_ query: HolyRestoreResolveQuery) async -> HolyRestoreResolveOutcome
}

// MARK: - Batch resolution

/// One row's question inside a `resolve-batch` call. The whole sheet ships
/// as one subprocess invocation so the CLI can scope a single reindex for
/// everything instead of stampeding one full reindex per row.
struct HolyRestoreResolveBatchRequest: Equatable, Sendable, Encodable {
    let cwd: String
    let harness: String
    /// Unix SECONDS, same law as the single-resolve `--near`.
    let near: Int
}

/// The full batch invocation. stdin carries `{"requests": [...]}`; stdout
/// returns `{"results": [...]}` with per-request candidate lists best-first.
struct HolyRestoreResolveBatchQuery: Equatable, Sendable {
    let requests: [HolyRestoreResolveBatchRequest]

    var arguments: [String] { ["resolve-batch", "--json"] }

    /// The exact stdin payload. Sorted keys keep the byte shape deterministic
    /// for tests and for diffing against the CLI's own fixtures.
    func stdinPayload() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(Envelope(requests: requests))
    }

    private struct Envelope: Encodable {
        let requests: [HolyRestoreResolveBatchRequest]
    }
}

/// One request's answer. POSITIONAL: `results[i]` answers `requests[i]`,
/// always — duplicates included, nothing omitted. The echoed `harness` is
/// canonicalized by the CLI (a "claude" request comes back "claude-code"),
/// so matching results to requests by coordinates would silently miss;
/// callers must pair by index. No confidence field — with global assignment
/// the verdict (exact / ambiguous / none) is derived in the app, across
/// rows, never per row.
struct HolyRestoreResolveBatchResult: Equatable, Sendable {
    let cwd: String
    /// Canonical harness ("claude-code"), never null; echoes the input
    /// verbatim only in the unknown-harness error case.
    let harness: String
    let runtime: String
    let candidates: [HolyRestoreResolveCandidate]
    /// Per-request failure (e.g. unknown harness). The batch still exits 0;
    /// only this request degrades.
    let error: String?
}

/// Parses the single JSON object `resolve-batch` prints to stdout.
/// Fail-closed like the single-resolve parser: any payload without a
/// `results` array (or with malformed entries) returns nil so callers
/// degrade to resolver-unavailable instead of assigning guesses.
struct HolyRestoreBatchResolution: Equatable, Sendable {
    let results: [HolyRestoreResolveBatchResult]

    static func parse(_ data: Data) -> HolyRestoreBatchResolution? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return nil
        }
        return .init(results: payload.results.map { result in
            .init(
                cwd: result.cwd,
                harness: result.harness,
                runtime: result.runtime,
                candidates: (result.candidates ?? []).map {
                    .init(id: $0.id, timestampEnd: $0.timestampEnd, preview: $0.preview ?? "")
                },
                error: result.error
            )
        })
    }

    private struct Payload: Decodable {
        let results: [ResultPayload]
    }

    private struct ResultPayload: Decodable {
        let cwd: String
        let harness: String
        let runtime: String
        let candidates: [CandidatePayload]?
        let error: String?
    }

    private struct CandidatePayload: Decodable {
        let id: String
        let timestampEnd: Int
        let preview: String?

        enum CodingKeys: String, CodingKey {
            case id
            case timestampEnd = "timestamp_end"
            case preview
        }
    }
}

enum HolyRestoreBatchResolveOutcome: Equatable, Sendable {
    case resolved([HolyRestoreResolveBatchResult])
    /// The CLI is missing, lacks resolve-batch, crashed, timed out, or
    /// violated the contract. Every unresolved row degrades to a retryable
    /// blocked state; nothing restores blind.
    case resolverUnavailable(String)
}

protocol HolyRestoreBatchResolving: Sendable {
    func resolveBatch(
        _ requests: [HolyRestoreResolveBatchRequest]
    ) async -> HolyRestoreBatchResolveOutcome
}

/// Production bridge to the installed `agent-sessions` binary. The binary is
/// PATH-resolved through a login shell once (a Dock launch does not inherit
/// Homebrew or pyenv bin directories) and then always invoked directly with
/// an argument array — the query never passes through shell source.
struct HolyAgentSessionsResolveClient: HolyRestoreResolving {
    static let binaryName = "agent-sessions"
    /// Single resolves always pass --no-reindex, so they are pure index
    /// lookups; this ceiling is generous headroom, not reindex budget.
    static let commandTimeout: TimeInterval = 90
    /// One batch call covers the whole sheet including the CLI's own scoped
    /// reindex; the sheet must reach an actionable state in seconds, so a
    /// batch that cannot finish inside this window is declared broken and
    /// every pending row degrades to a retryable blocked state.
    static let batchTimeout: TimeInterval = 30

    private let binaryPathOverride: String?

    init(binaryPathOverride: String? = nil) {
        self.binaryPathOverride = binaryPathOverride
    }

    func resolve(_ query: HolyRestoreResolveQuery) async -> HolyRestoreResolveOutcome {
        guard let binaryPath = await resolvedBinaryPath() else {
            return .resolverUnavailable(
                "The \(Self.binaryName) CLI was not found on PATH. Install it to resolve conversations; sessions can still be recreated as shells."
            )
        }

        let result = await HolyRestoreProcessRunner.run(
            executablePath: binaryPath,
            arguments: query.arguments,
            timeout: Self.commandTimeout
        )

        switch result {
        case let .failure(reason):
            return .resolverUnavailable(reason)
        case let .success(output):
            guard output.exitCode == 0 else {
                let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return .resolverUnavailable(
                    "\(Self.binaryName) resolve exited with status \(output.exitCode)."
                        + (detail.isEmpty ? "" : " \(detail)")
                )
            }
            guard let resolution = HolyRestoreResolution.parse(Data(output.stdout.utf8)) else {
                return .resolverUnavailable(
                    "\(Self.binaryName) resolve returned a payload outside the pinned contract."
                )
            }
            return .resolved(resolution)
        }
    }

    fileprivate func resolvedBinaryPath() async -> String? {
        if let binaryPathOverride {
            return FileManager.default.isExecutableFile(atPath: binaryPathOverride)
                ? binaryPathOverride
                : nil
        }
        return await Self.sharedBinaryPath.value
    }

    /// One PATH lookup per app lifetime; a missing binary is re-checked only
    /// on relaunch, which matches how often PATH realistically changes.
    private static let sharedBinaryPath = Task<String?, Never> {
        let result = await HolyRestoreProcessRunner.run(
            executablePath: "/bin/zsh",
            arguments: ["-lc", "command -v \(binaryName)"],
            timeout: 15
        )
        if case let .success(output) = result, output.exitCode == 0 {
            let path = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                return path
            }
        }
        return wellKnownBinaryPath()
    }

    /// A Dock launch gets a login (non-interactive) shell whose PATH misses
    /// managers initialized in .zshrc — pyenv shims on this machine. After
    /// the PATH probe misses, check the well-known install locations.
    static func wellKnownBinaryPath() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.pyenv/shims/\(binaryName)",
            "\(home)/.local/bin/\(binaryName)",
            "/opt/homebrew/bin/\(binaryName)",
            "/usr/local/bin/\(binaryName)",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

extension HolyAgentSessionsResolveClient: HolyRestoreBatchResolving {
    /// One subprocess call for the whole restore sheet. The CLI scopes any
    /// needed reindex internally — this is the fix for the post-reboot
    /// stampede where every per-row resolve raced its own full reindex.
    ///
    /// Staleness bound, and where the safety actually lives: the CLI skips
    /// the scoped refresh for a cwd claimed within the last 120 seconds, so
    /// a session that ended after the last refresh but before a rapid
    /// relaunch (rebuild-install-relaunch churn) can be genuinely absent
    /// from the answers. The index is NOT provably complete inside that
    /// window. Correctness rests on the degradation path instead: a missing
    /// conversation surfaces as a visible "no history found" row offering a
    /// shell-only recreate that a human must click, and reopening the sheet
    /// after the bound expires self-heals. Never build logic on top of this
    /// call that would turn that window into a silent failure.
    func resolveBatch(
        _ requests: [HolyRestoreResolveBatchRequest]
    ) async -> HolyRestoreBatchResolveOutcome {
        guard !requests.isEmpty else { return .resolved([]) }

        guard let binaryPath = await resolvedBinaryPath() else {
            return .resolverUnavailable(
                "The \(Self.binaryName) CLI was not found on PATH. Install it to resolve conversations; sessions can still be recreated as shells."
            )
        }

        let query = HolyRestoreResolveBatchQuery(requests: requests)
        guard let stdinPayload = query.stdinPayload() else {
            return .resolverUnavailable(
                "The resolve-batch request payload could not be encoded."
            )
        }

        let result = await HolyRestoreProcessRunner.run(
            executablePath: binaryPath,
            arguments: query.arguments,
            timeout: Self.batchTimeout,
            stdinData: stdinPayload
        )

        switch result {
        case let .failure(reason):
            return .resolverUnavailable(reason)
        case let .success(output):
            guard output.exitCode == 0 else {
                let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return .resolverUnavailable(
                    "\(Self.binaryName) resolve-batch exited with status \(output.exitCode)."
                        + (detail.isEmpty ? "" : " \(detail)")
                )
            }
            guard let resolution = HolyRestoreBatchResolution.parse(Data(output.stdout.utf8)) else {
                return .resolverUnavailable(
                    "\(Self.binaryName) resolve-batch returned a payload outside the pinned contract."
                )
            }
            return .resolved(resolution.results)
        }
    }
}

struct HolyRestoreProcessOutput: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

enum HolyRestoreProcessResult: Sendable {
    case success(HolyRestoreProcessOutput)
    case failure(String)
}

/// Minimal async process runner for restore-engine helpers: capped wall
/// clock, resume-once continuation, no shell unless the caller explicitly
/// invokes one.
enum HolyRestoreProcessRunner {
    static func run(
        executablePath: String,
        arguments: [String],
        timeout: TimeInterval,
        environment: [String: String]? = nil,
        stdinData: Data? = nil,
        currentDirectoryPath: String? = nil
    ) async -> HolyRestoreProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }
        // A Dock-launched app's cwd is "/", and estate tools (agent-do
        // brief/coord/git) anchor on the working directory — verified live
        // 2026-08-11: from "/" every relative resolution dies.
        if let currentDirectoryPath {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectoryPath)
        }
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let stdin: Pipe? = stdinData != nil ? Pipe() : nil
        if let stdin {
            process.standardInput = stdin
        }

        let resumeBox = ResumeBox()

        return await withCheckedContinuation { continuation in
            resumeBox.store(continuation)

            // Drain both pipes from launch, not after termination: a child
            // that writes more than the pipe buffer (~64KB) before exiting
            // would block forever against a post-exit read and die as a
            // fake timeout. `readDataToEndOfFile` on background queues
            // consumes continuously and returns at EOF.
            let collectedStdout = DataBox()
            let collectedStderr = DataBox()
            let drainGroup = DispatchGroup()

            process.terminationHandler = { finishedProcess in
                drainGroup.notify(queue: .global(qos: .utility)) {
                    resumeBox.resume(returning: .success(.init(
                        stdout: String(bytes: collectedStdout.take(), encoding: .utf8) ?? "",
                        stderr: String(bytes: collectedStderr.take(), encoding: .utf8) ?? "",
                        exitCode: finishedProcess.terminationStatus
                    )))
                }
            }

            do {
                try process.run()
            } catch {
                resumeBox.resume(returning: .failure(
                    holyDetailedProcessLaunchErrorDescription(error)
                ))
                return
            }

            drainGroup.enter()
            DispatchQueue.global(qos: .utility).async {
                collectedStdout.store(stdout.fileHandleForReading.readDataToEndOfFile())
                drainGroup.leave()
            }
            drainGroup.enter()
            DispatchQueue.global(qos: .utility).async {
                collectedStderr.store(stderr.fileHandleForReading.readDataToEndOfFile())
                drainGroup.leave()
            }

            if let stdin, let stdinData {
                // Payloads here are small (a JSON envelope for at most a few
                // dozen rows), far below pipe buffer size; write-then-close
                // cannot block against a reading child.
                try? stdin.fileHandleForWriting.write(contentsOf: stdinData)
                try? stdin.fileHandleForWriting.close()
            }

            Task.detached {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                resumeBox.resume(returning: .failure(
                    "\(URL(fileURLWithPath: executablePath).lastPathComponent) did not finish within \(Int(timeout)) seconds."
                ))
                if process.isRunning {
                    process.terminate()
                }
            }
        }
    }

    private final class DataBox: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func store(_ newData: Data) {
            lock.lock()
            defer { lock.unlock() }
            data = newData
        }

        func take() -> Data {
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }

    private final class ResumeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<HolyRestoreProcessResult, Never>?
        private var didResume = false

        func store(_ continuation: CheckedContinuation<HolyRestoreProcessResult, Never>) {
            lock.lock()
            defer { lock.unlock() }
            self.continuation = continuation
        }

        func resume(returning value: HolyRestoreProcessResult) {
            lock.lock()
            guard !didResume, let continuation else {
                lock.unlock()
                return
            }
            didResume = true
            self.continuation = nil
            lock.unlock()
            continuation.resume(returning: value)
        }
    }
}
