import Darwin
import Foundation
import Security

struct HolyMannaActorIdentity: Codable, Equatable, Sendable {
    let sessionID: String
    let token: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case token
        case createdAt = "created_at"
    }

    var environment: [String: String] {
        [
            "MANNA_SESSION_ID": sessionID,
            "MANNA_SESSION_TOKEN": token,
        ]
    }

    var isValid: Bool {
        sessionID.hasPrefix("holy-")
            && sessionID.utf8.count <= 80
            && sessionID.utf8.allSatisfy { byte in
                (48 ... 57).contains(byte)
                    || (97 ... 122).contains(byte)
                    || byte == 45
            }
            && token.utf8.count == 64
            && token.utf8.allSatisfy { byte in
                (48 ... 57).contains(byte) || (97 ... 102).contains(byte)
            }
    }
}

enum HolyMannaActorIdentityError: LocalizedError {
    case randomGenerationFailed(Int32)
    case unsafeIdentityFile(String)
    case unreadableIdentityFile(String)
    case invalidIdentityFile(String)
    case createFailed(String, Int32)
    case writeFailed(String, Int32)

    var errorDescription: String? {
        switch self {
        case let .randomGenerationFailed(code):
            "Holy could not generate a secure Manna actor identity (Security \(code))."
        case let .unsafeIdentityFile(path):
            "Holy refused the Manna actor identity because it is not a private regular file: \(path)"
        case let .unreadableIdentityFile(path):
            "Holy could not read its Manna actor identity: \(path)"
        case let .invalidIdentityFile(path):
            "Holy's Manna actor identity is malformed and was not replaced automatically: \(path)"
        case let .createFailed(path, code):
            "Holy could not create its Manna actor identity at \(path) (errno \(code))."
        case let .writeFailed(path, code):
            "Holy could not finish writing its Manna actor identity at \(path) (errno \(code))."
        }
    }
}

actor HolyMannaActorIdentityStore {
    static let shared = HolyMannaActorIdentityStore()

    private var cached: HolyMannaActorIdentity?
    private let fileURL: URL

    init(fileURL: URL = HolyDatabasePaths.containerDirectory.appendingPathComponent("manna-actor.json")) {
        self.fileURL = fileURL
    }

    func identity() throws -> HolyMannaActorIdentity {
        if let cached { return cached }

        let identity: HolyMannaActorIdentity
        if fileExistsWithoutFollowingSymlinks(at: fileURL.path) {
            identity = try readIdentity()
        } else {
            identity = try createIdentity()
        }
        cached = identity
        return identity
    }

    private func readIdentity() throws -> HolyMannaActorIdentity {
        var info = stat()
        guard lstat(fileURL.path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG else {
            throw HolyMannaActorIdentityError.unsafeIdentityFile(fileURL.path)
        }

        // Repair only permissions on Holy's own regular file. A symlink,
        // directory, or malformed payload remains a hard refusal.
        if info.st_mode & 0o077 != 0, chmod(fileURL.path, 0o600) != 0 {
            throw HolyMannaActorIdentityError.unsafeIdentityFile(fileURL.path)
        }

        guard let data = try? Data(contentsOf: fileURL), data.count <= 4_096 else {
            throw HolyMannaActorIdentityError.unreadableIdentityFile(fileURL.path)
        }
        guard let identity = try? JSONDecoder().decode(HolyMannaActorIdentity.self, from: data),
              identity.isValid else {
            throw HolyMannaActorIdentityError.invalidIdentityFile(fileURL.path)
        }
        return identity
    }

    private func createIdentity() throws -> HolyMannaActorIdentity {
        try HolyDatabasePaths.ensureContainerDirectory()
        let identity = HolyMannaActorIdentity(
            sessionID: "holy-\(try randomHex(byteCount: 8))",
            token: try randomHex(byteCount: 32),
            createdAt: ISO8601DateFormatter().string(from: .now)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(identity)
        data.append(0x0A)

        let descriptor = Darwin.open(
            fileURL.path,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
            S_IRUSR | S_IWUSR
        )
        if descriptor == -1 {
            if errno == EEXIST {
                return try readIdentity()
            }
            throw HolyMannaActorIdentityError.createFailed(fileURL.path, errno)
        }

        var writeError: Int32?
        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), rawBuffer.count - offset)
                if count < 0 {
                    writeError = errno
                    break
                }
                offset += count
            }
        }
        if writeError == nil, fsync(descriptor) != 0 {
            writeError = errno
        }
        _ = Darwin.close(descriptor)

        if let writeError {
            // A partial secret is unusable. Refuse it on the next read rather
            // than silently replacing identity and invalidating claim proofs.
            throw HolyMannaActorIdentityError.writeFailed(fileURL.path, writeError)
        }
        return identity
    }

    private func randomHex(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        guard status == errSecSuccess else {
            throw HolyMannaActorIdentityError.randomGenerationFailed(status)
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func fileExistsWithoutFollowingSymlinks(at path: String) -> Bool {
        var info = stat()
        if lstat(path, &info) == 0 { return true }
        return errno != ENOENT
    }
}
