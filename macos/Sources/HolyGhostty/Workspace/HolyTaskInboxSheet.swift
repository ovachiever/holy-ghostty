import AppKit
import SwiftUI

struct HolyTaskInboxSheet: View {
    @ObservedObject var store: HolyWorkspaceStore
    @State private var searchText: String = ""
    @State private var editorTask: HolyExternalTaskRecord?

    private var filteredTasks: [HolyExternalTaskRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.externalTasks }

        let loweredQuery = query.lowercased()
        return store.externalTasks.filter { task in
            [
                task.title,
                task.summary,
                task.sourceLabel,
                task.externalID,
                task.canonicalURL,
                task.linkedSessionTitle,
            ]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(loweredQuery) }
        }
    }

    var body: some View {
        ZStack {
            HolyGhosttyBackdrop()

            VStack(spacing: 0) {
                header

                Rectangle()
                    .fill(HolyGhosttyTheme.border)
                    .frame(height: 0.5)

                HSplitView {
                    taskList
                        .frame(minWidth: 260, idealWidth: 320, maxWidth: 400, maxHeight: .infinity)
                        .background(HolyGhosttyTheme.bgElevated)

                    taskDetail
                        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                        .layoutPriority(1)
                }
            }
        }
        .frame(minWidth: 1040, minHeight: 700)
        .onAppear {
            ensureSelection()
            reloadEditor()
        }
        .onChange(of: store.selectedTaskID) { _ in reloadEditor() }
        .onChange(of: filteredTasks.map(\.id)) { _ in ensureSelection() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Task Inbox")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(HolyGhosttyTheme.halo)

            Text(store.taskCountText)
                .font(.system(size: 11))
                .foregroundStyle(HolyGhosttyTheme.textTertiary)

            Spacer()

            Button("New Task") { store.createTask() }
                .buttonStyle(HolyGhosttyActionButtonStyle())

            Button("Done") { store.tasksPresented = false }
                .buttonStyle(HolyGhosttyActionButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(HolyGhosttyTheme.bgElevated)
    }

    private var taskList: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(HolyGhosttyTheme.bgSurface)
                )
                .padding(.horizontal, 10)
                .padding(.top, 10)

            if filteredTasks.isEmpty {
                HolyGhosttyEmptyStateView(
                    title: store.externalTasks.isEmpty ? "No tasks yet" : "No matches",
                    subtitle: store.externalTasks.isEmpty
                        ? "Create external tasks here and launch sessions directly from them."
                        : "Try different terms.",
                    symbol: "checklist"
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredTasks) { task in
                            HolyTaskRow(
                                task: task,
                                isSelected: task.id == store.selectedTaskID,
                                onSelect: { store.selectedTaskID = task.id }
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

    private var taskDetail: some View {
        Group {
            if let editorTask {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(editorTask.title)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(HolyGhosttyTheme.textPrimary)

                            Text(editorTask.sourceSummary)
                                .font(.system(size: 12))
                                .foregroundStyle(HolyGhosttyTheme.textSecondary)
                        }

                        actionBar(task: editorTask)
                        statusSection(task: editorTask)
                        editorSection
                    }
                    .padding(16)
                }
                .scrollIndicators(.hidden)
            } else {
                HolyGhosttyEmptyStateView(
                    title: "No task selected",
                    subtitle: "Choose a task from the inbox.",
                    symbol: "checklist"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func actionBar(task: HolyExternalTaskRecord) -> some View {
        HStack(spacing: 6) {
            Button("Save", action: saveEditor)
                .buttonStyle(HolyGhosttyActionButtonStyle())

            Button("Launch") {
                saveEditor()
                if let savedTask = store.externalTasks.first(where: { $0.id == task.id }) {
                    store.launchTask(savedTask)
                    store.tasksPresented = false
                }
            }
            .buttonStyle(HolyGhosttyActionButtonStyle())

            if task.canonicalURL != nil {
                Button("Open Link") { open(task) }
                    .buttonStyle(HolyGhosttyActionButtonStyle())
            }

            Button("Delete") { store.deleteTask(task) }
                .buttonStyle(HolyGhosttyActionButtonStyle())

            Spacer()
        }
    }

    private func statusSection(task: HolyExternalTaskRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Status")
            detailRow("Task", task.status.displayName, color: statusColor(task.status))
            detailRow("Runtime", task.preferredRuntime.displayName)
            detailRow("Linked", task.linkedSessionSummary)
            if let canonicalURL = task.canonicalURL {
                detailRow("URL", canonicalURL)
            }
        }
    }

    private var editorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Task")

            labeledField("Title", text: editorBinding(\.title), placeholder: "Implement recovery UI")
            labeledField("Summary", text: editorBinding(\.summary), placeholder: "Short task objective")
            labeledField("URL", text: editorBinding(\.canonicalURL), placeholder: "https://github.com/org/repo/issues/123")

            HStack(spacing: 10) {
                labeledField("Working Directory", text: editorBinding(\.preferredWorkingDirectory), placeholder: "/path/to/repo")
                labeledField("Repository Root", text: editorBinding(\.preferredRepositoryRoot), placeholder: "/path/to/repo")
            }

            HStack(spacing: 10) {
                runtimePicker
                labeledField("Command", text: editorBinding(\.preferredCommand), placeholder: "codex")
            }

            labeledField("Initial Input", text: editorBinding(\.preferredInitialInput), placeholder: "Start with the failing tests.")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(HolyGhosttyTheme.bgElevated)
        )
    }

    private var runtimePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Runtime")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(HolyGhosttyTheme.textTertiary)

            Picker("Runtime", selection: editorRuntimeBinding) {
                ForEach(HolySessionRuntime.allCases) { runtime in
                    Text(runtime.displayName).tag(runtime)
                }
            }
            .pickerStyle(.menu)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var editorRuntimeBinding: Binding<HolySessionRuntime> {
        Binding(
            get: { editorTask?.preferredRuntime ?? .codex },
            set: { runtime in
                guard var editorTask else { return }
                editorTask.preferredRuntime = runtime
                self.editorTask = editorTask
            }
        )
    }

    private func editorBinding(_ keyPath: WritableKeyPath<HolyExternalTaskRecord, String?>) -> Binding<String> {
        Binding(
            get: { editorTask?[keyPath: keyPath] ?? "" },
            set: { value in
                guard var editorTask else { return }
                editorTask[keyPath: keyPath] = value.nilIfBlank
                self.editorTask = editorTask
            }
        )
    }

    private func editorBinding(_ keyPath: WritableKeyPath<HolyExternalTaskRecord, String>) -> Binding<String> {
        Binding(
            get: { editorTask?[keyPath: keyPath] ?? "" },
            set: { value in
                guard var editorTask else { return }
                editorTask[keyPath: keyPath] = value
                self.editorTask = editorTask
            }
        )
    }

    private func labeledField(
        _ label: String,
        text: Binding<String>,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(HolyGhosttyTheme.textTertiary)

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(HolyGhosttyTheme.bgSurface)
                )
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(HolyGhosttyTheme.textTertiary)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.bottom, 2)
    }

    private func detailRow(_ key: String, _ value: String, color: Color = HolyGhosttyTheme.textPrimary) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(key)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(HolyGhosttyTheme.textTertiary)
                .frame(width: 70, alignment: .trailing)

            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func ensureSelection() {
        guard let first = filteredTasks.first else {
            store.selectedTaskID = nil
            editorTask = nil
            return
        }

        guard let selectedTaskID = store.selectedTaskID else {
            store.selectedTaskID = first.id
            return
        }

        if !filteredTasks.contains(where: { $0.id == selectedTaskID }) {
            store.selectedTaskID = first.id
        }
    }

    private func reloadEditor() {
        editorTask = store.selectedTask
    }

    private func saveEditor() {
        guard let editorTask else { return }
        store.upsertTask(editorTask)
        self.editorTask = store.selectedTask
    }

    private func open(_ task: HolyExternalTaskRecord) {
        guard let canonicalURL = task.canonicalURL,
              let url = URL(string: canonicalURL) else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func statusColor(_ status: HolyExternalTaskStatus) -> Color {
        switch status {
        case .inbox:
            return HolyGhosttyTheme.textTertiary
        case .claimed:
            return HolyGhosttyTheme.accentSoft
        case .active:
            return HolyGhosttyTheme.accent
        case .waitingInput:
            return HolyGhosttyTheme.warning
        case .done:
            return HolyGhosttyTheme.success
        case .failed:
            return HolyGhosttyTheme.danger
        case .archived:
            return HolyGhosttyTheme.textSecondary
        }
    }
}

private struct HolyTaskRow: View {
    let task: HolyExternalTaskRecord
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            HolyGhosttyStatusDot(color: statusColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.white : HolyGhosttyTheme.textPrimary)
                    .lineLimit(1)

                Text(task.sourceSummary)
                    .font(.system(size: 10))
                    .foregroundStyle(HolyGhosttyTheme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(task.status.displayName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? HolyGhosttyTheme.bgSurface : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onTapGesture(perform: onSelect)
    }

    private var statusColor: Color {
        switch task.status {
        case .inbox:
            return HolyGhosttyTheme.textTertiary
        case .claimed:
            return HolyGhosttyTheme.accentSoft
        case .active:
            return HolyGhosttyTheme.accent
        case .waitingInput:
            return HolyGhosttyTheme.warning
        case .done:
            return HolyGhosttyTheme.success
        case .failed:
            return HolyGhosttyTheme.danger
        case .archived:
            return HolyGhosttyTheme.textSecondary
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
