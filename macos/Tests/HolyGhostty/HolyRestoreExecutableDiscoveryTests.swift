import Foundation
import Testing
@testable import Ghostty

// The design law under test: the preflight check and the restored command must
// share one truth about what is invocable. A row may only pass when the binary
// was actually found, and whatever argv the pass produces must run under the
// PATH the pane really gets — the tmux server's, not the app's.
//
// The field failure this pins: `codex` installed under nvm v22.16.0 while
// v24.19.0 was the newest installed node. Probing only the newest version left
// codex invisible, so every Codex row blocked while Claude (homebrew, on the
// server's PATH) restored fine.
struct HolyRestoreExecutableDiscoveryTests {
    // MARK: - Layer ordering and argv pinning

    @Test func serverPathHitWinsAndKeepsTheBareName() {
        let discovery = HolyRestoreExecutableDiscovery.tmuxServerPath("/opt/homebrew/bin/claude")
        #expect(discovery.isFound)
        #expect(discovery.absolutePath == "/opt/homebrew/bin/claude")
        // The server PATH *is* the runtime PATH, so nothing needs pinning.
        #expect(discovery.pinnedArgvPath == nil)

        let rendered = HolyRestoreCommandBuilder.resumeArguments(
            runtime: .claude,
            providerSessionID: "ae3d63af-1111",
            executablePath: discovery.pinnedArgvPath
        )
        #expect(rendered == ["claude", "--resume", "ae3d63af-1111"])
    }

    @Test func fallbackHitPinsTheAbsolutePathIntoTheBuiltCommand() {
        let codexPath = "/Users/u/.nvm/versions/node/v22.16.0/bin/codex"
        let discovery = HolyRestoreExecutableDiscovery.wellKnownDirectory(codexPath)
        #expect(discovery.isFound)
        #expect(discovery.pinnedArgvPath == codexPath)

        let rendered = HolyRestoreCommandBuilder.resumeArguments(
            runtime: .codex,
            providerSessionID: "0198c5c1-a2b3",
            executablePath: discovery.pinnedArgvPath
        )
        #expect(rendered == [codexPath, "resume", "0198c5c1-a2b3"])
    }

    @Test func loginShellHitIsAlsoPinnedBecauseTheAppPathIsNotThePanePath() {
        let discovery = HolyRestoreExecutableDiscovery.loginShell("/usr/local/bin/opencode")
        #expect(discovery.pinnedArgvPath == "/usr/local/bin/opencode")
        #expect(HolyRestoreCommandBuilder.resumeArguments(
            runtime: .opencode,
            providerSessionID: "ses_4f2",
            executablePath: discovery.pinnedArgvPath
        ) == ["/usr/local/bin/opencode", "--session", "ses_4f2"])
    }

    @Test func totalMissCarriesNoPathAndNothingToPin() {
        let discovery = HolyRestoreExecutableDiscovery.missing
        #expect(!discovery.isFound)
        #expect(discovery.absolutePath == nil)
        #expect(discovery.pinnedArgvPath == nil)
    }

    // MARK: - Resolving a name against an explicit PATH

    @Test func serverPathResolutionTakesTheFirstDirectoryThatHoldsTheBinary() {
        let present: Set<String> = ["/usr/local/bin/codex", "/opt/homebrew/bin/codex"]
        let resolved = HolyRestoreExecutableSearch.resolve(
            name: "codex",
            inSearchPath: "/nope:/opt/homebrew/bin:/usr/local/bin",
            isExecutable: { present.contains($0) }
        )
        #expect(resolved == "/opt/homebrew/bin/codex")
    }

    @Test func serverPathResolutionMissesWhenNoDirectoryHoldsTheBinary() {
        // Erik's real server PATH: homebrew and friends, no nvm anywhere. This
        // is exactly why codex has to fall through to the next layer.
        let serverPath = "/Users/erik/go/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        #expect(HolyRestoreExecutableSearch.resolve(
            name: "codex",
            inSearchPath: serverPath,
            isExecutable: { _ in false }
        ) == nil)
    }

    @Test func relativePathEntriesAreNeverHonored() {
        // An empty or relative PATH entry means "current directory" to a
        // shell. A relative hit is never worth baking into a restored command.
        #expect(HolyRestoreExecutableSearch.resolve(
            name: "codex",
            inSearchPath: "::.:relative/bin",
            isExecutable: { _ in true }
        ) == nil)
    }

    @Test func trailingSlashesDoNotProduceDoubledSeparators() {
        #expect(HolyRestoreExecutableSearch.resolve(
            name: "codex",
            inSearchPath: "/opt/homebrew/bin/",
            isExecutable: { $0 == "/opt/homebrew/bin/codex" }
        ) == "/opt/homebrew/bin/codex")
    }

    @Test func hostileNamesNeverReachTheSearch() {
        for name in ["", "co dex", "codex;rm -rf ~", "../codex", "CODEX", String(repeating: "c", count: 33)] {
            #expect(!HolyRestoreExecutableSearch.isSafeExecutableName(name))
            #expect(HolyRestoreExecutableSearch.resolve(
                name: name,
                inSearchPath: "/opt/homebrew/bin",
                isExecutable: { _ in true }
            ) == nil)
        }
        #expect(HolyRestoreExecutableSearch.isSafeExecutableName("codex"))
        #expect(HolyRestoreExecutableSearch.isSafeExecutableName("agent-sessions"))
    }

    // MARK: - nvm: every version, newest first

    @Test func nvmVersionsAreOrderedNewestFirstBySemverNotByString() {
        // Plain string sorting would put v9 above v22 and v22.9 above v22.16.
        let ordered = HolyRestoreExecutableSearch.nvmVersionDirectoriesNewestFirst(
            ["v22.14.0", "v9.11.2", "v24.19.0", "v22.16.0", "v22.9.0"]
        )
        #expect(ordered == ["v24.19.0", "v22.16.0", "v22.14.0", "v22.9.0", "v9.11.2"])
    }

    @Test func nvmEntriesWithoutAVersionAreIgnored() {
        let ordered = HolyRestoreExecutableSearch.nvmVersionDirectoriesNewestFirst(
            ["v22.16.0", ".DS_Store", "versions", "vNext", "v"]
        )
        #expect(ordered == ["v22.16.0"])
    }

    /// Production picks `candidates.first(where: isExecutable)`; these tests
    /// model exactly that against a scripted filesystem.
    private func firstHit(
        name: String,
        nvmVersions: [String],
        installed: Set<String>
    ) -> String? {
        HolyRestoreExecutableSearch.wellKnownCandidates(
            name: name,
            home: "/Users/erik",
            nvmVersionDirectoryNames: nvmVersions
        )
        .first { installed.contains($0) }
    }

    @Test func aBinaryUnderAnOlderNodeIsFoundEvenWhenANewerNodeExists() {
        // The exact field failure: codex lives under v22.16.0, while v24.19.0
        // is newer and holds only node/npm/npx. Probing the newest version
        // alone found nothing and blocked every Codex row.
        #expect(firstHit(
            name: "codex",
            nvmVersions: ["v22.14.0", "v24.19.0", "v22.16.0"],
            installed: ["/Users/erik/.nvm/versions/node/v22.16.0/bin/codex"]
        ) == "/Users/erik/.nvm/versions/node/v22.16.0/bin/codex")
    }

    @Test func newestInstalledNvmVersionWinsWhenSeveralCarryTheBinary() {
        #expect(firstHit(
            name: "codex",
            nvmVersions: ["v22.14.0", "v24.19.0", "v22.16.0"],
            installed: [
                "/Users/erik/.nvm/versions/node/v22.14.0/bin/codex",
                "/Users/erik/.nvm/versions/node/v22.16.0/bin/codex",
                "/Users/erik/.nvm/versions/node/v24.19.0/bin/codex",
            ]
        ) == "/Users/erik/.nvm/versions/node/v24.19.0/bin/codex")
    }

    @Test func nothingInstalledAnywhereYieldsNoCandidateHit() {
        #expect(firstHit(
            name: "codex",
            nvmVersions: ["v24.19.0"],
            installed: []
        ) == nil)
    }

    @Test func versionManagerDirectoriesAreSearchedBeforeSystemDirectories() {
        let candidates = HolyRestoreExecutableSearch.wellKnownCandidates(
            name: "codex",
            home: "/Users/erik",
            nvmVersionDirectoryNames: ["v22.16.0"]
        )
        func rank(_ suffix: String) -> Int {
            candidates.firstIndex { $0.hasSuffix(suffix) } ?? Int.max
        }
        // By this layer the name is already absent from the server's PATH, so
        // the .zshrc-only managers are the likelier home.
        #expect(rank(".nvm/versions/node/v22.16.0/bin/codex") < rank(".volta/bin/codex"))
        #expect(rank(".volta/bin/codex") < rank("/opt/homebrew/bin/codex"))
        #expect(rank(".bun/bin/codex") < rank("/usr/local/bin/codex"))
        // Every historical location survives the reordering.
        for suffix in [
            ".pyenv/shims/codex", ".local/bin/codex", "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex", ".opencode/bin/codex", ".bun/bin/codex", ".volta/bin/codex",
        ] {
            #expect(rank(suffix) != Int.max, "lost candidate directory: \(suffix)")
        }
    }

    @Test func noNvmInstallStillProducesTheSystemCandidates() {
        let candidates = HolyRestoreExecutableSearch.wellKnownCandidates(
            name: "claude",
            home: "/Users/erik",
            nvmVersionDirectoryNames: []
        )
        #expect(candidates.contains("/opt/homebrew/bin/claude"))
        #expect(!candidates.contains { $0.contains(".nvm") })
    }

    // MARK: - Parsing the tmux server's environment

    @Test func showEnvironmentAssignmentYieldsThePath() {
        let output = "PATH=/opt/homebrew/bin:/usr/bin:/bin\n"
        #expect(HolyTmuxServerEnvironment.parseGlobalValue(
            fromShowEnvironmentOutput: output,
            variable: "PATH"
        ) == "/opt/homebrew/bin:/usr/bin:/bin")
    }

    @Test func explicitlyUnsetOrEmptyPathIsNoValue() {
        // tmux answers `-PATH` when the variable is explicitly unset.
        for output in ["-PATH\n", "PATH=\n", "", "no server running on /tmp/tmux-501/holy\n"] {
            #expect(HolyTmuxServerEnvironment.parseGlobalValue(
                fromShowEnvironmentOutput: output,
                variable: "PATH"
            ) == nil)
        }
    }

    @Test func onlyTheRequestedVariableIsRead() {
        let output = "PATHOLOGICAL=/nope\nHOME=/Users/erik\nPATH=/real/bin\n"
        #expect(HolyTmuxServerEnvironment.parseGlobalValue(
            fromShowEnvironmentOutput: output,
            variable: "PATH"
        ) == "/real/bin")
    }

    @Test func aPathContainingEqualsSignsSurvivesIntact() {
        let output = "PATH=/opt/bin:/weird=dir/bin\n"
        #expect(HolyTmuxServerEnvironment.parseGlobalValue(
            fromShowEnvironmentOutput: output,
            variable: "PATH"
        ) == "/opt/bin:/weird=dir/bin")
    }

    // MARK: - The query aimed at one exact server

    @Test func showEnvironmentCommandTargetsTheNamedSocketAndScrubsClientState() throws {
        let command = HolyTmuxServerEnvironment.showEnvironmentCommand(
            socketName: "holy",
            variable: "PATH"
        )
        #expect(command.executablePath == "/bin/zsh")
        let script = try #require(command.arguments.last)
        #expect(command.arguments.first == "-lc")
        #expect(script.contains("'-L' 'holy'"))
        #expect(script.contains("'show-environment' '-g' 'PATH'"))
        // Without this the query could be redirected at whatever server owns
        // the app's own pane.
        #expect(script.hasPrefix("unset TMUX TMUX_PANE TMUX_TMPDIR;"))
    }

    @Test func aNilSocketQueriesTheDefaultServerWithoutAnEmptyLabel() throws {
        for socketName in [nil, "", "   "] as [String?] {
            let command = HolyTmuxServerEnvironment.showEnvironmentCommand(
                socketName: socketName,
                variable: "PATH"
            )
            let script = try #require(command.arguments.last)
            #expect(!script.contains("-L"))
            #expect(script.contains("'tmux' 'show-environment'"))
        }
    }

    @Test func theRenderedQuerySurvivesShellParsingAsExactTokens() throws {
        let command = HolyTmuxServerEnvironment.showEnvironmentCommand(
            socketName: "holy socket'; touch /tmp/pwned; #",
            variable: "PATH"
        )
        let script = try #require(command.arguments.last)
        // Ground truth: hand the argv-building half to a real shell and read
        // the tokens it would deliver. The socket name must arrive as one.
        let printable = script.replacingOccurrences(
            of: "unset TMUX TMUX_PANE TMUX_TMPDIR; 'tmux'",
            with: "printf '%s\\n'"
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", printable]
        let stdout = Pipe()
        process.standardOutput = stdout
        try process.run()
        process.waitUntilExit()
        let output = String(
            bytes: stdout.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        #expect(output == "-L\nholy socket'; touch /tmp/pwned; #\nshow-environment\n-g\nPATH\n")
        #expect(!FileManager.default.fileExists(atPath: "/tmp/pwned"))
    }
}
