import Testing
@testable import Ghostty

@MainActor
struct HolySessionRuntimeInferenceTests {
    @Test func openCodeLandingScreenWinsOverClaudeModelLabel() {
        let preview = """
        opencode
        Ask anything... "What is the tech stack of this project?"
        Build - Claude Opus 4.6 Anthropic - max
        """

        #expect(Self.inferredRuntime(preview: preview) == .opencode)
    }

    @Test func claudeModelLabelAloneDoesNotInferClaudeRuntime() {
        let preview = """
        Ask anything... "What is the tech stack of this project?"
        Build - Claude Opus 4.6 Anthropic - max
        tab agents   ctrl+p commands
        """

        #expect(Self.inferredRuntime(preview: preview) == nil)
    }

    @Test func launchCommandStillInfersClaudeRuntime() {
        #expect(Self.inferredRuntime(command: "claude") == .claude)
    }

    @Test func codexStatusFooterStillInfersCodexRuntime() {
        #expect(Self.inferredRuntime(preview: "gpt-5.1 high") == .codex)
    }

    private static func inferredRuntime(
        preview: String = "",
        command: String? = nil
    ) -> HolySessionRuntime? {
        HolySession.inferredRuntimeForTesting(
            preview: preview,
            command: command
        )
    }
}
