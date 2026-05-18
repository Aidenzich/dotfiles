#Requires -Version 5.1
<#
.SYNOPSIS
  One-stop bootstrap: install WSL2 + Ubuntu + this dotfiles repo + run `make init-linux` inside Ubuntu.

.DESCRIPTION
  Detects the current state and resumes from wherever you are. Safe to re-run.

  States it handles:
    [A] WSL feature not installed       → install + tell you to reboot
    [B] WSL installed, no Ubuntu distro → install Ubuntu + tell you to first-launch it
    [C] Ubuntu exists, no dotfiles      → clone dotfiles inside WSL + run make init-linux
    [D] All done                        → greet and exit

  Reboot is REQUIRED between [A] and [B] — the WSL2 hypervisor (HCS) is a
  kernel-level Windows feature that can't load without restart. Nothing in
  PowerShell can avoid that. After reboot, just run this script again.

  Ubuntu's first launch ALWAYS prompts for username/password (one-time).
  This script intentionally does NOT auto-create a user — letting Ubuntu do
  it gives you the standard sudoer setup. After you've set the user, re-run.

.PARAMETER DotfilesRepo
  HTTPS URL of the dotfiles repo to clone inside WSL. Default: the same repo
  this script lives in (resolved from `git remote get-url origin` if the
  script was launched from a checkout, else hardcoded fallback).

.PARAMETER Distro
  WSL distro name. Default: Ubuntu.

.EXAMPLE
  # From an elevated PowerShell:
  pwsh -ExecutionPolicy Bypass -File install\windows-wsl-bootstrap.ps1

.EXAMPLE
  # Remote one-liner on a fresh box (elevated PowerShell):
  irm https://raw.githubusercontent.com/Aidenzich/dotfiles/main/install/windows-wsl-bootstrap.ps1 | iex
#>

[CmdletBinding()]
param(
  [string]$DotfilesRepo = "https://github.com/Aidenzich/dotfiles.git",
  [string]$Distro       = "Ubuntu"
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------- helpers
function Write-Step([string]$msg)  { Write-Host "[wsl-bootstrap] $msg" -ForegroundColor Cyan }
function Write-Warn2([string]$msg) { Write-Host "[wsl-bootstrap] $msg" -ForegroundColor Yellow }
function Write-Ok([string]$msg)    { Write-Host "[wsl-bootstrap] $msg" -ForegroundColor Green }
function Write-Err2([string]$msg)  { Write-Host "[wsl-bootstrap] $msg" -ForegroundColor Red }

function Test-Admin {
  $id  = [Security.Principal.WindowsIdentity]::GetCurrent()
  $pr  = [Security.Principal.WindowsPrincipal]::new($id)
  return $pr.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Test-WslInstalled {
  # `wsl --status` exits 0 only when the feature is installed AND a kernel
  # has been downloaded. On a fresh box without WSL it errors out.
  try {
    $null = wsl --status 2>&1
    return ($LASTEXITCODE -eq 0)
  } catch { return $false }
}

function Get-WslDistros {
  # Returns the list of installed distro names. Empty list if WSL just
  # installed but no distro yet. `wsl -l -q` strips headers.
  if (-not (Test-WslInstalled)) { return @() }
  try {
    $raw = (wsl -l -q 2>$null) -replace "`0", ""  # strip the UTF-16 null bytes wsl emits
    if ($LASTEXITCODE -ne 0) { return @() }
    return $raw -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^Windows' }
  } catch { return @() }
}

# ---------------------------------------------------------------- gate: admin
if (-not (Test-Admin)) {
  Write-Err2 "This script must run from an ELEVATED PowerShell (Run as Administrator)."
  Write-Err2 "WSL feature install + Windows feature toggles require admin."
  exit 1
}

# ---------------------------------------------------------------- [A] no WSL
if (-not (Test-WslInstalled)) {
  Write-Step "WSL is not installed. Installing now (this may take a few minutes)."
  Write-Step "Equivalent to: wsl --install --no-launch -d $Distro"
  wsl --install --no-launch -d $Distro
  if ($LASTEXITCODE -ne 0) {
    Write-Err2 "wsl --install failed (exit $LASTEXITCODE)."
    Write-Err2 "On older Windows you may need to: Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -All"
    Write-Err2 "and: Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All"
    exit $LASTEXITCODE
  }
  Write-Ok ""
  Write-Ok "Phase 1 done. REBOOT NOW, then re-run this same script to continue."
  Write-Ok "   Restart-Computer -Force"
  exit 0
}
Write-Ok "WSL is installed."

# ---------------------------------------------------------------- [B] no distro
$distros = Get-WslDistros
if (-not ($distros -contains $Distro)) {
  Write-Step "WSL is up but distro '$Distro' is not installed. Installing now."
  wsl --install -d $Distro --no-launch
  if ($LASTEXITCODE -ne 0) {
    Write-Err2 "wsl --install -d $Distro failed (exit $LASTEXITCODE)."
    exit $LASTEXITCODE
  }
  Write-Ok ""
  Write-Ok "Distro '$Distro' installed. First-launch it once to set up your user:"
  Write-Ok "   wsl -d $Distro"
  Write-Ok "It will prompt for a UNIX username + password. After that, re-run this script."
  exit 0
}
Write-Ok "Distro '$Distro' is present."

# ---------------------------------------------------------------- ensure user is set up
# After distro install you must first-launch it once for user creation.
# `wsl -d $Distro -u root -- whoami` works even before user setup; the test
# we actually care about is whether a non-root default user exists.
$defaultUser = wsl -d $Distro -e bash -c "id -un" 2>$null
if ($LASTEXITCODE -ne 0 -or $defaultUser -eq "root") {
  Write-Warn2 "Distro '$Distro' has no non-root default user yet."
  Write-Warn2 "First-launch it once to create your UNIX user:"
  Write-Warn2 "   wsl -d $Distro"
  Write-Warn2 "Then re-run this script."
  exit 0
}
Write-Ok "Default user in $Distro: $defaultUser"

# ---------------------------------------------------------------- [C] run dotfiles bootstrap inside WSL
Write-Step "Running dotfiles bootstrap inside WSL ($Distro)…"

# Heredoc-style bash so all the logic stays one wsl call. Idempotent: if
# the dotfiles repo is already cloned, just `git pull` + re-run init-linux.
$bashScript = @"
set -euo pipefail

# Required: git + curl (pre-init bootstrap). On Ubuntu both ship by default.
if ! command -v git >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  echo '[wsl] installing git/curl'
  sudo apt-get update -y
  sudo apt-get install -y git curl ca-certificates
fi

DOTFILES_DIR="\$HOME/Projects/dotfiles"
mkdir -p "\$(dirname "\$DOTFILES_DIR")"

if [ -d "\$DOTFILES_DIR/.git" ]; then
  echo "[wsl] dotfiles already cloned at \$DOTFILES_DIR — git pull"
  git -C "\$DOTFILES_DIR" pull --ff-only || true
else
  echo "[wsl] cloning $DotfilesRepo → \$DOTFILES_DIR"
  git clone "$DotfilesRepo" "\$DOTFILES_DIR"
fi

cd "\$DOTFILES_DIR"
echo "[wsl] running: make init-linux"
make init-linux
"@

# Write the script to a temp file and pipe through wsl. Avoids -e bash -c
# escaping hell when the body contains both single and double quotes.
$tmp = New-TemporaryFile
Set-Content -Path $tmp -Value $bashScript -Encoding utf8

try {
  # wsl can read /mnt/c/... paths.
  $wslTmp = wsl -d $Distro -e bash -c "wslpath -a '$($tmp.FullName)'" 2>$null
  $wslTmp = $wslTmp.Trim()
  wsl -d $Distro -e bash "$wslTmp"
  $rc = $LASTEXITCODE
} finally {
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}

if ($rc -ne 0) {
  Write-Err2 "dotfiles bootstrap failed inside $Distro (exit $rc)."
  exit $rc
}

# ---------------------------------------------------------------- [D] greet
$gitUser = $null
try { $gitUser = (git config --global user.name 2>$null).Trim() } catch {}
if (-not $gitUser) { $gitUser = "stranger" }

Write-Host ""
Write-Host "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Magenta
Write-Host "  bootstrap complete · systems are go ⌁"        -ForegroundColor Magenta
Write-Host ""                                                -ForegroundColor Magenta
Write-Host "  > welcome back, @$gitUser"                     -ForegroundColor Magenta
Write-Host "  > Windows + WSL ($Distro) · $(Get-Date -Format 'HH:mm')" -ForegroundColor Magenta
Write-Host "  > next: open WezTerm and point default_prog at WSL" -ForegroundColor Magenta
Write-Host "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Magenta
Write-Host ""
