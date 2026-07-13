import Foundation
import Testing
@testable import Ghostty

private let holyTmuxAvailableForModelStatusTests: Bool = {
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

struct HolyTmuxModelStatusTests {
    @Test func managedGreenBarConditionallyIncludesLiveModelLabel() {
        let status = HolyTmuxCommandBuilder.managedTmuxStatusRightForTesting

        #expect(status.contains("#{?@holy_model_label"))
        #expect(status.contains("#{@holy_model_label} · "))
        #expect(status.contains("#{@holy_model_source},claude"))
        #expect(status.contains("#{@holy_claude_model_enabled},off"))
        #expect(status.contains("#{=21:pane_title}"))
        #expect(!status.contains("Model unknown"))
    }

    @Test func updateTargetsStoredExactSessionWithoutRealizingIdentity() throws {
        var launchSpec = HolySessionLaunchSpec.interactiveTmuxShell()
        launchSpec.tmux = .init(
            socketName: "holy",
            sessionName: "demo-model-session",
            createIfMissing: false
        )

        let command = try #require(
            HolyTmuxModelLabelUpdateCommand.command(
                for: launchSpec,
                label: "gpt-5.6-sol · ultra"
            )
        )
        let script = try #require(command.arguments.last)

        #expect(command.executableURL.path == "/bin/zsh")
        #expect(script.contains("unset TMUX TMUX_PANE TMUX_TMPDIR"))
        #expect(script.contains("'tmux' '-L' 'holy'"))
        #expect(script.contains("'-t' '=demo-model-session:'"))
        #expect(script.contains("'@holy_model_label' 'gpt-5.6-sol · ultra'"))
        #expect(script.contains("'@holy_model_source' 'app'"))
        #expect(script.contains("'status-right'"))

        var missingName = launchSpec
        missingName.tmux?.sessionName = nil
        #expect(
            HolyTmuxModelLabelUpdateCommand.command(
                for: missingName,
                label: "must-not-invent"
            ) == nil
        )

        var missingSocket = launchSpec
        missingSocket.tmux?.socketName = nil
        #expect(
            HolyTmuxModelLabelUpdateCommand.command(
                for: missingSocket,
                label: "must-not-use-default-server"
            ) == nil
        )
    }

    @Test func remoteUpdateIsBoundedAndPassedAsOneQuotedCommand() throws {
        var launchSpec = HolySessionLaunchSpec.interactiveTmuxShell()
        launchSpec.transport = .init(
            kind: .ssh,
            hostLabel: "Studio",
            sshDestination: "erik@studio"
        )
        launchSpec.tmux = .init(
            socketName: "holy",
            sessionName: "remote-model-session",
            createIfMissing: false
        )

        let command = try #require(
            HolyTmuxModelLabelUpdateCommand.command(
                for: launchSpec,
                label: "Opus 4.8 · max"
            )
        )
        let remoteScript = try #require(command.arguments.last)

        #expect(command.executableURL.path == "/usr/bin/ssh")
        #expect(command.arguments.contains("BatchMode=yes"))
        #expect(command.arguments.contains("ConnectTimeout=5"))
        #expect(command.arguments.contains("ServerAliveInterval=5"))
        #expect(command.arguments.contains("ServerAliveCountMax=1"))
        #expect(command.arguments.contains("erik@studio"))
        #expect(remoteScript.hasPrefix("zsh -lc '"))
        #expect(remoteScript.contains("@holy_model_label"))
        #expect(remoteScript.contains("=remote-model-session:"))
    }

    @Test func terminalControlCharactersCannotEnterTmuxFormatValue() throws {
        var launchSpec = HolySessionLaunchSpec.interactiveTmuxShell()
        launchSpec.tmux = .init(socketName: "holy", sessionName: "demo", createIfMissing: false)
        let command = try #require(
            HolyTmuxModelLabelUpdateCommand.command(
                for: launchSpec,
                label: "gpt-5#bad\nmodel"
            )
        )
        let script = try #require(command.arguments.last)

        #expect(!script.contains("gpt-5#bad"))
        #expect(!script.contains("\nmodel"))
        #expect(script.contains("gpt-5badmodel"))
    }

    @Test(.enabled(if: holyTmuxAvailableForModelStatusTests))
    func liveTmuxOptionChangesToNewModel() throws {
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let socketName = "holy-model-\(suffix)"
        let sessionName = "model-\(suffix)"
        #expect(runLoginShell("tmux -L \(socketName) new-session -d -s \(sessionName)") == 0)
        defer {
            _ = runLoginShell("tmux -L \(socketName) kill-server >/dev/null 2>&1 || true")
        }

        var launchSpec = HolySessionLaunchSpec.interactiveTmuxShell()
        launchSpec.tmux = .init(
            socketName: socketName,
            sessionName: sessionName,
            createIfMissing: false
        )
        #expect(
            runLoginShell(
                "tmux -L \(socketName) set-option -gq status-right \(shellQuote(HolyTmuxCommandBuilder.managedTmuxStatusRightForTesting))"
            ) == 0
        )
        let first = try #require(
            HolyTmuxModelLabelUpdateCommand.command(
                for: launchSpec,
                label: "Opus 4.8 · max"
            )
        )
        #expect(first.run())
        #expect(
            runLoginShellOutput(
                "tmux -L \(socketName) show-options -pqv -t '\(sessionName)' @holy_model_label"
            ) == "Opus 4.8 · max"
        )
        #expect(
            runLoginShellOutput(
                "tmux -L \(socketName) show-options -pqv -t '\(sessionName)' @holy_model_source"
            ) == "app"
        )
        #expect(
            runLoginShellOutput(
                "tmux -L \(socketName) display-message -p -t '\(sessionName)' '#{E:status-right}'"
            )?.hasPrefix("Opus 4.8 · max · ") == true
        )

        let second = try #require(
            HolyTmuxModelLabelUpdateCommand.command(
                for: launchSpec,
                label: "Fable 5 · high"
            )
        )
        #expect(second.run())
        #expect(
            runLoginShellOutput(
                "tmux -L \(socketName) show-options -pqv -t '\(sessionName)' @holy_model_label"
            ) == "Fable 5 · high"
        )

        let clear = try #require(
            HolyTmuxModelLabelUpdateCommand.command(for: launchSpec, label: nil)
        )
        #expect(clear.run())
        #expect(
            runLoginShellOutput(
                "tmux -L \(socketName) display-message -p -t '\(sessionName)' '#{@holy_model_label}'"
            ) == ""
        )
        #expect(
            runLoginShellOutput(
                "tmux -L \(socketName) display-message -p -t '\(sessionName)' '#{@holy_model_source}'"
            ) == ""
        )
    }

    @Test(.enabled(if: holyTmuxAvailableForModelStatusTests))
    func missingExactSessionNeverMutatesPrefixMatch() throws {
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let socketName = "holy-exact-model-\(suffix)"
        let requestedName = "model-\(suffix)"
        let onlyLiveName = "\(requestedName)-longer"
        #expect(runLoginShell("tmux -L \(socketName) new-session -d -s \(onlyLiveName)") == 0)
        defer {
            _ = runLoginShell("tmux -L \(socketName) kill-server >/dev/null 2>&1 || true")
        }

        var launchSpec = HolySessionLaunchSpec.interactiveTmuxShell()
        launchSpec.tmux = .init(
            socketName: socketName,
            sessionName: requestedName,
            createIfMissing: false
        )
        let command = try #require(
            HolyTmuxModelLabelUpdateCommand.command(for: launchSpec, label: "must-not-land")
        )

        #expect(!command.run())
        #expect(
            runLoginShellOutput(
                "tmux -L \(socketName) display-message -p -t '\(onlyLiveName)' '#{@holy_model_label}'"
            ) == ""
        )
    }

    private func runLoginShell(_ script: String) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", script]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }

    private func runLoginShellOutput(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", script]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(
                data: output.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}
