#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATTERN='/Users?/'
PATTERN+='[[:alnum:]_.-]+'

if ! printf '%s\n' '/User/example/.config/tool' '/Users/example/.config/tool' | grep -Eq "$PATTERN"; then
  echo '[test-no-absolute-macos-home] detector did not catch the fixture' >&2
  exit 1
fi

matches="$(git -C "$ROOT" grep -nE "$PATTERN" -- . ':!tests/no-absolute-macos-home.sh' || true)"
if [ -n "$matches" ]; then
  echo '[test-no-absolute-macos-home] tracked files contain absolute macOS home paths:' >&2
  printf '%s\n' "$matches" >&2
  exit 1
fi

echo '[test-no-absolute-macos-home] no absolute macOS home paths found'
