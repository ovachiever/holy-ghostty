import Foundation
import OSLog

enum HolyWorkspacePersistence {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mitchellh.ghostty",
        category: "HolyWorkspacePersistence"
    )

    static func load() -> HolyWorkspaceSnapshot {
        let url = stateURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .empty
        }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder.holyWorkspace.decode(HolyWorkspaceSnapshot.self, from: data)
        } catch {
            quarantineCorruptSnapshot(at: url)
            logger.error("Failed to load Holy workspace state: \(error.localizedDescription, privacy: .public)")
            return .empty
        }
    }

    static func save(_ snapshot: HolyWorkspaceSnapshot) {
        do {
            try FileManager.default.createDirectory(
                at: containerDirectory,
                withIntermediateDirectories: true
            )

            let data = try JSONEncoder.holyWorkspace.encode(snapshot)
            try data.write(to: stateURL, options: [.atomic])
        } catch {
            logger.error("Failed to save Holy workspace state: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static var containerDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let bundleID = Bundle.main.bundleIdentifier ?? "com.mitchellh.ghostty"
        return appSupport
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("HolyGhostty", isDirectory: true)
    }

    private static var stateURL: URL {
        containerDirectory.appendingPathComponent("workspace-state.json", isDirectory: false)
    }

    private static func quarantineCorruptSnapshot(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let formatter = ISO8601DateFormatter()
        let quarantinedURL = url.deletingLastPathComponent()
            .appendingPathComponent("workspace-state.corrupt-\(formatter.string(from: .now)).json")

        do {
            try FileManager.default.moveItem(at: url, to: quarantinedURL)
            logger.warning("Quarantined corrupt Holy workspace snapshot at \(quarantinedURL.path, privacy: .public)")
        } catch {
            logger.error("Failed to quarantine corrupt Holy workspace snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }
}

private extension JSONEncoder {
    static let holyWorkspace: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

private extension JSONDecoder {
    static let holyWorkspace: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
