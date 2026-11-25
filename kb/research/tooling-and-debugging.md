# Tooling, verification and debugging for WoW Forever addons

Researched 2026-11-25 for the WoW Forever client (product `wowf`, patch 1.60.1, TOC interface `16001`, Lua 5.1).
Audience: a coding agent on Windows 11 / PowerShell that cannot launch the game.

Every claim carries one of these marks:

- **[verified]** - fetched or run during this research (URL returned content, command ran here, file read from the forever branch).
- **[source]** - read in upstream source or docs, not executed here.
- **[memory]** - from general knowledge, not re-checked today. Treat as a lead.
- **[unverified]** - could not be confirmed.

Nothing was installed on this machine. The only code run here was the three helper scripts in sections 2.4, 6.2 and 6.3 (Python stdlib and built-in Windows PowerShell 5.1).

---

## 0. Facts about Forever that change tooling decisions

| Fact | Value | Mark |
|---|---|---|
| Internal project name | "Camelot". `WOW_PROJECT_ID == WOW_PROJECT_CAMELOT` (18) | [verified] `Interface/AddOns/Blizzard_ProjectConstants/Camelot/ProjectConstants.lua` on the forever branch; [wiki](https://warcraft.wiki.gg/wiki/WOW_PROJECT_ID) |
| TOC game type | `camelot`, with alias `forever` (added in build 70291). `[Game]` expands to `Camelot`, `[Family]` to `Mainline` | [verified] [Patch 1.60.1/API changes](https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes), [BlizzardInterfaceResources forever README](https://github.com/Ketho/BlizzardInterfaceResources/tree/forever) |
| TOC file suffixes | `Addon_Camelot.toc`, `Addon_Forever.toc`; `Addon_Mainline.toc` also loads (family) | [verified] [TOC format](https://warcraft.wiki.gg/wiki/TOC_format); the local Questie ships both `Questie_Camelot.toc` and `Questie_Forever.toc` |
| `GetBuildInfo()` | `"1.60.1", "<build>", "<date>", 16001` | [verified] BlizzardInterfaceResources forever README |
| Newest `wowf` build | 1.60.1.71091, published 2026-11-24. The workspace notes say 71037; `Wow.exe` on disk was modified 2026-11-25, so the client has probably updated | [verified] `https://wago.tools/api/builds/wowf/latest` |
| Launch | Beta from 2026-09-17, launch 2026-11-04 | [verified] [wiki](https://warcraft.wiki.gg/wiki/World_of_Warcraft:_Forever) |
| `luaErrorExceptions` CVar | Default `1`: "Enable exceptions for non-tainted lua errors" | [verified] `Resources/CVars.lua` on the forever branch |

The last row explains the one file currently in `_forever_\Errors\`. It is a client crash report (`ERROR #141 Script assertion failure`, `<ExceptionType> Lua Script AssertSafe`) raised by an error in Blizzard's own `Blizzard_ProfessionsRecipeList.lua`. Reading that file and the CVar text together, the likely rule is that errors in untainted Blizzard code become exceptions and land in `Errors\`, while errors in addon code (tainted) do not. That is an inference, not something tested. Do not expect ordinary addon Lua errors to appear in `Errors\`; see section 7.2 for where they do go.

---

## 1. Lua 5.1 toolchain on Windows 11 without admin

### 1.1 Recommendation

Three portable binaries cover linting, syntax checking and formatting. None needs an installer or admin.

| Tool | Version | Direct download | Mark |
|---|---|---|---|
| luacheck | 1.2.0 (2024-05-24, still the latest release) | `https://github.com/lunarmodules/luacheck/releases/download/v1.2.0/luacheck.exe` (64-bit, 820 KB, single static exe) | [verified] resolves |
| StyLua | 2.6.0 (2026-10-10) | `https://github.com/JohnnyMorganz/StyLua/releases/download/v2.6.0/stylua-windows-x86_64.zip` | [verified] resolves |
| Lua 5.1.5 (LuaBinaries) | 5.1.5 | `https://downloads.sourceforge.net/project/luabinaries/5.1.5/Tools%20Executables/lua-5.1.5_Win64_bin.zip` | [verified] resolves with `curl -L` |

luacheck alone already reports Lua 5.1 syntax errors (as `E011`), so `luac` is optional. Lua 5.1 itself is only needed to run offline tests (section 6).

Other release assets on the luacheck v1.2.0 page: `luacheck32.exe` (32-bit), `luacheck` (Linux), `.asc` signatures, rockspec. [verified]

Portable install into a per-user folder:

```powershell
$ProgressPreference = 'SilentlyContinue'
$tools = "$env:LOCALAPPDATA\wow-addon-tools"
New-Item -ItemType Directory -Force $tools | Out-Null

# luacheck
curl.exe -L -o "$tools\luacheck.exe" https://github.com/lunarmodules/luacheck/releases/download/v1.2.0/luacheck.exe

# StyLua
curl.exe -L -o "$env:TEMP\stylua.zip" https://github.com/JohnnyMorganz/StyLua/releases/download/v2.6.0/stylua-windows-x86_64.zip
Expand-Archive -Force "$env:TEMP\stylua.zip" $tools

# Lua 5.1.5 (lua5.1.exe, luac5.1.exe, lua5.1.dll)
curl.exe -L -o "$env:TEMP\lua51.zip" "https://downloads.sourceforge.net/project/luabinaries/5.1.5/Tools%20Executables/lua-5.1.5_Win64_bin.zip"
Expand-Archive -Force "$env:TEMP\lua51.zip" "$tools\lua51"

# PATH for the current user (new shells pick it up)
[Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path','User') + ";$tools;$tools\lua51", 'User')
```

Verify:

```powershell
luacheck --version          # Luacheck: 1.2.0
stylua --version            # stylua 2.6.0
lua5.1 -v                   # Lua 5.1.5
luac5.1 -p addons\Foo\Foo.lua   # syntax check only, no output on success
```

Checksums published in the Scoop manifests (not recomputed here) [verified as manifest content]:

- `luacheck.exe` v1.2.0: `0f1c69c4d09f1ebb4d8df14c215e4553e2e639bd4cb7bf3c639b0daa6198317b`
- `lua-5.1.5_Win64_bin.zip`: `5f34cf7d40a20a587ea351482a4207d93b92ef6f1983e910a13338253819fe93`

Check with `Get-FileHash -Algorithm SHA256 <file>`.

### 1.2 Package managers

| Manager | Packages | Notes | Mark |
|---|---|---|---|
| **Scoop** (no admin, not installed on this machine) | `scoop install luacheck stylua lua-language-server` (Main bucket); `scoop bucket add versions; scoop install versions/lua51` | `lua51` installs LuaBinaries 5.1.5 and shims `lua51`, `lua`, `luac51`, `luac`. `luacheck` is the same GitHub exe | [verified] manifests exist in `ScoopInstaller/Main` and `ScoopInstaller/Versions` |
| **winget** | `winget install JohnnyMorganz.StyLua` (2.6.0); `winget install LuaLS.lua-language-server` (3.19.2) | No luacheck package. `DEVCOM.Lua` is **Lua 5.4.6**, the wrong version for WoW. `rjpcomputing.luaforwindows` is 5.1.5 but an old bundled installer. `DEVCOM.LuaJIT` exists | [verified] `winget search lua` |
| **Chocolatey** (installed here at `C:\ProgramData\chocolatey`) | `lua51`, `stylua` packages exist; no `luacheck` package (404) | Normally needs an elevated shell | [verified] package pages; admin need is [memory] |
| **LuaJIT** | `DEVCOM.LuaJIT` via winget, `luajit` via Scoop | Lua 5.1 semantics but accepts extensions (`goto`, `ULL` literals, `bit` built in), so it is not a strict 5.1 syntax gate. Useful as a fast test runner; `bit` matches WoW's `bit` library | [memory] |
| **LuaRocks on Windows** | - | Ketho calls it "strongly discouraged" and develops in WSL | [verified] [vscode-wow-api setup/README](https://github.com/Ketho/vscode-wow-api/blob/master/setup/README.md) |

### 1.3 lua-language-server (optional, for type-aware checks)

- Latest: 3.19.2 (2026-10-13). Asset: `https://github.com/LuaLS/lua-language-server/releases/download/3.19.2/lua-language-server-3.19.2-win32-x64.zip` [verified]
- Portable: extract anywhere; the binary is `bin\lua-language-server.exe` [memory].
- Headless mode is covered in section 3.

### 1.4 What works today with zero installs

- XML well-formedness and XSD validation: built-in PowerShell and .NET (section 6.3). [verified, ran here]
- TOC validation: PowerShell (section 6.2). [verified, ran here]
- Lua syntax: nothing reliable without a download. `luacheck.exe` is the smallest fix.

---

## 2. luacheck for WoW addons

Docs: <https://luacheck.readthedocs.io/en/stable/config.html>, warning codes <https://luacheck.readthedocs.io/en/stable/warnings.html>.

### 2.1 How respected repos configure it

All use `std = "lua51"`. luacheck 1.2.0 ships no WoW standard, so the differences are in how globals are handled.

| Repo | Strategy | Link | Mark |
|---|---|---|---|
| BigWigs | `max_line_length = false`, `codes = true`, excludes `**/Libs`, then **per-file** `files["Loader.lua"].ignore = { "113/C_AddOns", ... }` lists and a hand-kept global list. Strictest: every global a file touches is declared | [.luacheckrc](https://github.com/BigWigsMods/BigWigs/blob/master/.luacheckrc) (439 lines) | [verified] |
| DeadlyBossMods | Ignores `"1.."` (everything about globals) and leaves global checking to LuaLS. 17 lines | [.luacheckrc](https://github.com/DeadlyBossMods/DeadlyBossMods/blob/master/.luacheckrc) | [verified] |
| WeakAuras | Pattern ignores for `SLASH_.*`, `BINDING_.*`, `LE_.*`, a large `ignore` set, then one huge `globals` list (19.5k lines) | [.luacheckrc](https://github.com/WeakAuras/WeakAuras2/blob/main/.luacheckrc) | [verified] |
| Questie | `max_line_length = 140`, ignores 211/212/213/431/432/611/612/614/631, giant `globals` list of API names (3k lines) | [.luacheckrc](https://github.com/Questie/Questie/blob/master/.luacheckrc) | [verified] |
| Details!, Plater | No `.luacheckrc` in the repo root | - | [verified] 404 |

DBM's whole file, for reference:

```lua
---@diagnostic disable: lowercase-global
std = "lua51"
max_line_length = false
exclude_files = {
	"**/Libs/**/*.lua",
	".luacheckrc",
}
ignore = {
	"1..", -- Everything related to globals, the LuaLS check is better because it doesn't require us to define every single API functions
	"211", -- Unused local variable
	"211/L", -- Unused local variable "L"
	"211/CL", -- Unused local variable "CL"
	"212", -- Unused argument
	"43.", -- Shadowing an upvalue, an upvalue argument, an upvalue loop variable.
	"542", -- An empty if branch
}
```

### 2.2 Sources of WoW global lists

| Source | What it is | Forever-specific? | Mark |
|---|---|---|---|
| [Ketho/BlizzardInterfaceResources](https://github.com/Ketho/BlizzardInterfaceResources/tree/forever) branch `forever` | Dumps from the real client: `GlobalAPI.lua`, `FrameXML.lua`, `Frames.lua`, `Mixins.lua`, `LuaEnum.lua`, `GlobalStrings/enUS.lua` | **Yes** (last synced to 1.60.1.70938 on 2026-11-14) | [verified] |
| [LiangYuxuan/wow-addon-luacheckrc](https://github.com/LiangYuxuan/wow-addon-luacheckrc) | A complete `default.luacheckrc` (2.1 MB) rebuilt daily by GitHub Actions, published as a release asset. Latest tag `202611250106` | Flavor not stated in the README; assume retail | [verified] asset exists; flavor [unverified] |
| [Jayrgo/wow-luacheckrc](https://github.com/Jayrgo/wow-luacheckrc) | `.luacheckrc` parsed from Ketho's dumps, branches `mainline`, `classic`, `bc`, `wrath` | No forever branch; last commit 2024-08 | [verified] |

For this workspace the first row is the right one, because it is dumped from the Forever client itself. Section 2.4 has a generator.

### 2.3 Recommended `.luacheckrc` (workspace root)

Since the workspace rule is "no globals except SavedVariables and slash commands", make undeclared global **writes** an error and declare each addon's globals per folder.

```lua
-- .luacheckrc (workspace root). Lua 5.1 syntax; this file is itself Lua.
std = "lua51"
max_line_length = 140
codes = true                 -- print warning codes so they can be looked up or ignored precisely
self = false                 -- do not warn about unused implicit self in methods
unused_args = true           -- still report unused arguments ...
ignore = {
	"212/self",              -- ... except self
	"212/_.*",               -- and arguments named with a leading underscore
	"213/_.*",               -- unused loop variables with a leading underscore
	"211/_.*",               -- unused locals with a leading underscore
	"11./SLASH_.*",          -- slash command globals: SLASH_FOO1 = "/foo"
	"11./BINDING_.*",        -- keybinding header/name globals
	"432/self",              -- shadowing upvalue self in nested methods
	"542",                   -- empty if branch
}
exclude_files = {
	"**/Libs/**",            -- third-party libraries
	"**/.release/**",        -- packager output
	".luacheckrc",
}

-- Globals every addon may READ. Generated list goes in the block below (section 2.4).
read_globals = {
	-- tables and constants the client dumps do not list (verified missing from the generated list)
	"SlashCmdList", "StaticPopupDialogs", "Settings", "EventRegistry", "UISpecialFrames",
	"WOW_PROJECT_ID", "WOW_PROJECT_CAMELOT", "WOW_PROJECT_MAINLINE", "WOW_PROJECT_CLASSIC",
	"RAID_CLASS_COLORS", "ITEM_QUALITY_COLORS", "NORMAL_FONT_COLOR", "HIGHLIGHT_FONT_COLOR",
	"DEFAULT_CHAT_FRAME", "Minimap", "AddonCompartmentFrame",
	"GameFontNormal", "GameFontNormalSmall", "GameFontHighlight", "GameFontHighlightSmall",
	"LibStub",
	-- BEGIN GENERATED (tools: gen_luacheck_globals.py --branch forever)
	-- END GENERATED
}

-- Per-addon writable globals: SavedVariables only. One block per addon folder.
files["addons/Foo/**"] = {
	globals = { "FooDB" },
}

-- Tests may use busted's globals
files["**/spec/**"] = { std = "+busted" }
files["**/tests/**"] = { std = "+busted" }
```

Notes:

- A global declared as a plain string permits any field access, so `"C_Timer"` covers `C_Timer.After`. `SlashCmdList` is read-only here but assigning `SlashCmdList.FOO = fn` sets a field of a read-only global (code 122). If that fires, move `SlashCmdList` to `globals`, which is what most addon repos do. [memory, behavior of 122 with plain-string globals not run here]
- `StaticPopupDialogs` has the same issue; LiangYuxuan's config ignores `"122/StaticPopupDialogs"`. [verified in that file]
- Inline overrides: `-- luacheck: globals FooDB`, `-- luacheck: ignore 212`, `-- luacheck: push` / `-- luacheck: pop`. [memory]
- Fonts, color constants and other plain globals are not in any dump. Add them to the hand-written part as they come up, or fall back to DBM's approach (ignore `"113"` and let LuaLS judge reads). Keeping `111` and `112` (global writes) enabled is the part that enforces the no-globals rule.

Commands:

```powershell
luacheck addons --no-color                 # whole workspace, config found by walking up from cwd
luacheck addons\Foo --no-color --formatter plain   # one line per finding: file:line:col: (Wcode) message
luacheck addons\Foo -q                     # only files with findings
```

Exit code is 0 when clean, 1 for warnings only, 2 for errors such as syntax errors, higher for fatal problems. [memory]

### 2.4 Generator for the read-globals block

Tested here on 2026-11-25: it produced 11,338 top-level names from the forever branch, including `C_Timer`, `CreateFrame`, `Enum`, `Constants`, `LE_*`, `UIParent`, `GameTooltip`, `Mixin`, `strsplit`, `wipe`, `C_GameRules`, `ScrollBoxListMixin`. [verified, ran here]

```python
"""Build a luacheck read_globals list for the WoW Forever client from
Ketho/BlizzardInterfaceResources (branch: forever). Python stdlib only.
Usage: python gen_luacheck_globals.py [--branch forever] [--strings] > wow_globals.txt
"""
import argparse, re, sys, urllib.request

BASE = "https://raw.githubusercontent.com/Ketho/BlizzardInterfaceResources/{branch}/Resources/{name}"
IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")

def fetch(branch, name):
    with urllib.request.urlopen(BASE.format(branch=branch, name=name), timeout=60) as r:
        return r.read().decode("utf-8", "replace")

def quoted_names(text):
    # lines look like:  \t"C_Timer.After",   -> keep the top-level name only
    for m in re.finditer(r'^\s*"([^"]+)",?\s*$', text, re.M):
        top = m.group(1).split(".", 1)[0]
        if IDENT.match(top):
            yield top

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--branch", default="forever")
    ap.add_argument("--strings", action="store_true", help="also include GlobalStrings (enUS), about 25k names")
    a = ap.parse_args()
    names = set()
    for f in ("GlobalAPI.lua", "FrameXML.lua", "Frames.lua", "Mixins.lua"):
        names.update(quoted_names(fetch(a.branch, f)))
    enum = fetch(a.branch, "LuaEnum.lua")          # Enum = {, Constants = {, LE_FOO = 1
    names.update(m.group(1) for m in re.finditer(r"^([A-Za-z_][A-Za-z0-9_]*)\s*=", enum, re.M))
    if a.strings:
        gs = fetch(a.branch, "GlobalStrings/enUS.lua")   # _G["OKAY"] = "Okay";
        names.update(n for n in re.findall(r'^_G\["([^"]+)"\]\s*=', gs, re.M) if IDENT.match(n))
    lua51 = {"_G", "_VERSION", "assert", "collectgarbage", "dofile", "error", "getfenv", "getmetatable",
             "ipairs", "load", "loadfile", "loadstring", "module", "next", "pairs", "pcall", "print",
             "rawequal", "rawget", "rawset", "require", "select", "setfenv", "setmetatable", "tonumber",
             "tostring", "type", "unpack", "xpcall", "coroutine", "debug", "io", "math", "os", "package",
             "string", "table"}
    out = sorted(names - lua51, key=lambda s: (s.lower(), s))
    sys.stdout.reconfigure(newline="\n")          # avoid CRLF on Windows
    sys.stdout.write("\n".join('\t"%s",' % n for n in out) + "\n")
    sys.stderr.write("%d globals\n" % len(out))

if __name__ == "__main__":
    main()
```

Paste the output between the `BEGIN GENERATED` and `END GENERATED` markers. Whether luacheck 1.2.0 handles an 11k-entry list quickly was not measured (WeakAuras and LiangYuxuan ship lists of similar or larger size, so it is expected to be fine).

---

## 3. LuaLS and VS Code

### 3.1 Ketho's extension

- Marketplace id `ketho.wow-api`, repo <https://github.com/Ketho/vscode-wow-api>, depends on `sumneko.lua`. Activates automatically when the opened folder contains a `.toc`. [verified] `package.json`
- Latest release **0.22.3 (2026-02-24)**, annotations for retail **12.0.1**. Last commit on `master` 2026-06-24. [verified]
- **No Forever awareness.** The wiki says: "There is currently no targeted support for Classic Era and Cataclysm Classic. But the hover tooltip will show the flavors a function exists in." README badges list mainline 12.0.1, mists 5.5.3, vanilla 1.15.8 only. [verified] [wiki Home](https://github.com/Ketho/vscode-wow-api/wiki)
- Consequence: it will not flag retail-only APIs that Forever lacks, and it predates 12.1.x additions that Forever has. Use it for shapes and signatures, then confirm existence against the forever dumps (section 8).
- Settings: `wowAPI.locale`, `wowAPI.luals.configurationScope` (`Workspace` default), `wowAPI.luals.defineKnownGlobals` (default true), `wowAPI.luals.frameXML` (default false, loads Numy's FrameXML annotations). `"wowAPI.devMode": true` stops the extension from rewriting LuaLS settings. [verified]

### 3.2 Where the annotations live

- In the repo: `Annotations/Core/` with subfolders `Blizzard_APIDocumentationGenerated` (330 files), `Widget` (70), `Libraries` (70), `FrameXML` (57, hand-written), `Type`, `ScriptObject`, `Data`, `Lua` (the WoW flavor of the Lua 5.1 standard library). [verified] tree listing
- Installed by VS Code: `%USERPROFILE%\.vscode\extensions\ketho.wow-api-<version>\Annotations\Core`. [verified] path form from the wiki's Settings page; no WoW extension is installed on this machine
- `Annotations/FrameXML` is a git submodule of [NumyAddon/FramexmlAnnotations](https://github.com/NumyAddon/FramexmlAnnotations), branch `live-mix-into-source`.

**NumyAddon/FramexmlAnnotations has a `forever` branch**, auto-generated from Gethe's forever branch and last synced to 1.60.1 (71091) on 2026-11-24. It holds `Annotations/AddOns/**` (1,909 files) plus `_templates`, `_overrides`, `_enums`. It covers global frames, templates, mixins and their methods, and `EnumUtil.MakeEnum` enums. This is the only Forever-specific LuaLS annotation set found. [verified]

Fetch without VS Code:

```powershell
git clone --depth 1 https://github.com/Ketho/vscode-wow-api "$env:LOCALAPPDATA\wow-addon-tools\vscode-wow-api"
git clone --depth 1 --single-branch -b forever https://github.com/NumyAddon/FramexmlAnnotations "$env:LOCALAPPDATA\wow-addon-tools\FramexmlAnnotations-forever"
```

(The blobless clone of the forever annotations used during research was 171 KB of metadata; a full depth-1 checkout is larger.)

### 3.3 `.luarc.json` for headless checking

Not run here (LuaLS is not installed). The builtin-disabling block mirrors what the extension writes by default, per its wiki; without it LuaLS's own Lua 5.1 library definitions collide with `Annotations/Core/Lua`.

```json
{
  "$schema": "https://raw.githubusercontent.com/LuaLS/vscode-lua/master/setting/schema.json",
  "runtime.version": "Lua 5.1",
  "runtime.builtin": {
    "basic": "disable", "debug": "disable", "io": "disable", "math": "disable",
    "os": "disable", "package": "disable", "string": "disable", "table": "disable", "utf8": "disable"
  },
  "workspace.library": [
    "C:/Users/<you>/AppData/Local/wow-addon-tools/vscode-wow-api/Annotations/Core",
    "C:/Users/<you>/AppData/Local/wow-addon-tools/FramexmlAnnotations-forever/Annotations"
  ],
  "workspace.checkThirdParty": false,
  "workspace.ignoreDir": ["Libs", ".release"],
  "diagnostics.globals": ["FooDB"],
  "diagnostics.disable": ["lowercase-global"],
  "hint.enable": false
}
```

Real-world examples: [Questie `.luarc.json`](https://github.com/Questie/Questie/blob/master/.luarc.json) (library `.types` and `Libs`, a long `diagnostics.globals`), [WeakAuras `.luarc.json`](https://github.com/WeakAuras/WeakAuras2/blob/main/.luarc.json) (disables `deprecated`, `need-check-nil`, `undefined-field`, `param-type-mismatch` and others to keep noise down). [verified]

Run:

```powershell
lua-language-server.exe --check=C:\sandbox\wow-forever-addons\addons\Foo `
  --configpath=C:\sandbox\wow-forever-addons\.luarc.json `
  --checklevel=Warning --check_format=pretty `
  --logpath="$env:TEMP\luals-log"
```

- `--check`, `--checklevel` (Error, Warning, Information, Hint; default Warning), `--configpath`, `--logpath`, `--metapath` are documented at <https://luals.github.io/wiki/usage/>. Results are written to the log path (`check.json`). [verified] docs
- `--check_format` and `--check_out_path` appear in `script/cli/check.lua` but not in the docs page. [source]
- Add the namespace annotation in every file so LuaLS understands the shared table: `---@class ns` above `local ADDON, ns = ...`. [verified] wiki

Expect false positives on Forever from the retail-based core annotations. Treat LuaLS output as advisory and luacheck plus the TOC validator as the gate.

---

## 4. Formatting: StyLua and EditorConfig

### 4.1 What addon repos do

None of BigWigs, WeakAuras or Questie has a `.stylua.toml` in its repo root (all 404). [verified] StyLua is not a convention in the big addon repos; adopt it for consistency in this workspace, not for conformance.

- WeakAuras `.editorconfig`: 2 spaces, LF, UTF-8, trim trailing whitespace, final newline; tabs for `.luacheckrc`. [verified]
- BigWigs: tabs (seen in its files); no `.editorconfig`. [verified]
- Questie: 4 spaces, double quotes, max line 160, set through LuaLS `format.defaultConfig` in `.luarc.json`. [verified]

### 4.2 `.stylua.toml`

Options and defaults are from the [StyLua README](https://github.com/JohnnyMorganz/StyLua#options). `syntax = "Lua51"` matters: the default `All` accepts Luau and 5.2+ syntax that WoW rejects. [verified]

```toml
syntax = "Lua51"
column_width = 120
line_endings = "Unix"
indent_type = "Tabs"
indent_width = 4
quote_style = "AutoPreferDouble"
call_parentheses = "Always"
collapse_simple_statement = "Never"
```

```powershell
stylua --check addons            # exit 1 and a diff if anything is unformatted; also fails on parse errors
stylua addons                    # format in place
stylua --syntax lua51 --check addons\Foo\Foo.lua   # CLI form of the syntax option
```

- StyLua reads `stylua.toml` or `.stylua.toml`, then falls back to `.editorconfig`. [verified]
- Skip regions with `-- stylua: ignore`, or `-- stylua: ignore start` / `-- stylua: ignore end`. Use this for big data tables. [verified]
- `.styluaignore` (gitignore syntax) excludes paths such as `Libs/`. [memory]

### 4.3 `.editorconfig`

```ini
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true

[*.{lua,xml,toc}]
indent_style = tab
indent_size = 4

[*.{md,json,yml,yaml,toml}]
indent_style = space
indent_size = 2

[*.md]
trim_trailing_whitespace = false

[*.ps1]
end_of_line = crlf
indent_style = space
indent_size = 4

[.pkgmeta]
indent_style = space
indent_size = 2
```

TOC files must be UTF-8 **without** BOM (the validator in 6.2 warns on a BOM). `.pkgmeta` is YAML and must use spaces. [verified] packager wiki for the YAML rule; BOM rule is [memory]

---

## 5. Packaging and release: BigWigsMods/packager

Repo <https://github.com/BigWigsMods/packager>, latest tag **v2.7.0** (2026-11-05); the action is referenced as `BigWigsMods/packager@v2`. Everything below was read from `README.md`, the wiki and `release.sh` on `master`. [verified]

### 5.1 Forever support

The packager knows Forever:

- `-g forever` and `-g camelot` are accepted game types. `-g 1.60.1` also maps to forever (any `1.6x.y`).
- Interface numbers matching `16???` are classified as `forever`.
- A TOC named `Addon_Camelot.toc` is recognized. `Addon_Mainline.toc` may contain retail and forever interface numbers. Note `release.sh` matches the suffix list `Mainline|Classic|Vanilla|BCC|TBC|Wrath|WOTLKC|Cata|Mists|Camelot`: **`_Forever.toc` is not in that list**, although the client and Wago accept it.
- Build keywords `@version-forever@` / `@non-version-forever@` exist for Lua, XML and TOC.
- With TOC splitting (`-S`), an `## Interface-Forever:` line generates `Addon_Camelot.toc`.
- Upload targets:
  - **CurseForge**: game version type id `88568` for forever (retail 517, classic 67408, bcc 73246, wrath 73713, cata 77522, mists 79434, titan 81212).
  - **Wago**: `https://addons.wago.io/api/data/game` lists `forever: ["1.60.1"]` and `supported_forever_patches`. [verified, fetched]
  - **WoWInterface**: `release.sh` prints `No WoWInterface game type match for "forever" ... ignoring`, even though `https://api.wowinterface.com/addons/compatible.json` now lists `{"id":"1.60.1","name":"WoW Forever","game":"Forever","interface":"16001"}`. Expect WoWI uploads from the packager to skip Forever tagging until `release.sh` is updated. [verified both]

### 5.2 TOC metadata the packager reads

```toc
## Interface: 16001
## Title: Foo
## Notes: What Foo does.
## Author: you
## Version: @project-version@
## SavedVariables: FooDB
## X-Curse-Project-ID: 1234
## X-WoWI-ID: 5678
## X-Wago-ID: he54k6bL

Foo.lua
```

- CurseForge project id: "About Project" box on the project page. WoWInterface id: the number in `info5678-MyAddon`. Wago id: developer dashboard. They can also be passed as `-p`, `-w`, `-a`; `0` unsets the TOC value.
- For a Forever-only addon the wiki recommends:

  ```toc
  ## AllowLoadGameType: forever
  ## ExcludeLoadGameType: standard, classic
  ```

  The exclude line is needed because clients that do not know `forever` load unrecognized game types anyway. [verified] [Patch 1.60.1/API changes](https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes)
- Multi-flavor single TOC: `## Interface: 11509, 20506, 30405, 38002, 40402, 50504, 120100, 16001` (README example; BigWigs and BugSack ship `16001` in exactly this style). Per-file: `ForeverOnly.lua [AllowLoadGameType camelot][ExcludeLoadGameType standard, classic]`.

### 5.3 Substitutions and build blocks

Keyword substitutions (replaced in `.lua`, `.md`, `.toc`, `.txt`, `.xml`): `@project-version@`, `@project-revision@`, `@project-hash@`, `@project-abbreviated-hash@`, `@project-author@`, `@project-date-iso@`, `@project-date-integer@`, `@project-timestamp@`, the `@file-...@` equivalents, `@build-date@`, `@build-date-iso@`, `@build-date-integer@`, `@build-timestamp@`, and `@localization(locale="enUS", format="lua_table", ...)@`.

`@project-version@` is the tag name when HEAD is tagged; untagged builds are alphas.

A junction-deployed dev copy is never packaged, so the game shows the literal `@project-version@`. Do not compare against the literal in Lua, because the packager would replace both sides. Test for the `@` instead:

```lua
local version = C_AddOns.GetAddOnMetadata(ADDON, "Version") or ""
if version:find("@", 1, true) then version = "dev" end
```

(BigWigs uses the same `find("@")` idea for its git hash. [memory])

Build-type blocks:

| Keyword | Code runs when | Lua form | TOC form |
|---|---|---|---|
| `debug` | never in a packaged build; always in the raw source | `--@debug@` ... `--@end-debug@` | `#@debug@` ... `#@end-debug@` (lines removed) |
| `non-debug` | only in packaged builds | `--[===[@non-debug@` ... `--@end-non-debug@]===]` | `#@non-debug@` / `# line` / `#@end-non-debug@` (the `# ` prefix is stripped) |
| `alpha` | untagged builds | `--@alpha@` ... `--@end-alpha@` | same pattern |
| `do-not-package` | never; block and tags are deleted, so later line numbers shift | `--@do-not-package@` ... `--@end-do-not-package@` | `#@do-not-package@` ... |
| `version-forever`, `version-retail`, `version-classic`, ... | matching game type | `--@version-forever@` ... | `#@version-forever@` ... |

In packaged Lua, `--@debug@` becomes `--[===[@debug` and `--@end-debug@` becomes `--@end-debug@]===]`, which comments the block out while keeping line numbers. XML uses `<!--@debug@-->` ... `<!--@end-debug@-->` and must not be nested.

Example of the TOC pattern from BigWigs.toc (libraries load from the repo in dev, from externals in packaged builds):

```toc
Libs\LibStub\LibStub.lua
#@non-debug@
# Libs\AceDB-3.0\AceDB-3.0.lua
#@end-non-debug@
```

### 5.4 `.pkgmeta`

YAML in the repo root, spaces only. Directives: `package-as`, `externals`, `ignore`, `plain-copy`, `move-folders`, `manual-changelog`, `changelog-title`, `license-output`, `enable-nolib-creation`, `enable-toc-creation`, `required-dependencies`, `optional-dependencies`, `embedded-libraries`, `tools-used`, `wowi-archive-previous`, `wowi-create-changelog`, `wowi-convert-changelog`. Wiki: <https://github.com/BigWigsMods/packager/wiki/Preparing-the-PackageMeta-File>.

```yaml
package-as: Foo

externals:
  Libs/LibStub:
    url: https://repos.wowace.com/wow/libstub/trunk
    tag: latest
  Libs/CallbackHandler-1.0:
    url: https://repos.wowace.com/wow/callbackhandler/trunk/CallbackHandler-1.0
    tag: latest
  Libs/LibFoo-1.0:
    url: https://github.com/someone/LibFoo-1.0.git
    path: LibFoo-1.0          # subfolder inside that repo
    tag: v1.2                 # or branch: / commit:

ignore:
  - README.md
  - tests
  - "*.ps1"

manual-changelog:
  filename: CHANGELOG.md
  markup-type: markdown

enable-toc-creation: no
```

- Externals can be Git, SVN, Mercurial or a `.zip` URL. Files starting with a dot are always ignored. `move-folders` splits one repo into several addon folders (BigWigs uses it for its load-on-demand modules).
- Real examples: [BigWigs `.pkgmeta`](https://github.com/BigWigsMods/BigWigs/blob/master/.pkgmeta), [BugSack `.pkgmeta`](https://github.com/funkydude/BugSack/blob/master/.pkgmeta). [verified]

### 5.5 Running it

`release.sh` needs bash 4.3+, awk, grep, sed, curl, zip, git 2.13+, and `jq` 1.5+ for uploads. Git Bash on this machine has bash, curl and git, but **no `jq`** and probably no `zip`; run the packager in GitHub Actions or WSL instead of locally. [verified] `jq` missing; `zip` not checked

Flags: `-d` skip upload, `-z` skip zip, `-e` skip externals, `-o` keep the package dir, `-s` nolib package, `-S` split TOC, `-u` Unix line endings, `-t topdir`, `-r releasedir` (default `.release`), `-p/-w/-a` ids, `-g game-version`, `-m pkgmeta`, `-n "{package-name}-{project-version}{nolib}{classic}"`.

Local dry run in WSL: `./release.sh -d -z` builds `.release/Foo/` without zipping or uploading.

Release type: untagged commit is alpha, a tag containing `alpha` or `beta` is that type, any other tag is a release. [source] `release.sh`

Environment variables: `CF_API_TOKEN`, `WOWI_API_TOKEN`, `WAGO_API_TOKEN`, `GH_API_TOKEN`. `CF_API_KEY` and `GITHUB_OAUTH` still work but are marked deprecated in `release.sh`. A `.env` file in the top directory is also read.

### 5.6 GitHub Actions workflow

Adapted from the [packager wiki](https://github.com/BigWigsMods/packager/wiki/GitHub-Actions-workflow), with the current variable names:

```yaml
name: Package and release

on:
  push:
    tags:
      - '**'

permissions:
  contents: write

jobs:
  release:
    runs-on: ubuntu-latest
    env:
      CF_API_TOKEN: ${{ secrets.CF_API_TOKEN }}
      WOWI_API_TOKEN: ${{ secrets.WOWI_API_TOKEN }}
      WAGO_API_TOKEN: ${{ secrets.WAGO_API_TOKEN }}
      GH_API_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0        # full history for the changelog
      - uses: BigWigsMods/packager@v2
        # with:
        #   args: -g forever
```

- Tags must be annotated (`git tag -a v1.0.0 -m "v1.0.0"`). The repository's `GITHUB_TOKEN` needs read-write permission or the release step fails with "Resource not accessible by integration". [verified] wiki
- The wiki example uses `actions/checkout@v7`; tags `v7`, `v7.0.1` exist. [verified]
- Lint job alongside: `nebularg/actions-luacheck@v1` (tags up to v1.1.2) or `lunarmodules/luacheck@v1` (Docker image `ghcr.io/lunarmodules/luacheck:v1.2.0`), and `JohnnyMorganz/stylua-action` (tags up to v5.0.0). [verified] tags exist; inputs not checked
- Related helpers: [NumyAddon/ToCVersions](https://github.com/NumyAddon/ToCVersions) replaces `@toc-version-forever@` / `@toc-version-camelot@` with `16001` before packaging; [p3lim/toc-interface-updater](https://github.com/p3lim/toc-interface-updater) bumps `## Interface:` and accepts flavor `forever` (alias `camelot`). [verified] READMEs
- Alternative packager: [McTalian/wow-build-tools](https://github.com/McTalian-WoW-Addons/wow-build-tools) ships a Windows zip (`wow-build-tools_windows_amd64.zip`). Forever support not checked. [unverified]

### 5.7 Monorepo caveat

The packager assumes one addon per repository (TOC at the checkout root, version from that repo's tags). This workspace holds several addons under `addons/`. Options when one is ready to publish:

1. Give that addon its own repository (`git subtree split --prefix=addons/Foo -b foo-release`, push to a new remote) and run the packager there.
2. Skip the packager and zip the folder for manual upload: `Compress-Archive -Path addons\Foo -DestinationPath Foo-1.0.0.zip` (strip `README`-style dev files first, and replace `@project-version@` by hand).

Whether `-t addons/Foo` works inside a monorepo was not tested. [unverified]

---

## 6. Offline testing

### 6.1 Options

| Option | What it gives | Windows fit | Mark |
|---|---|---|---|
| luacheck | Syntax errors, undefined globals, unused and shadowed variables | Single exe | see section 2 |
| Smoke loader (6.4) | Runs every TOC-listed Lua file in order under Lua 5.1 with stub globals; catches load-time errors and nil calls at file scope | Needs `lua5.1.exe` | sketch, not run |
| [busted](https://github.com/lunarmodules/busted) | Unit tests for pure-logic modules | Needs LuaRocks, which is painful on Windows. Use WSL, or plain `lua5.1` assert-style tests | [memory] |
| [Wowless](https://github.com/lua-wow-tools/wowless) | Headless WoW Lua/FrameXML interpreter; loads the real Blizzard UI then your addon | Docker only | [verified] see below |
| [WoWUnit](https://github.com/Jaliborc/WoWUnit) | In-game unit test addon | Needs the human | [verified] repo exists |
| [Falkicon/Mechanic](https://github.com/Falkicon/Mechanic) | In-game diagnostic hub plus desktop CLI/MCP; README says TOCs declare `120100, 16001` and it has a Lua sandbox with generated API stubs | Alpha; not evaluated | [verified] README only |

**Wowless** details [verified from README, `data/products.yaml`, `bin/run.sh`]:

- Describes itself as pre-alpha: "if it outputs any errors, those errors are almost certainly still in Wowless, not your addon."
- **`wowf` is in its product list** (alongside `wow`, `wow_classic`, `wow_classic_era`, `wow_anniversary`, `wowt`, `wowxptr`, and PTR variants).
- "Development is currently only supported via Docker." Inside the container: `git submodule update --init --depth 1`, `cmake --preset default`, then `bin/run.sh wowf --addondir path/to/AddonName`. It downloads the client's interface code, evaluates it, then clicks and mouses over frames.
- Its Lua runtime is [elune](https://github.com/meorawr/elune), a taint-aware Lua 5.1 fork.
- Not run here. Whether the `wowf` target currently builds and passes is [unverified].

Older offline mocks ("WoWMock with LuaUnit" on WoWInterface, WoWBench) are stale and not worth adopting. [memory]

### 6.2 TOC validator (PowerShell, no installs)

Tested here against a fixture (caught a missing file, a `core\` vs `Core\` case mismatch, malformed XML, an unprefixed SavedVariable, an unlisted Lua file) and against the local Questie folder read-only. [verified, ran here]

Why case matters: Windows loads `core\Util.lua` when the folder is `Core`, but CI on Linux, macOS clients and the packager do not. [memory]

Suggested location: `tools\Test-AddonToc.ps1`.

```powershell
# Validates every *.toc under -Path. Exit code 1 on any ERROR.
#   - TOC base name equals folder name (suffixes like _Forever/_Camelot/_Mainline allowed)
#   - every listed file exists, with the exact on-disk case
#   - listed .xml files are well-formed
#   - '## Interface:' includes the target interface number, '## Title:' is present
#   - SavedVariables are prefixed with the addon name (warning)
#   - .lua files on disk that the TOC never mentions (warning)
param(
    [Parameter(Mandatory)][string]$Path,
    [int]$Interface = 16001,
    [switch]$SkipLibs
)
$ErrorActionPreference = 'Stop'
$script:errors = 0
function Write-Problem([string]$Level, [string]$Message) {
    if ($Level -eq 'ERROR') { $script:errors++ }
    Write-Output ('{0,-5} {1}' -f $Level, $Message)
}

function Get-ExactCaseStatus([string]$Root, [string]$Relative) {
    # Walk each path segment and compare it with the real directory entry name.
    $current = $Root
    foreach ($segment in ($Relative -split '[\\/]')) {
        if ($segment -eq '' -or $segment -eq '.') { continue }
        $entry = Get-ChildItem -LiteralPath $current -Force | Where-Object { $_.Name -ieq $segment } | Select-Object -First 1
        if (-not $entry) { return 'missing' }
        if ($entry.Name -cne $segment) { return 'case:' + $entry.Name }
        $current = $entry.FullName
    }
    return 'ok'
}

$suffixes = '[-_](Mainline|Standard|Classic|Vanilla|TBC|BCC|Wrath|WOTLKC|Cata|Mists|Camelot|Forever)$'
$tocFiles = Get-ChildItem -Path $Path -Recurse -Filter *.toc -File
if ($SkipLibs) { $tocFiles = $tocFiles | Where-Object { $_.FullName -notmatch '[\\/]Libs?[\\/]' } }

foreach ($toc in $tocFiles) {
    $dir = $toc.Directory.FullName
    $folder = $toc.Directory.Name
    $base = $toc.BaseName -replace $suffixes, ''
    if ($base -cne $folder) { Write-Problem ERROR "$($toc.FullName): TOC base name '$base' must equal folder name '$folder'" }

    $bytes = [System.IO.File]::ReadAllBytes($toc.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        Write-Problem WARN "$($toc.Name): starts with a UTF-8 BOM; save as UTF-8 without BOM"
    }

    $meta = @{}
    $listed = New-Object System.Collections.Generic.List[string]
    $lineNo = 0
    foreach ($raw in [System.IO.File]::ReadAllLines($toc.FullName, [System.Text.Encoding]::UTF8)) {
        $lineNo++
        $line = $raw.Trim().TrimStart([char]0xFEFF)
        if ($line -eq '') { continue }
        if ($line -match '^##\s*([^:]+?)\s*:\s*(.*)$') { $meta[$Matches[1]] = $Matches[2]; continue }
        if ($line.StartsWith('#')) { continue }
        $file = ($line -replace '\s*\[[^\]]*\]', '').Trim()     # strip inline [AllowLoadGameType ...] directives
        if ($line -match '\[(Family|Game|TextLocale)\]') { Write-Problem WARN "$($toc.Name):$lineNo uses a TOC variable, not checked: $line"; continue }
        $listed.Add($file.Replace('/', '\').ToLowerInvariant())
        $status = Get-ExactCaseStatus $dir $file
        if ($status -eq 'missing') {
            Write-Problem ERROR "$($toc.Name):${lineNo}: listed file not found: $file"
            continue
        }
        if ($status -like 'case:*') {
            Write-Problem ERROR "$($toc.Name):${lineNo}: case mismatch in '$file' (on disk: '$($status.Substring(5))'). Loads on Windows, breaks on case-sensitive systems and in CI"
        }
        if ($file -match '\.xml$') {
            try { $xml = New-Object System.Xml.XmlDocument; $xml.Load((Join-Path $dir $file)) }
            catch { Write-Problem ERROR "$($toc.Name):${lineNo}: $file is not well-formed XML: $($_.Exception.Message)" }
        }
    }

    foreach ($required in 'Interface', 'Title') {
        if (-not $meta.ContainsKey($required)) { Write-Problem ERROR "$($toc.Name): missing '## ${required}:'" }
    }
    if ($meta['Interface'] -and (($meta['Interface'] -split '\s*,\s*') -notcontains "$Interface")) {
        Write-Problem ERROR "$($toc.Name): '## Interface: $($meta['Interface'])' does not include $Interface (addon is flagged out of date)"
    }
    foreach ($key in 'SavedVariables', 'SavedVariablesPerCharacter') {
        if (-not $meta[$key]) { continue }
        foreach ($sv in ($meta[$key] -split '\s*,\s*')) {
            if ($sv -and -not $sv.StartsWith($base)) { Write-Problem WARN "$($toc.Name): $key '$sv' is not prefixed with the addon name '$base'" }
        }
    }
    foreach ($lua in Get-ChildItem -LiteralPath $dir -Recurse -Filter *.lua -File) {
        $rel = $lua.FullName.Substring($dir.Length + 1)
        if ($rel -match '^(Libs?|\.release|tests?|spec)[\\/]') { continue }
        if (-not $listed.Contains($rel.ToLowerInvariant())) {
            Write-Problem WARN "$($toc.Name): $rel is on disk but not listed in this TOC (loaded from XML or another TOC, or dead)"
        }
    }
    Write-Output "checked $($toc.FullName)"
}
if ($script:errors) { Write-Output "$($script:errors) error(s)"; exit 1 }
Write-Output 'TOC check passed'
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-AddonToc.ps1 -Path addons
```

Limits: it does not follow `<Script file="...">` or `<Include file="...">` inside XML, so Lua loaded only from XML shows up as an "unlisted" warning. The XML check is stricter than the game: Questie's own XML uses an undeclared `xsi:` prefix, which the game accepts and .NET rejects. Always declare `xmlns:xsi` in new files (the 6.3 template does).

### 6.3 XML validation against Blizzard's `UI.xsd`

- The schema for Forever is at `Interface/AddOns/Blizzard_SharedXML/UI.xsd` on the forever branch (71 KB, one file, no includes):
  `https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_SharedXML/UI.xsd` [verified]
- .NET's `XmlSchemaSet` compiles it and validates addon XML. Tested here: a good file passed; a file with `hiden="true"` and a `<Sizee>` element produced two precise errors, including the list of allowed child elements. [verified, ran here]
- [Meorawr/wow-ui-schema](https://github.com/Meorawr/wow-ui-schema) is a slightly stricter variant for editors, but it tracks retail and was last updated for 11.2.0 (2025-08). Prefer the forever-branch file. [verified]

Header for every addon XML file:

```xml
<Ui xmlns="http://www.blizzard.com/wow/ui/"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://www.blizzard.com/wow/ui/ https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_SharedXML/UI.xsd">
</Ui>
```

Suggested `tools\Test-UiXml.ps1`:

```powershell
param([Parameter(Mandatory)][string]$Xsd, [Parameter(Mandatory)][string[]]$Path)
$ErrorActionPreference = 'Stop'
$schemas = New-Object System.Xml.Schema.XmlSchemaSet
[void]$schemas.Add('http://www.blizzard.com/wow/ui/', (Resolve-Path $Xsd).Path)
$schemas.Compile()
$failed = 0
foreach ($file in Get-ChildItem -Path $Path -Recurse -Filter *.xml -File) {
    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.ValidationType = [System.Xml.ValidationType]::Schema
    $settings.Schemas = $schemas
    $settings.ValidationFlags = [System.Xml.Schema.XmlSchemaValidationFlags]::ReportValidationWarnings
    $script:problems = @()
    $settings.add_ValidationEventHandler({ param($s, $e)
        $script:problems += ('{0}({1},{2}): {3}: {4}' -f $file.FullName, $e.Exception.LineNumber, $e.Exception.LinePosition, $e.Severity, $e.Message) })
    try {
        $reader = [System.Xml.XmlReader]::Create($file.FullName, $settings)
        try { while ($reader.Read()) { } } finally { $reader.Close() }
    } catch [System.Xml.XmlException] {
        $script:problems += ('{0}({1},{2}): NotWellFormed: {3}' -f $file.FullName, $_.Exception.LineNumber, $_.Exception.LinePosition, $_.Exception.Message)
    }
    if ($script:problems.Count) { $failed++; $script:problems | ForEach-Object { Write-Output $_ } }
    else { Write-Output ('OK  {0}' -f $file.FullName) }
}
if ($failed) { exit 1 }
```

```powershell
curl.exe -L -o tools\UI.xsd https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_SharedXML/UI.xsd
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-UiXml.ps1 -Xsd tools\UI.xsd -Path addons
```

The XSD cannot check that `inherits="SomeTemplate"` or `mixin="FooMixin"` name things that exist. Check template names against `Resources/Templates.lua` and mixins against `Resources/Mixins.lua` on the forever branch.

### 6.4 Smoke loader sketch (needs `lua5.1.exe`; not run here)

Loads a TOC's Lua files in order, passing `(addonName, ns)` as the game does, with a permissive stub environment. It catches syntax errors and file-scope mistakes, and it can fire `ADDON_LOADED` / `PLAYER_LOGIN` handlers. It proves nothing about real API behavior.

```lua
-- tools/smoke.lua   usage: lua5.1 tools/smoke.lua addons/Foo Foo.toc
local dir, tocName = arg[1], arg[2]
local addonName = tocName:gsub("%.toc$", "")

-- A callable, indexable table that swallows everything.
local function stub(name)
	return setmetatable({}, {
		__index = function(t, k) local v = stub(name .. "." .. tostring(k)); rawset(t, k, v); return v end,
		__call = function() return stub(name .. "()") end,
		__tostring = function() return "<stub " .. name .. ">" end,
		__concat = function(a, b) return tostring(a) .. tostring(b) end,
	})
end

local handlers = {}
local function newFrame()
	local f = stub("Frame")
	f.RegisterEvent = function() end
	f.SetScript = function(self, script, fn) if script == "OnEvent" then handlers[#handlers + 1] = { self, fn } end end
	return f
end

local env = setmetatable({
	CreateFrame = newFrame,
	SlashCmdList = {},
	WOW_PROJECT_ID = 18, WOW_PROJECT_CAMELOT = 18, WOW_PROJECT_MAINLINE = 1,
	GetBuildInfo = function() return "1.60.1", "71091", "Nov 24 2026", 16001 end,
	strsplit = function(sep, s) local out = {}; for part in (s .. sep):gmatch("(.-)%" .. sep) do out[#out + 1] = part end; return unpack(out) end,
	wipe = function(t) for k in pairs(t) do t[k] = nil end; return t end,
	tinsert = table.insert, tremove = table.remove, format = string.format,
	strlower = string.lower, strupper = string.upper, strfind = string.find, strsub = string.sub,
	print = print,
}, { __index = function(_, k) return _G[k] or stub(k) end })
env._G = env

local ns, failures = {}, 0
for line in io.lines(dir .. "/" .. tocName) do
	line = line:gsub("^\239\187\191", ""):gsub("%s*%[.-%]", ""):gsub("^%s+", ""):gsub("%s+$", "")
	if line ~= "" and not line:match("^#") and line:match("%.lua$") then
		local chunk, err = loadfile(dir .. "/" .. line:gsub("\\", "/"))
		if not chunk then failures = failures + 1; print("SYNTAX " .. err)
		else
			setfenv(chunk, env)
			local ok, runErr = xpcall(function() chunk(addonName, ns) end, debug.traceback)
			if not ok then failures = failures + 1; print("LOAD " .. line .. ": " .. runErr) end
		end
	end
end
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD" }) do
	for _, h in ipairs(handlers) do
		local ok, err = xpcall(function() h[2](h[1], event, addonName) end, debug.traceback)
		if not ok then failures = failures + 1; print("EVENT " .. event .. ": " .. err) end
	end
end
os.exit(failures == 0 and 0 or 1)
```

Because unknown globals resolve to stubs, this will not flag a misspelled API name. luacheck with the generated global list does that job.

### 6.5 Suggested gate before asking for `/reload`

```powershell
luacheck addons --no-color                                                   # syntax + globals
stylua --check addons                                                        # formatting
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-AddonToc.ps1 -Path addons
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-UiXml.ps1 -Xsd tools\UI.xsd -Path addons
```

Then report to the user exactly which of these ran, and that in-game behavior is untested.

---

## 7. In-game debugging the human can run

Presence on Forever was checked in the forever branch of wow-ui-source (`Blizzard_ChatFrameBase/Shared/SlashCommands.lua`, `Blizzard_DebugTools`, `Blizzard_EventTrace`, `Blizzard_APIDocumentation`) and in the forever CVar dump. Behavior descriptions come from the wiki and are not tested in the client.

### 7.1 Commands

| Command | Purpose | Notes | Mark |
|---|---|---|---|
| `/console scriptErrors 1` | Show the Blizzard Lua error popup | CVar exists on Forever, default `0`, saved per account | [verified] CVar dump |
| `/console scriptWarnings 1` | Show Lua warnings | Default `0` | [verified] CVar dump |
| `/reload` | Reload the UI; also flushes SavedVariables to disk | `RELOAD` slash command present. `/console reloadui` and `/run ReloadUI()` or `C_UI.Reload()` are equivalents | [verified] source; `/console reloadui` is [memory] |
| `/fstack` or `/framestack [showHidden] [showRegions] [showAnchors]` | Tooltip listing frames under the cursor | `ALT` cycles the highlighted frame, `CTRL` opens it in the table inspector, `SHIFT` toggles texture info, `CTRL-C` copies the texture path. `/fstack t` shows hidden frames. CVars `fstack_showhidden`, `fstack_showregions`, `fstack_showanchors`, `fstack_showhighlight`, `fstack_preferParentKeys`, `fstack_showRaisedFrameLevels`, `fstack_enabled` | [verified] CVars; keys from [wiki](https://warcraft.wiki.gg/wiki/MACRO_framestack) |
| `/etrace` or `/eventtrace` | Live event log window with filtering | `/etrace mark some text` drops a marker. Pause with `/run EventTrace:TogglePause()` | [verified] source + [wiki](https://warcraft.wiki.gg/wiki/MACRO_eventtrace) |
| `/tinspect [GlobalName]` or `/tableinspect` | Table and frame inspector | With no argument it inspects the frame under the cursor | [verified] source |
| `/dump <expr>` | Print any Lua expression, tables up to 30 entries | `/dump C_AddOns.GetAddOnMetadata("Foo","Version")`, `/dump select(4, GetBuildInfo())` | [verified] source + [wiki](https://warcraft.wiki.gg/wiki/MACRO_dump) |
| `/api` | Search the in-game API documentation | `/api search <pattern>`, `/api system list`, `/api <system> list`, `/api <system> s <pattern>` | [verified] source + [wiki](https://warcraft.wiki.gg/wiki/MACRO_api) |
| `/run <lua>` or `/script <lua>` | Execute Lua | One line, 255 characters | [verified] `SCRIPT` command; limit is [memory] |
| `/tvis` or `/texelvis` | Texel snapping visualizer | Defined conditionally in the source | [source] |
| `/console taintLog <n>` | Log taint to `_forever_\Logs\taint.log` | Forever's CVar help lists: 0 off, 1 blocked actions and the taint leading to them, 2 tainted global reads/writes, 3 upvalues, 4 table fields. The wiki also lists 5 (secret-value writes, added 12.0.1). Written periodically and at logout. Related: `taintLogObjectSecrets` | [verified] CVar dump + [wiki](https://warcraft.wiki.gg/wiki/CVar_taintLog) |

Useful one-liners to ask the human for:

```
/dump GetBuildInfo()
/dump WOW_PROJECT_ID, WOW_PROJECT_CAMELOT
/dump C_AddOns.IsAddOnLoaded("Foo"), C_AddOns.GetAddOnInfo("Foo")
/dump FooDB
/api search Tooltip
```

`GetMouseFocus` is not in the Forever API dump; `GetMouseFoci` is. [verified]

### 7.2 Where Lua errors end up on disk

| Location | Contents | Mark |
|---|---|---|
| `_forever_\Errors\*.txt` | Client crash reports. The one file present is a script assertion from Blizzard code. Addon errors are not expected here (see section 0) | [verified] file read; rule inferred |
| `_forever_\WTF\Account\<ACCOUNT>\SavedVariables\!BugGrabber.lua` | **The reliable path.** With BugGrabber installed, every Lua error is stored in `BugGrabberDB.errors` as `{ message, stack, locals, session, time, counter }`, capped at 500 entries, written at `/reload` or logout | [verified] BugGrabber source |
| `_forever_\Logs\taint.log` | Only when `taintLog` > 0 | [verified] wiki |
| `_forever_\Logs\FrameXML.log` | Historically XML parse and load errors. **Not present** in this install's `Logs\` folder today | [unverified] on Forever |
| Blizzard error popup | Screen only; not written to disk | [memory] |

Current contents of `_forever_\Logs\`: `AccountData.log`, `Aurora.log`, `Client.log`, `ComponentRequests.log`, `Connection.log`, `DeveloperLog.log`, `EditMode.log`, `General.log`, `Hotfix.log`, `Housing.log`, `Model.log`, `Movie.log`, `Professions.log`, `QuestCache.log`, `Sound.log`, `Tact.log`, `TestSuite.log`, `Voice.log`, `WowConnection.log`, `cpu.log`, `gx.log`, `threadpool.log`, plus `.old` rotations. None is a Lua error log. [verified]

Recommended loop for an agent that cannot see the game:

1. Human installs BugGrabber and BugSack once.
2. Human reproduces, then types `/reload` (this writes SavedVariables).
3. Agent reads `...\SavedVariables\!BugGrabber.lua` and looks at the entries with the highest `session` number.
4. The addon's own debug log can use the same route: append to a capped table in `FooDB` behind `/foo debug`, and read `Foo.lua` in `SavedVariables\` after `/reload`.

Do not edit `WTF\` while the game is running; reading is fine.

### 7.3 Debugging addons

| Addon | Forever status | Source | Mark |
|---|---|---|---|
| **!BugGrabber** | TOC lists `16001`. SavedVariables `BugGrabberDB`. Slash `/buggrabber` | SVN `https://repos.wowace.com/wow/bug-grabber/trunk/` (no GitHub repo), [CurseForge](https://www.curseforge.com/wow/addons/bug-grabber) | [verified] TOC and source fetched |
| **BugSack** | TOC lists `16001`. SavedVariables `BugSackDB`. Curse id 6273, Wago `rkGrrgGy` | <https://github.com/funkydude/BugSack> | [verified] |
| **Advanced Interface Options** | TOC lists `16001`. CVar browser | <https://github.com/Stanzilla/AdvancedInterfaceOptions> | [verified] |
| **DevTool** (successor to ViragDevTool) | TOC lists `11508, 50503, 120000` only: will show as out of date on Forever and needs "Load out of date AddOns" | <https://github.com/brittyazel/DevTool> | [verified] TOC; in-game behavior unverified |
| **TextureAtlasViewer** | GitHub TOC is old (version 9.0.04) | <https://github.com/LanceDH/TextureAtlasViewer> | [verified] TOC; current CurseForge build unverified |
| **Mechanic** | README claims `120100, 16001` | <https://github.com/Falkicon/Mechanic> | [verified] README only |

For atlas names without an addon, search `Resources/AtlasInfo.lua` on the forever branch (2.5 MB; format `["atlas-name"] = {width, height, left, right, top, bottom, tilesH, tilesV}` grouped by texture file id). [verified]

### 7.4 Profiling

- **`C_AddOnProfiler`** exists on Forever: `GetAddOnMetric(name, metric)`, `GetOverallMetric(metric)`, `GetApplicationMetric(metric)`, `GetTopKAddOnsForMetric(metric, k)`, `IsEnabled()`, `MeasureCall(func, ...)`, `AddMeasuredCallEvent(name)`, `GetTicksPerSecond()`. [verified] `AddOnProfilerDocumentation.lua` on the forever branch
- `Enum.AddOnProfilerMetric`: `SessionAverageTime` (0), `RecentAverageTime` (1), `EncounterAverageTime` (2), `LastTime` (3), `PeakTime` (4), `CountTimeOver1Ms` (5), `CountTimeOver5Ms`, `CountTimeOver10Ms`, `CountTimeOver50Ms`, `CountTimeOver100Ms`, `CountTimeOver500Ms`, `CountTimeOver1000Ms` (11). [verified]
- It is always on and does not need `scriptProfile`. Times are milliseconds, reset on reload. Blame goes to the addon that created the frame or timer; mouse scripts such as `OnClick` and `OnEnter` are not covered. [verified] [wiki](https://warcraft.wiki.gg/wiki/API_C_AddOnProfiler.GetAddOnMetric)
- No `addonProfilerEnabled` CVar is in the Forever dump. The CVars present are `addonPerformanceMsgWarning`, `addonPerformanceMsgError`, `addonPerformanceMsgOverall` (thresholds, default 0). [verified]
- Legacy profiler: `/console scriptProfile 1` then `/reload`; APIs `UpdateAddOnCPUUsage`, `GetAddOnCPUUsage`, `GetFunctionCPUUsage`, `GetFrameCPUUsage`, `GetScriptCPUUsage`, `ResetCPUUsage`, and `UpdateAddOnMemoryUsage` / `GetAddOnMemoryUsage` are all in the Forever API dump. It slows the whole UI; turn it off afterwards. [verified] presence; cost is [memory]
- Micro-timing: `debugprofilestop()` returns milliseconds with sub-ms precision. [verified] presence

```
/dump C_AddOnProfiler.GetAddOnMetric("Foo", Enum.AddOnProfilerMetric.RecentAverageTime)
/dump C_AddOnProfiler.GetAddOnMetric("Foo", Enum.AddOnProfilerMetric.PeakTime)
/run UpdateAddOnMemoryUsage(); print(GetAddOnMemoryUsage("Foo"))
```

### 7.5 Exporting the client's own interface code

1. Enable the console: Battle.net app, Settings, Game Settings, the World of Warcraft entry, tick "Additional command line arguments", enter `-console`. (Or append ` -console` after the closing quote of a `Wow.exe` shortcut target.)
2. At the **login or character select screen**, press the backtick key and run:

   ```
   ExportInterfaceFiles code
   ExportInterfaceFiles art
   ```

3. Output goes to `BlizzardInterfaceCode` and `BlizzardInterfaceArt` in the World of Warcraft directory. For a flavored install that is expected to be `_forever_\BlizzardInterfaceCode\`; neither folder exists on this machine yet, so the exact location is [unverified].

It does not work through `/console` or while logged in to a character ("Unknown Command"). [verified] [wiki](https://warcraft.wiki.gg/wiki/Viewing_Blizzard%27s_interface_code), [Console](https://warcraft.wiki.gg/wiki/Console)

A local export is the exact code for the installed build. Gethe's forever branch (section 8) is the same content without involving the human.

---

## 8. Reference sources and how to query them from a script

### 8.1 Blizzard UI source: Gethe/wow-ui-source

Repo <https://github.com/Gethe/wow-ui-source>. **There is a `forever` branch**, at `1.60.1 (71091)` as of 2026-11-24 (it tracked 71037 on 2026-11-20). `version.txt` in the branch root holds the full build string. A `1.60.1` tag exists. [verified]

| Branch | Product |
|---|---|
| `live` | retail (`wow`) |
| `ptr`, `ptr2` | retail PTRs (`wowt`, `wowxptr`) |
| `beta` | retail beta |
| `forever` | **WoW Forever (`wowf`)** |
| `classic` | Classic progression (`wow_classic`, Mists 5.5.x) |
| `classic_ptr`, `classic_beta` | Classic PTR and beta |
| `classic_era`, `classic_era_ptr` | Classic Era 1.15.x |
| `classic_anniversary` | Anniversary realms (2.5.x) |
| `classic_titan` | Titan Reforged (3.80.x) |

Branch names are verified; the product mapping follows the names and the wago.tools product list, and the `forever` row is verified by `version.txt`.

Fetching:

```powershell
# one file
curl.exe -sL https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/version.txt
curl.exe -sL https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/AddOnProfilerDocumentation.lua

# file listing without downloading contents (7.8 MB of git metadata, 4,504 files)
git clone --depth 1 --filter=blob:none --no-checkout --single-branch -b forever https://github.com/Gethe/wow-ui-source.git uisrc
git -C uisrc ls-tree -r --name-only HEAD > uisrc_files.txt
git -C uisrc show HEAD:Interface/AddOns/Blizzard_ChatFrameBase/Shared/SlashCommands.lua

# full shallow checkout when grep across everything is needed
git clone --depth 1 --single-branch -b forever https://github.com/Gethe/wow-ui-source.git
```

Layout: everything is under `Interface/AddOns/Blizzard_*/`. Shared code sits in a `Shared/` subfolder and flavor code in `Mainline/`, `Classic/` or `Camelot/` subfolders; each Blizzard TOC decides which load. Key places:

- `Blizzard_APIDocumentationGenerated/*.lua` - machine-readable API docs (functions, events, enums, structures). The authoritative answer to "does this C_ API exist on Forever".
- `Blizzard_SharedXML/UI.xsd` - XML schema.
- `Blizzard_Deprecated*/` - deprecated shims, loaded while `loadDeprecationFallbacks` is `1`.
- `Blizzard_ProjectConstants/Camelot/ProjectConstants.lua`.

Diff retail against Forever: <https://github.com/Gethe/wow-ui-source/compare/12.1.5..forever>. [verified] link from the wiki

The unauthenticated GitHub REST API allows 60 requests an hour; prefer `raw.githubusercontent.com` and `git ls-remote`, which are not counted against it. [verified] limit observed

### 8.2 Client dumps: Ketho/BlizzardInterfaceResources

Repo <https://github.com/Ketho/BlizzardInterfaceResources>, branches `live`, `ptr`, `ptr2`, `classic`, `classic_era`, `classic_anniversary`, **`forever`**. The forever branch was last updated for 1.60.1 (70938) on 2026-11-14, so it trails the client by a few builds. [verified]

Base: `https://raw.githubusercontent.com/Ketho/BlizzardInterfaceResources/forever/Resources/`

| File | Contents |
|---|---|
| `GlobalAPI.lua` | Every global C function and `C_Namespace.Function`, one quoted name per line |
| `FrameXML.lua` | Global Lua functions defined by Blizzard's UI code |
| `Frames.lua` | Named global frames |
| `Mixins.lua` | Mixin table names |
| `Templates.lua` | XML template names with their widget type |
| `Events.lua` | Event names grouped by system |
| `CVars.lua` | Every CVar with default, category, scope flags and help text |
| `LuaEnum.lua` | `Enum`, `Constants`, `LE_*` values |
| `WidgetAPI.lua`, `ScriptObjectAPI.lua` | Widget methods per widget type, with inheritance |
| `AtlasInfo.lua` | Atlas name to size and texcoords |
| `GlobalStrings/enUS.lua` (and 10 other locales) | `_G["NAME"] = "text";` |

Existence checks:

```powershell
$r = 'https://raw.githubusercontent.com/Ketho/BlizzardInterfaceResources/forever/Resources'
(curl.exe -sL "$r/GlobalAPI.lua") | Select-String -SimpleMatch '"C_Timer.'
(curl.exe -sL "$r/Events.lua")    | Select-String -SimpleMatch 'PLAYER_ENTERING_WORLD'
(curl.exe -sL "$r/CVars.lua")     | Select-String -SimpleMatch '"scriptErrors"'
```

Diff against retail: <https://github.com/Ketho/BlizzardInterfaceResources/compare/12.1.5..1.60.1>.

### 8.3 Warcraft Wiki

- Raw wikitext for any page: append `?action=raw`, for example `https://warcraft.wiki.gg/wiki/TOC_format?action=raw`. Works with curl when a browser-like User-Agent is sent. [verified]
- API pages: `https://warcraft.wiki.gg/wiki/API_<Name>` (for example `API_C_AddOnProfiler.GetAddOnMetric`, `API_UnitLevel`). Other prefixes: `MACRO_<command>`, `CVar_<name>`.
- Forever-specific pages:
  - [Patch 1.60.1/API changes](https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes) - consolidated diff from 12.1.5 to 1.60.1 (global API, FrameXML, widgets, events, CVars) plus TOC and game-type examples. Read this first.
  - [TOC format](https://warcraft.wiki.gg/wiki/TOC_format), [WOW_PROJECT_ID](https://warcraft.wiki.gg/wiki/WOW_PROJECT_ID), [World of Warcraft: Forever](https://warcraft.wiki.gg/wiki/World_of_Warcraft:_Forever).
- API pages describe retail unless stated; confirm against 8.1 or 8.2.

### 8.4 Townlong Yak FrameXML browser

- <https://www.townlong-yak.com/framexml/builds> lists **Forever** builds (1.60.1 71091, 71037, 70959, 70938, 70888). [verified via page summary]
- URL pattern: `/framexml/<build>` and `/framexml/<build>/<path>`; `/framexml/<build>/get` downloads; `/framexml/go/<GlobalName>` jumps to a definition (the wiki links use it).
- It returned HTTP 403 to plain `curl`. Use it as a human-facing browser and script against Gethe's repo instead. [verified]

### 8.5 wago.tools

- Build listings include **`wowf`**. [verified]
  - `https://wago.tools/api/builds` - JSON object keyed by product, each a list of builds (17 for `wowf`).
  - `https://wago.tools/api/builds/latest` - latest build per product.
  - `https://wago.tools/api/builds/wowf/latest` - `{"product":"wowf","version":"1.60.1.71091","created_at":"2026-11-24 15:21:07",...}`.
  - `https://wago.tools/api/builds/wowf` (without `/latest`) is not a route.
- DB2 tables as CSV: `https://wago.tools/db2/<Table>/csv?build=1.60.1.71091`. `GlobalStrings` returned 1.98 MB with header `ID,BaseTag,TagText_lang,Flags`; `UiTextureAtlasMember` also returned 200. `?product=wowf` returned the same size as the explicit build, but whether that parameter is honored or ignored was not established. [verified for `build=`; `product=` unverified]
- Browsing UI: `https://wago.tools/db2/<Table>?build=<version>`.
- Other products seen: `wow`, `wowt`, `wowxptr`, `wow_beta`, `wow_classic`, `wow_classic_ptr`, `wow_classic_beta`, `wow_classic_era`, `wow_classic_era_ptr`, `wow_anniversary`, `wow_classic_titan`, `wow_cn_beta`.

Keep an eye on the build number with:

```powershell
(curl.exe -s https://wago.tools/api/builds/wowf/latest | ConvertFrom-Json).version
```

### 8.6 Other

- wow.tools itself is retired; wago.tools is the hosted replacement, and [Marlamin/wow.tools.local](https://github.com/Marlamin/wow.tools.local) is the self-hosted one. DB2 column definitions: [wowdev/WoWDBDefs](https://github.com/wowdev/WoWDBDefs). [verified] repos exist; retirement is [memory]
- [Stanzilla/WoWUIBugs](https://github.com/Stanzilla/WoWUIBugs) - community tracker for Blizzard UI and API bugs. [verified] exists
- [Gethe/wow-ui-textures](https://github.com/Gethe/wow-ui-textures) - exported art. Whether it has a forever branch was not checked. [unverified]
- WoWUIDev Discord is where Forever API issues are being reported (the wiki's change notes cite its #bugs channel). Not scriptable.

---

## 9. Version control hygiene

The workspace is not a git repository yet (`git init` has not been run). [verified]

### 9.1 `.gitignore`

```gitignore
# packager output
.release/
*.zip

# local tool caches and reference checkouts
.cache/
uisrc/
BlizzardInterfaceCode/
BlizzardInterfaceArt/

# LuaLS and luacheck artifacts
.luacheckcache
log/
meta/

# editor and OS
.vscode/*
!.vscode/settings.json
!.vscode/extensions.json
.idea/
Thumbs.db
desktop.ini
.DS_Store

# secrets for release.sh
.env

# never commit game state
WTF/
SavedVariables/
```

`.vscode/settings.json` holds absolute extension paths when Ketho's extension manages it in Workspace scope; commit it only if those paths are acceptable, otherwise ignore the whole folder.

### 9.2 `.gitattributes`

BigWigs uses `* text=auto`; WeakAuras adds `*.sh eol=lf`. [verified] For a Windows workspace that also runs bash and YAML tooling, be explicit:

```gitattributes
* text=auto eol=lf

*.lua   text eol=lf
*.xml   text eol=lf
*.toc   text eol=lf
*.md    text eol=lf
*.yml   text eol=lf
*.sh    text eol=lf
.pkgmeta text eol=lf
*.ps1   text eol=crlf

*.tga binary
*.blp binary
*.png binary
*.ogg binary
*.mp3 binary
*.ttf binary
```

The game reads LF and CRLF files alike [memory]. The packager converts line endings in processed files and has `-u` for Unix endings. [verified] README

### 9.3 Layout for several addons

```
wow-forever-addons/
  .editorconfig  .gitattributes  .gitignore  .luacheckrc  .stylua.toml  .luarc.json
  addons/
    Foo/
      Foo.toc
      Foo.lua
      Libs/            # embedded libraries (excluded from lint and format)
      CHANGELOG.md
      README.md
  tools/               # deploy.ps1, new-addon.ps1, Test-AddonToc.ps1, Test-UiXml.ps1, UI.xsd
  kb/
```

- One shared lint and format config at the root; per-addon SavedVariables globals declared with `files["addons/Foo/**"]` in `.luacheckrc`.
- Junction deployment means the game reads the working tree. Commit before asking for a `/reload` test so a bad edit can be reverted while the human is waiting.
- Publishing an addon means giving it its own repo or a manual zip (section 5.7).

### 9.4 Versions and changelogs

- Use `MAJOR.MINOR.PATCH`. Tag releases as annotated tags (`v1.2.3`); the packager uses the tag as `@project-version@`, treats tags containing `alpha` or `beta` as pre-releases, and builds the changelog from commits since the previous tag unless `manual-changelog` is set.
- In a monorepo, prefix tags per addon (`Foo-v1.2.3`) so histories do not collide. This is a local convention; the packager would use the full tag text as the version.
- Keep `## Version:` as `@project-version@` only for addons that are packaged. For addons deployed only by junction, write a real version in the TOC and bump it by hand, otherwise the addon list shows the placeholder.
- Per-addon `CHANGELOG.md` in Keep a Changelog style (`## [1.2.3] - 2026-11-25`, with Added / Changed / Fixed), referenced from `.pkgmeta` as `manual-changelog` with `markup-type: markdown`.
- `## Interface:` is not a version of the addon. Bump it when the client's interface number changes (watch `wago.tools/api/builds/wowf/latest`; 1.60.1 is `16001`, so 1.60.2 would be `16002`).
- Commit messages feed the automatic changelog, so write them as user-facing one-liners.

---

## 10. Open questions

| Item | Status |
|---|---|
| Whether addon Lua errors are ever written to `Errors\` on Forever | Inferred no; needs one deliberate `error("test")` in an addon to confirm |
| `Logs\FrameXML.log` on Forever | File absent in this install; unknown whether the client still writes it on XML errors |
| Location of `ExportInterfaceFiles` output for a flavored install | Expected `_forever_\BlizzardInterfaceCode`; not exported yet |
| LuaLS `--check` with the config in 3.3 | Not run; expect tuning of `diagnostics.disable` |
| Wowless `wowf` target | Listed in its products; build and run not attempted (Docker only) |
| luacheck with the 11k generated globals and the 122 behavior for `SlashCmdList` | Not run (luacheck not installed) |
| Smoke loader in 6.4 | Written, not executed (no Lua interpreter here) |
| LiangYuxuan's daily `.luacheckrc` flavor | Not stated upstream |
| DevTool and TextureAtlasViewer on Forever | TOCs do not list `16001`; behavior unknown |
| `release.sh -t addons/Foo` inside a monorepo | Not tested |
| `wago.tools ...?product=wowf` on DB2 CSV | Returned data, unclear if the parameter is honored; use `build=` |
