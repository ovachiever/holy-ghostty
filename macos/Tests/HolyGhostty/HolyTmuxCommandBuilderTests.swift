import Foundation
import Testing
@testable import Ghostty

private let holyTmuxAvailableForExactTargetTests: Bool = {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-lc", "command -v tmux >/dev/null 2>&1"]
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        return false
    }
}()

/// tmux matches a bare `-t name` by prefix when no exact session exists, so a
/// spawn or restore naming `lane` could attach to, or stamp metadata onto, an
/// existing `lane-2` (receipt: lane mn-e6e3d0, tmux 3.7c). Every target the
/// builder emits for a session name must be the exact form.
struct HolyTmuxCommandBuilderTests {
    /// `lane` is a prefix of `lane-2`, the collision the bare form falls into.
    private static let sessionName = "lane"
    private static let sessionTarget = "=lane"
    private static let paneTarget = "=lane:"

    /// Not `holy`: the managed socket makes the builder write the app's
    /// managed-tmux.conf, and these tests must not touch app data.
    private static func spec(
        socketName: String = "mn-8905ec",
        createIfMissing: Bool,
        ssh: Bool
    ) -> HolySessionLaunchSpec {
        var spec = HolySessionLaunchSpec.interactiveTmuxShell(title: "Lane")
        spec.runtime = .claude
        spec.command = "claude"
        spec.objective = "exact targets"
        spec.workingDirectory = "/tmp/lane"
        spec.tmux = .init(socketName: socketName, sessionName: sessionName, createIfMissing: createIfMissing)
        if ssh {
            spec.transport = .init(kind: .ssh, hostLabel: "Mac", sshDestination: "erik@mac")
        }
        return spec
    }

    /// Every argv a shell would run, through every nested layer: the outer
    /// zsh, ssh's remote command, tmux's pane command, and `sh -lc` scripts.
    private static func allCommands(in script: String) -> [[String]] {
        let lexer = HolyShellLexer(script)
        return lexer.commands + lexer.nestedScripts.flatMap(allCommands(in:))
    }

    private static func isTmux(_ command: [String]) -> Bool {
        command.contains { ($0 as NSString).lastPathComponent == "tmux" }
    }

    /// (subcommand, target) for every `-t` in a tmux argv. The subcommand is
    /// the first word after tmux's global flags (`-L socket`, `-f file`).
    private static func targets(in commands: [[String]]) -> [(subcommand: String, target: String)] {
        commands.filter(isTmux).flatMap { command -> [(subcommand: String, target: String)] in
            guard let tmux = command.firstIndex(where: { ($0 as NSString).lastPathComponent == "tmux" }) else {
                return []
            }
            var index = command.index(after: tmux)
            while index < command.endIndex, ["-L", "-f", "-S"].contains(command[index]) {
                index += 2
            }
            guard index < command.endIndex else { return [] }
            let subcommand = command[index]
            return command.indices.dropLast()
                .filter { command[$0] == "-t" }
                .map { (subcommand, command[$0 + 1]) }
        }
    }

    private static func mirrorTargets(in commands: [[String]]) -> [String] {
        commands
            .filter { $0.first == "python3" && $0.dropFirst().first == "-c" && $0.contains("sync") }
            .compactMap(\.last)
            .filter { !$0.isEmpty } // the in-pane preamble targets $TMUX_PANE
    }

    @MainActor
    @Test(arguments: [(true, false), (false, false), (true, true), (false, true)])
    func everyEmittedSessionTargetIsExact(createIfMissing: Bool, ssh: Bool) throws {
        let spec = Self.spec(createIfMissing: createIfMissing, ssh: ssh)
        let script = try #require(HolyTmuxCommandBuilder.command(for: spec))
        let commands = Self.allCommands(in: script)
        let targets = Self.targets(in: commands)
        let context = "createIfMissing=\(createIfMissing) ssh=\(ssh)"

        #expect(!targets.isEmpty, "\(context): no tmux target was found; the walk proves nothing")
        #expect(!targets.contains { $0.target == Self.sessionName },
                "\(context): a bare -t \(Self.sessionName) remains: \(targets)")

        let namedTargets = targets.filter { $0.target.contains(Self.sessionName) }
        for (subcommand, target) in namedTargets {
            switch subcommand {
            case "has-session", "attach", "attach-session":
                #expect(target == Self.sessionTarget, "\(context): \(subcommand) -t \(target)")
            default:
                #expect(target == Self.paneTarget, "\(context): \(subcommand) -t \(target)")
            }
        }
        #expect(namedTargets.contains { $0 == ("has-session", Self.sessionTarget) }, "\(context)")
        #expect(namedTargets.contains { $0 == ("attach", Self.sessionTarget) }, "\(context)")
        #expect(namedTargets.contains { $0.subcommand == "set-option" }, "\(context): no ownership stamp")
        if createIfMissing {
            #expect(namedTargets.contains { $0 == ("set-option", Self.paneTarget) }, "\(context)")
        }

        // The host-state preamble hands its target to `list-panes -s -t`.
        let mirrors = Self.mirrorTargets(in: commands)
        #expect(mirrors.contains(Self.paneTarget), "\(context): mirror targets \(mirrors)")
        #expect(!mirrors.contains(Self.sessionName), "\(context): mirror targets \(mirrors)")
    }

    @Test func detachedCreateEmitsOnlyExactTargets() throws {
        let command = try #require(HolyTmuxCommandBuilder.detachedCreateCommand(
            for: Self.spec(createIfMissing: true, ssh: false)
        ))
        let script = try #require(command.arguments.last)
        let commands = Self.allCommands(in: script)
        let targets = Self.targets(in: commands)
        #expect(targets.contains { $0 == ("has-session", Self.sessionTarget) })
        #expect(!targets.contains { $0.target == Self.sessionName }, "\(targets)")
        #expect(!targets.contains { $0.subcommand == "attach" })
        for (_, target) in targets where target.contains(Self.sessionName) {
            #expect([Self.sessionTarget, Self.paneTarget].contains(target), "\(target)")
        }
        #expect(Self.mirrorTargets(in: commands) == [Self.paneTarget])
    }

    @Test func exactTargetFormsMatchTheModelLabelWriter() throws {
        #expect(HolyTmuxCommandBuilder.exactSessionTarget("lane") == "=lane")
        #expect(HolyTmuxCommandBuilder.exactSessionPaneTarget("lane") == "=lane:")
        let spec = Self.spec(createIfMissing: true, ssh: false)
        let label = try #require(HolyTmuxModelLabelUpdateCommand.command(for: spec, label: "opus"))
        let script = try #require(label.arguments.last)
        let targets = Self.targets(in: Self.allCommands(in: script))
        #expect(!targets.isEmpty)
        #expect(targets.allSatisfy { $0.target == Self.paneTarget }, "\(targets)")
    }

    /// Live receipt on a throwaway socket (never `holy`): with only `lane-2`
    /// alive, the bare form hits it and the built has-session misses; the
    /// built create script then makes `lane` itself and stamps only `lane`.
    @Test(.enabled(if: holyTmuxAvailableForExactTargetTests))
    func builtHasSessionMissesAPrefixSiblingOnALiveServer() throws {
        let socket = "mn-8905ec-" + UUID().uuidString.lowercased()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mn-8905ec-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "TMUX")
        environment.removeValue(forKey: "TMUX_PANE")
        environment.removeValue(forKey: "TMUX_TMPDIR")
        environment["HOLY_HOST_STATE_DATABASE"] = root.appendingPathComponent("host.sqlite3").path

        func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = environment
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
            } catch {
                return (-1, "\(error)")
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)
            return (process.terminationStatus, output)
        }
        func quoted(_ words: [String]) -> String {
            words.map { "'" + $0.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" }.joined(separator: " ")
        }
        func tmux(_ arguments: [String]) -> (status: Int32, output: String) {
            run("/bin/zsh", ["-lc", quoted(["tmux", "-L", socket] + arguments)])
        }

        // `cat` blocks on the pane's tty, so the sibling lives until kill-server.
        let sibling = tmux(["-f", "/dev/null", "new-session", "-d", "-s", "lane-2", "cat"])
        defer {
            _ = tmux(["kill-server"])
            try? FileManager.default.removeItem(at: root)
        }
        try #require(sibling.status == 0, "\(sibling.output)")

        var spec = Self.spec(socketName: socket, createIfMissing: true, ssh: false)
        spec.command = nil
        spec.runtime = .shell
        spec.workingDirectory = root.path
        let create = try #require(HolyTmuxCommandBuilder.detachedCreateCommand(for: spec))
        let script = try #require(create.arguments.last)
        // The lexer keeps shell keywords (`if`) in argv; run from tmux on.
        let hasSessionCommand = try #require(Self.allCommands(in: script).first {
            Self.isTmux($0) && $0.contains("has-session")
        })
        let hasSession = Array(hasSessionCommand.drop { $0 != "tmux" })
        #expect(hasSession == ["tmux", "-L", socket, "has-session", "-t", Self.sessionTarget])

        // Control: the fixture reproduces the hazard the fix removes.
        #expect(tmux(["has-session", "-t", Self.sessionName]).status == 0,
                "bare has-session must hit lane-2 by prefix, or this fixture proves nothing")
        let builtProbe = run("/bin/zsh", ["-lc", quoted(hasSession)])
        #expect(builtProbe.status != 0, "the built has-session matched lane-2: \(builtProbe.output)")

        let created = run(create.executablePath, create.arguments)
        #expect(created.status == 0, "\(created.output)")
        #expect(tmux(["has-session", "-t", Self.sessionTarget]).status == 0, "lane was never created")
        let sessions = tmux(["list-sessions", "-F", "#{session_name}"]).output
            .split(separator: "\n").map(String.init).sorted()
        #expect(sessions == ["lane", "lane-2"])

        func option(_ name: String, on session: String) -> String {
            tmux(["display-message", "-p", "-t", "=\(session):", "#{\(name)}"]).output
        }
        #expect(option("@holy_session_name", on: "lane") == Self.sessionName)
        #expect(option("@holy_session_name", on: "lane-2").isEmpty, "metadata leaked onto lane-2")
        #expect(option(HolyAgentStateTransport.tmuxOwnershipOption, on: "lane")
                == HolyAgentStateTransport.tmuxOwnershipValue)
        #expect(option(HolyAgentStateTransport.tmuxOwnershipOption, on: "lane-2").isEmpty,
                "ownership leaked onto lane-2")
    }
}
