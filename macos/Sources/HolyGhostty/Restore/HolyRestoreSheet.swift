import SwiftUI

/// The crash-restore surface: every interrupted session as one row with an
/// honest verdict, restored only on explicit action. Restore Selected
/// attaches as each row verifies; Restore All stays headless and lets
/// attach happen lazily. Nothing here launches without a click.
struct HolyRestoreSheet: View {
    @ObservedObject var store: HolyWorkspaceStore
    @ObservedObject var engine: HolyRestoreEngine

    init(store: HolyWorkspaceStore) {
        self.store = store
        self.engine = store.restoreEngine
    }

    var body: some View {
        ZStack {
            HolyGhosttyBackdrop()

            VStack(spacing: 0) {
                header

                Rectangle()
                    .fill(HolyGhosttyTheme.border)
                    .frame(height: 0.5)

                if engine.rows.isEmpty {
                    HolyGhosttyEmptyStateView(
                        title: "Nothing to restore",
                        subtitle: "No interrupted sessions were found from the last cold boot.",
                        symbol: "checkmark.seal"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    rowList
                }

                Rectangle()
                    .fill(HolyGhosttyTheme.border)
                    .frame(height: 0.5)

                footer
            }
        }
        .frame(minWidth: 760, minHeight: 480)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Text("Crash Restore")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(HolyGhosttyTheme.halo)

            Text("\(engine.interruptedCount) interrupted")
                .font(.system(size: 11))
                .foregroundStyle(HolyGhosttyTheme.textTertiary)

            if engine.isPreflighting {
                ProgressView()
                    .controlSize(.small)
                Text("Checking sessions…")
                    .font(.system(size: 11))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
            }

            Spacer()

            Button("Keep for Later") { store.restorePresented = false }
                .buttonStyle(HolyGhosttyActionButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(HolyGhosttyTheme.bgElevated)
    }

    // MARK: - Rows

    private var rowList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(engine.rows) { row in
                    RestoreRowView(
                        row: row,
                        isBusy: engine.isRestoring,
                        onToggleSelection: { engine.setSelected(!row.isSelected, rowID: row.id) },
                        onPickCandidate: { engine.pickCandidate(rowID: row.id, candidateID: $0) },
                        onRetry: { Task { await engine.retry(rowID: row.id) } },
                        onAttach: { Task { await engine.attach(rowID: row.id) } }
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if engine.isRestoring {
                ProgressView()
                    .controlSize(.small)
                Text("Restoring…")
                    .font(.system(size: 11))
                    .foregroundStyle(HolyGhosttyTheme.textSecondary)
            } else {
                Text(footerSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
            }

            Spacer()

            Button("Restore Selected (\(engine.selectedCount))") {
                Task { await engine.restoreSelected() }
            }
            .buttonStyle(HolyGhosttyActionButtonStyle())
            .disabled(engine.isRestoring || engine.isPreflighting || engine.selectedCount == 0)

            Button("Restore All (headless)") {
                Task { await engine.restoreAll() }
            }
            .buttonStyle(HolyGhosttyActionButtonStyle())
            .disabled(engine.isRestoring || engine.isPreflighting || engine.rows.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(HolyGhosttyTheme.bgElevated)
    }

    private var footerSummary: String {
        let restored = engine.rows.filter {
            if case .restored = $0.phase { return true }
            return false
        }.count
        let failed = engine.rows.filter {
            if case .failed = $0.phase { return true }
            return false
        }.count

        var parts: [String] = []
        if restored > 0 { parts.append("\(restored) restored") }
        if failed > 0 { parts.append("\(failed) failed — retry available") }
        if parts.isEmpty {
            return "Selected sessions attach; Restore All recreates them headless."
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Row

private struct RestoreRowView: View {
    let row: HolyRestoreRow
    let isBusy: Bool
    let onToggleSelection: () -> Void
    let onPickCandidate: (String) -> Void
    let onRetry: () -> Void
    let onAttach: () -> Void

    @State private var pickerPresented = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Toggle("", isOn: .init(get: { row.isSelected }, set: { _ in onToggleSelection() }))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(isBusy)

            HolyGhosttyStatusDot(color: stateColor)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.archived.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(HolyGhosttyTheme.textPrimary)
                        .lineLimit(1)

                    Text(row.plannedLaunchSpec.runtime.displayName)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(HolyGhosttyTheme.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(HolyGhosttyTheme.bgSurface)
                        )
                }

                Text(row.archived.workingDirectoryDisplay)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.head)

                Text(statusLine)
                    .font(.system(size: 10))
                    .foregroundStyle(statusColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            trailingControls
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(HolyGhosttyTheme.bgElevated.opacity(0.6))
        )
    }

    @ViewBuilder
    private var trailingControls: some View {
        switch row.phase {
        case .preflighting, .restoring:
            ProgressView()
                .controlSize(.small)
        case .failed:
            Button("Retry", action: onRetry)
                .buttonStyle(HolyGhosttyActionButtonStyle())
                .disabled(isBusy)
        case .restored(attached: false):
            Button("Attach", action: onAttach)
                .buttonStyle(HolyGhosttyActionButtonStyle())
                .disabled(isBusy)
        case .restored(attached: true):
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(HolyGhosttyTheme.success)
        case .pending, .ready:
            if case let .ambiguous(candidates) = row.state {
                Button("Pick…") { pickerPresented = true }
                    .buttonStyle(HolyGhosttyActionButtonStyle())
                    .disabled(isBusy)
                    .popover(isPresented: $pickerPresented, arrowEdge: .bottom) {
                        CandidatePicker(candidates: candidates) { candidateID in
                            pickerPresented = false
                            onPickCandidate(candidateID)
                        }
                    }
            } else if case .alreadyRestored = row.state {
                Button("Attach", action: onAttach)
                    .buttonStyle(HolyGhosttyActionButtonStyle())
                    .disabled(isBusy)
            }
        }
    }

    /// One honest line combining the preflight verdict, lifecycle phase,
    /// and identity confirmation.
    private var statusLine: String {
        switch row.phase {
        case let .failed(reason):
            return reason
        case .restoring:
            return "Restoring…"
        case .preflighting, .pending:
            return "Checking…"
        case let .restored(attached):
            var line = attached
                ? "Restored and attached."
                : "Restored headless — attach when ready."
            switch row.confirmation {
            case .confirmed:
                line += " Conversation identity confirmed."
            case let .unverified(reason):
                line += " Identity unverified: \(reason)"
            case .mismatch, .notApplicable:
                break
            }
            return line
        case .ready:
            break
        }

        switch row.state {
        case let .exactResume(providerSessionID):
            return "Exact resume — conversation \(String(providerSessionID.prefix(8)))…"
        case let .ambiguous(candidates):
            return "\(candidates.count) conversations match — pick the one to resume."
        case .shellOnly:
            return "Shell only — recreates the directory and command. Processes and scrollback are gone."
        case .missingHistory:
            return "No conversation history found — offers a shell-only recreate, not a resume."
        case .wrongHost:
            return "Remote session — restore is local-only for now."
        case .alreadyRestored:
            return "Already live — restoring adopts the existing session."
        case let .conflict(reason):
            return reason
        case let .blocked(reason):
            return reason
        }
    }

    private var stateColor: Color {
        switch row.phase {
        case .failed:
            return HolyGhosttyTheme.danger
        case .restored:
            return HolyGhosttyTheme.success
        case .restoring, .preflighting:
            return HolyGhosttyTheme.accent
        case .pending, .ready:
            break
        }

        switch row.state {
        case .exactResume, .alreadyRestored:
            return HolyGhosttyTheme.success
        case .ambiguous:
            return HolyGhosttyTheme.warning
        case .shellOnly, .missingHistory:
            return HolyGhosttyTheme.accent
        case .wrongHost, .conflict, .blocked:
            return HolyGhosttyTheme.danger
        }
    }

    private var statusColor: Color {
        switch row.phase {
        case .failed:
            return HolyGhosttyTheme.danger
        default:
            return HolyGhosttyTheme.textSecondary
        }
    }
}

// MARK: - Candidate picker

private struct CandidatePicker: View {
    let candidates: [HolyRestoreResolveCandidate]
    let onPick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Which conversation was this session running?")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(HolyGhosttyTheme.textPrimary)

            ForEach(candidates) { candidate in
                Button {
                    onPick(candidate.id)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(candidate.preview.isEmpty ? "(no first prompt)" : candidate.preview)
                            .font(.system(size: 11))
                            .foregroundStyle(HolyGhosttyTheme.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Text("\(endDateText(candidate)) · \(String(candidate.id.prefix(8)))…")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(HolyGhosttyTheme.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(HolyGhosttyTheme.bgSurface)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: 380)
    }

    private func endDateText(_ candidate: HolyRestoreResolveCandidate) -> String {
        Date(timeIntervalSince1970: TimeInterval(candidate.timestampEnd))
            .formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - Cold-boot banner

/// Thin bar above the workspace after a cold boot: states the interrupted
/// count and offers the restore sheet. Never launches anything itself.
struct HolyRestoreBanner: View {
    let interruptedCount: Int
    let onRestore: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.trianglebadge.exclamationmark")
                .font(.system(size: 12))
                .foregroundStyle(HolyGhosttyTheme.warning)

            Text("\(interruptedCount) session\(interruptedCount == 1 ? "" : "s") interrupted by the last shutdown.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(HolyGhosttyTheme.textPrimary)

            Spacer()

            Button("Restore…", action: onRestore)
                .buttonStyle(HolyGhosttyActionButtonStyle())

            Button("Keep for Later", action: onDismiss)
                .buttonStyle(HolyGhosttyActionButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(HolyGhosttyTheme.bgElevated)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(HolyGhosttyTheme.border)
                .frame(height: 0.5)
        }
    }
}
