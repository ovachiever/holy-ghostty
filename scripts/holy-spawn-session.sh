#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  holy-spawn-session.sh [options]

Options:
  --title TEXT               Operator-facing session title
  --runtime NAME             shell|claude|codex|opencode
  --transport NAME           local|ssh
  --host DEST                SSH destination, e.g. studio or user@studio
  --tmux-session NAME        Tmux session name
  --tmux-socket NAME         Tmux socket name (defaults to holy)
  --working-directory PATH   Working directory used when tmux creates the session
  --bootstrap-command CMD    Command to run before handing off to the login shell
  --initial-input TEXT       Initial input sent after attach
  --create-if-missing BOOL   true|false (default: true)
  -h, --help                 Show this help

Examples:
  holy-spawn-session.sh --tmux-session temp --title temp
  holy-spawn-session.sh --host studio --transport ssh --tmux-session temp --title studio/temp
EOF
}

require_value() {
  local flag="$1"
  local value="${2-}"
  if [[ -z "$value" ]]; then
    echo "Missing value for ${flag}" >&2
    exit 1
  fi
}

title=""
runtime="shell"
transport=""
host=""
tmux_session=""
tmux_socket=""
working_directory=""
bootstrap_command=""
initial_input=""
create_if_missing="true"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)
      require_value "$1" "${2-}"
      title="$2"
      shift 2
      ;;
    --runtime)
      require_value "$1" "${2-}"
      runtime="$2"
      shift 2
      ;;
    --transport)
      require_value "$1" "${2-}"
      transport="$2"
      shift 2
      ;;
    --host)
      require_value "$1" "${2-}"
      host="$2"
      shift 2
      ;;
    --tmux-session)
      require_value "$1" "${2-}"
      tmux_session="$2"
      shift 2
      ;;
    --tmux-socket)
      require_value "$1" "${2-}"
      tmux_socket="$2"
      shift 2
      ;;
    --working-directory)
      require_value "$1" "${2-}"
      working_directory="$2"
      shift 2
      ;;
    --bootstrap-command)
      require_value "$1" "${2-}"
      bootstrap_command="$2"
      shift 2
      ;;
    --initial-input)
      require_value "$1" "${2-}"
      initial_input="$2"
      shift 2
      ;;
    --create-if-missing)
      require_value "$1" "${2-}"
      create_if_missing="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$transport" ]]; then
  if [[ -n "$host" ]]; then
    transport="ssh"
  else
    transport="local"
  fi
fi

if [[ "$transport" == "ssh" && -z "$host" ]]; then
  echo "--host is required when --transport ssh is used" >&2
  exit 1
fi

query="$(
  python3 - "$title" "$runtime" "$transport" "$host" "$tmux_session" "$tmux_socket" "$working_directory" "$bootstrap_command" "$initial_input" "$create_if_missing" <<'PY'
import sys
from urllib.parse import quote, urlencode

title, runtime, transport, host, tmux_session, tmux_socket, working_directory, bootstrap_command, initial_input, create_if_missing = sys.argv[1:]

params = {
    "title": title,
    "runtime": runtime,
    "transport": transport,
    "host": host,
    "tmuxSession": tmux_session,
    "tmuxSocket": tmux_socket,
    "workingDirectory": working_directory,
    "bootstrapCommand": bootstrap_command,
    "initialInput": initial_input,
    "createIfMissing": create_if_missing,
}

print(urlencode({key: value for key, value in params.items() if value}, quote_via=quote))
PY
)"

open "holy-ghostty://spawn?${query}"
