local _, ns = ...

-- Reads an item's stats from the same tooltip the auction house shows when a browse row is
-- hovered (GameTooltip:SetItemKey). A browse row is an item *key* (item, level, random
-- suffix), not a single auction, and the tooltip is the one source that describes exactly
-- that key, including "of the Monkey"-style suffix stats.

-- Stats the panel offers, in display order. `key` is the global string holding the stat's
-- localized name, which is also how the stat is spelled on tooltip lines ("+6 Agility").
ns.STATS = {
	{ key = "ITEM_MOD_STRENGTH_SHORT" },
	{ key = "ITEM_MOD_AGILITY_SHORT" },
	{ key = "ITEM_MOD_STAMINA_SHORT" },
	{ key = "ITEM_MOD_INTELLECT_SHORT" },
	{ key = "ITEM_MOD_SPIRIT_SHORT" },
}

local DEBUG_LOG_LIMIT = 80

local keyByLabel = {}
for _, stat in ipairs(ns.STATS) do
	stat.label = _G[stat.key] or stat.key
	keyByLabel[stat.label:lower()] = stat.key
end

local cache = {}

local function cacheKey(itemKey)
	return itemKey.itemID .. ":" .. (itemKey.itemLevel or 0) .. ":" .. (itemKey.itemSuffix or 0)
end

-- Sums "+N Stat" lines into { [statKey] = total }. Returns nil while the client is still
-- fetching the item, so the caller can tell "no agility" from "not known yet".
function ns.ParseTooltipLines(lines)
	local stats = {}
	for index, line in ipairs(lines) do
		local text = line.leftText
		if type(text) == "string" and not issecretvalue(text) then
			text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
			if index == 1 and text == RETRIEVING_ITEM_INFO then
				return nil
			end
			local amount, label = text:match("^%+(%d+) (.+)$")
			local key = label and keyByLabel[strtrim(label):lower()]
			if key then
				stats[key] = (stats[key] or 0) + tonumber(amount)
			end
		end
	end
	return stats
end

-- Second source, for keys whose tooltip lists no stats: a link to one concrete auction of
-- this key, if the client has one.
local function statsFromSampleLink(itemKey)
	local link = C_AuctionHouse.GetItemKeySampleLink(itemKey)
	local all = link and C_Item.GetItemStats(link)
	if type(all) ~= "table" then
		return nil
	end
	local stats = {}
	for _, stat in ipairs(ns.STATS) do
		local amount = all[stat.key]
		if type(amount) == "number" and amount > 0 then
			stats[stat.key] = amount
		end
	end
	return stats
end

-- Keeps what was read for the first items of the current search in
-- AuctionStatFilterDB.debugLog, so a wrong result can be diagnosed from the saved file.
local function record(itemKey, tooltip, stats, source)
	local log = ns.db.debugLog
	-- Plain items without stats or suffix are the bulk of any search and say nothing.
	local informative = next(stats) ~= nil or (itemKey.itemSuffix or 0) ~= 0
	if not log or #log >= DEBUG_LOG_LIMIT or not informative then
		return
	end
	local lines = {}
	for index, line in ipairs(tooltip.lines) do
		if index > 14 then
			break
		end
		local text = line.leftText
		lines[index] = (type(text) == "string" and not issecretvalue(text)) and text or "?"
	end
	local found = {}
	for key, amount in pairs(stats) do
		found[#found + 1] = key .. "=" .. amount
	end
	log[#log + 1] = {
		key = cacheKey(itemKey),
		source = source,
		stats = table.concat(found, " "),
		sampleLink = C_AuctionHouse.GetItemKeySampleLink(itemKey),
		lines = lines,
	}
end

-- Stats for a browse result's item key, or nil if the item's data has not arrived yet
-- (ITEM_DATA_LOAD_RESULT / GET_ITEM_INFO_RECEIVED will follow; Filter.lua re-applies then).
function ns.GetStats(itemKey)
	local id = cacheKey(itemKey)
	if cache[id] then
		return cache[id]
	end

	-- Before the item is cached the client hands back a partial tooltip (a name and little
	-- else) that looks like an item without stats. Never judge an item on that.
	if not C_Item.IsItemDataCachedByID(itemKey.itemID) then
		C_Item.RequestLoadItemDataByID(itemKey.itemID)
		return nil
	end

	local requiredLevel = C_AuctionHouse.GetItemKeyRequiredLevel(itemKey)
	local tooltip = C_TooltipInfo.GetItemKey(itemKey.itemID, itemKey.itemLevel or 0, itemKey.itemSuffix or 0, requiredLevel)
	local stats = tooltip and tooltip.lines and ns.ParseTooltipLines(tooltip.lines)
	if not stats then
		C_Item.RequestLoadItemDataByID(itemKey.itemID)
		return nil
	end

	local source = "tooltip"
	if next(stats) == nil then
		local fromLink = statsFromSampleLink(itemKey)
		if fromLink and next(fromLink) ~= nil then
			stats, source = fromLink, "sample link"
		end
	end

	record(itemKey, tooltip, stats, source)
	cache[id] = stats
	return stats
end

-- True if `stats` meets every minimum above zero.
function ns.MeetsMinimums(stats, minimums)
	for key, minimum in pairs(minimums) do
		if minimum > 0 and (stats[key] or 0) < minimum then
			return false
		end
	end
	return true
end

function ns.HasMinimums(minimums)
	for _, minimum in pairs(minimums) do
		if minimum > 0 then
			return true
		end
	end
	return false
end
