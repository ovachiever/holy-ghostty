import CryptoKit
import Darwin
import Foundation

enum HolySSHTransportLane: String, Sendable, Equatable {
    // Raw values ride inside the ControlPath socket filename, which counts
    // against the 104-byte sun_path cap (see controlPathByteLimit) — keep
    // them at two characters or fewer.
    case interactive0 = "i0"
    case interactive1 = "i1"
    case control = "c"
}

enum HolySSHTransportPurpose: Sendable, Equatable {
    case interactive(sessionKey: String)
    case control
}

enum HolySSHTransportError: Error, Sendable, Equatable, LocalizedError {
    case invalidDestination
    case transportOptionOverride
    case controlPathTooLong(path: String, limit: Int)

    var errorDescription: String? {
        switch self {
        case .invalidDestination:
            return "The SSH destination is invalid."
        case .transportOptionOverride:
            return "A caller attempted to override Holy's SSH transport ownership."
        case let .controlPathTooLong(path, limit):
            return "The SSH control socket path is \(path.utf8.count) bytes; "
                + "OpenSSH's mux listener needs it at or under \(limit) "
                + "(sun_path minus the temporary-bind suffix): \(path)"
        }
    }
}

struct HolySSHTransportCommand: Sendable, Equatable {
    let executablePath: String
    let arguments: [String]
    let controlPath: String
    let lane: HolySSHTransportLane

    var executableURL: URL {
        URL(fileURLWithPath: executablePath)
    }

    var shellInvocation: String {
        ([executablePath] + arguments)
            .map(Self.posixQuote)
            .joined(separator: " ")
    }

    private static func posixQuote(_ value: String) -> String {
        if value.isEmpty { return "''" }
        return "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}

/// Owns every outbound SSH connection made by Holy Ghostty.
///
/// Each stored destination gets exactly three possible TCP-bearing masters:
/// two lanes for terminal surfaces and one lane reserved for control work.
/// Every ordinary command is forced through one of those sockets. Its
/// `ProxyCommand=/usr/bin/false` is deliberate: if a checked master dies in
/// the narrow interval before the client attaches, the client fails closed
/// instead of silently opening a fourth server connection.
///
/// Master creation happens inside the rendered wrapper because terminal
/// surfaces are configured synchronously. A filesystem lock serializes every
/// process in this app, `ssh -O check` distinguishes a live master from a
/// stale socket, and only the lock owner may remove or recreate that socket.
/// Reconnect waits are finite and increasing, which absorbs the ordinary
/// sleep/network/Tailscale convergence window without creating a handshake
/// storm.
final class HolySSHTransportManager: @unchecked Sendable {
    static let shared = HolySSHTransportManager()

    static let interactiveLaneCount = 2
    static let maximumConnectionCountPerDestination = 3

    let controlDirectoryURL: URL
    private let sshExecutableURL: URL

    init(
        controlDirectoryURL: URL = HolySSHTransportManager.defaultControlDirectoryURL(),
        sshExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/ssh")
    ) {
        self.controlDirectoryURL = controlDirectoryURL.standardizedFileURL
        self.sshExecutableURL = sshExecutableURL.standardizedFileURL
        prepareControlDirectory()
    }

    func command(
        destination rawDestination: String,
        purpose: HolySSHTransportPurpose,
        controlOperation: HolySSHControlOperation = .metadata,
        options: [String] = [],
        remoteCommand: [String]
    ) throws -> HolySSHTransportCommand {
        let destination = try validatedDestination(rawDestination)
        guard callerOptionsAreSafe(options) else {
            throw HolySSHTransportError.transportOptionOverride
        }

        prepareControlDirectory()

        let lane = lane(for: purpose)
        let controlPath = try controlPath(destination: destination, lane: lane)
        let admissionPlan: HolySSHAdmissionShellPlan = switch purpose {
        case .interactive:
            .surface(
                controlPath: controlPath,
                destination: destination,
                interactiveLaneCount: Self.interactiveLaneCount
            )
        case .control:
            .control(
                controlPath: controlPath,
                destination: destination,
                operation: controlOperation
            )
        }
        let wrapper = wrapperScript(
            destination: destination,
            lane: lane,
            controlPath: controlPath,
            admissionPlan: admissionPlan,
            clientOptions: options,
            remoteCommand: remoteCommand
        )

        return HolySSHTransportCommand(
            executablePath: "/bin/zsh",
            arguments: ["-c", wrapper],
            controlPath: controlPath,
            lane: lane
        )
    }

    func controlPath(
        destination rawDestination: String,
        purpose: HolySSHTransportPurpose
    ) throws -> String {
        let destination = try validatedDestination(rawDestination)
        return try controlPath(destination: destination, lane: lane(for: purpose))
    }

    private func validatedDestination(_ rawDestination: String) throws -> String {
        let destination = rawDestination.trimmingCharacters(in: .whitespacesAndNewlines)
        let bytes = Array(destination.utf8)
        guard destination == rawDestination,
              !bytes.isEmpty,
              bytes.count <= 512,
              let first = bytes.first,
              Self.isASCIIAlphanumeric(first),
              bytes.allSatisfy(Self.isAllowedDestinationByte(_:)) else {
            throw HolySSHTransportError.invalidDestination
        }
        return destination
    }

    private static func isASCIIAlphanumeric(_ byte: UInt8) -> Bool {
        (48 ... 57).contains(byte)
            || (65 ... 90).contains(byte)
            || (97 ... 122).contains(byte)
    }

    private static func isAllowedDestinationByte(_ byte: UInt8) -> Bool {
        isASCIIAlphanumeric(byte)
            || [37, 45, 46, 58, 64, 91, 93, 95].contains(byte)
    }

    private func lane(for purpose: HolySSHTransportPurpose) -> HolySSHTransportLane {
        switch purpose {
        case .control:
            return .control
        case let .interactive(sessionKey):
            let digest = Array(SHA256.hash(data: Data(sessionKey.utf8)))
            return digest.first.map { $0 % 2 == 0 ? .interactive0 : .interactive1 }
                ?? .interactive0
        }
    }

    /// OpenSSH's mux listener binds the configured path plus "." and 16
    /// random characters, then checks the result against sun_path (104
    /// bytes, NUL included). 104 - 17 - 1 leaves 86 bytes for the path we
    /// configure; exceeding it kills every master with unix_listener errors
    /// before the connection exists.
    static let controlPathByteLimit = 86

    private func controlPath(destination: String, lane: HolySSHTransportLane) throws -> String {
        let hostKey = HolySSHAdmissionController.hostKey(for: destination)
        // 16 bytes (128 bits) of digest: a running mux master ignores the
        // destination argument, so two hosts colliding on this name would
        // silently share a connection — collision resistance is a security
        // property here, not hygiene. The short ~/.holy/ssh base leaves
        // ample room under controlPathByteLimit even with long usernames.
        let digest = SHA256.hash(data: Data(hostKey.utf8))
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
        let path = controlDirectoryURL
            .appendingPathComponent("h\(digest)-\(lane.rawValue).sock", isDirectory: false)
            .path
        guard path.utf8.count <= Self.controlPathByteLimit else {
            throw HolySSHTransportError.controlPathTooLong(
                path: path,
                limit: Self.controlPathByteLimit
            )
        }
        return path
    }

    private func wrapperScript(
        destination: String,
        lane: HolySSHTransportLane,
        controlPath: String,
        admissionPlan: HolySSHAdmissionShellPlan,
        clientOptions: [String],
        remoteCommand: [String]
    ) -> String {
        let directory = controlDirectoryURL.path
        let lockPath = controlPath + ".lock"
        let sshPath = sshExecutableURL.path
        let connectTimeout = lane == .control ? "5" : "8"
        let batchMode = lane == .control ? ["-o", "BatchMode=yes"] : []

        let healthCommand = shellCommand([
            sshPath,
            "-S", controlPath,
            "-o", "ControlPath=\(controlPath)",
            "-O", "check",
            "--", destination,
        ])
        let bootstrapCommand = shellCommand([
            sshPath,
            "-M", "-N", "-f",
            "-S", controlPath,
            "-o", "ControlMaster=yes",
            "-o", "ControlPath=\(controlPath)",
            "-o", "ControlPersist=600",
            "-o", "ConnectionAttempts=1",
            "-o", "ConnectTimeout=\(connectTimeout)",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=2",
            "-o", "TCPKeepAlive=no",
        ] + batchMode + ["--", destination])
        let rawClientCommand = shellCommand([
            sshPath,
            "-S", controlPath,
            "-o", "ControlMaster=no",
            "-o", "ControlPath=\(controlPath)",
            "-o", "ProxyCommand=/usr/bin/false",
        ] + batchMode + clientOptions + ["--", destination] + remoteCommand)
        let clientCommand = shellCommand([
            "/bin/zsh", "-c",
            clientRunnerScript(
                destination: destination,
                controlPath: controlPath,
                clientCommand: rawClientCommand
            ),
        ])
        let admittedClientCommand = admissionPlan.wrapping(clientCommand: clientCommand)
        let bootstrapFailureReporter = HolySSHFailureDiagnosis.shellReporterScript(
            destination: destination
        )

        return """
        setopt NO_NOMATCH
        umask 077
        holy_control_dir=\(posixQuote(directory))
        holy_control_path=\(posixQuote(controlPath))
        holy_lock_path=\(posixQuote(lockPath))
        if [[ -L "$holy_control_dir" ]]; then
          printf '%s\n' 'Holy SSH control directory is a symbolic link; refusing to connect.' >&2
          exit 255
        fi
        /bin/mkdir -p -- "$holy_control_dir" || exit 255
        /bin/chmod 700 "$holy_control_dir" || exit 255

        holy_master_is_healthy() {
          \(healthCommand) >/dev/null 2>&1
        }
        holy_release_lock() {
          /bin/rm -f -- "$holy_lock_path/owner"
          /bin/rmdir -- "$holy_lock_path" 2>/dev/null || true
        }
        holy_take_lock() {
          if /bin/mkdir -- "$holy_lock_path" 2>/dev/null; then
            printf '%s %s\n' "$$" "$(/bin/date +%s)" > "$holy_lock_path/owner"
            return 0
          fi

          holy_lock_mtime=$(/usr/bin/stat -f '%m' -- "$holy_lock_path" 2>/dev/null || printf '0')
          holy_now=$(/bin/date +%s)
          case "$holy_lock_mtime" in
            ''|*[!0-9]*) holy_lock_mtime=0 ;;
          esac
          if (( holy_now - holy_lock_mtime < 30 )); then
            return 1
          fi

          holy_stale_lock="$holy_lock_path.stale.$$.$holy_attempt"
          if /bin/mv -- "$holy_lock_path" "$holy_stale_lock" 2>/dev/null; then
            /bin/rm -f -- "$holy_stale_lock/owner"
            /bin/rmdir -- "$holy_stale_lock" 2>/dev/null || true
          fi
          if /bin/mkdir -- "$holy_lock_path" 2>/dev/null; then
            printf '%s %s\n' "$$" "$(/bin/date +%s)" > "$holy_lock_path/owner"
            return 0
          fi
          return 1
        }

        holy_attempt=0
        holy_last_bootstrap_evidence=''
        while ! holy_master_is_healthy; do
          holy_attempt=$((holy_attempt + 1))
          if holy_take_lock; then
            trap holy_release_lock EXIT HUP INT TERM
            if ! holy_master_is_healthy; then
              /bin/rm -f -- "$holy_control_path"
              holy_bootstrap_evidence="$(\(bootstrapCommand) 2>&1)"
              if [[ -n "$holy_bootstrap_evidence" ]]; then
                holy_last_bootstrap_evidence="$holy_bootstrap_evidence"
              fi
            fi
            holy_release_lock
            trap - EXIT HUP INT TERM
          fi

          if holy_master_is_healthy; then
            break
          fi
          if (( holy_attempt >= 12 )); then
            holy_status=255
            holy_ssh_evidence="$holy_last_bootstrap_evidence"
            if [[ -n "$holy_ssh_evidence" ]]; then
              printf '%s\n' "$holy_ssh_evidence" >&2
            fi
            \(bootstrapFailureReporter)
            exit 255
          fi
          case "$holy_attempt" in
            1) /bin/sleep 0.10 ;;
            2) /bin/sleep 0.20 ;;
            3) /bin/sleep 0.40 ;;
            4) /bin/sleep 0.80 ;;
            *) /bin/sleep 1.00 ;;
          esac
        done

        \(admittedClientCommand)
        """
    }

    private func clientRunnerScript(
        destination: String,
        controlPath: String,
        clientCommand: String
    ) -> String {
        let failureReporter = HolySSHFailureDiagnosis.shellReporterScript(destination: destination)
        return """
        holy_ssh_error_file=\(posixQuote(controlPath + ".client-error")).$$
        if [[ -L "$holy_ssh_error_file" ]]; then
          printf '%s\n' 'Holy found an unsafe SSH diagnostic file; refusing to connect.' >&2
          exit 255
        fi
        (umask 077; : > "$holy_ssh_error_file") || exit 255
        holy_cleanup_ssh_error() {
          /bin/rm -f -- "$holy_ssh_error_file"
        }
        trap holy_cleanup_ssh_error EXIT HUP INT TERM
        \(clientCommand) 2> "$holy_ssh_error_file"
        holy_status=$?
        if [[ -n "$holy_admission_fd" ]]; then
          zmodload zsh/system 2>/dev/null || true
          zsystem flock -u "$holy_admission_fd" 2>/dev/null || true
          unset holy_admission_fd
        fi
        holy_ssh_evidence="$(< "$holy_ssh_error_file")"
        if [[ -n "$holy_ssh_evidence" ]]; then
          printf '%s\n' "$holy_ssh_evidence" >&2
        fi
        if (( holy_status != 0 )); then
          \(failureReporter)
        fi
        holy_cleanup_ssh_error
        trap - EXIT HUP INT TERM
        exit "$holy_status"
        """
    }

    private func prepareControlDirectory() {
        do {
            try FileManager.default.createDirectory(
                at: controlDirectoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
            _ = Darwin.chmod(controlDirectoryURL.path, mode_t(0o700))
        } catch {
            // The rendered command repeats this operation and fails closed
            // with stderr attached to the caller. Planning stays pure enough
            // for UI construction and tests without silently using raw SSH.
        }
    }

    private func callerOptionsAreSafe(_ options: [String]) -> Bool {
        var index = 0
        while index < options.count {
            let token = options[index]
            switch token {
            case "-t", "-tt":
                index += 1
            case "-o":
                guard index + 1 < options.count,
                      isSafeOpenSSHOption(options[index + 1]) else {
                    return false
                }
                index += 2
            default:
                guard token.hasPrefix("-o"), token.count > 2,
                      isSafeOpenSSHOption(String(token.dropFirst(2))) else {
                    return false
                }
                index += 1
            }
        }
        return true
    }

    private func isSafeOpenSSHOption(_ rawOption: String) -> Bool {
        guard rawOption == rawOption.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawOption.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              let separator = rawOption.firstIndex(of: "="),
              separator != rawOption.startIndex else {
            return false
        }

        let name = rawOption[..<separator].lowercased()
        let value = String(rawOption[rawOption.index(after: separator)...])
        guard !value.isEmpty else { return false }

        switch name {
        case "batchmode", "tcpkeepalive":
            return value == "yes" || value == "no"
        case "connecttimeout", "connectionattempts", "serveraliveinterval", "serveralivecountmax":
            return value.utf8.allSatisfy { (48 ... 57).contains($0) }
        default:
            return false
        }
    }

    private func shellCommand(_ arguments: [String]) -> String {
        arguments.map(posixQuote).joined(separator: " ")
    }

    private func posixQuote(_ value: String) -> String {
        if value.isEmpty { return "''" }
        return "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private static func defaultControlDirectoryURL() -> URL {
        // ~/.holy/ssh, not Caches: the Caches prefix alone left the rendered
        // socket path 114-120 bytes — past the 86-byte cap for every macOS
        // user — so no master could ever bind. The home dot-directory keeps
        // the whole path around 36 bytes with room for long usernames, and
        // prepareControlDirectory() enforces 0700 on it.
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".holy", isDirectory: true)
            .appendingPathComponent("ssh", isDirectory: true)
    }
}
