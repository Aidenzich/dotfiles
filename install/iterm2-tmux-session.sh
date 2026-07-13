#!/usr/bin/env bash
# Give one iTerm2 profile invocation one tmux session with the same lifetime.

set -euo pipefail

tmux_bin="${1:-tmux}"
raw_id="${ITERM_SESSION_ID:-}"

if [[ -n "$raw_id" ]]; then
  # ITERM_SESSION_ID is normally term-position:UUID. The UUID remains unique
  # even when the tab/window layout changes.
  session_id="${raw_id##*:}"
else
  # Keep the launcher usable outside iTerm2 for diagnostics.
  session_id="$(date +%Y%m%d-%H%M%S)-$$-${RANDOM:-0}"
fi

session_id="${session_id//[^[:alnum:]_-]/-}"
session_name="iterm-${session_id}"

cleanup() {
  "$tmux_bin" kill-session -t "$session_name" >/dev/null 2>&1 || true
}

# Closing the owning iTerm2 session is an explicit request to destroy this
# tmux session. Other attached clients are therefore disconnected as well.
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

"$tmux_bin" -CC new-session -A -s "$session_name"
