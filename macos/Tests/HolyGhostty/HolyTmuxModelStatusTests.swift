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
    @Test func managedGreenBarShowsTitleLeftAndGlobalUsageByTheClock() {
        let left = HolyTmuxCommandBuilder.managedTmuxStatusLeftForTesting
        let right = HolyTmuxCommandBuilder.managedTmuxStatusRightForTesting

        // Left: session name (sliced), then the quoted pane title.
        #expect(left.contains("session_name}"))
        #expect(left.contains("#{=21:pane_title}"))
        #expect(left.range(of: "session_name")!.lowerBound < left.range(of: "pane_title")!.lowerBound)

        // Right: the machine-global usage segment beside the clock — and no
        // model or effort, which live only in the pane's printed status row.
        #expect(right.contains("#{?@holy_usage_v1,#{E:@holy_usage_v1} · ,}"))
        #expect(right.contains("%H:%M"))
        #expect(!right.contains("@holy_model_label"))
        #expect(!right.contains("pane_title"))
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
        let wrapper = try #require(command.arguments.last)

        #expect(command.executableURL.path == "/bin/zsh")
        #expect(wrapper.contains("'BatchMode=yes'"))
        #expect(wrapper.contains("'ConnectTimeout=5'"))
        #expect(wrapper.contains("'ServerAliveInterval=5'"))
        #expect(wrapper.contains("'ServerAliveCountMax=1'"))
        #expect(wrapper.contains("'--' 'erik@studio'"))
        #expect(wrapper.contains("'zsh -lc "))
        #expect(wrapper.contains("@holy_model_label"))
        #expect(wrapper.contains("=remote-model-session:"))
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
        // The label lives as a pane option only: the bar renders usage and
        // the clock, never the model.
        #expect(
            runLoginShellOutput(
                "tmux -L \(socketName) display-message -p -t '\(sessionName)' '#{E:status-right}'"
            )?.contains("Opus 4.8") == false
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
