local _, ns = ...

-- Blizzard's Sell tab looks up equipment by item ID alone, so the list and the suggested
-- price mix every random suffix of the item. This file makes both follow the suffix of the
-- item being sold.
--
-- Blizzard's query and results are left as they are. The list's data provider is wrapped so
-- that it skips other variants, and the cheapest matching auction is selected through the
-- list's own selection, which fills in the price. Unticking the checkbox shows every
-- variant; the suggested price still only ever comes from a matching auction.
--
-- Asking the server for the exact item instead (the Buy tab's search) was built and tested
-- in game on 2026-11-25. It worked, but cost a search per toggle and a visible wait, and
-- rewrote the item key Blizzard displays, for no gain. See kb/01-forever-essentials.md.

local MAX_ROWS = 2000 -- stop asking for further result pages beyond this
local SAMPLE_ROWS = 12

local attachedTo, sellFrame, list
local origGetEntry, origGetNumEntries
local map, mapDirty = {}, true
local sold -- what the list is being compared against; see describeSold
local auto = false -- the price is still ours to suggest (the user has not chosen one)
local inBlizzardSelect, ownSelect = false, false
local lastSignature

ns.state = { active = false, filtering = false, total = 0, matching = 0, other = 0, unknown = 0, full = true }

function ns.GetSold()
	return sold
end

local function describeSold(location)
	local key = C_AuctionHouse.GetItemKeyFromItem(location)
	if not key then
		return nil
	end
	local info = C_AuctionHouse.GetItemKeyInfo(key)
	local link = C_Item.GetItemLink(location)
	local name = ns.NameFromLink(link) or C_Item.GetItemName(location)
	local baseName = C_Item.GetItemNameByID(key.itemID)
	return {
		itemID = key.itemID,
		level = key.itemLevel or 0,
		suffix = key.itemSuffix or 0,
		name = name,
		baseName = baseName,
		suffixText = ns.SuffixText(name, baseName),
		isEquipment = info and info.isEquipment or false,
		vendorPrice = link and select(11, C_Item.GetItemInfo(link)) or nil,
		link = link,
	}
end

-- After a post the slot is empty but the list still shows the item just sold; keep
-- comparing against it until another item replaces it.
local function refreshSold()
	local location = sellFrame:GetItem()
	if location and location:IsValid() then
		sold = describeSold(location)
	else
		local key = sellFrame.listDisplayedItemKey
		if not (sold and key and key.itemID == sold.itemID) then
			sold = nil
		end
	end
end

local function hasItem()
	local location = sellFrame:GetItem()
	return location ~= nil and location:IsValid() and true or false
end

local function logResults(key, count, summary)
	local state = ns.state
	local signature = table.concat({
		key.itemID,
		key.itemSuffix or 0,
		summary.total,
		summary.matching,
		summary.other,
		summary.unknown,
		tostring(state.full),
	}, ":")
	if signature == lastSignature then
		return
	end
	lastSignature = signature

	-- One row per distinct variant is what tells us how the client labels them.
	local samples, seen = {}, {}
	for index = 1, count do
		local row = C_AuctionHouse.GetItemSearchResultInfo(key, index)
		if row and row.itemKey then
			local name = ns.NameFromLink(row.itemLink)
			local variant = (row.itemKey.itemSuffix or 0) .. ":" .. tostring(name)
			if not seen[variant] then
				seen[variant] = true
				samples[#samples + 1] = {
					suffix = row.itemKey.itemSuffix,
					level = row.itemKey.itemLevel,
					name = name,
					buyout = row.buyoutAmount,
					link = row.itemLink,
					verdict = tostring(ns.RowMatches(row, sold)),
				}
				if #samples >= SAMPLE_ROWS then
					break
				end
			end
		end
	end
	ns.Log("results", {
		keySuffix = key.itemSuffix,
		keyLevel = key.itemLevel,
		total = summary.total,
		matching = summary.matching,
		other = summary.other,
		unknown = summary.unknown,
		full = state.full,
		best = summary.best and summary.best.buyoutAmount or nil,
		samples = samples,
	})
end

-- Selecting a row is how Blizzard's own suggestion sets the price, so we do the same.
local function suggestPrice(best)
	local priceInput = sellFrame.PriceInput
	local selected = list:GetSelectedEntry()
	if best then
		local price = best.buyoutAmount or 0
		if selected and selected.auctionID == best.auctionID and (priceInput:GetAmount() or 0) == price then
			return
		end
		ownSelect = true
		list:SetSelectedEntry(best)
		ownSelect = false
		ns.Log("pick", { price = best.buyoutAmount, bid = best.bidAmount, auctionID = best.auctionID })
	else
		-- Nothing comparable is listed: do not leave another variant's price in the box.
		if selected and not selected.isVirtualEntry then
			ownSelect = true
			list:SetSelectedEntry(nil)
			ownSelect = false
		end
		local default = sellFrame:GetDefaultPrice() or 0
		if (priceInput:GetAmount() or 0) ~= default then
			priceInput:SetAmount(default)
			sellFrame:SetSearchResultPrice(nil)
			ns.Log("pick", { price = default, reason = "no matching auction" })
		end
	end
end

-- Brings the state, the suggested price, the list and the panel in line with what the
-- client currently holds. Safe to call at any time and any number of times.
function ns.Update()
	if not sellFrame then
		return
	end
	refreshSold()
	local state = ns.state
	local key = sellFrame.listDisplayedItemKey
	mapDirty = true

	if not (sold and sold.isEquipment and key) then
		state.active, state.filtering = false, false
		state.total, state.matching, state.other, state.unknown, state.full = 0, 0, 0, 0, true
	else
		local count = C_AuctionHouse.GetNumItemSearchResults(key) or 0
		local summary = ns.Summarize(function(index)
			return C_AuctionHouse.GetItemSearchResultInfo(key, index)
		end, count, sold)
		state.total, state.matching, state.other, state.unknown = summary.total, summary.matching, summary.other, summary.unknown
		state.full = C_AuctionHouse.HasFullItemSearchResults(key) and true or false
		-- Only items that come in variants get any of this; everything else is left alone.
		state.active = sold.suffix ~= 0 or summary.other > 0
		state.filtering = state.active and ns.db.onlyMatching
		logResults(key, count, summary)

		if state.active and auto and hasItem() and C_AuctionHouse.ShouldAutoPopulatePrice() then
			suggestPrice(summary.best)
		end
	end

	list:DirtyScrollFrame()
	if ns.UpdatePanel then
		ns.UpdatePanel()
	end
end

-- Blizzard fetches the next page only when the last rows scroll into view. A cheaper
-- matching auction may be on a later page, and a filtered list may never scroll.
local function requestMore()
	local state = ns.state
	local key = sellFrame.listDisplayedItemKey
	if state.active and key and not state.full and state.total > 0 and state.total < MAX_ROWS then
		C_AuctionHouse.RequestMoreItemSearchResults(key)
	end
end

function ns.SetOnlyMatching(enabled)
	ns.db.onlyMatching = enabled and true or false
	ns.Log("toggle", { onlyMatching = ns.db.onlyMatching })
	ns.Update()
end

local function rebuildMap()
	wipe(map)
	for index = 1, origGetNumEntries() or 0 do
		local row = origGetEntry(index)
		-- Rows we cannot judge stay visible; so does Blizzard's "none available" line.
		if row and (row.isVirtualEntry or ns.RowMatches(row, sold) ~= false) then
			map[#map + 1] = index
		end
	end
	mapDirty = false
end

local function getNumEntries()
	if not ns.state.filtering then
		return origGetNumEntries()
	end
	if mapDirty then
		rebuildMap()
	end
	return #map
end

local function getEntry(index)
	if not ns.state.filtering then
		return origGetEntry(index)
	end
	if mapDirty then
		rebuildMap()
	end
	local source = map[index]
	return source and origGetEntry(source) or nil
end

-- Wraps whatever provider the list has, so anything set before us keeps working underneath.
local function wrapProvider()
	if not list.getEntry or list.getEntry == getEntry then
		return
	end
	origGetEntry, origGetNumEntries = list.getEntry, list.getNumEntries
	list:SetDataProvider(list.searchStartedFunc, getEntry, getNumEntries, list.hasFullResultsFunc)
end

local function onResults()
	if sellFrame and sellFrame:IsShown() then
		ns.Update()
		requestMore()
	end
end

local function logEvent(event)
	return function(...)
		if sellFrame and sellFrame:IsShown() then
			ns.Log("event", { event = event, arg = ... })
		end
	end
end

function ns.Attach(frame)
	if not frame or frame == attachedTo then
		return
	end
	attachedTo, sellFrame, list = frame, frame.ItemSellFrame, frame.ItemSellList
	origGetEntry, origGetNumEntries, sold, lastSignature = nil, nil, nil, nil
	auto, mapDirty = false, true

	hooksecurefunc(sellFrame, "InitializeItemSellList", wrapProvider)
	wrapProvider()

	hooksecurefunc(sellFrame, "SetItem", function(_, itemLocation)
		if itemLocation ~= nil then
			auto = true
		end
		refreshSold()
		lastSignature = nil
		if sold then
			ns.Log("item", {
				itemID = sold.itemID,
				level = sold.level,
				suffix = sold.suffix,
				name = sold.name,
				baseName = sold.baseName,
				isEquipment = sold.isEquipment,
				vendorPrice = sold.vendorPrice,
				link = sold.link,
				placed = itemLocation ~= nil,
				onlyMatching = ns.db.onlyMatching,
			})
		end
		ns.Update()
	end)

	-- Blizzard's suggestion starts by clearing the remembered price and ends in our hook
	-- below; a selection made in between is Blizzard's, any other one is the user's click.
	hooksecurefunc(sellFrame, "ClearSearchResultPrice", function()
		inBlizzardSelect = true
	end)
	hooksecurefunc(sellFrame, "UpdatePriceSelection", function()
		inBlizzardSelect = false
		ns.Update()
	end)
	hooksecurefunc(list, "SetSelectedEntry", function(_, rowData)
		if rowData and not ownSelect and not inBlizzardSelect then
			auto = false
		end
	end)
	local money = sellFrame.PriceInput.MoneyInputFrame
	for _, box in ipairs({ money.GoldBox, money.SilverBox, money.CopperBox }) do
		box:HookScript("OnTextChanged", function(_, userInput)
			if userInput then
				auto = false
			end
		end)
	end
	hooksecurefunc(sellFrame, "UpdatePostState", function()
		if ns.UpdatePanel then
			ns.UpdatePanel()
		end
	end)

	ns.RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED", onResults)
	ns.RegisterEvent("ITEM_SEARCH_RESULTS_ADDED", onResults)
	for _, event in ipairs({
		"AUCTION_HOUSE_AUCTION_CREATED",
		"AUCTION_HOUSE_POST_ERROR",
		"AUCTION_HOUSE_SHOW_ERROR",
	}) do
		ns.RegisterEvent(event, logEvent(event))
	end

	ns.CreatePanel(frame)
end
