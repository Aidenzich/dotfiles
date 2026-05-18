#!/usr/bin/env bash
# Remove the block-auto-memory hook from a project's .claude/settings.json.
# Default target is $PWD.
#
# Usage:
#   bash uninstall-block-auto-memory.sh [project_dir]

set -euo pipefail

PROJECT="${1:-$PWD}"
SETTINGS="$PROJECT/.claude/settings.json"
DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK_SCRIPT="$DOTFILES_ROOT/claude/hooks/block-auto-memory.sh"
HOOK_CMD="bash $HOOK_SCRIPT"

if [ ! -f "$SETTINGS" ]; then
  echo "no $SETTINGS → nothing to uninstall"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required (brew install jq)" >&2
  exit 1
fi

tmp=$(mktemp)
jq --arg cmd "$HOOK_CMD" '
  if (.hooks // {}).PreToolUse then
    .hooks.PreToolUse |= map(
      select(
        ((.hooks // []) | map(.command)) | index($cmd) | not
      )
    )
  else . end
' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

echo "removed block-auto-memory hook from $SETTINGS"
