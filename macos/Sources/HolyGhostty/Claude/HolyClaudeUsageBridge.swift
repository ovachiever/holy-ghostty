import Foundation

enum HolyClaudeUsageBridgeInstallOutcome: Equatable {
    case installed
    case alreadyInstalled
}

enum HolyClaudeUsageBridgeInstallationState: Equatable {
    case notInstalled
    case installed
    case needsRepair(String)
}

enum HolyClaudeUsageBridgeRemovalOutcome: Equatable {
    case removed
    case notInstalled
}

struct HolyClaudeUsageBridgePaths: Equatable, Sendable {
    let settingsURL: URL
    let probeURL: URL
    let guardURL: URL
    let usageDirectoryURL: URL

    var policyURL: URL { usageDirectoryURL.appendingPathComponent("policy.json", isDirectory: false) }
    var latestURL: URL { usageDirectoryURL.appendingPathComponent("latest.json", isDirectory: false) }
    var historyURL: URL { usageDirectoryURL.appendingPathComponent("history.jsonl", isDirectory: false) }
    var sessionsDirectoryURL: URL { usageDirectoryURL.appendingPathComponent("sessions", isDirectory: true) }
    var accountsDirectoryURL: URL { usageDirectoryURL.appendingPathComponent("accounts", isDirectory: true) }
    var wrapUpRequestURL: URL { usageDirectoryURL.appendingPathComponent("wrap-up-requested.json", isDirectory: false) }

    static func currentUser(fileManager: FileManager = .default) -> HolyClaudeUsageBridgePaths {
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        let settingsURL = homeDirectory
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json", isDirectory: false)
        let supportRoot = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? homeDirectory.appendingPathComponent("Library/Application Support", isDirectory: true)
        let holyRoot = supportRoot.appendingPathComponent("Holy Ghostty", isDirectory: true)
        return HolyClaudeUsageBridgePaths(
            settingsURL: settingsURL,
            probeURL: holyRoot.appendingPathComponent("claude-usage-probe.py", isDirectory: false),
            guardURL: holyRoot.appendingPathComponent("claude-usage-guard.py", isDirectory: false),
            usageDirectoryURL: holyRoot.appendingPathComponent("usage", isDirectory: true)
        )
    }
}

/// Installs the usage guard: a probe that reads the signed-in account's live
/// rate-limit windows, and a hook that tells every running Claude session to
/// wrap up before a window caps. Both are generated files owned by Holy;
/// installation touches only Holy-owned entries in `~/.claude/settings.json`.
enum HolyClaudeUsageBridge {
    static let ownerMarker = "com.holyghostty.claude-usage.v1"
    static let hookEvents = ["PreToolUse", "UserPromptSubmit"]

    static func currentUserInstallationState() -> HolyClaudeUsageBridgeInstallationState {
        let paths = HolyClaudeUsageBridgePaths.currentUser()
        do {
            return try installationState(paths: paths)
        } catch {
            AppDelegate.logger.error(
                "Reading Holy Claude usage guard state failed: \(error.localizedDescription, privacy: .public)"
            )
            return .notInstalled
        }
    }

    @discardableResult
    static func installForCurrentUser(policy: HolyClaudeUsagePolicy) -> HolyClaudeUsageBridgeInstallOutcome? {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return nil
        }
        let paths = HolyClaudeUsageBridgePaths.currentUser()
        do {
            let outcome = try install(paths: paths, policy: policy)
            if outcome == .installed {
                AppDelegate.logger.notice("Installed Holy Claude usage guard")
            }
            NotificationCenter.default.post(name: .holyClaudeUsageBridgeDidChange, object: nil)
            return outcome
        } catch {
            AppDelegate.logger.error(
                "Holy Claude usage guard installation failed: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    @discardableResult
    static func removeForCurrentUser() -> HolyClaudeUsageBridgeRemovalOutcome? {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return nil
        }
        let paths = HolyClaudeUsageBridgePaths.currentUser()
        do {
            let outcome = try remove(paths: paths)
            // The probe published the green-bar segment as a server-global
            // option; without this the last value would outlive the guard.
            clearTmuxUsageSegment()
            NotificationCenter.default.post(name: .holyClaudeUsageBridgeDidChange, object: nil)
            return outcome
        } catch {
            AppDelegate.logger.error(
                "Holy Claude usage guard removal failed: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    static func install(
        paths: HolyClaudeUsageBridgePaths,
        policy: HolyClaudeUsagePolicy,
        fileManager: FileManager = .default
    ) throws -> HolyClaudeUsageBridgeInstallOutcome {
        var settings = try loadSettings(at: paths.settingsURL, fileManager: fileManager)
        let alreadyCurrent = try installationState(paths: paths, fileManager: fileManager) == .installed
            && (try? policyIsCurrent(paths: paths, policy: policy)) == true
        if alreadyCurrent {
            return .alreadyInstalled
        }

        for directory in [paths.usageDirectoryURL, paths.sessionsDirectoryURL, paths.accountsDirectoryURL] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }
        try writeHelper(probeScript, to: paths.probeURL, fileManager: fileManager)
        try writeHelper(guardScript, to: paths.guardURL, fileManager: fileManager)
        try writePolicy(policy, paths: paths)

        let command = shellQuote(paths.guardURL.path)
        for event in hookEvents {
            try replaceOwnedHooks(
                in: &settings,
                event: event,
                paths: paths,
                replacement: [
                    "matcher": "",
                    "hooks": [["type": "command", "command": command]],
                ]
            )
        }
        try writeSettings(settings, to: paths.settingsURL, fileManager: fileManager)
        return .installed
    }

    static func remove(
        paths: HolyClaudeUsageBridgePaths,
        fileManager: FileManager = .default
    ) throws -> HolyClaudeUsageBridgeRemovalOutcome {
        var settings = try loadSettings(at: paths.settingsURL, fileManager: fileManager)
        var removedAnything = false
        for event in hookEvents {
            removedAnything = try replaceOwnedHooks(
                in: &settings,
                event: event,
                paths: paths,
                replacement: nil
            ) || removedAnything
        }
        if removedAnything {
            try writeSettings(settings, to: paths.settingsURL, fileManager: fileManager)
        }
        for helper in [paths.probeURL, paths.guardURL] where fileManager.fileExists(atPath: helper.path) {
            if let contents = try? String(contentsOf: helper, encoding: .utf8), isOwnedHelper(contents) {
                try fileManager.removeItem(at: helper)
                removedAnything = true
            }
        }
        // The usage directory holds nothing secret (numbers, reset times,
        // account e-mail) and its history is what makes the meter useful again
        // on re-enable, so it stays.
        return removedAnything ? .removed : .notInstalled
    }

    static func installationState(
        paths: HolyClaudeUsageBridgePaths,
        fileManager: FileManager = .default
    ) throws -> HolyClaudeUsageBridgeInstallationState {
        let settings = try loadSettings(at: paths.settingsURL, fileManager: fileManager)
        let command = shellQuote(paths.guardURL.path)
        var hookedEvents = 0
        for event in hookEvents {
            let owned = try ownedHandlers(in: settings, event: event, paths: paths)
            if owned.count == 1, owned[0]["command"] as? String == command {
                hookedEvents += 1
            } else if !owned.isEmpty {
                return .needsRepair("Holy's \(event) usage hook is present but not current")
            }
        }
        let probeCurrent = (try? String(contentsOf: paths.probeURL, encoding: .utf8)) == probeScript
        let guardCurrent = (try? String(contentsOf: paths.guardURL, encoding: .utf8)) == guardScript
        if hookedEvents == 0, !probeCurrent, !guardCurrent {
            return .notInstalled
        }
        if hookedEvents == hookEvents.count, probeCurrent, guardCurrent {
            return .installed
        }
        return .needsRepair("Holy's usage guard files or hooks are out of date")
    }

    static func writePolicy(_ policy: HolyClaudeUsagePolicy, paths: HolyClaudeUsageBridgePaths) throws {
        try FileManager.default.createDirectory(at: paths.usageDirectoryURL, withIntermediateDirectories: true)
        try policy.policyFileJSON().write(to: paths.policyURL, options: .atomic)
    }

    static func policyIsCurrent(paths: HolyClaudeUsageBridgePaths, policy: HolyClaudeUsagePolicy) throws -> Bool {
        guard let data = try? Data(contentsOf: paths.policyURL) else { return false }
        return data == (try policy.policyFileJSON())
    }

    // MARK: - Wrap-up request

    struct WrapUpRequest: Equatable, Codable, Sendable {
        let requestedAt: Date
        let expiresAt: Date
        let accountEmail: String?
        let reason: String

        private enum CodingKeys: String, CodingKey {
            case requestedAt = "requested_at"
            case expiresAt = "expires_at"
            case accountEmail = "account_email"
            case reason
        }
    }

    /// Asks every running Claude session to pause on its next tool call, for
    /// the policy's lead window, regardless of the numbers. Used when Erik is
    /// about to switch accounts and wants nothing in flight.
    static func requestWrapUp(
        paths: HolyClaudeUsageBridgePaths,
        policy: HolyClaudeUsagePolicy,
        accountEmail: String?,
        reason: String,
        now: Date = .now
    ) throws {
        let request = WrapUpRequest(
            requestedAt: now,
            expiresAt: now.addingTimeInterval(policy.leadMinutes * 60),
            accountEmail: accountEmail,
            reason: reason
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: paths.usageDirectoryURL, withIntermediateDirectories: true)
        try encoder.encode(request).write(to: paths.wrapUpRequestURL, options: .atomic)
    }

    static func cancelWrapUp(paths: HolyClaudeUsageBridgePaths) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: paths.wrapUpRequestURL.path) else { return }
        try fileManager.removeItem(at: paths.wrapUpRequestURL)
    }

    static func activeWrapUpRequest(paths: HolyClaudeUsageBridgePaths, now: Date = .now) -> WrapUpRequest? {
        guard let data = try? Data(contentsOf: paths.wrapUpRequestURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let request = try? decoder.decode(WrapUpRequest.self, from: data),
              request.expiresAt > now else { return nil }
        return request
    }

    // MARK: - Generated helpers

    static func isOwnedHelper(_ contents: String) -> Bool {
        contents.contains("Owner: \(ownerMarker)")
    }

    /// Polls Anthropic's OAuth usage endpoint with the keychain token and writes
    /// `usage/latest.json`, `usage/history.jsonl`, and `usage/accounts/<email>.json`.
    /// The token is read over a pipe and sent only as a header: it never
    /// appears in a command line.
    static let probeScript = #"""
    #!/usr/bin/python3
    # Generated by Holy Ghostty. Owner: com.holyghostty.claude-usage.v1
    #
    # Reads the signed-in Claude Code account's OAuth token from the macOS
    # keychain, asks Anthropic's OAuth usage endpoint for the live rate-limit
    # windows, and writes a normalized snapshot that Holy's sidebar meter and the
    # usage guard hook both read. The token never leaves this process: it is read
    # from `security` over a pipe and sent only as a request header, never placed
    # in a command line.
    import glob
    import json
    import os
    import re
    import subprocess
    import sys
    import threading
    import time
    import urllib.error
    import urllib.request
    from datetime import datetime

    SCHEMA = 1
    USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
    KEYCHAIN_SERVICE = "Claude Code-credentials"
    CLAUDE_CONFIG = os.path.expanduser("~/.claude.json")
    # The endpoint's two window lengths, from its own bucket names. The weekly
    # window is the retention boundary for history: no bucket can use an older
    # sample. The session window bounds per-session files: a session silent for
    # a whole window has nothing current to say.
    WEEKLY_WINDOW_SECONDS = 7 * 24 * 60 * 60
    SESSION_WINDOW_SECONDS = 5 * 60 * 60
    # Recent burn rate is taken over the trailing tenth of a bucket's window:
    # long enough to hold several probe samples, short enough to react to a swarm
    # starting inside one session window.
    RECENT_WINDOW_FRACTION = 0.1
    # A probe must finish inside one poll period so runs never pile up; the
    # keychain read gets a quarter of that period and the request the rest.
    KEYCHAIN_SHARE_OF_DEADLINE = 0.25


    def usage_dir():
        override = os.environ.get("HOLY_USAGE_DIR")
        if override:
            return override
        return os.path.join(
            os.path.expanduser("~/Library/Application Support/Holy Ghostty"), "usage"
        )


    def load_policy(root):
        defaults = {
            "warn_percent": __WARN_PERCENT__,
            "critical_percent": __CRITICAL_PERCENT__,
            "lead_minutes": __LEAD_MINUTES__,
            "poll_seconds": __POLL_SECONDS__,
        }
        try:
            with open(os.path.join(root, "policy.json"), "r", encoding="utf-8") as handle:
                stored = json.load(handle)
        except (OSError, ValueError):
            stored = {}
        policy = dict(defaults)
        for key in policy:
            value = stored.get(key)
            if isinstance(value, (int, float)) and not isinstance(value, bool) and value > 0:
                policy[key] = float(value)
        if policy["critical_percent"] < policy["warn_percent"]:
            policy["critical_percent"] = policy["warn_percent"]
        return policy


    def read_keychain_token(deadline_seconds):
        try:
            out = subprocess.run(
                ["/usr/bin/security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"],
                capture_output=True,
                text=True,
                timeout=deadline_seconds,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired) as error:
            return None, "keychain read failed: %s" % error
        if out.returncode != 0:
            return None, "keychain item missing (is Claude Code logged in?)"
        try:
            blob = json.loads(out.stdout.strip())
        except ValueError:
            return None, "keychain item is not JSON"
        oauth = blob.get("claudeAiOauth") or {}
        token = oauth.get("accessToken")
        if not token:
            return None, "keychain item has no OAuth access token"
        meta = {
            "subscription": oauth.get("subscriptionType"),
            "tier": oauth.get("rateLimitTier"),
            "token_expires_at": _ms_to_s(oauth.get("expiresAt")),
        }
        return token, meta


    def _ms_to_s(value):
        if isinstance(value, (int, float)):
            return int(value / 1000)
        return None


    def read_account():
        try:
            with open(CLAUDE_CONFIG, "r", encoding="utf-8") as handle:
                config = json.load(handle)
        except (OSError, ValueError):
            return {}
        account = config.get("oauthAccount") or {}
        return {
            "email": account.get("emailAddress"),
            "account_uuid": account.get("accountUuid"),
            "organization": account.get("organizationName"),
        }


    def fetch_usage(token, deadline_seconds):
        request = urllib.request.Request(
            USAGE_URL,
            headers={
                "Authorization": "Bearer " + token,
                "anthropic-beta": "oauth-2025-04-20",
                "Accept": "application/json",
                "User-Agent": "holy-ghostty-usage-probe/1",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=deadline_seconds) as response:
                return json.loads(response.read().decode("utf-8")), None
        except urllib.error.HTTPError as error:
            detail = ""
            try:
                body = json.loads(error.read().decode("utf-8", "replace"))
                detail = str((body.get("error") or {}).get("message") or "")
            except Exception:
                detail = ""
            return None, ("HTTP %d from usage endpoint" % error.code) + (": " + detail if detail else "")
        except (urllib.error.URLError, OSError, ValueError) as error:
            return None, "usage endpoint unreachable: %s" % error


    def parse_iso(value):
        if not isinstance(value, str):
            return None
        text = value.strip()
        if text.endswith("Z"):
            text = text[:-1] + "+00:00"
        try:
            return int(datetime.fromisoformat(text).timestamp())
        except ValueError:
            return None


    def normalize(raw):
        """Turn the endpoint's `limits[]` (or the older flat fields) into buckets."""
        buckets = []
        limits = raw.get("limits")
        if isinstance(limits, list) and limits:
            for limit in limits:
                kind = limit.get("kind")
                scope = limit.get("scope") or {}
                model = ((scope.get("model") or {}).get("display_name")) if scope else None
                if kind == "session":
                    key, label, window = "session", "Session (5h)", SESSION_WINDOW_SECONDS
                elif kind == "weekly_all":
                    key, label, window = "weekly_all", "Week (all models)", WEEKLY_WINDOW_SECONDS
                elif kind == "weekly_scoped":
                    name = model or "scoped"
                    key, label, window = "weekly_scoped:" + name, "Week (%s)" % name, WEEKLY_WINDOW_SECONDS
                else:
                    key, label, window = str(kind), str(kind), WEEKLY_WINDOW_SECONDS
                buckets.append(
                    {
                        "key": key,
                        "label": label,
                        "percent": _number(limit.get("percent")),
                        "severity": limit.get("severity"),
                        "resets_at": parse_iso(limit.get("resets_at")),
                        "window_seconds": window,
                        "is_active": bool(limit.get("is_active")),
                    }
                )
        else:
            for key, label, window in (
                ("five_hour", "Session (5h)", SESSION_WINDOW_SECONDS),
                ("seven_day", "Week (all models)", WEEKLY_WINDOW_SECONDS),
            ):
                entry = raw.get(key)
                if not isinstance(entry, dict):
                    continue
                buckets.append(
                    {
                        "key": "session" if key == "five_hour" else "weekly_all",
                        "label": label,
                        "percent": _number(entry.get("utilization")),
                        "severity": None,
                        "resets_at": parse_iso(entry.get("resets_at")),
                        "window_seconds": window,
                        "is_active": True,
                    }
                )
        extra = raw.get("extra_usage") or {}
        return buckets, {
            "enabled": bool(extra.get("is_enabled")),
            "spend_limit_reached": bool(extra.get("spend_limit_reached")),
        }


    def _number(value):
        if isinstance(value, bool):
            return None
        if isinstance(value, (int, float)):
            return float(value)
        return None


    def sanitize_plain(text):
        """Text bound for the tmux #{E:...} sink: plain alphabet only."""
        return re.sub(r"[^A-Za-z0-9 ._+-]", "", str(text or ""))[:48]


    def _window_short(minutes):
        if minutes == 300:
            return "5h"
        if minutes == 10080:
            return "wk"
        return "%dm" % int(minutes or 0)


    def codex_binary():
        override = os.environ.get("HOLY_CODEX_BIN")
        candidates = [override] if override else []
        candidates += sorted(
            glob.glob(os.path.expanduser("~/.nvm/versions/node/*/bin/codex")), reverse=True
        )
        candidates += ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        for candidate in candidates:
            if candidate and os.access(candidate, os.X_OK):
                return candidate
        from shutil import which
        return which("codex")


    def codex_rpc(deadline_seconds):
        """One codex app-server round trip: rate limits plus the usage summary.

        The app server answers from codex's own auth (token refresh included)
        without spending any model tokens. Marked experimental upstream, so
        every failure degrades to (None, None) and the rollout fallback."""
        binary = codex_binary()
        if not binary:
            return None, None
        try:
            proc = subprocess.Popen(
                [binary, "app-server"],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
            )
        except OSError:
            return None, None
        replies = {}

        def reader():
            try:
                for line in proc.stdout:
                    try:
                        message = json.loads(line)
                    except ValueError:
                        continue
                    if isinstance(message, dict) and "id" in message:
                        replies[message["id"]] = message
            except Exception:
                pass

        thread = threading.Thread(target=reader, daemon=True)
        thread.start()
        try:
            def send(request_id, method, params):
                proc.stdin.write(json.dumps({
                    "jsonrpc": "2.0", "id": request_id, "method": method, "params": params,
                }) + "\n")
                proc.stdin.flush()

            deadline = time.time() + deadline_seconds
            send(1, "initialize", {"clientInfo": {
                "name": "holy-ghostty-usage", "title": "Holy Ghostty", "version": "1",
            }})
            while 1 not in replies and time.time() < deadline:
                time.sleep(0.05)
            if 1 not in replies:
                return None, None
            send(2, "account/rateLimits/read", {})
            send(3, "account/usage/read", {})
            while 2 not in replies and time.time() < deadline:
                time.sleep(0.05)
            limits = (replies.get(2) or {}).get("result")
            # The usage summary is garnish: take it only if it is already in.
            usage = (replies.get(3) or {}).get("result")
            return (limits if isinstance(limits, dict) else None,
                    usage if isinstance(usage, dict) else None)
        except (OSError, ValueError):
            return None, None
        finally:
            try:
                proc.kill()
            except OSError:
                pass


    def _codex_bucket(limit_id, slot, name, percent, minutes, resets_at):
        window = _window_short(minutes)
        if limit_id == "codex":
            label = "Codex (%s)" % ("week" if window == "wk" else window)
            short, on_bar = window, True
        else:
            display = name or sanitize_plain(limit_id)
            model = display[4:] if display.upper().startswith("GPT-") else display
            label = "Codex %s (%s)" % (display, "week" if window == "wk" else window)
            # Model chips earn bar space only while they carry real usage;
            # the popover always lists them all.
            short, on_bar = "%s %s" % (model, window), percent > 0
        return {
            "key": "codex:%s:%s" % (sanitize_plain(limit_id) or "limit", slot),
            "label": label,
            "percent": float(percent),
            "severity": None,
            "resets_at": int(resets_at) if isinstance(resets_at, (int, float)) else None,
            "window_seconds": int(minutes or 0) * 60,
            "is_active": percent > 0,
            "short": short,
            "bar": on_bar,
        }


    def normalize_codex(raw):
        """rateLimits/read result (camelCase) into buckets, dynamically: every
        limit id the endpoint reports is rendered, so a future top model
        appears without a code change."""
        limits = raw.get("rateLimitsByLimitId") or {}
        if not limits and isinstance(raw.get("rateLimits"), dict):
            limits = {"codex": raw["rateLimits"]}
        buckets = []
        for limit_id in sorted(limits):
            entry = limits[limit_id] or {}
            name = sanitize_plain(entry.get("limitName") or "")
            for slot in ("primary", "secondary"):
                window = entry.get(slot)
                if not isinstance(window, dict):
                    continue
                percent = _number(window.get("usedPercent"))
                if percent is None:
                    continue
                buckets.append(_codex_bucket(
                    limit_id, slot, name, percent,
                    window.get("windowDurationMins") or 0, window.get("resetsAt"),
                ))
        return buckets


    def codex_fallback_buckets(now):
        """Last-known snapshot from the newest session rollout file: codex
        writes rate_limits (snake_case) on every token_count event."""
        home = os.path.expanduser(os.environ.get("HOLY_CODEX_HOME", "~/.codex"))
        pattern = os.path.join(home, "sessions", "*", "*", "*", "rollout-*.jsonl")
        newest, newest_mtime = None, 0
        for path in glob.glob(pattern):
            try:
                mtime = os.path.getmtime(path)
            except OSError:
                continue
            if mtime > newest_mtime:
                newest, newest_mtime = path, mtime
        if newest is None or now - newest_mtime > WEEKLY_WINDOW_SECONDS:
            return []
        try:
            with open(newest, "rb") as handle:
                handle.seek(0, os.SEEK_END)
                handle.seek(max(0, handle.tell() - 262144))
                tail = handle.read().decode("utf-8", "replace")
        except OSError:
            return []
        snapshot = None
        for line in tail.split("\n"):
            if '"rate_limits"' not in line:
                continue
            try:
                payload = json.loads(line).get("payload") or {}
            except ValueError:
                continue
            if isinstance(payload.get("rate_limits"), dict):
                snapshot = payload["rate_limits"]
        if snapshot is None:
            return []
        buckets = []
        limit_id = sanitize_plain(snapshot.get("limit_id") or "codex") or "codex"
        name = sanitize_plain(snapshot.get("limit_name") or "")
        for slot in ("primary", "secondary"):
            window = snapshot.get(slot)
            if not isinstance(window, dict):
                continue
            percent = _number(window.get("used_percent"))
            if percent is None:
                continue
            buckets.append(_codex_bucket(
                limit_id, slot, name, percent,
                window.get("window_minutes") or 0, window.get("resets_at"),
            ))
        return buckets


    def collect_codex(now, deadline_seconds):
        """(buckets, meta): live RPC first, rollout tail as the fallback, and
        an honest ([], None) when there is no codex on this machine at all."""
        raw, usage = codex_rpc(deadline_seconds)
        if raw is None:
            buckets = codex_fallback_buckets(now)
            if not buckets:
                return [], None
            return buckets, {"source": "rollout", "stale_since": now}
        limits = raw.get("rateLimits") or {}
        summary = (usage or {}).get("summary") if isinstance(usage, dict) else None
        meta = {
            "source": "rpc",
            "plan": sanitize_plain(limits.get("planType") or "") or None,
            "spend_control_reached": bool(limits.get("spendControlReached")),
            "reset_credits": ((raw.get("rateLimitResetCredits") or {}).get("availableCount")),
            "summary": {
                key: summary.get(key)
                for key in ("lifetimeTokens", "peakDailyTokens", "currentStreakDays")
            } if isinstance(summary, dict) else None,
        }
        return normalize_codex(raw), meta


    def load_history(path, now):
        samples = []
        try:
            with open(path, "r", encoding="utf-8") as handle:
                for line in handle:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        sample = json.loads(line)
                    except ValueError:
                        continue
                    stamp = sample.get("t")
                    if isinstance(stamp, (int, float)) and now - stamp <= WEEKLY_WINDOW_SECONDS:
                        samples.append(sample)
        except OSError:
            pass
        return samples


    def project(buckets, samples, account_email, now):
        """Attach burn-rate projections: percent-per-hour and ETA to 100%."""
        for bucket in buckets:
            key = bucket["key"]
            percent = bucket.get("percent")
            bucket["rate_percent_per_hour"] = None
            bucket["eta_full_at"] = None
            if percent is None:
                continue
            recent_span = bucket["window_seconds"] * RECENT_WINDOW_FRACTION
            points = [
                (s["t"], s["b"][key])
                for s in samples
                if s.get("a") == account_email
                and isinstance(s.get("b"), dict)
                and isinstance(s["b"].get(key), (int, float))
                and now - s["t"] <= recent_span
            ]
            points.append((now, percent))
            # A reset inside the recent span makes earlier points meaningless.
            trimmed = []
            for point in points:
                if trimmed and point[1] < trimmed[-1][1]:
                    trimmed = []
                trimmed.append(point)
            if len(trimmed) < 2:
                continue
            t0, p0 = trimmed[0]
            t1, p1 = trimmed[-1]
            elapsed = t1 - t0
            if elapsed <= 0:
                continue
            rate = (p1 - p0) / elapsed * 3600.0
            bucket["rate_percent_per_hour"] = round(rate, 2)
            if rate > 0:
                eta = now + (100.0 - p1) / rate * 3600.0
                resets_at = bucket.get("resets_at")
                # A window that resets before the projected cap never reaches it.
                if resets_at is None or eta < resets_at:
                    bucket["eta_full_at"] = int(eta)


    def bucket_level(bucket, policy, now):
        """Mirror of HolyClaudeUsageEvaluator (also mirrored in the guard)."""
        percent = bucket.get("percent")
        if not isinstance(percent, (int, float)):
            return "normal"
        lead = policy["lead_minutes"] * 60.0
        if percent >= 100:
            return "capped"
        if percent >= policy["critical_percent"]:
            return "critical"
        eta = bucket.get("eta_full_at")
        if isinstance(eta, (int, float)):
            remaining = eta - now
            if remaining <= lead:
                return "critical"
            if remaining <= lead * 2 and percent >= policy["warn_percent"] / 2.0:
                return "warn"
        if percent >= policy["warn_percent"]:
            return "warn"
        severity = (bucket.get("severity") or "").lower()
        if severity and severity != "normal":
            return "warn"
        return "normal"


    def short_label(key):
        if key == "session":
            return "5h"
        if key == "weekly_all":
            return "wk"
        if key.startswith("weekly_scoped:"):
            label = key.split(":", 1)[1]
        else:
            label = key
        # The scoped-model name arrives from the API response and ends up
        # inside a tmux option that the status format expands with #{E:...},
        # where #(...) runs a command. Only this app's own style directives
        # may carry tmux syntax: strip everything outside a plain alphabet,
        # bounded like the status line's model label (48).
        label = re.sub(r"[^A-Za-z0-9 ._+-]", "", label)[:48]
        return label or "?"


    def compose_segment(buckets, policy, now, stale_seconds=None, wrap_up=False):
        """The green-bar segment, one ⌁-prefixed group per vendor. Styled for
        tmux's stock black-on-green bar: calm windows stay plain, a warn
        window becomes a yellow chip, critical/capped a red one. The identical
        value in every session marks it as machine-global, not this session's."""
        def chips_for(group):
            chips = []
            for bucket in group:
                percent = bucket.get("percent")
                if not isinstance(percent, (int, float)):
                    continue
                # tmux strftimes the fully expanded status line, so a literal
                # percent sign must arrive doubled or it is eaten as a (bad)
                # conversion. The sanitized label alphabet excludes %.
                short = bucket.get("short") or short_label(bucket.get("key") or "?")
                text = "%s %d%%%%" % (short, int(round(percent)))
                level = bucket_level(bucket, policy, now)
                if level in ("critical", "capped"):
                    chips.append("#[fg=white,bg=red,bold] %s #[default]" % text)
                elif level == "warn":
                    chips.append("#[fg=black,bg=yellow,bold] %s #[default]" % text)
                else:
                    chips.append(text)
            return chips
        is_codex = lambda b: (b.get("key") or "").startswith("codex:")
        parts = []
        claude_chips = chips_for([b for b in buckets if not is_codex(b)])
        if claude_chips:
            parts.append("#[dim]⌁ claude#[nodim] " + " · ".join(claude_chips))
        codex_chips = chips_for([b for b in buckets if is_codex(b) and b.get("bar", True)])
        if codex_chips:
            parts.append("#[dim]⌁ codex#[nodim] " + " · ".join(codex_chips))
        if not parts:
            return ""
        segment = "  ".join(parts)
        if wrap_up:
            segment = "#[fg=white,bg=red,bold] ⏸ WRAP UP #[default] " + segment
        if isinstance(stale_seconds, (int, float)) and stale_seconds > 0:
            segment += " #[dim](stale %dm)#[nodim]" % max(1, int(stale_seconds / 60))
        return segment


    def tmux_binary():
        override = os.environ.get("HOLY_TMUX_BIN")
        candidates = [override] if override else []
        candidates += ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        for candidate in candidates:
            if candidate and os.access(candidate, os.X_OK):
                return candidate
        from shutil import which
        return which("tmux")


    def publish_tmux(root, snapshot, policy, now, deadline_seconds):
        tmux = tmux_binary()
        if not tmux:
            return
        stale_since = snapshot.get("stale_since")
        stale_seconds = (now - stale_since) if isinstance(stale_since, (int, float)) else None
        wrap = read_wrap_up(root, snapshot, now)
        segment = compose_segment(
            snapshot.get("buckets") or [], policy, now,
            stale_seconds=stale_seconds, wrap_up=wrap,
        )
        socket = os.environ.get("HOLY_TMUX_SOCKET", "holy")
        try:
            subprocess.run(
                [tmux, "-L", socket, "set-option", "-g", "@holy_usage_v1", segment],
                capture_output=True,
                timeout=deadline_seconds,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired):
            pass


    def read_wrap_up(root, snapshot, now):
        try:
            with open(os.path.join(root, "wrap-up-requested.json"), "r", encoding="utf-8") as handle:
                request = json.load(handle)
        except (OSError, ValueError):
            return False
        expires = request.get("expires_at")
        if not isinstance(expires, (int, float)) or expires <= now:
            return False
        wanted = request.get("account_email")
        current = (snapshot.get("account") or {}).get("email")
        if wanted and current and wanted != current:
            return False
        return True


    def prune_session_files(root, now):
        sessions_dir = os.path.join(root, "sessions")
        try:
            names = os.listdir(sessions_dir)
        except OSError:
            return
        for name in names:
            path = os.path.join(sessions_dir, name)
            try:
                if now - os.path.getmtime(path) > SESSION_WINDOW_SECONDS:
                    os.remove(path)
            except OSError:
                pass


    def write_atomic(path, data):
        tmp = path + ".tmp.%d" % os.getpid()
        with open(tmp, "w", encoding="utf-8") as handle:
            handle.write(data)
        os.replace(tmp, path)


    def main():
        started = time.time()
        now = int(started)
        root = usage_dir()
        accounts_dir = os.path.join(root, "accounts")
        os.makedirs(accounts_dir, mode=0o700, exist_ok=True)
        latest_path = os.path.join(root, "latest.json")
        history_path = os.path.join(root, "history.jsonl")
        policy = load_policy(root)
        deadline = policy["poll_seconds"]

        try:
            with open(latest_path, "r", encoding="utf-8") as handle:
                previous = json.load(handle)
        except (OSError, ValueError):
            previous = None
        account = read_account()
        # A previous snapshot describes whichever account was signed in when
        # it was taken. Once the keychain moves (/login), its numbers are
        # someone else's headroom: neither the backoff nor the stale
        # carry-forward may serve them.
        previous_email = ((previous or {}).get("account") or {}).get("email")
        account_changed = bool(
            previous_email and account.get("email") and previous_email != account.get("email")
        )
        # A 429 from the endpoint set a backoff; honor it by serving the last
        # snapshot instead of knocking again. --force (the app's manual
        # Refresh) and an account change break through.
        backoff = (previous or {}).get("backoff_until")
        if (
            isinstance(backoff, (int, float))
            and backoff > now
            and "--force" not in sys.argv
            and not account_changed
        ):
            publish_tmux(root, previous, policy, now, deadline * KEYCHAIN_SHARE_OF_DEADLINE)
            if "--print" in sys.argv:
                sys.stdout.write(json.dumps(previous, indent=1) + "\n")
            return 1

        snapshot = {
            "schema": SCHEMA,
            "fetched_at": now,
            "account": account,
            "buckets": [],
            "extra_usage": None,
            "error": None,
        }

        token, meta = read_keychain_token(deadline * KEYCHAIN_SHARE_OF_DEADLINE)
        if token is None:
            snapshot["error"] = meta
        else:
            snapshot["account"].update(meta)
            remaining = max(deadline - (time.time() - started), deadline * KEYCHAIN_SHARE_OF_DEADLINE)
            raw, error = fetch_usage(token, remaining)
            if error:
                snapshot["error"] = error
            else:
                buckets, extra = normalize(raw)
                samples = load_history(history_path, now)
                project(buckets, samples, account.get("email"), now)
                snapshot["buckets"] = buckets
                snapshot["extra_usage"] = extra

        # Codex rides the same snapshot but is a different vendor: its fetch
        # is independent of the Anthropic account and of Claude's errors, and
        # its history projection reuses the same sample rows.
        codex_buckets, codex_meta = collect_codex(now, max(5.0, deadline * KEYCHAIN_SHARE_OF_DEADLINE))
        if codex_buckets:
            project(codex_buckets, load_history(history_path, now), account.get("email"), now)
            snapshot["buckets"] = [
                b for b in snapshot["buckets"] if not (b.get("key") or "").startswith("codex:")
            ] + codex_buckets
        if codex_meta is not None:
            snapshot["codex"] = codex_meta

        if snapshot["error"] is None:
            sample = {
                "t": now,
                "a": account.get("email"),
                "b": {b["key"]: b["percent"] for b in snapshot["buckets"] if b["percent"] is not None},
            }
            samples = load_history(history_path, now)
            samples.append(sample)
            write_atomic(history_path, "".join(json.dumps(s, separators=(",", ":")) + "\n" for s in samples))
            email = account.get("email")
            if email:
                safe = "".join(c if c.isalnum() or c in "@._-" else "_" for c in email)
                write_atomic(os.path.join(accounts_dir, safe + ".json"), json.dumps(snapshot, indent=1) + "\n")
        else:
            # Keep the last good buckets visible, marked stale, so a transient
            # network failure does not blank the meter or silence the guard.
            if previous and not account_changed and (previous.get("error") is None or previous.get("stale_since")):
                # Carry the Claude buckets forward but keep this run's fresh
                # codex readings: the vendors fail independently.
                fresh_codex = [
                    b for b in snapshot["buckets"] if (b.get("key") or "").startswith("codex:")
                ]
                carried = [
                    b for b in previous.get("buckets", [])
                    if not (b.get("key") or "").startswith("codex:")
                ]
                snapshot["buckets"] = carried + fresh_codex
                snapshot["extra_usage"] = previous.get("extra_usage")
                snapshot["stale_since"] = previous.get("stale_since") or previous.get("fetched_at")
            if "429" in (snapshot["error"] or ""):
                # The endpoint judged the current cadence too hot. Five quiet
                # poll periods drops the offered rate well under the one that
                # tripped it while the guard stays within minutes of fresh.
                snapshot["backoff_until"] = now + policy["poll_seconds"] * 5

        write_atomic(latest_path, json.dumps(snapshot, indent=1) + "\n")
        prune_session_files(root, now)
        publish_tmux(root, snapshot, policy, now, deadline * KEYCHAIN_SHARE_OF_DEADLINE)
        if "--print" in sys.argv:
            sys.stdout.write(json.dumps(snapshot, indent=1) + "\n")
        return 0 if snapshot["error"] is None else 1


    if __name__ == "__main__":
        sys.exit(main())
    """#
    .replacingOccurrences(of: "__WARN_PERCENT__", with: String(Int(HolyClaudeUsagePolicy.default.warnPercent)))
    .replacingOccurrences(of: "__CRITICAL_PERCENT__", with: String(Int(HolyClaudeUsagePolicy.default.criticalPercent)))
    .replacingOccurrences(of: "__LEAD_MINUTES__", with: String(Int(HolyClaudeUsagePolicy.default.leadMinutes)))
    .replacingOccurrences(of: "__POLL_SECONDS__", with: String(Int(HolyClaudeUsagePolicy.default.pollSeconds)))

    /// The hook. Runs on PreToolUse (every tool) and UserPromptSubmit, reads
    /// the probe snapshot plus the session's own status-line reading, and
    /// injects a wrap-up instruction when a window is near its cap. At the
    /// critical level it also denies new subagent spawns so they cannot die
    /// mid-work. It never blocks by exit code; every decision is JSON.
    static let guardScript = #"""
    #!/usr/bin/python3
    # Generated by Holy Ghostty. Owner: com.holyghostty.claude-usage.v1
    #
    # Claude Code hook (PreToolUse, UserPromptSubmit). Reads Holy's usage snapshot
    # and this session's own rate-limit reading, mirrors HolyClaudeUsageEvaluator
    # exactly, and tells the session to wrap up before a cap kills its work.
    # Output is always JSON on stdout with exit 0; the hook never reads prompts,
    # tool inputs, or anything beyond session_id, tool_name, and the event name.
    import json
    import os
    import subprocess
    import sys
    import time

    SESSION_WINDOW_SECONDS = 5 * 60 * 60
    WEEKLY_WINDOW_SECONDS = 7 * 24 * 60 * 60
    DEFAULT_POLICY = {
        "warn_percent": __WARN_PERCENT__,
        "critical_percent": __CRITICAL_PERCENT__,
        "lead_minutes": __LEAD_MINUTES__,
        "poll_seconds": __POLL_SECONDS__,
    }
    SPAWN_TOOLS = {"Agent", "Task", "Workflow"}
    LEVELS = ["normal", "warn", "critical", "capped"]


    def usage_dir():
        override = os.environ.get("HOLY_USAGE_DIR")
        if override:
            return override
        return os.path.join(
            os.path.expanduser("~/Library/Application Support/Holy Ghostty"), "usage"
        )


    def read_json(path):
        try:
            with open(path, "r", encoding="utf-8") as handle:
                return json.load(handle)
        except (OSError, ValueError):
            return None


    def load_policy(root):
        policy = dict(DEFAULT_POLICY)
        stored = read_json(os.path.join(root, "policy.json")) or {}
        for key in policy:
            value = stored.get(key)
            if isinstance(value, (int, float)) and not isinstance(value, bool) and value > 0:
                policy[key] = float(value)
        if policy["critical_percent"] < policy["warn_percent"]:
            policy["critical_percent"] = policy["warn_percent"]
        return policy


    def fmt_percent(value):
        return "%d%%" % int(round(value))


    def fmt_minutes(seconds):
        return "%d min" % max(0, int(round(seconds / 60.0)))


    def fmt_clock(stamp):
        if not isinstance(stamp, (int, float)):
            return "unknown"
        return time.strftime("%a %-I:%M%p", time.localtime(stamp)).replace("AM", "am").replace("PM", "pm")


    def level_for(bucket, policy, now):
        """Mirror of HolyClaudeUsageEvaluator.level(for:policy:now:)."""
        percent = bucket.get("percent")
        if not isinstance(percent, (int, float)):
            return None
        label = bucket.get("label") or bucket.get("key")
        lead = policy["lead_minutes"] * 60.0
        if percent >= 100:
            return "capped", "%s is at %s" % (label, fmt_percent(percent))
        if percent >= policy["critical_percent"]:
            return "critical", "%s at %s" % (label, fmt_percent(percent))
        eta = bucket.get("eta_full_at")
        if isinstance(eta, (int, float)):
            remaining = eta - now
            if remaining <= lead:
                return "critical", "%s at %s, cap in ~%s at current pace" % (label, fmt_percent(percent), fmt_minutes(remaining))
            if remaining <= lead * 2 and percent >= policy["warn_percent"] / 2.0:
                return "warn", "%s at %s, cap in ~%s at current pace" % (label, fmt_percent(percent), fmt_minutes(remaining))
        if percent >= policy["warn_percent"]:
            return "warn", "%s at %s" % (label, fmt_percent(percent))
        severity = (bucket.get("severity") or "").lower()
        if severity and severity != "normal":
            return "warn", "%s reported severity %s at %s" % (label, severity, fmt_percent(percent))
        return "normal", "%s at %s" % (label, fmt_percent(percent))


    def assess(buckets, policy, now):
        worst = None
        for bucket in buckets:
            verdict = level_for(bucket, policy, now)
            if verdict is None:
                continue
            level, reason = verdict
            rank = LEVELS.index(level)
            if worst is None or rank > worst[0] or (
                rank == worst[0] and (bucket.get("percent") or 0) > (worst[1].get("percent") or 0)
            ):
                worst = (rank, bucket, reason)
        if worst is None:
            return "normal", None, None
        return LEVELS[worst[0]], worst[1], worst[2]


    def session_buckets(root, session_id, now):
        if not session_id:
            return []
        reading = read_json(os.path.join(root, "sessions", session_id + ".json"))
        if not isinstance(reading, dict):
            return []
        buckets = []
        for key, bucket_key, label, window in (
            ("five_hour", "session", "Session (5h)", SESSION_WINDOW_SECONDS),
            ("seven_day", "weekly_all", "Week (all models)", WEEKLY_WINDOW_SECONDS),
        ):
            entry = reading.get(key)
            if not isinstance(entry, dict):
                continue
            percent = entry.get("percent")
            resets_at = entry.get("resets_at")
            if not isinstance(percent, (int, float)):
                continue
            if isinstance(resets_at, (int, float)) and resets_at <= now:
                continue
            buckets.append(
                {
                    "key": bucket_key,
                    "label": label,
                    "percent": float(percent),
                    "resets_at": resets_at,
                    "window_seconds": window,
                    "source": "session",
                }
            )
        return buckets


    def merged_buckets(latest, own):
        """This session's own 5h/weekly reading outranks the machine-wide one:
        it comes from this session's API responses, so it is right even when
        the keychain has moved to another account."""
        own_keys = {b["key"] for b in own}
        merged = list(own)
        for bucket in (latest or {}).get("buckets") or []:
            key = bucket.get("key") or ""
            if key in own_keys:
                continue
            if key.startswith("codex:"):
                # Codex headroom is another vendor's meter: it must never
                # pause a Claude session or deny its subagent spawns.
                continue
            copy = dict(bucket)
            copy["source"] = "machine"
            merged.append(copy)
        return merged


    def current_account_email():
        """The account the keychain token belongs to, as Claude records it."""
        config = read_json(os.path.expanduser("~/.claude.json"))
        if not isinstance(config, dict):
            return None
        return (config.get("oauthAccount") or {}).get("emailAddress")


    def maybe_refresh(root, latest, policy, now, force=False):
        """If Holy is not polling (snapshot stale), run the probe in the
        background so the next tool call sees fresh numbers. Rate-limited by a
        stamp file so a burst of tool calls spawns one probe. `force` skips
        the freshness check and breaks the probe through a 429 backoff."""
        fetched = (latest or {}).get("fetched_at")
        poll = policy["poll_seconds"]
        if not force and isinstance(fetched, (int, float)) and now - fetched <= poll * 2:
            return
        stamp = os.path.join(root, "refresh-requested")
        try:
            if now - os.path.getmtime(stamp) <= poll:
                return
        except OSError:
            pass
        probe = os.path.join(os.path.dirname(os.path.abspath(__file__)), "claude-usage-probe.py")
        if not os.access(probe, os.X_OK):
            return
        try:
            with open(stamp, "w", encoding="utf-8") as handle:
                handle.write(str(now))
            subprocess.Popen(
                [probe] + (["--force"] if force else []),
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
                env=dict(os.environ, HOLY_USAGE_DIR=root),
            )
        except OSError:
            pass


    def wrap_up_request(root, current_email, now):
        request = read_json(os.path.join(root, "wrap-up-requested.json"))
        if not isinstance(request, dict):
            return None
        expires = request.get("expires_at")
        if not isinstance(expires, (int, float)) or expires <= now:
            return None
        wanted = request.get("account_email")
        # The request was about one account; once the keychain moves on, the
        # sessions that follow it are on fresh headroom and must not be paused.
        if wanted and current_email and wanted != current_email:
            return None
        return request


    def describe(buckets, now):
        parts = []
        for bucket in buckets:
            percent = bucket.get("percent")
            if not isinstance(percent, (int, float)):
                continue
            text = "%s %s" % (bucket.get("label") or bucket.get("key"), fmt_percent(percent))
            resets = bucket.get("resets_at")
            if isinstance(resets, (int, float)):
                text += " (resets %s)" % fmt_clock(resets)
            eta = bucket.get("eta_full_at")
            if isinstance(eta, (int, float)) and eta > now:
                text += " ETA to cap ~%s" % fmt_minutes(eta - now)
            parts.append(text)
        return "; ".join(parts) if parts else "no usage numbers available"


    def message(level, reason, buckets, account_email, now, wrap_up):
        account = account_email or "unknown account"
        summary = describe(buckets, now)
        if wrap_up:
            head = "HOLY USAGE GUARD — the user asked every session to pause now (%s)." % (wrap_up.get("reason") or "usage")
        elif level == "capped":
            head = "HOLY USAGE GUARD — Claude usage cap REACHED: %s." % reason
        elif level == "critical":
            head = "HOLY USAGE GUARD — Claude usage cap IMMINENT: %s." % reason
        else:
            head = "HOLY USAGE GUARD — Claude usage cap approaching: %s." % reason
        if level in ("critical", "capped") or wrap_up:
            body = (
                " Account %s: %s. STOP starting new work. Immediately: (1) finish or abort the current step at a safe point;"
                " (2) commit or write all state to disk; (3) reply with a short note that begins 'PAUSED (usage cap):'"
                " listing what is done, what is in flight, and the exact next step to resume;"
                " (4) end your turn and do nothing further until the user says to continue."
                " New subagent spawns are denied while this stands. The user will switch accounts and tell you to resume."
            ) % (account, summary)
        else:
            body = (
                " Account %s: %s. Do not start new subagents or long tasks. Bring current work to a checkpoint now"
                " (commit, write state) so nothing is lost if the cap lands; keep steps small and finish cleanly."
            ) % (account, summary)
        return head + body


    def state_path(root, session_id):
        state_dir = os.path.join(root, "guard-state")
        os.makedirs(state_dir, mode=0o700, exist_ok=True)
        return os.path.join(state_dir, session_id + ".json")


    def should_announce(root, session_id, level, policy, now):
        """warn: once on entry plus a reminder every half lead window.
        critical/capped: every call, because the instruction is to stop."""
        if level in ("critical", "capped"):
            return True
        if not session_id:
            return True
        path = state_path(root, session_id)
        state = read_json(path) or {}
        last_level = state.get("level")
        last_at = state.get("announced_at")
        reminder = policy["lead_minutes"] * 60.0 / 2.0
        if last_level == level and isinstance(last_at, (int, float)) and now - last_at < reminder:
            return False
        try:
            with open(path, "w", encoding="utf-8") as handle:
                json.dump({"level": level, "announced_at": now}, handle)
        except OSError:
            pass
        return True


    def clear_state(root, session_id):
        if not session_id:
            return
        try:
            os.remove(state_path(root, session_id))
        except OSError:
            pass


    def emit(payload):
        sys.stdout.write(json.dumps(payload))
        sys.stdout.write("\n")


    def main():
        try:
            hook_input = json.load(sys.stdin)
        except ValueError:
            hook_input = {}
        if not isinstance(hook_input, dict):
            hook_input = {}
        event = hook_input.get("hook_event_name") or ""
        session_id = str(hook_input.get("session_id") or "")
        session_id = "".join(c for c in session_id if c.isalnum() or c in "-_")
        tool_name = str(hook_input.get("tool_name") or "")
        now = time.time()
        root = usage_dir()
        if not os.path.isdir(root):
            return 0

        policy = load_policy(root)
        latest = read_json(os.path.join(root, "latest.json"))
        current_email = current_account_email()
        latest_email = ((latest or {}).get("account") or {}).get("email")
        if current_email and latest_email and current_email != latest_email:
            # The keychain moved to another account since the last probe: its
            # numbers describe someone else's headroom. Drop them, ask for a
            # fresh read, and judge by this session's own windows meanwhile.
            latest = None
            maybe_refresh(root, None, policy, now, force=True)
        else:
            maybe_refresh(root, latest, policy, now)
        account_email = current_email or latest_email
        own = session_buckets(root, session_id, now)
        buckets = merged_buckets(latest, own)
        level, _bucket, reason = assess(buckets, policy, now)
        wrap_up = wrap_up_request(root, account_email, now)
        if wrap_up and LEVELS.index(level) < LEVELS.index("critical"):
            level = "critical"
            reason = wrap_up.get("reason") or "user requested pause"

        if level == "normal":
            clear_state(root, session_id)
            return 0

        text = message(level, reason, buckets, account_email, now, wrap_up)
        output = {"hookEventName": event or "PreToolUse"}
        if event == "PreToolUse" and level in ("critical", "capped") and tool_name in SPAWN_TOOLS:
            output["permissionDecision"] = "deny"
            output["permissionDecisionReason"] = (
                "Holy usage guard: %s. Subagent spawns are denied so they do not die mid-work. "
                "Wrap up and pause with a 'PAUSED (usage cap):' note." % reason
            )
            output["additionalContext"] = text
        elif should_announce(root, session_id, level, policy, now):
            output["additionalContext"] = text
        else:
            return 0
        emit({"hookSpecificOutput": output})
        return 0


    if __name__ == "__main__":
        try:
            sys.exit(main())
        except Exception:
            # A guard that crashes must never take a tool call down with it.
            sys.exit(0)
    """#
    .replacingOccurrences(of: "__WARN_PERCENT__", with: String(Int(HolyClaudeUsagePolicy.default.warnPercent)))
    .replacingOccurrences(of: "__CRITICAL_PERCENT__", with: String(Int(HolyClaudeUsagePolicy.default.criticalPercent)))
    .replacingOccurrences(of: "__LEAD_MINUTES__", with: String(Int(HolyClaudeUsagePolicy.default.leadMinutes)))
    .replacingOccurrences(of: "__POLL_SECONDS__", with: String(Int(HolyClaudeUsagePolicy.default.pollSeconds)))

    // MARK: - Settings plumbing

    private static func writeHelper(_ contents: String, to url: URL, fileManager: FileManager) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private static func loadSettings(at url: URL, fileManager: FileManager) throws -> [String: Any] {
        guard fileManager.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [:] }
        guard let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        return dictionary
    }

    private static func writeSettings(_ settings: [String: Any], to settingsURL: URL, fileManager: FileManager) throws {
        var writeURL = settingsURL
        if let destination = try? fileManager.destinationOfSymbolicLink(atPath: settingsURL.path) {
            writeURL = URL(fileURLWithPath: destination, relativeTo: settingsURL.deletingLastPathComponent())
                .standardizedFileURL
        }
        let existingPermissions = try? fileManager.attributesOfItem(atPath: writeURL.path)[.posixPermissions]
        try fileManager.createDirectory(at: writeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            + Data("\n".utf8)
        try data.write(to: writeURL, options: .atomic)
        if let existingPermissions {
            try fileManager.setAttributes([.posixPermissions: existingPermissions], ofItemAtPath: writeURL.path)
        }
    }

    private static func ownedHandlers(
        in settings: [String: Any],
        event: String,
        paths: HolyClaudeUsageBridgePaths
    ) throws -> [[String: Any]] {
        guard let hooksValue = settings["hooks"] else { return [] }
        guard let hooks = hooksValue as? [String: Any] else { throw CocoaError(.propertyListReadCorrupt) }
        guard let groupsValue = hooks[event] else { return [] }
        guard let groups = groupsValue as? [[String: Any]] else { throw CocoaError(.propertyListReadCorrupt) }
        var owned: [[String: Any]] = []
        for group in groups {
            guard let handlers = group["hooks"] as? [[String: Any]] else { throw CocoaError(.propertyListReadCorrupt) }
            owned.append(contentsOf: handlers.filter { isOwnedHandler($0, paths: paths) })
        }
        return owned
    }

    /// Returns true when an owned handler was present before the call.
    @discardableResult
    private static func replaceOwnedHooks(
        in settings: inout [String: Any],
        event: String,
        paths: HolyClaudeUsageBridgePaths,
        replacement: [String: Any]?
    ) throws -> Bool {
        var hooks: [String: Any]
        if let hooksValue = settings["hooks"] {
            guard let existing = hooksValue as? [String: Any] else { throw CocoaError(.propertyListReadCorrupt) }
            hooks = existing
        } else {
            hooks = [:]
        }
        var retainedGroups: [[String: Any]] = []
        var removedOwned = false
        if let groupsValue = hooks[event] {
            guard let groups = groupsValue as? [[String: Any]] else { throw CocoaError(.propertyListReadCorrupt) }
            for group in groups {
                guard let handlers = group["hooks"] as? [[String: Any]] else {
                    throw CocoaError(.propertyListReadCorrupt)
                }
                let retained = handlers.filter { !isOwnedHandler($0, paths: paths) }
                if retained.count != handlers.count { removedOwned = true }
                guard !retained.isEmpty else { continue }
                var retainedGroup = group
                retainedGroup["hooks"] = retained
                retainedGroups.append(retainedGroup)
            }
        }
        if let replacement {
            retainedGroups.append(replacement)
        }
        if retainedGroups.isEmpty {
            hooks.removeValue(forKey: event)
        } else {
            hooks[event] = retainedGroups
        }
        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }
        return removedOwned
    }

    private static func isOwnedHandler(_ handler: [String: Any], paths: HolyClaudeUsageBridgePaths) -> Bool {
        guard let command = handler["command"] as? String else { return false }
        let candidates = [paths.guardURL.path, shellQuote(paths.guardURL.path)]
        if candidates.contains(command) { return true }
        // A helper from another bundle id (debug vs release) is still Holy's.
        return command.hasSuffix("claude-usage-guard.py'") || command.hasSuffix("claude-usage-guard.py")
    }

    static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    @discardableResult
    static func clearTmuxUsageSegment(
        socketName: String = HolySessionTmuxSpec.defaultSocketName
    ) -> Bool {
        let script = "unset TMUX TMUX_PANE TMUX_TMPDIR; "
            + "tmux -L \(shellQuote(socketName)) set-option -gu @holy_usage_v1"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", script]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            let deadline = Date().addingTimeInterval(5)
            while process.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.025)
            }
            guard !process.isRunning else {
                process.terminate()
                return false
            }
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

extension Notification.Name {
    static let holyClaudeUsageBridgeDidChange = Notification.Name("holy.claudeUsage.bridgeDidChange")
}
