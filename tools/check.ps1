# The offline gate. Run before every deploy / before asking for a /reload:
#   tools\check.ps1            checks every addon
#   tools\check.ps1 Foo        checks addons\Foo only
#   tools\check.ps1 -Fix       also reformats with StyLua first
# Exit code 0 only if every step passed. What it cannot check is listed in kb\05-workflow.md.
param(
  [string]$Addon,
  [switch]$Fix
)
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$bin = Join-Path $PSScriptRoot "bin"
$xsd = Join-Path $root "reference\wow-ui-source\Interface\AddOns\Blizzard_SharedXML\UI.xsd"
$target = if ($Addon) { Join-Path $root "addons\$Addon" } else { Join-Path $root "addons" }
if (-not (Test-Path $target)) { throw "Not found: $target" }
$addonDirs = if ($Addon) { @(Get-Item $target) } else { @(Get-ChildItem $target -Directory) }

$results = [ordered]@{}
function Invoke-Step([string]$Name, [scriptblock]$Body) {
  Write-Host "`n== $Name" -ForegroundColor Cyan
  $global:LASTEXITCODE = 0
  & $Body
  $results[$Name] = ($LASTEXITCODE -eq 0)
}

Push-Location $root
try {
  if ($Fix) {
    Invoke-Step "stylua (format)" { & "$bin\stylua.exe" $target }
  }
  Invoke-Step "luacheck (syntax, globals that do not exist on Forever, leaks)" {
    & "$bin\luacheck.exe" $target --no-color -q
  }
  Invoke-Step "stylua --check (formatting)" { & "$bin\stylua.exe" --check $target }
  Invoke-Step "TOC (files exist, exact case, interface 16001, SavedVariables prefix)" {
    & "$PSScriptRoot\Test-AddonToc.ps1" -Path $target
  }
  if (Get-ChildItem $target -Recurse -Filter *.xml -File | Where-Object { $_.FullName -notmatch '[\\/]Libs?[\\/]' }) {
    Invoke-Step "XML (Blizzard UI.xsd)" { & "$PSScriptRoot\Test-UiXml.ps1" -Xsd $xsd -Path $target }
  }
  Invoke-Step "coexistence (no SavedVariable or slash command declared by two addons)" {
    $claims = @{}
    $clashes = 0
    foreach ($a in Get-ChildItem (Join-Path $root "addons") -Directory) {
      $names = @()
      foreach ($toc in Get-ChildItem $a.FullName -Filter *.toc -File) {
        foreach ($line in Get-Content $toc.FullName) {
          if ($line -match '^##\s*SavedVariables(PerCharacter)?\s*:\s*(.+)$') { $names += ($Matches[2] -split '\s*,\s*' | Where-Object { $_ }) }
        }
      }
      foreach ($lua in Get-ChildItem $a.FullName -Recurse -Filter *.lua -File | Where-Object { $_.FullName -notmatch '[\\/](Libs?|tests?)[\\/]' }) {
        foreach ($m in [regex]::Matches((Get-Content $lua.FullName -Raw), '(?m)^\s*(SLASH_\w+?)\d+\s*=\s*"(/[^"]+)"')) {
          $names += $m.Groups[1].Value
          $names += $m.Groups[2].Value.ToLower()
        }
      }
      foreach ($name in ($names | Sort-Object -Unique)) {
        if ($claims.ContainsKey($name) -and $claims[$name] -ne $a.Name) {
          Write-Host "CLASH $name is declared by both $($claims[$name]) and $($a.Name)" -ForegroundColor Red
          $clashes++
        } else { $claims[$name] = $a.Name }
      }
    }
    Write-Host "$($claims.Count) names checked across addons"
    $global:LASTEXITCODE = [int]($clashes -gt 0)
  }
  foreach ($dir in $addonDirs) {
    Invoke-Step "smoke test: $($dir.Name) (load, login, combat, slash commands, logout)" {
      & "$bin\lua5.1.exe" "$PSScriptRoot\smoke.lua" $dir.FullName
    }
  }
}
finally { Pop-Location }

Write-Host "`n== Summary" -ForegroundColor Cyan
$failed = 0
foreach ($step in $results.Keys) {
  if ($results[$step]) { Write-Host "PASS  $step" -ForegroundColor Green }
  else { Write-Host "FAIL  $step" -ForegroundColor Red; $failed++ }
}
Write-Host "Not covered offline: real API return values, layout, taint, secret values, combat behaviour. Those need the game."
exit $failed
