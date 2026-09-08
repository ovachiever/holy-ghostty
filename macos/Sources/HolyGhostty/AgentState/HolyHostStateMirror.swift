import Foundation

/// A journal on the producer host, independent of roster membership. Live tmux
/// options remain authoritative; the journal fills missing registers only.
/// The same program runs from hooks, acknowledgements, launch, and discovery,
/// including over SSH. It never opens a viewer's database for a remote session.
enum HolyHostStateMirror {
    static let schema = """
    CREATE TABLE IF NOT EXISTS host_indicator_state (
        socket_name TEXT NOT NULL,
        session_name TEXT NOT NULL,
        pane_key TEXT NOT NULL,
        option_name TEXT NOT NULL,
        wire_value TEXT NOT NULL,
        PRIMARY KEY (socket_name, session_name, pane_key, option_name)
    );
    """

    static func command(
        tmuxPrefix: [String],
        target: String = "",
        databasePath: String = "",
        restore: Bool = true,
        monitor: Bool = false
    ) -> String {
        let prefix = jsonLiteral(tmuxPrefix)
        return ["python3", "-c", script, monitor ? "monitor" : (restore ? "sync" : "snapshot"), databasePath, prefix, target]
            .map(quote).joined(separator: " ")
    }

    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    static let script = #"""
    import json, os, sqlite3, subprocess, sys

    OPTIONS = ["@holy_agent_state_v1", "@holy_agent_last_finished_v1",
               "@holy_agent_last_used_v1", "@holy_harness_identity_v1", "@holy_seen_v1"]
    SCHEMA = \#(jsonLiteral(schema))

    def main():
        mode, requested_db, prefix_json, target = sys.argv[1:]
        target = target or os.environ.get("TMUX_PANE", "")
        requested_db = os.environ.get("HOLY_HOST_STATE_DATABASE") or requested_db
        prefix = json.loads(prefix_json)
        def tmux(*args):
            return subprocess.check_output(prefix + list(args), text=True, stderr=subprocess.DEVNULL).rstrip("\n")
        fields = ["socket_path", "session_name", "session_id", "pane_id", "window_index", "pane_index",
                  "@holy_runtime", "@holy_agent_state_owner_v1", "@holy_host_state_db_v1"] + OPTIONS + [
                  "pane_dead", "pane_current_command", "window_activity", "@holy_watcher_v1"]
        fmt = "\x1f".join("#{" + field + "}" for field in fields)
        args = ["list-panes"] + (["-s", "-t", target] if target else ["-a"])
        output = tmux(*args, "-F", fmt)
        rows_by_db = {}
        all_rows = []
        default_db = os.path.expanduser("~/Library/Application Support/org.holyghostty.app/HolyGhostty/holy-ghostty.sqlite3")
        for line in output.splitlines():
            row = line.split("\x1f")
            if len(row) != len(fields):
                raise ValueError("malformed tmux journal snapshot")
            all_rows.append(row)
            if not row[6] and row[7] != "holy":
                continue
            db_path = requested_db or row[8] or default_db
            rows_by_db.setdefault(db_path, []).append(row)
        for db_path, rows in rows_by_db.items():
            os.makedirs(os.path.dirname(os.path.abspath(db_path)), mode=0o700, exist_ok=True)
            with sqlite3.connect(db_path, timeout=1) as db:
                db.execute(SCHEMA)
                # Registers carry producer timestamps. Under the writer lock,
                # never replace a newer journal event with an earlier snapshot.
                db.execute("BEGIN IMMEDIATE")
                for row in rows:
                    socket, name, session, pane, window, index = row[:6]
                    socket = os.path.realpath(socket)
                    live = row[9:14]
                    for position, (option, value) in enumerate(zip(OPTIONS, live), 9):
                        pane_key = "session" if option == "@holy_seen_v1" else window + ":" + index
                        key = (socket, name, pane_key, option)
                        saved = db.execute("SELECT wire_value FROM host_indicator_state WHERE socket_name=? AND session_name=? AND pane_key=? AND option_name=?", key).fetchone()
                        if not value and mode != "snapshot":
                            if saved:
                                # Set only if still absent on the server. The
                                # test and write are one tmux command queue.
                                scope, destination = ("-q", session) if pane_key == "session" else ("-pq", pane)
                                tmux("if-shell", "-F", "-t", pane, "#{!:#{" + option + "}}",
                                     "set-option " + scope + " -t " + destination + " " + option + " " + shquote(saved[0]))
                                value = tmux("display-message", "-p", "-t", pane, "#{" + option + "}")
                        row[position] = value
                        if value and (not saved or timestamp(value) >= timestamp(saved[0])):
                            db.execute("INSERT INTO host_indicator_state VALUES (?,?,?,?,?) ON CONFLICT(socket_name,session_name,pane_key,option_name) DO UPDATE SET wire_value=excluded.wire_value", key + (value,))

        if mode == "monitor":
            monitor_fields = ["session_name", "pane_id", OPTIONS[0], OPTIONS[1], OPTIONS[2], OPTIONS[4],
                              "pane_dead", "pane_current_command", "window_activity", "@holy_watcher_v1", OPTIONS[3]]
            for row in all_rows:
                values = dict(zip(fields, row))
                print("\x1f".join(values[field] for field in monitor_fields))

    def timestamp(wire):
        fields = wire.split("|")
        try:
            return int(fields[-1] if len(fields) == 4 else fields[3])
        except (ValueError, IndexError):
            return 0

    def shquote(value):
        return "'" + value.replace("'", "'\"'\"'") + "'"

    try:
        main()
    except Exception as error:
        print("Holy host state mirror failed: " + type(error).__name__, file=sys.stderr)
        raise SystemExit(1)
    """# + "\n"

    private static func jsonLiteral<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let text = String(data: data, encoding: .utf8) else {
            preconditionFailure("Cannot encode host journal command arguments")
        }
        return text
    }
}
