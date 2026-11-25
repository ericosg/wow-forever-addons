# WoW Forever addon workspace

Goal: build a series of custom addons for the **WoW Forever** client. Each addon is its own folder under `addons/`.

## Read first

**`kb/README.md`, then `kb/01-forever-essentials.md`, before writing any addon code.** What you remember about WoW addon APIs describes other clients and is wrong for this one in specific ways: legacy globals (`GetSpellInfo`, `UnitAura`, `IsAddOnLoaded`...) do not exist, secret values make combat data unreadable, there is no combat log for addons, and names have surnames instead of realms.

Never write an API call from memory. Look it up:

```powershell
python tools\wowapi.py C_Spell.GetSpellInfo   # signature, returns, secret flags (see kb\03-workflow.md)
```

## Target client (verified 2026-11-25)
- Install: `C:\Program Files (x86)\World of Warcraft\_forever_\` (launcher product `wowf`)
- Addons dir: `...\_forever_\Interface\AddOns\` (writable without admin)
- Build **1.60.1.71091**, `## Interface: 16001`, locale enUS. Current build: `Version` column of `C:\Program Files (x86)\World of Warcraft\.build.info`
- Retail-engine client (Mainline family, game type `camelot`/`forever`, `WOW_PROJECT_ID == WOW_PROJECT_CAMELOT == 18`, API close to retail 12.1.5) with Classic-style content
- SavedVariables: `...\_forever_\WTF\Account\<ACCOUNT>\SavedVariables\`. The account folder name for this machine is in `CLAUDE.local.md` (not versioned); otherwise list `...\_forever_\WTF\Account\`
- `...\_forever_\Errors\` holds client crash reports, not addon Lua errors. Addon errors come from ForeverDevKit (below)

## Layout
- `addons/<AddonName>/` - one folder per addon: `<AddonName>.toc`, Lua files, optional XML, `README.md`
- `addons/ForeverDevKit/` - dev aid: saves Lua errors, blocked actions and API probe results to SavedVariables
- `kb/` - knowledge base: essentials, blueprint, workflow, open questions, and long research references
- `reference/` - read-only checkouts of Blizzard's UI source and API dumps for this build (`forever` branches). Not ours; never edit. Recreate with `tools\update-reference.ps1`
- `tools/wowapi.py` - offline API lookup over `reference/`
- `tools/check.ps1` - the offline gate: luacheck (knows every global on Forever), StyLua, TOC and XML validation, Lua 5.1 smoke test
- `tools/new-addon.ps1 -Name Foo -Title "Foo" -Notes "..."` - scaffolds from the house template, registers it in `.luacheckrc`, deploys
- `tools/deploy.ps1` - junctions addons into the game's AddOns folder (edits are live)
- `tools/update-reference.ps1` - run after every client patch
- `tools/bin/` - portable luacheck, StyLua, Lua 5.1 (download URLs in `kb\03-workflow.md`)

## Workflow
1. Read the KB pages relevant to the feature; look up every API with `tools\wowapi.py`.
2. Scaffold with `tools\new-addon.ps1`; write the addon following `kb\02-addon-blueprint.md`.
3. Run `tools\check.ps1 <Addon>` until it passes.
4. `tools\deploy.ps1` (idempotent). New addon or changed TOC: the user must restart the client. Otherwise `/reload`.
5. Hand off: say what the gate verified, what is unverified and needs the game, and what the user should do.
6. After the user's `/reload`, read `...\SavedVariables\ForeverDevKit.lua` for errors, blocked actions and probe results (`kb\03-workflow.md` section 5).
7. Record anything learned from the game in the KB (`kb\04-open-questions.md` lists what is still unknown).

## Rules
- Never modify or delete addons we didn't create (Questie, Blizzard_*). The deploy script only touches junctions it created for folders in `addons/`.
- Don't write to `WTF\` while the game is running (`Get-Process Wow`). Reading is fine.
- Namespace everything via `local ADDON, ns = ...`; no globals except SavedVariables (prefixed with the addon name, declared in the TOC), `SLASH_*`, `BINDING_*`.
- Use `print()` sparingly; gate debug output behind a `/<addon> debug` toggle.
- Treat every unit, aura, cooldown, cast and damage-meter value as possibly secret: pass it to a widget or guard it with `issecretvalue` before any comparison, arithmetic or table-key use.
- Cannot test in game: say so plainly, and state what was verified offline vs. what is unverified.
- Keep a short `README.md` per addon: what it does, slash commands, settings.
- Keep the KB true: when the game or the source contradicts a page, fix the page.
- User plays on Windows 11; use PowerShell for scripts.

## Addon ideas / backlog
(user fills in; add as we go)
