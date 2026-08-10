import Foundation
import OSLog

// MARK: - Pinned payload

/// One PR row from `agent-do gh inbox --json`. Field names are pinned from a
/// live invocation on 2026-08-03 — author, comments, draft, labels, number,
/// reasons, ref, repo, state, title, updated_at, url — do not edit them from
/// memory; re-run the CLI. Top-level `sweep`/`total` keys are ignored.
struct HolyGitHubInboxItem: Equatable, Sendable {
    let author: String
    /// Ceremony-search rows carry a count. The maintainer REST sweep cannot
    /// obtain that field without another request per PR, so its live contract
    /// is `null`, meaning unknown rather than zero.
    let comments: Int?
    let draft: Bool
    let labels: [String]
    let number: Int
    /// Observed values: review_requested, maintainer_unreviewed,
    /// maintainer_review_stale, authored_open, bot_author. A row carries a
    /// list; unknown future values surface in the "Other attention" section.
    let reasons: [String]
    /// "org/repo#n" — display only; `repo` and `url` are provided directly.
    let ref: String
    let repo: String
    let state: String
    let title: String
    let updatedAt: Date?
    let url: String
}

extension HolyGitHubInboxItem: Decodable {
    private enum CodingKeys: String, CodingKey {
        case author
        case comments
        case draft
        case labels
        case number
        case reasons
        case ref
        case repo
        case state
        case title
        case updatedAt = "updated_at"
        case url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        author = try container.decode(String.self, forKey: .author)
        guard container.contains(.comments) else {
            throw DecodingError.keyNotFound(
                CodingKeys.comments,
                .init(
                    codingPath: container.codingPath,
                    debugDescription: "Expected comments to be present as a count or null."
                )
            )
        }
        comments = try container.decodeIfPresent(Int.self, forKey: .comments)
        draft = try container.decode(Bool.self, forKey: .draft)
        // Live rows always showed `[]`; if the CLI ever ships label objects
        // instead of strings, the row survives without them.
        labels = (try? container.decode([String].self, forKey: .labels)) ?? []
        number = try container.decode(Int.self, forKey: .number)
        reasons = try container.decode([String].self, forKey: .reasons)
        ref = try container.decode(String.self, forKey: .ref)
        repo = try container.decode(String.self, forKey: .repo)
        state = try container.decode(String.self, forKey: .state)
        title = try container.decode(String.self, forKey: .title)
        let rawDate = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        updatedAt = rawDate.flatMap { ISO8601DateFormatter().date(from: $0) }
        url = try container.decode(String.self, forKey: .url)
    }
}

struct HolyGitHubInboxPayload: Decodable, Equatable, Sendable {
    let count: Int
    let items: [HolyGitHubInboxItem]

    /// Fail-closed: any payload outside the pinned contract parses to nil so
    /// the source degrades honestly instead of rendering a guess.
    static func parse(_ data: Data) -> HolyGitHubInboxPayload? {
        try? JSONDecoder().decode(HolyGitHubInboxPayload.self, from: data)
    }
}

// MARK: - Remote → slug

/// Extracts "org/repo" from a `git remote get-url origin` answer so the
/// focused session's repo can sort first. Wrong slug is worse than no slug:
/// unrecognized shapes return nil.
enum HolyGitHubRemoteParser {
    static func slug(fromRemoteURL raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var path: Substring
        if let schemeRange = trimmed.range(of: "://") {
            // https://github.com/org/repo(.git) | ssh://git@github.com/org/repo.git
            let afterScheme = trimmed[schemeRange.upperBound...]
            guard let hostEnd = afterScheme.firstIndex(of: "/") else { return nil }
            path = afterScheme[afterScheme.index(after: hostEnd)...]
        } else if let colon = trimmed.firstIndex(of: ":"),
                  trimmed[..<colon].contains("@") {
            // scp-like: git@github.com:org/repo.git
            path = trimmed[trimmed.index(after: colon)...]
        } else {
            return nil
        }

        while path.hasSuffix("/") {
            path = path.dropLast()
        }
        if path.hasSuffix(".git") {
            path = path.dropLast(4)
        }

        let components = path.split(separator: "/").filter { !$0.isEmpty }
        guard components.count >= 2 else { return nil }
        return components.suffix(2).joined(separator: "/")
    }
}

/// One `git remote get-url origin` per repository root per app lifetime;
/// remotes do not churn while a session runs.
actor HolyGitHubRepoSlugResolver {
    private var cache: [String: String?] = [:]

    func slug(forRepositoryRoot root: String) async -> String? {
        if let cached = cache[root] {
            return cached
        }

        let result = await HolyRestoreProcessRunner.run(
            executablePath: "/usr/bin/git",
            arguments: ["-C", root, "remote", "get-url", "origin"],
            timeout: 10
        )

        var slug: String?
        if case let .success(output) = result, output.exitCode == 0 {
            slug = HolyGitHubRemoteParser.slug(fromRemoteURL: output.stdout)
        }
        cache[root] = slug
        return slug
    }
}

// MARK: - Sectioning

/// The admission law for GitHub rows. Attention-first sections from live
/// reason semantics; bot authors collapse to one digest per repo; the focused
/// session's repo sorts first but never filters — what waits on Erik
/// elsewhere still waits on Erik.
enum HolyGitHubInboxSectioner {
    static let sourceID = "gh"

    static func sections(
        items: [HolyGitHubInboxItem],
        focusedRepoSlug: String?
    ) -> [HolyInboxSection] {
        var authoredChanges: [HolyGitHubInboxItem] = []
        var review: [HolyGitHubInboxItem] = []
        var maintainer: [HolyGitHubInboxItem] = []
        var authored: [HolyGitHubInboxItem] = []
        var bots: [HolyGitHubInboxItem] = []
        var other: [HolyGitHubInboxItem] = []

        for item in items {
            let reasons = Set(item.reasons)
            if reasons.contains("bot_author") {
                bots.append(item)
            } else if reasons.contains("authored_changes_requested") {
                // Another human has acted on Erik's work and handed the ball
                // back. This is direct attention, not generic authored-open
                // inventory, so it must not hide in a collapsed section.
                authoredChanges.append(item)
            } else if reasons.contains("review_requested") {
                review.append(item)
            } else if reasons.contains("maintainer_unreviewed")
                || reasons.contains("maintainer_review_stale") {
                maintainer.append(item)
            } else if reasons.contains("authored_open") {
                authored.append(item)
            } else {
                other.append(item)
            }
        }

        var sections: [HolyInboxSection] = []

        func append(
            id: String,
            title: String,
            items sectionItems: [HolyGitHubInboxItem],
            collapsedByDefault: Bool = false,
            countsTowardBadge: Bool = false
        ) {
            guard !sectionItems.isEmpty else { return }
            sections.append(HolyInboxSection(
                id: id,
                sourceID: sourceID,
                title: title,
                rows: sorted(sectionItems, focusedRepoSlug: focusedRepoSlug).map(row(for:)),
                collapsedByDefault: collapsedByDefault,
                countsTowardBadge: countsTowardBadge
            ))
        }

        append(
            id: "gh.authored_changes",
            title: "Changes requested on yours",
            items: authoredChanges,
            countsTowardBadge: true
        )
        append(
            id: "gh.review",
            title: "Needs your review",
            items: review,
            countsTowardBadge: true
        )
        append(
            id: "gh.maintainer",
            title: "Unreviewed in repos you maintain",
            items: maintainer
        )
        append(
            id: "gh.authored",
            title: "Yours, open",
            items: authored,
            collapsedByDefault: true
        )
        if !bots.isEmpty {
            sections.append(botSection(bots, focusedRepoSlug: focusedRepoSlug))
        }
        append(
            id: "gh.other",
            title: "Other attention",
            items: other
        )

        return sections
    }

    // MARK: Rows

    private static func row(for item: HolyGitHubInboxItem) -> HolyInboxRow {
        var chips = item.reasons.compactMap(chip(forReason:))
        if item.draft {
            chips.append(HolyInboxChip("draft", emphasis: .neutral))
        }

        return HolyInboxRow(
            id: "gh:\(item.ref)",
            title: item.title,
            subtitle: "\(item.ref) · \(item.author)",
            updatedAt: item.updatedAt,
            chips: chips,
            action: URL(string: item.url).map(HolyInboxRowAction.openURL) ?? .none
        )
    }

    private static func chip(forReason reason: String) -> HolyInboxChip? {
        switch reason {
        case "review_requested":
            return HolyInboxChip("review requested", emphasis: .attention)
        case "maintainer_unreviewed":
            return HolyInboxChip("unreviewed", emphasis: .neutral)
        case "maintainer_review_stale":
            return HolyInboxChip("review stale", emphasis: .warning)
        case "authored_open":
            // The section already says "Yours, open"; a chip would repeat it.
            return nil
        case "authored_changes_requested":
            return HolyInboxChip("changes requested", emphasis: .attention)
        case "bot_author":
            return HolyInboxChip("bot", emphasis: .neutral)
        default:
            return HolyInboxChip(reason.replacingOccurrences(of: "_", with: " "), emphasis: .neutral)
        }
    }

    // MARK: Bot digests

    private static func botSection(
        _ items: [HolyGitHubInboxItem],
        focusedRepoSlug: String?
    ) -> HolyInboxSection {
        let byRepo = Dictionary(grouping: items, by: \.repo)

        var digests: [HolyInboxRow] = byRepo.map { repo, repoItems in
            let children = sorted(repoItems, focusedRepoSlug: nil).map(row(for:))
            let botNames = Set(repoItems.map { botName(fromAuthor: $0.author) })
            let name = botNames.count == 1 ? botNames.first! : "bot"
            let shortRepo = repo.split(separator: "/").last.map(String.init) ?? repo
            let plural = repoItems.count == 1 ? "PR" : "PRs"

            return HolyInboxRow(
                id: "gh.bots:\(repo)",
                title: "\(repoItems.count) \(name) \(plural) — \(shortRepo)",
                subtitle: repo,
                updatedAt: repoItems.compactMap(\.updatedAt).max(),
                chips: [HolyInboxChip("bot", emphasis: .neutral)],
                action: .none,
                children: children
            )
        }

        digests.sort { lhs, rhs in
            let lhsFocused = focusedRepoSlug != nil && lhs.subtitle == focusedRepoSlug
            let rhsFocused = focusedRepoSlug != nil && rhs.subtitle == focusedRepoSlug
            if lhsFocused != rhsFocused { return lhsFocused }
            return (lhs.updatedAt ?? .distantPast) > (rhs.updatedAt ?? .distantPast)
        }

        return HolyInboxSection(
            id: "gh.bots",
            sourceID: sourceID,
            title: "Bot PRs",
            rows: digests,
            collapsedByDefault: true,
            countsTowardBadge: false
        )
    }

    private static func botName(fromAuthor author: String) -> String {
        author.hasSuffix("[bot]") ? String(author.dropLast(5)) : author
    }

    // MARK: Ordering

    /// Focused repo first, then newest activity first. Focus reorders, never
    /// filters.
    private static func sorted(
        _ items: [HolyGitHubInboxItem],
        focusedRepoSlug: String?
    ) -> [HolyGitHubInboxItem] {
        items.sorted { lhs, rhs in
            if let focusedRepoSlug {
                let lhsFocused = lhs.repo == focusedRepoSlug
                let rhsFocused = rhs.repo == focusedRepoSlug
                if lhsFocused != rhsFocused { return lhsFocused }
            }
            return (lhs.updatedAt ?? .distantPast) > (rhs.updatedAt ?? .distantPast)
        }
    }
}

// MARK: - Source

/// Production bridge to `agent-do gh inbox`. Same subprocess-JSON-degrade
/// shape as HolyAgentSessionsResolveClient: PATH-resolved once through a
/// login shell, invoked directly with an argument array, and every failure
/// mode collapses into one quiet degraded row — never a crash, never
/// invented emptiness.
final class HolyGitHubInboxSource: HolyInboxRowSource {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mitchellh.ghostty",
        category: "HolyGitHubInboxSource"
    )
    static let binaryName = "agent-do"
    /// `gh inbox` sweeps every watched repo through the GitHub API; give it
    /// room on cold caches before declaring it broken.
    static let commandTimeout: TimeInterval = 120
    /// Same bound as the restore probes: a login shell that hasn't answered
    /// in 15s is wedged on rc files or a network mount, and inbox refresh
    /// must not hang behind it.
    static let loginShellProbeTimeout: TimeInterval = 15
    static let rowLimit = 50

    let sourceID = HolyGitHubInboxSectioner.sourceID

    private let binaryPathOverride: String?

    init(binaryPathOverride: String? = nil) {
        self.binaryPathOverride = binaryPathOverride
    }

    static func inboxArguments(limit: Int) -> [String] {
        ["gh", "inbox", "--json", "--limit", String(limit)]
    }

    static func degradedSnapshot(detail: String) -> HolyInboxSourceSnapshot {
        HolyInboxSourceSnapshot(sections: [
            HolyInboxSection(
                id: "gh.degraded",
                sourceID: HolyGitHubInboxSectioner.sourceID,
                title: "GitHub",
                rows: [
                    HolyInboxRow(
                        id: "gh:degraded",
                        title: "GitHub inbox unavailable",
                        subtitle: detail,
                        isDegraded: true
                    ),
                ]
            ),
        ])
    }

    func refresh(context: HolyInboxRefreshContext) async -> HolyInboxSourceSnapshot {
        guard let binaryPath = await resolvedBinaryPath() else {
            return Self.degradedSnapshot(
                detail: "The \(Self.binaryName) CLI was not found on PATH."
            )
        }

        let result = await HolyRestoreProcessRunner.run(
            executablePath: binaryPath,
            arguments: Self.inboxArguments(limit: Self.rowLimit),
            timeout: Self.commandTimeout,
            environment: await Self.sharedSubprocessEnvironment.value
        )

        switch result {
        case let .failure(reason):
            Self.logger.error("gh inbox subprocess failed: \(reason, privacy: .public)")
            return Self.degradedSnapshot(detail: reason)
        case let .success(output):
            guard output.exitCode == 0 else {
                // The panel truncates the row's subtitle, which has already
                // cost two diagnosis rounds — log the WHOLE failure, and put
                // the LAST stderr line in the row (gh's verdict line), not
                // the head of a traceback.
                let stderr = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                Self.logger.error(
                    "gh inbox exited \(output.exitCode): \(stderr, privacy: .public)"
                )
                let lastLine = stderr
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .last { !$0.isEmpty }
                return Self.degradedSnapshot(
                    detail: "\(Self.binaryName) gh inbox exited with status \(output.exitCode)."
                        + (lastLine.map { " \($0)" } ?? "")
                )
            }
            guard let payload = HolyGitHubInboxPayload.parse(Data(output.stdout.utf8)) else {
                return Self.degradedSnapshot(
                    detail: "\(Self.binaryName) gh inbox returned a payload outside the pinned contract."
                )
            }
            return HolyInboxSourceSnapshot(
                sections: HolyGitHubInboxSectioner.sections(
                    items: payload.items,
                    focusedRepoSlug: context.focusedRepoSlug
                )
            )
        }
    }

    private func resolvedBinaryPath() async -> String? {
        if let binaryPathOverride {
            return FileManager.default.isExecutableFile(atPath: binaryPathOverride)
                ? binaryPathOverride
                : nil
        }
        return await Self.sharedBinaryPath.value
    }

    /// The subprocess environment is launch-context roulette without this: a
    /// Dock launch has no /opt/homebrew/bin, so agent-gh cannot find the gh
    /// CLI it drives; an app relaunched from a terminal inherits that shell's
    /// whole world. Capture the login-shell PATH once and overlay it, so the
    /// sweep behaves identically however the app was started. HOME rides
    /// along untouched — gh reads its token from ~/.config/gh/hosts.yml.
    static let sharedSubprocessEnvironment = Task<[String: String], Never> {
        var environment = ProcessInfo.processInfo.environment
        let result = await HolyRestoreProcessRunner.run(
            executablePath: "/bin/zsh",
            arguments: ["-lc", #"printf %s "$PATH""#],
            timeout: loginShellProbeTimeout
        )
        if case let .success(output) = result, output.exitCode == 0 {
            let path = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                environment["PATH"] = path
            }
        }
        return environment
    }

    /// One PATH lookup per app lifetime, matching the resolve client: a Dock
    /// launch inherits a login (non-interactive) shell PATH, so probe through
    /// `/bin/zsh -lc` and fall back to well-known install locations.
    private static let sharedBinaryPath = Task<String?, Never> {
        let result = await HolyRestoreProcessRunner.run(
            executablePath: "/bin/zsh",
            arguments: ["-lc", "command -v \(binaryName)"],
            timeout: loginShellProbeTimeout
        )
        if case let .success(output) = result, output.exitCode == 0 {
            let path = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                return path
            }
        }
        return wellKnownBinaryPath()
    }

    static func wellKnownBinaryPath() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/\(binaryName)",
            "/opt/homebrew/bin/\(binaryName)",
            "/usr/local/bin/\(binaryName)",
            // This machine runs agent-do straight from its repo checkout.
            "\(home)/Custom-Coding/agent-do/\(binaryName)",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
