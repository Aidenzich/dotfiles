#!/usr/bin/env bash
# Apply the dotfiles-owned iTerm2 terminal profile settings.

set -euo pipefail

DOMAIN="${ITERM2_PREFERENCES_DOMAIN:-com.googlecode.iterm2}"
PROFILE_NAME="${1:-${ITERM_PROFILE_NAME:-Default}}"
TMUX_MODE="${ITERM2_TMUX_MODE:-local}"
PREFS_DIR="${ITERM2_PREFERENCES_DIR:-$HOME/Library/Preferences}"
DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMUX_LAUNCHER="$DOTFILES_ROOT/install/iterm2-tmux-session.sh"
LIVE_PROFILE_APPLIER="$DOTFILES_ROOT/install/iterm2-live-profile.py"

case "$TMUX_MODE" in
  local|off) ;;
  *)
    echo "[iterm2] unsupported ITERM2_TMUX_MODE: $TMUX_MODE (expected local or off)" >&2
    exit 2
    ;;
esac

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
  local index="$1"
  local key="$2"
  local value="$3"
  local path="New Bookmarks.${index}.${key}"

  if plutil -extract "$path" raw -o - "$tmp" >/dev/null 2>&1; then
    plutil -replace "$path" -bool "$value" "$tmp"
  else
    plutil -insert "$path" -bool "$value" "$tmp"
  fi
}

set_profile_string() {
  local index="$1"
  local key="$2"
  local value="$3"
  local path="New Bookmarks.${index}.${key}"

  if plutil -extract "$path" raw -o - "$tmp" >/dev/null 2>&1; then
    plutil -replace "$path" -string "$value" "$tmp"
  else
    plutil -insert "$path" -string "$value" "$tmp"
  fi
}

set_profile_json() {
  local key="$1"
  local value="$2"
  local path="New Bookmarks.${profile_index}.${key}"

  if plutil -extract "$path" raw -o - "$tmp" >/dev/null 2>&1; then
    plutil -replace "$path" -json "$value" "$tmp"
  else
    plutil -insert "$path" -json "$value" "$tmp"
  fi
}

managed_profile_rows="$(
  jq -r --argjson primary "$profile_index" '
    to_entries[]
    | select(.key == $primary or .value.Name == "tmux")
    | [.key, (.value.Name // "<unnamed>")]
    | @tsv
  ' <<<"$profiles_json"
)"

# Report the wheel as a real mouse event whenever the foreground terminal layer
# requests mouse input. Ordinary tmux then applies our WheelUpPane copy-mode
# binding instead of letting iTerm2 translate the wheel into Up/Down keys.
# Control-mode integration sessions explicitly use `mouse off`, so they retain
# native iTerm2 scrollback. Apply the same values to all managed profiles.
while IFS=$'\t' read -r managed_index managed_name; do
  [[ -n "$managed_index" ]] || continue
  set_profile_bool "$managed_index" 'Mouse Reporting' true
  set_profile_bool "$managed_index" 'Mouse Reporting allow mouse wheel' true
  set_profile_bool "$managed_index" 'Mouse Reporting allow clicks and drags' true
  set_profile_bool "$managed_index" 'Allow Alternate Mouse Scroll' false
  set_profile_bool "$managed_index" 'Automatically Enable Alternate Mouse Scroll' false
  set_profile_bool "$managed_index" 'Scrollback in Alternate Screen' true
  set_profile_bool "$managed_index" 'Scrollback With Status Bar' true
  set_profile_bool "$managed_index" 'Drag to Scroll in Alternate Screen Mode Disabled' true
  # watch-all relies on the standard smcup/rmcup alternate-screen lifecycle.
  set_profile_bool "$managed_index" 'Disable Smcup Rmcup' false
done <<<"$managed_profile_rows"

# local makes each profile invocation its own tmux control-mode session. off
# actively restores iTerm2's login-shell behavior instead of merely skipping
# the installer, because this profile may already contain an older launcher.
if [[ "$TMUX_MODE" == "local" ]]; then
  set_profile_string "$profile_index" 'Command' "$tmux_command"
  set_profile_string "$profile_index" 'Custom Command' 'Yes'
else
  set_profile_string "$profile_index" 'Command' ''
  set_profile_string "$profile_index" 'Custom Command' 'No'
fi

# Traditional terminals encode Return and Shift-Return identically. Give
# Shift-Return an explicit Esc+Return sequence so multiline-capable terminal
# apps (including Claude Code and Codex) can distinguish it across tmux + SSH.
# This updates only this shortcut and preserves all other profile key mappings.
set_profile_json 'Keyboard Map.0xd-0x20000' \
  '{"Action":11,"Text":"0x1b 0x0d"}'

defaults import "$DOMAIN" "$tmp" >/dev/null
defaults export "$DOMAIN" "$verify_tmp" >/dev/null

# iTerm2 caches both saved profile templates and session-local profiles while
# the app is running. Updating the preference plist alone changes neither.
# When the local API is enabled, refresh both layers so existing and future
# sessions work without a restart (which could destroy an integration-owned
# tmux session).
live_refresh_succeeded=false
if [[ "${ITERM2_SKIP_LIVE_REFRESH:-0}" != "1" ]] \
  && pgrep -x iTerm2 >/dev/null 2>&1 \
  && [[ "$(defaults read "$DOMAIN" NoSyncEnableAPIServer 2>/dev/null || true)" == "1" ]] \
  && command -v uv >/dev/null 2>&1 \
  && [[ -f "$LIVE_PROFILE_APPLIER" ]]; then
  if uv run --quiet --with iterm2 python "$LIVE_PROFILE_APPLIER" \
    "$PROFILE_NAME" "$TMUX_MODE" "$tmux_command"; then
    live_refresh_succeeded=true
  else
    echo "[iterm2] warning: in-memory profiles were not updated; restart iTerm2 after saving work" >&2
  fi
else
  echo "[iterm2] in-memory profile refresh skipped; saved profiles will apply on next iTerm2 launch"
fi

echo "[iterm2] tmux mode: $TMUX_MODE"
if [[ "$TMUX_MODE" == "local" ]]; then
  echo "[iterm2] tmux lifecycle: one iterm-<session UUID> per iTerm2 session"
else
  echo "[iterm2] tmux lifecycle: disabled; new $PROFILE_NAME sessions use the login shell"
fi
while IFS=$'\t' read -r managed_index managed_name; do
  [[ -n "$managed_index" ]] || continue
  echo "[iterm2] profile: $managed_name"
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
    value="$(plutil -extract "New Bookmarks.${managed_index}.${key}" raw -o - "$verify_tmp")"
    printf '[iterm2]   %-52s %s\n' "$key" "$value"
  done
done <<<"$managed_profile_rows"
for key in 'Command' 'Custom Command'; do
  value="$(plutil -extract "New Bookmarks.${profile_index}.${key}" raw -o - "$verify_tmp")"
  printf '[iterm2]   %-52s %s\n' "$key" "$value"
done
key_mapping="$(plutil -extract "New Bookmarks.${profile_index}.Keyboard Map.0xd-0x20000" json -o - "$verify_tmp")"
printf '[iterm2]   %-52s %s\n' 'Shift-Return key mapping' "$(jq -c . <<<"$key_mapping")"

echo "[iterm2] backup: $backup"
if [[ "$live_refresh_succeeded" == true ]]; then
  echo "[iterm2] saved templates and live sessions refreshed; no iTerm2 restart required"
else
  echo "[iterm2] restart iTerm2 after saving work to load the saved profiles"
fi
