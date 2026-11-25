# Workflow: look up, build, check, deploy, observe

You cannot launch or see the game. The loop below replaces that with three things: an offline copy of the client's own UI code, an offline gate that knows what exists on Forever, and an addon that writes what happened in game to disk.

## 1. Look things up (before writing a call)

```powershell
python tools\wowapi.py C_Spell.GetSpellInfo          # signature, returns, secret flags, doc text
python tools\wowapi.py UNIT_AURA SpellInfo           # events (payload) and structures / enums
python tools\wowapi.py Settings.RegisterAddOnSetting # Lua-side API: prints the definition and file:line
python tools\wowapi.py -s aura                       # substring search across functions, events, tables
python tools\wowapi.py -n C_UnitAuras                # everything in a namespace, with flags
python tools\wowapi.py -n C_UnitAuras --secret       # only entries with restriction flags
python tools\wowapi.py -g GetSpellInfo UnitHealth    # does this global exist on Forever at all?
```

- Widget methods are indexed by API table: search the method name (`-s SetTimerDuration` finds `SimpleStatusBarAPI.SetTimerDuration`).
- A Lua definition whose path contains `Classic/`, `Vanilla/`, `TBC/`, `Wrath/`, `Cata/`, `Mists/` or `Standard/` does not load on Forever. `Camelot/`, `Mainline/`, `Shared/` and unqualified paths do.
- Flag meanings: `SecretArguments=AllowedWhenTainted` you may pass secrets; `AllowedWhenUntainted` you may not; `NotAllowed` nobody may. `SecretReturns` / `SecretWhen*` the result can be secret. `HasRestrictions` / `IsProtectedFunction` not callable freely by addons.

For how Blizzard uses something, Grep `reference/wow-ui-source/Interface/AddOns`. Other flat lists live in `reference/BlizzardInterfaceResources/Resources/`: `Templates.lua`, `AtlasInfo.lua`, `Mixins.lua`, `Frames.lua`, `CVars.lua` (with help text), `Events.lua`, `LuaEnum.lua`, `GlobalStrings/enUS.lua`.

Online, only when the local source is not enough: `https://warcraft.wiki.gg/wiki/API_<Name>` and `https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes`. Check that the page covers Mainline 12.x, not Classic.

## 2. Build

`tools\new-addon.ps1 -Name Foo -Title "Foo" -Notes "..."` scaffolds from the house template, registers the addon in `.luacheckrc` and deploys it. Then follow [02-addon-blueprint.md](02-addon-blueprint.md).

## 3. Check (the offline gate)

```powershell
tools\check.ps1            # all addons
tools\check.ps1 Foo        # one addon
tools\check.ps1 Foo -Fix   # format with StyLua first
```

| Step | Catches |
|---|---|
| luacheck | syntax errors; reads of globals that do not exist on Forever (W113); `C_Namespace.Typo` (W143); accidental global writes (W111/W112); unused and shadowed variables |
| stylua --check | formatting drift |
| Test-AddonToc | missing or wrongly-cased files, missing `Interface: 16001`, unprefixed SavedVariables, BOM, Lua files no TOC lists |
| Test-UiXml | XML that violates Blizzard's `UI.xsd` |
| coexistence | a SavedVariable or slash command declared by two of our addons (always checks all addons) |
| smoke.lua | runs the addon under real Lua 5.1 against a fake client: file load, `ADDON_LOADED`, `PLAYER_LOGIN`, `PLAYER_ENTERING_WORLD`, combat enter/leave, every slash command with `""` and `"help"`, `PLAYER_LOGOUT`; fails on any error or leaked global |

The gate **cannot** tell you: what an API really returns, whether a frame looks right, whether something taints, whether a value is secret in combat, or anything timing-related. Say so in the hand-off.

The global lists come from Ketho's client dump, which can trail the client by a build or two (70938 vs 71091 on 2026-11-25); `tools\update-reference.ps1` prints both versions.

When luacheck flags a global you are sure exists (a frame created by a load-on-demand Blizzard addon, a new constant), confirm it in `reference/`, then add it to the hand-written `globals` / per-file section of `.luacheckrc` with a comment. Do not edit the generated block.

**Scenario tests:** if an addon has `tests/smoke.lua`, the harness runs it after the slash commands, in the addon's environment, with helpers `env`, `ns`, `fake(owner, name, func)`, `fire(event, ...)`, `flushTimers()` and `check(condition, description)`. Use it to replace API functions with fakes and assert on what the addon did; `addons/AuctionStatFilter/tests/smoke.lua` is the model. The harness implements `hooksecurefunc` for real, pretends load-on-demand Blizzard addons are loaded (`EventUtil.ContinueOnAddOnLoaded` calls back at once), and serves the real enUS global strings.

The smoke harness returns nothing from most API functions. If an addon fails there only because a stub returned nil where the game returns data, either nil-guard the code (often the right fix) or add a realistic implementation to `core` / `namespaceCore` in `tools/smoke.lua`.

Tool binaries live in `tools\bin` (not versioned). To restore them:

| Tool | Download |
|---|---|
| luacheck 1.2.0 | `https://github.com/lunarmodules/luacheck/releases/download/v1.2.0/luacheck.exe` |
| StyLua 2.6.0 | `https://github.com/JohnnyMorganz/StyLua/releases/download/v2.6.0/stylua-windows-x86_64.zip` |
| Lua 5.1.5 | `https://downloads.sourceforge.net/project/luabinaries/5.1.5/Tools%20Executables/lua-5.1.5_Win64_bin.zip` |

## 4. Deploy

`tools\deploy.ps1` junctions every folder in `addons\` into `_forever_\Interface\AddOns`. Edits are live.

- Changed Lua or XML in an addon the client already knows: user types `/reload`.
- **New addon folder, or a changed TOC:** the client reads TOCs at startup. The user must restart the client for the addon to appear (confirmed 2026-11-25); `/reload` is not enough.

## 5. Observe (the in-game feedback loop)

`addons/ForeverDevKit` records each session to `WTF\Account\<ACCOUNT>\SavedVariables\ForeverDevKit.lua`. SavedVariables are written on `/reload` and logout, never on a crash.

1. User plays or reproduces the problem, then types `/reload`.
2. Read `C:\Program Files (x86)\World of Warcraft\_forever_\WTF\Account\<ACCOUNT>\SavedVariables\ForeverDevKit.lua`. On disk, `ForeverDevKitDB.sessions[1]` is the session that just ended (it has an `ended` time); the session now running exists only in memory until the next `/reload`. The last five sessions are kept.
3. Each session holds:
   - `errors`: every Lua error and warning of the session (`message`, `stack`, `locals`, `count`, `time`), copied from Blizzard's `ScriptErrorsFrame`, whether or not the user has error popups enabled. Confirmed 2026-11-25 with a deliberate error: message, file:line and stack were captured; `locals` came back empty.
   - `blocked`: `ADDON_ACTION_BLOCKED` / `ADDON_ACTION_FORBIDDEN` with the addon, the protected function and a stack.
   - `probes`: answers to the questions in `addons/ForeverDevKit/Probes.lua`.
   - `trace`: the events listed in `ns.watchEvents` in `Probes.lua`, in order with their arguments. Set that list to the feature under test.
   - `client`, `character`, `addons` (name and version of every loaded addon: confirms a deploy took).

**Asking the game a question:** add a line to `Probes.lua` (`when = "login"`, `"combat"` or `"manual"`), run `tools\check.ps1 ForeverDevKit`, then ask the user to `/reload` **twice** (first runs the probe, second writes the result), or once plus whatever triggers it. Results are text; secrets appear as `<secret number>`. Record the answer in the KB and remove the probe.

Each addon's own debug log can use the same route: append to a capped table in `FooDB` behind `/foo debug` and read it back from `SavedVariables\Foo.lua`.

Never write to `WTF\` while the game is running (`Get-Process Wow`); reading is always fine.

Things only the user can do, and what to ask for:

| Ask | Why |
|---|---|
| `/reload` | apply Lua changes, flush SavedVariables |
| `/fdk errors` | quick count without leaving the game |
| `/console scriptErrors 1` | see error popups while testing |
| `/fstack`, `/tinspect`, `/etrace` | identify a frame, inspect a table, watch events |
| `/console taintLog 1` then reproduce | writes `_forever_\Logs\taint.log`, readable from here |
| `/dump <expr>` | one-off value; prefer a probe if you need the exact output |

`_forever_\Errors\` holds client crash reports and assertions from Blizzard's own code, not addon errors.

## 6. Hand-off message

State, in this order: what changed; what `check.ps1` verified; what is unverified and needs the game (be specific: "bar colour in combat", "position after reload"); exactly what the user should do (`/reload`, or restart to character select for a new addon); and what you will read afterwards.

## 7. After a client patch

```powershell
tools\update-reference.ps1     # refresh both checkouts, API index, luacheck globals; warns if source and client builds differ
tools\check.ps1                # new W113/W143 warnings mean an API we use was removed or renamed
```

Then update the build number in `CLAUDE.md` and the header of `kb/README.md`, and read the new section of `https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes` (or its successor).

## 8. Publishing

The workspace is one public repository, `https://github.com/ericosg/wow-forever-addons` (MIT). Commit and push only when the user asks.

```powershell
tools\check.ps1                                   # must pass
git grep -n -I -E "<account folder>|<character name>"   # must find nothing; real values are in CLAUDE.local.md
git add -A; git status --short                    # reference/, tools/bin/ and CLAUDE.local.md must not appear
git commit                                        # what changed; what was verified in game vs offline
git push
```

The GitHub CLI (`gh`) is installed for anything beyond push: releases, issues, repository settings. Its path is in `CLAUDE.local.md`.

To let other people install an addon, they copy its folder from `addons/` into `_forever_\Interface\AddOns\`. Packaged releases for CurseForge or Wago are not set up; research/tooling-and-debugging.md section 5 describes the BigWigs packager (flavor `forever`, TOC suffix `_Camelot`).

## 9. Lessons from the first addon (AuctionStatFilter, 2026-11-25)

- The first version passed every offline check and was still wrong in game, because a fake API in a test returns what you imagine the client returns. The bug was judging items before their data was cached. Offline tests prove logic, not assumptions about the client.
- Three in-game rounds were needed. Each round costs the user a `/reload` or a restart, so make every round answer a question: ship a diagnostic log with the first version of anything that reads client data.
- A capped log should keep the informative entries. The first log filled with 80 cheap statless items and missed the ones in question.
- Replacing a Blizzard frame's data table (the browse list) and letting Blizzard's code render it worked, including a purchase, with no taint problems. Prefer narrowing Blizzard's UI over rebuilding it.
- The user's suggestion (apply the filter on Search, not while typing) made the addon simpler and matched how Blizzard's own filters behave.

## 10. Lessons from the second addon (AuctionSuffixPrice, 2026-11-25)

- It worked in game on the first round. What made the difference: reading Blizzard's sell frame end to end before designing, and a scenario test built on a miniature port of that frame (its `SetItem`, `GetBestEntry`, `UpdatePriceSelection` and the list's data provider), so the hooks were exercised against Blizzard's real call order, including both orders of event delivery.
- An always-on diagnostic log answered every open question from one `/reload`: what the item keys and links look like, what the addon picked, which events fired.
- When two designs are in doubt, build both behind a switch and let the game and the user choose. The log showed the rejected design's cost (a search per toggle, the price flickering to the default while waiting) more convincingly than an argument would have.
- `hooksecurefunc` only gives post-hooks. A method the Blizzard function calls first on `self` (here `ClearSearchResultPrice` at the top of `UpdatePriceSelection`) can serve as the "before" marker, which is how the addon tells Blizzard's own row selection from the user's click.
- The log is only useful if the code path ran: an empty log after a test means the test did not reach the addon (stackables use a different sell frame), not that all is well. Say what the log should contain before the user tests.
- Ask for ForeverDevKit to stay enabled in every test round; without it there is no error or blocked-action record.
