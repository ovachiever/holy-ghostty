import Foundation

enum HolyGitFileChangeCategory: String, Codable, CaseIterable {
    case added
    case modified
    case deleted
    case renamed
    case copied
    case conflicted
    case untracked
    case typeChanged
    case unknown

    var displayName: String {
        switch self {
        case .added: "Added"
        case .modified: "Modified"
        case .deleted: "Deleted"
        case .renamed: "Renamed"
        case .copied: "Copied"
        case .conflicted: "Conflicted"
        case .untracked: "Untracked"
        case .typeChanged: "Type Changed"
        case .unknown: "Changed"
        }
    }
}

struct HolyGitFileChange: Identifiable, Codable, Equatable {
    let path: String
    let category: HolyGitFileChangeCategory
    let stagedStatus: String
    let unstagedStatus: String

    var id: String { path }
}

struct HolyGitSnapshot: Codable, Equatable {
    let repositoryRoot: String
    let worktreePath: String
    let commonGitDirectory: String
    let branch: String
    let upstreamBranch: String?
    let isDetachedHead: Bool
    let aheadCount: Int
    let behindCount: Int
    let stagedCount: Int
    let unstagedCount: Int
    let untrackedCount: Int
    let conflictedCount: Int
    let changedFiles: [HolyGitFileChange]

    var repositoryName: String {
        URL(fileURLWithPath: repositoryRoot).lastPathComponent
    }

    var worktreeName: String {
        URL(fileURLWithPath: worktreePath).lastPathComponent
    }

    var branchDisplayName: String {
        if isDetachedHead {
            return "Detached HEAD"
        }

        return branch.isEmpty ? "Unknown Branch" : branch
    }

    var changeCount: Int {
        changedFiles.count
    }

    var isClean: Bool {
        changeCount == 0 && conflictedCount == 0
    }

    var hasConflicts: Bool {
        conflictedCount > 0
    }

    var syncStatusText: String {
        switch (aheadCount, behindCount) {
        case (0, 0):
            return upstreamBranch == nil ? "No Upstream" : "Up To Date"
        case let (ahead, 0):
            return "Ahead \(ahead)"
        case let (0, behind):
            return "Behind \(behind)"
        case let (ahead, behind):
            return "Ahead \(ahead), Behind \(behind)"
        }
    }

    var changeSummaryText: String {
        if hasConflicts {
            return conflictedCount == 1 ? "1 conflict" : "\(conflictedCount) conflicts"
        }

        if isClean {
            return "Clean"
        }

        return changeCount == 1 ? "1 changed file" : "\(changeCount) changed files"
    }
}
