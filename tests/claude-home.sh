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
WORK_TOKEN="$TEST_ROOT/work.token"
PERSONAL_TOKEN="$TEST_ROOT/personal.token"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

mkdir -p "$FAKE_BIN" "$TEST_HOME"
printf 'token-work\n' > "$WORK_TOKEN"
printf 'token-personal\n' > "$PERSONAL_TOKEN"
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

if [ "$*" = 'setup-token' ]; then
  [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]
  printf 'generated-token-placeholder\n'
  exit 0
fi

expected_token="token-$(basename "$CLAUDE_CONFIG_DIR")"
[ "${CLAUDE_CODE_OAUTH_TOKEN:-}" = "$expected_token" ]
[ "${CLAUDE_CODE_SUBPROCESS_ENV_SCRUB:-}" = "1" ]
[ -z "${ANTHROPIC_API_KEY:-}" ]
[ -z "${ANTHROPIC_AUTH_TOKEN:-}" ]
[ -z "${CLAUDE_CODE_USE_BEDROCK:-}" ]
[ -z "${CLAUDE_CODE_USE_VERTEX:-}" ]
[ -z "${CLAUDE_CODE_USE_FOUNDRY:-}" ]

case "$*" in
  'auth status --json')
    if [ "$(basename "$CLAUDE_CONFIG_DIR")" = 'wrong-method' ]; then
      printf '{"loggedIn":true,"authMethod":"claude.ai"}\n'
    else
      printf '{"loggedIn":true,"authMethod":"oauth_token"}\n'
    fi
    ;;
  'auth login'|'auth logout') exit 70 ;;
  *) printf 'run:%s\n' "$*" ;;
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
  if [[ "$(uname -s)" == "Darwin" ]]; then
    stat -f '%Lp' "$1"
  else
    stat -c '%a' "$1"
  fi
}

mkdir -p "$HOMES_ROOT/work"
printf '{"preservedSetting":"keep-me"}\n' > "$HOMES_ROOT/work/.claude.json"
add_output="$(run_make claude-add-home ACCOUNT=work TOKEN_FILE="$WORK_TOKEN")"
[[ "$add_output" != *'token-work'* ]]
[[ -d "$HOMES_ROOT/work" ]]
[[ -f "$HOMES_ROOT/work/oauth-token" ]]
[[ "$(mode "$HOMES_ROOT")" == "700" ]]
[[ "$(mode "$HOMES_ROOT/work")" == "700" ]]
[[ "$(mode "$HOMES_ROOT/work/oauth-token")" == "600" ]]
[[ "$(mode "$HOMES_ROOT/work/.claude.json")" == "600" ]]
cmp -s "$HOMES_ROOT/work/oauth-token" "$WORK_TOKEN"
jq -e '.hasCompletedOnboarding == true and .preservedSetting == "keep-me"' "$HOMES_ROOT/work/.claude.json" >/dev/null
[[ "$(find "$HOMES_ROOT/work" -maxdepth 1 -name '.claude.json.bak.*' | wc -l | tr -d ' ')" == "1" ]]
[[ "$(grep -c $'\tauth status --json$' "$CALLS")" == "1" ]]
[[ "$(grep -c $'\tsetup-token$' "$CALLS" || true)" == "0" ]]

# The managed shortcut is written through the symlink and preserves other blocks.
[[ -L "$ZSHRC_LINK" ]]
grep -Fq 'claude-work() {' "$ZSHRC_TARGET"
grep -Fq "export CLAUDE_CONFIG_DIR=$HOMES_ROOT/work" "$ZSHRC_TARGET"
grep -Fq "claude_token_file=$HOMES_ROOT/work/oauth-token" "$ZSHRC_TARGET"
grep -Fq 'export CLAUDE_CODE_OAUTH_TOKEN="$(<"$claude_token_file")"' "$ZSHRC_TARGET"
grep -Fq 'export CLAUDE_CODE_SUBPROCESS_ENV_SCRUB="${CLAUDE_CODE_SUBPROCESS_ENV_SCRUB:-1}"' "$ZSHRC_TARGET"
grep -Fq '# >>> dotfiles codex-homes >>>' "$ZSHRC_TARGET"
grep -Fq 'codex-existing() {' "$ZSHRC_TARGET"
[[ "$(find "$TEST_HOME" -maxdepth 1 -name '.zshrc.bak.*' | wc -l | tr -d ' ')" == "1" ]]
[[ "$(find "$TEST_ROOT" -maxdepth 1 -name 'zshrc-target.bak.*' | wc -l | tr -d ' ')" == "0" ]]
[[ "$(grep -Fc '# >>> dotfiles claude-homes >>>' "$ZSHRC_TARGET")" == "1" ]]
[[ "$(grep -Fc '# <<< dotfiles claude-homes <<<' "$ZSHRC_TARGET")" == "1" ]]
zsh -n "$ZSHRC_TARGET"

# Re-adding reuses the private token without invoking setup-token or duplicating zsh entries.
token_before="$(cksum "$HOMES_ROOT/work/oauth-token")"
run_make claude-add-home ACCOUNT=work >/dev/null
[[ "$(cksum "$HOMES_ROOT/work/oauth-token")" == "$token_before" ]]
[[ "$(grep -c $'\tauth status --json$' "$CALLS")" == "2" ]]
[[ "$(grep -c $'\tsetup-token$' "$CALLS" || true)" == "0" ]]
[[ "$(find "$HOMES_ROOT/work" -maxdepth 1 -name '.claude.json.bak.*' | wc -l | tr -d ' ')" == "1" ]]
[[ "$(grep -Fc 'claude-work() {' "$ZSHRC_TARGET")" == "1" ]]
[[ "$(grep -Fc '# >>> dotfiles claude-homes >>>' "$ZSHRC_TARGET")" == "1" ]]

run_make claude-add-home ACCOUNT=personal TOKEN_FILE="$PERSONAL_TOKEN" >/dev/null
grep -Fq 'claude-work() {' "$ZSHRC_TARGET"
grep -Fq 'claude-personal() {' "$ZSHRC_TARGET"
wrapper_output="$(
  ANTHROPIC_API_KEY=wrong-provider \
  CLAUDE_CODE_USE_BEDROCK=1 \
  FAKE_CLAUDE_CALLS="$CALLS" \
  PATH="$FAKE_BIN:$PATH" \
    zsh -c 'source "$1"; claude-personal --version' _ "$ZSHRC_TARGET"
)"
[[ "$wrapper_output" == 'run:--version' ]]

# A damaged token fails closed instead of falling back to the shared Keychain.
personal_token_backup="$(mktemp "$HOMES_ROOT/personal/oauth-token.test.XXXXXX")"
cp "$HOMES_ROOT/personal/oauth-token" "$personal_token_backup"
: > "$HOMES_ROOT/personal/oauth-token"
calls_before="$(wc -l < "$CALLS" | tr -d ' ')"
if FAKE_CLAUDE_CALLS="$CALLS" PATH="$FAKE_BIN:$PATH" \
  zsh -c 'source "$1"; claude-personal --version' _ "$ZSHRC_TARGET" >/dev/null 2>&1; then
  echo '[test-claude-home] empty installed token unexpectedly reached Claude' >&2
  exit 1
fi
[[ "$(wc -l < "$CALLS" | tr -d ' ')" == "$calls_before" ]]
mv "$personal_token_backup" "$HOMES_ROOT/personal/oauth-token"

# Removing deletes only local state; it never calls logout against the shared Keychain.
CONFIRM=1 run_make claude-remove-home ACCOUNT=work >/dev/null
[[ ! -e "$HOMES_ROOT/work" ]]
[[ -d "$HOMES_ROOT/personal" ]]
! grep -Fq 'claude-work() {' "$ZSHRC_TARGET"
grep -Fq 'claude-personal() {' "$ZSHRC_TARGET"
[[ "$(grep -c $'\tauth logout$' "$CALLS" || true)" == "0" ]]
grep -Fq 'codex-existing() {' "$ZSHRC_TARGET"
[[ -L "$ZSHRC_LINK" ]]
zsh -n "$ZSHRC_TARGET"

printf 'first\nsecond\n' > "$TEST_ROOT/invalid.token"
if run_make claude-add-home ACCOUNT=invalid TOKEN_FILE="$TEST_ROOT/invalid.token" >/dev/null 2>&1; then
  echo '[test-claude-home] multi-line token unexpectedly accepted' >&2
  exit 1
fi
printf 'token-wrong-method\n' > "$TEST_ROOT/wrong-method.token"
if run_make claude-add-home ACCOUNT=wrong-method TOKEN_FILE="$TEST_ROOT/wrong-method.token" >/dev/null 2>&1; then
  echo '[test-claude-home] non-token auth method unexpectedly accepted' >&2
  exit 1
fi
if run_script add '../escape' >/dev/null 2>&1; then
  echo '[test-claude-home] traversal-like ACCOUNT unexpectedly accepted' >&2
  exit 1
fi
if run_make claude-add-home >/dev/null 2>&1; then
  echo '[test-claude-home] empty ACCOUNT unexpectedly accepted' >&2
  exit 1
fi
if run_make claude-add-home ACCOUNT=no-token >/dev/null 2>&1; then
  echo '[test-claude-home] non-interactive add without token unexpectedly succeeded' >&2
  exit 1
fi
if run_make claude-remove-home ACCOUNT=personal >/dev/null 2>&1; then
  echo '[test-claude-home] non-interactive removal unexpectedly skipped confirmation' >&2
  exit 1
fi

echo '[test-claude-home] isolated setup-token account lifecycle passed'
