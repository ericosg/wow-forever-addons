# Secret values and addon restrictions (Midnight rules as they apply to WoW Forever 1.60.1)

Researched 2026-11-25. Target client: WoW Forever 1.60.1, TOC 16001, build 71037 (game type `camelot` / `forever`).

Nothing here was tested in game. Every claim is tagged with a source key from the [source list](#sources), `[primary]` (Blizzard post, Blizzard-generated API docs, wiki transcription of those, or addon source code) or `[secondary]`, and the patch it was documented for. "Forever docs" means Blizzard's own generated API documentation on the `forever` branch of the wow-ui-source mirror, read at branch head build 71091 (the branch also has a commit for 71037; files cited here were last changed long before either).

## 0. Read this first

1. **The restrictions are on in Forever.** Blizzard, 2026-09-15: "The addon disarmament changes introduced in Midnight, including secrets, will also be active in Forever." Forever is the `Camelot` game type inside the Mainline code family and has "the vast majority of APIs available in 12.1.5". [W-1601N, primary, 1.60.1]
2. **Classic clients are different.** On Classic builds (5.5.4 etc.) the secret system is "entirely disabled". Forever is *not* a Classic build in this sense. Check at runtime with `C_Secrets.HasSecretRestrictions()`. [W-1205N, primary, 12.0.5; GH-DOC SecretPredicateAPI]
3. **A secret is a black box.** Addon (tainted) code may store it, pass it on, concatenate it, and hand it to a specific list of APIs. Any attempt to *look at* it (compare, do arithmetic, branch on a secret boolean, use as a table key, index it, take its length, call it) raises an immediate Lua error. [W-SV, primary, 12.0.0+]
4. **All addon code is tainted, always.** There is no way for an addon to become untainted. So every "AllowedWhenUntainted" note in the API docs means "not for you" when the argument is secret.
5. **Display, don't decide.** The design goal is that addons can restyle combat information but cannot run logic on it. Pipe secrets straight into widgets (`StatusBar:SetValue`, `FontString:SetText`, ...) or through Blizzard-provided transformers (curves, duration objects, formatters). [W-1200N Oct 1 and Nov 13 posts, primary, 12.0.0]

## 1. What a secret value is

- Introduced in 12.0.0. "Secret values ... restrict the ability for addons to perform some operations on Lua values on tainted execution paths." [W-SV, primary]
- A secret wraps a value of any Lua type. `type(secret)` returns the real type (`"number"`, `"string"`, ...). [W-SV, primary]
- "When execution is not tainted secret values are effectively equivalent to regular values" (this is how Blizzard's own UI keeps working). [W-SV, primary]
- "APIs that return Secrets are called out in the Lua API docs." [W-1200N Oct 1, primary]

### 1.1 Exactly what tainted code may and may not do

From the wiki "Restrictions" list [W-SV, primary, 12.0.0, still current on 12.1.5 page] plus the dated Blizzard posts in [W-1200N]:

| Operation on a secret | Tainted code | Notes |
|---|---|---|
| Store in local / upvalue / table **value** | allowed | |
| Pass to a Lua function | allowed | |
| Pass to a C API | only if that API is marked `SecretArguments = "AllowedWhenTainted"` | else error, see §9 |
| `..` concatenation of secret strings/numbers | allowed (result is secret) | relaxed in Alpha 3, Oct 2025 |
| `string.format`, `string.concat`, `string.join` | allowed (result is secret) | Alpha 3. Precision/width on `%s` is ignored for secret strings (`%.1s` no longer truncates) [W-1201N Mar 21, W-1205N] |
| Arithmetic (`+ - * / % ^`, unary minus) | **error** | |
| Comparison (`== ~= < <= > >=`) | **error** | exceptions below |
| `if secret then` / `not secret` / `and` / `or` on a secret **boolean** | **error** | |
| `if secret then` on a secret **non-boolean** | allowed | "nil always evaluates as false, and all other types besides boolean always evaluates as true". `if x then` is equivalent to `type(x) ~= "nil"` [W-SV; W-1200N Nov 4] |
| `#secret` | **error** | |
| Use as table **key** (`t[secret] = v`, `t[secret]`) | **error** | |
| Index or assign into it (`secret.foo`, `secret[1] = x`) | **error** | |
| Call it (`secret()`) | **error** | |
| `tonumber(secretString)` | **not permitted** | also applies to "any C API that would otherwise accept a number" [W-1200N Nov 4] |
| `tostring(secret)` | not explicitly documented; a 12.1.5 fix says `tostring` and `dumpobject` no longer *crash* on secret objects [W-1215N]. Treat the result as secret. | unconfirmed detail |
| `type(secret)` | allowed, returns real type | |
| Save in SavedVariables | silently replaced by `nil` (with a comment in the file) | Beta 1 [W-1200N Nov 11] |

Comparison exceptions (Alpha 6, Nov 2025) [W-1200N Nov 4, primary]:

- "Equality comparing two possibly-secret values of different types will no longer error and will produce a non-secret false."
- "Equality comparing two possibly-secret nil values will no longer error and will produce a non-secret true."

Loops: a "exploit with secret numbers and loops" was fixed before 12.0.1; do not use secrets as `for` bounds. [W-1200N Feb 3, primary]

### 1.2 How secrecy propagates

- Results of permitted string operations on secrets are secret. [W-1200N Oct 11]
- Many APIs return structured tables or mixins that are themselves ordinary tables with secret *fields* ("no longer make the entire table secret - just the values inside"), e.g. a `ColorMixin` from a color curve: `color:GetRGB()` works and returns secrets. [W-1200N Oct 17/27, primary]
- **Secret tables**: a table can be flagged so every indexed read yields a secret, and/or flagged inaccessible to tainted code ("attempted to index a forbidden table"). "When untainted code stores a secret value as a table key, the table itself is irrevocably marked with both". Test with `issecrettable(t)` / `canaccesstable(t)`. [W-SV, primary]
- **Widgets**: passing a secret into a widget setter marks the widget (secret aspects / "has secret values"), after which the matching getters return secrets. See §3.
- **Curves / durations / formatters** configured with secret inputs produce secret outputs (`HasSecretValues()` on those objects). [GH-DOC]
- `debugstack` and `debuglocals` "return secret values if the current function - or any caller up the stack - has accessed a secret value." [W-1207N, primary, 12.0.7]
- Secrets survive `/reload` (a bug that un-secreted them was fixed). [W-1200N Dec 18]

## 2. Testing and inspecting

### 2.1 Global functions

Signatures from Forever docs [GH-DOC FrameScriptDocumentation.lua, primary, 1.60.1]. All are callable by addons unless noted.

| Function | Returns | Doc text |
|---|---|---|
| `issecretvalue(value)` | `isSecret: bool` | "Returns true if a supplied value is a secret value." |
| `hasanysecretvalues(...)` | `bool` | True if any supplied value is secret. |
| `canaccessvalue(value)` | `bool` | "Returns true if the immediate calling function has appropriate permissions to access and operate on a specific value." (true for non-secrets; false for a secret when you are tainted) |
| `canaccessallvalues(...)` | `bool` | Same for a list of values. |
| `canaccesssecrets()` | `bool` | Whether the calling function may operate on secrets at all (false for addons). |
| `issecrettable(table)` | `bool` | True if the table value is secret "or if flags on the table are set such that accesses of the table would produce secrets." |
| `canaccesstable(table)` | `bool` | False "if the caller cannot access the table value itself, or if access to the table contents is disallowed by taint." |
| `scrubsecretvalues(...)` | `...` | "Returns a transformed list of values with inputs that are secret values replaced by nil values." |
| `scrub(...)` | `...` | As above, and also nils anything that is not string/number/boolean. |
| `secretwrap(...)` | `...` | "Converts all supplied values to secret values". Useful for testing your own code paths. |
| `mapvalues(func, ...)` | `...` | Applies `func` to each value. |
| `dropsecretaccess()` | | Removes the caller's ability to access secrets (for Blizzard code). |
| `secretunwrap(...)` | | Listed with `HasRestrictions = true`; "Removed secretunwrap from the global table" in Beta 3 [W-1200N Dec 1]. Not usable by addons. |
| `settablesecurity(table, option)` | | `HasRestrictions`. `Enum.TableSecurityOption`: `DisallowTaintedAccess=0, DisallowSecretKeys=1, SecretWrapContents=2`. |

These return plain (non-secret) booleans, so they are safe to branch on.

```lua
local hp = UnitHealth("target")
if issecretvalue(hp) then
    bar:SetValue(hp)                 -- display only
else
    bar:SetValue(hp)
    if hp < 100 then DoThing() end   -- logic allowed only on the non-secret path
end
```

Idiom used by oUF to turn "maybe secret" into "value or nil" [OUF private.lua, primary source code, supports Forever]:

```lua
local same = scrubsecretvalues(UnitIsUnit(unit, "target"))  -- nil when secret
local guid = scrubsecretvalues(UnitGUID(unit))
```

Idiom used by Questie on this Forever client for cross-client safety [QST, primary, local install]:

```lua
if issecretvalue and issecretvalue(npcGuid) then return end
```

### 2.2 `C_Secrets` (predict secrecy without calling the API)

All return non-secret values [GH-DOC SecretPredicateAPIDocumentation.lua, primary, 1.60.1; added 12.0.0 Beta 4 / PTR 2 per W-1200N]:

- `C_Secrets.HasSecretRestrictions() -> bool` - "Returns true if this client build has secret value restrictions enabled. If false, all APIs that are tagged as potentially returning secrets will never do so."
- General state: `ShouldAurasBeSecret()`, `ShouldCooldownsBeSecret()`, `ShouldUnitStatsBeSecret()`
- Units: `ShouldUnitIdentityBeSecret(unit)`, `ShouldUnitHealthMaxBeSecret(unit)`, `ShouldUnitPowerBeSecret(unit [, powerType])`, `ShouldUnitPowerMaxBeSecret(unit [, powerType])`, `ShouldUnitSpellCastingBeSecret(unit)`, `ShouldUnitSpellCastBeSecret(unit, spellIdentifier)`, `ShouldUnitComparisonBeSecret(unit1, unit2)`, `CanCompareUnitTokens(unit1, unit2)`, `ShouldUnitThreatStateBeSecret(unit [, mobUnit])`, `ShouldUnitThreatValuesBeSecret(unit, mobUnit)`
- Auras: `ShouldSpellAuraBeSecret(spell)`, `ShouldUnitAuraIndexBeSecret(unit, index [, filter])`, `ShouldUnitAuraInstanceBeSecret(unit, auraInstanceID)`, `ShouldUnitAuraSlotBeSecret(unit, slot)`
- Cooldowns: `ShouldSpellCooldownBeSecret(spell)`, `ShouldActionCooldownBeSecret(actionID)`, `ShouldSpellBookItemCooldownBeSecret(slot, bank)`
- Totems: `ShouldTotemSlotBeSecret(slot)`, `ShouldTotemSpellBeSecret(spellID)`
- Base secrecy level: `GetSpellAuraSecrecy(spell)`, `GetSpellCooldownSecrecy(spell)`, `GetSpellCastSecrecy(spell)`, `GetPowerTypeSecrecy(powerType)` -> `Enum.SecrecyLevel` (`NeverSecret=0, AlwaysSecret=1, ContextuallySecret=2`)

There is no `ShouldUnitHealthBeSecret`; see §4.1.

### 2.3 `C_RestrictedActions` (which restriction state is active)

[GH-DOC RestrictedActionsDocumentation.lua + Constants, primary, 1.60.1]

- `C_RestrictedActions.IsAddOnRestrictionActive(type) -> bool` ("Will always return false during dispatch of ADDON_RESTRICTION_STATE_CHANGED.")
- `C_RestrictedActions.GetAddOnRestrictionState(type) -> Enum.AddOnRestrictionState` (`Inactive=0, Activating=1, Active=2`)
- `Enum.AddOnRestrictionType`: `Combat=0, Encounter=1, ChallengeMode=2, PvPMatch=3, Map=4, Chat=5` (Chat added 12.0.5 [W-ART])
- Event `ADDON_RESTRICTION_STATE_CHANGED(type, state)` - "sequenced such that it will always be fired before a restriction becomes active, or after it is deactivated", timing similar to `PLAYER_REGEN_DISABLED/ENABLED`. [W-1200N Dec 8]
- `C_ChatInfo.InChatMessagingLockdown() -> bool` [GH-DOC ChatInfo]
- `InCombatLockdown()` is unchanged (old protected-frame lockdown, a separate system).

BigWigs example [BW Plugins/Sound.lua, primary source code]:

```lua
local IsAddOnRestrictionActive = C_RestrictedActions.IsAddOnRestrictionActive
if IsAddOnRestrictionActive(1) or (IsAddOnRestrictionActive(0) and IsAddOnRestrictionActive(2)) then
    -- Encounter, or Combat+ChallengeMode
end
```

### 2.4 Simulating restrictions (CVars, do not persist across restarts)

Two naming schemes appear in primary sources; check which exists on the client before relying on either:

- Wiki Secret Values page (current): `addonCombatRestrictionsForced`, `addonEncounterRestrictionsForced`, `addonChallengeModeRestrictionsForced`, `addonPvPMatchRestrictionsForced`, `addonMapRestrictionsForced`, `addonChatRestrictionsForced`. [W-SV]
- Blizzard PTR 2 post (Dec 2025): `secretCombatRestrictionsForced`, `secretEncounterRestrictionsForced`, `secretChallengeModeRestrictionsForced`, `secretPvPMatchRestrictionsForced`, `secretMapRestrictionsForced` (replacing older `secretXForced` CVars). [W-1200N Dec 22]

`/dump` prints the contents of secret values (Alpha 4), and `/eventtrace` shows the secret state of payloads (Beta 4). [W-1200N]

## 3. Widgets: secret aspects, secret anchors, what accepts secrets

### 3.1 Concepts

[W-SV; W-1200N Oct 1; primary]

- **Secret aspect**: a group of related APIs on one object. Passing a secret to a setter in the group marks the object with that aspect; all getters in the group then return secrets. Aspects are independent of each other.
- **Object "has secret values"**: when an API with no specific aspect receives a secret, the whole object is marked. That also makes its **anchoring secret**.
- **Secret anchors**: position/size getters return secrets; "The secrecy of anchoring and position data propagates downwards to dependent anchored regions" (frames anchored *to* it), not upward. "Calling any API with secrets that applies a Text aspect to fontstrings now marks anchoring as being secret" (Beta 1), so `GetStringWidth()`, `GetNumLines()`, `IsTruncated()`, `GetWidth()/GetHeight()` on that FontString return secrets. "Clearing anchor points can reset this state."
- **Clearing**: "Secret aspects presently can only be cleared by calling `FrameScriptObject:SetToDefaults()`", which resets the object "as if it had just been created". On Forever docs `SetToDefaults` is `IsProtectedFunction = true` and blocked by forbidden aspects. [GH-DOC SimpleFrameScriptObjectAPI]
- Inspect: `obj:HasSecretAspect(Enum.SecretAspect.X)`, `obj:HasAnySecretAspect()`, `obj:HasSecretValues()`, `obj:IsPreventingSecretValues()`, `region:IsAnchoringSecret()`. [GH-DOC]

`Enum.SecretAspect` on Forever [GH-DOC SecretAspectConstants, primary, 1.60.1]: `ObjectDebug/ObjectName/ObjectType/ObjectSecrets/ObjectSecurity/Attributes/Hierarchy = 1`, `ID=2`, `Toplevel=4`, `Text=8`, `SecureText=16`, `Shown=32`, `Scale=64`, `Alpha=128`, `FrameLevel=256`, `ScrollRange=512`, `Cursor=1024`, `VertexColor=2048`, `Desaturation=4096`, `TexCoords=8192`, `BarValue=16384`, `Cooldown=32768`, `Rotation=65536`, `MinimumWidth=131072`, `Padding=262144`, `CooldownStyle=524288`, `TooltipTexture=1048576`, `ButtonState=2097152`, `ScrollOffset=4194304`, `RadialProgress=8388608`, `FrameStrata=16777216`.

`FrameStrata` was added in Forever 1.60.1 Beta 4: "`GetFrameStrata` now returns a secret value for frames that have this aspect." [W-1601N, primary]

### 3.2 Setters that accept secrets from addon code

Extracted from Forever docs by filtering for `SecretArguments = "AllowedWhenTainted"` [GH-DOC Simple*API files, primary, 1.60.1]. Aspect applied in brackets.

**StatusBar**
- `SetValue(value [, interpolation])` [BarValue]
- `SetMinMaxValues(min, max [, interpolation])` [BarValue]
- `SetStatusBarColor(r, g, b [, a])` [VertexColor, Alpha]
- `SetStatusBarDesaturated(bool)`, `SetStatusBarDesaturation(0..1)` [Desaturation]
- `SetTimerDuration(durationObject [, interpolation [, direction]])` takes a duration object, not raw secrets (§5.3)
- `interpolation` is `Enum.StatusBarInterpolation` (`Immediate`, `ExponentialEaseOut`); it must not be secret.
- Getters `GetValue`, `GetMinMaxValues`, `GetInterpolatedValue`, `IsInterpolating` return secrets once BarValue is set. "Fixed an exploit where status bars could be used to launder secret numbers." [W-1201N]

**FontString**
- `SetText(text)`, `SetFormattedText(fmt, ...)`, `SetTextToFit(text)` [Text]
- `SetTextColor(r, g, b [, a])` [VertexColor, Alpha]
- `GetText()` returns a secret afterwards.

**Region (Texture, FontString, Line) and Frame**
- `SetAlpha(alpha)` [Alpha] ("always clamps its value to the range [0, 1] without raising an error")
- `SetAlphaFromBoolean(value [, alphaIfTrue = 1 [, alphaIfFalse = 0]])` [Alpha] - the standard way to show/hide on a secret boolean
- `SetVertexColor(r, g, b [, a])`, `SetVertexColorFromBoolean(value, colorIfTrue, colorIfFalse)` [VertexColor, Alpha] (Region only)
- `Frame:SetID(id)` [ID] (protected function)

**TextureBase**
- `SetTexture(asset)` - accepts secret **numbers** (file IDs); "no longer accepts secret strings" [W-1200N Oct 27]
- `SetAtlas(atlas, ...)` (only the atlas argument may be secret)
- `SetColorTexture(r, g, b [, a])`
- `SetDesaturated(bool)`, `SetDesaturation(v)` [Desaturation]
- `SetTexCoord(...)` [TexCoords], `SetSpriteSheetCell(cell, rows, cols, ...)` [TexCoords] ("only accepts secret cell values up to 256")
- `SetRotation(radians [, point])` [Rotation]
- `SetRadialProgressBarPercent(percent)` [RadialProgress] (12.1.0)

**Cooldown**
- Style only: `SetDrawSwipe`, `SetDrawEdge`, `SetDrawBling`, `SetSwipeColor`, `SetEdgeColor` [CooldownStyle]
- Timing: use `SetCooldownFromDurationObject(duration [, clearIfZero = true])`. Since the 2026-03-21 hotfix, tainted code can no longer pass secrets to `SetCooldown`, `SetCooldownFromExpirationTime`, `SetCooldownDuration`, `SetCooldownUNIX`; the duration-object call "going forward, is the only way to configure a cooldown frame with secret values." [W-1201N, primary; confirmed in GH-DOC FrameAPICooldown]
- `SetCooldown` and `Clear` "can no longer be called from tainted code when the cooldown frame itself is protected." [W-1215N]
- `SetCountdownFormatter(formatter)`, `SetCountdownMillisecondsThreshold(seconds)`, `SetCountdownAbbrevThreshold(seconds)`, `SetMinimumCountdownDuration(ms)` control the countdown text. [GH-DOC]
- `CooldownFrameTemplate` "now uses alpha instead of shown state (and has the alpha secret aspect)". [W-1200N Jan 12]

### 3.3 Setters that do NOT accept secrets from addon code (Forever docs)

Marked `AllowedWhenUntainted` [GH-DOC, primary, 1.60.1]:

- `SetShown(secretBool)` on both ScriptRegion and Frame. The October 2025 Blizzard post used `SetShown` as its example of a secret-accepting API, but the current docs do not allow it for tainted callers. Use `SetAlphaFromBoolean`. `Show()`/`Hide()` take no arguments and are fine.
- `SetScale`, `SetFrameLevel`, `SetFrameStrata`, `SetWidth/SetHeight/SetSize/SetPoint` with secret numbers
- `CheckButton:SetChecked` ("no longer accepts secrets from tainted code") [W-1200N Dec 8]
- `SetAttribute` values, `RegisterEvent` names, etc.

If you are unsure about an API: open its entry in `Blizzard_APIDocumentationGenerated` on the `forever` branch and read `SecretArguments`. That file is the authority.

### 3.4 Forbidden aspects and private script objects (12.1.0+)

"Where Secret Aspects obfuscate data, Forbidden Aspects restrict what addons are allowed to do with an object." [W-1210N, primary]. `Enum.ForbiddenAspect`: `SetToDefaults, ScriptBindings, UntrustedScriptExecution, UntrustedLayoutScriptExecution, EventRegistrations, AlwaysPropagateInput, ScriptedInput, QueryFocus, ChangeAnimationTarget, RemoveSecretAspects, ChangeParent`, plus 12.1.5: `SetTexture, QueryRotation, QueryAnimationProgress, AddAnimations`. [W-FA, primary]

- "API calls such as SetParent and SetPoint will error if an object would implicitly gain any Forbidden Aspects that it does not already have." [W-1210N PTR 2]
- Query with `obj:HasAnyForbiddenAspects(mask)`, `obj:HasAccessConstraints()`, `obj:CanBeAccessedInContext()`. [GH-DOC]
- These matter mainly for AuraButtons (§6.3).

## 4. Which APIs return secrets, and when

Restriction states (from the predicate descriptions) [GH-DOC SecretPredicatesDocumentation, primary, 1.60.1; W-SV]:

- **Combat**: "The player is actively affecting combat." Applies anywhere, including the open world.
- **Encounter**: in an instance encounter. **ChallengeMode**: active keystone run. **PvPMatch**: active PvP match.
- **Map**: "on a map that applies addon restrictions" such as a dungeon or raid.
- **Chat** ("chat messaging lockdown"): "when encounter, challenge mode, or PvP match addon restrictions are in effect, and when the player is on a communication-restricted map such as a dungeon or raid."

Which Forever maps are flagged as restricted, and whether Forever has anything that triggers ChallengeMode, is **not confirmed** by any source read.

### 4.1 Health and power

[GH-DOC UnitDocumentation, primary, 1.60.1]

| API | Secrecy marker | Meaning |
|---|---|---|
| `UnitHealth(unit [, usePredicted = true])` | `SecretReturns = true` | Documented as unconditionally secret (wiki: "Functions that unconditionally return secret values are marked as SecretReturns = true"). No `C_Secrets` predicate exists for it. Whether this truly holds for `"player"` out of combat on Forever is **unverified**; always code as if it is secret. |
| `UnitHealthMissing(unit [, usePredicted])` | `SecretReturns` | max - current |
| `UnitHealthPercent(unit [, usePredicted [, curve]])` | `SecretReturns`, `SecretWhenCurveSecret` | 0..1, or the curve's output |
| `UnitHealthMax(unit)` | `SecretWhenUnitHealthMaxRestricted` | "secret values when the unit isn't player-controlled" |
| `UnitPower(unit [, type [, unmodified]])`, `UnitPowerMissing`, `UnitPowerPercent(unit [, type [, unmodified [, curve]]])` | `SecretWhenUnitPowerRestricted` | secret "for power types not explicitly flagged as being never secret". On retail, secondary resources (combo points, runes, soul shards, holy power, chi, arcane charges, essence) were declassified; primary resources stay secret. [W-1200N Dec 1] |
| `UnitPowerMax` | `SecretWhenUnitPowerMaxRestricted` | secret for non-player-controlled units; "will now return a non-secret 0 value if the unit doesn't use the power type" |
| `UnitHasPowerType(unit, powerType)` | never secret | 12.0.5 |
| `UnitStagger(unit)` | conditional | non-secret for the player |
| `UnitGetIncomingHeals`, `UnitGetTotalAbsorbs` | `SecretReturns` | use the heal prediction calculator (§5.5) |
| `UnitInRange(unit)` | `SecretReturns` | |
| `UnitThreatSituation`, `UnitDetailedThreatSituation` | conditional on the token pair | [W-1201N] |
| Player stat APIs | secret "if auras are secret" | [W-1205N] |

Not marked secret in the Forever docs: `UnitExists`, `UnitIsDead`, `UnitIsDeadOrGhost`, `UnitIsConnected`, `UnitIsPlayer`, `UnitCanAttack`, `UnitIsEnemy`, `UnitReaction`, `UnitClassification`, `UnitLevel`, `UnitAffectingCombat`, `UnitIsTapDenied`, `UnitSelectionColor`. Many take plain `UnitToken`; health/power/aura APIs take restricted token types (§4.3).

### 4.2 Unit identity (names, GUIDs, creature IDs, class)

- Rule since 12.0.5 hotfix: "identities are secret while on instanced maps for any unit that isn't the player, their pet/vehicle, or a raid/party member." [W-1205N Apr 10, primary]. Predicate text: secret "when the unit isn't player-controlled or in the party/raid. For compound tokens (eg. 'boss1target'), results are secret if any unit in the chain fails this." [GH-DOC]. This is map-based, not combat-based ("no longer affected by combat state", Alpha 6).
- `UnitName(unit)` - `SecretWhenUnitNameIdentityRestricted`; "no longer accepts secret unit tokens" (12.0.5); "will no longer return secrets while in an active PvP match" (12.1.0).
- `UnitFullName`, `UnitNameUnmodified`, `UnitNameFromGUID(guid)`, `UnitGUID(unit)`, `UnitTokenFromGUID(guid)` - `SecretWhenUnitIdentityRestricted`.
- `UnitCreatureID(unit)` "now returns nil when unit identity is secret." [W-1201N]
- `UnitTokenFromGUID` "no longer return arena, nameplate, boss, party, raid, or target-of-target unit tokens when unit identities are secret." [W-1205N]
- 12.1.0: these return secrets when identity is secret: `UnitClass` (first return documented `ConditionalSecret`), `UnitClassBase`, `UnitIsOwnerOrControllerOfUnit`, `UnitSex`, `UnitSexBase`, `UnitPhaseReason`, `UnitGroupRolesAssigned`, `UnitGroupRolesAssignedEnum`, `UnitIsRaidOfficer`, `UnitInRaid`, `UnitIsPVP`, `UnitRace`, `UnitIsGroupLeader`, `UnitIsGroupAssistant`, `UnitLeadsAnyGroup`, `UnitGetAvailableRoles`, `GetInspectSpecialization`. `UnitIsCharmed`/`UnitIsPossessed` are secret when auras are secret (except player/pet/vehicle). `GetGuildInfo` no longer accepts compound tokens. [W-1210N PTR 7/8, primary]
- `UnitFrameUtil` (12.1.5, shared code, present on the forever branch at `Blizzard_UnitFrame/Shared/UnitFrameUtil.lua`) gives secret-safe display helpers: `UpdateUnitPvPIndicator`, `GetUnitRoleIconDisplayInfo`, `UpdateUnitFrameRoleIcon`, arena spec helpers. [W-1215N; GH-TREE]
- `C_ClassColor.GetClassColor(class)` accepts a secret class token (oUF does this when `issecretvalue(class)`). [OUF elements/health.lua]
- `SetPortraitTexture`/`PlayerModel:SetUnit` "no longer accept unit tokens for units which have secret identity" (return nil). [W-1205N]
- **Forever-specific, Beta 5**: "The server ID and spawn ID portions of creature, vehicle, pet and game object GUIDs have been replaced with obfuscated values to prevent comparison to determine layer. They remain stable and unique within your own session, and the GUID string format is otherwise unchanged." [W-1601N, primary]. Do not persist NPC GUIDs across sessions or share them between clients.
- Questie on this client guards NPC GUIDs, chat text, tooltip data and map x/y with `issecretvalue`. [QST]

### 4.3 Unit comparison and restricted unit tokens

- `UnitIsUnit(a, b)` rules (12.0.5 PTR 4) [W-1205N, primary]:
  - Permitted if either unit is one of `"player", "pet", "vehicle", "mouseover", "target", "softenemy", "softfriend", "softinteract", "focus", "none", "npc", "questnpc"`.
  - Permitted if either is a party/raid token (or its pet) and the other is not a compound token, a nameplate token, or `"targettarget"/"focustarget"`.
  - "All other comparisons are disallowed and return nil."
  - Docs: `RequiresComparableUnitTokens` (failure: returns nothing) and `SecretWhenUnitComparisonRestricted` ("only applies when the player is on an addon-restricted map"). Pre-check with `C_Secrets.CanCompareUnitTokens(a, b)`. ElvUI wraps exactly that. [EUI oUF/init.lua]
- Token types in the docs: `UnitTokenPvPRestrictedForAddOns` (health/power/cast APIs), `UnitTokenRestrictedForAddOns` (aura APIs; "doesn't accept compound unit tokens (boss1target) or player/pet names from addons. The 'targettarget' token is exempt"), `UnitTokenNamePlate` (nameplate APIs; no party/raid/target-of-target tokens). Since 12.0.7 unsupported tokens return nil/defaults instead of erroring. [W-1200N Jan 21; W-1205N; W-1207N]
- Castbar IDs are unique per unit token and **token casing matters** (`"PLAYER"` vs `"player"`); events use lowercase. [W-1215N]

### 4.4 Spell casts

- `UnitCastingInfo(unit)`, `UnitChannelInfo(unit)`: `SecretWhenUnitSpellCastRestricted` - secret "if the unit being queried for cast information is not the player or their pet. Individual spells may be flagged as never or always secret". Always non-secret fields: `isTradeskill`, `castBarID`, `delayTimeMs`, `isEmpowered`, `numEmpowerStages`. [GH-DOC Unit]
- `UnitCastingDuration(unit)`, `UnitChannelDuration(unit)`, `UnitEmpoweredChannelDuration(unit [, includeHoldAtMaxTime])` return duration objects for cast bars.
- `castBarID` "is incremented on each new spellcast, and is never secret. It can be used to identify and compare casts." [W-1200N Dec 22]
- Player's own casts (and player-controlled units) are not secret, "even in combat". [W-1200N Nov 4]
- `UNIT_SPELLCAST_SENT` sends the target name as a secret. Secret instant casts no longer fire `UNIT_SPELLCAST_SUCCEEDED` for non-player units. [W-1200N Dec 1; W-1205N Apr 10]
- `UnitSpellTargetName(unit)` (secret; only for player units), `UnitShouldDisplaySpellTargetName(unit)`.
- "APIs no longer accept secret spell names from addons". [W-1201N Feb 19]

### 4.5 Cooldowns

- Secret "when combat, encounter, challenge mode, or PvP match addon restrictions are in effect. Individual spells may be flagged as never or always secret". [GH-DOC `SecretWhenCooldownsRestricted`]
- `C_Spell.GetSpellCooldown(spell) -> SpellCooldownInfo { startTime, duration, isEnabled*, isActive*, modRate, activeCategory?, timeUntilEndOfStartRecovery?, isOnGCD* }`; `*` = `NeverSecret`. [GH-DOC SpellShared, primary, 1.60.1]
- `C_Spell.GetSpellCharges(spell) -> SpellChargeInfo { currentCharges, maxCharges*, cooldownStartTime, cooldownDuration, chargeModRate, isActive* }`
- `C_Spell.GetSpellLossOfControlCooldownInfo(spell) -> { startTime, duration, modRate, isActive*, shouldReplaceNormalCooldown* }`
- Duration-object variants (never need arithmetic): `C_Spell.GetSpellCooldownDuration(spell [, ignoreGCD])`, `C_Spell.GetSpellChargeDuration(spell)`, `C_Spell.GetSpellLossOfControlCooldownDuration(spell)`; `C_ActionBar.GetActionCooldownDuration(actionID [, ignoreGCD])`, `GetActionChargeDuration`, `GetActionLossOfControlCooldownDuration`; `C_SpellBook.GetSpellBookItemCooldownDuration(...)` etc. They "return a zero-span object if the isActive boolean evaluates to false". [W-1201N Mar 21; W-DUR]
- `isActive` definition: regular = `isEnabled and startTime > 0 and duration > 0`; charges = `maxCharges > 1 and currentCharges < maxCharges and startTime > 0 and duration > 0`. [W-1201N]
- Counts: `C_Spell.GetSpellDisplayCount(spell [, maxDisplayCount = 9999 [, replacementString = "*"]]) -> string`, `C_ActionBar.GetActionDisplayCount`.
- `C_Spell.GetItemCooldown(itemID) -> SpellCooldownInfo` is new in 1.60.1. [W-1601]
- Never-secret cooldown whitelist on retail includes the GCD dummy spell 61304, combat res, Hearthstone, skyriding. [W-1200N; W-1201N]. On Forever oUF uses spell **1283885** as the Global Cooldown spell instead of 61304 [OUF elements/castbar.lua]. The Forever whitelist itself is **not documented** anywhere read; query `C_Secrets.GetSpellCooldownSecrecy(spellID)`.
- `ActionButton_ApplyCooldown` no longer goes through a secure delegate (passing secrets to it errors). [W-1201N]

### 4.6 Auras (the most restricted area, changed again in 12.1.0)

State on Forever docs [GH-DOC UnitAuraDocumentation, primary, 1.60.1] and Blizzard 12.1.0 posts [W-1210N, primary]:

- "when auras are secret (during combat, encounters, M+, and PvP matches), all of the UnitAura APIs will now either return full secrets or nil when called by addons."
- "`C_UnitAuras` and `C_TooltipInfo` APIs that provide access to aura data via index, slot, or instance ID will Lua error when called by addons while auras are secret." In the docs these carry `RequiresUnitAuraAccess = true` (failure mode: Error): `GetAuraDataByIndex`, `GetBuffDataByIndex`, `GetDebuffDataByIndex`, `GetAuraDataBySlot`, `GetAuraDataByAuraInstanceID`, `GetAuraSlots`, `GetUnitAuras`, `GetUnitAuraInstanceIDs`, `GetAuraDuration`, `GetAuraApplicationDisplayCount`, `GetAuraDispelTypeColor`, `DoesAuraHaveExpirationTime`, `IsAuraFilteredOutByInstanceID`, `CancelAuraByInstanceID`.
- "C_UnitAura APIs that provide access to aura data via spell ID or spell name can still be called by addons as before (non-secret spells still return non-secrets)": `C_UnitAuras.GetPlayerAuraBySpellID(spellID)`, `GetUnitAuraBySpellID(unit, spellID)`, `GetAuraDataBySpellName(unit, name [, filter])`. They carry `RequiresNonSecretAura` ("protected APIs will return no values" for a secret aura). So nil means "absent **or** secret".
- `UNIT_AURA(unitTarget, updateInfo)` is `SecretWhenAurasRestricted`: "now delivers a fully secret payload while auras are secret. AuraData structs are now always fully secret."
- Aura instance IDs are not unique across units and are re-randomized on entering an encounter/M+/PvP match. [W-1200N Jan 12; W-1205N]
- "`SecureAuraHeaderTemplate` has been removed from Mainline (it will still exist for Classic). Addons ... should migrate over to using AuraContainers." [W-1210N PTR 4]. Whether the template exists on Forever was **not checked**.
- Out of combat (no restriction active) aura data is readable as before.
- Questie's guard on this client: `if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then ... end`. [QST QuestieCompat.lua]
- Aura sounds without reading auras: `C_UnitAuras.AddAuraSound(trigger, soundInfo) -> auraSoundID`, `RemoveAuraSound(id)` (renamed from `AddPrivateAuraAppliedSound`; sound limited to 5 s; restricted in some states). [W-1210N; W-1215N]
- Other secret-aware helpers accepting secret spell identifiers from addons: `C_UnitAuras.AuraIsPrivate(spellID)`, `AuraIsBigDefensive(spellID)`, `GetAuraBaseDuration`, `GetRefreshExtendedDuration`, `GetRefreshCarryOverDuration` (new in the 1.60.1 added list), `GetAuraCasterGUID`. [GH-DOC; W-1601]

The supported way to *display* auras in restricted states is AuraContainer (§6.3). Blizzard confirmed: "The AuraContainer/AuraButton changes introduced in 12.1.0 will be available as well" in Forever. [W-1601N]

### 4.7 Combat log

- "Combat Log Events are no longer available to addons, and messages in the Combat Log chat tab have been converted to KStrings to prevent addons from parsing the information inside them." [W-1200N Oct 1, primary]
- "COMBAT_LOG_EVENT and COMBAT_LOG_EVENT_UNFILTERED will error when trying to register them." [W-1200, primary, 12.0.0]. Forever docs list both with `HasRestrictions = true`. [GH-DOC CombatLog]
- `CombatLogGetCurrentEventInfo`: the forever-branch deprecation shim does `CombatLogGetCurrentEventInfo = C_CombatLog.GetCurrentEventInfo`, but the documented `C_CombatLog` namespace has no such function for addons (it lives in `C_CombatLogSecure`, environment `SecureOnly`). Expect `nil`. The shim only loads when CVar `loadDeprecationFallbacks` is set. [GH-DCL; GH-DOC]
- `C_CombatLog.IsCombatLogRestricted() -> bool` exists. [GH-DOC]
- BigWigs treats Forever the same as retail: `isModern = isRetail or isForever`, and `boss:Log(...)` (its CLEU registration) is `if isModern then return end`. [BW Loader.lua, Core/BossPrototype.lua, primary source code]
- Replacement events, both `SecretWhenUnitIdentityRestricted` in the Forever docs: `UNIT_DIED(unitGUID)` (Blizzard's Dec 2025 post called it `UNIT_DEATH`; the generated docs name it `UNIT_DIED`) and `PARTY_KILL(attackerGUID, targetGUID)`. `ENCOUNTER_END` carries a non-secret list of `{creatureID, creatureName, remainingHealthPercent}` (12.0.7). [W-1200N Dec 10/16; W-1207N]
- `C_CombatText.GetCurrentEventInfo()` is `SecretReturns`. [GH-DOC]
- On Classic clients the combat log works as before, which is why addons still ship CLEU code. Do not copy that code path for Forever.

### 4.8 Addon comms and chat

- `C_ChatInfo.SendAddonMessage(prefix, message [, chatType [, target]]) -> Enum.SendAddonMessageResult`; `SecretArguments = "NotAllowed"` (never accepts secrets, even from Blizzard code). Result enum: `Success=0, InvalidPrefix=1, InvalidMessage=2, AddonMessageThrottle=3, InvalidChatType=4, NotInGroup=5, TargetRequired=6, InvalidChannel=7, ChannelThrottle=8, GeneralError=9, NotInGuild=10, AddOnMessageLockdown=11, TargetOffline=12`. [GH-DOC ChatInfo/ChatConstants, primary, 1.60.1]
- When blocked: originally "While in an instance ... addons are not allowed to send communications to other players (either through addon comms or regular chat)", relaxed in Alpha 3 to apply only when a keystone run is active, a PvP match is active, or "An instance encounter is in progress." [W-1200N Oct 1 and Oct 11, primary]. The current predicate text for chat lockdown also mentions "a communication-restricted map" (§4). Always check `C_ChatInfo.InChatMessagingLockdown()` and the return value.
- **Forever-specific**: "Trial accounts can no longer send addon messages." "`SendChatMessage` with the "EMOTE" chat type now requires a hardware event when called from addon code outside of instances, matching the existing restriction on "SAY" and "YELL"." [W-1601N Beta 4, primary]
- Incoming chat: `CHAT_MSG_SAY/YELL/EMOTE/PARTY/RAID/GUILD/WHISPER/CHANNEL/SYSTEM/MONSTER_YELL/RAID_BOSS_EMOTE` are `SecretInChatMessagingLockdown`; in those events `text`, `playerName`, `playerName2`, `guid`, `bnSenderID` can be secret while `languageName`, `channelName`, `lineID`, etc. are `NeverSecret`. `CHAT_MSG_LOOT` has no secrecy marker; "Chat events for currency, honor, loot, money, reputation, and XP gains are no longer secret." [GH-DOC; W-1207N]
- `CHAT_MSG_ADDON` has no secrecy marker in the docs (you simply do not receive what others cannot send).
- Side channels were closed: `UnitIsAFK/UnitIsDND` secret in lockdown, `READY_CHECK`, `START_PLAYER_COUNTDOWN`, `GUILD_MOTD` payloads secret, LFG list info, club notes, calendar events, minimap pings (`PingLocation` not accessible to addons); raid-management calls (`DoReadyCheck`, `DoCountdown`, `PromoteToAssistant`, `SetLootMethod`, ...) blocked for addons in chat lockdown. [W-1200N Jan 21; W-1205N]
- Secret-string helpers for chat addons: `C_StringUtil.RemoveContiguousSpaces`, `EscapeLuaPatterns`, `EscapeLuaFormatString`, `EscapeQuotedCodes`, `StripHyperlinks`, `Ambiguate` (accepts secrets since 12.0.5). [W-1200N; W-1205N; GH-DOC StringUtil]
- AceComm/ChatThrottleLib as shipped with Questie on this client bails out on secret text/destination. [QST Libs/AceComm-3.0/ChatThrottleLib.lua]

### 4.9 Nameplates

- `C_NamePlate.GetNamePlateForUnit(unitToken [, includeForbidden])` takes `UnitTokenNamePlate`; "no longer accepts compound unit tokens (e.g. boss1target) from tainted code". [GH-DOC; W-1200N Jan 12]
- Hit rectangle control: `nameplate:SetHitTestPoints(anchors)`, `SetAllHitTestPoints(region)`, `ClearAllHitTestPoints()`, `GetHitTestPoints()`, `CanChangeHitTestPoints()`. "Updates are normally blocked for tainted code during combat, except on the tick a unit is first assigned"; 12.1.5 adds one extra frame after `UNIT_CLASSIFICATION_CHANGED`. Failure mode is a Lua error. [GH-DOC FrameAPINamePlate; W-1215N]
- Blizzard goal: addons must not be able to rename enemies/casts or color nameplates by priority; "APIs that allow addons to identify specific enemies and enemy spellcasts are the primary ones that need to be locked down". [W-1200N Nov 13]
- **Forever-specific** CVars: `nameplateMaxVerticalDistance`, `nameplateMaxVerticalDistanceAtMaxRange` (0 disables). Restored: `nameplateMotionSpeed`, `nameplateBottomInset`, `nameplateTopInset`. [W-1601N; W-1215N]
- Private auras "aren't supported in nameplates". [W-1205N]

### 4.10 Other

- Player position / minimap: "Fixed a further issue that allowed addons to access minimap rotation values during encounters." [W-1601N]. Questie guards map x/y with `issecretvalue`. [QST]
- Tooltips: all `GameTooltip:Set*` are secure delegates (safe to call); use `GameTooltip_AddMoneyLine` instead of `SetTooltipMoney`; tooltip data lines can contain secrets. [W-1200N Dec 10; W-1207N]
- `C_VoiceChat.SpeakText` accepts secrets (text to speech). [W-1200N Oct 17]
- `|T` texture markup in secret strings cannot reference addon (loose) texture files. [W-1200N Jan 12/27]
- Damage meter and encounter data: see §6.

## 5. Transforming secrets without reading them

### 5.1 Curves

[GH-DOC CurveUtil, LuaCurveObjectAPI, LuaColorCurveObjectAPI; W-CC; primary]

```lua
local curve = C_CurveUtil.CreateColorCurve()
curve:SetType(Enum.LuaCurveType.Step)          -- Linear=0 (default), Step=1, Cosine=2, Cubic=3
curve:AddPoint(0.0, CreateColor(1, 0, 0, 1))   -- x is 0..1, y is a ColorMixin
curve:AddPoint(0.3, CreateColor(1, 1, 0, 1))
curve:AddPoint(0.7, CreateColor(0, 1, 0, 1))

local color = UnitHealthPercent("target", true, curve)     -- ColorMixin with secret fields
bar:GetStatusBarTexture():SetVertexColor(color:GetRGB())
```

- `C_CurveUtil.CreateCurve() -> Curve` (numeric y), `C_CurveUtil.CreateColorCurve() -> ColorCurve`. "Curves support a maximum of 256 points."
- Methods: `AddPoint(x, y)`, `SetPoints(points)`, `ClearPoints()`, `RemovePoint(i)`, `GetPoint(i)`, `GetPoints()`, `GetPointCount()`, `SetType(type)`, `GetType()`, `Copy()`, `Evaluate(x)`, `EvaluateUnpacked(x)` (color curve), `HasSecretValues()`, `SetToDefaults()`.
- **Caution**: in the Forever docs `curve:Evaluate(x)` is `SecretArguments = "AllowedWhenUntainted"` (same on the live 12.1.5 branch). Addon code should not call `curve:Evaluate(secret)` directly; pass the curve *into* an API that does the evaluation natively.
- APIs that take a curve: `UnitHealthPercent`, `UnitPowerPercent`, `DurationObject:EvaluateElapsedPercent/RemainingPercent/ElapsedDuration/RemainingDuration/TotalDuration`, `UnitHealPredictionCalculator:EvaluateCurrentHealthPercent/EvaluateMissingHealthPercent`, `C_UnitAuras.GetAuraDispelTypeColor(unit, auraInstanceID, colorCurve)`. A numeric curve returns a number, a color curve returns a color.
- Predefined numeric curves in `CurveConstants` [GH-CURVE, primary, forever branch]: `CurveConstants.ZeroToOne`, `ScaleTo100`, `Reverse`, `ReverseTo100`.

```lua
-- percent text without arithmetic (pattern used by oUF tags)
fs:SetText(string.format("%d", UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)))
```

### 5.2 Booleans

- `region:SetAlphaFromBoolean(secretBool [, alphaIfTrue [, alphaIfFalse]])`
- `region:SetVertexColorFromBoolean(secretBool, colorIfTrue, colorIfFalse)`
- `C_CurveUtil.EvaluateColorFromBoolean(bool, colorIfTrue, colorIfFalse) -> color`
- `C_CurveUtil.EvaluateColorValueFromBoolean(bool, valueIfTrue, valueIfFalse) -> number` (a single color component such as alpha)

All four are `AllowedWhenTainted`. [GH-DOC, primary, 1.60.1]

```lua
shield:SetAlphaFromBoolean(notInterruptible, 1, 0)   -- oUF castbar shield
```

### 5.3 Duration objects

[GH-DOC DurationUtil, LuaDurationObjectAPI; W-DUR; W-1200N Dec 10; primary]

- `C_DurationUtil.CreateDuration() -> Duration` (zero span). Configure with `SetTimeSpan(start, end)`, `SetTimeFromStart(start, duration [, modRate])`, `SetTimeFromEnd(end, duration [, modRate])`. "These three APIs do not accept secret values from tainted callers" - so for secret timings you must obtain the object from a Blizzard API (list in §4.4/4.5, plus `GetTotemDuration(slot)`, `C_LossOfControl.GetActiveLossOfControlDuration(unit, index)`, `C_EncounterTimeline.GetEventTimer(eventID)`).
- Read-outs (secret when the object holds secrets): `GetRemainingDuration()`, `GetElapsedDuration()`, `GetTotalDuration()`, `GetRemainingPercent()`, `GetElapsedPercent()`, `GetStartTime()`, `GetEndTime()`, `HasExpired()`, `HasStarted()`, `IsActive()`; `IsZero()`, `HasSecretValues()`, `GetModRate()` have no secret marker. Optional `modifier`: `Enum.DurationTimeModifier.RealTime=0 | BaseTime=1`.
- "Duration objects that measure a zero-span are now considered fully elapsed." [W-1205N]
- Consumers: `StatusBar:SetTimerDuration(duration [, interpolation [, direction]])` (`Enum.StatusBarTimerDirection.ElapsedTime | RemainingTime`), `Cooldown:SetCooldownFromDurationObject(duration [, clearIfZero])`, `duration:FormatRemainingDuration(formatter)`, `DurationTextBinding`.

```lua
-- cast bar (after oUF castbar.lua)
local duration = UnitCastingDuration(unit) or UnitChannelDuration(unit)
if duration then
    bar:SetTimerDuration(duration, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.ElapsedTime)
end

-- cooldown swipe
cd:SetCooldownFromDurationObject(C_Spell.GetSpellCooldownDuration(spellID))
```

Self-updating countdown text (12.0.7) [W-1207N, primary]:

```lua
local fmt = C_StringUtil.CreateSecondsFormatter()
fmt:SetDefaultAbbreviation(Enum.SecondsFormatterAbbreviation.OneLetter)
fmt:SetMillisecondsThreshold(5)

local binding = C_DurationUtil.CreateDurationTextBinding()
binding:SetFontString(myFontString)
binding:SetDuration(duration)
binding:SetFormatter(fmt)
binding:SetExpiredText("")
binding:SetZeroDurationText("")
binding:SetEnabled(true)
```

### 5.4 Number and string formatting

- `AbbreviateNumbers(n)`, `AbbreviateLargeNumbers(n)`: native, "callable with secrets by tainted code (returned strings inherit secret state)". Breakpoints "can now only be powers of 10". [W-1200N Nov 4, Jan 12]
- Formatter objects (12.0.5): `C_StringUtil.CreateAbbreviatedNumberFormatter()`, `CreateNumericRuleFormatter()`, `CreateSecondsFormatter()`. "These types can be supplied with secret numbers through the Format functions on duration objects." Note `formatter:FormatNumber(n)` itself is documented `AllowedWhenUntainted`. [W-1205N; GH-DOC]
- `C_StringUtil.TruncateWhenZero(number) -> string` (empty string when 0), `C_StringUtil.WrapString(infix [, prefix [, suffix]])` (empty if infix empty), `RoundToNearestString`, `FloorToNearestString`. [W-1200N Dec 1; GH-DOC]
- Color: `WrapTextInColorCode(text, hex)`, `C_ColorUtil.WrapTextInColor(text, color)`, `C_ColorUtil.GenerateTextColorCode(color)` accept secrets. The HSV/RGB conversion functions do not. [GH-DOC ColorUtil]
- Display counts returned as ready-made strings: `C_UnitAuras.GetAuraApplicationDisplayCount`, `C_Spell.GetSpellDisplayCount`, `C_ActionBar.GetActionDisplayCount`.
- `string.format("%d", secretNumber)` and `..` work; width/precision on secret `%s` is ignored.

```lua
-- "missing health, blank when full" with no comparison
fs:SetText(C_StringUtil.TruncateWhenZero(UnitHealthMissing(unit)))
```

### 5.5 Heal prediction calculator

[W-1200N Dec 16, Jan 12, Jan 27; GH-DOC UnitHealPredictionCalculatorAPI; OUF elements/health.lua]

```lua
local calc = CreateUnitHealPredictionCalculator()         -- once per frame
UnitGetDetailedHealPrediction(unit, "player", calc)        -- fills calc

local max = calc:GetMaximumHealth()
bar:SetMinMaxValues(0, max)
bar:SetValue(calc:GetCurrentHealth())

local allHeal, playerHeal, otherHeal, healClamped = calc:GetIncomingHeals()
healBar:SetMinMaxValues(0, max); healBar:SetValue(allHeal)
overHealGlow:SetAlphaFromBoolean(healClamped, 1, 0)

local absorb, absorbClamped = calc:GetDamageAbsorbs()
local healAbsorb, healAbsorbClamped = calc:GetHealAbsorbs()
local color = calc:EvaluateCurrentHealthPercent(colorCurve)
```

Other methods: `GetMissingHealth`, `GetCurrentHealthPercent`, `GetMissingHealthPercent`, `GetTotalIncomingHeals`, `GetTotalDamageAbsorbs`, `GetTotalHealAbsorbs`, `GetMaximum*`, `SetMaximumHealthMode(Enum.UnitMaximumHealthMode)`, clamp-mode setters, `ResetPredictedValues()`.

### 5.6 `C_Intl` (12.1.5) and the claim in the task brief

- Blizzard, 12.1.5 PTR 2 (2026-09-16): "C_Intl functions now accept **secret string arguments from tainted code**. The `C_Intl.Transliterate` API does not allow `Null` or `Remove` transliterators for secret text from tainted code." [W-1215N, primary]
- Forever docs agree: 25 of 26 `C_Intl` functions are `SecretArguments = "AllowedWhenTainted"` at branch head (71091); only `CreateLocaleContext` is `AllowedWhenUntainted`. The file last changed at build 70009; at the earlier build 69876 all 26 were `AllowedWhenUntainted`. [GH-DOC IntlDocumentation.lua history, primary]
- **I could not find any 1.60.1 note saying C_Intl functions "no longer accept" secrets from tainted code.** The Forever notes on the wiki (2026-09-15, 10-08, 10-16) do not mention C_Intl, and the generated docs show the opposite direction of change. Treat that claim as unconfirmed and probably inverted.

## 6. Blizzard-provided replacements

### 6.1 Damage meter (`C_DamageMeter`) - loads on Forever

`Blizzard_DamageMeter.toc` has `## AllowLoadGameType: standard, camelot`, with a Camelot override file. [GH-TOC, primary, forever branch]

API [GH-DOC DamageMeterDocumentation + Constants, primary, 1.60.1]:

- `C_DamageMeter.IsDamageMeterAvailable() -> isAvailable, failureReason`
- `GetAvailableCombatSessions() -> { {sessionID, name, durationSeconds?}, ... }`
- `GetCombatSessionFromID(sessionID, type)` / `GetCombatSessionFromType(sessionType, type) -> DamageMeterCombatSession { combatSources, maxAmount, totalAmount, durationSeconds? }` - `SecretWhenInCombat`
- `GetCombatSessionSourceFromID(sessionID, type [, sourceGUID [, sourceCreatureID]])` / `...FromType(...) -> { combatSpells, maxAmount, totalAmount }` - `SecretWhenInCombat`
- `GetSessionDurationSeconds(sessionType)`, `ResetAllCombatSessions()`
- Events: `DAMAGE_METER_COMBAT_SESSION_UPDATED(type, sessionID)`, `DAMAGE_METER_CURRENT_SESSION_UPDATED`, `DAMAGE_METER_RESET`
- `Enum.DamageMeterType`: `DamageDone=0, Dps=1, HealingDone=2, Hps=3, Absorbs=4, Interrupts=5, Dispels=6, DamageTaken=7, AvoidableDamageTaken=8, Deaths=9, EnemyDamageTaken=10`
- `Enum.DamageMeterSessionType`: `Overall=0, Current=1, Expired=2`
- `DamageMeterCombatSource` fields: `sourceGUID` (conditional secret), `name` (conditional secret), `classFilename*`, `specIconID` (secret), `totalAmount`, `amountPerSecond`, `isLocalPlayer*`, `deathRecapID*`, `deathTimeSeconds`, `classification*`, `sourceDisplayType`, `factionGroup`; `*` = never secret.

Consequence: a custom meter can render Blizzard's numbers live (secret values into bars/text) and can do math on them only after combat ends.

### 6.2 Boss timeline / warnings - API present, UI addons NOT loaded on Forever

- `Blizzard_EncounterTimeline.toc` and `Blizzard_EncounterWarnings.toc` both say `## AllowLoadGameType: standard` on the forever branch, i.e. they do not load for `camelot`. [GH-TOC, primary, build 71091]. Whether the underlying C APIs do anything on Forever is **unconfirmed**; call `C_EncounterTimeline.IsFeatureAvailable()` / `C_EncounterWarnings.IsFeatureAvailable()` and feature-detect.
- API as documented [GH-DOC, primary]:
  - `C_EncounterTimeline`: `GetEventList()`, `GetSortedEventList(...)`, `GetEventInfo(eventID)`, `GetEventState`, `GetEventTimeRemaining`, `GetEventTimer(eventID) -> Duration`, `GetEventColor`, `GetTrackList`, `SetEventIconTextures(eventID, mask, textures)`, `AddScriptEvent(request) -> eventID`, `CancelScriptEvent`, `PauseScriptEvent`, `ResumeScriptEvent`, `FinishScriptEvent`, `IsFeatureAvailable`, `IsFeatureEnabled`. Events `ENCOUNTER_TIMELINE_EVENT_ADDED(eventInfo)` (`SecretWhenEncounterEvent`), `..._STATE_CHANGED`, `..._REMOVED`, `..._HIGHLIGHT`, etc. Most take `SecretArguments = "NotAllowed"`.
  - `C_EncounterWarnings`: event `ENCOUNTER_WARNING(info)` where `text, casterGUID, casterName, targetGUID, targetName, iconFileID, tooltipSpellID, isDeadly, color` are secret and `duration, severity, shouldPlaySound, shouldShowChatMessage, shouldShowWarning` are not; `PlaySound(severity)`, `GetColorForSeverity`, `SetWarningsShown(bool)`.
  - `C_EncounterEvents`: `GetEventList()`, `GetEventInfo(id)`, `SetEventColor(id, trigger, color)`, `SetEventSound(id, trigger, soundInfo)`, `PlayEventSound`.
- BigWigs consumes these on retail (`Plugins/Timeline.lua`, `Plugins/Messages.lua`), passing the secret `text`/`targetName` straight to display. [BW]
- BigWigs ships a separate `BigWigs_Forever` / `LittleWigs_Forever` content pack and an `Init_Camelot.lua`. [BW Loader.lua]

### 6.3 AuraContainer / AuraButton (12.1.0) - the way to show auras in combat

[W-1210N PTR 1-8, W-1215N, primary; OUF elements/auras.lua for a working Forever consumer]

```lua
local container = CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")
container:SetPoint("TOP", parent, "BOTTOM")
container:SetUnit("target")
container:AddAuraGroup("buffs", "HELPFUL", {
    maxFrameCount = 8,
    sortMethod = AuraContainerSortMethod.ExpirationOnly,
    sortDirection = AuraContainerSortDirection.Normal,
    initializeFrame = function(auraButton)
        -- create icon/duration/count regions here and bind them:
        -- auraButton:SetIcon(tex); auraButton:SetDurationText(fs); auraButton:SetAuraBorder(tex, opts)
    end,
    candidateFilters = { isFromPlayerOrPlayerPet = true },   -- optional
})
```

Rules that matter:

- Addons do not create AuraButtons; the container does (`AddAuraFrame` was removed in PTR 4). Configure buttons only inside `initializeFrame` or during UI load before `PLAYER_LOGIN`.
- "AuraButtons are now forbidden (meaning APIs called on them via tainted code will Lua error) **whenever auras are secret**. This forbidden state is not applied until after the `initializeFrame` callback has been called, and AuraButtons return to a non-forbidden state when auras become non-secret again".
- AuraButtons carry forbidden aspects: no addon script handlers run on them, no event registration on containers, no reparenting; `IsShown` returns secrets; containers with groups do not fire `OnSizeChanged`.
- API surface: `AddAuraGroup(groupKey, filterString, options)`, `AddAuraSlot(slotKey, filterString, options)` (single aura, manually anchorable), `AddItemEnchantment(slot, options)`, `SetAuraGroupLayout`, `SetAuraGroupFilterString`, `GetAuraGroupFrame`, `SetAuraGroupEnabled`, `SetAuraSlotEnabled`, `SetEditModePreviewEnabled`, `SetAuraProcessingPolicy`; on buttons `SetIcon`, `SetDurationText`, `SetApplicationCount`, `SetApplicationBar`, `SetAuraBorder`, `SetAuraSymbol`, `AddDispelTypeTexture`, `AddPandemicRegion`, `SetCasterName`, `SetCancelAuraButtons`, animation hooks (`AddPandemicActiveAnimation`, `AddAuraShownAnimation`, `AddAuraAssignedAnimation`).
- Filter strings are the usual aura filters plus `CROWD_CONTROL`, `BIG_DEFENSIVE`, `RAID_PLAYER_DISPELLABLE`, `RAID_IN_COMBAT`, `DISPELLABLE`, `IMPORTANT`, and `!` negation (e.g. `!PLAYER`).
- "Aura containers can now be created by addons during combat" (PTR 7).
- Source lives in `Interface/AddOns/Blizzard_AuraContainer/` on the forever branch; read `Blizzard_CustomAuraContainer.lua` / `Blizzard_CustomAuraButton.lua` for the option validators. [GH-TREE]

### 6.4 Cooldown Manager / Cooldown Viewer - loads on Forever

- `Blizzard_CooldownViewer.toc`: `AllowLoadGameType: standard, camelot`. [GH-TOC]
- Forever dev notes: "By default, the Cooldown Manager is disabled, and it can be enabled in Options under the Gameplay Enhancement settings"; by Oct 8 "All classes, racial abilities, and trinkets are now supported"; spell ranks collapse to one entry (Oct 16). [BLZ-FDN, primary]
- Addon-facing: `C_CooldownViewer.GetCooldownViewerCategorySet(category [, allowUnlearned])`, `GetCooldownViewerCooldownInfo(cooldownID)`, `GetValidAlertTypes(cooldownID)`, `GetLayoutData()`, `SetLayoutData(data)`, `IsCooldownViewerAvailable()`, `GetGroupBuffItems()`. [GH-DOC CooldownViewer]

### 6.5 Private auras

- Still exist: `C_UnitAuras.AddPrivateAuraAnchor(args) -> anchorID`, `RemovePrivateAuraAnchor(id)`, `SetPrivateWarningTextAnchor(parent [, anchor])`. Combat restriction on the anchor calls was added and then removed in 12.0.5. [W-1201N; W-1205N]
- In 12.1.0 "AuraContainers now treat private auras just like regular auras, allowing them to be shown and sorted normally." [W-1210N]
- Whether any Forever content flags private auras is **unknown**.

### 6.6 Other

- Combat Audio Alerts (`Blizzard_CombatAudioAlerts`, `AllowLoad: game`), `C_AssistedCombat` (one-button rotation helper) are present in the forever docs/tree; not investigated further.
- New in 1.60.1: `C_SwingTimer.*`, `C_PetInfo.GetPetHappiness()`; oUF's swing element "only functions in Forever". [W-1601; OUF]

## 7. Taint vs secrets

| | Taint (old system, still active) | Secrets (12.0+) |
|---|---|---|
| Unit of protection | Execution path / frames | Individual Lua values |
| Trigger | Addon code touching protected functions or secure frames | Receiving a value an API marked secret |
| In combat | Protected functions blocked (`ADDON_ACTION_BLOCKED`), `InCombatLockdown()` | Depends on restriction state (§4) |
| Failure | Blocked action event, sometimes silent | Immediate Lua error at the offending operation |
| Relationship | Being tainted is exactly what makes secrets opaque to you | Untainted (Blizzard) code treats secrets as normal values |

Rules that follow from the docs [W-SV; GH-DOC]:

- `SecretArguments = "AllowedWhenUntainted"`: Blizzard code only. `"AllowedWhenTainted"`: you may pass secrets. `"NotAllowed"`: nobody may (e.g. `SendAddonMessage`, `C_EncounterEvents.SetEventColor`).
- Hooks: `hooksecurefunc` post-hooks on Blizzard functions run tainted, so secrets passed to your hook are opaque. Many secret-related functions are `SecureHooksAllowed = false`.
- If your addon taints a Blizzard code path, Blizzard's own arithmetic on secrets starts failing *inside Blizzard files* with "(tainted by 'YourAddon')". Avoid writing into Blizzard tables/frames; avoid replacing Blizzard functions.
- Secure delegates: `GameTooltip:Set*`, `EditModeManagerFrame:ClearSelectedSystem`, `raidtarget`/`outfit` secure actions let addons trigger Blizzard behaviour without tainting it. `CreateSecureDelegate` itself has `HasRestrictions = true` (not for addons).
- `securecallfunction`/`securecallmethod` do not grant secret access.
- **pcall**: no Blizzard statement was found about `pcall` and secret errors. They are described as ordinary "immediate Lua errors", so `pcall` should catch them, but it reveals nothing (the comparison errors regardless of the value) and costs performance. No reference addon examined uses `pcall` as a secret guard; all use `issecretvalue`/`C_Secrets`. Treat pcall-probing as unsupported.
- Addon execution throttles exist (`GetScriptBucketThrottleLimits()` shows normal vs "Restricted" budgets); they do not apply during `PLAYER_LOGOUT` / `ADDONS_UNLOADING`. [GH-DOC FrameScript; W-1205N]

## 8. Practical rules and patterns

1. **Decide per value, at the point of use.** `if issecretvalue(v) then <display only> else <logic allowed> end`. Do not infer secrecy from `InCombatLockdown()`.
2. **Never do math or comparisons on health, power, cooldown times, aura data, or enemy identity.** Use `UnitHealthPercent`/`UnitPowerPercent` with curves, `UnitHealthMissing`, duration objects, the heal prediction calculator, `TruncateWhenZero`.
3. **Bars**: `SetMinMaxValues(0, UnitHealthMax(unit)); SetValue(UnitHealth(unit))` works with secrets. For smoothing pass `Enum.StatusBarInterpolation.ExponentialEaseOut`; do not hand-roll interpolation in `OnUpdate`.
4. **Timers**: never `duration - (GetTime() - start)`. Get a duration object and use `SetTimerDuration`, `SetCooldownFromDurationObject`, or a `DurationTextBinding`.
5. **Booleans**: `SetAlphaFromBoolean`/`SetVertexColorFromBoolean`/`C_CurveUtil.EvaluateColorFromBoolean`. Not `if`, not `SetShown(secret)`.
6. **Text**: build with `..`/`string.format`, set with `SetText`. After that the FontString's text and size getters are secret: do not auto-size layouts from `GetStringWidth()` of a secret-bearing FontString.
7. **Tables**: never key a table by a possibly secret value (GUID, name, spellID, auraInstanceID). Guard first: `if not issecretvalue(guid) then cache[guid] = ... end`. Key by unit token, `castBarID`, or your own counters.
8. **Do not anchor important frames to a widget that receives secrets**; anchoring secrecy flows down to dependents. Give secret-bearing regions their own leaf frames.
9. **Pool hygiene**: before reusing a pooled region that held secrets for non-secret work, call `SetToDefaults()` (not in combat for protected objects) or keep separate pools. Blizzard itself fixed a bug of this kind (RaidWarning fontstrings). [W-1215N]
10. **SavedVariables**: sanitize with `scrubsecretvalues`/`issecretvalue` before storing; secrets are written as `nil`.
11. **Unit comparisons**: `C_Secrets.CanCompareUnitTokens(a, b)` first, or `scrubsecretvalues(UnitIsUnit(a, b))`. Use lowercase unit tokens.
12. **Auras**: out of combat use `C_UnitAuras` normally. In combat use AuraContainers for display, by-spellID lookups for whitelisted spells, and treat nil as "unknown". Never iterate `GetUnitAuras` results while `C_Secrets.ShouldAurasBeSecret()`.
13. **Comms**: check `C_ChatInfo.InChatMessagingLockdown()` and the `SendAddonMessage` result (`AddOnMessageLockdown = 11`). Queue non-urgent sync for after the encounter. Never put a secret in a message.
14. **No combat log.** Do not register `COMBAT_LOG_EVENT_UNFILTERED` on Forever (registration errors). Use unit events, `UNIT_SPELLCAST_*` for the player, `C_DamageMeter`, `PARTY_KILL`, `UNIT_DIED`, `ENCOUNTER_START/END`.
15. **Feature-detect** everything (`if C_Secrets and C_Secrets.HasSecretRestrictions and C_Secrets.HasSecretRestrictions() then`). Well-maintained addons keep `issecretvalue or function() return false end` shims for older clients. [BW Core/PluginPrototype.lua]
16. **Test with `secretwrap`**: `local s = secretwrap(42)` gives a real secret to push through your code paths out of combat; combine with the forced-restriction CVars (§2.4).
17. **Read the generated docs for the exact build**: `https://github.com/Gethe/wow-ui-source/tree/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated`. Fields to look for: `SecretArguments`, `SecretReturns`, `ConditionalSecret`, `NeverSecret`, `SecretWhen*`, `SecretArgumentsAddAspect`, `SecretReturnsForAspect`, `Requires*`, `HasRestrictions`, `IsProtectedFunction`.

## 9. Common error messages

Exact strings below come from player/addon bug reports on retail 12.0.x [ERR, secondary] except where noted; wording on 1.60.1 may differ slightly.

| Message (pattern) | Meaning |
|---|---|
| `attempt to perform arithmetic on a secret number value (tainted by 'AddonName')` / `attempt to perform arithmetic on local 'x' (a secret number value, while execution tainted by 'AddonName')` | Arithmetic on a secret in tainted execution. If the file is a Blizzard file, the named addon tainted that code path. |
| `attempt to compare local 'x' (a secret number value, while execution tainted by 'AddonName')` | Comparison on a secret. |
| `bad argument #1 to 'SetCooldown' (... Secret values are only allowed during untainted execution for this argument.)` | Passed a secret to an API marked `AllowedWhenUntainted`. For cooldown frames switch to `SetCooldownFromDurationObject`. |
| `Usage: local result = Ambiguate(fullName, context). Secret values are only allowed during untainted execution for this argument.` | Same class of error for a global API (this specific one was relaxed in 12.0.5). |
| `attempted to index a forbidden table` | Tainted access to a table flagged inaccessible (e.g. one with secret keys). [W-SV, primary] |
| `ADDON_ACTION_BLOCKED` / `ADDON_ACTION_FORBIDDEN` events | Old taint system: protected function called from tainted code (in combat / at all). |
| Lua error from `C_UnitAuras.GetAuraDataByIndex` etc. during combat | `RequiresUnitAuraAccess` failure mode is "Error" while auras are secret (12.1.0+). |
| Lua error calling a method on an AuraButton in combat | Button is forbidden while auras are secret. |
| Error from `RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")` | Combat log events cannot be registered by addons. Exact text not captured. |
| API silently returns nothing | Precondition with failure mode `ReturnNothing` (e.g. `UnitIsUnit` on non-comparable tokens, by-spell aura lookup on a secret aura, unsupported unit token types since 12.0.7). |

Blizzard "improved lua error messaging when a script object API fails due to being passed secrets" (Beta 2) and for "security-related errors involving tables" (12.0.5), so messages are generally self-describing. [W-1200N; W-1205N]

## 10. Forever (1.60.x) specifics in one place

| Fact | Source |
|---|---|
| Secrets and "addon disarmament" are active in Forever; API is roughly 12.1.5; AuraContainer available | W-1601N (2026-09-15), primary |
| TOC `16001`; game type `camelot`, alias `forever` (TOC suffix `_Forever.toc`, `[Game]`, `AllowLoadGameType forever`); `WOW_PROJECT_ID == WOW_PROJECT_CAMELOT` (18) | W-1601, W-1601N, primary |
| Consolidated API diff is against 12.1.5 (69952): 176 global functions added, 10 removed | W-1601, primary |
| New `FrameStrata` secret aspect; `GetFrameStrata` can return a secret | W-1601N Beta 4 |
| Trial accounts cannot send addon messages; addon `SendChatMessage` "EMOTE" needs a hardware event outside instances (like SAY/YELL) | W-1601N Beta 4 |
| "Fixed a further issue that allowed addons to access minimap rotation values during encounters" | W-1601N Beta 4 |
| NPC/vehicle/pet/object GUID server and spawn IDs obfuscated per session | W-1601N Beta 5 |
| Lua `require` was added then renamed `import` | W-1601N Beta 4 |
| Damage Meter and Cooldown Viewer addons load on `camelot`; Encounter Timeline and Encounter Warnings addons are `standard` only | GH-TOC (build 71091), primary |
| `C_Intl` accepts secret strings from tainted code (25/26 functions) since build 70009 | GH-DOC, primary; contradicts the brief |
| oUF, BigWigs, ElvUI and Plater TOCs all list interface 16001 and use the same secret-handling code paths as retail; Questie (installed here) guards with `issecretvalue` | OUF, BW, EUI, PLT, QST source |
| oUF uses spell 1283885 as the GCD spell on Forever | OUF |
| The wiki has no API notes for Forever after 2026-10-16 (Beta 5, build 70425); the installed build is 71037 | W-1601N; gap noted |

## 11. What could not be confirmed

- **Nothing was run in the game.** All behaviour is from documentation and other addons' source.
- **C_Intl "no longer accepts secrets" in 1.60.1**: not found; primary sources say the opposite (§5.6).
- **Whether `UnitHealth("player")` is secret out of combat on Forever.** Docs say `SecretReturns = true` (unconditional). One addon comment (Cell) says "Health values are always secret in instances", which hints it may be contextual in practice. Verify with `/dump issecretvalue(UnitHealth("player"))` in each state.
- **Which Forever maps apply the Map/Chat restrictions**, whether battlegrounds count as PvPMatch, and whether ChallengeMode ever activates in Forever.
- **Forever's never-secret spell/aura/cooldown/power whitelists.** Retail lists exist (retail spell IDs); none published for Forever. Query `C_Secrets.Get*Secrecy`.
- **Whether `C_EncounterTimeline` / `C_EncounterWarnings` produce events on Forever**, given their UI addons are not loaded for `camelot`.
- **Whether `SecureAuraHeaderTemplate` exists on Forever** (removed from Mainline in 12.1.0, kept for Classic).
- **`tostring(secret)` result and `pcall` behaviour**: no explicit primary statement.
- **Exact error strings on 1.60.1** (collected from retail 12.0.x reports).
- **Forced-restriction CVar names** (two schemes in primary sources).
- **Changes in Forever builds 70425 -> 71037**: no Blizzard addon notes were found for that range; the generated docs at 71091 were used as ground truth instead.
- **Details, Platynator, WeakAuras were not examined**: Platynator's repo could not be cloned anonymously, Details' repo was not located, and the WeakAuras2 repo checked contains only Classic-flavour TOC files (no Mainline or 16001 TOC), so it gave no Forever-relevant patterns.
- Thin "WoW Forever" fan sites were not used for any claim.

## Sources

Primary = Blizzard statements, Blizzard-generated documentation/source, the wiki's transcription of those, or addon source code read directly.

| Key | Source | Type | Documented for |
|---|---|---|---|
| W-SV | https://warcraft.wiki.gg/wiki/Secret_Values | primary (wiki, cites Blizzard docs) | 12.0.0 - 12.1.5 |
| W-1200 | https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes | primary | 12.0.0 |
| W-1200N | https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes/notes (Blizzard WoWUIDev posts, Jun 2025 - Feb 2026) | primary | 12.0.0 alpha/beta/PTR |
| W-1201N | https://warcraft.wiki.gg/wiki/Patch_12.0.1/API_changes/notes | primary | 12.0.1 |
| W-1205N | https://warcraft.wiki.gg/wiki/Patch_12.0.5/API_changes/notes | primary | 12.0.5 |
| W-1207N | https://warcraft.wiki.gg/wiki/Patch_12.0.7/API_changes/notes | primary | 12.0.7 |
| W-1210N | https://warcraft.wiki.gg/wiki/Patch_12.1.0/API_changes/notes | primary | 12.1.0 |
| W-1215N | https://warcraft.wiki.gg/wiki/Patch_12.1.5/API_changes/notes | primary | 12.1.5 |
| W-1601 | https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes | primary | 1.60.1 (70205) |
| W-1601N | https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes/notes | primary | 1.60.1 beta (to build 70425) |
| W-CC | https://warcraft.wiki.gg/wiki/ScriptObject_ColorCurveObject | primary | 12.0.0+ |
| W-DUR | https://warcraft.wiki.gg/wiki/ScriptObject_DurationObject | primary | 12.0.0, list updated 12.0.7 |
| W-FA | https://warcraft.wiki.gg/wiki/Enum.ForbiddenAspect | primary | 12.1.0 / 12.1.5 |
| W-ART | https://warcraft.wiki.gg/wiki/Enum.AddOnRestrictionType | primary | 12.0.0 / 12.0.5 |
| GH-DOC | https://github.com/Gethe/wow-ui-source/tree/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated (files: FrameScript, SecretPredicateAPI, SecretPredicates, SecretAspectConstants, SecretWrapperConstants, RestrictedActions(+Constants), CurveUtil, LuaCurveObjectAPI, LuaColorCurveObjectAPI, DurationUtil, LuaDurationObjectAPI, Simple{FrameScriptObject,StatusBar,FontString,TextureBase,Region,ScriptRegion,Frame}API, FrameAPICooldown, FrameAPINamePlate, NamePlate, Unit, UnitAura, Spell, SpellShared, ChatInfo, ChatConstants, StringUtil, ColorUtil, Intl, CombatLog*, CombatText, DamageMeter(+Constants), EncounterTimeline, EncounterWarnings, EncounterEvents, UnitHealPredictionCalculatorAPI, CooldownViewer) | primary (Blizzard-generated) | 1.60.1, branch head build 71091; commits exist for 71037 |
| GH-TOC | `Blizzard_DamageMeter.toc`, `Blizzard_CooldownViewer.toc`, `Blizzard_EncounterTimeline.toc`, `Blizzard_EncounterWarnings.toc`, `Blizzard_AuraContainer.toc` under https://github.com/Gethe/wow-ui-source/tree/forever/Interface/AddOns | primary | 1.60.1 (71091) |
| GH-DCL | https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_DeprecatedCombatLog/Deprecated_CombatLog.lua | primary | 1.60.1 |
| GH-CURVE | https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXMLBase/CurveConstants.lua | primary | 1.60.1 |
| GH-TREE | https://github.com/Gethe/wow-ui-source/tree/forever (file listing; `Blizzard_AuraContainer/`, `Blizzard_UnitFrame/Shared/UnitFrameUtil.lua`) | primary | 1.60.1 |
| BLZ-NEWS | https://worldofwarcraft.blizzard.com/en-us/news/24246290 ("Combat Philosophy and Addon Disarmament in Midnight") | primary | 12.0.0 (Nov 2025) |
| BLZ-FDN | https://us.forums.blizzard.com/en/wow/t/wow-forever-beta-development-notes-%E2%80%93-updated-september-24/2360696 | primary | Forever beta, Sep - Nov 2026 (no API/secret content; Cooldown Manager, nameplate, Edit Mode notes only) |
| OUF | https://github.com/oUF-wow/oUF (commit of 2026-11-14; `oUF.toc` has `AllowLoadGameType: standard, camelot`; files `elements/health.lua`, `power.lua`, `castbar.lua`, `auras.lua`, `tags.lua`, `private.lua`, `colors.lua`) | primary (source code) | 12.1.x + 1.60.1 |
| BW | https://github.com/BigWigsMods/BigWigs (2026-11-24; `Loader.lua`, `Init_Camelot.lua`, `Core/BossPrototype.lua`, `Core/Core.lua`, `Plugins/Sound.lua`, `Plugins/Messages.lua`, `Plugins/Timeline.lua`, `Plugins/Pull.lua`, `Tools/AutoInvite.lua`) | primary (source code) | 12.1.x + 1.60.1 |
| EUI | https://github.com/tukui-org/ElvUI (2026-11-24; `ElvUI_Libraries/Game/Shared/oUF/init.lua`, `ElvUI/Game/Shared/Tags/Modern.lua`) | primary (source code) | 12.1.x + 1.60.1 |
| PLT | https://github.com/Tercioo/Plater-Nameplates (2026-11-24; `Plater_Interrupts.lua`) | primary (source code) | 12.1.x + 1.60.1 |
| CELL | https://github.com/enderneko/Cell (2026-08-09, r279-beta; `RaidFrames/UnitButton.lua`) | primary (source code) | 12.0.x (older) |
| QST | Local install `...\_forever_\Interface\AddOns\Questie` (`Modules/QuestieCompat.lua`, `Modules/Tooltips/Tooltip.lua`, `Modules/Map/Waypoints/*.lua`, `Libs/AceComm-3.0/ChatThrottleLib.lua`) | primary (source code running on this client) | 1.60.1 |
| ERR | Error-string reports: https://www.wowace.com/projects/handynotes/issues/226 , https://www.wowace.com/projects/grid2/issues/1364 , https://www.wowace.com/projects/broker_speed/issues/4 , https://www.wowace.com/projects/rarity/issues/563 , https://us.forums.blizzard.com/en/wow/t/can-anyone-understand-this-lua-error/2296610 , https://us.forums.blizzard.com/en/wow/t/fix-the-lua-errors-hotmess/2296699 (seen via search-result excerpts, pages not opened individually) | secondary | 12.0.x retail |
