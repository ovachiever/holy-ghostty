import Foundation
import OSLog

actor HolyGitClient {
    static let shared = HolyGitClient()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "org.holyghostty.app",
        category: "HolyGitClient"
    )

    func snapshot(for directory: String?) -> HolyGitSnapshot? {
        guard let directory = directory?.holyTrimmed, !directory.isEmpty else {
            return nil
        }

        guard let worktreeResult = runGit(arguments: ["-C", directory, "rev-parse", "--show-toplevel"]),
              worktreeResult.exitCode == 0,
              let worktreePath = worktreeResult.stdout.holyTrimmed.nilIfEmpty else {
            return nil
        }

        guard let commonDirResult = runGit(arguments: ["-C", directory, "rev-parse", "--path-format=absolute", "--git-common-dir"]),
              commonDirResult.exitCode == 0,
              let commonGitDirectory = commonDirResult.stdout.holyTrimmed.nilIfEmpty else {
            return nil
        }

        guard let statusResult = runGit(arguments: ["-C", directory, "status", "--porcelain=v1", "--branch", "--untracked-files=all"]),
              statusResult.exitCode == 0 else {
            return nil
        }

        return parseStatusOutput(
            statusResult.stdout,
            repositoryRoot: repositoryRoot(from: commonGitDirectory, fallback: worktreePath),
            worktreePath: worktreePath,
            commonGitDirectory: commonGitDirectory
        )
    }

    private func runGit(arguments: [String]) -> HolyGitCommandResult? {
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
            logger.error("Failed to run git command: \(arguments.joined(separator: " "), privacy: .public) - \(error.localizedDescription, privacy: .public)")
            return nil
        }

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()

        return HolyGitCommandResult(
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }

    private func parseStatusOutput(
        _ output: String,
        repositoryRoot: String,
        worktreePath: String,
        commonGitDirectory: String
    ) -> HolyGitSnapshot {
        var branch = ""
        var upstreamBranch: String?
        var isDetachedHead = false
        var aheadCount = 0
        var behindCount = 0
        var stagedCount = 0
        var unstagedCount = 0
        var untrackedCount = 0
        var conflictedCount = 0
        var changedFiles: [HolyGitFileChange] = []

        for line in output.split(whereSeparator: \.isNewline).map(String.init) {
            guard !line.isEmpty else { continue }

            if line.hasPrefix("## ") {
                let header = parseBranchHeader(line)
                branch = header.branch
                upstreamBranch = header.upstreamBranch
                isDetachedHead = header.isDetachedHead
                aheadCount = header.aheadCount
                behindCount = header.behindCount
                continue
            }

            if line.hasPrefix("?? ") {
                untrackedCount += 1
                changedFiles.append(
                    HolyGitFileChange(
                        path: normalizedPath(from: String(line.dropFirst(3))),
                        category: .untracked,
                        stagedStatus: "?",
                        unstagedStatus: "?"
                    )
                )
                continue
            }

            guard line.count >= 3 else { continue }

            let staged = String(line.prefix(1))
            let unstaged = String(line.dropFirst().prefix(1))
            let path = normalizedPath(from: String(line.dropFirst(3)))
            let conflict = isConflict(staged: staged, unstaged: unstaged)

            if conflict {
                conflictedCount += 1
            } else {
                if staged != " " {
                    stagedCount += 1
                }
                if unstaged != " " {
                    unstagedCount += 1
                }
            }

            changedFiles.append(
                HolyGitFileChange(
                    path: path,
                    category: category(staged: staged, unstaged: unstaged, conflict: conflict, path: path),
                    stagedStatus: staged,
                    unstagedStatus: unstaged
                )
            )
        }

        return HolyGitSnapshot(
            repositoryRoot: repositoryRoot,
            worktreePath: worktreePath,
            commonGitDirectory: commonGitDirectory,
            branch: branch,
            upstreamBranch: upstreamBranch,
            isDetachedHead: isDetachedHead,
            aheadCount: aheadCount,
            behindCount: behindCount,
            stagedCount: stagedCount,
            unstagedCount: unstagedCount,
            untrackedCount: untrackedCount,
            conflictedCount: conflictedCount,
            changedFiles: changedFiles
        )
    }

    private func repositoryRoot(from commonGitDirectory: String, fallback worktreePath: String) -> String {
        let commonURL = URL(fileURLWithPath: commonGitDirectory)

        if commonURL.lastPathComponent == ".git" {
            return commonURL.deletingLastPathComponent().path
        }

        return worktreePath
    }

    private func parseBranchHeader(_ line: String) -> HolyGitBranchHeader {
        let rawHeader = String(line.dropFirst(3)).holyTrimmed

        if rawHeader.hasPrefix("No commits yet on ") {
            return .init(
                branch: String(rawHeader.dropFirst("No commits yet on ".count)),
                upstreamBranch: nil,
                isDetachedHead: false,
                aheadCount: 0,
                behindCount: 0
            )
        }

        var branchSegment = rawHeader
        var upstreamBranch: String?
        var statusSegment: String?

        if let range = rawHeader.range(of: "...") {
            branchSegment = String(rawHeader[..<range.lowerBound])
            let remainder = String(rawHeader[range.upperBound...]).holyTrimmed
            if let bracketRange = remainder.range(of: " [") {
                upstreamBranch = String(remainder[..<bracketRange.lowerBound]).holyTrimmed.nilIfEmpty
                statusSegment = String(remainder[bracketRange.lowerBound...]).holyTrimmed.nilIfEmpty
            } else {
                upstreamBranch = remainder.nilIfEmpty
            }
        } else if let bracketRange = rawHeader.range(of: " [") {
            branchSegment = String(rawHeader[..<bracketRange.lowerBound])
            statusSegment = String(rawHeader[bracketRange.lowerBound...]).holyTrimmed.nilIfEmpty
        }

        let isDetachedHead = branchSegment == "HEAD" || branchSegment.contains("detached") || branchSegment.contains("no branch")
        let statusBody = statusSegment?
            .trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
            .holyTrimmed

        var aheadCount = 0
        var behindCount = 0

        for component in statusBody?.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) ?? [] {
            if component.hasPrefix("ahead ") {
                aheadCount = Int(component.dropFirst("ahead ".count)) ?? 0
            } else if component.hasPrefix("behind ") {
                behindCount = Int(component.dropFirst("behind ".count)) ?? 0
            }
        }

        return .init(
            branch: isDetachedHead ? "" : branchSegment.holyTrimmed,
            upstreamBranch: upstreamBranch,
            isDetachedHead: isDetachedHead,
            aheadCount: aheadCount,
            behindCount: behindCount
        )
    }

    private func normalizedPath(from rawPath: String) -> String {
        let renamedTarget = rawPath.components(separatedBy: " -> ").last ?? rawPath
        let trimmed = renamedTarget.holyTrimmed

        guard trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 else {
            return trimmed
        }

        return String(trimmed.dropFirst().dropLast())
            .replacingOccurrences(of: "\\\"", with: "\"")
    }

    private func isConflict(staged: String, unstaged: String) -> Bool {
        staged == "U" || unstaged == "U" || (staged == "A" && unstaged == "A") || (staged == "D" && unstaged == "D")
    }

    private func category(
        staged: String,
        unstaged: String,
        conflict: Bool,
        path: String
    ) -> HolyGitFileChangeCategory {
        if conflict {
            return .conflicted
        }

        if staged == "?" && unstaged == "?" {
            return .untracked
        }

        if path.contains(" -> ") || staged == "R" || unstaged == "R" {
            return .renamed
        }

        let signal = unstaged != " " ? unstaged : staged

        switch signal {
        case "A":
            return .added
        case "M":
            return .modified
        case "D":
            return .deleted
        case "R":
            return .renamed
        case "C":
            return .copied
        case "T":
            return .typeChanged
        default:
            return .unknown
        }
    }
}

private struct HolyGitCommandResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

private struct HolyGitBranchHeader {
    let branch: String
    let upstreamBranch: String?
    let isDetachedHead: Bool
    let aheadCount: Int
    let behindCount: Int
}

private extension String {
    var holyTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
