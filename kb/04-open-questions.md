# Open questions

Runtime behaviour that documentation and source could not settle. Ask the game with a probe in `addons/ForeverDevKit/Probes.lua`; results land in `ForeverDevKitDB.sessions[n].probes["<id>@<trigger>"]` (see [03-workflow.md](03-workflow.md) section 5).

When an answer arrives: write it into the KB page it belongs to with the date and build, delete the row here, and delete the probe.

**Status 2026-11-25:** the first probe run answered the identity, naming and open-world secrecy questions; those are now in [01-forever-essentials.md](01-forever-essentials.md) (sections 2 and 5-6). The probe mechanism, the event trace and Lua error capture are all confirmed working in game.

## Still open, with a probe ready

| Question | Why it matters | How to answer |
|---|---|---|
| What happens on `RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")`: Lua error, blocked-action popup, or silence? | Whether a guarded registration is even safe. May show a popup. | `/fdk probe cleu`, then `/reload` |
| Is target health secret out of combat? Are friendly players' health, name and GUID secret? | Unit-frame and group addons. | Add probes when such an addon is planned |

## Needs specific content or a second player

Ask the user when an addon depends on one.

- Whether dungeon and raid bosses activate the `Encounter` restriction, and what changes when they do (unit identity, chat lockdown).
- Which maps apply the `Map` and `Chat` restrictions; whether battlegrounds count as `PvPMatch`.
- Sender and whisper-target name format in `CHAT_MSG_*` events since the 2026-11-21 realm-name removal.
- Payloads of `SHARD_TRANSFER*` events.
- Whether `Settings.OpenToCategory` works during combat.
- Whether returning to character select (without a full restart) is enough for the client to see a new addon folder.
- Whether a TOC with a BOM or CRLF line endings loads correctly (we always write UTF-8 without BOM, LF).
