import Foundation
import Testing
@testable import Ghostty

struct HolyArchiveFederationTests {
    @Test func managedTransportIsControlLaneAndRemoteProgramIsReadOnly() throws {
        let root = URL(
            fileURLWithPath: "/private/tmp/hg-\(UUID().uuidString.prefix(8))",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = HolySSHTransportManager(controlDirectoryURL: root)
        let client = HolyArchiveRemoteSSHQueryClient(transportManager: manager)
        let host = HolyArchiveRemoteHost(
            id: UUID(),
            label: "Studio",
            sshDestination: "studio.tailnet"
        )

        let command = try client.transportCommand(for: host)

        #expect(command.lane == .control)
        #expect(command.executablePath == "/bin/zsh")
        #expect(command.arguments.joined(separator: " ").contains("ProxyCommand=/usr/bin/false"))
        #expect(HolyArchiveRemoteSSHQueryClient.pythonProgram.contains("?mode=ro"))
        #expect(HolyArchiveRemoteSSHQueryClient.pythonProgram.contains("PRAGMA query_only = ON"))
        #expect(!HolyArchiveRemoteSSHQueryClient.pythonProgram.contains("INSERT INTO"))
        #expect(!HolyArchiveRemoteSSHQueryClient.pythonProgram.contains("UPDATE archive_"))
        #expect(!HolyArchiveRemoteSSHQueryClient.pythonProgram.contains("DELETE FROM archive_"))
    }

    @Test func cachedPagesNamespaceIdentityCarryProvenanceAndGoStaleOffline() async throws {
        let root = temporaryRoot("cache")
        defer { try? FileManager.default.removeItem(at: root) }
        let studio = HolyArchiveRemoteHost(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            label: "Studio",
            sshDestination: "studio.tailnet"
        )
        let page = remotePage(
            sessions: [remoteSession(id: "shared-session")],
            childCounts: ["shared-session": 2]
        )
        let client = FixtureRemoteArchiveClient(pages: [studio.id: [.parents: page]])
        let sleeps = FederationSleepRecorder()
        let budget = HolyArchiveWriteBudget(
            rowsPerTransaction: 25,
            foregroundRowsPerSecond: 100,
            backgroundRowsPerSecond: 1_000,
            checkpointEveryRows: 100,
            maximumPauseNanoseconds: 1_000_000_000
        )
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let federation = HolyArchiveFederation(
            queryClient: client,
            cacheDirectoryURL: root,
            pacer: .init(
                budget: budget,
                isForeground: { true },
                sleep: { value in await sleeps.record(value) }
            ),
            now: { now }
        )
        let query = emptyQuery()

        let live = await federation.parents(hosts: [studio], query: query, limit: 500, policy: .refresh)

        let session = try #require(live.sessions.first)
        let expectedID = HolyArchiveSourceMetadata.namespacedID("shared-session", hostID: studio.id)
        #expect(session.id == expectedID)
        #expect(session.providerSessionID == "shared-session")
        #expect(session.shortID == "shared-s")
        #expect(session.archiveSource.hostLabel == "Studio")
        #expect(!session.archiveSource.isStale)
        #expect(live.childCounts[expectedID] == 2)
        #expect(await sleeps.values == [10_000_000])
        let cacheFile = try #require(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first)
        let permissions = try #require(
            FileManager.default.attributesOfItem(atPath: cacheFile.path)[.posixPermissions] as? NSNumber
        )
        #expect(permissions.intValue & 0o777 == 0o600)

        await client.fail(hostID: studio.id)
        let offline = await federation.parents(hosts: [studio], query: query, limit: 500, policy: .refresh)
        let cached = try #require(offline.sessions.first)
        #expect(cached.id == expectedID)
        #expect(cached.archiveSource.isStale)
        #expect(cached.archiveSource.error?.contains("offline") == true)
        #expect(offline.notices.count == 1)
        #expect(offline.notices.first?.contains("Studio is offline; showing its cached archive") == true)
    }

    @Test func livePageSurvivesCacheWriteFailureAndReportsTheDegradedCache() async throws {
        let root = temporaryRoot("blocked-cache")
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("not a directory".utf8).write(to: root)
        let host = HolyArchiveRemoteHost(id: UUID(), label: "Studio", sshDestination: "studio")
        let client = FixtureRemoteArchiveClient(pages: [
            host.id: [.parents: remotePage(sessions: [remoteSession(id: "live-session")])],
        ])
        let federation = HolyArchiveFederation(
            queryClient: client,
            cacheDirectoryURL: root,
            pacer: .init(budget: .unthrottled)
        )

        let result = await federation.parents(
            hosts: [host],
            query: emptyQuery(),
            limit: 500,
            policy: .refresh
        )

        let session = try #require(result.sessions.first)
        #expect(session.providerSessionID == "live-session")
        #expect(!session.archiveSource.isStale)
        #expect(session.archiveSource.error?.contains("Offline cache update failed") == true)
        #expect(result.notices == ["Studio is live, but its offline archive cache could not update."])
    }

    @Test func sameProviderIDOnTwoHostsNeverCollides() async throws {
        let root = temporaryRoot("identity")
        defer { try? FileManager.default.removeItem(at: root) }
        let first = HolyArchiveRemoteHost(id: UUID(), label: "Studio", sshDestination: "studio")
        let second = HolyArchiveRemoteHost(id: UUID(), label: "MacBook", sshDestination: "macbook")
        let page = remotePage(sessions: [remoteSession(id: "same-id")])
        let client = FixtureRemoteArchiveClient(
            pages: [first.id: [.parents: page], second.id: [.parents: page]]
        )
        let federation = HolyArchiveFederation(
            queryClient: client,
            cacheDirectoryURL: root,
            pacer: .init(budget: .unthrottled)
        )

        let result = await federation.parents(
            hosts: [first, second],
            query: emptyQuery(),
            limit: 500,
            policy: .refresh
        )

        #expect(result.sessions.count == 2)
        #expect(Set(result.sessions.map(\.id)).count == 2)
        #expect(Set(result.sessions.map(\.providerSessionID)) == ["same-id"])
        #expect(Set(result.sessions.map { $0.archiveSource.hostLabel }) == ["Studio", "MacBook"])
    }

    @Test func searchResultsAndMatchingChildrenRetainOwningHost() async throws {
        let root = temporaryRoot("search")
        defer { try? FileManager.default.removeItem(at: root) }
        let host = HolyArchiveRemoteHost(id: UUID(), label: "Studio", sshDestination: "studio")
        let parent = remoteSession(id: "parent")
        let child = remoteSession(id: "child", child: true, parentID: "parent")
        let match = HolyArchiveRemoteMatch(
            score: 0.5,
            keywordScore: 0.9,
            semanticScore: nil,
            snippet: "remote archive needle",
            source: "keyword"
        )
        let page = remotePage(
            sessions: [parent],
            childCounts: ["parent": 1],
            matches: ["parent": match],
            matchingChildren: ["parent": [child]]
        )
        let client = FixtureRemoteArchiveClient(pages: [host.id: [.search: page]])
        let federation = HolyArchiveFederation(
            queryClient: client,
            cacheDirectoryURL: root,
            pacer: .init(budget: .unthrottled)
        )
        let query = HolyArchiveSearchParser.parse("needle")

        let result = await federation.search(hosts: [host], query: query, limit: 50, policy: .refresh)

        let found = try #require(result.results.first)
        #expect(found.matchSource == .keyword)
        #expect(found.matchSnippet == "remote archive needle")
        #expect(found.session.archiveSource.hostLabel == "Studio")
        let childRows = try #require(result.matchingChildren[found.session.id])
        #expect(childRows.first?.parentID == found.session.id)
        #expect(childRows.first?.archiveSource.hostLabel == "Studio")
    }

    @Test func remoteResumeUsesRawProviderIDRuntimeCwdAndOwningHost() throws {
        var session = ArchiveFixtures.session(id: "namespaced", projectName: "holy-ghostty")
        let hostID = UUID()
        session.extra[HolyArchiveSourceMetadata.rawSessionID] = "provider-session-42"
        session.extra[HolyArchiveSourceMetadata.hostID] = hostID.uuidString
        session.extra[HolyArchiveSourceMetadata.hostLabel] = "Studio"
        session.extra[HolyArchiveSourceMetadata.sshDestination] = "studio.tailnet"
        session.extra[HolyArchiveSourceMetadata.tmuxSocketName] = "holy-studio"

        let spec = try #require(HolyArchiveResumeLaunchSpec.make(for: session))

        #expect(spec.runtime == .codex)
        #expect(spec.workingDirectory == "/project/holy-ghostty")
        #expect(spec.providerSessionID == "provider-session-42")
        #expect(spec.command == "'codex' 'resume' 'provider-session-42'")
        #expect(spec.transport.kind == .ssh)
        #expect(spec.transport.hostLabel == "Studio")
        #expect(spec.transport.sshDestination == "studio.tailnet")
        #expect(spec.tmux?.socketName == "holy-studio")
    }

    @Test func pythonQueryContractReadsCurrentArchiveWithoutMutation() async throws {
        let root = temporaryRoot("python")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = root
            .appendingPathComponent("Library/Application Support/org.holyghostty.app/HolyGhostty", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let databaseURL = container.appendingPathComponent(HolyArchiveDatabaseSchema.filename)
        let repository = try HolyArchiveRepository(databaseURL: databaseURL)
        let parent = ArchiveFixtures.session(id: "studio-parent", firstPrompt: "federated archive needle")
        let child = ArchiveFixtures.session(
            id: "studio-child",
            child: true,
            parentID: parent.id,
            firstPrompt: "child archive work"
        )
        let semanticChunk = HolyArchiveChunk(
            id: "studio-parent:semantic",
            sessionID: parent.id,
            messageID: nil,
            index: 0,
            type: .summary,
            content: "A concept represented only by its stored vector",
            metadata: [:],
            embedding: [1, 0],
            embeddingModel: "fixture",
            createdAt: parent.createdAt
        )
        try repository.replace(
            session: parent,
            messages: ArchiveFixtures.messages(sessionID: parent.id),
            chunks: [semanticChunk]
        )
        try repository.replace(
            session: child,
            messages: ArchiveFixtures.messages(sessionID: child.id),
            chunks: []
        )
        _ = try repository.addAnnotation(sessionID: parent.id, kind: .tag, value: "federated")
        let before = try Data(contentsOf: databaseURL)

        let parents = try await runPython(
            .parents(query: emptyQuery(), limit: 500),
            homeDirectory: root
        )
        #expect(parents.total == 1)
        #expect(parents.sessions.map(\.id) == [parent.id])
        #expect(parents.childCounts[parent.id] == 1)

        let search = try await runPython(
            .search(query: HolyArchiveSearchParser.parse("archive search"), limit: 50),
            homeDirectory: root
        )
        #expect(search.sessions.contains { $0.id == parent.id })
        #expect(search.matches[parent.id]?.source == "keyword")

        let semantic = try await runPython(
            .search(
                query: HolyArchiveSearchParser.parse("words absent from every remote row"),
                semanticQueryVector: [1, 0],
                limit: 50
            ),
            homeDirectory: root
        )
        #expect(semantic.sessions.map(\.id) == [parent.id])
        #expect(semantic.matches[parent.id]?.source == "semantic")
        #expect(semantic.matches[parent.id]?.keywordScore == nil)
        #expect(semantic.matches[parent.id]?.semanticScore == 1)

        let messages = try await runPython(
            .messages(sessionID: parent.id),
            homeDirectory: root
        )
        #expect(messages.messages.count == 3)
        let annotations = try await runPython(
            .annotations(sessionID: parent.id),
            homeDirectory: root
        )
        #expect(annotations.annotations.map(\.value) == ["federated"])
        #expect(try Data(contentsOf: databaseURL) == before)
    }

    @Test @MainActor func modeStoreMergesLocalAndRemoteRowsSearchesAndResumesRemote() async throws {
        let root = temporaryRoot("mode-store")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let databaseURL = root.appendingPathComponent("local.sqlite3")
        let repository = try HolyArchiveRepository(databaseURL: databaseURL)
        let local = ArchiveFixtures.session(id: "local-session", firstPrompt: "local archive result")
        try repository.replace(
            session: local,
            messages: ArchiveFixtures.messages(sessionID: local.id),
            chunks: []
        )
        let hostID = UUID()
        let host = HolyArchiveRemoteHost(id: hostID, label: "Studio", sshDestination: "studio.tailnet")
        let remote = remoteSession(id: "studio-session")
        let remoteMatch = HolyArchiveRemoteMatch(
            score: 0.5,
            keywordScore: 1,
            semanticScore: nil,
            snippet: "remote archive result",
            source: "keyword"
        )
        let client = FixtureRemoteArchiveClient(pages: [
            hostID: [
                .parents: remotePage(sessions: [remote]),
                .search: remotePage(sessions: [remote], matches: [remote.id: remoteMatch]),
            ],
        ])
        let federation = HolyArchiveFederation(
            queryClient: client,
            cacheDirectoryURL: root.appendingPathComponent("cache", isDirectory: true),
            pacer: .init(budget: .unthrottled)
        )
        let emptyHome = root.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyHome, withIntermediateDirectories: true)
        var resumed: HolyArchiveSession?
        let record = HolyRemoteHostRecord(
            id: hostID,
            label: host.label,
            sshDestination: host.sshDestination
        )
        let store = HolyArchiveModeStore(
            registry: .init(homeDirectory: emptyHome),
            databaseURL: databaseURL,
            federation: federation,
            remoteHostsProvider: { [record] },
            resumeHandler: { resumed = $0; return true }
        )

        store.present()
        for _ in 0 ..< 200 where store.sessions.count < 2 {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(store.sessions.count == 2)
        #expect(store.totalParentCount == 2)
        #expect(Set(store.sessions.map { $0.archiveSource.hostLabel }) == ["This Mac", "Studio"])

        store.query = "project:holy-ghostty"
        store.performSearch()
        for _ in 0 ..< 200 where store.isSearching || store.sessions.count < 2 {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(store.sessions.count == 2)
        let remoteRow = try #require(store.sessions.first { $0.isRemoteArchiveSession })
        store.selectParent(remoteRow.id)
        #expect(!store.canModifySelectedSession)
        store.resumeSelected()
        #expect(resumed?.providerSessionID == "studio-session")
        #expect(resumed?.archiveSource.hostLabel == "Studio")
    }

    private func runPython(
        _ request: HolyArchiveRemoteRequest,
        homeDirectory: URL
    ) async throws -> HolyArchiveRemotePage {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        let input = try encoder.encode(request)
        let result = await HolyRestoreProcessRunner.run(
            executablePath: "/usr/bin/python3",
            arguments: ["-c", HolyArchiveRemoteSSHQueryClient.pythonProgram],
            timeout: 10,
            environment: ["HOME": homeDirectory.path],
            stdinData: input
        )
        let output: HolyRestoreProcessOutput
        switch result {
        case let .success(value):
            output = value
        case let .failure(detail):
            Issue.record("Python archive query failed to launch: \(detail)")
            throw FederationFixtureError.offline
        }
        #expect(output.exitCode == 0, "Python archive query stderr: \(output.stderr)")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(HolyArchiveRemotePage.self, from: Data(output.stdout.utf8))
    }

    private func temporaryRoot(_ suffix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-archive-federation-\(suffix)-\(UUID().uuidString)", isDirectory: true)
    }

    private func emptyQuery() -> HolyArchiveSearchQuery {
        .init(text: "", harness: nil, rawHarness: nil, project: nil, after: nil, before: nil, tags: [])
    }

    private func remotePage(
        sessions: [HolyArchiveRemoteSession] = [],
        childCounts: [String: Int] = [:],
        matches: [String: HolyArchiveRemoteMatch] = [:],
        matchingChildren: [String: [HolyArchiveRemoteSession]] = [:]
    ) -> HolyArchiveRemotePage {
        .init(
            total: sessions.count,
            sessions: sessions,
            messages: [],
            annotations: [],
            childCounts: childCounts,
            matches: matches,
            matchingChildren: matchingChildren
        )
    }

    private func remoteSession(
        id: String,
        child: Bool = false,
        parentID: String? = nil
    ) -> HolyArchiveRemoteSession {
        .init(
            id: id,
            harness: "codex",
            rawPath: "/remote/archive/\(id).jsonl",
            projectPath: "/remote/project",
            projectName: "holy-ghostty",
            title: "Built remote archive",
            firstPrompt: "Build remote archive",
            lastPrompt: "Verify remote archive",
            lastResponse: "Verified",
            createdAt: 1_700_000_000,
            modifiedAt: 1_700_000_100,
            isChild: child,
            childType: child ? "worker" : nil,
            parentID: parentID,
            model: "gpt-5.6",
            toolCalls: ["rg"],
            tokensUsed: 100,
            summary: "Built federated archive",
            contentHash: "hash-\(id)",
            extra: [:],
            resumeCommand: "codex resume \(id)",
            messageCount: 2,
            turnCount: 1,
            fileMTime: 1_700_000_100,
            indexedAt: 1_700_000_100,
            autoTags: ["archive"]
        )
    }
}

private enum FederationFixtureError: LocalizedError {
    case offline

    var errorDescription: String? { "fixture host is offline" }
}

private actor FixtureRemoteArchiveClient: HolyArchiveRemoteQuerying {
    private let pages: [UUID: [HolyArchiveRemoteRequest.Operation: HolyArchiveRemotePage]]
    private var failedHostIDs: Set<UUID> = []

    init(pages: [UUID: [HolyArchiveRemoteRequest.Operation: HolyArchiveRemotePage]]) {
        self.pages = pages
    }

    func fail(hostID: UUID) {
        failedHostIDs.insert(hostID)
    }

    func query(_ request: HolyArchiveRemoteRequest, on host: HolyArchiveRemoteHost) async throws
        -> HolyArchiveRemotePage {
        if failedHostIDs.contains(host.id) { throw FederationFixtureError.offline }
        guard let page = pages[host.id]?[request.operation] else {
            return .init(
                total: 0,
                sessions: [],
                messages: [],
                annotations: [],
                childCounts: [:],
                matches: [:],
                matchingChildren: [:]
            )
        }
        return page
    }
}

private actor FederationSleepRecorder {
    private(set) var values: [UInt64] = []

    func record(_ value: UInt64) {
        values.append(value)
    }
}
