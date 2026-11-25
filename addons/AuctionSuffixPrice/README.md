# Auction Suffix Price

On the auction house Sell tab, Blizzard compares a random-suffix item ("Superior Tunic of Agility") with every auction of the base item, whatever its suffix, and suggests the cheapest of them as your price. This addon makes the Sell tab compare like with like.

- The suggested buyout comes from the cheapest auction with the **same suffix**.
- A checkbox above the price list, `Only "of Agility"`, is ticked by default and shows only matching auctions, with a count ("1 of 40 listings").
- Unticked, every variant is listed; each row shows its suffix and other variants are dimmed. The suggested price still comes from the same suffix.
- When nothing with the same suffix is listed, the price stays at Blizzard's default and a note says so.
- A red note warns when the buyout is at or below the vendor price.

Items without variants are left exactly as Blizzard handles them. A price you type or a row you click is never overridden. The addon sends nothing to the server beyond asking for further pages of the search Blizzard already made.

## Slash commands

| Command | Effect |
|---|---|
| `/asp` | Help |
| `/asp clear` | Empty the diagnostic log |
| `/asp debug` | Toggle debug output |

## Settings

Saved in `AuctionSuffixPriceDB`: `onlyMatching` (the checkbox), `debug`, and `log` (the last 100 entries of what the client returned and what the addon decided).

## Status

Version 0.2.0.

Tested in game on 2026-11-25 (build 71091), with the other addons disabled: suggested price, matching-only list and count, all-variants list with suffix labels and dimming, and posting an auction. Variants are matched by the suffix in the auction's item key; a comparison by item name is kept as a fallback and was never needed.

Verified offline only (`tests/smoke.lua`, against a miniature of Blizzard's sell frame): no matching auction, the vendor-price warning, results spread over several pages, equipment without variants, typed and clicked prices, the list after a post.

Loaded together with AuctionStatFilter and ForeverDevKit: 0 Lua errors and 0 blocked actions recorded, and selling stackable items is unaffected (they use a Blizzard frame this addon does not touch).

Not yet seen in game on 0.2.0: a random-suffix item (the same code path was tested on 0.1.0) and a piece of equipment without a suffix.

Version 0.1.0 also had a second way of producing the matching list (asking the server for the exact item, as the Buy tab does). It worked in game but was dropped: a search per toggle, a visible wait, and it rewrote the item key Blizzard displays.
