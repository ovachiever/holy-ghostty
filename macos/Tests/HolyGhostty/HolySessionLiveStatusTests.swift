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

    // Claude Code freezes the last spinner frame into the terminal title when
    // a turn ends ("✳ Fix missing activity"), so a glyph-prefixed title alone
    // is not evidence of live work — only a working verb in the title is.
    @Test func frozenSpinnerTitleIsNotBusy() {
        #expect(!HolySession.isBusyAgentTitleForTesting("✳ Fix missing activity spinner"))
        #expect(HolySession.isBusyAgentTitleForTesting("✳ Running the build"))
    }

    // Transcript prose QUOTING footer phrases must not read as live activity —
    // an agent explaining this detector poisons its own session otherwise.
    @Test func proseQuotingAgentCountsIsNotSwarmLine() {
        let prose = #"a background workflow ("Waiting for N dynamic workflow to finish" / "2/5 agents done") should show the gold multi-agent spinner"#
        #expect(!HolySession.isLiveAgentSwarmLineForTesting(prose))
    }

    @Test func proseQuotingTokenCounterIsNotLiveStatus() {
        let prose = "the ticker 2/5 agents done · 7m 12s · ↓ 598.5k tokens still renders"
        #expect(!HolySession.isLiveAgentStatusLineForTesting(prose))
    }

    // Claude Code's REPL prompt is "❯" (U+276F); draft text typed there must
    // classify as a prompt line so it stays out of the marker scans.
    @Test func heavyPromptGlyphIsPromptLine() {
        #expect(HolySession.isAgentPromptLineForTesting("❯"))
        #expect(HolySession.isAgentPromptLineForTesting("❯ the session shows the swarm spinner now, fix confirmed"))
        #expect(!HolySession.isAgentPromptLineForTesting("✻ Churned for 3m 16s"))
    }

    // The post-turn residue line is past tense — never busy.
    @Test func churnedResidueLineIsNotBusy() {
        #expect(!HolySession.isAgentBusyStatusLineForTesting("✻ Churned for 3m 16s"))
    }

    // The waiting signal must not echo the user's draft: its text flows into
    // telemetry detail, where words like "confirmed" read as an approval
    // request and raise the hand.
    @Test func waitingEvidenceDoesNotEchoPromptDraft() {
        let evidence = HolySession.agentWaitingEvidenceForTesting(lines: [
            "✻ Cooked for 14m 19s",
            "❯ blue dot confirmed, all states look right now",
            "Model · Fable 5 · xhigh",
        ])
        #expect(evidence != nil)
        #expect(evidence?.lowercased().contains("confirm") == false)
    }

    // Draft questions ("how should I…?") must not read as the agent asking
    // planning questions.
    @Test func promptDraftIsNotPlanningQuestionEvidence() {
        let evidence = HolySession.agentPlanningQuestionEvidenceForTesting(lines: [
            "✻ Churned for 3m 16s",
            "❯ how should we structure the roster refactor?",
            "Model · Fable 5 · xhigh",
        ])
        #expect(evidence == nil)
    }
}
