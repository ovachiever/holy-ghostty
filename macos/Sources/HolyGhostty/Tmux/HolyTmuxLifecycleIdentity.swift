import Foundation

/// A tmux target observed from a live server. Unlike a launch spec, this value
/// is never allowed to synthesize a session name or guess a socket namespace.
struct HolyTmuxLiveIdentity: Equatable {
    let transport: HolySessionTransportSpec
    let socketName: String?
    let sessionName: String

    init?(
        transport: HolySessionTransportSpec,
        socketName: String?,
        sessionName: String
    ) {
        let normalizedTransport = transport.normalized
        let normalizedSessionName = sessionName.holyLifecycleTrimmed
        guard !normalizedSessionName.isEmpty else { return nil }
        if normalizedTransport.isRemote,
           normalizedTransport.sshDestination?.holyLifecycleTrimmed.nilIfEmpty == nil {
            return nil
        }

        self.transport = normalizedTransport
        self.socketName = socketName?.holyLifecycleTrimmed.nilIfEmpty
        self.sessionName = normalizedSessionName
    }

    init?(
        transport: HolySessionTransportSpec,
        discoveredSession: HolyDiscoveredTmuxSession
    ) {
        let normalizedTransport = transport.normalized
        let sessionName = discoveredSession.sessionName.holyLifecycleTrimmed
        guard !sessionName.isEmpty else { return nil }

        if normalizedTransport.isRemote {
            guard let expectedDestination = normalizedTransport.sshDestination?.holyLifecycleTrimmed.nilIfEmpty,
                  expectedDestination.caseInsensitiveCompare(discoveredSession.hostDestination.holyLifecycleTrimmed) == .orderedSame else {
                return nil
            }
        }

        self.init(
            transport: normalizedTransport,
            socketName: discoveredSession.tmuxSocketName,
            sessionName: sessionName
        )
    }
}

enum HolyTmuxIdentityResolution: Equatable {
    case matched(HolyDiscoveredTmuxSession)
    case notFound
    case ambiguous
}

/// Resolves incomplete legacy launch specs against the live tmux inventory.
/// Resolution is deliberately fail-closed: a missing name must have unique,
/// stable metadata evidence before Holy may target a session.
enum HolyTmuxIdentityResolver {
    private struct MetadataEvidence {
        var matchCount = 0
        var strongMatchCount = 0
        var hasContradiction = false

        var authorizesMissingNameResolution: Bool {
            !hasContradiction && strongMatchCount >= 1 && matchCount >= 2
        }
    }

    static func resolve(
        launchSpec: HolySessionLaunchSpec,
        among discoveredSessions: [HolyDiscoveredTmuxSession]
    ) -> HolyTmuxIdentityResolution {
        guard let storedTmux = launchSpec.tmux?.normalized else {
            return .notFound
        }

        let candidates = discoveredSessions.filter {
            couldRefer(launchSpec: launchSpec, to: $0)
        }

        guard !candidates.isEmpty else { return .notFound }

        // A persisted session name is already a stable tmux identity. A missing
        // socket can be recovered only when that name occurs once across the
        // namespaces discovery actually inspected.
        if storedTmux.sessionName?.holyLifecycleTrimmed.nilIfEmpty != nil {
            return uniqueResolution(candidates)
        }

        let evidenced = candidates.map { candidate in
            (candidate, metadataEvidence(launchSpec: launchSpec, discovered: candidate))
        }
        let authorized = evidenced.filter { $0.1.authorizesMissingNameResolution }
        guard let bestScore = authorized.map({ $0.1.matchCount }).max() else {
            return candidates.count > 1 ? .ambiguous : .notFound
        }

        let bestMatches = authorized.filter { $0.1.matchCount == bestScore }.map(\.0)
        return uniqueResolution(bestMatches)
    }

    /// Rejects global collisions after per-record resolution. If two records
    /// independently select the same live tmux identity, neither is assigned;
    /// callers must surface the ambiguity instead of duplicating or retargeting
    /// a session.
    static func resolveOneToOne(
        launchSpecsByID: [UUID: HolySessionLaunchSpec],
        among discoveredSessions: [HolyDiscoveredTmuxSession]
    ) -> [UUID: HolyDiscoveredTmuxSession] {
        let candidates: [(id: UUID, session: HolyDiscoveredTmuxSession, key: String)] = launchSpecsByID.compactMap { id, launchSpec in
            guard case let .matched(session) = resolve(
                launchSpec: launchSpec,
                among: discoveredSessions
            ) else { return nil }
            return (id, session, liveIdentityKey(transport: launchSpec.transport, session: session))
        }
        let counts = Dictionary(grouping: candidates, by: \.key).mapValues(\.count)
        return Dictionary(uniqueKeysWithValues: candidates.compactMap { candidate in
            guard counts[candidate.key] == 1 else { return nil }
            return (candidate.id, candidate.session)
        })
    }

    /// Broad compatibility used only to reserve an unresolved live identity
    /// from archive adoption. It does not authorize targeting or mutation.
    static func couldRefer(
        launchSpec: HolySessionLaunchSpec,
        to discovered: HolyDiscoveredTmuxSession
    ) -> Bool {
        guard let storedTmux = launchSpec.tmux?.normalized,
              transportMatches(launchSpec.transport, discovered: discovered) else {
            return false
        }

        if let storedSocket = storedTmux.socketName?.holyLifecycleTrimmed.nilIfEmpty,
           storedSocket != (discovered.tmuxSocketName?.holyLifecycleTrimmed.nilIfEmpty ?? "") {
            return false
        }

        if let storedName = storedTmux.sessionName?.holyLifecycleTrimmed.nilIfEmpty,
           storedName != discovered.sessionName.holyLifecycleTrimmed {
            return false
        }

        return true
    }

    private static func uniqueResolution(
        _ candidates: [HolyDiscoveredTmuxSession]
    ) -> HolyTmuxIdentityResolution {
        guard candidates.count == 1, let candidate = candidates.first else {
            return candidates.isEmpty ? .notFound : .ambiguous
        }
        return .matched(candidate)
    }

    private static func liveIdentityKey(
        transport: HolySessionTransportSpec,
        session: HolyDiscoveredTmuxSession
    ) -> String {
        let normalizedTransport = transport.normalized
        let scheme = normalizedTransport.isRemote ? "ssh" : "local"
        let destination = normalizedTransport.isRemote
            ? session.hostDestination.holyLifecycleTrimmed.lowercased()
            : "local"
        let socket = session.tmuxSocketName?.holyLifecycleTrimmed.nilIfEmpty ?? "<default>"
        return [scheme, destination, socket, session.sessionName.holyLifecycleTrimmed]
            .joined(separator: "|")
    }

    private static func transportMatches(
        _ transport: HolySessionTransportSpec,
        discovered: HolyDiscoveredTmuxSession
    ) -> Bool {
        let normalized = transport.normalized
        guard normalized.isRemote else {
            return discovered.hostDestination.caseInsensitiveCompare("localhost") == .orderedSame
                || discovered.hostDestination.caseInsensitiveCompare("local") == .orderedSame
        }

        guard let destination = normalized.sshDestination?.holyLifecycleTrimmed.nilIfEmpty else {
            return false
        }
        return destination.caseInsensitiveCompare(discovered.hostDestination.holyLifecycleTrimmed) == .orderedSame
    }

    private static func metadataEvidence(
        launchSpec: HolySessionLaunchSpec,
        discovered: HolyDiscoveredTmuxSession
    ) -> MetadataEvidence {
        var evidence = MetadataEvidence()

        if let storedTitle = stableTitle(launchSpec.title),
           let discoveredTitle = stableTitle(discovered.title) {
            if storedTitle.caseInsensitiveCompare(discoveredTitle) == .orderedSame {
                evidence.matchCount += 1
            } else {
                evidence.hasContradiction = true
            }
        }

        if launchSpec.runtime != .shell, let discoveredRuntime = discovered.runtime {
            if discoveredRuntime == launchSpec.runtime {
                evidence.matchCount += 1
            } else {
                evidence.hasContradiction = true
            }
        }

        compare(
            normalized(launchSpec.objective),
            normalized(discovered.objective),
            isStrong: true,
            evidence: &evidence
        )
        compare(
            normalizedPath(launchSpec.workingDirectory),
            normalizedPath(discovered.workingDirectory),
            isStrong: true,
            evidence: &evidence
        )
        compare(
            normalized(launchSpec.command),
            normalized(discovered.bootstrapCommand),
            isStrong: true,
            evidence: &evidence
        )

        if let task = launchSpec.task {
            compare(
                normalized(task.title),
                normalized(discovered.taskTitle),
                isStrong: true,
                evidence: &evidence
            )
            compare(
                normalized(task.sourceLabel),
                normalized(discovered.taskSource),
                isStrong: false,
                evidence: &evidence
            )
        }

        return evidence
    }

    private static func compare(
        _ stored: String?,
        _ discovered: String?,
        isStrong: Bool,
        evidence: inout MetadataEvidence
    ) {
        guard let stored, let discovered else { return }
        if stored == discovered {
            evidence.matchCount += 1
            if isStrong {
                evidence.strongMatchCount += 1
            }
        } else {
            evidence.hasContradiction = true
        }
    }

    private static func stableTitle(_ value: String?) -> String? {
        guard let title = normalized(value) else { return nil }
        let lowercased = title.lowercased()
        if ["shell", "claude", "codex", "opencode", "local", "this mac"].contains(lowercased) {
            return nil
        }
        if lowercased.range(of: #"^shell\s+\d+$"#, options: .regularExpression) != nil {
            return nil
        }
        return title
    }

    private static func normalized(_ value: String?) -> String? {
        value?.holyLifecycleTrimmed.nilIfEmpty?.lowercased()
    }

    private static func normalizedPath(_ value: String?) -> String? {
        guard let value = value?.holyLifecycleTrimmed.nilIfEmpty else { return nil }
        return URL(fileURLWithPath: value).standardizedFileURL.path
    }
}

private extension String {
    var holyLifecycleTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
