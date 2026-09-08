import Foundation
import Testing
@testable import Ghostty

struct HolyMannaBoardActionsTests {
    @Test func honestyLawMatchesWebAndCitationsOnlyUseSuppliedRows() throws {
        #expect(HolyMannaBoardQuestion.system == "You answer questions about a software project board using only the rows you are given. Read every row before answering, including rows marked done: a done item that covers the question means the board covers it and the work is finished; say which state each cited item is in. Cite the item id (mn-xxxxxx) inline for every item you mention, and never cite an id that is not in the rows. If nothing on the board covers the question, say so plainly. Two short paragraphs at most; no headings, no bullet lists, no preamble.")
        let request = try fixtureQuestion()
        let result = HolyMannaBoardAnswer.validated(
            "Done: mn-abcdef. Unknown: mn-ffffff. Ready: mn-123456. Again mn-abcdef.", for: request
        )
        #expect(result.citedIDs == ["mn-abcdef", "mn-123456"])
        #expect(!result.text.contains("mn-ffffff"))
        #expect(request.rows.contains("done"))
        #expect(request.allowedIDs == ["mn-123456", "mn-abcdef"])
    }

    @Test func cacheIgnoresReadTimestampButInvalidatesOnContentAndModel() async throws {
        let calls = ActionCalls()
        let service = HolyMannaBoardAskService { _ in
            await calls.record("model")
            return "mn-123456 is ready."
        }
        let first = try await service.answer(fixtureQuestion())
        let repeated = try await service.answer(fixtureQuestion(timestamp: "later", question: "  what\n is ready?  "))
        #expect(!first.wasCached)
        #expect(repeated.wasCached)
        _ = try await service.answer(fixtureQuestion(title: "Different work"))
        _ = try await service.answer(fixtureQuestion(model: "gpt-5.6"))
        #expect(await calls.values.count == 3)
    }

    @Test @MainActor func typingGrepsAndOnlyEnterAsksThenCitationsSelectBoardRows() async throws {
        let calls = ActionCalls()
        let store = makeStore(calls: calls, asker: HolyMannaBoardAskService { _ in
            await calls.record("model")
            return "mn-abcdef is done."
        })
        store.prepare(context: context)
        try await eventually { store.state != nil }
        store.grep = "ready"
        #expect(!store.isAsking)
        #expect(await calls.values.allSatisfy { $0 != "model" })
        #expect(store.boardSections.flatMap(\.items).allSatisfy { $0.title.contains("ready") })
        store.grep = "what is ready?"
        store.submitQuestion()
        try await eventually { store.answer != nil }
        #expect(store.boardSections.first?.id == "cited")
        #expect(store.boardSections.first?.items.map(\.id) == ["mn-abcdef"])
        store.selectItem("mn-abcdef")
        #expect(store.selectedItem?.status == "done")
        #expect(store.answer != nil)
        store.grep = "changed"
        #expect(store.answer == nil)
        #expect(await calls.values.filter { $0 == "model" }.count == 1)
        #expect(await calls.values.allSatisfy { !$0.contains("manna claim") })
        store.dismiss()
    }

    @Test @MainActor func timeoutIsTypedAndLateAnswerCannotOverwriteIt() async throws {
        let store = makeStore(calls: ActionCalls(), asker: SlowAnswer(), timeout: .milliseconds(5))
        store.prepare(context: context)
        try await eventually { store.state != nil }
        store.grep = "question"
        store.submitQuestion()
        try await eventually { store.askFailure != nil }
        #expect(store.askFailure == .timedOut)
        #expect(store.askFailure?.localizedDescription.contains("60 seconds") == true)
        try await Task.sleep(for: .milliseconds(70))
        #expect(store.askFailure == .timedOut)
        #expect(store.answer == nil)
        #expect(!store.isAsking)
        store.dismiss()
    }

    @Test @MainActor func boardChangeCancelsAnswer() async throws {
        let store = makeStore(calls: ActionCalls(), asker: SlowAnswer())
        store.prepare(context: context)
        try await eventually { store.state != nil }
        store.grep = "question"
        store.submitQuestion()
        store.prepare(context: .init(boardRoot: nil, remoteHost: nil))
        try await Task.sleep(for: .milliseconds(70))
        #expect(store.answer == nil)
        #expect(!store.isAsking)
        store.dismiss()
    }

    @Test func dreamsAndClaimsAreRefusedWithReasons() throws {
        let dream = try item(kind: "dream")
        #expect(HolyMannaWorkerDispatch.refusal(for: dream, context: context)?.contains("Dreams") == true)
        let claimed = try item(status: "in_progress", claimant: "codex-owner")
        #expect(HolyMannaWorkerDispatch.refusal(for: claimed, context: context)?.contains("codex-owner") == true)
        #expect(HolyMannaWorkerDispatch.refusal(for: try item(), context: context) == nil)
        let request = HolyMannaWorkerDispatch(item: dream, context: context, profile: .init())
        #expect(throws: (any Error).self) { try request.launchSpec() }
    }

    @Test func workerBriefPinsProtocolAndArrivesAsOneStartupArgument() throws {
        let request = HolyMannaWorkerDispatch(item: try item(), context: context,
                                            profile: .init(runtime: .codex, model: "model'$(touch forbidden)"))
        let spec = try request.launchSpec()
        for clause in ["First run: agent-do manna claim mn-123456", "sealed handoff at .handoff/work.md",
                       "agent-do coord focus", "path claims", "focused test suites only",
                       "keep the tree buildable", "No app launches, installs, screenshots",
                       "App-hosted tests may be built", "Coordinate the live/visual acceptance",
                       "Manna: mn-123456", "Never push", "Lessons logged: N (new) | Decisions logged: N (new)"] {
            #expect(request.brief.contains(clause))
        }
        #expect(spec.initialInput == nil)
        #expect(spec.workingDirectory == context.boardRoot)
        #expect(spec.runtime == .codex)
        #expect(spec.title == "board")
        #expect(spec.command?.hasPrefix("'codex' '--model' 'model'\\''$(touch forbidden)' '--' '") == true)
        #expect(spec.command?.contains("First run: agent-do manna claim") == true)
        #expect(spec.tmux?.sessionName != (try request.launchSpec()).tmux?.sessionName)
        let remote = HolyMannaWorkerDispatch(item: try item(),
            context: .init(boardRoot: "/srv/board", remoteHost: "builder@example.com"),
            profile: .init(runtime: .claude, model: "opus"))
        #expect(try remote.launchSpec().transport.sshDestination == "builder@example.com")
        #expect(try remote.launchSpec().initialInput == nil)
    }

    @Test @MainActor func failedSpawnNeverClaimsAndConfirmationIsRequired() async throws {
        let calls = ActionCalls()
        var spawns = 0
        let store = makeStore(calls: calls, launcher: { _ in
            spawns += 1
            throw HolyMannaAskError.unavailable("synthetic spawn failure")
        })
        store.prepare(context: context)
        try await eventually { store.state != nil }
        store.requestWorker(try item())
        #expect(store.pendingDispatch != nil)
        #expect(spawns == 0)
        #expect(store.state?.item(id: "mn-123456")?.status == "open")
        store.confirmWorker()
        try await eventually { store.dispatchNotice != nil }
        #expect(spawns == 1)
        #expect(store.dispatchNotice?.contains("synthetic spawn failure") == true)
        #expect(store.state?.item(id: "mn-123456")?.status == "open")
        #expect(await calls.values.allSatisfy { $0.contains("manna state") || $0.contains("manna estate") })
        #expect(store.workerRefusal(for: try item()) == nil)
        store.dismiss()
    }

    @Test @MainActor func claimWonByAnotherWorkerDuringConfirmationPreventsSpawn() async throws {
        let calls = ActionCalls()
        let client = fixtureClient(calls: calls, claimAfterFirstRead: true)
        var spawns = 0
        let store = HolyMannaBoardModeStore(client: client, workerLauncher: { _ in
            spawns += 1
            return UUID()
        }, prewarmer: ActionPrewarmer())
        store.prepare(context: context)
        try await eventually { store.state != nil }
        store.requestWorker(try item())
        store.confirmWorker()
        try await eventually { store.dispatchNotice != nil }
        #expect(spawns == 0)
        #expect(store.dispatchNotice?.contains("codex-owner") == true)
        #expect(await calls.values.allSatisfy { !$0.contains("manna claim") })
        store.dismiss()
    }
}

private let context = HolyMannaBoardContext(boardRoot: "/synthetic/board", remoteHost: nil)

private func itemJSON(id: String = "mn-123456", title: String = "ready work", kind: String = "item",
                      status: String = "open", claimant: String? = nil) -> [String: Any] {
    var value: [String: Any] = ["id": id, "title": title, "title_plain": title, "status": status,
        "effective": status == "open" ? "ready" : status, "kind": kind, "decision": false,
        "blocked_by": [], "blockers": [], "dependents": [], "commits": [],
        "prompt": ".handoff/work.md", "handoff_digest": "sha256:synthetic", "handoff_exists": true]
    value["claimed_by"] = claimant
    return value
}

private func item(kind: String = "item", status: String = "open", claimant: String? = nil) throws -> HolyMannaBoardItem {
    try JSONDecoder().decode(HolyMannaBoardItem.self, from: JSONSerialization.data(
        withJSONObject: itemJSON(kind: kind, status: status, claimant: claimant)))
}

private func stateJSON(timestamp: String = "now", title: String = "ready work", claimed: Bool = false) throws -> String {
    let ready = itemJSON(title: title, status: claimed ? "in_progress" : "open", claimant: claimed ? "codex-owner" : nil)
    let done = itemJSON(id: "mn-abcdef", title: "finished work", status: "done")
    let value: [String: Any] = ["success": true, "generated_at": timestamp, "name": "board", "root": context.boardRoot!,
        "total": 2, "counts": [:], "status_counts": [:], "now": [], "next": [ready], "waves": [],
        "dreams": [], "decisions": [], "tracks": [], "peers": [], "attention": [:], "coord": [:],
        "drift": ["present": false, "count": 0, "kinds": [:], "findings": []],
        "git": ["dirty_paths": 0, "is_repo": true], "board": [:], "all": [ready, done]]
    return String(bytes: try JSONSerialization.data(withJSONObject: value), encoding: .utf8)!
}

private func fixtureQuestion(timestamp: String = "now", title: String = "ready work",
                             question: String = "what is ready?", model: String = "opus") throws -> HolyMannaBoardQuestion {
    let state = try JSONDecoder().decode(HolyMannaStatePayload.self, from: Data(stateJSON(timestamp: timestamp, title: title).utf8))
    return try .init(question: question, state: state, context: context, model: model)
}

private actor ActionCalls {
    var values: [String] = []
    func record(_ value: String) { values.append(value) }
    func stateReadCount() -> Int { values.filter { $0.contains("manna state") }.count }
}

private func fixtureClient(calls: ActionCalls, claimAfterFirstRead: Bool = false) -> HolyMannaBoardClient {
    let identity = HolyMannaActorIdentityStore(fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("holy-board-actions-\(UUID()).json"))
    return HolyMannaBoardClient(identityStore: identity) { invocation, _ in
        await calls.record(invocation.displayCommand)
        if invocation.displayCommand.contains("estate") {
            throw HolyMannaAskError.unavailable("No synthetic estate")
        }
        let reads = await calls.stateReadCount()
        return .init(stdout: try stateJSON(claimed: claimAfterFirstRead && reads > 1), stderr: "", exitCode: 0)
    }
}

@MainActor private func makeStore(calls: ActionCalls,
                                 asker: any HolyMannaBoardAsking = HolyMannaBoardAskService { _ in "answer" },
                                 timeout: Duration = .seconds(60),
                                 launcher: (@MainActor (HolySessionLaunchSpec) throws -> UUID)? = nil) -> HolyMannaBoardModeStore {
    HolyMannaBoardModeStore(client: fixtureClient(calls: calls), asker: asker, askTimeout: timeout,
                           workerLauncher: launcher, prewarmer: ActionPrewarmer())
}

private struct ActionPrewarmer: HolyMannaBoardPrewarming {
    func enqueueFocused(_ payload: HolyMannaStatePayload, context: HolyMannaBoardContext,
                        allowGeneration: Bool, usageGuardReason: String?, sink: @escaping HolyMannaWarmSink) async {}
    func enqueueEstate(_ payload: HolyMannaEstatePayload, baseContext: HolyMannaBoardContext,
                       focusedRoot: String?, allowGeneration: Bool, usageGuardReason: String?, sink: @escaping HolyMannaWarmSink) async {}
    func waitUntilIdle() async {}
}

private struct SlowAnswer: HolyMannaBoardAsking {
    func answer(_ request: HolyMannaBoardQuestion) async throws -> HolyMannaBoardAnswer {
        // Deliberately finishes after cancellation to exercise the store's generation guard.
        try? await Task.sleep(for: .milliseconds(50))
        return .validated("mn-123456", for: request)
    }
}

@MainActor private func eventually(_ predicate: () -> Bool) async throws {
    for _ in 0..<200 {
        if predicate() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Synthetic operation did not settle")
}
