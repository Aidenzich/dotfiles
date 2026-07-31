#!/usr/bin/env bash
# Apply the dotfiles-owned iTerm2 terminal profile settings.

set -euo pipefail

DOMAIN="com.googlecode.iterm2"
PROFILE_NAME="${1:-${ITERM_PROFILE_NAME:-Default}}"
PREFS_DIR="$HOME/Library/Preferences"
DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMUX_LAUNCHER="$DOTFILES_ROOT/install/iterm2-tmux-session.sh"
LIVE_PROFILE_APPLIER="$DOTFILES_ROOT/install/iterm2-live-profile.py"

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

# Keep click/drag reporting available to mouse-aware terminal apps, but reserve
# the wheel for native iTerm2 scrollback. Preserve output produced by tmux and
# full-screen TUIs so Claude/Codex history remains scrollable.
set_profile_bool 'Mouse Reporting' true
set_profile_bool 'Mouse Reporting allow mouse wheel' false
set_profile_bool 'Mouse Reporting allow clicks and drags' true
set_profile_bool 'Allow Alternate Mouse Scroll' false
set_profile_bool 'Automatically Enable Alternate Mouse Scroll' false
set_profile_bool 'Scrollback in Alternate Screen' true
set_profile_bool 'Scrollback With Status Bar' true
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

# iTerm2 caches a session-local profile while the app is running. Updating the
# preference plist alone does not change already-open Default/tmux sessions.
# When the local API is enabled, refresh those sessions in place so no restart
# (which could destroy an integration-owned tmux session) is necessary.
live_refresh_succeeded=false
if pgrep -x iTerm2 >/dev/null 2>&1 \
  && [[ "$(defaults read "$DOMAIN" NoSyncEnableAPIServer 2>/dev/null || true)" == "1" ]] \
  && command -v uv >/dev/null 2>&1 \
  && [[ -f "$LIVE_PROFILE_APPLIER" ]]; then
  if uv run --quiet --with iterm2 python "$LIVE_PROFILE_APPLIER" "$PROFILE_NAME"; then
    live_refresh_succeeded=true
  else
    echo "[iterm2] warning: live sessions were not updated; new sessions will use the saved profile" >&2
  fi
else
  echo "[iterm2] live session refresh skipped; saved profile will apply on next iTerm2 launch"
fi

echo "[iterm2] profile: $PROFILE_NAME"
echo "[iterm2] tmux lifecycle: one iterm-<session UUID> per iTerm2 session"
for key in \
  'Mouse Reporting' \
  'Mouse Reporting allow mouse wheel' \
  'Mouse Reporting allow clicks and drags' \
  'Allow Alternate Mouse Scroll' \
  'Automatically Enable Alternate Mouse Scroll' \
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
if [[ "$live_refresh_succeeded" == true ]]; then
  echo "[iterm2] live sessions refreshed; no iTerm2 restart required"
else
  echo "[iterm2] open a new iTerm2 session (or restart iTerm2) to load the saved profile"
fi
