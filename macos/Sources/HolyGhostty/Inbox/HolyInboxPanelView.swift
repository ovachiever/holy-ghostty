import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Panel layout law

enum HolyInboxPanelLayout {
    static let minWidth: CGFloat = 300
    static let defaultWidth: CGFloat = 360
    static let maxWidth: CGFloat = 480

    static func toggled(_ current: HolyWorkspaceRightPanel?) -> HolyWorkspaceRightPanel? {
        current == .inbox ? nil : .inbox
    }

    /// The panel yields to the terminal: it may never push the workspace
    /// below its minimum visible width, and it never leaves its own range.
    static func clampedWidth(
        _ proposed: CGFloat,
        available: CGFloat,
        reservedLeft: CGFloat
    ) -> CGFloat {
        let windowConstrainedMax = max(minWidth, available - reservedLeft)
        let ceiling = min(maxWidth, windowConstrainedMax)
        return min(max(proposed, minWidth), ceiling)
    }
}

enum HolyInboxBadge {
    /// Nil when there is nothing to say — a zero badge is noise.
    static func label(for count: Int) -> String? {
        guard count > 0 else { return nil }
        return count > 99 ? "99+" : String(count)
    }
}

// MARK: - Right panel host

/// The single right-hand region. Enum-driven: the archive surface
/// (mn-fe1b48) adds a case to HolyWorkspaceRightPanel and a branch here —
/// never a second panel.
struct HolyWorkspaceRightPanelHost: View {
    @ObservedObject var store: HolyWorkspaceStore

    var body: some View {
        switch store.rightPanelSelection {
        case .inbox:
            HolyInboxPanelView(store: store, engine: store.inboxEngine)
        case nil:
            EmptyView()
        }
    }
}

// MARK: - Inbox panel

/// The inbox for humans: every row is addressed to Erik, actionable, and
/// self-clearing when reality changes. The pane shows what the terminal
/// cannot — cross-repo attention state — with minimal chrome.
struct HolyInboxPanelView: View {
    @ObservedObject var store: HolyWorkspaceStore
    @ObservedObject var engine: HolyInboxEngine

    /// User overrides of per-section collapse; unset sections follow their
    /// snapshot default.
    @State private var expandedOverrides: [String: Bool] = [:]
    /// Expanded digest rows (bot PRs per repo).
    @State private var expandedDigestRowIDs: Set<String> = []
    /// The lens. Text filters every rendered row; Enter routes mn-ids to the
    /// board, #N to the focused repo's PR, prose to `brief ask`.
    @State private var lensText = ""

    /// Erik's spec, 2026-08-12, replacing the brief-instrument experiment:
    /// the default view is THIS PROJECT (its GitHub attention + its manna +
    /// alerts); one tab away is ALL GITHUB (every PR needing him anywhere).
    enum Tab: String, CaseIterable {
        case project
        case githubAll
    }

    @State private var tab: Tab = .project
    /// The focused session's GitHub slug, resolved async per selection.
    @State private var focusedSlug: String?

    var body: some View {
        VStack(spacing: 0) {
            header

            tabPicker

            lensField

            Rectangle()
                .fill(HolyGhosttyTheme.border)
                .frame(height: 0.5)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    switch tab {
                    case .project:
                        projectSections
                    case .githubAll:
                        globalGitHubSections
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)

            footer
        }
        .frame(maxHeight: .infinity)
        .background(HolyGhosttyTheme.bgElevated)
        .onAppear { engine.setPanelVisible(true) }
        .onDisappear { engine.setPanelVisible(false) }
        .task(id: store.selectedSessionID) {
            focusedSlug = await store.focusedRepoSlug()
        }
    }

    private var tabPicker: some View {
        HStack(spacing: 2) {
            tabButton(.project, title: focusedProjectName ?? "This project")
            tabButton(.githubAll, title: "All GitHub")
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private func tabButton(_ target: Tab, title: String) -> some View {
        Button {
            tab = target
        } label: {
            Text(title)
                .font(.system(size: 10.5, weight: tab == target ? .semibold : .regular))
                .foregroundStyle(tab == target
                    ? HolyGhosttyTheme.textPrimary
                    : HolyGhosttyTheme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(tab == target ? HolyGhosttyTheme.bg : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: This project

    /// A gh row belongs to the focused repo when its subtitle starts with
    /// the slug followed by a boundary ("org/repo#7 · author" or the digest
    /// row's bare "org/repo") — a bare prefix match would also claim
    /// "org/repo-sibling".
    private func rowBelongsToFocusedRepo(_ row: HolyInboxRow) -> Bool {
        guard let slug = focusedSlug, let subtitle = row.subtitle else { return false }
        if subtitle == slug { return true }
        if subtitle.hasPrefix(slug + "#") { return true }
        if subtitle.hasPrefix(slug + " ") { return true }
        return row.children.contains { rowBelongsToFocusedRepo($0) }
    }

    @ViewBuilder
    private var projectSections: some View {
        let lens = lensText.trimmingCharacters(in: .whitespaces).lowercased()

        // The focused repo's GitHub attention. No slug (no remote, detached
        // session) renders no GitHub here — All GitHub is one tab away.
        ForEach(engine.sections.filter { $0.sourceID == HolyGitHubInboxSectioner.sourceID }) { section in
            let rows = section.rows.filter {
                rowBelongsToFocusedRepo($0) && lensMatches($0.title + " " + ($0.subtitle ?? ""), lens)
            }
            if !rows.isEmpty {
                let visible = rows.reduce(0) { total, row in
                    let children = row.children.filter { rowBelongsToFocusedRepo($0) }
                    return total + (children.isEmpty ? 1 : children.count)
                }
                sectionHeader(section, visibleCount: visible)
                if isExpanded(section) {
                    ForEach(rows) { row in
                        rowView(row, in: section)
                        if expandedDigestRowIDs.contains(row.id) {
                            ForEach(row.children.filter { rowBelongsToFocusedRepo($0) }) { child in
                                rowView(child, in: section, indented: true)
                            }
                        }
                    }
                }
            }
        }

        // The focused project's board, whole.
        ForEach(engine.sections.filter { $0.sourceID == HolyMannaInboxSectioner.sourceID }) { section in
            let rows = section.rows.filter { lensMatches($0.title + " " + ($0.subtitle ?? ""), lens) }
            sectionHeader(section, visibleCount: rows.count)
            if isExpanded(section) {
                ForEach(rows) { row in
                    rowView(row, in: section)
                }
            }
        }

        // Alerts are already scoped to this machine's sessions.
        ForEach(engine.sections.filter { $0.sourceID == "alerts" }) { section in
            let rows = section.rows.filter { lensMatches($0.title, lens) }
            sectionHeader(section, visibleCount: rows.count)
            if isExpanded(section) {
                ForEach(rows) { row in
                    rowView(row, in: section)
                }
            }
        }
    }

    // MARK: All GitHub

    @ViewBuilder
    private var globalGitHubSections: some View {
        let lens = lensText.trimmingCharacters(in: .whitespaces).lowercased()
        ForEach(engine.sections.filter { $0.sourceID == HolyGitHubInboxSectioner.sourceID }) { section in
            let rows = section.rows.filter { lensMatches($0.title + " " + ($0.subtitle ?? ""), lens) }
            let visible = rows.reduce(0) { total, row in
                total + (row.children.isEmpty ? 1 : row.children.count)
            }
            sectionHeader(section, visibleCount: visible)
            if isExpanded(section) {
                ForEach(rows) { row in
                    rowView(row, in: section)
                    if expandedDigestRowIDs.contains(row.id) {
                        ForEach(row.children) { child in
                            rowView(child, in: section, indented: true)
                        }
                    }
                }
            }
        }
    }

    // MARK: Shared context

    private func lensMatches(_ haystack: String, _ lens: String) -> Bool {
        lens.isEmpty || haystack.lowercased().contains(lens)
    }

    private var focusedBoardPath: String? {
        HolyMannaInboxSource.repositoryRoots(focused: store.selectedSession).first
    }

    private var focusedProjectName: String? {
        focusedBoardPath.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    // MARK: Lens

    private var lensField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(HolyGhosttyTheme.textTertiary)
            TextField("Search or ask…", text: $lensText)
                .textFieldStyle(.plain)
                .font(.system(size: 10.5))
                .foregroundStyle(HolyGhosttyTheme.textPrimary)
                .onSubmit(routeLens)
            if !lensText.isEmpty {
                Button {
                    lensText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(HolyGhosttyTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
    }

    /// Enter routes by shape: a manna id opens the board row in a shell
    /// (typed, read-only verb), #N opens the focused repo's PR, anything
    /// else becomes a `brief ask` question typed into a shell.
    private func routeLens() {
        let input = lensText.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return }

        if HolyMannaInboxSectioner.isValidIssueID(input) {
            if let root = focusedBoardPath,
               let url = HolyMannaInboxSectioner.spawnURL(boardRoot: root, issueID: input) {
                openURL(url)
            }
            return
        }
        if input.hasPrefix("#"), let number = Int(input.dropFirst()), number > 0 {
            if let repo = focusedSlug,
               let url = URL(string: "https://github.com/\(repo)/pull/\(number)") {
                openURL(url)
            }
            return
        }
        if let url = HolyBriefSpawn.askURL(question: input, workingDirectory: focusedBoardPath) {
            openURL(url)
            lensText = ""
        }
    }

    private func openURL(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("Inbox")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(HolyGhosttyTheme.textPrimary)

            if let badge = HolyInboxBadge.label(for: engine.badgeCount) {
                Text(badge)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(HolyGhosttyTheme.bg)
                    .padding(.horizontal, 5)
                    .frame(height: 14)
                    .background(Capsule(style: .continuous).fill(HolyGhosttyTheme.halo))
            }

            Spacer()

            if engine.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
            }

            Button {
                engine.requestRefresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 22, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(HolyGhosttyTheme.textSecondary)
            .help("Refresh inbox")

            Button {
                store.toggleInboxPanel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 22, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(HolyGhosttyTheme.textSecondary)
            .help("Close inbox")
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
    }

    // MARK: Sections

    private var sectionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(engine.sections) { section in
                    sectionHeader(section)
                    if isExpanded(section) {
                        ForEach(section.rows) { row in
                            rowView(row, in: section)
                            if expandedDigestRowIDs.contains(row.id) {
                                ForEach(row.children) { child in
                                    rowView(child, in: section, indented: true)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
    }

    /// `visibleCount` is the count of what THIS TAB will actually render —
    /// a header must never advertise rows its body filters away (Erik
    /// 2026-08-12: "Yours, open" said 10 globally while the vms.io tab
    /// showed its 2).
    private func sectionHeader(
        _ section: HolyInboxSection,
        visibleCount: Int? = nil
    ) -> some View {
        Button {
            expandedOverrides[section.id] = !isExpanded(section)
        } label: {
            HStack(spacing: 6) {
                Text(section.title)
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(HolyGhosttyTheme.textSecondary)

                Text("\(visibleCount ?? rowCount(for: section))")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .rotationEffect(isExpanded(section) ? .zero : .degrees(-90))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }

    private func isExpanded(_ section: HolyInboxSection) -> Bool {
        expandedOverrides[section.id] ?? !section.collapsedByDefault
    }

    private func rowCount(for section: HolyInboxSection) -> Int {
        section.rows.reduce(0) { total, row in
            total + (row.children.isEmpty ? 1 : row.children.count)
        }
    }

    // MARK: Rows

    private func rowView(
        _ row: HolyInboxRow,
        in section: HolyInboxSection,
        indented: Bool = false
    ) -> some View {
        HolyInboxRowView(
            row: row,
            indented: indented,
            isDigestExpanded: expandedDigestRowIDs.contains(row.id),
            onPrimaryAction: { performPrimaryAction(for: row) },
            onAcknowledge: row.acknowledgeable
                ? { acknowledge(row, in: section) }
                : nil
        )
    }

    private func performPrimaryAction(for row: HolyInboxRow) {
        if !row.children.isEmpty {
            if expandedDigestRowIDs.contains(row.id) {
                expandedDigestRowIDs.remove(row.id)
            } else {
                expandedDigestRowIDs.insert(row.id)
            }
            return
        }

        switch row.action {
        case let .openURL(url):
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #endif
        case let .selectSession(sessionID):
            store.selectSession(sessionID)
        case .none:
            break
        }
    }

    private func acknowledge(_ row: HolyInboxRow, in section: HolyInboxSection) {
        let engine = engine
        Task { @MainActor in
            await engine.acknowledge(rowID: row.id, inSectionID: section.id)
        }
    }

    // MARK: Empty and footer

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            if engine.lastRefreshedAt == nil {
                Text("Checking…")
                    .font(.system(size: 11))
                    .foregroundStyle(HolyGhosttyTheme.textSecondary)
            } else {
                Text("Nothing needs you")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(HolyGhosttyTheme.textSecondary)
                Text("Rows appear when a PR or alert waits on you, and leave when reality clears them.")
                    .font(.system(size: 10))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 220)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var footer: some View {
        if !engine.footnotes.isEmpty || engine.lastRefreshedAt != nil {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(engine.footnotes, id: \.self) { note in
                    Text(note)
                        .font(.system(size: 9))
                        .foregroundStyle(HolyGhosttyTheme.textTertiary)
                        .lineLimit(1)
                }
                if let refreshedAt = engine.lastRefreshedAt {
                    Text("Updated \(HolyInboxRowView.relativeTime(from: refreshedAt))")
                        .font(.system(size: 9))
                        .foregroundStyle(HolyGhosttyTheme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(HolyGhosttyTheme.border)
                    .frame(height: 0.5)
            }
        }
    }
}

// MARK: - Row

struct HolyInboxRowView: View {
    let row: HolyInboxRow
    let indented: Bool
    let isDigestExpanded: Bool
    let onPrimaryAction: () -> Void
    let onAcknowledge: (() -> Void)?

    @State private var isHovering = false

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static func relativeTime(from date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: .now)
    }

    var body: some View {
        Button(action: onPrimaryAction) {
            HStack(alignment: .top, spacing: 8) {
                if !row.children.isEmpty {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .rotationEffect(isDigestExpanded ? .degrees(90) : .zero)
                        .foregroundStyle(HolyGhosttyTheme.textTertiary)
                        .frame(width: 10)
                        .padding(.top, 3)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(row.title)
                        .font(.system(size: 12, weight: row.isDegraded ? .regular : .medium))
                        .foregroundStyle(
                            row.isDegraded
                                ? HolyGhosttyTheme.textSecondary
                                : HolyGhosttyTheme.textPrimary
                        )
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    // The stage line: whose move it is, in words. Verb
                    // leads; tint reinforces only when the ball is Erik's
                    // (words + position law — color never carries alone).
                    if let stage = row.stage {
                        (Text(stage.verb).fontWeight(.semibold)
                            + Text(" — \(stage.detail)"))
                            .font(.system(size: 10))
                            .foregroundStyle(
                                stage.yours
                                    ? HolyGhosttyTheme.warning
                                    : HolyGhosttyTheme.textSecondary
                            )
                            .lineLimit(1)
                    }

                    if row.subtitle != nil || !row.chips.isEmpty {
                        HStack(spacing: 6) {
                            if let subtitle = row.subtitle {
                                Text(subtitle)
                                    .font(.system(size: 10))
                                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            ForEach(row.chips, id: \.self) { chip in
                                HolyInboxChipView(chip: chip)
                            }
                        }
                    }
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 4) {
                    if let updatedAt = row.updatedAt {
                        Text(Self.relativeTime(from: updatedAt))
                            .font(.system(size: 9))
                            .foregroundStyle(HolyGhosttyTheme.textTertiary)
                    }

                    if let onAcknowledge, isHovering {
                        Button(action: onAcknowledge) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .semibold))
                                .frame(width: 20, height: 16)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(HolyGhosttyTheme.success)
                        .help("Acknowledge")
                    }

                    // Spawns a shell with the stage's command TYPED; the
                    // human's Enter fires it (never auto-executed).
                    if let spawnURL = row.commandSpawnURL, isHovering {
                        Button {
                            NSWorkspace.shared.open(spawnURL)
                        } label: {
                            Image(systemName: "terminal")
                                .font(.system(size: 9, weight: .semibold))
                                .frame(width: 20, height: 16)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(HolyGhosttyTheme.accent)
                        .help("Open a shell with the command typed")
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.leading, indented ? 26 : 12)
            .padding(.trailing, 12)
            .contentShape(Rectangle())
            .background(isHovering ? Color.white.opacity(0.04) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Chip

struct HolyInboxChipView: View {
    let chip: HolyInboxChip

    var body: some View {
        Text(chip.label)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .frame(height: 14)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(color.opacity(0.35), lineWidth: 0.7)
            )
            .fixedSize()
    }

    private var color: Color {
        switch chip.emphasis {
        case .neutral:
            return HolyGhosttyTheme.textTertiary
        case .attention:
            return HolyGhosttyTheme.accent
        case .warning:
            return HolyGhosttyTheme.warning
        case .danger:
            return HolyGhosttyTheme.danger
        }
    }
}

// MARK: - Toggle affordance

/// The inbox toggle for the workspace's bottom-left control rail: tray icon
/// plus the unread badge, which only speaks when the count is nonzero.
struct HolyInboxToggleButton: View {
    @ObservedObject var store: HolyWorkspaceStore
    @ObservedObject var engine: HolyInboxEngine

    var body: some View {
        Button {
            store.toggleInboxPanel()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "tray")
                    .font(.system(size: 10, weight: .medium))
                    .symbolVariant(store.rightPanelSelection == .inbox ? .fill : .none)

                if let badge = HolyInboxBadge.label(for: engine.badgeCount) {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(HolyGhosttyTheme.bg)
                        .padding(.horizontal, 4)
                        .frame(height: 13)
                        .background(Capsule(style: .continuous).fill(HolyGhosttyTheme.halo))
                }
            }
            .frame(height: 22)
            .padding(.horizontal, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        store.rightPanelSelection == .inbox
                            ? HolyGhosttyTheme.halo.opacity(0.14)
                            : Color.clear
                    )
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            store.rightPanelSelection == .inbox
                ? HolyGhosttyTheme.halo
                : HolyGhosttyTheme.textSecondary
        )
        .help("Inbox — what needs you (⌘P)")
    }
}
