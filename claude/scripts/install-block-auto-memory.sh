#!/usr/bin/env bash
# Idempotently install the block-auto-memory PreToolUse hook into a project's
# .claude/settings.json. Default target is $PWD.
#
# Usage:
#   bash install-block-auto-memory.sh [project_dir]
#
# Re-running is safe: any prior entry referencing this hook is removed before
# the fresh one is appended.

set -euo pipefail

PROJECT="${1:-$PWD}"
SETTINGS="$PROJECT/.claude/settings.json"
DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK_SCRIPT="$DOTFILES_ROOT/claude/hooks/block-auto-memory.sh"
HOOK_CMD="bash $HOOK_SCRIPT"
MATCHER="Write|Edit|MultiEdit|NotebookEdit"

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required (brew install jq)" >&2
  exit 1
fi

if [ ! -x "$HOOK_SCRIPT" ]; then
  echo "warn: $HOOK_SCRIPT not executable; chmod +x applied" >&2
  chmod +x "$HOOK_SCRIPT"
fi

mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || printf '{}\n' > "$SETTINGS"

tmp=$(mktemp)
jq \
  --arg cmd "$HOOK_CMD" \
  --arg matcher "$MATCHER" \
  '
  .hooks //= {}
  | .hooks.PreToolUse //= []
  # Drop any existing entries whose nested hooks include OUR command,
  # so re-running this installer never duplicates.
  | .hooks.PreToolUse |= map(
      select(
        ((.hooks // []) | map(.command)) | index($cmd) | not
      )
    )
  | .hooks.PreToolUse += [{
      "matcher": $matcher,
      "hooks": [{"type": "command", "command": $cmd}]
    }]
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

echo "installed PreToolUse hook → $SETTINGS"
echo "  matcher: $MATCHER"
echo "  command: $HOOK_CMD"
