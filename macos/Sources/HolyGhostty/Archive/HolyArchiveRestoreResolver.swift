import Foundation

/// Crash restore's production resolver. It reads and refreshes the same
/// in-process archive that the native browser shows, so restore cannot disagree
/// with the visible history or depend on a second executable's cache.
struct HolyArchiveRestoreResolver: HolyRestoreBatchResolving, HolyRestoreResolving {
    static let defaultWindow: TimeInterval = 48 * 60 * 60
    static let defaultLimit = 5
    static let batchLimit = 10
    static let ambiguitySeconds: TimeInterval = 120
    static let claimInterval: TimeInterval = 120

    private let databaseURL: URL
    private let registry: HolyArchiveProviderRegistry

    init(
        databaseURL: URL = HolyDatabasePaths.databaseURL,
        registry: HolyArchiveProviderRegistry = .init()
    ) {
        self.databaseURL = databaseURL
        self.registry = registry
    }

    func resolve(_ query: HolyRestoreResolveQuery) async -> HolyRestoreResolveOutcome {
        let request = HolyRestoreResolveBatchRequest(
            cwd: query.workingDirectory,
            harness: query.harness,
            near: query.nearUnixSeconds
        )
        switch Self.validate(request) {
        case let .failure(_, message):
            return .resolverUnavailable(message)
        case let .success(_, harness, runtime, path):
            do {
                // The single-resolve contract is lookup-only. Batch restore is
                // the sole owner of refresh so a cold boot cannot launch one
                // archive crawl per roster row.
                let repository = try HolyArchiveRepository(databaseURL: databaseURL)
                let near = TimeInterval(query.nearUnixSeconds)
                let candidates = try repository.resolveCandidates(
                    projectPath: path,
                    harness: harness,
                    near: Date(timeIntervalSince1970: near),
                    window: TimeInterval(max(0, query.windowSeconds ?? Int(Self.defaultWindow))),
                    limit: max(0, query.limit ?? Self.defaultLimit)
                ).map(Self.candidate)
                let confidence = Self.confidence(candidates: candidates, near: near)
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
        _ requests: [HolyRestoreResolveBatchRequest]
    ) async -> HolyRestoreBatchResolveOutcome {
        guard !requests.isEmpty else { return .resolved([]) }
        do {
            let repository = try HolyArchiveRepository(databaseURL: databaseURL)
            let indexer = HolyArchiveIndexer(repository: repository, registry: registry, embedder: nil)
            let validated = requests.map(Self.validate)
            await refreshStaleScopes(validated, repository: repository, indexer: indexer)
            var results: [HolyRestoreResolveBatchResult] = []
            for item in validated {
                switch item {
                case let .failure(request, message):
                    results.append(.init(
                        cwd: request.cwd, harness: request.harness, runtime: request.harness,
                        candidates: [], error: message
                    ))
                case let .success(request, harness, runtime, path):
                    let sessions = try repository.resolveCandidates(
                        projectPath: path,
                        harness: harness,
                        near: Date(timeIntervalSince1970: TimeInterval(request.near)),
                        window: Self.defaultWindow,
                        limit: Self.batchLimit
                    )
                    results.append(.init(
                        cwd: request.cwd,
                        harness: harness.rawValue,
                        runtime: runtime,
                        candidates: sessions.map(Self.candidate),
                        error: nil
                    ))
                }
            }
            return .resolved(results)
        } catch {
            return .resolverUnavailable("Native archive resolution failed: \(error.localizedDescription)")
        }
    }

    private func refreshStaleScopes(
        _ validated: [ValidatedRequest],
        repository: HolyArchiveRepository,
        indexer: HolyArchiveIndexer
    ) async {
        let grouped = Dictionary(grouping: validated.compactMap { value -> Scope? in
            guard case let .success(request, harness, _, path) = value,
                  let provider = registry.provider(for: harness) else { return nil }
            return .init(request: request, harness: harness, path: path, provider: provider)
        }, by: \.harness)

        for (_, scopes) in grouped {
            guard let provider = scopes.first?.provider else { continue }
            var stale: [Scope] = []
            for scope in scopes {
                do {
                    let candidates = try repository.resolveCandidates(
                        projectPath: scope.path,
                        harness: scope.harness,
                        near: Date(timeIntervalSince1970: TimeInterval(scope.request.near)),
                        window: Self.defaultWindow,
                        limit: 1
                    )
                    if isStale(candidates.first, provider: provider) { stale.append(scope) }
                } catch {
                    continue
                }
            }
            guard !stale.isEmpty else { continue }

            var scopedPaths: [URL] = []
            var needsWholeProvider = false
            for scope in stale {
                let discovered: [URL]?
                do {
                    discovered = try provider.discoverSessionFiles(forProjectPath: scope.path)
                } catch {
                    continue
                }
                guard let discovered else {
                    needsWholeProvider = true
                    continue
                }
                // An empty discovery must not consume the 120-second claim.
                guard !discovered.isEmpty else { continue }
                let claim = "resolve_reindex:\(scope.harness.rawValue):\(scope.path)"
                if (try? repository.acquireReindexClaim(
                    key: claim, interval: Self.claimInterval
                )) == true {
                    scopedPaths.append(contentsOf: discovered)
                }
            }

            if needsWholeProvider {
                let claim = "resolve_reindex:\(provider.harness.rawValue):*"
                if (try? repository.acquireReindexClaim(
                    key: claim, interval: Self.claimInterval
                )) == true,
                   let paths = try? provider.discoverSessionFiles() {
                    _ = await indexer.indexPaths(provider: provider, paths: paths)
                }
            } else if !scopedPaths.isEmpty {
                var seen = Set<String>()
                let unique = scopedPaths.filter { seen.insert($0.path).inserted }
                _ = await indexer.indexPaths(provider: provider, paths: unique)
            }
        }
    }

    private func isStale(
        _ candidate: HolyArchiveSession?,
        provider: any HolyArchiveProviding
    ) -> Bool {
        guard let candidate else { return true }
        do {
            let current = try provider.modificationDate(for: URL(fileURLWithPath: candidate.rawPath))
            return !HolyArchiveFileTime.matches(current, candidate.fileMTime)
        } catch {
            return true
        }
    }

    private static func validate(_ request: HolyRestoreResolveBatchRequest) -> ValidatedRequest {
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

    private static func candidate(_ session: HolyArchiveSession) -> HolyRestoreResolveCandidate {
        .init(
            id: session.id,
            timestampEnd: Int(session.activityAt.timeIntervalSince1970),
            preview: HolyArchiveText.preview(session.firstPrompt, limit: 120),
            resumeCommand: session.resumeCommand
        )
    }

    private static func confidence(
        candidates: [HolyRestoreResolveCandidate],
        near: TimeInterval
    ) -> HolyRestoreResolution.Confidence {
        guard let first = candidates.first else { return .none }
        guard candidates.count > 1 else { return .exact }
        let firstDistance = abs(TimeInterval(first.timestampEnd) - near)
        let secondDistance = abs(TimeInterval(candidates[1].timestampEnd) - near)
        return secondDistance - firstDistance > ambiguitySeconds ? .exact : .ambiguous
    }

    private struct Scope: Sendable {
        let request: HolyRestoreResolveBatchRequest
        let harness: HolyArchiveHarness
        let path: String
        let provider: any HolyArchiveProviding
    }

    private enum ValidatedRequest: Sendable {
        case success(HolyRestoreResolveBatchRequest, HolyArchiveHarness, runtime: String, path: String)
        case failure(HolyRestoreResolveBatchRequest, String)
    }
}
