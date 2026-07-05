#!/usr/bin/env bash
# Check (never change) whether this machine accepts inbound SSH, so a remote
# client like Terminus can connect. Sourced from common.sh after installs.
#
# Philosophy: this is a *doctor*, not a fixer. Turning on remote login opens a
# listening port to the network, so we detect the state and print the exact
# enable command for the user to run deliberately — we never flip it silently.

# Print the machine's reachable addresses (LAN + tailscale) as connect hints.
_ssh_connect_hints() {
  local ts_ip lan_ip user
  user="$(id -un 2>/dev/null || echo "$USER")"

  if command -v tailscale >/dev/null 2>&1; then
    ts_ip="$(tailscale ip -4 2>/dev/null | head -n1)"
    [ -n "$ts_ip" ] && printf '    · via Tailscale : ssh %s@%s\n' "$user" "$ts_ip"
  fi

  case "$(uname -s 2>/dev/null)" in
    Darwin) lan_ip="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)" ;;
    *)      lan_ip="$(hostname -I 2>/dev/null | awk '{print $1}')" ;;
  esac
  [ -n "$lan_ip" ] && printf '    · via LAN       : ssh %s@%s\n' "$user" "$lan_ip"
}

# Is anything LISTENing on the local ssh port (22)? Best-effort, no sudo needed.
# Returns 0 (listening) / 1 (not) / 2 (couldn't tell — no probe tool).
_ssh_port_listening() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:22 -sTCP:LISTEN >/dev/null 2>&1 && return 0 || return 1
  elif command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE '(:|\.)22$' && return 0 || return 1
  elif command -v nc >/dev/null 2>&1; then
    nc -z -w1 127.0.0.1 22 >/dev/null 2>&1 && return 0 || return 1
  fi
  return 2
}

# Main entry point. Prints a status line and, if SSH is off, the enable command.
check_ssh_remote() {
  local os
  os="$(bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/detect-os.sh")"

  local GRN='\033[32m' RED='\033[31m' YEL='\033[33m' DIM='\033[2m' RST='\033[0m'
  printf '\n%b[ssh]%b checking remote-login (so Terminus can connect)…\n' "$DIM" "$RST"

  _ssh_port_listening
  local listening=$?

  if [ "$listening" -eq 0 ]; then
    printf '  %b✓%b sshd is listening on :22 — remote SSH looks ready.\n' "$GRN" "$RST"
    _ssh_connect_hints
    return 0
  fi

  if [ "$listening" -eq 2 ]; then
    printf '  %b?%b no probe tool (lsof/ss/nc) found — cannot verify sshd.\n' "$YEL" "$RST"
  else
    printf '  %b✗%b nothing listening on :22 — remote SSH is OFF.\n' "$RED" "$RST"
  fi

  # Print the deliberate enable command for this OS. We do NOT run it.
  case "$os" in
    mac)
      printf '    enable it with (asks for your password):\n'
      printf '      %bsudo systemsetup -setremotelogin on%b\n' "$YEL" "$RST"
      printf '    %bverify:%b sudo systemsetup -getremotelogin\n' "$DIM" "$RST"
      printf '    %bnote:%b also allow "Remote Login" under System Settings → General → Sharing.\n' "$DIM" "$RST"
      ;;
    linux|wsl)
      printf '    enable it with:\n'
      if command -v systemctl >/dev/null 2>&1; then
        printf '      %bsudo apt-get install -y openssh-server   # if not installed%b\n' "$DIM" "$RST"
        printf '      %bsudo systemctl enable --now ssh%b   (or: sshd, distro-dependent)\n' "$YEL" "$RST"
      else
        printf '      %bsudo service ssh start%b\n' "$YEL" "$RST"
      fi
      [ "$os" = "wsl" ] && printf '    %bnote:%b on WSL you also need a Windows firewall port-forward to reach it from outside.\n' "$DIM" "$RST"
      ;;
    *)
      printf '    enable your platform'\''s SSH server, then reconnect.\n'
      ;;
  esac
  _ssh_connect_hints
  return 1
}

# Allow running this file directly as a sanity check.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  check_ssh_remote
fi
