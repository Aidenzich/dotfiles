#!/usr/bin/env bash
# Print one of: mac | linux | wsl | windows | unknown
# WSL is reported separately so callers can decide whether to treat it as
# linux (most cases) or as a special hybrid (e.g. clipboard integration).

case "$(uname -s 2>/dev/null)" in
  Darwin)
    echo mac
    ;;
  Linux)
    if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
      echo wsl
    else
      echo linux
    fi
    ;;
  MINGW*|MSYS*|CYGWIN*)
    echo windows
    ;;
  *)
    echo unknown
    ;;
esac
