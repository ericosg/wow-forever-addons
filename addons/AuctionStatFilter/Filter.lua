local _, ns = ...

-- Narrows Blizzard's own browse list instead of building a second one, so sorting, the
-- category tree, the built-in filters, favourites and buying all keep working as they are.
--
-- The minimums typed in the panel take effect when a search starts (Search button, Enter),
-- exactly like Blizzard's own filters: `applied` is the copy the current results were
-- filtered with, and editing the panel does not disturb a list the user is reading.
--
-- The browse frame keeps its rows in `browseResults`. After every update Blizzard makes to
-- that list we swap in the subset that meets the stat minimums. While a filter is applied
-- we also keep requesting result pages until the search is complete, so the filter covers
-- the whole search and not just the first page.

local REFILTER_DELAY = 0.2

local applied = {} -- minimums in force for the current search
local browseFrame
local unfiltered = {} -- every result of the current search, in server order
local filterApplied = false -- whether browseFrame.browseResults currently holds our subset
local refilterQueued = false

ns.status = { shown = 0, total = 0, pending = 0, complete = true, active = false, unapplied = false }

local function sameMinimums(a, b)
	for key, value in pairs(a) do
		if b[key] ~= value then
			return false
		end
	end
	for key, value in pairs(b) do
		if a[key] ~= value then
			return false
		end
	end
	return true
end

local function apply()
	if not browseFrame then
		return
	end
	local status = ns.status
	status.active = ns.HasMinimums(applied)
	status.unapplied = not sameMinimums(applied, ns.db.minimums)
	status.total = #unfiltered
	status.pending = 0
	status.complete = C_AuctionHouse.HasFullBrowseResults()

	if not status.active then
		status.shown = status.total
		if filterApplied then
			filterApplied = false
			browseFrame.browseResults = unfiltered
			browseFrame.ItemList:RefreshScrollFrame()
		end
	else
		local matches = {}
		for _, result in ipairs(unfiltered) do
			local stats = ns.GetStats(result.itemKey)
			if not stats then
				status.pending = status.pending + 1
			elseif ns.MeetsMinimums(stats, applied) then
				matches[#matches + 1] = result
			end
		end
		status.shown = #matches
		filterApplied = true
		browseFrame.browseResults = matches
		browseFrame.ItemList:RefreshScrollFrame()

		-- Blizzard only asks for the next page while rows are on screen near the end of the
		-- list. With few or no matches so far that never happens, so ask for it here.
		if not status.complete then
			C_AuctionHouse.RequestMoreBrowseResults()
		end
	end

	if ns.UpdatePanelStatus then
		ns.UpdatePanelStatus()
	end
	ns.Debug("filter applied:", status.shown, "of", status.total, "pending", status.pending)
end

-- Collapses bursts (item data arriving row by row) into one pass.
function ns.QueueRefilter()
	if refilterQueued then
		return
	end
	refilterQueued = true
	C_Timer.After(REFILTER_DELAY, function()
		refilterQueued = false
		apply()
	end)
end

-- Remembers a minimum for the next search; the list on screen is left as it is.
function ns.SetMinimum(key, value)
	ns.db.minimums[key] = (value and value > 0) and value or nil
	ns.status.unapplied = not sameMinimums(applied, ns.db.minimums)
	if ns.UpdatePanelStatus then
		ns.UpdatePanelStatus()
	end
end

-- Runs the auction house search, which picks up whatever is typed in the panel.
function ns.StartSearch()
	if AuctionHouseFrame and AuctionHouseFrame.SearchBar then
		AuctionHouseFrame.SearchBar:StartSearch()
	end
end

-- Clearing only reveals rows that are already loaded, so it takes effect at once.
function ns.ClearMinimums()
	wipe(ns.db.minimums)
	wipe(applied)
	if ns.RefreshPanelInputs then
		ns.RefreshPanelInputs()
	end
	ns.QueueRefilter()
end

function ns.AttachFilter()
	if browseFrame or not AuctionHouseFrame then
		return
	end
	browseFrame = AuctionHouseFrame.BrowseResultsFrame

	local function forgetResults()
		unfiltered = {}
		filterApplied = false
	end
	hooksecurefunc(browseFrame, "Reset", forgetResults)
	hooksecurefunc(browseFrame, "OnBrowseSearchStarted", function()
		forgetResults()
		wipe(applied)
		for key, value in pairs(ns.db.minimums) do
			applied[key] = value
		end
		ns.db.debugLog = {}
	end)

	-- Blizzard calls this with a list when a further page arrives, and with nothing when
	-- the whole result set was replaced.
	hooksecurefunc(browseFrame, "UpdateBrowseResults", function(_, addedBrowseResults)
		if addedBrowseResults then
			for _, result in ipairs(addedBrowseResults) do
				unfiltered[#unfiltered + 1] = result
			end
		else
			unfiltered = C_AuctionHouse.GetBrowseResults() or {}
		end
		filterApplied = false
		apply()
	end)

	local listener = CreateFrame("Frame")
	listener:RegisterEvent("ITEM_DATA_LOAD_RESULT")
	listener:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	listener:SetScript("OnEvent", function()
		if ns.status.pending > 0 and browseFrame:IsShown() then
			ns.QueueRefilter()
		end
	end)
end
