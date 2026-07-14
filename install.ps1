[CmdletBinding()]
param(
  [string]$Source,
  [string]$Dest = (Join-Path $HOME '.claude\themes'),
  [string[]]$Family,
  [string]$Filter = '*',
  [switch]$List,
  [switch]$All
)

$root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

function Get-ThemeCatalog {
  param([string]$Root, [string]$SingleSource, [string[]]$Families)

  $pairs = @()
  if ($SingleSource) {
    $pairs += ,@($SingleSource, (Split-Path $SingleSource -Leaf))
  } else {
    Get-ChildItem -Path $Root -Directory |
      Where-Object { $_.Name -notmatch '^\.' } |
      ForEach-Object {
        if (-not $Families -or ($Families -contains $_.Name)) { $pairs += ,@($_.FullName, $_.Name) }
      }
  }

  $catalog = @()
  foreach ($pair in $pairs) {
    $dir, $fam = $pair
    if (-not (Test-Path $dir)) { continue }
    Get-ChildItem -Path $dir -Filter ('{0}-*.json' -f $fam) -File | ForEach-Object {
      $rest = $_.BaseName
      if ($rest.StartsWith("$fam-")) { $rest = $rest.Substring($fam.Length + 1) }
      $parts  = $rest -split '-', 2
      $catalog += [pscustomobject]@{
        File   = $_.FullName
        Name   = $_.Name
        Family = $fam
        Flavor = $parts[0]
        Accent = if ($parts.Count -gt 1) { $parts[1] } else { '' }
      }
    }
  }
  $catalog | Sort-Object Name
}

function Select-From {
  param([string]$Title, [string[]]$Items)

  if ($Items.Count -le 1) { return $Items }
  Write-Host ""
  Write-Host $Title
  for ($i = 0; $i -lt $Items.Count; $i++) { Write-Host ("  {0}) {1}" -f ($i + 1), $Items[$i]) }
  $ans = Read-Host "Choose (comma-separated numbers or names, 'a' for all) [a]"
  if ([string]::IsNullOrWhiteSpace($ans) -or $ans -in @('a', 'all', '*')) { return $Items }

  $chosen = New-Object System.Collections.Generic.List[string]
  foreach ($tok in ($ans -split '[,\s]+' | Where-Object { $_ })) {
    if ($tok -match '^\d+$') {
      $idx = [int]$tok - 1
      if ($idx -ge 0 -and $idx -lt $Items.Count) { $chosen.Add($Items[$idx]) }
      else { Write-Warning "out of range: $tok" }
    } elseif ($Items -contains $tok) {
      $chosen.Add($tok)
    } else {
      Write-Warning "unknown choice: $tok"
    }
  }
  if ($chosen.Count -eq 0) { Write-Warning "nothing recognized; selecting all"; return $Items }
  $chosen | Select-Object -Unique
}

$scripted = [bool]$Source -or [bool]$Family -or ($Filter -ne '*') -or $List -or $All
$canPrompt = (-not [Console]::IsInputRedirected) -or ($env:CCTHEME_FORCE_PROMPT -eq '1')
if (-not $scripted -and -not $canPrompt) {
  Write-Warning "non-interactive shell and no selection given; installing all themes (use -Family/-Filter to narrow)"
  $All = $true
}

$catalog = Get-ThemeCatalog -Root $root -SingleSource $Source -Families $Family
if (-not $catalog) {
  Write-Warning "no themes found (Source='$Source' Family='$($Family -join ',')')"
  return
}

if ($Source -or $Family -or ($Filter -ne '*') -or $All) {
  # scripted selection: filter the catalog by the -Filter wildcard
  $selected = $catalog | Where-Object { $_.Name -like $Filter }
} else {
  # interactive picker: family -> flavors -> accents
  Write-Host "=== Claude Code theme installer ==="
  $fams = $catalog.Family | Select-Object -Unique | Sort-Object
  $pickFams = Select-From -Title "Theme family:" -Items $fams
  $step1 = $catalog | Where-Object { $pickFams -contains $_.Family }

  $flavors = $step1.Flavor | Select-Object -Unique | Sort-Object
  $pickFlavors = Select-From -Title "Flavor(s):" -Items $flavors
  $step2 = $step1 | Where-Object { $pickFlavors -contains $_.Flavor }

  $accents = $step2.Accent | Where-Object { $_ } | Select-Object -Unique | Sort-Object
  if ($accents) {
    $pickAccents = Select-From -Title "Accent(s):" -Items $accents
    $selected = $step2 | Where-Object { $pickAccents -contains $_.Accent }
  } else {
    $selected = $step2
  }
}

$selected = @($selected | Sort-Object Name)
if (-not $selected) { Write-Warning "no themes matched your selection"; return }

if ($List) {
  Write-Host "$($selected.Count) theme(s) match:"
  $selected | ForEach-Object { Write-Host "  $($_.Name)" }
  return
}

if (-not $scripted -and $canPrompt) {
  Write-Host ""
  $confirm = Read-Host "Install $($selected.Count) theme(s) to $Dest? [Y/n]"
  if ($confirm -and $confirm -notmatch '^(y|yes)$') { Write-Host "cancelled."; return }
}

if (-not (Test-Path $Dest)) {
  New-Item -ItemType Directory -Path $Dest -Force | Out-Null
  Write-Host "created $Dest"
}
foreach ($t in $selected) {
  Copy-Item -Path $t.File -Destination $Dest -Force
  Write-Host "installed $($t.Name)"
}
Write-Host "`n$($selected.Count) themes installed to $Dest. Run /theme to select one."
