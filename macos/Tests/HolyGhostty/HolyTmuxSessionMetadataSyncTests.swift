import Foundation
import Testing
@testable import Ghostty

private let holyTmuxAvailableForSessionMetadataTests: Bool = {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-lc", "command -v tmux >/dev/null 2>&1"]
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        return false
    }
}()

struct HolyTmuxSessionMetadataSyncTests {
    @Test func multilineEmojiNoteEncodingRoundTripsByteExactly() throws {
        let note = "First line\nSecond line 👻\nCompass: 🧭"
        let encoded = try #require(HolyTmuxSessionMetadataCodec.encodeNote(note))

        #expect(Data(base64Encoded: encoded) == Data(note.utf8))
        #expect(HolyTmuxSessionMetadataCodec.decodeNote(encoded) == .value(note))
    }

    @Test func deletionEncodingIsDistinctFromAbsentAndOversizeFailsClosed() {
        #expect(HolyTmuxSessionMetadataCodec.encodeNote(nil) == "")
        #expect(HolyTmuxSessionMetadataCodec.decodeNote("") == .value(nil))
        #expect(HolyTmuxSessionMetadataCodec.decodeNote("%%%not-base64%%") == .invalid)

        let oversized = String(repeating: "é", count: 2_049)
        #expect(Data(oversized.utf8).count == 4_098)
        #expect(HolyTmuxSessionMetadataCodec.encodeNote(oversized) == nil)
    }

    @Test func strictlyNewerRemoteValueWinsAndKeepsItsStamp() {
        let local = HolyTmuxSessionMetadataField(
            value: "local",
            updatedAtMilliseconds: 100,
            isPresent: true
        )
        let remote = HolyTmuxSessionMetadataField(
            value: "remote",
            updatedAtMilliseconds: 101,
            isPresent: true
        )

        #expect(
            HolyTmuxSessionMetadataMerge.action(local: local, remote: remote)
                == .applyRemote(value: "remote", updatedAtMilliseconds: 101)
        )
    }

    @Test func olderRemoteValueRepublishesNewerLocalValue() {
        let local = HolyTmuxSessionMetadataField(
            value: "local",
            updatedAtMilliseconds: 200,
            isPresent: true
        )
        let remote = HolyTmuxSessionMetadataField(
            value: "remote",
            updatedAtMilliseconds: 199,
            isPresent: true
        )

        #expect(HolyTmuxSessionMetadataMerge.action(local: local, remote: remote) == .publishLocal)
    }

    @Test func equalOrTimestampLessRemoteNeverClobbersLocalValue() {
        let local = HolyTmuxSessionMetadataField(
            value: "local",
            updatedAtMilliseconds: 300,
            isPresent: true
        )
        let equalRemote = HolyTmuxSessionMetadataField(
            value: "different",
            updatedAtMilliseconds: 300,
            isPresent: true
        )
        let timestampLessRemote = HolyTmuxSessionMetadataField(
            value: "different",
            updatedAtMilliseconds: nil,
            isPresent: true
        )

        #expect(HolyTmuxSessionMetadataMerge.action(local: local, remote: equalRemote) == .keepLocal)
        #expect(HolyTmuxSessionMetadataMerge.action(local: local, remote: timestampLessRemote) == .keepLocal)
    }

    @Test func absentRemoteSelfHealsLocalButDoesNotManufactureBlankState() {
        let localNote = HolyTmuxSessionMetadataField(
            value: Optional("legacy local note"),
            updatedAtMilliseconds: nil,
            isPresent: true
        )
        let blankLocal = HolyTmuxSessionMetadataField<String?>(
            value: nil,
            updatedAtMilliseconds: nil,
            isPresent: false
        )

        #expect(HolyTmuxSessionMetadataMerge.action(local: localNote, remote: nil) == .publishLocal)
        #expect(HolyTmuxSessionMetadataMerge.action(local: blankLocal, remote: nil) == .keepLocal)
    }

    @Test func newerDeletionClearsWhileAbsentOptionDoesNot() {
        let local = HolyTmuxSessionMetadataField<String?>(
            value: "keep me",
            updatedAtMilliseconds: 400,
            isPresent: true
        )
        let deletion = HolyTmuxSessionMetadataField<String?>(
            value: nil,
            updatedAtMilliseconds: 401,
            isPresent: true
        )

        #expect(
            HolyTmuxSessionMetadataMerge.action(local: local, remote: deletion)
                == .applyRemote(value: nil, updatedAtMilliseconds: 401)
        )
        #expect(HolyTmuxSessionMetadataMerge.action(local: local, remote: nil) == .publishLocal)
    }

    @Test func emptyLocalStateAdoptsVersionedRemotePin() {
        let local = HolyTmuxSessionMetadataField(
            value: false,
            updatedAtMilliseconds: nil,
            isPresent: false
        )
        let remote = HolyTmuxSessionMetadataField(
            value: true,
            updatedAtMilliseconds: 500,
            isPresent: true
        )

        #expect(
            HolyTmuxSessionMetadataMerge.action(local: local, remote: remote)
                == .applyRemote(value: true, updatedAtMilliseconds: 500)
        )
    }

    @Test func localEditStampIsMonotonicWithinOneMillisecond() {
        #expect(HolyTmuxSessionMetadataClock.next(nowMilliseconds: 700, after: nil) == 700)
        #expect(HolyTmuxSessionMetadataClock.next(nowMilliseconds: 700, after: 700) == 701)
        #expect(HolyTmuxSessionMetadataClock.next(nowMilliseconds: 699, after: 700) == 701)
    }

    @Test func deliveryCoalescesPendingFieldsWithoutRepublishingDeliveredFields() throws {
        var launchSpec = HolySessionLaunchSpec.interactiveTmuxShell()
        launchSpec.note = "first"
        launchSpec.noteUpdatedAtMilliseconds = 710
        launchSpec.isFocused = true
        launchSpec.todayPinUpdatedAtMilliseconds = 711
        let note = try #require(
            HolyTmuxSessionMetadataPayload(
                launchSpec: launchSpec,
                includeNote: true,
                includeTodayPin: false
            )
        )
        let pin = try #require(
            HolyTmuxSessionMetadataPayload(
                launchSpec: launchSpec,
                includeNote: false,
                includeTodayPin: true
            )
        )

        var state = HolyTmuxSessionMetadataDeliveryState()
        let start = Date(timeIntervalSince1970: 1_000)
        state.request(note)
        let firstValue = state.beginAttempt(now: start)
        let first = try #require(firstValue)
        state.request(pin)
        state.complete(first, succeeded: false, now: start)

        #expect(state.beginAttempt(now: start.addingTimeInterval(0.5)) == nil)
        let combinedValue = state.beginAttempt(now: start.addingTimeInterval(1.1))
        let combined = try #require(combinedValue)
        #expect(combined.payload.encodedNote == note.encodedNote)
        #expect(combined.payload.todayPin == true)
        state.complete(combined, succeeded: true, now: start.addingTimeInterval(1.1))

        launchSpec.note = "second"
        launchSpec.noteUpdatedAtMilliseconds = 712
        let secondNote = try #require(
            HolyTmuxSessionMetadataPayload(
                launchSpec: launchSpec,
                includeNote: true,
                includeTodayPin: false
            )
        )
        state.request(secondNote)
        let nextValue = state.beginAttempt(now: start.addingTimeInterval(2))
        let next = try #require(nextValue)
        #expect(next.payload.encodedNote == secondNote.encodedNote)
        #expect(next.payload.todayPin == nil)
    }

    @Test func commandFailsClosedWithoutExactStoredIdentityAndBoundsRemoteSSH() throws {
        var launchSpec = HolySessionLaunchSpec.interactiveTmuxShell()
        launchSpec.note = "hello"
        launchSpec.noteUpdatedAtMilliseconds = 800
        launchSpec.tmux = .init(socketName: "holy", sessionName: "metadata-session", createIfMissing: false)
        let payload = try #require(HolyTmuxSessionMetadataPayload(launchSpec: launchSpec))
        let localCommand = try #require(
            HolyTmuxSessionMetadataUpdateCommand.command(for: launchSpec, payload: payload)
        )
        let localScript = try #require(localCommand.arguments.last)

        #expect(localScript.contains("unset TMUX TMUX_PANE TMUX_TMPDIR"))
        #expect(localScript.contains("'display-message' '-p' '-t' 'metadata-session' '#{session_id}'"))
        #expect(localScript.contains("[ \"$holy_session_name\" = 'metadata-session' ]"))
        #expect(localScript.contains("'-t' \"$holy_session_id\""))
        #expect(localScript.contains("'@holy_note_v1'"))
        #expect(localScript.contains("'@holy_note_updated_at_v1' '800'"))

        var missingName = launchSpec
        missingName.tmux?.sessionName = nil
        #expect(HolyTmuxSessionMetadataUpdateCommand.command(for: missingName, payload: payload) == nil)

        var missingSocket = launchSpec
        missingSocket.tmux?.socketName = nil
        #expect(HolyTmuxSessionMetadataUpdateCommand.command(for: missingSocket, payload: payload) == nil)

        var remote = launchSpec
        remote.transport = .init(kind: .ssh, hostLabel: "Studio", sshDestination: "studio")
        let remoteCommand = try #require(
            HolyTmuxSessionMetadataUpdateCommand.command(for: remote, payload: payload)
        )
        #expect(remoteCommand.executableURL.path == "/usr/bin/ssh")
        #expect(remoteCommand.arguments.contains("BatchMode=yes"))
        #expect(remoteCommand.arguments.contains("ConnectTimeout=5"))
        #expect(remoteCommand.arguments.contains("ConnectionAttempts=1"))
        #expect(remoteCommand.arguments.contains("ServerAliveInterval=5"))
        #expect(remoteCommand.arguments.contains("ServerAliveCountMax=1"))
    }

    @Test(.enabled(if: holyTmuxAvailableForSessionMetadataTests))
    func realTmuxCommandRejectsPrefixOnlySessionMatch() throws {
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let socketName = "hmf-\(suffix.prefix(12))"
        let expectedName = "metadata-\(suffix.prefix(8))"
        let actualName = "\(expectedName)-other"
        #expect(
            runShell(
                "tmux -L \(socketName) -f /dev/null new-session -d "
                    + "-s \(actualName) 'sleep 30'"
            ) == 0
        )
        defer { _ = runShell("tmux -L \(socketName) kill-server >/dev/null 2>&1 || true") }

        var launchSpec = HolySessionLaunchSpec.interactiveTmuxShell()
        launchSpec.note = "must not land on a prefix match"
        launchSpec.noteUpdatedAtMilliseconds = 900
        launchSpec.tmux = .init(
            socketName: socketName,
            sessionName: expectedName,
            createIfMissing: false
        )
        let payload = try #require(HolyTmuxSessionMetadataPayload(launchSpec: launchSpec))
        let command = try #require(
            HolyTmuxSessionMetadataUpdateCommand.command(for: launchSpec, payload: payload)
        )

        #expect(!command.run())
        #expect(
            runShellOutput(
                "tmux -L \(socketName) show-options -qv -t \(actualName) @holy_note_v1"
            ) == ""
        )
    }

    @Test(.enabled(if: holyTmuxAvailableForSessionMetadataTests))
    func realTmuxPTYRoundTripsVersionedNoteAndPinThroughDiscovery() async throws {
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let socketName = "hms-\(suffix.prefix(12))"
        let sessionName = "metadata-\(suffix.prefix(12))"
        let captureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("holy-metadata-pty-\(suffix).typescript")
        defer { try? FileManager.default.removeItem(at: captureURL) }

        #expect(
            runShell(
                "unset TMUX TMUX_PANE TMUX_TMPDIR; "
                    + "tmux -L \(socketName) -f /dev/null new-session -d -s \(sessionName) 'sleep 30'"
            ) == 0
        )
        defer { _ = runShell("tmux -L \(socketName) kill-server >/dev/null 2>&1 || true") }

        let attach = Process()
        attach.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        let tmuxExecutable = try #require(runShellOutput("command -v tmux"))
        attach.arguments = [
            "-q", "-F", captureURL.path,
            tmuxExecutable, "-L", socketName,
            "attach-session", "-t", sessionName,
        ]
        var attachEnvironment = ProcessInfo.processInfo.environment
        attachEnvironment.removeValue(forKey: "TMUX")
        attachEnvironment.removeValue(forKey: "TMUX_PANE")
        attachEnvironment.removeValue(forKey: "TMUX_TMPDIR")
        attachEnvironment["TERM"] = "xterm-256color"
        attach.environment = attachEnvironment
        attach.standardInput = Pipe()
        attach.standardOutput = Pipe()
        attach.standardError = Pipe()
        try attach.run()
        defer {
            if attach.isRunning { attach.terminate() }
        }

        #expect(try waitUntil(timeout: 3) {
            runShellOutput("tmux -L \(socketName) list-clients -F '#{client_name}'")?.isEmpty == false
        })

        let note = "Cross-host line one\nline two 👻🧭"
        var launchSpec = HolySessionLaunchSpec.interactiveTmuxShell(title: "Metadata Roundtrip")
        launchSpec.note = note
        launchSpec.noteUpdatedAtMilliseconds = 1_784_555_000_123
        launchSpec.isFocused = true
        launchSpec.todayPinUpdatedAtMilliseconds = 1_784_555_000_124
        launchSpec.tmux = .init(
            socketName: socketName,
            sessionName: sessionName,
            createIfMissing: false
        )
        let payload = try #require(HolyTmuxSessionMetadataPayload(launchSpec: launchSpec))
        let command = try #require(
            HolyTmuxSessionMetadataUpdateCommand.command(for: launchSpec, payload: payload)
        )
        #expect(command.run())

        #expect(
            runShellOutput("tmux -L \(socketName) show-options -qv -t '\(sessionName)' @holy_note_v1")
                == HolyTmuxSessionMetadataCodec.encodeNote(note)
        )
        #expect(
            runShellOutput("tmux -L \(socketName) show-options -qv -t '\(sessionName)' @holy_note_updated_at_v1")
                == "1784555000123"
        )
        #expect(
            runShellOutput("tmux -L \(socketName) show-options -qv -t '\(sessionName)' @holy_today_pin_v1") == "1"
        )
        #expect(
            runShellOutput("tmux -L \(socketName) show-options -qv -t '\(sessionName)' @holy_today_pin_updated_at_v1")
                == "1784555000124"
        )

        let sessions = try await HolyRemoteTmuxDiscoveryService.shared
            .discoverLocalSessionsThrowing(
                hostID: UUID(),
                hostLabel: "This Mac",
                tmuxSocketName: socketName,
                timeout: 3,
                includeHiddenSessions: true
            )
        let discovered = try #require(sessions.first)
        #expect(discovered.sessionName == sessionName)
        #expect(discovered.synchronizedMetadata.note?.value == note)
        #expect(discovered.synchronizedMetadata.note?.updatedAtMilliseconds == 1_784_555_000_123)
        #expect(discovered.synchronizedMetadata.todayPin?.value == true)
        #expect(discovered.synchronizedMetadata.todayPin?.updatedAtMilliseconds == 1_784_555_000_124)

        _ = runShell("tmux -L \(socketName) kill-server >/dev/null 2>&1 || true")
        #expect(try waitUntil(timeout: 3) { !attach.isRunning })
    }

    private func runShell(_ script: String) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "unset TMUX TMUX_PANE TMUX_TMPDIR; \(script)"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }

    private func runShellOutput(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "unset TMUX TMUX_PANE TMUX_TMPDIR; \(script)"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(
                data: output.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private func waitUntil(
        timeout: TimeInterval,
        condition: () throws -> Bool
    ) throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try condition() { return true }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return try condition()
    }
}
