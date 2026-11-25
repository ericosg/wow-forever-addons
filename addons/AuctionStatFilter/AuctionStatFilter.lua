local ADDON, ns = ...

local DB_VERSION = 1
local defaults = {
	debug = false,
	-- Minimum value per stat key (see ns.STATS). Absent or 0 means "no requirement".
	minimums = {},
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
	print("|cff33ff99Auction Stat Filter|r:", ...)
end

function ns.Debug(...)
	if ns.db and ns.db.debug then
		ns.Print("|cff888888debug|r", ...)
	end
end

local frame = CreateFrame("Frame")
local events = {}

function events.ADDON_LOADED(name)
	if name ~= ADDON then
		return
	end
	frame:UnregisterEvent("ADDON_LOADED")
	if type(AuctionStatFilterDB) ~= "table" then
		AuctionStatFilterDB = {}
	end
	ns.db = applyDefaults(AuctionStatFilterDB, defaults)
	ns.db.version = DB_VERSION

	-- Blizzard's auction house UI loads the first time an auctioneer is opened.
	EventUtil.ContinueOnAddOnLoaded("Blizzard_AuctionHouseUI", function()
		ns.AttachFilter()
		ns.CreatePanel()
	end)
end

frame:SetScript("OnEvent", function(_, event, ...)
	events[event](...)
end)
for event in pairs(events) do
	frame:RegisterEvent(event)
end

SLASH_AUCTIONSTATFILTER1 = "/asf"
SlashCmdList.AUCTIONSTATFILTER = function(input)
	local command = strtrim(input or ""):lower()
	if command == "debug" then
		ns.db.debug = not ns.db.debug
		ns.Print("debug", ns.db.debug and "on" or "off")
	elseif command == "clear" then
		ns.ClearMinimums()
		ns.Print("all minimums cleared.")
	else
		ns.Print("open the auction house; the stat filter panel sits to the right of the Buy tab.")
		ns.Print("/asf clear - remove all minimums")
		ns.Print("/asf debug - toggle debug output")
	end
end
