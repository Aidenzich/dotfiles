#!/usr/bin/env bash
# Manage isolated Claude Code homes with private, process-scoped OAuth tokens.

set -euo pipefail

COMMAND="${1:-}"
ACCOUNT="${2:-}"

usage() {
  cat <<'EOF'
Usage:
  claude-home.sh add ACCOUNT
  claude-home.sh remove ACCOUNT

Homes are stored under ~/.claude-accounts by default. Set CLAUDE_HOMES_ROOT to
override that parent directory, primarily for isolated tests.

If a home has no token, add runs `claude setup-token` and then securely prompts
for the generated raw token. Set TOKEN_FILE to import one without a prompt.
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

note() {
  printf '%s\n' "$*"
}

require_environment() {
  [ -n "${HOME:-}" ] || die "HOME is not set"
  [ "${EUID:-$(id -u)}" -ne 0 ] || die "do not manage Claude homes as root"
  [[ "$-" != *x* ]] || die "disable shell xtrace before handling credentials"
}

validate_account() {
  [ -n "$ACCOUNT" ] || die "ACCOUNT is required (example: ACCOUNT=work)"
  [ "${#ACCOUNT}" -le 64 ] || die "ACCOUNT must be at most 64 characters"
  [[ "$ACCOUNT" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] ||
    die "ACCOUNT must start with a letter or number and contain only letters, numbers, dot, underscore, or hyphen"
}

require_claude() {
  command -v claude >/dev/null 2>&1 || die "claude is not installed or not in PATH"
}

readonly HOMES_ROOT="${CLAUDE_HOMES_ROOT:-$HOME/.claude-accounts}"
readonly ZSHRC_LINK="${CLAUDE_ZSHRC:-$HOME/.zshrc}"
readonly SHARED_SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
readonly MANAGED_BEGIN="# >>> dotfiles claude-homes >>>"
readonly MANAGED_END="# <<< dotfiles claude-homes <<<"
readonly TOKEN_SOURCE="${TOKEN_FILE:-}"

account_home() {
  printf '%s/%s\n' "$HOMES_ROOT" "$ACCOUNT"
}

ensure_private_directories() {
  local home="$1"
  umask 077
  mkdir -p "$HOMES_ROOT" "$home"
  chmod 700 "$HOMES_ROOT" "$home"
}

link_shared_skills() {
  local home="$1"
  local account_skills="$home/skills"
  mkdir -p "$SHARED_SKILLS_DIR"
  if [ ! -e "$account_skills" ] && [ ! -L "$account_skills" ]; then
    ln -s "$SHARED_SKILLS_DIR" "$account_skills"
  fi
  [ -L "$account_skills" ] || die "Claude account skills path is not a symlink: $account_skills"
  [ "$(resolve_symlink_target "$account_skills")" = "$(resolve_symlink_target "$SHARED_SKILLS_DIR")" ] ||
    die "Claude account skills link does not target $SHARED_SKILLS_DIR: $account_skills"
}

token_mode() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    stat -f '%Lp' "$1"
  else
    stat -c '%a' "$1"
  fi
}

validate_raw_token_file() {
  local path="$1"
  [ ! -L "$path" ] || die "refusing symlinked Claude token: $path"
  [ -f "$path" ] || die "token file is not a regular file: $path"
  [ -r "$path" ] || die "token file is not readable: $path"
  [ -s "$path" ] || die "token file is empty: $path"

  if ! LC_ALL=C awk '
    NR > 1 { exit 1 }
    NR == 1 && ($0 == "" || $0 ~ /[[:space:]]/) { exit 1 }
    END { if (NR != 1) exit 1 }
  ' "$path"; then
    die "token file must contain exactly one non-empty line without whitespace"
  fi
  if LC_ALL=C grep -q '^CLAUDE_CODE_OAUTH_TOKEN=' "$path"; then
    die "token file must contain only the raw token, not KEY=value"
  fi
}

validate_token_permissions() {
  local path="$1"
  local mode
  mode="$(token_mode "$path")"
  if (( (8#$mode & 077) != 0 )); then
    die "token file permissions are too broad ($mode): $path"
  fi
}

run_setup_token() {
  local home="$1"
  (
    unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN
    unset CLAUDE_CODE_OAUTH_TOKEN CLAUDE_CODE_OAUTH_REFRESH_TOKEN CLAUDE_CODE_OAUTH_SCOPES
    unset CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY
    export CLAUDE_CONFIG_DIR="$home"
    command claude setup-token
  )
}

install_account_token() {
  local home="$1"
  local destination="$home/oauth-token"
  local source=""
  local temporary=""
  local prompted_token=""

  if [ -L "$destination" ]; then
    die "refusing symlinked Claude token: $destination"
  fi

  if [ -n "$TOKEN_SOURCE" ]; then
    source="$(cd "$(dirname "$TOKEN_SOURCE")" && pwd)/$(basename "$TOKEN_SOURCE")"
    validate_raw_token_file "$source"
    if [ "$source" != "$destination" ]; then
      temporary="$(mktemp "${destination}.tmp.XXXXXX")"
      trap 'rm -f "${temporary:-}"; unset prompted_token' EXIT
      cp "$source" "$temporary"
      chmod 600 "$temporary"
      mv "$temporary" "$destination"
      temporary=""
    fi
  elif [ -s "$destination" ]; then
    note "reusing installed token: $destination"
  else
    [ -t 0 ] || die "no token available; pass TOKEN_FILE or run interactively"
    note "Claude will now create a one-year, inference-only token for account '$ACCOUNT'."
    note "Copy the token it prints; it will not be saved by Claude Code."
    run_setup_token "$home"
    printf 'Paste setup-token for %s: ' "$ACCOUNT" >&2
    IFS= read -r -s prompted_token
    printf '\n' >&2
    [ -n "$prompted_token" ] || die "token cannot be empty"
    [[ "$prompted_token" != *[[:space:]]* ]] || die "token cannot contain whitespace"

    temporary="$(mktemp "${destination}.tmp.XXXXXX")"
    trap 'rm -f "${temporary:-}"; unset prompted_token' EXIT
    printf '%s\n' "$prompted_token" > "$temporary"
    unset prompted_token
    chmod 600 "$temporary"
    mv "$temporary" "$destination"
    temporary=""
  fi

  chmod 600 "$destination"
  validate_raw_token_file "$destination"
  validate_token_permissions "$destination"
  trap - EXIT
  note "installed account token with mode 0600: $destination"
}

run_with_account_token() {
  local home="$1"
  shift
  local token_file="$home/oauth-token"
  local account_token=""
  validate_raw_token_file "$token_file"
  validate_token_permissions "$token_file"
  IFS= read -r account_token < "$token_file"
  (
    unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN
    unset CLAUDE_CODE_OAUTH_REFRESH_TOKEN CLAUDE_CODE_OAUTH_SCOPES
    unset CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY
    export CLAUDE_CONFIG_DIR="$home"
    export CLAUDE_CODE_OAUTH_TOKEN="$account_token"
    export CLAUDE_CODE_SUBPROCESS_ENV_SCRUB="${CLAUDE_CODE_SUBPROCESS_ENV_SCRUB:-1}"
    command claude "$@"
  )
  unset account_token
}

verify_account_token() {
  local home="$1"
  local auth_status=""
  auth_status="$(run_with_account_token "$home" auth status --json)" ||
    die "Claude rejected the setup-token for account '$ACCOUNT'"
  if ! printf '%s\n' "$auth_status" | LC_ALL=C grep -Eq '"authMethod"[[:space:]]*:[[:space:]]*"oauth_token"'; then
    die "Claude did not select the setup-token for account '$ACCOUNT'"
  fi
}

complete_account_onboarding() {
  local home="$1"
  local state_file="$home/.claude.json"
  local temporary=""
  local backup=""
  command -v jq >/dev/null 2>&1 || die "jq is required to initialize Claude account state"
  [ ! -L "$state_file" ] || die "refusing symlinked Claude state: $state_file"
  if [ -e "$state_file" ] && [ ! -f "$state_file" ]; then
    die "Claude state is not a regular file: $state_file"
  fi

  temporary="$(mktemp "${state_file}.tmp.XXXXXX")"
  trap 'rm -f "${temporary:-}"' EXIT
  if [ -f "$state_file" ]; then
    jq 'if type == "object" then .hasCompletedOnboarding = true else error("Claude state must be a JSON object") end' \
      "$state_file" > "$temporary" || die "Claude state is not valid JSON: $state_file"
  else
    printf '{"hasCompletedOnboarding":true}\n' > "$temporary"
  fi
  chmod 600 "$temporary"

  if [ -f "$state_file" ] && cmp -s "$state_file" "$temporary"; then
    rm -f "$temporary"
    temporary=""
    chmod 600 "$state_file"
    trap - EXIT
    return
  fi
  if [ -f "$state_file" ]; then
    backup="$(mktemp "${state_file}.bak.$(date +%Y%m%d%H%M%S).XXXXXX")"
    cp -p "$state_file" "$backup"
    chmod 600 "$backup"
    note "backed up previous Claude state: $backup"
  fi
  mv "$temporary" "$state_file"
  temporary=""
  trap - EXIT
  note "completed local onboarding state: $state_file"
}

require_existing_home() {
  local home="$1"
  [ -d "$home" ] || die "unknown Claude account '$ACCOUNT'; run: make claude-add-home ACCOUNT=$ACCOUNT"
  [ ! -L "$home" ] || die "refusing symlinked Claude home: $home"
}

resolve_symlink_target() {
  local path="$1"
  local link=""
  local directory=""
  local hops=0

  while [ -L "$path" ]; do
    hops=$((hops + 1))
    [ "$hops" -le 20 ] || die "too many symlink levels: $1"
    link="$(readlink "$path")"
    if [[ "$link" = /* ]]; then
      path="$link"
    else
      directory="$(cd -P "$(dirname "$path")" && pwd)"
      path="$directory/$link"
    fi
  done
  directory="$(cd -P "$(dirname "$path")" && pwd)"
  printf '%s/%s\n' "$directory" "$(basename "$path")"
}

render_zsh_without_managed_block() {
  local source="$1"
  local output="$2"
  awk -v begin="$MANAGED_BEGIN" -v end="$MANAGED_END" '
    $0 == begin {
      if (inside) exit 20
      inside = 1
      next
    }
    $0 == end {
      if (!inside) exit 21
      inside = 0
      next
    }
    !inside { lines[++count] = $0 }
    END {
      if (inside) exit 22
      while (count > 0 && lines[count] == "") count--
      for (i = 1; i <= count; i++) print lines[i]
    }
  ' "$source" > "$output" || die "malformed Claude managed block in $source"
}

append_zsh_wrappers() {
  local output="$1"
  local excluded_account="${2:-}"
  local home
  local name
  local quoted_home
  local quoted_token
  local wrote_header=0

  [ -d "$HOMES_ROOT" ] || return
  while IFS= read -r home; do
    name="$(basename "$home")"
    [ "$name" != "$excluded_account" ] || continue
    [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || continue
    if [ "$wrote_header" -eq 0 ]; then
      printf '\n%s\n' "$MANAGED_BEGIN" >> "$output"
      printf '# Generated by make claude-add-home/claude-remove-home.\n' >> "$output"
      wrote_header=1
    fi
    printf -v quoted_home '%q' "$home"
    printf -v quoted_token '%q' "$home/oauth-token"
    printf 'claude-%s() {\n' "$name" >> "$output"
    printf '  local claude_bin claude_token_file=%s\n' "$quoted_token" >> "$output"
    printf '  claude_bin="$(whence -p claude)"\n' >> "$output"
    printf '  if [[ -z "$claude_bin" || ! -r "$claude_token_file" ]]; then\n' >> "$output"
    printf '    echo "Claude executable or account token is unavailable for %s." >&2\n' "$name" >> "$output"
    printf '    return 1\n' >> "$output"
    printf '  fi\n' >> "$output"
    printf '  (\n' >> "$output"
    printf '    unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN\n' >> "$output"
    printf '    unset CLAUDE_CODE_OAUTH_REFRESH_TOKEN CLAUDE_CODE_OAUTH_SCOPES\n' >> "$output"
    printf '    unset CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY\n' >> "$output"
    printf '    export CLAUDE_CONFIG_DIR=%s\n' "$quoted_home" >> "$output"
    printf '    export CLAUDE_CODE_OAUTH_TOKEN="$(<"$claude_token_file")"\n' >> "$output"
    printf '    if [[ -z "$CLAUDE_CODE_OAUTH_TOKEN" ]]; then\n' >> "$output"
    printf '      echo "Claude account token is empty for %s." >&2\n' "$name" >> "$output"
    printf '      return 1\n' >> "$output"
    printf '    fi\n' >> "$output"
    printf '    export CLAUDE_CODE_SUBPROCESS_ENV_SCRUB="${CLAUDE_CODE_SUBPROCESS_ENV_SCRUB:-1}"\n' >> "$output"
    printf '    command "$claude_bin" "$@"\n' >> "$output"
    printf '  )\n' >> "$output"
    printf '}\n' >> "$output"
  done < <(find "$HOMES_ROOT" -mindepth 1 -maxdepth 1 -type d -print | LC_ALL=C sort)
  if [ "$wrote_header" -eq 1 ]; then
    printf '%s\n' "$MANAGED_END" >> "$output"
  fi
}

sync_zsh_wrappers() {
  local excluded_account="${1:-}"
  local zshrc
  local temporary
  local backup
  local mode

  if [ ! -e "$ZSHRC_LINK" ] && [ ! -L "$ZSHRC_LINK" ]; then
    umask 077
    : > "$ZSHRC_LINK"
  fi
  zshrc="$(resolve_symlink_target "$ZSHRC_LINK")"
  [ -f "$zshrc" ] || die "zshrc is not a regular file: $zshrc"

  temporary="$(mktemp "${zshrc}.tmp.XXXXXX")"
  trap 'rm -f "${temporary:-}"' EXIT
  render_zsh_without_managed_block "$zshrc" "$temporary"
  append_zsh_wrappers "$temporary" "$excluded_account"
  mode="$(token_mode "$zshrc")"
  chmod "$mode" "$temporary"
  command -v zsh >/dev/null 2>&1 || die "zsh is required to validate generated wrappers"
  zsh -n "$temporary" || die "generated zsh configuration failed syntax validation"

  if cmp -s "$zshrc" "$temporary"; then
    rm -f "$temporary"
    temporary=""
    trap - EXIT
    return
  fi
  backup="$(mktemp "${ZSHRC_LINK}.bak.$(date +%Y%m%d%H%M%S).XXXXXX")"
  cp -p "$zshrc" "$backup"
  mv "$temporary" "$zshrc"
  temporary=""
  trap - EXIT
  note "updated Claude shortcuts in $ZSHRC_LINK"
  note "backup: $backup"
}

add_home() {
  local home
  validate_account
  require_claude
  home="$(account_home)"
  ensure_private_directories "$home"
  link_shared_skills "$home"
  install_account_token "$home"
  verify_account_token "$home"
  complete_account_onboarding "$home"
  sync_zsh_wrappers
  note "Claude home ready: $home"
  note "shortcut ready after opening a new shell: claude-$ACCOUNT"
}

remove_home() {
  local home
  local answer=""
  local resolved_parent
  local resolved_root
  validate_account
  home="$(account_home)"
  require_existing_home "$home"
  resolved_parent="$(cd -P "$(dirname "$home")" && pwd)"
  resolved_root="$(cd -P "$HOMES_ROOT" && pwd)"
  [ "$resolved_parent" = "$resolved_root" ] || die "refusing to remove home outside $HOMES_ROOT"

  if [ "${CONFIRM:-}" != "1" ]; then
    [ -t 0 ] || die "removal requires an interactive confirmation or CONFIRM=1"
    printf 'Permanently remove local Claude home %s? This does not revoke its server token. [y/N] ' "$home" >&2
    IFS= read -r answer
    [[ "$answer" =~ ^[Yy]$ ]] || die "removal cancelled"
  fi

  sync_zsh_wrappers "$ACCOUNT"
  rm -rf -- "$home"
  note "removed Claude home permanently: $home"
  note "the setup-token was removed locally but was not revoked server-side"
  note "removed shortcut: claude-$ACCOUNT"
}

require_environment
case "$COMMAND" in
  add) add_home ;;
  remove) remove_home ;;
  -h|--help|help) usage ;;
  *) usage >&2; exit 2 ;;
esac
