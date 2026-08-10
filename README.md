# dotfiles

Personal dev-machine bootstrap. One `make init` on a fresh box → packages
installed, dotfiles symlinked, Claude Code hooks ready.

```
git clone https://github.com/Aidenzich/dotfiles.git ~/Projects/dotfiles
cd ~/Projects/dotfiles
make init
```

On a machine that should open a normal iTerm2 login shell—for example, an SSH
client that will hand control mode to a remote tmux—disable the local tmux
launcher during bootstrap:

```bash
make init ITERM2_TMUX_MODE=off
```

The default is `ITERM2_TMUX_MODE=local`. Both modes retain the managed
scrollback and Shift-Return settings. `off` actively clears a previously
installed custom command and restores the selected profile to Login Shell, so
it also reverses an earlier `local` installation.

## What `make init` does

1. **Detect OS** via `install/lib/detect-os.sh` → routes to one of:
   - `install/mac.sh` — ensures Homebrew, runs `brew bundle pkgs/Brewfile` (which includes Rectangle, `node`, and the `claude-code` and `codex` CLI casks), applies the managed Rectangle shortcuts, then installs/upgrades Antigravity CLI via Google's installer.
   - `install/linux.sh` — picks the right pm (apt/dnf/pacman/zypper/apk), installs `pkgs/linux.txt` (incl. `nodejs npm`), installs `uv` + Antigravity CLI via official scripts, then `npm i -g` every entry in `pkgs/npm-global.txt`.
   - `install/windows.ps1` — winget from `pkgs/winget.txt` (incl. `OpenJS.NodeJS.LTS`), `uv` + Antigravity CLI via official PowerShell scripts, then `npm i -g` every entry in `pkgs/npm-global.txt`. Must be invoked via `pwsh`, not GNU make.
2. **Symlinks** every entry in `install/symlinks.txt` into `$HOME`, backing up any existing file to `<dst>.bak.<timestamp>`.
3. **SSH remote-login check** via `install/lib/ssh-check.sh` — report-only. Detects whether inbound SSH is on (so a remote client like [Terminus](https://termius.com/) can connect) and, if it's off, prints the exact enable command for your OS. It never flips the setting itself. Also prints your reachable addresses (Tailscale IP + LAN IP) as connect hints.
4. **Installs and configures Rectangle on macOS** via `install/rectangle.sh`: applies only the version-controlled preferences and shortcuts in `rectangle/config.json`, verifies them by reading the preference domain back, and preserves all unmanaged Rectangle settings.
5. **Configures iTerm2 on macOS** via `install/iterm2.sh`: keeps click/drag/wheel reporting enabled so ordinary tmux receives real wheel events instead of synthesized arrow keys, saves alternate-screen/status-bar output, disables alternate mouse scroll, and preserves the standard `smcup`/`rmcup` lifecycle. Each profile invocation gets a uniquely named `iterm-<UUID>` tmux control-mode session with tmux mouse handling disabled for that session only, so its windows and panes still use native iTerm2 tabs, splits, and scrollback while ordinary tmux sessions retain the global `mouse on` behavior. When iTerm2's local API is enabled, the installer refreshes the in-memory `Default`/`tmux` profile templates as well as every already-open matching session, so future sessions do not clone stale settings; otherwise the saved profiles apply on the next launch. You can attach another client while it is alive; closing the owning iTerm2 session destroys its tmux session. The current preference domain is backed up before every application.
   In ordinary tmux clients, `WheelUpPane` is deliberately bound to tmux copy mode instead of being forwarded to mouse-aware applications. This makes the wheel consistently mean scrollback while keyboard Up/Down remain application input, including `local tmux -> SSH -> remote tmux -> Claude`. The same `.tmux.conf` is used on both machines; the outermost configured tmux handles the wheel.
6. **Greets** via `install/lib/greet.sh` — geeky welcome using `git config --global user.name`. Uses `figlet`+`lolcat` for ASCII art if installed, else falls back to an ANSI block.

### VPN & remote access

`make init` now also installs, per OS:

| Tool | mac | linux / WSL | windows |
|---|---|---|---|
| **OpenVPN** (CLI client) | `brew "openvpn"` | `openvpn` (apt/dnf/…, from `pkgs/linux.txt`) | `OpenVPNTechnologies.OpenVPNConnect` (winget) |
| **Tailscale** (mesh VPN) | `brew "tailscale"` | official `tailscale.com/install.sh` (skipped on WSL) | `tailscale.tailscale` (winget) |

Both VPNs need a deliberate privileged step to actually connect, which the bootstrap does **not** automate — it only installs + reminds you:

- OpenVPN: `sudo openvpn --config your.ovpn`
- Tailscale: `sudo tailscale up` (mac also needs `sudo tailscaled install-system-daemon` first).

### What ends up installed

Cross-platform baseline (every OS path): `git`, `jq`, `tmux`, `gh`, `ripgrep`, `fd`, `fzf`, `figlet`, `lolcat`, `uv`, `node` + `npm`, `claude` (Anthropic Claude Code CLI), `codex` (OpenAI Codex CLI), `agy` (Google Antigravity CLI).

AI CLI delivery is split per OS to use the most native packaging:

| Tool | mac | linux / WSL | windows |
|---|---|---|---|
| `claude` | `cask "claude-code"` — Mach-O binary | `npm i -g @anthropic-ai/claude-code` | `npm i -g @anthropic-ai/claude-code` |
| `codex`  | `cask "codex"` — Rust binary         | `npm i -g @openai/codex`              | `npm i -g @openai/codex`              |
| `agy` | `curl -fsSL https://antigravity.google/cli/install.sh \| bash` | same shell installer | `irm https://antigravity.google/cli/install.ps1 \| iex` |

The `claude` and `codex` casks are CLI binaries (not GUI `.app`s — Homebrew's `cask` keyword is misleading there; see notes in `pkgs/Brewfile`). On mac, update both with `brew upgrade --cask`. Antigravity CLI is installed via Google's official installer.

| Make target | What it does |
|---|---|
| `make init [ITERM2_TMUX_MODE=local\|off]` | auto-detect OS; enable or disable the local iTerm tmux launcher |
| `make init-mac` / `make init-linux` / `make init-windows` | force a specific OS path |
| `make symlinks` | re-run only the symlink step |
| `make doctor` | print detected OS + which expected tools are installed (now incl. `openvpn`, `tailscale`, `ssh`) |
| `make ssh-check` | check whether inbound SSH is on (for Terminus) + print connect hints |
| `make greet` | sanity-check the welcome script |
| `make iterm2 [PROFILE=Default] [ITERM2_TMUX_MODE=local\|off]` | apply iTerm settings and enable/disable the local tmux launcher |
| `make test-iterm2` | verify `local`/`off` transitions in an isolated macOS preferences domain |
| `make test-tmux-wheel` | verify wheel-to-scrollback and arrow-key passthrough on both sides of a nested tmux topology |
| `make rectangle` | install Rectangle if needed and reapply the managed shortcuts |
| `make claude-disable-auto-memory [TARGET=…]` | install Claude's auto-memory block hook into a project. See `claude/README.md`. |
| `make claude-enable-auto-memory  [TARGET=…]` | uninstall it |
| `make claude-list-memory         [TARGET=…]` | list existing auto-memory files (for manual ALR migration) |
| `make claude-ssh-oauth-install [TOKEN_FILE=…]` | install an SSH-only Claude OAuth token wrapper on macOS |
| `make claude-ssh-oauth-check` | verify token permissions, managed wrapper, and zsh syntax |
| `make claude-ssh-oauth-uninstall [DELETE_TOKEN=1]` | remove the managed wrapper; retain the token unless explicitly deleted |
| `make claude-add-home ACCOUNT=work [TOKEN_FILE=…]` | install a private setup-token in `~/.claude-accounts/work`, then add `claude-work` |
| `make claude-remove-home ACCOUNT=work` | permanently remove that local token/home and its shell command |
| `make codex-add-home ACCOUNT=work` | create and log in to `~/.codex-accounts/work`, then add the `codex-work` shell command |
| `make codex-remove-home ACCOUNT=work` | log out, permanently remove that home, and remove its shell command |

### Isolated Claude account homes

Claude Code's macOS Keychain login is shared by every process under the same OS
user, so account homes use one long-lived `claude setup-token` per account:

```bash
make claude-add-home ACCOUNT=work
make claude-add-home ACCOUNT=personal
exec zsh

claude-work
claude-personal auth status
```

Homes live under `~/.claude-accounts/<ACCOUNT>`. Each generated command sets
`CLAUDE_CONFIG_DIR`, loads that home's mode-`0600` `oauth-token`, and injects
`CLAUDE_CODE_OAUTH_TOKEN` only into that Claude process. The wrapper also enables
subprocess credential scrubbing and removes higher-precedence API/provider variables
so they cannot silently select another account. Repository-level `.claude`
configuration remains available from the current project. After validating the token,
the installer marks onboarding complete in that account's `.claude.json` so interactive
launch does not fall through to the shared Keychain login; existing fields are preserved
and backed up before the one-field merge.

When a home has no token, `claude-add-home` runs `claude setup-token`. Complete its
authorization, copy the token it prints, then paste it into the script's hidden prompt.
To import an existing raw-token file without a prompt:

```bash
make claude-add-home ACCOUNT=work TOKEN_FILE=/path/to/raw-token
```

Setup tokens currently last one year, are limited to inference, cannot establish
Remote Control sessions, and may use the separate Agent SDK subscription allowance.
See [Claude Code authentication](https://code.claude.com/docs/en/team).

Remove an account interactively with `make claude-remove-home ACCOUNT=work`.
Removal permanently deletes the selected local token/config directory and removes its
shell command, but does not revoke the token server-side. Use `CONFIRM=1` to bypass
the prompt in automation.

### Isolated Codex account homes

Create one complete Codex home per account instead of swapping a shared
`auth.json` in place:

```bash
make codex-add-home ACCOUNT=work
make codex-add-home ACCOUNT=personal
exec zsh

codex-work
codex-personal login status
```

Homes live under `~/.codex-accounts/<ACCOUNT>` with private directory permissions.
The installer sets `cli_auth_credentials_store = "file"`, starts `codex login` for
a new home, verifies `codex login status`, and restricts `auth.json` to mode `0600`.
Re-running `codex-add-home` preserves an existing credential rather than silently
replacing it. It also maintains a marked block in `~/.zshrc`, preserving a symlinked
zsh configuration and creating one `codex-<ACCOUNT>` command per home. Open a new
shell (or run `exec zsh`) after adding or removing an account.

Remove an account interactively with:

```bash
make codex-remove-home ACCOUNT=work
```

Removal logs the account out and permanently deletes its Codex home. For automation,
the confirmation prompt can be bypassed explicitly with `CONFIRM=1`.

Shared personal skills remain in `~/.agents/skills`, while repository skills remain
in each repo's `.agents/skills`; changing `CODEX_HOME` does not duplicate either
canonical skill location. Account-specific Codex config and sessions remain isolated.

`ACCOUNT` must start with a letter or number and may contain only letters, numbers,
`.` `_` and `-`. The default root can be overridden with `CODEX_HOMES_ROOT`, which is
mainly useful for isolated tests.

## Layout

```
dotfiles/
├── Makefile                       # entry points
├── install/
│   ├── common.sh                  # OS-agnostic post-install (symlinks + greet)
│   ├── mac.sh                     # brew bundle
│   ├── rectangle.sh               # Rectangle install + managed shortcut settings
│   ├── iterm2-tmux-session.sh     # one iTerm session ↔ one tmux session lifecycle
│   ├── iterm2-live-profile.py     # refresh already-open iTerm session profiles
│   ├── iterm2.sh                  # idempotent iTerm2 + tmux integration settings and backup
│   ├── linux.sh                   # detect apt/dnf/…, install + uv
│   ├── windows.ps1                # winget + uv (native PowerShell)
│   ├── symlinks.txt               # src:dst, one per line
│   └── lib/
│       ├── detect-os.sh           # → mac | linux | wsl | windows | unknown
│       ├── symlink.sh             # idempotent symlink + backup helpers
│       ├── ssh-check.sh           # report-only remote-login check (for Terminus)
│       └── greet.sh               # geeky welcome (figlet/lolcat or ANSI)
├── pkgs/
│   ├── Brewfile                   # mac packages (incl. claude-code + codex casks)
│   ├── linux.txt                  # debian/ubuntu names (other distros: edit)
│   ├── winget.txt                 # winget package IDs
│   └── npm-global.txt             # `npm i -g <line>` for linux + windows (mac skips — brew handles)
├── rectangle/
│   └── config.json                # managed Rectangle preferences + shortcuts
├── claude/                        # auto-memory hardening — see claude/README.md
│   └── scripts/claude-home.sh     # isolated Claude account-home lifecycle
├── codex/scripts/codex-home.sh    # isolated Codex account-home lifecycle
├── .tmux.conf                     # symlinked to ~/.tmux.conf
├── .zshrc                         # guarded cross-OS zsh setup
├── .p10k.zsh                      # Powerlevel10k prompt config
└── README.md
```

## Platform notes

- **macOS**: tested. Apple Silicon brew path handled.
- **Linux**: `apt-get` is best tested. `dnf`/`pacman`/`zypper`/`apk` paths share the same package names — adjust `pkgs/linux.txt` if your distro spells something differently.
- **WSL / Git Bash**: `make init` will detect `wsl` and route to `linux.sh`. Run from inside the shell, not from PowerShell.
- **Native Windows**: `make` itself isn't shipped with Windows. Either:
  - install [GNU make for Windows](https://gnuwin32.sourceforge.net/packages/make.htm) / use MSYS2, then `make init` works
  - or run the PowerShell entry point directly: `pwsh -ExecutionPolicy Bypass -File install\windows.ps1`. Symlinks require Developer Mode enabled OR running as Administrator.
- **Windows from scratch (WSL2 path — recommended)**: if you don't have WSL yet and want the full mac/linux-flavored toolbelt, use `install\windows-wsl-bootstrap.ps1`. It detects the current state and resumes from wherever you are. From an **elevated** PowerShell:
  ```powershell
  irm https://raw.githubusercontent.com/Aidenzich/dotfiles/main/install/windows-wsl-bootstrap.ps1 | iex
  ```
  Two unavoidable manual steps in between: (1) reboot after WSL feature install, (2) first-launch Ubuntu once to set your UNIX user. Re-running the script picks up from wherever you stopped. After it finishes, open WezTerm and set `config.default_prog = { 'wsl.exe', '~', '-d', 'Ubuntu' }` in `~/.wezterm.lua` so every new tab launches into the WSL bash with the full bootstrap.

## Adding things

| Want to | Do this |
|---|---|
| add a brew package | append `brew "name"` to `pkgs/Brewfile` |
| add a linux package | append a line to `pkgs/linux.txt` |
| add a winget package | append the ID (e.g. `Author.Name`) to `pkgs/winget.txt` |
| add an npm global (linux/win) | append the package spec (e.g. `@scope/name`) to `pkgs/npm-global.txt`. On mac add the equivalent `brew "..."` / `cask "..."` to `Brewfile` instead — brew updates are nicer than `npm i -g` on macOS. |
| symlink a new dotfile | put the file in repo root (or any subdir), add `<repo-path>:<home-path>` to `install/symlinks.txt` |
| change the welcome | edit `install/lib/greet.sh` |
| add a new OS path | drop `install/<os>.sh`, extend `detect-os.sh` + Makefile `init` switch |

## Requirements

- `bash` (mac/linux/WSL/Git Bash). Native Windows path uses PowerShell.
- `jq` is installed by the bootstrap itself, but is *also* required by the Claude hook installer — so `make init` is the bootstrap of bootstraps.
- `git` (for the username in the greeting + obviously cloning this).
