import Foundation
import SwiftUI

struct HolySessionRosterView: View {
    @ObservedObject var store: HolyWorkspaceStore
    var compact: Bool = false
    var titlebarInset: CGFloat = 0
    var paneLabelsBySessionID: [UUID: String] = [:]
    var onPresentRemoteHosts: () -> Void = {}
    var onPresentHistory: () -> Void = {}

    private var sections: [HolyRosterSection] {
        let grouped = Dictionary(grouping: store.sessions, by: { $0.displayRuntime })

        return HolySessionRuntime.rosterOrder.compactMap { runtime in
            guard let sessions = grouped[runtime], !sessions.isEmpty else {
                return nil
            }

            return HolyRosterSection(
                runtime: runtime,
                sessions: Self.sortedSessions(sessions)
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            workspaceToolbar

            Rectangle()
                .fill(HolyGhosttyTheme.border)
                .frame(height: 0.5)

            sessionToolbar

            Rectangle()
                .fill(HolyGhosttyTheme.border)
                .frame(height: 0.5)

            if store.sessions.isEmpty {
                HolyGhosttyEmptyStateView(
                    title: "No sessions",
                    subtitle: "Start tmux from the session controls.",
                    symbol: "rectangle.stack.badge.plus"
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 0) {
                                HolyRosterSectionHeader(
                                    runtime: section.runtime,
                                    count: section.sessions.count
                                )

                                ForEach(section.sessions) { session in
                                    HolyRosterRow(
                                        session: session,
                                        primaryTitle: Self.primaryTitle(for: session),
                                        paneLabel: paneLabelsBySessionID[session.id],
                                        coordination: store.coordination(for: session),
                                        attention: store.attentionPresentation(for: session),
                                        isSelected: store.selectedSessionID == session.id,
                                        compact: compact,
                                        onSelect: { store.selectedSessionID = session.id },
                                        onDuplicate: { store.duplicate(session.id) },
                                        canReattach: store.canReattachSession(session),
                                        onReattach: { store.reattach(session) },
                                        onArchive: { store.close(session) },
                                        canKillTmux: store.canKillTmuxSession(session),
                                        onKillTmux: { store.killTmuxSession(session) },
                                        onRename: { store.rename(session, to: $0) }
                                    )
                                }
                            }
                        }

                        Color.clear.frame(height: 16)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .animation(.easeInOut(duration: 0.12), value: store.sessions.map(\.id))
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var workspaceToolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image("HolyGhosttyLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                Text("Holy Ghostty")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(HolyGhosttyTheme.halo)
                    .lineLimit(1)

                Spacer(minLength: 4)

                moreMenu
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8 + titlebarInset)
        .padding(.bottom, 8)
        .background(HolyGhosttyTheme.bgElevated)
    }

    private var moreMenu: some View {
        Menu {
            if !store.builtInTemplates.isEmpty {
                Section("Built-In Templates") {
                    ForEach(store.builtInTemplates, id: \.id) { template in
                        Button(template.name) {
                            store.launchTemplate(template)
                        }
                    }
                }
            }

            if !store.savedTemplates.isEmpty {
                Section("Saved Templates") {
                    ForEach(store.savedTemplates, id: \.id) { template in
                        Button(template.name) {
                            store.launchTemplate(template)
                        }
                    }
                }
            }

            if !store.launchProfiles.isEmpty {
                Section("New From Profile") {
                    ForEach(store.launchProfiles) { profile in
                        Button {
                            store.createSession(using: profile)
                        } label: {
                            Label(profile.name, systemImage: profile.isRemote ? "network" : "laptopcomputer")
                        }
                    }
                }

                Section("Default New Profile") {
                    ForEach(store.launchProfiles) { profile in
                        Button {
                            store.setDefaultLaunchProfile(profile)
                        } label: {
                            Label(
                                profile.name,
                                systemImage: store.defaultLaunchProfileID == profile.id ? "checkmark.circle.fill" : "circle"
                            )
                        }
                    }
                }
            }

            Divider()

            Button {
                onPresentRemoteHosts()
            } label: {
                Label("SSH Hosts", systemImage: "network")
            }

            Button {
                onPresentHistory()
            } label: {
                Label("Session History", systemImage: "clock")
            }

            if let selected = store.selectedSession {
                Divider()

                Button("Duplicate Session") {
                    store.duplicate(selected)
                }

                if store.canReattachSession(selected) {
                    Button("Reattach") {
                        store.reattach(selected)
                    }
                }

                Button("Detach From Roster") {
                    store.close(selected)
                }

                if store.canKillTmuxSession(selected) {
                    Button("Kill from Roster", role: .destructive) {
                        store.killTmuxSession(selected)
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(HolyGhosttyTheme.textSecondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("More")
    }

    private var sessionToolbar: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Label {
                    Text("TMUX Sessions")
                        .font(.system(size: 10, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(0.6)
                } icon: {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(HolyGhosttyTheme.textTertiary)

                Spacer(minLength: 4)

                Text("\(store.sessions.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                rosterActionButton(
                    title: "New",
                    symbol: "rectangle.stack.badge.plus",
                    help: "Start a new tmux-backed shell using \(store.defaultLaunchProfileName)",
                    action: { _ = store.createSessionFromDefaultLaunchProfile() }
                )
                .keyboardShortcut("n", modifiers: [.command])

                rosterActionButton(
                    title: "Clear",
                    symbol: "rectangle.stack.badge.minus",
                    help: "Detach every session from this roster without stopping tmux",
                    action: { store.detachAllSessions() }
                )
                .disabled(store.sessions.isEmpty)

                rosterActionButton(
                    title: "Join",
                    symbol: "arrow.triangle.2.circlepath",
                    help: "Reattach every SSH tmux session in this roster",
                    action: { store.reattachAllSessions() }
                )
                .disabled(!store.hasReattachableSessions)

                rosterActionButton(
                    title: "SSH",
                    symbol: "network",
                    help: "Open SSH and tmux hosts",
                    action: onPresentRemoteHosts
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(HolyGhosttyTheme.bgElevated)
    }

    private func rosterActionButton(
        title: String,
        symbol: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .medium))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(HolyRosterActionButtonStyle())
        .help(help)
    }

    private static func sortedSessions(_ sessions: [HolySession]) -> [HolySession] {
        sessions.sorted { lhs, rhs in
            let lhsKey = sortKey(for: lhs)
            let rhsKey = sortKey(for: rhs)

            for pair in [
                (lhsKey.primary, rhsKey.primary),
                (lhsKey.parent, rhsKey.parent),
                (lhsKey.identity, rhsKey.identity),
                (lhs.displayTitle, rhs.displayTitle)
            ] {
                let comparison = pair.0.localizedStandardCompare(pair.1)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func primaryTitle(for session: HolySession) -> String {
        if let title = session.rosterTitleOverride?.holyRosterTrimmed.nilIfEmpty {
            return title
        }

        if let project = session.displayProjectName?.holyRosterTrimmed.nilIfEmpty {
            return project
        }

        if let folderName = folderName(from: session.workingDirectory) {
            return folderName
        }

        return session.displayTitle
    }

    private static func sortKey(for session: HolySession) -> HolyRosterSortKey {
        let primary = primaryTitle(for: session)
        return HolyRosterSortKey(
            primary: primary,
            parent: parentFolderName(from: session.workingDirectory) ?? "",
            identity: launchIdentity(for: session)
        )
    }

    private static func launchIdentity(for session: HolySession) -> String {
        let launchSpec = session.record.launchSpec
        var parts: [String] = [
            launchSpec.transport.isRemote ? launchSpec.transport.destinationDisplayName : "Local"
        ]

        if let tmux = launchSpec.tmux {
            if let sessionName = tmux.sessionName?.holyRosterTrimmed.nilIfEmpty {
                parts.append(sessionName)
            } else if let serverName = tmux.socketName?.holyRosterTrimmed.nilIfEmpty {
                parts.append(serverName)
            } else {
                parts.append("tmux")
            }
        }

        return parts
            .compactMap(\.holyRosterTrimmed.nilIfEmpty)
            .joined(separator: "/")
    }

    private static func folderName(from directory: String?) -> String? {
        pathComponent(from: directory, parent: false)
    }

    private static func parentFolderName(from directory: String?) -> String? {
        pathComponent(from: directory, parent: true)
    }

    private static func pathComponent(from directory: String?, parent: Bool) -> String? {
        guard let directory = directory?.holyRosterTrimmed.nilIfEmpty else {
            return nil
        }

        let url = URL(fileURLWithPath: directory).standardizedFileURL
        let target = parent ? url.deletingLastPathComponent() : url
        return target.lastPathComponent.holyRosterTrimmed.nilIfEmpty
    }
}

private struct HolyRosterSection: Identifiable {
    let runtime: HolySessionRuntime
    let sessions: [HolySession]

    var id: String { runtime.rawValue }
}

private struct HolyRosterSortKey {
    let primary: String
    let parent: String
    let identity: String
}

private struct HolyRosterActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? HolyGhosttyTheme.textPrimary : HolyGhosttyTheme.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(configuration.isPressed ? HolyGhosttyTheme.bgSurface : HolyGhosttyTheme.bg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(HolyGhosttyTheme.borderActive, lineWidth: 0.5)
            )
    }
}

private struct HolyRosterSectionHeader: View {
    let runtime: HolySessionRuntime
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(runtime.displayName.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(HolyGhosttyTheme.textTertiary)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text("\(count)")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(HolyGhosttyTheme.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.top, 5)
        .padding(.bottom, 1)
    }
}

// MARK: - Roster Row

private struct HolyRosterRow: View {
    @ObservedObject var session: HolySession
    let primaryTitle: String
    let paneLabel: String?
    let coordination: HolySessionCoordination
    let attention: HolySessionAttentionPresentation
    let isSelected: Bool
    var compact: Bool = false
    let onSelect: () -> Void
    let onDuplicate: () -> Void
    let canReattach: Bool
    let onReattach: () -> Void
    let onArchive: () -> Void
    let canKillTmux: Bool
    let onKillTmux: () -> Void
    let onRename: (String) -> Void

    @State private var isRenaming = false
    @State private var renameText = ""

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            HolyAgentStatusOrb(
                state: activityIndicatorState
            )
            .frame(width: 18, height: 18)
            .help(attention.helpText)

            if isRenaming {
                TextField("Session name", text: $renameText, onCommit: commitRename)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
            } else {
                displayLine
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)

            if !compact && !isRenaming {
                Menu {
                    Button("Rename") { startRename() }
                    Button("Duplicate") {
                        onSelect()
                        onDuplicate()
                    }
                    if canReattach {
                        Button("Reattach") {
                            onSelect()
                            onReattach()
                        }
                    }

                    Divider()

                    Button("Detach From Roster") {
                        onSelect()
                        onArchive()
                    }
                    if canKillTmux {
                        Button("Kill from Roster", role: .destructive) {
                            onSelect()
                            onKillTmux()
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(HolyGhosttyTheme.textTertiary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .frame(width: 14, height: 14)
                .opacity(isSelected ? 1 : 0.5)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? HolyGhosttyTheme.bgSurface : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isSelected ? rowOutlineColor.opacity(0.18) : Color.clear, lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onTapGesture(perform: onSelect)
    }

    @ViewBuilder
    private var statusIconRail: some View {
        if hasStatusIcons {
            HStack(spacing: 4) {
                riskIndicator
            }
            .frame(minWidth: 18, alignment: .trailing)
            .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    private var riskIndicator: some View {
        switch riskState {
        case .overlap:
            rosterIcon(
                "exclamationmark.triangle.fill",
                color: HolyGhosttyTheme.warning.opacity(0.75)
            )
        case .sharedWorktree:
            rosterIcon(
                "link",
                color: HolyGhosttyTheme.warning.opacity(0.65)
            )
        case .sharedBranch:
            rosterIcon(
                "arrow.triangle.branch",
                color: HolyGhosttyTheme.warning.opacity(0.65)
            )
        case .drift:
            rosterIcon(
                "arrow.triangle.2.circlepath",
                color: HolyGhosttyTheme.warning.opacity(0.65)
            )
        case .none:
            EmptyView()
        }
    }

    private func rosterIcon(_ systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
    }

    // Runtime grouping owns the agent label; dense rows lead with project context only.
    private var displayLine: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                connectionIndicator

                Text(primaryTitle)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.white : HolyGhosttyTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if let paneLabel {
                Text(paneLabel)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundStyle(HolyGhosttyTheme.halo.opacity(isSelected ? 0.95 : 0.72))
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var connectionIndicator: some View {
        if session.record.launchSpec.transport.isRemote {
            Image(systemName: "network")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(connectionColor)
                .frame(width: 10, height: 10)
                .opacity(isSelected ? 0.9 : 0.62)
                .help(connectionHelpText)
        }
    }

    private var connectionColor: Color {
        session.record.launchSpec.transport.isRemote
            ? HolyGhosttyTheme.halo
            : HolyGhosttyTheme.textTertiary
    }

    private var connectionHelpText: String {
        if session.record.launchSpec.transport.isRemote {
            return "SSH: \(session.record.launchSpec.transport.destinationDisplayName)"
        }

        return "Local: This Mac"
    }

    private func startRename() {
        renameText = session.title
        isRenaming = true
    }

    private func commitRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onRename(trimmed)
        }
        isRenaming = false
    }

    private var activityColor: Color {
        attention.kind.holyColor
    }

    private var rowOutlineColor: Color {
        if activityIndicatorState == .failed {
            return HolyGhosttyTheme.danger
        }

        return activityColor
    }

    private var activityIndicatorState: HolyRosterActivityState {
        switch attention.kind {
        case .working:
            return .working
        case .swarming:
            return .swarming
        case .planningQuestion:
            return .planningQuestion
        case .approvalNeeded:
            return .approvalNeeded
        case .newReply:
            return .newReply
        case .waitingQuiet:
            return .waitingQuiet
        case .overdueReply:
            return .overdueReply
        case .staleReply:
            return .staleReply
        case .stalled:
            return .stalled
        case .failed:
            return .failed
        case .done:
            return .done
        case .conflict:
            return .conflict
        case .quiet:
            return .idle
        }
    }

    private var riskState: HolyRosterRiskState {
        if !coordination.overlappingFiles.isEmpty {
            return .overlap
        }

        if !coordination.sharedWorktreeSessionIDs.isEmpty {
            return .sharedWorktree
        }

        if coordination.hasSharedBranch {
            return .sharedBranch
        }

        if session.hasBranchOwnershipDrift {
            return .drift
        }

        return .none
    }

    private var hasStatusIcons: Bool {
        riskState != .none
    }

    private var phaseColor: Color {
        switch session.phase {
        case .active:    return HolyGhosttyTheme.textTertiary
        case .working:   return HolyAgentPalette.workingBlue
        case .waitingInput: return attention.kind.holyColor
        case .completed: return HolyAgentPalette.done
        case .failed:    return HolyGhosttyTheme.danger
        }
    }
}

private enum HolyRosterActivityState {
    case idle
    case working
    case swarming
    case planningQuestion
    case approvalNeeded
    case newReply
    case waitingQuiet
    case overdueReply
    case staleReply
    case done
    case stalled
    case failed
    case conflict
}

private enum HolyRosterRiskState {
    case none
    case sharedWorktree
    case sharedBranch
    case drift
    case overlap
}

enum HolyAgentPalette {
    static let workingBlue = Color(red: 0.25, green: 0.72, blue: 1.0)
    static let workingViolet = Color(red: 0.68, green: 0.44, blue: 1.0)
    static let workingMint = Color(red: 0.25, green: 0.92, blue: 0.70)
    static let workingGold = Color(red: 1.0, green: 0.78, blue: 0.30)
    static let swarmCyan = Color(red: 0.18, green: 0.88, blue: 1.0)
    static let swarmPink = Color(red: 1.0, green: 0.35, blue: 0.78)
    static let swarmGold = Color(red: 1.0, green: 0.84, blue: 0.28)
    static let done = Color(red: 0.42, green: 0.47, blue: 0.52)
    static let stalled = Color(red: 1.0, green: 0.47, blue: 0.22)
    static let waitingReply = Color(red: 0.30, green: 0.76, blue: 1.0)
    static let approvalNeeded = Color(red: 1.0, green: 0.58, blue: 0.22)
    static let freshWait = Color(red: 0.12, green: 0.86, blue: 1.0)
    static let planningQuestion = Color(red: 1.0, green: 0.78, blue: 0.30)
    static let warmWait = Color(red: 0.43, green: 0.82, blue: 0.52)
    static let agingWait = Color(red: 0.98, green: 0.70, blue: 0.24)
    static let oldWait = Color(red: 0.98, green: 0.43, blue: 0.22)
    static let staleWait = Color(red: 1.0, green: 0.24, blue: 0.56)
}

extension HolySessionAttentionKind {
    var holyColor: Color {
        switch self {
        case .quiet, .waitingQuiet:
            return HolyGhosttyTheme.textTertiary
        case .working:
            return HolyAgentPalette.workingBlue
        case .swarming:
            return HolyAgentPalette.swarmGold
        case .newReply:
            return HolyAgentPalette.waitingReply
        case .overdueReply:
            return HolyAgentPalette.agingWait
        case .staleReply:
            return HolyAgentPalette.oldWait
        case .planningQuestion:
            return HolyAgentPalette.planningQuestion
        case .approvalNeeded:
            return HolyAgentPalette.approvalNeeded
        case .stalled:
            return HolyAgentPalette.stalled
        case .failed, .conflict:
            return HolyGhosttyTheme.danger
        case .done:
            return HolyAgentPalette.done
        }
    }
}

enum HolyWaitingFreshness {
    case justFinished
    case fresh
    case waiting
    case aging
    case stale

    init(age: TimeInterval) {
        switch age {
        case ..<300:
            self = .justFinished
        case ..<1_800:
            self = .fresh
        case ..<7_200:
            self = .waiting
        case ..<86_400:
            self = .aging
        default:
            self = .stale
        }
    }

    var color: Color {
        switch self {
        case .justFinished: return HolyAgentPalette.freshWait
        case .fresh:        return HolyAgentPalette.warmWait
        case .waiting:      return HolyAgentPalette.agingWait
        case .aging:        return HolyAgentPalette.oldWait
        case .stale:        return HolyAgentPalette.staleWait
        }
    }

    var label: String {
        switch self {
        case .justFinished: return "Just finished"
        case .fresh:        return "Fresh handoff"
        case .waiting:      return "Waiting on you"
        case .aging:        return "Aging handoff"
        case .stale:        return "Stale handoff"
        }
    }
}

private struct HolyAgentStatusOrb: View {
    let state: HolyRosterActivityState

    var body: some View {
        switch state {
        case .working:
            HolyAgentWorkingSpinner(size: 13, lineWidth: 2)
                .frame(width: 13, height: 13)
        case .swarming:
            HolyAgentSwarmSpinner(size: 16)
                .frame(width: 16, height: 16)
        case .planningQuestion:
            HolyAgentPlanningQuestionOrb()
                .frame(width: 15, height: 15)
        case .approvalNeeded:
            HolyAgentSymbolOrb(systemName: "hand.raised.fill", color: HolyAgentPalette.approvalNeeded)
        case .newReply:
            HolyAgentWaitingOrb()
                .frame(width: 15, height: 15)
        case .waitingQuiet:
            HolyAgentStaticOrb(color: HolyGhosttyTheme.textTertiary, symbol: nil, opacity: 0.40)
        case .overdueReply:
            HolyAgentSymbolOrb(systemName: "clock", color: HolyAgentPalette.agingWait)
        case .staleReply:
            HolyAgentSymbolOrb(systemName: "clock.fill", color: HolyAgentPalette.oldWait)
        case .stalled:
            HolyAgentSymbolOrb(systemName: "hourglass", color: HolyAgentPalette.stalled)
        case .failed:
            HolyAgentSymbolOrb(systemName: "xmark.octagon.fill", color: HolyGhosttyTheme.danger)
        case .conflict:
            HolyAgentSymbolOrb(systemName: "exclamationmark.triangle.fill", color: HolyGhosttyTheme.danger)
        case .done:
            HolyAgentSymbolOrb(systemName: "checkmark.circle.fill", color: HolyAgentPalette.done)
        case .idle:
            HolyAgentStaticOrb(color: HolyGhosttyTheme.textTertiary, symbol: nil, opacity: 0.55)
        }
    }
}

private struct HolyAgentPlanningQuestionOrb: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(HolyAgentPalette.planningQuestion.opacity(0.18))
                .frame(width: 14, height: 14)

            Image(systemName: "questionmark.bubble.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(HolyAgentPalette.planningQuestion)
        }
    }
}

private struct HolyAgentSwarmSpinner: View {
    let size: CGFloat

    var body: some View {
        TimelineView(.animation) { context in
            let cycle = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1.35) / 1.35
            let colors = [
                HolyAgentPalette.swarmCyan,
                HolyAgentPalette.swarmPink,
                HolyAgentPalette.swarmGold,
            ]

            ZStack {
                Circle()
                    .stroke(HolyAgentPalette.swarmGold.opacity(0.18), lineWidth: 1.2)
                    .frame(width: size - 2, height: size - 2)

                ForEach(0..<3, id: \.self) { index in
                    let radians = (cycle * 2 * Double.pi) + (Double(index) * 2 * Double.pi / 3)
                    Circle()
                        .fill(colors[index])
                        .frame(width: 3.5, height: 3.5)
                        .shadow(color: colors[index].opacity(0.65), radius: 2.5)
                        .offset(
                            x: CGFloat(cos(radians)) * (size * 0.36),
                            y: CGFloat(sin(radians)) * (size * 0.36)
                        )
                }

                Image(systemName: "sparkles")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(HolyAgentPalette.swarmGold)
            }
            .frame(width: size, height: size)
        }
    }
}

private struct HolyAgentWorkingSpinner: View {
    let size: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        TimelineView(.animation) { context in
            let cycle = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1.15) / 1.15

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.10), lineWidth: lineWidth)

                Circle()
                    .trim(from: 0.08, to: 0.82)
                    .stroke(
                        AngularGradient(
                            colors: [
                                HolyAgentPalette.workingBlue,
                                HolyAgentPalette.workingViolet,
                                HolyAgentPalette.workingMint,
                                HolyAgentPalette.workingGold,
                                HolyAgentPalette.workingBlue
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(cycle * 360))

                Circle()
                    .fill(HolyAgentPalette.workingBlue.opacity(0.30))
                    .frame(width: max(3, size * 0.28), height: max(3, size * 0.28))
            }
            .frame(width: size, height: size)
        }
    }
}

private struct HolyAgentWaitingOrb: View {
    var body: some View {
        HolyAgentSymbolOrb(systemName: "arrowshape.turn.up.left.fill", color: HolyAgentPalette.waitingReply)
    }
}

private struct HolyAgentSymbolOrb: View {
    let systemName: String
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.18))
                .frame(width: 14, height: 14)

            Image(systemName: systemName)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 14, height: 14)
        }
    }
}

private struct HolyAgentStaticOrb: View {
    let color: Color
    let symbol: String?
    var opacity: Double = 1

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.18 * opacity))
                .frame(width: 13, height: 13)

            Circle()
                .fill(color.opacity(opacity))
                .frame(width: 7, height: 7)

            if let symbol {
                Text(symbol)
                    .font(.system(size: 6, weight: .bold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.70))
            }
        }
    }
}

private extension HolySessionRuntime {
    static let rosterOrder: [HolySessionRuntime] = [.claude, .codex, .opencode, .shell]
}

private extension String {
    var holyRosterTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
