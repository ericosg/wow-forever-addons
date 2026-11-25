# Addon blueprint

How addons in this workspace are built. `addons/ForeverDevKit` follows these rules and is the smallest working example. Signatures and longer examples for everything named here are in [research/modern-api-patterns.md](research/modern-api-patterns.md); grep it by heading.

## Layout

```
addons/Foo/
  Foo.toc          UTF-8 without BOM, LF
  Foo.lua          bootstrap: namespace, SavedVariables, events, slash command
  <Feature>.lua    one file per feature once Foo.lua passes ~300 lines
  Locales/enUS.lua only when there are user-facing strings worth translating
  README.md        what it does, slash commands, settings
```

Scaffold with `tools\new-addon.ps1 -Name Foo -Title "Foo" -Notes "..."`. It also registers the addon's globals in `.luacheckrc`.

TOC essentials:

```
## Interface: 16001
## Title: Foo
## Notes: One line for the addon list.
## Author: Eric
## Version: 0.1.0
## Category: <existing category>
## IconTexture: Interface\AddOns\Foo\icon.png
## SavedVariables: FooDB
## SavedVariablesPerCharacter: FooCharDB
## AddonCompartmentFunc: Foo_OnCompartmentClick
```

A single-client addon needs no `_Forever` suffix and no `AllowLoadGameType`. Files load top to bottom; XML `<Script>` runs where it is encountered. File paths in the TOC must match the on-disk case exactly.

## Code rules

1. **`local ADDON, ns = ...` at the top of every file.** State and functions shared between files live on `ns`. The only globals an addon may create are its SavedVariables, `SLASH_*`, `BINDING_*`, and functions named by TOC directives (`AddonCompartmentFunc`). `tools\check.ps1` fails on anything else.
2. **Nothing but definitions at file scope.** Read SavedVariables in `ADDON_LOADED` (compare the name, then unregister). Read player data from `PLAYER_LOGIN`. `PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)` fires on every loading screen.
3. **One event frame per addon, table dispatch:** `events[event](...)`. Use `RegisterUnitEvent` for `UNIT_*`. Unregister what a disabled feature does not need.
4. **SavedVariables:** type-check on load, merge defaults without overwriting user values, keep a `version` field and write numbered migrations. Never store API returns from combat without an `issecretvalue` guard. Key per-character data by `UnitGUID("player")`.
5. **Feature-detect by calling, not by namespace existence** (see essentials 2.5). Cross-client shims are unnecessary here: this workspace targets Forever only.
6. **Protected frames:** check `InCombatLockdown()` before `Show`/`Hide`/`SetPoint`/`SetAttribute`/`SetParent` on secure frames or anything anchored into them; queue the change and apply on `PLAYER_REGEN_ENABLED`.
7. **Never write into Blizzard tables or replace Blizzard functions.** Observe with `hooksecurefunc(table, "Method", fn)` or `frame:HookScript`. Taint from an addon makes Blizzard's own secret-value code fail, and the error names your addon.
8. **Secrets:** follow essentials 2.2 for every unit, aura, cooldown, cast and meter value. Give secret-bearing widgets their own leaf frames; do not anchor layout to them or measure them.
9. **Output:** one `ns.Print`, and `ns.Debug` gated on `ns.db.debug` (`/foo debug`). No chat spam at login. Check the flag before building the message in hot paths.
10. **Performance:** events over `OnUpdate`; debounce bursty events (`BAG_UPDATE_DELAYED`, `UNIT_AURA`, `QUEST_LOG_UPDATE`) with a dirty flag and `C_Timer.After`; do nothing while the frame is hidden; no table or closure creation per frame; pool frames or use ScrollBox for lists.
11. **Style:** tabs, double quotes, 140 columns (StyLua enforces). Names say what a thing is. Comments explain why, never restate the code.

## Which API for which job

| Need | Use | Not |
|---|---|---|
| Options panel | `Settings.RegisterVerticalLayoutCategory` + `Settings.RegisterAddOnSetting(category, "Foo_Key", "key", FooDB, type, label, default)` + `Settings.CreateCheckbox/Slider/Dropdown`, then `Settings.RegisterAddOnCategory`. Open with `Settings.OpenToCategory(category:GetID())` | `InterfaceOptions_AddCategory`, AceConfig for small addons |
| Context / dropdown menu | `MenuUtil.CreateContextMenu(owner, function(owner, root) root:CreateButton(...) end)`; `Menu.ModifyMenu` to extend Blizzard menus | `UIDropDownMenu_*`, `EasyMenu` |
| Scrolling list | `CreateDataProvider` + `ScrollUtil.InitScrollBoxListWithScrollBar` | `FauxScrollFrame`, `HybridScrollFrame` |
| Tooltip additions | `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, fn)` | `OnTooltipSetItem` scripts |
| Addon list / minimap entry | TOC `AddonCompartmentFunc` (+ `IconTexture`) | a custom minimap button, unless asked |
| Delay / repeat | `C_Timer.After`, `C_Timer.NewTicker`, `RunNextFrame` | bare `OnUpdate` counters |
| Item / spell data that may not be cached | `Item:CreateFromItemID(id):ContinueOnItemLoad(fn)`, `Spell:CreateFromSpellID(id):ContinueOnSpellLoad(fn)` | polling `C_Item.GetItemInfo` |
| Custom events between modules | `EventRegistry:RegisterCallback` / `TriggerEvent`, or a `CallbackRegistryMixin` on `ns` | globals |
| Popup confirmation | `StaticPopupDialogs["FOO_CONFIRM"]` + `StaticPopup_Show` | custom modal frames |
| Movable frame | save `point, x, y` on `OnDragStop`, `SetClampedToScreen(true)`; consider LibEditMode only if several frames need Edit Mode | `SetUserPlaced` |
| Player names | `UnitNameUnmodified` + `NameUtil` helpers, GUID keys | `Name-Realm` string handling |
| Serialising / sharing data | `C_EncodingUtil` (CBOR, JSON, Deflate, Base64) | bundling LibDeflate / LibSerialize |

Verify each in `reference/` before first use; Blizzard's own callers are the best examples (`Grep` for the function name under `reference/wow-ui-source/Interface/AddOns`).

## Coexistence

Every addon here must work installed alone and installed together with any combination of the others. Related addons will share a Blizzard window (several auction house addons are planned), which is where conflicts come from. Treat "what else of ours touches this?" as a design question for every feature.

**Independence**

- No addon requires another addon from this repo. If one can use another, declare `## OptionalDeps: Other` and test `C_AddOns.IsAddOnLoaded("Other")` at run time; the feature must degrade cleanly when it is absent.
- Never rely on load order between our addons. Alphabetical order changes when an addon is renamed or added.
- No file is shared between addon folders. Each folder is installable by copying it alone.

**Names**

Anything that lives in a shared namespace carries the addon's name: SavedVariables (`FooDB`), slash commands (`/foo`; check the others in `.luacheckrc` for clashes on short forms), named frames (`FooPanel`), `StaticPopupDialogs["FOO_CONFIRM"]`, Settings variable IDs (`"Foo_Enabled"`), addon-message prefixes, `EventRegistry` event names (`"Foo.Changed"`), keybinding names (`BINDING_NAME_FOO_TOGGLE`). `tools\check.ps1` fails when two addons declare the same SavedVariable or slash command.

**Shared Blizzard surfaces**

- Find existing users first: `Grep` the Blizzard frame or function name under `addons/`.
- Hooks must stack: `hooksecurefunc` and `HookScript` only. Never `SetScript` on a Blizzard frame, replace a Blizzard method, or call `UnregisterAllEvents` on something you did not create.
- A hook must tolerate other hooks having run before or after it. Do not keep a private copy of Blizzard state and write it back later (that erases whatever another addon did in between) unless the addon is the registered owner of that state under the shared mechanism below.
- Do not change shared settings as a side effect: CVars, Blizzard's saved filters and sort order, tooltip anchors, frame strata of Blizzard frames.

**Composing behaviour**

When two addons need to act on the same thing, neither may own it outright. They combine through one small shared component that:

- is embedded in every addon that needs it (the `LibStub` pattern: each copy registers a version, the newest wins, so any subset of addons carries a working copy);
- lets each addon register its contribution (a filter predicate, a column, a docked panel) and unregister it;
- applies all contributions in one place, in a defined order, with one refresh.

For the auction browse list this means: one shared "browse filter" library holds the unfiltered results and the hooks, and each addon registers a predicate; a row is shown when every registered predicate accepts it. Build this when the second such addon is written, and move the first addon onto it in the same change. Until then the single existing addon may own the surface, and the debt is listed in the `CLAUDE.md` backlog.

**UI**

- Panels attached to the same Blizzard window dock through a shared layout (same library): each registers its frame, and they stack in a stable order with no overlap, whichever subset is installed. A lone addon looks complete on its own.
- One visual family: the same templates, fonts, padding, button sizes and wording ("Clear All", "Press Search to apply") across related addons. Copy from the existing addon rather than inventing.
- One interaction model per window: if one auction addon applies on Search, they all do.
- Never cover Blizzard controls or another addon's panel; never steal keyboard focus on show.
- Chat output is prefixed with the addon's own name, so the user can tell which addon spoke.

**Checks before hand-off**

- `tools\check.ps1` with no arguments: every addon, plus the cross-addon name check.
- Scenario tests for a shared component cover: addon A alone, addon B alone, both in either load order.
- Ask the user to test with all of our addons enabled, and once with only the new one.

## Libraries

Default to none. The client now ships most of what Ace3-era libraries provided (settings, menus, serialisation, callbacks, timers). Bring in a library only when it replaces a lot of risky code: LibDataBroker/LibDBIcon for a broker display, AceDB for real profile support, LibEditMode for Edit Mode integration, ChatThrottleLib for heavy addon comms. Embed under `Libs/` (excluded from lint and formatting), list `LibStub` first, and confirm the library's TOC or source mentions 16001 or is version-agnostic.

## UI construction

Prefer Lua over XML for small UIs (one language, lintable). Use XML when defining reusable templates or intrinsic-heavy layouts; start each file with the header in research/tooling-and-debugging.md section 6.3 so `check.ps1` validates it against Blizzard's schema. Use Blizzard templates and atlases so the addon matches the client: look up template names in `reference/BlizzardInterfaceResources/Resources/Templates.lua` and atlas names in `AtlasInfo.lua`. Frames that need a backdrop inherit `BackdropTemplate`.

## Review checklist before hand-off

- [ ] Every API call looked up with `tools/wowapi.py`; none from memory alone.
- [ ] Secret-capable values never compared, computed on, or used as keys without a guard.
- [ ] No protected action reachable in combat without deferral.
- [ ] SavedVariables survive: fresh install, existing data from the previous version, hand-corrupted values.
- [ ] Works with the feature's frame hidden, on `/reload` mid-combat, and at login before data is cached.
- [ ] No global leaks, no chat spam, debug output gated.
- [ ] README lists slash commands and settings.
- [ ] `tools\check.ps1` passes; hand-off states what was and was not verified.
