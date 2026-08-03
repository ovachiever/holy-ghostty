import Foundation
import Darwin

/// The stage of a tmux lifecycle command that produced a failure. Reported to
/// the user verbatim so a field failure names the layer that broke instead of
/// collapsing into an opaque Foundation error rendering.
enum HolyTmuxLifecycleStage: String, Sendable {
    /// The local helper process (zsh or ssh) could not be spawned at all.
    case launch
    /// SSH exited before the remote script ran (remote transport only).
    case connect
    /// tmux refused the kill-session command.
    case kill
    /// tmux still reported the session after the kill was accepted.
    case verify
    /// A liveness probe could not determine whether the session exists.
    case probe
    /// The helper process outlived its wall-clock cap and was terminated.
    case timeout
}

/// A lifecycle command failure that preserves every diagnostic coordinate:
/// which stage broke, the exact socket and target, tmux's stderr, and the
/// full identity of any process-launch error (domain, code, errno). The
/// roster record is never mutated on failure; callers surface `message`.
struct HolyTmuxLifecycleFailure: Error, Sendable, Equatable {
    let stage: HolyTmuxLifecycleStage
    let socketName: String?
    let target: String
    let stderr: String?
    let underlyingDescription: String?

    var message: String {
        let summary: String
        switch stage {
        case .launch:
            summary = "The tmux helper process could not be launched"
        case .connect:
            summary = "SSH could not reach the host to run tmux"
        case .kill:
            summary = "tmux could not kill the session"
        case .verify:
            summary = "tmux still reported the session after the kill attempt"
        case .probe:
            summary = "tmux could not report whether the session is alive"
        case .timeout:
            summary = "The tmux command did not finish in time"
        }

        var details: [String] = []
        if let stderr = stderr?.holyLifecycleServiceTrimmed.nilIfEmpty {
            details.append(stderr)
        }
        if let underlyingDescription = underlyingDescription?.holyLifecycleServiceTrimmed.nilIfEmpty {
            details.append(underlyingDescription)
        }
        let detailSuffix = details.isEmpty ? "" : " \(details.joined(separator: " — "))"

        return "\(summary).\(detailSuffix) [stage: \(stage.rawValue); socket: \(Self.socketLabel(socketName)); target: \(target)]"
    }

    static func socketLabel(_ socketName: String?) -> String {
        socketName ?? "default"
    }
}

/// How a verified kill concluded. Both cases are inventory-proven absence;
/// they differ only in whether this call did the killing.
enum HolyTmuxKillOutcome: Sendable, Equatable {
    /// kill-session succeeded and a polled has-session inventory proved the
    /// session gone.
    case killed
    /// The server or session was already gone before the kill ran (dead
    /// server, missing session). Absence is equally proven; the kill was a
    /// no-op.
    case alreadyAbsent
}

/// Whether an exact live identity currently exists on its tmux server.
enum HolyTmuxLiveness: Sendable, Equatable {
    case present
    case absent
    /// The probe could not run or could not be interpreted. Callers must
    /// treat this as "unknown", never as absence.
    case undetermined(HolyTmuxLifecycleFailure)
}

/// Lifecycle operations against one exact live tmux identity. This is the
/// only sanctioned kill path: every operation targets the identity's exact
/// socket (or the default socket only when the identity was discovered there)
/// and its exact `=`-prefixed session name. Nothing here ever synthesizes a
/// name, broadens a match, or guesses a socket namespace.
///
/// The API is deliberately caller-agnostic: the roster kill flow, the Hosts
/// panel, and the crash-restore engine all consume the same three verbs —
/// verify an identity is live, kill exactly that identity, poll until absence
/// is proven.
enum HolyTmuxLifecycleService {
    static let defaultKillTimeout: TimeInterval = 12
    static let defaultProbeTimeout: TimeInterval = 8

    /// Kills the exact identity and returns only after a polled inventory
    /// proves the session absent (or reports the precise failure stage).
    /// A dead server or already-missing session counts as proven absence.
    static func killVerified(
        _ identity: HolyTmuxLiveIdentity,
        timeout: TimeInterval = defaultKillTimeout
    ) async -> Result<HolyTmuxKillOutcome, HolyTmuxLifecycleFailure> {
        let command = HolyTmuxLifecycleCommand.killCommand(for: identity)
        let outcome = await run(command: command, identity: identity, timeout: timeout)

        switch interpret(outcome, command: command, identity: identity) {
        case let .failure(failure):
            return .failure(failure)
        case let .success(result):
            guard result.exitCode == 0 else {
                return .failure(failure(
                    from: result,
                    fallbackStage: .kill,
                    identity: identity,
                    isRemote: command.isRemote
                ))
            }
            let absent = result.stdout.contains(HolyTmuxLifecycleCommand.absentMarker)
            return .success(absent ? .alreadyAbsent : .killed)
        }
    }

    /// Reports whether the exact identity is currently live. Fail-closed: any
    /// probe that cannot be launched or interpreted is `.undetermined`, never
    /// `.absent`.
    static func verifyLiveIdentity(
        _ identity: HolyTmuxLiveIdentity,
        timeout: TimeInterval = defaultProbeTimeout
    ) async -> HolyTmuxLiveness {
        let command = HolyTmuxLifecycleCommand.probeCommand(for: identity)
        let outcome = await run(command: command, identity: identity, timeout: timeout)

        switch interpret(outcome, command: command, identity: identity) {
        case let .failure(failure):
            return .undetermined(failure)
        case let .success(result):
            guard result.exitCode == 0 else {
                return .undetermined(failure(
                    from: result,
                    fallbackStage: .probe,
                    identity: identity,
                    isRemote: command.isRemote
                ))
            }
            if result.stdout.contains(HolyTmuxLifecycleCommand.presentMarker) {
                return .present
            }
            if result.stdout.contains(HolyTmuxLifecycleCommand.absentMarker) {
                return .absent
            }
            return .undetermined(.init(
                stage: .probe,
                socketName: identity.socketName,
                target: HolyTmuxLifecycleCommand.exactTarget(for: identity),
                stderr: "The liveness probe exited cleanly without reporting presence or absence.",
                underlyingDescription: nil
            ))
        }
    }

    /// Re-probes the identity until absence is proven or the deadline passes.
    /// Returns `.absent` on proof, otherwise the last observed liveness.
    static func pollUntilAbsent(
        _ identity: HolyTmuxLiveIdentity,
        timeout: TimeInterval = 10,
        interval: TimeInterval = 0.25
    ) async -> HolyTmuxLiveness {
        let deadline = Date().addingTimeInterval(timeout)
        var lastObserved: HolyTmuxLiveness = .present

        repeat {
            lastObserved = await verifyLiveIdentity(identity)
            if case .absent = lastObserved {
                return .absent
            }
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        } while Date() < deadline

        return lastObserved
    }

    // MARK: - Process transport

    private struct CommandResult {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    private typealias RunOutcome = HolyTmuxLifecycleServiceRunOutcome

    private static func run(
        command: HolyTmuxLifecycleCommand,
        identity: HolyTmuxLiveIdentity,
        timeout: TimeInterval
    ) async -> RunOutcome {
        var attempt = 0
        while true {
            attempt += 1
            let outcome = await runOnce(command: command, timeout: timeout)
            // One retry, launch stage only. Nothing has executed yet when
            // posix_spawn fails, so a rerun is side-effect free; transient
            // spawn errors (EAGAIN under swarm load) heal in one beat.
            if case .launchFailed = outcome, attempt == 1 {
                try? await Task.sleep(nanoseconds: 300_000_000)
                continue
            }
            return outcome
        }
    }

    private static func runOnce(
        command: HolyTmuxLifecycleCommand,
        timeout: TimeInterval
    ) async -> RunOutcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executablePath)
        process.arguments = command.arguments
        process.environment = scrubbedTmuxEnvironment(ProcessInfo.processInfo.environment)
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let resumeBox = HolyTmuxLifecycleResumeBox()

        return await withCheckedContinuation { (continuation: CheckedContinuation<RunOutcome, Never>) in
            resumeBox.store(continuation)

            process.terminationHandler = { finishedProcess in
                let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
                resumeBox.resume(returning: .completed(
                    stdout: String(bytes: stdoutData, encoding: .utf8) ?? "",
                    stderr: String(bytes: stderrData, encoding: .utf8) ?? "",
                    exitCode: finishedProcess.terminationStatus
                ))
            }

            do {
                try process.run()
            } catch {
                resumeBox.resume(returning: .launchFailed(
                    description: holyDetailedProcessLaunchErrorDescription(error)
                ))
                return
            }

            // Wall-clock cap. Resume first so the termination handler cannot
            // misreport our SIGTERM as a command failure; escalate to SIGKILL
            // for a helper that ignores SIGTERM.
            Task.detached {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                resumeBox.resume(returning: .timedOut(seconds: timeout))
                if process.isRunning {
                    process.terminate()
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if process.isRunning {
                        Darwin.kill(process.processIdentifier, SIGKILL)
                    }
                }
            }
        }
    }

    private static func interpret(
        _ outcome: RunOutcome,
        command: HolyTmuxLifecycleCommand,
        identity: HolyTmuxLiveIdentity
    ) -> Result<CommandResult, HolyTmuxLifecycleFailure> {
        let target = HolyTmuxLifecycleCommand.exactTarget(for: identity)
        switch outcome {
        case let .completed(stdout, stderr, exitCode):
            return .success(.init(stdout: stdout, stderr: stderr, exitCode: exitCode))
        case let .launchFailed(description):
            return .failure(.init(
                stage: .launch,
                socketName: identity.socketName,
                target: target,
                stderr: nil,
                underlyingDescription: description
            ))
        case let .timedOut(seconds):
            let secondsDescription = seconds.rounded() == seconds
                ? String(Int(seconds))
                : String(format: "%.1f", seconds)
            return .failure(.init(
                stage: .timeout,
                socketName: identity.socketName,
                target: target,
                stderr: nil,
                underlyingDescription: "Terminated after \(secondsDescription) seconds. The session was left untouched."
            ))
        }
    }

    private static func failure(
        from result: CommandResult,
        fallbackStage: HolyTmuxLifecycleStage,
        identity: HolyTmuxLiveIdentity,
        isRemote: Bool
    ) -> HolyTmuxLifecycleFailure {
        let (markedStage, detail) = HolyTmuxLifecycleCommand.parseStage(fromStderr: result.stderr)
        var stage = markedStage ?? fallbackStage
        // ssh reserves exit 255 for its own failures; the script never ran,
        // so a missing stage marker plus 255 on a remote transport means the
        // connection itself broke.
        if isRemote, markedStage == nil, result.exitCode == 255 {
            stage = .connect
        }

        let stderrDetail = detail?.holyLifecycleServiceTrimmed.nilIfEmpty
            ?? result.stdout.holyLifecycleServiceTrimmed.nilIfEmpty
        return .init(
            stage: stage,
            socketName: identity.socketName,
            target: HolyTmuxLifecycleCommand.exactTarget(for: identity),
            stderr: stderrDetail ?? "tmux exited with status \(result.exitCode).",
            underlyingDescription: nil
        )
    }

    static func scrubbedTmuxEnvironment(_ environment: [String: String]) -> [String: String] {
        var environment = environment
        environment.removeValue(forKey: "TMUX")
        environment.removeValue(forKey: "TMUX_PANE")
        environment.removeValue(forKey: "TMUX_TMPDIR")
        return environment
    }
}

/// Renders a Process launch error with its full identity preserved: domain,
/// code, errno name for POSIX failures, and any underlying error. A bare
/// `localizedDescription` renders unmapped Foundation codes as the useless
/// "(Cocoa error NNNN.)" — this keeps the coordinates a diagnosis needs.
func holyDetailedProcessLaunchErrorDescription(_ error: Error) -> String {
    let nsError = error as NSError
    var parts: [String] = []

    var identity = "\(nsError.domain) code \(nsError.code)"
    if nsError.domain == NSPOSIXErrorDomain {
        identity += " (\(String(cString: strerror(Int32(nsError.code)))))"
    } else if nsError.domain == NSCocoaErrorDomain, nsError.code == 3584 {
        identity += " (executable not loadable — posix_spawn layer)"
    }
    parts.append(identity)

    let localized = nsError.localizedDescription
    if !localized.isEmpty, !localized.contains("(\(nsError.domain) error \(nsError.code)") {
        parts.append(localized)
    }

    if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
        parts.append("underlying: \(underlying.domain) code \(underlying.code)")
    }
    if let path = nsError.userInfo["NSFilePath"] as? String {
        parts.append("path: \(path)")
    }

    return "Process launch failed: \(parts.joined(separator: " — "))."
}

/// Builds the exact zsh/ssh invocations for lifecycle operations. Local
/// commands resolve tmux through a login shell because a Dock/Finder launch
/// does not inherit Homebrew's bin directory.
struct HolyTmuxLifecycleCommand: Sendable {
    static let killedMarker = "HOLY_TMUX_KILLED"
    static let absentMarker = "HOLY_TMUX_ABSENT"
    static let presentMarker = "HOLY_TMUX_PRESENT"
    private static let stageMarkerPrefix = "HOLY_TMUX_STAGE:"

    let executablePath: String
    let arguments: [String]
    let isRemote: Bool

    static func exactTarget(for identity: HolyTmuxLiveIdentity) -> String {
        "=\(identity.sessionName)"
    }

    static func killCommand(for identity: HolyTmuxLiveIdentity) -> Self {
        let tmuxArguments = tmuxArguments(for: identity)
        let target = exactTarget(for: identity)
        let killCommand = shellCommand(tmuxArguments + ["kill-session", "-t", target])
        let probeCommand = shellCommand(tmuxArguments + ["has-session", "-t", target])
        return command(for: identity, script: killScript(
            killCommand: killCommand,
            probeCommand: probeCommand
        ))
    }

    static func probeCommand(for identity: HolyTmuxLiveIdentity) -> Self {
        let tmuxArguments = tmuxArguments(for: identity)
        let target = exactTarget(for: identity)
        let probeCommand = shellCommand(tmuxArguments + ["has-session", "-t", target])
        return command(for: identity, script: probeScript(probeCommand: probeCommand))
    }

    /// Splits a stage marker off the stderr stream. The scripts emit the
    /// marker as the first stderr line on failure; everything after it is
    /// tmux's own message.
    static func parseStage(fromStderr stderr: String) -> (HolyTmuxLifecycleStage?, String?) {
        var stage: HolyTmuxLifecycleStage?
        var detailLines: [String] = []
        for line in stderr.split(separator: "\n", omittingEmptySubsequences: false) {
            if stage == nil, line.hasPrefix(stageMarkerPrefix) {
                stage = HolyTmuxLifecycleStage(rawValue: String(line.dropFirst(stageMarkerPrefix.count)))
                continue
            }
            detailLines.append(String(line))
        }
        let detail = detailLines.joined(separator: "\n").holyLifecycleServiceTrimmed.nilIfEmpty
        return (stage, detail)
    }

    private static func command(for identity: HolyTmuxLiveIdentity, script: String) -> Self {
        if identity.transport.isRemote {
            let destination = identity.transport.sshDestination?.holyLifecycleServiceTrimmed.nilIfEmpty ?? ""
            return .init(
                executablePath: "/usr/bin/env",
                arguments: [
                    "ssh",
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    destination,
                    "zsh", "-lc", posixQuote(script),
                ],
                isRemote: true
            )
        }

        return .init(
            executablePath: "/bin/zsh",
            arguments: ["-lc", script],
            isRemote: false
        )
    }

    private static func tmuxArguments(for identity: HolyTmuxLiveIdentity) -> [String] {
        var arguments = ["tmux"]
        if let socketName = identity.socketName?.holyLifecycleServiceTrimmed.nilIfEmpty {
            arguments += ["-L", socketName]
        }
        return arguments
    }

    /// tmux messages that positively prove the target cannot exist: the
    /// server is not running, its socket is gone, or the exact session name
    /// is unknown to a live server. Anything else stays a failure.
    private static let absenceCasePatterns = """
    *"no server running"*|*"error connecting to"*|*"failed to connect to server"*|*"can't find session"*|*"session not found"*
    """

    private static func killScript(killCommand: String, probeCommand: String) -> String {
        """
        unset TMUX TMUX_PANE
        kill_output=$(\(killCommand) 2>&1)
        kill_status=$?
        if (( kill_status != 0 )); then
          lowered="${kill_output:l}"
          case "$lowered" in
            \(absenceCasePatterns))
              printf '%s\n' '\(absentMarker)'
              exit 0
              ;;
          esac
          printf '%s\n' '\(stageMarkerPrefix)kill' >&2
          if [[ -n "$kill_output" ]]; then printf '%s\n' "$kill_output" >&2; fi
          exit "$kill_status"
        fi
        attempt=0
        while \(probeCommand) >/dev/null 2>&1; do
          attempt=$((attempt + 1))
          if (( attempt >= 20 )); then
            printf '%s\n' '\(stageMarkerPrefix)verify' >&2
            if [[ -n "$kill_output" ]]; then printf '%s\n' "$kill_output" >&2; fi
            printf '%s\n' 'tmux still reports the session after kill verification.' >&2
            exit 1
          fi
          sleep 0.1
        done
        printf '%s\n' '\(killedMarker)'
        exit 0
        """
    }

    private static func probeScript(probeCommand: String) -> String {
        """
        unset TMUX TMUX_PANE
        probe_output=$(\(probeCommand) 2>&1)
        probe_status=$?
        if (( probe_status == 0 )); then
          printf '%s\n' '\(presentMarker)'
          exit 0
        fi
        lowered="${probe_output:l}"
        case "$lowered" in
          \(absenceCasePatterns))
            printf '%s\n' '\(absentMarker)'
            exit 0
            ;;
        esac
        printf '%s\n' '\(stageMarkerPrefix)probe' >&2
        if [[ -n "$probe_output" ]]; then printf '%s\n' "$probe_output" >&2; fi
        exit "$probe_status"
        """
    }

    private static func shellCommand(_ arguments: [String]) -> String {
        arguments.map(posixQuote).joined(separator: " ")
    }

    private static func posixQuote(_ value: String) -> String {
        if value.isEmpty {
            return "''"
        }

        let escaped = value.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(escaped)'"
    }
}

private enum HolyTmuxLifecycleServiceRunOutcome {
    case completed(stdout: String, stderr: String, exitCode: Int32)
    case launchFailed(description: String)
    case timedOut(seconds: TimeInterval)
}

/// Resumes a lifecycle continuation exactly once; the termination handler and
/// the timeout task race and the loser is a no-op.
private final class HolyTmuxLifecycleResumeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<HolyTmuxLifecycleServiceRunOutcome, Never>?
    private var didResume = false

    func store(_ continuation: CheckedContinuation<HolyTmuxLifecycleServiceRunOutcome, Never>) {
        lock.lock()
        defer { lock.unlock() }
        self.continuation = continuation
    }

    func resume(returning value: HolyTmuxLifecycleServiceRunOutcome) {
        lock.lock()
        guard !didResume, let continuation = self.continuation else {
            lock.unlock()
            return
        }
        didResume = true
        self.continuation = nil
        lock.unlock()
        continuation.resume(returning: value)
    }
}

private extension String {
    var holyLifecycleServiceTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
