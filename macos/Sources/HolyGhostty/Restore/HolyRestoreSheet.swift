import SwiftUI

/// The crash-restore surface: this reboot's interruptions as one honest
/// section, helper shells grouped one click away inside it, older
/// interruptions grouped per crash event beneath, every row restored only on
/// explicit action. Each crash wears its recency hue — a wash and a leading
/// edge, never a status — so a whole holy experience can be spotted and
/// restored as one. Restore Selected attaches as each row verifies; Restore
/// All recreates the fresh batch's parent rows headless and lets attach
/// happen lazily. Nothing here launches without a click, and nothing is
/// deleted without a confirmation that states the count.
struct HolyRestoreSheet: View {
    @ObservedObject var store: HolyWorkspaceStore
    @ObservedObject var engine: HolyRestoreEngine
    @State private var freshHelpersExpanded = false
    @State private var expandedOlderGroups: Set<HolyRestoreCrashGroupKey> = []
    @State private var expandedOlderHelperGroups: Set<HolyRestoreCrashGroupKey> = []
    @State private var clearOlderConfirmationPresented = false

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
            Text("Session Restore")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(HolyGhosttyTheme.halo)

            Text(headerCounts)
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

            HolyGhosttyCloseButton(
                action: { store.restorePresented = false },
                label: "Close",
                isCancelAction: true
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(HolyGhosttyTheme.bgElevated)
    }

    /// Itemized rather than summed: the interrupted count is parents only,
    /// so helpers get their own number instead of quietly disappearing from
    /// a total the user could otherwise check against the row list.
    private var headerCounts: String {
        var parts = ["\(engine.interruptedCount) interrupted"]
        if engine.freshHelperCount > 0 {
            parts.append("\(engine.freshHelperCount) helper\(engine.freshHelperCount == 1 ? "" : "s")")
        }
        if engine.olderCount > 0 {
            parts.append("\(engine.olderCount) older")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Rows

    /// The rows the user can currently see. The law itself lives on the
    /// engine (and is tested there); the sheet only reports which
    /// disclosures are open.
    private var visibleRowIDs: [UUID] {
        engine.visibleRowIDs(
            freshHelpersExpanded: freshHelpersExpanded,
            expandedOlderGroups: expandedOlderGroups,
            expandedOlderHelperGroups: expandedOlderHelperGroups
        )
    }

    private var rowList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                if !engine.freshRows.isEmpty {
                    freshSectionHeader
                    ForEach(engine.freshParentRows) { row in
                        restoreRow(row, rank: HolyRestoreEngine.freshCrashRank)
                    }
                    helperSection(
                        rows: engine.freshHelperRows,
                        isExpanded: $freshHelpersExpanded,
                        rank: HolyRestoreEngine.freshCrashRank
                    )
                }

                if engine.olderCount > 0 {
                    olderSectionHeader
                    ForEach(engine.olderCrashSections) { section in
                        olderCrashSectionView(section)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
    }

    /// One crash event: a header naming when and how much, its parent rows,
    /// and its helper shells nested one more click down. Every row inside
    /// wears the crash's recency hue.
    @ViewBuilder
    private func olderCrashSectionView(_ section: HolyRestoreEngine.OlderCrashSection) -> some View {
        let isExpanded = expandedOlderGroups.contains(section.key)

        HStack(spacing: 8) {
            Button {
                if isExpanded {
                    expandedOlderGroups.remove(section.key)
                } else {
                    expandedOlderGroups.insert(section.key)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(HolyGhosttyTheme.textTertiary)

                    Circle()
                        .fill(
                            HolyGhosttyTheme.crashBatchHue(rank: section.rank)
                                .opacity(HolyGhosttyTheme.crashBatchTickOpacity)
                        )
                        .frame(width: 6, height: 6)

                    Text(crashSectionTitle(section))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(HolyGhosttyTheme.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            if engine.restoringCrashGroupKey == section.key {
                ProgressView()
                    .controlSize(.mini)
            } else if !section.parentRows.isEmpty {
                Button("Restore this shutdown (\(section.parentRows.count))") {
                    Task { await engine.restoreCrashGroup(key: section.key) }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(HolyGhosttyTheme.accent)
                .disabled(engine.isRestoring)
                .help(
                    "Recreates this shutdown's \(section.parentRows.count) named "
                        + "session\(section.parentRows.count == 1 ? "" : "s") headless. "
                        + "Helper shells restore only by explicit selection."
                )
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
        .padding(.bottom, 3)

        if isExpanded {
            ForEach(section.parentRows) { row in
                restoreRow(row, rank: section.rank)
            }
            helperSection(
                rows: section.helperRows,
                isExpanded: helperExpansionBinding(for: section.key),
                rank: section.rank
            )
        }
    }

    /// "Shutdown · 2 days ago · 5 sessions · 3 helpers". Parents and helpers
    /// are itemized separately so the restore action's count is checkable
    /// against the header; a batch with nothing but helpers says so instead of
    /// showing an empty batch. "Shutdown" covers every cold boot the batch can
    /// come from — deliberate reboot, manual tmux server kill, or crash.
    private func crashSectionTitle(_ section: HolyRestoreEngine.OlderCrashSection) -> String {
        var parts = ["Shutdown", Self.relativeTime(section.newestArchivedAt)]
        let parents = section.parentRows.count
        let helpers = section.helperRows.count
        if parents > 0 {
            parts.append("\(parents) session\(parents == 1 ? "" : "s")")
            if helpers > 0 {
                parts.append("\(helpers) helper\(helpers == 1 ? "" : "s")")
            }
        } else {
            parts.append("only helper sessions (\(helpers))")
        }
        return parts.joined(separator: " · ")
    }

    private func helperExpansionBinding(for key: HolyRestoreCrashGroupKey) -> Binding<Bool> {
        Binding(
            get: { expandedOlderHelperGroups.contains(key) },
            set: { expanded in
                if expanded {
                    expandedOlderHelperGroups.insert(key)
                } else {
                    expandedOlderHelperGroups.remove(key)
                }
            }
        )
    }

    static func relativeTime(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named))
    }

    /// Helper shells, grouped one click away. Grouped, never hidden: the
    /// count is always visible and every row inside stays fully restorable.
    @ViewBuilder
    private func helperSection(
        rows: [HolyRestoreRow],
        isExpanded: Binding<Bool>,
        rank: Int
    ) -> some View {
        if !rows.isEmpty {
            Button {
                isExpanded.wrappedValue.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(HolyGhosttyTheme.textTertiary)

                    Text("Helper sessions (\(rows.count))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(HolyGhosttyTheme.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    Spacer()
                }
                .padding(.leading, 14)
                .padding(.trailing, 4)
                .padding(.top, 8)
                .padding(.bottom, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Named by Holy when it adopted a sub-agent's shell. Grouped, not hidden.")

            if isExpanded.wrappedValue {
                ForEach(rows) { row in
                    restoreRow(row, rank: rank)
                }
            }
        }
    }

    private func restoreRow(_ row: HolyRestoreRow, rank: Int) -> some View {
        RestoreRowView(
            row: row,
            batchHue: HolyGhosttyTheme.crashBatchHue(rank: rank),
            lineageTicks: engine.lineageTicks(for: row).map { tick in
                RestoreLineageTickDisplay(
                    sectionID: tick.sectionID,
                    color: HolyGhosttyTheme.crashBatchHue(rank: tick.rank),
                    tooltip: "Also interrupted in the shutdown of "
                        + "\(Self.relativeTime(tick.occurredAt))."
                )
            },
            isBusy: engine.isRestoring,
            onToggleSelection: { engine.setSelected(!row.isSelected, rowID: row.id) },
            onPickCandidate: { engine.pickCandidate(rowID: row.id, candidateID: $0) },
            onRetry: { Task { await engine.retry(rowID: row.id) } },
            onAttach: { Task { await engine.attach(rowID: row.id) } }
        )
    }

    private var freshSectionHeader: some View {
        HStack(spacing: 8) {
            // The fresh batch's hue swatch, mirroring the older crash
            // headers: a blue lineage tick anywhere below points here.
            Circle()
                .fill(
                    HolyGhosttyTheme.crashBatchHue(rank: HolyRestoreEngine.freshCrashRank)
                        .opacity(HolyGhosttyTheme.crashBatchTickOpacity)
                )
                .frame(width: 6, height: 6)

            Text("Interrupted by the last shutdown")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(HolyGhosttyTheme.textTertiary)
                .textCase(.uppercase)
                .tracking(0.5)

            Spacer()

            Button("Select All") { engine.setSelection(true, rowIDs: visibleRowIDs) }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(HolyGhosttyTheme.accent)
                .disabled(engine.isRestoring)

            Button("Select None") { engine.setSelection(false, rowIDs: visibleRowIDs) }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(HolyGhosttyTheme.accent)
                .disabled(engine.isRestoring)
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .padding(.bottom, 3)
    }

    /// The umbrella label over the per-crash subsections. Not a disclosure
    /// itself — each crash opens and shuts on its own — but it keeps the
    /// honest region total and carries the one destructive action.
    private var olderSectionHeader: some View {
        HStack(spacing: 8) {
            Text("Older interruptions (\(engine.olderCount))")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(HolyGhosttyTheme.textTertiary)
                .textCase(.uppercase)
                .tracking(0.5)

            Spacer()

            // Quiet by weight, danger by color: it sits in a header row, so
            // it must never outrank the restore actions below it, and it
            // must never be mistaken for one of them.
            Button("Clear older interruptions…") { clearOlderConfirmationPresented = true }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(HolyGhosttyTheme.danger)
                .disabled(engine.isRestoring)
        }
        .padding(.horizontal, 4)
        .padding(.top, 10)
        .padding(.bottom, 3)
        .confirmationDialog(
            clearOlderConfirmationTitle,
            isPresented: $clearOlderConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(clearOlderConfirmationAction, role: .destructive) {
                engine.clearOlderInterruptions()
                expandedOlderGroups.removeAll()
                expandedOlderHelperGroups.removeAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Deletes the archived records from Session History. "
                    + "The sessions themselves ended at the last shutdown; "
                    + "this boot's interruptions are not touched."
            )
        }
    }

    private var clearOlderConfirmationTitle: String {
        engine.olderCount == 1
            ? "Clear 1 older interruption?"
            : "Clear \(engine.olderCount) older interruptions?"
    }

    private var clearOlderConfirmationAction: String {
        engine.olderCount == 1
            ? "Clear 1 record"
            : "Clear \(engine.olderCount) records"
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

            // Deliberately NOT disabled while preflight is still running:
            // rows whose checks finished are restorable immediately, and
            // rows still checking are skipped honestly (blocked state) and
            // restorable once ready. A slow resolver must never hold rows
            // that are already verified hostage.
            Button("Restore All (\(engine.interruptedCount), headless)") {
                Task { await engine.restoreAll() }
            }
            .buttonStyle(HolyGhosttyActionButtonStyle())
            .disabled(engine.isRestoring || engine.interruptedCount == 0)

            Button("Restore Selected (\(engine.selectedCount))") {
                Task { await engine.restoreSelected() }
            }
            .buttonStyle(HolyGhosttyProminentButtonStyle())
            .disabled(engine.isRestoring || engine.selectedCount == 0)
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

/// One lineage tick, resolved to render facts: the other crash's hue and a
/// tooltip naming when it happened. Information, never dual membership.
private struct RestoreLineageTickDisplay: Identifiable, Equatable {
    let sectionID: HolyRestoreCrashSectionID
    let color: Color
    let tooltip: String

    var id: HolyRestoreCrashSectionID { sectionID }
}

private struct RestoreRowView: View {
    let row: HolyRestoreRow
    /// The recency hue of the crash this row belongs to.
    let batchHue: Color
    let lineageTicks: [RestoreLineageTickDisplay]
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

                    // Lineage: this same session also died in another crash.
                    // A 6pt swatch in that crash's hue — a fact to notice,
                    // not a state to act on.
                    ForEach(lineageTicks) { tick in
                        Circle()
                            .fill(tick.color.opacity(HolyGhosttyTheme.crashBatchTickOpacity))
                            .frame(width: 6, height: 6)
                            .help(tick.tooltip)
                            .accessibilityLabel(tick.tooltip)
                    }
                }

                Text(row.archived.workingDirectoryDisplay)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.head)

                // The note sits with the identity lines, not the status
                // line: it answers "which one is this?", not "what will
                // restore do?". Five rows in the same worktree are told
                // apart by exactly this.
                if let note = row.noteDisplay {
                    RestoreNoteLine(note: note)
                }

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
            // The batch's recency wash over the row surface, plus a leading
            // edge in the same hue: the edge names the batch even where the
            // mist is too soft to call. Neither carries health — status
            // stays with the dot.
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(HolyGhosttyTheme.bgElevated.opacity(0.6))
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(batchHue.opacity(HolyGhosttyTheme.crashBatchWashOpacity))
                Rectangle()
                    .fill(batchHue.opacity(HolyGhosttyTheme.crashBatchEdgeOpacity))
                    .frame(width: HolyGhosttyTheme.crashBatchEdgeWidth)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
                        CandidatePicker(
                            rowTitle: row.archived.title,
                            rowNote: row.noteDisplay,
                            candidates: candidates
                        ) { candidateID in
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

    /// One honest line combining the preflight verdict and lifecycle phase.
    private var statusLine: String {
        switch row.phase {
        case let .failed(reason):
            return reason
        case .restoring:
            return "Restoring…"
        case .preflighting, .pending:
            return "Checking…"
        case let .restored(attached):
            // The argv is the identity: we launched `--resume <exact id>` as
            // an argument array, so the resumed conversation IS that id. No
            // re-resolve happens, and nothing here claims one did.
            if case let .exactResume(providerSessionID) = row.state {
                let shortID = String(providerSessionID.prefix(8))
                return attached
                    ? "Restored and attached — resumed conversation \(shortID)…"
                    : "Restored headless — resumed conversation \(shortID)…, attach when ready."
            }
            return attached
                ? "Restored and attached."
                : "Restored headless — attach when ready."
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

// MARK: - Note line

/// The session note, drawn the way the roster draws it — orange rule, warm
/// rounded text — so one note reads as the same object wherever it surfaces.
private struct RestoreNoteLine: View {
    let note: String

    var body: some View {
        HStack(spacing: 5) {
            Capsule(style: .continuous)
                .fill(HolyGhosttyTheme.noteAccent.opacity(0.58))
                .frame(width: 3, height: 10)

            Text(note)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(HolyGhosttyTheme.noteAccent.opacity(0.82))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

// MARK: - Candidate picker

private struct CandidatePicker: View {
    /// Which row is being answered. The popover floats away from its row and
    /// every candidate here looks like every other, so the question needs to
    /// name the session it is about — the note especially, since two rows in
    /// one worktree differ by nothing else.
    let rowTitle: String
    let rowNote: String?
    let candidates: [HolyRestoreResolveCandidate]
    let onPick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Which conversation was this session running?")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(HolyGhosttyTheme.textPrimary)

                Text(rowTitle)
                    .font(.system(size: 10))
                    .foregroundStyle(HolyGhosttyTheme.textSecondary)
                    .lineLimit(1)

                if let rowNote {
                    RestoreNoteLine(note: rowNote)
                }
            }

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

/// Bar above the workspace after a cold boot: states this reboot's
/// interrupted count and offers the restore sheet as its one primary
/// action. Never launches anything itself. The mount pads below the
/// transparent-titlebar strip (mn-9a6145 D5a: flush to the top, the native
/// tab bar covered everything but the trailing button); the warning tint
/// and accent edge keep it findable in a stressed glance.
struct HolyRestoreBanner: View {
    let interruptedCount: Int
    let interruptedAt: Date?
    let onRestore: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.trianglebadge.exclamationmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(HolyGhosttyTheme.warning)

            Text(headline)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(HolyGhosttyTheme.textPrimary)

            if let interruptedAt {
                Text(interruptedAt.formatted(.relative(presentation: .named)))
                    .font(.system(size: 11))
                    .foregroundStyle(HolyGhosttyTheme.textSecondary)
            }

            Spacer()

            Button("Restore…", action: onRestore)
                .buttonStyle(HolyGhosttyProminentButtonStyle())

            // The bar's one labeled action is gold and to its left; dismiss
            // is the conventional X, so nothing competes with Restore.
            HolyGhosttyCloseButton(
                action: onDismiss,
                size: .compact,
                label: "Dismiss"
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(HolyGhosttyTheme.warning.opacity(0.10))
        .background(HolyGhosttyTheme.bgElevated)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(HolyGhosttyTheme.warning.opacity(0.55))
                .frame(height: 2)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(HolyGhosttyTheme.border)
                .frame(height: 0.5)
        }
    }

    private var headline: String {
        "\(interruptedCount) session\(interruptedCount == 1 ? "" : "s") interrupted by the last shutdown."
    }
}
