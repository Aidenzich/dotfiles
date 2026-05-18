#!/usr/bin/env bash
# Geeky end-of-bootstrap welcome. Reads git config user.name.
# Uses figlet + lolcat if available, falls back to ANSI box.

geeky_welcome() {
  local user email os_name now uname_s
  user="$(git config --global user.name 2>/dev/null || echo stranger)"
  email="$(git config --global user.email 2>/dev/null || echo '')"
  uname_s="$(uname -s 2>/dev/null || echo '?')"
  now="$(date '+%H:%M %Z' 2>/dev/null || date '+%H:%M')"

  case "$uname_s" in
    Darwin) os_name="macOS $(sw_vers -productVersion 2>/dev/null || echo)" ;;
    Linux)
      if [ -r /etc/os-release ]; then
        os_name="$(. /etc/os-release && echo "${PRETTY_NAME:-Linux}")"
      else
        os_name=Linux
      fi
      ;;
    *) os_name="$uname_s" ;;
  esac

  local msg_main="welcome back, @${user}"
  local msg_sub="${os_name} · ${now}"
  local msg_tag="systems are go ⌁"

  echo
  if command -v figlet >/dev/null 2>&1; then
    if command -v lolcat >/dev/null 2>&1; then
      printf '%s\n' "$msg_main" | figlet -f small 2>/dev/null | lolcat
    else
      printf '\033[1;38;5;201m'
      printf '%s\n' "$msg_main" | figlet -f small 2>/dev/null
      printf '\033[0m'
    fi
    printf '   \033[2m%s · %s\033[0m\n\n' "$msg_sub" "$msg_tag"
    return 0
  fi

  # ANSI-only fallback (no figlet/lolcat).
  # Magenta + dim, with leading bar — no right-side border so unicode width
  # mismatches don't make it look ragged.
  printf '\033[1;38;5;201m'
  printf '\n'
  printf '  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
  printf '  bootstrap complete · %s\n' "$msg_tag"
  printf '\n'
  printf '  > %s\n' "$msg_main"
  printf '  > %s\n' "$msg_sub"
  printf '  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
  printf '\033[0m\n'
}

# Allow running this file directly as a sanity check.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  geeky_welcome
fi
