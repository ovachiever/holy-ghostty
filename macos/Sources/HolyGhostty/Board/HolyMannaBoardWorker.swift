import Foundation

struct HolyMannaWorkerProfile: Equatable {
    var runtime: HolySessionRuntime = .codex
    var model = ""
}

struct HolyMannaWorkerDispatch: Equatable {
    let item: HolyMannaBoardItem
    let context: HolyMannaBoardContext
    let profile: HolyMannaWorkerProfile

    static func refusal(for item: HolyMannaBoardItem, context: HolyMannaBoardContext) -> String? {
        if item.kind == "dream" { return "Dreams cannot be claimed. Promote this dream before building it." }
        if item.status == "in_progress" || item.claimedBy != nil {
            return "Claimed by \(item.claimant?.label ?? item.claimedBy ?? "another worker")."
        }
        guard item.kind == "item", item.status == "open", item.effective == "ready" else {
            return "This item is not ready to claim (\(item.effective))."
        }
        guard let root = context.boardRoot, root.hasPrefix("/"), !root.contains("\u{0}") else {
            return "The board needs an absolute repository path."
        }
        guard let prompt = item.prompt, !prompt.isEmpty, item.handoffExists != false else {
            return "This item needs a handoff before a worker can start."
        }
        guard item.handoffDigest?.isEmpty == false else { return "Seal the handoff before starting a worker." }
        return nil
    }

    var confirmation: String {
        "Start a new \(profile.runtime.rawValue) worker (\(profile.model.isEmpty ? "runtime default model" : profile.model)) "
            + "in \(context.remoteHost.map { "\($0):" } ?? "")\(context.boardRoot ?? "") for \(item.id)? "
            + "The worker will claim first and read \(item.prompt ?? ""). No launches, installs, screenshots, or push."
    }

    var brief: String {
        """
        Claim and build \(item.id) in \(context.boardRoot ?? "").

        First run: agent-do manna claim \(item.id)
        If the claim fails or another worker owns the item, stop and report the refusal. Never steal a claim.
        Then read the sealed handoff at \(item.prompt ?? "") (expected binding \(item.handoffDigest ?? "")).
        Verify the handoff against canonical Manna state; if missing, changed, or unsealed, stop and report.
        Read the nearest AGENTS.md and obey the repository's work order.
        Establish agent-do coord focus and path claims before editing. Preserve other workers' changes.
        Implement the handoff's acceptance requirements and keep the tree buildable.
        Run focused test suites only, using the repository's canonical validation commands.
        No app launches, installs, screenshots, or live session spawning mid-lane.
        App-hosted tests may be built, but must not launch the app. Coordinate the live/visual acceptance pass at close.
        Commit the verified change with a Conventional Commit and this exact trailer:
        Manna: \(item.id)
        Never push or create a pull request.
        Update and seal the handoff with verification receipts. Mark done only after required acceptance is verified.
        Standard report: outcome; changes; focused test/build commands and actual results; commit;
        remaining acceptance or blockers. Distinguish compiled tests from executed tests.
        Include Lessons logged: N (new) | Decisions logged: N (new).
        End the report with TL;DR (12th grade): a plain-language summary.
        """
    }

    func launchSpec() throws -> HolySessionLaunchSpec {
        if let reason = Self.refusal(for: item, context: context) { throw HolyMannaAskError.unavailable(reason) }
        guard profile.runtime == .codex || profile.runtime == .claude else {
            throw HolyMannaAskError.unavailable("Choose Codex or Claude for the board worker.")
        }
        if context.remoteHost != nil {
            // Reuse canonical SSH validation, including option-injection rejection.
            _ = try HolyMannaBoardClient.remoteInvocation(
                arguments: ["manna", "state", "--json"], context: context, needsBoardRoot: true, identity: nil
            )
        }
        var spec = HolySessionLaunchSpec.interactiveTmuxShell(
            title: URL(fileURLWithPath: context.boardRoot!).lastPathComponent
        )
        spec.runtime = profile.runtime
        spec.objective = "Claim and build \(item.id)"
        spec.workingDirectory = context.boardRoot
        if let host = context.remoteHost {
            spec.transport = .init(kind: .ssh, hostLabel: host, sshDestination: host)
        }
        spec.tmux?.sessionName = "holy-worker-\(UUID().uuidString.lowercased())"
        var arguments = [profile.runtime.rawValue]
        let model = profile.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty { arguments += ["--model", model] }
        arguments += ["--", brief]
        // The prompt is one startup argument, never terminal input or an executable claim command.
        spec.command = arguments.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
            .joined(separator: " ")
        spec.initialInput = nil
        return spec
    }
}
