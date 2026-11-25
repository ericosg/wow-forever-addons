# Modern addon framework APIs and idioms for WoW Forever (1.60.1, Interface 16001)

Researched 2026-11-25. Target: WoW Forever 1.60.1, TOC `16001`, Lua 5.1, UI API roughly retail 12.1.5.

## How to read this file

Every claim carries one of these evidence tags:

- **[SRC]** read directly in Blizzard's UI source for this client: `Gethe/wow-ui-source`, branch `forever`, commit `c01a87b`, version `1.60.1.71091` (the installed client is build 71037, 54 builds older; treat as the same API). Browse at <https://github.com/Gethe/wow-ui-source/tree/forever>. Paths below are relative to `Interface/AddOns/`.
- **[DOC]** taken from the generated API documentation in that same branch (`Blizzard_APIDocumentationGenerated/*.lua`). These are the exact signatures for this client.
- **[WIKI]** from warcraft.wiki.gg (page linked inline).
- **[UNVERIFIED]** general addon knowledge that was not confirmed against the Forever source or wiki in this pass. Feature-detect or test before relying on it.

Nothing here was tested in game.

### The five facts that override old tutorials

1. **Forever is a Mainline-family client.** Blizzard: "Forever and modern WoW (Midnight) are two game types within the Mainline code family: Camelot ... and Standard". Game type is `camelot`, with `forever` accepted as an alias since build 70291. [WIKI] <https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes/notes>
2. **Secret values and addon restrictions are active in Forever.** "The addon disarmament changes introduced in Midnight, including secrets, will also be active in Forever." (same page). Combat data can be unreadable by addon code. See section 9.
3. **The 11.x deprecation shims are gone.** `GetSpellInfo`, `GetItemInfo`, `UnitAura`/`UnitBuff`, `GetContainerItemInfo`, `IsAddOnLoaded`, `GetAddOnMetadata`, `GetMouseFocus`, `InterfaceOptions_AddCategory`, `EasyMenu` have no Lua definition anywhere in the Forever source, and Blizzard's own code never calls them bare. [SRC] Use the `C_*` forms in section 11.
4. **`COMBAT_LOG_EVENT_UNFILTERED` cannot be registered by addons** (errors on register since 12.0.0). [WIKI] <https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes>
5. **Classic-era API names mostly do not apply**, even though the game looks like Classic. A few Classic-style systems do exist under new names (`C_SkillInfo`, `C_PetInfo.GetPetHappiness`). Always feature-detect.

Detecting the client [WIKI] <https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes>:

```lua
local IS_FOREVER = WOW_PROJECT_ID == WOW_PROJECT_CAMELOT   -- WOW_PROJECT_CAMELOT == 18
-- or by interface number
local tocVersion = select(4, GetBuildInfo())               -- 16001
local isForever = tocVersion > 16000 and tocVersion < 20000
```

---

## 1. TOC file format

Reference: [WIKI] <https://warcraft.wiki.gg/wiki/TOC_format>. Real examples: every `*.toc` in the source branch, and the working local `Questie_Forever.toc`.

### Basics

- File is `Interface\AddOns\<Name>\<Name>.toc`; folder and TOC base name must match.
- `## Directive: Value` is a directive. A line starting with a single `#` is a comment. Anything else is a file path (Lua or XML only), loaded top to bottom.
- Whitespace around directive values is trimmed. **Only the first 1024 characters of a line are read**; the rest is silently dropped. [WIKI]
- A repeated directive: the last one wins, except list directives (`Dependencies`, `SavedVariables`, ...) which append. [WIKI]
- New files and new addons are picked up by `/reload` (since 9.0.1). Renaming or deleting an already-loaded TOC needs a client restart. [WIKI]
- **Encoding and line endings:** the wiki does not specify. Observed convention: UTF-8 **without BOM**, LF line endings. Both Blizzard's TOCs and the working Questie TOC (which has non-ASCII localized `Notes-koKR` etc.) start with `## ` bytes `23 23 20` and contain no CR. [SRC] Whether a BOM or CRLF breaks parsing is [UNVERIFIED]; write UTF-8 no BOM. On Windows PowerShell 5.1, `Out-File`/`>` add a BOM, so write TOC files with a tool that does not.
- Paths may use `\` or `/`; the wiki recommends backslashes, especially inside XML `<Include>`.

### Minimal Forever TOC

```
## Interface: 16001
## Title: MyAddon
## Notes: One line shown in the AddOn list tooltip
## Author: Me
## Version: 1.0.0
## Category: Quests
## IconTexture: Interface\AddOns\MyAddon\icon.png
## SavedVariables: MyAddonDB
## SavedVariablesPerCharacter: MyAddonCharDB
## AddonCompartmentFunc: MyAddon_OnAddonCompartmentClick

Locales\enUS.lua
Locales\[TextLocale].lua
Core.lua
Options.lua
```

### Directives that matter

| Directive | Notes |
|---|---|
| `Interface` | One number per client. **Comma lists allowed since 10.2.7**: `## Interface: 120105, 16001, 50504, 11509`. Mismatch marks the addon out of date. Current: Forever `16001`, Midnight `120105`, Mists `50504`, TBC `20506`, Vanilla `11509`. |
| `Title`, `Notes` | Shown in the AddOn list. Colour escapes allowed. Localize with a suffix: `## Title-frFR: ...`. The unsuffixed fallback must come first. |
| `Category` (11.1.0) | Collapsible AddOn list header. Localizable (`Category-deDE`). Use the standard names from <https://warcraft.wiki.gg/wiki/Addon_Categories> where possible. |
| `Group` (11.1.0) | Name of the "main" addon to nest this one under. No nested groups. |
| `IconTexture`, `IconAtlas` (10.1.0) | AddOn list and Addon Compartment icon. `IconTexture` wins if both are set. |
| `SavedVariables` | Account-wide globals, comma separated, saved to `WTF\Account\<acct>\SavedVariables\<Addon>.lua`. |
| `SavedVariablesPerCharacter` | Per-character globals, saved under `WTF\Account\<acct>\<realm>\<char>\SavedVariables\`. |
| `LoadSavedVariablesFirst: 1` (11.1.5) | Loads saved variables **before** any addon file runs, so file-scope code can read them. Cannot be turned off later in the file. Questie uses it. |
| `Dependencies` | Must load first; addon will not load if missing. Aliases: `RequiredDeps`, and any word starting with `Dep` (Blizzard uses `## Dep:`). |
| `OptionalDeps` | Load first if present. |
| `LoadOnDemand: 1` | Not loaded at login; load with `C_AddOns.LoadAddOn`. |
| `LoadWith` | Load this addon when any listed addon loads. Implies LoadOnDemand. |
| `LoadManagers` | If any listed addon is present, this addon becomes LoadOnDemand (the manager loads it). |
| `DefaultState: disabled` | User must enable it manually. |
| `AddonCompartmentFunc`, `AddonCompartmentFuncOnEnter`, `AddonCompartmentFuncOnLeave` (10.1.0) | Names of **global** functions. Present in Forever. See section 7. |
| `AllowLoadGameType` | Comma list of game types or families. Values: `standard`, `forever`, `camelot`, `mists`, `cata`, `wrath`, `tbc`, `vanilla`, `plunderstorm`, `wowhack`; families `mainline` (standard, forever, camelot, plunderstorm, wowhack) and `classic` (vanilla, tbc, wrath, cata, mists). |
| `ExcludeLoadGameType` (12.0.0) | Inverse. |
| `AllowAddOnTableAccess: 1` (11.1.7) | Lets other code fetch your private `ns` table via `C_AddOns.GetAddOnLocalTable(name)`. |
| `OnlyBetaAndPTR: 1` | Loads only on test clients. |
| `Author`, `Version`, `X-Anything` | Free metadata, read with `C_AddOns.GetAddOnMetadata(name, field)`. |

Restricted to Blizzard (ignored or inoperable for third-party addons): `AllowLoad`, `LoadFirst`, `UseSecureEnvironment`, `SavedVariablesMachine`, `EscalateErrorDuringLoad`, and the inline `AllowLoadEnvironment` / `LoadIntoEnvironment`. [WIKI]

### Inline conditionals and path variables (11.1.5+)

Inline directives go in square brackets, usually at the end of a line. They work on file lines and, since 12.0.7, on `##` directive lines.

```
Core.lua
ForeverOnly.lua       [AllowLoadGameType forever][ExcludeLoadGameType standard, classic]
RetailOnly.lua        [AllowLoadGameType standard]
ClassicFamily.lua     [AllowLoadGameType classic]
FrenchOnly.lua        [AllowLoadTextLocale frFR]

# variables expand anywhere in a file path
[Family]\Compat.lua            # Mainline\Compat.lua on Forever
[Game]\Overrides.lua           # Camelot\Overrides.lua on Forever (see gotcha)
Locales\[TextLocale].lua       # Locales\enUS.lua
```

- `[Family]` is `Mainline` or `Classic`. **On Forever it is `Mainline`.**
- `[Game]` is `Standard`, `Camelot`, `Vanilla`, `TBC`, `Wrath`, `Mists`... On Forever, Blizzard's own TOCs use `[Game]\File.lua [AllowLoadGameType camelot]` and the folders are named `Camelot`. The official notes say `Forever` is accepted as an alias "in the `[Game]` variable, and in game-type folder lookup". Safest: name the folder `Camelot` or avoid `[Game]` and use explicit paths with `AllowLoadGameType`.
- `[TextLocale]` (11.2.0) is the `GetLocale()` value. `[RegionalTextLocale]` (12.1.7 and Forever) distinguishes `enGB`/`ptPT` from `enUS`/`ptBR`.
- Variables inside `##` directive values were allowed in 12.0.7 and "prevented" in 12.1.7 per the wiki's history list; yet the wiki's own 1.60.1 example uses `## X-Game: [Game]`. Treat variables in directives as [UNVERIFIED] on Forever.
- **Gotcha:** if `AllowLoadGameType` lists only types the running client does not recognise, the condition counts as satisfied. Older clients do not know `forever`. For a multi-client addon always pair it: `[AllowLoadGameType forever][ExcludeLoadGameType standard, classic]`. [WIKI]
- `[Bootstrap]` (12.1.0, Midnight and Forever) marks files that run during the bootstrap phase of a LoadOnDemand addon. Rarely needed.

### Flavor-suffixed TOC files and precedence

The client looks for the most specific TOC first, then falls back to `<Name>.toc`:

1. Game-specific suffix: `MyAddon_Forever.toc` or `MyAddon_Camelot.toc` (also `_Standard`, `_Mists`, `_Cata`, `_Wrath`, `_TBC`, `_Vanilla`).
2. Family suffix: `MyAddon_Mainline.toc` (Forever is Mainline) or `MyAddon_Classic.toc`.
3. `MyAddon.toc`.

Game suffix beats family suffix. [WIKI] For a Forever-only addon a single `MyAddon.toc` with `## Interface: 16001` is enough. The wiki recommends a comma `Interface` list plus inline conditionals over multiple TOC files. Questie ships both `Questie_Forever.toc` and `Questie_Camelot.toc`.

**Trap:** `_Mainline.toc` is also what retail Midnight loads. A file written for Forever under that name will load on retail.

### Lua module `import` (new, Mainline)

Files may `return` a value, and other files can fetch it with `import("Addon.Path.File")` (renamed from `require` during the 1.60.1 beta). It only references modules already loaded; it does not load anything. Cross-addon imports need a declared `Dep`/`OptionalDeps`. [WIKI] <https://warcraft.wiki.gg/wiki/API_import>. Not available on Classic-family clients, so the `local ADDON, ns = ...` namespace remains the portable pattern and the one this workspace uses.

---

## 2. Addon lifecycle and events

References: [WIKI] <https://warcraft.wiki.gg/wiki/AddOn_loading_process>, [DOC] `AddOnsDocumentation.lua`, [SRC] `Blizzard_SharedXML/EventUtil.lua`, `Blizzard_SharedXMLBase/GlobalCallbackRegistry.lua`, `CallbackRegistry.lua`, `Event.lua`.

### Order

1. Blizzard addons load, then third-party addons alphabetically, adjusted by dependencies.
2. Per addon: files run in TOC order (XML `<Script file>` / `<Include>` run when encountered). Then saved variables are loaded (or before all files with `LoadSavedVariablesFirst: 1`).
3. `ADDON_LOADED(addOnName, containsBindings)` fires for that addon. **Earliest safe point to read SavedVariables.** It fires for every addon, so compare the name.
4. `PLAYER_LOGIN()` fires once per login or reload, before the first `PLAYER_ENTERING_WORLD`. Most player data is available. Good for one-time setup.
5. `PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)` fires on **every** loading screen (login, reload, instance transitions).
6. If the player is already in combat on reload, `PLAYER_REGEN_DISABLED` fires after that. `SPELLS_CHANGED` follows when the spellbook is ready.
7. Logout: `PLAYER_LEAVING_WORLD` (also fires before any loading screen), `PLAYER_LOGOUT()` (last chance to edit SavedVariables), `ADDONS_UNLOADING(closingClient)`. Nothing fires on a crash or Alt-F4, and saved variables are not written.

`VARIABLES_LOADED` is unreliable for addon init (since 3.0.2). `SAVED_VARIABLES_TOO_LARGE(addOnName)` fires if the file could not be loaded for memory reasons.

Fixed during the Forever beta: `UnitName("player")` used to return `"Unknown"` before `PLAYER_LOGIN`. Still, read player identity at `PLAYER_LOGIN`, not at file scope. [WIKI]

### Canonical bootstrap

```lua
local ADDON, ns = ...

local defaults = { version = 1, enabled = true }

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_LOGOUT")
f:SetScript("OnEvent", function(self, event, ...)
    local handler = ns[event]
    if handler then return handler(ns, ...) end
end)

function ns:ADDON_LOADED(name)
    if name ~= ADDON then return end
    f:UnregisterEvent("ADDON_LOADED")
    MyAddonDB = MyAddonDB or {}
    for k, v in pairs(defaults) do
        if MyAddonDB[k] == nil then MyAddonDB[k] = v end
    end
    ns.db = MyAddonDB
end

function ns:PLAYER_LOGIN()
    -- UnitName, UnitClass, bags, quest log are usable here
end

function ns:PLAYER_LOGOUT()
    -- strip transient data from ns.db before it is written
end
```

### C_AddOns (all [DOC], this client)

```
C_AddOns.IsAddOnLoaded(name)            -> loadedOrLoading, loaded      -- TWO returns
C_AddOns.LoadAddOn(name)                -> loaded?, value?              -- value is the failure reason string
C_AddOns.GetAddOnMetadata(name, field)  -> value
C_AddOns.GetAddOnInfo(name)             -> name, title, notes, loadable, reason, security
C_AddOns.GetAddOnEnableState(name, character="0") -> Enum.AddOnEnableState
C_AddOns.EnableAddOn(name, character="0")  /  C_AddOns.DisableAddOn(name, character="0")
C_AddOns.IsAddOnLoadOnDemand(name)      -> bool
C_AddOns.IsAddOnLoadable(name, character="0", demandLoaded=false) -> loadable, reason
C_AddOns.DoesAddOnExist(name)           -> bool
C_AddOns.GetNumAddOns() / GetAddOnName(index) / GetAddOnTitle(name) / GetAddOnNotes(name)
C_AddOns.GetAddOnDependencies(name) / GetAddOnOptionalDependencies(name)
C_AddOns.GetAddOnInterfaceVersion(name) -> number
C_AddOns.GetAddOnLocalTable(name)       -> table   -- needs AllowAddOnTableAccess: 1 in that addon's TOC
C_AddOns.SaveAddOns()
```

`name` accepts the folder name or a 1-based index. The bare globals (`IsAddOnLoaded`, `LoadAddOn`, `GetAddOnMetadata`, `EnableAddOn`) do not exist in Lua on this client. [SRC]

```lua
local version = C_AddOns.GetAddOnMetadata(ADDON, "Version")

local _, loaded = C_AddOns.IsAddOnLoaded("Questie")   -- second return = fully loaded
if not loaded then
    local ok, reason = C_AddOns.LoadAddOn("Blizzard_Collections")
end
```

### EventUtil helpers [SRC] `Blizzard_SharedXML/EventUtil.lua`

```
EventUtil.ContinueOnAddOnLoaded(addOnName, callback)   -- runs now if already loaded, else once on its ADDON_LOADED
EventUtil.ContinueOnPlayerLogin(callback)              -- runs now if IsLoggedIn()
EventUtil.ContinueOnVariablesLoaded(callback)
EventUtil.ContinueAfterAllEvents(callback, ...)        -- once every listed event has fired at least once
EventUtil.RegisterOnceFrameEventAndCallback(event, callback, ...)  -- extra args must match the payload
```

```lua
EventUtil.ContinueOnAddOnLoaded(ADDON, function()
    MyAddonDB = MyAddonDB or {}
end)
```

This is the form Blizzard's own Settings readme uses. It is fine for init; it does not replace a frame for ongoing events.

### EventRegistry and CallbackRegistryMixin [SRC]

`EventRegistry` is a global `CallbackRegistryMixin` instance. It can also relay real frame events:

```
EventRegistry:RegisterFrameEventAndCallback(frameEvent, func, owner, ...)            -> owner
EventRegistry:RegisterFrameEventAndCallbackWithHandle(frameEvent, func, owner, ...)  -> handle  (handle:Unregister())
EventRegistry:UnregisterFrameEventAndCallback(frameEvent, owner)
EventRegistry:RegisterCallback(event, func, owner, ...)      -- named UI events such as "EditMode.Enter"
EventRegistry:UnregisterCallback(event, owner)
EventRegistry:TriggerEvent(event, ...)
```

Callback argument order depends on how you register:

- With no extra args: `func(owner, ...eventArgs)`.
- With extra args: `func(owner, extraArgs..., ...eventArgs)` (it is wrapped by `GenerateClosure(func, owner, ...)`).
- `owner` may be any non-number value; if nil a unique ID is generated and returned. One callback per `(event, owner)`; registering again replaces it.

```lua
EventRegistry:RegisterFrameEventAndCallback("PLAYER_REGEN_ENABLED", function(owner)
    ns:FlushCombatQueue()
end, ns)

-- Useful Blizzard UI events delivered through EventRegistry (not frame events):
EventRegistry:RegisterCallback("EditMode.Enter", function() ns:ShowMover() end, ns)
EventRegistry:RegisterCallback("EditMode.Exit",  function() ns:HideMover() end, ns)
```

Make your own registry for internal messaging:

```lua
local Bus = CreateFromMixins(CallbackRegistryMixin)
Bus:OnLoad()
Bus:GenerateCallbackEvents({ "SettingChanged", "DataReady" })   -- populates Bus.Event.SettingChanged etc.
Bus:RegisterCallback("SettingChanged", function(owner, key, value) end, ns)
Bus:TriggerEvent("SettingChanged", "scale", 1.2)
```

`TriggerEvent` errors on an event name that was not generated, unless `Bus:SetUndefinedEventsAllowed(true)`.

### Frame-less event callbacks (12.0.0+) [DOC] `FrameScriptDocumentation.lua`, [SRC] `Blizzard_SharedXMLBase/Event.lua`

```
RegisterEventCallback(eventName, callback)
RegisterUnitEventCallback(eventName, callback, unit)
UnregisterEventCallback(eventName, callback)
UnregisterUnitEventCallback(eventName, callback, unit)
frame:RegisterEventCallback(eventName, cb) -> registered
frame:RegisterUnitEventCallback(eventName, cb, ...units) -> registered
C_EventUtils.IsEventValid(eventName) -> bool
C_EventUtils.IsCallbackEvent(eventName) -> bool
```

Blizzard's wrapper, which shows the calling convention (the callback receives a nil owner first):

```lua
-- Blizzard_SharedXMLBase/Event.lua
local handle = Event.RegisterCallback("PLAYER_REGEN_ENABLED", function(...) end)
handle:Unregister()
local h2 = Event.RegisterUnitCallback("UNIT_HEALTH", function(unit) end, "player")
```

Raw global usage in Blizzard code: `RegisterEventCallback("SOME_EVENT", function(_nilOwner, arg1) ... end)`. All of these are marked `SecretArguments = "AllowedWhenUntainted"`, which only concerns passing secret values. Whether addon (tainted) code hits any other restriction calling them is [UNVERIFIED]; the classic frame + `OnEvent` pattern is the proven path.

### RegisterUnitEvent

```
frame:RegisterUnitEvent(eventName, unit1 [, unit2 ...]) -> registered    [DOC]
```

Filters `UNIT_*` events in C, which is far cheaper than an `if unit ~= "player" then return end` in Lua. Calling it again for the same event **replaces** the unit list. [UNVERIFIED for unit count limit; historically two units, the current doc declares a variadic list.]

```lua
f:RegisterUnitEvent("UNIT_AURA", "player", "target")
```

Registering a non-existent event name raises an error. Guard events that differ per client: `if C_EventUtils.IsEventValid("FOO") then f:RegisterEvent("FOO") end`.

---

## 3. Mixins, templates, textures, fonts, layering

### Mixins [DOC]/[SRC] `Blizzard_SharedXMLBase/Mixin.lua`

```
Mixin(object, ...mixins)            -> object        -- copies keys, later mixins win
CreateFromMixins(...mixins)         -> new table
CreateAndInitFromMixin(mixin, ...)  -> object        -- CreateFromMixins(mixin) then object:Init(...)
```

`Mixin` and `CreateFromMixins` are now C functions. They copy, they do not inherit: changing the mixin table later does not affect existing objects.

```lua
local CounterMixin = {}
function CounterMixin:Init(start) self.n = start or 0 end
function CounterMixin:Bump() self.n = self.n + 1; return self.n end

local c = CreateAndInitFromMixin(CounterMixin, 10)

-- on a frame
local RowMixin = {}
function RowMixin:OnLoad() self:RegisterForClicks("AnyUp") end
function RowMixin:SetData(data) self.Text:SetText(data.name) end

local row = Mixin(CreateFrame("Button", nil, UIParent), RowMixin)
row:OnLoad()
```

Keep mixins on `ns`. A mixin only needs to be a global if XML refers to it by name (`mixin="MyAddonRowMixin"`), since XML resolves names in `_G`.

### XML vs pure Lua

Pure Lua is enough for almost everything and keeps everything in `ns`. Use XML when you need:

- a **named virtual template** to hand to `CreateFrame(type, name, parent, "MyTemplate")`, a frame pool, or a ScrollBox element initializer (ScrollBox reads the template's size to compute extents);
- `Bindings.xml`;
- an intrinsic frame type.

```xml
<Ui xmlns="http://www.blizzard.com/wow/ui/">
  <Button name="MyAddonRowTemplate" mixin="MyAddonRowMixin" virtual="true">
    <Size x="200" y="20"/>
    <Layers>
      <Layer level="ARTWORK">
        <FontString parentKey="Text" inherits="GameFontNormal" justifyH="LEFT">
          <Anchors><Anchor point="LEFT" x="4"/></Anchors>
        </FontString>
      </Layer>
    </Layers>
    <Scripts>
      <OnLoad method="OnLoad"/>
      <OnClick method="OnClick"/>
    </Scripts>
  </Button>
</Ui>
```

- `mixin="A, B"` applies mixins before `OnLoad`. `secureMixin=` is Blizzard-only.
- `inherits="T1, T2"` composes templates. `parentKey="Text"` creates `parent.Text`; `parentArray="Rows"` appends to `parent.Rows`.
- `<OnLoad method="OnLoad"/>` calls `self:OnLoad()`. `inherit="prepend"`/`"append"` chains with an inherited script.
- XML errors go to `Logs\FrameXML.log`, not to the Lua error frame.

Intrinsic frames are engine-registered frame types built from a template (`<Frame intrinsic="true">`), created with their own type name. The ones you will use: `DropdownButton`, `EventFrame`, `EventButton`, `ScrollingMessageFrame`, `ItemButton`. Example: `CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")`. [SRC] `Blizzard_Menu/DropdownButton.xml`

### Templates present in Forever [SRC] (file where each is defined)

| Template | Type | Defined in | Use |
|---|---|---|---|
| `BackdropTemplate` | Frame | `Blizzard_SharedXML/Backdrop.xml` | Required for `SetBackdrop` (since 9.0). |
| `TooltipBackdropTemplate` | Frame | `Blizzard_SharedXML/SharedTooltipTemplates.xml` | Tooltip-style border, NineSlice based. |
| `DefaultPanelTemplate` / `DefaultPanelFlatTemplate` | Frame | `Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml` | Modern window without portrait; `frame:SetTitle(text)`. |
| `PortraitFrameTemplate` | Frame | same | Window with portrait; `SetTitle`, `SetPortraitToAsset`. |
| `ButtonFrameTemplate` | Frame | same | Portrait frame plus inset and button bar. |
| `BasicFrameTemplate` / `BasicFrameTemplateWithInset` | Frame | `Blizzard_UIPanelTemplates/Mainline/UIPanelTemplates.xml` | Simple titled window; `frame.TitleText`, `frame.CloseButton`. |
| `InsetFrameTemplate` | Frame | SharedUIPanelTemplates | Inner inset. |
| `UIPanelButtonTemplate` | Button | same | Standard red button. |
| `UIPanelCloseButton` | Button | same | Close X. |
| `SharedButtonSmallTemplate` | Button | `Shared/Button/ThreeSliceButtonTemplate.xml` | Newer three-slice button. |
| `UICheckButtonTemplate` | CheckButton | `Shared/Button/CheckButtonTemplates.xml` | Checkbox; label is `check.Text`. |
| `InputBoxTemplate`, `SearchBoxTemplate`, `InputBoxInstructionsTemplate` | EditBox | `Shared/InputBox/InputBoxTemplates.xml` | Edit boxes. |
| `MinimalSliderWithSteppersTemplate` | Frame | `Shared/Slider/MinimalSlider.xml` | Modern slider (Settings uses it). |
| `UISliderTemplate` | Slider | SharedUIPanelTemplates | Old slider. |
| `PanelTabButtonTemplate`, `TabSystemTemplate` | | SharedUIPanelTemplates, `Shared/TabSystem` | Tabs. |
| `PanelDragBarTemplate`, `TitleDragAreaTemplate`, `PanelResizeButtonTemplate` | | SharedUIPanelTemplates, SharedBasicControls | Drag and resize helpers. |
| `WowScrollBoxList`, `WowScrollBox`, `MinimalScrollBar`, `WowTrimScrollBar`, `WowClassicScrollBar` | | `Blizzard_SharedXML/Shared/Scroll` | Section 6. |
| `WowStyle1DropdownTemplate`, `WowStyle1FilterDropdownTemplate`, `WowStyle1ArrowDropdownTemplate`, `WowStyle2DropdownTemplate` | DropdownButton | `Blizzard_Menu/MenuTemplates.xml`, `Mainline/MenuTemplates.xml` | Section 5. |
| `SecureActionButtonTemplate`, `SecureUnitButtonTemplate`, `InsecureActionButtonTemplate` | Button | `Blizzard_FrameXML/SecureTemplates.xml` | Section 9. |
| `SecureHandlerBaseTemplate`, `SecureHandlerStateTemplate` (and siblings) | Frame | `Blizzard_RestrictedAddOnEnvironment/SecureHandlerTemplates.xml` | Section 9. |
| `UIDropDownMenuTemplate` | Frame | `Blizzard_SharedXML/Mainline/UIDropDownMenuTemplates.xml` | Legacy, still shipped, deprecated. Do not start new work on it. |

`ThinBorderTemplate` does not exist in this client. `OptionsButtonTemplate` is gone as a general template.

Forever reskinned several frames during beta; template names above are present but their art is Forever-specific in places. Do not assume retail texture layout inside Blizzard frames. [WIKI notes page]

```lua
local win = CreateFrame("Frame", "MyAddonWindow", UIParent, "DefaultPanelTemplate")
win:SetSize(360, 420)
win:SetPoint("CENTER")
win:SetTitle("My Addon")
win:SetFrameStrata("MEDIUM")
win:SetClampedToScreen(true)
win:EnableMouse(true)
win:SetMovable(true)
win:RegisterForDrag("LeftButton")
win:SetScript("OnDragStart", win.StartMoving)
win:SetScript("OnDragStop", win.StopMovingOrSizing)
tinsert(UISpecialFrames, "MyAddonWindow")      -- Escape closes it (needs a global frame name)

local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", 0, 0)

local btn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
btn:SetSize(100, 22)
btn:SetPoint("BOTTOMRIGHT", -8, 8)
btn:SetText(OKAY)
btn:SetScript("OnClick", function() win:Hide() end)
```

`SetTitle` on `DefaultPanelTemplate` comes from its mixin; if a template lacks it, set `frame.TitleContainer.TitleText` or `frame.TitleText`. Check the XML in the source branch before assuming a child key.

Backdrop:

```lua
local box = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
box:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
box:SetBackdropColor(0, 0, 0, 0.8)
box:SetBackdropBorderColor(0.4, 0.4, 0.4)
```

NineSlice: Blizzard panels build borders with `NineSliceUtil.ApplyLayoutByName(frame.NineSlice, "layoutName")` from `Blizzard_SharedXML/NineSlice.lua` and layouts in `NineSliceLayouts.lua`. Layout names differ per game flavor; read that file in the `forever` branch before using one. [UNVERIFIED which layout names exist on Forever.]

### Atlases vs file textures

```lua
tex:SetAtlas("ui-hud-minimap-addon-indicator", TextureKitConstants.UseAtlasSize)  -- name, useAtlasSize
tex:SetTexture("Interface\\AddOns\\MyAddon\\media\\icon")      -- path (no extension needed) or a fileID number
tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)                         -- trim default icon borders
tex:SetColorTexture(0, 0, 0, 0.5)                               -- flat colour
local info = C_Texture.GetAtlasInfo("some-atlas")               -- nil if the atlas does not exist  [DOC]
```

- Atlas names are client data and **differ between retail and Forever**. Guard with `C_Texture.GetAtlasInfo(name)` and fall back to a file texture. Blizzard's compartment code does exactly this to tell atlas from file. [SRC]
- Custom textures: TGA, BLP, or PNG (Questie ships `Icons\questie.png` as its `IconTexture`). Power-of-two dimensions are the safe choice. [UNVERIFIED whether non-power-of-two is accepted.]
- Lua and XML files added to a TOC are picked up by `/reload` (since 9.0.1) [WIKI]. Whether a newly added *texture* file is found without restarting the client is [UNVERIFIED]; historically media added while the client was running needed a restart. If a new texture shows as solid green, restart before debugging the path.

### Fonts

```lua
local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")   -- inherit a font object
fs:SetFontObject(GameFontHighlightSmall)
fs:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")                          -- path, size, flags

local font = CreateFont("MyAddonFont")                                  -- creates a global font object
font:CopyFontObject(GameFontNormal)
font:SetTextColor(1, 0.82, 0)
```

Common font objects: `GameFontNormal`, `GameFontNormalSmall`, `GameFontNormalLarge`, `GameFontHighlight`, `GameFontHighlightSmall`, `GameFontDisable`, `GameFontRed`, `GameFontGreen`, `NumberFontNormal`, `ChatFontNormal`, `GameTooltipText`. Prefer inheriting font objects over hard-coded paths: they follow locale (CJK, Cyrillic) and user font settings. `STANDARD_TEXT_FONT`, `UNIT_NAME_FONT`, `DAMAGE_TEXT_FONT`, `NAMEPLATE_FONT` hold locale-correct paths. Measuring text: `fs:GetStringWidth()`, `fs:GetUnboundedStringWidth()`.

### Layers and strata

- Frame strata, low to high: `WORLD`, `BACKGROUND`, `LOW`, `MEDIUM`, `HIGH`, `DIALOG`, `FULLSCREEN`, `FULLSCREEN_DIALOG`, `TOOLTIP`. [WIKI] <https://warcraft.wiki.gg/wiki/Frame_Strata>
- Within a stratum, `SetFrameLevel(n)` orders frames. `frame:SetToplevel(true)` raises on click. `frame:Raise()`.
- Within a frame, draw layers: `BACKGROUND`, `BORDER`, `ARTWORK`, `OVERLAY`, `HIGHLIGHT` (shown only on mouseover). Sublevel -8..7: `tex:SetDrawLayer("ARTWORK", 2)`. [WIKI] <https://warcraft.wiki.gg/wiki/Layer>
- Child frames always draw above their parent's regions regardless of layer.
- **New on Forever:** `GetFrameStrata()` can return a secret value for frames carrying the `FrameStrata` secret aspect (1.60.1 beta 4). Do not branch on the strata of Blizzard combat frames.

### Pixel-perfect helpers [SRC] `Blizzard_SharedXML/PixelUtil.lua`

```
PixelUtil.SetSize(region, width, height, minWidthPixels, minHeightPixels)
PixelUtil.SetWidth(region, width, minPixels) / PixelUtil.SetHeight(region, height, minPixels)
PixelUtil.SetPoint(region, point, relativeTo, relativePoint, offsetX, offsetY, minOffsetXPixels, minOffsetYPixels)
PixelUtil.GetNearestPixelSize(uiUnitSize, layoutScale, minPixels)
PixelUtil.ConvertPixelsToUIForRegion(desiredPixels, region)
PixelUtil.GetPixelToUIUnitFactor()
```

```lua
local border = frame:CreateTexture(nil, "BORDER")
border:SetColorTexture(1, 1, 1)
PixelUtil.SetPoint(border, "TOPLEFT", frame, "TOPLEFT", 0, 0)
PixelUtil.SetPoint(border, "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
PixelUtil.SetHeight(border, 1, 1)      -- exactly one physical pixel at any UI scale
```

Also: `tex:SetSnapToPixelGrid(false)` and `tex:SetTexelSnappingBias(0)` stop 1px lines from shimmering. Re-apply pixel sizes on `UI_SCALE_CHANGED` / `DISPLAY_SIZE_CHANGED`.

---

## 4. Settings API

References: [SRC] `Blizzard_Settings_Shared/Blizzard_Settings.lua`, `Blizzard_ImplementationReadme.lua` (Blizzard's own guide, in the branch), [WIKI] <https://warcraft.wiki.gg/wiki/Settings_API>, <https://warcraft.wiki.gg/wiki/Patch_11.0.2/API_changes>.

### History, so you can spot stale examples

- **Pre-10.0:** `InterfaceOptions_AddCategory(panel)` and `InterfaceOptionsFrame_OpenToCategory`. **Removed.** No definition in the Forever source.
- **10.0:** Settings API introduced.
- **11.0.2:** `Settings.RegisterAddOnSetting` gained **two parameters in the middle** (`variableKey`, `variableTbl`). `Settings.RegisterProxySetting` became callable from addon code. `Settings.OpenToCategory` learned subcategories.
- **12.x:** `Settings.OpenToCategory` forwards to `C_SettingsUtil.OpenSettingsPanel(categoryID, scrollToElementName)`.

### Exact signatures on this client [SRC]

```
Settings.RegisterVerticalLayoutCategory(name)                              -> category, layout
Settings.RegisterVerticalLayoutSubcategory(parentCategory, name)           -> subcategory, layout
Settings.RegisterCanvasLayoutCategory(frame, name)                         -> category, layout
Settings.RegisterCanvasLayoutSubcategory(parentCategory, frame, name)      -> subcategory, layout
Settings.RegisterAddOnCategory(category)

Settings.RegisterAddOnSetting(categoryTbl, variable, variableKey, variableTbl, variableType, name, defaultValue) -> setting
Settings.RegisterProxySetting(categoryTbl, variable, variableType, name, defaultValue, getValue, setValue)       -> setting

Settings.CreateCheckbox(category, setting, tooltip)                        -> initializer
Settings.CreateCheckboxWithOptions(category, setting, options, tooltip)    -> initializer
Settings.CreateSlider(category, setting, options, tooltip)                 -> initializer
Settings.CreateDropdown(category, setting, options, tooltip)               -> initializer   -- options = function returning container:GetData()
Settings.CreateColorSwatch(category, setting, tooltip, options)            -> initializer
Settings.CreateSliderOptions(minValue, maxValue, rate)                     -> options
Settings.CreateControlTextContainer()                                      -> container (container:Add(value, label, tooltip); container:GetData())

Settings.OpenToCategory(categoryID, scrollToElementName)                   -- categoryID = category:GetID(), a number
Settings.GetSetting(variable) / Settings.GetValue(variable) / Settings.SetValue(variable, value, force)
Settings.SetOnValueChangedCallback(variable, callback, owner)
Settings.NotifyUpdate(variable)
setting:SetValueChangedCallback(function(setting, value) end)
setting:GetValue() / setting:SetValue(value) / setting:GetVariable() / setting:GetName()

Settings.VarType = { Boolean = "boolean", String = "string", Number = "number" }
Settings.Default = { True = true, False = false }

CreateSettingsListSectionHeaderInitializer(name, tooltip, newTagID)
CreateSettingsButtonInitializer(name, buttonText, buttonClick, tooltip, addSearchTags, newTagID, gameDataFunc, gameDataEvent)
CreateSettingsCheckboxDropdownInitializer(cbSetting, cbLabel, cbTooltip, dropdownSetting, dropdownOptions, dropDownLabel, dropDownTooltip, ...)
CreateSettingsCheckboxSliderInitializer(cbSetting, cbLabel, cbTooltip, sliderSetting, sliderOptions, sliderLabel, sliderTooltip, ...)
initializer:SetParentInitializer(parentInitializer, modifyPredicate)       -- indents and disables with the parent
initializer:AddShownPredicate(func) / initializer:AddSearchTags(...)
layout:AddInitializer(initializer)
```

Parameter meaning for `RegisterAddOnSetting`:

- `variable`: a **globally unique** string ID for the setting (prefix with the addon name). Used by `Settings.GetSetting`.
- `variableKey`: the key inside `variableTbl` the value is stored under.
- `variableTbl`: the table to read and write, normally your SavedVariables table. Must exist when called.
- `variableType`: `"boolean"`, `"number"` or `"string"`. `type(defaultValue)` works.
- `name`: the label shown.
- The setting writes straight into `variableTbl[variableKey]`, and initializes it to `defaultValue` if nil.

### Complete vertical-layout example

```lua
local ADDON, ns = ...

local function CreateOptions()
    local db = MyAddonDB
    local category, layout = Settings.RegisterVerticalLayoutCategory("My Addon")
    ns.settingsCategory = category

    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("General"))

    -- checkbox bound directly to the saved table
    local enabled = Settings.RegisterAddOnSetting(category, "MyAddon_Enabled", "enabled", db,
        Settings.VarType.Boolean, "Enable", Settings.Default.True)
    enabled:SetValueChangedCallback(function(setting, value) ns:ApplyEnabled(value) end)
    local enabledInit = Settings.CreateCheckbox(category, enabled, "Turn the addon on or off.")

    -- slider through a proxy (custom get/set)
    local function GetScale() return db.scale or 1 end
    local function SetScale(value) db.scale = value; ns:ApplyScale(value) end
    local scale = Settings.RegisterProxySetting(category, "MyAddon_Scale",
        Settings.VarType.Number, "Scale", 1, GetScale, SetScale)
    local sliderOptions = Settings.CreateSliderOptions(0.5, 2, 0.05)          -- min, max, step
    sliderOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, FormatPercentage)
    local scaleInit = Settings.CreateSlider(category, scale, sliderOptions, "Frame scale.")
    scaleInit:SetParentInitializer(enabledInit, function() return db.enabled end)

    -- dropdown
    local function GetAnchorOptions()
        local container = Settings.CreateControlTextContainer()
        container:Add("TOP", "Top")
        container:Add("BOTTOM", "Bottom")
        return container:GetData()
    end
    local anchor = Settings.RegisterAddOnSetting(category, "MyAddon_Anchor", "anchor", db,
        Settings.VarType.String, "Anchor", "TOP")
    Settings.CreateDropdown(category, anchor, GetAnchorOptions, "Where the frame attaches.")

    -- a plain button row
    layout:AddInitializer(CreateSettingsButtonInitializer("Position", "Reset", function()
        ns:ResetPosition()
    end, "Move the frame back to its default spot.", true))

    Settings.RegisterAddOnCategory(category)
end

EventUtil.ContinueOnAddOnLoaded(ADDON, function()
    MyAddonDB = MyAddonDB or {}
    CreateOptions()
end)

SLASH_MYADDON1 = "/myaddon"
SlashCmdList.MYADDON = function()
    Settings.OpenToCategory(ns.settingsCategory:GetID())
end
```

### Canvas layout (your own frame)

```lua
local panel = CreateFrame("Frame")
panel:Hide()
function panel:OnRefresh() end    -- optional: settings panel shown
function panel:OnCommit()  end    -- optional: Apply pressed (only relevant with Apply-flagged settings)
function panel:OnDefault() end    -- optional: Defaults applied

local category, layout = Settings.RegisterCanvasLayoutCategory(panel, "My Addon")
layout:AddAnchorPoint("TOPLEFT", 10, -10)        -- default is TOPLEFT 0,0 / BOTTOMRIGHT 0,0
layout:AddAnchorPoint("BOTTOMRIGHT", -10, 10)
Settings.RegisterAddOnCategory(category)

local sub = Settings.RegisterVerticalLayoutSubcategory(category, "Advanced")   -- mixing layouts is allowed
```

### Gotchas

- **Register after SavedVariables exist** (`ADDON_LOADED` or `EventUtil.ContinueOnAddOnLoaded`). `variableTbl` is captured by reference; if you later replace `MyAddonDB` with a new table (profile switch), the settings still point at the old one. Mutate in place or use proxy settings that read through `ns.db`.
- `Settings.OpenToCategory` takes the **numeric ID** (`category:GetID()`), not the name and not the category object. Passing the name was the 10.x idiom.
- Call `Settings.RegisterAddOnCategory(category)` once, for the top-level category only. Subcategories attach via their parent.
- Addon categories sort alphabetically; subcategories do not unless `category:SetShouldSortAlphabetically(true)`. [SRC readme]
- The dropdown `options` argument is a **function** returning `container:GetData()`, called each time the menu opens.
- Callbacks you pass to proxy settings run tainted; do not make them call protected functions, and expect them to be blocked in combat if they touch secure frames.
- Opening the Settings panel from addon code during combat: [UNVERIFIED]. Guard with `if InCombatLockdown() then print(...) return end` if it errors in testing.
- Slider `rate` is the step size: steps are computed as `(max - min) / rate`.

---

## 5. Menu system (replaces UIDropDownMenu)

References: [SRC] `Blizzard_Menu/` (`MenuUtil.lua`, `Menu.lua`, `MenuTemplates.xml`, `11_0_0_MenuImplementationGuide.lua`), [WIKI] <https://warcraft.wiki.gg/wiki/Blizzard_Menu_implementation_guide>.

Introduced 11.0.0. `EasyMenu` is gone. `UIDropDownMenu_*` still ships on Mainline but is deprecated and a classic taint source; no shims map it to the new system.

### Signatures [SRC]

```
MenuUtil.CreateContextMenu(ownerRegion, generator, ...)            -- generator(ownerRegion, rootDescription, ...)
MenuUtil.CreateButtonContextMenu(ownerRegion, {text, callback, data}, ...)
MenuUtil.CreateCheckboxContextMenu(ownerRegion, isSelected, setSelected, {text, data}, ...)
MenuUtil.CreateRadioContextMenu(ownerRegion, isSelected, setSelected, {text, data}, ...)
MenuUtil.CreateButtonMenu(dropdown, ...) / CreateCheckboxMenu / CreateRadioMenu / CreateEnumRadioMenu(dropdown, enum, enumTranslator, isSelected, setSelected, orderTbl)
MenuUtil.SetElementText(desc, text) / MenuUtil.GetElementText(desc)

description:CreateButton(text, callback, data)                     -- callback(data, menuInputData, menu)
description:CreateCheckbox(text, isSelected, setSelected, data)    -- isSelected(data) -> bool ; setSelected(data)
description:CreateRadio(text, isSelected, setSelected, data)
description:CreateTitle(text, color)
description:CreateDivider()
description:CreateSpacer()
description:CreateColorSwatch(text, callback, colorInfo)
description:CreateTemplate(templateName) / description:CreateFrame()
description:QueueTitle(text) / QueueDivider() / QueueSpacer()      -- only emitted if something is added after
description:SetScrollMode(maxExtent) / description:SetGridMode(MenuConstants.VerticalGridDirection, columns)
description:SetTag(tag, contextData)

element:SetEnabled(boolOrFunc) / element:SetTooltip(function(tooltip, elementDescription) end)
element:AddInitializer(function(frame, description, menu) end)
element:SetResponder(function(data, menuInputData, menu) return MenuResponse.Close end)
element:SetResponse(MenuResponse.Refresh) / element:SetSelectionIgnored() / element:SetOnEnter(f) / SetOnLeave(f)

Menu.ModifyMenu(tag, function(owner, rootDescription, contextData) end)
Menu.PrintOpenMenuTags()

MenuResponse = { Open = 1, Refresh = 2, Close = 3, CloseAll = 4 }
```

Any element description can have children added, which turns it into a submenu.

### Context menu

```lua
local function Generator(owner, root)
    root:CreateTitle("My Addon")
    root:CreateButton("Open settings", function() Settings.OpenToCategory(ns.settingsCategory:GetID()) end)

    root:CreateCheckbox("Enabled",
        function() return ns.db.enabled end,
        function() ns.db.enabled = not ns.db.enabled end)

    local sub = root:CreateButton("Anchor")          -- becomes a submenu because it gets children
    for _, point in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        sub:CreateRadio(point,
            function(p) return ns.db.anchor == p end,
            function(p) ns.db.anchor = p; ns:Reanchor() end,
            point)
    end

    root:CreateDivider()
    local danger = root:CreateButton("Reset everything", function() ns:Reset() end)
    danger:SetEnabled(not InCombatLockdown())
    danger:SetTooltip(function(tooltip, desc)
        GameTooltip_SetTitle(tooltip, MenuUtil.GetElementText(desc))
        GameTooltip_AddNormalLine(tooltip, "Cannot be undone.")
    end)
end

button:RegisterForClicks("AnyUp")
button:SetScript("OnClick", function(self, mouseButton)
    if mouseButton == "RightButton" then
        MenuUtil.CreateContextMenu(self, Generator)
    end
end)
```

### Dropdown button

```lua
local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
dropdown:SetPoint("TOPLEFT", 16, -40)
dropdown:SetWidth(160)
dropdown:SetDefaultText("Choose...")
dropdown:SetupMenu(function(owner, root)
    for i, name in ipairs(ns.profileNames) do
        root:CreateRadio(name,
            function(index) return ns.db.profileIndex == index end,
            function(index) ns:SelectProfile(index) end,
            i)
    end
end)
-- state changed from outside the menu: rebuild so the displayed text updates
dropdown:GenerateMenu()
```

The button text is derived from the selected radio/checkbox elements. Override with `dropdown:SetSelectionText(function(selections) return "..." end)`, `dropdown:SetSelectionTranslator(function(selection) return ... end)` or `dropdown:OverrideText("text")`.

### Adding to Blizzard menus

```lua
Menu.ModifyMenu("MENU_UNIT_PLAYER", function(owner, root, contextData)
    root:CreateDivider()
    root:CreateTitle("My Addon")
    root:CreateButton("Note this player", function()
        ns:AddNote(contextData.name, contextData.server)
    end)
end)
```

- Unit popup tags are `MENU_UNIT_<TYPE>` (`SELF`, `PLAYER`, `TARGET`, `PARTY`, `RAID_PLAYER`, `FRIEND`, ...). Find a tag by opening the menu and running `/run Menu.PrintOpenMenuTags()` or watching `/etrace` for `Menu.OpenMenuTag`.
- `contextData` fields for unit menus (`unit`, `name`, `server`, ...) are defined by `Blizzard_UnitPopupShared`; read it in the branch rather than guessing. Fields may be secret in restricted contexts.
- This is the supported, taint-safe way to extend Blizzard menus. Do not hook `UnitPopup_ShowMenu` or touch `UnitPopupMenus`.

### Gotchas

- The generator runs every time the menu opens (and on `GenerateMenu`). Keep it cheap and stateless.
- `isSelected` is called often; make it a simple lookup.
- A checkbox click keeps the menu open and refreshes; a button click closes it. Change with `SetResponse` or a responder.
- A context menu closes automatically if its owner region is hidden.
- `MenuUtil.ShowTooltip`/`HideTooltip` are deprecated (12.0.7 shim); use `element:SetTooltip`.

---

## 6. ScrollBox and DataProvider

References: [SRC] `Blizzard_SharedXML/Shared/Scroll/*.lua`, `Blizzard_SharedXML/DataProvider.lua`, `TreeListDataProvider.lua`; [WIKI] <https://warcraft.wiki.gg/wiki/Making_scrollable_frames>.

Use ScrollBox for any list with more than a screenful of rows or with dynamic content. It is virtualized: only visible rows have frames, recycled from a pool. `FauxScrollFrame` and `HybridScrollFrame` still exist in the Forever source but are legacy. For a block of static text or a free-form canvas, a plain `ScrollFrame` with `ScrollFrameTemplate` (or `WowScrollBox` plus `CreateScrollBoxLinearView`) is simpler.

### Signatures [SRC]

```
CreateDataProvider(tbl)                       -> provider     -- tbl is optional initial array
CreateDataProviderByIndexCount(count)
CreateIndexRangeDataProvider(size)            -- virtual 1..size, no table
CreateTreeDataProvider()

CreateScrollBoxListLinearView(top, bottom, left, right, spacing)
CreateScrollBoxListGridView(stride, top, bottom, left, right, horizontalSpacing, verticalSpacing)
CreateScrollBoxListTreeListView(indent, top, bottom, left, right, spacing)
CreateScrollBoxLinearView(top, bottom, left, right, spacing)              -- non-list (scroll a child frame)

view:SetElementInitializer(frameTemplateOrFrameType, function(frame, elementData) end)
view:SetElementFactory(function(factory, elementData) factory(templateOrType, initializer) end)
view:SetElementExtent(extent)                                              -- fixed row height
view:SetElementExtentCalculator(function(dataIndex, elementData) return height end)
view:SetElementResetter(function(frame, elementData) end)
view:SetPadding(top, bottom, left, right, spacing)

ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
ScrollUtil.InitScrollBoxWithScrollBar(scrollBox, scrollBar, view)
ScrollUtil.AddManagedScrollBarVisibilityBehavior(scrollBox, scrollBar, anchorsWithBar, anchorsWithoutBar)
ScrollUtil.AddSelectionBehavior(scrollBox, ...)
ScrollUtil.AddAcquiredFrameCallback(scrollBox, callback, owner, iterateExisting)
ScrollUtil.AddReleasedFrameCallback(scrollBox, callback, owner)

scrollBox:SetDataProvider(provider, retainScrollPosition)                  -- ScrollBoxConstants.RetainScrollPosition
scrollBox:GetDataProvider() / scrollBox:Rebuild(retain) / scrollBox:ForEachFrame(func) / scrollBox:FindFrame(elementData)
scrollBox:ScrollToElementData(elementData, alignment, offset, noInterpolation)
scrollBox:ScrollToElementDataIndex(index, alignment, offset, noInterpolation)
scrollBox:ScrollToBegin(noInterp) / scrollBox:ScrollToEnd(noInterp)

provider:Insert(...) / InsertTable(tbl) / InsertAtIndex(elementData, index)
provider:Remove(...) / RemoveIndex(i) / RemoveByPredicate(pred) / Flush()
provider:SetSortComparator(comparator, skipSort) / Sort()
provider:Find(index) / FindByPredicate(pred) / FindIndex(elementData) / GetSize() / ForEach(func) / Enumerate()
frame:GetElementData()                                                     -- assigned to each row frame by the view
```

### Flat list, pure Lua

```lua
local scrollBox = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
scrollBox:SetPoint("TOPLEFT", 8, -30)
scrollBox:SetPoint("BOTTOMRIGHT", -26, 8)

local scrollBar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)

local view = CreateScrollBoxListLinearView()
view:SetElementExtent(20)                       -- required when using a bare frame type (no template size)
view:SetElementInitializer("Button", function(row, data)
    if not row.Text then                        -- one-time construction; rows are recycled
        row.Text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.Text:SetPoint("LEFT", 4, 0)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row:SetScript("OnClick", function(self) ns:OnRowClicked(self:GetElementData()) end)
    end
    row.Text:SetText(data.name)
end)
ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

local provider = CreateDataProvider()
provider:SetSortComparator(function(a, b) return a.name < b.name end)
scrollBox:SetDataProvider(provider)

provider:Insert({ name = "Alpha" }, { name = "Beta" })          -- view updates itself
provider:RemoveByPredicate(function(d) return d.name == "Alpha" end)
```

With an XML template instead of a bare type, pass the template name; the view reads the template's height, so `SetElementExtent` is optional.

### Mixed row types

```lua
view:SetElementFactory(function(factory, data)
    if data.isHeader then
        factory("MyAddonHeaderTemplate", function(frame, d) frame.Text:SetText(d.title) end)
    else
        factory("MyAddonRowTemplate", function(frame, d) frame:SetData(d) end)
    end
end)
view:SetElementExtentCalculator(function(dataIndex, data)
    return data.isHeader and 28 or 20
end)
```

### Tree view

```lua
local view = CreateScrollBoxListTreeListView(10)     -- indent per depth level
view:SetElementFactory(function(factory, node)
    local data = node:GetData()                      -- element data is a tree NODE, not your table
    factory(data.isCategory and "MyAddonHeaderTemplate" or "MyAddonRowTemplate", function(frame, n)
        frame.Text:SetText(n:GetData().name)
        if n:GetData().isCategory then
            frame:SetScript("OnClick", function() n:ToggleCollapsed() end)
        end
    end)
end)
view:SetElementExtentCalculator(function(_, node) return node:GetData().isCategory and 24 or 20 end)
ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

local tree = CreateTreeDataProvider()
local cat = tree:Insert({ name = "Weapons", isCategory = true })    -- returns a node
cat:Insert({ name = "Sword" })
cat:Insert({ name = "Axe" })
scrollBox:SetDataProvider(tree)
```

Node API: `node:Insert(data)`, `node:GetData()`, `node:GetParent()`, `node:GetDepth()`, `node:GetNodes()`, `node:SetCollapsed(collapsed, affectChildren, skipInvalidate)`, `node:ToggleCollapsed()`, `node:IsCollapsed()`. Provider: `tree:CollapseAll()`, `tree:UncollapseAll()`, `tree:SetSortComparator(cmp, affectChildren, skipSort)`. `ScrollBoxListTreeListViewMixin` is created from `ScrollBoxListLinearViewMixin` [SRC `ScrollBoxTreeView.lua:2`], so `SetElementExtent` and `SetElementExtentCalculator` are inherited.

### Gotchas

- **Rows are recycled.** The initializer must set every visual property on every call. State that belongs to the data goes on the data table, not on the frame.
- Initializers run after layout, so the frame has its real size. Frames are not initialized during the factory step. [SRC comment in `ScrollBoxListView.lua`]
- Without a fixed extent or template height the view has to measure every element. Give an extent for large lists.
- For bulk changes, build a table and call `scrollBox:SetDataProvider(CreateDataProvider(tbl), ScrollBoxConstants.RetainScrollPosition)` rather than thousands of `Insert` calls.
- `scrollBar` must be created as an `EventFrame`.
- Hide the bar when not needed with `ScrollUtil.AddManagedScrollBarVisibilityBehavior`.

---

## 7. Tooltips, compartment, minimap, bindings, slash commands, chat, popups, comms

### Tooltips

[SRC] `Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua`, `TooltipUtil.lua`; [DOC] `TooltipInfoDocumentation.lua`.

Basic use is unchanged:

```lua
frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip_SetTitle(GameTooltip, "My Addon")                 -- (tooltip, text, overrideColor, wrap)
    GameTooltip_AddNormalLine(GameTooltip, "Left-click to open.") -- (tooltip, text, wrap, leftOffset)
    GameTooltip:AddDoubleLine("Kills", "12", 1, 1, 1, 0, 1, 0)
    GameTooltip:Show()
end)
frame:SetScript("OnLeave", GameTooltip_Hide)
```

Helpers present: `GameTooltip_SetTitle`, `GameTooltip_AddNormalLine`, `GameTooltip_AddHighlightLine`, `GameTooltip_AddInstructionLine`, `GameTooltip_AddErrorLine`, `GameTooltip_AddColoredLine(tooltip, text, color, wrap, leftOffset)`, `GameTooltip_AddColoredDoubleLine`, `GameTooltip_AddBlankLineToTooltip`. [SRC]

**Hooking item/spell/unit tooltips: `OnTooltipSetItem`, `OnTooltipSetSpell`, `OnTooltipSetUnit` scripts do not exist on Mainline** (removed 10.0.2; no occurrence in the Forever source). Use:

```
TooltipDataProcessor.AddTooltipPostCall(tooltipType, func)    -- func(tooltip, data)
TooltipDataProcessor.AddTooltipPreCall(tooltipType, func)     -- return true to stop default processing
TooltipDataProcessor.AddLinePreCall(lineType, func) / AddLinePostCall(lineType, func)
TooltipDataProcessor.AllTypes = "ALL"
TooltipUtil.GetDisplayedItem(tooltip)  -> name, link, id
TooltipUtil.GetDisplayedSpell(tooltip) -> name, id
TooltipUtil.GetDisplayedUnit(tooltip)  -> name, unit, guid
```

`Enum.TooltipDataType` on this client [DOC]: `Item=0, Spell=1, Unit=2, Corpse=3, Object=4, Currency=5, BattlePet=6, UnitAura=7, AzeriteEssence=8, CompanionPet=9, Mount=10, PetAction=11, Achievement=12, EnhancedConduit=13, EquipmentSet=14, InstanceLock=15, PvPBrawl=16, RecipeRankInfo=17, Totem=18, Toy=19, CorruptionCleanser=20, MinimapMouseover=21, Flyout=22, Quest=23, QuestPartyProgress=24, Macro=25, Debug=26, Outfit=27`.

```lua
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    local itemID = data and data.id
    if not itemID or issecretvalue(itemID) then return end
    local note = ns.db.notes[itemID]
    if note then
        tooltip:AddLine(note, 0.6, 0.8, 1, true)
    end
end)
```

- The callback fires for **every** tooltip that mixes in the data handler (compare tooltips, shopping tooltips, embedded ones). Filter by tooltip object.
- Addon callbacks are wrapped with `forceinsecure()`, so you always run tainted there. [SRC]
- Unit tooltips: unit name and GUID can be secret values for non-group units under restrictions. Test with `issecretvalue` before comparing or indexing with them.
- `data.id`, `data.type`, `data.guid`, `data.lines` are the commonly used fields; args are surfaced directly on the table on current clients (no `TooltipUtil.SurfaceArgs` needed). [UNVERIFIED field-by-field for Forever.]

Reading tooltip text without a hidden scanning tooltip: `C_TooltipInfo.*` returns a `TooltipData` table.

```lua
local data = C_TooltipInfo.GetHyperlink(itemLink)      -- also GetBagItem(bag, slot), GetInventoryItem(unit, slot),
if data then                                           -- GetItemByID(id), GetSpellByID(id), GetUnit(unit), GetQuestLogItem(...)
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if text and not issecretvalue(text) and text:find(ITEM_SOULBOUND, 1, true) then
            -- ...
        end
    end
end
```

### Addon Compartment

Present on Forever: `Blizzard_Minimap/Camelot/AddonCompartment.lua` plus the Mainline implementation. [SRC] Reference: [WIKI] <https://warcraft.wiki.gg/wiki/Addon_compartment>.

TOC route (automatic, runs at `PLAYER_ENTERING_WORLD`):

```
## IconTexture: Interface\AddOns\MyAddon\icon.png
## AddonCompartmentFunc: MyAddon_OnAddonCompartmentClick
## AddonCompartmentFuncOnEnter: MyAddon_OnAddonCompartmentEnter
## AddonCompartmentFuncOnLeave: MyAddon_OnAddonCompartmentLeave
```

```lua
-- must be globals; argument order verified in source
function MyAddon_OnAddonCompartmentClick(addonName, buttonName)     -- buttonName: "LeftButton" / "RightButton"
    ns:ToggleWindow()
end
function MyAddon_OnAddonCompartmentEnter(addonName, menuButtonFrame)
    GameTooltip:SetOwner(menuButtonFrame, "ANCHOR_LEFT")
    GameTooltip:SetText("My Addon")
    GameTooltip:Show()
end
function MyAddon_OnAddonCompartmentLeave(addonName, menuButtonFrame)
    GameTooltip:Hide()
end
```

Lua route (keeps globals out of `_G`):

```lua
if AddonCompartmentFrame and AddonCompartmentFrame.RegisterAddon then
    AddonCompartmentFrame:RegisterAddon({
        text = "My Addon",
        icon = "Interface\\AddOns\\MyAddon\\icon",          -- file path or atlas name
        notCheckable = true,
        func = function(data, menuInputData, menu) ns:ToggleWindow(menuInputData.buttonName) end,
        funcOnEnter = function(button) end,
        funcOnLeave = function(button) end,
    })
end
```

The entry text is the TOC `Title`; the icon is `IconTexture` or `IconAtlas`. The addon must be enabled and loadable (LoadOnDemand addons are loaded on click). These are the three globals the workspace rule "no globals except SavedVariables and slash commands" has to make room for if the TOC route is used; prefer the Lua route.

### Minimap button (LibDataBroker + LibDBIcon)

Convention: do not hand-roll a minimap button. Publish a LibDataBroker launcher and let LibDBIcon draw it, so it works with button collectors and broker bars. Repos: <https://github.com/tekkub/libdatabroker-1-1>, LibDBIcon-1.0 on CurseForge/WoWAce (<https://www.wowace.com/projects/libdbicon-1-0>). Both are listed as `OptionalDeps` by the Forever-working Questie, so they run on this client. Exact library versions compatible with 16001: [UNVERIFIED]; take current releases.

```lua
local LDB = LibStub("LibDataBroker-1.1")
local icon = LibStub("LibDBIcon-1.0")

local launcher = LDB:NewDataObject("MyAddon", {
    type = "launcher",
    text = "My Addon",
    icon = "Interface\\AddOns\\MyAddon\\icon",
    OnClick = function(self, button)
        if button == "RightButton" then MenuUtil.CreateContextMenu(self, ns.MenuGenerator) else ns:ToggleWindow() end
    end,
    OnTooltipShow = function(tooltip)
        tooltip:AddLine("My Addon")
        tooltip:AddLine("Left-click: toggle. Right-click: menu.", 1, 1, 1)
    end,
})

-- in ADDON_LOADED, after the DB exists
MyAddonDB.minimap = MyAddonDB.minimap or { hide = false }     -- LibDBIcon stores minimapPos and hide here
icon:Register("MyAddon", launcher, MyAddonDB.minimap)
-- icon:Show("MyAddon") / icon:Hide("MyAddon")
```

Embed libraries inside the addon folder (`Libs\LibStub\LibStub.lua` first), list them as `OptionalDeps` too. `LibStub` is not shipped by Blizzard.

### Keybindings

[WIKI] <https://warcraft.wiki.gg/wiki/Creating_key_bindings>

`Bindings.xml` in the addon root is **loaded automatically; do not list it in the TOC** (Questie does not). A game-specific file may be named `Bindings_<Client>.xml`.

```xml
<Bindings>
  <Binding name="MYADDON_TOGGLE" category="ADDONS" header="MYADDON">
    MyAddon_ToggleFromBinding()
  </Binding>
  <Binding name="MYADDON_HOLD" runOnUp="true">
    MyAddon_Hold(keystate == "down")
  </Binding>
  <Binding name="CLICK MyAddonSecureButton:LeftButton"/>
</Bindings>
```

```lua
BINDING_HEADER_MYADDON = "My Addon"
BINDING_NAME_MYADDON_TOGGLE = "Toggle window"
BINDING_NAME_MYADDON_HOLD = "Hold to peek"
_G["BINDING_NAME_CLICK MyAddonSecureButton:LeftButton"] = "Use smart button"
```

- Attributes: `name` (required), `header`, `category`, `runOnUp`, `default` (e.g. `"SHIFT-F"`). Questie uses `category="Questie"`. The wiki text documents `header`/`runOnUp`/`default`; `category` is seen in real addons and Blizzard bindings. A custom `category` string shows as its own section; `category="ADDONS"` puts it under the shared AddOns section. [UNVERIFIED display details on Forever.]
- Binding bodies are Lua run **insecurely** in the global environment, so they can only reach globals. That forces one global function per binding (or a global table). They cannot cast spells; use a `CLICK frame:button` binding to a `SecureActionButtonTemplate` for that.
- `BINDING_NAME_*` and `BINDING_HEADER_*` are required globals; this is another unavoidable exception to "no globals".
- The file must be valid XML: escape `<` as `&lt;` or use CDATA.
- Runtime bindings: `SetBinding(key, command)`, `SetBindingClick(key, buttonName, mouseButton)`, `SetOverrideBindingClick(owner, isPriority, key, buttonName, mouseButton)`, `ClearOverrideBindings(owner)`, `GetBindingKey(command)`. All are blocked in combat. Persist with `SaveBindings(GetCurrentBindingSet())`. [UNVERIFIED signatures; the functions are in use in Forever source.]
- `ADDON_LOADED`'s second argument `containsBindings` tells you whether the addon shipped bindings.

### Slash commands

[SRC] `Blizzard_ChatFrameBase/Shared/SlashCommandsRegistry.lua`, `SlashCommands.lua`.

```lua
SLASH_MYADDON1 = "/myaddon"
SLASH_MYADDON2 = "/ma"
SlashCmdList.MYADDON = function(msg, editBox)
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "debug" then
        ns.db.debug = not ns.db.debug
        print("|cff33ff99MyAddon|r debug:", ns.db.debug and "on" or "off")
    elseif cmd == "" then
        ns:ToggleWindow()
    else
        print("|cff33ff99MyAddon|r usage: /myaddon [debug]")
    end
end
```

- The key (`MYADDON`) must match between `SLASH_<KEY><n>` and `SlashCmdList.<KEY>`. `msg` arrives trimmed.
- New helper that does the same thing: `RegisterNewSlashCommand(callback, command, commandAlias)` sets `SLASH_<UPPER>1/2` and `SlashCmdList[<UPPER>]` (both `command` and `commandAlias` are required, without the slash). [SRC]
- Slash handlers run tainted. They cannot call protected functions, in or out of combat.
- Check for collisions before picking a short alias.

### Chat output and hyperlinks

```lua
print("|cff33ff99MyAddon:|r hello")                                 -- to DEFAULT_CHAT_FRAME
DEFAULT_CHAT_FRAME:AddMessage("text", r, g, b)
UIErrorsFrame:AddMessage("Not now", 1, 0.1, 0.1)
```

Renamed chat functions (the old globals exist only as deprecation aliases gated by the `loadDeprecationFallbacks` CVar) [SRC] `Blizzard_DeprecatedChatInfo/`:

| Old | Current |
|---|---|
| `SendChatMessage(msg, type, lang, target)` | `C_ChatInfo.SendChatMessage(message, chatType, languageID, target)` |
| `ChatFrame_AddMessageEventFilter(event, fn)` | `ChatFrameUtil.AddMessageEventFilter(event, callback)` |
| `ChatFrame_RemoveMessageEventFilter` | `ChatFrameUtil.RemoveMessageEventFilter(event, callback)` |
| `ChatEdit_InsertLink(text)` | `ChatFrameUtil.InsertLink(text)` |
| `ChatFrame_OpenChat(text, frame)` | `ChatFrameUtil.OpenChat(text, chatFrame, desiredCursorPosition)` |
| `ChatEdit_GetActiveWindow()` | `ChatFrameUtil.GetActiveWindow()` |
| `ChatFrame_SendTell(name)` | `ChatFrameUtil.SendTell(name)` |
| `DoEmote(token, target)` | `C_ChatInfo.PerformEmote(emoteName, targetName, suppressMoveError)` |
| `GetMouseFocus()` | `GetMouseFoci()` returns an **array** of regions |

Feature-detect: `local AddFilter = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter`.

`C_ChatInfo.SendChatMessage` restrictions: `SAY`, `YELL`, and (new in Forever 1.60.1 beta 4, outside instances) `EMOTE` need a hardware event when called from addon code. `CHANNEL` has long required one. It is also blocked during chat messaging lockdown (`C_ChatInfo.InChatMessagingLockdown()`). [WIKI notes]

Chat message filters receive chat text that may be secret under chat lockdown; guard with `issecretvalue` before pattern matching.

Hyperlinks: `|H<type>:<payload>|h[display text]|h`, usually wrapped in a colour. Standard types: `item`, `spell`, `quest`, `achievement`, `unit`, `player`, `currency`, `url` (not clickable by default). Get real links from the API (`C_Item.GetItemInfo` second return, `C_Spell.GetSpellLink`). Custom links use the `addon` type:

```lua
local link = ("|cff71d5ff|Haddon:MyAddon:note:%d|h[My note %d]|h|r"):format(id, id)
print(link)

EventRegistry:RegisterCallback("SetItemRef", function(_, linkBody, text, button, chatFrame)
    local linkType, addon, kind, arg = strsplit(":", linkBody)
    if linkType == "addon" and addon == "MyAddon" then
        ns:OpenNote(tonumber(arg))
    end
end, ns)
```

The `addon:` link type (`LinkTypes.AddOn = "addon"` in `Blizzard_SharedXML/LinkUtil.lua`) and the `"SetItemRef"` EventRegistry event are the modern replacement for hooking `SetItemRef`. Verified [SRC] `Blizzard_UIPanels_Game/Shared/ItemRefHandlersShared.lua:281`: `EventRegistry:TriggerEvent("SetItemRef", link, text, contextData.button, contextData.frame)`, so the callback receives `(owner, link, text, button, frame)` with `link` being the body such as `addon:MyAddon:note:3`. Alternative that Blizzard's own PTR addon uses: `hooksecurefunc("SetItemRef", function(link, text, button, chatFrame) ... end)`.

Shift-click to link into chat: `if IsModifiedClick("CHATLINK") then ChatFrameUtil.InsertLink(link) end`. `HandleModifiedItemClick(link)` handles both chat-link and dressing room.

### StaticPopup

[SRC] `Blizzard_StaticPopup/StaticPopup.lua`, `Blizzard_StaticPopup_Game/GameDialogDefs.lua`.

```
StaticPopup_Show(which, text_arg1, text_arg2, data, insertedFrame, customOnHideScript) -> dialog or nil
StaticPopup_Hide(which, data)
StaticPopup_Visible(which) / StaticPopup_FindVisible(which, data)
StaticPopup_ShowGenericConfirmation(text, callback, insertedFrame)
StaticPopup_ShowCustomGenericConfirmation(customData, insertedFrame)
```

Callback shapes used throughout Blizzard's own dialogs on this client: `OnAccept = function(dialog, data)`, `OnCancel = function(dialog, data, reason)`, `OnShow = function(dialog, data)`, `EditBoxOnEnterPressed = function(editBox, data)`.

```lua
StaticPopupDialogs["MYADDON_CONFIRM_RESET"] = {
    text = "Reset all My Addon data for %s?",
    button1 = YES,
    button2 = NO,
    OnAccept = function(dialog, data) ns:Reset(data) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
StaticPopup_Show("MYADDON_CONFIRM_RESET", UnitName("player"), nil, { scope = "char" })

StaticPopupDialogs["MYADDON_RENAME"] = {
    text = "New profile name:",
    button1 = ACCEPT, button2 = CANCEL,
    hasEditBox = true, maxLetters = 32,
    OnShow = function(dialog, data)
        local editBox = dialog.GetEditBox and dialog:GetEditBox() or dialog.editBox
        editBox:SetText(data or "")
        editBox:HighlightText()
    end,
    OnAccept = function(dialog, data)
        local editBox = dialog.GetEditBox and dialog:GetEditBox() or dialog.editBox
        ns:RenameProfile(editBox:GetText())
    end,
    EditBoxOnEnterPressed = function(editBox, data)
        local dialog = editBox:GetParent()
        ns:RenameProfile(editBox:GetText())
        dialog:Hide()
    end,
    EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
```

- Key names must be globally unique: prefix with the addon name.
- The dialog frame internals were refactored in 11.2/12.x. Old code that reads `self.editBox`, `self.button1`, `self.text` directly may get nil. `dialog:GetEditBox()` is confirmed in use in `Blizzard_StaticPopup/StaticPopup.lua` on this client [SRC]; accessors for buttons and the text region were not looked up ([UNVERIFIED]), so read that file before touching them. The example above feature-detects the edit box both ways.
- `StaticPopup_Show` returns nil if the dialog could not be shown.
- For a one-off yes/no, `StaticPopup_ShowGenericConfirmation(text, callback)` needs no dialog definition.
- Addon-created static popups taint the dialog frame they occupy. A later Blizzard popup reusing that frame for a protected action (e.g. a confirm that calls a protected function) can be blocked. `preferredIndex = 3` was the historic mitigation, but the string `preferredIndex` no longer appears anywhere in the Forever Lua source [SRC], so it is almost certainly ignored now and harmless to leave in. If popup taint matters, build your own small dialog frame.

### Addon communication

[DOC] `ChatInfoDocumentation.lua`; [WIKI] <https://warcraft.wiki.gg/wiki/API_C_ChatInfo.SendAddonMessage>.

```
C_ChatInfo.RegisterAddonMessagePrefix(prefix)                          -> Enum.RegisterAddonMessagePrefixResult
C_ChatInfo.IsAddonMessagePrefixRegistered(prefix)                      -> bool
C_ChatInfo.SendAddonMessage(prefix, message, chatType, target)         -> Enum.SendAddonMessageResult
C_ChatInfo.SendAddonMessageLogged(prefix, message, chatType, target)   -> result
C_ChatInfo.InChatMessagingLockdown()                                   -> bool
CHAT_MSG_ADDON(prefix, text, channel, sender, target, zoneChannelID, localID, name, instanceID)
```

`Enum.SendAddonMessageResult` on this client: `Success=0, InvalidPrefix=1, InvalidMessage=2, AddonMessageThrottle=3, InvalidChatType=4, NotInGroup=5, TargetRequired=6, InvalidChannel=7, ChannelThrottle=8, GeneralError=9, NotInGuild=10, AddOnMessageLockdown=11, TargetOffline=12`.

Limits [WIKI]: prefix at most 16 characters; message at most 255 bytes, any byte except NUL; default `chatType` is `"PARTY"`. Chat types: `PARTY`, `RAID` (falls back to PARTY), `INSTANCE_CHAT`, `GUILD`, `OFFICER`, `WHISPER` (same or connected realm; `target` = name). `CHANNEL` works on retail and is disabled on Classic; `SAY`/`YELL` work on Classic and not on retail. **Which of those Forever follows is [UNVERIFIED]**: check the returned result code (`InvalidChatType`) at runtime.

Throttle [WIKI]: each prefix has an allowance of 10 messages, refilling 1 per second; exceeding returns `AddonMessageThrottle`. Sending too much across prefixes can disconnect the client. Whispers outside instances are exempt from the per-prefix allowance. Values are server-tunable.

Forever-specific: **trial and veteran accounts cannot send addon messages** (1.60.1 beta 4). `SecretArguments = "NotAllowed"`: you can never pass a secret value into an addon message. During encounter / challenge / PvP restrictions sends fail with `AddOnMessageLockdown` and received payloads can be secret.

```lua
local PREFIX = "MyAddon"
C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

local f = CreateFrame("Frame")
f:RegisterEvent("CHAT_MSG_ADDON")
f:SetScript("OnEvent", function(_, _, prefix, text, channel, sender)
    if prefix ~= PREFIX then return end
    if issecretvalue(text) then return end                 -- restricted context
    if Ambiguate(sender, "none") == UnitName("player") then return end
    ns:OnComm(text, channel, sender)
end)

local function Send(text, channel, target)
    if C_ChatInfo.InChatMessagingLockdown() then return false end
    if ChatThrottleLib then
        ChatThrottleLib:SendAddonMessage("NORMAL", PREFIX, text, channel, target)   -- prio: "BULK" | "NORMAL" | "ALERT"
        return true
    end
    local result = C_ChatInfo.SendAddonMessage(PREFIX, text, channel, target)
    return result == Enum.SendAddonMessageResult.Success
end
```

- Use **ChatThrottleLib** (<https://github.com/wowace/ChatThrottleLib>, also bundled in Ace3's AceComm-3.0) for anything beyond an occasional single message. AceComm adds multi-part messages over 255 bytes. For binary payloads use `C_EncodingUtil.SerializeCBOR` + `CompressString` + an encoder that avoids NUL, or LibSerialize/LibDeflate.
- Never trust incoming data: validate types and lengths, never `loadstring` it.
- Use `SendAddonMessageLogged` for user-authored text (profiles, notes) so it is reportable; it must be plain text.
- Sender is `Name-Realm`; normalise with `Ambiguate(sender, "none")`.

---

## 8. Timers, async data, pools

### C_Timer [DOC] `UITimerDocumentation.lua`; [WIKI] <https://warcraft.wiki.gg/wiki/API_C_Timer.NewTimer>

```
C_Timer.After(seconds, callback)                     -- not cancelable
C_Timer.NewTimer(seconds, callback)                  -> handle    -- one shot
C_Timer.NewTicker(seconds, callback, iterations)     -> handle    -- iterations nil = forever
handle:Cancel() / handle:IsCancelled() / handle:Invoke()
RunNextFrame(callback)                               -- next frame, used widely by Blizzard
```

The callback receives the timer handle as its argument. The handle is a native `FunctionContainer`; user fields written on it are shared with the view passed to the callback. [WIKI]

```lua
C_Timer.After(0, function() ns:AfterLayout() end)          -- next frame

-- debounce: collapse an event burst into one update
local pending
local function RequestUpdate()
    if pending then return end
    pending = true
    C_Timer.After(0.1, function()
        pending = false
        ns:Update()
    end)
end

local ticker = C_Timer.NewTicker(1, function(self)
    if not ns.frame:IsShown() then self:Cancel() return end
    ns:RefreshClock()
end)
```

`C_Timer.After` resolution is one frame. Timer callbacks run tainted like all addon code. Keep a reference to tickers so they can be cancelled; a ticker on a hidden UI keeps running.

### OnUpdate throttling

Use `OnUpdate` only for per-frame visuals (animation, cursor following). It runs every rendered frame while the frame is **shown**.

```lua
local elapsedTotal = 0
frame:SetScript("OnUpdate", function(self, elapsed)
    elapsedTotal = elapsedTotal + elapsed
    if elapsedTotal < 0.2 then return end
    elapsedTotal = 0
    ns:Tick()
end)
-- stop entirely when idle
frame:SetScript("OnUpdate", nil)       -- or frame:Hide()
```

Prefer `AnimationGroup` for fades and slides, `Cooldown` frames for cooldown sweeps, and `StatusBar:SetTimerDuration` for timed bars; these run in C and work with secret durations.

### Coroutines

Lua 5.1 coroutines work. Use them to spread heavy work across frames:

```lua
local function RunChunked(co)
    local ticker
    ticker = C_Timer.NewTicker(0, function()
        local start = debugprofilestop()
        while debugprofilestop() - start < 8 do          -- ~8 ms per frame budget
            local ok, err = coroutine.resume(co)
            if not ok then ticker:Cancel() geterrorhandler()(err) return end
            if coroutine.status(co) == "dead" then ticker:Cancel() return end
        end
    end)
end

RunChunked(coroutine.create(function()
    for i, entry in ipairs(ns.bigList) do
        ns:Index(entry)
        if i % 200 == 0 then coroutine.yield() end
    end
end))
```

Errors inside a coroutine do not reach the error handler by themselves; forward them as above. Do not `coroutine.yield` across a C boundary (inside `pcall`, `table.sort` comparators, or event dispatch).

### Async item and spell data

Item and spell data is loaded lazily from the server. `C_Item.GetItemInfo(id)` returns nil for an uncached item and later fires `GET_ITEM_INFO_RECEIVED(itemID, success)` / `ITEM_DATA_LOAD_RESULT(itemID, success)`. Spells: `SPELL_DATA_LOAD_RESULT(spellID, success)`.

[SRC] `Blizzard_ObjectAPI/`:

```
Item:CreateFromItemID(itemID) / Item:CreateFromItemLink(link) / Item:CreateFromBagAndSlot(bag, slot) / Item:CreateFromItemLocation(loc)
item:ContinueOnItemLoad(callback)                 -- runs immediately if cached
item:ContinueWithCancelOnItemLoad(callback)       -> cancelFunc
item:IsItemEmpty() / item:IsItemDataCached()
item:GetItemName() / GetItemLink() / GetItemIcon() / GetItemQuality() / GetItemQualityColor() / GetItemID()
Spell:CreateFromSpellID(spellID)
spell:ContinueOnSpellLoad(callback) / spell:ContinueWithCancelOnSpellLoad(callback)
spell:GetSpellName() / GetSpellDescription() / GetSpellSubtext() / GetSpellTexture()
ContinuableContainer:Create(); container:AddContinuable(obj); container:AddContinuables(tbl); container:ContinueOnLoad(callback)
C_Item.RequestLoadItemDataByID(itemInfo) / C_Item.IsItemDataCachedByID(itemInfo) / C_Item.DoesItemExistByID(itemInfo)
C_Spell.RequestLoadSpellData(spellIdentifier) / C_Spell.IsSpellDataCached(spellIdentifier)
C_QuestLog.RequestLoadQuestByID(questID)          -- then QUEST_DATA_LOAD_RESULT
```

```lua
local item = Item:CreateFromItemID(itemID)
if not item:IsItemEmpty() then
    item:ContinueOnItemLoad(function()
        row.Text:SetText(item:GetItemLink())
        row.Icon:SetTexture(item:GetItemIcon())
    end)
end

-- wait for many
local container = ContinuableContainer:Create()
for _, id in ipairs(itemIDs) do container:AddContinuable(Item:CreateFromItemID(id)) end
container:ContinueOnLoad(function() ns:AllItemsReady() end)
```

- `ContinueOnItemLoad` on an item ID that does not exist never calls back and can error on an empty item. Check `C_Item.DoesItemExistByID(id)` first for untrusted IDs.
- In a recycled ScrollBox row, use `ContinueWithCancelOnItemLoad` and call the cancel function when the row is reused, or compare `row:GetElementData()` inside the callback, so a late callback does not paint the wrong row.
- `C_Item.GetItemInfoInstant(id)` and `C_Item.GetItemIconByID(id)` need no server round trip.

### Frame and object pools

[SRC] `Blizzard_SharedXMLBase/Pools.lua`. The classic names are aliases of the "secure" pool constructors:

```
CreateFramePool(frameType, parent, template, resetFunc, forbidden, postCreate, capacity)   -> pool
CreateTexturePool(parent, layer, subLayer, template, resetFunc, capacity)
CreateFontStringPool(parent, layer, subLayer, template, resetFunc, capacity)
CreateObjectPool(createFunc, resetFunc, capacity)
CreateFramePoolCollection()
CreateUnsecuredFramePool(frameType, parent, template, resetFunc, capacity)                 -- explicit non-secure variants

pool:Acquire()            -> object, isNew
pool:Release(object)      -> bool
pool:ReleaseAll()
pool:EnumerateActive()    -> iterator of objects
pool:GetNumActive() / pool:IsActive(object) / pool:DoesObjectBelongToPool(object)
```

```lua
local pool = CreateFramePool("Button", container, "MyAddonRowTemplate", function(pool, frame, isNew)
    frame:Hide()
    frame:ClearAllPoints()
    frame.data = nil
end)

local function Rebuild(list)
    pool:ReleaseAll()
    local prev
    for _, data in ipairs(list) do
        local row, isNew = pool:Acquire()
        if isNew then row:SetScript("OnClick", ns.Row_OnClick) end
        row.data = data
        row:SetPoint("TOPLEFT", prev or container, prev and "BOTTOMLEFT" or "TOPLEFT")
        row:Show()
        prev = row
    end
end
```

- The reset function signature is `(pool, object, isNew)`; the default reset hides and clears points. [UNVERIFIED third arg name; the source calls `CallReset(object, new)`.]
- Frames are never destroyed in WoW; pools are how you avoid leaking them. Do not `CreateFrame` inside a function that runs repeatedly.
- `EnumerateActive` iteration order is not creation order. Keep your own array if order matters.
- If the list is scrollable, use a ScrollBox instead; it pools for you.
- The default aliases route through a secure proxy, which is why pool internals are not plain tables. Do not poke at pool fields; use the methods.

---

## 9. Taint, secure execution, combat lockdown, secret values

References: [WIKI] <https://warcraft.wiki.gg/wiki/Secure_Execution_and_Tainting>, <https://warcraft.wiki.gg/wiki/Secret_Values>, <https://warcraft.wiki.gg/wiki/SecureActionButtonTemplate>, <https://warcraft.wiki.gg/wiki/SecureStateDriver>, <https://warcraft.wiki.gg/wiki/API_hooksecurefunc>; [SRC] `Blizzard_FrameXML/SecureTemplates.lua`, `Blizzard_RestrictedAddOnEnvironment/`; [DOC] `RestrictedActionsDocumentation.lua`, `SecretPredicateAPIDocumentation.lua`.

### The model

- All addon code is **tainted** (insecure). Every value it creates or writes is tainted. Blizzard code that reads a tainted value becomes tainted for the rest of that execution path.
- **Protected functions** (cast, target, use item, move, most `C_Container.UseContainerItem`-style actions, `SetBinding*` in combat, ...) fail when called from a tainted path. Result: `ADDON_ACTION_FORBIDDEN(isTainted, function)` with the "addon has been blocked" popup (always forbidden), or `ADDON_ACTION_BLOCKED(isTainted, function)` (blocked because of combat lockdown).
- **Combat lockdown:** while `InCombatLockdown()` is true, addon code cannot change protected frames: `Show`, `Hide`, `SetPoint`, `SetSize`, `SetParent`, `SetAttribute`, `SetScale`, `ClearAllPoints`, `EnableMouse`, and it cannot create frames from secure templates in some cases. A frame anchored to a protected frame becomes subject to the same limits.
- `InCombatLockdown()` exists as a global on this client (used by Blizzard code) and as `C_RestrictedActions.InCombatLockdown()`. Lockdown starts at `PLAYER_REGEN_DISABLED` (you may still change secure frames inside that handler) and ends at `PLAYER_REGEN_ENABLED`.

### Deferral pattern

```lua
local queue = {}
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function()
    for i = 1, #queue do
        local fn = queue[i]
        queue[i] = nil
        fn()
    end
end)

function ns:RunOutOfCombat(fn)
    if InCombatLockdown() then
        queue[#queue + 1] = fn
    else
        fn()
    end
end

ns:RunOutOfCombat(function() secureButton:SetAttribute("spell", spellName) end)
```

De-duplicate queued work by key when the same update can be requested many times during a fight.

### SecureActionButtonTemplate

Action types defined in this client's `SECURE_ACTIONS` [SRC]: `actionbar`, `action`, `actionrelease`, `pet`, `flyout`, `multispell`, `spell`, `toy`, `item`, `equipmentset`, `macro`, `cancelaura`, `leavevehicle`, `destroytotem`, `stop`, `target`, `focus`, `assist`, `maintank`, `mainassist`, `click`, `attribute`, `raidtarget`, `worldmarker`, `teleporthome`, `returnhome`, `visithouse`, `outfit`, `menu`, `togglemenu`. (Several are retail systems that will do nothing useful on Forever.)

```lua
local btn = CreateFrame("Button", "MyAddonSecureButton", UIParent, "SecureActionButtonTemplate")
btn:SetSize(36, 36)
btn:SetPoint("CENTER")
btn:RegisterForClicks("AnyUp", "AnyDown")          -- see key-down note below
btn:SetAttribute("type", "spell")                  -- any mouse button
btn:SetAttribute("spell", "Frostbolt")             -- name or spellID
btn:SetAttribute("unit", "target")

btn:SetAttribute("type2", "macro")                 -- right button
btn:SetAttribute("macrotext2", "/use 13")

btn:SetAttribute("shift-type1", "item")            -- modifier-button form: [modifier-]attribute[button]
btn:SetAttribute("shift-item1", "Hearthstone")

btn:SetAttribute("*type-heal", "spell")            -- virtual button "heal"
btn:SetAttribute("helpbutton", "heal")             -- friendly target remaps the click to "heal"
```

Rules and gotchas:

- Attribute lookup order is most specific first: `modifier-name-button`, then `*name-button`, `modifier-name*`, `*name*`, then plain `name`. Modifier prefix order is `alt-ctrl-shift-`.
- **Key down vs key up** [SRC `SecureTemplates.lua` ~line 793]: the button acts on key down when the `ActionButtonUseKeyDown` CVar is true (or the `useOnKeyDown` attribute is set) and on up otherwise. If the frame is only registered for `"AnyUp"` and the CVar says key-down, key-bound clicks do nothing. Register both `"AnyUp", "AnyDown"`; the template picks the right phase itself. Related attributes: `useOnKeyDown`, `pressAndHoldAction`, `typerelease`.
- Attributes cannot be changed in combat from addon Lua. Decide dynamic behaviour ahead of time with a macro conditional (`/cast [@mouseover,help,nodead][] Flash Heal`) or a secure handler snippet.
- `macrotext`: the template still reads it. `SECURE_ACTIONS.macro` uses the `macro` attribute if set, otherwise passes `macrotext` to `C_Macro.RunMacroText(text, button)` [SRC `SecureTemplates.lua:450`]. Retail has at times restricted what `RunMacroText` accepts from addon-created buttons; what the C side allows on Forever is [UNVERIFIED]. If a `macrotext` button silently does nothing, switch to `type="macro"` with a real macro index/name, or to `type="spell"`/`"item"`.
- `PreClick`/`PostClick` scripts run insecurely around the secure click and cannot change attributes in combat. `HookScript("OnClick", ...)` is safe; `SetScript("OnClick", ...)` on a secure button destroys the secure handler.
- Never `SetAttribute` a function or table and expect it to act; values are data for the secure handler.
- For a clickable unit frame use `SecureUnitButtonTemplate` with `*type1 = "target"`, `*type2 = "togglemenu"`, `unit = "party1"`.
- `/click MyAddonSecureButton` and `CLICK MyAddonSecureButton:LeftButton` bindings let a keybind fire it.

### Secure handlers and state drivers

```lua
-- visibility / attribute driven by macro conditionals, evaluated securely even in combat
RegisterStateDriver(frame, "visibility", "[combat] show; hide")
RegisterAttributeDriver(frame, "state-unitexists", "[@target,exists] true; false")
UnregisterStateDriver(frame, "visibility")

-- custom state with a snippet (restricted Lua environment)
local header = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
header:SetAttribute("_onstate-stance", [[
    -- self is a frame handle; newstate is the driver's value
    local btn = self:GetFrameRef("btn")
    btn:SetAttribute("spell", newstate == "1" and "Shield Bash" or "Pummel")
]])
SecureHandlerSetFrameRef(header, "btn", btn)
RegisterStateDriver(header, "stance", "[stance:2] 1; 0")

-- wrap a script on a secure frame
SecureHandlerWrapScript(btn, "OnClick", header, [[ return nil ]])
```

- Snippets are strings compiled in the **restricted environment**: no `_G`, no closures over your Lua, only a whitelisted API (`self:GetAttribute`, `SetAttribute`, `Show`, `Hide`, `SetPoint` to other handles, `GetFrameRef`, `owner`, `control`, `PlayerInCombat()`, `UnitExists` and similar, `newtable`, `print`).
- `"visibility"` is a built-in state; other state names fire `_onstate-<name>`.
- Drivers are polled on a short timer (about 0.2 s) plus relevant events, so they are not instant.
- The Forever beta had a bug where the restricted environment did not load; it was fixed in build 70009. [WIKI]

### hooksecurefunc vs replacing globals

```
hooksecurefunc([table,] "functionName", hookFunc)      -- post-hook; same args; return values ignored
frame:HookScript("OnShow", hookFunc)                    -- post-hook a script handler
```

```lua
hooksecurefunc("ToggleCharacter", function(tab) ns:OnCharacterToggled(tab) end)
hooksecurefunc(GameTooltip, "SetBagItem", function(self, bag, slot) end)
```

- **Never** overwrite a Blizzard global or method (`OldFn = Fn; Fn = function(...) ... end`). The replacement is tainted, and everything that calls it becomes tainted.
- A hook cannot be removed until reload; gate it with a flag.
- `hooksecurefunc` replaces the function value in its table. Code that captured the old reference in a local (very common in Blizzard files, and in mixins already copied onto frames) will not call your hook. Hook the instance (`hooksecurefunc(SomeFrame, "Method", fn)`), not only the mixin table.
- Hooks run tainted after the original; they cannot change its result. Some C functions are flagged `SecureHooksAllowed = false` in the API docs and cannot be hooked at all (for example `RegisterEventCallback`).
- Your hook receives the original arguments, which may include secret values.

### Avoiding taint of Blizzard UI

- Do not write fields onto Blizzard frames or tables (`PlayerFrame.myFlag = true`). Keep side tables keyed by frame: `local state = setmetatable({}, { __mode = "k" })`.
- Do not reparent, re-anchor, or resize protected Blizzard frames (action bars, unit frames, nameplates, raid frames) outside Edit Mode. If you must, do it out of combat and expect conflicts with Edit Mode.
- Do not call Blizzard *internal* Lua functions that then call protected functions (the taint travels with your call).
- Do not modify shared Blizzard tables that secure code iterates (`UnitPopupMenus`, `StaticPopupDialogs` entries owned by Blizzard, `UIPanelWindows`, `UISpecialFrames` is fine).
- `UIDropDownMenu` is the historic number-one taint spreader. Use the Menu system.
- Use the designed extension points: `Menu.ModifyMenu`, `TooltipDataProcessor`, `Settings`, `EventRegistry`, `AddonCompartmentFrame:RegisterAddon`. They contain explicit taint barriers.
- Use the global `ns` namespace (`local ADDON, ns = ...`); never create short common global names.

### Diagnostics

```
issecurevariable([table,] "name") -> isSecure, taintedByAddon      [WIKI] <https://warcraft.wiki.gg/wiki/API_issecurevariable>
issecure() -> bool                                                 -- always false in addon code
/console taintLog 1        -- blocked actions only; 2 adds global-variable taint; 11 is the most verbose
                           -- output: <client>\Logs\taint.log, written on logout or /reload
/console scriptErrors 1    -- show Lua errors
/etrace                    -- event trace window
/fstack                    -- frame stack under the cursor
/tinspect <frame>          -- table inspector
/dump expr
```

`taintLogObjectSecrets` is a newer companion CVar (12.1.0) for secret-aspect logging. [WIKI CVar list] `ADDON_ACTION_BLOCKED` / `ADDON_ACTION_FORBIDDEN` payload is `(isTainted, function)` where the first value is the offending addon's name. [DOC] Lua errors on this machine land in the client's `Errors\` folder; taint logs in `Logs\taint.log`.

### Secret values (12.0.0+, active in Forever)

Blizzard confirmed secrets are active in Forever. [WIKI notes] Summary of the rules for addon code [WIKI Secret_Values]:

- Some API returns and event payloads are **secret values** under certain conditions (in combat, in an encounter, in an instance, in PvP, or for units that are not you or your group).
- With a secret value addon code **may**: store it, pass it to Lua functions, concatenate it, use it in `string.format`/`string.concat`/`string.join`, and pass it to C functions explicitly marked as accepting secrets (many widget setters: `FontString:SetText`, `StatusBar:SetValue`, `StatusBar:SetMinMaxValues`, `Texture:SetTexture`, `Cooldown:SetCooldownFromDurationObject`, ...).
- Addon code **may not**: do arithmetic on it, compare it, test a secret boolean in `if`, take its length, use it as a table key, index it, or call it. Each of those raises an **immediate Lua error**.
- `type(secret)` returns the real type. A non-boolean secret can be tested for nil-ness with `if value then`.
- A widget that was fed a secret can become "secret-aspected": getters such as `GetText()`, `GetValue()`, and now `GetFrameStrata()` then return secrets too.

```
issecretvalue(value) -> bool
canaccessvalue(value) -> bool
hasanysecretvalues(...) -> bool
issecrettable(tbl) / canaccesstable(tbl) -> bool
scrubsecretvalues(...) -> ...      -- secrets replaced by nil
C_Secrets.HasSecretRestrictions() -> bool
C_Secrets.ShouldAurasBeSecret() / C_Secrets.ShouldCooldownsBeSecret() -> bool
C_RestrictedActions.IsAddOnRestrictionActive(Enum.AddOnRestrictionType.X) -> bool
C_RestrictedActions.GetAddOnRestrictionState(type) -> Enum.AddOnRestrictionState   -- Inactive=0, Activating=1, Active=2
Enum.AddOnRestrictionType: Combat=0, Encounter=1, ChallengeMode=2, PvPMatch=3, Map=4, Chat=5
ADDON_RESTRICTION_STATE_CHANGED(type, state)
```

Signature annotations on this client [DOC]: `UnitHealth(unit, usePredicted=true)` is `SecretReturns = true`; `UnitName(unit)` and `UnitGUID(unit)` are conditionally secret; `C_UnitAuras.GetAuraDataBy*`, `C_Spell.GetSpellCooldown`, `C_Spell.GetSpellCharges` are conditionally secret. In the generated docs look for `SecretReturns`, `SecretWhen...`, `ConditionalSecret`, and `SecretArguments`.

Practical patterns:

```lua
-- 1. Display-only: hand the value straight to a widget, never inspect it.
healthBar:SetMinMaxValues(0, UnitHealthMax("target"))
healthBar:SetValue(UnitHealth("target"))
nameText:SetText(UnitName("target"))
pctText:SetText(string.format("%d%%", UnitHealthPercent("target", true, CurveConstants.ScaleTo100)))  -- [UNVERIFIED args]

-- 2. Logic: guard, and have a fallback.
local hp = UnitHealth("target")
if not issecretvalue(hp) then
    if hp < 1000 then ns:Warn() end
end

-- 3. Cooldowns and aura timers: use duration objects, not arithmetic.
local duration = C_Spell.GetSpellCooldownDuration(spellID)      -- LuaDurationObject
if duration then cooldownFrame:SetCooldownFromDurationObject(duration) end
```

What this means for addon design on Forever:

- Addons that only *show* things (bars, timers, icons, text) remain possible if they are written to pass values through to widgets.
- Addons that *decide* things from combat data (rotation helpers, boss-mod style logic keyed on enemy casts or auras, damage meters parsing the combat log) are restricted or impossible. `COMBAT_LOG_EVENT_UNFILTERED` registration errors; Blizzard ships its own damage meter (`Blizzard_DamageMeter`, `C_DamageMeter`).
- Out-of-combat, non-instance data (bags, quests, map, professions, reputation, your own character sheet) is not secret. That is the comfortable territory: quest, inventory, profession, collection, UI-layout, and social addons.
- **Which restriction types actually activate where on Forever (open world combat vs dungeons vs raids) was not confirmed.** Test with `/dump C_Secrets.HasSecretRestrictions()` and `/dump issecretvalue(UnitHealth("target"))` in each context before designing around either answer. The test CVar `addonChatRestrictionsForced` forces chat lockdown for testing. [WIKI]
- Creature GUIDs: server and spawn ID portions are obfuscated on Forever (beta 5) so GUIDs cannot be compared to detect layers. They stay stable and unique within a session. Do not persist creature GUIDs or parse their server/spawn fields.

---

## 10. Edit Mode, frame positions, scale

### What exists

- `Blizzard_EditMode` loads on Forever (it has a `Camelot` subfolder), with `C_EditMode` [DOC]: `GetLayouts() -> EditModeLayouts`, `SetActiveLayout(index)`, `SaveLayouts(info)`, `GetAccountSettings()`, `ConvertLayoutInfoToString(info)`, `ConvertStringToLayoutInfo(str)`, `IsValidLayoutName(name)`, `GetEditModeDefaultLayout()` (new in 1.60.1). Event `EDIT_MODE_LAYOUTS_UPDATED(layoutInfo, reconcileLayouts)`.
- `EditModeManagerFrame:IsEditModeActive()`, and the EventRegistry events `"EditMode.Enter"`, `"EditMode.Exit"`, `"EditMode.SavedLayouts"`. [SRC] `Blizzard_EditMode/Shared/EditModeManager.lua`
- Forever saves Edit Mode layouts separately per UI type (mouse+keyboard vs gamepad). [WIKI notes]
- **There is no official API for registering an addon frame as an Edit Mode system.** `EditModeManagerFrame:RegisterSystemFrame` is Blizzard-internal; calling it from an addon taints the manager and breaks layout saving for protected frames.

### Options for addon frames

1. **LibEditMode** (<https://github.com/p3lim-wow/LibEditMode>, wiki <https://github.com/p3lim-wow/LibEditMode/wiki>). Its TOC lists `16001` and `## AllowLoadGameType: standard, camelot, mists, tbc`, so it targets Forever. It draws its own selection overlay and settings dialog rather than re-using Blizzard's, to limit taint.

   ```lua
   local LEM = ns.LibEditMode or LibStub("LibEditMode")     -- namespaced embed is the recommended load method

   local defaults = { point = "CENTER", x = 0, y = 0 }

   LEM:AddFrame(frame, function(f, layoutName, point, x, y)
       local pos = MyAddonDB.layouts[layoutName]
       pos.point, pos.x, pos.y = point, x, y
   end, defaults)

   LEM:RegisterCallback("layout", function(layoutName)        -- fires at login and on every layout switch
       MyAddonDB.layouts = MyAddonDB.layouts or {}
       local pos = MyAddonDB.layouts[layoutName]
       if not pos then pos = CopyTable(defaults); MyAddonDB.layouts[layoutName] = pos end
       frame:ClearAllPoints()
       frame:SetPoint(pos.point, pos.x, pos.y)
   end)
   LEM:RegisterCallback("enter", function() frame:Show() end)
   LEM:RegisterCallback("exit",  function() ns:UpdateVisibility() end)

   LEM:AddFrameSettings(frame, {
       {
           name = "Scale", kind = LEM.SettingType.Slider, default = 1,
           get = function(layoutName) return MyAddonDB.layouts[layoutName].scale or 1 end,
           set = function(layoutName, value) MyAddonDB.layouts[layoutName].scale = value; frame:SetScale(value) end,
           minValue = 0.5, maxValue = 2, valueStep = 0.05,
       },
   })
   ```

   Other callbacks: `create(layoutName, layoutIndex, sourceLayoutName)`, `rename(old, new, index)`, `delete(layoutName)`. Also `LEM:IsInEditMode()`, `LEM:GetActiveLayoutName()` (valid only after the `layout` callback). Positions are stored **per Edit Mode layout name** in your own SavedVariables. Embedding: load `libs\LibEditMode\namespaced.lua` then `libs\LibEditMode\embed.xml` before your code. Not tested on this client.

2. **Listen to Edit Mode and show your own mover.** No dependency:

   ```lua
   EventRegistry:RegisterCallback("EditMode.Enter", function() ns:SetUnlocked(true) end, ns)
   EventRegistry:RegisterCallback("EditMode.Exit",  function() ns:SetUnlocked(false) end, ns)
   ```

3. **Plain lock/unlock** via slash command or settings checkbox. Always offer this, since Edit Mode cannot be entered in combat.

### Saving positions yourself

```lua
local function SavePosition(frame)
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    ns.db.pos = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function RestorePosition(frame)
    local p = ns.db.pos
    frame:ClearAllPoints()
    if p then
        frame:SetPoint(p.point, UIParent, p.relativePoint, p.x, p.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    end
end

frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", function(self) if not ns.db.locked then self:StartMoving() end end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition(self)
end)
```

- After `StartMoving`/`StopMovingOrSizing` the frame is anchored to the screen by the nearest corner with absolute offsets; `GetPoint(1)` returns that anchor. Save all of point, relativePoint, x, y.
- **`SetUserPlaced` / layout-cache:** a *named* movable frame is, by default after being moved, remembered by the client in `WTF\...\layout-cache.txt` and restored before your code runs. That fights your own saved position. Either rely on it entirely (`frame:SetUserPlaced(true)`, nothing in SavedVariables) or opt out: create the frame unnamed, or call `frame:SetUserPlaced(false)` after `StopMovingOrSizing` and restore from your DB at `PLAYER_LOGIN`. Do not mix. `SetUserPlaced` errors on a non-movable frame. [UNVERIFIED on Forever; long-standing behaviour.]
- Restore at `PLAYER_LOGIN` or later, after the UI scale is final.
- `frame:SetClampedToScreen(true)` keeps it reachable; `SetClampRectInsets(l, r, t, b)` lets part hang off.
- Offer a reset command. Users change resolution and lose frames off screen.

### Scale

- `UIParent:GetEffectiveScale()` and `frame:GetEffectiveScale()` multiply all parent scales. Screen coordinates from `GetCursorPosition()` are in physical-ish units; divide by `frame:GetEffectiveScale()` to get that frame's units.
- Parent to `UIParent` so the frame follows UI scale and hides with Alt-Z. A frame with no parent ignores UI scale.
- Offsets saved under one scale place the frame elsewhere after `frame:SetScale(n)` changes. If you offer a per-frame scale, convert the saved offsets (multiply by old scale / new scale) or anchor by `CENTER`.
- React to `UI_SCALE_CHANGED` and `DISPLAY_SIZE_CHANGED` if you cache sizes.
- `C_UI.GetUIParent()` exists [DOC] for code that should not assume the global.

---

## 11. Data API families: current form vs removed globals

All signatures below are [DOC] for this client unless noted. "Bare" means the old global. Usage evidence comes from scanning Blizzard's own Lua in the `forever` branch: where Blizzard calls only the namespaced form and no Lua shim defines the bare name, the bare global is treated as gone.

A caveat on that evidence: a function implemented in C and not listed in the generated docs would not show up either way. If you need certainty for one name, run `/dump GetItemInfo` in game. Always write `C_*` first.

### Deprecation shims and `loadDeprecationFallbacks`

- Blizzard keeps short-lived Lua compatibility wrappers in `Blizzard_Deprecated*` addons. Every file begins with `if not GetCVarBool("loadDeprecationFallbacks") then return end`. [SRC]
- The CVar (added 10.2.7) defaults to on in release builds, can default to off on test builds, and **is not persisted**: it resets every client start. [WIKI] <https://warcraft.wiki.gg/wiki/CVar_loadDeprecationFallbacks>
- Test your addon with `/console loadDeprecationFallbacks 0` then `/reload` to prove it does not depend on shims.
- On Forever, `Blizzard_Deprecated.toc` loads only `Mainline/Deprecated_12_0_1.lua`, `12_0_5`, `12_0_7`, `12_1_0` and `Shared/Deprecated_12_1_0.lua`. **Nothing from 10.x or 11.x remains.** What the shims still cover:
  - `Blizzard_DeprecatedActionBar`: `GetActionInfo`-family globals (`GetActionTexture`, `GetActionCooldown`, `HasAction`, `IsUsableAction`, `IsActionInRange`, `GetActionBarPage`, `ChangeActionBarPage`, ...) forwarding to `C_ActionBar.*`.
  - `Blizzard_DeprecatedChatInfo`: `SendChatMessage`, `DoEmote`, `CancelEmote`, and the `ChatFrame_*` / `ChatEdit_*` / `Chat_*` aliases to `ChatFrameUtil.*`, plus constants like `NUM_CHAT_WINDOWS`.
  - `Blizzard_DeprecatedCombatLog`: `CombatLog_Color_*` helpers to `CombatLogUtil.*`.
  - `Blizzard_DeprecatedSpellBook`: `IsSpellKnown`, `IsPlayerSpell`-style helpers to `C_SpellBook.*`.
  - `Blizzard_DeprecatedPartyInfo`: `UninviteUnit`, `PromoteToLeader`, `DoReadyCheck`, `ConfirmReadyCheck`, ... to `C_PartyInfo.*`.
  - `Shared/Deprecated_12_1_0.lua`: `getglobal`, `setglobal`, `GetWeaponEnchantInfo` (now `C_Item.GetWeaponEnchantInfo`), `CancelItemTempEnchantment`, `GetInspectSpecialization`.
  - `Deprecated_12_0_7.lua`: `MenuUtil.ShowTooltip/HideTooltip`, `GetMerchantCurrencies`.
  - Settings: `Blizzard_Settings_Shared/Blizzard_Deprecated.lua` exists but defines no `InterfaceOptions_*` shims.
- Shims are removed without notice in a later patch. Never ship code that needs them.

### Spells: `C_Spell`, `C_SpellBook`

```
C_Spell.GetSpellInfo(spellIdentifier)        -> SpellInfo { name, iconID, originalIconID, castTime, minRange, maxRange, spellID } or nil
C_Spell.GetSpellName(spellIdentifier)        -> name
C_Spell.GetSpellTexture(spellIdentifier)     -> iconID, originalIconID, conditionalIconID?
C_Spell.GetSpellLink(spellIdentifier, glyphID?) -> link
C_Spell.GetSpellDescription(spellIdentifier) / GetSpellSubtext(spellIdentifier)
C_Spell.GetSpellCooldown(spellIdentifier)    -> SpellCooldownInfo { startTime, duration, isEnabled, isActive, modRate, activeCategory?, timeUntilEndOfStartRecovery?, isOnGCD? }
C_Spell.GetSpellCooldownDuration(spellIdentifier, ignoreGCD=false) -> LuaDurationObject
C_Spell.GetSpellCharges(spellIdentifier)     -> SpellChargeInfo { currentCharges, maxCharges, cooldownStartTime, cooldownDuration, chargeModRate, isActive }
C_Spell.GetSpellPowerCost(spellIdentifier)   -> table<SpellPowerCostInfo>
C_Spell.IsSpellUsable(spellIdentifier)       -> isUsable, insufficientPower
C_Spell.IsSpellInRange(spellIdentifier, targetUnit?) -> bool?       -- nil = not applicable
C_Spell.IsSpellPassive / DoesSpellExist / GetOverrideSpell(spellIdentifier, spec=0, onlyKnown=true, ignoreOverrideSpellID=0)
C_Spell.RequestLoadSpellData / IsSpellDataCached

C_SpellBook.IsSpellKnown(spellID, spellBank="Player")
C_SpellBook.IsSpellInSpellBook(spellID, spellBank="Player", includeOverrides=true)
C_SpellBook.IsSpellKnownOrInSpellBook(spellID, spellBank="Player", includeOverrides=true)
C_SpellBook.GetNumSpellBookSkillLines() ; GetSpellBookSkillLineInfo(index) -> SpellBookSkillLineInfo
C_SpellBook.GetSpellBookItemInfo(slotIndex, Enum.SpellBookSpellBank.Player) -> SpellBookItemInfo
C_SpellBook.GetSpellBookItemName(slotIndex, spellBank) -> name, subName
C_SpellBook.FindSpellBookSlotForSpell(spellIdentifier, ...) -> slotIndex, spellBank
```

`spellIdentifier` is a spell ID, name, `name(subtext)`, or link. Name lookups only resolve spells the player knows. The migration notes ship in the branch: `Blizzard_Deprecated/11_0_0_SpellBookAPITransitionGuide.lua`.

| Removed bare global | Replacement |
|---|---|
| `GetSpellInfo(id)` -> name, rank, icon, castTime, minRange, maxRange, spellID | `C_Spell.GetSpellInfo(id)` -> **table**; no rank (use `GetSpellSubtext`) |
| `GetSpellCooldown(id)` -> start, duration, enabled, modRate | `C_Spell.GetSpellCooldown(id)` -> table |
| `GetSpellCharges`, `GetSpellTexture`, `GetSpellLink`, `GetSpellDescription`, `GetSpellSubtext` | `C_Spell.*` same names |
| `IsUsableSpell` | `C_Spell.IsSpellUsable` |
| `IsSpellInRange(name, unit)` -> 1/0/nil | `C_Spell.IsSpellInRange` -> true/false/nil |
| `IsSpellKnown`, `IsPlayerSpell` | `C_SpellBook.IsSpellKnown`, `IsSpellKnownOrInSpellBook` |
| `GetSpellBookItemInfo`, `GetNumSpellTabs`, `GetSpellTabInfo` | `C_SpellBook.*`; "tabs" are "skill lines"; `BOOKTYPE_SPELL` -> `Enum.SpellBookSpellBank.Player` |

```lua
local info = C_Spell.GetSpellInfo(spellID)
if info then icon:SetTexture(info.iconID); label:SetText(info.name) end

local cd = C_Spell.GetSpellCooldown(spellID)
if cd and not issecretvalue(cd.startTime) and cd.duration > 0 then
    cooldown:SetCooldown(cd.startTime, cd.duration, cd.modRate)
end
```

Cooldown and charge data is conditionally secret. Prefer `GetSpellCooldownDuration` + `SetCooldownFromDurationObject` for display.

### Items: `C_Item`

```
C_Item.GetItemInfo(itemInfo) -> itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType,
                                itemStackCount, itemEquipLoc, itemTexture, sellPrice, classID, subclassID, bindType,
                                expansionID, setID, isCraftingReagent, itemDescription       -- 18th return added 12.0.0
C_Item.GetItemInfoInstant(itemInfo) -> itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subClassID
C_Item.GetItemNameByID / GetItemIconByID / GetItemQualityByID (itemInfo)
C_Item.GetItemCount(itemInfo, includeBank=false, includeUses=false, includeReagentBank=false, includeAccountBank=false)
C_Item.GetItemCooldown(itemInfo) -> startTimeSeconds, durationSeconds, enableCooldownTimer
C_Item.GetItemSpell(itemInfo) -> spellName, spellID
C_Item.GetItemQualityColor(quality) -> r, g, b, hexString
C_Item.GetDetailedItemLevelInfo(itemInfo) -> actualItemLevel, previewLevel, sparseItemLevel
C_Item.IsEquippedItem(itemInfo) / IsUsableItem(itemInfo) -> usable, noMana
C_Item.GetItemID(itemLocation) / GetItemLink(itemLocation) / DoesItemExistByID(itemInfo)
C_Item.RequestLoadItemDataByID(itemInfo) / IsItemDataCachedByID(itemInfo)
```

`itemInfo` is an item ID, name (only if in bags/cache), or link. `C_Item.GetItemInfo` still returns **multiple values**, unlike `C_Spell.GetSpellInfo`. It returns nil for uncached items; see section 8. `itemLocation` is an `ItemLocation` object: `ItemLocation:CreateFromBagAndSlot(bag, slot)` or `ItemLocation:CreateFromEquipmentSlot(slot)`.

Removed bare globals: `GetItemInfo`, `GetItemInfoInstant`, `GetItemCount`, `GetItemIcon`, `GetItemCooldown`, `GetItemSpell`, `GetItemQualityColor`, `GetDetailedItemLevelInfo`, `IsEquippedItem`, `IsUsableItem`. Still bare and used by Blizzard: `GetInventoryItemLink`, `GetInventoryItemID`, `GetInventoryItemTexture`, `GetInventoryItemDurability`.

### Bags: `C_Container`

```
C_Container.GetContainerNumSlots(bag) -> numSlots
C_Container.GetContainerNumFreeSlots(bag) -> numFreeSlots, bagFamily
C_Container.GetContainerItemInfo(bag, slot) -> ContainerItemInfo { iconFileID, stackCount, isLocked, quality?, isReadable,
                                               hasLoot, hyperlink, isFiltered, hasNoValue, itemID, isBound, itemName } or nothing
C_Container.GetContainerItemLink(bag, slot) / GetContainerItemID(bag, slot)
C_Container.GetContainerItemCooldown(bag, slot) -> startTime, duration, enable
C_Container.GetItemCooldown(itemID) -> startTime, duration, enable
C_Container.UseContainerItem(bag, slot, unitToken?, bankType?, reagentBankOpen=false)     -- protected in most contexts
C_Container.PickupContainerItem(bag, slot)
C_Container.GetBagName(bag)
```

`GetContainerItemInfo` returns a **table** (the old global returned 10 positional values) and returns nothing for an empty slot. Backpack is `0` (`BACKPACK_CONTAINER`), bags `1..NUM_BAG_SLOTS`. Whether Forever has a reagent bag slot or Classic-style keyring was not checked ([UNVERIFIED]; `C_ActionBar.ShouldShowKeyring` was added in 1.60.1, which suggests a keyring exists). Iterate using `Enum.BagIndex` and guard `GetContainerNumSlots(bag) > 0`.

```lua
for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info and info.quality == Enum.ItemQuality.Poor and not info.hasNoValue then
            ns:QueueSell(bag, slot, info)
        end
    end
end
```

Events: `BAG_UPDATE(bagID)` fires per bag and in bursts; do work on `BAG_UPDATE_DELAYED()`, which fires once after the burst.

### Auras: `C_UnitAuras`, `AuraUtil`

```
C_UnitAuras.GetAuraDataByIndex(unit, index, filter?) -> AuraData?
C_UnitAuras.GetBuffDataByIndex(unit, index, filter?) / GetDebuffDataByIndex(unit, index, filter?)
C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID) -> AuraData?
C_UnitAuras.GetAuraDataBySpellName(unit, spellName, filter?) -> AuraData?
C_UnitAuras.GetPlayerAuraBySpellID(spellID) -> AuraData?
C_UnitAuras.GetUnitAuraBySpellID(unit, spellID) -> AuraData?
C_UnitAuras.GetUnitAuras(unit, filter, maxCount?, sortRule="Unsorted", sortDirection="Normal") -> table<AuraData>
C_UnitAuras.GetAuraSlots(unit, filter?, maxSlots?, continuationToken?) -> continuationToken?, ...slots
C_UnitAuras.GetAuraDataBySlot(unit, slot) -> AuraData?
C_UnitAuras.GetAuraDuration(unit, auraInstanceID) -> LuaDurationObject
UNIT_AURA(unitTarget, updateInfo { isFullUpdate, addedAuras?, updatedAuraInstanceIDs?, removedAuraInstanceIDs? })
AuraUtil.ForEachAura(unit, filter, batchSize, func, usePackedAura)   -- func returns true to stop; usePackedAura=true passes AuraData
AuraUtil.FindAuraByName(auraName, unit, filter)
AuraUtil.UnpackAuraData(auraData)        -- old positional return list
AuraUtil.CreateFilterString(...) / AuraUtil.AuraFilters
```

`UnitAura`, `UnitBuff`, `UnitDebuff` are **removed** (no definition, no bare call in the source). `AuraData` fields (from the long-standing structure; not re-read for Forever, [UNVERIFIED] field list): `name`, `icon`, `applications`, `dispelName`, `duration`, `expirationTime`, `sourceUnit`, `isStealable`, `spellId`, `auraInstanceID`, `isHelpful`, `isHarmful`, `isFromPlayerOrPlayerPet`, `points`, `timeMod`, `isBossAura`, `isRaid`, `nameplateShowAll`, `nameplateShowPersonal`, `canApplyAura`, `charges`, `maxCharges`. Note the field is `spellId` with a lowercase `d`.

Filters are strings: `"HELPFUL"`, `"HARMFUL"`, `"PLAYER"`, `"RAID"`, `"CANCELABLE"`, combined with `|` (`"HELPFUL|PLAYER"`). `"NOT_CANCELABLE"` was replaced by negation `"!CANCELABLE"` (12.x). [SRC `Blizzard_DeprecatedAuraFilters`]

```lua
local f = CreateFrame("Frame")
f:RegisterUnitEvent("UNIT_AURA", "player")
f:SetScript("OnEvent", function(_, _, unit, updateInfo)
    if not updateInfo or updateInfo.isFullUpdate then return ns:FullAuraScan(unit) end
    if updateInfo.addedAuras then
        for _, aura in ipairs(updateInfo.addedAuras) do ns:OnAuraAdded(unit, aura) end
    end
    if updateInfo.removedAuraInstanceIDs then
        for _, id in ipairs(updateInfo.removedAuraInstanceIDs) do ns:OnAuraRemoved(unit, id) end
    end
end)

local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
if aura and not issecretvalue(aura.expirationTime) then
    local remaining = aura.expirationTime - GetTime()
end
```

Aura data is conditionally secret (in combat and restricted content, per-spell exceptions). Track by `auraInstanceID` with incremental updates; do not rescan all auras on every `UNIT_AURA`. For displaying auras, 12.1.0 added `AuraContainer`/`AuraButton` widgets (`Blizzard_AuraContainer`, `C_AuraContainerUtil`) that render secret auras for you; Blizzard states these are available on Forever.

### Cooldowns

Covered above (`C_Spell.GetSpellCooldown`, `C_Item.GetItemCooldown`, `C_Container.GetContainerItemCooldown`). `Cooldown` widget: `cd:SetCooldown(start, duration, modRate)`, `cd:SetCooldownFromDurationObject(duration)`, `cd:SetCooldownFromExpirationTime(...)`, `cd:Clear()`. Events: `SPELL_UPDATE_COOLDOWN`, `BAG_UPDATE_COOLDOWN`, `ACTIONBAR_UPDATE_COOLDOWN`. Action-slot queries moved to `C_ActionBar.*` in 12.0.

### Units

Unit functions remain bare globals: `UnitName`, `UnitGUID`, `UnitClass`, `UnitRace`, `UnitLevel`, `UnitFactionGroup`, `UnitExists`, `UnitIsUnit`, `UnitIsPlayer`, `UnitHealth`, `UnitHealthMax`, `UnitPower`, `UnitAffectingCombat`, `UnitInParty`, `UnitInRaid`, `UnitIsGroupLeader`, `UnitCastingInfo`, `UnitChannelInfo`, `GetUnitName`, `UnitFullName`, `GetPlayerInfoByGUID`, `UnitTokenFromGUID`. Group: `IsInGroup`, `IsInRaid`, `GetNumGroupMembers`, `GetNumSubgroupMembers`, `GetRaidRosterInfo`. [SRC usage]

New in 12.0 for secret-safe display: `UnitHealthPercent`, `UnitHealthMissing`, `UnitPowerPercent`, `UnitPowerMissing`, `UnitCastingDuration`, `UnitChannelDuration`, `UnitNameFromGUID`, `UnitClassFromGUID`. `UnitCastingInfo` gained a 10th return `castBarID`; `notInterruptible` may be nil.

Classic-only unit functions were not found: `UnitPVPRank`, `UnitCharacterPoints`, `GetPVPRankInfo`, `GetHonorCurrency`. Pet happiness is `C_PetInfo.GetPetHappiness() -> happiness, damagePercentage, loyaltyRate`. Loot method is `C_PartyInfo.GetLootMethod() -> method, masterLootPartyID?, masterLooterRaidID?`.

### Maps: `C_Map`

```
C_Map.GetBestMapForUnit(unitToken) -> uiMapID?
C_Map.GetMapInfo(uiMapID) -> UiMapDetails { mapID, name, mapType, parentMapID, flags }
C_Map.GetPlayerMapPosition(uiMapID, unitToken) -> vector2?        -- position:GetXY() -> x, y in 0..1
C_Map.GetMapChildrenInfo(uiMapID, mapType?, allDescendants?) -> table<UiMapDetails>
C_Map.GetWorldPosFromMapPos(uiMapID, mapPosition) -> continentID, worldPosition
C_Map.GetMapInfoAtPosition(uiMapID, x, y) / C_Map.GetAreaInfo(areaID) -> name
```

```lua
local mapID = C_Map.GetBestMapForUnit("player")
local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
if pos then
    local x, y = pos:GetXY()
end
```

- `GetPlayerMapPosition` allocates a vector each call; do not call it every frame for many units. It returns nil in instances and for non-group units. `UnitPosition(unit)` is still a bare global.
- `uiMapID` numbers differ between games. Forever's zone IDs must be looked up on this client; do not copy retail or Classic Era tables without checking.
- Zone text globals remain: `GetZoneText`, `GetRealZoneText`, `GetSubZoneText`, `GetMinimapZoneText`.
- Removed: `GetCurrentMapAreaID`, `SetMapToCurrentZone`, bare `GetPlayerMapPosition`.
- Map pins: `MapCanvas` data providers and pin templates (`Blizzard_MapCanvas`, `Blizzard_SharedMapDataProviders`); the common library is HereBeDragons (listed in Questie's OptionalDeps).

### Quests: `C_QuestLog`

```
C_QuestLog.GetNumQuestLogEntries() -> numShownEntries, numQuests
C_QuestLog.GetInfo(questLogIndex) -> QuestInfo?      -- title, questLogIndex, questID, level, isHeader, isCollapsed, isHidden, frequency, ...
C_QuestLog.GetLogIndexForQuestID(questID) / GetQuestIDForLogIndex(index)
C_QuestLog.GetTitleForQuestID(questID)
C_QuestLog.GetQuestObjectives(questID) -> table<QuestObjectiveInfo>   -- text, type, finished, numFulfilled, numRequired
C_QuestLog.IsOnQuest(questID) / IsComplete(questID) / ReadyForTurnIn(questID)
C_QuestLog.IsQuestFlaggedCompleted(questID) / IsQuestFlaggedCompletedOnAccount(questID)
C_QuestLog.GetAllCompletedQuestIDs() -> table<number>
C_QuestLog.GetSelectedQuest() / SetSelectedQuest(questID)
C_QuestLog.GetQuestTagInfo(questID) / RequestLoadQuestByID(questID)
```

```lua
for i = 1, C_QuestLog.GetNumQuestLogEntries() do
    local info = C_QuestLog.GetInfo(i)
    if info and not info.isHeader and not info.isHidden then
        for _, obj in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
            -- obj.text, obj.finished, obj.numFulfilled, obj.numRequired
        end
    end
end
```

Removed: `GetQuestLogTitle`, `GetQuestLogIndexByID`, `IsQuestFlaggedCompleted`, `GetQuestsCompleted`, `GetQuestLogLeaderBoard` family in their Classic forms. Note: the repository contains `Vanilla/QuestLogFrame.lua` using `GetQuestLogTitle`, but that file loads only on Classic-family clients; do not take a hit in the repo as proof an API exists on Forever. Check the file's TOC condition. Some bare quest globals are still called from shared files (`GetNumQuestLeaderBoards`, `GetQuestLogSelection`, `GetQuestLink`, `GetQuestLogRewardMoney`, `GetQuestID`); whether those specific call sites load on Forever was not traced, so prefer the `C_QuestLog` forms. Gossip is `C_GossipInfo.GetOptions()`, `GetAvailableQuests()`, `GetActiveQuests()`, `SelectOption(optionID, text?, confirmed?)`. Events: `QUEST_LOG_UPDATE` (bursty; debounce), `QUEST_ACCEPTED`, `QUEST_REMOVED`, `QUEST_TURNED_IN`, `QUEST_WATCH_UPDATE`, `UNIT_QUEST_LOG_CHANGED`.

### Currency, reputation, skills, misc

```
C_CurrencyInfo.GetCurrencyInfo(type) -> CurrencyInfo            -- name, quantity, iconFileID, maxQuantity, ...
C_CurrencyInfo.GetCurrencyListSize() ; GetCurrencyListInfo(index) -> CurrencyInfo
C_CurrencyInfo.GetCoinTextureString(amount, fontHeight=14) -> string      -- replaces bare GetCoinTextureString
C_CurrencyInfo.GetCurrencyLink(type, amount?)
GetMoney() -> copper ; GetMoneyString(copper, separateThousands) -> string   -- still bare

C_Reputation.GetNumFactions() ; GetFactionDataByIndex(index) -> FactionData?
C_Reputation.GetFactionDataByID(factionID) ; GetWatchedFactionData()
   FactionData { factionID, name, description, reaction, currentReactionThreshold, nextReactionThreshold, currentStanding,
                 atWarWith, canToggleAtWar, isChild, isHeader, isHeaderWithRep, isCollapsed, isWatched, hasBonusRepGain,
                 canSetInactive, isAccountWide }

C_SkillInfo.GetNumSkillLines() ; GetSkillLineInfo(index) ; GetSkillLineInfoByID(ID) -> SkillLineAttributes
   { skillID, name, isHeader, isCollapsed, rank, tempPoints, modifier, maxRank, isAbandonable, ... }

C_MerchantFrame.GetItemInfo(index) -> MerchantItemInfo { name, texture, price, stackCount, numAvailable, isPurchasable, isUsable, hasExtendedCost, currencyID, spellID, isQuestStartItem }
C_FriendList.GetNumFriends() ; GetFriendInfoByIndex(index) ; GetFriendInfo(name)
C_GuildInfo.GuildRoster()                                       -- replaces GuildRoster()
C_Minimap.GetNumTrackingTypes() ; GetTrackingInfo(index) ; SetTracking(index, on)
C_SpecializationInfo.GetTalentInfo(query) -> TalentInfoResult    -- table in, table out
C_CVar.GetCVar(name) / SetCVar(name, value) / GetCVarBool(name) / GetCVarDefault(name) / RegisterCVar(name, value)
C_DateAndTime.GetCurrentCalendarTime() ; GetServerTime() ; GetTime() ; time() ; date()
C_StringUtil.StripHyperlinks(text, ...) ; C_StringUtil.BreakUpLargeNumbers(n) ; AbbreviateNumbers(n)
C_EncodingUtil.SerializeJSON / DeserializeJSON / SerializeCBOR / DeserializeCBOR / CompressString / DecompressString / EncodeHex / DecodeHex
```

- Removed: `GetFactionInfo`, `GetNumFactions`, `GetCurrencyInfo`, `GetNumSkillLines`/`GetSkillLineInfo` (bare), `GetMerchantItemInfo` (positional), `GetFriendInfo`, `GetTrackingInfo`, `GetGuildRosterInfo` was not seen in use ([UNVERIFIED] replacement), `GetCoinTextureString`.
- `C_SkillInfo` gives Forever a Classic-style skills list (weapon skills, professions with ranks) under a modern namespace.
- `GetCVar`/`SetCVar` still exist as Lua wrappers in `Blizzard_SharedXMLBase/CvarUtil.lua`; `C_CVar.*` is the direct form. `SetCVar` on protected CVars is blocked in combat or entirely.
- `C_EncodingUtil` gives native JSON/CBOR/Deflate, which removes the need for LibSerialize/LibDeflate in new code that only targets Mainline-family clients.
- Table and string helpers present and used by Blizzard: `CopyTable`, `tContains`, `tInvert`, `tIndexOf`, `tFilter`, `tAppendAll`, `MergeTable`, `wipe`, `tinsert`, `tremove`, `strsplit`, `strtrim`, `string.split`, `GenerateClosure`, `RunNextFrame`, `ipairs_reverse`, `Clamp`, `table.create`, `table.count`, `securecallfunction`.
- `getglobal`/`setglobal` are deprecated shims: use `_G[name]`.

---

## 12. Localization, escapes, performance, SavedVariables design

### Localization

[WIKI] <https://warcraft.wiki.gg/wiki/Localizing_an_addon>

```
GetLocale() -> "enUS" | "deDE" | "frFR" | "esES" | "esMX" | "ptBR" | "ruRU" | "koKR" | "zhCN" | "zhTW" | "itIT"
```

`GetLocale()` returns `"enUS"` on enGB clients. This install is enUS.

Namespace-table pattern with English fallback:

```lua
-- Locales\enUS.lua   (listed first in the TOC; always loaded)
local ADDON, ns = ...
local L = setmetatable({}, {
    __index = function(t, k)        -- missing key: show the key itself and cache it
        rawset(t, k, k)
        return k
    end,
})
ns.L = L
L["Enable"] = "Enable"
L.RESET_CONFIRM = "Reset all data for %s?"

-- Locales\deDE.lua
local ADDON, ns = ...
if GetLocale() ~= "deDE" then return end
local L = ns.L
L["Enable"] = "Aktivieren"
L.RESET_CONFIRM = "Alle Daten für %s zurücksetzen?"
```

TOC options, newest first:

```
Locales\enUS.lua
Locales\[TextLocale].lua                          # 11.2.0+: loads only the matching file; the enUS line above is the fallback
# or
Locales\deDE.lua [AllowLoadTextLocale deDE]
# or simply list every file and let each one early-return on GetLocale()
```

With `[TextLocale]`, a missing file for a locale is a load error for that line ([UNVERIFIED]: whether it is silent). Listing explicit files with `AllowLoadTextLocale` avoids the question.

- Reuse Blizzard **global strings** wherever one fits; they are already translated: `OKAY`, `CANCEL`, `YES`, `NO`, `ACCEPT`, `CLOSE`, `DEFAULTS`, `ENABLE`, `DISABLE`, `SETTINGS`, `NONE`, `ALL`, `UNKNOWN`, `ITEM_SOULBOUND`, `ERR_NOT_IN_COMBAT`, class names in `LOCALIZED_CLASS_NAMES_MALE[classFile]`. Full list: <https://www.townlong-yak.com/framexml/live/GlobalStrings.lua> (retail; Forever's set differs, so nil-check: `local text = SOME_GLOBAL or "Fallback"`).
- Never parse localized chat/system text with English patterns. Build patterns from the global format strings (`ERR_QUEST_COMPLETE_S`, `LOOT_ITEM_SELF`) by converting `%s`/`%d` to captures.
- Use `format` with positional args for word order: `"%2$s has %1$d"`.
- Compare class and race by file token (`select(2, UnitClass("player"))` -> `"MAGE"`), never by localized name.
- TOC `Title-xxXX` / `Notes-xxXX` localize the AddOn list entry.
- 12.1.5 added `C_Intl` (locale-aware formatting, plural selection, collation). Present in the 12.1.5 additions list; presence on Forever not individually checked: [UNVERIFIED].

### Colour codes and escape sequences

[WIKI] <https://warcraft.wiki.gg/wiki/UI_escape_sequences>

| Sequence | Meaning |
|---|---|
| `\|cAARRGGBB` ... `\|r` | Colour. Alpha byte is ignored; write `ff`. `\|r` ends the colour. |
| `\|cnCOLOR_NAME:` ... `\|r` | Named global colour, e.g. `\|cnGREEN_FONT_COLOR:text\|r` (10.0+). |
| `\|Hlinktype:payload\|h[text]\|h` | Hyperlink. |
| `\|Tpath:height:width:offsetX:offsetY\|t` | Inline texture. Size `0` = match text height. Long form adds `:texW:texH:left:right:top:bottom:r:g:b`. |
| `\|A:atlas:height:width:offsetX:offsetY\|a` | Inline atlas. |
| `\|n` | Newline. |
| `\|\|` | Literal pipe. |
| `\|Kxxx\|k` | Protected (Battle.net) string; unreadable. |
| `\|4singular:plural;` | Plural by the preceding number (`"%d \|4item:items;"`). |
| `\|1`, `\|2`, `\|3-n(...)` | Grammar helpers for Korean, French, Russian. |

In Lua source write a single `|` (`"|cffff0000red|r"`); in the chat edit box and in `/run` type `\124` or `||`.

Helpers [SRC] `Blizzard_SharedXMLBase` colour utilities:

```
CreateColor(r, g, b, a) -> ColorMixin
CreateColorFromHexString("ffrrggbb") / CreateColorFromRGBHexString("rrggbb") / CreateColorFromBytes(r, g, b, a)
color:GetRGB() / GetRGBA() / GetRGBAsBytes() / GenerateHexColor() / GenerateHexColorNoAlpha() / GenerateHexColorMarkup()
color:WrapTextInColorCode(text) / color:SetRGBA(r, g, b, a) / color:IsEqualTo(other)
WrapTextInColorCode(text, "ffrrggbb")        -- hex string, with alpha byte
WrapTextInColor(text, colorObject)
CreateAtlasMarkup(atlasName, width, height, offsetX, offsetY, r, g, b)
CreateTextureMarkup(file, fileWidth, fileHeight, width, height, left, right, top, bottom, xOffset, yOffset)
CreateSimpleTextureMarkup(file, width, height, xOffset, yOffset)
GetClassColor(classFile) -> r, g, b, hex ; GetClassColorObj(classFile) ; GetClassColoredTextForUnit(unit, text)
C_Item.GetItemQualityColor(quality) -> r, g, b, hex
```

```lua
local PREFIX = WrapTextInColorCode("MyAddon:", "ff33ff99")
print(PREFIX, GREEN_FONT_COLOR:WrapTextInColorCode("ready"))
local classColor = RAID_CLASS_COLORS[select(2, UnitClass("player"))]      -- a ColorMixin
name:SetText(classColor:WrapTextInColorCode(UnitName("player")))
label:SetText(CreateSimpleTextureMarkup("Interface\\Icons\\INV_Misc_Coin_01", 14, 14) .. " 12")
```

Global colour objects: `NORMAL_FONT_COLOR` (gold), `HIGHLIGHT_FONT_COLOR` (white), `RED_FONT_COLOR`, `GREEN_FONT_COLOR`, `GRAY_FONT_COLOR`, `YELLOW_FONT_COLOR`, `ORANGE_FONT_COLOR`, `DISABLED_FONT_COLOR`, `ITEM_QUALITY_COLORS[quality]`, `RAID_CLASS_COLORS[classFile]`. Strip markup with `C_StringUtil.StripHyperlinks(text, maintainColor, maintainBrackets, stripNewlines, maintainAtlases, maintainTextures)`. Text passed to `SetText` may be a secret string; `WrapTextInColorCode` concatenates and is allowed on secrets, but measuring or pattern-matching is not.

### Performance

- **Events over polling.** Register only what you need; unregister when a feature is off or the window is hidden. Use `RegisterUnitEvent` for `UNIT_*`.
- **Debounce bursty events** (`BAG_UPDATE`, `QUEST_LOG_UPDATE`, `UNIT_AURA`, `GROUP_ROSTER_UPDATE`, `SPELLS_CHANGED`) with a flag plus `C_Timer.After(0.05..0.2, ...)` or `RunNextFrame`. Prefer the "delayed" variant where one exists (`BAG_UPDATE_DELAYED`).
- **Do nothing while hidden.** Put refresh logic behind `if not frame:IsShown() then dirty = true return end` and refresh in `OnShow`.
- **OnUpdate** runs per rendered frame (144+ times a second). Throttle with an elapsed accumulator, and clear the script when idle.
- **Local upvalues** for hot paths only: `local pairs, GetTime, format = pairs, GetTime, string.format`. It saves a global table lookup per call; it matters inside loops and `OnUpdate`, not in one-shot code. Do not upvalue functions you may want hooks or shims to affect.
- **Garbage:** avoid creating tables, closures, and concatenated strings per frame or per event. Reuse scratch tables with `wipe(t)`; define callbacks once outside the loop; build long strings with `table.concat`. `SetText` with an unchanged string is cheap, but building that string is not: cache the last value and skip.
- **Table reuse:** `table.create(arraySize, hashSize)` preallocates; `wipe` keeps the allocation.
- **Avoid `string.format`/`..` in debug calls that are disabled:** `if ns.db.debug then print(...) end`, not `Debug(format(...))`.
- **Frames:** never create frames repeatedly; pool or use ScrollBox. Hide a parent rather than many children. Avoid `SetPoint` churn in loops.
- **Large static data** (databases): store as plain tables in their own file, consider LoadOnDemand companion addons (Questie splits `QuestieDB`). Lazy-build indexes with a coroutine.
- **SavedVariables size** affects login and logout time; the whole table is serialized on every reload.
- `collectgarbage("count")` gives total Lua memory in KB; never call `collectgarbage("collect")` in normal operation.

Profiling [DOC] `AddOnProfilerDocumentation.lua`, [WIKI] <https://warcraft.wiki.gg/wiki/API_C_AddOnProfiler.GetAddOnMetric>:

```
C_AddOnProfiler.IsEnabled() -> bool
C_AddOnProfiler.GetAddOnMetric(name, metric) -> number          -- milliseconds, or a count for the Count* metrics
C_AddOnProfiler.GetOverallMetric(metric) / GetApplicationMetric(metric)
C_AddOnProfiler.GetTopKAddOnsForMetric(metric, k) -> { { addOnName, metricValue }, ... }
C_AddOnProfiler.MeasureCall(func, ...) -> results, ...returns
Enum.AddOnProfilerMetric: SessionAverageTime, RecentAverageTime, EncounterAverageTime, LastTime, PeakTime,
    CountTimeOver1Ms, CountTimeOver5Ms, CountTimeOver10Ms, CountTimeOver50Ms, CountTimeOver100Ms, CountTimeOver500Ms, CountTimeOver1000Ms
```

```lua
if C_AddOnProfiler and C_AddOnProfiler.IsEnabled() then
    local recent = C_AddOnProfiler.GetAddOnMetric(ADDON, Enum.AddOnProfilerMetric.RecentAverageTime)
    local peak   = C_AddOnProfiler.GetAddOnMetric(ADDON, Enum.AddOnProfilerMetric.PeakTime)
    print(("%s: %.3f ms/frame recent, %.2f ms peak"):format(ADDON, recent, peak))
end
```

The client itself warns users about slow addons (`Blizzard_AddOnPerformance`, `C_AddOnProfiler.CheckForPerformanceMessage`). Micro-timing: `debugprofilestop()` returns milliseconds with sub-ms precision. The old `scriptProfile` CVar functions (`GetAddOnCPUUsage`, `GetFunctionCPUUsage`) were removed from retail in 11.x; `UpdateAddOnMemoryUsage`/`GetAddOnMemoryUsage` are still called by Blizzard code on this client.

### SavedVariables design

[WIKI] <https://warcraft.wiki.gg/wiki/Saving_variables_between_game_sessions>

Mechanics:

- Declared globals are written to disk at logout, `/reload`, and exit. **Not** on crash or Alt-F4; data since the last reload is lost.
- Loaded after the addon's files (before them with `LoadSavedVariablesFirst: 1`), available from `ADDON_LOADED`.
- **Serializable:** strings, numbers, booleans, and tables of those (nested). Keys may be strings or numbers. **Dropped silently:** functions, userdata (frames, `ColorMixin` instances keep their fields but lose methods), threads, metatables. Cyclic references are not preserved as shared references. `nil` values vanish. NaN and infinity do not round-trip safely; sanitize.
- Secret values cannot be saved meaningfully; never store API returns from combat contexts without `issecretvalue` checks.
- Array part with holes is saved as explicit keys, which bloats the file. Keep arrays dense.
- The file is Lua source; a file that is too large fails with `SAVED_VARIABLES_TOO_LARGE`.
- Do not edit `WTF` files while the game is running; the client overwrites them at exit.

Defaults that do not get saved, plus versioned migrations:

```lua
local ADDON, ns = ...

local DB_VERSION = 3
local defaults = {
    enabled = true,
    scale = 1,
    minimap = { hide = false },
    window = { point = "CENTER", x = 0, y = 0 },
}

-- copy missing keys only; never overwrite user values
local function ApplyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            ApplyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

-- remove values equal to the default before saving, so changed defaults reach existing users
local function StripDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" and type(dst[k]) == "table" then
            StripDefaults(dst[k], v)
            if next(dst[k]) == nil then dst[k] = nil end
        elseif dst[k] == v then
            dst[k] = nil
        end
    end
end

local migrations = {
    [1] = function(db) db.scale = db.size and db.size / 100 or nil; db.size = nil end,   -- v1 -> v2
    [2] = function(db) db.window = { point = db.point, x = db.x, y = db.y }; db.point, db.x, db.y = nil end,
}

function ns:InitDB()
    local db = MyAddonDB
    if type(db) ~= "table" then db = { version = DB_VERSION }; MyAddonDB = db end
    local v = tonumber(db.version) or 1
    if v > DB_VERSION then
        -- saved by a newer version of the addon: do not migrate downward, keep what fits
        v = DB_VERSION
    end
    while v < DB_VERSION do
        local step = migrations[v]
        if step then step(db) end
        v = v + 1
    end
    db.version = DB_VERSION
    ApplyDefaults(db, defaults)
    ns.db = db
end

function ns:PLAYER_LOGOUT()
    StripDefaults(ns.db, defaults)
    ns.db.version = DB_VERSION
end
```

- Type-check what you load. Users hand-edit and share files; a string where a table is expected must not break login.
- Write migrations as small numbered steps, each idempotent. Never delete user data in the same release that introduces its replacement.
- `StripDefaults` at logout is optional. Without it, a default you change later never reaches users who already have the old value stored.

Account vs character:

- `SavedVariables` for settings and cross-character data; `SavedVariablesPerCharacter` for character state (positions per character, per-character toggles, cached character data).
- A common single-file layout keeps everything account-wide and keys by character, so alts' data can be shown:

```lua
local charKey = UnitName("player") .. " - " .. GetNormalizedRealmName()     -- valid from PLAYER_LOGIN
MyAddonDB.chars = MyAddonDB.chars or {}
MyAddonDB.chars[charKey] = MyAddonDB.chars[charKey] or {}
ns.char = MyAddonDB.chars[charKey]
```

  `GetNormalizedRealmName()` can be nil very early; build the key at `PLAYER_LOGIN`. `UnitGUID("player")` is a stable alternative key for players.

Profiles:

```lua
-- MyAddonDB = { version = n, profiles = { Default = {...} }, profileKeys = { ["Name - Realm"] = "Default" } }
function ns:SetProfile(name)
    local db = MyAddonDB
    db.profiles[name] = ApplyDefaults(db.profiles[name] or {}, profileDefaults)
    db.profileKeys[ns.charKey] = name
    ns.profile = db.profiles[name]
    ns.Bus:TriggerEvent("ProfileChanged", name)       -- every module re-reads ns.profile
end
```

- Modules must read through `ns.profile` at use time, not cache sub-tables, or a profile switch leaves stale references. The same trap applies to `Settings.RegisterAddOnSetting`'s captured `variableTbl`: with profiles, use proxy settings.
- AceDB-3.0 (<https://www.wowace.com/projects/ace3>) implements exactly this shape (profiles, char, realm, class, faction, global scopes, default stripping). Questie lists Ace3 as an optional dep, so it loads on Forever. Use it for an addon that needs profiles; hand-roll for a small one.
- Export/import strings: `C_EncodingUtil.SerializeCBOR` -> `CompressString` -> base64/hex. Validate everything on import.

---

## Appendix A. Could not confirm

Consolidated list of the [UNVERIFIED] items above, most consequential first:

1. Which addon restriction types (secrets) are active in which Forever content. Blizzard says the system is active; the per-context behaviour was not found.
2. What `C_Macro.RunMacroText` accepts from `macrotext` on addon-created secure buttons on Forever.
3. StaticPopup accessors other than `GetEditBox()` (buttons, text region).
4. `SendAddonMessage` chat types on Forever (`CHANNEL` vs `SAY`/`YELL` availability).
5. Whether tainted code can call `RegisterEventCallback` and whether `Settings.OpenToCategory` works in combat.
6. TOC parsing of BOM / CRLF, variables inside `##` directives on Forever, and behaviour of `[TextLocale]` when the file is missing.
7. `AuraData` field list and tooltip `data` field list on this client.
8. Pool reset function signature details, `SetUserPlaced` behaviour, whether new texture files need a client restart.
9. NineSlice layout names, atlas names, global strings and uiMapIDs available on Forever (all differ from retail; check per use).
10. Bag layout on Forever (reagent bag, keyring) and several bare quest-log globals.
11. Library version compatibility (LibDBIcon, LibDataBroker, LibEditMode, ChatThrottleLib, Ace3) with 16001; all are plausible from their TOCs or from Questie's dependency list, none were run.

## Appendix B. Sources

- Blizzard UI source, Forever branch: <https://github.com/Gethe/wow-ui-source/tree/forever> (commit `c01a87b`, 1.60.1.71091). Diff against retail: <https://github.com/Gethe/wow-ui-source/compare/12.1.5..forever>
- <https://warcraft.wiki.gg/wiki/TOC_format>
- <https://warcraft.wiki.gg/wiki/AddOn_loading_process>
- <https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes> and <https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes/notes>
- <https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes>, <https://warcraft.wiki.gg/wiki/Patch_12.1.5/API_changes>, <https://warcraft.wiki.gg/wiki/Patch_11.0.2/API_changes>
- <https://warcraft.wiki.gg/wiki/Secret_Values>, <https://warcraft.wiki.gg/wiki/Secret_aspects>
- <https://warcraft.wiki.gg/wiki/Settings_API>
- <https://warcraft.wiki.gg/wiki/Blizzard_Menu_implementation_guide>
- <https://warcraft.wiki.gg/wiki/Making_scrollable_frames>
- <https://warcraft.wiki.gg/wiki/Addon_compartment>
- <https://warcraft.wiki.gg/wiki/Creating_key_bindings>
- <https://warcraft.wiki.gg/wiki/API_C_ChatInfo.SendAddonMessage>
- <https://warcraft.wiki.gg/wiki/API_C_Timer.NewTimer>, <https://warcraft.wiki.gg/wiki/API_hooksecurefunc>, <https://warcraft.wiki.gg/wiki/API_import>
- <https://warcraft.wiki.gg/wiki/Secure_Execution_and_Tainting>, <https://warcraft.wiki.gg/wiki/SecureActionButtonTemplate>, <https://warcraft.wiki.gg/wiki/SecureStateDriver>
- <https://warcraft.wiki.gg/wiki/CVar_loadDeprecationFallbacks>
- <https://warcraft.wiki.gg/wiki/UI_escape_sequences>, <https://warcraft.wiki.gg/wiki/Localizing_an_addon>, <https://warcraft.wiki.gg/wiki/Saving_variables_between_game_sessions>
- LibEditMode: <https://github.com/p3lim-wow/LibEditMode> and its wiki
- Local reference addon: `Interface\AddOns\Questie\Questie_Forever.toc` and `Bindings.xml` in the Forever install
