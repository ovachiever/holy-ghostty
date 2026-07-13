import Foundation

enum HolyClaudeModelBridgeInstallOutcome: Equatable {
    case installed
    case alreadyInstalled
    case skippedExistingStatusLine
}

enum HolyClaudeModelBridgeInstallationState: Equatable {
    case notInstalled
    case installed
    case blockedByExistingStatusLine
}

enum HolyClaudeModelBridgeRemovalOutcome: Equatable {
    case removed
    case notInstalled
    case skippedExistingStatusLine
}

enum HolyClaudeModelBridgeError: Error, Equatable, LocalizedError {
    case tmuxPublishingGateFailed
    case tmuxLabelCleanupFailed

    var errorDescription: String? {
        switch self {
        case .tmuxPublishingGateFailed:
            "Could not disable Claude model publishing on Holy's tmux server"
        case .tmuxLabelCleanupFailed:
            "Could not verify removal of Claude-owned model labels"
        }
    }
}

/// Connects Claude Code's supported live status-line JSON to Holy's tmux bar.
///
/// Claude does not expose its current model in ordinary process arguments or
/// persistent terminal chrome. Its status-line command does receive the live
/// `model` and `effort` values, including mid-session `/model` changes. The
/// bridge publishes that truth to the containing tmux pane and also prints it
/// inside Claude's own status row.
enum HolyClaudeModelBridge {
    static func currentUserInstallationState() -> HolyClaudeModelBridgeInstallationState {
        let paths = currentUserPaths(fileManager: .default)
        do {
            return try installationState(
                settingsURL: paths.settingsURL,
                helperURL: paths.helperURL
            )
        } catch {
            AppDelegate.logger.error(
                "Reading Holy Claude model bridge state failed: \(error.localizedDescription, privacy: .public)"
            )
            return .notInstalled
        }
    }

    @discardableResult
    static func installForCurrentUser() -> HolyClaudeModelBridgeInstallOutcome? {
        // Unit tests launch the app target as their host. Never let that host
        // mutate the developer's real Claude configuration.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return nil
        }

        let fileManager = FileManager.default
        let paths = currentUserPaths(fileManager: fileManager)

        do {
            let outcome = try installIfSafe(
                settingsURL: paths.settingsURL,
                helperURL: paths.helperURL,
                fileManager: fileManager
            )
            switch outcome {
            case .installed:
                AppDelegate.logger.notice("Installed Holy Claude live-model status bridge")
            case .alreadyInstalled:
                break
            case .skippedExistingStatusLine:
                AppDelegate.logger.notice(
                    "Holy Claude live-model bridge left an existing custom status line unchanged"
                )
            }
            if outcome != .skippedExistingStatusLine {
                _ = setTmuxPublishingEnabled(true)
            }
            return outcome
        } catch {
            AppDelegate.logger.error(
                "Holy Claude live-model bridge installation failed: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    @discardableResult
    static func removeForCurrentUser() -> HolyClaudeModelBridgeRemovalOutcome? {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return nil
        }

        let fileManager = FileManager.default
        let paths = currentUserPaths(fileManager: fileManager)
        do {
            return try deactivateIfOwned(
                settingsURL: paths.settingsURL,
                helperURL: paths.helperURL,
                fileManager: fileManager
            )
        } catch {
            AppDelegate.logger.error(
                "Holy Claude live-model bridge removal failed: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    static func installIfSafe(
        settingsURL: URL,
        helperURL: URL,
        fileManager: FileManager = .default
    ) throws -> HolyClaudeModelBridgeInstallOutcome {
        var settings = try loadSettings(at: settingsURL, fileManager: fileManager)
        let command = shellQuote(helperURL.path)
        let desiredStatusLine: [String: Any] = [
            "type": "command",
            "command": command,
            "padding": 0,
            // A fixed refresh makes `/model` visible even if Claude does not
            // emit another assistant message after the selection changes.
            "refreshInterval": 5,
        ]
        let desiredSessionEndHook: [String: Any] = [
            "matcher": "*",
            "hooks": [
                [
                    "type": "command",
                    "command": command,
                ],
            ],
        ]

        if let existing = settings["statusLine"], !(existing is NSNull) {
            guard isHolyStatusLine(existing, helperURL: helperURL) else {
                return .skippedExistingStatusLine
            }

            let existingDictionary = existing as? [String: Any]
            let helperIsCurrent = (try? String(contentsOf: helperURL, encoding: .utf8)) == helperScript
            let sessionEndHookIsCurrent = try hasCurrentSessionEndHook(
                in: settings,
                helperURL: helperURL
            )
            let isCurrent = existingDictionary?["type"] as? String == "command"
                && existingDictionary?["command"] as? String == command
                && existingDictionary?["padding"] as? Int == 0
                && existingDictionary?["refreshInterval"] as? Int == 5
                && helperIsCurrent
                && sessionEndHookIsCurrent
            if isCurrent {
                return .alreadyInstalled
            }
        }

        try fileManager.createDirectory(
            at: helperURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(helperScript.utf8).write(to: helperURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: helperURL.path
        )

        settings["statusLine"] = desiredStatusLine
        try replaceOwnedSessionEndHooks(
            in: &settings,
            helperURL: helperURL,
            replacement: desiredSessionEndHook
        )
        try writeSettings(settings, to: settingsURL, fileManager: fileManager)
        return .installed
    }

    static func installationState(
        settingsURL: URL,
        helperURL: URL,
        fileManager: FileManager = .default
    ) throws -> HolyClaudeModelBridgeInstallationState {
        let settings = try loadSettings(at: settingsURL, fileManager: fileManager)
        guard let statusLine = settings["statusLine"], !(statusLine is NSNull) else {
            return .notInstalled
        }
        return isHolyStatusLine(statusLine, helperURL: helperURL)
            ? .installed
            : .blockedByExistingStatusLine
    }

    static func removeIfOwned(
        settingsURL: URL,
        helperURL: URL,
        fileManager: FileManager = .default
    ) throws -> HolyClaudeModelBridgeRemovalOutcome {
        var settings = try loadSettings(at: settingsURL, fileManager: fileManager)
        guard let statusLine = settings["statusLine"], !(statusLine is NSNull) else {
            return .notInstalled
        }
        guard let ownedHelperURL = ownedHelperURL(from: statusLine, helperURL: helperURL) else {
            return .skippedExistingStatusLine
        }

        settings.removeValue(forKey: "statusLine")
        try replaceOwnedSessionEndHooks(
            in: &settings,
            helperURL: helperURL,
            replacement: nil
        )
        try writeSettings(settings, to: settingsURL, fileManager: fileManager)

        if (try? String(contentsOf: ownedHelperURL, encoding: .utf8)) == helperScript {
            try fileManager.removeItem(at: ownedHelperURL)
        }
        return .removed
    }

    static func deactivateIfOwned(
        settingsURL: URL,
        helperURL: URL,
        socketName: String = HolySessionTmuxSpec.defaultSocketName,
        fileManager: FileManager = .default,
        setPublishingEnabled: (_ enabled: Bool, _ socketName: String) -> Bool = { enabled, socketName in
            HolyClaudeModelBridge.setTmuxPublishingEnabled(enabled, socketName: socketName)
        },
        clearOwnedLabels: (_ socketName: String) -> Bool = { socketName in
            HolyClaudeModelBridge.clearClaudeOwnedTmuxLabels(socketName: socketName)
        }
    ) throws -> HolyClaudeModelBridgeRemovalOutcome {
        let state = try installationState(
            settingsURL: settingsURL,
            helperURL: helperURL,
            fileManager: fileManager
        )
        switch state {
        case .notInstalled:
            return .notInstalled
        case .blockedByExistingStatusLine:
            return .skippedExistingStatusLine
        case .installed:
            break
        }

        // Gate at the tmux server before cleanup. The helper's final check and
        // writes are one server-side command queue, so an already-running
        // helper either lands before this gate (and is cleared below) or sees
        // the disabled gate and cannot recreate stale state afterward.
        guard setPublishingEnabled(false, socketName) else {
            throw HolyClaudeModelBridgeError.tmuxPublishingGateFailed
        }
        guard clearOwnedLabels(socketName) else {
            throw HolyClaudeModelBridgeError.tmuxLabelCleanupFailed
        }

        // Leave the gate disabled if file removal fails. That is the safe
        // state: a cached helper cannot resume publishing while the user
        // retries removal.
        return try removeIfOwned(
            settingsURL: settingsURL,
            helperURL: helperURL,
            fileManager: fileManager
        )
    }

    @discardableResult
    static func setTmuxPublishingEnabled(
        _ enabled: Bool,
        socketName: String = HolySessionTmuxSpec.defaultSocketName
    ) -> Bool {
        let script = "unset TMUX TMUX_PANE TMUX_TMPDIR; "
            + "tmux -L \(shellQuote(socketName)) set-option -gq "
            + "@holy_claude_model_enabled \(enabled ? "on" : "off")"
        return runLoginShell(script)
    }

    @discardableResult
    static func clearClaudeOwnedTmuxLabels(
        socketName: String = HolySessionTmuxSpec.defaultSocketName
    ) -> Bool {
        let socket = shellQuote(socketName)
        let script = """
        set -o pipefail
        unset TMUX TMUX_PANE TMUX_TMPDIR
        tmux -L \(socket) list-panes -a -F '#{pane_id}|#{@holy_model_source}' |
        while IFS='|' read -r pane source; do
          [ "$source" = "claude" ] || continue
          tmux -L \(socket) set-option -pu -t "$pane" @holy_model_label || exit 1
          tmux -L \(socket) set-option -pu -t "$pane" @holy_model_source || exit 1
        done || exit 1
        remaining=$(tmux -L \(socket) list-panes -a -F '#{@holy_model_source}') || exit 1
        if printf '%s\n' "$remaining" | grep -qx claude; then
          exit 1
        fi
        """
        return runLoginShell(script)
    }

    static let helperScript = #"""
    #!/bin/sh
    # Generated by Holy Ghostty. Claude Code sends current session JSON on stdin.
    input=$(cat)

    if command -v jq >/dev/null 2>&1; then
      fields=$(printf '%s' "$input" | jq -r '[
        (.hook_event_name // ""),
        ((.model.display_name // .model.id // "") | gsub("[^A-Za-z0-9 ._+/@:-]"; "") | .[0:48]),
        ((.effort.level // "") | gsub("[^A-Za-z0-9_ -]"; "") | .[0:12])
      ] | @tsv' 2>/dev/null)
      tab=$(printf '\t')
      event=${fields%%"$tab"*}
      remainder=${fields#*"$tab"}
      model=${remainder%%"$tab"*}
      if [ "$remainder" = "$model" ]; then
        effort=""
      else
        effort=${remainder#*"$tab"}
      fi
    else
      event=$(printf '%s' "$input" | /usr/bin/plutil -extract hook_event_name raw -o - - 2>/dev/null)
      model=$(printf '%s' "$input" | /usr/bin/plutil -extract model.display_name raw -o - - 2>/dev/null)
      if [ -z "$model" ]; then
        model=$(printf '%s' "$input" | /usr/bin/plutil -extract model.id raw -o - - 2>/dev/null)
      fi
      effort=$(printf '%s' "$input" | /usr/bin/plutil -extract effort.level raw -o - - 2>/dev/null)
      model=$(printf '%s' "$model" | LC_ALL=C tr -cd '[:alnum:] ._+/@:-' | cut -c1-48)
      effort=$(printf '%s' "$effort" | LC_ALL=C tr -cd '[:alnum:]_- ' | cut -c1-12)
    fi

    if [ "$event" = "SessionEnd" ]; then
      if [ -n "${TMUX_PANE:-}" ] && command -v tmux >/dev/null 2>&1; then
        tmux if-shell -F -t "$TMUX_PANE" '#{==:#{@holy_model_source},claude}' \
          "set-option -pu -t '$TMUX_PANE' @holy_model_label ; set-option -pu -t '$TMUX_PANE' @holy_model_source" \
          2>/dev/null || true
      fi
      exit 0
    fi

    [ -n "$model" ] || exit 0

    label=$model
    [ -z "$effort" ] || label="$label · $effort"

    if [ -n "${TMUX_PANE:-}" ] && command -v tmux >/dev/null 2>&1; then
      # Model and effort are restricted above to a small, quote-free alphabet.
      # `if-shell -F` evaluates the gate and queues both writes inside tmux,
      # serializing them against Disable's server-side gate update.
      tmux if-shell -F -t "$TMUX_PANE" '#{!=:#{@holy_claude_model_enabled},off}' \
        "set-option -p -t '$TMUX_PANE' @holy_model_label '$label' ; set-option -p -t '$TMUX_PANE' @holy_model_source claude" \
        2>/dev/null || true
    fi

    printf 'Model · %s\n' "$label"
    """#

    private static func loadSettings(
        at url: URL,
        fileManager: FileManager
    ) throws -> [String: Any] {
        guard fileManager.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [:] }
        guard let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        return dictionary
    }

    private static func writeSettings(
        _ settings: [String: Any],
        to settingsURL: URL,
        fileManager: FileManager
    ) throws {
        let writeURL = resolvedSettingsWriteURL(settingsURL, fileManager: fileManager)
        let existingPermissions = try? fileManager.attributesOfItem(
            atPath: writeURL.path
        )[.posixPermissions]
        try fileManager.createDirectory(
            at: writeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        ) + Data("\n".utf8)
        try data.write(to: writeURL, options: .atomic)
        if let existingPermissions {
            try fileManager.setAttributes(
                [.posixPermissions: existingPermissions],
                ofItemAtPath: writeURL.path
            )
        }
    }

    private static func resolvedSettingsWriteURL(
        _ settingsURL: URL,
        fileManager: FileManager
    ) -> URL {
        if let destination = try? fileManager.destinationOfSymbolicLink(atPath: settingsURL.path) {
            return URL(
                fileURLWithPath: destination,
                relativeTo: settingsURL.deletingLastPathComponent()
            )
            .standardizedFileURL
            .resolvingSymlinksInPath()
        }
        return settingsURL.resolvingSymlinksInPath()
    }

    private static func isHolyStatusLine(_ value: Any, helperURL: URL) -> Bool {
        ownedHelperURL(from: value, helperURL: helperURL) != nil
    }

    private static func hasCurrentSessionEndHook(
        in settings: [String: Any],
        helperURL: URL
    ) throws -> Bool {
        guard let hooksValue = settings["hooks"] else { return false }
        guard let hooks = hooksValue as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        guard let groupsValue = hooks["SessionEnd"] else { return false }
        guard let groups = groupsValue as? [[String: Any]] else {
            throw CocoaError(.propertyListReadCorrupt)
        }

        let desiredCommand = shellQuote(helperURL.path)
        var ownedHandlers = 0
        var hasDesiredHandler = false
        for group in groups {
            guard let handlers = group["hooks"] as? [[String: Any]] else {
                throw CocoaError(.propertyListReadCorrupt)
            }
            for handler in handlers where ownedHelperURL(from: handler, helperURL: helperURL) != nil {
                ownedHandlers += 1
                hasDesiredHandler = handler["type"] as? String == "command"
                    && handler["command"] as? String == desiredCommand
            }
        }
        return ownedHandlers == 1 && hasDesiredHandler
    }

    private static func replaceOwnedSessionEndHooks(
        in settings: inout [String: Any],
        helperURL: URL,
        replacement: [String: Any]?
    ) throws {
        var hooks: [String: Any]
        if let hooksValue = settings["hooks"] {
            guard let existingHooks = hooksValue as? [String: Any] else {
                throw CocoaError(.propertyListReadCorrupt)
            }
            hooks = existingHooks
        } else {
            hooks = [:]
        }

        var retainedGroups: [[String: Any]] = []
        if let groupsValue = hooks["SessionEnd"] {
            guard let groups = groupsValue as? [[String: Any]] else {
                throw CocoaError(.propertyListReadCorrupt)
            }
            for existingGroup in groups {
                guard let handlers = existingGroup["hooks"] as? [[String: Any]] else {
                    throw CocoaError(.propertyListReadCorrupt)
                }
                let retainedHandlers = handlers.filter {
                    ownedHelperURL(from: $0, helperURL: helperURL) == nil
                }
                guard !retainedHandlers.isEmpty else { continue }
                var retainedGroup = existingGroup
                retainedGroup["hooks"] = retainedHandlers
                retainedGroups.append(retainedGroup)
            }
        }

        if let replacement {
            retainedGroups.append(replacement)
        }
        if retainedGroups.isEmpty {
            hooks.removeValue(forKey: "SessionEnd")
        } else {
            hooks["SessionEnd"] = retainedGroups
        }
        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }
    }

    private static func ownedHelperURL(from value: Any, helperURL: URL) -> URL? {
        guard let dictionary = value as? [String: Any],
              let command = dictionary["command"] as? String else {
            return nil
        }

        return ownedHelperURLs(for: helperURL).first { candidate in
            command == candidate.path || command == shellQuote(candidate.path)
        }
    }

    private static func ownedHelperURLs(for helperURL: URL) -> [URL] {
        let supportRoot = helperURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return [
            helperURL,
            supportRoot
                .appendingPathComponent("org.holyghostty.app.debug", isDirectory: true)
                .appendingPathComponent("HolyGhostty", isDirectory: true)
                .appendingPathComponent("claude-model-statusline.sh"),
            supportRoot
                .appendingPathComponent("org.holyghostty.app", isDirectory: true)
                .appendingPathComponent("HolyGhostty", isDirectory: true)
                .appendingPathComponent("claude-model-statusline.sh"),
        ]
    }

    private struct CurrentUserPaths {
        let settingsURL: URL
        let helperURL: URL
    }

    private static func currentUserPaths(fileManager: FileManager) -> CurrentUserPaths {
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        let settingsURL = homeDirectory
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json", isDirectory: false)
        let supportRoot = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? homeDirectory.appendingPathComponent(
            "Library/Application Support",
            isDirectory: true
        )
        let helperURL = supportRoot
            .appendingPathComponent("Holy Ghostty", isDirectory: true)
            .appendingPathComponent("claude-model-statusline.sh", isDirectory: false)
        return .init(settingsURL: settingsURL, helperURL: helperURL)
    }

    private static func runLoginShell(
        _ script: String,
        timeout: TimeInterval = 5
    ) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", script]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.025)
            }
            guard !process.isRunning else {
                process.terminate()
                return false
            }
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}
