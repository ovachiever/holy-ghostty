import Foundation
import Testing
@testable import Ghostty

struct HolyMannaBoardTests {
    @Test func canonicalStateAndEstateContractsDecodeWithoutLegacyList() async throws {
        let recorder = HolyMannaInvocationRecorder()
        let client = HolyMannaBoardClient { invocation, _ in
            await recorder.append(invocation)
            let payload = invocation.displayCommand.contains("estate")
                ? HolyMannaBoardFixtures.estate
                : HolyMannaBoardFixtures.state
            return .init(stdout: payload, stderr: "", exitCode: 0)
        }
        let context = HolyMannaBoardContext(
            boardRoot: "/srv/holy-ghostty",
            remoteHost: "builder@example.com"
        )

        let state = try await client.state(for: context)
        let estate = try await client.estate(for: context)
        let invocations = await recorder.values

        #expect(state.name == "holy-ghostty")
        #expect(state.now.map(\.id) == ["mn-live001"])
        #expect(state.coord.drops.first?.paths == [".handoff/live.md"])
        #expect(state.asks.map(\.verb) == ["grant", "close", "read"])
        #expect(state.asks.first?.detail == "“Approve the final action”")
        #expect(estate.boards.first?.needsYou == 1)
        #expect(estate.totals.needsYou == 1)
        #expect(invocations.count == 2)
        #expect(invocations[0].displayCommand == "builder@example.com: agent-do manna state --json")
        #expect(invocations[1].displayCommand == "builder@example.com: agent-do manna estate --json")
        #expect(invocations.allSatisfy { !$0.displayCommand.contains("manna list") })
    }

    @Test func remoteHostCannotSmuggleSSHFlags() throws {
        let context = HolyMannaBoardContext(
            boardRoot: "/srv/holy-ghostty",
            remoteHost: "builder@[2001:db8::1]"
        )
        let invocation = try HolyMannaBoardClient.remoteInvocation(
            arguments: ["manna", "state", "--json"],
            context: context,
            needsBoardRoot: true,
            identity: nil
        )

        let wrapper = try #require(invocation.arguments.last)
        #expect(invocation.executablePath == "/bin/zsh")
        #expect(wrapper.contains("'/usr/bin/ssh'"))
        #expect(wrapper.contains("zsystem flock -e"))
        #expect(wrapper.contains("holy_ssh_error_file="))
        #expect(wrapper.components(separatedBy: "'ControlMaster=no'").count == 2)
        #expect(wrapper.contains("'--' 'builder@[2001:db8::1]'"))

        #expect(throws: HolyMannaBoardClientError.launchFailed("invalid remote host")) {
            _ = try HolyMannaBoardClient.remoteInvocation(
                arguments: ["manna", "state", "--json"],
                context: .init(
                    boardRoot: "/srv/holy-ghostty",
                    remoteHost: "-oProxyCommand=touch /tmp/pwned"
                ),
                needsBoardRoot: true,
                identity: nil
            )
        }
    }

    @Test func remoteMutationsUseHolyProofOnStdinAndNeverRetry() async throws {
        let directory = try temporaryDirectory(named: "holy-board-identity")
        defer { try? FileManager.default.removeItem(at: directory) }
        let identityStore = HolyMannaActorIdentityStore(
            fileURL: directory.appendingPathComponent("manna-actor.json")
        )
        let identity = try await identityStore.identity()
        let recorder = HolyMannaInvocationRecorder()
        let client = HolyMannaBoardClient(identityStore: identityStore) { invocation, _ in
            await recorder.append(invocation)
            return .init(stdout: "{\"success\":true}\n", stderr: "", exitCode: 0)
        }

        let receipts = try await client.perform(
            .close("mn-live001"),
            in: .init(boardRoot: "/srv/holy-ghostty", remoteHost: "builder@example.com")
        )
        let invocations = await recorder.values

        #expect(receipts.count == 2)
        #expect(invocations.count == 2)
        #expect(invocations[0].stdin.flatMap { String(bytes: $0, encoding: .utf8) }?.contains(identity.token) == true)
        #expect(invocations[1].stdin.flatMap { String(bytes: $0, encoding: .utf8) }?.contains(identity.token) == true)
        #expect(invocations.allSatisfy { !$0.arguments.joined().contains(identity.token) })
        #expect(invocations.allSatisfy { !$0.displayCommand.contains(identity.token) })
        #expect(
            invocations[0].stdin
                .flatMap { String(bytes: $0, encoding: .utf8) }?
                .contains("'manna' 'claim' 'mn-live001'") == true
        )
        #expect(
            invocations[1].stdin
                .flatMap { String(bytes: $0, encoding: .utf8) }?
                .contains("'manna' 'done' 'mn-live001'") == true
        )
    }

    @Test func holyActorIdentityIsStableAndPrivate() async throws {
        let directory = try temporaryDirectory(named: "holy-board-identity")
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("manna-actor.json")
        let firstStore = HolyMannaActorIdentityStore(fileURL: fileURL)
        let secondStore = HolyMannaActorIdentityStore(fileURL: fileURL)

        let first = try await firstStore.identity()
        let second = try await secondStore.identity()
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)

        #expect(first == second)
        #expect(first.isValid)
        #expect(attributes[.posixPermissions] as? Int == 0o600)
        #expect(!(try String(contentsOf: fileURL, encoding: .utf8)).contains("CODEX_THREAD_ID"))
    }

    @Test func attentionBadgeDeduplicatesJoinedPeersButCountsIdentitylessSessions() {
        let count = HolyAttentionBadgeCounter.count(
            github: 2,
            boardAsks: 3,
            boardPeerIDs: ["codex-019f62805fc77093", "claude-aaaaaaaaaaaa"],
            sessionIDs: [
                "019f6280-5fc7-7093-a705-8d6f4916f911",
                "019f62805fc77093a7058d6f4916f911",
                nil,
            ]
        )

        // 2 GitHub + 1 non-peer Board ask + 1 joined harness + 1
        // identityless session + 1 unmatched peer. The compact duplicate is
        // the same harness identity, not a second demand on the human.
        #expect(count == 6)
    }

    @Test func digestHashChangesOnlyWhenMeaningfulItemContentChanges() throws {
        let first = try HolyMannaBoardFixtures.item(
            description: "Build the native Board.",
            blockerStatus: "open"
        )
        let same = try HolyMannaBoardFixtures.item(
            description: "Build the native Board.",
            blockerStatus: "open"
        )
        let changed = try HolyMannaBoardFixtures.item(
            description: "Build and verify the native Board.",
            blockerStatus: "open"
        )
        let blockerChanged = try HolyMannaBoardFixtures.item(
            description: "Build the native Board.",
            blockerStatus: "done"
        )

        #expect(HolyMannaBoardDigestService.contentHash(for: first).count == 64)
        #expect(HolyMannaBoardDigestService.contentHash(for: first) == HolyMannaBoardDigestService.contentHash(for: same))
        #expect(HolyMannaBoardDigestService.contentHash(for: first) != HolyMannaBoardDigestService.contentHash(for: changed))
        #expect(HolyMannaBoardDigestService.contentHash(for: first) != HolyMannaBoardDigestService.contentHash(for: blockerChanged))
    }

    @Test func presentationServicePrefersAttachmentsAndRegeneratesOnlyChangedContent() async throws {
        let directory = try temporaryDirectory(named: "holy-board-presentations")
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("holy.sqlite3")
        let database = try HolyDatabase.open(at: databaseURL)
        try HolyDatabaseMigrator.migrate(database)
        let completion = HolyMannaCompletionRecorder(responses: [
            #"{"items":[{"id":"mn-generated","digest":"Generate one shared line","summary":"Generate the missing explanation once, then keep it in the stable item slot."}]}"#,
            #"{"items":[{"id":"mn-generated","digest":"Regenerate the changed line","summary":"Only this changed item should ask the fast role for new presentation text."}]}"#,
        ])
        let service = HolyMannaBoardDigestService(databaseURL: databaseURL) { role, prompt, workingDirectory, timeout in
            await completion.complete(role: role, prompt: prompt, workingDirectory: workingDirectory, timeout: timeout)
        }
        let context = HolyMannaBoardContext(boardRoot: "/srv/presentation", remoteHost: nil)
        let attached = try HolyMannaBoardFixtures.item(
            id: "mn-attached",
            title: "Attached",
            description: "Already shared by canonical state.",
            digest: "Canonical shared line",
            summary: "Canonical shared summary"
        )
        let generated = try HolyMannaBoardFixtures.item(
            id: "mn-generated",
            title: "Generated",
            description: "Needs both fields."
        )

        let first = try await service.presentations(
            for: [attached, generated],
            context: context,
            allowGeneration: true
        )
        let firstCalls = await completion.calls
        #expect(first.count == 2)
        #expect(first[0].digest == "Canonical shared line")
        #expect(first[0].summary == "Canonical shared summary")
        #expect(first[0].wasCached)
        #expect(first[1].digest == "Generate one shared line")
        #expect(first[1].isComplete)
        #expect(firstCalls.count == 1)
        #expect(firstCalls[0].prompt.contains("mn-generated"))
        #expect(!firstCalls[0].prompt.contains("mn-attached"))
        #expect(firstCalls[0].workingDirectory == "/srv/presentation")
        #expect(firstCalls[0].timeout == 65, "Only the missing item contributes to the batch deadline")

        let second = try await service.presentations(
            for: [attached, generated],
            context: context,
            allowGeneration: true
        )
        #expect(second.map(\.isComplete) == [true, true])
        #expect(second.map(\.wasCached) == [true, true])
        #expect(await completion.calls.count == 1)

        let guarded = try HolyMannaBoardFixtures.item(
            id: "mn-guarded",
            title: "Guarded",
            description: "Wait for usage headroom."
        )
        let guardedResult = try await service.presentations(
            for: [guarded],
            context: context,
            allowGeneration: false
        )
        #expect(guardedResult.map(\.isComplete) == [false])
        #expect(await completion.calls.count == 1)

        let changed = try HolyMannaBoardFixtures.item(
            id: "mn-generated",
            title: "Generated",
            description: "Only this content changed."
        )
        let changedResult = try await service.presentations(
            for: [changed],
            context: context,
            allowGeneration: true,
            retryAttempt: 1
        )
        #expect(changedResult.first?.digest == "Regenerate the changed line")
        #expect(await completion.calls.count == 2)
        #expect(await completion.calls.last?.timeout == 130)
        #expect(
            try database.scalarInt64(
                "SELECT COUNT(*) FROM board_digest_cache WHERE role = 'fast';"
            ) == 2,
            "content changes overwrite the stable per-item slot instead of growing the cache"
        )
    }

    @Test @MainActor func fullDayEstateReplayWarmsFocusedFirstAndSkipsUnchangedBoards() async throws {
        let focusPayload = try JSONDecoder().decode(
            HolyMannaStatePayload.self,
            from: Data(HolyMannaBoardFixtures.state(itemCount: 25, root: "/srv/focus").utf8)
        )
        let estate = try JSONDecoder().decode(
            HolyMannaEstatePayload.self,
            from: Data(HolyMannaBoardFixtures.estateJSON(otherLatestUpdate: "2026-09-03T12:00:00Z").utf8)
        )
        let changedEstate = try JSONDecoder().decode(
            HolyMannaEstatePayload.self,
            from: Data(HolyMannaBoardFixtures.estateJSON(otherLatestUpdate: "2026-09-03T13:00:00Z").utf8)
        )
        let digestRecorder = HolyMannaDigestRecorder()
        let client = HolyMannaBoardClient { invocation, _ in
            let root = invocation.currentDirectoryPath ?? "/srv/other"
            return .init(
                stdout: HolyMannaBoardFixtures.state(itemCount: 1, root: root),
                stderr: "",
                exitCode: 0
            )
        }
        let delayRecorder = HolyMannaDelayRecorder()
        let pacer = HolyArchiveWritePacer(
            budget: .init(
                rowsPerTransaction: 12,
                foregroundRowsPerSecond: 1,
                backgroundRowsPerSecond: 100,
                checkpointEveryRows: 100,
                maximumPauseNanoseconds: 500_000_000
            ),
            isForeground: { true },
            sleep: { nanoseconds in await delayRecorder.append(nanoseconds) }
        )
        let warmer = HolyMannaBoardPrewarmer(
            client: client,
            digestService: digestRecorder,
            pacer: pacer
        )
        let context = HolyMannaBoardContext(boardRoot: "/srv/focus", remoteHost: nil)
        let sink: HolyMannaWarmSink = { _ in }

        await warmer.enqueueFocused(
            focusPayload,
            context: context,
            allowGeneration: true,
            usageGuardReason: nil,
            sink: sink
        )
        await warmer.enqueueEstate(
            estate,
            baseContext: context,
            focusedRoot: context.boardRoot,
            allowGeneration: true,
            usageGuardReason: nil,
            sink: sink
        )
        await warmer.waitUntilIdle()

        let firstBatches = await digestRecorder.batches
        #expect(firstBatches.map(\.count) == [12, 12, 1, 1])
        #expect(firstBatches.prefix(3).allSatisfy { $0.root == "/srv/focus" })
        #expect(firstBatches.last?.root == "/srv/other")
        #expect(await delayRecorder.values.count == 4)
        #expect(await delayRecorder.values.allSatisfy { $0 > 0 })

        // 144 unchanged estate refreshes model a ten-minute workday cadence.
        // They enqueue no board reads and therefore cannot create a writing
        // placeholder or pay generation twice.
        for _ in 0 ..< 144 {
            await warmer.enqueueEstate(
                estate,
                baseContext: context,
                focusedRoot: context.boardRoot,
                allowGeneration: true,
                usageGuardReason: nil,
                sink: sink
            )
        }
        await warmer.waitUntilIdle()
        #expect(await digestRecorder.batches.count == 4)

        await warmer.enqueueEstate(
            changedEstate,
            baseContext: context,
            focusedRoot: context.boardRoot,
            allowGeneration: true,
            usageGuardReason: nil,
            sink: sink
        )
        await warmer.waitUntilIdle()
        #expect(await digestRecorder.batches.count == 5)
        #expect(await digestRecorder.batches.last?.root == "/srv/other")
    }

    @Test @MainActor func backgroundBoardRefreshStartsWarmWithoutDelayingState() async throws {
        let directory = try temporaryDirectory(named: "holy-board-preload")
        defer { try? FileManager.default.removeItem(at: directory) }
        let generation = AsyncStream<Void>.makeStream()
        defer { generation.continuation.finish() }
        let digestRecorder = HolyMannaDigestRecorder(beforeReturning: {
            for await _ in generation.stream { break }
        })
        let client = HolyMannaBoardClient(
            identityStore: HolyMannaActorIdentityStore(
                fileURL: directory.appendingPathComponent("manna-actor.json")
            )
        ) { invocation, _ in
            .init(
                stdout: invocation.displayCommand.contains("estate")
                    ? HolyMannaBoardFixtures.estate
                    : HolyMannaBoardFixtures.state,
                stderr: "",
                exitCode: 0
            )
        }
        let warmer = HolyMannaBoardPrewarmer(
            client: client,
            digestService: digestRecorder
        )
        let store = HolyMannaBoardModeStore(client: client, prewarmer: warmer)

        store.prepare(context: .init(
            boardRoot: "/srv/holy-ghostty",
            remoteHost: "builder@example.com"
        ))
        for _ in 0 ..< 400 {
            if await digestRecorder.callCount > 0 { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        // Generation is still suspended: canonical state must already be usable.
        #expect(await digestRecorder.callCount == 1)
        #expect(store.state != nil)
        #expect(store.selectedItemID == "mn-live001")
        #expect(!store.isRefreshing)
        #expect(!store.isPresented)
        #expect(!store.isDigestLoading)
        #expect(store.digestText == nil)

        // A service call records its start before the prewarmer delivers its
        // result to the MainActor sink. Wait for that delivery, not callCount.
        generation.continuation.finish()
        await warmer.waitUntilIdle()

        #expect(await digestRecorder.callCount == 1)
        #expect(!store.isDigestLoading)
        #expect(store.digestText == "Warm summary for Native Board")
        #expect(store.presentationDigest(for: try #require(store.selectedItem)) == "Warm Native Board")
    }

    @Test(arguments: [false, true]) @MainActor
    func deadlineMissKeepsInspectorPendingUntilRetrySucceeds(networkTimeout: Bool) async throws {
        let directory = try temporaryDirectory(named: "holy-board-deadline-pending")
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = AsyncStream<Void>.makeStream()
        defer { gate.continuation.finish() }
        let delays = HolyMannaDelayRecorder()
        let recorder = HolyMannaDigestRecorder(attemptHandler: { _, _, attempt in
            if attempt == 0 {
                if networkTimeout { throw URLError(.timedOut) }
                throw HolyMannaBoardClientError.timedOut("Holy fast model")
            }
        })
        let (store, warmer) = warmStore(directory: directory, digestService: recorder, retrySleep: { delay in
            await delays.append(delay)
            for await _ in gate.stream { break }
        })
        store.prepare(context: .init(boardRoot: "/srv/holy-ghostty", remoteHost: "builder@example.com"))
        for _ in 0 ..< 400 {
            if await !delays.values.isEmpty { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        #expect(await recorder.callCount == 1)
        #expect(await delays.values == [5_000_000_000])
        #expect(store.digestText == nil)
        #expect(store.digestFailure == nil)
        #expect(store.isDigestLoading)
        // Selection churn must not restore a saved deadline message.
        store.selectItem(nil)
        store.selectItem("mn-live001")
        #expect(store.digestFailure == nil)
        #expect(store.isDigestLoading)

        gate.continuation.finish()
        await warmer.waitUntilIdle()
        #expect(await recorder.batches.map(\.retryAttempt) == [0, 1])
        #expect(store.digestText == "Warm summary for Native Board")
        #expect(store.digestFailure == nil)
        #expect(!store.isDigestLoading)
    }

    @Test(arguments: [false, true]) @MainActor
    func presentationRefusalsRemainVisibleWithoutRetry(binaryMissing: Bool) async throws {
        let directory = try temporaryDirectory(named: "holy-board-refusal")
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = HolyMannaDigestRecorder(attemptHandler: { _, _, _ in
            if binaryMissing { throw HolyIntelligenceError.binaryMissing }
            throw HolyIntelligenceError.usageGuard("account at cap")
        })
        let (store, warmer) = warmStore(directory: directory, digestService: recorder)
        store.prepare(context: .init(boardRoot: "/srv/holy-ghostty", remoteHost: "builder@example.com"))
        for _ in 0 ..< 400 {
            if await recorder.callCount > 0 { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        await warmer.waitUntilIdle()
        #expect(await recorder.callCount == 1)
        #expect(store.digestText == nil)
        #expect(!store.isDigestLoading)
        let refusal = binaryMissing ? HolyIntelligenceError.binaryMissing : .usageGuard("account at cap")
        #expect(store.digestFailure == refusal.localizedDescription)
    }

    @Test @MainActor func usageGuardShowsWhyUncachedPresentationIsPaused() async throws {
        let directory = try temporaryDirectory(named: "holy-board-guarded")
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = HolyMannaDigestRecorder()
        let (store, warmer) = warmStore(directory: directory, digestService: recorder, usageLevel: .restrain)
        store.prepare(context: .init(boardRoot: "/srv/holy-ghostty", remoteHost: "builder@example.com"))
        for _ in 0 ..< 400 {
            if await recorder.callCount > 0 { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        await warmer.waitUntilIdle()
        #expect(await recorder.callCount == 1)
        #expect(await recorder.batches.allSatisfy { !$0.allowGeneration })
        #expect(store.digestText == nil)
        #expect(store.digestFailure == HolyIntelligenceError.usageGuard("account at cap").localizedDescription)
        #expect(!store.isDigestLoading)
    }

    @Test @MainActor func splitBatchSalvagesAndCachesEveryItemExceptTheSlowOne() async throws {
        let directory = try temporaryDirectory(named: "holy-board-salvage")
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("holy.sqlite3")
        let database = try HolyDatabase.open(at: databaseURL)
        try HolyDatabaseMigrator.migrate(database)
        let completion = HolyMannaSlowCompletionRecorder(slowItemID: "mn-batch000")
        let service = HolyMannaBoardDigestService(databaseURL: databaseURL) { _, prompt, _, timeout in
            try await completion.complete(prompt: prompt, timeout: timeout)
        }
        let delays = HolyMannaDelayRecorder()
        let warmer = HolyMannaBoardPrewarmer(
            client: .init(),
            digestService: service,
            pacer: .init(isForeground: { false }, sleep: { _ in }),
            retrySleep: { await delays.append($0) }
        )
        let context = HolyMannaBoardContext(boardRoot: "/srv/focus", remoteHost: nil)
        let payload = try JSONDecoder().decode(
            HolyMannaStatePayload.self,
            from: Data(HolyMannaBoardFixtures.state(itemCount: 13, root: "/srv/focus").utf8)
        )
        var resolved: [HolyMannaPresentationResult] = []
        var failures: [String] = []
        var pending: [String] = []
        await warmer.enqueueFocused(payload, context: context, allowGeneration: true, usageGuardReason: nil) { event in
            switch event {
            case let .resolved(_, results): resolved.append(contentsOf: results)
            case let .failed(_, _, message): failures.append(message)
            case let .pending(_, ids): pending.append(contentsOf: ids)
            }
        }
        await warmer.waitUntilIdle()

        let calls = await completion.batches
        // The second original batch progresses before the first one's retry.
        #expect(calls.prefix(3).map(\.count) == [12, 1, 12])
        let slowCalls = calls.filter { $0.contains("mn-batch000") }
        #expect(slowCalls.map(\.count) == [12, 12, 6, 3, 2, 1])
        #expect(await completion.timeouts.prefix(3) == [120, 65, 240])
        #expect(await delays.values.contains(10_000_000_000))
        #expect(failures.isEmpty)
        #expect(pending.contains("mn-batch000"))
        #expect(resolved.count == 12)
        #expect(resolved.allSatisfy { $0.itemID != "mn-batch000" && $0.isComplete })
        #expect(try database.scalarInt64("SELECT COUNT(*) FROM board_digest_cache;") == 12)
        let cached = try await service.presentations(
            for: Array(payload.allVisibleItems.prefix(12)), context: context, allowGeneration: false
        )
        #expect(cached.filter(\.isComplete).count == 11)
        #expect(cached.first { $0.itemID == "mn-batch000" }?.summary == nil)
    }

    @Test(arguments: [false, true]) @MainActor
    func queuedRefreshCannotResetRetryAllowanceButChangedContentCan(contentChanged: Bool) async throws {
        let gate = AsyncStream<Void>.makeStream()
        defer { gate.continuation.finish() }
        let delays = HolyMannaDelayRecorder()
        let recorder = HolyMannaDigestRecorder(attemptHandler: { _, _, _ in
            throw HolyMannaBoardClientError.timedOut("Holy fast model")
        })
        let warmer = HolyMannaBoardPrewarmer(
            client: .init(),
            digestService: recorder,
            pacer: .init(isForeground: { false }, sleep: { _ in }),
            retrySleep: { delay in
                await delays.append(delay)
                for await _ in gate.stream { break }
            }
        )
        let context = HolyMannaBoardContext(boardRoot: "/srv/focus", remoteHost: nil)
        let original = HolyMannaBoardFixtures.state(itemCount: 1, root: "/srv/focus")
        let payload = try JSONDecoder().decode(HolyMannaStatePayload.self, from: Data(original.utf8))
        let next = try JSONDecoder().decode(HolyMannaStatePayload.self, from: Data(
            (contentChanged ? original.replacingOccurrences(of: "Generate complete presentation 0.", with: "New content.") : original).utf8
        ))
        let sink: HolyMannaWarmSink = { event in
            if case .failed = event { Issue.record("A deadline miss must stay pending") }
        }
        await warmer.enqueueFocused(payload, context: context, allowGeneration: true, usageGuardReason: nil, sink: sink)
        for _ in 0 ..< 400 {
            if await !delays.values.isEmpty { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        try #require(await recorder.callCount == 1)
        await warmer.enqueueFocused(next, context: context, allowGeneration: true, usageGuardReason: nil, sink: sink)
        gate.continuation.finish()
        await warmer.waitUntilIdle()
        let expected = contentChanged ? [0, 1, 0, 1] : [0, 1]
        #expect(await recorder.batches.map(\.retryAttempt) == expected)

        // Only a new warm cycle gives parked content a fresh bounded attempt.
        await warmer.enqueueFocused(next, context: context, allowGeneration: true, usageGuardReason: nil, sink: sink)
        await warmer.waitUntilIdle()
        #expect(await recorder.batches.map(\.retryAttempt) == expected + [0, 1])
    }

    @Test @MainActor func usageGuardRefreshStopsGenerationBeforeTheQueuedRetry() async throws {
        let gate = AsyncStream<Void>.makeStream()
        defer { gate.continuation.finish() }
        let delays = HolyMannaDelayRecorder()
        let recorder = HolyMannaDigestRecorder(attemptHandler: { _, allowGeneration, _ in
            if allowGeneration { throw HolyMannaBoardClientError.timedOut("Holy fast model") }
        })
        let warmer = HolyMannaBoardPrewarmer(
            client: .init(), digestService: recorder,
            pacer: .init(isForeground: { false }, sleep: { _ in }),
            retrySleep: { delay in
                await delays.append(delay)
                for await _ in gate.stream { break }
            }
        )
        let context = HolyMannaBoardContext(boardRoot: "/srv/focus", remoteHost: nil)
        let payload = try JSONDecoder().decode(
            HolyMannaStatePayload.self,
            from: Data(HolyMannaBoardFixtures.state(itemCount: 1, root: "/srv/focus").utf8)
        )
        var failures: [String] = []
        let sink: HolyMannaWarmSink = { event in
            if case let .failed(_, _, message) = event { failures.append(message) }
        }
        await warmer.enqueueFocused(payload, context: context, allowGeneration: true, usageGuardReason: nil, sink: sink)
        for _ in 0 ..< 400 {
            if await !delays.values.isEmpty { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        try #require(await recorder.callCount == 1)
        await warmer.enqueueFocused(
            payload, context: context, allowGeneration: false, usageGuardReason: "account at cap", sink: sink
        )
        gate.continuation.finish()
        await warmer.waitUntilIdle()
        #expect(await recorder.batches.map(\.allowGeneration) == [true, false])
        #expect(failures == [HolyIntelligenceError.usageGuard("account at cap").localizedDescription])
    }

    @Test @MainActor func unchangedEstateRetriesAfterDeadlineMissInsteadOfBeingMarkedComplete() async throws {
        let recorder = HolyMannaDigestRecorder(attemptHandler: { _, _, _ in throw URLError(.networkConnectionLost) })
        let client = HolyMannaBoardClient { invocation, _ in
            .init(stdout: HolyMannaBoardFixtures.state(itemCount: 1, root: invocation.currentDirectoryPath!), stderr: "", exitCode: 0)
        }
        let warmer = HolyMannaBoardPrewarmer(
            client: client, digestService: recorder,
            pacer: .init(isForeground: { false }, sleep: { _ in }), retrySleep: { _ in }
        )
        let estate = try JSONDecoder().decode(
            HolyMannaEstatePayload.self,
            from: Data(HolyMannaBoardFixtures.estateJSON(otherLatestUpdate: "unchanged").utf8)
        )
        for _ in 0 ..< 2 {
            await warmer.enqueueEstate(
                estate, baseContext: .init(boardRoot: "/srv/focus", remoteHost: nil), focusedRoot: "/srv/focus",
                allowGeneration: true, usageGuardReason: nil
            ) { event in
                if case .failed = event { Issue.record("Transport failure must remain pending") }
            }
            await warmer.waitUntilIdle()
        }
        #expect(await recorder.batches.map(\.retryAttempt) == [0, 1, 0, 1])
    }

    @Test func databaseMigrationCreatesBoundedDigestCacheSurface() throws {
        let directory = try temporaryDirectory(named: "holy-board-database")
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try HolyDatabase.open(at: directory.appendingPathComponent("holy.sqlite3"))

        try HolyDatabaseMigrator.migrate(database)

        #expect(try database.userVersion() == HolyDatabaseSchema.currentUserVersion)
        #expect(
            try database.scalarInt64(
                "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'board_digest_cache';"
            ) == 1
        )
        #expect(
            try database.scalarInt64(
                "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = 'board_digest_cache_last_used_at_idx';"
            ) == 1
        )
    }

    @Test func mutationCommandsMapOnlyToRealMannaVerbsAndGateDeletion() {
        #expect(HolyMannaMutation.close("mn-live001").commands == [
            ["manna", "claim", "mn-live001"],
            ["manna", "done", "mn-live001"],
        ])
        #expect(HolyMannaMutation.fix.commands == [["manna", "reconcile", "--fix", "--json"]])
        #expect(HolyMannaMutation.delete("mn-live001").isDestructive)
        #expect(!HolyMannaMutation.claim("mn-live001").isDestructive)
    }

    @Test(arguments: [Int32(0), 2])
    func refusalEnvelopeSurfacesTheCliErrorAndTheDirectoryTried(exitCode: Int32) async throws {
        let client = HolyMannaBoardClient { _, _ in
            .init(stdout: HolyMannaBoardFixtures.storageNotInitialized, stderr: "", exitCode: exitCode)
        }
        let context = HolyMannaBoardContext(boardRoot: "/srv/nowhere", remoteHost: "builder@example.com")

        await #expect(throws: HolyMannaBoardClientError.rejected(
            command: "builder@example.com: agent-do manna state --json",
            error: "Storage not initialized. Run 'manna-core init' first.",
            directory: "builder@example.com:/srv/nowhere"
        )) {
            _ = try await client.state(for: context)
        }

        do {
            _ = try await client.state(for: context)
            Issue.record("a refusal must throw")
        } catch let error as HolyMannaBoardClientError {
            // The regression: the honest refusal used to be masked by the
            // contract message because the full payload was decoded first.
            let description = error.localizedDescription
            #expect(description.contains("Storage not initialized"))
            #expect(description.contains("/srv/nowhere"))
            #expect(!description.contains("canonical JSON contract"))
            #expect(error.meansNoBoardHere)
        }
    }

    @Test(arguments: ["not JSON", #"{"success":true}"#])
    func nonzeroExitWithoutARefusalPreservesTheTransportFailure(stdout: String) async throws {
        let client = HolyMannaBoardClient { _, _ in
            .init(stdout: stdout, stderr: "ssh: connection closed\n", exitCode: 255)
        }
        await #expect(throws: HolyMannaBoardClientError.commandFailed(
            command: "builder@example.com: agent-do manna state --json",
            code: 255,
            detail: "ssh: connection closed"
        )) {
            _ = try await client.state(for: .init(boardRoot: "/srv/holy-ghostty", remoteHost: "builder@example.com"))
        }
    }

    @Test func contractMismatchNamesTheFieldThatFailed() async throws {
        let client = HolyMannaBoardClient { _, _ in
            .init(stdout: #"{"success": true, "generated_at": "2026-09-02T14:00:00Z", "name": "x"}"#, stderr: "", exitCode: 0)
        }
        let context = HolyMannaBoardContext(boardRoot: "/srv/holy-ghostty", remoteHost: "builder@example.com")

        do {
            _ = try await client.state(for: context)
            Issue.record("a contract miss must throw")
        } catch let error as HolyMannaBoardClientError {
            guard case let .invalidPayload(command, detail) = error else {
                Issue.record("expected invalidPayload, got \(error)")
                return
            }
            #expect(command == "builder@example.com: agent-do manna state --json")
            #expect(detail.contains("missing key 'root'"))
            #expect(!error.meansNoBoardHere)
        }

        let garbage = HolyMannaBoardClient { _, _ in
            .init(stdout: "not json at all", stderr: "", exitCode: 0)
        }
        do {
            _ = try await garbage.estate(for: context)
            Issue.record("garbage must throw")
        } catch let error as HolyMannaBoardClientError {
            guard case .invalidPayload = error else {
                Issue.record("expected invalidPayload, got \(error)")
                return
            }
        }
    }

    @Test(arguments: [Int32(0), 2])
    func estateRefusalIsSurfacedInItsOwnWords(exitCode: Int32) async throws {
        let client = HolyMannaBoardClient { _, _ in
            .init(stdout: #"{"success": false, "error": "estate read failed: registry unreadable"}"#,
                  stderr: "", exitCode: exitCode)
        }
        await #expect(throws: HolyMannaBoardClientError.rejected(
            command: "builder@example.com: agent-do manna estate --json",
            error: "estate read failed: registry unreadable",
            directory: "builder@example.com:/srv/holy-ghostty"
        )) {
            _ = try await client.estate(for: .init(boardRoot: "/srv/holy-ghostty", remoteHost: "builder@example.com"))
        }
    }

    @Test @MainActor func presentingWithoutABoardLandsOnTheEstate() async throws {
        let client = HolyMannaBoardClient { invocation, _ in
            if invocation.displayCommand.contains("estate") {
                return .init(stdout: HolyMannaBoardFixtures.estate, stderr: "", exitCode: 0)
            }
            let rooted = invocation.arguments.joined(separator: " ").contains("/srv/holy-ghostty")
            return .init(
                stdout: rooted ? HolyMannaBoardFixtures.state : HolyMannaBoardFixtures.storageNotInitialized,
                stderr: "",
                exitCode: 0
            )
        }
        let store = HolyMannaBoardModeStore(client: client, digestService: HolyMannaDigestRecorder())

        // A session outside any board: the estate, with the CLI's own reason.
        store.present(context: .init(boardRoot: "/srv/nowhere", remoteHost: "builder@example.com"))
        #expect(store.surface == .board)
        for _ in 0 ..< 400 where store.isRefreshing || store.estate == nil {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(!store.isRefreshing)
        #expect(store.surface == .estate)
        #expect(store.state == nil)
        #expect(store.boardFailure?.contains("Storage not initialized") == true)
        #expect(store.boardFailure?.contains("/srv/nowhere") == true)
        #expect(store.estate?.boards.count == 1)

        // Picking a board from the estate reads it and shows it.
        let board = try #require(store.sortedEstateBoards.first)
        store.selectEstateBoard(board)
        #expect(store.surface == .board)
        for _ in 0 ..< 400 where store.state == nil {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(store.state?.name == "holy-ghostty")
        #expect(store.boardFailure == nil)
        #expect(store.selectedItemID == "mn-live001")

        // The crumb's estate keeps the board warm; a session with no
        // directory at all lands on the estate without waiting.
        store.showEstate()
        #expect(store.surface == .estate)
        #expect(store.state != nil)
        store.dismiss()
        store.present(context: .init(boardRoot: nil, remoteHost: nil))
        #expect(store.surface == .estate)
        #expect(store.state == nil)

        // Coming back to a board already read shows it at once, from the
        // cache, while the refresh runs behind it.
        store.prepare(context: .init(boardRoot: "/srv/holy-ghostty", remoteHost: "builder@example.com"))
        #expect(store.surface == .board)
        #expect(store.state?.name == "holy-ghostty")
        #expect(store.selectedItemID == "mn-live001")
        store.dismiss()
    }

    @Test @MainActor func grepEscapeClearsTheFilterInsteadOfLeavingTheBoard() {
        let store = HolyMannaBoardModeStore(digestService: HolyMannaDigestRecorder())
        store.grep = "board"
        #expect(!store.consumeEscape())
        #expect(store.grep == "board")
        store.isGrepFocused = true
        #expect(store.consumeEscape())
        #expect(store.grep.isEmpty)
        #expect(!store.isGrepFocused)
        let before = store.grepFocusRequest
        store.requestGrepFocus()
        #expect(store.grepFocusRequest == before + 1)
    }

    private func temporaryDirectory(named prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @MainActor private func warmStore(
        directory: URL,
        digestService: any HolyMannaBoardDigesting,
        usageLevel: HolyClaudeUsageLevel = .normal,
        retrySleep: @escaping @Sendable (UInt64) async throws -> Void = { _ in }
    ) -> (HolyMannaBoardModeStore, HolyMannaBoardPrewarmer) {
        let client = HolyMannaBoardClient(
            identityStore: HolyMannaActorIdentityStore(fileURL: directory.appendingPathComponent("actor.json"))
        ) { _, _ in .init(stdout: HolyMannaBoardFixtures.state, stderr: "", exitCode: 0) }
        let warmer = HolyMannaBoardPrewarmer(
            client: client, digestService: digestService,
            pacer: .init(isForeground: { false }, sleep: { _ in }), retrySleep: retrySleep
        )
        let store = HolyMannaBoardModeStore(client: client, prewarmer: warmer, usageAssessmentProvider: {
            .init(level: usageLevel, decidingBucket: nil, reason: "account at cap")
        })
        return (store, warmer)
    }
}

private actor HolyMannaInvocationRecorder {
    private(set) var values: [HolyMannaProcessInvocation] = []

    func append(_ invocation: HolyMannaProcessInvocation) {
        values.append(invocation)
    }
}

private struct HolyMannaRecordedBatch: Sendable {
    let root: String?
    let count: Int
    let retryAttempt: Int
    let allowGeneration: Bool
}

private actor HolyMannaDigestRecorder: HolyMannaBoardDigesting {
    private(set) var callCount = 0
    private(set) var batches: [HolyMannaRecordedBatch] = []
    private let beforeReturning: @Sendable () async -> Void
    private let attemptHandler: @Sendable ([HolyMannaBoardItem], Bool, Int) async throws -> Void

    init(
        beforeReturning: @escaping @Sendable () async -> Void = {},
        attemptHandler: @escaping @Sendable ([HolyMannaBoardItem], Bool, Int) async throws -> Void = { _, _, _ in }
    ) {
        self.beforeReturning = beforeReturning
        self.attemptHandler = attemptHandler
    }

    func presentations(
        for items: [HolyMannaBoardItem],
        context: HolyMannaBoardContext,
        allowGeneration: Bool,
        retryAttempt: Int
    ) async throws -> [HolyMannaPresentationResult] {
        callCount += 1
        batches.append(.init(root: context.boardRoot, count: items.count, retryAttempt: retryAttempt, allowGeneration: allowGeneration))
        try await attemptHandler(items, allowGeneration, retryAttempt)
        await beforeReturning()
        return items.map { item in
            .init(
                itemID: item.id,
                digest: item.digest ?? (allowGeneration ? "Warm \(item.titlePlain)" : nil),
                summary: item.summary ?? (allowGeneration ? "Warm summary for \(item.titlePlain)" : nil),
                contentHash: HolyMannaBoardDigestService.contentHash(for: item),
                model: "test",
                wasCached: false
            )
        }
    }
}

private actor HolyMannaSlowCompletionRecorder {
    let slowItemID: String
    private(set) var batches: [[String]] = []
    private(set) var timeouts: [TimeInterval] = []

    init(slowItemID: String) { self.slowItemID = slowItemID }

    func complete(prompt: String, timeout: TimeInterval) throws -> HolyIntelligenceResponse {
        let input = try #require(prompt.components(separatedBy: "INPUT_JSON:\n").last)
        let payload = try #require(JSONSerialization.jsonObject(with: Data(input.utf8)) as? [String: Any])
        let items = try #require(payload["items"] as? [[String: Any]])
        let ids = try items.map { try #require($0["id"] as? String) }
        batches.append(ids)
        timeouts.append(timeout)
        if ids.contains(slowItemID) { throw HolyMannaBoardClientError.timedOut("Holy fast model") }
        let reply = ["items": ids.map { ["id": $0, "digest": "A saved digest", "summary": "A saved summary"] }]
        let data = try JSONSerialization.data(withJSONObject: reply)
        return .init(text: try #require(String(bytes: data, encoding: .utf8)), model: "test-fast")
    }
}

private struct HolyMannaRecordedCompletion: Sendable {
    let role: HolyIntelligenceRole
    let prompt: String
    let workingDirectory: String?
    let timeout: TimeInterval
}

private actor HolyMannaCompletionRecorder {
    private var responses: [String]
    private(set) var calls: [HolyMannaRecordedCompletion] = []

    init(responses: [String]) {
        self.responses = responses
    }

    func complete(
        role: HolyIntelligenceRole,
        prompt: String,
        workingDirectory: String?,
        timeout: TimeInterval
    ) -> HolyIntelligenceResponse {
        calls.append(.init(role: role, prompt: prompt, workingDirectory: workingDirectory, timeout: timeout))
        let text = responses.isEmpty ? #"{"items":[]}"# : responses.removeFirst()
        return .init(text: text, model: "test-fast")
    }
}

private actor HolyMannaDelayRecorder {
    private(set) var values: [UInt64] = []

    func append(_ value: UInt64) {
        values.append(value)
    }
}

private enum HolyMannaBoardFixtures {
    /// What `manna state --json` prints in a directory with no board.
    static let storageNotInitialized = #"{"success":false,"error":"Storage not initialized. Run 'manna-core init' first."}"#

    static let state = """
    {
      "success": true,
      "generated_at": "2026-09-01T16:00:00Z",
      "name": "holy-ghostty",
      "root": "/srv/holy-ghostty",
      "total": 1,
      "counts": {"now": 1},
      "status_counts": {"in_progress": 1},
      "now": [\(itemJSON(description: "Build the native Board."))],
      "next": [],
      "waves": [],
      "dreams": [],
      "decisions": [],
      "tracks": [{
        "id": "mn-track01",
        "title": "Holy cockpit",
        "status": "active",
        "items": [\(itemJSON(description: "Build the native Board."))]
      }],
      "peers": [{
        "agent_id": "codex-019f62805fc77093",
        "alias": null,
        "runtime": "codex",
        "status": "active",
        "attention": "needs-user",
        "age": "0s ago",
        "age_seconds": 0,
        "goal": "build Board",
        "mode": "writer",
        "phase": "building",
        "role": null,
        "paths": ["macos/Sources/HolyGhostty/Board"],
        "holding": [{"id": "mn-live001", "title": "Native Board"}],
        "pulse": {
          "status": "needs-user",
          "activity": "waiting",
          "latest_prompt": "Approve the final action",
          "updated_at": "2026-09-01T16:00:00Z",
          "turns": 4
        }
      }],
      "attention": {"needs-user": 1},
      "coord": {
        "claims": [{
          "path": "macos/Sources/HolyGhostty/Board",
          "owner": "codex-019f62805fc77093",
          "owner_alias": null,
          "owner_status": "active",
          "reason": "native Board",
          "strength": "soft",
          "updated_at": "2026-09-01T16:00:00Z",
          "stale": false,
          "contended": false
        }],
        "contention": [],
        "needs": [{"key": "build-green", "why": "compile", "owner": "codex", "updated_at": null}],
        "drops": [{
          "path": ".handoff/live.md",
          "note": "ready",
          "owner": "codex-019f62805fc77093",
          "created_at": "2026-09-01T16:00:00Z"
        }]
      },
      "drift": {
        "present": true,
        "source": "reconcile",
        "count": 1,
        "generated_at": "2026-09-01T16:00:00Z",
        "kinds": {"landed_open": 1},
        "findings": [{
          "kind": "landed_open",
          "issue_id": "mn-live001",
          "detail": "landed but open",
          "evidence": "abc123",
          "proposed_fix": "claim and close"
        }]
      },
      "git": {"branch": "main", "head": "abc123", "dirty_paths": 1, "is_repo": true},
      "board": {
        "board_id": "mb-live",
        "workflow": "strict",
        "path": ".manna/issues.jsonl",
        "handoff_dir": ".handoff",
        "order_count": 1,
        "issues_modified_at": "2026-09-01T16:00:00Z"
      }
    }
    """

    static func state(itemCount: Int, root: String) -> String {
        let original = itemJSON(description: "Build the native Board.")
        let rows = (0 ..< itemCount).map { index in
            itemJSON(
                id: String(format: "mn-batch%03d", index),
                title: "Warm item \(index)",
                description: "Generate complete presentation \(index)."
            )
        }.joined(separator: ",")
        return Self.state
            .replacingOccurrences(of: original, with: rows)
            .replacingOccurrences(of: "/srv/holy-ghostty", with: root)
    }

    static func estateJSON(otherLatestUpdate: String) -> String {
        """
        {
          "generated_at": "2026-09-03T16:00:00Z",
          "boards": [
            {
              "name": "focus",
              "root": "/srv/focus",
              "exists": true,
              "total": 25,
              "status_counts": {"active": 25},
              "dreams": 0,
              "decisions": 0,
              "drift_count": 0,
              "drift_generated_at": null,
              "latest_update": "2026-09-03T12:00:00Z",
              "coord": {"attention": {}, "needs_you": 0, "working": 0, "here": 0, "gone": 0},
              "slug": "focus",
              "url": "manna://focus"
            },
            {
              "name": "other",
              "root": "/srv/other",
              "exists": true,
              "total": 1,
              "status_counts": {"ready": 1},
              "dreams": 0,
              "decisions": 0,
              "drift_count": 0,
              "drift_generated_at": null,
              "latest_update": "\(otherLatestUpdate)",
              "coord": {"attention": {}, "needs_you": 0, "working": 0, "here": 0, "gone": 0},
              "slug": "other",
              "url": "manna://other"
            }
          ],
          "count": 2,
          "registry": "/Users/erik/.agent-do/manna/serve/boards.json",
          "totals": {"needs_you": 0, "working": 0, "here": 0},
          "building": 0
        }
        """
    }

    static let estate = """
    {
      "generated_at": "2026-09-01T16:00:00Z",
      "boards": [{
        "name": "holy-ghostty",
        "root": "/srv/holy-ghostty",
        "exists": true,
        "total": 1,
        "status_counts": {"active": 1},
        "dreams": 0,
        "decisions": 0,
        "drift_count": 1,
        "drift_generated_at": "2026-09-01T16:00:00Z",
        "latest_update": "2026-09-01T16:00:00Z",
        "coord": {
          "attention": {"needs-user": 1},
          "needs_you": 1,
          "working": 0,
          "here": 1,
          "gone": 0
        },
        "slug": "holy-ghostty",
        "url": "manna://holy-ghostty"
      }],
      "count": 1,
      "registry": "/Users/erik/.manna/registry.yaml",
      "totals": {"needs_you": 1, "working": 0, "here": 1},
      "building": 1
    }
    """

    static func item(
        id: String = "mn-live001",
        title: String = "Native Board",
        description: String,
        blockerStatus: String? = nil,
        digest: String? = nil,
        summary: String? = nil
    ) throws -> HolyMannaBoardItem {
        try JSONDecoder().decode(
            HolyMannaBoardItem.self,
            from: Data(itemJSON(
                id: id,
                title: title,
                description: description,
                blockerStatus: blockerStatus,
                digest: digest,
                summary: summary
            ).utf8)
        )
    }

    private static func itemJSON(
        id: String = "mn-live001",
        title: String = "Native Board",
        description: String,
        blockerStatus: String? = nil,
        digest: String? = nil,
        summary: String? = nil
    ) -> String {
        func encoded(_ value: String?) -> String {
            guard let value else { return "null" }
            let data = (try? JSONEncoder().encode(value)) ?? Data("\"\"".utf8)
            return String(bytes: data, encoding: .utf8) ?? "\"\""
        }
        let blockedBy = blockerStatus == nil ? "[]" : "[\"mn-blocker1\"]"
        let blockers = blockerStatus.map { status in
            "{\"id\":\"mn-blocker1\",\"status\":\"\(status)\",\"title\":\"Land prerequisite\"}"
        } ?? ""
        return """
        {
          "id": \(encoded(id)),
          "title": \(encoded(title)),
          "title_plain": \(encoded(title)),
          "description": \(encoded(description)),
          "status": "in_progress",
          "effective": "active",
          "kind": "item",
          "order": 0,
          "decision": false,
          "blocked_by": \(blockedBy),
          "blockers": [\(blockers)],
          "dependents": [],
          "claimant": {
            "label": "codex-019f62805fc77093",
            "liveness": "present",
            "attention": "needs-user",
            "runtime": "codex",
            "age": "0s ago",
            "goal": "build Board",
            "pulse": null
          },
          "commits": [{"sha": "abc123", "at": "2026-09-01T16:00:00Z", "subject": "feat: Board"}],
          "claimed_by": "holy-0123456789abcdef",
          "claimed_at": "2026-09-01T15:00:00Z",
          "created_at": "2026-09-01T14:00:00Z",
          "updated_at": "2026-09-01T16:00:00Z",
          "track": "mn-track01",
          "track_title": "Holy cockpit",
          "prompt": ".handoff/live.md",
          "handoff_digest": "sha256:live",
          "handoff_exists": true,
          "source": ".manna/issues.jsonl",
          "digest": \(encoded(digest)),
          "summary": \(encoded(summary))
        }
        """
    }
}

struct HolyMannaTrackDecodeRegressionTests {
    // The core emits a synthetic "(no track)" bucket (id: null, status: null)
    // on any board with untracked items; the state decode must survive it.
    @Test func noTrackBucketWithNullIdentityDecodes() throws {
        let json = """
        [{"id": null, "status": null, "title": "(no track)", "items": []},
         {"id": "mn-9a97cc", "status": "open", "title": "TRACK: One Ledger, Two Faces", "items": []}]
        """
        let tracks = try JSONDecoder().decode([HolyMannaTrack].self, from: Data(json.utf8))
        #expect(tracks[0].trackID == nil)
        #expect(tracks[0].status == nil)
        #expect(tracks[0].id == "(no track)")
        #expect(tracks[1].id == "mn-9a97cc")
    }
}
