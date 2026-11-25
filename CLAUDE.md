# WoW Forever addon workspace

Goal: build a series of custom addons for the **WoW Forever** client. Each addon is its own folder under `addons/`. Published at https://github.com/ericosg/wow-forever-addons (public, MIT).

## Read first

**`kb/README.md`, then `kb/01-forever-essentials.md`, before writing any addon code.** What you remember about WoW addon APIs describes other clients and is wrong for this one in specific ways: legacy globals (`GetSpellInfo`, `UnitAura`, `IsAddOnLoaded`...) do not exist, secret values make combat data unreadable, there is no combat log for addons, and names have surnames instead of realms.

Never write an API call from memory. Look it up:

```powershell
python tools\wowapi.py C_Spell.GetSpellInfo   # signature, returns, secret flags (see kb\03-workflow.md)
```

`CLAUDE.local.md` (not versioned) holds this machine's account folder, GitHub CLI path and commit identity.

## Target client (verified 2026-11-25)
- Install: `C:\Program Files (x86)\World of Warcraft\_forever_\` (launcher product `wowf`)
- Addons dir: `...\_forever_\Interface\AddOns\` (writable without admin)
- Build **1.60.1.71091**, `## Interface: 16001`, locale enUS. Current build: `Version` column of `C:\Program Files (x86)\World of Warcraft\.build.info`
- Retail-engine client (Mainline family, game type `camelot`/`forever`, `WOW_PROJECT_ID == WOW_PROJECT_CAMELOT == 18`, API close to retail 12.1.5) with Classic-style content
- SavedVariables: `...\_forever_\WTF\Account\<ACCOUNT>\SavedVariables\` (account folder name: `CLAUDE.local.md`, or list `...\WTF\Account\`)
- `...\_forever_\Errors\` holds client crash reports, not addon Lua errors. Addon errors come from ForeverDevKit (below)

## Layout
- `addons/<AddonName>/` - one folder per addon: `<AddonName>.toc`, Lua files, optional XML, `README.md`, optional `tests/smoke.lua` (offline scenario)
- `addons/ForeverDevKit/` - dev aid: saves Lua errors, blocked actions, an event trace and API probe results to SavedVariables. Proven in game
- `addons/AuctionStatFilter/` - first real addon, verified in game; the model for structure, a scenario test and a diagnostic log
- `kb/` - knowledge base: essentials, blueprint, workflow, open questions, and long research references
- `reference/` - read-only checkouts of Blizzard's UI source and API dumps for this build (`forever` branches). Not ours, not versioned; never edit. Recreate with `tools\update-reference.ps1`
- `tools/wowapi.py` - offline API lookup over `reference/`
- `tools/check.ps1` - the offline gate: luacheck (knows every global on Forever), StyLua, TOC and XML validation, Lua 5.1 smoke test plus each addon's scenario
- `tools/new-addon.ps1 -Name Foo -Title "Foo" -Notes "..."` - scaffolds from the house template, registers it in `.luacheckrc`, deploys
- `tools/deploy.ps1` - junctions addons into the game's AddOns folder (edits are live)
- `tools/update-reference.ps1` - run after every client patch
- `tools/bin/` - portable luacheck, StyLua, Lua 5.1; not versioned (download URLs in `kb\03-workflow.md`)

## Workflow: make or change an addon
1. Read the KB pages relevant to the feature; look up every API with `tools\wowapi.py`; read how Blizzard's own UI does it under `reference/`.
2. New addon: `tools\new-addon.ps1`. Follow `kb\02-addon-blueprint.md`.
3. Put the logic in functions on `ns` and cover it with `tests/smoke.lua` (fake the API, assert on results).
4. Run `tools\check.ps1 <Addon> -Fix` until it passes.
5. `tools\deploy.ps1` (idempotent). **New addon or changed TOC: the user must restart the client. Otherwise `/reload`.**
6. Hand off: what the gate verified, what is unverified and needs the game, and numbered steps for the user ending in `/reload` (SavedVariables are only written then; remind them, it is easy to forget).
7. After the user's `/reload`, read `...\SavedVariables\ForeverDevKit.lua` (errors, blocked actions, trace, probes) and the addon's own SavedVariables. Summarise with a short script; never dump these files whole.
8. Record anything learned from the game in the KB (`kb\04-open-questions.md` lists what is still unknown), and update the addon's README status.

## Workflow: fix a bug reported from the game
- Get evidence before changing behaviour: DevKit session, the addon's saved state, a screenshot if the user offers one. If the evidence is not there, add a capped diagnostic log to the addon's SavedVariables (see `debugLog` in AuctionStatFilter) or events to `ns.watchEvents` in `addons/ForeverDevKit/Probes.lua`, and ask for one more run.
- Reproduce in `tests/smoke.lua` first when the cause is logic, then fix, then keep the test.
- Suspect timing before logic: item, spell and quest data that is not cached yet returns partial results, not nil (`kb\01-forever-essentials.md` section 6).
- Take the user's design suggestions seriously; they see the game and you do not.

## Publishing
- Remote: `origin` = `https://github.com/ericosg/wow-forever-addons.git`, branch `main`. GitHub CLI is installed and logged in (path in `CLAUDE.local.md`).
- **Commit and push only when the user asks.** One commit per coherent change, imperative subject, body saying what changed and what was verified in game vs offline.
- Before every commit: `tools\check.ps1` passes, and `git grep` finds no account folder name, character name or GUID in tracked files (this repo is public; use `<ACCOUNT>`, `Firstname Surname`).
- Never commit `reference/`, `tools/bin/`, `CLAUDE.local.md` or anything from `WTF\`.
- Addon versions: bump `## Version` in the TOC when behaviour changes (semver). Releases to CurseForge/Wago are not set up; `kb\research\tooling-and-debugging.md` section 5 covers the packager when wanted.

## Coexistence (applies to every addon here)
Every addon in this repo must work **installed alone, and installed together with any or all of the others**, with no conflict in behaviour, UI or saved data. We will build families of related addons (several for the auction house, for example); a user may install one, some or all. Full rules: `kb\02-addon-blueprint.md`, section "Coexistence". In short:
- **Standalone:** no addon may require another addon from this repo. Use `## OptionalDeps` and feature-detect at run time; never assume load order.
- **No shared names:** SavedVariables, slash commands, named frames, `StaticPopupDialogs` keys, Settings variable IDs, addon-message prefixes and `EventRegistry` event names are all prefixed with the addon's name. `tools\check.ps1` fails on duplicate SavedVariables and slash commands across addons.
- **Shared Blizzard surfaces are shared:** before touching a Blizzard frame, list which of our addons already touch it (`Grep` the frame name under `addons/`). Hook with `hooksecurefunc` / `HookScript` only; never `SetScript` on, replace a method of, or take exclusive ownership of something another addon may also need.
- **Compose, don't overwrite:** when two addons act on the same data (two filters on the auction browse list), they must combine through one shared, versioned mechanism that works with any subset installed. Design that mechanism when the second addon arrives, and migrate the first to it in the same change.
- **UI:** panels attached to the same Blizzard window must stack or dock without overlapping, whichever subset is installed, and look like one family (same templates, fonts, spacing, wording).
- **Verify together:** before hand-off, run `tools\check.ps1` with no arguments (all addons), and ask the user to test with the other addons enabled, not only the new one.

## Rules
- Never modify or delete addons we didn't create (Questie, Blizzard_*). The deploy script only touches junctions it created for folders in `addons/`.
- Don't write to `WTF\` while the game is running (`Get-Process Wow`). Reading is fine.
- Namespace everything via `local ADDON, ns = ...`; no globals except SavedVariables (prefixed with the addon name, declared in the TOC), `SLASH_*`, `BINDING_*`.
- Use `print()` sparingly; gate debug output behind a `/<addon> debug` toggle.
- Treat every unit, aura, cooldown, cast and damage-meter value as possibly secret: pass it to a widget or guard it with `issecretvalue` before any comparison, arithmetic or table-key use.
- Cannot test in game: say so plainly, and state what was verified offline vs. what is unverified.
- Keep a short `README.md` per addon: what it does, slash commands, settings, status.
- Keep the KB true: when the game or the source contradicts a page, fix the page.
- User plays on Windows 11; use PowerShell for scripts.

## Shell notes for this machine
- The Bash tool is Git Bash. Backslashes inside heredocs get mangled (`\0`, `\s`, `\A`): for multi-line edits use the Edit/Write tools, or write a script file and run it, not an inline heredoc with Windows paths.
- Run the gate from bash as `powershell -NoProfile -ExecutionPolicy Bypass -File tools/check.ps1 ...`.
- A command the user runs with the `!` prefix goes through bash and the session's original PATH; newly installed programs need their full path.

## Addon ideas / backlog
- Coexistence debt: AuctionStatFilter currently owns `AuctionHouseFrame.BrowseResultsFrame.browseResults` and the dock position right of the auction house by itself. Before a second addon filters the browse list or docks a panel there, build the shared mechanism described in `kb\02-addon-blueprint.md` ("Coexistence") and move AuctionStatFilter onto it.
- AuctionStatFilter: more stats ("Equip:" effects such as attack power and spell power, armor), a price cap, saved presets. Offered to the user 2026-11-25; none chosen yet.
