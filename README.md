# dotfiles

Personal dev-machine bootstrap. One `make init` on a fresh box → packages
installed, dotfiles symlinked, Claude Code hooks ready.

```
git clone https://github.com/Aidenzich/dotfiles.git ~/Projects/dotfiles
cd ~/Projects/dotfiles
make init
```

## What `make init` does

1. **Detect OS** via `install/lib/detect-os.sh` → routes to one of:
   - `install/mac.sh` — ensures Homebrew, runs `brew bundle pkgs/Brewfile` (which includes `node` + the `claude-code` and `codex` CLI casks).
   - `install/linux.sh` — picks the right pm (apt/dnf/pacman/zypper/apk), installs `pkgs/linux.txt` (incl. `nodejs npm`), installs `uv` via the official script, then `npm i -g` every entry in `pkgs/npm-global.txt`.
   - `install/windows.ps1` — winget from `pkgs/winget.txt` (incl. `OpenJS.NodeJS.LTS`), `uv` via the official PowerShell script, then `npm i -g` every entry in `pkgs/npm-global.txt`. Must be invoked via `pwsh`, not GNU make.
2. **Symlinks** every entry in `install/symlinks.txt` into `$HOME`, backing up any existing file to `<dst>.bak.<timestamp>`.
3. **Greets** via `install/lib/greet.sh` — geeky welcome using `git config --global user.name`. Uses `figlet`+`lolcat` for ASCII art if installed, else falls back to an ANSI block.

### What ends up installed

Cross-platform baseline (every OS path): `git`, `jq`, `tmux`, `gh`, `ripgrep`, `fd`, `fzf`, `figlet`, `lolcat`, `uv`, `node` + `npm`, `claude` (Anthropic Claude Code CLI), `codex` (OpenAI Codex CLI).

AI CLI delivery is split per OS to use the most native packaging:

| Tool | mac | linux / WSL | windows |
|---|---|---|---|
| `claude` | `cask "claude-code"` — Mach-O binary | `npm i -g @anthropic-ai/claude-code` | `npm i -g @anthropic-ai/claude-code` |
| `codex`  | `cask "codex"` — Rust binary         | `npm i -g @openai/codex`              | `npm i -g @openai/codex`              |

Both casks are CLI binaries (not GUI `.app`s — Homebrew's `cask` keyword is misleading there; see notes in `pkgs/Brewfile`). On mac, update both with `brew upgrade --cask`.

| Make target | What it does |
|---|---|
| `make init` | auto-detect OS, full path |
| `make init-mac` / `make init-linux` / `make init-windows` | force a specific OS path |
| `make symlinks` | re-run only the symlink step |
| `make doctor` | print detected OS + which expected tools are installed |
| `make greet` | sanity-check the welcome script |
| `make claude-disable-auto-memory [TARGET=…]` | install Claude's auto-memory block hook into a project. See `claude/README.md`. |
| `make claude-enable-auto-memory  [TARGET=…]` | uninstall it |
| `make claude-list-memory         [TARGET=…]` | list existing auto-memory files (for manual ALR migration) |

## Layout

```
dotfiles/
├── Makefile                       # entry points
├── install/
│   ├── common.sh                  # OS-agnostic post-install (symlinks + greet)
│   ├── mac.sh                     # brew bundle
│   ├── linux.sh                   # detect apt/dnf/…, install + uv
│   ├── windows.ps1                # winget + uv (native PowerShell)
│   ├── symlinks.txt               # src:dst, one per line
│   └── lib/
│       ├── detect-os.sh           # → mac | linux | wsl | windows | unknown
│       ├── symlink.sh             # idempotent symlink + backup helpers
│       └── greet.sh               # geeky welcome (figlet/lolcat or ANSI)
├── pkgs/
│   ├── Brewfile                   # mac packages (incl. claude-code + codex casks)
│   ├── linux.txt                  # debian/ubuntu names (other distros: edit)
│   ├── winget.txt                 # winget package IDs
│   └── npm-global.txt             # `npm i -g <line>` for linux + windows (mac skips — brew handles)
├── claude/                        # auto-memory hardening — see claude/README.md
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
