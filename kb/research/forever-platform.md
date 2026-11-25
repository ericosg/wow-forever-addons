# WoW Forever platform reference for addon authors

Researched 2026-11-25. Everything here comes from pages and source read on that date, not from model memory.

Source tags: **[P]** = primary (Blizzard post, warcraft.wiki.gg, Blizzard UI source / API dumps, addon source commits). **[S]** = secondary (fan/news site, addon store listing, search-result summary). Source IDs like `[P1]` refer to the list in section 14.

How the "present / missing" facts were established: I downloaded the `forever` branch of `Gethe/wow-ui-source` (head commit "1.60.1 (71091)", 2026-11-24) and the `forever` branch of `Ketho/BlizzardInterfaceResources` (head "1.60.1 (70938)") and grepped them. Those are static dumps of the client. Nothing in this document was tested in a running game.

---

## 1. Identity card

| Item | Value | Source |
|---|---|---|
| Product name | World of Warcraft: Forever | [P7] |
| Internal game type | `camelot` (alias `forever` added build 70291) | [P1][P2] |
| Game type family | `mainline` (same family as retail `standard`, `plunderstorm`, `wowhack`) | [P3] |
| Patch / TOC | 1.60.1 / `## Interface: 16001` | [P1] |
| `WOW_PROJECT_ID` | `WOW_PROJECT_CAMELOT` = **18** | [P4][P5] |
| Launcher product / folder | `wowf` / `_forever_` (beta: `wow_classic_beta` / `_classic_beta_`) | [P6] |
| Builds | beta 70009 (Sep 23), 70170 (Oct 1), 70205 (Oct 2), 70291 (Oct 7/8), 70425 (Oct 16), 70532 (Oct 20); live 70790 (Nov 3); UI source head 71091 (Nov 24) | [P1][P2][P6][P5] |
| Base API | retail 12.1.5 (build 69952) plus Forever deltas | [P1][P2] |
| Retail at same time | 12.1.5 = interface 120105 | [P6] |
| Launch | 2026-11-04 15:00 PST; beta from 2026-09-17 | [P7] |
| Level cap | 60 | [P7] |
| Classes (9) | Warrior, Paladin, Priest, Shaman, Druid, Rogue, Mage, Warlock, Hunter (`CLASS_SORT_ORDER` in `Blizzard_FrameXMLBase/Camelot/Constants.lua`) | [P5][P8] |
| Races | Human, Dwarf, Gnome, Night Elf, Orc, Tauren, Troll, Undead, plus new **Skyborne** (both factions) | [P8][P9] |
| Expansion constants | `LE_EXPANSION_LEVEL_CURRENT = 0`, `NUM_LE_EXPANSION_LEVELS = 1` (`LE_EXPANSION_CLASSIC = 0`) | [P10] |

The local install is build 71091 as of 2026-11-25 (`.build.info`: 1.60.1.71091), the same build as the UI source head. (The one file in `_forever_\Errors` is from build 71037, four days earlier.)

Blizzard's framing (Discord post "An Update On Secrets In WoW: Forever", 2026-09-15, mirrored on the wiki) [P2]:

> WoW Forever shares Mainline WoW's UI architecture, including the vast majority of APIs available in 12.1.5. From a UI loading perspective, the easiest way to think about it is that Forever and modern WoW (Midnight) are two game types within the Mainline code family: Camelot (to be renamed before launch) and Standard, respectively.
>
> The addon disarmament changes introduced in Midnight, including secrets, will also be active in Forever.
>
> The AuraContainer/AuraButton changes introduced in 12.1.0 will be available as well, and you can expect similar UI changes in the future to be introduced to both Standard and Forever.

Practical reading: **write Forever addons as Midnight-era retail addons, then subtract retail-only systems and add the Classic-flavoured ones.** Do not start from a Classic Era addon and expect the old globals to exist.

---

## 2. Detecting Forever

### 2.1 In Lua [P1][P4]

```lua
if WOW_PROJECT_ID == WOW_PROJECT_CAMELOT then  -- 18
    -- Forever
end

-- by interface version (works even where the constant is absent)
local version = select(4, GetBuildInfo())
if version > 16000 and version < 20000 then
    -- Forever
end
```

- `WOW_PROJECT_CAMELOT` was added in beta build 70170 (Oct 1). Before that, `WOW_PROJECT_ID` on Forever equalled `WOW_PROJECT_MAINLINE` (wiki cites a WoWUIDev bug thread). Details still guards with `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE and not IsForeverWow()` and detects Forever by `gameVersion >= 16000 and gameVersion <= 19999` [P13]. The interface-number range check is the most robust test.
- `WOW_PROJECT_CAMELOT` is `nil` on other clients, so `WOW_PROJECT_ID == WOW_PROJECT_CAMELOT` is safely false there.
- Source of the constant: `Interface/AddOns/Blizzard_ProjectConstants/Camelot/ProjectConstants.lua` contains exactly `WOW_PROJECT_CAMELOT = 18; WOW_PROJECT_ID = WOW_PROJECT_CAMELOT;`, loaded with `[AllowLoadGameType camelot]` [P5].
- Full `WOW_PROJECT_ID` table: 1 MAINLINE, 2 CLASSIC, 3 WOWLABS, 5 BURNING_CRUSADE_CLASSIC, 11 WRATH_CLASSIC, 14 CATACLYSM_CLASSIC, 18 CAMELOT, 19 MISTS_CLASSIC [P4].

### 2.2 Via TOC metadata [P1]

```
## X-Game: [Game]
```
```lua
if C_AddOns.GetAddOnMetadata("MyAddOn", "X-Game") == "Camelot" then ... end
```

The `[Game]` variable expands to `Camelot` on Forever (the wiki notes it "may be changed to Forever in the future"; the beta-4 note says `Forever` is accepted as an alias "in the `[Game]` variable"). Caveat: the TOC page's 12.1.7 entry says "Prevented use of variables in addon directives", so this metadata trick may stop working when Forever picks up that change. Prefer the Lua checks [P3].

### 2.3 Rulesets [P1]

```lua
if C_GameRules.IsGameRuleActive(Enum.GameRule.HardcoreRuleset) then      -- 10
elseif C_GameRules.IsGameRuleActive(Enum.GameRule.RPRuleset) then        -- 214
elseif C_GameRules.IsGameRuleActive(Enum.GameRule.PvPRuleset) then       -- 213
else -- PvE
end
```

Also available: `C_GameRules.IsHardcoreActive()`, `C_GameRules.IsSelfFoundAllowed()`, event `GAME_RULES_CHANGED` [P1][P10]. Five rulesets exist (Normal, PvP, RP, RP-PvP, Hardcore), one mega-realm per ruleset per region, Hardcore arriving later [P8].

---

## 3. TOC format on Forever

### 3.1 Interface line

`## Interface: 16001`. Comma-separated multi-value lists are supported (since 10.2.7) [P3]:

```
## Interface: 11509, 20506, 30405, 38002, 40402, 50504, 120105, 16001
```

BigWigs' actual line after adding Forever: `## Interface: 11508, 11509, 16001, 20505, 20506, 30405, 38002, 40402, 50503, 50504, 120100, 120105, 120007` [P12].

The wiki has an open TODO "Check incompatible range in Forever and document", so the exact out-of-date behaviour on Forever is undocumented [P3].

### 3.2 Game types and suffixes [P3]

| Game type | Suffix file | Notes |
|---|---|---|
| `standard` | `AddOn_Standard.toc` | retail (suffix added 12.1.5) |
| `forever`, `camelot` | `AddOn_Forever.toc`, `AddOn_Camelot.toc` | Forever |
| `mists`, `cata`, `wrath`, `tbc`, `vanilla` | `_Mists`, `_Cata`, `_Wrath`, `_TBC`, `_Vanilla` | Classic flavours |
| `plunderstorm` | `_Plunderstorm`, `_WoWLabs` | |
| `wowhack` | `_WoWHack` | "Talebound" |

Families: `mainline` = standard, forever, camelot, plunderstorm, wowhack (`AddOn_Mainline.toc`); `classic` = vanilla, tbc, wrath, cata, mists (`AddOn_Classic.toc`).

- The client looks for a game-type suffix first, then a family suffix, then the plain `AddOn.toc`.
- **`AddOn_Mainline.toc` loads on Forever** because Forever is in the mainline family. A retail-only addon shipping `_Mainline.toc` will be picked up by Forever unless it is excluded.
- **`AddOn_Classic.toc` does not load on Forever.**
- `Forever` as a suffix/alias only exists from build 70291. Blizzard beta-4 note: "Forever is now accepted as an alias for Camelot in TOC file suffixes (e.g. `MyAddon_Forever.toc`), in the `[Game]` variable, and in game-type folder lookup." [P2]
- Questie ships both `Questie_Camelot.toc` and `Questie_Forever.toc` (seen in the local install).

### 3.3 `AllowLoadGameType` / `ExcludeLoadGameType`

Wiki guidance for Forever-only loading [P1]. Because retail 12.1.5/12.1.0 and Classic clients do not recognise the token `forever`, and **an `AllowLoadGameType` list where no token is recognised is treated as satisfied**, you must also exclude the others:

```
## AllowLoadGameType: forever
## ExcludeLoadGameType: standard, classic
```

Per file:

```
MyFile.lua [AllowLoadGameType forever][ExcludeLoadGameType standard, classic]
```

Per-game-type metadata (list the `forever` line first, since unrecognised types load anyway and later lines overwrite earlier ones):

```
## Title: My title for Forever [AllowLoadGameType forever]
## Title: My title for Midnight [AllowLoadGameType standard]
## Title: My title for Mists/TBC/Vanilla [AllowLoadGameType classic]
```

Notes:
- For an addon that only ever targets Forever (this workspace), a single `AddOn.toc` with `## Interface: 16001` is enough. The game-type directives matter only for multi-client releases.
- Blizzard's own TOCs use `camelot`, never `forever` (e.g. `## AllowLoadGameType: standard, camelot`) [P5]. `camelot` is recognised by every Forever build; `forever` only from 70291.
- Other inline directives available on Forever: `[AllowLoadTextLocale enUS, frFR]`, `[Bootstrap]`, variables `[Family]`, `[Game]`, `[TextLocale]`; `[RegionalTextLocale]` is listed as supported on Forever [P3].
- Directives confirmed for Forever: `IconTexture`, `IconAtlas`, `Category`, `Group`, `AddonCompartmentFunc` / `AddonCompartmentFuncOnEnter` / `AddonCompartmentFuncOnLeave`, `LoadSavedVariablesFirst`, `AllowAddOnTableAccess`, `SavedVariables`, `SavedVariablesPerCharacter`, `LoadOnDemand`, `Dependencies`, `OptionalDeps`, `LoadWith`, `DefaultState` [P3]. The wiki's Forever history line: "Includes all Modern changes up to 12.1.5".
- The addon compartment exists on Forever with its own implementation (`Blizzard_Minimap/Camelot/AddonCompartment.lua`) [P5]. Questie has a commit "[fix][Forever] Open settings on addon compartment left click" [P14].

### 3.4 Beta-era loader bugs, all fixed before launch [P1]

- SavedVariables not loading; RestrictedEnvironment not loading; `UnitName` inconsistent between unit tokens (fixed build 70009).
- `UnitName("player")` returning `"Unknown", nil` before `PLAYER_LOGIN` (fixed build 70170).

---

## 4. Packaging ecosystem

### 4.1 BigWigsMods/packager (`release.sh`, master, read 2026-11-25) [P11]

- Commit "Add WoW Forever support (#202)"; later "Allow Forever interface versions in `Mainline` toc files (Fixes #204)" and "Don't allow Forever interface versions in `Classic` toc files".
- Game type name: `forever` (`-g forever`; `-g camelot` maps to `forever`; `-g 1.60.x` maps to forever via the rule "major 1, minor 6x").
- Interface detection: `16???` => `forever`.
- **TOC suffix recognised by the packager: `Camelot` only.** Its regex is `[-_](Mainline|Classic|Vanilla|BCC|TBC|Wrath|WOTLKC|Cata|Mists|Camelot)\.toc`. `_Forever.toc` is not in that list as of this read, even though the game client accepts it. Split-TOC output is written as `<name>_Camelot.toc`.
- Keyword blocks: `@version-forever@ ... @end-version-forever@` and `@non-version-forever@`.
- CurseForge game version **type id for Forever: `88568`** (classic 67408, bcc 73246, wrath 73713, cata 77522, mists 79434, titan 81212, retail 517).
- Release file suffix: `-forever` appended to the version label unless the tag already contains it.
- WoWInterface: "No WoWInterface game type match for ... forever ... is not supported, ignoring".
- README multi-interface example ends with `16001` and calls it "Forever Beta".

### 4.2 Wago Addons (`https://addons.wago.io/api/data/game`, fetched 2026-11-25) [P15]

- Patch key `"forever": ["1.60.1"]`, upload property `supported_forever_patches`.
- `toc_suffixes.forever`: `-Camelot`, `_Camelot`, `-Forever`, `_Forever`.
- TOC metadata `## X-Wago-ID:` is read by the packager.

### 4.3 CurseForge

- Forever is a distinct game-version type (id 88568 per the packager) [P11]. CurseForge's own multi-TOC help article does not mention Forever [P16]. A fan guide says the CurseForge app's folder for Forever is `World of Warcraft\_forever_` [S1], which matches the local install.
- TOC metadata `## X-Curse-Project-ID:` as usual.

### 4.4 Advice for multi-client releases

Ship `_Camelot.toc` (works with client, packager and Wago) or use a single TOC with `camelot`-based inline directives. `_Forever.toc` works in the client and on Wago but is not recognised by the BigWigs packager.

---

## 5. Blizzard UI source and API dumps

| Repo | Ref | Notes |
|---|---|---|
| `Gethe/wow-ui-source` | **branch `forever`**, **tag `1.60.1`** (both at commit c01a87b, "1.60.1 (71091)", 2026-11-24) | `version.txt` = `1.60.1.71091` [P5] |
| `Gethe/wow-ui-source` | branch `classic_beta` | was the Forever beta channel (`_classic_beta_`) per the wiki patch-info template [P6]; not inspected |
| `Ketho/BlizzardInterfaceResources` | **branch `forever`**, **tag `1.60.1`** (head "1.60.1 (70938)") | `Resources/GlobalAPI.lua`, `Events.lua`, `LuaEnum.lua`, `CVars.lua`, `FrameXML.lua`, `Mixins.lua`, `Templates.lua`, `WidgetAPI.lua`, `Frames.lua`, `AtlasInfo.lua` [P10] |

Do not confuse with the tags `1.6.0` and `1.6.1` in wow-ui-source; those exist too and are not the Forever tag (`1.60.1`).

Diff links given by the wiki [P1]:
- `https://github.com/Gethe/wow-ui-source/compare/12.1.5..forever`
- `https://github.com/Ketho/BlizzardInterfaceResources/compare/12.1.5..1.60.1`

Useful raw URLs:
- `https://raw.githubusercontent.com/Ketho/BlizzardInterfaceResources/forever/Resources/GlobalAPI.lua`
- `https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/<Blizzard_X>/...`
- API docs (signatures, secret predicates, event payloads): `Interface/AddOns/Blizzard_APIDocumentationGenerated/*.lua` on the `forever` branch.

Forever-specific Blizzard code lives in `Camelot/` subfolders (e.g. `Blizzard_UnitFrame/Camelot/PlayerFrame.lua`, `Blizzard_NamePlates/Camelot/`, `Blizzard_PlayerSpells/Camelot/`, `Blizzard_UIPanels_Game/Camelot/PaperDollFrame.lua`, `Blizzard_EditMode/Camelot/`, `Blizzard_Minimap/Camelot/`, `Blizzard_ActionBar/Camelot/`).

There is no wiki page `Patch_1.60.0/API_changes` (the URL returns empty). The only Forever API-changes page is `Patch_1.60.1/API_changes` with the subpage `/notes`.

---

## 6. API surface: what exists and what does not

All "present"/"absent" statements below come from `GlobalAPI.lua` and `FrameXML.lua` on Ketho's `forever` branch (build 70938) and the wow-ui-source `forever` branch (build 71091) [P5][P10]. `GlobalAPI.lua` has about 7,100 entries.

### 6.1 Old globals that are GONE (use the namespaced form)

Not present as C globals and not provided by any deprecation shim on Forever:

| Missing global | Use instead (present) |
|---|---|
| `GetSpellInfo`, `GetSpellTexture`, `GetSpellCooldown`, `GetSpellSubtext` | `C_Spell.GetSpellInfo`, `C_Spell.GetSpellName`, `C_Spell.GetSpellTexture`, `C_Spell.GetSpellCooldown`, `C_Spell.GetSpellCooldownDuration`, `C_Spell.GetSpellCharges`, `C_Spell.GetSpellSubtext` |
| `GetItemInfo`, `GetItemCount`, `GetItemIcon`, `GetItemQualityColor` | `C_Item.GetItemInfo`, `C_Item.GetItemInfoInstant`, `C_Item.GetItemCount`, `C_Item.GetItemQualityColor` |
| `UnitAura`, `UnitBuff`, `UnitDebuff` | `C_UnitAuras.GetAuraDataByIndex`, `GetBuffDataByIndex`, `GetPlayerAuraBySpellID`, `GetAuraDataBySpellName`, `GetUnitAuras`, `GetAuraDuration` |
| `GetAddOnMetadata`, `IsAddOnLoaded`, `GetNumAddOns`, `UIParentLoadAddOn` | `C_AddOns.GetAddOnMetadata`, `C_AddOns.IsAddOnLoaded`, `C_AddOns.GetNumAddOns`, `C_AddOns.LoadAddOn` |
| `GetContainerItemInfo` etc. | `C_Container.*` |
| `GetNumQuestLogEntries`, `GetQuestLogTitle` | `C_QuestLog.GetNumQuestLogEntries`, `C_QuestLog.GetInfo`, `C_QuestLog.IsQuestFlaggedCompleted` |
| `GetNumTalentTabs`, `GetTalentInfo`, `GetSpecialization` | `C_SpecializationInfo.*`, `C_Traits.*`, `C_ClassTalents.*` (section 8.1) |
| `GetNumSkillLines`, `GetSkillLineInfo`, `AbandonSkill` | `C_SkillInfo.*` (section 8.4) |
| `GetNumFactions`, `GetFactionInfo` | `C_Reputation.GetFactionDataByIndex` etc. |
| `GetCraftInfo`, `GetNumCrafts`, `GetTradeSkillInfo` | `C_TradeSkillUI.*` (retail professions UI, `Blizzard_Professions` loads on mainline) |
| `GetAuctionItemInfo`, `QueryAuctionItems` | `C_AuctionHouse.*` (retail-style AH; `Blizzard_AuctionHouseUI` has a Camelot folder) |
| `SendAddonMessage`, `RegisterAddonMessagePrefix` | `C_ChatInfo.SendAddonMessage`, `C_ChatInfo.RegisterAddonMessagePrefix` |
| `IsSpellKnown`, `IsPlayerSpell`, `GetSpellBookItemInfo`, `GetNumSpellTabs` | `C_SpellBook.IsSpellKnown`, `C_SpellBook.GetSpellBookItemInfo`, `C_SpellBook.GetNumSpellBookSkillLines` |
| `InviteUnit`, `GetLootMethod` | `C_PartyInfo.InviteUnit`, `C_PartyInfo.GetLootMethod` |
| `CastingInfo` (Classic) | `UnitCastingInfo`, `UnitChannelInfo` |
| `GetPVPRankInfo`, `UnitPVPRank` (Classic honor ranks) | not present; `GetInspectHonorData`, `GetPVPLifetimeStats` exist; see `Blizzard_UIPanels_Game/Camelot/PVPRankFrame.lua` |
| `GetMouseFocus` | `GetMouseFoci` |
| `EasyMenu`, `InterfaceOptions_AddCategory`, `InterfaceOptionsFrame_OpenToCategory` | `MenuUtil` / `Settings.RegisterAddOnCategory`, `Settings.RegisterCanvasLayoutCategory`, `Settings.RegisterVerticalLayoutCategory`, `Settings.RegisterAddOnSetting`, `Settings.OpenToCategory` (defined in `Blizzard_Settings_Shared/Blizzard_Settings.lua`) |
| `C_Engraving.*`, `C_Seasons.*` (SoD / Classic seasons) | not present |
| `require` | renamed `import` (present) [P2] |

`UIDropDownMenu_Initialize` still exists in FrameXML.

Still present as plain globals (sample): `UnitHealth`, `UnitHealthMax`, `UnitPower`, `UnitGUID`, `UnitClass`, `UnitRace`, `UnitLevel`, `UnitXP`, `GetXPExhaustion`, `UnitName`, `UnitNameUnmodified`, `UnitFullName`, `Ambiguate`, `GetPlayerInfoByGUID`, `GetRealmName`, `GetNormalizedRealmName`, `GetMoney`, `GetComboPoints`, `GetShapeshiftForm`, `GetShapeshiftFormInfo`, `GetTotemInfo`, `GetCombatRating`, `UnitRangedDamage`, `UnitThreatSituation`, `UnitDetailedThreatSituation`, `UnitCastingInfo`, `UnitChannelInfo`, `GetInventoryItemLink`, `GetInventoryItemID`, `GetNumGroupMembers`, `IsInRaid`, `GetRaidRosterInfo`, `SetRaidTarget`, `GetRaidTargetIndex`, `GetInstanceInfo`, `IsInInstance`, `GetZoneText`, `GetSubZoneText`, `UnitPosition`, `CastSpellByName`, `InCombatLockdown`, `hooksecurefunc`, `CreateFrame`, `GetMaxPlayerLevel`, `GetMaxLevelForPlayerExpansion`, `GetExpansionLevel`, `GetServerTime`, `AbbreviateNumbers`, `BreakUpLargeNumbers`, `C_Timer.After`, `C_Timer.NewTicker`, `C_Map.GetBestMapForUnit`, `C_Map.GetPlayerMapPosition`, `RegisterEventCallback`, `RegisterUnitEventCallback`, `C_EventUtils.IsEventValid`, `UnitHealthPercent`, `UnitPowerPercent`, `UnitHealthMissing`, `C_CurveUtil.*`, `C_DurationUtil.*`, `C_EncodingUtil.*` (CBOR/JSON/Base64/compress), `C_StringUtil.*`.

### 6.2 Deprecation shims (CVar `loadDeprecationFallbacks`, default `"1"`)

Blizzard's `Blizzard_Deprecated*` addons each begin with `if not GetCVarBool("loadDeprecationFallbacks") then return end`. With the default they define (among others) [P5]:

- `SendChatMessage` (wrapper for `C_ChatInfo.SendChatMessage`), `DoEmote`, `CancelEmote`
- Action bar globals: `GetActionCooldown`, `GetActionTexture`, `GetActionText`, `GetActionCount`, `GetActionCharges`, `HasAction`, `IsUsableAction`, `IsActionInRange`, `IsCurrentAction`, `IsAttackAction`, `IsAutoRepeatAction`, `GetActionBarPage`, `ChangeActionBarPage`, `GetBonusBarOffset`, ... (wrappers for `C_ActionBar.*`)
- `IsEncounterInProgress`, `IsEncounterLimitingResurrections`, `IsEncounterSuppressingRelease`
- `PromoteToLeader`, `PromoteToAssistant`, `DemoteAssistant`, `UninviteUnit`, `DoReadyCheck`, `ConfirmReadyCheck`, `IsGUIDInGroup`, `SetEveryoneIsAssistant`
- `BNSendWhisper`, `BNSendGameData`, `BNInviteFriend`, `BNSetCustomMessage`, `BNSetBlocked`, ...
- `GetAutoCompleteResults`, `GetAutoCompletePresenceID`, `IsRecognizedName`, `AUTOCOMPLETE_FLAG_*`
- `ChatEdit_*` and `ChatFrame_*` legacy function names (e.g. `ChatFrame_AddMessageEventFilter`, `ChatEdit_InsertLink`)
- `RaidNotice_AddMessage`, ...
- `GetWeaponEnchantInfo`, `CancelItemTempEnchantment`, `GetInspectSpecialization`, `getglobal`, `setglobal`, `GetInventorySlotInfo`, `GetBattlefieldScore`, `GetMerchantCurrencies`
- Combat-log aliases: `CombatLogGetCurrentEventInfo = C_CombatLog.GetCurrentEventInfo` and `COMBATLOG_OBJECT_*` constants. Note `C_CombatLog.GetCurrentEventInfo` is not in the insecure API list, so the alias resolves to `nil` for addons (section 7.2).

`Blizzard_DeprecatedSpecialization` is `## AllowLoadGameType: classic, standard`, so its shims (`GetSpecialization` etc.) do **not** load on Forever.

Treat every shim as temporary: the TOC notes say they "will be removed at the next expansion" / "once all live versions of the game have been updated". Call the `C_*` form directly.

### 6.3 Changes 12.1.5 -> 1.60.1 [P1]

Totals: Global API +176 / -10; FrameXML functions +471 / -1041; Widgets +7 / 0; Events +24 / -2; CVars +138 / -7.

**Removed globals (10):** `AbandonSkill`, `BNSetBlocked`, `C_PaperDollInfo.CanCursorCanGoInSlot`, `C_PvP.GetRandomTrainingGroundRewards`, `C_PvP.HasRandomTrainingGroundWinToday`, `C_PvP.JoinRandomTrainingGroundBattleground`, `C_TransmogOutfitInfo.GetWeaponOptionsForSlot`, `C_TransmogOutfitInfo.SetViewedWeaponOptionForSlot`, `GetPetFoodTypes`, `SetBarSlotFromIntro`.

**Added globals of interest to addon authors:**

- Classic-style stats: `GetArmorPenetration`, `GetCritChanceFromStat`, `GetSpellCritChanceFromStat`, `GetHealthRegen`, `GetHealthRegenFromSpirit`, `GetManaRegenFromSpirit`, `GetRangedAttackPowerForStat`, `GetRangedHitModifier`, `GetPetHitChanceModifier`, `GetPetSpellHitChanceModifier`, `UnitDefenseSkill`, `UnitResistance`, `UnitUsesAmmo`, `C_PaperDollInfo.AmmoNeeded`, `C_PaperDollInfo.CursorCanGoInSlot`
- Hunter pets: `C_PetInfo.GetPetHappiness`, `GetPetLoyalty`, `GetPetTrainingPoints`, `GetPetFoodTypes`, `CanPetEatItem`, `GetPetUIModelSceneID`; `C_StableInfo.BuyStableSlot`, `GetNextStableSlotCost`, `GetNumStableSlots`
- Skills: `C_SkillInfo.AbandonSkill`, `CollapseSkillHeader`, `ExpandSkillHeader`, `GetNumSkillLines`, `GetSelectedSkill`, `GetSkillLineInfo`, `GetSkillLineInfoByID`, `SetSelectedSkill`
- Swing timer: `C_SwingTimer.EnableRangeCheck`, `C_SwingTimer.IsTargetWithinSwingRange`
- Spells/spellbook: `C_Spell.CancelAutoRepeatSpell`, `C_Spell.CancelItemTempEnchantment`, `C_Spell.GetItemCooldown`, `C_Spell.GetTargetSpellID`, `C_Spell.IsActiveSpell`, `C_Spell.PlaceTargetingSpellAtCursor`, `C_SpellBook.GetClassSkillLineInfo`, `C_SpellBook.IsSpellBookItemLowRank`, `C_SpellBook.IsSpellBookItemLooseFlyoutMember`, `C_SpellBook.AbortSpellIntro`, `C_SpellBook.SetBarSlotFromIntro`
- Flyouts: `C_Flyout.FlyoutHasSpell`, `GetFlyoutID`, `GetFlyoutInfo`, `GetFlyoutSlotInfo`, `GetFlyoutTexture`, `GetNumFlyouts`
- Talents: `C_SpecializationInfo.GetAllClassIDs`, `GetCombatConfigIDForSpecGroup`, `HasPlayerEarnedATalentPoint`, `IsSpecSelectionEnabled`, `SetActiveSpecGroup`; `C_Traits.GetGroupCurrencyInfo`, `GetGroupDisplayInfoByTreeID`, `GetMaxAvailableTraitCurrency`, `GetTraitCurrencyForAchievement`
- Game rules: `C_GameRules.GetForeverExperiencePreset`, `SetForeverExperiencePreset` (in the 71091 source this is split into `SetForeverExperiencePresetPreLogin` / `SetForeverExperiencePresetPostLogin`), `IsHardcoreActive`, `IsSelfFoundAllowed`, `AccountHasSDEnabled`, `IsSDHDToggleEnabled`, `SetSDHDToggleValue`
- Items/bags/bank: `C_Item.GetWeaponEnchantInfo`, `C_Item.DeleteItem`, `C_Item.ConfirmDeleteItem`, `C_ActionBar.ShouldShowKeyring`, `C_Bank.BankBagTypeAndIDToInvSlot`, `C_Bank.FetchMaxNumBankTabs`, `C_Bank.ShouldUsePlayerBagsInBank`, `ReagentsFromBankAllowed`, `C_LootFrame.TryAutoLoot`, `C_AutoLoot.SetUseAutoLootToggle`
- Quests: `C_QuestLog.GetQuestTimers`, `C_QuestLog.GetTrivialRange`, `C_QuestLog.IsEliteQuest`
- Trainers: `C_Trainer.GetTrainerType`, `GetCategorizeTrainerUI`, `SetCategorizeTrainerUI`
- Names: `C_NameUtil.ReplaceSurnameSeparatorWithLinkSeparator`, `C_PlayerInfo.ShouldDisplaySurname`, `RegionalUniqueNamesEnabled`
- Units: `UnitIsInInteractRange`, `UnitHasLootInteraction`, `UnitHasMouseoverHighlight`, `UnitHasEffectivelyTankAura`
- Group/LFG: `C_LFGListRoles.GetRoles`, `GetSavedRoles`, `SetRoles`, `C_PartyInfo.IsRaidListEnabled`, `IsRaidListSupported`, `C_FriendList.GetWhoRaceFilters`, `GetNextAvailableRaidTargetMarkerIndex`
- Layer/shard: `C_PlayerInteractionManager.ShardTransferConfirm`
- Misc: `C_CVar.SetTempCVar`, `C_CVar.RemoveTempCVar`, `C_DateAndTime.IsDayTime`, `C_EditMode.GetEditModeDefaultLayout`, `C_UnitAuras.GetRefreshCarryOverDuration`, `C_InputInterfaceStyle.GetCurrentStyle`, `ToggleSit`, `UIReload`, `CanPortGraveyard`, `GetEvictionTimeRemaining`, `GetTextureMetatable`, `PlatformIsHandheld`, `require` (later renamed `import`)
- Gamepad: `C_GamepadTargeting.*`, `C_GamepadUI.*`, `C_GamePad.Get/SetAllowHoverEventsWithFreeLook`, `SetPreferredGamepadInteractTarget`
- Not for addons but notable: `C_BlizzCon2026.*`, `C_SocialRestrictions.*AgeVerification*`, `C_CharacterServices.*HardcoreTransfer*`

**Events added (24):** `ALERT_AGE_VERIFICATION_RESTRICTED`, `BC_26_COLD_SWAP_FEATURE_ENABLED_CHANGED`, `BC_26_EXPERIENCE_CHANGED`, `CHAT_MSG_COLLECTED_APPEARANCE`, `DIEL_CYCLE_CHANGED`, `GAME_PAD_ALLOW_HOVER_EVENTS_WITH_FREE_LOOK_CHANGED`, `GAME_RULES_CHANGED`, `GAMEPAD_POSSESS_BAR_OVERRIDE_CHANGED`, `GAMEPAD_STANCE_BAR_OVERRIDE_CHANGED`, `GLOBAL_REGION_MOUSE_DOWN`, `GLOBAL_REGION_MOUSE_UP`, `GUILD_PREFERRED_PLAY_SETTINGS_UPDATED`, `INPUT_DEVICE_INTERFACE_TRANSITION`, `LFG_LIST_ROLE_UPDATE`, `LFG_LIST_SHOW_SEARCH`, `PET_STATS_UPDATE`, `PLAYER_PVP_FLAG_CHANGED`, `PLAYER_SWING_RANGE_UPDATE`, `PLAYER_SWING`, `SHARD_TRANSFER_IMMINENT`, `SHARD_TRANSFER`, `SOCIAL_UI_RAID_LIST_SYSTEM_STATUS_UPDATED`, `UNIT_HAPPINESS`, `UNIT_PET_TRAINING_POINTS`, `VIEWED_TRANSMOG_OUTFIT_SLOT_OPTION_CHANGED`. (`SHARD_TRANSFER_CANCELLED` also exists in the 70938 dump.)

**Events removed (2):** `PET_SPELL_POWER_UPDATE`, `VIEWED_TRANSMOG_OUTFIT_SLOT_WEAPON_OPTION_CHANGED`.

**Widget methods added (7):** `ScriptRegion:FocusEnter`, `FocusExit`, `MouseDown`, `MouseUp`; `ModelSceneActorBase:SetModelByUnitCreatureDisplayID`; `Minimap:SetUsingSoftCursor`, `Minimap:UpdateMouseoverAtPoint`.

**CVars added, addon-relevant subset:** `showSwingTimer` (0), `showKeyring` (0), `ShowAllSpellRanks` (0), `spellBookHideFlyouts` (1), `classicStyleWorldText` (0), `categorizeTrainerUI` (0), `characterFrameCollapsed`, `displayFreeBagSlots` (0), `displayTemporaryEnchantIcon` (1), `instantQuestText` (1), `showQuestLevel` (0), `showQuestDifficultyColor` (1), `showLootSpam` (1), `showMaxLevelAnnouncements` (1), `showTaxiNodeLearnedIcon` (0), `canUseQuestItemWithLeftClick` (0), `tooltipPointsShowMinAndMax` (1), `UnitSurnameOwn` (1), `hasSelectedExperiencePreset` (0), `InputDeviceInterfaceStyle` (0), `nameplateTopInset` (0.08), `nameplateBottomInset` (0.1), `nameplateMotionSpeed` (0.025), `minFontHeight` (0), `targetHighlightAlwaysShown` (1), `SoftTargetInteractOnlyInRange` (0), `enableLootToasts` / `enableCollectionToasts` / `enableLearnedRecipeToasts` (1), `onlyShowCollectedItemsInJournal` (1), `deemphasizeOffspecPrimaryStats` (0), `CAAPulsePlayerHealthPercent` / `CAAPulsePlayerHealthVolume`, plus about 60 `Gamepad*` / `SmartNavigation*` CVars. Added after the 70205 diff: `nameplateMaxVerticalDistance`, `nameplateMaxVerticalDistanceAtMaxRange` (0 disables the check) [P2].

**FrameXML:** 1,041 functions removed vs retail, almost entirely retail-only UIs: `EncounterJournal_*` (87), `LFGList*` / `LFD*` / `RaidFinder*` / `ScenarioQueue*` / `PVEFrame_*` / `GroupFinderFrame_*`, `Garrison*`, `PVPUIFrame_*` / `ConquestFrame_*` / `HonorFrame_*`, `HousingFramesUtil.*` / `Blizzard_HousingCatalogUtil.*`, `PerksProgram*`, `MonthlyActivities*`, `RemixArtifact*`, `ChallengeMode*`, `EncounterTimelineUtil.*`, `EncounterWarningsUtil.*`, `AccountStoreUtil.*`, `ClassTrial*`. 471 added: `MultiCast*` (shaman totem bar), `LFGBrowse*` / `LFGListing*` / `LFGVanilla_*` (Vanilla-style group finder), `PaperDollFrame_Set*` classic stats (defense, resistances, weapon skill, ranged, spell healing), `PaperDollAmmoSlotButton_*`, `GetKeyRingSize` / `PutKeyInKeyRing`, `MasterLooter*`, `SmartNavigation_*` / `InputUtil.*` / `Gamepad*` (gamepad UI), `NameUtil.*`, `LegacySystemFrame_LoadUI` / `ToggleLegacySystemUI` / `LegacyChallengeViewedUtil.*`, `ShouldUseSilverUnitFrame`, `PlayerFrame_*` PvP icon helpers, `UnitFrameUtil.*`.

### 6.4 Retail namespaces that still exist in the binary but whose UI does not load

Only 10 globals were removed, so namespaces such as `C_Housing*` (15 namespaces), `C_Garrison` (227 functions), `C_EncounterJournal`, `C_EncounterTimeline`, `C_EncounterWarnings`, `C_MythicPlus`, `C_ChallengeMode`, `C_DelvesUI`, `C_PerksProgram`, `C_WeeklyRewards`, `C_Covenants`, `C_AzeriteItem`, `C_ArtifactUI`, `C_Soulbinds` **are non-nil on Forever** [P10]. `if C_Housing then` is therefore not a valid "is this retail?" test. Feature-detect with a behavioural call or game-rule check instead (e.g. `C_PvP.IsWarModeFeatureEnabled()` returns false on Forever [P2]; `Enum.GameRule.HousingEnabled` = 154, `EncounterJournalDisabled` = 42, `TransmogEnabled` = 109 exist).

---

## 7. Addon restrictions ("disarmament") on Forever

### 7.1 Secrets apply [P2]

Blizzard: "The addon disarmament changes introduced in Midnight, including secrets, will also be active in Forever." The machinery is present in the Forever dump [P10]:

- Globals: `issecretvalue`, `issecrettable`, `canaccessvalue`, `canaccessallvalues`, `canaccesssecrets`, `canaccesstable`, `hasanysecretvalues`, `scrub`, `scrubsecretvalues`, `secretwrap`, `dropsecretaccess`.
- `C_Secrets` (27 functions): `HasSecretRestrictions`, `ShouldAurasBeSecret`, `ShouldCooldownsBeSecret`, `ShouldSpellCooldownBeSecret`, `ShouldSpellAuraBeSecret`, `ShouldUnitAuraIndexBeSecret` / `InstanceBeSecret` / `SlotBeSecret`, `ShouldUnitIdentityBeSecret`, `ShouldUnitHealthMaxBeSecret`, `ShouldUnitPowerBeSecret` / `PowerMaxBeSecret`, `ShouldUnitSpellCastBeSecret` / `SpellCastingBeSecret`, `ShouldUnitStatsBeSecret`, `ShouldUnitThreatStateBeSecret` / `ThreatValuesBeSecret`, `ShouldUnitComparisonBeSecret`, `ShouldActionCooldownBeSecret`, `ShouldSpellBookItemCooldownBeSecret`, `ShouldTotemSlotBeSecret` / `TotemSpellBeSecret`, `CanCompareUnitTokens`, `GetPowerTypeSecrecy`, `GetSpellAuraSecrecy`, `GetSpellCastSecrecy`, `GetSpellCooldownSecrecy`.
- `C_RestrictedActions.GetAddOnRestrictionState`, `IsAddOnRestrictionActive`, `CheckAllowProtectedFunctions`; event `ADDON_RESTRICTION_STATE_CHANGED`.
- `Enum.AddOnRestrictionType`: Combat 0, Encounter 1, ChallengeMode 2, PvPMatch 3, Map 4, Chat 5. `Enum.AddOnRestrictionState`: Inactive 0, Activating 1, Active 2.
- `GetRestrictedActionStatus` (mentioned in 12.0.0 notes) is **not** in the Forever dump; use `C_RestrictedActions`.
- Test CVars present on Forever (default 0, not persisted): `addonCombatRestrictionsForced`, `addonChatRestrictionsForced`, `addonMapRestrictionsForced`. The 12.0.0-era `secretAurasForced` / `secretCooldownsForced` / ... names did not turn up in the Forever CVar dump.
- `Enum.SecretAspect` includes the new `FrameStrata = 0x1000000`; `Frame:GetFrameStrata()` returns a secret for frames carrying that aspect (beta 4) [P2].
- `UnitName` is documented `SecretWhenUnitNameIdentityRestricted = true` in the Forever API docs [P5].
- General rule (wiki Secret Values page): secrets typically apply "when combat, encounter, challenge mode, or PvP match addon restrictions are in effect"; unit identity is secret "when the unit isn't player-controlled or in the party/raid"; max health/power secret "when the unit isn't player-controlled" [P17].

What secrets mean for code: values can be passed to widgets (`SetText`, `SetValue`, `SetFormattedText`, status bars, cooldown frames) but cannot be compared, used in arithmetic, concatenated or used as table keys by tainted code. Guard with `issecretvalue(v)` before doing logic. Details' Forever commit shows this pattern being used around actor names [P13].

How strictly each predicate fires in Forever's open world, dungeons and raids (which have no Mythic+ and different encounter flagging) was **not found in any primary source**. Determine it in game with `C_Secrets.Should*` and `C_RestrictedActions.IsAddOnRestrictionActive(Enum.AddOnRestrictionType.Combat)`.

### 7.2 Combat log

- Blizzard, 12.0.0 notes: "Combat Log Events are no longer available to addons, and messages in the Combat Log chat tab have been converted to KStrings to prevent addons from parsing the information inside them." [P18] Forever inherits Midnight's disarmament [P2].
- In the Forever API docs, `COMBAT_LOG_EVENT_UNFILTERED` is declared with `HasRestrictions = true` and `CallbackEvent = true`. The event names `COMBAT_LOG_EVENT`, `COMBAT_LOG_EVENT_UNFILTERED`, `COMBAT_LOG_EVENT_INTERNAL_UNFILTERED`, `COMBAT_LOG_MESSAGE` exist in the event list [P5][P10].
- The insecure `C_CombatLog` namespace has only: `ApplyFilterSettings`, `AreFilteredEventsEnabled`, `ClearEntries`, `DoesObjectMatchFilter`, `GetEntryRetentionTime`, `GetMessageLimit`, `IsCombatLogRestricted`, `RefilterEntries`, `SetEntryRetentionTime`, `SetFilteredEventsEnabled`, `SetMessageLimit`. **There is no `C_CombatLog.GetCurrentEventInfo` for addons**; Blizzard's parser runs in `Blizzard_CombatLogProcessor` with `## UseSecureEnvironment: 1`. The deprecation file says: "Some functions have been relocated to the secure environment, for which no deprecation is (intentionally) provided." [P5]
- `C_CombatLog.IsCombatLogRestricted()` returns a bool. Its semantics on Forever are undocumented.
- [S] An addon PR (ownjoo/bgcomms #11, seen only through a search summary; the PR page itself returned 404 to me) reports that registering `COMBAT_LOG_EVENT_UNFILTERED` on Forever raises a blocked-action popup, confirmed in game by its author. [S] CurseForge listings for Forever meters (ForeverMeter, DaliCount, WombatLog) all say the combat log is unreadable and that they use `C_DamageMeter` or estimates [S2].
- Conclusion: **treat CLEU as unavailable on Forever.** Whether registration errors, pops `ADDON_ACTION_FORBIDDEN`, or silently delivers nothing was not confirmed from a primary source. Never call `RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")` unguarded; wrap it in `pcall` or skip it on project 18.

Alternatives that exist on Forever: `C_DamageMeter` (section 8.3), `UNIT_SPELLCAST_*` events, `UNIT_AURA` with `C_UnitAuras`, `PLAYER_SWING` (section 8.5), `C_CombatText`, `C_DeathRecap`, `ENCOUNTER_START` / `ENCOUNTER_END`, `UNIT_HEALTH`, `UNIT_POWER_UPDATE`, threat APIs.

### 7.3 Chat and addon messaging

- **Trial accounts can no longer send addon messages** (beta 4) [P2].
- `C_ChatInfo.SendChatMessage` with `"EMOTE"` requires a hardware event when called from addon code outside instances, "matching the existing restriction on SAY and YELL" (beta 4) [P2].
- Inherited from Midnight: addon messages and chat reading are locked down while an instance encounter is in progress, a PvP match is running, or a keystone run is active [P18]. Check with `C_ChatInfo.InChatMessagingLockdown()`.
- `C_ChatInfo.SendAddonMessage(prefix, message, chatType, target)` returns `Enum.SendAddonMessageResult`: Success 0, InvalidPrefix 1, InvalidMessage 2, AddonMessageThrottle 3, InvalidChatType 4, NotInGroup 5, TargetRequired 6, InvalidChannel 7, ChannelThrottle 8, GeneralError 9, NotInGuild 10, AddOnMessageLockdown 11, TargetOffline 12. Arguments are documented `SecretArguments = "NotAllowed"` [P5][P10].
- `C_ChatInfo.AreOutgoingAddonChatMessagesRestricted()`: "Returns false if addons are allowed to send outgoing chat messages. This is controlled on a realm-by-realm basis (tournament realms allow it)..." [P5]
- Whisper-target names changed (section 9): there are no realm suffixes, and names may contain a space plus surname.

### 7.4 Layer detection blocked [P2]

Beta 5 (build 70425): "The server ID and spawn ID portions of creature, vehicle, pet and game object GUIDs have been replaced with obfuscated values to prevent comparison to determine layer. They remain stable and unique within your own session, and the GUID string format is otherwise unchanged."

- GUID parsing for NPC ID (the 6th field) still works; using zone/server/spawn fields to infer a layer does not.
- Layer transfers surface as `SHARD_TRANSFER_IMMINENT`, `SHARD_TRANSFER`, `SHARD_TRANSFER_CANCELLED` and `C_PlayerInteractionManager.ShardTransferConfirm` [P1][P10]. Payloads were not checked.
- [S] Several CurseForge "layer" addons for Forever describe their output as an estimate from observed creatures, not a real layer ID [S3]. No Blizzard policy statement on layer-hopping addons was found beyond the GUID change.

### 7.5 Other security changes [P2]

- "Fixed a further issue that allowed addons to access minimap rotation values during encounters." (beta 4)
- `Enum.GameRule.UserAddonsDisabled` (29) and `UserScriptsDisabled` (30) exist as game rules [P10]. The wiki notes "Some game modes may be restricted to disallow loading of third-party addons." Not known to be active on any Forever ruleset.

---

## 8. Systems: present, absent, Forever-only

Determined from which Blizzard addon TOCs allow the `camelot` game type on the `forever` branch [P5].

### 8.0 Summary table

| System | On Forever? | Evidence |
|---|---|---|
| Edit Mode | Yes | `Blizzard_EditMode` with `Camelot/` presets; `C_EditMode.*`; layouts saved per UI type (mouse/keyboard vs gamepad); old layout strings import without error [P2] |
| Settings API | Yes | `Blizzard_Settings_Shared` |
| Menu API (`MenuUtil`) | Yes | `Blizzard_Menu` with `Camelot\Menu.xml` |
| ScrollBox, AuraContainer / AuraButton (12.1.0) | Yes | `Blizzard_AuraContainer`; Blizzard statement [P2] |
| Built-in damage meter | Yes | `Blizzard_DamageMeter` `## AllowLoadGameType: standard, camelot` |
| Cooldown Manager / viewer | Yes, off by default | `Blizzard_CooldownViewer` (standard, camelot); CVar `cooldownViewerEnabled` 0; dev notes [P19] |
| Swing timer | **Forever-only** | `Blizzard_SwingTimer` `## AllowLoadGameType: camelot` |
| Legacy system | **Forever-only** | `Blizzard_LegacySystem`, `Blizzard_LegacyChallengeTracker` (camelot) |
| Statistics panel | camelot-only addon | `Blizzard_Statistics` |
| Gamepad UI | **Forever-only** | `Blizzard_Gamepad`, `Blizzard_GamepadActionBars`, `Blizzard_GamepadTargeting` (camelot) |
| Hardcore UI | Yes | `Blizzard_HardcoreUI` (vanilla, camelot) |
| Vanilla-style group finder | Yes | `Blizzard_GroupFinder_VanillaStyle` (classic, camelot) |
| Retail Group Finder (LFD/LFR/premade) | No | `Blizzard_GroupFinder` excludes camelot |
| Encounter Journal | No | `## AllowLoadGameType: standard, classic` |
| Boss timeline / encounter warnings | No | `Blizzard_EncounterTimeline`, `Blizzard_EncounterWarnings` standard only |
| Housing | No | all `Blizzard_Hous*` standard only; beta note calls out housing decor as a modern-WoW reward |
| War Mode | No | `C_PvP.IsWarModeFeatureEnabled()` returns false [P2] |
| Retail PvP UI (`Blizzard_PVPUI`) | No | `## ExcludeLoadGameType: camelot`; `PVPMatch` does load |
| Mythic+/Challenges, Delves pickers, Great Vault landing, Garrison UI, Trading Post, Remix, class trial, expansion landing page, photo sharing | No | standard-only or camelot-excluded TOCs |
| Professions (retail UI) | Yes | `Blizzard_Professions` (mainline) with `Camelot/` folder |
| Auction House (retail UI) | Yes | `Blizzard_AuctionHouseUI` (mainline, ...) |
| Collections (mounts/pets/toys/transmog) | Yes | `Blizzard_Collections` with `Camelot/`; `C_GameRules` `TransmogEnabled` |
| Pet battles | UI loads | `Blizzard_PetBattleUI` (standard, camelot, mists); `Enum.GameRule.PetBattlesDisabled` exists. Whether enabled in game is unconfirmed |
| Nameplates | Yes, retail engine | `Blizzard_NamePlates/Camelot/`; `C_NamePlate.*`, `C_NamePlateManager.*`, `NAME_PLATE_UNIT_ADDED` |
| Personal resource display | Yes | `Blizzard_PersonalResourceDisplay/Camelot` |
| Addon compartment | Yes | section 3.3 |
| Ping system, Quick Join, Recent Allies, RAF | Yes | mainline TOCs |
| Stable UI (retail) | Yes | `Blizzard_StableUI` (standard, camelot) plus stable-slot purchase APIs |
| Quest timer frame | Yes | `Blizzard_QuestTimer` (classic, camelot) |
| Totem bar (MultiCast) | Yes | `MultiCastActionBarFrame`; `Enum.EditModeSystem.TotemActionBar = 25` |
| Keyring, ammo slot | Yes | `showKeyring`, `C_ActionBar.ShouldShowKeyring`, `PaperDollAmmoSlotButton_*`, `Enum.GameRule.EnableAmmoSystem = 177` |

`Enum.EditModeSystem` on Forever: ActionBar 0, CastBar 1, Minimap 2, UnitFrame 3, EncounterBar 4, ExtraAbilities 5, AuraFrame 6, TalkingHeadFrame 7, ChatFrame 8, VehicleLeaveButton 9, LootFrame 10, HudTooltip 11, ObjectiveTracker 12, MicroMenu 13, Bags 14, StatusTrackingBar 15, DurabilityFrame 16, TimerBars 17, VehicleSeatIndicator 18, ArchaeologyBar 19, CooldownViewer 20, PersonalResourceDisplay 21, EncounterEvents 22, DamageMeter 23, RaidWarning 24, TotemActionBar 25, MainActionBarEndCap 26, GroupFinder 27, LossOfControl 28, **SwingTimer 29**, **GamepadMainActionBar 30** [P10].

### 8.1 Talents and specs

- The talent UI is `Blizzard_PlayerSpells/Camelot/ClassTalents/` built on the retail **Traits** system: `C_Traits.GetGroupDisplayInfoByTreeID`, `C_Traits.GetGroupCurrencyInfo`, config IDs from `C_SpecializationInfo.GetCombatConfigIDForSpecGroup(tab)`. New `Enum.TraitConfigType.CamelotCombat = 4` [P5][P10].
- Dual spec: `C_SpecializationInfo.GetActiveSpecGroup()`, `C_SpecializationInfo.SetActiveSpecGroup(group)`; game rules `TalentRespecCostMin/Max/Step` (18/19/20). The wiki describes dual talent specialization unlocking at level 40 for 50 gold [P8].
- Classic-style trees with point thresholds are implied by the dev notes ("16-point talent", "31-point talent") [P19].
- `C_SpecializationInfo.GetTalentInfo`, `GetSpecialization`, `GetSpecializationInfo`, `IsSpecSelectionEnabled`, `HasPlayerEarnedATalentPoint` exist. `GetNumTalentTabs` / global `GetTalentInfo` / global `GetSpecialization` do not. Events present: `CHARACTER_POINTS_CHANGED`, `PLAYER_TALENT_UPDATE`, `TRAIT_CONFIG_UPDATED`, `TRAIT_NODE_CHANGED`, `TRAIT_TREE_CURRENCY_INFO_UPDATED`, `ACTIVE_PLAYER_SPECIALIZATION_CHANGED`, `PLAYER_SPECIALIZATION_CHANGED`.
- What `C_SpecializationInfo.GetSpecialization()` returns for a Forever character (whether "spec" means anything beyond the active spec group) is **unconfirmed**.

### 8.2 Legacy system (Forever-only)

- Replaces achievements: completing challenges earns account-wide Legacy Points spent in per-character trees; 65 points at launch; account rewards at 15/25/40/55 points [P8]. Beta notes mention "Legacy Challenge", "Legacy talent re-spec", "Legacy Reward", "Legacy Talent" [P19].
- UI: `Blizzard_LegacySystem` (load on demand; `LegacySystemFrame_LoadUI`, `ToggleLegacySystemUI`), `Blizzard_LegacyChallengeTracker`.
- There is **no `C_Legacy` namespace**. It is built from `C_Traits` (trees), `C_MajorFactions` (reward track as renown), and achievements (`C_AchievementInfo`, `C_Traits.GetTraitCurrencyForAchievement`) [P5].
- `Constants.LegacyConsts`: `LEGACY_TREE_PROFESSIONS_ID = 1187`, `LEGACY_TREE_ADVENTURE_ID = 1188`, `LEGACY_TREE_PROGRESSION_ID = 1189`, `LEGACY_POINTS_TRAIT_CURRENCY_ID = 4225`, `LEGACY_REWARD_TRACK_FACTION_ID = 2802`, `LEGACY_TREE_ADVENTURE_TALENTED_NODE_ID = 110298`, `LEGACY_DEFAULT_CATEGORY_<CLASS>` = 15577 (Druid) .. 15585 (Warrior) [P10].
- Likely access pattern (derived from Blizzard's own calls, untested): `C_Traits.GetConfigIDByTreeID(1188)`, `C_Traits.GetTreeCurrencyInfo(configID, treeID, ...)`, `C_MajorFactions.GetCurrentRenownLevel(2802)`.

### 8.3 Built-in damage meter

- `C_DamageMeter`: `IsDamageMeterAvailable()` -> `isAvailable, failureReason`; `GetAvailableCombatSessions`, `GetCombatSessionFromID`, `GetCombatSessionFromType`, `GetCombatSessionSourceFromID`, `GetCombatSessionSourceFromType`, `GetSessionDurationSeconds`, `ResetAllCombatSessions` [P5][P10].
- Events: `DAMAGE_METER_COMBAT_SESSION_UPDATED`, `DAMAGE_METER_CURRENT_SESSION_UPDATED`, `DAMAGE_METER_RESET`.
- `Enum.DamageMeterType`: DamageDone 0, Dps 1, HealingDone 2, Hps 3, Absorbs 4, Interrupts 5, Dispels 6, DamageTaken 7, AvoidableDamageTaken 8, Deaths 9, EnemyDamageTaken 10. `Enum.DamageMeterSessionType`: Overall 0, Current 1, Expired 2.
- CVar `damageMeterEnabled` default 0. SavedVariablesPerCharacter `DamageMeterPerCharacterSettings`.
- Forever difference: `Camelot/DamageMeterEntryOverrides.lua` makes `DamageMeterEntryMixin:ShouldShowClassification()` return false.
- Values returned during combat can be secrets (Details and Recount changelogs describe hardening against this) [S2][P13].

### 8.4 Skills (weapon skills, professions list)

`C_SkillInfo.GetNumSkillLines`, `GetSkillLineInfo`, `GetSkillLineInfoByID`, `ExpandSkillHeader`, `CollapseSkillHeader`, `GetSelectedSkill`, `SetSelectedSkill`, `AbandonSkill`; event `SKILL_LINES_CHANGED`; UI in `Blizzard_UIPanels_Game/Camelot/SkillsFrame.lua` [P5]. `UnitDefenseSkill` exists; game rule `FishingClassicDifficulty` (209).

### 8.5 Swing timer (Forever-only)

From `SwingTimerDocumentation.lua` [P5]:

- `C_SwingTimer.EnableRangeCheck(swingType, enable)`
- `C_SwingTimer.IsTargetWithinSwingRange(swingType)` -> `isInRange` (nilable; "Nil must not be treated as out of range")
- Event `PLAYER_SWING`: `swingDuration` (number), `swingType`
- Event `PLAYER_SWING_RANGE_UPDATE`: `swingType`, `isInRange`, `checksRange` (only fires for swing types with an active range check)
- `Enum.PlayerSwingType`: MainHand 0, OffHand 1, Ranged 2
- CVar `showSwingTimer` default 0; Edit Mode system 29.

This is the sanctioned replacement for CLEU-based swing timers.

### 8.6 Experience presets and input style

- `Enum.ForeverExperiencePreset`: Classic 0, Enhanced 1. `C_GameRules.GetForeverExperiencePreset()` (nilable). CVar `hasSelectedExperiencePreset`. Blizzard uses it to pick defaults (e.g. nameplate settings 5 vs 3 in `NameplatesOverrides.lua`) [P5][P10].
- `ShouldUseSilverUnitFrame` exists as a FrameXML function (unit frame art variant; exact trigger not checked).
- Input style: `C_InputInterfaceStyle.GetCurrentStyle()`, event `INPUT_DEVICE_INTERFACE_TRANSITION`, FrameXML `InputUtil.IsGamepadUIEnabled()`, `InputUtil.IsMKBUIEnabled()`, `InputUtil.RegisterForInterfaceTransitions`. The Nov 3 notes say Blizzard "Improved Gamepad UI compatibility with user-created add-ons" [P19]. Addons that replace action bars or bags should check whether gamepad UI is active.

### 8.7 Unit frames, nameplates, minimap (skinning hazards) [P2]

- Beta 5: "The Forever player, target, pet, target-of-target, totem and focus frames, and the minimap header, have been reskinned and some of their child frames reorganized. Addons that skin or anchor to these frames may need to adjust things."
- Beta 5: "Nameplates are no longer shown for non-target units far above or below the player", controlled by `nameplateMaxVerticalDistance` and `nameplateMaxVerticalDistanceAtMaxRange` (0 disables).
- Game rules can disable or alter stock frames: `PlayerFrameDisabled` 131, `TargetFrameDisabled` 130, `PlayerCastBarDisabled` 105, `TargetCastBarDisabled` 106, `NameplateCastBarDisabled` 107, `EditModeDisabled` 82, `MaxNameplateDistance` 28, `NoDebuffLimit` 1, `SingleTargetComboPoints` 112.
- Combo points: `Blizzard_UnitFrame/Camelot/ComboFrame.lua`, `TargetBoundComboPointBar.lua`. ElvUI needed "oUF: attempt to fix rogue combo points on Forever" [P20].
- Day/night: `C_DateAndTime.IsDayTime()`, event `DIEL_CYCLE_CHANGED`.

### 8.8 Other Classic-flavoured game rules visible in `Enum.GameRule` [P10]

`VanillaNpcKnockback` 16, `VanillaRageGenerationModifier` 21, `DisableHonorDecay` 23, `BinarySpellPushbackResist` 90, `PremadeGroupFinderStyle` 93 (`Enum.PremadeGroupFinderStyle`: Disabled 0, Mainline 1, Vanilla 2), `SummoningStones` 108, `LootMethodStyle` 157, `EnableAmmoSystem` 177, `DisallowAbandoningLastPet` 180, `ThrownWeaponsUseDurability` 181, `AutoLearnPetSpells` 182, `QuestLootRoundRobin` 197, `ManaRegenBonusStatMeansMp5` 244, `CannotSkinCreaturesTooHighLevelForYourSkinningSkill` 247, `RangedAttackDelay` 249, `WeaponSwapIgnoresCombatSwapCd` 252, `RequirePvPFlagForPvPKillCredit` 255. Query with `C_GameRules.IsGameRuleActive(Enum.GameRule.X)` or `C_GameRules.GetGameRuleAsFloat(...)`. Which are active on live realms was not checked.

`GetInspectHonorData` returns two extra values: the inspected player's current honor and honor needed for their next level [P2].

---

## 9. Names: surnames replace realm names (biggest surprise)

Forever characters have a first name and optional surname, and names are regionally unique rather than per-realm.

- `UnitName(unit)` and `UnitNameUnmodified(unit)` return `name, surname` on Forever. The API doc still labels the second return `unitServer`, but Blizzard's `Blizzard_FrameXMLUtil/Camelot/NameUtil.lua` reads it as `surname` [P5]:

```lua
function NameUtil.GetUnmodifiedUnitFullName(unit)
    local name, surname = UnitNameUnmodified(unit);
    if surname then
        return name .. Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR .. surname;
    end
    return name;
end
```

- `Constants.CharacterNameSeparatorConsts`: `CHARACTERNAME_SURNAME_SEPARATOR = " "` (space), `CHARACTERNAME_REALMNAME_SEPARATOR = "-"`, `CHARACTERNAME_LINK_SEPARATOR = "-"` [P10].
- Helpers: `NameUtil.FormatUnitNameForDisplay(unit)`, `NameUtil.GetUnmodifiedUnitFullName(unit)`, `NameUtil.GetFullNameWithoutRealm(first, surname)`, `NameUtil.SplitPlayerNameIntoParts(full)`, `NameUtil.GetUnitFirstName(unit)`, `NameUtil.IsPlayerMe(name, surname)`; C API `RegionalUniqueNamesEnabled()`, `C_PlayerInfo.ShouldDisplaySurname()`, `C_NameUtil.ReplaceSurnameSeparatorWithLinkSeparator(fullName)`; CVar `UnitSurnameOwn`.
- BigWigs' fix ("UnitName fixes for WoW Forever", 2026-11-08) [P12]:

```lua
if addonTbl.isForever then
    function API.UnitName(unit)
        local name, surname = UnitNameUnmodified(unit)
        if not name then return
        elseif surname then name = name .." ".. surname end
        return name
    end
end
```

- BigWigs then rewrote AutoInvite on 2026-11-22 "to compensate for latest WoW Forever changes (no more realm name)", switching to GUID-keyed logic and `C_BattleNet.IsGameAccountOnSameRealm` (annotated by the author as Forever-only) [P12]. This implies a post-launch server/client change around Nov 21-22 that removed realm names from sender strings. ElvUI has matching commits "API: receive sender adjustment forever" and "AFK: display full name on forever" (2026-11-21) [P20]; Details has "Standardize the remove realm names and use it for removing last names on Forever" [P13].

Consequences for addon code:
- `name .. "-" .. realm` logic is wrong on Forever. Patterns like `name:gsub("%-.*", "")` or `strsplit("-", sender)` do not strip anything useful and names may contain a space.
- Key player data by GUID where possible.
- Whisper/invite targets and `CHAT_MSG_*` sender formats: the exact string format after the Nov 21-22 change was **not verified from a primary source**. Test in game before relying on it.
- SavedVariables paths still use `WTF\Account\<acct>\<server>\<character>\`. How surnames appear in the character folder name was not checked.

---

## 10. What real addons changed for Forever

All from commit messages and diffs in the projects' GitHub repos (primary for "what the addon did", not for Blizzard behaviour).

**BigWigs** (BigWigsMods/BigWigs, 7 commits mentioning Forever) [P12]
- 2026-09-18 "Initial toc file improvements for WoW Forever": added `16001` to one combined `## Interface:` line and moved to inline directives, e.g. `BossPrototype.lua [ExcludeLoadGameType vanilla, tbc, wrath]`, `BossPrototype_Classic.lua [AllowLoadGameType vanilla, tbc, wrath]`.
- 2026-09-18 "Define `## AllowLoadGameType` in our retail content addons to prevent them showing on Forever": retail raid files tagged `[AllowLoadGameType standard]`, because `mainline`-family addons otherwise appear on Forever.
- 2026-09-19 "Plugins/BossBlock: Tweaks for WoW Forever": does not register `TALKINGHEAD_REQUESTED` on Forever; hides garrison / guild-challenge blocking options.
- 2026-11-05 "Plugins/Bars: Allow additional bar callbacks on Forever": Forever takes the same code path as retail (`if isRetail or isForever`).
- 2026-11-08 UnitName surname fix; 2026-11-22 AutoInvite rewrite (section 9).
- LittleWigs: "Prep separate folder for Forever" (2026-11-04).

**Details! Damage Meter** (Tercioo/Details-Damage-Meter, 8 commits) [P13]
- 2026-09-24 "First pass to making it work on forever": adds `DF.IsForeverWow()` (interface 16000-19999), excludes Forever from `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE` branches, removes retail spell tables that call `GetSpellInfo`.
- Later: "More fixing for forever + midnight normalization", "ORL fix for Forever", "Bug fixes for Forever Wow; Added LibKeystone", surname handling, "Add translit on forever/midnight".

**DBM** (DeadlyBossMods/DeadlyBossMods, 41 commits) [P21]
- "Fix bug causing aura sounds and aura container to not fully work in forever"; "Allow aura sounds on enemies and co tanks, making dbm a bit more useful in forever"; "restore whisper privacy options on midnight and forever"; "Fix forever version check not actually check for vanilla/forever raid modules".
- Author's complaint in a commit message: "rework trash alerts again ... blizzard can't use right events for cast bar casts on bosses in forever". Suggests boss cast events on Forever are irregular; unverified beyond that message.

**Questie** (Questie/Questie, 110 commits) [P14]
- Ships `Questie_Forever.toc` and `Questie_Camelot.toc` with `## Interface: 16001` (local install, v12.6.4).
- "[fix][Forever] Open the quest details from the tracker without tainting the map"; "[fix][Forever] Open settings on addon compartment left click"; "fix(locale): use Era German translations on Forever"; database commits such as "[db][Forever] Blacklist the SoD daily mission quests".

**ElvUI** (tukui-org/ElvUI, 64 commits) [P20]
- "AB: allow MultiCastActionButton only on Forever", "AB: adjust Forever paging for priests", "oUF: attempt to fix rogue combo points on Forever", "DT: add ammo on forever", "Skins: Forever update/fixes" (several), "DB: Bump cam distance to 4 in Forever", "minimap: external event is also on forever (cn region)".

**Bartender4** (Nevcairiel/Bartender4, 13 commits) [P22]
- "Update BlizzardArt to better match Mainline, and add Forever support", "Add Presets for WoW Forever", "Set the correct default bag bar padding for the Forever Modern layout", "Enable Totem bar in Wow Forever".

**WeakAuras**
- The GitHub commit search reported 2 commits matching "forever" in WeakAuras/WeakAuras2 but I could not read them (API returned nothing on retry). [S] Icy Veins ran a piece titled "No WeakAuras in WoW Forever, here's what to use instead" (page returned 403; title and gist from search results) and a CurseForge listing "Musca Auras" describes itself as an unofficial WeakAuras 5.22.0 port to client 1.60.1 [S4]. No official WeakAuras statement about Forever was found. **Unconfirmed.**

**Leatrix** - not researched.

Recurring themes across these addons:
1. Forever goes down the retail/Midnight code path, not the Classic one.
2. Retail-only content must be explicitly excluded (`[AllowLoadGameType standard]`) because Forever is in the `mainline` family.
3. Surnames / no realm names broke name handling everywhere.
4. Classic-only widgets came back and need support: totem bar (`MultiCastActionButton`), ammo, combo points on target, weapon skills.
5. Reskinned unit frames required skin updates through late October.

---

## 11. Checklist for writing a Forever addon in this workspace

1. TOC: `## Interface: 16001`. Single-client addon needs no suffix or game-type directive.
2. Namespaced APIs only: `C_Spell`, `C_Item`, `C_UnitAuras`, `C_AddOns`, `C_Container`, `C_QuestLog`, `C_ChatInfo`, `C_SpellBook`, `C_PartyInfo`, `C_Reputation`, `C_SkillInfo`, `C_SpecializationInfo`, `C_Traits`. Do not rely on `Blizzard_Deprecated*` shims.
3. No combat log. Use `C_DamageMeter`, `PLAYER_SWING`, `UNIT_SPELLCAST_*`, `UNIT_AURA`.
4. Assume secrets in combat: check `issecretvalue()` before comparing/arithmetic/concatenation on health, power, aura, cooldown, name and damage-meter values; pass values straight to widgets.
5. Names: `local name, surname = UnitNameUnmodified(unit)`; join with `" "`; never assume `Name-Realm`; key by GUID.
6. Options UI: `Settings.RegisterCanvasLayoutCategory` / `RegisterVerticalLayoutCategory` + `Settings.RegisterAddOnCategory`; menus via `MenuUtil`; lists via ScrollBox.
7. Movable frames: consider Edit Mode coexistence; Blizzard frames were reorganised in beta 5, so verify child frame names against the `forever` branch before anchoring.
8. `C_X ~= nil` is not a feature test for retail systems (section 6.4).
9. Addon comms: check the `Enum.SendAddonMessageResult` return; expect lockdown during encounters; trial accounts cannot send.
10. Verify signatures against `Blizzard_APIDocumentationGenerated` on the `forever` branch or with `/api` in game.

---

## 12. Confirmed vs unconfirmed

### Confirmed from primary sources
- Interface 16001, patch 1.60.1, `WOW_PROJECT_CAMELOT = 18`, game types `camelot`/`forever`, family `mainline`.
- TOC suffixes `_Camelot` / `_Forever`; `forever` alias from build 70291; `AllowLoadGameType` needs a paired `ExcludeLoadGameType` on multi-client TOCs.
- `Gethe/wow-ui-source` branch `forever` and tag `1.60.1`; `Ketho/BlizzardInterfaceResources` branch `forever` and tag `1.60.1`.
- BigWigs packager: game type `forever`, suffix `Camelot` only, CurseForge type id 88568, no WoWInterface mapping. Wago: `forever` / `supported_forever_patches`, suffixes `-Camelot`, `_Camelot`, `-Forever`, `_Forever`.
- Midnight secrets and addon disarmament apply to Forever (Blizzard statement); secret APIs, `C_Secrets`, `C_RestrictedActions` exist in the Forever client.
- Old globals (`GetSpellInfo`, `GetItemInfo`, `UnitAura`, `UnitBuff`, `GetAddOnMetadata`, `IsAddOnLoaded`, `GetContainerItemInfo`, `GetNumTalentTabs`, `GetNumSkillLines`, `SendAddonMessage`, ...) are absent; `C_*` equivalents present.
- `SendChatMessage` and action-bar globals exist only via deprecation shims gated on `loadDeprecationFallbacks` (default 1).
- No insecure `C_CombatLog.GetCurrentEventInfo`; CLEU flagged `HasRestrictions`.
- Trial accounts cannot send addon messages; EMOTE needs hardware event outside instances; creature/vehicle/pet/object GUID server and spawn IDs obfuscated; `FrameStrata` secret aspect; `require` renamed `import`; `C_PvP.IsWarModeFeatureEnabled()` false; `GetInspectHonorData` +2 returns; Edit Mode layouts per UI type; unit frames and minimap header reskinned; nameplate vertical-distance CVars.
- Edit Mode, Settings, Menu, damage meter, cooldown viewer, addon compartment present; housing, encounter journal, retail group finder, retail PvP UI, M+/delves UI, garrison UI absent; swing timer, Legacy system, gamepad UI are Forever-only.
- Talents use `C_Traits` with `TraitConfigType.CamelotCombat = 4` and spec groups via `C_SpecializationInfo`.
- `UnitName` second return is treated as a surname by Blizzard's Forever code; surname separator is a space.
- Level cap 60; nine classes; classic races plus Skyborne; launch 2026-11-04.

### Unconfirmed, stale-risk, or secondary only
- **Exact runtime behaviour of registering `COMBAT_LOG_EVENT_UNFILTERED` on Forever** (error vs forbidden popup vs silence). Only a secondary report says it is forbidden with a popup.
- **When secrets actually trigger on Forever** (open-world combat, dungeons, raids, PvP). No Forever-specific primary description found; only the general Midnight predicates.
- `C_CombatLog.IsCombatLogRestricted()` semantics.
- Chat sender / whisper target string format after the ~Nov 21-22 "no more realm name" change. Inferred from BigWigs and ElvUI commits only.
- Any Blizzard policy statement on layer-hopping addons beyond the GUID obfuscation note. None found.
- Payloads of `SHARD_TRANSFER*` events.
- Whether WeakAuras officially supports Forever. Secondary sources say no.
- Whether pet battles, transmog and other retail systems whose UI loads are actually enabled in game.
- Which `Enum.GameRule` values are active on live realms.
- Out-of-date / incompatible interface-version tolerance on Forever (open TODO on the wiki).
- Whether `## X-Game: [Game]` keeps working (12.1.7 "Prevented use of variables in addon directives").
- The Discord-hosted originals of Blizzard's addon notes were not read directly; I used the wiki's mirror (`Patch_1.60.1/API_changes/notes`). The wiki's reference links point to the WoWUIDev Discord, which I cannot open.
- CurseForge's own documentation of the Forever game version; only the packager's hard-coded id was seen.
- Beta-specific items that may be stale: everything dated Sep 15 - Oct 16 in the Blizzard notes (the statements were not retracted anywhere I read, and the live UI source is consistent with them). The wiki's "consolidated changes" lists are a diff at beta build 70205, so later additions (`forever` alias, `import`, nameplate CVars, `SetForeverExperiencePresetPre/PostLogin`) are not in those lists.
- The Blizzard forum dev-notes thread contains no API/addon statements other than the gamepad compatibility line; about 64k characters of that page were read only through a summarising fetch.
- Sibling research files in the session scratchpad (12.0.x / 12.1.x wiki dumps) were present but not used here.

---

## 13. Quick reference: constants

```
## Interface: 16001
WOW_PROJECT_CAMELOT            = 18
WOW_PROJECT_MAINLINE           = 1
LE_EXPANSION_LEVEL_CURRENT     = 0
Enum.GameRule.HardcoreRuleset  = 10
Enum.GameRule.PvPRuleset       = 213
Enum.GameRule.RPRuleset        = 214
Enum.GameRule.UserAddonsDisabled = 29
Enum.ForeverExperiencePreset   = { Classic = 0, Enhanced = 1 }
Enum.PlayerSwingType           = { MainHand = 0, OffHand = 1, Ranged = 2 }
Enum.TraitConfigType.CamelotCombat = 4
Enum.AddOnRestrictionType      = { Combat=0, Encounter=1, ChallengeMode=2, PvPMatch=3, Map=4, Chat=5 }
Enum.AddOnRestrictionState     = { Inactive=0, Activating=1, Active=2 }
Enum.EditModeSystem.SwingTimer = 29
Enum.EditModeSystem.DamageMeter = 23
Enum.EditModeSystem.TotemActionBar = 25
Enum.SecretAspect.FrameStrata  = 0x1000000
Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR = " "
Constants.LegacyConsts.LEGACY_POINTS_TRAIT_CURRENCY_ID = 4225
Constants.LegacyConsts.LEGACY_REWARD_TRACK_FACTION_ID  = 2802
Constants.LegacyConsts.LEGACY_TREE_PROFESSIONS_ID / ADVENTURE_ID / PROGRESSION_ID = 1187 / 1188 / 1189
CurseForge game version type id (packager) = 88568
Wago patch key = "forever"
```

---

## 14. Sources

### Primary
- [P1] warcraft.wiki.gg, "Patch 1.60.1/API changes" (raw wikitext): https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes
- [P2] warcraft.wiki.gg, "Patch 1.60.1/API changes/notes" (mirror of Blizzard's WoWUIDev Discord posts of 2026-09-15, 10-08, 10-16): https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes/notes
- [P3] warcraft.wiki.gg, "TOC format" and Template:GameTypes: https://warcraft.wiki.gg/wiki/TOC_format , https://warcraft.wiki.gg/wiki/Template:GameTypes
- [P4] warcraft.wiki.gg, "WOW_PROJECT_ID": https://warcraft.wiki.gg/wiki/WOW_PROJECT_ID
- [P5] Gethe/wow-ui-source, branch `forever` / tag `1.60.1` (commit c01a87b, "1.60.1 (71091)"): https://github.com/Gethe/wow-ui-source/tree/forever . Files cited: `Blizzard_ProjectConstants/`, `Blizzard_Deprecated*/`, `Blizzard_DamageMeter/`, `Blizzard_SwingTimer/`, `Blizzard_LegacySystem/`, `Blizzard_FrameXMLUtil/Camelot/NameUtil.lua`, `Blizzard_FrameXMLBase/Camelot/Constants.lua`, `Blizzard_PlayerSpells/Camelot/`, `Blizzard_CombatLogProcessor/`, `Blizzard_APIDocumentationGenerated/{CombatLog,ChatInfo,SwingTimer,DamageMeter,GameRules,Unit}Documentation.lua`, and all addon TOCs.
- [P6] warcraft.wiki.gg, Template:LatestPatchInfo (build numbers, product folders): https://warcraft.wiki.gg/wiki/Template:LatestPatchInfo
- [P7] Blizzard news, "Carve a New Path with World of Warcraft: Forever": https://news.blizzard.com/en-us/article/24302093/carve-a-new-path-with-world-of-warcraft-forever
- [P8] warcraft.wiki.gg, "World of Warcraft: Forever": https://warcraft.wiki.gg/wiki/World_of_Warcraft:_Forever
- [P9] Blizzard forums, "WoW Forever Beta Development Notes" (class/race lists, see P19).
- [P10] Ketho/BlizzardInterfaceResources, branch `forever` / tag `1.60.1` ("1.60.1 (70938)"): https://github.com/Ketho/BlizzardInterfaceResources/tree/forever/Resources
- [P11] BigWigsMods/packager `release.sh` and `README.md` (master): https://github.com/BigWigsMods/packager
- [P12] BigWigsMods/BigWigs commits 6ccb8ed51c, 8e4f0ecfcd, 3bb5624361, 6eb1eac9ba, 1ebaca2ddf, 9a5314d0b2: https://github.com/BigWigsMods/BigWigs/commits
- [P13] Tercioo/Details-Damage-Meter commits a15bcae19b, 5a11e5e20d and others: https://github.com/Tercioo/Details-Damage-Meter/commits
- [P14] Questie/Questie commits (a3f79844b8, 7df91a1a79, 1583685e1e, 58ab19cb5c) and the locally installed `Questie_Forever.toc`: https://github.com/Questie/Questie/commits
- [P15] Wago Addons game data API: https://addons.wago.io/api/data/game
- [P16] CurseForge support, "Multi-TOC for World of Warcraft addons" (no Forever content): https://support.curseforge.com/support/solutions/articles/9000209856-multi-toc-for-world-of-warcraft-addons
- [P17] warcraft.wiki.gg, "Secret Values": https://warcraft.wiki.gg/wiki/Secret_Values
- [P18] warcraft.wiki.gg, "Patch 12.0.0/API changes/notes" (Blizzard's Midnight addon notes): https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes/notes
- [P19] Blizzard forums, "WoW Forever Beta Development Notes" (updated through Nov 2-4, 2026): https://us.forums.blizzard.com/en/wow/t/wow-forever-beta-development-notes-%E2%80%93-updated-september-24/2360696
- [P20] tukui-org/ElvUI commits (3d5a190c1f, 9d4f81a542, ca7d1cfce8, 4ec2b91b32, 3866b3f0f4, ...): https://github.com/tukui-org/ElvUI/commits
- [P21] DeadlyBossMods/DeadlyBossMods commits (bc5676f882, 010b7befce, 537ed1b9ca, e903df8116, 3e0fa7b448, ...): https://github.com/DeadlyBossMods/DeadlyBossMods/commits
- [P22] Nevcairiel/Bartender4 commits (2ced21c041, cd62b9c21e, 00a75f694c, 6d4f7e6636): https://github.com/Nevcairiel/Bartender4/commits

### Secondary (leads only)
- [S1] gamertagmythras.com Forever addons guide (install path, Questie TOC claim): https://gamertagmythras.com/blog/world-of-warcraft/wow-forever-addons-guide
- [S2] CurseForge listings describing combat-log unavailability and `C_DamageMeter` use: https://www.curseforge.com/wow/addons/forever-meter , https://www.curseforge.com/wow/addons/dalicount , https://www.curseforge.com/wow/addons/wombatlog , https://www.curseforge.com/wow/addons/recount-revived/files/8225229 ; GitHub PR (page not retrievable, 404): https://github.com/ownjoo/bgcomms/pull/11
- [S3] CurseForge layer addons for Forever: https://www.curseforge.com/wow/addons/hopper , https://www.curseforge.com/wow/addons/layertracker , https://www.curseforge.com/wow/addons/my-layer-tracker
- [S4] Icy Veins, "No WeakAuras in WoW Forever..." (403 on fetch): https://www.icy-veins.com/wow-forever/news/no-weakauras-in-wow-forever-heres-what-to-use-instead/ ; CurseForge "Musca Auras": https://www.curseforge.com/wow/addons/musca-auras
- General launch coverage seen in search results (not used for facts beyond what P7/P8 state): Game Informer, Kotaku, Icy Veins, TechSpot.
