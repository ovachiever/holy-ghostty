import Foundation

enum HolyAgentStateBridgeInstallationState: Equatable {
    case notInstalled
    case installed
    case blocked(String)
}

enum HolyAgentStateBridgeInstallOutcome: Equatable {
    case installed
    case alreadyInstalled
}

enum HolyAgentStateBridgeInstallerError: Error, LocalizedError {
    case foreignHelper
    case foreignOpenCodePlugin
    case foreignCodexNotifyAdapter
    case invalidJSONObject(URL)

    var errorDescription: String? {
        switch self {
        case .foreignHelper:
            "Holy's agent-state helper path already contains a different file"
        case .foreignOpenCodePlugin:
            "OpenCode's Holy agent-state plugin path already contains a different file"
        case .foreignCodexNotifyAdapter:
            "Codex's Holy turn-complete adapter path already contains a different file"
        case let .invalidJSONObject(url):
            "\(url.path) is not a valid JSON object"
        }
    }
}

struct HolyAgentStateBridgePaths {
    let helperURL: URL
    let claudeSettingsURL: URL
    let codexHooksURL: URL
    let codexConfigURL: URL
    let codexNotifyAdapterURL: URL
    let openCodePluginURL: URL
}

/// Explicit, ownership-safe installation of Holy's harness adapters.
///
/// This mutates only exact Holy-owned handlers/files, preserves unrelated JSON
/// and symlinks, and rolls all touched files back if any write fails. Codex's
/// hook trust store is deliberately outside this installer; Codex must ask the
/// user to trust the exact commands through `/hooks`.
enum HolyAgentStateBridgeInstaller {
    static func currentUserInstallationState() -> HolyAgentStateBridgeInstallationState {
        do {
            return try installationState(paths: currentUserPaths())
        } catch {
            return .blocked(error.localizedDescription)
        }
    }

    @discardableResult
    static func installForCurrentUser() -> HolyAgentStateBridgeInstallOutcome? {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return nil
        }
        do {
            return try install(paths: currentUserPaths())
        } catch {
            AppDelegate.logger.error(
                "Holy agent-state bridge installation failed: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    @discardableResult
    static func removeForCurrentUser() -> Bool {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return false
        }
        do {
            try remove(paths: currentUserPaths())
            return true
        } catch {
            AppDelegate.logger.error(
                "Holy agent-state bridge removal failed: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    static func installationState(
        paths: HolyAgentStateBridgePaths,
        fileManager: FileManager = .default
    ) throws -> HolyAgentStateBridgeInstallationState {
        if let helper = try contentsIfPresent(at: paths.helperURL, fileManager: fileManager),
           !HolyAgentStateBridge.isOwnedHelperScript(helper) {
            return .blocked(HolyAgentStateBridgeInstallerError.foreignHelper.localizedDescription)
        }
        if let plugin = try contentsIfPresent(at: paths.openCodePluginURL, fileManager: fileManager),
           !HolyAgentStateBridge.isOwnedOpenCodePlugin(plugin, helperURL: paths.helperURL) {
            return .blocked(HolyAgentStateBridgeInstallerError.foreignOpenCodePlugin.localizedDescription)
        }
        if let adapter = try contentsIfPresent(at: paths.codexNotifyAdapterURL, fileManager: fileManager),
           !HolyAgentStateBridge.isOwnedCodexNotifyAdapter(adapter, helperURL: paths.helperURL) {
            return .blocked(HolyAgentStateBridgeInstallerError.foreignCodexNotifyAdapter.localizedDescription)
        }

        let codexConfig = try contentsIfPresent(at: paths.codexConfigURL, fileManager: fileManager) ?? ""
        let desiredCodexConfig: String
        do {
            desiredCodexConfig = try HolyAgentStateBridge.mergingCodexConfiguration(
                codexConfig,
                adapterURL: paths.codexNotifyAdapterURL
            )
        } catch {
            return .blocked(error.localizedDescription)
        }

        guard (try contentsIfPresent(at: paths.helperURL, fileManager: fileManager)) == HolyAgentStateBridge.helperScript,
              (try contentsIfPresent(at: paths.openCodePluginURL, fileManager: fileManager))
                == HolyAgentStateBridge.openCodePlugin(helperURL: paths.helperURL),
              (try contentsIfPresent(at: paths.codexNotifyAdapterURL, fileManager: fileManager))
                == HolyAgentStateBridge.codexNotifyAdapter(helperURL: paths.helperURL) else {
            return .notInstalled
        }

        let claude = try loadJSONObject(at: paths.claudeSettingsURL, fileManager: fileManager)
        let codex = try loadJSONObject(at: paths.codexHooksURL, fileManager: fileManager)
        let desiredClaude = try HolyAgentStateBridge.mergingClaudeSettings(
            claude,
            helperURL: paths.helperURL
        )
        let desiredCodex = try HolyAgentStateBridge.mergingCodexHooks(
            codex,
            helperURL: paths.helperURL
        )
        guard try canonicalJSON(claude) == canonicalJSON(desiredClaude),
              try canonicalJSON(codex) == canonicalJSON(desiredCodex),
              codexConfig == desiredCodexConfig else {
            return .notInstalled
        }
        return .installed
    }

    static func install(
        paths: HolyAgentStateBridgePaths,
        fileManager: FileManager = .default
    ) throws -> HolyAgentStateBridgeInstallOutcome {
        if try installationState(paths: paths, fileManager: fileManager) == .installed {
            return .alreadyInstalled
        }
        if let helper = try contentsIfPresent(at: paths.helperURL, fileManager: fileManager),
           !HolyAgentStateBridge.isOwnedHelperScript(helper) {
            throw HolyAgentStateBridgeInstallerError.foreignHelper
        }
        if let plugin = try contentsIfPresent(at: paths.openCodePluginURL, fileManager: fileManager),
           !HolyAgentStateBridge.isOwnedOpenCodePlugin(plugin, helperURL: paths.helperURL) {
            throw HolyAgentStateBridgeInstallerError.foreignOpenCodePlugin
        }
        if let adapter = try contentsIfPresent(at: paths.codexNotifyAdapterURL, fileManager: fileManager),
           !HolyAgentStateBridge.isOwnedCodexNotifyAdapter(adapter, helperURL: paths.helperURL) {
            throw HolyAgentStateBridgeInstallerError.foreignCodexNotifyAdapter
        }

        let claude = try loadJSONObject(at: paths.claudeSettingsURL, fileManager: fileManager)
        let codex = try loadJSONObject(at: paths.codexHooksURL, fileManager: fileManager)
        let desiredClaude = try HolyAgentStateBridge.mergingClaudeSettings(
            claude,
            helperURL: paths.helperURL
        )
        let desiredCodex = try HolyAgentStateBridge.mergingCodexHooks(
            codex,
            helperURL: paths.helperURL
        )
        let codexConfig = try contentsIfPresent(at: paths.codexConfigURL, fileManager: fileManager) ?? ""
        let desiredCodexConfig = try HolyAgentStateBridge.mergingCodexConfiguration(
            codexConfig,
            adapterURL: paths.codexNotifyAdapterURL
        )

        let writeURLs = [
            paths.helperURL,
            paths.claudeSettingsURL,
            paths.codexHooksURL,
            paths.codexConfigURL,
            paths.codexNotifyAdapterURL,
            paths.openCodePluginURL,
        ]
        let snapshots = try writeURLs.map {
            try FileSnapshot(url: resolvedWriteURL($0, fileManager: fileManager), fileManager: fileManager)
        }

        do {
            try write(
                Data(HolyAgentStateBridge.helperScript.utf8),
                to: paths.helperURL,
                permissions: 0o700,
                fileManager: fileManager
            )
            try writeJSON(desiredClaude, to: paths.claudeSettingsURL, fileManager: fileManager)
            try writeJSON(desiredCodex, to: paths.codexHooksURL, fileManager: fileManager)
            try write(
                Data(desiredCodexConfig.utf8),
                to: paths.codexConfigURL,
                permissions: 0o600,
                fileManager: fileManager
            )
            try write(
                Data(HolyAgentStateBridge.codexNotifyAdapter(helperURL: paths.helperURL).utf8),
                to: paths.codexNotifyAdapterURL,
                permissions: 0o700,
                fileManager: fileManager
            )
            try write(
                Data(HolyAgentStateBridge.openCodePlugin(helperURL: paths.helperURL).utf8),
                to: paths.openCodePluginURL,
                permissions: 0o600,
                fileManager: fileManager
            )
        } catch {
            for snapshot in snapshots.reversed() {
                try? snapshot.restore(fileManager: fileManager)
            }
            throw error
        }
        return .installed
    }

    static func remove(
        paths: HolyAgentStateBridgePaths,
        fileManager: FileManager = .default
    ) throws {
        let touchedURLs = [
            paths.helperURL,
            paths.claudeSettingsURL,
            paths.codexHooksURL,
            paths.codexConfigURL,
            paths.codexNotifyAdapterURL,
            paths.openCodePluginURL,
        ]
        let snapshots = try touchedURLs.map {
            try FileSnapshot(url: resolvedWriteURL($0, fileManager: fileManager), fileManager: fileManager)
        }
        var claude = try loadJSONObject(at: paths.claudeSettingsURL, fileManager: fileManager)
        var codex = try loadJSONObject(at: paths.codexHooksURL, fileManager: fileManager)
        let codexConfig = try contentsIfPresent(at: paths.codexConfigURL, fileManager: fileManager) ?? ""
        let desiredCodexConfig = try HolyAgentStateBridge.removingCodexConfiguration(
            codexConfig,
            adapterURL: paths.codexNotifyAdapterURL
        )
        removeOwnedHooks(
            from: &claude,
            helperURL: paths.helperURL,
            source: HolyAgentStateSource.claude
        )
        removeOwnedHooks(
            from: &codex,
            helperURL: paths.helperURL,
            source: HolyAgentStateSource.codex
        )
        do {
            try writeJSON(claude, to: paths.claudeSettingsURL, fileManager: fileManager)
            try writeJSON(codex, to: paths.codexHooksURL, fileManager: fileManager)
            if codexConfig != desiredCodexConfig {
                if desiredCodexConfig.isEmpty {
                    let resolved = resolvedWriteURL(paths.codexConfigURL, fileManager: fileManager)
                    if fileManager.fileExists(atPath: resolved.path) {
                        try fileManager.removeItem(at: resolved)
                    }
                } else {
                    try write(
                        Data(desiredCodexConfig.utf8),
                        to: paths.codexConfigURL,
                        permissions: 0o600,
                        fileManager: fileManager
                    )
                }
            }

            if let adapter = try contentsIfPresent(at: paths.codexNotifyAdapterURL, fileManager: fileManager),
               HolyAgentStateBridge.isOwnedCodexNotifyAdapter(adapter, helperURL: paths.helperURL) {
                try fileManager.removeItem(
                    at: resolvedWriteURL(paths.codexNotifyAdapterURL, fileManager: fileManager)
                )
            }

            if let plugin = try contentsIfPresent(at: paths.openCodePluginURL, fileManager: fileManager),
               HolyAgentStateBridge.isOwnedOpenCodePlugin(plugin, helperURL: paths.helperURL) {
                try fileManager.removeItem(at: resolvedWriteURL(paths.openCodePluginURL, fileManager: fileManager))
            }
            if let helper = try contentsIfPresent(at: paths.helperURL, fileManager: fileManager),
               HolyAgentStateBridge.isOwnedHelperScript(helper) {
                try fileManager.removeItem(at: resolvedWriteURL(paths.helperURL, fileManager: fileManager))
            }
        } catch {
            for snapshot in snapshots.reversed() {
                try? snapshot.restore(fileManager: fileManager)
            }
            throw error
        }
    }

    private static func removeOwnedHooks(
        from root: inout [String: Any],
        helperURL: URL,
        source: String
    ) {
        guard var hooks = root["hooks"] as? [String: Any] else { return }
        for event in hooks.keys {
            guard let groups = hooks[event] as? [[String: Any]] else { continue }
            let retainedGroups = groups.compactMap { group -> [String: Any]? in
                guard let handlers = group["hooks"] as? [[String: Any]] else { return group }
                let retainedHandlers = handlers.filter { handler in
                    guard let command = handler["command"] as? String else { return true }
                    return !HolyAgentStateBridge.isOwnedHookCommand(
                        command,
                        helperURL: helperURL,
                        source: source
                    )
                }
                guard !retainedHandlers.isEmpty else { return nil }
                var retained = group
                retained["hooks"] = retainedHandlers
                return retained
            }
            if retainedGroups.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = retainedGroups
            }
        }
        if hooks.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = hooks
        }
    }

    private static func currentUserPaths(fileManager: FileManager = .default) -> HolyAgentStateBridgePaths {
        let home = fileManager.homeDirectoryForCurrentUser
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let helper = support
            .appendingPathComponent("Holy Ghostty", isDirectory: true)
            .appendingPathComponent("agent-state-hook.sh")
        return .init(
            helperURL: helper,
            claudeSettingsURL: home
                .appendingPathComponent(".claude", isDirectory: true)
                .appendingPathComponent("settings.json"),
            codexHooksURL: home
                .appendingPathComponent(".codex", isDirectory: true)
                .appendingPathComponent("hooks.json"),
            codexConfigURL: home
                .appendingPathComponent(".codex", isDirectory: true)
                .appendingPathComponent("config.toml"),
            codexNotifyAdapterURL: support
                .appendingPathComponent("Holy Ghostty", isDirectory: true)
                .appendingPathComponent(HolyAgentStateBridge.codexNotifyAdapterFileName),
            openCodePluginURL: home
                .appendingPathComponent(".config/opencode/plugins", isDirectory: true)
                .appendingPathComponent(HolyAgentStateBridge.openCodePluginFileName)
        )
    }

    private static func loadJSONObject(
        at url: URL,
        fileManager: FileManager
    ) throws -> [String: Any] {
        let readURL = resolvedWriteURL(url, fileManager: fileManager)
        guard fileManager.fileExists(atPath: readURL.path) else { return [:] }
        let data = try Data(contentsOf: readURL)
        guard !data.isEmpty else { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HolyAgentStateBridgeInstallerError.invalidJSONObject(url)
        }
        return object
    }

    private static func contentsIfPresent(
        at url: URL,
        fileManager: FileManager
    ) throws -> String? {
        let readURL = resolvedWriteURL(url, fileManager: fileManager)
        guard fileManager.fileExists(atPath: readURL.path) else { return nil }
        return try String(contentsOf: readURL, encoding: .utf8)
    }

    private static func writeJSON(
        _ value: [String: Any],
        to url: URL,
        fileManager: FileManager
    ) throws {
        let data = try canonicalJSON(value) + Data("\n".utf8)
        try write(data, to: url, permissions: 0o600, fileManager: fileManager)
    }

    private static func canonicalJSON(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    }

    private static func write(
        _ data: Data,
        to url: URL,
        permissions: Int,
        fileManager: FileManager
    ) throws {
        let writeURL = resolvedWriteURL(url, fileManager: fileManager)
        let existingPermissions = try? fileManager.attributesOfItem(atPath: writeURL.path)[.posixPermissions]
        try fileManager.createDirectory(
            at: writeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: writeURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: existingPermissions ?? permissions],
            ofItemAtPath: writeURL.path
        )
    }

    private static func resolvedWriteURL(_ url: URL, fileManager: FileManager) -> URL {
        if let destination = try? fileManager.destinationOfSymbolicLink(atPath: url.path) {
            return URL(
                fileURLWithPath: destination,
                relativeTo: url.deletingLastPathComponent()
            )
            .standardizedFileURL
            .resolvingSymlinksInPath()
        }
        return url.resolvingSymlinksInPath()
    }

    private struct FileSnapshot {
        let url: URL
        let data: Data?
        let permissions: Any?

        init(url: URL, fileManager: FileManager) throws {
            self.url = url
            if fileManager.fileExists(atPath: url.path) {
                data = try Data(contentsOf: url)
                permissions = try? fileManager.attributesOfItem(atPath: url.path)[.posixPermissions]
            } else {
                data = nil
                permissions = nil
            }
        }

        func restore(fileManager: FileManager) throws {
            if let data {
                try fileManager.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: url, options: .atomic)
                if let permissions {
                    try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
                }
            } else if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }
}
