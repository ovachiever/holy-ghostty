import Testing
@testable import Ghostty

@MainActor
struct HolySessionLiveStatusTests {
    // While OpenCode is generating it shows an interrupt hint ("esc interrupt")
    // in its footer. That phrasing lacks the "to" used by Claude/Codex, so it
    // must be recognized as a live working signal or active sessions show no
    // throbber at all.
    @Test func openCodeWorkingFooterIsLiveStatus() {
        let working = "esc interrupt   190.4K (19%)  ctrl+p commands   - OpenCode 1.17.7"
        #expect(HolySession.isLiveAgentStatusLineForTesting(working))
    }

    @Test func openCodeIdleFooterIsNotLiveStatus() {
        let idle = "97.9K (10%)  ctrl+p commands   - OpenCode 1.17.7"
        #expect(!HolySession.isLiveAgentStatusLineForTesting(idle))
    }

    // While a background workflow runs, Claude Code parks the REPL at the
    // prompt and shows only this wait line — the session is working even
    // though "waiting" normally signals idleness.
    @Test func dynamicWorkflowWaitLineIsLiveStatus() {
        let waiting = "✽ Waiting for 1 dynamic workflow to finish"
        #expect(HolySession.isLiveAgentStatusLineForTesting(waiting))
    }

    // The workflow ticker renders elapsed time and a token counter without
    // parentheses, so the parenthesized-time rule never sees it.
    @Test func workflowTickerFooterIsLiveStatus() {
        let ticker = "○ code-review  Workflow-backed code review — one finder per correctness angle… 2/5 agents done · 7m 12s · ↓ 598.5k tokens"
        #expect(HolySession.isLiveAgentStatusLineForTesting(ticker))
    }

    // A live elapsed-time + token counter only renders mid-turn.
    @Test func elapsedTokenCounterWithoutVerbIsLiveStatus() {
        let counter = "✻ Finagling… (1m 45s · ↓ 4.3k tokens)"
        #expect(HolySession.isLiveAgentStatusLineForTesting(counter))
    }

    // Fable's xhigh effort tier isn't covered by the high/medium/low phrases.
    @Test func xhighEffortThinkingFooterIsLiveStatus() {
        let thinking = "✻ Finagling… (1m 45s · ↓ 4.3k tokens · thinking with xhigh effort)"
        #expect(HolySession.isLiveAgentStatusLineForTesting(thinking))
    }

    // Claude Code's spinner cycles ·✢✳✶✻✽; frames outside the strip set left
    // the glyph attached and defeated the leading-verb match.
    @Test func allClaudeSpinnerFramesStripBeforeVerbMatch() {
        for frame in ["·", "✢", "✳", "✶", "✻", "✽"] {
            #expect(
                HolySession.isAgentBusyStatusLineForTesting("\(frame) Running tests…"),
                "frame \(frame) should read as busy"
            )
        }
    }

    // Claude Code invents gerunds ("Finagling…", "Moseying…") faster than any
    // fixed verb list can track; spinner glyph + gerund + ellipsis is busy.
    @Test func whimsicalGerundWithSpinnerGlyphIsBusy() {
        #expect(HolySession.isAgentBusyStatusLineForTesting("✶ Finagling…"))
        #expect(HolySession.isAgentBusyStatusLineForTesting("✽ Moseying… (3s)"))
    }

    @Test func promptAndChromeLinesAreNotBusy() {
        #expect(!HolySession.isAgentBusyStatusLineForTesting("› "))
        #expect(!HolySession.isAgentBusyStatusLineForTesting("Model · Fable 5 · xhigh"))
        #expect(!HolySession.isAgentBusyStatusLineForTesting("⏺ Updated 3 files"))
    }

    // "2/5 agents done" is the workflow fan-out ticker — swarm evidence, so the
    // roster shows the multi-agent spinner while a workflow runs.
    @Test func workflowAgentProgressCountIsSwarmLine() {
        let ticker = "○ code-review  Workflow-backed code review… 2/5 agents done · 7m 12s · ↓ 598.5k tokens"
        #expect(HolySession.isLiveAgentSwarmLineForTesting(ticker))
    }

    @Test func idleWorkflowPickerRowIsNotSwarmLine() {
        let pickerRow = "○ code-review  Workflow-backed code review — one finder per correctness angle"
        #expect(!HolySession.isLiveAgentSwarmLineForTesting(pickerRow))
    }
}
