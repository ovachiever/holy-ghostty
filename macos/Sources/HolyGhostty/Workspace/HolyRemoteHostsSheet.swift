import SwiftUI

struct HolyRemoteHostsSheet: View {
    @ObservedObject var store: HolyWorkspaceStore
    @State private var selectedConnection: HolyConnectionSelection = .local
    @State private var editorHost: HolyRemoteHostRecord?

    var body: some View {
        ZStack {
            HolyGhosttyBackdrop()

            VStack(spacing: 0) {
                header

                Rectangle()
                    .fill(HolyGhosttyTheme.border)
                    .frame(height: 0.5)

                HSplitView {
                    connectionList
                        .frame(minWidth: 270, idealWidth: 310, maxWidth: 360, maxHeight: .infinity)
                        .background(HolyGhosttyTheme.bgElevated)

                    connectionDetail
                        .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
                        .layoutPriority(1)
                }
            }
        }
        .frame(minWidth: 1040, minHeight: 700)
        .onAppear {
            ensureSelection()
            reloadEditor()
            store.refreshConnectionOverview()
        }
        .onChange(of: selectedConnection) { _ in
            reloadEditor()
            refreshIfNeeded()
        }
        .onChange(of: store.remoteHosts.map(\.id)) { _ in
            ensureSelection()
            reloadEditor()
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Connections")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(HolyGhosttyTheme.halo)

                Text(connectionCountText)
                    .font(.system(size: 11))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)

                Spacer()

                Button("Refresh All") { store.refreshConnectionOverview() }
                    .buttonStyle(HolyGhosttyActionButtonStyle())

                Menu("Import") {
                    Button("SSH Config") { store.importRemoteHostsFromSSHConfig() }
                    Button("Tailscale Macs") { store.importRemoteHostsFromTailscale() }
                }
                .buttonStyle(HolyGhosttyActionButtonStyle())

                Button("Add SSH") { addRemoteHost() }
                    .buttonStyle(HolyGhosttyActionButtonStyle())

                Button("Done") { store.remoteHostsPresented = false }
                    .buttonStyle(HolyGhosttyActionButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, store.remoteHostImportMessage == nil ? 10 : 8)

            if let remoteHostImportMessage = store.remoteHostImportMessage {
                HStack {
                    Text(remoteHostImportMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(HolyGhosttyTheme.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        }
        .background(HolyGhosttyTheme.bgElevated)
    }

    private var connectionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                connectionGroupLabel("This Mac")

                HolyConnectionRow(
                    title: store.localMachineDisplayName,
                    subtitle: "Local tmux on this Mac",
                    symbolName: "laptopcomputer",
                    isSelected: selectedConnection == .local,
                    isBusy: store.localTmuxDiscoveryBusy,
                    sessionCount: store.discoveredLocalTmuxSessions.count,
                    statusText: localConnectionStatusText,
                    statusColor: localConnectionStatusColor,
                    onSelect: { selectedConnection = .local }
                )

                connectionGroupLabel("Remote")
                    .padding(.top, 6)

                if store.remoteHosts.isEmpty {
                    Text("Add Studio or import SSH hosts. Local devices and phones are filtered out.")
                        .font(.system(size: 11))
                        .foregroundStyle(HolyGhosttyTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(HolyGhosttyTheme.bgSurface.opacity(0.55))
                        )
                } else {
                    ForEach(store.remoteHosts) { host in
                        HolyConnectionRow(
                            title: host.displayTitle,
                            subtitle: host.subtitle,
                            symbolName: "desktopcomputer",
                            isSelected: selectedConnection == .remote(host.id),
                            isBusy: store.isRemoteDiscoveryBusy(for: host),
                            sessionCount: primaryRemoteSessions(for: host).count,
                            statusText: remoteConnectionStatusText(for: host),
                            statusColor: remoteConnectionStatusColor(for: host),
                            onSelect: { selectRemoteHost(host) }
                        )
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
    }

    private var connectionDetail: some View {
        Group {
            switch selectedConnection {
            case .local:
                localDetail
            case .remote:
                if let selectedRemoteHost {
                    remoteDetail(for: selectedRemoteHost)
                } else {
                    localDetail
                }
            }
        }
    }

    private var localDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                titleBlock(
                    title: store.localMachineDisplayName,
                    subtitle: "This Mac"
                )

                localActionBar
                localStatusSection
                localSessionsSection
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
    }

    private func remoteDetail(for host: HolyRemoteHostRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                titleBlock(
                    title: host.displayTitle,
                    subtitle: host.subtitle
                )

                remoteActionBar(for: host)
                remoteStatusSection(for: host)
                editorSection
                remoteSessionsSection(for: host)
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
    }

    private func titleBlock(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(HolyGhosttyTheme.textPrimary)

            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(HolyGhosttyTheme.textSecondary)
        }
    }

    private var localActionBar: some View {
        HStack(spacing: 6) {
            Button("Refresh") { store.refreshLocalTmuxSessions() }
                .buttonStyle(HolyGhosttyActionButtonStyle())

            if !store.discoveredLocalTmuxSessions.isEmpty {
                Button("Attach All") {
                    store.launchLocalTmuxSessions(store.discoveredLocalTmuxSessions)
                }
                .buttonStyle(HolyGhosttyActionButtonStyle())
            }

            Spacer()
        }
    }

    private func remoteActionBar(for host: HolyRemoteHostRecord) -> some View {
        let discoveredSessions = store.remoteSessions(for: host)

        return HStack(spacing: 6) {
            Button("Save", action: saveEditor)
                .buttonStyle(HolyGhosttyActionButtonStyle())

            Button("Refresh") { store.refreshRemoteSessions(for: host) }
                .buttonStyle(HolyGhosttyActionButtonStyle())

            if !discoveredSessions.isEmpty {
                Button("Attach All") {
                    store.launchRemoteTmuxSessions(discoveredSessions, on: host)
                }
                .buttonStyle(HolyGhosttyActionButtonStyle())
            }

            Button("Delete") { store.deleteRemoteHost(host) }
                .buttonStyle(HolyGhosttyActionButtonStyle())

            Spacer()
        }
    }

    private var localStatusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Connection")
            detailRow("Type", "Local")
            detailRow("Address", "This Mac")
            detailRow("Probe", "Default tmux + holy")
            detailRow("Discovery", localDiscoverySummary, color: localConnectionStatusColor)
        }
    }

    private func remoteStatusSection(for host: HolyRemoteHostRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Connection")
            detailRow("Type", "SSH")
            detailRow("Address", host.subtitle)
            detailRow("Probe", host.tmuxSummary)
            detailRow("Last Checked", host.lastDiscoveredAt.map(Self.timestampString(from:)) ?? "Never")
            detailRow("Discovery", discoverySummary(for: host), color: remoteConnectionStatusColor(for: host))
        }
    }

    private var editorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Remote SSH")

            labeledField("Name", text: editorBinding(\.label), placeholder: "Studio")
            labeledField("SSH Destination", text: editorBinding(\.sshDestination), placeholder: "studio")

            DisclosureGroup("Advanced") {
                VStack(alignment: .leading, spacing: 8) {
                    labeledField("Tmux Socket Override", text: editorOptionalBinding(\.tmuxSocketName), placeholder: "holy")

                    Text("Leave this blank for automatic discovery. Holy checks both the default tmux server and the holy socket.")
                        .font(.system(size: 11))
                        .foregroundStyle(HolyGhosttyTheme.textTertiary)
                }
                .padding(.top, 4)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(HolyGhosttyTheme.textSecondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(HolyGhosttyTheme.bgElevated)
        )
    }

    private var localSessionsSection: some View {
        sessionListSection(
            title: "Tmux Sessions",
            sessions: store.discoveredLocalTmuxSessions,
            isBusy: store.localTmuxDiscoveryBusy,
            error: store.localTmuxDiscoveryError,
            emptyTitle: "No local tmux sessions",
            emptySubtitle: "No sessions were found on the default tmux server or the holy socket.",
            onLaunch: store.launchLocalTmuxSession(_:)
        )
    }

    private func remoteSessionsSection(for host: HolyRemoteHostRecord) -> some View {
        sessionListSection(
            title: "Tmux Sessions",
            sessions: store.remoteSessions(for: host),
            isBusy: store.isRemoteDiscoveryBusy(for: host),
            error: store.remoteDiscoveryError(for: host),
            emptyTitle: "No tmux sessions found",
            emptySubtitle: emptyDiscoverySubtitle(for: host),
            onLaunch: { store.launchRemoteTmuxSession($0, on: host) }
        )
    }

    private func sessionListSection(
        title: String,
        sessions: [HolyDiscoveredTmuxSession],
        isBusy: Bool,
        error: String?,
        emptyTitle: String,
        emptySubtitle: String,
        onLaunch: @escaping (HolyDiscoveredTmuxSession) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(title)

            if isBusy && sessions.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .tint(HolyGhosttyTheme.halo)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else if let error {
                HolyGhosttyEmptyStateView(
                    title: "Can’t inspect tmux",
                    subtitle: error,
                    symbol: "exclamationmark.triangle"
                )
                .frame(maxWidth: .infinity)
            } else if sessions.isEmpty {
                HolyGhosttyEmptyStateView(
                    title: emptyTitle,
                    subtitle: emptySubtitle,
                    symbol: "rectangle.stack"
                )
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 8) {
                    ForEach(sessions) { session in
                        HolyDiscoveredTmuxSessionRow(
                            session: session,
                            onLaunch: { onLaunch(session) }
                        )
                    }
                }
            }
        }
    }

    private func labeledField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(HolyGhosttyTheme.textTertiary)

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(HolyGhosttyTheme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(HolyGhosttyTheme.bgSurface)
                )
        }
    }

    private func editorBinding(_ keyPath: WritableKeyPath<HolyRemoteHostRecord, String>) -> Binding<String> {
        Binding(
            get: { editorHost?[keyPath: keyPath] ?? "" },
            set: { value in
                guard var editorHost else { return }
                editorHost[keyPath: keyPath] = value
                self.editorHost = editorHost
            }
        )
    }

    private func editorOptionalBinding(_ keyPath: WritableKeyPath<HolyRemoteHostRecord, String?>) -> Binding<String> {
        Binding(
            get: { editorHost?[keyPath: keyPath] ?? "" },
            set: { value in
                guard var editorHost else { return }
                editorHost[keyPath: keyPath] = value.nilIfBlank
                self.editorHost = editorHost
            }
        )
    }

    private func connectionGroupLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(HolyGhosttyTheme.textTertiary)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, 6)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(HolyGhosttyTheme.halo.opacity(0.75))
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private func detailRow(_ key: String, _ value: String, color: Color = HolyGhosttyTheme.textPrimary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(key)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(HolyGhosttyTheme.textTertiary)
                .frame(width: 92, alignment: .leading)

            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func ensureSelection() {
        if case let .remote(id) = selectedConnection,
           !store.remoteHosts.contains(where: { $0.id == id }) {
            selectedConnection = .local
        }
    }

    private func reloadEditor() {
        editorHost = selectedRemoteHost
    }

    private func refreshIfNeeded() {
        switch selectedConnection {
        case .local:
            if store.discoveredLocalTmuxSessions.isEmpty && !store.localTmuxDiscoveryBusy {
                store.refreshLocalTmuxSessions()
            }
        case .remote:
            guard let selectedRemoteHost,
                  store.remoteSessions(for: selectedRemoteHost).isEmpty,
                  !store.isRemoteDiscoveryBusy(for: selectedRemoteHost) else {
                return
            }

            store.refreshRemoteSessions(for: selectedRemoteHost)
        }
    }

    private func addRemoteHost() {
        store.createRemoteHost()
        if let selectedRemoteHostID = store.selectedRemoteHostID {
            selectedConnection = .remote(selectedRemoteHostID)
        }
        reloadEditor()
    }

    private func selectRemoteHost(_ host: HolyRemoteHostRecord) {
        store.selectedRemoteHostID = host.id
        selectedConnection = .remote(host.id)
    }

    private func saveEditor() {
        guard let editorHost else { return }
        store.upsertRemoteHost(editorHost)
        selectedConnection = .remote(editorHost.id)
        reloadEditor()
    }

    private var selectedRemoteHost: HolyRemoteHostRecord? {
        guard case let .remote(id) = selectedConnection else { return nil }
        return store.remoteHosts.first(where: { $0.id == id })
    }

    private var connectionCountText: String {
        let count = store.remoteHosts.count + 1
        return count == 1 ? "1 connection" : "\(count) connections"
    }

    private var localConnectionStatusText: String {
        if let localTmuxDiscoveryError = store.localTmuxDiscoveryError?.nilIfBlank {
            return localTmuxDiscoveryError
        }

        return "Default tmux + holy"
    }

    private var localConnectionStatusColor: Color {
        store.localTmuxDiscoveryError == nil ? HolyGhosttyTheme.textTertiary : HolyGhosttyTheme.danger
    }

    private var localDiscoverySummary: String {
        if let error = store.localTmuxDiscoveryError?.nilIfBlank {
            return error
        }

        if store.localTmuxDiscoveryBusy {
            return "Refreshing…"
        }

        let sessions = store.discoveredLocalTmuxSessions
        return sessions.count == 1 ? "1 tmux session discovered" : "\(sessions.count) tmux sessions discovered"
    }

    private func remoteConnectionStatusText(for host: HolyRemoteHostRecord) -> String {
        if let discoveryError = store.remoteDiscoveryError(for: host)?.nilIfBlank {
            return discoveryError
        }

        let sessions = store.remoteSessions(for: host)
        guard !sessions.isEmpty else { return host.tmuxSummary }

        let primaryCount = primaryRemoteSessions(for: host).count
        if primaryCount == sessions.count {
            return sessions.count == 1 ? "1 live tmux session" : "\(sessions.count) live tmux sessions"
        }

        return "\(primaryCount) active · \(sessions.count) total"
    }

    private func remoteConnectionStatusColor(for host: HolyRemoteHostRecord) -> Color {
        store.remoteDiscoveryError(for: host) == nil ? HolyGhosttyTheme.textTertiary : HolyGhosttyTheme.danger
    }

    private func discoverySummary(for host: HolyRemoteHostRecord) -> String {
        if let error = store.remoteDiscoveryError(for: host)?.nilIfBlank {
            return error
        }

        if store.isRemoteDiscoveryBusy(for: host) {
            return "Refreshing…"
        }

        let sessions = store.remoteSessions(for: host)
        if sessions.isEmpty {
            return emptyDiscoverySubtitle(for: host)
        }

        let primaryCount = primaryRemoteSessions(for: host).count
        if primaryCount != sessions.count {
            return "\(primaryCount) active/attached, \(sessions.count) total tmux sessions discovered"
        }

        return sessions.count == 1 ? "1 tmux session discovered" : "\(sessions.count) tmux sessions discovered"
    }

    private func primaryRemoteSessions(for host: HolyRemoteHostRecord) -> [HolyDiscoveredTmuxSession] {
        let sessions = store.remoteSessions(for: host)
        let primarySessions = sessions.filter { session in
            session.attachedClientCount > 0 || session.isHolyManaged
        }

        return primarySessions.isEmpty ? sessions : primarySessions
    }

    private func emptyDiscoverySubtitle(for host: HolyRemoteHostRecord) -> String {
        let explicitSocketName = host.tmuxSocketName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank

        if explicitSocketName == nil {
            return "No sessions were found on the default tmux server or the holy socket."
        }

        return "No sessions were found on \(host.tmuxSummary.lowercased())."
    }

    private static func timestampString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private enum HolyConnectionSelection: Equatable {
    case local
    case remote(UUID)
}

private struct HolyConnectionRow: View {
    let title: String
    let subtitle: String
    let symbolName: String
    let isSelected: Bool
    let isBusy: Bool
    let sessionCount: Int
    let statusText: String
    let statusColor: Color
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: symbolName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? HolyGhosttyTheme.halo : HolyGhosttyTheme.textTertiary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HolyGhosttyTheme.textPrimary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(HolyGhosttyTheme.textSecondary)
                        .lineLimit(1)

                    Text(statusText)
                        .font(.system(size: 10))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(HolyGhosttyTheme.halo)
                } else {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(sessionCount)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(HolyGhosttyTheme.textPrimary)

                        Text(sessionCount == 1 ? "session" : "sessions")
                            .font(.system(size: 9))
                            .foregroundStyle(HolyGhosttyTheme.textTertiary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(background)
        }
        .buttonStyle(.plain)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(isSelected ? HolyGhosttyTheme.bgSurface : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(isSelected ? HolyGhosttyTheme.halo.opacity(0.36) : HolyGhosttyTheme.border.opacity(0.7), lineWidth: 0.8)
            )
    }
}

private struct HolyDiscoveredTmuxSessionRow: View {
    let session: HolyDiscoveredTmuxSession
    let onLaunch: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(session.displayTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HolyGhosttyTheme.textPrimary)
                        .lineLimit(1)

                    if session.isHolyManaged {
                        Text("Holy")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(HolyGhosttyTheme.halo)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(HolyGhosttyTheme.halo.opacity(0.14))
                            )
                    }
                }

                Text(session.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(HolyGhosttyTheme.textSecondary)
                    .lineLimit(2)

                Text(session.statusSummary)
                    .font(.system(size: 10))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
                    .lineLimit(1)

                Text(session.tmuxServerSummary)
                    .font(.system(size: 10))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
                    .lineLimit(1)

                if let gitSummary = session.gitSummary {
                    Text("\(gitSummary.repositoryName) · \(gitSummary.branchDisplayName) · \(gitSummary.syncStatusText)")
                        .font(.system(size: 10))
                        .foregroundStyle(HolyGhosttyTheme.textTertiary)
                        .lineLimit(1)
                }

                if let taskTitle = session.taskTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !taskTitle.isEmpty {
                    Text("Task: \(taskTitle)")
                        .font(.system(size: 10))
                        .foregroundStyle(HolyGhosttyTheme.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Button("Attach", action: onLaunch)
                .buttonStyle(HolyGhosttyActionButtonStyle())
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(HolyGhosttyTheme.bgElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(HolyGhosttyTheme.border, lineWidth: 0.8)
                )
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
