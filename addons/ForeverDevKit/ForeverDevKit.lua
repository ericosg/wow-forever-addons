local ADDON, ns = ...

-- Persists what happened in a play session to SavedVariables, so it can be read from
-- WTF\Account\<account>\SavedVariables\ForeverDevKit.lua after a /reload or logout.
--
-- Lua errors are copied from Blizzard's ScriptErrorsFrame, which records every error and
-- warning of the session whether or not the scriptErrors CVar shows them. Nothing here
-- replaces the error handler or writes to a Blizzard table.

local MAX_SESSIONS = 5
local MAX_ERRORS = 100
local MAX_TEXT = 3000
local MAX_TABLE_ENTRIES = 40
local MAX_COMBAT_RUNS = 3
local MAX_TRACE = 300
local PREFIX = "|cff33ff99DevKit|r"

local db, session
local combatRuns = 0

local function isSecret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

-- Text for any Lua value, without ever reading a secret.
local function describe(value, depth)
	if isSecret(value) then
		return "<secret " .. type(value) .. ">"
	end
	local kind = type(value)
	if kind == "string" then
		return string.format("%q", value)
	elseif kind ~= "table" then
		return tostring(value)
	elseif canaccesstable and not canaccesstable(value) then
		return "<inaccessible table>"
	elseif depth <= 0 then
		return "{...}"
	end

	local parts, count = {}, 0
	for key, item in pairs(value) do
		count = count + 1
		if count > MAX_TABLE_ENTRIES then
			parts[#parts + 1] = "~more"
			break
		end
		parts[#parts + 1] = "[" .. describe(key, 0) .. "]=" .. describe(item, depth - 1)
	end
	table.sort(parts)
	return "{" .. table.concat(parts, ", ") .. "}"
end

local function describeAll(...)
	local out = {}
	for i = 1, select("#", ...) do
		local ok, text = pcall(describe, (select(i, ...)), 3)
		out[i] = (ok and not isSecret(text)) and text or "<could not describe>"
	end
	return out
end

-- Plain, bounded copy of a string that may be secret or missing.
local function clean(text)
	if isSecret(text) then
		return "<secret>"
	elseif type(text) ~= "string" then
		return text ~= nil and tostring(text) or nil
	end
	return #text > MAX_TEXT and (text:sub(1, MAX_TEXT) .. " ~truncated") or text
end

local function now()
	return date("%Y-%m-%d %H:%M:%S")
end

local function runProbe(probe, trigger)
	local record = { code = probe.code, at = now(), inCombat = InCombatLockdown() and true or false }
	local chunk, compileError = loadstring("return " .. probe.code, "probe:" .. probe.id)
	if chunk then
		local function capture(ok, ...)
			record.ok = ok
			record.results = describeAll(...)
		end
		capture(pcall(chunk))
	else
		record.ok = false
		record.results = { clean(compileError) }
	end
	session.probes[probe.id .. "@" .. trigger] = record
end

local function runProbes(when, onlyID)
	local ran = 0
	for _, probe in ipairs(ns.probes or {}) do
		if (onlyID and probe.id == onlyID) or (not onlyID and probe.when == when) then
			runProbe(probe, onlyID and "manual" or when)
			ran = ran + 1
		end
	end
	return ran
end

local function snapshotErrors()
	local frame = ScriptErrorsFrame
	if not frame or not frame.GetCount or not frame.GetErrorData then
		return 0
	end
	local errors = {}
	local total = frame:GetCount()
	for i = math.max(1, total - MAX_ERRORS + 1), total do
		local data = frame:GetErrorData(i)
		if type(data) == "table" then
			errors[#errors + 1] = {
				message = clean(data.message),
				stack = clean(data.stack),
				locals = clean(data.locals),
				count = clean(data.count),
				time = clean(data.time),
				kind = clean(data.messageType),
			}
		end
	end
	session.errors = errors
	session.errorTotal = total
	return total
end

local function listAddOns()
	local list = {}
	for i = 1, C_AddOns.GetNumAddOns() do
		local name = C_AddOns.GetAddOnInfo(i)
		if name and C_AddOns.IsAddOnLoaded(i) then
			list[#list + 1] = name .. " " .. (C_AddOns.GetAddOnMetadata(i, "Version") or "?")
		end
	end
	return list
end

local function startSession()
	ForeverDevKitDB = ForeverDevKitDB or {}
	db = ForeverDevKitDB
	db.sessions = db.sessions or {}

	local version, build, buildDate, interface = GetBuildInfo()
	session = {
		started = now(),
		client = string.format("%s (%s) interface %s, built %s", version, build, tostring(interface), buildDate),
		locale = GetLocale(),
		errors = {},
		blocked = {},
		probes = {},
		trace = {},
	}
	table.insert(db.sessions, 1, session)
	for i = #db.sessions, MAX_SESSIONS + 1, -1 do
		db.sessions[i] = nil
	end
end

local frame = CreateFrame("Frame")
local handlers = {}

function handlers.ADDON_LOADED(name)
	if name ~= ADDON then
		return
	end
	frame:UnregisterEvent("ADDON_LOADED")
	startSession()
end

function handlers.PLAYER_LOGIN()
	local _, classFile = UnitClass("player")
	session.character = string.format("level %s %s", tostring(UnitLevel("player")), tostring(classFile))
	session.addons = listAddOns()
end

function handlers.PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)
	if isInitialLogin or isReloadingUi then
		C_Timer.After(3, function()
			runProbes("login")
		end)
	end
end

function handlers.PLAYER_REGEN_DISABLED()
	if combatRuns < MAX_COMBAT_RUNS then
		combatRuns = combatRuns + 1
		C_Timer.After(1, function()
			runProbes("combat")
		end)
	end
end

local function onBlocked(event, addonName, protectedFunction)
	if #session.blocked < MAX_ERRORS then
		session.blocked[#session.blocked + 1] = {
			event = event,
			addon = clean(addonName),
			func = clean(protectedFunction),
			at = now(),
			inCombat = InCombatLockdown() and true or false,
			stack = clean(debugstack(3)),
		}
	end
end

function handlers.ADDON_ACTION_BLOCKED(...)
	onBlocked("ADDON_ACTION_BLOCKED", ...)
end

function handlers.ADDON_ACTION_FORBIDDEN(...)
	onBlocked("ADDON_ACTION_FORBIDDEN", ...)
end

function handlers.PLAYER_LOGOUT()
	session.ended = now()
	local ok, problem = pcall(snapshotErrors)
	if not ok then
		session.snapshotFailed = clean(problem)
	end
end

frame:SetScript("OnEvent", function(_, event, ...)
	handlers[event](...)
end)

-- Event trace: every event named in ns.watchEvents (Probes.lua), with its arguments, in order.
local tracer = CreateFrame("Frame")
tracer:SetScript("OnEvent", function(_, event, ...)
	if session and #session.trace < MAX_TRACE then
		session.trace[#session.trace + 1] = { event = event, at = now(), args = describeAll(...) }
	end
end)
for _, event in ipairs(ns.watchEvents or {}) do
	-- An event name the client does not know raises an error; one bad entry must not cost the rest.
	pcall(tracer.RegisterEvent, tracer, event)
end
for event in pairs(handlers) do
	frame:RegisterEvent(event)
end

SLASH_FOREVERDEVKIT1 = "/fdk"
SlashCmdList.FOREVERDEVKIT = function(input)
	local command, argument = strsplit(" ", strtrim(input or ""), 2)
	command = command:lower()

	if command == "probe" then
		local id = argument and strtrim(argument) or ""
		local ran = id ~= "" and runProbes(nil, id) or runProbes("login")
		print(PREFIX, ran, "probe(s) run. /reload to write the results to disk.")
	elseif command == "errors" then
		local total = snapshotErrors()
		print(PREFIX, total, "Lua error(s)/warning(s) this session,", #session.blocked, "blocked action(s).")
		local last = session.errors[#session.errors]
		if last then
			print(PREFIX, "latest:", last.message or "?")
		end
	elseif command == "error" then
		-- Raised outside any pcall so it reaches the client's error handler like a real bug.
		C_Timer.After(0, function()
			error("ForeverDevKit test error (raised on purpose by /fdk error)")
		end)
		print(PREFIX, "test error raised. /reload, then check that it was captured.")
	elseif command == "clear" then
		wipe(db.sessions)
		table.insert(db.sessions, session)
		print(PREFIX, "older sessions cleared.")
	else
		print(PREFIX, "/fdk errors - count errors captured this session")
		print(PREFIX, "/fdk probe [id] - re-run login probes, or one probe by id")
		print(PREFIX, "/fdk clear - forget earlier sessions")
		print(PREFIX, "/fdk error - raise a test error to verify capture")
		print(PREFIX, "Everything is written to disk on /reload or logout.")
	end
end
