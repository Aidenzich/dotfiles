#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d -t dotfiles-tmux-wheel.XXXXXX)"

cleanup() {
  tmux -S "$TEST_ROOT/local.sock" kill-server >/dev/null 2>&1 || true
  tmux -S "$TEST_ROOT/remote.sock" kill-server >/dev/null 2>&1 || true
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

assert_server() {
  local socket="$1"
  local label="$2"
  local wheel_up

  tmux -S "$socket" -f "$ROOT/.tmux.conf" new-session -d

  [[ "$(tmux -S "$socket" show-options -gv mouse)" == "on" ]]
  wheel_up="$(tmux -S "$socket" list-keys -T root | grep 'WheelUpPane')"
  [[ "$wheel_up" == *'copy-mode -e'* ]]
  [[ "$wheel_up" != *'send-keys -M'* ]]

  # No root-table override may consume arrow keys: they must continue through
  # SSH/tmux to Claude's prompt-history handler as normal terminal input.
  if [[ -n "$(tmux -S "$socket" list-keys -T root Up 2>/dev/null)" ]]; then
    echo "[$label] root Up unexpectedly bound" >&2
    return 1
  fi
  if [[ -n "$(tmux -S "$socket" list-keys -T root Down 2>/dev/null)" ]]; then
    echo "[$label] root Down unexpectedly bound" >&2
    return 1
  fi

  echo "[test-tmux-wheel] $label: wheel=copy-mode, arrows=passthrough"
}

# Model both ends of `local tmux -> SSH -> remote tmux -> Claude`. Whichever
# server is outermost and receives the wheel uses the same portable rule.
assert_server "$TEST_ROOT/local.sock" local
assert_server "$TEST_ROOT/remote.sock" remote

echo "[test-tmux-wheel] local/SSH/nested-tmux policy passed"
