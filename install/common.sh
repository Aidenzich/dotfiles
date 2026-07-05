#!/usr/bin/env bash
# OS-agnostic post-install steps:
#   1. symlink dotfiles → $HOME (from install/symlinks.txt)
#   2. check remote-login / SSH readiness (report-only, for Terminus)
#   3. greet
#
# Called by mac.sh / linux.sh after the OS-specific package installs finish.
# Idempotent: safe to re-run.

set -euo pipefail
DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "$DOTFILES_ROOT/install/lib/symlink.sh"
# shellcheck disable=SC1091
source "$DOTFILES_ROOT/install/lib/ssh-check.sh"
# shellcheck disable=SC1091
source "$DOTFILES_ROOT/install/lib/greet.sh"

echo "[common] symlinking dotfiles → \$HOME"
process_symlinks_file \
  "$DOTFILES_ROOT/install/symlinks.txt" \
  "$DOTFILES_ROOT" \
  "$HOME"

echo
echo "[common] Claude per-project hook: 'make claude-disable-auto-memory TARGET=/path/to/project'"
echo "[common] uv tip: 'uv python install 3.12 && uv tool install ruff'"

# Report-only SSH/remote-login check (for connecting via Terminus). Never
# flips the setting; only prints the enable command when it's off.
check_ssh_remote || true

geeky_welcome
