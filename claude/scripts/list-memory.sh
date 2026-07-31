#!/usr/bin/env bash
# List any existing Claude auto-memory entries for a project so the user
# (or operator) can hand-migrate them to .agent-lessons/.
#
# Usage:
#   bash list-memory.sh [project_dir]
#
# The Claude auto-memory dir name is derived from the project's expanded
# absolute path: ~/Projects/example → -Users-<account>-Projects-example (macOS)

set -euo pipefail

PROJECT="${1:-$PWD}"
PROJECT_ABS="$(cd "$PROJECT" && pwd)"
SLUG=$(printf '%s' "$PROJECT_ABS" | tr '/' '-')
MEMORY_DIR="$HOME/.claude/projects/$SLUG/memory"

if [ ! -d "$MEMORY_DIR" ]; then
  echo "no auto-memory dir for $PROJECT_ABS"
  echo "  expected: $MEMORY_DIR"
  exit 0
fi

echo "auto-memory dir: $MEMORY_DIR"
echo
if [ -f "$MEMORY_DIR/MEMORY.md" ]; then
  echo "=== MEMORY.md (index) ==="
  cat "$MEMORY_DIR/MEMORY.md"
  echo
fi

shopt -s nullglob
files=( "$MEMORY_DIR"/*.md )
if [ ${#files[@]} -eq 0 ]; then
  echo "no .md files under $MEMORY_DIR"
  exit 0
fi

echo "=== individual lesson files (${#files[@]}) ==="
for f in "${files[@]}"; do
  base=$(basename "$f")
  [ "$base" = "MEMORY.md" ] && continue
  echo
  echo "--- $base ---"
  cat "$f"
done

echo
echo "→ migrate each to: $PROJECT_ABS/.agent-lessons/lessons/<name>.md"
echo "→ update         : $PROJECT_ABS/.agent-lessons/index.md (Latest Lessons table, keep ≤20 entries)"
echo "→ then remove    : rm $MEMORY_DIR/<file>"
