#!/bin/zsh

# --- 1. P10K Instant Prompt (必須在最前面) ---
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# --- 2. 基礎設定 ---
export ZSH=$HOME/.oh-my-zsh

# 自動安裝 Oh My Zsh (若無)
if [ ! -d "$ZSH" ]; then
    echo "未偵測到 Oh My Zsh，正在自動下載..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# 自動安裝 Powerlevel10k 主題 (若無)
if [ ! -d "${ZSH_CUSTOM:-$ZSH/custom}/themes/powerlevel10k" ]; then
    echo "未偵測到 Powerlevel10k 主題，正在自動下載..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$ZSH/custom}/themes/powerlevel10k
fi

ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git) # 如有安裝 brew 插件可加入 brew
source $ZSH/oh-my-zsh.sh

# --- 3. PATH 路徑管理與 Homebrew (自動去重) ---
# 使用 Zsh 特有的 path 陣列，易讀且自動處理重複路徑
typeset -U path PATH

# 動態設定 Homebrew 路徑 (支援 M系列 Mac、Intel Mac 與 Linux)
if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
elif [[ -f /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# 其他自訂 PATH (無效路徑會自動被略過)
path=(
    ${HOMEBREW_PREFIX:-/opt/homebrew}/opt/mysql-client/bin
    /Applications/Docker.app/Contents/Resources/bin
    $HOME/flutter/bin
    "$HOME/.pyenv/shims" # 建議直接寫絕對路徑避免啟動時執行 $(pyenv root) 造成延遲
    $HOME/bin
    $HOME/.local/bin
    /Applications/Antigravity.app/Contents/Resources/app/bin
    $path
)
export PATH
# --- 4. 語言環境 ---
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

# --- 5. 工具設定 ---

# VSCode Shell Integration
[[ "$TERM_PROGRAM" == "vscode" ]] && . "$(code --locate-shell-integration-path zsh)"

# Conda Initialization (保持原樣，因為它包含複雜的 hook)
__conda_setup="$('$HOME/miniconda3/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
        . "$HOME/miniconda3/etc/profile.d/conda.sh"
    else
        export PATH="$HOME/miniconda3/bin:$PATH"
    fi
fi
unset __conda_setup

# --- 6. NVM Lazy Load (大幅提升啟動速度) ---
export NVM_DIR="$HOME/.nvm"
_lazy_load_nvm() {
    # 移除佔位函式
    unset -f nvm node npm npx yarn
    
    # 載入 NVM
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
    
    # 執行使用者原本輸入的指令
    "$@"
}
# 定義觸發指令
nvm()  { _lazy_load_nvm nvm  "$@"; }
node() { _lazy_load_nvm node "$@"; }
npm()  { _lazy_load_nvm npm  "$@"; }
npx()  { _lazy_load_nvm npx  "$@"; }
yarn() { _lazy_load_nvm yarn "$@"; }

# --- 7. P10K 設定 (放在最後以覆蓋前面的設定) ---
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Alias
alias ag="antigravity"

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# --- Skills 同步指令 ---
# 用法：直接在終端機輸入 sync-skills 即可手動觸發
sync-skills() {
  local SOURCE_DIR="$HOME/.agents/skills"
  local TARGET_DIRS=(
    "$HOME/.claude/skills"
    "$HOME/.gemini/antigravity/skills"
  )

  # 1. 確保目標目錄存在
  for target in "${TARGET_DIRS[@]}"; do
    mkdir -p "$target"
  done

  # 2. 清理無效連結 (處理減少/刪除的情況)
  # 尋找目標目錄下所有的軟連結，若指向的路徑已不存在則刪除
  for target in "${TARGET_DIRS[@]}"; do
    if [[ -d "$target" ]]; then
      find -L "$target" -type l -delete
    fi
  done

  # 3. 執行同步邏輯
  for skill_dir in "$SOURCE_DIR"/*/; do
    local skill_name=$(basename "$skill_dir")

    # A. 標準結構：SKILL.md 在根目錄
    if [[ -f "${skill_dir}SKILL.md" ]]; then
      for target in "${TARGET_DIRS[@]}"; do
        [[ ! -L "$target/$skill_name" ]] && ln -s "$skill_dir" "$target/$skill_name"
      done
    fi

    # B. 特殊嵌套結構：.claude/skills
    if [[ -d "${skill_dir}.claude/skills" ]]; then
      for nested in "${skill_dir}.claude/skills/"/*/; do
        local nested_name=$(basename "$nested")
        for target in "${TARGET_DIRS[@]}"; do
          [[ ! -L "$target/$nested_name" ]] && ln -s "$nested" "$target/$nested_name"
        done
      done
    fi
  done

  echo "✅ Skills 同步完成。目標路徑：${#TARGET_DIRS[@]} 個，已清理無效連結。"
}


# Use local opencode dev version
opencode() {
  local OPENCODE_DIR="$HOME/Projects/lab/opencode"
  if [[ ! -d "$OPENCODE_DIR" ]]; then
    echo "⚠️ opencode 自訂專案目錄不存在，請檢查：$OPENCODE_DIR"
    return 1
  fi

  # 1. 先捕捉使用者當前的原始目錄
  local USER_CWD="$PWD"
  
  # 2. 在 Subshell 中執行，使用剛才捕捉的變數
  (cd "$OPENCODE_DIR" && \
   PWD="$USER_CWD" bun run --cwd packages/opencode --conditions=browser src/index.ts "$USER_CWD" "$@")
}