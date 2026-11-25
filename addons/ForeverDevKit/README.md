# Forever DevKit

Development aid for this workspace. It writes what happened in a play session to disk so that it can be read without seeing the game.

Output: `WTF\Account\<account>\SavedVariables\ForeverDevKit.lua`, written by the client on `/reload` and logout.

## What it records

`ForeverDevKitDB.sessions` holds the last five sessions, newest first. Each has:

| Field | Content |
|---|---|
| `started`, `ended`, `client`, `locale`, `character` | When, which build, level and class |
| `addons` | Name and version of every loaded addon |
| `errors`, `errorTotal` | Lua errors and warnings of the session, copied from Blizzard's `ScriptErrorsFrame` at logout (last 100; message, stack, locals, count, time) |
| `blocked` | `ADDON_ACTION_BLOCKED` / `ADDON_ACTION_FORBIDDEN` events with a stack |
| `trace` | The events listed in `ns.watchEvents` (`Probes.lua`), in order, with time and arguments (first 300) |
| `probes` | Results of the expressions in `Probes.lua`, keyed `"<id>@<login|combat|manual>"` |
| `snapshotFailed` | Set only if copying the errors itself failed |

It does not replace the error handler, hook anything, or write to any Blizzard table.

## Probes

`Probes.lua` is a list of Lua expressions to evaluate in the live client. `login` probes run three seconds after entering the world, `combat` probes one second into each of the first three fights, `manual` probes only on request. Secret values are recorded as `<secret type>`, never read.

To ask a new question: add a line, `/reload` (runs it), `/reload` again (saves it).

## Slash commands

| Command | Effect |
|---|---|
| `/fdk` | Help |
| `/fdk errors` | Count of errors and blocked actions so far this session, and the latest message |
| `/fdk probe` | Re-run the login probes now |
| `/fdk probe <id>` | Run one probe by id (the only way to run `manual` probes) |
| `/fdk clear` | Forget earlier sessions |
| `/fdk error` | Raise a deliberate Lua error, to verify that capture works |

No settings.

## Status

Confirmed in game on 2026-11-25 (build 71091): session recording, login and combat probes, the event trace, and Lua error capture (a deliberate `/fdk error` was saved with message, file:line and stack). Blocked-action capture has not been exercised, because nothing has been blocked yet.
