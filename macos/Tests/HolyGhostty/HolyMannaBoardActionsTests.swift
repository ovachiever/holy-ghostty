import Foundation
import Testing
@testable import Ghostty

struct HolyMannaBoardActionsTests {
    @Test(arguments: [HolySessionRuntime.codex, .claude])
    func runtimeLookupIsSharedAndScopedToExecutionHost(runtime: HolySessionRuntime) async throws {
        let calls = ActionCalls()
        let resolver = HolyMannaWorkerExecutableResolver { runtime, host in
            await calls.record("\(host ?? "local")/\(runtime.rawValue)")
            try await Task.sleep(for: .milliseconds(40))
            return "/\(host ?? "local")/bin/\(runtime.rawValue)"
        }
        try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<16 {
                group.addTask { try await resolver.binaryPath(runtime: runtime, remoteHost: nil) }
            }
            for try await path in group { #expect(path == "/local/bin/\(runtime.rawValue)") }
        }
        #expect(try await resolver.binaryPath(runtime: runtime, remoteHost: "builder") == "/builder/bin/\(runtime.rawValue)")
        #expect(try await resolver.binaryPath(runtime: runtime, remoteHost: nil) == "/local/bin/\(runtime.rawValue)")
        #expect(await calls.values.count == 2)
    }

    @Test(arguments: [HolySessionRuntime.codex, .claude]) @MainActor
    func missingRuntimeRefusesBeforeSpawnOrClaim(runtime: HolySessionRuntime) async throws {
        let calls = ActionCalls()
        let probes = ActionCalls()
        var spawns = 0
        let resolver = HolyMannaWorkerExecutableResolver { runtime, _ in
            await probes.record(runtime.rawValue)
            return nil
        }
        let store = makeStore(calls: calls, resolver: resolver, launcher: { _ in spawns += 1; return UUID() })
        store.workerRuntime = runtime
        store.prepare(context: context)
        try await requireBoardLoaded(store)
        for _ in 0..<2 {
            store.requestWorker(try item())
            store.confirmWorker()
            try await eventually { !store.isDispatching }
            #expect(store.dispatchNotice?.contains("The \(runtime.rawValue) executable was not found on this Mac") == true)
        }
        #expect(spawns == 0)
        #expect(await probes.values == [runtime.rawValue])
        #expect(store.state?.item(id: "mn-123456")?.status == "open")
        #expect(await calls.values.allSatisfy { $0.contains("manna state") || $0.contains("manna estate") })
        do {
            _ = try await resolver.binaryPath(runtime: runtime, remoteHost: nil)
            Issue.record("Missing runtime unexpectedly resolved")
        } catch {
            #expect(error as? HolyMannaWorkerLaunchError == .runtimeMissing(runtime, host: nil))
        }
        store.dismiss()
    }

    @Test @MainActor func confirmedWorkerReceivesResolvedRuntimeAndFullMannaNote() async throws {
        var launched: HolySessionLaunchSpec?
        let store = makeStore(calls: ActionCalls(), launcher: { launched = $0; return UUID() })
        store.workerRuntime = .codex
        store.prepare(context: context)
        try await requireBoardLoaded(store)
        store.requestWorker(try item())
        #expect(launched == nil)
        store.confirmWorker()
        try await eventually { !store.isDispatching }
        let spec = try #require(launched)
        #expect(spec.command?.contains("'/synthetic/codex'") == true)
        #expect(spec.note == "mn-123456")
        #expect(spec.noteUpdatedAtMilliseconds != nil)
        #expect(spec.initialInput == nil)
        #expect(spec.title == "board")
        store.dismiss()
    }

    @Test func relativeOrMalformedRuntimePathsCannotBecomeLaunchCommands() throws {
        let request = HolyMannaWorkerDispatch(item: try item(), context: context, profile: .init())
        for path in ["codex", "./codex", "/bin/codex\nextra", "/bin/codex\u{0}"] {
            #expect(throws: HolyMannaWorkerLaunchError.runtimeMissing(.codex, host: nil)) {
                try request.launchSpec(executablePath: path)
            }
        }
    }

    @Test(arguments: [HolySessionRuntime.codex, .claude])
    func probeRunsOnRequestedHostAndRejectsInvalidSSH(runtime: HolySessionRuntime) throws {
        let local = try HolyMannaWorkerExecutableResolver.probeInvocation(runtime: runtime, remoteHost: nil)
        #expect(local.executablePath == "/bin/zsh")
        #expect(local.arguments.first == "-lc")
        #expect(local.arguments.last?.contains("command -v \(runtime.rawValue)") == true)
        let remote = try HolyMannaWorkerExecutableResolver.probeInvocation(runtime: runtime, remoteHost: "worker@example.com")
        // Holy's SSH manager executes a local admission/control wrapper. Its
        // local control-socket path is distinct from the remote tool lookup.
        #expect(remote.executablePath == "/bin/zsh")
        let wrapper = try #require(remote.arguments.last)
        #expect(wrapper.contains("worker@example.com"))
        #expect(wrapper.contains("ProxyCommand=/usr/bin/false"))
        #expect(wrapper.contains("/bin/zsh -lc"))
        #expect(wrapper.contains("$HOME"))
        let localHome = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(!wrapper.contains(localHome + "/.nvm"))
        #expect(!wrapper.contains(localHome + "/.local/bin"))
        #expect(throws: (any Error).self) {
            try HolyMannaWorkerExecutableResolver.probeInvocation(runtime: runtime, remoteHost: "-oProxyCommand=bad")
        }
    }

    @Test(arguments: [HolySessionRuntime.codex, .claude])
    func fallbackFindsOlderNvmRuntimeAndLaunchWorksWithBareSystemPath(runtime: HolySessionRuntime) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("holy-worker-'\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appendingPathComponent(".nvm/versions/node/v22.16.0/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".nvm/versions/node/v24.19.0/bin"),
                                                withIntermediateDirectories: true)
        // A provider shim with an env shebang, like the installed npm Codex.
        let executable = bin.appendingPathComponent(runtime.rawValue)
        try "#!/usr/bin/env holy-worker-interpreter\n".write(to: executable, atomically: true, encoding: .utf8)
        let interpreter = bin.appendingPathComponent("holy-worker-interpreter")
        try "#!/bin/sh\nprintf '%s\\n' \"$@\"\n".write(to: interpreter, atomically: true, encoding: .utf8)
        for file in [executable, interpreter] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        let script = HolyMannaWorkerExecutableResolver.probeScript(runtime: runtime)
        // Disable user rc files only for this fixture, so the real machine's
        // installations cannot hide the fallback regression.
        let output = try await actionShell(script, shell: "/bin/zsh", flags: ["-f", "-c"],
                                           environment: ["HOME": root.path, "PATH": "/usr/bin:/bin"])
        #expect(output.exitCode == 0)
        #expect(output.stdout == "HOLY_WORKER_EXECUTABLE=\(executable.path)\n")
        let request = HolyMannaWorkerDispatch(item: try item(), context: context,
                                            profile: .init(runtime: runtime, model: "model'$(touch forbidden)"))
        let spec = try request.launchSpec(executablePath: executable.path)
        let launched = try await actionShell(try #require(spec.command), environment: ["PATH": "/usr/bin:/bin"])
        #expect(launched.exitCode == 0)
        #expect(launched.stdout == "\(executable.path)\n--model\nmodel'$(touch forbidden)\n--\n\(request.brief)\n")
        #expect(launched.stderr.isEmpty)
    }

    @Test func dispatchNoteSurvivesTmuxDetachDiscoveryAndReadoption() async throws {
        let request = HolyMannaWorkerDispatch(item: try item(), context: context, profile: .init())
        var spec = try request.launchSpec(executablePath: "/usr/bin/true")
        let socket = "holy-worker-test-\(UUID().uuidString.lowercased())"
        let name = try #require(spec.tmux?.sessionName)
        spec.tmux?.socketName = socket
        spec.workingDirectory = FileManager.default.temporaryDirectory.path
        let command = try #require(HolyTmuxCommandBuilder.detachedCreateCommand(for: spec))
        let created = try await HolyMannaProcessRunner.run(.init(
            executablePath: command.executablePath, arguments: command.arguments,
            currentDirectoryPath: nil, environment: [:], stdin: nil, displayCommand: "create isolated note test"
        ), 10)
        defer {
            let cleanup = Process()
            cleanup.executableURL = URL(fileURLWithPath: "/bin/zsh")
            cleanup.arguments = ["-lc", "tmux -L '\(socket)' kill-server"]
            cleanup.standardOutput = FileHandle.nullDevice
            cleanup.standardError = FileHandle.nullDevice
            try? cleanup.run()
            cleanup.waitUntilExit()
        }
        #expect(created.exitCode == 0, Comment(rawValue: created.stderr))
        // No viewer is attached. Discovery must still recover the initial note
        // from the server, before any later local note edit or sync poll.
        let discovered = try await HolyRemoteTmuxDiscoveryService.shared.discoverLocalSessionsThrowing(
            hostID: UUID(), hostLabel: "Test", tmuxSocketName: socket, timeout: 5, includeHiddenSessions: true
        )
        let live = try #require(discovered.first { $0.sessionName == name })
        #expect(live.synchronizedMetadata.note?.value == "mn-123456")
        #expect(live.synchronizedMetadata.note?.updatedAtMilliseconds == spec.noteUpdatedAtMilliseconds)
        let action = HolyTmuxSessionMetadataMerge.action(
            local: .init(value: Optional<String>.none, updatedAtMilliseconds: nil, isPresent: false),
            remote: live.synchronizedMetadata.note
        )
        #expect(action == .applyRemote(value: "mn-123456", updatedAtMilliseconds: try #require(spec.noteUpdatedAtMilliseconds)))
        let record = HolySessionRecord(launchSpec: spec)
        let archived = HolyArchivedSession(sourceSessionID: record.id, record: record, phase: .completed,
            preview: "", signals: [], commandTelemetry: .empty, budgetTelemetry: .empty, runtimeTelemetry: .empty,
            gitSnapshot: nil, lastKnownWorkingDirectory: nil, lastActivityAt: .now, archivedAt: .now)
        var reattach = spec
        reattach.tmux?.createIfMissing = false
        reattach.note = nil
        let readopted = HolySessionSupervisor.readoptedRecordForTesting(archived, launchSpec: reattach, updatedAt: .now)
        #expect(readopted.id == record.id)
        #expect(readopted.launchSpec.note == "mn-123456")
        #expect(readopted.launchSpec.noteUpdatedAtMilliseconds == spec.noteUpdatedAtMilliseconds)

        var edited = spec
        edited.note = "mn-123456: human follow-up"
        edited.noteUpdatedAtMilliseconds = (try #require(spec.noteUpdatedAtMilliseconds)) + 1
        let payload = try #require(HolyTmuxSessionMetadataPayload(launchSpec: edited))
        let update = try #require(HolyTmuxSessionMetadataUpdateCommand.command(for: edited, payload: payload))
        #expect(update.run())
        // Running the original create-if-missing spec again must not replace
        // a later user edit with the initial ticket-only note.
        let repeated = try await HolyMannaProcessRunner.run(.init(
            executablePath: command.executablePath, arguments: command.arguments,
            currentDirectoryPath: nil, environment: [:], stdin: nil, displayCommand: "reopen isolated note test"
        ), 10)
        #expect(repeated.exitCode == 0)
        let notes = try await actionShell("tmux -L '\(socket)' show-options -qv -t '\(name)' @holy_note_v1",
                                          shell: "/bin/zsh", flags: ["-lc"])
        #expect(HolyTmuxSessionMetadataCodec.decodeNote(notes.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
                == .value(edited.note))
    }

    @Test func concurrentBinaryLookupWaitsForTheSameSuccessfulProbe() async {
        await checkConcurrentLookup(result: "/synthetic/agent-do")
    }

    @Test func concurrentBinaryLookupDoesNotReportMissingBeforeProbeFinishes() async {
        await checkConcurrentLookup(result: nil)
    }

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
        try await requireBoardLoaded(store)
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
        try await requireBoardLoaded(store)
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
        try await requireBoardLoaded(store)
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
        #expect(throws: (any Error).self) { try request.launchSpec(executablePath: "/synthetic/codex") }
    }

    @Test func workerBriefPinsProtocolAndArrivesAsOneStartupArgument() throws {
        let request = HolyMannaWorkerDispatch(item: try item(), context: context,
                                            profile: .init(runtime: .codex, model: "model'$(touch forbidden)"))
        let spec = try request.launchSpec(executablePath: "/synthetic/codex")
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
        #expect(spec.command?.contains("'/synthetic/codex' '--model' 'model'\\''$(touch forbidden)' '--' '") == true)
        #expect(spec.command?.contains("First run: agent-do manna claim") == true)
        #expect(spec.tmux?.sessionName != (try request.launchSpec(executablePath: "/synthetic/codex")).tmux?.sessionName)
        let remote = HolyMannaWorkerDispatch(item: try item(),
            context: .init(boardRoot: "/srv/board", remoteHost: "builder@example.com"),
            profile: .init(runtime: .claude, model: "opus"))
        #expect(try remote.launchSpec(executablePath: "/remote/claude").transport.sshDestination == "builder@example.com")
        #expect(try remote.launchSpec(executablePath: "/remote/claude").initialInput == nil)
    }

    @Test @MainActor func failedSpawnNeverClaimsAndConfirmationIsRequired() async throws {
        let calls = ActionCalls()
        var spawns = 0
        let store = makeStore(calls: calls, launcher: { _ in
            spawns += 1
            throw HolyMannaAskError.unavailable("synthetic spawn failure")
        })
        store.prepare(context: context)
        try await requireBoardLoaded(store)
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
        }, workerExecutableResolver: fixtureWorkerResolver(), prewarmer: ActionPrewarmer())
        store.prepare(context: context)
        try await requireBoardLoaded(store)
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

private func actionShell(_ script: String, shell: String = "/bin/sh", flags: [String] = ["-c"],
                         environment: [String: String] = [:]) async throws -> HolyMannaProcessOutput {
    try await HolyMannaProcessRunner.run(.init(executablePath: shell, arguments: flags + [script],
        currentDirectoryPath: nil, environment: environment, stdin: nil, displayCommand: "worker shell regression"), 10)
}

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

private func fixtureWorkerResolver() -> HolyMannaWorkerExecutableResolver {
    .init { runtime, host in "/\(host ?? "synthetic")/\(runtime.rawValue)" }
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

@MainActor private func makeStore(
    calls: ActionCalls,
    asker: any HolyMannaBoardAsking = HolyMannaBoardAskService { _ in "answer" },
    timeout: Duration = .seconds(60),
    resolver: HolyMannaWorkerExecutableResolver = fixtureWorkerResolver(),
    launcher: (@MainActor (HolySessionLaunchSpec) throws -> UUID)? = nil
) -> HolyMannaBoardModeStore {
    HolyMannaBoardModeStore(client: fixtureClient(calls: calls), asker: asker, askTimeout: timeout,
                           workerLauncher: launcher, workerExecutableResolver: resolver, prewarmer: ActionPrewarmer())
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
    try #require(predicate(), "Synthetic operation did not settle")
}

@MainActor private func requireBoardLoaded(_ store: HolyMannaBoardModeStore) async throws {
    try await eventually { store.state != nil || store.boardFailure != nil }
    try #require(store.boardFailure == nil, Comment(rawValue: store.boardFailure ?? "Board read completed"))
    _ = try #require(store.state)
}

private actor DelayedExecutableProbe {
    private(set) var calls = 0
    private(set) var finished = false

    func resolve(_ result: String?) async -> String? {
        calls += 1
        // Keep the I/O boundary suspended so the other callers reenter the resolver.
        try? await Task.sleep(for: .milliseconds(50))
        finished = true
        return result
    }
}

private func checkConcurrentLookup(result: String?) async {
    let probe = DelayedExecutableProbe()
    let resolver = HolyBoardExecutableResolver { await probe.resolve(result) }
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<16 {
            group.addTask {
                let path = await resolver.binaryPath()
                #expect(await probe.finished, "A pending lookup must never appear to be a missing executable")
                #expect(path == result)
            }
        }
    }
    #expect(await resolver.binaryPath() == result)
    #expect(await probe.calls == 1)
}
