import Foundation
import OSLog

actor HolyRemoteHostImportService {
    static let shared = HolyRemoteHostImportService()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "org.holyghostty.app",
        category: "HolyRemoteHostImport"
    )

    func importSSHConfigHosts() -> [HolyRemoteHostRecord] {
        let configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh", isDirectory: true)
            .appendingPathComponent("config", isDirectory: false)

        guard let config = try? String(contentsOf: configURL, encoding: .utf8) else {
            return []
        }

        var discoveredAliases: [String] = []

        for rawLine in config.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            let lowered = line.lowercased()
            guard lowered.hasPrefix("host ") else { continue }

            let aliases = line.dropFirst(4)
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)
                .filter(Self.isConcreteSSHHostAlias(_:))

            discoveredAliases.append(contentsOf: aliases)
        }

        return Array(Set(discoveredAliases))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map {
                HolyRemoteHostRecord(
                    label: $0,
                    sshDestination: $0,
                    tmuxSocketName: nil
                )
            }
    }

    func importTailscaleHosts() -> [HolyRemoteHostRecord] {
        guard let tailscaleBinary = findExecutable(named: "tailscale") else {
            return []
        }

        let process = Process()
        process.executableURL = tailscaleBinary
        process.arguments = ["status", "--json"]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            logger.error("Failed to run tailscale status: \(error.localizedDescription, privacy: .public)")
            return []
        }

        guard process.terminationStatus == 0 else {
            let stderrText = String(
                bytes: stderr.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            logger.error("tailscale status failed: \(stderrText, privacy: .public)")
            return []
        }

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()

        do {
            let jsonData = sanitizedTailscaleJSON(from: stdoutData)
            let payload = try JSONDecoder().decode(HolyTailscaleStatusPayload.self, from: jsonData)
            return payload.peer.values
                .compactMap { peer -> HolyRemoteHostRecord? in
                    let destination = peer.normalizedDestination
                    guard let destination else { return nil }

                    return HolyRemoteHostRecord(
                        label: peer.displayLabel,
                        sshDestination: destination,
                        tmuxSocketName: nil
                    )
                }
                .sorted {
                    $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
                }
        } catch {
            logger.error("Failed to decode tailscale status: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func findExecutable(named name: String) -> URL? {
        let defaultPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ]

        let searchPaths = (ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []) + defaultPaths

        for path in searchPaths {
            let candidate = URL(fileURLWithPath: path).appendingPathComponent(name, isDirectory: false)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }

    private static func isConcreteSSHHostAlias(_ alias: String) -> Bool {
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !trimmed.contains("*") && !trimmed.contains("?") && !trimmed.contains("!")
    }

    private func sanitizedTailscaleJSON(from data: Data) -> Data {
        guard let text = String(data: data, encoding: .utf8),
              let jsonStart = text.firstIndex(of: "{") else {
            return data
        }

        return Data(text[jsonStart...].utf8)
    }
}

private struct HolyTailscaleStatusPayload: Decodable {
    let peer: [String: HolyTailscalePeer]

    enum CodingKeys: String, CodingKey {
        case peer = "Peer"
    }
}

private struct HolyTailscalePeer: Decodable {
    let hostName: String?
    let dnsName: String?
    let tailscaleIPs: [String]?

    enum CodingKeys: String, CodingKey {
        case hostName = "HostName"
        case dnsName = "DNSName"
        case tailscaleIPs = "TailscaleIPs"
    }

    var displayLabel: String {
        if let hostName = hostName?.holyTrimmed.nilIfEmpty {
            return hostName
        }

        if let dnsName = dnsName?.holyTrimmed.nilIfEmpty {
            return dnsName.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        }

        return tailscaleIPs?.first ?? "Tailscale Peer"
    }

    var normalizedDestination: String? {
        if let dnsName = dnsName?.holyTrimmed.nilIfEmpty {
            return dnsName.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        }

        return tailscaleIPs?.first?.holyTrimmed.nilIfEmpty
    }
}

private extension String {
    var holyTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
