<#
.SYNOPSIS
  Install this repo's Catppuccin themes into Claude Code.
.DESCRIPTION
  Copies every catppuccin-*.json in this folder to ~/.claude/themes/, where Claude Code
  reads custom themes. Claude Code hot-reloads that directory, so a running session picks
  up changes without a restart. Select a theme afterwards with /theme.
#>
[CmdletBinding()]
param(
  [string]$Source,
  [string]$Dest = (Join-Path $HOME '.claude\themes')
)

# Default source is the catppuccin/ subfolder next to this script (this script stays in the root).
$root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
if (-not $Source) { $Source = Join-Path $root 'catppuccin' }

if (-not (Test-Path $Dest)) {
  New-Item -ItemType Directory -Path $Dest -Force | Out-Null
  Write-Host "created $Dest"
}

$themes = Get-ChildItem -Path $Source -Filter 'catppuccin-*.json' -File
if (-not $themes) { Write-Warning "no catppuccin-*.json found in $Source (run build.ps1 first)"; return }

foreach ($t in $themes) {
  Copy-Item -Path $t.FullName -Destination $Dest -Force
  Write-Host "installed $($t.Name)"
}
Write-Host "`n$($themes.Count) themes installed to $Dest. Run /theme to select one."
