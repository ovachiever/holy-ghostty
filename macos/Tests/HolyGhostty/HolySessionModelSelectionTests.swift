import Foundation
import Testing
@testable import Ghostty

struct HolySessionModelSelectionTests {
    @Test func failedTmuxDeliveryRetriesThenDeduplicatesSuccess() throws {
        var state = HolyTmuxModelLabelDeliveryState()
        let start = Date(timeIntervalSince1970: 1_000)
        state.request("Opus 4.8 · max")
        let firstValue = state.beginAttempt(now: start)
        let first = try #require(firstValue)
        state.complete(first, succeeded: false, now: start)

        let prematureRetry = state.beginAttempt(now: start.addingTimeInterval(0.5))
        #expect(prematureRetry == nil)
        let retryValue = state.beginAttempt(now: start.addingTimeInterval(1.1))
        let retry = try #require(retryValue)
        #expect(retry.label == "Opus 4.8 · max")
        state.complete(retry, succeeded: true, now: start.addingTimeInterval(1.1))
        let duplicate = state.beginAttempt(now: start.addingTimeInterval(10))
        #expect(duplicate == nil)

        state.request("Fable 5 · high")
        let changedModel = state.beginAttempt(now: start.addingTimeInterval(10))
        #expect(changedModel?.label == "Fable 5 · high")
    }

    @Test func parsesCurrentCodexFooterAndReasoningEffort() throws {
        let contents = """
        • Finished the requested work.

          gpt-5.6-sol ultra fast · ~/Custom-Coding/holy-ghostty · Main [default]
        """

        let selection = try #require(HolySessionModelSelectionParser.selection(from: contents))
        #expect(selection.runtime == .codex)
        #expect(selection.modelName == "gpt-5.6-sol")
        #expect(selection.qualifier == "ultra")
        #expect(selection.statusLabel == "gpt-5.6-sol · ultra")
        #expect(selection.source == .codexFooter)
    }

    @Test func supportsOlderCodexFastBeforeEffortFooter() throws {
        let selection = try #require(
            HolySessionModelSelectionParser.selection(from: "gpt-5.1 fast high")
        )

        #expect(selection.modelName == "gpt-5.1")
        #expect(selection.qualifier == "high")
    }

    @Test func newestStructuralCodexFooterWins() throws {
        let contents = """
        gpt-5.1 low
        ordinary terminal output
        gpt-5.6-sol xhigh fast · ~/work
        """

        let selection = try #require(HolySessionModelSelectionParser.selection(from: contents))
        #expect(selection.modelName == "gpt-5.6-sol")
        #expect(selection.qualifier == "xhigh")
    }

    @Test func proseNeverMasqueradesAsCodexModelState() {
        let contents = "I think gpt-5.6-sol ultra is active, but verify it."
        #expect(HolySessionModelSelectionParser.selection(from: contents) == nil)
    }

    @Test func parsesOpenCodePromptMetadataWithoutMisclassifyingProvider() throws {
        let selection = try #require(
            HolySessionModelSelectionParser.selection(
                from: "Build - Claude Opus 4.6 Anthropic - max"
            )
        )

        #expect(selection.runtime == .opencode)
        #expect(selection.modelName == "Claude Opus 4.6")
        #expect(selection.provider == "Anthropic")
        #expect(selection.qualifier == "max")
        #expect(selection.statusLabel == "Claude Opus 4.6 · max")
        #expect(selection.source == .openCodePrompt)
    }

    @Test func parsesCurrentOpenCodeDotSeparators() throws {
        let selection = try #require(
            HolySessionModelSelectionParser.selection(
                from: "Plan · GPT-5.6 OpenAI · high"
            )
        )

        #expect(selection.runtime == .opencode)
        #expect(selection.modelName == "GPT-5.6")
        #expect(selection.qualifier == "high")
    }

    @Test func runtimeGateRejectsAnotherAgentsModelChrome() throws {
        #expect(
            HolySessionModelSelectionParser.selection(
                from: "gpt-5.6-sol ultra fast",
                expectedRuntime: .claude
            ) == nil
        )

        let contents = """
        Plan · GPT-5.6 OpenAI · high
        gpt-5.6-sol ultra fast
        """
        let openCode = try #require(
            HolySessionModelSelectionParser.selection(
                from: contents,
                expectedRuntime: .opencode
            )
        )
        #expect(openCode.runtime == .opencode)
        #expect(openCode.modelName == "GPT-5.6")
    }

    @Test func claudeLookingTerminalTextIsNeverModelAuthority() {
        #expect(
            HolySessionModelSelectionParser.selection(
                from: "Model · Opus 4.8 · max",
                expectedRuntime: .claude
            ) == nil
        )
        #expect(
            HolySessionModelSelectionParser.selection(
                from: "I switched from Opus to Sonnet in another session."
            ) == nil
        )
    }

    @Test func exitedTUIRemnantIsNotLiveModelEvidence() {
        let contents = """
        Model · Opus 4.8 · max

        erik@studio holy-ghostty %
        """

        #expect(
            HolySessionModelSelectionParser.selection(
                from: contents,
                expectedRuntime: .claude
            ) == nil
        )
    }

    @MainActor
    @Test func currentUltraFastCodexFooterAlsoInfersRuntime() {
        #expect(
            HolySession.inferredRuntimeForTesting(
                preview: "gpt-5.6-sol ultra fast · ~/Custom-Coding/holy-ghostty"
            ) == .codex
        )
    }

    @MainActor
    @Test func shellTextCannotImpersonateClaudeRuntime() {
        #expect(
            HolySession.inferredRuntimeForTesting(
                preview: "Model · Opus 4.8 · max"
            ) == nil
        )
    }
}
