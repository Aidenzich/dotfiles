#!/usr/bin/env bash
# Linux / WSL bootstrap. Detects the package manager (apt/dnf/pacman/zypper/apk),
# installs pkgs/linux.txt, installs uv via the official script (apt versions
# lag), then runs common.sh.

set -euo pipefail
DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mgr=""
for m in apt-get dnf pacman zypper apk; do
  if command -v "$m" >/dev/null 2>&1; then
    mgr="$m"
    break
  fi
done

if [ -z "$mgr" ]; then
  echo "error: no supported package manager (apt/dnf/pacman/zypper/apk)" >&2
  exit 1
fi
echo "[linux] using $mgr"

SUDO=""
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
fi

# Read non-blank non-comment lines into an array.
pkgs=()
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in ''|\#*) continue ;; esac
  pkgs+=("$line")
done < "$DOTFILES_ROOT/pkgs/linux.txt"

if [ ${#pkgs[@]} -eq 0 ]; then
  echo "[linux] pkgs/linux.txt is empty — skipping package install"
else
  case "$mgr" in
    apt-get) $SUDO apt-get update && $SUDO apt-get install -y "${pkgs[@]}" ;;
    dnf)     $SUDO dnf install -y "${pkgs[@]}" ;;
    pacman)  $SUDO pacman -S --needed --noconfirm "${pkgs[@]}" ;;
    zypper)  $SUDO zypper install -y "${pkgs[@]}" ;;
    apk)     $SUDO apk add "${pkgs[@]}" ;;
  esac
fi

if ! command -v uv >/dev/null 2>&1; then
  echo "[linux] installing uv via official script"
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi

# Install npm globals (e.g. @openai/codex). Skipped silently if npm is absent
# — happens if the user's distro ships a different nodejs package set.
NPM_GLOBALS_FILE="$DOTFILES_ROOT/pkgs/npm-global.txt"
if [ -f "$NPM_GLOBALS_FILE" ]; then
  if command -v npm >/dev/null 2>&1; then
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in ''|\#*) continue ;; esac
      echo "[linux] npm i -g $line"
      $SUDO npm i -g "$line"
    done < "$NPM_GLOBALS_FILE"
  else
    echo "[linux] WARN: npm not on PATH — skipped pkgs/npm-global.txt"
    echo "        install npm manually, then run: $(grep -v '^[#[:space:]]*$' "$NPM_GLOBALS_FILE" | sed 's/^/  npm i -g /')"
  fi
fi

bash "$DOTFILES_ROOT/install/common.sh"
