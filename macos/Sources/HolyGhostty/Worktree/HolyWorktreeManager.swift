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
            guard let existingSnapshot = await HolyGitClient.shared.snapshot(for: worktreeURL.path) else {
                throw HolyWorktreeManagerError.occupiedManagedPath(worktreeURL.path)
            }

            guard existingSnapshot.repositoryRoot == repositoryRoot else {
                throw HolyWorktreeManagerError.occupiedManagedPath(worktreeURL.path)
            }

            if !existingSnapshot.isDetachedHead,
               !existingSnapshot.branch.isEmpty,
               existingSnapshot.branch != branchName {
                throw HolyWorktreeManagerError.occupiedManagedPath(worktreeURL.path)
            }
        } else {
            try FileManager.default.createDirectory(
                at: worktreeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if branchExists(branchName, in: repositoryRoot) {
                try runGit(
                    arguments: ["-C", repositoryRoot, "worktree", "add", worktreeURL.path, branchName],
                    context: "attach existing branch \(branchName)"
                )
            } else {
                try runGit(
                    arguments: ["-C", repositoryRoot, "worktree", "add", "-b", branchName, worktreeURL.path],
                    context: "create managed branch \(branchName)"
                )
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
            logger.error("Failed to start git command: \(arguments.joined(separator: " "), privacy: .public) - \(error.localizedDescription, privacy: .public)")
            return .init(stdout: "", stderr: error.localizedDescription, exitCode: 1)
        }

        return .init(
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            exitCode: process.terminationStatus
        )
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

private extension String {
    var holyTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
