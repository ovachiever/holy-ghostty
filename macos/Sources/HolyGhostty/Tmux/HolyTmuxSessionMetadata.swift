import Darwin
import Foundation

enum HolyTmuxDecodedNote: Equatable, Sendable {
    case value(String?)
    case invalid
}

enum HolyTmuxSessionMetadataCodec {
    static let maximumNoteUTF8Bytes = 4_096

    static func encodeNote(_ note: String?) -> String? {
        guard let note else { return "" }
        let data = Data(note.utf8)
        guard data.count <= maximumNoteUTF8Bytes else { return nil }
        return data.base64EncodedString()
    }

    static func decodeNote(_ encodedNote: String) -> HolyTmuxDecodedNote {
        guard let data = Data(base64Encoded: encodedNote),
              data.count <= maximumNoteUTF8Bytes,
              let decoded = String(data: data, encoding: .utf8) else {
            return .invalid
        }
        return .value(decoded.isEmpty ? nil : decoded)
    }

    static func decodeSnapshot(
        encodedNote: String,
        noteUpdatedAt: String,
        todayPin: String,
        todayPinUpdatedAt: String
    ) -> HolyTmuxSessionMetadataSnapshot {
        let noteWasPresent = !encodedNote.isEmpty || !noteUpdatedAt.isEmpty
        let note: HolyTmuxSessionMetadataField<String?>?
        if noteWasPresent {
            switch decodeNote(encodedNote) {
            case let .value(value):
                note = .init(
                    value: value,
                    updatedAtMilliseconds: timestamp(from: noteUpdatedAt),
                    isPresent: true
                )
            case .invalid:
                note = .init(
                    value: nil,
                    updatedAtMilliseconds: nil,
                    isPresent: true,
                    isValid: false
                )
            }
        } else {
            note = nil
        }

        let todayPinWasPresent = !todayPin.isEmpty || !todayPinUpdatedAt.isEmpty
        let decodedTodayPin: HolyTmuxSessionMetadataField<Bool>?
        if todayPinWasPresent {
            switch todayPin {
            case "1":
                decodedTodayPin = .init(
                    value: true,
                    updatedAtMilliseconds: timestamp(from: todayPinUpdatedAt),
                    isPresent: true
                )
            case "0":
                decodedTodayPin = .init(
                    value: false,
                    updatedAtMilliseconds: timestamp(from: todayPinUpdatedAt),
                    isPresent: true
                )
            default:
                decodedTodayPin = .init(
                    value: false,
                    updatedAtMilliseconds: nil,
                    isPresent: true,
                    isValid: false
                )
            }
        } else {
            decodedTodayPin = nil
        }

        return .init(note: note, todayPin: decodedTodayPin)
    }

    private static func timestamp(from rawValue: String) -> Int64? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int64(trimmed), value >= 0 else { return nil }
        return value
    }
}

struct HolyTmuxSessionMetadataField<Value: Equatable & Sendable>: Equatable, Sendable {
    let value: Value
    let updatedAtMilliseconds: Int64?
    let isPresent: Bool
    let isValid: Bool

    init(
        value: Value,
        updatedAtMilliseconds: Int64?,
        isPresent: Bool,
        isValid: Bool = true
    ) {
        self.value = value
        self.updatedAtMilliseconds = updatedAtMilliseconds
        self.isPresent = isPresent
        self.isValid = isValid
    }
}

struct HolyTmuxSessionMetadataSnapshot: Equatable, Sendable {
    var note: HolyTmuxSessionMetadataField<String?>?
    var todayPin: HolyTmuxSessionMetadataField<Bool>?

    static let empty = Self()
}

enum HolyTmuxSessionMetadataMergeAction<Value: Equatable & Sendable>: Equatable, Sendable {
    case keepLocal
    case applyRemote(value: Value, updatedAtMilliseconds: Int64)
    case publishLocal
}

enum HolyTmuxSessionMetadataMerge {
    static func action<Value: Equatable & Sendable>(
        local: HolyTmuxSessionMetadataField<Value>,
        remote: HolyTmuxSessionMetadataField<Value>?
    ) -> HolyTmuxSessionMetadataMergeAction<Value> {
        guard let remote else {
            return local.isPresent ? .publishLocal : .keepLocal
        }
        guard remote.isValid,
              let remoteUpdatedAt = remote.updatedAtMilliseconds else {
            return .keepLocal
        }

        guard let localUpdatedAt = local.updatedAtMilliseconds else {
            if !local.isPresent || local.value == remote.value {
                return .applyRemote(
                    value: remote.value,
                    updatedAtMilliseconds: remoteUpdatedAt
                )
            }
            return .keepLocal
        }

        if remoteUpdatedAt > localUpdatedAt {
            return .applyRemote(
                value: remote.value,
                updatedAtMilliseconds: remoteUpdatedAt
            )
        }
        if remoteUpdatedAt < localUpdatedAt {
            return .publishLocal
        }
        return .keepLocal
    }
}

enum HolyTmuxSessionMetadataClock {
    static func next(nowMilliseconds: Int64, after previous: Int64?) -> Int64 {
        guard let previous else { return nowMilliseconds }
        guard previous < Int64.max else { return Int64.max }
        return max(nowMilliseconds, previous + 1)
    }

    static func next(after previous: Int64?, now: Date = .now) -> Int64 {
        let milliseconds = Int64((now.timeIntervalSince1970 * 1_000).rounded(.down))
        return next(nowMilliseconds: milliseconds, after: previous)
    }
}

struct HolyTmuxSessionMetadataPayload: Equatable, Sendable {
    let encodedNote: String?
    let noteUpdatedAtMilliseconds: Int64?
    let todayPin: Bool?
    let todayPinUpdatedAtMilliseconds: Int64?

    init?(
        launchSpec: HolySessionLaunchSpec,
        includeNote: Bool = true,
        includeTodayPin: Bool = true
    ) {
        var encodedNote: String?
        var noteUpdatedAtMilliseconds: Int64?
        if includeNote,
           let timestamp = launchSpec.noteUpdatedAtMilliseconds,
           let encoded = HolyTmuxSessionMetadataCodec.encodeNote(launchSpec.note) {
            encodedNote = encoded
            noteUpdatedAtMilliseconds = timestamp
        }

        let todayPin: Bool?
        let todayPinUpdatedAtMilliseconds: Int64?
        if includeTodayPin,
           let timestamp = launchSpec.todayPinUpdatedAtMilliseconds {
            todayPin = launchSpec.isFocused ?? false
            todayPinUpdatedAtMilliseconds = timestamp
        } else {
            todayPin = nil
            todayPinUpdatedAtMilliseconds = nil
        }

        guard noteUpdatedAtMilliseconds != nil || todayPinUpdatedAtMilliseconds != nil else {
            return nil
        }
        self.encodedNote = encodedNote
        self.noteUpdatedAtMilliseconds = noteUpdatedAtMilliseconds
        self.todayPin = todayPin
        self.todayPinUpdatedAtMilliseconds = todayPinUpdatedAtMilliseconds
    }

    private init(
        encodedNote: String?,
        noteUpdatedAtMilliseconds: Int64?,
        todayPin: Bool?,
        todayPinUpdatedAtMilliseconds: Int64?
    ) {
        self.encodedNote = encodedNote
        self.noteUpdatedAtMilliseconds = noteUpdatedAtMilliseconds
        self.todayPin = todayPin
        self.todayPinUpdatedAtMilliseconds = todayPinUpdatedAtMilliseconds
    }

    func merging(_ newer: Self) -> Self {
        let hasNewerNote = newer.noteUpdatedAtMilliseconds != nil
        let hasNewerTodayPin = newer.todayPinUpdatedAtMilliseconds != nil
        return .init(
            encodedNote: hasNewerNote ? newer.encodedNote : encodedNote,
            noteUpdatedAtMilliseconds: hasNewerNote
                ? newer.noteUpdatedAtMilliseconds
                : noteUpdatedAtMilliseconds,
            todayPin: hasNewerTodayPin ? newer.todayPin : todayPin,
            todayPinUpdatedAtMilliseconds: hasNewerTodayPin
                ? newer.todayPinUpdatedAtMilliseconds
                : todayPinUpdatedAtMilliseconds
        )
    }
}

struct HolyTmuxSessionMetadataUpdateCommand: Sendable, Equatable {
    let executableURL: URL
    let arguments: [String]

    static func command(
        for launchSpec: HolySessionLaunchSpec,
        payload: HolyTmuxSessionMetadataPayload
    ) -> Self? {
        // Session metadata is user-authored authority. Never realize missing
        // identity or fall back to an ambient/default tmux server.
        guard let tmux = launchSpec.tmux?.normalized,
              let socketName = tmux.socketName?.holyMetadataTrimmed.nilIfEmpty,
              let sessionName = tmux.sessionName?.holyMetadataTrimmed.nilIfEmpty else {
            return nil
        }

        let tmuxArguments = ["tmux", "-L", socketName]
        let tmuxCommandPrefix = shellCommand(tmuxArguments)
        let resolveSessionID = shellCommand(tmuxArguments + [
            "display-message", "-p", "-t", sessionName, "#{session_id}",
        ])
        let resolveSessionNamePrefix = shellCommand(tmuxArguments + [
            "display-message", "-p", "-t",
        ])
        let resolveSessionNameSuffix = shellCommand(["#{session_name}"])
        var commands: [String] = []
        if let encodedNote = payload.encodedNote,
           let updatedAt = payload.noteUpdatedAtMilliseconds {
            commands.append(
                "\(tmuxCommandPrefix) 'set-option' '-q' '-t' \"$holy_session_id\" "
                    + "'@holy_note_v1' \(posixQuote(encodedNote))"
            )
            commands.append(
                "\(tmuxCommandPrefix) 'set-option' '-q' '-t' \"$holy_session_id\" "
                    + "'@holy_note_updated_at_v1' '\(updatedAt)'"
            )
        }
        if let todayPin = payload.todayPin,
           let updatedAt = payload.todayPinUpdatedAtMilliseconds {
            commands.append(
                "\(tmuxCommandPrefix) 'set-option' '-q' '-t' \"$holy_session_id\" "
                    + "'@holy_today_pin_v1' '\(todayPin ? "1" : "0")'"
            )
            commands.append(
                "\(tmuxCommandPrefix) 'set-option' '-q' '-t' \"$holy_session_id\" "
                    + "'@holy_today_pin_updated_at_v1' '\(updatedAt)'"
            )
        }
        guard !commands.isEmpty else { return nil }

        // tmux 3.7b documents `=name` as exact matching, but set-option treats
        // it as an invalid target and `-q` turns that into a successful no-op.
        // Resolve the stored name once, verify the resolved name byte-for-byte,
        // then write only through tmux's immutable server-local session ID.
        // A missing, ambiguous, or prefix/glob-only match therefore fails
        // closed and can never redirect metadata to a neighboring session.
        let exactIdentityPreamble = [
            "holy_session_id=$(\(resolveSessionID)) || exit 1",
            "[ -n \"$holy_session_id\" ] || exit 1",
            "holy_session_name=$(\(resolveSessionNamePrefix) \"$holy_session_id\" \(resolveSessionNameSuffix)) || exit 1",
            "[ \"$holy_session_name\" = \(posixQuote(sessionName)) ] || exit 1",
        ]
        // Each field's timestamp lands after its value. `&&` prevents a new
        // authority stamp from becoming visible when the corresponding value
        // write failed; retries are idempotent.
        let tmuxScript = (exactIdentityPreamble + commands).joined(separator: " && ")
        if launchSpec.transport.isRemote {
            guard let destination = launchSpec.transport.sshDestination?
                .holyMetadataTrimmed.nilIfEmpty else {
                return nil
            }
            return .init(
                executableURL: URL(fileURLWithPath: "/usr/bin/ssh"),
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    "-o", "ConnectionAttempts=1",
                    "-o", "ServerAliveInterval=5",
                    "-o", "ServerAliveCountMax=1",
                    destination,
                    "zsh -lc \(posixQuote(tmuxScript))",
                ]
            )
        }

        return .init(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: [
                "-lc",
                "unset TMUX TMUX_PANE TMUX_TMPDIR; \(tmuxScript)",
            ]
        )
    }

    @discardableResult
    func run(timeout: TimeInterval = 10) -> Bool {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            guard !process.isRunning else {
                process.terminate()
                let terminationDeadline = Date().addingTimeInterval(0.5)
                while process.isRunning, Date() < terminationDeadline {
                    Thread.sleep(forTimeInterval: 0.025)
                }
                if process.isRunning {
                    _ = Darwin.kill(process.processIdentifier, SIGKILL)
                }
                return false
            }
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func shellCommand(_ arguments: [String]) -> String {
        arguments.map(posixQuote).joined(separator: " ")
    }

    private static func posixQuote(_ value: String) -> String {
        if value.isEmpty { return "''" }
        return "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}

struct HolyTmuxSessionMetadataDeliveryState {
    struct Attempt: Equatable, Sendable {
        let payload: HolyTmuxSessionMetadataPayload
    }

    private(set) var desired: Attempt?
    private(set) var delivered: Attempt?
    private(set) var inFlight: Attempt?
    private(set) var retryAttempt = 0
    private(set) var retryNotBefore: Date = .distantPast

    mutating func request(_ payload: HolyTmuxSessionMetadataPayload) {
        let attempt = Attempt(payload: payload)
        if inFlight != nil || desired != delivered,
           let desired {
            self.desired = .init(payload: desired.payload.merging(payload))
        } else {
            desired = attempt
        }
    }

    mutating func beginAttempt(now: Date = .now) -> Attempt? {
        guard inFlight == nil,
              let desired,
              desired != delivered,
              now >= retryNotBefore else {
            return nil
        }
        inFlight = desired
        return desired
    }

    mutating func complete(
        _ attempt: Attempt,
        succeeded: Bool,
        now: Date = .now
    ) {
        guard inFlight == attempt else { return }
        inFlight = nil
        if succeeded {
            delivered = attempt
            retryAttempt = 0
            retryNotBefore = .distantPast
        } else {
            retryAttempt = min(retryAttempt + 1, 5)
            retryNotBefore = now.addingTimeInterval(pow(2, Double(retryAttempt - 1)))
        }
    }

    func retryDelay(now: Date = .now) -> TimeInterval? {
        guard desired != delivered, inFlight == nil else { return nil }
        return max(0, retryNotBefore.timeIntervalSince(now))
    }
}

private extension String {
    var holyMetadataTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
