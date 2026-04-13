import Foundation

enum HolySessionTemplateCatalog {
    static let builtIns: [HolySessionTemplate] = [
        .init(
            id: UUID(uuidString: "8B7B0AB2-3A9E-4D2F-A9C3-5BE6D8D4C101")!,
            name: "Shell Workspace",
            summary: "A plain terminal session rooted in the current directory or selected session context.",
            launchSpec: .init(
                runtime: .shell,
                title: "Shell Workspace",
                objective: "Operate directly in the terminal.",
                workingDirectory: nil,
                command: nil,
                initialInput: nil,
                waitAfterCommand: false,
                environment: [:],
                workspace: nil
            )
        ),
        .init(
            id: UUID(uuidString: "58A4133D-1E49-4F92-88AE-5A7827036D11")!,
            name: "Claude Code",
            summary: "Launch Claude in the current working directory with the Holy session shell around it.",
            launchSpec: .init(
                runtime: .claude,
                title: "Claude Session",
                objective: "Drive the assigned coding task to completion.",
                workingDirectory: nil,
                command: "claude",
                initialInput: nil,
                waitAfterCommand: false,
                environment: [:],
                workspace: nil
            )
        ),
        .init(
            id: UUID(uuidString: "58F4F0BE-9D18-4D08-86D5-112450D87222")!,
            name: "Codex",
            summary: "Launch Codex in the active project context for code reading, editing, and command execution.",
            launchSpec: .init(
                runtime: .codex,
                title: "Codex Session",
                objective: "Plan, edit, verify, and complete the assigned coding task.",
                workingDirectory: nil,
                command: "codex",
                initialInput: nil,
                waitAfterCommand: false,
                environment: [:],
                workspace: nil
            )
        ),
        .init(
            id: UUID(uuidString: "863C7C32-8A22-4E6C-BBEF-62A92765D333")!,
            name: "OpenCode",
            summary: "Launch OpenCode in the active project context as a managed Holy session.",
            launchSpec: .init(
                runtime: .opencode,
                title: "OpenCode Session",
                objective: "Advance the assigned task inside the current project context.",
                workingDirectory: nil,
                command: "opencode",
                initialInput: nil,
                waitAfterCommand: false,
                environment: [:],
                workspace: nil
            )
        ),
        .init(
            id: UUID(uuidString: "C6A93D3A-9DA5-4680-9D86-C7F948D9B444")!,
            name: "Managed Claude Worktree",
            summary: "Create a dedicated managed worktree and launch Claude inside that owned branch context.",
            launchSpec: .init(
                runtime: .claude,
                title: "Claude Managed Session",
                objective: "Work in an isolated Claude-owned worktree.",
                workingDirectory: nil,
                command: "claude",
                initialInput: nil,
                waitAfterCommand: false,
                environment: [:],
                workspace: .init(
                    strategy: .createManagedWorktree,
                    repositoryRoot: nil,
                    branchName: nil
                )
            )
        ),
        .init(
            id: UUID(uuidString: "F19B05D1-E6E2-42F6-8435-8A4FF038F555")!,
            name: "Managed Codex Worktree",
            summary: "Create a dedicated managed worktree and launch Codex inside that owned branch context.",
            launchSpec: .init(
                runtime: .codex,
                title: "Codex Managed Session",
                objective: "Work in an isolated Codex-owned worktree.",
                workingDirectory: nil,
                command: "codex",
                initialInput: nil,
                waitAfterCommand: false,
                environment: [:],
                workspace: .init(
                    strategy: .createManagedWorktree,
                    repositoryRoot: nil,
                    branchName: nil
                )
            )
        ),
    ]
}
