import SwiftUI

struct HolyRemoteHostsSheet: View {
    @ObservedObject var store: HolyWorkspaceStore
    @State private var selectedConnection: HolyConnectionSelection = .local
    @State private var editorHost: HolyRemoteHostRecord?
    @State private var selectedDiscoveredSessionIDs: Set<String> = []
    @State private var killConfirmation: HolyDiscoveredKillRequest?

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
            selectedDiscoveredSessionIDs.removeAll()
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
                    sessionCount: localConnectionSessions.count,
                    statusText: localConnectionStatusText,
                    statusColor: localConnectionStatusColor,
                    onSelect: { selectedConnection = .local }
                )

                connectionGroupLabel("Remote")
                    .padding(.top, 6)

                if store.remoteHosts.isEmpty {
                    Text("Add or import SSH hosts. Local devices and phones are filtered out.")
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
                    ForEach(sortedRemoteHosts) { host in
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
            VStack(alignment: .leading, spacing: 12) {
                connectionHero(.init(
                    title: store.localMachineDisplayName,
                    subtitle: "Local tmux on this Mac",
                    symbolName: "laptopcomputer",
                    status: localDiscoverySummary,
                    statusColor: localConnectionStatusColor,
                    sessionCount: localConnectionSessions.count,
                    isBusy: store.localTmuxDiscoveryBusy
                )) {
                    localActionBar
                }
                localSessionsSection
            }
            .padding(14)
        }
        .scrollIndicators(.hidden)
    }

    private func remoteDetail(for host: HolyRemoteHostRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                connectionHero(.init(
                    title: host.displayTitle,
                    subtitle: host.subtitle,
                    symbolName: "desktopcomputer",
                    status: discoverySummary(for: host),
                    statusColor: remoteConnectionStatusColor(for: host),
                    sessionCount: sortedConnectionSessions(store.remoteSessions(for: host)).count,
                    isBusy: store.isRemoteDiscoveryBusy(for: host)
                )) {
                    remoteActionBar(for: host)
                }
                editorSection
                remoteSessionsSection(for: host)
            }
            .padding(14)
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

            if !localConnectionSessions.isEmpty {
                Button("Attach All") {
                    store.launchLocalTmuxSessions(localConnectionSessions, keepHostsOpen: true)
                }
                .buttonStyle(HolyGhosttyActionButtonStyle())
            }
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
                    store.launchRemoteTmuxSessions(discoveredSessions, on: host, keepHostsOpen: true)
                }
                .buttonStyle(HolyGhosttyActionButtonStyle())
            }

            Button("Delete") { store.deleteRemoteHost(host) }
                .buttonStyle(HolyGhosttyActionButtonStyle())
        }
    }

    private func connectionHero<Actions: View>(
        _ content: HolyConnectionHeroContent,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: content.symbolName)
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(HolyGhosttyTheme.halo.opacity(0.86))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(content.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(HolyGhosttyTheme.textPrimary)
                        .lineLimit(1)

                    Text(content.sessionCount == 1 ? "1 session" : "\(content.sessionCount) sessions")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(HolyGhosttyTheme.textTertiary)
                        .lineLimit(1)
                }

                Text(content.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(HolyGhosttyTheme.textSecondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if content.isBusy {
                        ProgressView()
                            .controlSize(.small)
                            .tint(HolyGhosttyTheme.halo)
                    }

                    Text(content.status)
                        .font(.system(size: 10))
                        .foregroundStyle(content.statusColor)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            actions()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(HolyGhosttyTheme.bgElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(HolyGhosttyTheme.borderActive, lineWidth: 0.6)
                )
        )
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

            labeledField("Name", text: editorBinding(\.label), placeholder: "Workstation")
            labeledField("SSH Destination", text: editorBinding(\.sshDestination), placeholder: "workstation")

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
            .init(
                title: "Tmux Sessions",
                sessions: localConnectionSessions,
                isBusy: store.localTmuxDiscoveryBusy,
                error: store.localTmuxDiscoveryError,
                emptyTitle: "No local tmux sessions",
                emptySubtitle: "No sessions were found on the default tmux server or the holy socket."
            ),
            onAttach: { store.launchLocalTmuxSession($0, keepHostsOpen: true) },
            onAttachMany: { store.launchLocalTmuxSessions($0, keepHostsOpen: true) },
            onKill: { store.killDiscoveredLocalTmuxSession($0) }
        )
    }

    private func remoteSessionsSection(for host: HolyRemoteHostRecord) -> some View {
        sessionListSection(
            .init(
                title: "Tmux Sessions",
                sessions: sortedConnectionSessions(store.remoteSessions(for: host)),
                isBusy: store.isRemoteDiscoveryBusy(for: host),
                error: store.remoteDiscoveryError(for: host),
                emptyTitle: "No tmux sessions found",
                emptySubtitle: emptyDiscoverySubtitle(for: host)
            ),
            onAttach: { store.launchRemoteTmuxSession($0, on: host, keepHostsOpen: true) },
            onAttachMany: { store.launchRemoteTmuxSessions($0, on: host, keepHostsOpen: true) },
            onKill: { store.killDiscoveredRemoteTmuxSession($0, on: host) }
        )
    }

    private func sessionListSection(
        _ content: HolyConnectionSessionListContent,
        onAttach: @escaping (HolyDiscoveredTmuxSession) -> Void,
        onAttachMany: @escaping ([HolyDiscoveredTmuxSession]) -> Void,
        onKill: @escaping (HolyDiscoveredTmuxSession) -> Void
    ) -> some View {
        let visibleIDs = Set(content.sessions.map(\.id))
        let selectedSessions = content.sessions.filter { selectedDiscoveredSessionIDs.contains($0.id) }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                sectionLabel(content.title)

                Text(content.sessions.count == 1 ? "1 visible" : "\(content.sessions.count) visible")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)

                Spacer()

                if !content.sessions.isEmpty {
                    Button(allVisibleSelected(in: visibleIDs) ? "Clear" : "Select All") {
                        toggleSelectAll(visibleIDs: visibleIDs)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(HolyGhosttyTheme.halo)
                }
            }

            if content.isBusy && content.sessions.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .tint(HolyGhosttyTheme.halo)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else if let error = content.error {
                HolyGhosttyEmptyStateView(
                    title: "Can’t inspect tmux",
                    subtitle: error,
                    symbol: "exclamationmark.triangle"
                )
                .frame(maxWidth: .infinity)
            } else if content.sessions.isEmpty {
                HolyGhosttyEmptyStateView(
                    title: content.emptyTitle,
                    subtitle: content.emptySubtitle,
                    symbol: "rectangle.stack"
                )
                .frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(groupedConnectionSessions(content.sessions)) { group in
                        VStack(alignment: .leading, spacing: 0) {
                            sessionGroupLabel(group.runtime, count: group.sessions.count)

                            VStack(spacing: 0) {
                                ForEach(group.sessions) { session in
                                    HolyDiscoveredTmuxSessionRow(
                                        session: session,
                                        isSelected: selectedDiscoveredSessionIDs.contains(session.id),
                                        onToggleSelected: { toggleSelection(for: session) },
                                        onLaunch: { onAttach(session) },
                                        onKill: { requestKill(of: session, onKill: onKill) }
                                    )
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(HolyGhosttyTheme.border, lineWidth: 0.6)
                            )
                        }
                    }
                }

                if !selectedSessions.isEmpty {
                    bulkActionBar(
                        for: selectedSessions,
                        onAttachMany: onAttachMany,
                        onKill: onKill
                    )
                }
            }
        }
        .onChange(of: visibleIDs) { ids in
            // Drop selections for sessions that are no longer discovered (e.g. after refresh).
            selectedDiscoveredSessionIDs.formIntersection(ids)
        }
        .confirmationDialog(
            killConfirmation?.confirmationTitle ?? "",
            isPresented: Binding(
                get: { killConfirmation != nil },
                set: { if !$0 { killConfirmation = nil } }
            ),
            titleVisibility: .visible,
            presenting: killConfirmation
        ) { request in
            Button("Kill \(request.countLabel)", role: .destructive) {
                request.perform()
                selectedDiscoveredSessionIDs.subtract(request.sessionIDs)
                killConfirmation = nil
            }
            Button("Cancel", role: .cancel) { killConfirmation = nil }
        } message: { request in
            Text(request.confirmationMessage)
        }
    }

    private func bulkActionBar(
        for selectedSessions: [HolyDiscoveredTmuxSession],
        onAttachMany: @escaping ([HolyDiscoveredTmuxSession]) -> Void,
        onKill: @escaping (HolyDiscoveredTmuxSession) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text("\(selectedSessions.count) selected")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(HolyGhosttyTheme.textPrimary)

            Spacer()

            Button("Attach Selected") {
                onAttachMany(selectedSessions)
                selectedDiscoveredSessionIDs.subtract(selectedSessions.map(\.id))
            }
            .buttonStyle(HolyGhosttyActionButtonStyle())

            Button("Kill Selected") {
                requestKill(of: selectedSessions, onKill: onKill)
            }
            .buttonStyle(HolyGhosttyActionButtonStyle())
            .tint(HolyGhosttyTheme.danger)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(HolyGhosttyTheme.bgElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(HolyGhosttyTheme.border, lineWidth: 0.6)
        )
    }

    private func allVisibleSelected(in visibleIDs: Set<String>) -> Bool {
        !visibleIDs.isEmpty && visibleIDs.isSubset(of: selectedDiscoveredSessionIDs)
    }

    private func toggleSelectAll(visibleIDs: Set<String>) {
        if allVisibleSelected(in: visibleIDs) {
            selectedDiscoveredSessionIDs.subtract(visibleIDs)
        } else {
            selectedDiscoveredSessionIDs.formUnion(visibleIDs)
        }
    }

    private func toggleSelection(for session: HolyDiscoveredTmuxSession) {
        if selectedDiscoveredSessionIDs.contains(session.id) {
            selectedDiscoveredSessionIDs.remove(session.id)
        } else {
            selectedDiscoveredSessionIDs.insert(session.id)
        }
    }

    private func requestKill(
        of session: HolyDiscoveredTmuxSession,
        onKill: @escaping (HolyDiscoveredTmuxSession) -> Void
    ) {
        requestKill(of: [session], onKill: onKill)
    }

    private func requestKill(
        of sessions: [HolyDiscoveredTmuxSession],
        onKill: @escaping (HolyDiscoveredTmuxSession) -> Void
    ) {
        guard !sessions.isEmpty else { return }
        killConfirmation = HolyDiscoveredKillRequest(sessions: sessions, onKill: onKill)
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

    private func sessionGroupLabel(_ runtime: HolySessionRuntime, count: Int) -> some View {
        HStack(spacing: 7) {
            Image(systemName: runtime.connectionSymbolName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(runtime.connectionTint)
                .frame(width: 12)

            Text(runtime.displayName.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(HolyGhosttyTheme.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text("\(count)")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(HolyGhosttyTheme.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
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

    private var localConnectionSessions: [HolyDiscoveredTmuxSession] {
        sortedConnectionSessions(store.discoveredLocalTmuxSessions)
    }

    private var sortedRemoteHosts: [HolyRemoteHostRecord] {
        store.remoteHosts.sorted {
            $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
        }
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

        let sessions = localConnectionSessions
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
        let sessions = sortedConnectionSessions(store.remoteSessions(for: host))
        let primarySessions = sessions.filter { session in
            session.attachedClientCount > 0 || session.isHolyManaged
        }

        return primarySessions.isEmpty ? sessions : primarySessions
    }

    private func groupedConnectionSessions(_ sessions: [HolyDiscoveredTmuxSession]) -> [HolyDiscoveredTmuxSessionGroup] {
        let grouped = Dictionary(grouping: sortedConnectionSessions(sessions)) { session in
            session.connectionRuntime
        }

        return HolySessionRuntime.connectionRosterOrder.compactMap { runtime in
            guard let sessions = grouped[runtime], !sessions.isEmpty else {
                return nil
            }

            return .init(runtime: runtime, sessions: sessions)
        }
    }

    private func sortedConnectionSessions(_ sessions: [HolyDiscoveredTmuxSession]) -> [HolyDiscoveredTmuxSession] {
        sessions.sorted { lhs, rhs in
            if lhs.connectionRuntime != rhs.connectionRuntime {
                let lhsRank = HolySessionRuntime.connectionRosterOrder.firstIndex(of: lhs.connectionRuntime) ?? Int.max
                let rhsRank = HolySessionRuntime.connectionRosterOrder.firstIndex(of: rhs.connectionRuntime) ?? Int.max
                return lhsRank < rhsRank
            }

            let titleComparison = lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle)
            if titleComparison != .orderedSame {
                return titleComparison == .orderedAscending
            }

            if lhs.isHolyManaged != rhs.isHolyManaged {
                return lhs.isHolyManaged && !rhs.isHolyManaged
            }

            return lhs.sessionName.localizedCaseInsensitiveCompare(rhs.sessionName) == .orderedAscending
        }
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

private struct HolyConnectionHeroContent {
    let title: String
    let subtitle: String
    let symbolName: String
    let status: String
    let statusColor: Color
    let sessionCount: Int
    let isBusy: Bool
}

private struct HolyConnectionSessionListContent {
    let title: String
    let sessions: [HolyDiscoveredTmuxSession]
    let isBusy: Bool
    let error: String?
    let emptyTitle: String
    let emptySubtitle: String
}

private struct HolyDiscoveredKillRequest: Identifiable {
    let id = UUID()
    let sessions: [HolyDiscoveredTmuxSession]
    let onKill: (HolyDiscoveredTmuxSession) -> Void

    var sessionIDs: Set<String> {
        Set(sessions.map(\.id))
    }

    var countLabel: String {
        sessions.count == 1 ? "Session" : "\(sessions.count) Sessions"
    }

    var confirmationTitle: String {
        sessions.count == 1
            ? "Kill tmux session “\(sessions[0].displayTitle)”?"
            : "Kill \(sessions.count) tmux sessions?"
    }

    var confirmationMessage: String {
        let warning = "This permanently kills the session on its tmux server. Unsaved work in it will be lost and cannot be recovered."
        guard sessions.count > 1 else { return warning }

        if sessions.count <= 5 {
            let names = sessions.map { "• \($0.displayTitle)" }.joined(separator: "\n")
            return "\(warning)\n\n\(names)"
        }

        return warning
    }

    func perform() {
        for session in sessions {
            onKill(session)
        }
    }
}

private struct HolyDiscoveredTmuxSessionGroup: Identifiable {
    let runtime: HolySessionRuntime
    let sessions: [HolyDiscoveredTmuxSession]

    var id: String { runtime.rawValue }
}

private extension HolySessionRuntime {
    static let connectionRosterOrder: [HolySessionRuntime] = [.claude, .codex, .opencode, .shell]

    var connectionSymbolName: String {
        switch self {
        case .claude:
            return "sparkles"
        case .codex:
            return "arrow.triangle.2.circlepath"
        case .opencode:
            return "curlybraces"
        case .shell:
            return "terminal"
        }
    }

    var connectionTint: Color {
        switch self {
        case .claude:
            return HolyGhosttyTheme.halo
        case .codex:
            return HolyGhosttyTheme.accent
        case .opencode:
            return HolyGhosttyTheme.success
        case .shell:
            return HolyGhosttyTheme.textTertiary
        }
    }
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
    let isSelected: Bool
    let onToggleSelected: () -> Void
    let onLaunch: () -> Void
    let onKill: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: onToggleSelected) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(isSelected ? HolyGhosttyTheme.halo : HolyGhosttyTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .help(isSelected ? "Deselect session" : "Select session")

            Image(systemName: session.connectionRuntime.connectionSymbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(session.connectionRuntime.connectionTint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.displayTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HolyGhosttyTheme.textPrimary)
                    .lineLimit(1)

                Text(secondaryLine)
                    .font(.system(size: 10))
                    .foregroundStyle(HolyGhosttyTheme.textSecondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 3) {
                Text(session.connectionRosterSummary)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(HolyGhosttyTheme.textSecondary)
                    .lineLimit(1)

                Text(trailingLine)
                    .font(.system(size: 9))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
                    .lineLimit(1)
            }
            .frame(width: 180, alignment: .trailing)

            Button("Attach", action: onLaunch)
                .buttonStyle(HolyGhosttyActionButtonStyle())

            Button(action: onKill) {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HolyGhosttyTheme.danger)
            }
            .buttonStyle(.plain)
            .help("Kill this tmux session on the server")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background((isSelected ? HolyGhosttyTheme.halo.opacity(0.12) : HolyGhosttyTheme.bgElevated.opacity(0.72)))
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggleSelected)
        .contextMenu {
            Button("Attach", action: onLaunch)
            Divider()
            Button("Kill Session on Server", role: .destructive, action: onKill)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(HolyGhosttyTheme.border)
                .frame(height: 0.5)
        }
    }

    private var secondaryLine: String {
        if let taskTitle = session.taskTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !taskTitle.isEmpty {
            return taskTitle
        }

        if let objective = session.objective?.trimmingCharacters(in: .whitespacesAndNewlines),
           !objective.isEmpty {
            return objective
        }

        return session.subtitle
    }

    private var trailingLine: String {
        if let gitSummary = session.gitSummary {
            return "\(gitSummary.branchDisplayName) · \(gitSummary.syncStatusText)"
        }

        return session.tmuxServerSummary
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
