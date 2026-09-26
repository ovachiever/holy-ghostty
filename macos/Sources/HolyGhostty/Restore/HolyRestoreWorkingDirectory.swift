import Foundation

/// Where a restored session will run, and where that answer came from.
///
/// A row carries several recorded directories: the pane's last observed
/// directory (discovery-inferred, which is how row 985BC829 came to claim
/// a folder named after its pane title on 2026-09-26), the directory the
/// session was launched in, the git worktree, the repository root. Any of
/// them can vanish or be wrong. The resolution evaluates them in evidence
/// order, restores into the first that exists, and names the source so a
/// human can see when the obvious answer was not the one used.
struct HolyRestoreWorkingDirectoryResolution: Equatable, Sendable {
    enum Source: String, Codable, Equatable, Sendable {
        /// The pane's working directory as last observed (resume metadata).
        case lastKnownDirectory
        /// The directory the session was launched in (launch spec).
        case launchDirectory
        /// The git worktree the session's snapshot recorded.
        case gitWorktree
        /// The repository root the launch spec recorded.
        case repositoryRoot
        /// The parent of a recorded directory whose leaf no longer exists —
        /// the last known valid directory when every recorded path is gone.
        case parentOfLastKnownDirectory
        case parentOfLaunchDirectory

        var displayName: String {
            switch self {
            case .lastKnownDirectory: return "last known directory"
            case .launchDirectory: return "launch directory"
            case .gitWorktree: return "git worktree"
            case .repositoryRoot: return "repository root"
            case .parentOfLastKnownDirectory: return "parent of the last known directory"
            case .parentOfLaunchDirectory: return "parent of the launch directory"
            }
        }
    }

    struct Candidate: Equatable, Sendable {
        let path: String
        let source: Source
        let exists: Bool
    }

    /// Every distinct recorded directory, evidence order, existence checked.
    let candidates: [Candidate]

    var chosen: Candidate? { candidates.first(where: \.exists) }
    var path: String? { chosen?.path }
    var source: Source? { chosen?.source }
    /// The candidates that would have been preferred over the chosen one.
    var missingBeforeChosen: [Candidate] {
        guard let chosen else { return candidates }
        return Array(candidates.prefix { $0 != chosen })
    }
    var usedFallback: Bool { !missingBeforeChosen.isEmpty && chosen != nil }
    var hasRecordedDirectory: Bool { !candidates.isEmpty }

    static let empty = HolyRestoreWorkingDirectoryResolution(candidates: [])

    static func resolve(
        lastKnownWorkingDirectory: String?,
        launchWorkingDirectory: String?,
        gitWorktreePath: String?,
        repositoryRoot: String?,
        directoryExists: (String) -> Bool
    ) -> HolyRestoreWorkingDirectoryResolution {
        let recorded: [(String?, Source)] = [
            (lastKnownWorkingDirectory, .lastKnownDirectory),
            (launchWorkingDirectory, .launchDirectory),
            (gitWorktreePath, .gitWorktree),
            (repositoryRoot, .repositoryRoot),
        ]

        var seen: Set<String> = []
        var candidates: [Candidate] = []
        func append(_ raw: String?, _ source: Source) {
            guard let path = normalized(raw), seen.insert(path).inserted else { return }
            candidates.append(.init(path: path, source: source, exists: directoryExists(path)))
        }
        for (raw, source) in recorded {
            append(raw, source)
        }

        // Parents only when nothing recorded exists: they are the last
        // known VALID directory, never a preference over a real record.
        if !candidates.contains(where: \.exists) {
            let parents: [(String?, Source)] = [
                (lastKnownWorkingDirectory, .parentOfLastKnownDirectory),
                (launchWorkingDirectory, .parentOfLaunchDirectory),
            ]
            for (raw, source) in parents {
                guard let path = normalized(raw) else { continue }
                let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
                guard parent != path, parent != "/" else { continue }
                append(parent, source)
            }
        }

        return .init(candidates: candidates)
    }

    private static func normalized(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: trimmed).standardizedFileURL.path
    }

    /// The directory line the row shows: the path restore will use, and
    /// where it came from whenever that is not the first recorded answer.
    var displayLine: String {
        guard let first = candidates.first else { return "Unassigned" }
        guard let chosen else {
            return "\(first.path) — \(first.source.displayName), no longer exists"
        }
        guard usedFallback, let skipped = missingBeforeChosen.first else {
            return chosen.path
        }
        return "\(chosen.path) — \(chosen.source.displayName) "
            + "(\(skipped.source.displayName) \(skipped.path) no longer exists)"
    }

    /// The blocked verdict when nothing recorded exists: every source named.
    var missingReason: String {
        guard hasRecordedDirectory else {
            return "No working directory was recorded for this session."
        }
        let named = candidates.map { "\($0.source.displayName) \($0.path)" }
        return "The working directory no longer exists — " + named.joined(separator: "; ") + "."
    }
}
