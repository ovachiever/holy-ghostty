import SwiftUI

struct HolyNewSessionSheet: View {
    @Binding var draft: HolySessionDraft
    let templates: [HolySessionTemplate]
    let ownershipPreview: HolySessionOwnership?
    let launchGuardrail: HolyLaunchGuardrail
    let isCheckingLaunchOwnership: Bool
    let errorMessage: String?
    let isBusy: Bool
    let onApplyTemplate: (HolySessionTemplate) -> Void
    let onDraftChanged: () -> Void
    let onSaveTemplate: () -> Void
    let onCreate: () -> Void
    let onCancel: () -> Void

    @State private var environmentText: String = ""
    @State private var previousRuntime: HolySessionRuntime?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetHeader

            Rectangle()
                .fill(HolyGhosttyTheme.border)
                .frame(height: 0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    templateStrip
                    taskSection
                    executionSection
                    runtimePicker
                    labeledField("Title", text: $draft.title, placeholder: "Untitled Session")
                    labeledField("Mission", text: $draft.objective, placeholder: "What should this session accomplish?")
                    workspaceSection
                    budgetSection
                    guardrailSection
                    commandSection
                    initialInputSection
                    environmentSection
                }
                .padding(16)
            }

            Rectangle()
                .fill(HolyGhosttyTheme.border)
                .frame(height: 0.5)

            footerBar
        }
        .background(HolyGhosttyTheme.bg)
        .onAppear {
            if environmentText.isEmpty {
                environmentText = Self.renderEnvironment(draft.environment)
            }
            adoptSuggestedCommand(from: nil, to: draft.runtime)
            previousRuntime = draft.runtime
            onDraftChanged()
        }
        .onChange(of: environmentText) { newValue in
            draft.environment = Self.parseEnvironment(newValue)
        }
        .onChange(of: draft.environment) { newValue in
            if environmentText.isEmpty {
                environmentText = Self.renderEnvironment(newValue)
            }
        }
        .onChange(of: draft.workspaceStrategy) { strategy in
            if strategy == .createManagedWorktree && draft.repositoryRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.repositoryRoot = draft.workingDirectory
            }
        }
        .onChange(of: draft.transportKind) { kind in
            if kind == .ssh {
                draft.workspaceStrategy = .directDirectory
            }
        }
        .onChange(of: draft.runtime) { newRuntime in
            adoptSuggestedCommand(from: previousRuntime, to: newRuntime)
            previousRuntime = newRuntime
        }
        .onChange(of: draft) { _ in onDraftChanged() }
    }

    // MARK: - Header

    private var sheetHeader: some View {
        HStack {
            Text("Create Session")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(HolyGhosttyTheme.halo)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(HolyGhosttyTheme.bgElevated)
    }

    // MARK: - Template Strip

    private var templateStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Templates")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(templates) { template in
                        Button {
                            onApplyTemplate(template)
                            environmentText = Self.renderEnvironment(template.launchSpec.environment)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(template.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(HolyGhosttyTheme.textPrimary)
                                    .lineLimit(1)

                                Text(template.runtime.displayName)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(templateTint(template))
                            }
                            .frame(width: 120, alignment: .leading)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(HolyGhosttyTheme.bgSurface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(HolyGhosttyTheme.border, lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Runtime

    private var executionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Execution")

            Picker("Transport", selection: $draft.transportKind) {
                ForEach(HolySessionTransportKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            if draft.transportKind == .ssh {
                HStack(spacing: 10) {
                    labeledField("Host Label", text: $draft.remoteHostLabel, placeholder: "studio")
                    labeledField("SSH Destination", text: $draft.remoteHostDestination, placeholder: "studio")
                }

                helperText("Remote sessions attach through SSH and currently treat workspace ownership as direct-directory only.")
            } else {
                helperText("Holy launches local sessions through tmux so they remain attachable after the app closes.")
            }

            HStack(spacing: 10) {
                labeledField("Tmux Socket", text: $draft.tmuxSocketName, placeholder: HolySessionTmuxSpec.defaultSocketName)
                labeledField("Tmux Session", text: $draft.tmuxSessionName, placeholder: "Automatic")
            }

            Toggle("Create tmux session if missing", isOn: $draft.tmuxCreateIfMissing)
                .font(.system(size: 11))
                .tint(HolyGhosttyTheme.accent)
        }
    }

    @ViewBuilder
    private var taskSection: some View {
        if let linkedTask = draft.linkedTask {
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("Task")
                helperText(
                    "\(linkedTask.sourceSummary) · \(linkedTask.title)",
                    tint: HolyGhosttyTheme.halo
                )

                let summary = (linkedTask.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 10))
                        .foregroundStyle(HolyGhosttyTheme.textSecondary)
                }
            }
        }
    }

    private var runtimePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Runtime")

            Picker("Runtime", selection: $draft.runtime) {
                ForEach(HolySessionRuntime.allCases) { runtime in
                    Text(runtime.displayName).tag(runtime)
                }
            }
            .pickerStyle(.segmented)

            Text(currentAdapter.runtimeDescription)
                .font(.system(size: 10))
                .foregroundStyle(HolyGhosttyTheme.textTertiary)
        }
    }

    // MARK: - Workspace

    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Workspace Strategy")

            if draft.transportKind == .ssh {
                labeledField(
                    "Remote Directory",
                    text: $draft.workingDirectory,
                    placeholder: "/Users/you/project"
                )

                Text("Remote tmux launches use the provided path as the tmux working directory when a new session has to be created.")
                    .font(.system(size: 10))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
            } else {
                Picker("Workspace Strategy", selection: $draft.workspaceStrategy) {
                    ForEach(HolySessionWorkspaceStrategy.allCases) { strategy in
                        Text(strategy.displayName).tag(strategy)
                    }
                }
                .pickerStyle(.segmented)

                Text(draft.workspaceStrategy.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)

                if draft.workspaceStrategy == .createManagedWorktree {
                    labeledField("Repository Root", text: $draft.repositoryRoot, placeholder: "/Users/you/project")
                    labeledField("Managed Branch", text: $draft.branchName, placeholder: "holy/feature-name")

                    if let predictedPath = HolyWorktreeManager.predictedManagedWorktreePath(
                        repositoryRoot: draft.repositoryRoot,
                        branchName: draft.branchName,
                        runtime: draft.runtime,
                        title: draft.title
                    ) {
                        helperText("Worktree: \(predictedPath)")
                    }
                } else {
                    labeledField(
                        draft.workspaceStrategy == .attachExistingWorktree ? "Existing Worktree" : "Working Directory",
                        text: $draft.workingDirectory,
                        placeholder: "/Users/you/project"
                    )
                }
            }

            if let ownershipPreview {
                helperText(ownershipPreviewText(for: ownershipPreview), tint: ownershipPreviewTint(for: ownershipPreview))
            }
        }
    }

    // MARK: - Guardrails

    private var budgetSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Budget")

            HStack(spacing: 10) {
                labeledField("Token Limit", text: $draft.tokenBudget, placeholder: "25000")
                labeledField("Cost Limit USD", text: $draft.costBudgetUSD, placeholder: "15")
            }

            let hasBudget = draft.budget != nil
            if hasBudget {
                Picker("Budget Policy", selection: $draft.budgetEnforcementPolicy) {
                    ForEach(HolySessionBudgetEnforcementPolicy.allCases, id: \.self) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }
                .pickerStyle(.segmented)

                helperText(budgetSummaryText)
            } else {
                Text("Optional. Use this to set hard expectations for agent spend.")
                    .font(.system(size: 9))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
            }

            if !draft.hasValidBudgetInput {
                helperText("Budget values must be numeric.", tint: HolyGhosttyTheme.danger)
            }
        }
    }

    @ViewBuilder
    private var guardrailSection: some View {
        if isCheckingLaunchOwnership {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking ownership...")
                    .font(.system(size: 10))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
            }
        } else if !launchGuardrail.isClear {
            VStack(alignment: .leading, spacing: 6) {
                Text(launchGuardrail.headline)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(launchGuardrailTint)

                Text(launchGuardrail.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(HolyGhosttyTheme.textSecondary)

                ForEach(launchGuardrail.conflicts) { conflict in
                    helperText(
                        "\(conflict.severity.displayName): \(conflict.headline)",
                        tint: conflict.severity == .blocking ? HolyGhosttyTheme.danger : HolyGhosttyTheme.warning
                    )
                }

                if launchGuardrail.requiresOverride {
                    Toggle(launchGuardrail.overrideLabel, isOn: $draft.allowOwnershipCollision)
                        .tint(HolyGhosttyTheme.warning)
                        .font(.system(size: 11))
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(launchGuardrailTint.opacity(0.06))
            )
        }
    }

    // MARK: - Command

    private var commandSection: some View {
        labeledField(
            "Command",
            text: $draft.command,
            placeholder: currentAdapter.recommendedCommand ?? "Interactive shell"
        )
    }

    // MARK: - Initial Input

    private var initialInputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Initial Input")

            TextEditor(text: $draft.initialInput)
                .font(.system(size: 11, design: .monospaced))
                .frame(minHeight: 80)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(HolyGhosttyTheme.bgSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(HolyGhosttyTheme.border, lineWidth: 0.5)
                )

            Toggle("Wait after command exits", isOn: $draft.waitAfterCommand)
                .font(.system(size: 11))
                .tint(HolyGhosttyTheme.accent)
        }
    }

    // MARK: - Environment

    private var environmentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Environment")

            TextEditor(text: $environmentText)
                .font(.system(size: 11, design: .monospaced))
                .frame(minHeight: 60)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(HolyGhosttyTheme.bgSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(HolyGhosttyTheme.border, lineWidth: 0.5)
                )

            Text("KEY=VALUE per line")
                .font(.system(size: 9))
                .foregroundStyle(HolyGhosttyTheme.textTertiary)
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(HolyGhosttyTheme.danger)
                    .lineLimit(2)
            }

            if isBusy {
                ProgressView().controlSize(.small)
                Text("Preparing...")
                    .font(.system(size: 10))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
            }

            Spacer()

            Button("Cancel", action: onCancel)
                .buttonStyle(HolyGhosttyActionButtonStyle())
                .disabled(isBusy)

            Button("Save Template") {
                syncEnvironment()
                onSaveTemplate()
            }
            .buttonStyle(HolyGhosttyActionButtonStyle())
            .disabled(isBusy || !canSaveTemplate)

            Button {
                syncEnvironment()
                onCreate()
            } label: {
                Text(isBusy ? "Preparing..." : "Launch")
            }
            .buttonStyle(HolyGhosttyActionButtonStyle())
            .disabled(!canCreate)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(HolyGhosttyTheme.bgElevated)
    }

    // MARK: - Primitives

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(HolyGhosttyTheme.textTertiary)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private func labeledField(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel(title)

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(HolyGhosttyTheme.bgSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(HolyGhosttyTheme.border, lineWidth: 0.5)
                )
                .foregroundStyle(HolyGhosttyTheme.textPrimary)
        }
    }

    private func helperText(_ text: String, tint: Color = HolyGhosttyTheme.accent) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Logic

    private var canCreate: Bool {
        let hasTitle = !draft.launchSpec.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !hasTitle || isBusy || isCheckingLaunchOwnership || !draft.hasValidBudgetInput { return false }

        let hasRequiredWorkspaceFields: Bool
        if draft.transportKind == .ssh {
            hasRequiredWorkspaceFields = draft.remoteHostDestination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        } else {
            switch draft.workspaceStrategy {
            case .directDirectory, .attachExistingWorktree:
                hasRequiredWorkspaceFields = !draft.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .createManagedWorktree:
                hasRequiredWorkspaceFields = !draft.repositoryRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
        guard hasRequiredWorkspaceFields else { return false }
        return launchGuardrail.allowsLaunch(allowOverride: draft.allowOwnershipCollision)
    }

    private var canSaveTemplate: Bool {
        !draft.launchSpec.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var currentAdapter: HolySessionAdapter {
        HolySessionAdapterRegistry.adapter(for: draft.runtime)
    }

    private var launchGuardrailTint: Color {
        launchGuardrail.hasBlockingConflict ? HolyGhosttyTheme.danger : HolyGhosttyTheme.warning
    }

    private func adoptSuggestedCommand(from previousRuntime: HolySessionRuntime?, to newRuntime: HolySessionRuntime) {
        let trimmed = draft.command.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousSuggested = previousRuntime
            .flatMap { HolySessionAdapterRegistry.adapter(for: $0).recommendedCommand }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let newSuggested = HolySessionAdapterRegistry.adapter(for: newRuntime).recommendedCommand ?? ""
        if trimmed.isEmpty || (previousSuggested != nil && trimmed == previousSuggested) {
            draft.command = newSuggested
        }
    }

    private func syncEnvironment() {
        draft.environment = Self.parseEnvironment(environmentText)
    }

    private func templateTint(_ template: HolySessionTemplate) -> Color {
        switch template.runtime {
        case .shell:    return HolyGhosttyTheme.accentSoft
        case .claude:   return HolyGhosttyTheme.halo
        case .codex:    return HolyGhosttyTheme.accent
        case .opencode: return HolyGhosttyTheme.success
        }
    }

    private func ownershipPreviewTint(for ownership: HolySessionOwnership) -> Color {
        switch ownership.source {
        case .managedWorktree:  return HolyGhosttyTheme.accent
        case .attachedWorktree: return HolyGhosttyTheme.warning
        case .directDirectory:  return HolyGhosttyTheme.accentSoft
        }
    }

    private func ownershipPreviewText(for ownership: HolySessionOwnership) -> String {
        [
            "\(ownership.source.displayName): \(ownership.summary)",
            "Branch: \(ownership.branchDisplayName)",
        ].joined(separator: " · ")
    }

    private var budgetSummaryText: String {
        var components: [String] = []
        if let tokenLimit = draft.budget?.tokenLimit {
            components.append("\(tokenLimit.formatted(.number.grouping(.automatic))) tokens")
        }
        if let costLimitUSD = draft.budget?.costLimitUSD {
            components.append(String(format: "$%.2f", costLimitUSD))
        }
        if draft.budget != nil {
            components.append(draft.budgetEnforcementPolicy.displayName)
        }
        return components.joined(separator: " · ")
    }

    static func parseEnvironment(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            result[key] = value
        }
        return result
    }

    static func renderEnvironment(_ environment: [String: String]) -> String {
        environment
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n")
    }
}
