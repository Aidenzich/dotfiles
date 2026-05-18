#!/usr/bin/env bash
# PreToolUse hook: block Claude Code's built-in auto-memory writes.
# All project knowledge must go through agent-lessons-router (ALR).
#
# Triggers on Write|Edit|MultiEdit|NotebookEdit when the target file_path
# lives under ~/.claude/projects/<slug>/memory/.
#
# Stdin: tool input JSON from Claude Code.
# Exit 2 + JSON `{"decision":"block","reason":...}` → tells the LLM the call
# was rejected and why, prompting it to retry against .agent-lessons/.

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  # Fail open: if jq is missing we can't parse the payload safely.
  # Prefer letting the call through over silently mis-deciding.
  exit 0
fi

input=$(cat)
file_path=$(printf '%s' "$input" | jq -r '
  .tool_input.file_path
  // .tool_input.notebook_path
  // .tool_input.path
  // ""
')

case "$file_path" in
  */.claude/projects/*/memory|*/.claude/projects/*/memory/*)
    cat <<'JSON'
{
  "decision": "block",
  "reason": "Auto-memory is disabled on this machine (~/Projects/dotfiles policy). All knowledge persistence MUST go through agent-lessons-router (ALR). Write the lesson to <PROJECT_ROOT>/.agent-lessons/lessons/<name>.md with the ALR frontmatter (title/domain/tags/severity), then update the matching sub-index (index.md Latest Lessons + the relevant index_<domain>.md). Use the /agent-lessons-router skill for the SOP. Do not retry the same write path."
}
JSON
    exit 2
    ;;
esac

exit 0
