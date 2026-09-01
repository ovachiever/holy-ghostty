import Foundation

struct HolyMannaProcessInvocation: Equatable, Sendable {
    let executablePath: String
    let arguments: [String]
    let currentDirectoryPath: String?
    let environment: [String: String]
    let stdin: Data?
    let displayCommand: String
}

struct HolyMannaProcessOutput: Equatable, Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

enum HolyMannaBoardClientError: LocalizedError, Equatable {
    case noFocusedBoard
    case localBinaryMissing
    case launchFailed(String)
    case timedOut(String)
    case outputTooLarge(String)
    case commandFailed(command: String, code: Int32, detail: String?)
    case invalidPayload(command: String)
    case rejectedPayload(command: String)

    var errorDescription: String? {
        switch self {
        case .noFocusedBoard:
            "Select a session with a repository or working directory, or choose a board from the estate strip."
        case .localBinaryMissing:
            "The agent-do CLI was not found in the runtime environment Holy uses."
        case let .launchFailed(detail):
            "The Manna command could not start: \(detail)"
        case let .timedOut(command):
            "\(command) did not finish before the safety deadline."
        case let .outputTooLarge(command):
            "\(command) exceeded Holy's 8 MB structured-output limit."
        case let .commandFailed(command, code, detail):
            "\(command) exited with status \(code)." + (detail.map { " \($0)" } ?? "")
        case let .invalidPayload(command):
            "\(command) returned data outside the canonical JSON contract."
        case let .rejectedPayload(command):
            "\(command) returned success=false."
        }
    }
}

struct HolyMannaMutationReceipt: Equatable, Sendable {
    let command: String
    let output: String
}

struct HolyMannaBoardClient: Sendable {
    typealias Runner = @Sendable (HolyMannaProcessInvocation, TimeInterval) async throws -> HolyMannaProcessOutput

    static let stateTimeout: TimeInterval = 90
    static let estateTimeout: TimeInterval = 60
    static let mutationTimeout: TimeInterval = 60

    private let runner: Runner
    private let identityStore: HolyMannaActorIdentityStore

    init(
        identityStore: HolyMannaActorIdentityStore = .shared,
        runner: @escaping Runner = { invocation, timeout in
            try await HolyMannaProcessRunner.run(invocation, timeout)
        }
    ) {
        self.identityStore = identityStore
        self.runner = runner
    }

    func actorIdentityLabel() async throws -> String {
        (try await identityStore.identity()).sessionID
    }

    func state(for context: HolyMannaBoardContext) async throws -> HolyMannaStatePayload {
        guard context.boardRoot != nil else { throw HolyMannaBoardClientError.noFocusedBoard }
        let invocation = try await invocation(
            arguments: ["manna", "state", "--json"],
            context: context,
            needsBoardRoot: true,
            identity: nil
        )
        let output = try await checkedRun(invocation, timeout: Self.stateTimeout)
        guard let payload = try? JSONDecoder().decode(HolyMannaStatePayload.self, from: Data(output.stdout.utf8)) else {
            throw HolyMannaBoardClientError.invalidPayload(command: invocation.displayCommand)
        }
        guard payload.success else {
            throw HolyMannaBoardClientError.rejectedPayload(command: invocation.displayCommand)
        }
        return payload
    }

    func estate(for context: HolyMannaBoardContext) async throws -> HolyMannaEstatePayload {
        let invocation = try await invocation(
            arguments: ["manna", "estate", "--json"],
            context: context,
            needsBoardRoot: false,
            identity: nil
        )
        let output = try await checkedRun(invocation, timeout: Self.estateTimeout)
        guard let payload = try? JSONDecoder().decode(HolyMannaEstatePayload.self, from: Data(output.stdout.utf8)) else {
            throw HolyMannaBoardClientError.invalidPayload(command: invocation.displayCommand)
        }
        return payload
    }

    func perform(
        _ mutation: HolyMannaMutation,
        in context: HolyMannaBoardContext
    ) async throws -> [HolyMannaMutationReceipt] {
        guard context.boardRoot != nil else { throw HolyMannaBoardClientError.noFocusedBoard }
        let identity = try await identityStore.identity()
        var receipts: [HolyMannaMutationReceipt] = []
        for command in mutation.commands {
            let invocation = try await invocation(
                arguments: command,
                context: context,
                needsBoardRoot: true,
                identity: identity
            )
            let output = try await checkedRun(invocation, timeout: Self.mutationTimeout)
            receipts.append(.init(
                command: invocation.displayCommand,
                output: output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }
        return receipts
    }

    static func remoteInvocation(
        arguments: [String],
        context: HolyMannaBoardContext,
        needsBoardRoot: Bool,
        identity: HolyMannaActorIdentity?
    ) throws -> HolyMannaProcessInvocation {
        guard let remoteHost = context.remoteHost else {
            preconditionFailure("remoteInvocation requires a remote host")
        }
        guard isValidRemoteHost(remoteHost) else {
            throw HolyMannaBoardClientError.launchFailed("invalid remote host")
        }
        if needsBoardRoot, context.boardRoot == nil {
            throw HolyMannaBoardClientError.noFocusedBoard
        }

        let sshArguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
            "-o", "ServerAliveInterval=5",
            "-o", "ServerAliveCountMax=1",
            "--",
            remoteHost,
        ]
        let command = (["agent-do"] + arguments).map(posixQuote).joined(separator: " ")
        let rootedCommand = context.boardRoot.map { "cd -- \(posixQuote($0)) && exec \(command)" } ?? "exec \(command)"

        if let identity {
            // Send the private proof through SSH stdin, never argv or logs.
            let script = """
            set -eu
            export MANNA_SESSION_ID=\(posixQuote(identity.sessionID))
            export MANNA_SESSION_TOKEN=\(posixQuote(identity.token))
            \(rootedCommand)
            """
            return .init(
                executablePath: "/usr/bin/ssh",
                arguments: sshArguments + ["zsh -l -s"],
                currentDirectoryPath: nil,
                environment: [:],
                stdin: Data(script.utf8),
                displayCommand: "\(remoteHost): agent-do \(arguments.joined(separator: " "))"
            )
        }

        return .init(
            executablePath: "/usr/bin/ssh",
            arguments: sshArguments + ["zsh -lc \(posixQuote(rootedCommand))"],
            currentDirectoryPath: nil,
            environment: [:],
            stdin: nil,
            displayCommand: "\(remoteHost): agent-do \(arguments.joined(separator: " "))"
        )
    }

    private static func isValidRemoteHost(_ value: String) -> Bool {
        guard let first = value.utf8.first,
              (48...57).contains(first)
                || (65...90).contains(first)
                || (97...122).contains(first) else {
            return false
        }

        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._@:-[]")
        return !value.isEmpty
            && value.unicodeScalars.allSatisfy(allowed.contains)
    }

    private func invocation(
        arguments: [String],
        context: HolyMannaBoardContext,
        needsBoardRoot: Bool,
        identity: HolyMannaActorIdentity?
    ) async throws -> HolyMannaProcessInvocation {
        if context.remoteHost != nil {
            return try Self.remoteInvocation(
                arguments: arguments,
                context: context,
                needsBoardRoot: needsBoardRoot,
                identity: identity
            )
        }

        if needsBoardRoot, context.boardRoot == nil {
            throw HolyMannaBoardClientError.noFocusedBoard
        }
        guard let binaryPath = await HolyMannaBinaryResolver.shared.binaryPath() else {
            throw HolyMannaBoardClientError.localBinaryMissing
        }
        return .init(
            executablePath: binaryPath,
            arguments: arguments,
            currentDirectoryPath: context.boardRoot ?? FileManager.default.homeDirectoryForCurrentUser.path,
            environment: identity?.environment ?? [:],
            stdin: nil,
            displayCommand: "agent-do \(arguments.joined(separator: " "))"
        )
    }

    private func checkedRun(
        _ invocation: HolyMannaProcessInvocation,
        timeout: TimeInterval
    ) async throws -> HolyMannaProcessOutput {
        let output = try await runner(invocation, timeout)
        guard output.exitCode == 0 else {
            let detail = output.stderr
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .last { !$0.isEmpty }
                .map { String($0.prefix(400)) }
            throw HolyMannaBoardClientError.commandFailed(
                command: invocation.displayCommand,
                code: output.exitCode,
                detail: detail
            )
        }
        return output
    }
}

private actor HolyMannaBinaryResolver {
    static let shared = HolyMannaBinaryResolver()

    private var cached: String?
    private var didResolve = false

    func binaryPath() async -> String? {
        if didResolve { return cached }
        didResolve = true

        let probe = HolyMannaProcessInvocation(
            executablePath: "/bin/zsh",
            arguments: ["-lc", "command -v agent-do"],
            currentDirectoryPath: nil,
            environment: [:],
            stdin: nil,
            displayCommand: "locate agent-do"
        )
        if let output = try? await HolyMannaProcessRunner.run(probe, 15),
           output.exitCode == 0 {
            let path = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if FileManager.default.isExecutableFile(atPath: path) {
                cached = path
                return path
            }
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for candidate in [
            "\(home)/.local/bin/agent-do",
            "/opt/homebrew/bin/agent-do",
            "/usr/local/bin/agent-do",
        ] where FileManager.default.isExecutableFile(atPath: candidate) {
            cached = candidate
            return candidate
        }
        return nil
    }
}

enum HolyMannaProcessRunner {
    private static let maximumOutputBytes = 8 * 1_024 * 1_024

    static func run(
        _ invocation: HolyMannaProcessInvocation,
        _ timeout: TimeInterval
    ) async throws -> HolyMannaProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: invocation.executablePath)
        process.arguments = invocation.arguments
        if let currentDirectoryPath = invocation.currentDirectoryPath {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectoryPath)
        }

        var environment = ProcessInfo.processInfo.environment
        // A GUI action must never inherit the coding session that launched
        // the app. Reads need no actor; writes overlay Holy's own identity.
        for key in ["MANNA_SESSION_ID", "MANNA_SESSION_TOKEN", "CLAUDE_SESSION_ID", "CODEX_THREAD_ID"] {
            environment.removeValue(forKey: key)
        }
        environment.merge(invocation.environment) { _, holyValue in holyValue }
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let stdin = invocation.stdin.map { _ in Pipe() }
        if let stdin {
            process.standardInput = stdin
        } else {
            process.standardInput = FileHandle.nullDevice
        }

        let continuationBox = HolyMannaContinuationBox()
        return try await withCheckedThrowingContinuation { continuation in
            continuationBox.store(continuation)
            let stdoutBox = HolyMannaDataBox()
            let stderrBox = HolyMannaDataBox()
            let drainGroup = DispatchGroup()

            process.terminationHandler = { finished in
                drainGroup.notify(queue: .global(qos: .utility)) {
                    let stdoutData = stdoutBox.take()
                    let stderrData = stderrBox.take()
                    guard stdoutData.count <= maximumOutputBytes,
                          stderrData.count <= maximumOutputBytes else {
                        continuationBox.resume(throwing: HolyMannaBoardClientError.outputTooLarge(
                            invocation.displayCommand
                        ))
                        return
                    }
                    continuationBox.resume(returning: .init(
                        stdout: String(bytes: stdoutData, encoding: .utf8) ?? "",
                        stderr: String(bytes: stderrData, encoding: .utf8) ?? "",
                        exitCode: finished.terminationStatus
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                continuationBox.resume(throwing: HolyMannaBoardClientError.launchFailed(
                    holyDetailedProcessLaunchErrorDescription(error)
                ))
                return
            }

            drainGroup.enter()
            DispatchQueue.global(qos: .utility).async {
                stdoutBox.store(stdout.fileHandleForReading.readDataToEndOfFile())
                drainGroup.leave()
            }
            drainGroup.enter()
            DispatchQueue.global(qos: .utility).async {
                stderrBox.store(stderr.fileHandleForReading.readDataToEndOfFile())
                drainGroup.leave()
            }

            if let input = invocation.stdin, let stdin {
                DispatchQueue.global(qos: .utility).async {
                    do {
                        try stdin.fileHandleForWriting.write(contentsOf: input)
                    } catch {
                        // The command's exit and stderr remain the canonical
                        // failure receipt. Never retry a board mutation here.
                    }
                    try? stdin.fileHandleForWriting.close()
                }
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                guard continuationBox.resume(throwing: HolyMannaBoardClientError.timedOut(
                    invocation.displayCommand
                )) else { return }
                if process.isRunning {
                    process.terminate()
                }
            }
        }
    }
}

private final class HolyMannaDataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func store(_ value: Data) {
        lock.lock()
        data = value
        lock.unlock()
    }

    func take() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

private final class HolyMannaContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<HolyMannaProcessOutput, Error>?
    private var completed = false

    func store(_ continuation: CheckedContinuation<HolyMannaProcessOutput, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    @discardableResult
    func resume(returning output: HolyMannaProcessOutput) -> Bool {
        complete { $0.resume(returning: output) }
    }

    @discardableResult
    func resume(throwing error: Error) -> Bool {
        complete { $0.resume(throwing: error) }
    }

    private func complete(_ body: (CheckedContinuation<HolyMannaProcessOutput, Error>) -> Void) -> Bool {
        lock.lock()
        guard !completed, let continuation else {
            lock.unlock()
            return false
        }
        completed = true
        self.continuation = nil
        lock.unlock()
        body(continuation)
        return true
    }
}

private func posixQuote(_ value: String) -> String {
    value.isEmpty
        ? "''"
        : "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
}
