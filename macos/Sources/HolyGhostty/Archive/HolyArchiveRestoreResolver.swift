import Foundation

/// Crash restore's production resolver. It reads and refreshes the same
/// in-process archive that the native browser shows, so restore cannot disagree
/// with the visible history or depend on a second executable's cache.
///
/// Every lookup, staleness check, provider read, and archive write runs on
/// `HolyArchiveRestoreResolutionWorker`, an actor with its own executor. The
/// engine that calls `resolveBatch` is `@MainActor`; nothing here inherits
/// that isolation, whichever nonisolated-async default the calling module is
/// compiled with. The caller's actor only ever awaits.
struct HolyArchiveRestoreResolver: HolyRestoreBatchResolving, HolyRestoreResolving {
    typealias Progress = @Sendable (HolyArchiveIndexProgress) async -> Void

    static let defaultWindow: TimeInterval = 48 * 60 * 60
    static let defaultLimit = 5
    static let batchLimit = 10
    static let ambiguitySeconds: TimeInterval = 120
    static let claimInterval: TimeInterval = 120

    private let databaseURL: URL
    private let legacyDatabaseURL: URL?
    private let registry: HolyArchiveProviderRegistry
    private let progress: Progress?
    private let accounting: HolyArchiveWriteAccounting

    init(
        databaseURL: URL = HolyDatabasePaths.archiveDatabaseURL,
        legacyDatabaseURL: URL? = nil,
        registry: HolyArchiveProviderRegistry = .init(),
        progress: Progress? = nil,
        accounting: HolyArchiveWriteAccounting = .shared
    ) {
        self.databaseURL = databaseURL
        self.legacyDatabaseURL = legacyDatabaseURL ?? (
            databaseURL.standardizedFileURL == HolyDatabasePaths.archiveDatabaseURL.standardizedFileURL
                ? HolyDatabasePaths.databaseURL
                : nil
        )
        self.registry = registry
        self.progress = progress
        self.accounting = accounting
    }

    func resolve(_ query: HolyRestoreResolveQuery) async -> HolyRestoreResolveOutcome {
        await makeWorker().resolve(query)
    }

    func resolveBatch(
        _ requests: [HolyRestoreResolveBatchRequest]
    ) async -> HolyRestoreBatchResolveOutcome {
        await resolveBatch(requests, progress: progress)
    }

    /// The `HolyRestoreBatchResolving` contract with a progress channel. The
    /// sheet can show every pending row as resolving the moment this is
    /// called and narrate the refresh (`.discovering`, then the indexer's
    /// `.indexing` per file, then `.finishing`); results are positional, one
    /// per request, exactly as `resolveBatch(_:)` returns them.
    func resolveBatch(
        _ requests: [HolyRestoreResolveBatchRequest],
        progress: Progress?
    ) async -> HolyRestoreBatchResolveOutcome {
        await makeWorker().resolveBatch(requests, progress: progress)
    }

    private func makeWorker() -> HolyArchiveRestoreResolutionWorker {
        .init(
            databaseURL: databaseURL,
            legacyDatabaseURL: legacyDatabaseURL,
            registry: registry,
            accounting: accounting
        )
    }

    fileprivate static func validate(_ request: HolyRestoreResolveBatchRequest) -> ValidatedRequest {
        guard let path = request.cwd.holyArchiveNilIfBlank else {
            return .failure(request, "cwd must not be empty")
        }
        let mapping: (HolyArchiveHarness, String)? = switch request.harness.lowercased() {
        case "claude", "claude-code": (.claudeCode, "claude")
        case "codex": (.codex, "codex")
        case "opencode": (.opencode, "opencode")
        default: nil
        }
        guard let (harness, runtime) = mapping else {
            return .failure(request, "Unknown harness: \(request.harness)")
        }
        return .success(request, harness, runtime: runtime, path: canonicalPath(path))
    }

    private static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
            .standardizedFileURL.resolvingSymlinksInPath().path
    }

    fileprivate static func candidate(_ session: HolyArchiveSession) -> HolyRestoreResolveCandidate {
        .init(
            id: session.id,
            timestampEnd: Int(session.activityAt.timeIntervalSince1970),
            preview: HolyArchiveText.preview(session.firstPrompt, limit: 120),
            resumeCommand: session.resumeCommand
        )
    }

    fileprivate static func confidence(
        candidates: [HolyRestoreResolveCandidate],
        near: TimeInterval
    ) -> HolyRestoreResolution.Confidence {
        guard let first = candidates.first else { return .none }
        guard candidates.count > 1 else { return .exact }
        let firstDistance = abs(TimeInterval(first.timestampEnd) - near)
        let secondDistance = abs(TimeInterval(candidates[1].timestampEnd) - near)
        return secondDistance - firstDistance > ambiguitySeconds ? .exact : .ambiguous
    }
}

private enum ValidatedRequest: Sendable {
    case success(HolyRestoreResolveBatchRequest, HolyArchiveHarness, runtime: String, path: String)
    case failure(HolyRestoreResolveBatchRequest, String)
}

/// Owns one resolve call end to end. Being an actor, its methods run on the
/// global concurrent executor: the archive database, the provider stores,
/// and the indexer are never touched from the caller's actor.
actor HolyArchiveRestoreResolutionWorker {
    private let databaseURL: URL
    private let legacyDatabaseURL: URL?
    private let registry: HolyArchiveProviderRegistry
    private let accounting: HolyArchiveWriteAccounting

    init(
        databaseURL: URL,
        legacyDatabaseURL: URL?,
        registry: HolyArchiveProviderRegistry,
        accounting: HolyArchiveWriteAccounting
    ) {
        self.databaseURL = databaseURL
        self.legacyDatabaseURL = legacyDatabaseURL
        self.registry = registry
        self.accounting = accounting
    }

    func resolve(_ query: HolyRestoreResolveQuery) async -> HolyRestoreResolveOutcome {
        let request = HolyRestoreResolveBatchRequest(
            cwd: query.workingDirectory,
            harness: query.harness,
            near: query.nearUnixSeconds
        )
        switch HolyArchiveRestoreResolver.validate(request) {
        case let .failure(_, message):
            return .resolverUnavailable(message)
        case let .success(_, harness, runtime, path):
            do {
                // The single-resolve contract is lookup-only. Batch restore is
                // the sole owner of refresh so a cold boot cannot launch one
                // archive crawl per roster row. The one-time database move is
                // a storage prerequisite, not a provider refresh.
                try await prepareStorage()
                let repository = try HolyArchiveRepository(databaseURL: databaseURL, accounting: accounting)
                let near = TimeInterval(query.nearUnixSeconds)
                let candidates = try repository.resolveCandidates(
                    projectPath: path,
                    harness: harness,
                    near: Date(timeIntervalSince1970: near),
                    window: TimeInterval(max(0, query.windowSeconds ?? Int(HolyArchiveRestoreResolver.defaultWindow))),
                    limit: max(0, query.limit ?? HolyArchiveRestoreResolver.defaultLimit)
                ).map(HolyArchiveRestoreResolver.candidate)
                let confidence = HolyArchiveRestoreResolver.confidence(candidates: candidates, near: near)
                let matched = confidence == .exact ? candidates.first : nil
                return .resolved(.init(
                    matched: matched != nil,
                    providerSessionID: matched?.id,
                    harness: harness.rawValue,
                    runtime: runtime,
                    projectPath: path,
                    resumeCommand: matched?.resumeCommand,
                    confidence: confidence,
                    candidates: candidates
                ))
            } catch {
                return .resolverUnavailable(
                    "Native archive resolution failed: \(error.localizedDescription)"
                )
            }
        }
    }

    func resolveBatch(
        _ requests: [HolyRestoreResolveBatchRequest],
        progress: HolyArchiveRestoreResolver.Progress?
    ) async -> HolyRestoreBatchResolveOutcome {
        guard !requests.isEmpty else { return .resolved([]) }
        do {
            await progress?(.init(
                phase: .discovering,
                completed: 0,
                total: requests.count,
                detail: "Checking \(requests.count) archived conversation\(requests.count == 1 ? "" : "s")"
            ))
            try await prepareStorage()
            let repository = try HolyArchiveRepository(databaseURL: databaseURL, accounting: accounting)
            let indexer = HolyArchiveIndexer(repository: repository, registry: registry)
            let validated = requests.map(HolyArchiveRestoreResolver.validate)
            var candidates = try lookup(validated, repository: repository)
            let refreshed = await refreshStaleScopes(
                validated,
                candidates: candidates,
                repository: repository,
                indexer: indexer,
                progress: progress
            )
            if !refreshed.isEmpty {
                for (index, rows) in try lookup(validated, only: refreshed, repository: repository) {
                    candidates[index] = rows
                }
            }
            await progress?(.init(
                phase: .finishing,
                completed: requests.count,
                total: requests.count,
                detail: "Archive ready"
            ))

            var results: [HolyRestoreResolveBatchResult] = []
            for (index, item) in validated.enumerated() {
                switch item {
                case let .failure(request, message):
                    results.append(.init(
                        cwd: request.cwd, harness: request.harness, runtime: request.harness,
                        candidates: [], error: message
                    ))
                case let .success(request, harness, runtime, _):
                    results.append(.init(
                        cwd: request.cwd,
                        harness: harness.rawValue,
                        runtime: runtime,
                        candidates: (candidates[index] ?? []).map(HolyArchiveRestoreResolver.candidate),
                        error: nil
                    ))
                }
            }
            return .resolved(results)
        } catch {
            return .resolverUnavailable("Native archive resolution failed: \(error.localizedDescription)")
        }
    }

    private func prepareStorage() async throws {
        guard let legacyDatabaseURL else { return }
        let receipt = try await HolyArchiveLegacyDatabaseMigrator(
            sourceURL: legacyDatabaseURL,
            destinationURL: databaseURL
        ).migrateIfNeeded()
        guard receipt.didComplete else {
            throw HolyArchiveRestoreStorageError.migrationIncomplete
        }
    }

    /// Candidates per request index (successful requests only).
    private func lookup(
        _ validated: [ValidatedRequest],
        only: Set<Int>? = nil,
        repository: HolyArchiveRepository
    ) throws -> [Int: [HolyArchiveSession]] {
        var result: [Int: [HolyArchiveSession]] = [:]
        for (index, item) in validated.enumerated() {
            guard case let .success(request, harness, _, path) = item else { continue }
            if let only, !only.contains(index) { continue }
            result[index] = try repository.resolveCandidates(
                projectPath: path,
                harness: harness,
                near: Date(timeIntervalSince1970: TimeInterval(request.near)),
                window: HolyArchiveRestoreResolver.defaultWindow,
                limit: HolyArchiveRestoreResolver.batchLimit
            )
        }
        return result
    }

    /// Refreshes only the files behind the rows being resolved: the candidate
    /// sessions whose file changed since they were indexed, plus, for a
    /// provider that can narrow discovery to one project, that project's
    /// files (so a session the archive has never seen is found). Never a
    /// whole-provider walk: the retired `needsWholeProvider` path indexed
    /// every session of a provider for one stale row, and OpenCode alone
    /// holds 71,761 in the live archive. Returns the request indexes whose
    /// candidates must be looked up again.
    private func refreshStaleScopes(
        _ validated: [ValidatedRequest],
        candidates: [Int: [HolyArchiveSession]],
        repository: HolyArchiveRepository,
        indexer: HolyArchiveIndexer,
        progress: HolyArchiveRestoreResolver.Progress?
    ) async -> Set<Int> {
        var pathsByHarness: [HolyArchiveHarness: [URL]] = [:]
        var requestsByHarness: [HolyArchiveHarness: [Int]] = [:]
        for (index, item) in validated.enumerated() {
            guard case let .success(_, harness, _, path) = item,
                  let provider = registry.provider(for: harness) else { continue }
            // Keyed by canonical path so one file is one refresh, with the
            // spelling the archive already stores preferred over the one a
            // directory listing just produced.
            var scoped: [String: URL] = [:]
            for candidate in candidates[index] ?? [] where isStale(candidate, provider: provider) {
                let url = URL(fileURLWithPath: candidate.rawPath)
                scoped[HolyArchiveFilePath.canonical(url)] = url
            }
            if let discovered = try? provider.discoverSessionFiles(forProjectPath: path) {
                for url in discovered {
                    let key = HolyArchiveFilePath.canonical(url)
                    if scoped[key] == nil { scoped[key] = url }
                }
            }
            // An empty scope must not consume the 120-second claim.
            guard !scoped.isEmpty else { continue }
            let claim = "resolve_reindex:\(harness.rawValue):\(path)"
            guard (try? repository.acquireReindexClaim(
                key: claim, interval: HolyArchiveRestoreResolver.claimInterval
            )) == true else { continue }
            pathsByHarness[harness, default: []] += scoped.values.sorted { $0.path < $1.path }
            requestsByHarness[harness, default: []].append(index)
        }

        var refreshed = Set<Int>()
        for (harness, paths) in pathsByHarness {
            guard let provider = registry.provider(for: harness) else { continue }
            var seen = Set<String>()
            let unique = paths.filter { seen.insert(HolyArchiveFilePath.canonical($0)).inserted }
            _ = await indexer.indexPaths(provider: provider, paths: unique, progress: progress)
            refreshed.formUnion(requestsByHarness[harness] ?? [])
        }
        return refreshed
    }

    private func isStale(
        _ candidate: HolyArchiveSession,
        provider: any HolyArchiveProviding
    ) -> Bool {
        do {
            let current = try provider.modificationDate(for: URL(fileURLWithPath: candidate.rawPath))
            return !HolyArchiveFileTime.matches(current, candidate.fileMTime)
        } catch {
            return true
        }
    }
}

private enum HolyArchiveRestoreStorageError: LocalizedError {
    case migrationIncomplete

    var errorDescription: String? {
        "Archive storage migration paused before restore resolution could read a complete index."
    }
}
