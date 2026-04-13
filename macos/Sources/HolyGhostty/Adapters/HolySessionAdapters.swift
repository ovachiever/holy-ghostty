import Foundation

struct HolySessionAdapter {
    let runtime: HolySessionRuntime
    let runtimeDescription: String
    let recommendedCommand: String?
    let idleHeadline: String
    let idleDetail: String
    let approvalMarkers: [String]
    let readingMarkers: [String]
    let editingMarkers: [String]
    let commandMarkers: [String]
    let failureHeadlines: [(marker: String, headline: String)]
    let completionMarkers: [String]
}

enum HolySessionAdapterRegistry {
    static func adapter(for runtime: HolySessionRuntime) -> HolySessionAdapter {
        switch runtime {
        case .shell:
            return .init(
                runtime: .shell,
                runtimeDescription: "Pure terminal session for direct commands, scripts, and manual intervention.",
                recommendedCommand: nil,
                idleHeadline: "Interactive shell ready",
                idleDetail: "Waiting for direct terminal input.",
                approvalMarkers: [],
                readingMarkers: [],
                editingMarkers: [],
                commandMarkers: [],
                failureHeadlines: [],
                completionMarkers: []
            )

        case .claude:
            return .init(
                runtime: .claude,
                runtimeDescription: "Claude-oriented coding session with approval-heavy and tool-use aware attention heuristics.",
                recommendedCommand: "claude",
                idleHeadline: "Claude session ready",
                idleDetail: "Waiting for the next Claude task or approval decision.",
                approvalMarkers: [
                    "permission",
                    "approval",
                    "would you like",
                    "needs approval",
                    "awaiting approval",
                ],
                readingMarkers: [
                    "reading",
                    "reviewing",
                    "searching",
                    "thinking",
                    "tool",
                ],
                editingMarkers: [
                    "writing",
                    "editing",
                    "updating",
                    "modifying",
                ],
                commandMarkers: [
                    "bash",
                    "running",
                    "executing",
                ],
                failureHeadlines: [
                    ("permission denied", "Permission denied"),
                    ("traceback", "Runtime exception reported"),
                    ("exception", "Runtime exception reported"),
                ],
                completionMarkers: [
                    "finished task",
                    "task complete",
                    "task completed",
                ]
            )

        case .codex:
            return .init(
                runtime: .codex,
                runtimeDescription: "Codex-oriented session with planning, tool use, and approval prompt detection.",
                recommendedCommand: "codex",
                idleHeadline: "Codex session ready",
                idleDetail: "Waiting for the next Codex prompt or intervention.",
                approvalMarkers: [
                    "permission",
                    "approval",
                    "clarify",
                    "select an option",
                    "needs input",
                ],
                readingMarkers: [
                    "reading",
                    "inspecting",
                    "reviewing",
                    "searching",
                    "updating plan",
                ],
                editingMarkers: [
                    "editing",
                    "writing",
                    "apply_patch",
                    "patching",
                    "updated",
                ],
                commandMarkers: [
                    "running",
                    "executing",
                    "xcodebuild",
                    "zig build",
                    "git ",
                ],
                failureHeadlines: [
                    ("fatal:", "Fatal error reported"),
                    ("error:", "Command reported an error"),
                    ("failed with exit code", "Command exited with failure"),
                ],
                completionMarkers: [
                    "completed successfully",
                    "finished successfully",
                    "done",
                ]
            )

        case .opencode:
            return .init(
                runtime: .opencode,
                runtimeDescription: "OpenCode-oriented session with generic agent workflow detection and runtime-aware defaults.",
                recommendedCommand: "opencode",
                idleHeadline: "OpenCode session ready",
                idleDetail: "Waiting for the next OpenCode task or instruction.",
                approvalMarkers: [
                    "permission",
                    "approval",
                    "awaiting approval",
                ],
                readingMarkers: [
                    "reading",
                    "reviewing",
                    "scanning",
                    "searching",
                ],
                editingMarkers: [
                    "editing",
                    "writing",
                    "modifying",
                    "updated",
                ],
                commandMarkers: [
                    "running",
                    "executing",
                    "installing",
                    "building",
                    "testing",
                ],
                failureHeadlines: [
                    ("error:", "Command reported an error"),
                    ("exception", "Runtime exception reported"),
                ],
                completionMarkers: [
                    "task complete",
                    "task completed",
                    "done",
                ]
            )
        }
    }
}
