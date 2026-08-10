#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d -t dotfiles-claude-home.XXXXXX)"
FAKE_BIN="$TEST_ROOT/bin"
HOMES_ROOT="$TEST_ROOT/homes"
TEST_HOME="$TEST_ROOT/home"
ZSHRC_TARGET="$TEST_ROOT/zshrc-target"
ZSHRC_LINK="$TEST_HOME/.zshrc"
CALLS="$TEST_ROOT/calls.log"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

mkdir -p "$FAKE_BIN" "$TEST_HOME"
cat > "$ZSHRC_TARGET" <<'EOF'
# existing zsh configuration

# >>> dotfiles codex-homes >>>
codex-existing() {
  CODEX_HOME=/tmp/existing command codex "$@"
}
# <<< dotfiles codex-homes <<<
EOF
ln -s ../zshrc-target "$ZSHRC_LINK"

cat > "$FAKE_BIN/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${CLAUDE_CONFIG_DIR:?}"
: "${FAKE_CLAUDE_CALLS:?}"
printf '%s\t%s\n' "$CLAUDE_CONFIG_DIR" "$*" >> "$FAKE_CLAUDE_CALLS"

case "$*" in
  'auth status')
    [ -f "$CLAUDE_CONFIG_DIR/.logged-in" ]
    printf 'Logged in\n'
    ;;
  'auth login')
    umask 077
    printf 'authenticated\n' > "$CLAUDE_CONFIG_DIR/.logged-in"
    ;;
  'auth logout')
    rm -f "$CLAUDE_CONFIG_DIR/.logged-in"
    ;;
  *)
    printf 'run:%s\n' "$*"
    ;;
esac
EOF
chmod 755 "$FAKE_BIN/claude"

run_script() {
  CLAUDE_HOMES_ROOT="$HOMES_ROOT" \
  CLAUDE_ZSHRC="$ZSHRC_LINK" \
  FAKE_CLAUDE_CALLS="$CALLS" \
  PATH="$FAKE_BIN:$PATH" \
    bash "$ROOT/claude/scripts/claude-home.sh" "$@"
}

run_make() {
  CLAUDE_HOMES_ROOT="$HOMES_ROOT" \
  CLAUDE_ZSHRC="$ZSHRC_LINK" \
  FAKE_CLAUDE_CALLS="$CALLS" \
  PATH="$FAKE_BIN:$PATH" \
    make -s -C "$ROOT" "$@"
}

mode() {
  stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"
}

run_make claude-add-home ACCOUNT=work >/dev/null
[[ -d "$HOMES_ROOT/work" ]]
[[ -f "$HOMES_ROOT/work/.logged-in" ]]
[[ "$(mode "$HOMES_ROOT")" == "700" ]]
[[ "$(mode "$HOMES_ROOT/work")" == "700" ]]
[[ "$(mode "$HOMES_ROOT/work/.logged-in")" == "600" ]]
[[ "$(grep -c $'\tauth login$' "$CALLS")" == "1" ]]
[[ "$(grep -c $'\tauth status$' "$CALLS")" == "2" ]]

# The managed shortcut is written through the symlink and preserves other blocks.
[[ -L "$ZSHRC_LINK" ]]
grep -Fq 'claude-work() {' "$ZSHRC_TARGET"
grep -Fq "CLAUDE_CONFIG_DIR=$HOMES_ROOT/work command claude \"\$@\"" "$ZSHRC_TARGET"
grep -Fq '# >>> dotfiles codex-homes >>>' "$ZSHRC_TARGET"
grep -Fq 'codex-existing() {' "$ZSHRC_TARGET"
[[ "$(find "$TEST_HOME" -maxdepth 1 -name '.zshrc.bak.*' | wc -l | tr -d ' ')" == "1" ]]
[[ "$(find "$TEST_ROOT" -maxdepth 1 -name 'zshrc-target.bak.*' | wc -l | tr -d ' ')" == "0" ]]
[[ "$(grep -Fc '# >>> dotfiles claude-homes >>>' "$ZSHRC_TARGET")" == "1" ]]
[[ "$(grep -Fc '# <<< dotfiles claude-homes <<<' "$ZSHRC_TARGET")" == "1" ]]
zsh -n "$ZSHRC_TARGET"

# Re-adding preserves the login and does not duplicate auth or zsh entries.
login_before="$(cksum "$HOMES_ROOT/work/.logged-in")"
run_make claude-add-home ACCOUNT=work >/dev/null
[[ "$(cksum "$HOMES_ROOT/work/.logged-in")" == "$login_before" ]]
[[ "$(grep -c $'\tauth login$' "$CALLS")" == "1" ]]
[[ "$(grep -c $'\tauth status$' "$CALLS")" == "3" ]]
[[ "$(grep -Fc 'claude-work() {' "$ZSHRC_TARGET")" == "1" ]]
[[ "$(grep -Fc '# >>> dotfiles claude-homes >>>' "$ZSHRC_TARGET")" == "1" ]]

run_make claude-add-home ACCOUNT=personal >/dev/null
grep -Fq 'claude-work() {' "$ZSHRC_TARGET"
grep -Fq 'claude-personal() {' "$ZSHRC_TARGET"
wrapper_output="$(
  FAKE_CLAUDE_CALLS="$CALLS" PATH="$FAKE_BIN:$PATH" \
    zsh -c 'source "$1"; claude-personal --version' _ "$ZSHRC_TARGET"
)"
[[ "$wrapper_output" == 'run:--version' ]]

# Removing deletes only the selected home and removes only its shortcut.
CONFIRM=1 run_make claude-remove-home ACCOUNT=work >/dev/null
[[ ! -e "$HOMES_ROOT/work" ]]
[[ -d "$HOMES_ROOT/personal" ]]
! grep -Fq 'claude-work() {' "$ZSHRC_TARGET"
grep -Fq 'claude-personal() {' "$ZSHRC_TARGET"
grep -Fq "$HOMES_ROOT/work"$'\tauth logout' "$CALLS"
grep -Fq 'codex-existing() {' "$ZSHRC_TARGET"
[[ -L "$ZSHRC_LINK" ]]
zsh -n "$ZSHRC_TARGET"

if run_script add '../escape' >/dev/null 2>&1; then
  echo '[test-claude-home] traversal-like ACCOUNT unexpectedly accepted' >&2
  exit 1
fi
if run_make claude-add-home >/dev/null 2>&1; then
  echo '[test-claude-home] empty ACCOUNT unexpectedly accepted' >&2
  exit 1
fi
if run_make claude-remove-home ACCOUNT=personal >/dev/null 2>&1; then
  echo '[test-claude-home] non-interactive removal unexpectedly skipped confirmation' >&2
  exit 1
fi

echo '[test-claude-home] isolated account home lifecycle passed'
