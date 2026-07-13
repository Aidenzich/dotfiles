#!/usr/bin/env bash
# Apply the dotfiles-owned iTerm2 terminal profile settings.

set -euo pipefail

DOMAIN="com.googlecode.iterm2"
PROFILE_NAME="${1:-${ITERM_PROFILE_NAME:-Default}}"
PREFS_DIR="$HOME/Library/Preferences"
DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMUX_LAUNCHER="$DOTFILES_ROOT/install/iterm2-tmux-session.sh"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "[iterm2] skipped: macOS only"
  exit 0
fi

for command in defaults plutil jq tmux; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "[iterm2] required command not found: $command" >&2
    exit 1
  fi
done

tmux_path="$(command -v tmux)"
tmux_command="$TMUX_LAUNCHER $tmux_path"

tmp="$(mktemp -t dotfiles-iterm2.XXXXXX.plist)"
verify_tmp="$(mktemp -t dotfiles-iterm2-verify.XXXXXX.plist)"
trap 'rm -f "$tmp" "$verify_tmp"' EXIT

if ! defaults export "$DOMAIN" "$tmp" >/dev/null 2>&1; then
  echo "[iterm2] no existing iTerm2 preferences found; launch iTerm2 once, then rerun make iterm2" >&2
  exit 1
fi

profiles_json="$(plutil -extract 'New Bookmarks' json -o - "$tmp" 2>/dev/null || true)"
profile_index="$(jq -r --arg name "$PROFILE_NAME" '
  to_entries[] | select(.value.Name == $name) | .key
' <<<"$profiles_json" | head -n 1)"

if [[ -z "$profile_index" ]]; then
  echo "[iterm2] profile not found: $PROFILE_NAME" >&2
  echo "[iterm2] available profiles:" >&2
  jq -r '.[] | "  - \(.Name // "<unnamed>")"' <<<"$profiles_json" >&2
  exit 1
fi

mkdir -p "$PREFS_DIR"
backup="$PREFS_DIR/${DOMAIN}.plist.dotfiles-backup.$(date +%Y%m%d-%H%M%S)"
cp "$tmp" "$backup"

set_profile_bool() {
  local key="$1"
  local value="$2"
  local path="New Bookmarks.${profile_index}.${key}"

  if plutil -extract "$path" raw -o - "$tmp" >/dev/null 2>&1; then
    plutil -replace "$path" -bool "$value" "$tmp"
  else
    plutil -insert "$path" -bool "$value" "$tmp"
  fi
}

set_profile_string() {
  local key="$1"
  local value="$2"
  local path="New Bookmarks.${profile_index}.${key}"

  if plutil -extract "$path" raw -o - "$tmp" >/dev/null 2>&1; then
    plutil -replace "$path" -string "$value" "$tmp"
  else
    plutil -insert "$path" -string "$value" "$tmp"
  fi
}

# Keep mouse-aware terminal apps working, while preventing alternate-screen
# dashboards from growing scrollback when a local selection drag scrolls.
set_profile_bool 'Mouse Reporting' true
set_profile_bool 'Scrollback in Alternate Screen' false
set_profile_bool 'Scrollback With Status Bar' false
set_profile_bool 'Drag to Scroll in Alternate Screen Mode Disabled' true
# watch-all relies on the standard smcup/rmcup alternate-screen lifecycle.
set_profile_bool 'Disable Smcup Rmcup' false

# Make each profile invocation its own tmux control-mode session. The launcher
# derives a unique name from ITERM_SESSION_ID and destroys the tmux session
# when its owning iTerm2 session closes.
set_profile_string 'Command' "$tmux_command"
set_profile_string 'Custom Command' 'Yes'

defaults import "$DOMAIN" "$tmp" >/dev/null
defaults export "$DOMAIN" "$verify_tmp" >/dev/null

echo "[iterm2] profile: $PROFILE_NAME"
echo "[iterm2] tmux lifecycle: one iterm-<session UUID> per iTerm2 session"
for key in \
  'Mouse Reporting' \
  'Scrollback in Alternate Screen' \
  'Scrollback With Status Bar' \
  'Drag to Scroll in Alternate Screen Mode Disabled' \
  'Disable Smcup Rmcup'; do
  value="$(plutil -extract "New Bookmarks.${profile_index}.${key}" raw -o - "$verify_tmp")"
  printf '[iterm2]   %-52s %s\n' "$key" "$value"
done
for key in 'Command' 'Custom Command'; do
  value="$(plutil -extract "New Bookmarks.${profile_index}.${key}" raw -o - "$verify_tmp")"
  printf '[iterm2]   %-52s %s\n' "$key" "$value"
done

echo "[iterm2] backup: $backup"
echo "[iterm2] open a new iTerm2 session (or restart iTerm2) to guarantee the profile reloads"
