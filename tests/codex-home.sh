#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d -t dotfiles-codex-home.XXXXXX)"
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
printf '# existing zsh configuration\n' > "$ZSHRC_TARGET"
ln -s ../zshrc-target "$ZSHRC_LINK"

cat > "$FAKE_BIN/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${CODEX_HOME:?}"
: "${FAKE_CODEX_CALLS:?}"
printf '%s\t%s\n' "$CODEX_HOME" "$*" >> "$FAKE_CODEX_CALLS"

if [[ " $* " == *" login status "* ]]; then
  [ -f "$CODEX_HOME/auth.json" ]
  printf 'Logged in using ChatGPT\n'
  exit 0
fi
if [[ " $* " == *" login "* ]]; then
  umask 077
  printf '{}\n' > "$CODEX_HOME/auth.json"
  exit 0
fi
if [[ " $* " == *" logout "* ]]; then
  rm -f "$CODEX_HOME/auth.json"
  exit 0
fi
printf 'run:%s\n' "$*"
EOF
chmod 755 "$FAKE_BIN/codex"

run_script() {
  CODEX_HOMES_ROOT="$HOMES_ROOT" \
  CODEX_ZSHRC="$ZSHRC_LINK" \
  FAKE_CODEX_CALLS="$CALLS" \
  PATH="$FAKE_BIN:$PATH" \
    bash "$ROOT/codex/scripts/codex-home.sh" "$@"
}

run_make() {
  CODEX_HOMES_ROOT="$HOMES_ROOT" \
  CODEX_ZSHRC="$ZSHRC_LINK" \
  FAKE_CODEX_CALLS="$CALLS" \
  PATH="$FAKE_BIN:$PATH" \
    make -s -C "$ROOT" "$@"
}

mode() {
  stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"
}

run_make codex-add-home ACCOUNT=work >/dev/null
[[ -d "$HOMES_ROOT/work" ]]
[[ -f "$HOMES_ROOT/work/auth.json" ]]
[[ "$(mode "$HOMES_ROOT")" == "700" ]]
[[ "$(mode "$HOMES_ROOT/work")" == "700" ]]
[[ "$(mode "$HOMES_ROOT/work/auth.json")" == "600" ]]
[[ "$(mode "$HOMES_ROOT/work/config.toml")" == "600" ]]
[[ "$(grep -c '^cli_auth_credentials_store = "file"$' "$HOMES_ROOT/work/config.toml")" == "1" ]]
[[ "$(grep -c $'\t.*login$' "$CALLS")" == "1" ]]
[[ "$(grep -c $'\tlogin status$' "$CALLS")" == "1" ]]

# The managed shortcut is written through the symlink without replacing it.
[[ -L "$ZSHRC_LINK" ]]
grep -Fq 'codex-work() {' "$ZSHRC_TARGET"
grep -Fq "CODEX_HOME=$HOMES_ROOT/work command codex \"\$@\"" "$ZSHRC_TARGET"
[[ "$(find "$TEST_HOME" -maxdepth 1 -name '.zshrc.bak.*' | wc -l | tr -d ' ')" == "1" ]]
[[ "$(find "$TEST_ROOT" -maxdepth 1 -name 'zshrc-target.bak.*' | wc -l | tr -d ' ')" == "0" ]]
[[ "$(grep -Fc '# >>> dotfiles codex-homes >>>' "$ZSHRC_TARGET")" == "1" ]]
[[ "$(grep -Fc '# <<< dotfiles codex-homes <<<' "$ZSHRC_TARGET")" == "1" ]]
zsh -n "$ZSHRC_TARGET"

# Re-adding preserves credentials and does not duplicate login or zsh entries.
auth_before="$(cksum "$HOMES_ROOT/work/auth.json")"
run_make codex-add-home ACCOUNT=work >/dev/null
[[ "$(cksum "$HOMES_ROOT/work/auth.json")" == "$auth_before" ]]
[[ "$(grep -c $'\t.*login$' "$CALLS")" == "1" ]]
[[ "$(grep -c $'\tlogin status$' "$CALLS")" == "2" ]]
[[ "$(grep -Fc 'codex-work() {' "$ZSHRC_TARGET")" == "1" ]]
[[ "$(grep -Fc '# >>> dotfiles codex-homes >>>' "$ZSHRC_TARGET")" == "1" ]]

# Existing config is preserved except for the credential-store key, with a unique backup.
mkdir -p "$HOMES_ROOT/personal"
printf 'model = "example"\ncli_auth_credentials_store = "keyring"\n' > "$HOMES_ROOT/personal/config.toml"
run_make codex-add-home ACCOUNT=personal >/dev/null
grep -q '^model = "example"$' "$HOMES_ROOT/personal/config.toml"
grep -q '^cli_auth_credentials_store = "file"$' "$HOMES_ROOT/personal/config.toml"
[[ "$(find "$HOMES_ROOT/personal" -maxdepth 1 -name 'config.toml.bak.*' | wc -l | tr -d ' ')" == "1" ]]
grep -Fq 'codex-work() {' "$ZSHRC_TARGET"
grep -Fq 'codex-personal() {' "$ZSHRC_TARGET"
wrapper_output="$(
  FAKE_CODEX_CALLS="$CALLS" PATH="$FAKE_BIN:$PATH" \
    zsh -c 'source "$1"; codex-personal --version' _ "$ZSHRC_TARGET"
)"
[[ "$wrapper_output" == 'run:--version' ]]

# Removing deletes only the selected home and removes only its shortcut.
CONFIRM=1 run_make codex-remove-home ACCOUNT=work >/dev/null
[[ ! -e "$HOMES_ROOT/work" ]]
[[ -d "$HOMES_ROOT/personal" ]]
! grep -Fq 'codex-work() {' "$ZSHRC_TARGET"
grep -Fq 'codex-personal() {' "$ZSHRC_TARGET"
grep -Fq "$HOMES_ROOT/work"$'\tlogout' "$CALLS"
[[ -L "$ZSHRC_LINK" ]]
zsh -n "$ZSHRC_TARGET"

if run_script add '../escape' >/dev/null 2>&1; then
  echo '[test-codex-home] traversal-like ACCOUNT unexpectedly accepted' >&2
  exit 1
fi
if run_make codex-add-home >/dev/null 2>&1; then
  echo '[test-codex-home] empty ACCOUNT unexpectedly accepted' >&2
  exit 1
fi
if run_make codex-remove-home ACCOUNT=personal >/dev/null 2>&1; then
  echo '[test-codex-home] non-interactive removal unexpectedly skipped confirmation' >&2
  exit 1
fi

echo '[test-codex-home] isolated account home lifecycle passed'
