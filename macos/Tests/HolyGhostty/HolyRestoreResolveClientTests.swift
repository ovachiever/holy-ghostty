import Foundation
import Testing
@testable import Ghostty

// The resolve CLI contract (05-RESOLVE-CLI.md) is pinned verbatim: a single
// JSON object on stdout whose `confidence` field is law. The bridge must
// parse every legal shape exactly and collapse every illegal one into the
// degraded resolver-unavailable state — never a guess, never a crash.
struct HolyRestoreResolveClientTests {
    // MARK: - Query → argument array

    @Test func queryBuildsExactArgumentArray() {
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
            "--json",
        ])
    }

    @Test func queryCarriesOptionalWindowLimitAndReindexFlags() {
        var query = HolyRestoreResolveQuery(
            workingDirectory: "/tmp/project",
            harness: "codex",
            nearUnixSeconds: 100
        )
        query.windowSeconds = 172_800
        query.limit = 5
        query.skipReindex = true

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
}
