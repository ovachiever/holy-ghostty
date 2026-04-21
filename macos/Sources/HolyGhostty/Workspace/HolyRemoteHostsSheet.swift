import SwiftUI

struct HolyRemoteHostsSheet: View {
    @ObservedObject var store: HolyWorkspaceStore
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
                    hostList
                        .frame(minWidth: 260, idealWidth: 300, maxWidth: 380, maxHeight: .infinity)
                        .background(HolyGhosttyTheme.bgElevated)

                    hostDetail
                        .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
                        .layoutPriority(1)
                }
            }
        }
        .frame(minWidth: 1080, minHeight: 720)
        .onAppear {
            ensureSelection()
            reloadEditor()
            refreshIfNeeded()
        }
        .onChange(of: store.selectedRemoteHostID) { _ in
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
                Text("Machines")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(HolyGhosttyTheme.halo)

                Text(machineCountText)
                    .font(.system(size: 11))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)

                Spacer()

                Menu("Discover") {
                    Button("From SSH Config") { store.importRemoteHostsFromSSHConfig() }
                    Button("From Tailscale") { store.importRemoteHostsFromTailscale() }
                }
                .buttonStyle(HolyGhosttyActionButtonStyle())

                if let selectedHost {
                    Button("Refresh") { store.refreshRemoteSessions(for: selectedHost) }
                        .buttonStyle(HolyGhosttyActionButtonStyle())
                }

                Button("Add Machine") { store.createRemoteHost() }
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

    private var hostList: some View {
        Group {
            if store.remoteHosts.isEmpty {
                HolyGhosttyEmptyStateView(
                    title: "No machines yet",
                    subtitle: "Add or discover a machine and Holy Ghostty will inspect its tmux sessions over SSH.",
                    symbol: "server.rack"
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(store.remoteHosts) { host in
                            HolyRemoteHostRow(
                                host: host,
                                isSelected: host.id == store.selectedRemoteHostID,
                                isBusy: store.isRemoteDiscoveryBusy(for: host),
                                sessionCount: store.remoteSessions(for: host).count,
                                discoveryError: store.remoteDiscoveryError(for: host),
                                onSelect: { store.selectedRemoteHostID = host.id }
                            )
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var hostDetail: some View {
        Group {
            if editorHost != nil, let selectedHost {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selectedHost.displayTitle)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(HolyGhosttyTheme.textPrimary)

                            Text(selectedHost.subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(HolyGhosttyTheme.textSecondary)
                        }

                        actionBar(for: selectedHost)
                        statusSection(for: selectedHost)
                        editorSection
                        sessionsSection(for: selectedHost)
                    }
                    .padding(16)
                }
                .scrollIndicators(.hidden)
            } else {
                HolyGhosttyEmptyStateView(
                    title: "No machine selected",
                    subtitle: "Choose a saved machine to inspect its tmux sessions.",
                    symbol: "server.rack"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func actionBar(for host: HolyRemoteHostRecord) -> some View {
        let discoveredSessions = store.remoteSessions(for: host)
        let holyManagedSessions = discoveredSessions.filter(\.isHolyManaged)

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

            if !holyManagedSessions.isEmpty, holyManagedSessions.count != discoveredSessions.count {
                Button("Attach Holy") {
                    store.launchRemoteTmuxSessions(holyManagedSessions, on: host)
                }
                .buttonStyle(HolyGhosttyActionButtonStyle())
            }

            Button("Delete") { store.deleteRemoteHost(host) }
                .buttonStyle(HolyGhosttyActionButtonStyle())

            Spacer()
        }
    }

    private func statusSection(for host: HolyRemoteHostRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Machine")
            detailRow("SSH", host.subtitle)
            detailRow("Probe", host.tmuxSummary)
            detailRow("Last Seen", host.lastDiscoveredAt.map(Self.timestampString(from:)) ?? "Never")

            if let error = store.remoteDiscoveryError(for: host) {
                detailRow("Discovery", error, color: HolyGhosttyTheme.danger)
            } else if store.isRemoteDiscoveryBusy(for: host) {
                detailRow("Discovery", "Refreshing…", color: HolyGhosttyTheme.halo)
            } else {
                let summary = discoverySummary(for: host)
                detailRow("Discovery", summary)
            }
        }
    }

    private var editorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Connection")

            labeledField("Label", text: editorBinding(\.label), placeholder: "studio")
            labeledField("SSH Destination", text: editorBinding(\.sshDestination), placeholder: "studio")

            DisclosureGroup("Advanced") {
                VStack(alignment: .leading, spacing: 8) {
                    labeledField("Tmux Socket Override", text: editorOptionalBinding(\.tmuxSocketName), placeholder: "holy")

                    Text("Leave this blank unless you need a specific tmux socket. Holy will check the default tmux server first, then the holy socket.")
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
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(HolyGhosttyTheme.bgElevated)
        )
    }

    private func sessionsSection(for host: HolyRemoteHostRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Discovered Sessions")

            if store.isRemoteDiscoveryBusy(for: host) && store.remoteSessions(for: host).isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .tint(HolyGhosttyTheme.halo)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else if let discoveryError = store.remoteDiscoveryError(for: host) {
                HolyGhosttyEmptyStateView(
                    title: "Can’t inspect this machine",
                    subtitle: discoveryError,
                    symbol: "exclamationmark.triangle"
                )
                .frame(maxWidth: .infinity)
            } else if store.remoteSessions(for: host).isEmpty {
                HolyGhosttyEmptyStateView(
                    title: "No tmux sessions found",
                    subtitle: emptyDiscoverySubtitle(for: host),
                    symbol: "rectangle.stack.badge.plus"
                )
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 8) {
                    ForEach(store.remoteSessions(for: host)) { session in
                        HolyDiscoveredRemoteSessionRow(
                            session: session,
                            onLaunch: { store.launchRemoteTmuxSession(session, on: host) }
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
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
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
        if store.selectedRemoteHostID == nil {
            store.selectedRemoteHostID = store.remoteHosts.first?.id
        }
    }

    private func reloadEditor() {
        editorHost = selectedHost
    }

    private func refreshIfNeeded() {
        guard let selectedHost,
              store.remoteSessions(for: selectedHost).isEmpty,
              !store.isRemoteDiscoveryBusy(for: selectedHost) else {
            return
        }

        store.refreshRemoteSessions(for: selectedHost)
    }

    private func saveEditor() {
        guard let editorHost else { return }
        store.upsertRemoteHost(editorHost)
        reloadEditor()
    }

    private var selectedHost: HolyRemoteHostRecord? {
        store.selectedRemoteHost
    }

    private var machineCountText: String {
        let count = store.remoteHosts.count
        return count == 1 ? "1 machine" : "\(count) machines"
    }

    private func discoverySummary(for host: HolyRemoteHostRecord) -> String {
        let sessions = store.remoteSessions(for: host)
        if sessions.isEmpty {
            return emptyDiscoverySubtitle(for: host)
        }

        return sessions.count == 1 ? "1 tmux session discovered" : "\(sessions.count) tmux sessions discovered"
    }

    private func emptyDiscoverySubtitle(for host: HolyRemoteHostRecord) -> String {
        let explicitSocketName = host.tmuxSocketName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank

        if explicitSocketName == nil {
            return "No tmux sessions found on the default tmux server or the holy socket."
        }

        return "No tmux sessions found on \(host.tmuxSummary.lowercased())."
    }

    private static func timestampString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct HolyRemoteHostRow: View {
    let host: HolyRemoteHostRecord
    let isSelected: Bool
    let isBusy: Bool
    let sessionCount: Int
    let discoveryError: String?
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(host.displayTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HolyGhosttyTheme.textPrimary)
                        .lineLimit(1)

                    Text(host.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(HolyGhosttyTheme.textSecondary)
                        .lineLimit(1)

                    Text(statusText)
                        .font(.system(size: 10))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                            .tint(HolyGhosttyTheme.halo)
                    } else {
                        Text("\(sessionCount)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(HolyGhosttyTheme.textSecondary)
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
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(isSelected ? HolyGhosttyTheme.bgSurface : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isSelected ? HolyGhosttyTheme.halo.opacity(0.4) : HolyGhosttyTheme.border, lineWidth: 0.8)
            )
    }

    private var statusText: String {
        if let discoveryError = discoveryError?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank {
            return discoveryError
        }

        return host.tmuxSummary
    }

    private var statusColor: Color {
        discoveryError == nil ? HolyGhosttyTheme.textTertiary : HolyGhosttyTheme.danger
    }
}

private struct HolyDiscoveredRemoteSessionRow: View {
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
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(HolyGhosttyTheme.bgElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
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
