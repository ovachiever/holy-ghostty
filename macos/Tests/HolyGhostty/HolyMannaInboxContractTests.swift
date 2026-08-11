import Foundation
import Testing
@testable import Ghostty

/// Manna's read-only JSON contracts, pinned from live invocations on
/// 2026-08-03. The inbox production path invokes only `list`; reconcile
/// fixtures remain here for adapters that inject explicit decision findings.
///
///   cd /Users/erik/Custom-Coding/holy-ghostty && agent-do manna list --json
///   cd /Users/erik/Custom-Coding/holy-ghostty && agent-do manna reconcile --json
///   cd /Users/erik/Custom-Coding          && agent-do manna list --json
///
/// list  → {"success":true,"issues":[{id,title,status,claimed_by?,type?,track?,updated,gate?}]}
///         `type` is omitted when it is the default `item`; `claimed_by`,
///         `track` and `gate` are omitted when absent (`gate` appears only on
///         dreams). `updated` is a display string — "2026-07-21 (13d ago)" —
///         never ISO8601.
/// recon → {"success":true,"findings":[{kind,issue_id?,detail,evidence?,proposed_fix?}]}
///         kinds pinned from the FindingKind enum and observed live:
///         landed_open, dead_claim, blocker_desync, stale_dream,
///         dangling_track, doc_reference, prompt_pairing, skipped.
///
/// Shape drift must fail loud: anything outside this contract parses to nil so
/// the source degrades honestly instead of rendering a guess.
struct HolyMannaInboxContractTests {
    /// Rows verbatim from the live 2026-08-03 holy-ghostty board: one dream
    /// (the only shape carrying `gate`), one blocked item on a track, one
    /// done+claimed item, one bare open item with no optional keys at all.
    static let pinnedListFixture = """
    {"success":true,"issues":[\
    {"id":"mn-cb681f","title":"[P3][OPTIONAL][HALF-BAKED] Git-action glyphs on unread","status":"open","type":"dream","updated":"2026-07-21 (13d ago)","gate":"[DREAM: not claimable, needs conversion]"},\
    {"id":"mn-569b91","title":"[VERIFY][TMUX] Reconcile known sessions and safely reap true orphans","status":"blocked","track":"mn-eb7a80","updated":"2026-07-21 (13d ago)"},\
    {"id":"mn-495322","title":"[P0][TMUX] Kill and verify the exact discovered live session","status":"done","claimed_by":"6e040306-1877-4113-b974-ce3e45bfb87e","track":"mn-eb7a80","updated":"2026-08-03 (4h ago)"},\
    {"id":"mn-4a1b2c","title":"Bare item","status":"open","updated":"2026-08-01 (2d ago)"}\
    ]}
    """

    /// Findings verbatim from the live 2026-08-03 holy-ghostty run, plus the
    /// `skipped` finding the workspace-root board produced (no proposed_fix,
    /// no issue_id).
    static let pinnedReconcileFixture = """
    {"success":true,"findings":[\
    {"kind":"landed_open","issue_id":"mn-70875b","detail":"referenced by landed commit trailer but status is open","evidence":"bc004f7c53c7","proposed_fix":"review the commits; if the work landed, claim and done mn-70875b"},\
    {"kind":"blocker_desync","issue_id":"mn-569b91","detail":"all blockers resolved but status is still blocked","evidence":"mn-495322 (done)","proposed_fix":"remove resolved blockers to unblock"},\
    {"kind":"stale_dream","issue_id":"mn-cb681f","detail":"open dream older than 14 days","evidence":"created_at 2026-07-16","proposed_fix":"promote to an item on a track, or close it"},\
    {"kind":"doc_reference","issue_id":"mn-b17dc6","detail":"referenced id does not exist on this board","evidence":".handoff/OVERSEER-JARVIS-PLAN-2026-07-16.md:137"},\
    {"kind":"skipped","detail":"landed_open skipped: not a git repository"}\
    ]}
    """

    // MARK: - list

    @Test func pinnedListFixtureDecodesEveryField() throws {
        let payload = try #require(HolyMannaListPayload.parse(Data(Self.pinnedListFixture.utf8)))
        #expect(payload.issues.count == 4)

        let dream = payload.issues[0]
        #expect(dream.id == "mn-cb681f")
        #expect(dream.title == "[P3][OPTIONAL][HALF-BAKED] Git-action glyphs on unread")
        #expect(dream.status == .open)
        #expect(dream.type == .dream)
        #expect(dream.claimedBy == nil)
        #expect(dream.track == nil)
        #expect(dream.gate == "[DREAM: not claimable, needs conversion]")
        #expect(dream.updated == "2026-07-21 (13d ago)")

        let blocked = payload.issues[1]
        #expect(blocked.status == .blocked)
        // `type` omitted means the default: item.
        #expect(blocked.type == .item)
        #expect(blocked.track == "mn-eb7a80")

        let done = payload.issues[2]
        #expect(done.status == .done)
        #expect(done.claimedBy == "6e040306-1877-4113-b974-ce3e45bfb87e")

        let bare = payload.issues[3]
        #expect(bare.type == .item)
        #expect(bare.claimedBy == nil)
        #expect(bare.track == nil)
        #expect(bare.gate == nil)
    }

    /// `updated` is a display string; only its leading calendar date is real.
    @Test func updatedDateReadsTheLeadingCalendarDayAndNothingElse() {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 21
        let expected = Calendar(identifier: .gregorian).date(from: components)

        #expect(HolyMannaIssueSummary.updatedDate(from: "2026-07-21 (13d ago)") == expected)
        #expect(HolyMannaIssueSummary.updatedDate(from: "13d ago") == nil)
        #expect(HolyMannaIssueSummary.updatedDate(from: "") == nil)
        #expect(HolyMannaIssueSummary.updatedDate(from: "2026-13-45 (x)") == nil)
    }

    @Test func unknownStatusOrTypeValuesDegradeRatherThanDropTheBoard() throws {
        // A future manna release adding a status must not blank the pane; the
        // row survives as an unknown value that no admission rule matches.
        let json = """
        {"success":true,"issues":[{"id":"mn-000001","title":"t","status":"archived","type":"epic","updated":"2026-08-01 (2d ago)"}]}
        """
        let payload = try #require(HolyMannaListPayload.parse(Data(json.utf8)))
        #expect(payload.issues[0].status == .unknown)
        #expect(payload.issues[0].type == .unknown)
    }

    /// The CLI answers errors in YAML even when `--json` is passed — verified
    /// live by running `agent-do manna list --json` outside a board.
    @Test func yamlErrorAnswerParsesToNilNotAnEmptyBoard() {
        let liveErrorBytes = "success: false\nerror: Storage not initialized. Run 'manna-core init' first.\n\n"
        #expect(HolyMannaListPayload.parse(Data(liveErrorBytes.utf8)) == nil)
        #expect(HolyMannaReconcilePayload.parse(Data(liveErrorBytes.utf8)) == nil)
    }

    @Test func malformedListPayloadsParseToNil() {
        #expect(HolyMannaListPayload.parse(Data("not json".utf8)) == nil)
        #expect(HolyMannaListPayload.parse(Data()) == nil)
        // `issues` present but the wrong shape.
        #expect(HolyMannaListPayload.parse(Data(#"{"success":true,"issues":7}"#.utf8)) == nil)
        // success:false with a JSON body is still not a board.
        #expect(HolyMannaListPayload.parse(Data(#"{"success":false,"error":"x"}"#.utf8)) == nil)
    }

    // MARK: - reconcile

    @Test func pinnedReconcileFixtureDecodesEveryFindingField() throws {
        let payload = try #require(
            HolyMannaReconcilePayload.parse(Data(Self.pinnedReconcileFixture.utf8))
        )
        #expect(payload.findings.count == 5)

        let landed = payload.findings[0]
        #expect(landed.kind == .landedOpen)
        #expect(landed.issueID == "mn-70875b")
        #expect(landed.detail == "referenced by landed commit trailer but status is open")
        #expect(landed.evidence == "bc004f7c53c7")

        #expect(payload.findings[1].kind == .blockerDesync)
        #expect(payload.findings[1].issueID == "mn-569b91")
        #expect(payload.findings[2].kind == .staleDream)
        #expect(payload.findings[3].kind == .docReference)
        #expect(payload.findings[3].proposedFix == nil)

        // `skipped` carries neither issue_id nor proposed_fix.
        #expect(payload.findings[4].kind == .skipped)
        #expect(payload.findings[4].issueID == nil)
    }

    @Test func everyPinnedFindingKindDecodesAndUnknownKindsSurviveAsUnknown() {
        let pinned: [(String, HolyMannaFindingKind)] = [
            ("landed_open", .landedOpen),
            ("dead_claim", .deadClaim),
            ("blocker_desync", .blockerDesync),
            ("stale_dream", .staleDream),
            ("dangling_track", .danglingTrack),
            ("doc_reference", .docReference),
            ("prompt_pairing", .promptPairing),
            ("skipped", .skipped),
        ]
        for (raw, expected) in pinned {
            #expect(HolyMannaFindingKind(rawValue: raw) == expected)
        }
        #expect(HolyMannaFindingKind(rawValue: "future_kind") == .unknown)
    }

    @Test func reconcileWithNoFindingsIsAQuietCleanBoard() throws {
        let payload = try #require(
            HolyMannaReconcilePayload.parse(Data(#"{"success":true,"findings":[]}"#.utf8))
        )
        #expect(payload.findings.isEmpty)
    }

    // MARK: - Invocation contract

    /// The production read resolves `./.manna` from the process working
    /// directory. It deliberately does not run the much heavier reconcile
    /// audit before making the local backlog visible.
    @Test func productionInvocationIsTheFastListContractOnly() {
        #expect(HolyMannaInboxSource.listArguments == ["manna", "list", "--json"])
    }

    @Test func productionInvocationNeverMutatesTheBoard() {
        let mutating = ["--fix", "--write-drift", "claim", "done", "abandon", "update", "delete"]
        for argument in HolyMannaInboxSource.listArguments {
            #expect(!mutating.contains(argument))
        }
        #expect(!HolyMannaInboxSource.listArguments.contains("reconcile"))
    }
}
