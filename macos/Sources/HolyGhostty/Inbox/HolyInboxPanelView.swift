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
            HolyInboxPanelView(
                store: store,
                engine: store.inboxEngine,
                brief: store.briefFeed
            )
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
    @ObservedObject var brief: HolyBriefFeed

    /// User overrides of per-section collapse; unset sections follow their
    /// snapshot default.
    @State private var expandedOverrides: [String: Bool] = [:]
    /// Expanded digest rows (bot PRs per repo).
    @State private var expandedDigestRowIDs: Set<String> = []
    /// The Library drawer: everything browsable, collapsed by default so
    /// attention is the panel's resting state.
    @State private var libraryExpanded = false
    /// Suggestion groups the user opened past their preview rows.
    @State private var expandedSuggestionKinds: Set<String> = []
    /// The attention overflow ("N more waiting") opened by hand.
    @State private var attentionOverflowExpanded = false
    /// The lens. Text filters every rendered row; Enter routes mn-ids to the
    /// board, #N to the focused repo's PR, prose to `brief ask`.
    @State private var lensText = ""

    var body: some View {
        VStack(spacing: 0) {
            header

            lensField

            Rectangle()
                .fill(HolyGhosttyTheme.border)
                .frame(height: 0.5)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    briefBlock
                    needsMeDrawer
                    libraryDrawer
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)

            footer
        }
        .frame(maxHeight: .infinity)
        .background(HolyGhosttyTheme.bgElevated)
        .onAppear {
            engine.setPanelVisible(true)
            brief.requestRefresh()
        }
        .onDisappear { engine.setPanelVisible(false) }
    }

    // MARK: Brief (answer line + attention)

    private var triaged: HolyBriefTriage.Triaged? {
        brief.payload.map { HolyBriefTriage.triage($0, now: .now) }
    }

    private var focusedBoardPath: String? {
        HolyMannaInboxSource.repositoryRoots(focused: store.selectedSession).first
    }

    @ViewBuilder
    private var briefBlock: some View {
        if let payload = brief.payload {
            HolyBriefAnswerLineView(
                paragraph: payload.paragraph,
                generatedAt: payload.generatedAt,
                failureReason: brief.failureReason,
                sourceNotes: triaged?.sourceNotes ?? []
            )
        } else if let failureReason = brief.failureReason {
            VStack(alignment: .leading, spacing: 4) {
                Text("Brief unavailable")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(HolyGhosttyTheme.textPrimary)
                Text(failureReason)
                    .font(.system(size: 9.5))
                    .foregroundStyle(HolyGhosttyTheme.textSecondary)
                    .lineLimit(3)
                    .help(failureReason)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        } else if brief.isRefreshing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small).scaleEffect(0.55)
                Text("Reading the estate…")
                    .font(.system(size: 10.5))
                    .foregroundStyle(HolyGhosttyTheme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private var needsMeDrawer: some View {
        if let triaged {
            let lens = lensText.trimmingCharacters(in: .whitespaces).lowercased()

            if let hero = triaged.hero, lensMatches(hero.title, lens) {
                drawerLabel("Needs you")
                HolyBriefThreadRowView(
                    thread: hero,
                    density: .hero,
                    isNewSinceLastLook: triaged.deltaThreadIDs.contains(hero.id),
                    onOpen: openAction(for: hero)
                )
            }
            ForEach(triaged.needsMe.filter { lensMatches($0.title, lens) }, id: \.id) { thread in
                HolyBriefThreadRowView(
                    thread: thread,
                    density: .standard,
                    isNewSinceLastLook: triaged.deltaThreadIDs.contains(thread.id),
                    onOpen: openAction(for: thread)
                )
            }

            let overflow = triaged.needsMeOverflow.filter { lensMatches($0.title, lens) }
            if !overflow.isEmpty {
                Button {
                    attentionOverflowExpanded.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .rotationEffect(attentionOverflowExpanded ? .zero : .degrees(-90))
                            .foregroundStyle(HolyGhosttyTheme.textTertiary)
                        Text("\(overflow.count) more waiting — older or lower rank")
                            .font(.system(size: 10))
                            .foregroundStyle(HolyGhosttyTheme.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if attentionOverflowExpanded {
                    ForEach(overflow, id: \.id) { thread in
                        HolyBriefThreadRowView(
                            thread: thread,
                            density: .compact,
                            isNewSinceLastLook: triaged.deltaThreadIDs.contains(thread.id),
                            onOpen: openAction(for: thread)
                        )
                    }
                }
            }

            let activity = triaged.activity.filter { lensMatches($0.title, lens) }
            if !activity.isEmpty {
                drawerLabel("Since you last looked")
                ForEach(activity, id: \.id) { thread in
                    HolyBriefThreadRowView(
                        thread: thread,
                        density: .compact,
                        isNewSinceLastLook: true,
                        onOpen: openAction(for: thread)
                    )
                }
            }

            ForEach(triaged.suggestionGroups) { group in
                let matching = group.suggestions.filter {
                    lensMatches($0.label + " " + $0.command, lens)
                }
                if !matching.isEmpty {
                    suggestionGroupHeader(group, visible: matching.count)
                    let limit = expandedSuggestionKinds.contains(group.kind)
                        ? matching.count
                        : min(matching.count, Self.suggestionPreviewCount)
                    ForEach(matching.prefix(limit), id: \.id) { suggestion in
                        HolyBriefSuggestionRowView(
                            suggestion: suggestion,
                            workingDirectory: focusedBoardPath
                        )
                    }
                }
            }

            // Alerts are local deliveries needing acknowledgement — genuine
            // attention, rendered from the engine's alert source.
            ForEach(engine.sections.filter { $0.sourceID == "alerts" }) { section in
                sectionHeader(section)
                if isExpanded(section) {
                    ForEach(section.rows.filter { lensMatches($0.title, lens) }) { row in
                        rowView(row, in: section)
                    }
                }
            }
        }
    }

    /// Preview depth for a suggestion group before "show all" expands it:
    /// enough to act on the top of a category without ceding the panel to it.
    private static let suggestionPreviewCount = 3

    private func suggestionGroupHeader(
        _ group: HolyBriefTriage.SuggestionGroup,
        visible: Int
    ) -> some View {
        Button {
            if expandedSuggestionKinds.contains(group.kind) {
                expandedSuggestionKinds.remove(group.kind)
            } else {
                expandedSuggestionKinds.insert(group.kind)
            }
        } label: {
            HStack(spacing: 6) {
                Text(group.title)
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(HolyGhosttyTheme.textSecondary)
                Text("\(visible)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
                Spacer()
                if visible > Self.suggestionPreviewCount {
                    Text(expandedSuggestionKinds.contains(group.kind) ? "less" : "all")
                        .font(.system(size: 9))
                        .foregroundStyle(HolyGhosttyTheme.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }

    private func drawerLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(HolyGhosttyTheme.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 26, alignment: .leading)
            .padding(.top, 6)
    }

    private func openAction(for thread: HolyBriefThread) -> (() -> Void)? {
        guard thread.kind == "session" else { return nil }
        // Thread ids for sessions are coord agent ids ("session-<12 hex>");
        // match against the roster's session UUID prefixes.
        let suffix = thread.id.replacingOccurrences(of: "session-", with: "").lowercased()
        guard let match = store.sessions.first(where: {
            $0.id.uuidString.replacingOccurrences(of: "-", with: "").lowercased().hasPrefix(suffix)
        }) else { return nil }
        return { store.selectSession(match.id) }
    }

    private func lensMatches(_ haystack: String, _ lens: String) -> Bool {
        lens.isEmpty || haystack.lowercased().contains(lens)
    }

    // MARK: Library

    @ViewBuilder
    private var libraryDrawer: some View {
        let librarySections = engine.sections.filter { $0.sourceID != "alerts" }
        Button {
            libraryExpanded.toggle()
            if libraryExpanded {
                // The gh browse refreshes lazily — expanding is the request.
                engine.requestRefresh(sourceID: HolyGitHubInboxSectioner.sourceID)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .rotationEffect(libraryExpanded ? .zero : .degrees(-90))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
                Text("Library")
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(HolyGhosttyTheme.textSecondary)
                Text(libraryCountLabel(sections: librarySections))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 10)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(HolyGhosttyTheme.border)
                .frame(height: 0.5)
                .padding(.horizontal, 12)
        }

        if libraryExpanded {
            let lens = lensText.trimmingCharacters(in: .whitespaces).lowercased()
            ForEach(librarySections) { section in
                sectionHeader(section)
                if isExpanded(section) {
                    ForEach(section.rows.filter { lensMatches($0.title + " " + ($0.subtitle ?? ""), lens) }) { row in
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
    }

    private func libraryCountLabel(sections: [HolyInboxSection]) -> String {
        let rows = sections.reduce(0) { $0 + rowCount(for: $1) }
        let threads = triaged?.libraryThreadCount ?? 0
        return "\(rows + threads)"
    }

    // MARK: Lens

    private var lensField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(HolyGhosttyTheme.textTertiary)
            TextField("Filter — or mn-id, #PR, a question…", text: $lensText)
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
            // PR jumps ride the brief's caller echo when it carries a real
            // slug; a path echo (observed 2026-08-11) makes this a no-op.
            if let repo = brief.payload?.caller?.focusedRepo,
               repo.contains("/"), !repo.hasPrefix("/"),
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

    private func sectionHeader(_ section: HolyInboxSection) -> some View {
        Button {
            expandedOverrides[section.id] = !isExpanded(section)
        } label: {
            HStack(spacing: 6) {
                Text(section.title)
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(HolyGhosttyTheme.textSecondary)

                Text("\(rowCount(for: section))")
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
