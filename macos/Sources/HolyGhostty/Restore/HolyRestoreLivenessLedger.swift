import Darwin
import Foundation

/// What the app last knew to be live, and under which boot. Written whenever
/// the roster's membership changes and again at an orderly quit; read once
/// at the next launch to decide what the last shutdown interrupted.
///
/// This is the record that the 2026-09-26 panic showed the archive rows
/// cannot be: a row's `recoveryBootBatchID` says which sweep last archived
/// it, not whether the session was live afterwards. The ledger says exactly
/// that, from the app's own last observation.
struct HolyRestoreLivenessLedger: Codable, Equatable, Sendable {
    struct LiveSession: Codable, Equatable, Sendable {
        let sourceSessionID: UUID
        let title: String
        /// Restore is local-only; remote rows are recorded for the receipt
        /// and never renewed.
        let isLocal: Bool
        let tmuxSocketName: String?
        let tmuxSessionName: String?
    }

    static let currentVersion = 1

    var version: Int = HolyRestoreLivenessLedger.currentVersion
    /// The boot the app was running under when this ledger was written.
    var boot: HolyBootIdentity
    var recordedAt: Date
    var liveSessions: [LiveSession]
    /// Set only by an orderly quit (`applicationWillTerminate`). An installer
    /// kill, a crash, or a panic leaves it nil.
    var cleanExitAt: Date?
    /// The batch of the last shutdown that interrupted anything, carried
    /// across relaunches inside one boot so a clean quit never promotes an
    /// older group to "interrupted by the last shutdown".
    var lastInterruptionBatchID: UUID?

    init(
        boot: HolyBootIdentity,
        recordedAt: Date,
        liveSessions: [LiveSession],
        cleanExitAt: Date? = nil,
        lastInterruptionBatchID: UUID? = nil
    ) {
        self.boot = boot
        self.recordedAt = recordedAt
        self.liveSessions = liveSessions
        self.cleanExitAt = cleanExitAt
        self.lastInterruptionBatchID = lastInterruptionBatchID
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case boot
        case recordedAt
        case liveSessions
        case cleanExitAt
        case lastInterruptionBatchID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        boot = try container.decode(HolyBootIdentity.self, forKey: .boot)
        recordedAt = try container.decode(Date.self, forKey: .recordedAt)
        liveSessions = try container.decodeIfPresent([LiveSession].self, forKey: .liveSessions) ?? []
        cleanExitAt = try container.decodeIfPresent(Date.self, forKey: .cleanExitAt)
        lastInterruptionBatchID = try container.decodeIfPresent(UUID.self, forKey: .lastInterruptionBatchID)
    }
}

/// The ledger's own file, deliberately outside the SQLite store: it is
/// written with `F_FULLFSYNC` so the record of what was live reaches the
/// platter before the next power event, and it must stay readable even when
/// the workspace database needs journal recovery after a panic.
enum HolyRestoreLivenessLedgerStore {
    static let filename = "restore-liveness-ledger.json"

    static func url(in directory: URL) -> URL {
        directory.appendingPathComponent(filename, isDirectory: false)
    }

    static func load(from url: URL) -> HolyRestoreLivenessLedger? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? HolyRestoreFileCoding.decoder.decode(HolyRestoreLivenessLedger.self, from: data)
    }

    static func save(_ ledger: HolyRestoreLivenessLedger, to url: URL) throws {
        let data = try HolyRestoreFileCoding.encoder.encode(ledger)
        try HolyRestoreFileCoding.writeDurably(data, to: url)
    }
}

/// Shared coding and the durable-write primitive for restore's own files.
enum HolyRestoreFileCoding {
    /// Dates as exact epoch seconds: ISO 8601 would drop the fraction and a
    /// ledger read back would no longer equal the one written.
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    /// Write to a sibling temp file, force it through the disk cache with
    /// `F_FULLFSYNC` (what SQLite does for its own durability on macOS), then
    /// rename over the destination so a reader sees the old file or the new
    /// one, never a torn one.
    static func writeDurably(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let tempURL = directory.appendingPathComponent(
            ".\(url.lastPathComponent).\(UUID().uuidString).tmp",
            isDirectory: false
        )

        let descriptor = open(tempURL.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        var failure: Error?
        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = write(descriptor, base.advanced(by: offset), buffer.count - offset)
                if written < 0 {
                    failure = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                    return
                }
                offset += written
            }
        }
        if failure == nil, fcntl(descriptor, F_FULLFSYNC) < 0 {
            // F_FULLFSYNC is refused on some file systems (network mounts);
            // fall back to fsync so the write is still ordered.
            if fsync(descriptor) < 0 {
                failure = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
        close(descriptor)
        if let failure {
            try? FileManager.default.removeItem(at: tempURL)
            throw failure
        }

        if rename(tempURL.path, url.path) != 0 {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }
}
