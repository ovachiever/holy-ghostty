import Foundation
import OSLog

actor HolyRemoteTmuxDiscoveryService {
    static let shared = HolyRemoteTmuxDiscoveryService()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "org.holyghostty.app",
        category: "HolyRemoteTmuxDiscovery"
    )

    func discoverSessions(for host: HolyRemoteHostRecord) -> [HolyDiscoveredTmuxSession] {
        do {
            return try discoverSessionsThrowing(for: host)
        } catch {
            return []
        }
    }

    func discoverSessionsThrowing(for host: HolyRemoteHostRecord) throws -> [HolyDiscoveredTmuxSession] {
        let normalizedHost = host.normalized()
        guard !normalizedHost.sshDestination.isEmpty else { return [] }

        for probeTarget in probeTargets(for: normalizedHost) {
            guard let result = runDiscovery(for: normalizedHost, socketName: probeTarget.socketName) else {
                throw CocoaError(.executableNotLoadable)
            }

            guard result.exitCode == 0 else {
                throw friendlyDiscoveryError(for: normalizedHost, result: result)
            }

            if !result.stderr.holyTrimmed.isEmpty {
                logger.notice(
                    "Remote discovery stderr for \(normalizedHost.sshDestination, privacy: .public): \(result.stderr, privacy: .public)"
                )
            }

            let sessions = parseSessions(
                output: result.stdout,
                host: normalizedHost,
                tmuxSocketName: probeTarget.socketName,
                discoveredAt: .now
            )

            if !sessions.isEmpty || probeTarget.isExplicit {
                return sessions
            }
        }

        return []
    }

    private func runDiscovery(
        for host: HolyRemoteHostRecord,
        socketName: String?
    ) -> HolyRemoteCommandResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=5",
            "-o",
            "ServerAliveInterval=5",
            "-o",
            "ServerAliveCountMax=1",
            host.sshDestination,
            "zsh",
            "-lc",
            remoteDiscoveryScript(socketName: socketName)
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            logger.error("Failed to run remote tmux discovery for \(host.sshDestination, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()

        return .init(
            stdout: String(bytes: stdoutData, encoding: .utf8) ?? "",
            stderr: String(bytes: stderrData, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
    }

    private func parseSessions(
        output: String,
        host: HolyRemoteHostRecord,
        tmuxSocketName: String?,
        discoveredAt: Date
    ) -> [HolyDiscoveredTmuxSession] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> HolyDiscoveredTmuxSession? in
                let fields = line
                    .split(separator: "\u{1F}", omittingEmptySubsequences: false)
                    .map(String.init)

                guard fields.count >= 10 else { return nil }

                return .init(
                    hostID: host.id,
                    hostLabel: host.displayTitle,
                    hostDestination: host.sshDestination,
                    tmuxSocketName: tmuxSocketName?.holyTrimmed.nilIfEmpty,
                    sessionName: fields[0],
                    title: fields[3].holyTrimmed.nilIfEmpty,
                    runtimeRawValue: fields[4].holyTrimmed.nilIfEmpty,
                    objective: fields[5].holyTrimmed.nilIfEmpty,
                    workingDirectory: fields[6].holyTrimmed.nilIfEmpty,
                    bootstrapCommand: fields[7].holyTrimmed.nilIfEmpty,
                    taskTitle: fields[8].holyTrimmed.nilIfEmpty,
                    taskSource: fields[9].holyTrimmed.nilIfEmpty,
                    gitSummary: Self.makeGitSummary(from: fields),
                    attachedClientCount: Int(fields[1]) ?? 0,
                    windowCount: Int(fields[2]) ?? 0,
                    discoveredAt: discoveredAt
                )
            }
            .sorted { lhs, rhs in
                if lhs.isHolyManaged != rhs.isHolyManaged {
                    return lhs.isHolyManaged && !rhs.isHolyManaged
                }

                if lhs.attachedClientCount != rhs.attachedClientCount {
                    return lhs.attachedClientCount > rhs.attachedClientCount
                }

                return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
            }
    }

    private func remoteDiscoveryScript(socketName: String?) -> String {
        let socketBinding = socketName?.holyTrimmed.nilIfEmpty.map(posixQuote) ?? "''"

        return """
        setopt pipefail
        socket_name=\(socketBinding)
        sep=$'\\x1f'
        tmux_cmd=(tmux)
        if [[ -n "$socket_name" ]]; then
          tmux_cmd+=(-L "$socket_name")
        fi

        sanitize() {
          local value="$1"
          value=${value//$'\\n'/ }
          value=${value//$'\\r'/ }
          printf '%s' "$value"
        }

        option_value() {
          local session_name="$1"
          local option_name="$2"
          "${tmux_cmd[@]}" show-options -qv -t "$session_name" "$option_name" 2>/dev/null || true
        }

        git_metadata() {
          local working_directory="$1"
          if [[ -z "$working_directory" ]]; then
            printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s' \
              "" "$sep" \
              "" "$sep" \
              0 "$sep" \
              0 "$sep" \
              0 "$sep" \
              0 "$sep" \
              0 "$sep" \
              0 "$sep" \
              0
            return
          fi

          local repository_root branch upstream_counts ahead_count behind_count status_output staged_count unstaged_count untracked_count conflicted_count detached_flag

          repository_root=$(git -C "$working_directory" rev-parse --show-toplevel 2>/dev/null) || {
            printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s' \
              "" "$sep" \
              "" "$sep" \
              0 "$sep" \
              0 "$sep" \
              0 "$sep" \
              0 "$sep" \
              0 "$sep" \
              0 "$sep" \
              0
            return
          }

          branch=$(git -C "$working_directory" symbolic-ref --short -q HEAD 2>/dev/null || true)
          detached_flag=0
          if [[ -z "$branch" ]]; then
            detached_flag=1
          fi

          upstream_counts=$(git -C "$working_directory" rev-list --left-right --count @{upstream}...HEAD 2>/dev/null || true)
          behind_count=$(awk '{print $1}' <<<"$upstream_counts")
          ahead_count=$(awk '{print $2}' <<<"$upstream_counts")
          behind_count=${behind_count:-0}
          ahead_count=${ahead_count:-0}

          staged_count=0
          unstaged_count=0
          untracked_count=0
          conflicted_count=0

          status_output=$(git -C "$working_directory" status --porcelain=v1 --untracked-files=all 2>/dev/null || true)
          while IFS= read -r status_line; do
            [[ -z "$status_line" ]] && continue

            if [[ "$status_line" == '?? '* ]]; then
              ((untracked_count++))
              continue
            fi

            local staged_status="${status_line[1,1]}"
            local unstaged_status="${status_line[2,2]}"

            if [[ "$staged_status" == U || "$staged_status" == A || "$staged_status" == D || "$unstaged_status" == U || "$unstaged_status" == A || "$unstaged_status" == D ]]; then
              ((conflicted_count++))
              continue
            fi

            if [[ "$staged_status" != ' ' ]]; then
              ((staged_count++))
            fi

            if [[ "$unstaged_status" != ' ' ]]; then
              ((unstaged_count++))
            fi
          done <<<"$status_output"

          printf '%s%s%s%s%s%s%s%s%s' \
            "$(sanitize "$repository_root")" "$sep" \
            "$(sanitize "$branch")" "$sep" \
            "$(sanitize "$detached_flag")" "$sep" \
            "$(sanitize "$ahead_count")" "$sep" \
            "$(sanitize "$behind_count")" "$sep" \
            "$(sanitize "$staged_count")" "$sep" \
            "$(sanitize "$unstaged_count")" "$sep" \
            "$(sanitize "$untracked_count")" "$sep" \
            "$(sanitize "$conflicted_count")"
        }

        while IFS=$'\\t' read -r session_name attached windows; do
          [[ -z "$session_name" ]] && continue
          title=$(option_value "$session_name" @holy_title)
          runtime=$(option_value "$session_name" @holy_runtime)
          objective=$(option_value "$session_name" @holy_objective)
          working_directory=$(option_value "$session_name" @holy_working_directory)
          command=$(option_value "$session_name" @holy_command)
          task_title=$(option_value "$session_name" @holy_task_title)
          task_source=$(option_value "$session_name" @holy_task_source)
          git_fields=$(git_metadata "$working_directory")

          printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\\n' \
            "$(sanitize "$session_name")" "$sep" \
            "$(sanitize "$attached")" "$sep" \
            "$(sanitize "$windows")" "$sep" \
            "$(sanitize "$title")" "$sep" \
            "$(sanitize "$runtime")" "$sep" \
            "$(sanitize "$objective")" "$sep" \
            "$(sanitize "$working_directory")" "$sep" \
            "$(sanitize "$command")" "$sep" \
            "$(sanitize "$task_title")" "$sep" \
            "$(sanitize "$task_source")" "$sep" \
            "$git_fields"
        done < <("${tmux_cmd[@]}" list-sessions -F $'#{session_name}\\t#{session_attached}\\t#{session_windows}' 2>/dev/null || true)
        """
    }

    private func posixQuote(_ value: String) -> String {
        if value.isEmpty {
            return "''"
        }

        let escaped = value.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(escaped)'"
    }

    private func probeTargets(for host: HolyRemoteHostRecord) -> [HolyRemoteProbeTarget] {
        if let explicitSocketName = host.tmuxSocketName?.holyTrimmed.nilIfEmpty {
            return [.init(socketName: explicitSocketName, isExplicit: true)]
        }

        return [
            .init(socketName: nil, isExplicit: false),
            .init(socketName: HolySessionTmuxSpec.defaultSocketName, isExplicit: false),
        ]
    }

    private func friendlyDiscoveryError(
        for host: HolyRemoteHostRecord,
        result: HolyRemoteCommandResult
    ) -> NSError {
        let stderr = result.stderr.holyTrimmed
        let description: String

        if stderr.localizedCaseInsensitiveContains("host key verification failed") {
            description = "SSH trust failed for \(host.sshDestination). Run `ssh \(host.sshDestination)` in Terminal once and accept or refresh the host key."
        } else if stderr.localizedCaseInsensitiveContains("could not resolve hostname") {
            description = "Holy couldn't resolve \(host.sshDestination). Use a working SSH alias or reachable host name."
        } else if stderr.localizedCaseInsensitiveContains("permission denied") {
            description = "SSH login failed for \(host.sshDestination). Verify your SSH key or agent."
        } else if stderr.localizedCaseInsensitiveContains("operation timed out")
            || stderr.localizedCaseInsensitiveContains("connection timed out") {
            description = "\(host.sshDestination) timed out. Check VPN/Tailscale reachability or choose another address."
        } else if let stderr = stderr.nilIfEmpty {
            description = stderr
        } else {
            description = "Failed to inspect tmux sessions on \(host.displayTitle)."
        }

        return NSError(
            domain: "HolyRemoteTmuxDiscovery",
            code: Int(result.exitCode),
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }
}

private extension HolyRemoteTmuxDiscoveryService {
    static func makeGitSummary(from fields: [String]) -> HolyRemoteGitSummary? {
        guard fields.count >= 19,
              let repositoryRoot = fields[10].holyTrimmed.nilIfEmpty else {
            return nil
        }

        let branch = fields[11].holyTrimmed
        let isDetachedHead = fields[12] == "1"
        let aheadCount = Int(fields[13]) ?? 0
        let behindCount = Int(fields[14]) ?? 0
        let stagedCount = Int(fields[15]) ?? 0
        let unstagedCount = Int(fields[16]) ?? 0
        let untrackedCount = Int(fields[17]) ?? 0
        let conflictedCount = Int(fields[18]) ?? 0

        return HolyRemoteGitSummary(
            repositoryRoot: repositoryRoot,
            branch: branch,
            isDetachedHead: isDetachedHead,
            aheadCount: aheadCount,
            behindCount: behindCount,
            stagedCount: stagedCount,
            unstagedCount: unstagedCount,
            untrackedCount: untrackedCount,
            conflictedCount: conflictedCount
        )
    }
}

private struct HolyRemoteCommandResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

private struct HolyRemoteProbeTarget {
    let socketName: String?
    let isExplicit: Bool
}

private extension String {
    var holyTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
