# Scaffolds addons\<Name> from the house template (kb\02-addon-blueprint.md), registers its
# globals in .luacheckrc, runs the offline gate and deploys it.
#   tools\new-addon.ps1 -Name Foo -Title "Foo" -Notes "What it does."
param(
  [Parameter(Mandatory)][ValidatePattern('^[A-Za-z][A-Za-z0-9]*$')][string]$Name,
  [string]$Title = $Name,
  [string]$Notes = "",
  [string]$Interface = "16001"
)
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$dir = Join-Path $root "addons\$Name"
if (Test-Path $dir) { throw "Addon already exists: $dir" }
New-Item -ItemType Directory $dir | Out-Null

$tokens = @{ '{{Name}}' = $Name; '{{Title}}' = $Title; '{{Notes}}' = $Notes; '{{Interface}}' = $Interface
             '{{SlashKey}}' = $Name.ToUpper(); '{{command}}' = $Name.ToLower() }
function Write-Template([string]$File, [string]$Text) {
  foreach ($key in $tokens.Keys) { $Text = $Text.Replace($key, $tokens[$key]) }
  # UTF-8 without BOM, LF line endings: what the client and the TOC check expect.
  [System.IO.File]::WriteAllText((Join-Path $dir $File), ($Text -replace "`r`n", "`n"), (New-Object System.Text.UTF8Encoding $false))
}

Write-Template "$Name.toc" @'
## Interface: {{Interface}}
## Title: {{Title}}
## Notes: {{Notes}}
## Author: Eric
## Version: 0.1.0
## SavedVariables: {{Name}}DB

{{Name}}.lua
'@

Write-Template "$Name.lua" @'
local ADDON, ns = ...

local DB_VERSION = 1
local defaults = {
	debug = false,
}

-- Fills in missing keys only; never overwrites what the user has saved.
local function applyDefaults(target, source)
	for key, value in pairs(source) do
		if type(value) == "table" then
			if type(target[key]) ~= "table" then
				target[key] = {}
			end
			applyDefaults(target[key], value)
		elseif target[key] == nil then
			target[key] = value
		end
	end
	return target
end

function ns.Print(...)
	print("|cff33ff99{{Title}}|r:", ...)
end

function ns.Debug(...)
	if ns.db and ns.db.debug then
		ns.Print("|cff888888debug|r", ...)
	end
end

local frame = CreateFrame("Frame")
local events = {}

function events.ADDON_LOADED(name)
	if name ~= ADDON then
		return
	end
	frame:UnregisterEvent("ADDON_LOADED")
	if type({{Name}}DB) ~= "table" then
		{{Name}}DB = {}
	end
	ns.db = applyDefaults({{Name}}DB, defaults)
	ns.db.version = DB_VERSION
end

function events.PLAYER_LOGIN()
	-- Player data (name, class, bags, quest log) is available from here on.
end

frame:SetScript("OnEvent", function(_, event, ...)
	events[event](...)
end)
for event in pairs(events) do
	frame:RegisterEvent(event)
end

SLASH_{{SlashKey}}1 = "/{{command}}"
SlashCmdList.{{SlashKey}} = function(input)
	local command = strtrim(input or ""):lower()
	if command == "debug" then
		ns.db.debug = not ns.db.debug
		ns.Print("debug", ns.db.debug and "on" or "off")
	else
		ns.Print("/{{command}} debug - toggle debug output")
	end
end
'@

Write-Template "README.md" @'
# {{Title}}

{{Notes}}

## Slash commands

| Command | Effect |
|---|---|
| `/{{command}}` | Help |
| `/{{command}} debug` | Toggle debug output |

## Settings

None yet. Saved in `{{Name}}DB`.
'@

$luacheckrc = Join-Path $root ".luacheckrc"
$entry = "files[`"addons/$Name/**`"] = { globals = { `"${Name}DB`", `"SLASH_$($Name.ToUpper())1`" } }`n"
[System.IO.File]::AppendAllText($luacheckrc, $entry, (New-Object System.Text.UTF8Encoding $false))

& "$PSScriptRoot\check.ps1" $Name -Fix
if ($LASTEXITCODE -ne 0) { Write-Warning "Offline gate reported problems for the fresh scaffold; fix tools\new-addon.ps1." }
& "$PSScriptRoot\deploy.ps1"
Write-Host "Created $dir. The client reads TOC files at startup: restart it to see a new addon (/reload is not enough)."
