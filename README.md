# WoW Forever addons

Addons for the **World of Warcraft: Forever** client (patch 1.60.1, `## Interface: 16001`), together with the knowledge base and offline tooling used to build them with an AI coding agent that cannot see the game.

## Addons

| Addon | What it does | Status |
|---|---|---|
| [AuctionStatFilter](addons/AuctionStatFilter) | Filters the auction house browse list by minimum item stats ("at least 6 Agility"), on top of Blizzard's own search and filters. | Verified in game |
| [ForeverDevKit](addons/ForeverDevKit) | Development aid: saves Lua errors, blocked actions, an event trace and answers to API "probes" into SavedVariables, so they can be read from disk after `/reload`. | Verified in game |

### Installing an addon

Copy the addon's folder from `addons/` into `World of Warcraft\_forever_\Interface\AddOns\` and restart the game.

## Knowledge base

[`kb/`](kb/README.md) documents what is different about writing addons for Forever. It is a retail-engine client with Classic-style content, and most older addon knowledge is wrong for it:

- legacy globals such as `GetSpellInfo`, `UnitAura` and `IsAddOnLoaded` do not exist;
- "secret values" make health, auras and cooldowns unreadable to addon logic, in any combat;
- there is no combat log for addons;
- characters have surnames instead of realm names.

Start with [`kb/01-forever-essentials.md`](kb/01-forever-essentials.md). Statements there are marked as checked against Blizzard's UI source, observed in the live client, or unconfirmed.

## Tooling

Windows, PowerShell. Python 3 and git are required.

| Tool | Purpose |
|---|---|
| `tools\update-reference.ps1` | Fetches the `forever` branches of [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source) and [Ketho/BlizzardInterfaceResources](https://github.com/Ketho/BlizzardInterfaceResources) into `reference/` and rebuilds the indexes. Run this first, and after every client patch. |
| `python tools\wowapi.py <name>` | Offline lookup of any API: signature, returns, secret-value flags. |
| `tools\check.ps1 [Addon]` | The offline gate: luacheck against the list of globals that actually exist on Forever, StyLua, TOC and XML validation, and a Lua 5.1 smoke test that loads the addon against a fake client. |
| `tools\new-addon.ps1 -Name Foo` | Scaffolds an addon from the house template. |
| `tools\deploy.ps1` | Junctions every addon into the game's AddOns folder. |

`reference/` and `tools/bin/` (luacheck, StyLua, Lua 5.1) are not versioned. Download links for the binaries are in [`kb/03-workflow.md`](kb/03-workflow.md).

[`CLAUDE.md`](CLAUDE.md) holds the working instructions for the agent.

## Licence

[MIT](LICENSE) for the code and documentation written here. The knowledge base quotes short excerpts from Blizzard's interface code and from other addons to document behaviour; those remain the property of their authors. World of Warcraft is a trademark of Blizzard Entertainment; this project is not affiliated with or endorsed by Blizzard.
