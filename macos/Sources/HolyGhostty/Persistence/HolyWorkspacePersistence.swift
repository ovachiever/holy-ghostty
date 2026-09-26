import CryptoKit
import Foundation
import OSLog

/// Why one flush did or did not rewrite `workspace-state.json`.
enum HolyWorkspaceLegacySnapshotWriteReceipt: Equatable {
    /// Nothing durable differs from the last snapshot written this run.
    case skippedDurableStateUnchanged
    /// The encoding is byte-identical to the file already on disk.
    case skippedIdenticalOnDisk
    case written(bytes: Int)
    case failed
}

/// The legacy whole-workspace JSON snapshot. The database is the store of
/// record; this file is read only when the database has no initialized
/// workspace (`HolyWorkspaceRepository.loadSnapshot`, `HolyMigrationService`).
///
/// It is rewritten only when the durable state it encodes changed. The one
/// field left out of that comparison is the active records' `updatedAt`:
/// `HolySession.markUpdated` advances it on preview churn, git refresh, and
/// telemetry change, so it rides at "a moment ago" for every live pane (the
/// supervisor's own description). Read-only diffs of the live file on
/// 2026-09-26 showed it as the only field that changed in 12 of 12
/// rewrites over 120 s (1,338,678 bytes each). The database row carries the
/// live value every flush; this file refreshes it on the next durable change
/// and, exactly, at an orderly quit (`flushForTermination`).
enum HolyWorkspacePersistence {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mitchellh.ghostty",
        category: "HolyWorkspacePersistence"
    )

    /// What this run knows about one snapshot file.
    private struct Journal {
        /// The most recent snapshot handed to `save`, written or not.
        var lastHandedSnapshot: HolyWorkspaceSnapshot?
        /// The snapshot whose encoding is on disk, as far as this run knows.
        var lastWrittenSnapshot: HolyWorkspaceSnapshot?
        /// Digest of the bytes on disk, read once from the file and then
        /// carried forward from each write.
        var onDiskDigest: SHA256Digest?
    }

    @MainActor private static var journals: [URL: Journal] = [:]

    static func load() -> HolyWorkspaceSnapshot {
        load(from: stateURL)
    }

    static func load(from url: URL) -> HolyWorkspaceSnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .empty
        }

        do {
            let data = try Data(contentsOf: url)
            return try HolyPersistenceCoders.jsonDecoder.decode(HolyWorkspaceSnapshot.self, from: data)
        } catch {
            quarantineCorruptSnapshot(at: url)
            logger.error("Failed to load Holy workspace state: \(error.localizedDescription, privacy: .public)")
            return .empty
        }
    }

    @MainActor
    @discardableResult
    static func save(
        _ snapshot: HolyWorkspaceSnapshot,
        to url: URL = stateURL
    ) -> HolyWorkspaceLegacySnapshotWriteReceipt {
        var journal = journals[url] ?? Journal()
        journal.lastHandedSnapshot = snapshot
        defer { journals[url] = journal }

        if let lastWritten = journal.lastWrittenSnapshot,
           snapshot.durableStateEquals(lastWritten) {
            return .skippedDurableStateUnchanged
        }

        return write(snapshot, to: url, journal: &journal)
    }

    /// Writes the last handed snapshot exactly (activity clocks included)
    /// when its bytes differ from the file. Called at an orderly quit.
    @MainActor
    @discardableResult
    static func flushForTermination(to url: URL = stateURL) -> HolyWorkspaceLegacySnapshotWriteReceipt {
        var journal = journals[url] ?? Journal()
        defer { journals[url] = journal }

        guard let snapshot = journal.lastHandedSnapshot else {
            return .skippedDurableStateUnchanged
        }
        return write(snapshot, to: url, journal: &journal)
    }

    #if DEBUG
    @MainActor
    static func forgetJournalForTesting(at url: URL) {
        journals[url] = nil
    }
    #endif

    @MainActor
    private static func write(
        _ snapshot: HolyWorkspaceSnapshot,
        to url: URL,
        journal: inout Journal
    ) -> HolyWorkspaceLegacySnapshotWriteReceipt {
        do {
            let data = try HolyPersistenceCoders.jsonEncoder.encode(snapshot)
            let digest = SHA256.hash(data: data)

            if journal.onDiskDigest == nil {
                journal.onDiskDigest = digestOfFile(at: url)
            }
            if digest == journal.onDiskDigest {
                journal.lastWrittenSnapshot = snapshot
                return .skippedIdenticalOnDisk
            }

            if url == stateURL {
                try HolyDatabasePaths.ensureContainerDirectory()
            } else {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
            }
            try data.write(to: url, options: [.atomic])
            journal.onDiskDigest = digest
            journal.lastWrittenSnapshot = snapshot
            return .written(bytes: data.count)
        } catch {
            logger.error("Failed to save Holy workspace state: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    private static func digestOfFile(at url: URL) -> SHA256Digest? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data)
    }

    private static var containerDirectory: URL {
        HolyDatabasePaths.containerDirectory
    }

    private static var stateURL: URL {
        HolyDatabasePaths.legacyWorkspaceStateURL
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

extension HolyWorkspaceSnapshot {
    /// Equality over everything the snapshot persists except the active
    /// records' activity clock (`updatedAt`), which every live pane advances
    /// per poll. Archived sessions, templates, layout, selection, and
    /// attention metadata compare whole.
    func durableStateEquals(_ other: HolyWorkspaceSnapshot) -> Bool {
        guard selectedSessionID == other.selectedSessionID,
              paneLayout == other.paneLayout,
              templates == other.templates,
              archivedSessions == other.archivedSessions,
              attentionMetadata == other.attentionMetadata,
              sessions.count == other.sessions.count else {
            return false
        }

        return zip(sessions, other.sessions).allSatisfy { lhs, rhs in
            lhs.id == rhs.id
                && lhs.launchSpec == rhs.launchSpec
                && lhs.harnessSessionID == rhs.harnessSessionID
                && lhs.createdAt == rhs.createdAt
        }
    }
}
