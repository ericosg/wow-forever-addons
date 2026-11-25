# Auction Stat Filter

Filters the auction house browse list by minimum item stats, on top of Blizzard's own search, category and filter controls.

## Use

Open the auction house. On the Buy tab a "Minimum stats" panel sits to the right of the window with one box each for Strength, Agility, Stamina, Intellect and Spirit. Type a number (for example 6 next to Agility), then press Search (or Enter in the box): the browse list shows only items with at least that much. Like Blizzard's own filters, a change takes effect on the next search; the panel says "Press Search to apply" until then. Several minimums combine: an item must meet all of them. Empty or 0 means no requirement. "Clear All" removes every minimum at once, without a new search.

Search, sort, pick categories and use Blizzard's filter dropdown as usual; the stat minimums apply to whatever that search returns. Minimums are remembered between sessions.

The line under the button reports what happened: how many of the loaded items are shown, how many are still being read, and whether the server is still sending results.

## How it works

- A browse row is an item type (item, level, random suffix), not a single auction. Its stats are read from the same tooltip you see when hovering the row, by summing lines of the form `+6 Agility`.
- While any minimum is set, the addon keeps asking the server for the next page until the whole search has arrived, so the filter covers every result and not just the first page. On a very broad search (no category, no text) that can take a while; narrow the search first.
- Items whose data the client has not received yet are left out until it arrives, then added.

## Limits

- Only the five primary stats. Effects written as "Equip: ..." (attack power, spell power, hit) are not read.
- Stat names are matched in the client's language through its own strings; only enUS has been exercised.
- Enchants on individual auctions are not considered.

## Slash commands

| Command | Effect |
|---|---|
| `/asf` | Help |
| `/asf clear` | Remove all minimums |
| `/asf debug` | Toggle debug output |

## Settings

Saved in `AuctionStatFilterDB`: `minimums` (per stat), `debug`, and `debugLog` (the tooltip text and stats read for the first 80 new items of the latest search, for diagnosing wrong results).

## Status

Works in game as of 2026-11-25 (build 71091): an Armor search with "Usable Only" and minimums of 6 Agility and 6 Intellect showed 11 of 4,392 items, including the "of the Falcon" pieces a keyword search finds. The first version missed those because it judged items before their data was cached. Buying out an item from the filtered list also works (purchase completed, no errors or blocked actions).
