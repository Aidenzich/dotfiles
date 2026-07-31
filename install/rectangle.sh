#!/usr/bin/env bash
# Install Rectangle when needed and apply the shortcuts in rectangle/config.json.

set -euo pipefail

DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_PATH="$DOTFILES_ROOT/rectangle/config.json"
PREFERENCE_DOMAIN="com.knollsoft.Rectangle"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "[rectangle] Rectangle is only available on macOS" >&2
  exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "[rectangle] Homebrew is required; run 'make init-mac' first" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "[rectangle] jq is required; run 'make init-mac' first" >&2
  exit 1
fi

if ! jq -e '
  (.preferences.allowAnyShortcut | type == "boolean") and
  (.preferences.alternateDefaultShortcuts | type == "boolean") and
  (.shortcuts | type == "object" and length > 0) and
  ([.shortcuts[] |
    (.keyCode | type == "number") and
    (.modifierFlags | type == "number")
  ] | all)
' "$CONFIG_PATH" >/dev/null; then
  echo "[rectangle] invalid config: $CONFIG_PATH" >&2
  exit 1
fi

if ! brew list --cask rectangle >/dev/null 2>&1; then
  echo "[rectangle] installing Rectangle"
  brew install --cask rectangle
fi

was_running=0
if pgrep -x Rectangle >/dev/null 2>&1; then
  was_running=1
  echo "[rectangle] stopping Rectangle before updating preferences"
  killall Rectangle

  for _ in {1..50}; do
    if ! pgrep -x Rectangle >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done

  if pgrep -x Rectangle >/dev/null 2>&1; then
    echo "[rectangle] could not stop Rectangle cleanly" >&2
    exit 1
  fi
fi

echo "[rectangle] applying managed preferences and shortcuts"
defaults write "$PREFERENCE_DOMAIN" allowAnyShortcut \
  -bool "$(jq -r '.preferences.allowAnyShortcut' "$CONFIG_PATH")"
defaults write "$PREFERENCE_DOMAIN" alternateDefaultShortcuts \
  -bool "$(jq -r '.preferences.alternateDefaultShortcuts' "$CONFIG_PATH")"

while IFS=$'\t' read -r action key_code modifier_flags; do
  defaults write "$PREFERENCE_DOMAIN" "$action" \
    -dict keyCode -int "$key_code" modifierFlags -int "$modifier_flags"
done < <(
  jq -r '
    .shortcuts
    | to_entries[]
    | [.key, (.value.keyCode | tostring), (.value.modifierFlags | tostring)]
    | @tsv
  ' "$CONFIG_PATH"
)

actual_config="$(
  defaults export "$PREFERENCE_DOMAIN" - \
    | plutil -convert json -o - -
)"

if ! jq -e --argjson expected "$(jq -c . "$CONFIG_PATH")" '
  .allowAnyShortcut == $expected.preferences.allowAnyShortcut and
  .alternateDefaultShortcuts == $expected.preferences.alternateDefaultShortcuts and
  ([($expected.shortcuts | to_entries[]) as $item |
    .[$item.key].keyCode == $item.value.keyCode and
    .[$item.key].modifierFlags == $item.value.modifierFlags
  ] | all)
' <<<"$actual_config" >/dev/null; then
  echo "[rectangle] preference read-back did not match $CONFIG_PATH" >&2
  exit 1
fi

echo "[rectangle] configuration verified"

if open -a Rectangle; then
  if (( was_running == 1 )); then
    echo "[rectangle] restarted Rectangle"
  else
    echo "[rectangle] launched Rectangle; grant macOS Accessibility access if prompted"
  fi
else
  echo "[rectangle] settings saved; launch Rectangle from Applications when a GUI session is available"
fi
