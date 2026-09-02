import Darwin
import Foundation
import Testing
@testable import Ghostty

struct HolySSHTransportManagerTests {
    @Test func literalMagicDNSDestinationGetsTwoInteractiveLanesAndOneReservedLane() throws {
        let fixture = try HolySSHTransportTestFixture()
        defer { fixture.destroy() }
        let manager = fixture.manager()
        let destination = "studio.blue-wren.ts.net"

        let interactive = try (0 ..< 40).map { index in
            try manager.command(
                destination: destination,
                purpose: .interactive(sessionKey: "surface-\(index)"),
                options: ["-tt"],
                remoteCommand: ["tmux attach -t session-\(index)"]
            )
        }
        let controls = try (0 ..< 20).map { index in
            try manager.command(
                destination: destination,
                purpose: .control,
                options: ["-o", "BatchMode=yes"],
                remoteCommand: ["tmux list-sessions # \(index)"]
            )
        }

        let interactivePaths = Set(interactive.map(\.controlPath))
        let controlPaths = Set(controls.map(\.controlPath))
        let everyPath = interactivePaths.union(controlPaths)

        #expect(interactivePaths.count == HolySSHTransportManager.interactiveLaneCount)
        #expect(controlPaths.count == 1)
        #expect(interactivePaths.isDisjoint(with: controlPaths))
        #expect(everyPath.count == HolySSHTransportManager.maximumConnectionCountPerDestination)
        #expect(controls.allSatisfy { $0.lane == .control })
        #expect(try manager.controlPath(
            destination: "STUDIO.BLUE-WREN.TS.NET",
            purpose: .control
        ) == controls.first?.controlPath)
    }

    @Test func wrapperChecksHealthLocksRecoveryAndCannotFallBackToRawTCP() throws {
        let fixture = try HolySSHTransportTestFixture()
        defer { fixture.destroy() }
        let destination = "erik@studio.blue-wren.ts.net"
        let command = try fixture.manager().command(
            destination: destination,
            purpose: .control,
            options: ["-o", "BatchMode=yes"],
            remoteCommand: ["true"]
        )
        let script = try #require(command.arguments.last)

        #expect(script.contains("'-O' 'check' '--' '\(destination)'"))
        #expect(script.contains("'-M' '-N' '-f'"))
        #expect(script.contains("'ControlMaster=yes'"))
        #expect(script.contains("'ControlPersist=600'"))
        #expect(script.contains("ProxyCommand=/usr/bin/false"))
        #expect(script.contains("/bin/mkdir -- \"$holy_lock_path\""))
        #expect(script.contains("/bin/rm -f -- \"$holy_control_path\""))
        #expect(script.contains("holy_attempt >= 12"))
        #expect(script.contains("zsystem flock -e -t 0"))
        #expect(script.contains("SSH instance saturation"))
        #expect(script.components(separatedBy: "'--' '\(destination)'").count - 1 == 2)
    }

    @Test func renderedAdmissionKeepsLifecycleSlotsOutsideTheSharedPool() throws {
        let fixture = try HolySSHTransportTestFixture()
        defer { fixture.destroy() }
        let manager = fixture.manager()

        let surface = try manager.command(
            destination: "studio",
            purpose: .interactive(sessionKey: "surface"),
            remoteCommand: ["true"]
        )
        let discovery = try manager.command(
            destination: "studio",
            purpose: .control,
            controlOperation: .discovery,
            remoteCommand: ["true"]
        )
        let lifecycle = try manager.command(
            destination: "studio",
            purpose: .control,
            controlOperation: .lifecycle,
            remoteCommand: ["true"]
        )
        let lifecycleDiscovery = try manager.command(
            destination: "studio",
            purpose: .control,
            controlOperation: .lifecycleDiscovery,
            remoteCommand: ["true"]
        )
        let surfaceScript = try #require(surface.arguments.last)
        let discoveryScript = try #require(discovery.arguments.last)
        let lifecycleScript = try #require(lifecycle.arguments.last)
        let lifecycleDiscoveryScript = try #require(lifecycleDiscovery.arguments.last)

        #expect(surfaceScript.contains("for holy_slot_index in 0 1 2 3 4 5 6 7 8; do"))
        #expect(discoveryScript.contains("for holy_slot_index in 0 1 2 3 4 5; do"))
        #expect(lifecycleScript.contains("for holy_slot_index in 6 7 0 1 2 3 4 5; do"))
        #expect(lifecycleDiscoveryScript.contains("for holy_slot_index in 6 7 0 1 2 3 4 5; do"))
    }

    @Test func syntheticKeyExchangeResetPrintsExplicitSaturationDiagnosis() throws {
        let fixture = try HolySSHTransportTestFixture()
        defer { fixture.destroy() }
        let command = try fixture.manager().command(
            destination: "studio",
            purpose: .control,
            controlOperation: .discovery,
            remoteCommand: ["true"]
        )
        try Data().write(to: URL(fileURLWithPath: command.controlPath))

        let result = fixture.runCapturing(
            command,
            clientFailure: "kex_exchange_identification: read: Connection reset by peer"
        )

        #expect(result.status == 255)
        #expect(result.stderr.contains("SSH instance saturation"))
        #expect(result.stderr.contains("server admission limit is saturated"))
        #expect(!result.stderr.contains("could not reach"))
    }

    @Test func controlDirectoryIsForcedPrivate() throws {
        let fixture = try HolySSHTransportTestFixture(initialDirectoryMode: 0o755)
        defer { fixture.destroy() }
        _ = fixture.manager()

        let attributes = try FileManager.default.attributesOfItem(
            atPath: fixture.controlDirectoryURL.path
        )
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(permissions.intValue & 0o777 == 0o700)
    }

    @Test func managerRejectsEveryDestinationThatCouldBecomeAnSSHOption() throws {
        let fixture = try HolySSHTransportTestFixture()
        defer { fixture.destroy() }
        let manager = fixture.manager()
        let invalidDestinations = [
            "-oProxyCommand=evil",
            " host.example",
            "host.example ",
            "host name",
            "host\nname",
            "host;touch",
            "user+tag@host",
        ]

        for destination in invalidDestinations {
            #expect(throws: HolySSHTransportError.invalidDestination) {
                try manager.command(
                    destination: destination,
                    purpose: .control,
                    remoteCommand: ["true"]
                )
            }
            #expect(throws: HolySSHTransportError.invalidDestination) {
                try manager.command(
                    destination: destination,
                    purpose: .interactive(sessionKey: "surface"),
                    remoteCommand: ["true"]
                )
            }
        }
    }

    @Test func managerRejectsEveryCallerOptionThatCanRerouteTransport() throws {
        let fixture = try HolySSHTransportTestFixture()
        defer { fixture.destroy() }
        let manager = fixture.manager()
        let rejectedOptions = [
            ["-S", "/tmp/foreign.sock"],
            ["-M"],
            ["-J", "jump.example"],
            ["-F", "/tmp/foreign-config"],
            ["-W", "host:22"],
            ["-O", "exit"],
            ["-o", "ControlMaster=auto"],
            ["-oControlPath=/tmp/foreign.sock"],
            ["-o", "ControlPersist=yes"],
            ["-o", "ProxyCommand=evil"],
            ["-o", "ProxyJump=jump.example"],
            ["-o", "LocalCommand=evil"],
            ["-o", "PermitLocalCommand=yes"],
            ["-o", "RemoteCommand=evil"],
            ["-o", "Include=/tmp/foreign-config"],
            ["-o", "ConnectTimeout=5 ProxyCommand=evil"],
            ["-o"],
            ["--"],
        ]

        for options in rejectedOptions {
            for purpose in [
                HolySSHTransportPurpose.control,
                HolySSHTransportPurpose.interactive(sessionKey: "surface"),
            ] {
                #expect(throws: HolySSHTransportError.transportOptionOverride) {
                    try manager.command(
                        destination: "studio.blue-wren.ts.net",
                        purpose: purpose,
                        options: options,
                        remoteCommand: ["true"]
                    )
                }
            }
        }
    }

    /// Synthetic 40-surface saturation plus a concurrent discovery storm.
    /// The fake server records only TCP-bearing bootstrap operations; every
    /// ordinary client must attach through a checked socket. If lock recovery
    /// races or any client falls back, this test either records more than
    /// three starts or returns a nonzero client status.
    @Test func fortySurfacesAndDiscoveryStormStartAtMostThreeConnections() async throws {
        let fixture = try HolySSHTransportTestFixture()
        defer { fixture.destroy() }
        let manager = fixture.manager()
        let destination = "studio.blue-wren.ts.net"

        var commands = try (0 ..< 40).map { index in
            try manager.command(
                destination: destination,
                purpose: .interactive(sessionKey: "surface-\(index)"),
                options: ["-tt"],
                remoteCommand: ["tmux attach -t session-\(index)"]
            )
        }
        commands += try (0 ..< 40).map { index in
            try manager.command(
                destination: destination,
                purpose: .control,
                options: ["-o", "BatchMode=yes"],
                remoteCommand: ["tmux list-sessions # discovery-\(index)"]
            )
        }

        let statuses = await withTaskGroup(of: Int32.self, returning: [Int32].self) { group in
            for command in commands {
                group.addTask {
                    await fixture.run(command)
                }
            }
            var values: [Int32] = []
            for await status in group {
                values.append(status)
            }
            return values
        }

        #expect(statuses.count == 80)
        let statusCounts = Dictionary(grouping: statuses, by: { $0 }).mapValues(\.count)
        #expect(statuses.allSatisfy { $0 == 0 }, "statuses: \(statusCounts)")
        let starts = try String(contentsOf: fixture.connectionLogURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        #expect(starts.count == HolySSHTransportManager.maximumConnectionCountPerDestination)
        #expect(Set(starts).count == HolySSHTransportManager.maximumConnectionCountPerDestination)
    }
}

private final class HolySSHTransportTestFixture: @unchecked Sendable {
    let rootURL: URL
    let controlDirectoryURL: URL
    let sshExecutableURL: URL
    let connectionLogURL: URL

    init(initialDirectoryMode: Int = 0o700) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-ssh-transport-tests-\(UUID().uuidString)", isDirectory: true)
        controlDirectoryURL = rootURL.appendingPathComponent("control", isDirectory: true)
        sshExecutableURL = rootURL.appendingPathComponent("fake-ssh", isDirectory: false)
        connectionLogURL = rootURL.appendingPathComponent("connection-starts.log", isDirectory: false)

        try FileManager.default.createDirectory(
            at: controlDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: initialDirectoryMode)]
        )
        try Data().write(to: connectionLogURL)
        try Self.fakeSSHScript.write(to: sshExecutableURL, atomically: true, encoding: .utf8)
        guard Darwin.chmod(sshExecutableURL.path, mode_t(0o700)) == 0 else {
            throw CocoaError(.fileWriteNoPermission)
        }
    }

    func manager() -> HolySSHTransportManager {
        HolySSHTransportManager(
            controlDirectoryURL: controlDirectoryURL,
            sshExecutableURL: sshExecutableURL
        )
    }

    func run(_ command: HolySSHTransportCommand) async -> Int32 {
        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        var environment = ProcessInfo.processInfo.environment
        environment["HOLY_FAKE_SSH_LOG"] = connectionLogURL.path
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        return await withCheckedContinuation { continuation in
            process.terminationHandler = { finishedProcess in
                continuation.resume(returning: finishedProcess.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: -1)
            }
        }
    }

    func runCapturing(
        _ command: HolySSHTransportCommand,
        clientFailure: String? = nil
    ) -> (status: Int32, stderr: String) {
        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        var environment = ProcessInfo.processInfo.environment
        environment["HOLY_FAKE_SSH_LOG"] = connectionLogURL.path
        environment["HOLY_FAKE_SSH_CLIENT_FAILURE"] = clientFailure
        process.environment = environment
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
            process.waitUntilExit()
            let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
            return (
                process.terminationStatus,
                String(bytes: stderrData, encoding: .utf8) ?? ""
            )
        } catch {
            return (-1, String(describing: error))
        }
    }

    func destroy() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    private static let fakeSSHScript = #"""
    #!/bin/zsh
    socket=''
    operation=''
    is_bootstrap=0
    while (( $# > 0 )); do
      case "$1" in
        -S)
          socket="$2"
          shift 2
          ;;
        -O)
          operation="$2"
          shift 2
          ;;
        -M)
          is_bootstrap=1
          shift
          ;;
        --)
          shift
          break
          ;;
        *)
          shift
          ;;
      esac
    done

    if [[ "$operation" == 'check' ]]; then
      [[ -f "$socket" ]]
      exit $?
    fi
    if (( is_bootstrap )); then
      /bin/sleep 0.10
      printf '%s\n' "$socket" >> "$HOLY_FAKE_SSH_LOG"
      : > "$socket"
      exit 0
    fi
    [[ -f "$socket" ]] || exit 90
    if [[ -n "$HOLY_FAKE_SSH_CLIENT_FAILURE" ]]; then
      printf '%s\n' "$HOLY_FAKE_SSH_CLIENT_FAILURE" >&2
      exit 255
    fi
    exit 0
    """#
}
