#Requires -Version 5.1
<#
Native Windows bootstrap (PowerShell).
For WSL or Git Bash users: run `make init-linux` from inside the shell instead.

Run as:
  pwsh -ExecutionPolicy Bypass -File install\windows.ps1

Symlink creation requires either:
  - Developer Mode enabled (Settings → For developers), or
  - elevated (Run as Administrator) PowerShell.
#>

$ErrorActionPreference = "Stop"

$DotfilesRoot = (Get-Item $PSScriptRoot).Parent.FullName
Write-Host "[win] dotfiles root: $DotfilesRoot"

# ---------- packages via winget ----------
Write-Host "[win] installing packages via winget"
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  Write-Error "winget not found — install 'App Installer' from the Microsoft Store first."
  exit 1
}

$wingetList = Join-Path $DotfilesRoot "pkgs\winget.txt"
$packages = Get-Content $wingetList | Where-Object { $_ -notmatch '^\s*(#|$)' }
foreach ($pkg in $packages) {
  Write-Host "  → $pkg"
  winget install --silent --accept-source-agreements --accept-package-agreements --id $pkg 2>$null
  # winget exits non-zero if already installed — don't abort
}

# ---------- uv (official installer is fresher than winget) ----------
if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
  Write-Host "[win] installing uv"
  powershell -ExecutionPolicy ByPass -Command "irm https://astral.sh/uv/install.ps1 | iex"
}

# ---------- symlinks ----------
Write-Host "[win] creating symlinks (requires Developer Mode or admin)"
$symlinksFile = Join-Path $DotfilesRoot "install\symlinks.txt"
Get-Content $symlinksFile | Where-Object { $_ -notmatch '^\s*(#|$)' } | ForEach-Object {
  $parts = $_.Split(':', 2)
  $src = Join-Path $DotfilesRoot $parts[0]
  $dst = Join-Path $HOME $parts[1]

  if (Test-Path $dst) {
    $existingTarget = (Get-Item $dst -Force).Target
    if ($existingTarget -eq $src) {
      Write-Host "  ok     $dst → $src (already linked)"
      return
    }
    $bak = "$dst.bak.$(Get-Date -Format yyyyMMddHHmmss)"
    Move-Item $dst $bak
    Write-Host "  backup $dst → $bak"
  }
  $parent = Split-Path $dst -Parent
  if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
  New-Item -ItemType SymbolicLink -Path $dst -Target $src -Force | Out-Null
  Write-Host "  link   $dst → $src"
}

# ---------- geeky welcome ----------
$gitUser = $null
try { $gitUser = (git config --global user.name).Trim() } catch {}
if (-not $gitUser) { $gitUser = "stranger" }
$os = "Windows $((Get-CimInstance Win32_OperatingSystem).Caption -replace 'Microsoft ', '')"
$now = Get-Date -Format "HH:mm"

Write-Host ""
Write-Host "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Magenta
Write-Host "  bootstrap complete · systems are go ⌁"      -ForegroundColor Magenta
Write-Host ""                                              -ForegroundColor Magenta
Write-Host "  > welcome back, @$gitUser"                   -ForegroundColor Magenta
Write-Host "  > $os · $now"                                -ForegroundColor Magenta
Write-Host "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Magenta
Write-Host ""
