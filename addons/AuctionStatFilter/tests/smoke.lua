-- Offline scenario for tools/smoke.lua: fake auction results and tooltips, real addon code.
local t = ...
local env, ns = t.env, t.ns

local function line(text)
	return { leftText = text }
end

-- Tooltips as C_TooltipInfo.GetItemKey would return them, keyed by itemID * 1000 + suffix.
local tooltips = {
	[1001000] = { lines = { line("Plain Vest"), line("45 Armor"), line("+3 Stamina") } },
	[1002000] = { lines = { line("Scout Vest"), line("|cffffffff+6 Agility|r"), line("+2 Stamina") } },
	[1003014] = { lines = { line("Bandit Vest of the Monkey"), line("+4 Agility"), line("+4 Stamina"), line("+3 Agility") } },
	[1004000] = { lines = { line("Sage Robe"), line("+9 Intellect"), line("Equip: Increases something by 6.") } },
	[1005000] = { lines = { line(env.RETRIEVING_ITEM_INFO) } },
}
local requestedLoads = 0
local moreRequested = 0
local fullResults = true

t.fake(env.C_TooltipInfo, "GetItemKey", function(itemID, _, itemSuffix)
	return tooltips[itemID * 1000 + itemSuffix]
end)
local uncached = { [1005] = true }
t.fake(env.C_Item, "IsItemDataCachedByID", function(itemID)
	return not uncached[itemID]
end)
t.fake(env.C_Item, "RequestLoadItemDataByID", function()
	requestedLoads = requestedLoads + 1
end)
t.fake(env.C_AuctionHouse, "HasFullBrowseResults", function()
	return fullResults
end)
t.fake(env.C_AuctionHouse, "RequestMoreBrowseResults", function()
	moreRequested = moreRequested + 1
end)

local function result(itemID, suffix)
	return { itemKey = { itemID = itemID, itemLevel = 20, itemSuffix = suffix or 0 }, totalQuantity = 1, minPrice = 100 }
end
local firstPage = { result(1001), result(1002), result(1003, 14), result(1004), result(1005) }
t.fake(env.C_AuctionHouse, "GetBrowseResults", function()
	return firstPage
end)

local browse = env.AuctionHouseFrame.BrowseResultsFrame
t.fake(browse, "IsShown", function()
	return true -- the Buy tab is open
end)
local function shownIDs()
	local ids = {}
	for index, entry in ipairs(browse.browseResults) do
		ids[index] = entry.itemKey.itemID
	end
	return table.concat(ids, ",")
end

-- Parsing
local parsed = ns.ParseTooltipLines(tooltips[1003014].lines)
t.check(parsed.ITEM_MOD_AGILITY_SHORT == 7, "two agility lines on one item are summed (4 + 3 = 7)")
t.check(parsed.ITEM_MOD_STAMINA_SHORT == 4, "stamina is read alongside agility")
t.check(ns.ParseTooltipLines(tooltips[1002000].lines).ITEM_MOD_AGILITY_SHORT == 6, "colour codes around a stat line are ignored")
t.check(next(ns.ParseTooltipLines(tooltips[1001000].lines), "ITEM_MOD_STAMINA_SHORT") == nil, "'45 Armor' is not mistaken for a stat")
t.check(ns.ParseTooltipLines(tooltips[1005000].lines) == nil, "an item still being retrieved reports 'unknown', not 'no stats'")

-- Stands in for pressing Search: Blizzard announces the search, then delivers results.
local function search()
	browse:OnBrowseSearchStarted()
	browse:UpdateBrowseResults()
end

-- No minimums: Blizzard's list is left alone
wipe(ns.db.minimums)
search()
t.check(ns.status.active == false and ns.status.total == 5, "with no minimums the filter is inactive and sees all 5 results")

-- Typing a minimum changes nothing until a search is run
ns.SetMinimum("ITEM_MOD_AGILITY_SHORT", 6)
t.flushTimers("scenario")
t.check(ns.status.unapplied and ns.status.active == false, "typing a minimum does not touch the list; the panel says to press Search")

search()
t.check(shownIDs() == "1002,1003", "after Search, minimum 6 agility keeps exactly the two items with 6+ agility (got " .. shownIDs() .. ")")
t.check(ns.status.pending == 1 and requestedLoads > 0, "the item not yet cached is counted as pending and its data requested")
t.check(ns.status.unapplied == false, "nothing is waiting to be applied after the search")

-- A second minimum narrows further
ns.SetMinimum("ITEM_MOD_STAMINA_SHORT", 4)
search()
t.check(shownIDs() == "1003", "adding minimum 4 stamina leaves only the item meeting both (got " .. shownIDs() .. ")")

-- Item data arrives: a partial tooltip seen earlier must not have been held against it
uncached[1005] = nil
tooltips[1005000] = { lines = { line("Late Vest"), line("+10 Agility"), line("+10 Stamina") } }
t.fire("ITEM_DATA_LOAD_RESULT", 1005, true)
t.check(shownIDs() == "1003,1005", "an item whose data arrives later joins the list (got " .. shownIDs() .. ")")
t.check(ns.status.pending == 0, "nothing is pending afterwards")

-- A further page arrives while results are incomplete
fullResults = false
moreRequested = 0
tooltips[1006000] = { lines = { line("Page Two Vest"), line("+8 Agility"), line("+5 Stamina") } }
browse:UpdateBrowseResults({ result(1006) })
t.check(shownIDs() == "1003,1005,1006", "results from the next page are filtered and appended (got " .. shownIDs() .. ")")
t.check(moreRequested == 1, "while the search is incomplete the next page is requested")
fullResults = true

-- A new search starts from nothing
firstPage = { result(1001) }
search()
t.check(shownIDs() == "" and ns.status.total == 1, "a new search replaces the old results")

-- Clearing restores Blizzard's full list at once
ns.ClearMinimums()
t.flushTimers("scenario")
t.check(shownIDs() == "1001" and ns.status.active == false, "clearing the minimums shows every result again without a new search")

-- Debug log
ns.db.debug = true
tooltips[1007000] = { lines = { line("Logged Vest"), line("+1 Spirit") } }
firstPage = { result(1007) }
ns.SetMinimum("ITEM_MOD_SPIRIT_SHORT", 1)
search()
t.check(
	ns.db.debugLog and ns.db.debugLog[1] and ns.db.debugLog[1].lines[2] == "+1 Spirit",
	"with debug on, the tooltip read for each new item is logged"
)
ns.db.debug = false
ns.ClearMinimums()
t.flushTimers("scenario")
