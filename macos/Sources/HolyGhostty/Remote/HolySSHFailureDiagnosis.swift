import Foundation

enum HolySSHFailureKind: String, Sendable, Equatable {
    /// sshd/launchd rejected a new connection before authentication, most
    /// commonly because the macOS inetd instance budget is saturated.
    case serverAdmissionRejected
    case network
    case hostVerification
    case authentication
    case remoteCommand
    case transport
}

struct HolySSHFailureDiagnosis: Sendable, Equatable {
    let kind: HolySSHFailureKind
    let destination: String
    let exitCode: Int32
    let evidence: String?

    var headline: String {
        switch kind {
        case .serverAdmissionRejected:
            return "SSH instance saturation"
        case .network:
            return "SSH network failure"
        case .hostVerification:
            return "SSH host verification failed"
        case .authentication:
            return "SSH authentication failed"
        case .remoteCommand:
            return "Remote command failed"
        case .transport:
            return "SSH transport failed"
        }
    }

    var userMessage: String {
        let detail: String
        switch kind {
        case .serverAdmissionRejected:
            detail = "The SSH service on \(destination) rejected a connection during key exchange. Its server instance limit is saturated; this is not a generic reachability failure."
        case .network:
            detail = "Holy could not establish a network connection to \(destination). Check the host name, route, VPN or Tailscale path, and whether SSH is listening."
        case .hostVerification:
            detail = "Holy reached \(destination), but SSH would not trust its host key. Connect once in Terminal and verify the key before retrying."
        case .authentication:
            detail = "Holy reached \(destination), but SSH authentication was rejected. Check the selected user, key, and agent."
        case .remoteCommand:
            detail = "SSH reached \(destination), but the command on the remote host failed. The connection itself was healthy."
        case .transport:
            detail = "SSH exited before Holy could prove whether it reached \(destination). See the logged SSH evidence for the exact transport failure."
        }

        guard let evidence = evidence?.trimmingCharacters(in: .whitespacesAndNewlines),
              !evidence.isEmpty else {
            return detail
        }
        return "\(detail) SSH said: \(evidence)"
    }

    var logMessage: String {
        "\(headline) for \(destination) [kind: \(kind.rawValue); exit: \(exitCode)]: \(evidence ?? "no stderr or stdout")"
    }

    static func diagnose(
        destination: String,
        exitCode: Int32,
        stderr: String,
        stdout: String = "",
        remoteCommandStarted: Bool = false
    ) -> Self? {
        guard exitCode != 0 else { return nil }

        let rawEvidence = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfSSHDiagnosisEmpty
            ?? stdout.trimmingCharacters(in: .whitespacesAndNewlines).nilIfSSHDiagnosisEmpty
        let lowered = [stderr, stdout].joined(separator: "\n").lowercased()
        let hasRemoteStageMarker = lowered.contains("holy_tmux_stage:")

        let kind: HolySSHFailureKind
        if remoteCommandStarted || hasRemoteStageMarker || exitCode != 255 {
            kind = .remoteCommand
        } else if isServerAdmissionRejection(lowered) {
            kind = .serverAdmissionRejected
        } else if isHostVerificationFailure(lowered) {
            kind = .hostVerification
        } else if isAuthenticationFailure(lowered) {
            kind = .authentication
        } else if isNetworkFailure(lowered) {
            kind = .network
        } else {
            kind = .transport
        }

        return .init(
            kind: kind,
            destination: destination.trimmingCharacters(in: .whitespacesAndNewlines),
            exitCode: exitCode,
            evidence: conciseEvidence(rawEvidence)
        )
    }

    /// The terminal-surface path is rendered before an async Swift caller can
    /// inspect a Process result. Keep its messages aligned with `diagnose` so
    /// exit 255 is never flattened into a generic reachability claim.
    /// The rendered zsh expects `holy_status` and `holy_ssh_evidence`.
    static func shellReporterScript(destination: String) -> String {
        let destination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        holy_ssh_lowered="${holy_ssh_evidence:l}"
        if (( holy_status != 255 )); then
          holy_ssh_diagnosis=\(posixQuote("Remote command failed: SSH reached \(destination), but the command on the remote host failed."))
        elif [[ ( "$holy_ssh_lowered" == *kex_exchange_identification* || "$holy_ssh_lowered" == *ssh_exchange_identification* ) && ( "$holy_ssh_lowered" == *connection\\ reset\\ by\\ peer* || "$holy_ssh_lowered" == *connection\\ closed\\ by\\ remote\\ host* || "$holy_ssh_lowered" == *read:\\ connection\\ reset* ) ]] || [[ "$holy_ssh_lowered" == *maxstartups* || "$holy_ssh_lowered" == *too\\ many\\ unauthenticated\\ connections* || "$holy_ssh_lowered" == *drop\\ connection\\ \\#* ]]; then
          holy_ssh_diagnosis=\(posixQuote("SSH instance saturation: \(destination) rejected the connection during key exchange. Its server admission limit is saturated."))
        elif [[ "$holy_ssh_lowered" == *host\\ key\\ verification\\ failed* || "$holy_ssh_lowered" == *remote\\ host\\ identification\\ has\\ changed* ]]; then
          holy_ssh_diagnosis=\(posixQuote("SSH host verification failed for \(destination). Verify the host key in Terminal before retrying."))
        elif [[ "$holy_ssh_lowered" == *permission\\ denied* || "$holy_ssh_lowered" == *authentication\\ failed* || "$holy_ssh_lowered" == *too\\ many\\ authentication\\ failures* || "$holy_ssh_lowered" == *no\\ supported\\ authentication\\ methods\\ available* ]]; then
          holy_ssh_diagnosis=\(posixQuote("SSH authentication failed for \(destination). Check the selected user, key, and agent."))
        elif [[ "$holy_ssh_lowered" == *could\\ not\\ resolve\\ hostname* || "$holy_ssh_lowered" == *name\\ or\\ service\\ not\\ known* || "$holy_ssh_lowered" == *nodename\\ nor\\ servname\\ provided* || "$holy_ssh_lowered" == *no\\ route\\ to\\ host* || "$holy_ssh_lowered" == *network\\ is\\ unreachable* || "$holy_ssh_lowered" == *connection\\ timed\\ out* || "$holy_ssh_lowered" == *operation\\ timed\\ out* || "$holy_ssh_lowered" == *connection\\ refused* ]]; then
          holy_ssh_diagnosis=\(posixQuote("SSH network failure for \(destination). Check the host name, route, VPN or Tailscale path, and whether SSH is listening."))
        else
          holy_ssh_diagnosis=\(posixQuote("SSH transport failed for \(destination). SSH exited before Holy could prove whether it reached the host."))
        fi
        printf '%s\n' "$holy_ssh_diagnosis" >&2
        /usr/bin/logger -t org.holyghostty.ssh -- "$holy_ssh_diagnosis Evidence: $holy_ssh_evidence" 2>/dev/null &!
        """
    }

    private static func isServerAdmissionRejection(_ value: String) -> Bool {
        let keyExchangeFailed = value.contains("kex_exchange_identification")
            || value.contains("ssh_exchange_identification")
        let admissionReset = value.contains("connection reset by peer")
            || value.contains("connection closed by remote host")
            || value.contains("read: connection reset")

        return (keyExchangeFailed && admissionReset)
            || value.contains("maxstartups")
            || value.contains("too many unauthenticated connections")
            || value.contains("drop connection #")
    }

    private static func isNetworkFailure(_ value: String) -> Bool {
        [
            "could not resolve hostname",
            "name or service not known",
            "nodename nor servname provided",
            "no route to host",
            "network is unreachable",
            "connection timed out",
            "operation timed out",
            "connection refused",
        ].contains(where: value.contains)
    }

    private static func isHostVerificationFailure(_ value: String) -> Bool {
        value.contains("host key verification failed")
            || value.contains("remote host identification has changed")
    }

    private static func isAuthenticationFailure(_ value: String) -> Bool {
        value.contains("permission denied")
            || value.contains("authentication failed")
            || value.contains("too many authentication failures")
            || value.contains("no supported authentication methods available")
    }

    private static func conciseEvidence(_ value: String?) -> String? {
        guard let value else { return nil }
        let lines = value
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }
        return lines.prefix(3).joined(separator: " | ")
    }

    private static func posixQuote(_ value: String) -> String {
        if value.isEmpty { return "''" }
        return "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}

private extension String {
    var nilIfSSHDiagnosisEmpty: String? {
        isEmpty ? nil : self
    }
}
