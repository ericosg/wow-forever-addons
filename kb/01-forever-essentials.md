# Forever essentials

Status of every statement: checked against `reference/wow-ui-source` at 1.60.1.71091 unless marked **(Blizzard statement)**, **(observed)** or **(unconfirmed)**. "Observed" means recorded by ForeverDevKit in the live client on 2026-11-25 (build 71091, level 29 hunter, open world, Enhanced preset); section 6 has the raw results. Remaining unknowns: [04-open-questions.md](04-open-questions.md).

## 1. What this client is

WoW Forever is a **retail-engine client with Classic-flavoured content**. Blizzard describes it as a second game type (`camelot`, alias `forever`) inside the Mainline code family, sharing "the vast majority of APIs available in 12.1.5" (Blizzard statement, 2026-09-15).

| | |
|---|---|
| TOC | `## Interface: 16001` |
| Detect in Lua | `WOW_PROJECT_ID == WOW_PROJECT_CAMELOT` (18, observed). Also valid: `select(4, GetBuildInfo())` in 16000..19999 |
| Game type / family | `camelot` (alias `forever`) / `mainline`. `[Family]` expands to `Mainline`, `[Game]` to `Camelot` |
| Lua | 5.1, no `goto`, no integer division, no `bit32` (use `bit`) |
| Content | Level cap 60, nine classic classes, classic races plus Skyborne, `LE_EXPANSION_LEVEL_CURRENT = 0` |
| Blizzard's Forever-specific code | `Camelot/` subfolders in `reference/wow-ui-source/Interface/AddOns/Blizzard_*` |

**Write Forever addons as Midnight-era retail addons, then subtract retail-only systems and add the Classic ones.** Never start from Classic Era idioms.

## 2. The five ways old knowledge breaks

### 2.1 Legacy globals do not exist

Not present, with no shim: `GetSpellInfo`, `GetSpellCooldown`, `GetItemInfo`, `GetItemCount`, `UnitAura`, `UnitBuff`, `UnitDebuff`, `IsAddOnLoaded`, `GetAddOnMetadata`, `GetContainerItemInfo`, `GetQuestLogTitle`, `GetNumTalentTabs`, `GetTalentInfo`, `GetNumSkillLines`, `SendAddonMessage`, `GetMouseFocus`, `EasyMenu`, `InterfaceOptions_AddCategory`, `CombatLogGetCurrentEventInfo`.

Use `C_Spell`, `C_Item`, `C_UnitAuras`, `C_AddOns`, `C_Container`, `C_QuestLog`, `C_SpecializationInfo` / `C_Traits`, `C_SkillInfo`, `C_ChatInfo`, `GetMouseFoci`, `MenuUtil`, `Settings`. Several return **tables** where the old global returned a tuple (`C_Spell.GetSpellInfo`, `C_Container.GetContainerItemInfo`, `C_UnitAuras.*`).

`SendChatMessage`, `GetActionCooldown`, `ChatFrame_AddMessageEventFilter` and friends exist only through `Blizzard_Deprecated*` shims gated on the `loadDeprecationFallbacks` CVar (observed: the CVar is `1` and those two are functions; `UIDropDownMenu_Initialize` also still exists). Do not use them; call `C_ChatInfo.SendChatMessage`, `C_ActionBar.*`, `ChatFrameUtil.*`.

`tools\check.ps1` enforces this: luacheck fails on any global or `C_*` field that is not on the Forever client.

### 2.2 Secret values are active

The Midnight "addon disarmament" applies (Blizzard statement). In restricted contexts, APIs return **secret values**: opaque boxes that addon code may store, pass on, concatenate, and hand to specific widget setters, but may not inspect.

| On a secret | Result |
|---|---|
| arithmetic, comparison, `#`, use as table key, index, call, `if secretBoolean` | **Lua error** |
| `..`, `string.format`, store in a variable or table value, pass to a Lua function | allowed (result is secret) |
| pass to a C API | only if that API's doc says `SecretArguments = "AllowedWhenTainted"` |
| save to SavedVariables | written as `nil` |

Rules:

- **Display, do not decide.** Feed values straight to `StatusBar:SetValue` / `SetMinMaxValues`, `FontString:SetText` / `SetFormattedText`, `SetAlpha`, `SetVertexColor`. Use `SetAlphaFromBoolean` for secret booleans (`SetShown(secret)` is not allowed from addon code), `UnitHealthPercent(unit, true, curve)` and curve objects for thresholds and colours, duration objects with `SetCooldownFromDurationObject` / `SetTimerDuration` for timers.
- **Guard before logic:** `if issecretvalue(v) then <display only> else <logic> end`. Predict with `C_Secrets.Should*BeSecret(...)`. Never infer secrecy from `InCombatLockdown()`.
- Never key a table by a possibly-secret value (GUID, name, spellID, auraInstanceID) without the guard.
- Which restriction is live: `C_RestrictedActions.IsAddOnRestrictionActive(Enum.AddOnRestrictionType.X)` with `Combat=0, Encounter=1, ChallengeMode=2, PvPMatch=3, Map=4, Chat=5`; event `ADDON_RESTRICTION_STATE_CHANGED`.
- All addon code is tainted, always. "AllowedWhenUntainted" in the API docs means "not for addons".
- Test paths out of combat with `secretwrap(42)` and the CVars `addonCombatRestrictionsForced`, `addonEncounterRestrictionsForced`, `addonChatRestrictionsForced` (not persisted).

What is secret when (observed, open world):

| Value | Out of combat | In combat |
|---|---|---|
| `UnitHealth("player")`, `UnitPower("player")` | **secret** | secret |
| `UnitHealthMax("player")` | readable | readable |
| `UnitHealth("target")`, `UnitHealthMax("target")` (hostile NPC) | not probed | **secret** |
| `UnitName`, `UnitGUID` (player and target), `UnitLevel("target")` | readable | readable |
| Auras, cooldowns, unit stats (`C_Secrets.ShouldAurasBeSecret()` etc.) | readable | **secret** |
| `C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL")` | not probed | **raises a Lua error** |

- **Current health and power are always secret, even standing in town.** There is no state in which `if UnitHealth("player") < x` is legal. Use `UnitHealthPercent` with a curve, or status bars.
- **Every open-world fight activates the `Combat` restriction** (state 2); `Encounter`, `Map` and `Chat` stayed inactive, and `C_ChatInfo.InChatMessagingLockdown()` stayed false. Auras and cooldowns are therefore unreadable in any combat, not only in instances.
- Read auras, cooldowns and stats **out of combat** and cache what you need; in combat, call nothing in `C_UnitAuras` by index without `C_Secrets.ShouldAurasBeSecret()` returning false first.
- `tostring(secret)` returns a secret string. `type(secret)` returns the real type.

Check any API before use: `python tools/wowapi.py C_UnitAuras.GetAuraDataByIndex` prints its secret flags. Dungeon, raid and PvP behaviour is **unconfirmed**.

Full treatment: [research/secret-values-and-restrictions.md](research/secret-values-and-restrictions.md).

### 2.3 No combat log for addons

There is no insecure `C_CombatLog.GetCurrentEventInfo`; Blizzard's parser runs in a secure environment. `C_CombatLog.IsCombatLogRestricted()` returns true at all times, in and out of combat (observed). Do not register `COMBAT_LOG_EVENT_UNFILTERED` (reported to raise a blocked-action error; exact behaviour unconfirmed).

Use instead: `C_DamageMeter` (built-in meter data; loads on Forever), `PLAYER_SWING` + `C_SwingTimer` (Forever-only), `UNIT_SPELLCAST_*`, `UNIT_AURA` + `C_UnitAuras` (restricted in combat), `UNIT_HEALTH`, `UNIT_POWER_UPDATE`, `ENCOUNTER_START` / `ENCOUNTER_END`, `UNIT_DIED`, `PARTY_KILL`, threat APIs.

### 2.4 Names have surnames, not realms

Names are regionally unique. `UnitName(unit)`, `UnitNameUnmodified(unit)` and `UnitFullName(unit)` all return `name, surname`; the separator is a **space** (`Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR`). Blizzard's own helper is `NameUtil.GetUnmodifiedUnitFullName(unit)`.

Observed for the player: `UnitName("player")` gives `"Firstname", "Surname"`; `NameUtil.GetUnmodifiedUnitFullName("player")` gives `"Firstname Surname"`; **`GetRealmName()` and `GetNormalizedRealmName()` both return the empty string**; `UnitGUID("player")` is `Player-<id>-<hex>` and readable. Any `name .. "-" .. GetRealmName()` key becomes `"Firstname-"`. The character's WTF folder is named `Firstname-Surname`.

- `Name-Realm` parsing (`strsplit("-", sender)`, `gsub("%-.*", "")`) is wrong here. A server change around 2026-11-21 removed realm names from sender strings and broke BigWigs, ElvUI and Details.
- Key player data by GUID.
- Sender and whisper-target string formats are **unconfirmed**; test before relying on them.

### 2.5 `C_Something ~= nil` proves nothing

Only 10 globals were removed versus retail, so `C_Housing`, `C_Garrison`, `C_MythicPlus`, `C_EncounterJournal` and the rest are non-nil even though their systems do not exist. Feature-detect by behaviour or game rule (`C_GameRules.IsGameRuleActive(Enum.GameRule.X)`), or by whether the owning Blizzard addon is allowed on `camelot`.

Conversely, a `Name_Mainline.toc` **does** load on Forever, and `Name_Classic.toc` does not.

## 3. Systems

| Present | Absent |
|---|---|
| Settings API, `MenuUtil`, ScrollBox, Edit Mode, addon compartment, AuraContainer | Encounter Journal, boss timeline / encounter warnings UI |
| Built-in damage meter (`C_DamageMeter`, CVar `damageMeterEnabled`), Cooldown Viewer | Housing, War Mode, Mythic+, Delves, Great Vault, Garrison UI, Trading Post |
| Retail professions UI, retail auction house, collections, nameplates (retail engine) | Retail Group Finder and retail PvP UI |
| Vanilla-style group finder, hardcore UI, keyring, ammo slot, totem bar, weapon skills (`C_SkillInfo`) | `C_Engraving`, `C_Seasons` |

Forever-only: swing timer (`PLAYER_SWING`, `C_SwingTimer`, Edit Mode system 29), the **Legacy** system (no namespace of its own: built on `C_Traits` trees 1187/1188/1189 and `C_MajorFactions` faction 2802), gamepad UI (`C_GamepadUI`, `InputUtil.IsGamepadUIEnabled()`), experience presets (`C_GameRules.GetForeverExperiencePreset()`).

Talents are the retail Traits system with classic-shaped trees (`Enum.TraitConfigType.CamelotCombat = 4`); dual spec via `C_SpecializationInfo.GetActiveSpecGroup` / `SetActiveSpecGroup`.

The player, target, pet, focus and totem frames and the minimap header were reskinned and their child frames reorganised late in beta. Before anchoring to or skinning a Blizzard frame, read its current definition under `reference/wow-ui-source/.../Camelot/`.

## 4. Other restrictions worth knowing

- Addon messages: `C_ChatInfo.SendAddonMessage` returns `Enum.SendAddonMessageResult` (check it; `AddOnMessageLockdown = 11`), never accepts secrets, is blocked during encounters / PvP matches (`C_ChatInfo.InChatMessagingLockdown()`), and is unavailable to trial accounts.
- `C_ChatInfo.SendChatMessage` to `SAY`, `YELL` and `EMOTE` needs a hardware event outside instances.
- Creature, pet, vehicle and object GUIDs have obfuscated server and spawn fields (layer detection is blocked). The NPC ID field still parses.
- Protected-frame rules are unchanged from retail: no `Show`/`Hide`/`SetPoint`/`SetAttribute` on secure frames in combat; defer to `PLAYER_REGEN_ENABLED`.

## 5. Error messages you will see (observed wording, 1.60.1)

| Message | Cause |
|---|---|
| `attempt to perform arithmetic on a secret number value (execution tainted by 'Foo')` | arithmetic on a secret |
| `attempt to compare a secret number value (execution tainted by 'Foo')` | comparison on a secret |
| `attempted to perform indexed assignment on a table that cannot be indexed with secret keys` | secret used as a table key |
| `GetAuraDataByIndex(): Auras cannot be accessed when secret while tainted by 'Foo'` | aura API called while auras are secret (any combat) |

The taint name is the addon's name. Code compiled with `loadstring` (ForeverDevKit probes, `/run`) reports `*** ForceTaint_Strong ***` instead. `pcall` catches all four.

## 6. Other observed facts (2026-11-25)

- `GetBuildInfo()` returns `"1.60.1", "71091", "Nov 20 2026", 16001, "", " "`.
- `GetExpansionLevel()` 0, `GetMaxPlayerLevel()` 60, `C_GameRules.IsHardcoreActive()` false, `C_GameRules.GetForeverExperiencePreset()` 1 (Enhanced) on this account.
- `C_Secrets.HasSecretRestrictions()` true; `canaccesssecrets()` false for addon code.
- `C_DamageMeter.IsDamageMeterAvailable()` returns `true, ""`; CVar `damageMeterEnabled` is `1`, `cooldownViewerEnabled` `0`, `scriptErrors` `0`.
- `C_SpecializationInfo.GetSpecialization()` returns 1 and `GetActiveSpecGroup()` 1 on a level 29 hunter.
- A new addon folder was picked up after a full client restart.
- Auction house (retail UI): each browse row is an item key that includes the random suffix, and `C_TooltipInfo.GetItemKey(itemID, itemLevel, itemSuffix, requiredLevel)` returns that row's real stat lines (`+9 Agility`). Seen with AuctionStatFilter on "of the Falcon" items.
- Every browse-row tooltip ends with the line "Items in this group may vary in stats and appearance. Check the auction's tooltip before buying.", and `C_AuctionHouse.GetItemKeySampleLink(itemKey)` already returns a link at browse time (80 of 80 rows), e.g. `|Hitem:1369::::::::29:1485:::::::::|h`.
- **Item data that is not cached yet yields a partial tooltip with no stat lines, not nil.** Check `C_Item.IsItemDataCachedByID(id)` before trusting tooltip or item info, request with `C_Item.RequestLoadItemDataByID`, and retry on `ITEM_DATA_LOAD_RESULT`. Caching a result read too early was the cause of AuctionStatFilter's first bug.
- An addon can replace `AuctionHouseFrame.BrowseResultsFrame.browseResults` (after `hooksecurefunc` on `UpdateBrowseResults`) and refresh the list without Lua errors or blocked actions; a 4,392-row armor search filtered fine. Buying out an item from a list filtered this way works: `AUCTION_HOUSE_PURCHASE_COMPLETED` fired, with no blocked action or error (2026-11-25). So `C_AuctionHouse.PlaceBid` tolerates an addon-tainted browse list.
- Auction house Sell tab (observed 2026-11-25 with AuctionSuffixPrice):
  - Blizzard looks equipment up by item ID alone (`AuctionHouseUtil.ConvertItemSellItemKey` zeroes level and suffix), so the price list and the suggested price mix every random suffix. For green items `GetBestEntry` takes the cheapest row of any suffix.
  - Each sell-search row still carries its own `itemKey.itemSuffix` and `itemKey.itemLevel` (for example 14308 "of Agility", 14312 "of Strength" on item 9809) and an `itemLink` with the suffixed name. `C_AuctionHouse.GetItemKeyFromItem(itemLocation)` returns the same suffix for the item in the bag, so comparing the two numbers identifies the variant; 40 of 40 and 46 of 46 rows were classified with none undecided.
  - Item links have no suffix field: `|Hitem:9809::::::::29:1485::1:1:12728:1:28:4512:::::|h[Superior Tunic of Agility]|h`. The variant shows up only as a bonus-style ID near the end (12728 here, 12732 for "of Strength"). Use the item key, not the link, to tell variants apart.
  - Wrapping the sell list's data provider (`ItemSellList:SetDataProvider` with functions that skip rows) and selecting a row with `SetSelectedEntry` from addon code did not stop `C_AuctionHouse.PostItem`: the auction was created (`AUCTION_HOUSE_AUCTION_CREATED`).
  - Writing level and suffix back into `ItemSellFrame.listDisplayedItemKey` and calling `AuctionHouseFrame:QueryItem(context, key, false)` returns only the exact variant, the same rows as the Buy tab, and posting still worked afterwards. AuctionSuffixPrice does not use this: it costs a search per change and shows the default price while the search is in flight; filtering the rows already fetched is instant.
  - A second search sent right after Blizzard's own is not dropped: `AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED` fires and it goes out when `AUCTION_HOUSE_THROTTLED_SYSTEM_READY` arrives, about one to two seconds later.
  - ForeverDevKit was disabled for the runs above, so they have no error record; none were visible to the user. Later sessions with ForeverDevKit, AuctionStatFilter and AuctionSuffixPrice loaded together recorded 0 Lua errors and 0 blocked actions.
  - Stackable items (trade goods, fish) placed on the Sell tab go to `CommoditiesSellFrame` / `CommoditiesSellList`, not `ItemSellFrame` / `ItemSellList`; hooks on the item frames never see them.

## 7. Pre-flight checklist

1. TOC has `## Interface: 16001`; SavedVariables are prefixed with the addon name.
2. Every API used was looked up with `tools/wowapi.py` (exists, signature, secret flags).
3. No legacy globals, no deprecation shims, no combat log.
4. Every value from a unit, aura, cooldown, cast or damage-meter API is either passed straight to a widget or guarded with `issecretvalue`.
5. No `Name-Realm` assumptions; players keyed by GUID.
6. Nothing protected is touched in combat.
7. `tools\check.ps1` passes.
8. The hand-off message to the user says what was verified offline and what still needs the game.
