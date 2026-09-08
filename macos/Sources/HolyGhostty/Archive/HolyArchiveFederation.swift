import CryptoKit
import Foundation

struct HolyArchiveSource: Equatable, Sendable {
    let hostID: UUID?
    let hostLabel: String
    let sshDestination: String?
    let tmuxSocketName: String?
    let providerSessionID: String
    let fetchedAt: Date?
    let isStale: Bool
    let error: String?

    var isRemote: Bool { hostID != nil }
}

enum HolyArchiveSourceMetadata {
    static let rawSessionID = "holy.archive.source.session-id"
    static let hostID = "holy.archive.source.host-id"
    static let hostLabel = "holy.archive.source.host-label"
    static let sshDestination = "holy.archive.source.ssh-destination"
    static let tmuxSocketName = "holy.archive.source.tmux-socket"
    static let fetchedAt = "holy.archive.source.fetched-at"
    static let stale = "holy.archive.source.stale"
    static let error = "holy.archive.source.error"

    static func source(for session: HolyArchiveSession) -> HolyArchiveSource {
        let rawID = session.extra[rawSessionID] ?? session.id
        guard let rawHostID = session.extra[hostID], let parsedHostID = UUID(uuidString: rawHostID) else {
            return .init(
                hostID: nil,
                hostLabel: "This Mac",
                sshDestination: nil,
                tmuxSocketName: nil,
                providerSessionID: rawID,
                fetchedAt: nil,
                isStale: false,
                error: nil
            )
        }
        let timestamp = session.extra[fetchedAt].flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
        return .init(
            hostID: parsedHostID,
            hostLabel: session.extra[hostLabel] ?? "Remote Host",
            sshDestination: session.extra[sshDestination],
            tmuxSocketName: session.extra[tmuxSocketName],
            providerSessionID: rawID,
            fetchedAt: timestamp,
            isStale: session.extra[stale] == "true",
            error: session.extra[error]
        )
    }

    static func namespacedID(_ rawID: String, hostID: UUID) -> String {
        "remote:\(hostID.uuidString.lowercased()):\(rawID)"
    }
}

extension HolyArchiveSession {
    var archiveSource: HolyArchiveSource { HolyArchiveSourceMetadata.source(for: self) }
    var isRemoteArchiveSession: Bool { archiveSource.isRemote }
    var providerSessionID: String { archiveSource.providerSessionID }
}

struct HolyArchiveFederatedSessions: Equatable, Sendable {
    let sessions: [HolyArchiveSession]
    let total: Int
    let childCounts: [String: Int]
    let notices: [String]
}

struct HolyArchiveFederatedSearch: Equatable, Sendable {
    let results: [HolyArchiveSearchResult]
    let matchingChildren: [String: [HolyArchiveSession]]
    let childCounts: [String: Int]
    let notices: [String]
}

enum HolyArchiveRemoteLoadPolicy: Sendable {
    case cacheOnly
    case refresh
}

private struct HolyArchiveRemoteCacheEnvelope: Codable, Equatable, Sendable {
    let fetchedAt: Double
    let page: HolyArchiveRemotePage
}

private struct HolyArchiveRemoteSnapshot: Sendable {
    let host: HolyArchiveRemoteHost
    let page: HolyArchiveRemotePage
    let fetchedAt: Date
    let isStale: Bool
    let error: String?
}

actor HolyArchiveFederation {
    static let freshnessInterval: TimeInterval = 5 * 60

    private let queryClient: any HolyArchiveRemoteQuerying
    private let cacheDirectoryURL: URL
    private let pacer: HolyArchiveWritePacer
    private let now: @Sendable () -> Date
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        queryClient: any HolyArchiveRemoteQuerying = HolyArchiveRemoteSSHQueryClient(),
        cacheDirectoryURL: URL = HolyArchiveFederation.defaultCacheDirectoryURL,
        pacer: HolyArchiveWritePacer = .init(),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.queryClient = queryClient
        self.cacheDirectoryURL = cacheDirectoryURL
        self.pacer = pacer
        self.now = now
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    static var defaultCacheDirectoryURL: URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let bundleID = Bundle.main.bundleIdentifier ?? "org.holyghostty.app"
        return root
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("HolyGhostty/RemoteArchivePages", isDirectory: true)
    }

    func parents(
        hosts: [HolyArchiveRemoteHost],
        query: HolyArchiveSearchQuery,
        limit: Int,
        policy: HolyArchiveRemoteLoadPolicy
    ) async -> HolyArchiveFederatedSessions {
        let request = HolyArchiveRemoteRequest.parents(query: query, limit: limit)
        let snapshots = await snapshots(hosts: hosts, request: request, policy: policy)
        var sessions: [HolyArchiveSession] = []
        var total = 0
        var counts: [String: Int] = [:]
        for snapshot in snapshots {
            sessions += snapshot.page.sessions.map { session($0, snapshot: snapshot) }
            total += snapshot.page.total
            for (rawID, count) in snapshot.page.childCounts {
                counts[HolyArchiveSourceMetadata.namespacedID(rawID, hostID: snapshot.host.id)] = count
            }
        }
        return .init(
            sessions: sessions,
            total: total,
            childCounts: counts,
            notices: notices(hosts: hosts, snapshots: snapshots, policy: policy)
        )
    }

    func search(
        hosts: [HolyArchiveRemoteHost],
        query: HolyArchiveSearchQuery,
        semanticQueryVector: [Float]? = nil,
        limit: Int,
        policy: HolyArchiveRemoteLoadPolicy
    ) async -> HolyArchiveFederatedSearch {
        let request = HolyArchiveRemoteRequest.search(
            query: query,
            semanticQueryVector: semanticQueryVector,
            limit: limit
        )
        let snapshots = await snapshots(hosts: hosts, request: request, policy: policy)
        var results: [HolyArchiveSearchResult] = []
        var children: [String: [HolyArchiveSession]] = [:]
        var counts: [String: Int] = [:]
        for snapshot in snapshots {
            for remote in snapshot.page.sessions {
                let converted = session(remote, snapshot: snapshot)
                let match = snapshot.page.matches[remote.id]
                results.append(.init(
                    session: converted,
                    score: match?.score ?? 1,
                    keywordScore: match?.keywordScore,
                    semanticScore: match?.semanticScore,
                    matchSnippet: match?.snippet,
                    matchSource: match.flatMap { HolyArchiveMatchSource(rawValue: $0.source) } ?? .metadata
                ))
            }
            for (rawParentID, remoteChildren) in snapshot.page.matchingChildren {
                let parentID = HolyArchiveSourceMetadata.namespacedID(rawParentID, hostID: snapshot.host.id)
                children[parentID] = remoteChildren.map { session($0, snapshot: snapshot) }
            }
            for (rawID, count) in snapshot.page.childCounts {
                counts[HolyArchiveSourceMetadata.namespacedID(rawID, hostID: snapshot.host.id)] = count
            }
        }
        return .init(
            results: results,
            matchingChildren: children,
            childCounts: counts,
            notices: notices(hosts: hosts, snapshots: snapshots, policy: policy)
        )
    }

    func children(
        of session: HolyArchiveSession,
        policy: HolyArchiveRemoteLoadPolicy = .refresh
    ) async -> [HolyArchiveSession] {
        guard let host = remoteHost(for: session) else { return [] }
        let request = HolyArchiveRemoteRequest.children(parentID: session.providerSessionID)
        guard let snapshot = await snapshot(host: host, request: request, policy: policy) else { return [] }
        return snapshot.page.sessions.map { self.session($0, snapshot: snapshot) }
    }

    func messages(
        for session: HolyArchiveSession,
        policy: HolyArchiveRemoteLoadPolicy = .refresh
    ) async -> [HolyArchiveMessage] {
        guard let host = remoteHost(for: session) else { return [] }
        var offset = 0
        var result: [HolyArchiveMessage] = []
        while true {
            let request = HolyArchiveRemoteRequest.messages(
                sessionID: session.providerSessionID,
                offset: offset
            )
            guard let snapshot = await snapshot(host: host, request: request, policy: policy) else {
                return result
            }
            result += snapshot.page.messages.map { remote in
                .init(
                    id: HolyArchiveSourceMetadata.namespacedID(remote.id, hostID: host.id),
                    sessionID: session.id,
                    role: HolyArchiveMessageRole(rawValue: remote.role) ?? .unknown,
                    content: remote.content,
                    timestamp: remote.timestamp.map(Date.init(timeIntervalSince1970:)),
                    sequence: remote.sequence
                )
            }
            offset += snapshot.page.messages.count
            if snapshot.page.messages.isEmpty || offset >= snapshot.page.total { break }
            if policy == .cacheOnly { continue }
        }
        return result
    }

    func annotations(
        for session: HolyArchiveSession,
        policy: HolyArchiveRemoteLoadPolicy = .refresh
    ) async -> [HolyArchiveAnnotation] {
        guard let host = remoteHost(for: session) else { return [] }
        let request = HolyArchiveRemoteRequest.annotations(sessionID: session.providerSessionID)
        guard let snapshot = await snapshot(host: host, request: request, policy: policy) else { return [] }
        return snapshot.page.annotations.map { remote in
            .init(
                id: remote.id,
                sessionID: session.id,
                timestamp: Date(timeIntervalSince1970: remote.timestamp),
                kind: HolyArchiveAnnotation.Kind(rawValue: remote.kind) ?? .note,
                value: remote.value,
                source: remote.source
            )
        }
    }

    private func snapshots(
        hosts: [HolyArchiveRemoteHost],
        request: HolyArchiveRemoteRequest,
        policy: HolyArchiveRemoteLoadPolicy
    ) async -> [HolyArchiveRemoteSnapshot] {
        await withTaskGroup(of: HolyArchiveRemoteSnapshot?.self) { group in
            for host in hosts where host.sshDestination.holyArchiveNilIfBlank != nil {
                group.addTask { await self.snapshot(host: host, request: request, policy: policy) }
            }
            var values: [HolyArchiveRemoteSnapshot] = []
            for await value in group {
                if let value { values.append(value) }
            }
            return values.sorted { $0.host.label.localizedCaseInsensitiveCompare($1.host.label) == .orderedAscending }
        }
    }

    private func snapshot(
        host: HolyArchiveRemoteHost,
        request: HolyArchiveRemoteRequest,
        policy: HolyArchiveRemoteLoadPolicy
    ) async -> HolyArchiveRemoteSnapshot? {
        let cached = loadCache(host: host, request: request)
        if policy == .cacheOnly {
            return cached.map { envelope in
                .init(
                    host: host,
                    page: envelope.page,
                    fetchedAt: Date(timeIntervalSince1970: envelope.fetchedAt),
                    isStale: now().timeIntervalSince1970 - envelope.fetchedAt > Self.freshnessInterval,
                    error: nil
                )
            }
        }
        do {
            let page = try await queryClient.query(request, on: host)
            let fetchedAt = now()
            var cacheError: String?
            do {
                try saveCache(
                    .init(fetchedAt: fetchedAt.timeIntervalSince1970, page: page),
                    host: host,
                    request: request
                )
                await pacer.yield(afterWritingRows: page.rowCount)
            } catch {
                cacheError = "Offline cache update failed: \(error.localizedDescription)"
            }
            return .init(
                host: host,
                page: page,
                fetchedAt: fetchedAt,
                isStale: false,
                error: cacheError
            )
        } catch {
            guard let cached else { return nil }
            return .init(
                host: host,
                page: cached.page,
                fetchedAt: Date(timeIntervalSince1970: cached.fetchedAt),
                isStale: true,
                error: error.localizedDescription
            )
        }
    }

    private func notices(
        hosts: [HolyArchiveRemoteHost],
        snapshots: [HolyArchiveRemoteSnapshot],
        policy: HolyArchiveRemoteLoadPolicy
    ) -> [String] {
        guard policy == .refresh else { return [] }
        let byHost = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.host.id, $0) })
        return hosts.compactMap { host in
            if let snapshot = byHost[host.id], snapshot.isStale {
                return "\(host.label) is offline; showing its cached archive from \(Self.cacheStamp(snapshot.fetchedAt))."
            }
            if let snapshot = byHost[host.id], snapshot.error != nil {
                return "\(host.label) is live, but its offline archive cache could not update."
            }
            if byHost[host.id] == nil {
                return "\(host.label) archive is unavailable and has no cached page yet."
            }
            return nil
        }
    }

    private func session(
        _ remote: HolyArchiveRemoteSession,
        snapshot: HolyArchiveRemoteSnapshot
    ) -> HolyArchiveSession {
        var extra = remote.extra
        extra[HolyArchiveSourceMetadata.rawSessionID] = remote.id
        extra[HolyArchiveSourceMetadata.hostID] = snapshot.host.id.uuidString
        extra[HolyArchiveSourceMetadata.hostLabel] = snapshot.host.label
        extra[HolyArchiveSourceMetadata.sshDestination] = snapshot.host.sshDestination
        extra[HolyArchiveSourceMetadata.tmuxSocketName] = snapshot.host.tmuxSocketName
        extra[HolyArchiveSourceMetadata.fetchedAt] = String(snapshot.fetchedAt.timeIntervalSince1970)
        extra[HolyArchiveSourceMetadata.stale] = snapshot.isStale ? "true" : "false"
        extra[HolyArchiveSourceMetadata.error] = snapshot.error
        return .init(
            id: HolyArchiveSourceMetadata.namespacedID(remote.id, hostID: snapshot.host.id),
            harness: HolyArchiveHarness(rawValue: remote.harness) ?? .claudeCode,
            rawPath: remote.rawPath,
            projectPath: remote.projectPath,
            projectName: remote.projectName,
            title: remote.title,
            firstPrompt: remote.firstPrompt,
            lastPrompt: remote.lastPrompt,
            lastResponse: remote.lastResponse,
            createdAt: Date(timeIntervalSince1970: remote.createdAt),
            modifiedAt: remote.modifiedAt.map(Date.init(timeIntervalSince1970:)),
            isChild: remote.isChild,
            childType: remote.childType,
            parentID: remote.parentID.map {
                HolyArchiveSourceMetadata.namespacedID($0, hostID: snapshot.host.id)
            },
            model: remote.model,
            toolCalls: remote.toolCalls,
            tokensUsed: remote.tokensUsed,
            summary: remote.summary,
            contentHash: remote.contentHash,
            extra: extra,
            resumeCommand: remote.resumeCommand,
            messageCount: remote.messageCount,
            turnCount: remote.turnCount,
            fileMTime: Date(timeIntervalSince1970: remote.fileMTime),
            indexedAt: Date(timeIntervalSince1970: remote.indexedAt),
            autoTags: remote.autoTags
        )
    }

    private func remoteHost(for session: HolyArchiveSession) -> HolyArchiveRemoteHost? {
        let source = session.archiveSource
        guard let id = source.hostID, let destination = source.sshDestination else { return nil }
        return .init(
            id: id,
            label: source.hostLabel,
            sshDestination: destination,
            tmuxSocketName: source.tmuxSocketName
        )
    }

    private func loadCache(
        host: HolyArchiveRemoteHost,
        request: HolyArchiveRemoteRequest
    ) -> HolyArchiveRemoteCacheEnvelope? {
        try? decoder.decode(
            HolyArchiveRemoteCacheEnvelope.self,
            from: Data(contentsOf: cacheURL(host: host, request: request))
        )
    }

    private func saveCache(
        _ envelope: HolyArchiveRemoteCacheEnvelope,
        host: HolyArchiveRemoteHost,
        request: HolyArchiveRemoteRequest
    ) throws {
        try FileManager.default.createDirectory(
            at: cacheDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let url = cacheURL(host: host, request: request)
        try encoder.encode(envelope).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func cacheURL(
        host: HolyArchiveRemoteHost,
        request: HolyArchiveRemoteRequest
    ) -> URL {
        let requestData = (try? encoder.encode(request)) ?? Data()
        let digest = SHA256.hash(data: requestData).map { String(format: "%02x", $0) }.joined()
        return cacheDirectoryURL.appendingPathComponent(
            "\(host.id.uuidString.lowercased())-\(digest).json",
            isDirectory: false
        )
    }

    private static func cacheStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

enum HolyArchiveResumeLaunchSpec {
    static func make(for session: HolyArchiveSession) -> HolySessionLaunchSpec? {
        let source = session.archiveSource
        guard let runtime = session.harness.runtime,
              let command = HolyRestoreCommandBuilder.renderedResumeCommand(
                  runtime: runtime,
                  providerSessionID: source.providerSessionID
              ) else { return nil }
        var spec = HolySessionLaunchSpec.interactiveTmuxShell(title: session.displayTitle)
        spec.runtime = runtime
        spec.objective = "Resume archived \(session.harness.displayName) conversation \(session.shortID)"
        spec.workingDirectory = session.projectPath
        spec.command = command
        spec.initialInput = nil
        spec.providerSessionID = source.providerSessionID
        if source.isRemote, let destination = source.sshDestination?.holyArchiveNilIfBlank {
            spec.transport = .init(
                kind: .ssh,
                hostLabel: source.hostLabel,
                sshDestination: destination
            )
            if let socketName = source.tmuxSocketName?.holyArchiveNilIfBlank {
                spec.tmux?.socketName = socketName
            }
        }
        return spec
    }
}
