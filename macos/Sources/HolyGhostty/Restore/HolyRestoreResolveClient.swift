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
    var skipReindex: Bool = false

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
        if skipReindex {
            arguments.append("--no-reindex")
        }
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

/// Production bridge to the installed `agent-sessions` binary. The binary is
/// PATH-resolved through a login shell once (a Dock launch does not inherit
/// Homebrew or pyenv bin directories) and then always invoked directly with
/// an argument array — the query never passes through shell source.
struct HolyAgentSessionsResolveClient: HolyRestoreResolving {
    static let binaryName = "agent-sessions"
    /// Post-crash the first resolve triggers a full reindex of the provider
    /// stores; give it room before declaring the resolver broken.
    static let commandTimeout: TimeInterval = 90

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

    private func resolvedBinaryPath() async -> String? {
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
        guard case let .success(output) = result, output.exitCode == 0 else { return nil }
        let path = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
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
        environment: [String: String]? = nil
    ) async -> HolyRestoreProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let resumeBox = ResumeBox()

        return await withCheckedContinuation { continuation in
            resumeBox.store(continuation)

            process.terminationHandler = { finishedProcess in
                let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
                resumeBox.resume(returning: .success(.init(
                    stdout: String(bytes: stdoutData, encoding: .utf8) ?? "",
                    stderr: String(bytes: stderrData, encoding: .utf8) ?? "",
                    exitCode: finishedProcess.terminationStatus
                )))
            }

            do {
                try process.run()
            } catch {
                resumeBox.resume(returning: .failure(
                    holyDetailedProcessLaunchErrorDescription(error)
                ))
                return
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
