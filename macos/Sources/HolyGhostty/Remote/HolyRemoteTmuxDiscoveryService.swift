import Foundation
import OSLog

actor HolyRemoteTmuxDiscoveryService {
    static let shared = HolyRemoteTmuxDiscoveryService()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "org.holyghostty.app",
        category: "HolyRemoteTmuxDiscovery"
    )

    func discoverSessions(for host: HolyRemoteHostRecord) async -> [HolyDiscoveredTmuxSession] {
        do {
            return try await discoverSessionsThrowing(for: host)
        } catch {
            return []
        }
    }

    /// - Parameter timeout: Optional hard wall-clock cap applied per discovery
    ///   process. Passed by the converge sweep (5s) so a hung host can never
    ///   stall the run; left nil by the Hosts panel and metadata refresh, where
    ///   a slow-but-alive host must still be allowed to answer.
    func discoverSessionsThrowing(
        for host: HolyRemoteHostRecord,
        timeout: TimeInterval? = nil,
        includeHiddenSessions: Bool = false
    ) async throws -> [HolyDiscoveredTmuxSession] {
        let normalizedHost = host.normalized()
        guard !normalizedHost.sshDestination.isEmpty else { return [] }

        return try await discoverSessionsThrowing(
            for: normalizedHost,
            includeHiddenSessions: includeHiddenSessions
        ) { host, socketName in
            await runRemoteDiscovery(for: host, socketName: socketName, timeout: timeout)
        }
    }

    func discoverLocalSessionsThrowing(
        hostID: UUID,
        hostLabel: String,
        tmuxSocketName: String? = nil,
        timeout: TimeInterval? = nil,
        includeHiddenSessions: Bool = false
    ) async throws -> [HolyDiscoveredTmuxSession] {
        let localHost = HolyRemoteHostRecord(
            id: hostID,
            label: hostLabel,
            sshDestination: "localhost",
            tmuxSocketName: tmuxSocketName
        )

        return try await discoverSessionsThrowing(
            for: localHost,
            includeHiddenSessions: includeHiddenSessions
        ) { _, socketName in
            await runLocalDiscovery(socketName: socketName, timeout: timeout)
        }
    }

    private func discoverSessionsThrowing(
        for normalizedHost: HolyRemoteHostRecord,
        includeHiddenSessions: Bool,
        using runDiscovery: (HolyRemoteHostRecord, String?) async -> HolyRemoteCommandResult?
    ) async throws -> [HolyDiscoveredTmuxSession] {
        var discoveredSessions: [HolyDiscoveredTmuxSession] = []
        var discoveredSessionIDs: Set<String> = []

        for probeTarget in probeTargets(for: normalizedHost) {
            guard let result = await runDiscovery(normalizedHost, probeTarget.socketName) else {
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
                discoveredAt: .now,
                includeHiddenSessions: includeHiddenSessions
            )

            if probeTarget.isExplicit {
                return sessions
            }

            for session in sessions where !discoveredSessionIDs.contains(session.id) {
                discoveredSessions.append(session)
                discoveredSessionIDs.insert(session.id)
            }
        }

        return sortedSessions(discoveredSessions)
    }

    private func runRemoteDiscovery(
        for host: HolyRemoteHostRecord,
        socketName: String?,
        timeout: TimeInterval?
    ) async -> HolyRemoteCommandResult? {
        let script = remoteDiscoveryScript(socketName: socketName, includeGitMetadata: true)
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
            "zsh -lc \(posixQuote(script))"
        ]

        return await run(process: process, context: host.sshDestination, timeout: timeout)
    }

    private func runLocalDiscovery(socketName: String?, timeout: TimeInterval?) async -> HolyRemoteCommandResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", remoteDiscoveryScript(socketName: socketName, includeGitMetadata: false)]

        // Scrub the inherited tmux context. If Holy was launched from a shell
        // running inside tmux, $TMUX makes a default-socket probe (no -L)
        // resolve to that server instead of the real default socket — listing
        // the same sessions twice in discovery. The probe must always mean the
        // socket it names.
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "TMUX")
        environment.removeValue(forKey: "TMUX_PANE")
        environment.removeValue(forKey: "TMUX_TMPDIR")
        process.environment = environment

        return await run(process: process, context: "local tmux", timeout: timeout)
    }

    /// Runs a discovery process asynchronously. The blocking `waitUntilExit()`
    /// is gone: termination is bridged into async/await via the process
    /// termination handler, so N concurrent sweep children never pin N executor
    /// threads. When `timeout` is set, a process that outlives the cap is
    /// terminated and reported as unreachable (nil) - the async result is
    /// bounded regardless of whether the process honors SIGTERM, so the converge
    /// sweep can never wedge on a runaway child.
    private func run(process: Process, context: String, timeout: TimeInterval?) async -> HolyRemoteCommandResult? {
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let resumeBox = HolyProcessRunResumeBox()

        return await withCheckedContinuation { (continuation: CheckedContinuation<HolyRemoteCommandResult?, Never>) in
            resumeBox.store(continuation)

            process.terminationHandler = { finishedProcess in
                let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
                resumeBox.resume(returning: HolyRemoteCommandResult(
                    stdout: String(bytes: stdoutData, encoding: .utf8) ?? "",
                    stderr: String(bytes: stderrData, encoding: .utf8) ?? "",
                    exitCode: finishedProcess.terminationStatus
                ))
            }

            do {
                try process.run()
            } catch {
                logger.error("Failed to run tmux discovery for \(context, privacy: .public): \(error.localizedDescription, privacy: .public)")
                resumeBox.resume(returning: nil)
                return
            }

            guard let timeout else { return }

            // Hard wall-clock cap. A wedged login profile, a hung ssh, or a
            // stalled tmux server is SIGTERM'd and reported unreachable so the
            // sweep stays bounded. Best-effort terminate; the nil resume below
            // bounds the async result even if the process ignores the signal.
            Task.detached {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if process.isRunning {
                    process.terminate()
                }
                resumeBox.resume(returning: nil)
            }
        }
    }

    private func parseSessions(
        output: String,
        host: HolyRemoteHostRecord,
        tmuxSocketName: String?,
        discoveredAt: Date,
        includeHiddenSessions: Bool
    ) -> [HolyDiscoveredTmuxSession] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> HolyDiscoveredTmuxSession? in
                let fields = line
                    .split(separator: "\u{1F}", omittingEmptySubsequences: false)
                    .map(String.init)

                guard fields.count >= 10 else { return nil }

                let session = HolyDiscoveredTmuxSession(
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

                guard includeHiddenSessions || !session.shouldHideFromDiscovery else { return nil }
                return session
            }
            .sorted(by: sessionSortOrder)
    }

    private func sortedSessions(_ sessions: [HolyDiscoveredTmuxSession]) -> [HolyDiscoveredTmuxSession] {
        sessions.sorted(by: sessionSortOrder)
    }

    private func sessionSortOrder(_ lhs: HolyDiscoveredTmuxSession, _ rhs: HolyDiscoveredTmuxSession) -> Bool {
        if lhs.connectionRuntime != rhs.connectionRuntime {
            return Self.runtimeSortRank(lhs.connectionRuntime) < Self.runtimeSortRank(rhs.connectionRuntime)
        }

        let titleComparison = lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle)
        if titleComparison != .orderedSame {
            return titleComparison == .orderedAscending
        }

        if lhs.isHolyManaged != rhs.isHolyManaged {
            return lhs.isHolyManaged && !rhs.isHolyManaged
        }

        return lhs.sessionName.localizedCaseInsensitiveCompare(rhs.sessionName) == .orderedAscending
    }

    private static func runtimeSortRank(_ runtime: HolySessionRuntime) -> Int {
        switch runtime {
        case .claude:
            return 0
        case .codex:
            return 1
        case .opencode:
            return 2
        case .shell:
            return 3
        }
    }

    private func remoteDiscoveryScript(socketName: String?, includeGitMetadata: Bool) -> String {
        let socketBinding = socketName?.holyTrimmed.nilIfEmpty.map(posixQuote) ?? "''"
        let includeGitMetadataFlag = includeGitMetadata ? "1" : "0"

        return """
        setopt pipefail
        socket_name=\(socketBinding)
        include_git_metadata=\(includeGitMetadataFlag)
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

        trimmed_value() {
          local value="$1"
          value="${value#"${value%%[![:space:]]*}"}"
          value="${value%"${value##*[![:space:]]}"}"
          printf '%s' "$value"
        }

        option_value() {
          local session_name="$1"
          local option_name="$2"
          "${tmux_cmd[@]}" show-options -qv -t "$session_name" "$option_name" 2>/dev/null || true
        }

        pane_value() {
          local session_name="$1"
          local format="$2"
          "${tmux_cmd[@]}" display-message -p -t "$session_name" "$format" 2>/dev/null || true
        }

        project_candidate() {
          local value lowered
          value=$(trimmed_value "$1")
          [[ -z "$value" ]] && return 1
          [[ "$value" == */* ]] && return 1
          live_agent_status_title "$value" && return 1

          lowered="${value:l}"
          [[ "$lowered" =~ '^[0-9]+$' ]] && return 1
          [[ "$lowered" == *"claude code"* ]] && return 1
          [[ "$lowered" == *"codex cli"* ]] && return 1

          case "$lowered" in
            zsh|bash|sh|fish|tmux|"[tmux]"|node|python|python[0-9]*|*.exe|*.local|localhost|holy-*|ai|coding|custom-coding|custom_coding|projects|repos|repositories|workspace|workspaces)
              return 1
              ;;
          esac

          printf '%s' "$value"
        }

        live_agent_status_title() {
          local value first
          value=$(trimmed_value "$1")
          [[ -z "$value" ]] && return 1

          first="${value[1,1]}"
          case "$first" in
            ✱|✳|✻|✽|✢|⏺|●|○|◐|◓|◑|◒|•|·|⠂|⠄|⠆|⠇|⠋|⠐|⠴|⠼|⠿)
              return 0
              ;;
          esac

          return 1
        }

        generic_directory_name() {
          local value lowered
          value=$(trimmed_value "$1")
          lowered="${value:l}"
          case "$lowered" in
            custom-coding|custom_coding|projects|repos|repositories|workspace|workspaces)
              return 0
              ;;
          esac
          return 1
        }

        generated_holy_title() {
          local value lowered
          value=$(trimmed_value "$1")
          [[ -z "$value" ]] && return 0
          lowered="${value:l}"
          [[ "$lowered" == "shell" ]] && return 0
          [[ "$lowered" =~ '^shell[[:space:]]+[0-9]+$' ]] && return 0
          [[ "$lowered" == "claude" || "$lowered" == "codex" || "$lowered" == "opencode" ]] && return 0
          [[ "$lowered" == "local" || "$lowered" == "mac" || "$lowered" == "local mac" || "$lowered" == "this mac" || "$lowered" == "localhost" ]] && return 0
          return 1
        }

        inferred_runtime() {
          local configured lowered candidate
          configured=$(trimmed_value "$1")
          shift

          if [[ -n "$configured" && "$configured" != "shell" ]]; then
            printf '%s' "$configured"
            return
          fi

          for candidate in "$@"; do
            lowered="$(trimmed_value "$candidate")"
            lowered="${lowered:l}"
            [[ -z "$lowered" ]] && continue

            if [[ "$lowered" == *"opencode"* || "$lowered" == *"open code"* ]]; then
              printf '%s' "opencode"
              return
            fi

            if [[ "$lowered" == *"codex"* || "$lowered" == *"openai codex"* ]]; then
              printf '%s' "codex"
              return
            fi

            if [[ "$lowered" == *"claude"* ]]; then
              printf '%s' "claude"
              return
            fi
          done

          printf '%s' "$configured"
        }

        process_tree_commands() {
          local root_pid="$1"
          local -a frontier next_frontier children
          local pid child command depth

          [[ -z "$root_pid" ]] && return 0
          frontier=("$root_pid")

          for depth in 1 2 3 4; do
            next_frontier=()

            for pid in "${frontier[@]}"; do
              children=($(pgrep -P "$pid" 2>/dev/null || true))
              for child in "${children[@]}"; do
                command=$(ps -p "$child" -o command= 2>/dev/null | head -n 1)
                command=$(trimmed_value "$command")
                [[ -n "$command" ]] && printf '%s\n' "$command"
                next_frontier+=("$child")
              done
            done

            (( ${#next_frontier[@]} == 0 )) && break
            frontier=("${next_frontier[@]}")
          done
        }

        inferred_working_directory() {
          local working_directory directory_name candidate raw_candidate base_directory
          working_directory=$(trimmed_value "$1")
          shift

          directory_name="${working_directory:t}"
          for raw_candidate in "$@"; do
            if candidate=$(project_candidate "$raw_candidate"); then
              if [[ "$candidate" == "$directory_name" ]]; then
                printf '%s' "$working_directory"
                return
              fi
              if generic_directory_name "$directory_name"; then
                base_directory="${working_directory%/}"
                [[ -z "$base_directory" ]] && base_directory="$working_directory"
                printf '%s/%s' "$base_directory" "$candidate"
                return
              fi
            fi
          done

          printf '%s' "$working_directory"
        }

        repository_name_for_directory() {
          local working_directory repository_root
          working_directory=$(trimmed_value "$1")
          [[ -z "$working_directory" ]] && return 1

          repository_root=$(git -C "$working_directory" rev-parse --show-toplevel 2>/dev/null) || return 1
          repository_root=$(trimmed_value "$repository_root")
          [[ -z "$repository_root" ]] && return 1

          printf '%s' "${repository_root:t}"
        }

        fallback_session_title() {
          local working_directory candidate raw_candidate directory_name repository_name
          local session_name="$2"
          local pane_title="$3"
          local window_name="$4"

          working_directory=$(trimmed_value "$1")

          if repository_name=$(repository_name_for_directory "$working_directory"); then
            printf '%s' "$repository_name"
            return
          fi

          directory_name="${working_directory:t}"
          if candidate=$(project_candidate "$directory_name"); then
            printf '%s' "$candidate"
            return
          fi

          if candidate=$(project_candidate "$session_name"); then
            printf '%s' "$candidate"
            return
          fi

          # Intentionally NOT falling back to pane_title / window_name: those
          # reflect the live foreground command or an agent's per-task status
          # line (e.g. "✱ Verify auto-commit"), which would churn and pollute
          # the persistent session name. A session with no stable identity is
          # left untitled rather than named after transient screen content.
          return 1
        }

        git_metadata() {
          local working_directory="$1"
          if [[ "$include_git_metadata" != "1" || -z "$working_directory" ]]; then
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
          pane_title=$(pane_value "$session_name" '#{pane_title}')
          window_name=$(pane_value "$session_name" '#{window_name}')
          pane_command=$(pane_value "$session_name" '#{pane_current_command}')
          pane_pid=$(pane_value "$session_name" '#{pane_pid}')
          process_context=$(process_tree_commands "$pane_pid" | tr '\n' ' ')
          metadata_working_directory=$(option_value "$session_name" @holy_working_directory)
          working_directory=$(pane_value "$session_name" '#{pane_current_path}')
          if [[ -n "$working_directory" ]]; then
            working_directory=$(inferred_working_directory "$working_directory" "$pane_title" "$window_name" "$session_name")
          else
            working_directory="$metadata_working_directory"
            working_directory=$(inferred_working_directory "$working_directory" "$pane_title" "$window_name" "$session_name")
          fi
          command=$(option_value "$session_name" @holy_command)
          runtime=$(inferred_runtime "$runtime" "$pane_command" "$process_context" "$window_name" "$pane_title" "$title" "$command" "$session_name")
          if generated_holy_title "$title"; then
            title=""
          fi
          if [[ -z "$title" ]]; then
            title=$(fallback_session_title "$working_directory" "$session_name" "$pane_title" "$window_name")
          fi
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

    /// The tmux socket namespaces discovery probes for a host. Converge treats
    /// exactly these namespaces as reachable on a successful sweep, so it never
    /// archives a session on a socket discovery never inspected. This is the
    /// single source of truth for probe coverage - callers must not hardcode
    /// socket names.
    nonisolated func probedSocketNames(for host: HolyRemoteHostRecord) -> [String?] {
        probeTargets(for: host.normalized()).map(\.socketName)
    }

    /// Socket namespaces probed by the local sweep. Mirrors the synthesized
    /// localhost host `discoverLocalSessionsThrowing` uses (default socket, no
    /// explicit override).
    nonisolated var localProbedSocketNames: [String?] {
        probeTargets(for: HolyRemoteHostRecord(sshDestination: "localhost")).map(\.socketName)
    }

    nonisolated private func probeTargets(for host: HolyRemoteHostRecord) -> [HolyRemoteProbeTarget] {
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

/// Resumes a discovery continuation exactly once. The termination handler
/// (arbitrary Process queue) and the timeout task race to resolve the same
/// process run; whichever wins, the loser is a no-op. `store` always runs
/// before either resumer (synchronously at the top of the continuation body),
/// so there is no store-after-resume race to guard.
private final class HolyProcessRunResumeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<HolyRemoteCommandResult?, Never>?
    private var didResume = false

    func store(_ continuation: CheckedContinuation<HolyRemoteCommandResult?, Never>) {
        lock.lock()
        defer { lock.unlock() }
        self.continuation = continuation
    }

    func resume(returning value: HolyRemoteCommandResult?) {
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

#if DEBUG
extension HolyRemoteTmuxDiscoveryService {
    /// Runs `/bin/sleep <sleepSeconds>` under the wall-clock cap and reports
    /// whether the cap fired (result nil). Exercises the converge timeout end
    /// to end - no SSH, roster, or dependency-injection scaffolding required.
    static func runProcessWithTimeoutForTesting(
        sleepSeconds: Int,
        timeoutSeconds: TimeInterval
    ) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = [String(sleepSeconds)]
        let result = await shared.run(process: process, context: "timeout-test", timeout: timeoutSeconds)
        return result == nil
    }
}
#endif
