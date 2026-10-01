#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d -t dotfiles-tmux-wheel.XXXXXX)"

cleanup() {
  tmux -S "$TEST_ROOT/local.sock" kill-server >/dev/null 2>&1 || true
  tmux -S "$TEST_ROOT/remote.sock" kill-server >/dev/null 2>&1 || true
  tmux -S "$TEST_ROOT/e2e.sock" kill-server >/dev/null 2>&1 || true
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

assert_server() {
  local socket="$1"
  local label="$2"
  local wheel_up

  tmux -S "$socket" -f "$ROOT/.tmux.conf" new-session -d

  [[ "$(tmux -S "$socket" show-options -gv mouse)" == "on" ]]
  wheel_up="$(tmux -S "$socket" list-keys -T root | grep 'WheelUpPane')"
  [[ "$wheel_up" == *'#{alternate_on}'* ]]
  [[ "$wheel_up" == *'#{mouse_any_flag}'* ]]
  [[ "$wheel_up" == *'send-keys -M'* ]]
  [[ "$wheel_up" == *'copy-mode -e'* ]]

  # No root-table override may consume arrow keys: they must continue through
  # SSH/tmux to Claude's prompt-history handler as normal terminal input.
  if [[ -n "$(tmux -S "$socket" list-keys -T root Up 2>/dev/null)" ]]; then
    echo "[$label] root Up unexpectedly bound" >&2
    return 1
  fi
  if [[ -n "$(tmux -S "$socket" list-keys -T root Down 2>/dev/null)" ]]; then
    echo "[$label] root Down unexpectedly bound" >&2
    return 1
  fi

  echo "[test-tmux-wheel] $label: wheel policy bound, arrows=passthrough"
}

# Model both ends of `local tmux -> SSH -> remote tmux -> Claude`. Whichever
# server is outermost and receives the wheel uses the same portable rule.
assert_server "$TEST_ROOT/local.sock" local
assert_server "$TEST_ROOT/remote.sock" remote

# End to end: attach a real client through a pty, type actual SGR wheel-up
# bytes into it, and observe where tmux delivers the event.
python3 - "$ROOT/.tmux.conf" "$TEST_ROOT" <<'PY'
import fcntl, os, pty, struct, subprocess, sys, termios, threading, time

conf, root = sys.argv[1], sys.argv[2]
sock = os.path.join(root, "e2e.sock")
env = dict(os.environ, TERM="xterm-256color")
env.pop("TMUX", None)

# Fake TUI: optionally enter the alternate screen, request SGR mouse input,
# and log every byte it receives.
APP = r'''
import os, sys, tty
log, alt = sys.argv[1], sys.argv[2] == "1"
tty.setraw(0)
os.write(1, ((b"\x1b[?1049h" if alt else b"") + b"\x1b[?1000h\x1b[?1006h"))
with open(log, "ab", buffering=0) as f:
    while True:
        f.write(os.read(0, 1024))
'''

def tmux(*args):
    return subprocess.run(["tmux", "-S", sock, *args], env=env, check=True,
                          capture_output=True, text=True).stdout.strip()

def wait(cond, what, timeout=5.0):
    end = time.time() + timeout
    while time.time() < end:
        if cond():
            return
        time.sleep(0.05)
    raise SystemExit(f"[test-tmux-wheel] e2e timeout: {what}")

app = os.path.join(root, "app.py")
open(app, "w").write(APP)
logs = {name: os.path.join(root, f"{name}.log") for name in ("fullscreen", "inline")}

tmux("-f", conf, "new-session", "-d", "-x", "80", "-y", "24", "-s", "e2e", "-n", "shell")
tmux("send-keys", "-t", "e2e:shell", "seq 1 200", "Enter")
wait(lambda: int(tmux("display", "-p", "-t", "e2e:shell", "#{history_size}")) > 0,
     "shell history")
tmux("new-window", "-d", "-t", "e2e", "-n", "fullscreen",
     f"python3 {app} {logs['fullscreen']} 1")
tmux("new-window", "-d", "-t", "e2e", "-n", "inline",
     f"python3 {app} {logs['inline']} 0")
wait(lambda: tmux("display", "-p", "-t", "e2e:fullscreen",
                  "#{alternate_on}#{mouse_any_flag}") == "11", "fullscreen app ready")
wait(lambda: tmux("display", "-p", "-t", "e2e:inline",
                  "#{alternate_on}#{mouse_any_flag}") == "01", "inline app ready")

pid, fd = pty.fork()
if pid == 0:
    os.execvpe("tmux", ["tmux", "-S", sock, "attach-session", "-t", "e2e"], env)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))

def drain():
    try:
        while os.read(fd, 65536):
            pass
    except OSError:
        pass
threading.Thread(target=drain, daemon=True).start()
wait(lambda: tmux("list-clients", "-F", "#{client_name}") != "", "client attached")

WHEEL_UP = b"\x1b[<64;10;10M"

def wheel(window):
    tmux("select-window", "-t", f"e2e:{window}")
    wait(lambda: tmux("display", "-p", "-c", tmux("list-clients", "-F", "#{client_name}"),
                      "#{window_name}") == window, f"{window} selected")
    os.write(fd, WHEEL_UP)

def in_mode(window):
    return tmux("display", "-p", "-t", f"e2e:{window}", "#{pane_in_mode}") == "1"

def received(name):
    return os.path.exists(logs[name]) and b"\x1b[<64;" in open(logs[name], "rb").read()

# 1. Plain shell: wheel enters copy mode over existing scrollback.
wheel("shell")
wait(lambda: in_mode("shell"), "shell enters copy mode")
print("[test-tmux-wheel] e2e shell: wheel -> copy mode")

# 2. Alternate-screen mouse TUI (Codex-like): wheel reaches the app.
wheel("fullscreen")
wait(lambda: received("fullscreen"), "fullscreen app receives wheel")
assert not in_mode("fullscreen"), "fullscreen app must not enter copy mode"
print("[test-tmux-wheel] e2e fullscreen TUI: wheel -> app")

# 3. Inline mouse TUI (Claude-like): wheel stays tmux scrollback.
wheel("inline")
wait(lambda: in_mode("inline"), "inline app enters copy mode")
assert not received("inline"), "inline app must not receive the wheel"
print("[test-tmux-wheel] e2e inline TUI: wheel -> copy mode")

os.kill(pid, 15)
PY

echo "[test-tmux-wheel] local/SSH/nested-tmux policy passed"
