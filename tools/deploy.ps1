# Links every folder in ..\addons into the WoW Forever AddOns folder using junctions.
# Safe to re-run. Only touches links that point into this workspace.
param(
  [string]$GameAddOns = "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns"
)
$ErrorActionPreference = "Stop"
$src = Join-Path (Split-Path $PSScriptRoot -Parent) "addons"
if (-not (Test-Path $GameAddOns)) { throw "AddOns folder not found: $GameAddOns" }

Get-ChildItem $src -Directory | ForEach-Object {
  $dest = Join-Path $GameAddOns $_.Name
  if (Test-Path $dest) {
    $item = Get-Item $dest -Force
    if ($item.LinkType -eq "Junction" -and ($item.Target -contains $_.FullName)) {
      Write-Host "ok       $($_.Name)"; return
    }
    Write-Warning "SKIP $($_.Name): '$dest' exists and is not our junction"; return
  }
  New-Item -ItemType Junction -Path $dest -Target $_.FullName | Out-Null
  Write-Host "linked   $($_.Name)"
}
