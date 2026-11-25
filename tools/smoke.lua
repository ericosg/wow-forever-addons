-- Offline smoke test: loads an addon the way the client does and walks it through a
-- login, one fight, its slash commands and a logout, under Lua 5.1 with a fake WoW API.
--
--   tools\bin\lua5.1.exe tools\smoke.lua addons\Foo
--
-- The fake API knows which globals exist on Forever (reference/.forever-globals.lua, built
-- by tools/gen-globals.py). A global that does not exist there is nil here too, so calling
-- a removed API such as GetSpellInfo fails exactly as it would in game. Functions that do
-- exist return nothing unless given a real implementation in `core` below; widgets accept
-- any method call. This proves load order, event wiring and nil-safety. It proves nothing
-- about what the real API returns, about layout, or about taint and secret values.

local dir = assert(arg[1], "usage: lua5.1 tools/smoke.lua <addon folder>"):gsub("[\\/]+$", "")
local addonName = dir:match("([^\\/]+)$")
local toolsDir = arg[0]:gsub("[\\/][^\\/]*$", "")
local known = dofile(toolsDir .. "/../reference/.forever-globals.lua")

-- The client's enUS global strings (OKAY, ITEM_MOD_AGILITY_SHORT, ...), so tests see real text.
local globalStrings = {}
do
	local chunk = loadfile(toolsDir .. "/../reference/BlizzardInterfaceResources/Resources/GlobalStrings/enUS.lua")
	if chunk then
		setfenv(chunk, setmetatable(globalStrings, {
			__index = function(self, key)
				return key == "_G" and self or nil
			end,
		}))
		pcall(chunk)
		setmetatable(globalStrings, nil)
	end
end

local failures, notes = 0, {}
local function fail(where, message)
	failures = failures + 1
	print("FAIL  " .. where .. "\n      " .. tostring(message):gsub("\n", "\n      "))
end
local function note(text)
	if not notes[text] then
		notes[text] = true
		notes[#notes + 1] = text
	end
end

-- TOC ------------------------------------------------------------------------------------

local function readLines(path)
	local file = io.open(path, "r")
	if not file then
		return nil
	end
	local lines = {}
	for line in file:lines() do
		lines[#lines + 1] = (line:gsub("^\239\187\191", ""):gsub("\r$", ""))
	end
	file:close()
	return lines
end

local tocLines = readLines(dir .. "/" .. addonName .. ".toc")
	or readLines(dir .. "/" .. addonName .. "_Camelot.toc")
	or readLines(dir .. "/" .. addonName .. "_Forever.toc")
if not tocLines then
	print("FAIL  no " .. addonName .. ".toc in " .. dir)
	os.exit(2)
end

local metadata, files = {}, {}
for _, line in ipairs(tocLines) do
	local key, value = line:match("^##%s*([^:]-)%s*:%s*(.-)%s*$")
	if key then
		metadata[key] = value
	elseif not line:match("^%s*#") and line:match("%S") then
		files[#files + 1] = (line:gsub("%s*%[.-%]", ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("\\", "/"))
	end
end

local savedVariables = {}
for _, key in ipairs({ "SavedVariables", "SavedVariablesPerCharacter" }) do
	for name in (metadata[key] or ""):gmatch("[%w_]+") do
		savedVariables[name] = true
	end
end

-- Fake client ----------------------------------------------------------------------------

local env = {}
local timers, frames = {}, {}

local function nothing() end

-- Stands in for any table, frame, font, mixin or enum: index it, call it, concatenate it.
local function object(name)
	return setmetatable({}, {
		__index = function(self, key)
			local child = object(name .. "." .. tostring(key))
			rawset(self, key, child)
			return child
		end,
		__call = nothing,
		__concat = function(a, b)
			return tostring(a) .. tostring(b)
		end,
		__tostring = function()
			return "<" .. name .. ">"
		end,
	})
end

local frameMethods = {}
function frameMethods:RegisterEvent(event)
	self.__events[event] = true
	return true
end
frameMethods.RegisterUnitEvent = frameMethods.RegisterEvent
function frameMethods:UnregisterEvent(event)
	self.__events[event] = nil
end
function frameMethods:UnregisterAllEvents()
	self.__events = {}
end
function frameMethods:IsEventRegistered(event)
	return self.__events[event] == true
end
function frameMethods:SetScript(script, handler)
	self.__scripts[script] = handler
end
function frameMethods:HookScript(script, handler)
	local previous = self.__scripts[script]
	self.__scripts[script] = previous and function(...)
		previous(...)
		handler(...)
	end or handler
end
function frameMethods:GetScript(script)
	return self.__scripts[script]
end
function frameMethods:GetName()
	return self.__name
end
function frameMethods:GetObjectType()
	return self.__type
end
function frameMethods:IsShown()
	return self.__shown
end
frameMethods.IsVisible = frameMethods.IsShown
function frameMethods:Show()
	self.__shown = true
end
function frameMethods:Hide()
	self.__shown = false
end
function frameMethods:SetShown(shown)
	self.__shown = shown and true or false
end
local function createWidget(kind, name, parent)
	local widget = setmetatable({ __type = kind or "Frame", __name = name, __events = {}, __scripts = {}, __shown = true }, {
		__index = function(self, key)
			if frameMethods[key] then
				return frameMethods[key]
			end
			if type(key) == "string" and key:match("^Create") then
				return function(_, childName)
					return createWidget(key:sub(7), childName, self)
				end
			end
			if type(key) == "string" and key:match("^[A-Z]") then
				return nothing -- any other widget method: accepted, returns nothing
			end
		end,
	})
	widget.__parent = parent
	frames[#frames + 1] = widget
	if type(name) == "string" then
		rawset(env, name, widget)
	end
	return widget
end

local function tocField(_, field)
	return metadata[field]
end

local core = {
	_G = env,
	print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring((select(i, ...)))
		end
		print("  chat| " .. table.concat(parts, " "))
	end,
	loadstring = function(code, chunkName)
		local chunk, problem = loadstring(code, chunkName)
		if chunk then
			setfenv(chunk, env)
		end
		return chunk, problem
	end,
	CreateFrame = function(kind, name, parent)
		return createWidget(kind, name, parent)
	end,
	SlashCmdList = {},
	StaticPopupDialogs = {},
	UISpecialFrames = {},
	WOW_PROJECT_ID = 18,
	WOW_PROJECT_CAMELOT = 18,
	WOW_PROJECT_MAINLINE = 1,
	WOW_PROJECT_CLASSIC = 2,
	GetBuildInfo = function()
		return "1.60.1", "71091", "Nov 24 2026", 16001, "", ""
	end,
	GetLocale = function()
		return "enUS"
	end,
	GetTime = os.clock,
	GetServerTime = os.time,
	GetTimePreciseSec = os.clock,
	debugprofilestop = function()
		return os.clock() * 1000
	end,
	debugstack = function()
		return debug.traceback("", 2)
	end,
	date = os.date,
	time = os.time,
	InCombatLockdown = function()
		return false
	end,
	IsInInstance = function()
		return false, "none"
	end,
	UnitName = function()
		return "Tester", nil
	end,
	UnitNameUnmodified = function()
		return "Tester", nil
	end,
	UnitClass = function()
		return "Warrior", "WARRIOR", 1
	end,
	UnitLevel = function()
		return 60
	end,
	UnitGUID = function()
		return "Player-1-00000001"
	end,
	UnitExists = function(unit)
		return unit == "player"
	end,
	GetRealmName = function()
		return "Testrealm"
	end,
	GetCVar = nothing,
	GetCVarBool = function()
		return false
	end,
	issecretvalue = function()
		return false
	end,
	hasanysecretvalues = function()
		return false
	end,
	canaccessvalue = function()
		return true
	end,
	canaccesstable = function()
		return true
	end,
	scrubsecretvalues = function(...)
		return ...
	end,
	-- Like the real one: the original runs first, then the hook with the same arguments.
	hooksecurefunc = function(a, b, c)
		local owner, name, hook = a, b, c
		if type(a) == "string" then
			owner, name, hook = env, a, b
		end
		local original = owner[name]
		rawset(owner, name, function(...)
			local results = { original(...) }
			hook(...)
			return unpack(results)
		end)
	end,
	EventUtil = {
		-- Pretends every Blizzard load-on-demand addon is already loaded.
		ContinueOnAddOnLoaded = function(_, callback)
			callback()
		end,
	},
	RunNextFrame = function(callback)
		timers[#timers + 1] = callback
	end,
	Mixin = function(target, ...)
		for i = 1, select("#", ...) do
			for key, value in pairs((select(i, ...))) do
				target[key] = value
			end
		end
		return target
	end,
	wipe = function(t)
		for key in pairs(t) do
			t[key] = nil
		end
		return t
	end,
	tContains = function(t, item)
		for _, value in ipairs(t) do
			if value == item then
				return true
			end
		end
		return false
	end,
	strsplit = function(separator, text, limit)
		local parts, start = {}, 1
		while true do
			local at = (not limit or #parts < limit - 1) and text:find(separator, start, true)
			if not at then
				parts[#parts + 1] = text:sub(start)
				break
			end
			parts[#parts + 1] = text:sub(start, at - 1)
			start = at + #separator
		end
		return unpack(parts)
	end,
	strtrim = function(text)
		return (text:gsub("^%s+", ""):gsub("%s+$", ""))
	end,
	strjoin = function(separator, ...)
		return table.concat({ ... }, separator)
	end,
	tostringall = function(...)
		local out = {}
		for i = 1, select("#", ...) do
			out[i] = tostring((select(i, ...)))
		end
		return unpack(out, 1, select("#", ...))
	end,
	format = string.format,
	gsub = string.gsub,
	strfind = string.find,
	strmatch = string.match,
	strsub = string.sub,
	strlen = string.len,
	strlower = string.lower,
	strupper = string.upper,
	strrep = string.rep,
	tinsert = table.insert,
	tremove = table.remove,
	sort = table.sort,
	floor = math.floor,
	ceil = math.ceil,
	min = math.min,
	max = math.max,
	abs = math.abs,
}
core.CreateFromMixins = function(...)
	return core.Mixin({}, ...)
end

local namespaceCore = {
	C_Timer = {
		After = function(_, callback)
			timers[#timers + 1] = callback
		end,
		NewTimer = function(_, callback)
			timers[#timers + 1] = callback
			return object("timer")
		end,
		NewTicker = function(_, callback)
			timers[#timers + 1] = callback
			return object("ticker")
		end,
	},
	C_AddOns = {
		GetNumAddOns = function()
			return 1
		end,
		GetAddOnInfo = function()
			return addonName, metadata.Title, metadata.Notes, true, nil, "INSECURE"
		end,
		IsAddOnLoaded = function()
			return true, true
		end,
		GetAddOnMetadata = tocField,
	},
	C_Secrets = {
		HasSecretRestrictions = function()
			return true
		end,
	},
}

setmetatable(env, {
	__index = function(_, name)
		local value
		if core[name] ~= nil then
			value = core[name]
		elseif _G[name] ~= nil and (type(_G[name]) ~= "table" or name == "string" or name == "table" or name == "math" or name == "bit" or name == "coroutine") then
			value = _G[name]
		elseif known.namespaces[name] then
			local fields, real = known.namespaces[name], namespaceCore[name] or {}
			value = setmetatable({}, {
				__index = function(_, field)
					if real[field] then
						return real[field]
					end
					return fields[field] and nothing or nil
				end,
			})
		elseif known.functions[name] then
			value = nothing
		elseif known.other[name] then
			-- Localized text comes from the real enUS strings; other ALL_CAPS names are
			-- overwhelmingly constants, and their own name is a harmless stand-in.
			value = globalStrings[name] or (name:match("^[A-Z0-9_]+$") and name) or object(name)
		else
			if not savedVariables[name] then
				note("reads global '" .. name .. "', which does not exist on Forever (nil)")
			end
			return nil
		end
		rawset(env, name, value)
		return value
	end,
})

-- Run --------------------------------------------------------------------------------------

local function attempt(where, func, ...)
	local args, count = { ... }, select("#", ...)
	local ok, problem = xpcall(function()
		return func(unpack(args, 1, count))
	end, debug.traceback)
	if not ok then
		fail(where, problem)
	end
	return ok
end

local function flushTimers(where)
	for _ = 1, 20 do
		if #timers == 0 then
			return
		end
		local due = timers
		timers = {}
		for _, callback in ipairs(due) do
			attempt(where .. " (timer callback)", callback)
		end
	end
	timers = {} -- a ticker that re-arms forever is fine; stop following it
end

local function fire(event, ...)
	local delivered = 0
	for _, frame in ipairs(frames) do
		local handler = frame.__events[event] and frame.__scripts.OnEvent
		if handler then
			delivered = delivered + 1
			attempt("event " .. event, handler, frame, event, ...)
		end
	end
	flushTimers("event " .. event)
	print(string.format("  %-24s delivered to %d frame(s)", event, delivered))
end

local namespace = {}
local function loadLua(path)
	local chunk, problem = loadfile(dir .. "/" .. path)
	if not chunk then
		return fail("syntax " .. path, problem)
	end
	setfenv(chunk, env)
	if attempt("loading " .. path, chunk, addonName, namespace) then
		print("  loaded " .. path)
	end
end

local function loadXml(path)
	local lines = readLines(dir .. "/" .. path)
	if not lines then
		return fail("toc", "listed file not found: " .. path)
	end
	local base = path:match("^(.*/)") or ""
	local text = table.concat(lines, "\n")
	note(path .. ": XML layout is not executed; only its <Script file> and <Include file> entries are followed")
	for tag, target in text:gmatch("<(%a+)[^>]-file%s*=%s*\"([^\"]+)\"") do
		target = base .. target:gsub("\\", "/")
		if tag == "Script" then
			loadLua(target)
		elseif tag == "Include" then
			loadXml(target)
		end
	end
end

print("smoke test: " .. addonName .. " (" .. (metadata.Interface or "no Interface line") .. ")")
for _, path in ipairs(files) do
	if path:lower():match("%.lua$") then
		loadLua(path)
	elseif path:lower():match("%.xml$") then
		loadXml(path)
	end
end
flushTimers("file load")

fire("ADDON_LOADED", addonName, false)
fire("PLAYER_LOGIN")
fire("PLAYER_ENTERING_WORLD", true, false)
fire("PLAYER_REGEN_DISABLED")
fire("PLAYER_REGEN_ENABLED")

for key, handler in pairs(rawget(env, "SlashCmdList") or {}) do
	for _, input in ipairs({ "", "help" }) do
		attempt("slash command " .. key .. " '" .. input .. "'", handler, input)
	end
	print("  slash " .. key .. " ran")
end
flushTimers("slash commands")

-- Optional addon-specific scenario: <addon>/tests/smoke.lua receives a table of helpers and
-- may replace API functions with fakes, drive the addon and assert on what it did.
local scenario = loadfile(dir .. "/tests/smoke.lua")
if scenario then
	setfenv(scenario, env) -- the scenario sees the same globals the addon does
	local helpers = {
		env = env,
		ns = namespace,
		fire = fire,
		flushTimers = flushTimers,
		-- Replace one function of a C_ namespace (or any global table) with a fake.
		fake = function(owner, name, func)
			rawset(owner, name, func)
		end,
		check = function(condition, description)
			if condition then
				print("  ok    " .. description)
			else
				fail("scenario", description)
			end
		end,
	}
	if attempt("tests/smoke.lua", scenario, helpers) then
		print("  scenario tests/smoke.lua ran")
	end
end

fire("PLAYER_LOGOUT")

-- Globals the addon created: only SavedVariables, SLASH_* and BINDING_* are legitimate.
local created = {}
for name, value in pairs(env) do
	local mine = core[name] == nil
		and _G[name] == nil
		and not known.namespaces[name]
		and not known.functions[name]
		and not known.other[name]
	local isNamedFrame = type(value) == "table" and rawget(value, "__events") ~= nil
	if mine and not isNamedFrame then
		created[#created + 1] = name
	end
end
table.sort(created)
for _, name in ipairs(created) do
	if savedVariables[name] then
		print("  saved variable " .. name .. " = " .. type(env[name]))
	elseif not name:match("^SLASH_") and not name:match("^BINDING_") then
		fail("global leak", "addon created global '" .. name .. "' (not a SavedVariable, SLASH_ or BINDING_ name)")
	end
end
for name in pairs(savedVariables) do
	if rawget(env, name) == nil then
		note("SavedVariable '" .. name .. "' is declared in the TOC but was never assigned")
	end
end

for _, text in ipairs(notes) do
	print("note  " .. text)
end
print(failures == 0 and "smoke test passed" or (failures .. " failure(s)"))
os.exit(failures == 0 and 0 or 1)
