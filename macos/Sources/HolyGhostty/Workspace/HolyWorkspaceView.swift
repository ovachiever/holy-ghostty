import SwiftUI
import GhosttyKit

struct HolyWorkspaceRootView: View {
    @EnvironmentObject private var ghostty: Ghostty.App
    @ObservedObject var store: HolyWorkspaceStore

    var body: some View {
        ZStack {
            HolyGhosttyBackdrop()

            VStack(spacing: 0) {
                header

                Rectangle()
                    .fill(HolyGhosttyTheme.border)
                    .frame(height: 0.5)

                HSplitView {
                    HolySessionRosterView(store: store)
                        .frame(minWidth: 220, idealWidth: 320, maxWidth: 440, maxHeight: .infinity)
                        .background(HolyGhosttyTheme.bgElevated)

                    HolySessionDetailView(
                        session: store.selectedSession,
                        coordination: store.selectedSession.map(store.coordination(for:)) ?? .empty,
                        ghosttyApp: ghostty
                    )
                    .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                    .background(HolyGhosttyTheme.bg)
                    .layoutPriority(1)

                    HolyContextPanelView(
                        session: store.selectedSession,
                        coordination: store.selectedSession.map(store.coordination(for:)) ?? .empty
                    )
                    .frame(minWidth: 220, idealWidth: 280, maxWidth: 360, maxHeight: .infinity)
                    .background(HolyGhosttyTheme.bgElevated)
                }
            }
        }
        .sheet(isPresented: $store.composerPresented) {
            HolyNewSessionSheet(
                draft: $store.draft,
                templates: store.availableTemplates,
                ownershipPreview: store.draftOwnershipPreview,
                launchGuardrail: store.draftLaunchGuardrail,
                isCheckingLaunchOwnership: store.draftLaunchGuardrailRefreshing,
                errorMessage: store.composerErrorMessage,
                isBusy: store.composerBusy,
                onApplyTemplate: { store.applyTemplateToDraft($0) },
                onDraftChanged: { store.refreshDraftLaunchGuardrail() },
                onSaveTemplate: { store.saveDraftAsTemplate() },
                onCreate: { store.createFromDraft() },
                onCancel: { store.composerPresented = false }
            )
            .frame(width: 560, height: 600)
        }
        .sheet(isPresented: $store.historyPresented) {
            HolySessionHistorySheet(store: store)
        }
        .onAppear(perform: focusSelectedSession)
        .onChange(of: store.selectedSessionID) { _ in focusSelectedSession() }
    }

    // MARK: - Header (thin bar: brand left, controls right)

    private var header: some View {
        HStack(spacing: 8) {
            Image("HolyGhosttyLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            Text("Holy Ghostty")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(HolyGhosttyTheme.halo)

            if !store.sessions.isEmpty {
                Text("\(store.sessions.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(HolyGhosttyTheme.bgSurface))
            }

            if conflictCount > 0 {
                HStack(spacing: 3) {
                    HolyGhosttyStatusDot(color: HolyGhosttyTheme.danger)
                    Text("\(conflictCount)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(HolyGhosttyTheme.danger)
                }
            }

            Button { store.presentComposer() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(HolyGhosttyActionButtonStyle())

            Spacer()

            Menu {
                Section("Templates") {
                    templateSection(title: "Built-In", templates: store.builtInTemplates)

                    if !store.savedTemplates.isEmpty {
                        Divider()
                        templateSection(title: "Saved", templates: store.savedTemplates)
                    }
                }

                Divider()

                Button { store.presentHistory() } label: {
                    Label("Session History", systemImage: "clock")
                }

                if let selected = store.selectedSession {
                    Divider()
                    Button("Duplicate Session") { store.duplicate(selected) }
                    Button("Archive Session") { store.close(selected) }
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(HolyGhosttyActionButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .background(HolyGhosttyTheme.bgElevated)
    }

    // MARK: - Helpers

    private func focusSelectedSession() {
        guard let session = store.selectedSession else { return }
        Ghostty.moveFocus(to: session.surfaceView)
    }

    private var conflictCount: Int {
        store.coordinationBySessionID.values.filter(\.hasBlockingConflict).count
    }

    @ViewBuilder
    private func templateSection(title: String, templates: [HolySessionTemplate]) -> some View {
        Section(title) {
            ForEach(templates) { template in
                Menu(template.name) {
                    Button("Launch Now") { store.launchTemplate(template) }
                    Button("Edit Before Launch") { store.presentComposer(using: template) }
                }
            }
        }
    }
}
