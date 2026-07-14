import Darwin
import Foundation

enum HolyRemoteAgentStateBridgeState: Equatable, Sendable {
    case notInstalled
    case partial
    case installed
    case blocked(String)

    var isInstalled: Bool {
        if case .installed = self { return true }
        return false
    }
}

struct HolyRemoteAgentStateBridgeResult: Equatable, Sendable {
    let state: HolyRemoteAgentStateBridgeState
    let manualTrustHarnesses: [String]
}

enum HolyRemoteAgentStateBridgeServiceError: Error, Equatable, LocalizedError {
    case invalidDestination
    case launchFailed(String)
    case timedOut
    case commandFailed(String)
    case outputTooLarge
    case malformedResponse
    case invalidRemoteHome

    var errorDescription: String? {
        switch self {
        case .invalidDestination:
            "The SSH destination is not safe to use. Save a normal host alias or user@host value first."
        case let .launchFailed(description):
            "Could not start SSH: \(description)"
        case .timedOut:
            "The remote indicator setup timed out, so Holy could not verify a complete result. Check this host again before retrying."
        case let .commandFailed(description):
            "Remote indicator setup failed: \(description)"
        case .outputTooLarge:
            "The remote host returned too much output, so Holy stopped without trusting it."
        case .malformedResponse:
            "The remote host returned an invalid indicator-setup response."
        case .invalidRemoteHome:
            "The remote account reported an invalid home directory."
        }
    }
}

/// Consent is owned by the caller. This service performs one bounded,
/// transactional operation on one explicitly selected SSH host.
///
/// Existing harness configuration is parsed and merged by the remote process;
/// its contents never cross SSH. The only stdin payload is Holy's generated
/// adapter manifest, and stdout contains status codes only.
actor HolyRemoteAgentStateBridgeService {
    static let shared = HolyRemoteAgentStateBridgeService()

    enum Action: String, Equatable, Sendable {
        case inspect
        case install
        case remove
    }

    private static let probeTimeout: TimeInterval = 10
    private static let transactionTimeout: TimeInterval = 20
    private static let maximumResponseBytes = 64 * 1_024
    private static let maximumRequestBytes = 1 * 1_024 * 1_024

    func inspect(_ host: HolyRemoteHostRecord) async throws -> HolyRemoteAgentStateBridgeResult {
        try await perform(.inspect, on: host)
    }

    func install(on host: HolyRemoteHostRecord) async throws -> HolyRemoteAgentStateBridgeResult {
        try await perform(.install, on: host)
    }

    func remove(from host: HolyRemoteHostRecord) async throws -> HolyRemoteAgentStateBridgeResult {
        try await perform(.remove, on: host)
    }

    private func perform(
        _ action: Action,
        on host: HolyRemoteHostRecord
    ) async throws -> HolyRemoteAgentStateBridgeResult {
        let destination = try Self.validatedDestination(host.normalized().sshDestination)
        let home = try await remoteHome(destination: destination)
        let helperURL = URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent(".local/share/holy-ghostty", isDirectory: true)
            .appendingPathComponent("agent-state-hook.sh")
        let manifest = try HolyAgentStateBridge.remoteInstallationManifest(helperURL: helperURL)
        let request = try Self.requestData(action: action, expectedHome: home, manifest: manifest)
        guard request.count <= Self.maximumRequestBytes else {
            throw HolyRemoteAgentStateBridgeServiceError.outputTooLarge
        }

        let plan = Self.commandPlan(destination: destination, program: Self.transactionProgram)
        let outcome = await Self.run(plan: plan, stdin: request, timeout: Self.transactionTimeout)
        return try Self.decodeTransactionResult(outcome)
    }

    private func remoteHome(destination: String) async throws -> String {
        let plan = Self.commandPlan(destination: destination, program: Self.homeProbeProgram)
        let outcome = await Self.run(plan: plan, stdin: nil, timeout: Self.probeTimeout)
        let data = try Self.completedStdout(from: outcome)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["ok"] as? Bool == true,
              let home = object["home"] as? String,
              Self.isValidRemoteHome(home) else {
            throw HolyRemoteAgentStateBridgeServiceError.invalidRemoteHome
        }
        return home
    }

    private static func decodeTransactionResult(
        _ outcome: RunOutcome
    ) throws -> HolyRemoteAgentStateBridgeResult {
        let data = try completedStdout(from: outcome)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["protocolVersion"] as? Int == 1,
              let ok = object["ok"] as? Bool,
              let stateValue = object["state"] as? String else {
            throw HolyRemoteAgentStateBridgeServiceError.malformedResponse
        }

        let manualTrust = (object["manualTrust"] as? [String] ?? []).filter {
            !$0.isEmpty && $0.utf8.count <= 48
        }
        if ok {
            switch stateValue {
            case "not-installed":
                return .init(state: .notInstalled, manualTrustHarnesses: manualTrust)
            case "partial":
                return .init(state: .partial, manualTrustHarnesses: manualTrust)
            case "installed":
                return .init(state: .installed, manualTrustHarnesses: manualTrust)
            default:
                throw HolyRemoteAgentStateBridgeServiceError.malformedResponse
            }
        }

        guard stateValue == "blocked",
              let message = object["message"] as? String,
              !message.isEmpty,
              message.utf8.count <= 1_024 else {
            throw HolyRemoteAgentStateBridgeServiceError.malformedResponse
        }
        return .init(state: .blocked(message), manualTrustHarnesses: manualTrust)
    }

    private static func completedStdout(from outcome: RunOutcome) throws -> Data {
        switch outcome {
        case let .completed(stdout, stderr, exitCode, overflowed):
            guard !overflowed else {
                throw HolyRemoteAgentStateBridgeServiceError.outputTooLarge
            }
            guard exitCode == 0 else {
                let detail = String(data: stderr, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw HolyRemoteAgentStateBridgeServiceError.commandFailed(
                    detail?.isEmpty == false ? String(detail!.prefix(1_024)) : "SSH exited \(exitCode)"
                )
            }
            return stdout
        case let .launchFailed(description):
            throw HolyRemoteAgentStateBridgeServiceError.launchFailed(description)
        case .timedOut:
            throw HolyRemoteAgentStateBridgeServiceError.timedOut
        }
    }

    private static func requestData(
        action: Action,
        expectedHome: String,
        manifest: Data
    ) throws -> Data {
        guard let manifestObject = try JSONSerialization.jsonObject(with: manifest) as? [String: Any] else {
            throw HolyRemoteAgentStateBridgeServiceError.malformedResponse
        }
        return try JSONSerialization.data(
            withJSONObject: [
                "action": action.rawValue,
                "expectedHome": expectedHome,
                "manifest": manifestObject,
            ],
            options: [.sortedKeys]
        )
    }

    private static func validatedDestination(_ value: String) throws -> String {
        let bytes = Array(value.utf8)
        guard !bytes.isEmpty,
              bytes.count <= 512,
              bytes.first != 45,
              bytes.allSatisfy({ byte in
                  switch byte {
                  case 37, 43, 45, 46, 48 ... 58, 64 ... 90, 91, 93, 95, 97 ... 122:
                      true
                  default:
                      false
                  }
              }) else {
            throw HolyRemoteAgentStateBridgeServiceError.invalidDestination
        }
        return value
    }

    private static func isValidRemoteHome(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        return value.hasPrefix("/")
            && !value.contains("\n")
            && !value.contains("\0")
            && bytes.count <= 2_048
    }

    struct CommandPlan: Equatable, Sendable {
        let executablePath: String
        let arguments: [String]
    }

    private static func commandPlan(destination: String, program: String) -> CommandPlan {
        .init(
            executablePath: "/usr/bin/ssh",
            arguments: [
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=5",
                "-o", "ConnectionAttempts=1",
                "-o", "ServerAliveInterval=5",
                "-o", "ServerAliveCountMax=1",
                destination,
                "/usr/bin/env python3 -c \(posixQuote(program))",
            ]
        )
    }

    private static func posixQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private static let homeProbeProgram = #"""
    import json, os, sys
    home = os.path.realpath(os.path.expanduser("~"))
    valid = sys.version_info >= (3, 8) and os.path.isabs(home) and "\n" not in home and "\x00" not in home
    print(json.dumps({"ok": bool(valid), "home": home if valid else ""}, separators=(",", ":"), sort_keys=True))
    raise SystemExit(0 if valid else 78)
    """#

    /// Python is a deliberate prerequisite: safe structural JSON merging is
    /// required, and a host without it is blocked instead of falling back to
    /// brittle shell text editing. The program is fixed app code; stdin carries
    /// only Holy-generated adapter data.
    private static let transactionProgram = #"""
    import json
    import os
    import stat
    import sys
    import tempfile

    MAX_INPUT = 1024 * 1024
    MAX_CONFIG = 4 * 1024 * 1024
    MAX_OWNED = 1024 * 1024
    PROTOCOL = 1

    class Blocked(Exception):
        def __init__(self, code, message):
            super().__init__(message)
            self.code = code
            self.message = message

    def emit(ok, state, message=None, manual_trust=None):
        value = {
            "protocolVersion": PROTOCOL,
            "ok": bool(ok),
            "state": state,
            "manualTrust": sorted(set(manual_trust or [])),
        }
        if message:
            value["message"] = message
        sys.stdout.write(json.dumps(value, separators=(",", ":"), sort_keys=True) + "\n")

    def fail(code, message):
        raise Blocked(code, message)

    def strict_loads(raw, label):
        try:
            return json.loads(raw.decode("utf-8"), parse_constant=lambda _: fail("invalid-json", label + " is not valid JSON"))
        except Blocked:
            raise
        except Exception:
            fail("invalid-json", label + " is not a valid JSON object")

    def validate_relative(value):
        if not isinstance(value, str) or not value or len(value.encode("utf-8")) > 512:
            fail("invalid-manifest", "The adapter manifest contains an invalid relative path")
        if value.startswith("/") or "\x00" in value or "\n" in value:
            fail("invalid-manifest", "The adapter manifest contains an invalid relative path")
        normalized = os.path.normpath(value)
        if normalized in (".", "..") or normalized.startswith("../"):
            fail("invalid-manifest", "The adapter manifest path escapes the remote home")
        return normalized

    def within_home(path, home):
        try:
            return os.path.commonpath([home, path]) == home
        except ValueError:
            return False

    def resolve_target(home, relative):
        logical = os.path.join(home, validate_relative(relative))
        resolved = os.path.realpath(logical)
        if not within_home(resolved, home):
            fail("unsafe-symlink", "A target resolves outside the remote home directory")
        if os.path.lexists(logical) and not os.path.islink(logical):
            info = os.lstat(logical)
            if not stat.S_ISREG(info.st_mode):
                fail("special-file", "A target is not a regular file")
        if os.path.exists(resolved):
            info = os.stat(resolved)
            if not stat.S_ISREG(info.st_mode):
                fail("special-file", "A target is not a regular file")
        return logical, resolved

    def read_snapshot(target, maximum, label):
        if not os.path.exists(target):
            return {"exists": False, "data": None, "mode": None}
        info = os.stat(target)
        if not stat.S_ISREG(info.st_mode):
            fail("special-file", label + " is not a regular file")
        if info.st_size > maximum:
            fail("file-too-large", label + " is too large to update safely")
        with open(target, "rb") as handle:
            data = handle.read(maximum + 1)
        if len(data) > maximum:
            fail("file-too-large", label + " is too large to update safely")
        return {"exists": True, "data": data, "mode": stat.S_IMODE(info.st_mode)}

    def parse_object(snapshot, label):
        if not snapshot["exists"] or not snapshot["data"]:
            return {}
        value = strict_loads(snapshot["data"], label)
        if not isinstance(value, dict):
            fail("invalid-json", label + " is not a valid JSON object")
        return value

    def metadata(value, maximum):
        if not isinstance(value, str) or not value or len(value.encode("utf-8")) > maximum:
            return False
        allowed = set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._:/-")
        return all(character in allowed for character in value)

    def shell_quote(value):
        return "'" + value.replace("'", "'\"'\"'") + "'"

    def owned_hook(command, helper_path, source, lifecycle_values):
        if not isinstance(command, str):
            return False
        prefix = shell_quote(helper_path) + " " + source + " "
        if not command.startswith(prefix):
            return False
        fields = command[len(prefix):].split(" ")
        return len(fields) == 2 and fields[0] in lifecycle_values and metadata(fields[1], 64)

    def checked_hook_root(value, label):
        if not isinstance(value, dict):
            fail("invalid-hooks", label + " is not a JSON object")
        hooks = value.get("hooks")
        if hooks is not None and not isinstance(hooks, dict):
            fail("invalid-hooks", label + " has a malformed hooks object")
        for event, groups in (hooks or {}).items():
            if not isinstance(event, str) or not isinstance(groups, list):
                fail("invalid-hooks", label + " has malformed hook groups")
            for group in groups:
                if not isinstance(group, dict) or not isinstance(group.get("hooks"), list):
                    fail("invalid-hooks", label + " has malformed hook handlers")
                if not all(isinstance(handler, dict) for handler in group["hooks"]):
                    fail("invalid-hooks", label + " has malformed hook handlers")
        return value

    def merge_hook_document(existing, desired, helper_path, source, lifecycle_values, remove):
        result = dict(checked_hook_root(existing, "Remote harness configuration"))
        desired = checked_hook_root(desired, "Holy adapter manifest")
        hooks = dict(result.get("hooks") or {})
        desired_hooks = desired.get("hooks") or {}
        events = sorted(set(hooks.keys()) | set(desired_hooks.keys()))
        for event in events:
            retained = []
            insertion = None
            for group in hooks.get(event, []):
                handlers = group["hooks"]
                keep = [handler for handler in handlers if not owned_hook(handler.get("command"), helper_path, source, lifecycle_values)]
                if len(keep) != len(handlers) and insertion is None:
                    insertion = len(retained)
                if keep:
                    copy = dict(group)
                    copy["hooks"] = keep
                    retained.append(copy)
            wanted = [] if remove else desired_hooks.get(event, [])
            index = min(insertion if insertion is not None else len(retained), len(retained))
            retained[index:index] = wanted
            if retained:
                hooks[event] = retained
            else:
                hooks.pop(event, None)
        if hooks:
            result["hooks"] = hooks
        else:
            result.pop("hooks", None)
        return result

    def guarded_assignment_prefix(line, key):
        for candidate in (key, '"' + key + '"', "'" + key + "'"):
            if not line.startswith(candidate):
                continue
            remainder = line[len(candidate):]
            if not remainder or remainder[0] not in "= \t":
                if remainder.startswith("."):
                    return True
                continue
            if remainder.lstrip(" \t").startswith("="):
                return True
        return False

    def guarded_table_header(line, key):
        body = line[2:] if line.startswith("[[") else line[1:]
        body = body.lstrip(" \t")
        for candidate in (key, '"' + key + '"', "'" + key + "'"):
            if not body.startswith(candidate):
                continue
            remainder = body[len(candidate):]
            if remainder.startswith((".", "]", " ", "\t")):
                return True
        return False

    def guarded_assignment_single_line(line):
        if "=" not in line:
            return False
        rhs = line.split("=", 1)[1].strip()
        if not rhs.startswith("["):
            return True
        quote = None
        escaped = False
        depth = 0
        for character in rhs:
            if quote is not None:
                if quote == '"' and character == "\\" and not escaped:
                    escaped = True
                elif character == quote and not escaped:
                    quote = None
                else:
                    escaped = False
                continue
            if character == "#":
                break
            if character in ("'", '"'):
                quote = character
            elif character == "[":
                depth += 1
            elif character == "]":
                depth -= 1
        return quote is None and depth == 0

    def scan_toml_line(line, multiline, square_depth, brace_depth):
        index = 0
        quote = None
        escaped = False
        while index < len(line):
            if multiline is not None:
                if line.startswith(multiline * 3, index):
                    multiline = None
                    index += 3
                else:
                    index += 1
                continue
            if quote is not None:
                character = line[index]
                if quote == '"' and character == "\\" and not escaped:
                    escaped = True
                elif character == quote and not escaped:
                    quote = None
                else:
                    escaped = False
                index += 1
                continue
            character = line[index]
            if character == "#":
                break
            if character in ("'", '"') and line.startswith(character * 3, index):
                multiline = character
                index += 3
            elif character in ("'", '"'):
                quote = character
                index += 1
            else:
                if character == "[":
                    square_depth += 1
                elif character == "]":
                    square_depth = max(0, square_depth - 1)
                elif character == "{":
                    brace_depth += 1
                elif character == "}":
                    brace_depth = max(0, brace_depth - 1)
                index += 1
        return multiline, square_depth, brace_depth

    def guarded_top_level_state(contents, key):
        multiline = None
        square_depth = 0
        brace_depth = 0
        entered_table = False
        result = "absent"
        for line in contents.split("\n"):
            starts_top = multiline is None and square_depth == 0 and brace_depth == 0
            if starts_top and not entered_table:
                stripped = line.strip(" \t")
                if stripped and not stripped.startswith("#"):
                    if stripped.startswith("["):
                        if guarded_table_header(stripped, key):
                            return "single"
                        entered_table = True
                    elif guarded_assignment_prefix(stripped, key):
                        if result != "absent":
                            return "multiline"
                        result = "single" if guarded_assignment_single_line(stripped) else "multiline"
            multiline, square_depth, brace_depth = scan_toml_line(
                line, multiline, square_depth, brace_depth
            )
        return result

    def merge_guarded_text(existing, declaration, remove):
        key = declaration.get("guardedTopLevelKey")
        marker = declaration.get("ownershipMarker")
        desired_line = declaration.get("desiredLine")
        if not metadata(key, 64) or not isinstance(marker, str) or not isinstance(desired_line, str):
            fail("invalid-manifest", "A guarded text declaration is invalid")
        if "\n" in marker or "\r" in marker or "\n" in desired_line or "\r" in desired_line:
            fail("invalid-manifest", "A guarded text declaration is invalid")
        if "\ufeff" in existing:
            fail("ambiguous-guarded-setting", "A guarded user setting is multiline or ambiguous")

        block = marker + "\n" + desired_line
        owned = False
        remainder = None
        if existing in (block, block + "\n"):
            owned = True
            remainder = ""
        elif existing.startswith(block + "\n\n"):
            owned = True
            remainder = existing[len(block + "\n\n"):]
        elif existing.startswith(block + "\n"):
            owned = True
            remainder = existing[len(block + "\n"):]

        if owned:
            remainder_state = guarded_top_level_state(remainder, key)
            if remainder_state == "multiline":
                fail("ambiguous-guarded-setting", "A guarded user setting is multiline or ambiguous")
            if remainder_state == "single":
                fail("foreign-guarded-setting", "A guarded user setting already has a different value")
            return (remainder if remove else existing), True

        state = guarded_top_level_state(existing, key)
        if state == "multiline":
            fail("ambiguous-guarded-setting", "A guarded user setting is multiline or ambiguous")
        if state == "single":
            fail("foreign-guarded-setting", "A guarded user setting already has a different value")
        if remove:
            return existing, False
        return (block + "\n" if not existing else block + "\n\n" + existing), False

    def owned_generated(contents, expected, marker_prefix, generation, line_index):
        if contents == expected:
            return True
        lines = contents.splitlines()
        if line_index >= len(lines) or not lines[line_index].startswith(marker_prefix):
            return False
        suffix = lines[line_index][len(marker_prefix):]
        return suffix.isdigit() and 0 < int(suffix) < generation

    def canonical_json(value):
        return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True, allow_nan=False) + "\n").encode("utf-8")

    def make_parent(path):
        parent = os.path.dirname(path)
        missing = []
        cursor = parent
        while cursor and not os.path.exists(cursor):
            missing.append(cursor)
            cursor = os.path.dirname(cursor)
        for directory in reversed(missing):
            os.mkdir(directory, 0o700)
        return parent

    def write_atomic(path, data, mode):
        parent = make_parent(path)
        descriptor, temporary = tempfile.mkstemp(prefix=".holy-agent-state-", dir=parent)
        try:
            os.fchmod(descriptor, mode)
            with os.fdopen(descriptor, "wb", closefd=True) as handle:
                descriptor = -1
                handle.write(data)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, path)
            temporary = None
            directory = os.open(parent, os.O_RDONLY)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
        finally:
            if descriptor >= 0:
                os.close(descriptor)
            if temporary and os.path.exists(temporary):
                os.unlink(temporary)

    def restore(path, snapshot):
        if snapshot["exists"]:
            write_atomic(path, snapshot["data"], snapshot["mode"])
        elif os.path.exists(path):
            os.unlink(path)

    def apply_transaction(changes, snapshots):
        completed = []
        fail_at = int(os.environ.get("HOLY_AGENT_STATE_TEST_FAIL_AT", "0") or "0")
        try:
            for index, (path, data, default_mode) in enumerate(changes, start=1):
                if fail_at == index:
                    raise OSError("injected transaction failure")
                snapshot = snapshots[path]
                # Include the current path before its first filesystem call so
                # an exception after os.replace still restores that snapshot.
                completed.append(path)
                if data is None:
                    if os.path.exists(path):
                        os.unlink(path)
                else:
                    write_atomic(path, data, snapshot["mode"] if snapshot["exists"] else default_mode)
        except Exception:
            rollback_failed = False
            for path in reversed(completed):
                try:
                    restore(path, snapshots[path])
                except Exception:
                    rollback_failed = True
            if rollback_failed:
                fail("rollback-failed", "Remote setup failed and rollback also needs attention")
            fail("write-failed", "Remote setup failed and its completed file changes were rolled back")

    def validate_manifest(manifest, home):
        if not isinstance(manifest, dict) or manifest.get("protocolVersion") != PROTOCOL:
            fail("invalid-manifest", "The adapter manifest version is unsupported")
        generation = manifest.get("generationVersion")
        lifecycles = manifest.get("lifecycleValues")
        helper = manifest.get("helper")
        documents = manifest.get("hookDocuments")
        guarded_documents = manifest.get("guardedTextDocuments")
        exact_files = manifest.get("exactFiles")
        if not isinstance(generation, int) or generation < 1:
            fail("invalid-manifest", "The adapter generation is invalid")
        if not isinstance(lifecycles, list) or not lifecycles or not all(metadata(value, 48) for value in lifecycles):
            fail("invalid-manifest", "The adapter lifecycle vocabulary is invalid")
        if not isinstance(helper, dict) or not isinstance(documents, list) or not isinstance(guarded_documents, list) or not isinstance(exact_files, list):
            fail("invalid-manifest", "The adapter manifest is incomplete")
        if len(documents) > 16 or len(guarded_documents) > 16 or len(exact_files) > 16:
            fail("invalid-manifest", "The adapter manifest contains too many targets")
        return generation, set(lifecycles), helper, documents, guarded_documents, exact_files

    try:
        raw = sys.stdin.buffer.read(MAX_INPUT + 1)
        if len(raw) > MAX_INPUT:
            fail("request-too-large", "The Holy adapter request is too large")
        request = strict_loads(raw, "Holy adapter request")
        if not isinstance(request, dict):
            fail("invalid-request", "The Holy adapter request is invalid")
        action = request.get("action")
        if action not in ("inspect", "install", "remove"):
            fail("invalid-request", "The Holy adapter action is invalid")

        home = os.path.realpath(os.path.expanduser("~"))
        expected_home = request.get("expectedHome")
        if not isinstance(expected_home, str) or home != os.path.realpath(expected_home):
            fail("home-changed", "The remote home changed between preflight and setup")
        generation, lifecycles, helper, documents, guarded_documents, exact_files = validate_manifest(request.get("manifest"), home)

        helper_relative = helper.get("relativePath")
        helper_content = helper.get("content")
        helper_mode = helper.get("mode")
        helper_marker = helper.get("ownershipMarkerPrefix")
        if helper_relative != ".local/share/holy-ghostty/agent-state-hook.sh" or not isinstance(helper_content, str) or helper_mode != 0o700 or not isinstance(helper_marker, str):
            fail("invalid-manifest", "The Holy helper declaration is invalid")
        helper_logical_path, helper_path = resolve_target(home, helper_relative)
        if len(helper_content.encode("utf-8")) > MAX_OWNED:
            fail("invalid-manifest", "The Holy helper is too large")

        targets = {}
        helper_snapshot = read_snapshot(helper_path, MAX_OWNED, "Holy helper")
        targets[helper_path] = helper_snapshot
        if helper_snapshot["exists"]:
            helper_existing = helper_snapshot["data"].decode("utf-8", errors="strict")
            if not owned_generated(helper_existing, helper_content, helper_marker, generation, 1):
                fail("foreign-helper", "Holy's remote helper path contains a different file")

        prepared_documents = []
        manual_trust = []
        seen_paths = {helper_path}
        for document in documents:
            if not isinstance(document, dict):
                fail("invalid-manifest", "A hook document declaration is invalid")
            source = document.get("source")
            relative = document.get("relativePath")
            desired = document.get("desiredRoot")
            if not metadata(source, 48) or not isinstance(desired, dict):
                fail("invalid-manifest", "A hook document declaration is invalid")
            _, target = resolve_target(home, relative)
            if target in seen_paths:
                fail("invalid-manifest", "The adapter manifest repeats a target")
            seen_paths.add(target)
            snapshot = read_snapshot(target, MAX_CONFIG, "Remote harness configuration")
            targets[target] = snapshot
            existing = parse_object(snapshot, "Remote harness configuration")
            removed = merge_hook_document(existing, desired, helper_logical_path, source, lifecycles, True)
            merged = removed if action == "remove" else merge_hook_document(existing, desired, helper_logical_path, source, lifecycles, False)
            document_data = None if action == "remove" and not snapshot["exists"] and not merged else canonical_json(merged)
            prepared_documents.append((target, document_data, 0o600, existing == merged, existing != removed))
            if bool(document.get("manualTrust")):
                manual_trust.append(source)

        prepared_guarded = []
        for document in guarded_documents:
            if not isinstance(document, dict):
                fail("invalid-manifest", "A guarded text declaration is invalid")
            relative = document.get("relativePath")
            _, target = resolve_target(home, relative)
            if target in seen_paths:
                fail("invalid-manifest", "The adapter manifest repeats a target")
            seen_paths.add(target)
            snapshot = read_snapshot(target, MAX_CONFIG, "Remote guarded configuration")
            targets[target] = snapshot
            try:
                existing = snapshot["data"].decode("utf-8") if snapshot["exists"] else ""
            except Exception:
                fail("invalid-text", "Remote guarded configuration is not valid UTF-8")
            merged, owned = merge_guarded_text(existing, document, action == "remove")
            data = None if action == "remove" and not merged else merged.encode("utf-8")
            prepared_guarded.append((target, data, 0o600, existing == merged, owned))

        prepared_files = []
        for exact_file in exact_files:
            if not isinstance(exact_file, dict):
                fail("invalid-manifest", "An exact-file declaration is invalid")
            relative = exact_file.get("relativePath")
            content = exact_file.get("content")
            mode = exact_file.get("mode")
            marker = exact_file.get("ownershipMarkerPrefix")
            marker_line = exact_file.get("ownershipMarkerLine")
            accept_prior = exact_file.get("acceptPriorGeneration")
            if not isinstance(content, str) or mode not in (0o600, 0o700) or not isinstance(marker, str) or marker_line not in (0, 1) or not isinstance(accept_prior, bool):
                fail("invalid-manifest", "An exact-file declaration is invalid")
            _, target = resolve_target(home, relative)
            if target in seen_paths:
                fail("invalid-manifest", "The adapter manifest repeats a target")
            seen_paths.add(target)
            encoded = content.encode("utf-8")
            if len(encoded) > MAX_OWNED:
                fail("invalid-manifest", "A generated adapter file is too large")
            snapshot = read_snapshot(target, MAX_OWNED, "Generated adapter file")
            targets[target] = snapshot
            if snapshot["exists"]:
                existing = snapshot["data"].decode("utf-8", errors="strict")
                if existing != content and (not accept_prior or not owned_generated(existing, content, marker, generation, marker_line)):
                    fail("foreign-adapter", "A generated adapter path contains a different file")
            prepared_files.append((target, encoded, mode, snapshot["exists"] and snapshot["data"] == encoded))

        helper_exact = helper_snapshot["exists"] and helper_snapshot["data"] == helper_content.encode("utf-8")
        documents_exact = all(item[3] for item in prepared_documents)
        guarded_exact = all(item[3] for item in prepared_guarded)
        files_exact = all(item[3] for item in prepared_files)
        present_count = int(helper_snapshot["exists"]) + sum(int(item[4]) for item in prepared_documents) + sum(int(item[4]) for item in prepared_guarded) + sum(int(targets[item[0]]["exists"]) for item in prepared_files)
        total_count = 1 + len(prepared_documents) + len(prepared_guarded) + len(prepared_files)

        if action == "inspect":
            if helper_exact and documents_exact and guarded_exact and files_exact:
                state = "installed"
            elif present_count == 0:
                state = "not-installed"
            else:
                state = "partial"
            emit(True, state, manual_trust=manual_trust if state == "installed" else [])
            raise SystemExit(0)

        changes = []
        if action == "install":
            changes.append((helper_path, helper_content.encode("utf-8"), helper_mode))
            changes.extend((path, data, mode) for path, data, mode, _, _ in prepared_documents)
            changes.extend((path, data, mode) for path, data, mode, _, _ in prepared_guarded)
            changes.extend((path, data, mode) for path, data, mode, _ in prepared_files)
        else:
            changes.extend((path, data, mode) for path, data, mode, _, _ in prepared_documents)
            changes.extend((path, data, mode) for path, data, mode, _, _ in prepared_guarded)
            changes.extend((path, None, mode) for path, _, mode, _ in prepared_files)
            changes.append((helper_path, None, helper_mode))

        apply_transaction(changes, targets)
        emit(True, "installed" if action == "install" else "not-installed", manual_trust=manual_trust if action == "install" else [])
    except Blocked as error:
        emit(False, "blocked", error.message)
    except SystemExit:
        raise
    except Exception:
        emit(False, "blocked", "Remote setup failed before Holy could verify a complete result")
    """#
}

// MARK: - Bounded process execution

private extension HolyRemoteAgentStateBridgeService {
    enum RunOutcome {
        case completed(stdout: Data, stderr: Data, exitCode: Int32, overflowed: Bool)
        case launchFailed(String)
        case timedOut
    }

    static func run(
        plan: CommandPlan,
        stdin: Data?,
        timeout: TimeInterval,
        environment: [String: String]? = nil
    ) async -> RunOutcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: plan.executablePath)
        process.arguments = plan.arguments
        process.environment = environment

        let standardInput = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = standardInput
        process.standardOutput = stdout
        process.standardError = stderr

        let stdoutBuffer = HolyRemoteAgentStateBridgeOutputBuffer(limit: maximumResponseBytes)
        let stderrBuffer = HolyRemoteAgentStateBridgeOutputBuffer(limit: maximumResponseBytes)
        stdout.fileHandleForReading.readabilityHandler = { stdoutBuffer.append($0.availableData) }
        stderr.fileHandleForReading.readabilityHandler = { stderrBuffer.append($0.availableData) }

        let resumeBox = HolyRemoteAgentStateBridgeResumeBox()
        return await withCheckedContinuation { continuation in
            resumeBox.store(continuation)
            process.terminationHandler = { finished in
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                stdoutBuffer.append(stdout.fileHandleForReading.readDataToEndOfFile())
                stderrBuffer.append(stderr.fileHandleForReading.readDataToEndOfFile())
                let out = stdoutBuffer.snapshot()
                let error = stderrBuffer.snapshot()
                resumeBox.resume(returning: .completed(
                    stdout: out.data,
                    stderr: error.data,
                    exitCode: finished.terminationStatus,
                    overflowed: out.overflowed || error.overflowed
                ))
            }

            do {
                try process.run()
            } catch {
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                try? standardInput.fileHandleForWriting.close()
                resumeBox.resume(returning: .launchFailed(error.localizedDescription))
                return
            }

            // A future adapter manifest may exceed a pipe buffer. Feed stdin
            // off the actor so an SSH peer that never reads cannot prevent the
            // timeout task below from terminating the process.
            DispatchQueue.global(qos: .utility).async {
                if let stdin {
                    try? standardInput.fileHandleForWriting.write(contentsOf: stdin)
                }
                try? standardInput.fileHandleForWriting.close()
            }

            Task.detached {
                try? await Task.sleep(nanoseconds: UInt64(max(0.1, timeout) * 1_000_000_000))
                if resumeBox.resume(returning: .timedOut), process.isRunning {
                    process.terminate()
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if process.isRunning {
                        _ = Darwin.kill(process.processIdentifier, SIGKILL)
                    }
                }
            }
        }
    }
}

private final class HolyRemoteAgentStateBridgeOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var data = Data()
    private var overflowed = false

    init(limit: Int) {
        self.limit = limit
    }

    func append(_ next: Data) {
        guard !next.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        let remaining = max(0, limit - data.count)
        if next.count > remaining { overflowed = true }
        if remaining > 0 { data.append(next.prefix(remaining)) }
    }

    func snapshot() -> (data: Data, overflowed: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (data, overflowed)
    }
}

private final class HolyRemoteAgentStateBridgeResumeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<HolyRemoteAgentStateBridgeService.RunOutcome, Never>?
    private var didResume = false

    func store(_ continuation: CheckedContinuation<HolyRemoteAgentStateBridgeService.RunOutcome, Never>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    @discardableResult
    func resume(returning value: HolyRemoteAgentStateBridgeService.RunOutcome) -> Bool {
        lock.lock()
        guard !didResume, let continuation else {
            lock.unlock()
            return false
        }
        didResume = true
        self.continuation = nil
        lock.unlock()
        continuation.resume(returning: value)
        return true
    }
}

#if DEBUG
extension HolyRemoteAgentStateBridgeService {
    static func commandPlanForTesting(destination: String) throws -> CommandPlan {
        commandPlan(destination: try validatedDestination(destination), program: transactionProgram)
    }

    static func runTransactionForTesting(
        action: Action,
        home: URL,
        failAt: Int? = nil
    ) async throws -> (result: HolyRemoteAgentStateBridgeResult, stdout: Data) {
        guard let resolvedPointer = Darwin.realpath(home.path, nil) else {
            throw HolyRemoteAgentStateBridgeServiceError.invalidRemoteHome
        }
        defer { free(resolvedPointer) }
        let resolvedHome = URL(fileURLWithPath: String(cString: resolvedPointer), isDirectory: true)
        let helperURL = resolvedHome
            .appendingPathComponent(".local/share/holy-ghostty", isDirectory: true)
            .appendingPathComponent("agent-state-hook.sh")
        let manifest = try HolyAgentStateBridge.remoteInstallationManifest(helperURL: helperURL)
        let request = try requestData(
            action: action,
            expectedHome: resolvedHome.path,
            manifest: manifest
        )
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = resolvedHome.path
        if let failAt {
            environment["HOLY_AGENT_STATE_TEST_FAIL_AT"] = String(failAt)
        } else {
            environment.removeValue(forKey: "HOLY_AGENT_STATE_TEST_FAIL_AT")
        }
        let plan = CommandPlan(
            executablePath: "/usr/bin/env",
            arguments: ["python3", "-c", transactionProgram]
        )
        let outcome = await run(plan: plan, stdin: request, timeout: transactionTimeout, environment: environment)
        let stdout = try completedStdout(from: outcome)
        let result = try decodeTransactionResult(.completed(
            stdout: stdout,
            stderr: Data(),
            exitCode: 0,
            overflowed: false
        ))
        return (result, stdout)
    }
}
#endif
