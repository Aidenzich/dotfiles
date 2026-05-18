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

bash "$DOTFILES_ROOT/install/common.sh"
