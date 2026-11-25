# Fetches / refreshes the read-only Blizzard UI reference checkouts under ..\reference
# (the `forever` branches), then rebuilds the tools\wowapi.py index and the list of
# Forever globals used by luacheck (.luacheckrc) and tools\smoke.lua.
# Run after every client patch: compare reference\wow-ui-source\version.txt with the
# Version column in "C:\Program Files (x86)\World of Warcraft\.build.info".
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$ref = Join-Path $root "reference"
New-Item -ItemType Directory -Force $ref | Out-Null

$repos = @(
  @{ Name = "wow-ui-source";              Url = "https://github.com/Gethe/wow-ui-source" },
  @{ Name = "BlizzardInterfaceResources"; Url = "https://github.com/Ketho/BlizzardInterfaceResources" }
)
foreach ($r in $repos) {
  $dir = Join-Path $ref $r.Name
  if (Test-Path (Join-Path $dir ".git")) {
    git -C $dir fetch --depth 1 origin forever
    git -C $dir reset --hard FETCH_HEAD
  } else {
    git clone --depth 1 --single-branch --branch forever $r.Url $dir
  }
  if ($LASTEXITCODE -ne 0) { throw "git failed for $($r.Name)" }
  Write-Host ("{0,-28} {1}" -f $r.Name, (git -C $dir log -1 --format="%s (%ad)" --date=short))
}

python (Join-Path $PSScriptRoot "wowapi.py") --rebuild
python (Join-Path $PSScriptRoot "gen-globals.py")

$installed = ((Get-Content "C:\Program Files (x86)\World of Warcraft\.build.info" | Select-Object -Skip 1) |
  Where-Object { $_ -match '\|wowf$' } | ForEach-Object { ($_ -split '\|')[12] }) | Select-Object -First 1
$source = (Get-Content (Join-Path $ref "wow-ui-source\version.txt") -Raw).Trim()
Write-Host "installed client: $installed"
Write-Host "ui source:        $source"
if ($installed -and $installed -ne $source) { Write-Warning "Reference source does not match the installed client build." }
