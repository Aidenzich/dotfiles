#!/usr/bin/env bash

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "[test-iterm2] skipped: macOS only"
  exit 0
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d -t dotfiles-iterm2-mode.XXXXXX)"
DOMAIN="com.aiden.dotfiles.iterm2-mode-test.$$"
FIXTURE="$TEST_ROOT/input.plist"
VERIFY="$TEST_ROOT/verify.plist"

cleanup() {
  defaults delete "$DOMAIN" >/dev/null 2>&1 || true
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

plutil -create xml1 "$FIXTURE"
plutil -insert 'New Bookmarks' -json '[
  {"Name":"Default","Command":"old-launcher","Custom Command":"Yes","Keyboard Map":{}},
  {"Name":"tmux","Command":"runtime-command","Custom Command":"Yes","Keyboard Map":{}}
]' "$FIXTURE"
defaults import "$DOMAIN" "$FIXTURE" >/dev/null

run_mode() {
  local mode="$1"
  ITERM2_PREFERENCES_DOMAIN="$DOMAIN" \
  ITERM2_PREFERENCES_DIR="$TEST_ROOT/backups" \
  ITERM2_SKIP_LIVE_REFRESH=1 \
  ITERM2_TMUX_MODE="$mode" \
    bash "$ROOT/install/iterm2.sh" Default >/dev/null
  defaults export "$DOMAIN" "$VERIFY" >/dev/null
}

value() {
  plutil -extract "$1" raw -o - "$VERIFY"
}

run_mode off
[[ "$(value 'New Bookmarks.0.Custom Command')" == "No" ]]
[[ -z "$(value 'New Bookmarks.0.Command')" ]]
[[ "$(value 'New Bookmarks.0.Mouse Reporting allow mouse wheel')" == "false" ]]
[[ "$(value 'New Bookmarks.1.Scrollback in Alternate Screen')" == "true" ]]
[[ "$(value 'New Bookmarks.1.Command')" == "runtime-command" ]]

run_mode local
[[ "$(value 'New Bookmarks.0.Custom Command')" == "Yes" ]]
[[ "$(value 'New Bookmarks.0.Command')" == *'/install/iterm2-tmux-session.sh '* ]]
[[ "$(value 'New Bookmarks.0.Keyboard Map.0xd-0x20000.Action')" == "11" ]]
[[ "$(value 'New Bookmarks.0.Keyboard Map.0xd-0x20000.Text')" == "0x1b 0x0d" ]]

set +e
ITERM2_PREFERENCES_DOMAIN="$DOMAIN" ITERM2_TMUX_MODE=invalid \
  bash "$ROOT/install/iterm2.sh" Default >/dev/null 2>&1
status=$?
set -e
[[ "$status" -eq 2 ]]

echo "[test-iterm2] local/off transitions passed"
