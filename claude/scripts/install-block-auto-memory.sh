#!/usr/bin/env bash
# Idempotently install the block-auto-memory PreToolUse hook into a project's
# .claude/settings.json. Default target is $PWD.
#
# Usage:
#   bash install-block-auto-memory.sh [project_dir]
#
# The hook entry is sourced from ../settings.snippets/block-auto-memory.json
# (the canonical merge fragment) with __HOOK_COMMAND__ substituted for the
# absolute path to this dotfiles checkout. Re-running is safe: any prior
# entry referencing the same command is removed before the fresh one is
# appended.

set -euo pipefail

PROJECT="${1:-$PWD}"
SETTINGS="$PROJECT/.claude/settings.json"
DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK_SCRIPT="$DOTFILES_ROOT/claude/hooks/block-auto-memory.sh"
SNIPPET="$DOTFILES_ROOT/claude/settings.snippets/block-auto-memory.json"
HOOK_CMD="bash $HOOK_SCRIPT"

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required (brew install jq)" >&2
  exit 1
fi

if [ ! -f "$SNIPPET" ]; then
  echo "error: snippet missing: $SNIPPET" >&2
  exit 1
fi

if [ ! -x "$HOOK_SCRIPT" ]; then
  echo "warn: $HOOK_SCRIPT not executable; chmod +x applied" >&2
  chmod +x "$HOOK_SCRIPT"
fi

mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || printf '{}\n' > "$SETTINGS"

# Resolve the snippet: substitute the __HOOK_COMMAND__ placeholder with the
# real bash invocation. Done via jq so escaping is correct.
resolved_entry=$(jq \
  --arg cmd "$HOOK_CMD" \
  '
    .hooks |= map(
      if .command == "__HOOK_COMMAND__" then .command = $cmd else . end
    )
  ' "$SNIPPET")

tmp=$(mktemp)
jq \
  --arg cmd "$HOOK_CMD" \
  --argjson entry "$resolved_entry" \
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
  | .hooks.PreToolUse += [$entry]
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

echo "installed PreToolUse hook → $SETTINGS"
echo "  matcher: $(jq -r '.matcher' <<<"$resolved_entry")"
echo "  command: $HOOK_CMD"
