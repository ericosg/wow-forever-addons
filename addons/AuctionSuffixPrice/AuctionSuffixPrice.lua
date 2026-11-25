local ADDON, ns = ...

local DB_VERSION = 2
local LOG_LIMIT = 100
local defaults = {
	debug = false,
	-- Show only listings of the same variant as the item being sold.
	onlyMatching = true,
	log = {},
}

-- Fills in missing keys only; never overwrites what the user has saved.
local function applyDefaults(target, source)
	for key, value in pairs(source) do
		if type(value) == "table" then
			if type(target[key]) ~= "table" then
				target[key] = {}
			end
			applyDefaults(target[key], value)
		elseif target[key] == nil then
			target[key] = value
		end
	end
	return target
end

function ns.Print(...)
	print("|cff33ff99Auction Suffix Price|r:", ...)
end

function ns.Debug(...)
	if ns.db and ns.db.debug then
		ns.Print("|cff888888debug|r", ...)
	end
end

-- Diagnostic log, read back from SavedVariables after a /reload: what the client returned
-- and what the addon decided. Small and capped, so it stays on.
function ns.Log(kind, entry)
	if not ns.db then
		return
	end
	entry = entry or {}
	entry.kind = kind
	entry.at = date("%H:%M:%S")
	local log = ns.db.log
	log[#log + 1] = entry
	while #log > LOG_LIMIT do
		table.remove(log, 1)
	end
	ns.Debug(kind)
end

local frame = CreateFrame("Frame")
local events = {}

-- One event frame for the whole addon; other files add their handlers here.
function ns.RegisterEvent(event, handler)
	events[event] = handler
	frame:RegisterEvent(event)
end

function events.ADDON_LOADED(name)
	if name ~= ADDON then
		return
	end
	frame:UnregisterEvent("ADDON_LOADED")
	if type(AuctionSuffixPriceDB) ~= "table" then
		AuctionSuffixPriceDB = {}
	end
	ns.db = applyDefaults(AuctionSuffixPriceDB, defaults)
	ns.db.mode = nil -- version 1 could also ask the server for the exact item; removed
	ns.db.version = DB_VERSION

	-- Blizzard's auction house UI loads the first time an auctioneer is opened.
	EventUtil.ContinueOnAddOnLoaded("Blizzard_AuctionHouseUI", function()
		ns.Attach(AuctionHouseFrame)
	end)
end

frame:SetScript("OnEvent", function(_, event, ...)
	events[event](...)
end)
for event in pairs(events) do
	frame:RegisterEvent(event)
end

SLASH_AUCTIONSUFFIXPRICE1 = "/asp"
SLASH_AUCTIONSUFFIXPRICE2 = "/auctionsuffixprice"
SlashCmdList.AUCTIONSUFFIXPRICE = function(input)
	local command = strtrim(input or ""):lower()
	if command == "debug" then
		ns.db.debug = not ns.db.debug
		ns.Print("debug", ns.db.debug and "on" or "off")
	elseif command == "clear" then
		wipe(ns.db.log)
		ns.Print("diagnostic log cleared.")
	else
		ns.Print("on the auction house Sell tab, random-suffix items are priced and listed against the same suffix.")
		ns.Print("/asp clear - empty the diagnostic log")
		ns.Print("/asp debug - toggle debug output")
	end
end
