local _, ns = ...

-- Questions for the running client. Each probe is a Lua expression list; its results are
-- described as text and saved to ForeverDevKitDB (see README.md).
--
--   when = "login"   runs a few seconds after entering the world
--   when = "combat"  runs one second into combat (first three fights of a session)
--   when = "manual"  runs only on `/fdk probe <id>`; use for anything with a visible side effect
--
-- Edit freely: add a probe, /reload (runs it), /reload again (flushes results to disk).
-- Remove probes once their answer is recorded in the KB (kb/04-open-questions.md).
ns.probes = {
	-- Kept as a per-session fingerprint of the client.
	{ id = "build", when = "login", code = [[GetBuildInfo()]] },
	{
		id = "restrictions",
		when = "combat",
		code = [[C_RestrictedActions.GetAddOnRestrictionState(0), C_RestrictedActions.GetAddOnRestrictionState(1), C_RestrictedActions.GetAddOnRestrictionState(4), C_RestrictedActions.GetAddOnRestrictionState(5), IsInInstance()]],
	},

	-- Side effects: may raise a "blocked action" popup. Run by hand: /fdk probe cleu
	{
		id = "cleu",
		when = "manual",
		code = [[pcall(function() local f = CreateFrame("Frame") return f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED") end)]],
	},
}

-- Events to trace into ForeverDevKitDB.sessions[n].trace (name, time, arguments; first 300).
-- Keep this to the feature under test, and avoid events that fire constantly.
ns.watchEvents = {}
