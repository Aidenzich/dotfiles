#!/usr/bin/env bash
# macOS bootstrap: ensure Homebrew, run brew bundle, then common.sh.

set -euo pipefail
DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v brew >/dev/null 2>&1; then
  echo "[mac] installing Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # New brew on Apple Silicon installs to /opt/homebrew — make it findable now
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
fi

echo "[mac] running brew bundle from pkgs/Brewfile"
brew bundle --file="$DOTFILES_ROOT/pkgs/Brewfile"

echo "[mac] verifying uv"
if ! command -v uv >/dev/null 2>&1; then
  echo "[mac] uv missing after brew bundle — installing via official script"
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi

echo "[mac] installing/upgrading Antigravity CLI"
curl -fsSL https://antigravity.google/cli/install.sh | bash

# Tailscale ships via brew as CLI + daemon, but the system daemon and login
# are deliberate (privileged) steps we don't automate. Remind the user.
if command -v tailscale >/dev/null 2>&1 && ! tailscale status >/dev/null 2>&1; then
  echo "[mac] tailscale installed but not up yet. Start it with:"
  echo "        sudo tailscaled install-system-daemon"
  echo "        sudo tailscale up"
fi

if [[ -d /Applications/iTerm.app ]] || defaults export com.googlecode.iterm2 - >/dev/null 2>&1; then
  bash "$DOTFILES_ROOT/install/iterm2.sh"
else
  echo "[mac] iTerm2 not installed/configured; skipping profile settings"
fi

bash "$DOTFILES_ROOT/install/common.sh"
