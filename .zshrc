#!/bin/zsh

# Enable Powerlevel10k instant prompt. Keep this near the top.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

typeset -U path PATH

_add_path_if_dir() {
  [[ -d "$1" ]] && path=("$1" $path)
}

_set_utf8_locale() {
  command -v locale >/dev/null 2>&1 || return 0

  local available locale_name
  available="$(locale -a 2>/dev/null)"
  for locale_name in en_US.UTF-8 en_US.utf8 C.UTF-8 C.utf8; do
    if print -r -- "$available" | grep -qi "^${locale_name}$"; then
      export LC_ALL="$locale_name"
      export LANG="$locale_name"
      return 0
    fi
  done
}

_set_utf8_locale

# Detect Homebrew on Apple Silicon, Intel macOS, or Linux.
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
elif [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

_add_path_if_dir "${HOMEBREW_PREFIX:-/opt/homebrew}/opt/mysql-client/bin"
_add_path_if_dir /Applications/Docker.app/Contents/Resources/bin
_add_path_if_dir "$HOME/flutter/bin"
_add_path_if_dir "$HOME/.pyenv/shims"
_add_path_if_dir "$HOME/go/bin"
_add_path_if_dir "$HOME/bin"
_add_path_if_dir "$HOME/.local/bin"
_add_path_if_dir /Applications/Antigravity.app/Contents/Resources/app/bin
_add_path_if_dir "$HOME/.antigravity-ide/antigravity-ide/bin"

# Bun.
export BUN_INSTALL="$HOME/.bun"
_add_path_if_dir "$BUN_INSTALL/bin"
[[ -s "$BUN_INSTALL/_bun" ]] && source "$BUN_INSTALL/_bun"

export PATH

# Oh My Zsh + Powerlevel10k. Missing dependencies are skipped so the shell still starts.
export ZSH="$HOME/.oh-my-zsh"

if [[ -o interactive && -z "${DOTFILES_SKIP_ZSH_BOOTSTRAP:-}" && ! -d "$ZSH" ]]; then
  if command -v curl >/dev/null 2>&1 && command -v sh >/dev/null 2>&1; then
    echo "Oh My Zsh not found; installing..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
  else
    echo "Oh My Zsh not found; install skipped because curl or sh is unavailable."
  fi
fi

if [[ -o interactive && -z "${DOTFILES_SKIP_ZSH_BOOTSTRAP:-}" && -d "$ZSH" && ! -d "${ZSH_CUSTOM:-$ZSH/custom}/themes/powerlevel10k" ]]; then
  if command -v git >/dev/null 2>&1; then
    echo "Powerlevel10k not found; installing..."
    mkdir -p "${ZSH_CUSTOM:-$ZSH/custom}/themes"
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
      "${ZSH_CUSTOM:-$ZSH/custom}/themes/powerlevel10k"
  else
    echo "Powerlevel10k not found; install skipped because git is unavailable."
  fi
fi

if [[ -r "$ZSH/oh-my-zsh.sh" ]]; then
  ZSH_THEME="powerlevel10k/powerlevel10k"
  plugins=(git)
  source "$ZSH/oh-my-zsh.sh"
fi

# VSCode shell integration. Avoid re-sourcing .zshrc when VS Code already injected it.
if [[ "$TERM_PROGRAM" == "vscode" && "$VSCODE_INJECTION" != "1" ]] && command -v code >/dev/null 2>&1; then
  _vscode_shell_integration="$(code --locate-shell-integration-path zsh 2>/dev/null)"
  [[ -r "$_vscode_shell_integration" ]] && source "$_vscode_shell_integration"
  unset _vscode_shell_integration
fi

# Conda initialization.
if [[ -x "$HOME/miniconda3/bin/conda" ]]; then
  __conda_setup="$("$HOME/miniconda3/bin/conda" shell.zsh hook 2>/dev/null)"
  if [[ $? -eq 0 ]]; then
    eval "$__conda_setup"
  elif [[ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]]; then
    source "$HOME/miniconda3/etc/profile.d/conda.sh"
  fi
  unset __conda_setup
elif [[ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]]; then
  source "$HOME/miniconda3/etc/profile.d/conda.sh"
else
  _add_path_if_dir "$HOME/miniconda3/bin"
fi

# Lazy-load NVM for faster shell startup while still falling back to PATH binaries.
export NVM_DIR="$HOME/.nvm"
_lazy_load_nvm() {
  unset -f nvm node npm npx yarn
  [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
  [[ -s "$NVM_DIR/bash_completion" ]] && source "$NVM_DIR/bash_completion"
  "$@"
}
nvm() { _lazy_load_nvm nvm "$@"; }
node() { _lazy_load_nvm node "$@"; }
npm() { _lazy_load_nvm npm "$@"; }
npx() { _lazy_load_nvm npx "$@"; }
yarn() { _lazy_load_nvm yarn "$@"; }

alias ag="agy"

sync-skills() {
  local SOURCE_DIR="$HOME/.agents/skills"
  local TARGET_DIRS=(
    "$HOME/.claude/skills"
    "$HOME/.gemini/antigravity/skills"
  )

  if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "Skills source directory not found: $SOURCE_DIR"
    return 0
  fi

  for target in "${TARGET_DIRS[@]}"; do
    mkdir -p "$target"
  done

  for target in "${TARGET_DIRS[@]}"; do
    [[ -d "$target" ]] && find -L "$target" -type l -delete
  done

  for skill_dir in "$SOURCE_DIR"/*(/N); do
    local skill_name
    skill_name="$(basename "$skill_dir")"

    if [[ -f "${skill_dir}SKILL.md" ]]; then
      for target in "${TARGET_DIRS[@]}"; do
        [[ ! -L "$target/$skill_name" ]] && ln -s "$skill_dir" "$target/$skill_name"
      done
    fi

    if [[ -d "${skill_dir}.claude/skills" ]]; then
      for nested in "${skill_dir}.claude/skills/"*(/N); do
        local nested_name
        nested_name="$(basename "$nested")"
        for target in "${TARGET_DIRS[@]}"; do
          [[ ! -L "$target/$nested_name" ]] && ln -s "$nested" "$target/$nested_name"
        done
      done
    fi
  done

  echo "Skills synced to ${#TARGET_DIRS[@]} target directories."
}

opencode() {
  local OPENCODE_DIR="$HOME/Projects/lab/opencode"
  if [[ ! -d "$OPENCODE_DIR" ]]; then
    echo "opencode project directory not found: $OPENCODE_DIR"
    return 1
  fi
  if ! command -v bun >/dev/null 2>&1; then
    echo "bun is required to run opencode."
    return 1
  fi

  local USER_CWD="$PWD"
  (
    cd "$OPENCODE_DIR" && \
    PWD="$USER_CWD" bun run --cwd packages/opencode --conditions=browser src/index.ts "$USER_CWD" "$@"
  )
}

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ -r "$HOME/.p10k.zsh" ]] && source "$HOME/.p10k.zsh"

unset -f _add_path_if_dir _set_utf8_locale
