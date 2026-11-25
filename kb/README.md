# WoW Forever addon knowledge base

Built 2026-11-25 against client **1.60.1.71091** (interface 16001). Read this before writing or changing any addon here. Your training data predates this client and is wrong about it in specific, predictable ways; the pages below say where.

## Reading order

| Page | Read it when | Size |
|---|---|---|
| [01-forever-essentials.md](01-forever-essentials.md) | Always, first. What this client is, what is gone, what is restricted. | short |
| [02-addon-blueprint.md](02-addon-blueprint.md) | Before writing code. House structure, patterns and review checklist. | short |
| [03-workflow.md](03-workflow.md) | Before running anything. Lookup tools, the offline gate, the in-game feedback loop. | short |
| [04-open-questions.md](04-open-questions.md) | When a design depends on runtime behaviour nobody has confirmed. | short |
| [research/forever-platform.md](research/forever-platform.md) | Details: TOC rules, API diff vs retail 12.1.5, systems present/absent, names, packaging, what other addons changed. | long |
| [research/secret-values-and-restrictions.md](research/secret-values-and-restrictions.md) | Anything touching health, power, auras, cooldowns, casts, unit identity, combat, or addon comms. | long |
| [research/modern-api-patterns.md](research/modern-api-patterns.md) | Exact signatures and worked examples: Settings, Menu, ScrollBox, tooltips, timers, secure templates, Edit Mode, C_* families, SavedVariables. | very long |
| [research/tooling-and-debugging.md](research/tooling-and-debugging.md) | Linting, formatting, packaging, in-game debug commands, reference sources. | long |

The research pages are long. Use Grep on a heading or API name instead of reading them whole.

## What to trust, in order

1. **`reference/wow-ui-source`** (branch `forever`): Blizzard's own UI code and generated API docs for this exact build. Query it with `python tools/wowapi.py`. If a KB page and the source disagree, the source wins; fix the page.
2. **Results recorded by the ForeverDevKit addon** from the running game (see 03-workflow.md). This is the only evidence of runtime behaviour.
3. The research pages. Every claim there is tagged primary/secondary and "verified"/"unverified". Nothing in them was tested in game.
4. Your memory of WoW APIs. Assume it describes a different client until checked against 1.

Fan sites about "WoW Forever" (wowforeverguides, gamgem, forevermeta and similar) contradict each other and were not used for any claim here. Do not cite them.

## Keeping this current

- After a client patch: `tools\update-reference.ps1` (refreshes source, API index and the luacheck globals), then skim `git -C reference\wow-ui-source log -1` and re-run `tools\check.ps1`.
- When the game answers an open question, move it from 04-open-questions.md into the relevant page with the date and build, and delete the probe.
- When a page turns out to be wrong, correct it in place. Do not append a contradiction.
