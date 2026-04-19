import Foundation

enum HolyDatabasePaths {
    static var containerDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let bundleID = Bundle.main.bundleIdentifier ?? "com.mitchellh.ghostty"

        return appSupport
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("HolyGhostty", isDirectory: true)
    }

    static var databaseURL: URL {
        containerDirectory.appendingPathComponent(HolyDatabaseSchema.filename, isDirectory: false)
    }

    static var legacyWorkspaceStateURL: URL {
        containerDirectory.appendingPathComponent("workspace-state.json", isDirectory: false)
    }

    static func ensureContainerDirectory() throws {
        try FileManager.default.createDirectory(
            at: containerDirectory,
            withIntermediateDirectories: true
        )
    }
}
