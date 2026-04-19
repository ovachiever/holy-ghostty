import Foundation
import OSLog

enum HolyWorktreeManagerError: LocalizedError {
    case missingWorkingDirectory
    case missingRepositoryRoot
    case invalidRepository(String)
    case invalidWorktree(String)
    case invalidBranchName(String)
    case occupiedManagedPath(String)
    case gitFailure(String)

    var errorDescription: String? {
        switch self {
        case .missingWorkingDirectory:
            return "A working directory is required for this session."
        case .missingRepositoryRoot:
            return "A repository root is required to create a managed worktree."
        case let .invalidRepository(path):
            return "No git repository was found at \(path)."
        case let .invalidWorktree(path):
            return "No git worktree was found at \(path)."
        case let .invalidBranchName(branch):
            return "The branch name `\(branch)` is not valid."
        case let .occupiedManagedPath(path):
            return "The managed worktree path is already occupied by unrelated content: \(path)."
        case let .gitFailure(message):
            return message
        }
    }
}

actor HolyWorktreeManager {
    static let shared = HolyWorktreeManager()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "org.holyghostty.app",
        category: "HolyWorktreeManager"
    )

    func prepareLaunchSpec(_ launchSpec: HolySessionLaunchSpec) async throws -> HolySessionLaunchSpec {
        guard let workspace = launchSpec.workspace else {
            return try prepareDirectLaunchSpec(launchSpec)
        }

        switch workspace.strategy {
        case .directDirectory:
            return try prepareDirectLaunchSpec(launchSpec)
        case .attachExistingWorktree:
            return try await prepareAttachedWorktreeLaunchSpec(launchSpec)
        case .createManagedWorktree:
            return try await prepareManagedWorktreeLaunchSpec(launchSpec)
        }
    }

    nonisolated static func suggestedBranchName(for title: String, runtime: HolySessionRuntime) -> String {
        let base = sanitizedBranchComponent(from: title)
        if !base.isEmpty {
            return "holy/\(base)"
        }

        let fallback = sanitizedBranchComponent(from: runtime.displayName)
        return "holy/\(fallback.isEmpty ? "session" : fallback)"
    }

    nonisolated static func predictedManagedWorktreePath(
        repositoryRoot: String?,
        branchName: String?,
        runtime: HolySessionRuntime,
        title: String
    ) -> String? {
        guard let repositoryRoot = repositoryRoot?.holyTrimmed, !repositoryRoot.isEmpty else {
            return nil
        }

        let branch = branchName?.holyTrimmed.nilIfEmpty ?? suggestedBranchName(for: title, runtime: runtime)
        return managedWorktreeURL(repositoryRoot: repositoryRoot, branchName: branch).path
    }

    nonisolated static func recoveryIssue(for launchSpec: HolySessionLaunchSpec) -> String? {
        recoveryEvaluation(for: launchSpec).issue
    }

    nonisolated static func recoveryEvaluation(for launchSpec: HolySessionLaunchSpec) -> HolyWorktreeRecoveryEvaluation {
        let strategy = launchSpec.workspace?.strategy ?? .directDirectory
        let workingDirectory = launchSpec.workingDirectory?.holyTrimmed.nilIfEmpty

        guard let workingDirectory else {
            switch strategy {
            case .createManagedWorktree:
                return .init(
                    issue: "Recovery archived this session because no restorable managed worktree path was recorded.",
                    cleanupSummary: nil
                )
            case .attachExistingWorktree:
                return .init(
                    issue: "Recovery archived this session because no attached worktree path was recorded.",
                    cleanupSummary: nil
                )
            case .directDirectory:
                return .empty
            }
        }

        let standardizedPath = URL(fileURLWithPath: workingDirectory).standardizedFileURL.path
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: standardizedPath, isDirectory: &isDirectory)
        guard exists, isDirectory.boolValue else {
            switch strategy {
            case .createManagedWorktree:
                return .init(
                    issue: "Recovery archived this session because its managed worktree is missing: \(standardizedPath)",
                    cleanupSummary: nil
                )
            case .attachExistingWorktree:
                return .init(
                    issue: "Recovery archived this session because its attached worktree is no longer available: \(standardizedPath)",
                    cleanupSummary: nil
                )
            case .directDirectory:
                return .init(
                    issue: "Recovery archived this session because its working directory no longer exists: \(standardizedPath)",
                    cleanupSummary: nil
                )
            }
        }

        guard strategy != .directDirectory else {
            return .empty
        }

        guard let snapshot = recoverySnapshot(for: standardizedPath) else {
            let cleanupSummary = cleanupInvalidManagedWorktreeIfPossible(at: standardizedPath)
            switch strategy {
            case .createManagedWorktree:
                return .init(
                    issue: "Recovery archived this session because its managed worktree is no longer a valid git worktree: \(standardizedPath)",
                    cleanupSummary: cleanupSummary
                )
            case .attachExistingWorktree:
                return .init(
                    issue: "Recovery archived this session because its attached worktree is no longer a valid git worktree: \(standardizedPath)",
                    cleanupSummary: cleanupSummary
                )
            case .directDirectory:
                return .empty
            }
        }

        if snapshot.worktreePath != standardizedPath {
            switch strategy {
            case .createManagedWorktree:
                return .init(
                    issue: "Recovery archived this session because its managed worktree path resolved to `\(snapshot.worktreePath)` instead of `\(standardizedPath)`.",
                    cleanupSummary: nil
                )
            case .attachExistingWorktree:
                return .init(
                    issue: "Recovery archived this session because the attached path is no longer the worktree root: \(standardizedPath)",
                    cleanupSummary: nil
                )
            case .directDirectory:
                return .empty
            }
        }

        if let expectedRepositoryRoot = launchSpec.workspace?.repositoryRoot?.holyTrimmed.nilIfEmpty {
            let normalizedExpectedRepositoryRoot = URL(fileURLWithPath: expectedRepositoryRoot).standardizedFileURL.path
            if snapshot.repositoryRoot != normalizedExpectedRepositoryRoot {
                let observed = snapshot.repositoryRoot
                switch strategy {
                case .createManagedWorktree:
                    return .init(
                        issue: "Recovery archived this session because its managed worktree now points at a different repository: expected `\(normalizedExpectedRepositoryRoot)`, observed `\(observed)`.",
                        cleanupSummary: nil
                    )
                case .attachExistingWorktree:
                    return .init(
                        issue: "Recovery archived this session because the attached worktree now points at a different repository: expected `\(normalizedExpectedRepositoryRoot)`, observed `\(observed)`.",
                        cleanupSummary: nil
                    )
                case .directDirectory:
                    return .empty
                }
            }
        }

        let expectedBranchName = launchSpec.workspace?.branchName?.holyTrimmed.nilIfEmpty
        if strategy == .createManagedWorktree, expectedBranchName == nil {
            return .init(
                issue: "Recovery archived this session because no managed branch was recorded for its worktree.",
                cleanupSummary: nil
            )
        }

        if let expectedBranchName {
            if snapshot.isDetachedHead {
                switch strategy {
                case .createManagedWorktree:
                    return .init(
                        issue: "Recovery archived this session because its managed worktree is now in Detached HEAD instead of `\(expectedBranchName)`.",
                        cleanupSummary: nil
                    )
                case .attachExistingWorktree:
                    return .init(
                        issue: "Recovery archived this session because the attached worktree is now in Detached HEAD instead of `\(expectedBranchName)`.",
                        cleanupSummary: nil
                    )
                case .directDirectory:
                    return .empty
                }
            }

            if snapshot.branch != expectedBranchName {
                switch strategy {
                case .createManagedWorktree:
                    return .init(
                        issue: "Recovery archived this session because its managed worktree switched branches: expected `\(expectedBranchName)`, observed `\(snapshot.branch)`.",
                        cleanupSummary: nil
                    )
                case .attachExistingWorktree:
                    return .init(
                        issue: "Recovery archived this session because the attached worktree switched branches: expected `\(expectedBranchName)`, observed `\(snapshot.branch)`.",
                        cleanupSummary: nil
                    )
                case .directDirectory:
                    return .empty
                }
            }
        }

        return .empty
    }

    nonisolated static func cleanupOrphanedManagedWorktrees(referencedPaths: [String]) -> [String] {
        let fileManager = FileManager.default
        let containerURL = managedWorktreeContainerDirectory()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: containerURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return []
        }

        let normalizedReferencedPaths = Set(referencedPaths.map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        })
        let repoContainerURLs = (try? fileManager.contentsOfDirectory(
            at: containerURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var summaries: [String] = []
        for repoContainerURL in repoContainerURLs {
            guard (try? repoContainerURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }

            let worktreeURLs = (try? fileManager.contentsOfDirectory(
                at: repoContainerURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for worktreeURL in worktreeURLs {
                guard (try? worktreeURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                    continue
                }

                let path = worktreeURL.standardizedFileURL.path
                guard !normalizedReferencedPaths.contains(path) else { continue }

                if let snapshot = recoverySnapshot(for: path) {
                    guard gitWorktreeIsClean(path),
                          removeGitWorktree(snapshot: snapshot) else {
                        continue
                    }

                    pruneEmptyManagedParents(for: worktreeURL)
                    summaries.append("Removed orphaned managed worktree `\(path)`.")
                    continue
                }

                guard cleanupInvalidManagedWorktreeIfPossible(at: path) != nil else {
                    continue
                }

                summaries.append("Removed invalid orphaned managed worktree directory `\(path)`.")
            }
        }

        return summaries
    }

    private func prepareDirectLaunchSpec(_ launchSpec: HolySessionLaunchSpec) throws -> HolySessionLaunchSpec {
        guard let directory = launchSpec.workingDirectory?.holyTrimmed, !directory.isEmpty else {
            throw HolyWorktreeManagerError.missingWorkingDirectory
        }

        return launchSpec
    }

    private func prepareAttachedWorktreeLaunchSpec(_ launchSpec: HolySessionLaunchSpec) async throws -> HolySessionLaunchSpec {
        guard let directory = launchSpec.workingDirectory?.holyTrimmed, !directory.isEmpty else {
            throw HolyWorktreeManagerError.missingWorkingDirectory
        }

        guard let snapshot = await HolyGitClient.shared.snapshot(for: directory) else {
            throw HolyWorktreeManagerError.invalidWorktree(directory)
        }

        var resolved = launchSpec
        resolved.workingDirectory = snapshot.worktreePath
        resolved.workspace = .init(
            strategy: .attachExistingWorktree,
            repositoryRoot: snapshot.repositoryRoot,
            branchName: snapshot.isDetachedHead ? nil : snapshot.branch.nilIfEmpty
        )
        return resolved
    }

    private func prepareManagedWorktreeLaunchSpec(_ launchSpec: HolySessionLaunchSpec) async throws -> HolySessionLaunchSpec {
        guard let requestedRepositoryRoot = launchSpec.workspace?.repositoryRoot?.holyTrimmed.nilIfEmpty
            ?? launchSpec.workingDirectory?.holyTrimmed.nilIfEmpty else {
            throw HolyWorktreeManagerError.missingRepositoryRoot
        }

        guard let repositorySnapshot = await HolyGitClient.shared.snapshot(for: requestedRepositoryRoot) else {
            throw HolyWorktreeManagerError.invalidRepository(requestedRepositoryRoot)
        }

        let repositoryRoot = repositorySnapshot.repositoryRoot
        let branchName = launchSpec.workspace?.branchName?.holyTrimmed.nilIfEmpty
            ?? Self.suggestedBranchName(for: launchSpec.title, runtime: launchSpec.runtime)

        try validateBranchName(branchName)

        let worktreeURL = Self.managedWorktreeURL(repositoryRoot: repositoryRoot, branchName: branchName)
        if FileManager.default.fileExists(atPath: worktreeURL.path) {
            if let existingSnapshot = await HolyGitClient.shared.snapshot(for: worktreeURL.path) {
                guard existingSnapshot.repositoryRoot == repositoryRoot else {
                    throw HolyWorktreeManagerError.occupiedManagedPath(worktreeURL.path)
                }

                if !existingSnapshot.isDetachedHead,
                   !existingSnapshot.branch.isEmpty,
                   existingSnapshot.branch != branchName {
                    throw HolyWorktreeManagerError.occupiedManagedPath(worktreeURL.path)
                }
            } else if Self.cleanupInvalidManagedWorktreeIfPossible(at: worktreeURL.path) == nil {
                throw HolyWorktreeManagerError.occupiedManagedPath(worktreeURL.path)
            }
        } else {
            try FileManager.default.createDirectory(
                at: worktreeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if branchExists(branchName, in: repositoryRoot) {
                do {
                    try runGit(
                        arguments: ["-C", repositoryRoot, "worktree", "add", worktreeURL.path, branchName],
                        context: "attach existing branch \(branchName)"
                    )
                } catch {
                    _ = Self.cleanupInvalidManagedWorktreeIfPossible(at: worktreeURL.path)
                    throw error
                }
            } else {
                do {
                    try runGit(
                        arguments: ["-C", repositoryRoot, "worktree", "add", "-b", branchName, worktreeURL.path],
                        context: "create managed branch \(branchName)"
                    )
                } catch {
                    _ = Self.cleanupInvalidManagedWorktreeIfPossible(at: worktreeURL.path)
                    throw error
                }
            }
        }

        var resolved = launchSpec
        resolved.workingDirectory = worktreeURL.path
        resolved.workspace = .init(
            strategy: .createManagedWorktree,
            repositoryRoot: repositoryRoot,
            branchName: branchName
        )
        return resolved
    }

    private func validateBranchName(_ branchName: String) throws {
        let result = runGitCommand(arguments: ["check-ref-format", "--branch", branchName])
        guard result.exitCode == 0 else {
            throw HolyWorktreeManagerError.invalidBranchName(branchName)
        }
    }

    private func branchExists(_ branchName: String, in repositoryRoot: String) -> Bool {
        let result = runGitCommand(arguments: [
            "-C", repositoryRoot,
            "show-ref",
            "--verify",
            "--quiet",
            "refs/heads/\(branchName)"
        ])
        return result.exitCode == 0
    }

    private func runGit(arguments: [String], context: String) throws {
        let result = runGitCommand(arguments: arguments)
        guard result.exitCode == 0 else {
            let stderr = result.stderr.holyTrimmed.nilIfEmpty
            let stdout = result.stdout.holyTrimmed.nilIfEmpty
            let detail = stderr ?? stdout ?? "Unknown git failure"
            logger.error("Git command failed during \(context, privacy: .public): \(detail, privacy: .public)")
            throw HolyWorktreeManagerError.gitFailure(detail)
        }
    }

    private func runGitCommand(arguments: [String]) -> HolyWorktreeGitCommandResult {
        Self.runGitCommand(arguments: arguments, logger: logger)
    }

    private nonisolated static func cleanupInvalidManagedWorktreeIfPossible(at path: String) -> String? {
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        guard pathIsInsideManagedContainer(standardizedPath) else { return nil }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: standardizedPath) else {
            return nil
        }

        do {
            try fileManager.removeItem(atPath: standardizedPath)
            pruneEmptyManagedParents(for: URL(fileURLWithPath: standardizedPath))
            return "Removed invalid managed worktree directory `\(standardizedPath)`."
        } catch {
            return nil
        }
    }

    private nonisolated static func recoverySnapshot(for path: String) -> HolyWorktreeRecoverySnapshot? {
        let worktreeResult = runGitCommand(arguments: ["-C", path, "rev-parse", "--show-toplevel"], logger: nil)
        guard worktreeResult.exitCode == 0,
              let worktreePath = worktreeResult.stdout.holyTrimmed.nilIfEmpty else {
            return nil
        }

        let commonDirResult = runGitCommand(
            arguments: ["-C", path, "rev-parse", "--path-format=absolute", "--git-common-dir"],
            logger: nil
        )
        guard commonDirResult.exitCode == 0,
              let commonGitDirectory = commonDirResult.stdout.holyTrimmed.nilIfEmpty else {
            return nil
        }

        let branchResult = runGitCommand(arguments: ["-C", path, "branch", "--show-current"], logger: nil)
        let branch = branchResult.stdout.holyTrimmed
        let isDetachedHead = branch.isEmpty

        return .init(
            repositoryRoot: repositoryRoot(from: commonGitDirectory, fallback: worktreePath),
            worktreePath: URL(fileURLWithPath: worktreePath).standardizedFileURL.path,
            branch: branch,
            isDetachedHead: isDetachedHead
        )
    }

    private nonisolated static func gitWorktreeIsClean(_ path: String) -> Bool {
        let result = runGitCommand(
            arguments: ["-C", path, "status", "--porcelain=v1", "--untracked-files=all"],
            logger: nil
        )
        guard result.exitCode == 0 else { return false }
        return result.stdout.holyTrimmed.isEmpty
    }

    private nonisolated static func removeGitWorktree(snapshot: HolyWorktreeRecoverySnapshot) -> Bool {
        let result = runGitCommand(
            arguments: ["-C", snapshot.repositoryRoot, "worktree", "remove", "--force", snapshot.worktreePath],
            logger: nil
        )
        return result.exitCode == 0
    }

    private nonisolated static func runGitCommand(
        arguments: [String],
        logger: Logger?
    ) -> HolyWorktreeGitCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            logger?.error("Failed to start git command: \(arguments.joined(separator: " "), privacy: .public) - \(error.localizedDescription, privacy: .public)")
            return .init(stdout: "", stderr: error.localizedDescription, exitCode: 1)
        }

        return .init(
            stdout: String(bytes: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(bytes: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
    }

    private nonisolated static func repositoryRoot(from commonGitDirectory: String, fallback worktreePath: String) -> String {
        let commonURL = URL(fileURLWithPath: commonGitDirectory)

        if commonURL.lastPathComponent == ".git" {
            return commonURL.deletingLastPathComponent().path
        }

        return URL(fileURLWithPath: worktreePath).standardizedFileURL.path
    }

    private nonisolated static func pathIsInsideManagedContainer(_ path: String) -> Bool {
        let containerPath = managedWorktreeContainerDirectory().standardizedFileURL.path
        return path == containerPath || path.hasPrefix(containerPath + "/")
    }

    private nonisolated static func pruneEmptyManagedParents(for worktreeURL: URL) {
        let fileManager = FileManager.default
        let containerPath = managedWorktreeContainerDirectory().standardizedFileURL.path
        var currentURL = worktreeURL.deletingLastPathComponent()

        while currentURL.standardizedFileURL.path.hasPrefix(containerPath + "/") {
            let path = currentURL.standardizedFileURL.path
            guard let contents = try? fileManager.contentsOfDirectory(atPath: path),
                  contents.isEmpty else {
                break
            }

            try? fileManager.removeItem(atPath: path)
            currentURL = currentURL.deletingLastPathComponent()
        }
    }

    private nonisolated static func managedWorktreeURL(repositoryRoot: String, branchName: String) -> URL {
        let repoName = sanitizedBranchComponent(from: URL(fileURLWithPath: repositoryRoot).lastPathComponent)
        let repoHash = stableRepositoryHash(for: repositoryRoot)
        let branchComponent = sanitizedBranchComponent(from: branchName)

        return managedWorktreeContainerDirectory()
            .appendingPathComponent("\(repoName)-\(repoHash)", isDirectory: true)
            .appendingPathComponent(branchComponent.isEmpty ? "session" : branchComponent, isDirectory: true)
    }

    private nonisolated static func managedWorktreeContainerDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let bundleID = Bundle.main.bundleIdentifier ?? "org.holyghostty.app"

        return appSupport
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("HolyGhostty", isDirectory: true)
            .appendingPathComponent("ManagedWorktrees", isDirectory: true)
    }

    private nonisolated static func sanitizedBranchComponent(from value: String) -> String {
        let lowered = value.lowercased()
        let mapped = lowered.map { character -> Character in
            if character.isLetter || character.isNumber {
                return character
            }

            return "-"
        }

        let collapsed = String(mapped)
            .components(separatedBy: "-")
            .filter { !$0.isEmpty }
            .joined(separator: "-")

        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private nonisolated static func stableRepositoryHash(for path: String) -> String {
        var hash: UInt32 = 5381
        for scalar in path.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ UInt32(scalar.value)
        }

        return String(format: "%08x", hash)
    }
}

private struct HolyWorktreeGitCommandResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

private struct HolyWorktreeRecoverySnapshot {
    let repositoryRoot: String
    let worktreePath: String
    let branch: String
    let isDetachedHead: Bool
}

struct HolyWorktreeRecoveryEvaluation {
    let issue: String?
    let cleanupSummary: String?

    static let empty = Self(issue: nil, cleanupSummary: nil)
}

private extension String {
    var holyTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
