# Claude Code dotfiles — auto-memory hardening

Tools for redirecting Claude Code's built-in auto-memory writes to the
project-level `.agent-lessons/` (ALR) knowledge base.

## Why

Claude Code's default system prompt contains a long `# auto memory` section
that strongly biases the model toward writing experiences / feedback / rules
into `~/.claude/projects/<slug>/memory/`. That directory is per-user,
per-machine, opaque to the team, and not git-tracked.

Most isuper-style monorepos want the opposite: every lesson lives in
`<repo>/.agent-lessons/` so it's git-tracked, reviewable, and shared across
agents / sessions / engineers. Project-level CLAUDE.md instructions to
"ignore auto-memory" sit near the bottom of the prompt and are routinely
overridden in practice by the longer default section.

These scripts make the rule enforceable instead of advisory.

## Components

| Path | Role |
|---|---|
| `hooks/block-auto-memory.sh` | PreToolUse hook. Rejects Write/Edit/MultiEdit/NotebookEdit when `file_path` lives under `~/.claude/projects/<slug>/memory/`. Returns a `decision:block` JSON with a redirect message so the LLM retries against `.agent-lessons/`. |
| `settings.snippets/block-auto-memory.json` | Canonical merge fragment — the exact JSON the install script splices into `<project>/.claude/settings.json` under `.hooks.PreToolUse[]`. Contains the placeholder `__HOOK_COMMAND__` which install replaces with the absolute path to the hook script. |
| `scripts/install-block-auto-memory.sh [project_dir]` | Idempotently merges the snippet into `<project>/.claude/settings.json` via jq. Safe to re-run. |
| `scripts/uninstall-block-auto-memory.sh [project_dir]` | Removes the hook from `<project>/.claude/settings.json`. |
| `scripts/list-memory.sh [project_dir]` | Prints existing auto-memory files for the project so they can be hand-migrated to `.agent-lessons/lessons/`. |
| `scripts/ssh-oauth-token.sh` | Installs, checks, or removes a private SSH-only OAuth token wrapper for Claude Code on macOS. See `docs/macos-ssh-claude-code-oauth-token-sop.md`. |

## macOS SSH OAuth token

Install from an existing single-line raw token file without printing its content:

```bash
make claude-ssh-oauth-install TOKEN_FILE=/path/to/raw-token
```

Or omit `TOKEN_FILE` to receive a hidden interactive prompt:

```bash
make claude-ssh-oauth-install
```

Verify or uninstall:

```bash
make claude-ssh-oauth-check
make claude-ssh-oauth-uninstall
make claude-ssh-oauth-uninstall DELETE_TOKEN=1
```

The installer is idempotent, backs up `~/.zshrc` before changing it, stores the
token at `~/.config/claude/ssh-oauth-token` with mode `0600`, and never prints
the token. If `~/.zshrc` is a symlink, it edits the resolved target atomically
without replacing the symlink, while keeping unique backups under
`~/.zshrc.bak.*` rather than inside the target repo. Uninstall retains the
token unless `DELETE_TOKEN=1` is explicit.

The SSH wrapper defaults `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` to `1`, preventing
Claude-launched subprocesses from inheriting Anthropic and cloud-provider
credentials. In Claude Code 2.1.220 that hardening also forces permission mode
back to `default`. A trusted workflow that explicitly needs another supported
permission mode can opt out for one invocation, accepting that subprocesses may
inherit the injected OAuth credential:

```bash
CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=0 claude
```

## Per-project usage

In any project Makefile that wants this behavior, add:

```makefile
DOTFILES_CLAUDE := $(HOME)/Projects/dotfiles/claude

.PHONY: claude-disable-auto-memory claude-enable-auto-memory claude-list-memory

claude-disable-auto-memory:
	@bash $(DOTFILES_CLAUDE)/scripts/install-block-auto-memory.sh $(PWD)

claude-enable-auto-memory:
	@bash $(DOTFILES_CLAUDE)/scripts/uninstall-block-auto-memory.sh $(PWD)

claude-list-memory:
	@bash $(DOTFILES_CLAUDE)/scripts/list-memory.sh $(PWD)
```

Then run:

```
make claude-disable-auto-memory
```

The hook is registered in `<project>/.claude/settings.json` and fires on
every Write-like tool call in that project's Claude Code sessions.

## Manual install (no jq, or you want to read what gets merged)

If you can't or don't want to run the install script (CI without jq,
non-standard dotfiles path, you already have a complex `settings.json` and
prefer to splice by eye), the canonical merge fragment lives at
`settings.snippets/block-auto-memory.json`:

```json
{
  "matcher": "Write|Edit|MultiEdit|NotebookEdit",
  "hooks": [
    {
      "type": "command",
      "command": "__HOOK_COMMAND__"
    }
  ]
}
```

Substitute `__HOOK_COMMAND__` with the absolute path to the hook script
(`bash /absolute/path/to/dotfiles/claude/hooks/block-auto-memory.sh`) and
append the resulting object to your project's
`.claude/settings.json` under `.hooks.PreToolUse[]`. The install script is
just `jq` automation on top of this exact fragment — nothing more.

## Requirements

- `jq` (`brew install jq`) — used by install/uninstall scripts to merge JSON.
- The dotfiles repo cloned at `~/Projects/dotfiles/`. The Makefile snippet
  above assumes this path.

## What gets blocked

Any tool call whose `file_path` matches:

```
*/.claude/projects/*/memory
*/.claude/projects/*/memory/*
```

Reading from those paths is NOT blocked — only writes. That way old memory
content stays accessible while new persistence is forced to ALR.

## Reversibility

`make claude-enable-auto-memory` removes the hook from the project's
`.claude/settings.json` without touching anything else. The hook script
itself in dotfiles is untouched.
