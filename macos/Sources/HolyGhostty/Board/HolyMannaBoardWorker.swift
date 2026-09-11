import Foundation

struct HolyMannaWorkerProfile: Equatable {
    var runtime: HolySessionRuntime = .codex
    var model = ""
}

enum HolyMannaWorkerLaunchError: LocalizedError, Equatable {
    case runtimeMissing(HolySessionRuntime, host: String?)

    var errorDescription: String? {
        switch self {
        case let .runtimeMissing(runtime, host):
            return "The \(runtime.rawValue) executable was not found on \(host ?? "this Mac"). "
                + "Checked the login-shell PATH and known tool directories. No worker was opened."
        }
    }
}

/// One completed lookup per runtime and execution host for this app lifetime.
/// An in-flight lookup is shared too; a pending probe is never a missing tool.
actor HolyMannaWorkerExecutableResolver {
    typealias Probe = @Sendable (HolySessionRuntime, String?) async throws -> String?
    static let shared = HolyMannaWorkerExecutableResolver()

    private struct Key: Hashable {
        let runtime: HolySessionRuntime
        let remoteHost: String?
    }

    private let probe: Probe
    private var resolutions: [Key: Task<String?, Error>] = [:]

    init(probe: @escaping Probe = HolyMannaWorkerExecutableResolver.locate) {
        self.probe = probe
    }

    func binaryPath(runtime: HolySessionRuntime, remoteHost: String?) async throws -> String {
        guard runtime == .codex || runtime == .claude else {
            throw HolyMannaAskError.unavailable("Choose Codex or Claude for the board worker.")
        }
        let key = Key(runtime: runtime, remoteHost: remoteHost)
        let task: Task<String?, Error>
        if let pending = resolutions[key] {
            task = pending
        } else {
            task = Task { [probe] in try await probe(runtime, remoteHost) }
            resolutions[key] = task
        }
        let path: String?
        do {
            path = try await task.value
        } catch {
            // A transport/probe failure is not proof that the tool is absent.
            resolutions[key] = nil
            throw error
        }
        guard let path, Self.isAbsoluteExecutablePath(path) else {
            throw HolyMannaWorkerLaunchError.runtimeMissing(runtime, host: remoteHost)
        }
        return path
    }

    static func isAbsoluteExecutablePath(_ path: String) -> Bool {
        path.hasPrefix("/") && !path.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    /// The same bounded zsh login-shell probe runs on the execution host.
    /// Reuse restore's known installer locations, including every nvm version.
    static func probeScript(runtime: HolySessionRuntime) -> String {
        let name = runtime.rawValue
        let candidates = HolyRestoreExecutableSearch.wellKnownCandidates(
            name: name, home: "$HOME", nvmVersionDirectoryNames: []
        ) + ["$HOME/.npm-global/bin/\(name)", "$HOME/.npm/bin/\(name)"]
        let candidateArguments = candidates.map { "\"\($0)\"" }.joined(separator: " ")
        return """
        holy_worker_path=$(command -v \(name) 2>/dev/null)
        if [[ "$holy_worker_path" == /* && -f "$holy_worker_path" && -x "$holy_worker_path" ]]; then
          printf 'HOLY_WORKER_EXECUTABLE=%s\\n' "$holy_worker_path"
          exit 0
        fi
        for holy_worker_path in "$HOME"/.nvm/versions/node/v*/bin/\(name)(NnOn) \(candidateArguments); do
          if [[ -f "$holy_worker_path" && -x "$holy_worker_path" ]]; then
            printf 'HOLY_WORKER_EXECUTABLE=%s\\n' "$holy_worker_path"
            exit 0
          fi
        done
        exit 1
        """
    }

    static func probeInvocation(runtime: HolySessionRuntime, remoteHost: String?) throws -> HolyMannaProcessInvocation {
        let script = probeScript(runtime: runtime)
        if let host = remoteHost {
            // Keep the board's destination validation and managed SSH routing.
            _ = try HolyMannaBoardClient.remoteInvocation(
                arguments: [], context: .init(boardRoot: nil, remoteHost: host), needsBoardRoot: false, identity: nil
            )
            let transport = try HolySSHTransportManager.shared.command(
                destination: host, purpose: .control,
                options: ["-o", "BatchMode=yes", "-o", "ConnectTimeout=5"],
                remoteCommand: ["/bin/zsh -lc " + "'" + script.replacingOccurrences(of: "'", with: "'\\''") + "'"]
            )
            return .init(executablePath: transport.executablePath, arguments: transport.arguments,
                         currentDirectoryPath: nil, environment: [:], stdin: nil,
                         displayCommand: "\(host): locate \(runtime.rawValue)")
        }
        return .init(executablePath: "/bin/zsh", arguments: ["-lc", script],
                     currentDirectoryPath: nil, environment: [:], stdin: nil,
                     displayCommand: "locate \(runtime.rawValue)")
    }

    private static func locate(runtime: HolySessionRuntime, remoteHost: String?) async throws -> String? {
        let invocation = try probeInvocation(runtime: runtime, remoteHost: remoteHost)
        let output: HolyMannaProcessOutput
        if let host = remoteHost {
            output = try await HolySSHAdmissionController.shared.withControlPermit(for: host, operation: .metadata) {
                try await HolyMannaProcessRunner.run(invocation, 15)
            }
        } else {
            output = try await HolyMannaProcessRunner.run(invocation, 15)
        }
        if output.exitCode == 1 { return nil }
        guard output.exitCode == 0 else {
            throw HolyMannaBoardClientError.commandFailed(
                command: invocation.displayCommand, code: output.exitCode, detail: String(output.stderr.suffix(400))
            )
        }
        let prefix = "HOLY_WORKER_EXECUTABLE="
        return output.stdout.components(separatedBy: .newlines)
            .last { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }
}

struct HolyMannaWorkerDispatch: Equatable {
    let item: HolyMannaBoardItem
    let context: HolyMannaBoardContext
    let profile: HolyMannaWorkerProfile

    static func refusal(for item: HolyMannaBoardItem, context: HolyMannaBoardContext) -> String? {
        if item.kind == "dream" { return "Dreams cannot be claimed. Promote this dream before building it." }
        if item.status == "in_progress" || item.claimedBy != nil {
            return "Claimed by \(item.claimant?.label ?? item.claimedBy ?? "another worker")."
        }
        guard item.kind == "item", item.status == "open", item.effective == "ready" else {
            return "This item is not ready to claim (\(item.effective))."
        }
        guard let root = context.boardRoot, root.hasPrefix("/"), !root.contains("\u{0}") else {
            return "The board needs an absolute repository path."
        }
        guard let prompt = item.prompt, !prompt.isEmpty, item.handoffExists != false else {
            return "This item needs a handoff before a worker can start."
        }
        guard item.handoffDigest?.isEmpty == false else { return "Seal the handoff before starting a worker." }
        return nil
    }

    var confirmation: String {
        "Start a new \(profile.runtime.rawValue) worker (\(profile.model.isEmpty ? "runtime default model" : profile.model)) "
            + "in \(context.remoteHost.map { "\($0):" } ?? "")\(context.boardRoot ?? "") for \(item.id)? "
            + "The worker will claim first and read \(item.prompt ?? ""). No launches, installs, screenshots, or push."
    }

    var brief: String {
        """
        Claim and build \(item.id) in \(context.boardRoot ?? "").

        First run: agent-do manna claim \(item.id)
        If the claim fails or another worker owns the item, stop and report the refusal. Never steal a claim.
        Then read the sealed handoff at \(item.prompt ?? "") (expected binding \(item.handoffDigest ?? "")).
        Verify the handoff against canonical Manna state; if missing, changed, or unsealed, stop and report.
        Read the nearest AGENTS.md and obey the repository's work order.
        Establish agent-do coord focus and path claims before editing. Preserve other workers' changes.
        Implement the handoff's acceptance requirements and keep the tree buildable.
        Run focused test suites only, using the repository's canonical validation commands.
        No app launches, installs, screenshots, or live session spawning mid-lane.
        App-hosted tests may be built, but must not launch the app. Coordinate the live/visual acceptance pass at close.
        Commit the verified change with a Conventional Commit and this exact trailer:
        Manna: \(item.id)
        Never push or create a pull request.
        Update and seal the handoff with verification receipts. Mark done only after required acceptance is verified.
        Standard report: outcome; changes; focused test/build commands and actual results; commit;
        remaining acceptance or blockers. Distinguish compiled tests from executed tests.
        Include Lessons logged: N (new) | Decisions logged: N (new).
        End the report with TL;DR (12th grade): a plain-language summary.
        """
    }

    func launchSpec(executablePath: String) throws -> HolySessionLaunchSpec {
        if let reason = Self.refusal(for: item, context: context) { throw HolyMannaAskError.unavailable(reason) }
        guard profile.runtime == .codex || profile.runtime == .claude else {
            throw HolyMannaAskError.unavailable("Choose Codex or Claude for the board worker.")
        }
        guard HolyMannaWorkerExecutableResolver.isAbsoluteExecutablePath(executablePath) else {
            throw HolyMannaWorkerLaunchError.runtimeMissing(profile.runtime, host: context.remoteHost)
        }
        if context.remoteHost != nil {
            // Reuse canonical SSH validation, including option-injection rejection.
            _ = try HolyMannaBoardClient.remoteInvocation(
                arguments: ["manna", "state", "--json"], context: context, needsBoardRoot: true, identity: nil
            )
        }
        var spec = HolySessionLaunchSpec.interactiveTmuxShell(
            title: URL(fileURLWithPath: context.boardRoot!).lastPathComponent
        )
        spec.runtime = profile.runtime
        spec.objective = "Claim and build \(item.id)"
        spec.note = item.id
        spec.noteUpdatedAtMilliseconds = HolyTmuxSessionMetadataClock.next(after: nil)
        spec.workingDirectory = context.boardRoot
        if let host = context.remoteHost {
            spec.transport = .init(kind: .ssh, hostLabel: host, sshDestination: host)
        }
        spec.tmux?.sessionName = "holy-worker-\(UUID().uuidString.lowercased())"
        var arguments = [executablePath]
        let model = profile.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty { arguments += ["--model", model] }
        arguments += ["--", brief]
        // The prompt is one startup argument, never terminal input or an executable claim command.
        let quote: (String) -> String = { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        // npm's Codex entry point uses /usr/bin/env node. Its sibling node
        // must resolve even when the pane inherited only the system PATH.
        let binaryDirectory = URL(fileURLWithPath: executablePath).deletingLastPathComponent().path
        // exec replaces the pane's shell with the runtime: the agent IS the
        // pane process, so discovery, the hosts sheet, kill targeting, and
        // liveness all see codex/claude instead of a bash wrapper (mn-37c1b4:
        // six invisible workers were bash-leader panes).
        spec.command = "export PATH=\(quote(binaryDirectory)):\"$PATH\"; exec "
            + arguments.map(quote).joined(separator: " ")
        spec.initialInput = nil
        return spec
    }
}
