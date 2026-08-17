#!/usr/bin/env bash
# Manage isolated, file-backed Codex homes without reading or copying tokens.

set -euo pipefail

COMMAND="${1:-}"
ACCOUNT="${2:-}"
if [ "$#" -ge 2 ]; then
  shift 2
else
  set --
fi

usage() {
  cat <<'EOF'
Usage:
  codex-home.sh add ACCOUNT
  codex-home.sh remove ACCOUNT

Homes are stored under ~/.codex-accounts by default. Set CODEX_HOMES_ROOT to
override that parent directory, primarily for isolated tests.
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
  [ "${EUID:-$(id -u)}" -ne 0 ] || die "do not manage Codex homes as root"
  [[ "$-" != *x* ]] || die "disable shell xtrace before handling credentials"
}

validate_account() {
  [ -n "$ACCOUNT" ] || die "ACCOUNT is required (example: ACCOUNT=work)"
  [ "${#ACCOUNT}" -le 64 ] || die "ACCOUNT must be at most 64 characters"
  [[ "$ACCOUNT" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] ||
    die "ACCOUNT must start with a letter or number and contain only letters, numbers, dot, underscore, or hyphen"
}

require_codex() {
  command -v codex >/dev/null 2>&1 || die "codex is not installed or not in PATH"
}

readonly HOMES_ROOT="${CODEX_HOMES_ROOT:-$HOME/.codex-accounts}"
readonly ZSHRC_LINK="${CODEX_ZSHRC:-$HOME/.zshrc}"
readonly MANAGED_BEGIN="# >>> dotfiles codex-homes >>>"
readonly MANAGED_END="# <<< dotfiles codex-homes <<<"

account_home() {
  printf '%s/%s\n' "$HOMES_ROOT" "$ACCOUNT"
}

ensure_private_directories() {
  local home="$1"
  umask 077
  mkdir -p "$HOMES_ROOT" "$home"
  chmod 700 "$HOMES_ROOT" "$home"
}

ensure_file_credentials_config() {
  local home="$1"
  local config="$home/config.toml"
  local temporary
  local backup
  local key_count=0

  if [ -L "$config" ]; then
    die "refusing to replace symlinked Codex config: $config"
  fi
  if [ -e "$config" ] && [ ! -f "$config" ]; then
    die "Codex config is not a regular file: $config"
  fi

  if [ -f "$config" ]; then
    key_count="$(LC_ALL=C awk '/^[[:space:]]*cli_auth_credentials_store[[:space:]]*=/ { count++ } END { print count + 0 }' "$config")"
    [ "$key_count" -le 1 ] || die "Codex config contains duplicate cli_auth_credentials_store keys: $config"
  fi

  temporary="$(mktemp "$home/config.toml.tmp.XXXXXX")"
  trap 'rm -f "${temporary:-}"' EXIT
  if [ ! -f "$config" ]; then
    printf 'cli_auth_credentials_store = "file"\n' > "$temporary"
  elif [ "$key_count" -eq 1 ]; then
    LC_ALL=C awk '
      /^[[:space:]]*cli_auth_credentials_store[[:space:]]*=/ {
        print "cli_auth_credentials_store = \"file\""
        next
      }
      { print }
    ' "$config" > "$temporary"
  else
    LC_ALL=C awk '{ print } END { if (NR > 0) print ""; print "cli_auth_credentials_store = \"file\"" }' \
      "$config" > "$temporary"
  fi
  chmod 600 "$temporary"

  if [ -f "$config" ] && cmp -s "$config" "$temporary"; then
    rm -f "$temporary"
    temporary=""
    chmod 600 "$config"
    trap - EXIT
    return
  fi

  if [ -f "$config" ]; then
    backup="$(mktemp "$home/config.toml.bak.$(date +%Y%m%d%H%M%S).XXXXXX")"
    cp -p "$config" "$backup"
    note "backed up previous config: $backup"
  fi
  mv "$temporary" "$config"
  temporary=""
  trap - EXIT
  note "configured file-backed credentials: $config"
}

validate_auth_file() {
  local auth_file="$1"
  [ ! -L "$auth_file" ] || die "refusing symlinked Codex credentials: $auth_file"
  [ -f "$auth_file" ] || die "Codex login succeeded but auth.json was not created: $auth_file"
  chmod 600 "$auth_file"
}

require_existing_home() {
  local home="$1"
  [ -d "$home" ] || die "unknown Codex account '$ACCOUNT'; run: make codex-add-home ACCOUNT=$ACCOUNT"
  [ ! -L "$home" ] || die "refusing symlinked Codex home: $home"
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
  ' "$source" > "$output" || die "malformed Codex managed block in $source"
}

append_zsh_wrappers() {
  local output="$1"
  local excluded_account="${2:-}"
  local home
  local name
  local quoted_home
  local wrote_header=0

  [ -d "$HOMES_ROOT" ] || return
  while IFS= read -r home; do
    name="$(basename "$home")"
    [ "$name" != "$excluded_account" ] || continue
    [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || continue
    if [ "$wrote_header" -eq 0 ]; then
      printf '\n%s\n' "$MANAGED_BEGIN" >> "$output"
      printf '# Generated by make codex-add-home/codex-remove-home.\n' >> "$output"
      wrote_header=1
    fi
    if [[ "$home" == "$HOME/.codex-accounts/"* ]]; then
      quoted_home="~/.codex-accounts/$name"
    else
      printf -v quoted_home '%q' "$home"
    fi
    printf 'codex-%s() {\n' "$name" >> "$output"
    printf '  CODEX_HOME=%s command codex "$@"\n' "$quoted_home" >> "$output"
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
  if [[ "$(uname -s)" == "Darwin" ]]; then
    mode="$(stat -f '%Lp' "$zshrc")"
  else
    mode="$(stat -c '%a' "$zshrc")"
  fi
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
  note "updated Codex shortcuts in $ZSHRC_LINK"
  note "backup: $backup"
}

codex_login() {
  local home="$1"
  require_codex
  CODEX_HOME="$home" codex -c 'cli_auth_credentials_store="file"' login
  validate_auth_file "$home/auth.json"
  CODEX_HOME="$home" codex login status
}

add_home() {
  local home
  local auth_file
  validate_account
  home="$(account_home)"
  auth_file="$home/auth.json"
  ensure_private_directories "$home"
  ensure_file_credentials_config "$home"

  if [ -e "$auth_file" ]; then
    validate_auth_file "$auth_file"
    note "preserving existing credentials: $auth_file"
    require_codex
    if ! CODEX_HOME="$home" codex login status; then
      note "credentials need attention; run: codex-$ACCOUNT login"
    fi
    sync_zsh_wrappers
    note "shortcut ready: codex-$ACCOUNT"
    return
  fi

  note "starting Codex login for account '$ACCOUNT'"
  codex_login "$home"
  sync_zsh_wrappers
  note "Codex home ready: $home"
  note "shortcut ready after opening a new shell: codex-$ACCOUNT"
}

remove_home() {
  local home
  local answer=""
  local resolved_parent
  local resolved_root
  validate_account
  home="$(account_home)"
  require_existing_home "$home"
  require_codex
  resolved_parent="$(cd -P "$(dirname "$home")" && pwd)"
  resolved_root="$(cd -P "$HOMES_ROOT" && pwd)"
  [ "$resolved_parent" = "$resolved_root" ] || die "refusing to remove home outside $HOMES_ROOT"

  if [ "${CONFIRM:-}" != "1" ]; then
    [ -t 0 ] || die "removal requires an interactive confirmation or CONFIRM=1"
    printf 'Permanently log out and remove Codex home %s? [y/N] ' "$home" >&2
    IFS= read -r answer
    [[ "$answer" =~ ^[Yy]$ ]] || die "removal cancelled"
  fi

  CODEX_HOME="$home" codex logout
  sync_zsh_wrappers "$ACCOUNT"
  rm -rf -- "$home"
  note "removed Codex home permanently: $home"
  note "removed shortcut: codex-$ACCOUNT"
}

require_environment
case "$COMMAND" in
  add) add_home ;;
  remove) remove_home ;;
  -h|--help|help) usage ;;
  *) usage >&2; exit 2 ;;
esac
