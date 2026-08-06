import Foundation
import Testing
@testable import Ghostty

// The resolve CLI contract (05-RESOLVE-CLI.md) is pinned verbatim: a single
// JSON object on stdout whose `confidence` field is law. The bridge must
// parse every legal shape exactly and collapse every illegal one into the
// degraded resolver-unavailable state — never a guess, never a crash.
struct HolyRestoreResolveClientTests {
    // MARK: - Query → argument array

    @Test func queryBuildsExactArgumentArrayAndAlwaysSkipsReindex() {
        // --no-reindex is unconditional: a single resolve is a lookup, never
        // a reindex trigger. The post-reboot stampede (every per-row resolve
        // racing its own full 2.5GB reindex into 90s timeouts) must stay
        // impossible by construction.
        let query = HolyRestoreResolveQuery(
            workingDirectory: "/Users/erik/Custom-Coding/holy-ghostty",
            harness: "claude",
            nearUnixSeconds: 1_785_261_280
        )

        #expect(query.arguments == [
            "resolve",
            "--cwd", "/Users/erik/Custom-Coding/holy-ghostty",
            "--harness", "claude",
            "--near", "1785261280",
            "--no-reindex",
            "--json",
        ])
    }

    @Test func queryCarriesOptionalWindowAndLimitFlags() {
        var query = HolyRestoreResolveQuery(
            workingDirectory: "/tmp/project",
            harness: "codex",
            nearUnixSeconds: 100
        )
        query.windowSeconds = 172_800
        query.limit = 5

        #expect(query.arguments == [
            "resolve",
            "--cwd", "/tmp/project",
            "--harness", "codex",
            "--near", "100",
            "--window", "172800",
            "--limit", "5",
            "--no-reindex",
            "--json",
        ])
    }

    // MARK: - Contract parsing

    @Test func exactMatchPayloadParsesEveryPinnedField() throws {
        let payload = """
        {"matched": true, "id": "ae3d63af-e0b6-40b2-8dfa-cbc64d2e456c", \
        "harness": "claude-code", "runtime": "claude", \
        "project_path": "/Users/erik/Custom-Coding/holy-ghostty", \
        "resume_command": "claude --resume ae3d63af-e0b6-40b2-8dfa-cbc64d2e456c", \
        "confidence": "exact", \
        "candidates": [{"id": "ae3d63af-e0b6-40b2-8dfa-cbc64d2e456c", \
        "timestamp_end": 1785261280, "preview": "please see the recent commits"}]}
        """

        let resolution = try #require(
            HolyRestoreResolution.parse(Data(payload.utf8))
        )
        #expect(resolution.matched)
        #expect(resolution.providerSessionID == "ae3d63af-e0b6-40b2-8dfa-cbc64d2e456c")
        #expect(resolution.runtime == "claude")
        #expect(resolution.confidence == .exact)
        #expect(resolution.candidates.count == 1)
        #expect(resolution.candidates.first?.timestampEnd == 1_785_261_280)
        #expect(resolution.candidates.first?.preview == "please see the recent commits")
    }

    @Test func unmatchedPayloadParsesAsNoneWithNullID() throws {
        let payload = """
        {"matched": false, "id": null, "harness": "claude-code", "runtime": "claude", \
        "project_path": "/nowhere", "resume_command": null, "confidence": "none", "candidates": []}
        """

        let resolution = try #require(
            HolyRestoreResolution.parse(Data(payload.utf8))
        )
        #expect(!resolution.matched)
        #expect(resolution.providerSessionID == nil)
        #expect(resolution.resumeCommand == nil)
        #expect(resolution.confidence == HolyRestoreResolution.Confidence.none)
        #expect(resolution.candidates.isEmpty)
    }

    @Test func ambiguousPayloadCarriesEveryCandidate() throws {
        let payload = """
        {"matched": false, "id": null, "harness": "claude-code", "runtime": "claude", \
        "project_path": "/p", "resume_command": null, "confidence": "ambiguous", \
        "candidates": [\
        {"id": "aaa", "timestamp_end": 100, "preview": "first prompt"}, \
        {"id": "bbb", "timestamp_end": 200, "preview": "second prompt"}]}
        """

        let resolution = try #require(
            HolyRestoreResolution.parse(Data(payload.utf8))
        )
        #expect(resolution.confidence == .ambiguous)
        #expect(resolution.candidates.map(\.id) == ["aaa", "bbb"])
        #expect(resolution.candidates.map(\.timestampEnd) == [100, 200])
    }

    @Test func malformedJSONParsesAsNil() {
        #expect(HolyRestoreResolution.parse(Data("not json".utf8)) == nil)
        #expect(HolyRestoreResolution.parse(Data()) == nil)
        #expect(HolyRestoreResolution.parse(Data("[]".utf8)) == nil)
    }

    @Test func unknownConfidenceIsAContractViolationNotAGuess() {
        let payload = """
        {"matched": true, "id": "x", "harness": "claude-code", "runtime": "claude", \
        "project_path": "/p", "resume_command": "claude --resume x", \
        "confidence": "probably", "candidates": []}
        """

        #expect(HolyRestoreResolution.parse(Data(payload.utf8)) == nil)
    }

    @Test func matchedTrueWithoutIDIsAContractViolation() {
        let payload = """
        {"matched": true, "id": null, "harness": "claude-code", "runtime": "claude", \
        "project_path": "/p", "resume_command": null, "confidence": "exact", "candidates": []}
        """

        #expect(HolyRestoreResolution.parse(Data(payload.utf8)) == nil)
    }

    // MARK: - Degraded resolver state

    @Test func missingBinaryDegradesToResolverUnavailable() async {
        let client = HolyAgentSessionsResolveClient(
            binaryPathOverride: "/nonexistent/definitely-not-agent-sessions"
        )
        let outcome = await client.resolve(.init(
            workingDirectory: "/tmp",
            harness: "claude",
            nearUnixSeconds: 1
        ))

        guard case let .resolverUnavailable(reason) = outcome else {
            Issue.record("Expected resolverUnavailable, got \(outcome)")
            return
        }
        #expect(!reason.isEmpty)
    }

    // MARK: - Batch contract (resolve-batch)

    @Test func batchQueryUsesTheResolveBatchSubcommand() {
        let query = HolyRestoreResolveBatchQuery(requests: [
            .init(cwd: "/tmp/a", harness: "claude", near: 100),
        ])
        #expect(query.arguments == ["resolve-batch", "--json"])
    }

    @Test func batchStdinPayloadMatchesThePinnedEnvelopeByteForByte() throws {
        let query = HolyRestoreResolveBatchQuery(requests: [
            .init(cwd: "/Users/erik/Custom-Coding", harness: "claude", near: 1_785_261_280),
            .init(cwd: "/tmp/other", harness: "codex", near: 42),
        ])

        let payload = try #require(query.stdinPayload())
        let rendered = try #require(String(bytes: payload, encoding: .utf8))
        #expect(rendered == #"{"requests":[{"cwd":"\/Users\/erik\/Custom-Coding","harness":"claude","near":1785261280},{"cwd":"\/tmp\/other","harness":"codex","near":42}]}"#)
    }

    @Test func batchPayloadParsesEveryPinnedField() throws {
        // Mirrors real CLI output: the echoed harness is CANONICAL
        // ("claude-code" for a "claude" request), runtime is never null, and
        // a nonexistent cwd still gets a full result with empty candidates.
        let payload = """
        {"results": [\
        {"cwd": "/Users/erik/Custom-Coding", "harness": "claude-code", "runtime": "claude", \
        "candidates": [\
        {"id": "e3565698-4bd2-449b-9f84-000000000001", "timestamp_end": 1785261280, \
        "preview": "lane twelve", "resume_command": "claude --resume e3565698-4bd2-449b-9f84-000000000001"}, \
        {"id": "41d7e2aa-0000-0000-0000-000000000002", "timestamp_end": 1785261100, "preview": "lane nine"}]}, \
        {"cwd": "/Users/erik/does-not-exist", "harness": "claude-code", "runtime": "claude", "candidates": []}]}
        """

        let resolution = try #require(HolyRestoreBatchResolution.parse(Data(payload.utf8)))
        #expect(resolution.results.count == 2)

        let first = resolution.results[0]
        #expect(first.cwd == "/Users/erik/Custom-Coding")
        #expect(first.harness == "claude-code")
        #expect(first.runtime == "claude")
        #expect(first.error == nil)
        #expect(first.candidates.map(\.id) == [
            "e3565698-4bd2-449b-9f84-000000000001",
            "41d7e2aa-0000-0000-0000-000000000002",
        ])
        #expect(first.candidates.map(\.timestampEnd) == [1_785_261_280, 1_785_261_100])
        #expect(first.candidates.first?.preview == "lane twelve")

        let second = resolution.results[1]
        #expect(second.runtime == "claude")
        #expect(second.candidates.isEmpty)
        #expect(second.error == nil)
    }

    @Test func batchPayloadCarriesPerRequestErrors() throws {
        // Unknown harness: exit 0, full result, harness/runtime echo the
        // input verbatim, candidates empty, "error" explains.
        let payload = """
        {"results": [{"cwd": "/p", "harness": "emacs", "runtime": "emacs", "candidates": [], \
        "error": "unknown harness 'emacs'; expected one of claude, claude-code, codex, opencode"}]}
        """

        let resolution = try #require(HolyRestoreBatchResolution.parse(Data(payload.utf8)))
        #expect(resolution.results.first?.error
            == "unknown harness 'emacs'; expected one of claude, claude-code, codex, opencode")
        #expect(resolution.results.first?.candidates.isEmpty == true)
    }

    @Test func batchPayloadToleratesMissingCandidatesAndPreview() throws {
        let payload = """
        {"results": [{"cwd": "/p", "harness": "claude-code", "runtime": "claude"}, \
        {"cwd": "/q", "harness": "claude-code", "runtime": "claude", \
        "candidates": [{"id": "abc", "timestamp_end": 7}]}]}
        """

        let resolution = try #require(HolyRestoreBatchResolution.parse(Data(payload.utf8)))
        #expect(resolution.results[0].candidates.isEmpty)
        #expect(resolution.results[1].candidates == [
            .init(id: "abc", timestampEnd: 7, preview: ""),
        ])
    }

    @Test func batchPayloadOutsideTheContractParsesAsNil() {
        #expect(HolyRestoreBatchResolution.parse(Data("not json".utf8)) == nil)
        #expect(HolyRestoreBatchResolution.parse(Data()) == nil)
        #expect(HolyRestoreBatchResolution.parse(Data("[]".utf8)) == nil)
        #expect(HolyRestoreBatchResolution.parse(Data(#"{"matched": true}"#.utf8)) == nil)
        // A results entry missing its cwd is a contract violation, not a
        // partial success.
        #expect(HolyRestoreBatchResolution.parse(
            Data(#"{"results": [{"harness": "claude-code"}]}"#.utf8)
        ) == nil)
        // runtime is pinned non-null; null is a contract violation.
        #expect(HolyRestoreBatchResolution.parse(
            Data(#"{"results": [{"cwd": "/p", "harness": "claude-code", "runtime": null, "candidates": []}]}"#.utf8)
        ) == nil)
    }

    @Test func missingBinaryDegradesBatchToResolverUnavailable() async {
        let client = HolyAgentSessionsResolveClient(
            binaryPathOverride: "/nonexistent/definitely-not-agent-sessions"
        )
        let outcome = await client.resolveBatch([
            .init(cwd: "/tmp", harness: "claude", near: 1),
        ])

        guard case let .resolverUnavailable(reason) = outcome else {
            Issue.record("Expected resolverUnavailable, got \(outcome)")
            return
        }
        #expect(!reason.isEmpty)
    }

    @Test func emptyBatchNeverSpawnsAProcess() async {
        // A sheet with nothing to resolve must not pay a subprocess launch;
        // the nonexistent-binary override would fail if it tried.
        let client = HolyAgentSessionsResolveClient(
            binaryPathOverride: "/nonexistent/definitely-not-agent-sessions"
        )
        let outcome = await client.resolveBatch([])
        #expect(outcome == .resolved([]))
    }
}
