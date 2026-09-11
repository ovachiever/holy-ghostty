import Foundation
import Testing
@testable import Ghostty

/// App-hosted. Compile during the lane; execute in the coordinated acceptance window.
struct HolyMannaBoardLinkTests {
    @Test(arguments: ["mn-abcdef", "mn-012345", "mn-0123456789abcdef"])
    func validIdentifiersAndURLRoundTrip(id: String) throws {
        #expect(HolyMannaLink.isIdentifier(id))
        let url = try #require(HolyMannaLink.url(for: id))
        #expect(HolyAutomationURLParser.boardItemID(from: url) == id)
        #expect(HolyAutomationURLParser.launchSpec(from: url) == nil)
    }

    @Test(arguments: ["", "mn-", "mn-abcde", "MN-abcdef", "mn-ABCDEF", "xmn-abcdef",
                      "_mn-abcdef", "émn-abcdef", "mn-abcdefg", "mn-abcdef_", "mn-abcdefé"])
    func invalidPatternsNeverLink(text: String) {
        #expect(!HolyMannaLink.isIdentifier(text))
        for offset in 0..<(text as NSString).length {
            #expect(HolyMannaLink.match(in: text, atUTF16Offset: offset) == nil)
        }
    }

    @Test func onlyTheIdentifierCellsInProseLink() {
        let line = "界 🔭 cite (`mn-abcdef`), then mn-123456."
        let first = (line as NSString).range(of: "mn-abcdef")
        let second = (line as NSString).range(of: "mn-123456")
        for offset in 0..<(line as NSString).length {
            let expected: NSRange? = NSLocationInRange(offset, first) ? first
                : (NSLocationInRange(offset, second) ? second : nil)
            #expect(HolyMannaLink.match(in: line, atUTF16Offset: offset) == expected)
        }
        #expect(HolyMannaLink.match(in: line, atUTF16Offset: -1) == nil)
    }

    @Test(arguments: ["https://board?item=mn-abcdef", "holy-ghostty://board?item=mn-ABCDEF",
                      "holy-ghostty://board?item=mn-abcdef&item=mn-123456",
                      "holy-ghostty://board?item=mn-abcdef&initialInput=touch+file",
                      "holy-ghostty://board/extra?item=mn-abcdef", "holy-ghostty://board?item=mn-abcdef%0A",
                      "holy-ghostty://user@board?item=mn-abcdef"])
    func malformedBoardRoutesRefuse(value: String) throws {
        #expect(HolyAutomationURLParser.boardItemID(from: try #require(URL(string: value))) == nil)
    }

    @Test func wrappedIdentifierUnderlineUsesViewportCellsAndBaseline() {
        let lines = HolyMannaLink.underlines(for: "mn-abcdef", startingAt: 18, columns: 10,
                                           origin: CGPoint(x: 8, y: 13), cellSize: CGSize(width: 9, height: 18))
        #expect(lines == [CGRect(x: 80, y: 32, width: 18, height: 1),
                          CGRect(x: 8, y: 50, width: 63, height: 1)])
    }

    @Test func wrappedPunctuationAndOtherWordsStayOutsideTheLink() {
        let word = "see/mn-abcdef."
        for offset in 0..<word.count {
            let match = HolyMannaLink.wrappedMatch(in: word, startingAt: 37, columns: 40,
                                                   clickedColumn: (37 + offset) % 40)
            #expect(match == ((4..<13).contains(offset) ? NSRange(location: 4, length: 9) : nil))
        }
        #expect(HolyMannaLink.wrappedMatch(in: "mn-abcdef", startingAt: 37, columns: 40, clickedColumn: 20) == nil)
        #expect(HolyMannaLink.wrappedMatch(in: "xmn-abcdef", startingAt: 37, columns: 40, clickedColumn: 0) == nil)
    }

    @Test func wrappedLongIdentifierRefusesAColumnSharedWithPunctuation() {
        let id = "mn-0123456789abcdef"
        #expect(HolyMannaLink.wrappedMatch(in: id, startingAt: 7, columns: 10, clickedColumn: 7)
                == NSRange(location: 0, length: id.count))
        #expect(HolyMannaLink.wrappedMatch(in: id + ".", startingAt: 7, columns: 10,
                                         clickedColumn: (7 + id.count) % 10) == nil)
    }

    @Test func originatingBoardWinsEvenIfTheEstateWouldBeAmbiguous() async throws {
        let calls = LinkCalls()
        let client = linkClient(states: ["/a": try linkState(root: "/a"), "/b": try linkState(root: "/b")], calls: calls)
        let result = try await HolyMannaBoardLinkResolver(client: client).resolve("mn-abcdef", from: linkOrigin)
        #expect(result.matches.map(\.root) == ["/a"])
        #expect(result.estate == nil)
        #expect(await calls.values.count == 1)
    }

    @Test func nestedCwdUsesTheCanonicalBoardRoot() async throws {
        let client = linkClient(states: ["/a/subdir": try linkState(root: "/a")])
        let result = try await HolyMannaBoardLinkResolver(client: client).resolve(
            "mn-abcdef", from: .init(boardRoot: "/a/subdir", remoteHost: nil))
        #expect(result.matches.map(\.root) == ["/a"])
    }

    @Test(arguments: [Optional<String>.none, "builder@example.com"])
    func uniqueCrossBoardMatchStaysOnTheOriginatingHost(host: String?) async throws {
        let calls = LinkCalls()
        let client = linkClient(states: ["/a": try linkState(root: "/a", includesItem: false),
                                         "/b": try linkState(root: "/b")], calls: calls)
        let result = try await HolyMannaBoardLinkResolver(client: client).resolve(
            "mn-abcdef", from: .init(boardRoot: "/a", remoteHost: host))
        #expect(result.matches.map(\.root) == ["/b"])
        #expect(await calls.values.count == 3)
        #expect(await calls.values.allSatisfy { invocation in
            invocation.displayCommand.hasPrefix(host.map { "\($0): " } ?? "agent-do")
                && (invocation.displayCommand.contains("manna state --json")
                    || invocation.displayCommand.contains("manna estate --json"))
        })
    }

    @Test func ambiguityAndUnknownRemainUnselectedSearches() async throws {
        for includesItem in [false, true] {
            let client = linkClient(states: ["/a": try linkState(root: "/a", includesItem: false),
                                             "/b": try linkState(root: "/b", includesItem: includesItem),
                                             "/c": try linkState(root: "/c", includesItem: includesItem)])
            let result = try await HolyMannaBoardLinkResolver(client: client).resolve("mn-abcdef", from: linkOrigin)
            #expect(result.matches.count == (includesItem ? 2 : 0))
            await verifySearch(client: client)
        }
    }

    @Test func missingFocusedBoardStillSearchesTheEstate() async throws {
        let client = linkClient(states: ["/b": try linkState(root: "/b")], missingRoot: "/a")
        let result = try await HolyMannaBoardLinkResolver(client: client).resolve("mn-abcdef", from: linkOrigin)
        #expect(result.matches.map(\.root) == ["/b"])
    }

    @Test func unreadableBoardCannotProveUniqueness() async throws {
        let client = linkClient(states: ["/a": try linkState(root: "/a", includesItem: false),
                                         "/b": try linkState(root: "/b"), "/c": "invalid JSON"])
        await #expect(throws: (any Error).self) {
            try await HolyMannaBoardLinkResolver(client: client).resolve("mn-abcdef", from: linkOrigin)
        }
        await verifySearch(client: client)
    }

    @Test func omittedDoneRowsCannotProveUniqueness() async throws {
        var partial = try #require(JSONSerialization.jsonObject(with: Data(linkState(root: "/c").utf8)) as? [String: Any])
        partial["all"] = []
        partial["next"] = []
        let client = linkClient(states: ["/a": try linkState(root: "/a", includesItem: false),
                                         "/b": try linkState(root: "/b"), "/c": try linkJSON(partial)])
        await #expect(throws: (any Error).self) {
            try await HolyMannaBoardLinkResolver(client: client).resolve("mn-abcdef", from: linkOrigin)
        }
    }

    @Test @MainActor func unknownWithoutAFocusedBoardStillOpensBoardSearch() async throws {
        let store = linkStore(client: linkClient(states: [:]))
        store.openItemLink("mn-abcdef", from: .init(boardRoot: nil, remoteHost: nil))
        try await linkSettled(store)
        #expect(store.isPresented && store.surface == .board)
        #expect(store.grep == "mn-abcdef" && store.grepFocusRequest > 0)
        #expect(store.selectedItem == nil && store.dispatchNotice != nil)
        store.dismiss()
    }

    @Test @MainActor func scrollbackDoneCitationLandsOnItsDoneRowWithoutDispatch() async throws {
        let scrollback = "Earlier: mn-abcdef completed."
        let range = try #require(HolyMannaLink.match(in: scrollback, atUTF16Offset: 12))
        let id = (scrollback as NSString).substring(with: range)
        let calls = LinkCalls()
        let store = linkStore(client: linkClient(states: ["/a": try linkState(root: "/a", includesItem: false),
                                                         "/b": try linkState(root: "/b", status: "done")], calls: calls))
        store.boardFilter = .live
        store.trackFilter = "unrelated-track"
        store.openItemLink(id, from: linkOrigin)
        try await linkSettled(store)
        #expect(store.context.boardRoot == "/b")
        #expect(store.selectedItemID == id)
        #expect(store.boardFilter == .done)
        #expect(store.trackFilter == nil)
        #expect(store.boardSections.flatMap(\.items).map(\.id) == [id])
        #expect(store.selectedItem?.effective == "done")
        #expect(store.pendingDispatch == nil && store.pendingMutation == nil)
        #expect(await calls.values.allSatisfy { !$0.displayCommand.contains("manna claim") })
        store.dismiss()
    }

    @Test @MainActor func linkAndWorkerRequestCannotDispatchBeforeConfirmation() async throws {
        var launches = 0
        let store = linkStore(client: linkClient(states: ["/a": try linkState(root: "/a")]),
                              launcher: { _ in launches += 1; return UUID() })
        store.openItemLink("mn-abcdef", from: linkOrigin)
        try await linkSettled(store)
        #expect(launches == 0 && store.pendingDispatch == nil && store.pendingMutation == nil)
        store.confirmWorker()
        #expect(launches == 0)
        store.requestWorker(try #require(store.selectedItem))
        #expect(store.pendingDispatch != nil && launches == 0)
        store.confirmWorker()
        for _ in 0..<200 where store.isDispatching { try await Task.sleep(for: .milliseconds(5)) }
        #expect(launches == 1)
        store.dismiss()
    }

    @Test(arguments: ["dream", "claimed"]) @MainActor
    func linkedDreamsRefuseAndClaimsNameTheOwner(kind: String) async throws {
        let store = linkStore(client: linkClient(states: ["/a": try linkState(
            root: "/a", status: kind == "claimed" ? "in_progress" : "open", kind: kind == "dream" ? "dream" : "item")]))
        store.openItemLink("mn-abcdef", from: linkOrigin)
        try await linkSettled(store)
        store.requestWorker(try #require(store.selectedItem))
        #expect(store.pendingDispatch == nil)
        #expect(store.dispatchNotice != nil)
        if kind == "claimed" { #expect(store.dispatchNotice?.contains("other-worker") == true) }
        store.dismiss()
    }

    @Test @MainActor func dismissedOrEditedSearchCannotBeReopenedByLateResolution() async throws {
        let store = linkStore(client: linkClient(states: ["/a": try linkState(root: "/a")], delay: .milliseconds(60)))
        store.openItemLink("mn-abcdef", from: linkOrigin)
        store.grep = "different search"
        try await Task.sleep(for: .milliseconds(100))
        #expect(store.grep == "different search")
        #expect(!store.isResolvingItemLink)
        store.openItemLink("mn-abcdef", from: linkOrigin)
        store.dismiss()
        try await Task.sleep(for: .milliseconds(100))
        #expect(!store.isPresented)
        #expect(store.pendingDispatch == nil && store.pendingMutation == nil)
    }
}

private let linkOrigin = HolyMannaBoardContext(boardRoot: "/a", remoteHost: nil)

private actor LinkCalls {
    var values: [HolyMannaProcessInvocation] = []
    func record(_ value: HolyMannaProcessInvocation) { values.append(value) }
}

private func linkClient(states: [String: String], calls: LinkCalls = LinkCalls(), missingRoot: String? = nil,
                        delay: Duration = .zero) -> HolyMannaBoardClient {
    let identity = HolyMannaActorIdentityStore(fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("holy-link-tests-\(UUID()).json"))
    return HolyMannaBoardClient(identityStore: identity) { invocation, _ in
        await calls.record(invocation)
        if delay > .zero { try? await Task.sleep(for: delay) }
        if invocation.displayCommand.contains("estate") {
            return .init(stdout: try linkEstate(roots: states.keys.sorted()), stderr: "", exitCode: 0)
        }
        let root = invocation.currentDirectoryPath ?? states.keys.first { invocation.arguments.joined().contains($0 + "'") }
        if root == missingRoot {
            return .init(stdout: #"{"success":false,"error":"Storage not initialized. Run 'manna-core init' first."}"#,
                         stderr: "", exitCode: 1)
        }
        return .init(stdout: states[root ?? ""] ?? "invalid fixture root", stderr: "", exitCode: 0)
    }
}

private func linkState(root: String, includesItem: Bool = true, status: String = "open", kind: String = "item") throws -> String {
    var item: [String: Any] = ["id": "mn-abcdef", "title": "cited work", "status": status,
        "effective": status == "open" ? (kind == "dream" ? "dream" : "ready") : status,
        "kind": kind, "decision": false, "blocked_by": [], "blockers": [], "dependents": [], "commits": [],
        "prompt": ".handoff/cited.md", "handoff_digest": "sha256:synthetic", "handoff_exists": true]
    if status == "in_progress" { item["claimed_by"] = "other-worker" }
    let items = includesItem ? [item] : []
    return try linkJSON(["success": true, "generated_at": "now", "name": root, "root": root,
        "total": items.count, "counts": [:], "status_counts": [:],
        "now": status == "in_progress" ? items : [], "next": status == "open" && kind == "item" ? items : [],
        "dreams": kind == "dream" ? items : [], "waves": [], "decisions": [], "tracks": [], "peers": [],
        "attention": [:], "coord": [:], "board": [:], "all": items,
        "drift": ["present": false, "count": 0, "kinds": [:], "findings": []],
        "git": ["dirty_paths": 0, "is_repo": true]])
}

private func linkEstate(roots: [String]) throws -> String {
    let boards: [[String: Any]] = roots.map { root in
        ["name": root, "root": root, "exists": true, "total": 1, "status_counts": [:], "dreams": 0,
         "decisions": 0, "drift_count": 0, "slug": root, "url": "manna://board",
         "coord": ["attention": [:], "needs_you": 0, "working": 0, "here": 0, "gone": 0]]
    }
    return try linkJSON(["generated_at": "now", "boards": boards, "count": boards.count,
                         "registry": "synthetic", "building": 0, "totals": ["needs_you": 0, "working": 0, "here": 0]])
}

private func linkJSON(_ value: [String: Any]) throws -> String {
    try #require(String(bytes: JSONSerialization.data(withJSONObject: value), encoding: .utf8))
}

@MainActor private func linkStore(
    client: HolyMannaBoardClient,
    launcher: (@MainActor (HolySessionLaunchSpec) throws -> UUID)? = nil
) -> HolyMannaBoardModeStore {
    HolyMannaBoardModeStore(client: client, workerLauncher: launcher,
                           workerExecutableResolver: .init { _, _ in "/synthetic/codex" }, prewarmer: LinkPrewarmer())
}

@MainActor private func linkSettled(_ store: HolyMannaBoardModeStore) async throws {
    for _ in 0..<200 where store.isResolvingItemLink { try await Task.sleep(for: .milliseconds(5)) }
    try #require(!store.isResolvingItemLink)
}

@MainActor private func verifySearch(client: HolyMannaBoardClient) async {
    let store = linkStore(client: client)
    store.openItemLink("mn-abcdef", from: linkOrigin)
    try? await linkSettled(store)
    #expect(store.grep == "mn-abcdef" && store.grepFocusRequest > 0)
    #expect(store.selectedItem == nil && store.pendingDispatch == nil && store.pendingMutation == nil)
    #expect(store.dispatchNotice != nil)
    store.dismiss()
}

private struct LinkPrewarmer: HolyMannaBoardPrewarming {
    func enqueueFocused(_ payload: HolyMannaStatePayload, context: HolyMannaBoardContext,
                        allowGeneration: Bool, usageGuardReason: String?, sink: @escaping HolyMannaWarmSink) async {}
    func enqueueEstate(_ payload: HolyMannaEstatePayload, baseContext: HolyMannaBoardContext,
                       focusedRoot: String?, allowGeneration: Bool, usageGuardReason: String?, sink: @escaping HolyMannaWarmSink) async {}
    func waitUntilIdle() async {}
}
