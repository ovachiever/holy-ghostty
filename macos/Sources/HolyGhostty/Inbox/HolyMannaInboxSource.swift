import Foundation

// MARK: - Pinned payloads

/// Issue status as `agent-do manna list --json` reports it. Not
/// `RawRepresentable`: a manna release that adds a status must degrade to
/// `.unknown` (a value no admission rule matches) rather than blank the pane.
enum HolyMannaIssueStatus: Sendable, Equatable {
    case open
    case inProgress
    case blocked
    case done
    case unknown

    init(rawValue: String) {
        switch rawValue {
        case "open": self = .open
        case "in_progress": self = .inProgress
        case "blocked": self = .blocked
        case "done": self = .done
        default: self = .unknown
        }
    }
}

/// Manna grammar: a board row is a track (grouping), an item (work unit,
/// the wire default) or a dream (raw intake awaiting a human decision).
enum HolyMannaIssueType: Sendable, Equatable {
    case track
    case item
    case dream
    case unknown

    init(rawValue: String) {
        switch rawValue {
        case "track": self = .track
        case "item": self = .item
        case "dream": self = .dream
        default: self = .unknown
        }
    }
}

/// One row of `agent-do manna list --json`. Field names pinned from live
/// invocations on 2026-08-03 against `/Users/erik/Custom-Coding/holy-ghostty`
/// and `/Users/erik/Custom-Coding`: id, title, status, claimed_by?, type?
/// (omitted when the default `item`), track?, updated, gate? (dreams only).
/// Do not edit them from memory; re-run the CLI.
struct HolyMannaIssueSummary: Equatable, Sendable {
    let id: String
    let title: String
    let status: HolyMannaIssueStatus
    let claimedBy: String?
    let type: HolyMannaIssueType
    let track: String?
    /// Display string — "2026-07-21 (13d ago)" — never ISO8601.
    let updated: String
    /// Present only on dreams: the row is visible but not workable.
    let gate: String?

    /// Only the leading calendar day of `updated` is real data; the "(13d
    /// ago)" tail is prose. An unparseable value is no date, never a guess.
    static func updatedDate(from raw: String) -> Date? {
        let head = raw.prefix(10)
        guard head.count == 10 else { return nil }
        let parts = head.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              (1...12).contains(month),
              (1...31).contains(day) else {
            return nil
        }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day

        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: components),
              calendar.component(.year, from: date) == year,
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day else {
            return nil
        }
        return date
    }

    var updatedDate: Date? {
        Self.updatedDate(from: updated)
    }
}

extension HolyMannaIssueSummary: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case status
        case claimedBy = "claimed_by"
        case type
        case track
        case updated
        case gate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        status = HolyMannaIssueStatus(rawValue: try container.decode(String.self, forKey: .status))
        claimedBy = try container.decodeIfPresent(String.self, forKey: .claimedBy)
        type = HolyMannaIssueType(
            rawValue: try container.decodeIfPresent(String.self, forKey: .type) ?? "item"
        )
        track = try container.decodeIfPresent(String.self, forKey: .track)
        updated = try container.decode(String.self, forKey: .updated)
        gate = try container.decodeIfPresent(String.self, forKey: .gate)
    }
}

struct HolyMannaListPayload: Decodable, Equatable, Sendable {
    let success: Bool
    let issues: [HolyMannaIssueSummary]

    /// Fail-closed. The CLI answers errors in YAML even under `--json`
    /// ("success: false\nerror: …", verified live 2026-08-03), and a
    /// `success:false` JSON body is not a board either: both parse to nil so
    /// the source degrades instead of inventing an empty board.
    static func parse(_ data: Data) -> HolyMannaListPayload? {
        guard let payload = try? JSONDecoder().decode(HolyMannaListPayload.self, from: data),
              payload.success else {
            return nil
        }
        return payload
    }
}

/// Drift kinds pinned from manna's `FindingKind` enum (agent-do
/// tools/agent-manna/src/reconcile.rs, 2026-08-03).
enum HolyMannaFindingKind: Sendable, Equatable {
    case landedOpen
    case deadClaim
    case blockerDesync
    case staleDream
    case danglingTrack
    case docReference
    case promptPairing
    case skipped
    case unknown

    init(rawValue: String) {
        switch rawValue {
        case "landed_open": self = .landedOpen
        case "dead_claim": self = .deadClaim
        case "blocker_desync": self = .blockerDesync
        case "stale_dream": self = .staleDream
        case "dangling_track": self = .danglingTrack
        case "doc_reference": self = .docReference
        case "prompt_pairing": self = .promptPairing
        case "skipped": self = .skipped
        default: self = .unknown
        }
    }
}

/// One `agent-do manna reconcile --json` finding: kind, issue_id?, detail,
/// evidence?, proposed_fix?.
struct HolyMannaReconcileFinding: Equatable, Sendable {
    let kind: HolyMannaFindingKind
    let issueID: String?
    let detail: String
    let evidence: String?
    let proposedFix: String?
}

extension HolyMannaReconcileFinding: Decodable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case issueID = "issue_id"
        case detail
        case evidence
        case proposedFix = "proposed_fix"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = HolyMannaFindingKind(rawValue: try container.decode(String.self, forKey: .kind))
        issueID = try container.decodeIfPresent(String.self, forKey: .issueID)
        detail = try container.decode(String.self, forKey: .detail)
        evidence = try container.decodeIfPresent(String.self, forKey: .evidence)
        proposedFix = try container.decodeIfPresent(String.self, forKey: .proposedFix)
    }
}

struct HolyMannaReconcilePayload: Decodable, Equatable, Sendable {
    let success: Bool
    let findings: [HolyMannaReconcileFinding]

    static func parse(_ data: Data) -> HolyMannaReconcilePayload? {
        guard let payload = try? JSONDecoder().decode(HolyMannaReconcilePayload.self, from: data),
              payload.success else {
            return nil
        }
        return payload
    }
}

// MARK: - Board discovery

/// Which boards the pane reads. The caller supplies one focused-project
/// anchor; this locator admits that project's board plus its nearest umbrella
/// board, discovered by probing for `.manna`, never hardcoded.
enum HolyMannaBoardLocator {
    /// Each board costs two subprocesses per refresh tick.
    static let maxBoards = 8
    /// How far above a repository to look for its umbrella board. Bounded so
    /// a repo outside the home directory cannot walk the whole filesystem.
    static let maxAncestorDepth = 4

    /// Session repo boards first (in the caller's order — focused session
    /// first), then the nearest umbrella board above each. The walk stops at
    /// the home directory and never climbs past it.
    static func boardRoots(
        repositoryRoots: [String],
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path,
        maxBoards: Int = maxBoards,
        hasBoard: (String) -> Bool = { FileManager.default.fileExists(atPath: $0 + "/.manna") }
    ) -> [String] {
        let home = normalized(homeDirectory)
        let roots = repositoryRoots.compactMap(normalizedIfAbsolute(_:))

        var found: [String] = []
        var seen: Set<String> = []

        func admit(_ root: String) {
            guard found.count < maxBoards, seen.insert(root).inserted else { return }
            found.append(root)
        }

        for root in roots where hasBoard(root) {
            admit(root)
        }

        for root in roots {
            // Two bounds, each with its own reason: a repo inside the home
            // directory never reads boards above it (they would be somebody
            // else's), and a repo anywhere else stops well short of `/`.
            let underHome = root == home || isDescendant(root, of: home)
            var ancestor = root
            for _ in 0..<maxAncestorDepth {
                guard let parent = parentDirectory(of: ancestor), parent != "/" else { break }
                if underHome, !(parent == home || isDescendant(parent, of: home)) { break }
                ancestor = parent
                if hasBoard(ancestor) {
                    admit(ancestor)
                    break
                }
                if ancestor == home { break }
            }
        }

        return found
    }

    // MARK: Paths

    private static func normalized(_ path: String) -> String {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard standardized.count > 1, standardized.hasSuffix("/") else { return standardized }
        return String(standardized.dropLast())
    }

    private static func normalizedIfAbsolute(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }
        return normalized(trimmed)
    }

    private static func parentDirectory(of path: String) -> String? {
        let parent = normalized(URL(fileURLWithPath: path).deletingLastPathComponent().path)
        return parent == path ? nil : parent
    }

    private static func isDescendant(_ path: String, of ancestor: String) -> Bool {
        path.hasPrefix(ancestor.hasSuffix("/") ? ancestor : ancestor + "/")
    }
}

// MARK: - Source

/// Production bridge to the local manna boards. Manna is git-backed JSONL on
/// disk, so there is no polling problem: both commands run on the inbox's own
/// refresh tick, read-only, once per board.
///
/// Same subprocess-JSON-degrade shape as HolyGitHubInboxSource: the CLI is
/// PATH-resolved once through a login shell, invoked directly with an argument
/// array, and every failure mode collapses into one quiet degraded row per
/// board — never a crash, never invented emptiness.
final class HolyMannaInboxSource: HolyInboxRowSource {
    static let binaryName = "agent-do"
    /// `list` reads one local JSONL board. A stuck read must fail closed
    /// without making a project switch look like an empty board for a minute.
    static let commandTimeout: TimeInterval = 10

    /// `list` reads `./.manna` from the child's working directory; manna
    /// exposes no board flag, so the board root is the process cwd.
    static let listArguments = ["manna", "list", "--json"]

    let sourceID = HolyMannaInboxSectioner.sourceID

    /// A filesystem anchor for the focused Holy session. The shared refresh
    /// context carries only a GitHub slug, and a board is a path, so board
    /// scope arrives through the store instead.
    private let repositoryRootsProvider: @Sendable () async -> [String]
    private let homeDirectory: String
    private let boardReader: (@Sendable (String) async -> HolyMannaBoardReading)?
    private let binaryPathOverride: String?

    init(
        repositoryRootsProvider: @escaping @Sendable () async -> [String] = { [] },
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path,
        binaryPathOverride: String? = nil,
        boardReader: (@Sendable (String) async -> HolyMannaBoardReading)? = nil
    ) {
        self.repositoryRootsProvider = repositoryRootsProvider
        self.homeDirectory = homeDirectory
        self.binaryPathOverride = binaryPathOverride
        self.boardReader = boardReader
    }

    static func degradedSnapshot(detail: String) -> HolyInboxSourceSnapshot {
        HolyInboxSourceSnapshot(sections: [
            HolyInboxSection(
                id: "manna.degraded",
                sourceID: HolyMannaInboxSectioner.sourceID,
                title: "manna",
                rows: [
                    HolyInboxRow(
                        id: "manna:degraded",
                        title: "manna boards unavailable",
                        subtitle: detail,
                        isDegraded: true
                    ),
                ]
            ),
        ])
    }

    func refresh(context: HolyInboxRefreshContext) async -> HolyInboxSourceSnapshot {
        let repositoryRoots = await repositoryRootsProvider()
        let boardRoots = HolyMannaBoardLocator.boardRoots(
            repositoryRoots: repositoryRoots,
            homeDirectory: homeDirectory
        )
        // No session, no board: silence is the honest answer, not a row.
        guard !boardRoots.isEmpty else { return .empty }

        let read: @Sendable (String) async -> HolyMannaBoardReading
        if let boardReader {
            read = boardReader
        } else {
            guard let binaryPath = await resolvedBinaryPath() else {
                return Self.degradedSnapshot(
                    detail: "The \(Self.binaryName) CLI was not found on PATH."
                )
            }
            read = { await Self.readBoard(root: $0, binaryPath: binaryPath) }
        }

        var boards: [HolyMannaBoardReading] = []
        boards.reserveCapacity(boardRoots.count)
        for root in boardRoots {
            boards.append(await read(root))
        }

        return HolyInboxSourceSnapshot(
            sections: HolyMannaInboxSectioner.sections(
                boards: boards,
                focusedBoardRoot: boardRoots.first
            )
        )
    }

    // MARK: - Reading one board

    /// The pane is a view of the focused project's board, not a board-health
    /// auditor. `manna reconcile` can walk git, coord, and thousands of doc
    /// references; making that audit a prerequisite caused a valid local list
    /// to remain invisible for seconds or deadlock behind a full stdout pipe.
    /// `list` is the complete production dependency for this glance surface.
    private static func readBoard(root: String, binaryPath: String) async -> HolyMannaBoardReading {
        switch await run(binaryPath: binaryPath, arguments: listArguments, boardRoot: root) {
        case let .failure(reason):
            return HolyMannaBoardReading(root: root, degradedDetail: reason)
        case let .success(output):
            guard let parsed = HolyMannaListPayload.parse(Data(output.utf8)) else {
                return HolyMannaBoardReading(
                    root: root,
                    degradedDetail: "\(binaryName) manna list returned a payload outside the pinned contract."
                )
            }
            return HolyMannaBoardReading(root: root, issues: parsed.issues)
        }
    }

    /// stdout of a clean run, or one human-readable reason it is missing.
    private enum CommandOutcome {
        case success(String)
        case failure(String)
    }

    private static func run(
        binaryPath: String,
        arguments: [String],
        boardRoot: String
    ) async -> CommandOutcome {
        let result = await HolyMannaProcessRunner.run(
            executablePath: binaryPath,
            arguments: arguments,
            workingDirectory: boardRoot,
            timeout: commandTimeout
        )
        switch result {
        case let .failure(reason):
            return .failure(reason)
        case let .success(output):
            guard output.exitCode == 0 else {
                let stderr = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let command = arguments.joined(separator: " ")
                return .failure(
                    "\(binaryName) \(command) exited with status \(output.exitCode)."
                        + (stderr.isEmpty ? "" : " \(stderr)")
                )
            }
            return .success(output.stdout)
        }
    }

    // MARK: - Binary discovery

    private func resolvedBinaryPath() async -> String? {
        if let binaryPathOverride {
            return FileManager.default.isExecutableFile(atPath: binaryPathOverride)
                ? binaryPathOverride
                : nil
        }
        return await Self.sharedBinaryPath.value
    }

    /// One PATH lookup per app lifetime: a Dock launch inherits a login
    /// (non-interactive) shell PATH, so probe through `/bin/zsh -lc` and fall
    /// back to the same well-known install locations the GitHub source uses —
    /// it is the same `agent-do` binary.
    private static let sharedBinaryPath = Task<String?, Never> {
        let result = await HolyMannaProcessRunner.run(
            executablePath: "/bin/zsh",
            arguments: ["-lc", "command -v \(binaryName)"],
            workingDirectory: nil,
            timeout: 15
        )
        if case let .success(output) = result, output.exitCode == 0 {
            let path = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                return path
            }
        }
        return HolyGitHubInboxSource.wellKnownBinaryPath()
    }
}

extension HolyMannaInboxSource {
    @MainActor
    /// The focused session's repository only (Erik 2026-08-10: "I should not
    /// be seeing manna from other projects"). Git ownership arrives
    /// asynchronously after focus, so fall back to the focused worktree/cwd
    /// immediately instead of blanking the panel until `gitSnapshot` lands.
    /// Other live sessions' boards stay out; the umbrella climb in
    /// `boardRoots` still covers a focused project whose board lives above it.
    static func repositoryRoots(focused: HolySession?) -> [String] {
        guard let focused else { return [] }
        let ownership = focused.ownership
        return repositoryRoots(
            repositoryRoot: ownership.repositoryRoot,
            worktreePath: ownership.worktreePath,
            workingDirectory: focused.workingDirectory
        )
    }

    /// Pure form of focused-project resolution, kept testable without a live
    /// terminal surface. Take exactly one anchor: authoritative repository
    /// root first, then the observed worktree, then cwd while git is loading.
    nonisolated static func repositoryRoots(
        repositoryRoot: String?,
        worktreePath: String?,
        workingDirectory: String?
    ) -> [String] {
        for candidate in [repositoryRoot, worktreePath, workingDirectory] {
            guard let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  trimmed.hasPrefix("/") else {
                continue
            }
            return [URL(fileURLWithPath: trimmed).standardizedFileURL.path]
        }
        return []
    }
}

// MARK: - Process runner

/// A process runner with a working directory.
///
/// manna resolves its board as `./.manna` from the child's cwd and offers no
/// board flag, so a working directory is not a convenience here — it is the
/// only way to name a board. The shared restore runner has no cwd hook and
/// lives in another lane's file; hoisting one there is the obvious cleanup
/// once both lanes have landed.
enum HolyMannaProcessRunner {
    static func run(
        executablePath: String,
        arguments: [String],
        workingDirectory: String?,
        timeout: TimeInterval
    ) async -> HolyRestoreProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let resumeBox = ResumeBox()

        return await withCheckedContinuation { continuation in
            resumeBox.store(continuation)

            // Drain from launch. Waiting for termination before reading lets
            // a large board fill the pipe and block the child before it can
            // exit, which presents as a false timeout and an empty pane.
            let collectedStdout = DataBox()
            let collectedStderr = DataBox()
            let drainGroup = DispatchGroup()

            process.terminationHandler = { finishedProcess in
                drainGroup.notify(queue: .global(qos: .utility)) {
                    resumeBox.resume(returning: .success(.init(
                        stdout: String(bytes: collectedStdout.take(), encoding: .utf8) ?? "",
                        stderr: String(bytes: collectedStderr.take(), encoding: .utf8) ?? "",
                        exitCode: finishedProcess.terminationStatus
                    )))
                }
            }

            do {
                try process.run()
            } catch {
                resumeBox.resume(returning: .failure(
                    holyDetailedProcessLaunchErrorDescription(error)
                ))
                return
            }

            drainGroup.enter()
            DispatchQueue.global(qos: .utility).async {
                collectedStdout.store(stdout.fileHandleForReading.readDataToEndOfFile())
                drainGroup.leave()
            }
            drainGroup.enter()
            DispatchQueue.global(qos: .utility).async {
                collectedStderr.store(stderr.fileHandleForReading.readDataToEndOfFile())
                drainGroup.leave()
            }

            Task.detached {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                resumeBox.resume(returning: .failure(
                    "\(URL(fileURLWithPath: executablePath).lastPathComponent) did not finish within \(Int(timeout)) seconds."
                ))
                if process.isRunning {
                    process.terminate()
                }
            }
        }
    }

    private final class DataBox: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func store(_ newData: Data) {
            lock.lock()
            defer { lock.unlock() }
            data = newData
        }

        func take() -> Data {
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }

    private final class ResumeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<HolyRestoreProcessResult, Never>?
        private var didResume = false

        func store(_ continuation: CheckedContinuation<HolyRestoreProcessResult, Never>) {
            lock.lock()
            defer { lock.unlock() }
            self.continuation = continuation
        }

        func resume(returning value: HolyRestoreProcessResult) {
            lock.lock()
            guard !didResume, let continuation else {
                lock.unlock()
                return
            }
            didResume = true
            self.continuation = nil
            lock.unlock()
            continuation.resume(returning: value)
        }
    }
}

/// Everything one board answered on one refresh tick. `degradedDetail` is set
/// when the board read failed; injected adapters may still attach findings,
/// but the production glance path depends only on the list payload.
struct HolyMannaBoardReading: Equatable, Sendable {
    /// Absolute path of the directory containing `.manna`.
    let root: String
    let issues: [HolyMannaIssueSummary]
    let findings: [HolyMannaReconcileFinding]
    let degradedDetail: String?

    init(
        root: String,
        issues: [HolyMannaIssueSummary] = [],
        findings: [HolyMannaReconcileFinding] = [],
        degradedDetail: String? = nil
    ) {
        self.root = root
        self.issues = issues
        self.findings = findings
        self.degradedDetail = degradedDetail
    }

    var displayName: String {
        URL(fileURLWithPath: root).lastPathComponent
    }
}

/// The admission law for manna rows, kept out of the source so it is a pure
/// function of board data (same shape as HolyGitHubInboxSectioner).
///
/// The focused project's incomplete board belongs here because Manna is the
/// user's local, self-addressed work. That does not make every row an alert:
/// decision states stay expanded and badge-counting, while ordinary active,
/// ready, blocked, and track inventory lives in compact secondary sections.
/// Every row clears when the board moves — never by dismissal.
///
///   1. **Dreams awaiting triage.** The grammar says a dream is converted or
///      closed with a written reason; until then it waits on Erik. Converting
///      moves it into the ready backlog; closing removes it on the next tick.
///   2. **Unblocked but unclaimed.** `done` never auto-unblocks dependents, so
///      work whose blockers are all resolved sits invisibly blocked with
///      nobody on it. Reconcile calls this `blocker_desync`. A claim or a
///      blocker-state change clears it.
///   3. **Stale claims.** A claim held by a session that is provably gone
///      (`dead_claim`). A reclaim or an abandon clears it.
///
/// The production source intentionally uses `manna list`, not `reconcile`;
/// injected findings remain supported for tests and adapters, but board-health
/// bookkeeping (`landed_open`, `doc_reference`, and friends) never earns rows.
enum HolyMannaInboxSectioner {
    static let sourceID = "manna"

    static func sections(
        boards: [HolyMannaBoardReading],
        focusedBoardRoot: String? = nil
    ) -> [HolyInboxSection] {
        var dreams: [HolyInboxRow] = []
        var unblocked: [HolyInboxRow] = []
        var staleClaims: [HolyInboxRow] = []
        var active: [HolyInboxRow] = []
        var ready: [HolyInboxRow] = []
        var blocked: [HolyInboxRow] = []
        var tracks: [HolyInboxRow] = []
        var degraded: [HolyInboxRow] = []

        for board in boards {
            let byID = Dictionary(board.issues.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let staleDreamIDs = Set(findingIssueIDs(board.findings, kind: .staleDream))
            var dedicatedIssueIDs: Set<String> = []

            // 1. Dreams awaiting triage.
            for issue in board.issues where issue.type == .dream && issue.status != .done {
                var chips = [HolyInboxChip("dream", emphasis: .attention)]
                if staleDreamIDs.contains(issue.id) {
                    chips.append(HolyInboxChip("stale", emphasis: .warning))
                }
                dreams.append(row(board: board, issue: issue, chips: chips, evidence: nil))
            }

            // 2. Unblocked but unclaimed. A dream is never claimable and a
            //    track is a grouping, so neither can be this row.
            for finding in deduplicated(board.findings, kind: .blockerDesync) {
                guard let id = finding.issueID,
                      let issue = byID[id],
                      issue.type == .item,
                      issue.claimedBy == nil else {
                    continue
                }
                unblocked.append(row(
                    board: board,
                    issue: issue,
                    chips: [HolyInboxChip("unblocked", emphasis: .attention)],
                    evidence: finding.evidence
                ))
                dedicatedIssueIDs.insert(issue.id)
            }

            // 3. Stale claims.
            for finding in deduplicated(board.findings, kind: .deadClaim) {
                guard let id = finding.issueID,
                      let issue = byID[id],
                      issue.claimedBy != nil,
                      issue.status != .done else {
                    continue
                }
                staleClaims.append(row(
                    board: board,
                    issue: issue,
                    chips: [HolyInboxChip("stale claim", emphasis: .warning)],
                    evidence: finding.evidence ?? finding.detail
                ))
                dedicatedIssueIDs.insert(issue.id)
            }

            // The rest of the focused board is useful local context, not an
            // unread alert. Keep each issue in exactly one status section and
            // hide only completed or future-schema rows we cannot classify.
            for issue in board.issues where !dedicatedIssueIDs.contains(issue.id) {
                switch issue.type {
                case .dream:
                    // Already admitted above when incomplete.
                    continue
                case .track:
                    guard issue.status != .done, issue.status != .unknown else { continue }
                    tracks.append(row(board: board, issue: issue, chips: [], evidence: nil))
                case .item:
                    switch issue.status {
                    case .inProgress:
                        active.append(row(board: board, issue: issue, chips: [], evidence: nil))
                    case .open:
                        ready.append(row(board: board, issue: issue, chips: [], evidence: nil))
                    case .blocked:
                        blocked.append(row(board: board, issue: issue, chips: [], evidence: nil))
                    case .done, .unknown:
                        continue
                    }
                case .unknown:
                    continue
                }
            }

            if let detail = board.degradedDetail {
                degraded.append(HolyInboxRow(
                    id: "manna:\(board.root):degraded",
                    title: "manna unavailable — \(board.displayName)",
                    subtitle: detail,
                    isDegraded: true
                ))
            }
        }

        var sections: [HolyInboxSection] = []

        func append(
            id: String,
            title: String,
            rows: [HolyInboxRow],
            collapsedByDefault: Bool = false,
            countsTowardBadge: Bool = false
        ) {
            guard !rows.isEmpty else { return }
            sections.append(HolyInboxSection(
                id: id,
                sourceID: sourceID,
                title: title,
                rows: sorted(rows, focusedBoardRoot: focusedBoardRoot),
                collapsedByDefault: collapsedByDefault,
                countsTowardBadge: countsTowardBadge
            ))
        }

        append(
            id: "manna.dreams",
            title: "Manna · Dreams to triage",
            rows: dreams,
            countsTowardBadge: true
        )
        append(
            id: "manna.unblocked",
            title: "Manna · Unblocked, nobody on it",
            rows: unblocked,
            countsTowardBadge: true
        )
        // Drift cleanup is real work but it is not first-person attention;
        // it stays collapsed and out of the badge so the badge cannot lie.
        append(
            id: "manna.staleclaims",
            title: "Manna · Stale claims",
            rows: staleClaims,
            collapsedByDefault: true
        )
        append(id: "manna.active", title: "Manna · In progress", rows: active)
        append(
            id: "manna.ready",
            title: "Manna · Ready backlog",
            rows: ready,
            collapsedByDefault: true
        )
        append(
            id: "manna.blocked",
            title: "Manna · Blocked",
            rows: blocked,
            collapsedByDefault: true
        )
        append(
            id: "manna.tracks",
            title: "Manna · Tracks",
            rows: tracks,
            collapsedByDefault: true
        )
        append(id: "manna.degraded", title: "manna", rows: degraded)

        return sections
    }

    // MARK: Rows

    private static func row(
        board: HolyMannaBoardReading,
        issue: HolyMannaIssueSummary,
        chips: [HolyInboxChip],
        evidence: String?
    ) -> HolyInboxRow {
        let subtitle = [board.displayName, issue.id, evidence]
            .compactMap { $0 }
            .joined(separator: " · ")

        return HolyInboxRow(
            id: rowID(boardRoot: board.root, issueID: issue.id),
            title: issue.title,
            subtitle: subtitle,
            updatedAt: issue.updatedDate,
            chips: chips,
            action: spawnURL(boardRoot: board.root, issueID: issue.id)
                .map(HolyInboxRowAction.openURL) ?? .none
        )
    }

    static func rowID(boardRoot: String, issueID: String) -> String {
        "manna:\(boardRoot):\(issueID)"
    }

    /// Manna's own id alphabet: `mn-` plus a short lowercase [a-z0-9] token.
    /// Issue ids arrive from `.manna/issues.jsonl` in discovered repos, which
    /// makes them untrusted input when a board sits in a cloned third-party
    /// repo — and `spawnURL` puts the id into executed stdin. Anything outside
    /// this alphabet must never reach that surface.
    static func isValidIssueID(_ id: String) -> Bool {
        guard id.hasPrefix("mn-") else { return false }
        let token = id.dropFirst(3)
        guard (4...12).contains(token.count) else { return false }
        return token.allSatisfy { ($0.isLowercase && $0.isLetter && $0.isASCII) || ($0.isNumber && $0.isASCII) }
    }

    /// Clicking a row opens a shell in the board's repo showing the issue.
    ///
    /// `initial_input` is piped to the child's stdin, so whatever goes here
    /// RUNS — which is exactly why it is `manna show` and never `claim`,
    /// `abandon`, or `reconcile --fix`, and why the id is validated against
    /// manna's alphabet first. A glance must never move the board, and a
    /// hostile board must never move the machine.
    static func spawnURL(boardRoot: String, issueID: String) -> URL? {
        guard isValidIssueID(issueID) else { return nil }
        var components = URLComponents()
        components.scheme = HolyAutomationURLParser.scheme
        components.host = "spawn"
        components.queryItems = [
            URLQueryItem(name: "runtime", value: "shell"),
            URLQueryItem(name: "workingDirectory", value: boardRoot),
            URLQueryItem(name: "title", value: "manna · \(URL(fileURLWithPath: boardRoot).lastPathComponent)"),
            URLQueryItem(name: "initialInput", value: "agent-do manna show \(issueID)"),
        ]
        // URLComponents leaves "+" literal in a query value and the automation
        // parser reads it back as a space (form-encoding convention), so a
        // path like "a+b" would arrive mangled. Encode it here.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }

    // MARK: Findings

    private static func findingIssueIDs(
        _ findings: [HolyMannaReconcileFinding],
        kind: HolyMannaFindingKind
    ) -> [String] {
        findings.filter { $0.kind == kind }.compactMap(\.issueID)
    }

    /// Reconcile can report the same issue twice under one kind (blocked with
    /// an empty `blocked_by` and blocked with everything resolved are separate
    /// findings). One issue is one row.
    private static func deduplicated(
        _ findings: [HolyMannaReconcileFinding],
        kind: HolyMannaFindingKind
    ) -> [HolyMannaReconcileFinding] {
        var seen: Set<String> = []
        return findings.filter { finding in
            guard finding.kind == kind, let id = finding.issueID else { return false }
            return seen.insert(id).inserted
        }
    }

    // MARK: Ordering

    /// Focused board first, then newest activity first, then id for a stable
    /// order across ticks. The source supplies only the focused project and
    /// its nearest umbrella board; this ordering never widens that scope.
    private static func sorted(
        _ rows: [HolyInboxRow],
        focusedBoardRoot: String?
    ) -> [HolyInboxRow] {
        let focusedPrefix = focusedBoardRoot.map { "manna:\($0):" }
        return rows.sorted { lhs, rhs in
            if let focusedPrefix {
                let lhsFocused = lhs.id.hasPrefix(focusedPrefix)
                let rhsFocused = rhs.id.hasPrefix(focusedPrefix)
                if lhsFocused != rhsFocused { return lhsFocused }
            }
            let lhsDate = lhs.updatedAt ?? .distantPast
            let rhsDate = rhs.updatedAt ?? .distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.id < rhs.id
        }
    }
}
