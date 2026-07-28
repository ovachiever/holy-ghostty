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

    // Erik's field report 2026-07-28: the agent-sessions browser TUI — a
    // python program whose whole screen is DATA about Claude Code sessions —
    // reclassified its shell session as Claude through prose substrings
    // ("Claude Code", "claude --resume", ".claude" paths). A screen about
    // Claude is not a screen of Claude.
    @Test func sessionBrowserScreenAboutClaudeDoesNotInferClaude() {
        let preview = """
        Harness: Claude Code
        Type: PARENT SESSION
        Path: /Users/erik/Custom-Coding/agent-sessions
        claude --resume 923572c2-0b4d-439d-a793-c05875070443
        Transcripts live under /Users/erik/.claude/projects and CLAUDE.md rules apply.
        q Quit ? Chat y Copy All c Copy
        """

        #expect(Self.inferredRuntime(preview: preview) == nil)
    }

    @Test func claudeModeFooterChromeInfersClaude() {
        let preview = """
        ❯
        Model · Fable 5 · xhigh
        ⏵⏵ auto mode on (shift+tab to cycle) · ← for agents
        """

        #expect(Self.inferredRuntime(preview: preview) == .claude)
    }

    @Test func tmuxStatusBarWithActiveClaudeWindowInfersClaude() {
        let preview = #"[holy-shel0:claude.exe*   Fable 5 · xhigh 14:46 28-Jul-26"#

        #expect(Self.inferredRuntime(preview: preview) == .claude)
    }

    @Test func midLineOpenAICodexProseDoesNotInferCodex() {
        #expect(Self.inferredRuntime(preview: "Harness: OpenAI Codex session browser row") == nil)
    }

    // The live terminal title is screen state, not launch intent: editors
    // write filenames into it and agents write task text. Neither may
    // reclassify a shell session.
    @Test func liveTitleMentioningClaudeDoesNotInferClaude() {
        #expect(Self.inferredRuntime(surfaceTitle: "vim CLAUDE.md") == nil)
        #expect(Self.inferredRuntime(surfaceTitle: "✳ Condense CLAUDE rules and remove Moon hook") == nil)
    }

    private static func inferredRuntime(
        preview: String = "",
        command: String? = nil,
        surfaceTitle: String = ""
    ) -> HolySessionRuntime? {
        HolySession.inferredRuntimeForTesting(
            preview: preview,
            command: command,
            surfaceTitle: surfaceTitle
        )
    }
}
