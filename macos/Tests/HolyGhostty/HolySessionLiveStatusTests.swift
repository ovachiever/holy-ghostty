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

    // Claude Code renders the live spinner ABOVE the todo checklist; a tall
    // checklist must not push the only proof-of-work line out of scan range.
    @Test func workingEvidenceSurvivesTodoChecklistBelowSpinner() {
        let lines = [
            "✻ Attacking speed_dist earned attribution… (4m 26s · ↓ 12.2k tokens · thinking with xhigh effort)",
            "■ Attack speed_dist earned attribution (τ·ṙ closure + se-rate-artifact)",
            "□ Attack hash-bound attestation (flip bin + migration 0005)",
            "□ Verify census stratum fix (jerk_x plant) and regressions caption",
            "□ Live gates: full test suite + census/attribution recount",
            "□ Render verdict + append ledger section",
            "… +1 completed",
            "❯",
            "Model · Fable 5 · xhigh",
            "⏵⏵ auto mode on · 1 shell · ← for agents",
        ]
        #expect(HolySession.agentWorkingEvidenceForTesting(lines: lines) != nil)
    }

    // The detection window must be deeper than the 8-line display preview —
    // otherwise every suffix() in the matchers scans a truncated pane and the
    // spinner above a checklist is simply never seen.
    @Test func detectionTextRetainsSpinnerAboveTallChecklist() {
        let checklist = (1...9).map { "□ Todo item number \($0)" }
        let pane = (
            ["older transcript prose"]
            + ["✻ Frolicking… (2m 3s · ↓ 8.1k tokens)"]
            + checklist
            + ["❯", "Model · Fable 5 · xhigh", "⏵⏵ auto mode on · ← for agents"]
        ).joined(separator: "\n")
        #expect(HolySession.detectionTextForTesting(from: pane).contains("Frolicking"))
    }

    // The telemetry parser picks its evidence line independently of the
    // signal pipeline; a prompt draft ending the pane must not become
    // evidence, or extractNextStepHint turns "…confirm…" into "Review the
    // prompt and confirm approval" and the hand rises through telemetry.
    @Test func telemetryEvidenceSkipsPromptDraft() {
        let preview = """
        ✻ Churned for 3m 16s
        ❯ please confirm the approval flow works
        """
        let evidence = HolySessionRuntimeTelemetryParser.evidenceLineForTesting(from: preview)
        #expect(evidence == "✻ Churned for 3m 16s")
    }

    // "N shells still running" is NOT working evidence: background shells
    // outlive turns, so the IDLE residue line carries the same suffix
    // ("✻ Churned for 7m 12s · 1 shell still running") indefinitely — a rule
    // matching it makes any session with a persistent shell throb forever
    // and never earn a recent-reply dot. The mid-turn variant is identical
    // per-sample; only a temporal check can split them (oracle redesign).
    @Test func shellStillRunningResidueIsNotLiveStatus() {
        #expect(!HolySession.isLiveAgentStatusLineForTesting("✻ Churned for 7m 12s · 1 shell still running"))
        #expect(!HolySession.isLiveAgentStatusLineForTesting("✻ Sautéed for 1m 34s · 1 shell still running"))
        #expect(!HolySession.isLiveAgentStatusLineForTesting("⏵⏵ auto mode on · 1 shell · ← for agents"))
    }

    // Next-step hints must derive from an actual approval signal, never be
    // harvested from arbitrary transcript prose — streamed text containing
    // "confirm" otherwise becomes "Review the prompt and confirm approval"
    // and raises the hand while the agent is mid-reply.
    @Test func nextStepHintRequiresApprovalSignal() {
        let prose = "Password, credential, permission, and destructive confirmation prompts remain human-only by default."
        #expect(HolySessionRuntimeTelemetryParser.nextStepHintForTesting(
            evidence: prose, hasApprovalSignal: false
        ) == nil)
        #expect(HolySessionRuntimeTelemetryParser.nextStepHintForTesting(
            evidence: "Allow this tool call? (y/n)", hasApprovalSignal: true
        ) != nil)
    }

    // The freshness signature must watch at least as deep as the busy scans:
    // a spinner animating at scan depth but outside the signature window
    // would flap the freshness gate and read as idle.
    @Test func freshnessSignatureCoversBusyScanDepth() {
        func pane(spinner: String) -> String {
            (
                [spinner]
                + (1...20).map { "□ Todo item number \($0)" }
                + ["❯", "Model · Fable 5 · xhigh", "⏵⏵ auto mode on · ← for agents"]
            ).joined(separator: "\n")
        }
        let before = HolySession.visibleActivitySignatureForTesting(preview: pane(spinner: "✻ Frolicking… (2m 3s · ↓ 8.1k tokens)"))
        let after = HolySession.visibleActivitySignatureForTesting(preview: pane(spinner: "✽ Frolicking… (2m 4s · ↓ 8.2k tokens)"))
        #expect(before != after)
    }

    // The shell census feeds the watcher eye from the input-box footer only.
    // The mid-turn epitaph ("· 1 shell still running") freezes into
    // scrollback when the turn ends, so it must never count — that is the
    // exact false-permanence HolySession's working rules already refuse.
    @Test func backgroundShellCensusReadsTheFooterSegment() {
        let pane = [
            "✳ Cogitated for 27s · 1 shell still running",
            "❯",
            "Model · Fable 5 · xhigh",
            "⏵⏵ auto mode on · 2 shells · ← for agents",
        ].joined(separator: "\n")
        #expect(HolySession.backgroundShellCountForTesting(fromActiveContents: pane) == 2)
    }

    @Test func backgroundShellCensusIgnoresTheFrozenEpitaph() {
        let pane = [
            "Transcript prose about work",
            "✻ Churned for 7m 12s · 1 shell still running",
            "❯",
            "Model · Fable 5 · xhigh",
            "⏵⏵ auto mode on (shift+tab to cycle) · ← for agents",
        ].joined(separator: "\n")
        #expect(HolySession.backgroundShellCountForTesting(fromActiveContents: pane) == 0)
    }

    @Test func backgroundShellCensusIgnoresTranscriptAboveTheChromeWindow() {
        let pane = [
            "At the time the footer read auto mode on · 3 shells",
            "More transcript prose",
            "❯",
            "Model · Fable 5 · xhigh",
            "⏵⏵ auto mode on · ← for agents",
        ].joined(separator: "\n")
        #expect(HolySession.backgroundShellCountForTesting(fromActiveContents: pane) == 0)
    }

    @Test func backgroundShellCensusHandlesTheSingularFooter() {
        let pane = [
            "❯",
            "Model · Fable 5 · xhigh",
            "⏵⏵ auto mode on · 1 shell · ← for agents",
        ].joined(separator: "\n")
        #expect(HolySession.backgroundShellCountForTesting(fromActiveContents: pane) == 1)
    }

    // MARK: - Codex background-terminal census (footer pinned 2026-08-10)

    // Fixture captured verbatim from the live pane 2026-08-10: the census
    // line sits FOURTH from the bottom, above the command continuation, the
    // input box, and the status line — a three-line window never reaches it.
    @Test func codexCensusReadsTheLiveBackgroundTerminalFooter() {
        let pane = [
            "─────────────────────────────",
            "• No error has surfaced. The promise verifier is a silent all-in-one gate.",
            "• Waiting for background terminal (1m 50s • esc to interrupt) · 1 background terminal running · /ps to view · /stop to close",
            "└ EPHEM_PATH=/Users/erik/.local/share/aldebaran-group/ephemeris cargo run --locked --offline -p dm-ephemeris-oracle --bin verify-promise",
            "› Find and fix a bug in @filename",
            "gpt-5.6-sol xhigh fast · ~/Custom-Coding/aldebaran-group",
        ].joined(separator: "\n")
        #expect(HolySession.backgroundShellCountForTesting(
            fromActiveContents: pane, runtime: .codex
        ) == 1)
    }

    @Test func codexCensusCountsPluralTerminalsAndIgnoresTranscriptMentions() {
        // The prose line quotes the fenced count phrase inside the window but
        // carries no same-line live-chrome marker, so it cannot poison.
        let pane = [
            "At one point the footer said · 5 background terminals running · but that is prose",
            "More transcript history",
            "Working (2m 03s • esc to interrupt) · 3 background terminals running · /ps to view",
            "❯",
            "gpt-5.6-sol xhigh · ~/Custom-Coding/aldebaran-group",
        ].joined(separator: "\n")
        #expect(HolySession.backgroundShellCountForTesting(
            fromActiveContents: pane, runtime: .codex
        ) == 3)
    }

    @Test func codexCensusIgnoresPastTenseAndUnfencedPhrases() {
        let pane = [
            "• Waited for background terminal · EPHEM_PATH=... cargo test --workspace",
            "❯",
            "gpt-5.6-sol xhigh · ~/Custom-Coding/aldebaran-group",
        ].joined(separator: "\n")
        #expect(HolySession.backgroundShellCountForTesting(
            fromActiveContents: pane, runtime: .codex
        ) == 0)
    }

    @Test func censusVocabulariesDoNotCrossRuntimes() {
        // Claude's footer read by a codex census (and vice versa) is silence,
        // not a miscount: each runtime speaks only its own chrome.
        let claudeFooter = [
            "❯",
            "Model · Fable 5 · xhigh",
            "⏵⏵ auto mode on · 2 shells · ← for agents",
        ].joined(separator: "\n")
        let codexFooter = [
            "Working (10s · esc to interrupt) · 2 background terminals running · /ps to view",
            "❯",
            "gpt-5.6-sol xhigh · ~/Custom-Coding/aldebaran-group",
        ].joined(separator: "\n")
        #expect(HolySession.backgroundShellCountForTesting(
            fromActiveContents: claudeFooter, runtime: .codex
        ) == 0)
        #expect(HolySession.backgroundShellCountForTesting(
            fromActiveContents: codexFooter, runtime: .claude
        ) == 0)
        #expect(HolySession.backgroundShellCountForTesting(
            fromActiveContents: codexFooter, runtime: .opencode
        ) == 0)
    }
}
