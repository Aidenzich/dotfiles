.DEFAULT_GOAL := help

DOTFILES_ROOT   := $(CURDIR)
DOTFILES_CLAUDE := $(DOTFILES_ROOT)/claude

# Per-project Claude targets accept TARGET=/path/to/project.
# Default: current working directory (so cd'ing into a project and running
# `make -f /path/to/dotfiles/Makefile claude-disable-auto-memory` works).
TARGET ?= $(CURDIR)

.PHONY: help init init-mac init-linux init-windows symlinks doctor greet \
        claude-disable-auto-memory claude-enable-auto-memory claude-list-memory

help:
	@echo "dotfiles bootstrap"
	@echo
	@echo "  make init                      auto-detect OS and run the right installer"
	@echo "  make init-mac                  force mac path (brew bundle + common)"
	@echo "  make init-linux                force linux/wsl path (apt|dnf|… + uv + common)"
	@echo "  make init-windows              print the pwsh command for windows.ps1"
	@echo "  make symlinks                  re-run only the symlink step"
	@echo "  make doctor                    print detected OS + which tools are installed"
	@echo "  make greet                     just print the welcome (sanity-check)"
	@echo
	@echo "  make claude-disable-auto-memory [TARGET=/path/to/project]"
	@echo "  make claude-enable-auto-memory  [TARGET=/path/to/project]"
	@echo "  make claude-list-memory         [TARGET=/path/to/project]"

init:
	@os=$$(bash $(DOTFILES_ROOT)/install/lib/detect-os.sh); \
	echo "[init] detected: $$os"; \
	case "$$os" in \
	  mac)        $(MAKE) --no-print-directory init-mac ;; \
	  linux|wsl)  $(MAKE) --no-print-directory init-linux ;; \
	  windows)    $(MAKE) --no-print-directory init-windows; exit 1 ;; \
	  *)          echo "Unsupported OS: $$os" >&2; exit 1 ;; \
	esac

init-mac:
	@bash $(DOTFILES_ROOT)/install/mac.sh

init-linux:
	@bash $(DOTFILES_ROOT)/install/linux.sh

init-windows:
	@echo "[init] Native Windows uses PowerShell, not GNU make. Run:"
	@echo "  pwsh -ExecutionPolicy Bypass -File $(DOTFILES_ROOT)/install/windows.ps1"
	@echo "(WSL / Git Bash users: just run 'make init-linux' from inside the shell.)"

symlinks:
	@bash -c 'set -e; \
	  source "$(DOTFILES_ROOT)/install/lib/symlink.sh"; \
	  process_symlinks_file \
	    "$(DOTFILES_ROOT)/install/symlinks.txt" \
	    "$(DOTFILES_ROOT)" \
	    "$$HOME"'

greet:
	@bash $(DOTFILES_ROOT)/install/lib/greet.sh

doctor:
	@echo "detected os : $$(bash $(DOTFILES_ROOT)/install/lib/detect-os.sh)"
	@echo "dotfiles    : $(DOTFILES_ROOT)"
	@echo "git user    : $$(git config --global user.name 2>/dev/null || echo '(unset)')"
	@echo "tools:"
	@for cmd in git jq tmux brew apt-get dnf pacman winget figlet lolcat uv gh fzf rg fd node npm codex claude; do \
	  if command -v $$cmd >/dev/null 2>&1; then \
	    printf '  \033[32m✓\033[0m %s  (%s)\n' "$$cmd" "$$(command -v $$cmd)"; \
	  else \
	    printf '  \033[31m✗\033[0m %s\n' "$$cmd"; \
	  fi; \
	done

# --- Claude auto-memory hardening (per-project) ---
claude-disable-auto-memory:
	@bash $(DOTFILES_CLAUDE)/scripts/install-block-auto-memory.sh "$(TARGET)"

claude-enable-auto-memory:
	@bash $(DOTFILES_CLAUDE)/scripts/uninstall-block-auto-memory.sh "$(TARGET)"

claude-list-memory:
	@bash $(DOTFILES_CLAUDE)/scripts/list-memory.sh "$(TARGET)"
