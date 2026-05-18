#!/usr/bin/env bash
# Idempotent symlink helpers shared by every per-OS installer.
# Sourced (not executed) from common.sh / windows.ps1 calls bash equivalent.

# Symlink one absolute src → absolute dst.
# - If dst is already the desired symlink, no-op.
# - If dst exists (regular file or wrong symlink), back it up to
#   dst.bak.<unix-timestamp> before linking.
# - Always mkdir -p the parent of dst.
symlink_one() {
  local src="$1" dst="$2"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    printf '  ok     %s → %s (already linked)\n' "$dst" "$src"
    return 0
  fi
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    local bak="$dst.bak.$(date +%Y%m%d%H%M%S)"
    mv "$dst" "$bak"
    printf '  backup %s → %s\n' "$dst" "$bak"
  fi
  mkdir -p "$(dirname "$dst")"
  ln -s "$src" "$dst"
  printf '  link   %s → %s\n' "$dst" "$src"
}

# Process a symlinks list file.
# Each non-comment line: <src_relative_to_dotfiles>:<dst_relative_to_home>
# Lines starting with '#' or blank lines are skipped.
process_symlinks_file() {
  local list="$1" dotfiles_root="$2" home_root="$3"
  if [ ! -f "$list" ]; then
    echo "  (no symlinks.txt at $list — nothing to link)"
    return 0
  fi
  while IFS= read -r raw || [ -n "$raw" ]; do
    # strip comments + blanks
    case "$raw" in
      ''|\#*) continue ;;
    esac
    # split on first ':'
    local src="${raw%%:*}"
    local dst="${raw#*:}"
    [ -z "$src" ] || [ -z "$dst" ] && continue
    symlink_one "$dotfiles_root/$src" "$home_root/$dst"
  done < "$list"
}
