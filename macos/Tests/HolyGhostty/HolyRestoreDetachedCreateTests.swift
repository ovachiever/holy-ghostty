import Foundation
import Testing
@testable import Ghostty

// Crash restore creates tmux sessions headless: same create-if-missing
// script the surface path uses (metadata stamps, ownership stamp, cwd,
// bootstrap) but no attach and no surface. Attach happens later, lazily,
// through readoption.
struct HolyRestoreDetachedCreateTests {
    private func restoredSpec(
        sessionName: String? = "holy-restore-demo-1234",
        command: String? = "'claude' '--resume' 'ae3d63af'"
    ) -> HolySessionLaunchSpec {
        var spec = HolySessionLaunchSpec.interactiveTmuxShell(title: "Restored")
        spec.runtime = .claude
        spec.command = command
        spec.workingDirectory = "/tmp/restore-demo"
        spec.tmux = .init(
            socketName: "holy",
            sessionName: sessionName,
            createIfMissing: true
        )
        return spec
    }

    @Test func detachedCreateBuildsCreateOnlyScriptWithMetadataAndOwnership() throws {
        let command = try #require(
            HolyTmuxCommandBuilder.detachedCreateCommand(for: restoredSpec())
        )

        #expect(command.executablePath == "/bin/zsh")
        #expect(command.arguments.first == "-lc")
        let script = try #require(command.arguments.last)
        #expect(script.contains("new-session' '-d'"))
        #expect(script.contains("has-session"))
        #expect(script.contains("holy-restore-demo-1234"))
        #expect(script.contains("/tmp/restore-demo"))
        #expect(script.contains("@holy_runtime' 'claude'"))
        #expect(script.contains("@holy_agent_state_owner_v1"))
        #expect(script.contains("--resume"))
        // "destroy-unattached" is expected server config; the attach COMMAND
        // ('attach' '-t') must be absent.
        #expect(!script.contains("'attach'"))
    }

    @Test func detachedCreateRequiresAnExactPersistedIdentity() {
        #expect(HolyTmuxCommandBuilder.detachedCreateCommand(
            for: restoredSpec(sessionName: nil)
        ) == nil)
    }

    @Test func detachedCreateIsLocalOnly() {
        var spec = restoredSpec()
        spec.transport = .init(kind: .ssh, hostLabel: "Mac", sshDestination: "erik@mac")
        #expect(HolyTmuxCommandBuilder.detachedCreateCommand(for: spec) == nil)
    }

    @Test func surfaceLaunchScriptStillEndsInAttach() throws {
        let script = try #require(HolyTmuxCommandBuilder.command(for: restoredSpec()))
        #expect(script.contains("attach"))
    }
}
