# macOS SSH 使用 Claude Code OAuth Token SOP

## 目的

在 macOS 主機透過 SSH 執行 Claude Code 時，避免因 SSH security session 無法讀取
macOS login Keychain，而在每次連線後被要求重新登入或手動執行
`security unlock-keychain`。

本 SOP 使用 Claude Code 官方支援的長效 OAuth token，且遵循以下原則：

- token 不寫入 shell profile、Git repo、命令列參數或 shell history。
- token 檔案只允許擁有者讀寫。
- token 只注入 SSH 中執行的 Claude Code process。
- 一般本機終端仍使用 macOS Keychain。
- Claude Code 啟動的 Bash、hooks 與 MCP 子程序不繼承 token。

## 適用範圍

- 遠端主機為 macOS。
- 登入 shell 為 zsh。
- 已安裝可正常執行的 Claude Code CLI。
- 帳號方案支援 `claude setup-token`。
- 使用者了解：以檔案保存 token 的 at-rest 保護弱於 macOS Keychain。

## 背景

Claude Code 在 macOS 預設將訂閱帳號的 OAuth 憑證存入加密的 macOS Keychain。
由 GUI login session 啟動的終端通常可以讀取該憑證，但 SSH connection 擁有不同的
security session，可能看得到 Keychain item metadata，卻無法解密其中的 secret。

`security unlock-keychain` 能在目前 SSH connection 暫時恢復存取，但重新連線後可能需要
再次解鎖。若需要穩定、免互動的 SSH CLI 使用方式，可改由
`CLAUDE_CODE_OAUTH_TOKEN` 提供官方長效 OAuth token。

## 安全模型與限制

此方案不保存 macOS 登入密碼，但會將 OAuth token 保存為 mode `0600` 的純文字檔案。
任何已能以同一個 Unix 帳號執行程式或讀取該帳號檔案的攻擊者，仍可能取得 token。

降低風險的措施：

- token 檔案不得放在 Git repo、同步資料夾或多人共享目錄。
- 不可在 `.zshrc` 直接寫 token。
- 不可全域 `export CLAUDE_CODE_OAUTH_TOKEN`。
- 不可把 token 放進 command argument。
- 設定 `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1`。
- 定期輪替；疑似外洩時立即進行 server-side 撤銷。

長效 token 僅適合 CLI 推論用途，且不等同完整互動式登入能力；例如部分 Remote Control
功能可能仍需要一般 OAuth login。

## 設定步驟

### 自動安裝（建議）

若使用包含本 SOP 的 dotfiles repo，可直接執行：

```bash
make claude-ssh-oauth-install TOKEN_FILE=/path/to/raw-token
```

腳本不會輸出 token，會將它安全匯入
`~/.config/claude/ssh-oauth-token`、收緊為 mode `0600`、備份 `.zshrc`，
再安裝或更新受 marker 管理的 SSH-only wrapper。重複執行不會產生重複設定；
若 `~/.zshrc` 是 dotfiles symlink，腳本會修改解析後的 target，不會用普通檔案取代 symlink，
且 backup 仍放在 `~/.zshrc.bak.*`，不會污染 target repo。

若沒有既有 token 檔，可省略 `TOKEN_FILE`，在隱藏的互動提示中貼上
`claude setup-token` 產生的 token：

```bash
make claude-ssh-oauth-install
```

檢查：

```bash
make claude-ssh-oauth-check
```

卸載 wrapper 但保留 token：

```bash
make claude-ssh-oauth-uninstall
```

明確要求同時刪除 token：

```bash
make claude-ssh-oauth-uninstall DELETE_TOKEN=1
```

以下手動步驟適用於未使用 dotfiles installer，或需要人工理解與審查設定的情況。

### 1. 產生長效 OAuth token

在能正常登入 Claude Code 的可信任本機終端執行：

```bash
claude setup-token
```

依畫面完成授權。指令會顯示 token，但不會替使用者保存。

注意：

- 不要把 token 貼進聊天、issue、文件或 Git commit。
- 不要使用 `export CLAUDE_CODE_OAUTH_TOKEN=...` 直接貼在命令列，避免進入 shell history。

### 2. 安全保存純 token

以下範例將 token 保存到通用的使用者設定目錄：

```zsh
mkdir -p "$HOME/.config/claude"
umask 077
read -s "claude_token?Claude SSH token: "
print
print -r -- "$claude_token" > "$HOME/.config/claude/ssh-oauth-token"
unset claude_token
chmod 600 "$HOME/.config/claude/ssh-oauth-token"
```

在 `read` 提示出現後貼上 token 並按 Enter；畫面不會回顯 token。

只檢查 metadata，不輸出內容：

```bash
stat -f 'mode=%Sp owner=%Su path=%N' \
  "$HOME/.config/claude/ssh-oauth-token"
```

預期 mode 為：

```text
-rw-------
```

不要使用 `cat`、`head`、`tail` 或 debug trace 顯示 token 檔內容。

### 3. 在 `.zshrc` 加入 SSH-only wrapper

將以下函式加入 `~/.zshrc`。若原本已有同名 `claude()` function，先人工整合，不要重複定義。

```zsh
# Claude Code: use an SSH-only OAuth token without exporting it globally.
claude() {
  local claude_bin
  claude_bin="$(whence -p claude)"

  if [[ -z "$claude_bin" ]]; then
    echo "Claude Code executable was not found in PATH." >&2
    return 127
  fi

  if [[ -z "${SSH_CONNECTION:-}" ]]; then
    command "$claude_bin" "$@"
    return
  fi

  local claude_ssh_token_file="$HOME/.config/claude/ssh-oauth-token"
  if [[ ! -r "$claude_ssh_token_file" ]]; then
    echo "Claude SSH token file is not readable: $claude_ssh_token_file" >&2
    return 1
  fi

  (
    export CLAUDE_CODE_OAUTH_TOKEN="$(<"$claude_ssh_token_file")"
    if [[ -z "$CLAUDE_CODE_OAUTH_TOKEN" ]]; then
      echo "Claude SSH token file is empty: $claude_ssh_token_file" >&2
      return 1
    fi

    export CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1
    command "$claude_bin" "$@"
  )
}
```

設計重點：

- `SSH_CONNECTION` 不存在時直接執行原始 binary，保留本機 Keychain 行為。
- token 僅在 subshell 中 export；Claude 結束後即離開該環境。
- 使用 `whence -p` 找 PATH 中的外部 executable，避免 function 遞迴呼叫自己。
- token 檔是純 token，不是 shell script，因此不能 `source`。`source` 會把 token 當成 command。
- `"$@"` 保留所有 Claude CLI arguments。

### 4. 檢查 zsh 語法並套用

```bash
zsh -n "$HOME/.zshrc"
```

沒有輸出且 exit code 為 0 代表語法通過。

在目前互動式 SSH shell 套用：

```bash
source "$HOME/.zshrc"
```

新建立的互動式 SSH connection 會自動載入 `.zshrc`。

## 驗證

### SSH session

在 SSH 中執行：

```bash
claude auth status
```

預期至少包含：

```json
{
  "loggedIn": true,
  "authMethod": "oauth_token"
}
```

確認 token 沒有污染父 shell：

```zsh
if [[ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
  echo "PASS: parent shell has no OAuth token"
else
  echo "FAIL: OAuth token leaked into parent shell"
fi
```

預期：

```text
PASS: parent shell has no OAuth token
```

### 非 SSH 本機終端

在一般本機終端執行：

```bash
claude auth status
```

預期仍由一般登入憑證處理，而不是 SSH 專用 token。實際 `authMethod` 名稱依 Claude Code
版本與登入類型而異。

## 非互動式 SSH 注意事項

`ssh host command` 通常不會啟動 interactive zsh，因此不保證讀取 `.zshrc`。
需要使用本 SOP 的 function 時，可明確要求 interactive zsh：

```bash
ssh -t host 'zsh -ic "claude auth status"'
```

自動化服務、CI 或無 TTY 腳本應使用專屬 wrapper／service environment，並遵循相同的
process-local token 與權限原則，不要假設 `.zshrc` 一定會載入。

## 疑難排解

### 仍顯示未登入

依序檢查：

```bash
whence -p claude
stat -f '%Sp %Su %N' "$HOME/.config/claude/ssh-oauth-token"
zsh -n "$HOME/.zshrc"
typeset -f claude
claude auth status
```

確認：

- token 檔存在、非空，且 mode 為 `0600`。
- `claude()` function 已在目前 shell 定義。
- token 未過期、撤銷或貼錯。
- 沒有較高優先序的 `ANTHROPIC_AUTH_TOKEN`、`ANTHROPIC_API_KEY` 或 cloud-provider
  credential 覆蓋。

列出變數名稱時不要輸出值：

```zsh
for name in \
  ANTHROPIC_AUTH_TOKEN \
  ANTHROPIC_API_KEY \
  CLAUDE_CODE_OAUTH_TOKEN \
  CLAUDE_CODE_USE_BEDROCK \
  CLAUDE_CODE_USE_VERTEX \
  CLAUDE_CODE_USE_FOUNDRY
do
  [[ -n "${(P)name:-}" ]] && echo "$name=<set>"
done
```

### Token 被當成 command

若看到類似 `command not found: sk-...`，表示把純 token 檔拿去 `source`。改用：

```zsh
export CLAUDE_CODE_OAUTH_TOKEN="$(<"$claude_ssh_token_file")"
```

不要把錯誤中的 token 貼到 issue 或 log；若 token 曾出現在可被他人讀取的輸出中，立即撤銷並輪替。

### 本機終端意外使用 SSH token

檢查是否曾在 `.zshrc`、`.zprofile`、`.profile` 或其他 env loader 全域 export：

```bash
rg -n 'CLAUDE_CODE_OAUTH_TOKEN' \
  "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.profile" 2>/dev/null
```

只保留 SSH-only wrapper 內的 process-local export，移除其他全域設定，重新開啟終端後再驗證。

## Token 輪替

1. 在可信任終端重新執行 `claude setup-token`。
2. 使用 Step 2 的隱藏輸入流程覆寫 token 檔。
3. 確認 mode 仍為 `0600`。
4. 建立新的 SSH connection，執行 `claude auth status`。
5. 驗證新 token 後，依帳號或組織的 token 管理流程撤銷舊 token。

不要只刪除本機 token 檔就假設 token 已失效；本機刪除只會停止本機使用，不等於
server-side revocation。

## 回復原狀

1. 從 `~/.zshrc` 移除本 SOP 的 `claude()` function。
2. 重新載入 shell：

   ```bash
   exec zsh
   ```

3. 移除本機 token 檔：

   ```bash
   rm "$HOME/.config/claude/ssh-oauth-token"
   ```

4. 依帳號或組織的 token 管理流程撤銷長效 token。
5. 執行 `claude auth status`，確認回到一般登入或 Keychain 憑證。

## 替代方案

若不接受純文字 token at rest，可選擇：

- 每個 SSH connection 執行 `security unlock-keychain`，不保存密碼。
- 由 GUI login security context 啟動長駐 tmux／LaunchAgent，SSH 僅 attach 到既有 session。
- 使用組織核准的 secret manager 動態提供 credential。

不要把 macOS 登入密碼或 Keychain 密碼寫進 shell profile 來換取自動解鎖。

## 參考資料

- [Claude Code authentication](https://code.claude.com/docs/en/iam)
- [Claude Code environment variables](https://code.claude.com/docs/en/env-vars)
- [Claude Code CLI reference](https://code.claude.com/docs/en/cli-usage)
