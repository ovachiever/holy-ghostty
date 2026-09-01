import AppKit
import SwiftUI

private enum HolyMannaBoardLayout {
    static let titlebarInset: CGFloat = 42
    static let estateHeight: CGFloat = 58
    static let sheetBarHeight: CGFloat = 38
    static let inspectorWidth: CGFloat = 390
    static let rowMinimumHeight: CGFloat = 58
}

struct HolyMannaBoardView: View {
    @ObservedObject var store: HolyMannaBoardModeStore
    let onDismiss: () -> Void
    let onFocusPeer: (String) -> Bool

    @State private var navigationMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            boardHeader
            estateHorizon
            sheetBar
            failureStrip
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HolyGhosttyTheme.bg)
        .onExitCommand(perform: onDismiss)
        .confirmationDialog(
            store.pendingMutation?.confirmationTitle ?? "Confirm Manna action",
            isPresented: Binding(
                get: { store.pendingMutation != nil },
                set: { if !$0 { store.pendingMutation = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let mutation = store.pendingMutation {
                Button(mutation.label, role: mutation.isDestructive ? .destructive : nil) {
                    store.confirmPendingMutation()
                }
            }
            Button("Cancel", role: .cancel) {
                store.pendingMutation = nil
            }
        } message: {
            Text(store.pendingMutation?.confirmationDetail ?? "")
        }
    }

    private var boardHeader: some View {
        HStack(spacing: 14) {
            Button(action: onDismiss) {
                Label("Terminal", systemImage: "chevron.backward")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(HolyGhosttyTheme.textSecondary)
            .help("Return to terminal (Escape)")

            Rectangle()
                .fill(HolyGhosttyTheme.borderActive)
                .frame(width: 1, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text("BOARD / \(store.boardName.uppercased())")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(HolyGhosttyTheme.textPrimary)

                HStack(spacing: 8) {
                    if let root = store.context.boardRoot {
                        Text(root)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("No board selected")
                    }
                    if let remoteHost = store.context.remoteHost {
                        Text("via \(remoteHost)")
                            .foregroundStyle(HolyGhosttyTheme.accent)
                    }
                }
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(HolyGhosttyTheme.textTertiary)
            }

            Spacer(minLength: 12)

            if let state = store.state {
                headerFact("\(state.total)", label: "items")
                headerFact("\(state.drift.count)", label: "drift", tint: state.drift.count > 0 ? HolyGhosttyTheme.warning : nil)
                headerFact(state.git.head ?? "none", label: state.git.branch ?? "git")
            }

            if store.isMutating {
                ProgressView()
                    .controlSize(.small)
                    .help("Manna action in progress")
            }

            Button {
                store.requestRefresh(force: true)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .rotationEffect(store.isRefreshing ? .degrees(360) : .zero)
                    .animation(
                        store.isRefreshing
                            ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                            : .default,
                        value: store.isRefreshing
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(HolyGhosttyTheme.textSecondary)
            .disabled(store.isRefreshing)
            .accessibilityLabel("Refresh Board and estate")
            .help("Refresh board and estate")
        }
        .padding(.top, HolyMannaBoardLayout.titlebarInset)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .background(HolyGhosttyTheme.bgElevated)
        .overlay(alignment: .bottom) {
            Rectangle().fill(HolyGhosttyTheme.border).frame(height: 1)
        }
    }

    private var estateHorizon: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                if store.sortedEstateBoards.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                        Text(store.estateFailure ?? "Reading registered boards…")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(store.estateFailure == nil ? HolyGhosttyTheme.textTertiary : HolyGhosttyTheme.warning)
                    .padding(.horizontal, 16)
                } else {
                    ForEach(store.sortedEstateBoards) { board in
                        estateBoardButton(board)
                    }
                }
            }
            .frame(minHeight: HolyMannaBoardLayout.estateHeight)
        }
        .frame(height: HolyMannaBoardLayout.estateHeight)
        .background(HolyGhosttyTheme.bg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(HolyGhosttyTheme.border).frame(height: 1)
        }
    }

    private func estateBoardButton(_ board: HolyMannaEstateBoard) -> some View {
        let isSelected = board.root == store.context.boardRoot
        return Button {
            store.selectEstateBoard(board)
        } label: {
            HStack(alignment: .bottom, spacing: 9) {
                VStack(spacing: 2) {
                    Spacer(minLength: 0)
                    Rectangle()
                        .fill(board.needsYou > 0 ? HolyGhosttyTheme.halo : HolyGhosttyTheme.accentSoft)
                        .frame(
                            width: 3,
                            height: min(34, CGFloat(max(1, board.needsYou * 9 + board.activeCount * 3)))
                        )
                }
                .frame(height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(board.name)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? HolyGhosttyTheme.textPrimary : HolyGhosttyTheme.textSecondary)
                        .lineLimit(1)

                    HStack(spacing: 7) {
                        if board.needsYou > 0 {
                            Text("\(board.needsYou) ask\(board.needsYou == 1 ? "" : "s")")
                                .foregroundStyle(HolyGhosttyTheme.halo)
                        }
                        Text("\(board.activeCount) live")
                        Text("\(board.total) total")
                    }
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .frame(height: HolyMannaBoardLayout.estateHeight)
            .background(isSelected ? HolyGhosttyTheme.bgSurface.opacity(0.72) : Color.clear)
            .overlay(alignment: .trailing) {
                Rectangle().fill(HolyGhosttyTheme.border).frame(width: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isSelected ? HolyGhosttyTheme.halo : Color.clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
        .help("\(board.name): \(board.needsYou) need you, \(board.activeCount) active, \(board.driftCount) drift")
    }

    private var sheetBar: some View {
        HStack(spacing: 2) {
            ForEach(HolyMannaBoardSheet.allCases) { sheet in
                Button {
                    store.selectSheet(sheet)
                } label: {
                    HStack(spacing: 6) {
                        Text(sheet.title)
                        let count = count(for: sheet)
                        if count > 0 {
                            Text("\(count)")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(sheet == .asks && count > 0 ? HolyGhosttyTheme.halo : HolyGhosttyTheme.textTertiary)
                        }
                    }
                    .font(.system(size: 11, weight: store.selectedSheet == sheet ? .semibold : .medium))
                    .foregroundStyle(store.selectedSheet == sheet ? HolyGhosttyTheme.textPrimary : HolyGhosttyTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .frame(height: HolyMannaBoardLayout.sheetBarHeight)
                    .background(store.selectedSheet == sheet ? HolyGhosttyTheme.bgSurface : Color.clear)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(store.selectedSheet == sheet ? HolyGhosttyTheme.halo : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 8)

            if let refreshed = store.lastRefreshedAt {
                Text("read \(refreshed.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
                    .padding(.trailing, 12)
            }
        }
        .frame(height: HolyMannaBoardLayout.sheetBarHeight)
        .background(HolyGhosttyTheme.bgElevated)
        .overlay(alignment: .bottom) {
            Rectangle().fill(HolyGhosttyTheme.border).frame(height: 1)
        }
    }

    @ViewBuilder
    private var failureStrip: some View {
        let messages = [store.mutationFailure, store.mutationMessage, navigationMessage]
            .compactMap { $0 }
        if let message = messages.first {
            HStack(spacing: 8) {
                Image(systemName: store.mutationFailure == nil ? "checkmark.circle" : "exclamationmark.triangle")
                Text(message)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Button("Dismiss") {
                    navigationMessage = nil
                    store.clearNotice()
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(store.mutationFailure == nil ? HolyGhosttyTheme.success : HolyGhosttyTheme.warning)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(HolyGhosttyTheme.bgSurface)
            .overlay(alignment: .bottom) {
                Rectangle().fill(HolyGhosttyTheme.border).frame(height: 1)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.state == nil {
            boardUnavailable
        } else {
            HStack(spacing: 0) {
                sheetContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Rectangle()
                    .fill(HolyGhosttyTheme.borderActive)
                    .frame(width: 1)

                inspector
                    .frame(width: HolyMannaBoardLayout.inspectorWidth)
                    .frame(maxHeight: .infinity)
                    .background(HolyGhosttyTheme.bgElevated)
            }
        }
    }

    private var boardUnavailable: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(HolyGhosttyTheme.warning)
            Text(store.context.boardRoot == nil ? "Choose a board" : "Board unavailable")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(HolyGhosttyTheme.textPrimary)
            Text(store.boardFailure ?? "Choose a registered board from the estate horizon above.")
                .font(.system(size: 11))
                .foregroundStyle(HolyGhosttyTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            if store.isRefreshing {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    @ViewBuilder
    private var sheetContent: some View {
        switch store.selectedSheet {
        case .asks:
            asksSheet
        case .coordination:
            coordinationSheet
        default:
            itemSheet
        }
    }

    private var itemSheet: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(store.itemSections) { section in
                    Section {
                        if section.items.isEmpty {
                            emptySheet
                        } else {
                            ForEach(section.items) { item in
                                itemRow(item)
                            }
                        }
                    } header: {
                        if let title = section.title {
                            sheetSectionHeader(title, count: section.items.count)
                        }
                    }
                }
            }
        }
        .background(HolyGhosttyTheme.bg)
    }

    private var asksSheet: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let asks = store.state?.asks, !asks.isEmpty {
                    ForEach(asks) { ask in
                        askRow(ask)
                    }
                } else {
                    emptySheet
                }
            }
        }
        .background(HolyGhosttyTheme.bg)
    }

    private var coordinationSheet: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                if let state = store.state {
                    Section {
                        ForEach(state.peers) { peer in peerRow(peer) }
                    } header: {
                        sheetSectionHeader("Peers", count: state.peers.count)
                    }

                    Section {
                        ForEach(state.coord.claims) { claim in claimRow(claim) }
                        ForEach(state.coord.needs) { need in needRow(need) }
                        ForEach(state.coord.drops) { drop in dropRow(drop) }
                    } header: {
                        sheetSectionHeader(
                            "Shared state",
                            count: state.coord.claims.count + state.coord.needs.count + state.coord.drops.count
                        )
                    }
                }
            }
        }
        .background(HolyGhosttyTheme.bg)
    }

    private func itemRow(_ item: HolyMannaBoardItem) -> some View {
        let selected = store.selectedItemID == item.id
        return Button {
            store.selectItem(item.id)
        } label: {
            HStack(spacing: 12) {
                Rectangle()
                    .fill(statusColor(item.effective))
                    .frame(width: 3)

                Text(item.order.map { String(format: "%02d", $0 + 1) } ?? "··")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
                    .frame(width: 24, alignment: .trailing)

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.titlePlain)
                        .font(.system(size: 12, weight: selected ? .semibold : .medium))
                        .foregroundStyle(HolyGhosttyTheme.textPrimary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 8) {
                        Text(item.id)
                        Text(item.effective)
                            .foregroundStyle(statusColor(item.effective))
                        if let claimant = item.claimant {
                            Text(claimant.label)
                                .foregroundStyle(attentionColor(claimant.attention))
                        } else if !item.blockers.isEmpty {
                            Text("\(item.blockers.count) blocker\(item.blockers.count == 1 ? "" : "s")")
                                .foregroundStyle(HolyGhosttyTheme.warning)
                        }
                    }
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
                }

                if !item.commits.isEmpty {
                    Text("\(item.commits.count) commit\(item.commits.count == 1 ? "" : "s")")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(HolyGhosttyTheme.success)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(selected ? HolyGhosttyTheme.halo : HolyGhosttyTheme.textTertiary)
            }
            .padding(.trailing, 12)
            .frame(minHeight: HolyMannaBoardLayout.rowMinimumHeight)
            .background(selected ? HolyGhosttyTheme.bgSurface.opacity(0.72) : Color.clear)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle().fill(HolyGhosttyTheme.border).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func askRow(_ ask: HolyMannaAsk) -> some View {
        HStack(spacing: 12) {
            Text(ask.kind.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(askColor(ask))
                .frame(width: 76, alignment: .leading)

            Button {
                follow(ask.target)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ask.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(HolyGhosttyTheme.textPrimary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let detail = ask.detail {
                        Text(detail)
                            .font(.system(size: 10))
                            .foregroundStyle(HolyGhosttyTheme.textTertiary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .buttonStyle(.plain)

            if let action = ask.action {
                Button(ask.verb) {
                    store.requestMutation(action)
                }
                .buttonStyle(HolyGhosttyActionButtonStyle())
                .disabled(store.isMutating)
            } else {
                Text(ask.verb)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(askColor(ask))
                    .frame(minWidth: 54, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(minHeight: HolyMannaBoardLayout.rowMinimumHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(HolyGhosttyTheme.border).frame(height: 1)
        }
    }

    private func peerRow(_ peer: HolyMannaPeer) -> some View {
        Button {
            focusPeer(peer.agentID)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(attentionColor(peer.attention))
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(peer.displayName)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(HolyGhosttyTheme.textPrimary)
                        Text(peer.runtime ?? "agent")
                        Text(peer.status)
                    }
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)

                    Text(peer.pulse?.activity ?? peer.goal ?? "No focus declared")
                        .font(.system(size: 10))
                        .foregroundStyle(HolyGhosttyTheme.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)
                Text(peer.age ?? "")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
                Image(systemName: "arrow.turn.down.right")
                    .foregroundStyle(HolyGhosttyTheme.accent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle().fill(HolyGhosttyTheme.border).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
        .help("Focus the Holy session joined by harness identity")
    }

    private func claimRow(_ claim: HolyMannaCoordClaim) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: claim.contended ? "exclamationmark.triangle.fill" : "lock.open")
                .foregroundStyle(claim.contended ? HolyGhosttyTheme.warning : HolyGhosttyTheme.textTertiary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 4) {
                Text(claim.path)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(HolyGhosttyTheme.textPrimary)
                Text("\(claim.ownerAlias ?? claim.owner) · \(claim.reason ?? "claimed")")
                    .font(.system(size: 10))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(HolyGhosttyTheme.border).frame(height: 1) }
    }

    private func needRow(_ need: HolyMannaCoordNeed) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.down.to.line")
                .foregroundStyle(HolyGhosttyTheme.halo)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 4) {
                Text(need.key)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(HolyGhosttyTheme.textPrimary)
                Text(need.why ?? "Dependency declared")
                    .font(.system(size: 10))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(HolyGhosttyTheme.border).frame(height: 1) }
    }

    private func dropRow(_ drop: HolyMannaCoordDrop) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.text")
                .foregroundStyle(HolyGhosttyTheme.accent)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 4) {
                Text(drop.paths.isEmpty ? "Published note" : drop.paths.joined(separator: ", "))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(HolyGhosttyTheme.textPrimary)
                Text(drop.note ?? "No note")
                    .font(.system(size: 10))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(HolyGhosttyTheme.border).frame(height: 1) }
    }

    @ViewBuilder
    private var inspector: some View {
        if let item = store.selectedItem {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    inspectorTitle(item)
                    inspectorDigest
                    inspectorBody(item)
                    inspectorFacts(item)
                    inspectorActions(item)
                }
            }
        } else {
            HolyGhosttyEmptyStateView(
                title: "Nothing selected",
                subtitle: "Choose a board row to inspect its source, blockers, claimant, commits, and handoff.",
                symbol: "sidebar.right"
            )
            .frame(maxHeight: .infinity)
        }
    }

    private func inspectorTitle(_ item: HolyMannaBoardItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(item.id)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(HolyGhosttyTheme.halo)
                Spacer(minLength: 8)
                Text(item.effective.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(statusColor(item.effective))
            }

            Text(item.titlePlain)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(HolyGhosttyTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("Copy ID") { copy(item.id) }
                if let prompt = item.prompt {
                    Button("Copy handoff") { copy(prompt) }
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(HolyGhosttyTheme.accent)
        }
        .padding(16)
        .overlay(alignment: .bottom) { Rectangle().fill(HolyGhosttyTheme.border).frame(height: 1) }
    }

    private var inspectorDigest: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("AI DIGEST")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
                Spacer(minLength: 8)
                if let model = store.digestModel {
                    Text("\(model)\(store.digestWasCached ? " · cached" : "")")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(HolyGhosttyTheme.textTertiary)
                }
            }

            if store.isDigestLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text("Reading the item through Holy's fast role…")
                }
                .foregroundStyle(HolyGhosttyTheme.textSecondary)
            } else if let digest = store.digestText {
                Text(digest)
                    .foregroundStyle(HolyGhosttyTheme.textPrimary)
                    .textSelection(.enabled)
            } else {
                Text(store.digestFailure ?? "No digest available.")
                    .foregroundStyle(store.digestFailure == nil ? HolyGhosttyTheme.textTertiary : HolyGhosttyTheme.warning)
            }
        }
        .font(.system(size: 11))
        .padding(16)
        .background(HolyGhosttyTheme.halo.opacity(0.035))
        .overlay(alignment: .leading) {
            Rectangle().fill(HolyGhosttyTheme.halo.opacity(0.65)).frame(width: 2)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(HolyGhosttyTheme.border).frame(height: 1) }
    }

    private func inspectorBody(_ item: HolyMannaBoardItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            inspectorLabel("BODY")
            Text(item.description ?? "No body supplied.")
                .font(.system(size: 11))
                .foregroundStyle(HolyGhosttyTheme.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .overlay(alignment: .bottom) { Rectangle().fill(HolyGhosttyTheme.border).frame(height: 1) }
    }

    private func inspectorFacts(_ item: HolyMannaBoardItem) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            inspectorLabel("LEDGER")
            if let track = item.track {
                factRow("track", value: "\(track) · \(item.trackTitle ?? "")")
            }
            if let claimant = item.claimant {
                HStack(alignment: .top, spacing: 10) {
                    factKey("claimant")
                    Button {
                        focusPeer(claimant.label)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(claimant.label)
                            Text("\(claimant.liveness) · \(claimant.attention)")
                                .foregroundStyle(attentionColor(claimant.attention))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(HolyGhosttyTheme.textPrimary)
                }
            }
            if !item.blockers.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    factKey("blockers")
                    ForEach(item.blockers) { blocker in
                        HStack(alignment: .top, spacing: 7) {
                            Circle().fill(statusColor(blocker.status)).frame(width: 6, height: 6).padding(.top, 4)
                            Text("\(blocker.id) · \(blocker.title)")
                                .foregroundStyle(HolyGhosttyTheme.textSecondary)
                        }
                    }
                }
            }
            if !item.commits.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    factKey("commits")
                    ForEach(item.commits) { commit in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(commit.sha)
                                .foregroundStyle(HolyGhosttyTheme.success)
                            Text(commit.subject)
                                .foregroundStyle(HolyGhosttyTheme.textSecondary)
                        }
                    }
                }
            }
            if let prompt = item.prompt { factRow("handoff", value: prompt) }
            if let source = item.source { factRow("source", value: source) }
            if let updatedAt = item.updatedAt { factRow("updated", value: updatedAt) }
        }
        .font(.system(size: 10, design: .monospaced))
        .padding(16)
        .overlay(alignment: .bottom) { Rectangle().fill(HolyGhosttyTheme.border).frame(height: 1) }
    }

    @ViewBuilder
    private func inspectorActions(_ item: HolyMannaBoardItem) -> some View {
        let mutations = store.availableMutations(for: item)
        if !mutations.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                inspectorLabel("ACTIONS")
                Text("Every action asks first, then runs the real CLI under \(store.actorID ?? "Holy's private actor").")
                    .font(.system(size: 10))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)

                FlowLayout(spacing: 7) {
                    ForEach(mutations) { mutation in
                        Button(mutation.label) {
                            store.requestMutation(mutation)
                        }
                        .buttonStyle(HolyGhosttyActionButtonStyle())
                        .disabled(store.isMutating)
                    }
                }
            }
            .padding(16)
        }
    }

    private var emptySheet: some View {
        HolyGhosttyEmptyStateView(
            title: "Nothing here",
            subtitle: "This sheet is empty in canonical Manna state.",
            symbol: "checkmark"
        )
        .frame(minHeight: 240)
    }

    private func sheetSectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title.uppercased())
            Spacer(minLength: 0)
            Text("\(count)")
        }
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .tracking(0.6)
        .foregroundStyle(HolyGhosttyTheme.textTertiary)
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(HolyGhosttyTheme.bgElevated.opacity(0.98))
        .overlay(alignment: .bottom) { Rectangle().fill(HolyGhosttyTheme.border).frame(height: 1) }
    }

    private func count(for sheet: HolyMannaBoardSheet) -> Int {
        guard let state = store.state else { return 0 }
        switch sheet {
        case .now: return state.now.count
        case .next: return state.next.count
        case .waves: return state.waves.reduce(0) { $0 + $1.items.count }
        case .asks: return state.asks.count
        case .coordination:
            return state.peers.count
                + state.coord.claims.count
                + state.coord.needs.count
                + state.coord.drops.count
        case .dreams: return state.dreams.count
        case .decisions: return state.decisions.count
        }
    }

    private func follow(_ target: HolyMannaAsk.Target) {
        switch target {
        case let .item(id):
            store.selectItem(id)
        case let .peer(id):
            focusPeer(id)
        case let .sheet(sheet):
            store.selectSheet(sheet)
        }
    }

    private func focusPeer(_ identity: String) {
        if onFocusPeer(identity) {
            onDismiss()
        } else {
            navigationMessage = "No unique Holy session currently proves the harness identity \(identity)."
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        navigationMessage = "Copied \(text)."
    }

    private func headerFact(_ value: String, label: String, tint: Color? = nil) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint ?? HolyGhosttyTheme.textPrimary)
            Text(label)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(HolyGhosttyTheme.textTertiary)
        }
    }

    private func inspectorLabel(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(HolyGhosttyTheme.textTertiary)
    }

    private func factKey(_ value: String) -> some View {
        Text(value)
            .foregroundStyle(HolyGhosttyTheme.textTertiary)
            .frame(width: 66, alignment: .leading)
    }

    private func factRow(_ key: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            factKey(key)
            Text(value)
                .foregroundStyle(HolyGhosttyTheme.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "active", "in_progress", "working": HolyGhosttyTheme.success
        case "ready", "open": HolyGhosttyTheme.accent
        case "waiting", "blocked": HolyGhosttyTheme.warning
        case "decision", "needs-user": HolyGhosttyTheme.halo
        case "failed": HolyGhosttyTheme.danger
        case "done", "finished": HolyGhosttyTheme.textTertiary
        case "dream": HolyGhosttyTheme.noteAccent
        default: HolyGhosttyTheme.textTertiary
        }
    }

    private func attentionColor(_ attention: String) -> Color {
        switch attention {
        case "needs-user": HolyGhosttyTheme.halo
        case "failed": HolyGhosttyTheme.danger
        case "working", "present": HolyGhosttyTheme.success
        case "finished": HolyGhosttyTheme.textPrimary
        default: HolyGhosttyTheme.textTertiary
        }
    }

    private func askColor(_ ask: HolyMannaAsk) -> Color {
        switch ask.kind {
        case "peer", "decision": HolyGhosttyTheme.halo
        case "failed": HolyGhosttyTheme.danger
        case "landed", "ready": HolyGhosttyTheme.success
        case "contention", "dream": HolyGhosttyTheme.warning
        default: HolyGhosttyTheme.textTertiary
        }
    }
}

/// Small wrapping layout for confirmation-gated inspector verbs. Actions are
/// words, not icon riddles, and this keeps them readable at narrow widths.
private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        HStack(spacing: spacing) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
