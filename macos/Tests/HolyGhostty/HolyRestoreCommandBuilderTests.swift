import Foundation
import Testing
@testable import Ghostty

// The one non-negotiable of crash restore: Claude resumes with exact
// `--resume <id>`, Codex with exact `resume <id>`, OpenCode with exact
// `--session <id>` — as argument arrays. Never `--last`, never `--continue`,
// never a picker, never an id smuggled through shell interpolation.
struct HolyRestoreCommandBuilderTests {
    private let claudeID = "ae3d63af-e0b6-40b2-8dfa-cbc64d2e456c"

    // MARK: - Per-runtime argument arrays

    @Test func claudeResumesWithExactResumeFlag() {
        #expect(HolyRestoreCommandBuilder.resumeArguments(
            runtime: .claude,
            providerSessionID: claudeID
        ) == ["claude", "--resume", claudeID])
    }

    @Test func codexResumesWithExactResumeSubcommand() {
        #expect(HolyRestoreCommandBuilder.resumeArguments(
            runtime: .codex,
            providerSessionID: "0198c5c1-a2b3"
        ) == ["codex", "resume", "0198c5c1-a2b3"])
    }

    @Test func opencodeResumesWithExactSessionFlag() {
        #expect(HolyRestoreCommandBuilder.resumeArguments(
            runtime: .opencode,
            providerSessionID: "ses_4f2"
        ) == ["opencode", "--session", "ses_4f2"])
    }

    @Test func shellRuntimeHasNoResumeCommand() {
        #expect(HolyRestoreCommandBuilder.resumeArguments(
            runtime: .shell,
            providerSessionID: claudeID
        ) == nil)
    }

    @Test func forbiddenFlagsNeverAppear() {
        for runtime in HolySessionRuntime.allCases {
            let arguments = HolyRestoreCommandBuilder.resumeArguments(
                runtime: runtime,
                providerSessionID: claudeID
            ) ?? []
            #expect(!arguments.contains("--continue"))
            #expect(!arguments.contains("--last"))
            #expect(!arguments.contains("-c"))
        }
    }

    // MARK: - Provider id validation (defense in depth on top of quoting)

    @Test func providerIDsWithSafeCharactersAreAccepted() {
        for id in [claudeID, "0198c5c1", "ses_4f2-abc.DEF"] {
            #expect(HolyRestoreCommandBuilder.isSafeProviderSessionID(id))
        }
    }

    @Test func providerIDsWithShellMetacharactersAreRejected() {
        for id in [
            "",
            " ",
            "id; rm -rf ~",
            "id$(whoami)",
            "id'quote",
            "id\"quote",
            "id id",
            "id\nnewline",
            "id`tick`",
            String(repeating: "a", count: 300),
        ] {
            #expect(!HolyRestoreCommandBuilder.isSafeProviderSessionID(id))
        }
    }

    @Test func unsafeProviderIDProducesNoResumeArguments() {
        #expect(HolyRestoreCommandBuilder.resumeArguments(
            runtime: .claude,
            providerSessionID: "bad; rm -rf ~"
        ) == nil)
    }

    // MARK: - Absolute executable paths (login-shell PATH blindness)

    @Test func executablePathOverrideReplacesArgvZeroForEveryProviderRuntime() {
        #expect(HolyRestoreCommandBuilder.resumeArguments(
            runtime: .codex,
            providerSessionID: "0198c5c1-a2b3",
            executablePath: "/Users/u/.nvm/versions/node/v22.16.0/bin/codex"
        ) == ["/Users/u/.nvm/versions/node/v22.16.0/bin/codex", "resume", "0198c5c1-a2b3"])
        #expect(HolyRestoreCommandBuilder.resumeArguments(
            runtime: .opencode,
            providerSessionID: "ses_4f2",
            executablePath: "/Users/u/.opencode/bin/opencode"
        ) == ["/Users/u/.opencode/bin/opencode", "--session", "ses_4f2"])
        #expect(HolyRestoreCommandBuilder.resumeArguments(
            runtime: .claude,
            providerSessionID: claudeID,
            executablePath: "/opt/homebrew/bin/claude"
        ) == ["/opt/homebrew/bin/claude", "--resume", claudeID])
    }

    @Test func renderedCommandQuotesAnExecutablePathWithSpacesAsOneToken() throws {
        let rendered = try #require(HolyRestoreCommandBuilder.renderedResumeCommand(
            runtime: .claude,
            providerSessionID: claudeID,
            executablePath: "/Users/u/My Tools/claude"
        ))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", "printf '%s\\n' \(rendered)"]
        let stdout = Pipe()
        process.standardOutput = stdout
        try process.run()
        process.waitUntilExit()
        let output = String(
            bytes: stdout.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        #expect(output == "/Users/u/My Tools/claude\n--resume\n\(claudeID)\n")
    }

    @Test func unsafeProviderIDStillRefusesWithAnExecutablePath() {
        #expect(HolyRestoreCommandBuilder.resumeArguments(
            runtime: .codex,
            providerSessionID: "bad; rm -rf ~",
            executablePath: "/opt/homebrew/bin/codex"
        ) == nil)
    }

    // MARK: - Shell rendering for tmux bootstrap

    @Test func shellCommandQuotesEveryArgumentAsOneToken() {
        let rendered = HolyRestoreCommandBuilder.shellCommand(
            fromArguments: ["claude", "--resume", claudeID]
        )
        #expect(rendered == "'claude' '--resume' '\(claudeID)'")
    }

    @Test func renderedResumeCommandSurvivesShellParsingAsExactTokens() throws {
        let rendered = try #require(HolyRestoreCommandBuilder.renderedResumeCommand(
            runtime: .claude,
            providerSessionID: claudeID
        ))

        // Ground truth: hand the rendered string to a real shell and read the
        // argv it would deliver. The id must arrive as one untouched token.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", "printf '%s\\n' \(rendered)"]
        let stdout = Pipe()
        process.standardOutput = stdout
        try process.run()
        process.waitUntilExit()
        let output = String(
            bytes: stdout.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        #expect(output == "claude\n--resume\n\(claudeID)\n")
    }
}
