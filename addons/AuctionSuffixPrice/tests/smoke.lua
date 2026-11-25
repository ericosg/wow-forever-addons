-- Offline scenario for tools/smoke.lua: a fake auction house holding one base item in three
-- suffixes, a miniature of Blizzard's sell frame and price list (ported from
-- Blizzard_AuctionHouseItemSellFrame.lua / ItemList.lua at 1.60.1.71091), and the real addon.
local t = ...
local env, ns = t.env, t.ns

local TUNIC = 9001
local AGILITY, MONKEY, STRENGTH = 14, 587, 17
local SUFFIX_NAMES = { [AGILITY] = "of Agility", [MONKEY] = "of the Monkey", [STRENGTH] = "of Strength" }
local VENDOR = 1855
local SILVER = 100

-- The fake server ---------------------------------------------------------------------------

local auctions = {} -- every auction of the item, any suffix
local nextAuctionID = 1
local sendSuffixInKeys = true -- false: result keys arrive without a suffix (the unverified case)
local sendLinks = true
local pageSize = 100
local held = {} -- key string -> { rows = all rows of the search, loaded = how many the client has }
local queries = {} -- what was sent, in order: "sell 9001:0:0", "search 9001:27:14"
local moreRequests = 0

local function addAuction(suffix, buyout)
	auctions[#auctions + 1] = { auctionID = nextAuctionID, suffix = suffix, buyout = buyout }
	nextAuctionID = nextAuctionID + 1
end

local function keyString(key)
	return key.itemID .. ":" .. (key.itemLevel or 0) .. ":" .. (key.itemSuffix or 0)
end

local function link(suffix)
	local name = "Superior Tunic" .. (suffix ~= 0 and (" " .. SUFFIX_NAMES[suffix]) or "")
	return "|cff1eff00|Hitem:" .. TUNIC .. "::::::::29:::::::::|h[" .. name .. "]|h|r"
end

local function runSearch(key, exact)
	local rows = {}
	for _, auction in ipairs(auctions) do
		if not exact or auction.suffix == key.itemSuffix then
			rows[#rows + 1] = auction
		end
	end
	table.sort(rows, function(a, b)
		return a.buyout < b.buyout
	end)
	held[keyString(key)] = { rows = rows, loaded = math.min(pageSize, #rows) }
end

local sellFrame, list, auctionFrame

-- Results reach the client as an event; Blizzard's sell frame and the addon both listen.
-- `addonFirst` covers both orders, since the client does not promise one.
local function deliver(event, key, addonFirst)
	local function blizzard()
		if event == "ITEM_SEARCH_RESULTS_UPDATED" then
			sellFrame:UpdatePriceSelection()
		end
		list:DirtyScrollFrame()
	end
	if addonFirst then
		t.fire(event, key)
		blizzard()
	else
		blizzard()
		t.fire(event, key)
	end
end

t.fake(env.C_AuctionHouse, "SendSellSearchQuery", function(key)
	queries[#queries + 1] = "sell " .. keyString(key)
	runSearch(key, false)
end)
t.fake(env.C_AuctionHouse, "SendSearchQuery", function(key)
	queries[#queries + 1] = "search " .. keyString(key)
	runSearch(key, true)
end)
t.fake(env.C_AuctionHouse, "GetNumItemSearchResults", function(key)
	local search = held[keyString(key)]
	return search and search.loaded or 0
end)
t.fake(env.C_AuctionHouse, "GetItemSearchResultInfo", function(key, index)
	local search = held[keyString(key)]
	local auction = search and index <= search.loaded and search.rows[index]
	if not auction then
		return nil
	end
	return { -- a fresh table per call, like the client
		auctionID = auction.auctionID,
		buyoutAmount = auction.buyout,
		itemKey = { itemID = TUNIC, itemLevel = 27, itemSuffix = sendSuffixInKeys and auction.suffix or 0 },
		itemLink = sendLinks and link(auction.suffix) or nil,
	}
end)
t.fake(env.C_AuctionHouse, "HasFullItemSearchResults", function(key)
	local search = held[keyString(key)]
	return search ~= nil and search.loaded >= #search.rows
end)
t.fake(env.C_AuctionHouse, "RequestMoreItemSearchResults", function(key)
	moreRequests = moreRequests + 1
	local search = held[keyString(key)]
	search.loaded = math.min(search.loaded + pageSize, #search.rows)
	return search.loaded >= #search.rows
end)
t.fake(env.C_AuctionHouse, "GetItemKeyFromItem", function(location)
	return { itemID = location.itemID, itemLevel = 27, itemSuffix = location.suffix }
end)
t.fake(env.C_AuctionHouse, "GetItemKeyInfo", function()
	return { isEquipment = true, isPet = false, isCommodity = false }
end)
t.fake(env.C_AuctionHouse, "ShouldAutoPopulatePrice", function()
	return true
end)
t.fake(env.C_Item, "GetItemLink", function(location)
	return link(location.suffix)
end)
t.fake(env.C_Item, "GetItemNameByID", function()
	return "Superior Tunic"
end)
t.fake(env.C_Item, "GetItemInfo", function()
	return "Superior Tunic", nil, 2, 27, 23, "Armor", "Leather", 1, "INVTYPE_CHEST", 1, VENDOR
end)
t.fake(env, "GetMoneyString", function(amount)
	return amount .. "c"
end)

-- Blizzard's frames, in miniature --------------------------------------------------------

local function editBox()
	local box = { hooks = {} }
	function box:HookScript(_, handler)
		self.hooks[#self.hooks + 1] = handler
	end
	return box
end

list = { ScrollBox = { callbacks = {} } }
function list.ScrollBox:RegisterCallback(_, callback, owner)
	self.callbacks[#self.callbacks + 1] = function(...)
		callback(owner, ...)
	end
end
function list:SetDataProvider(searchStartedFunc, getEntry, getNumEntries, hasFullResultsFunc)
	self.searchStartedFunc, self.getEntry, self.getNumEntries, self.hasFullResultsFunc =
		searchStartedFunc, getEntry, getNumEntries, hasFullResultsFunc
end
function list:SetSelectedEntry(rowData)
	if self.selectionCallback and not self.selectionCallback(rowData) then
		return
	end
	self.selectedRowData = rowData
end
function list:GetSelectedEntry()
	return self.selectedRowData
end
function list:DirtyScrollFrame() end

sellFrame = {
	PostButton = {},
	PriceInput = { amount = 0, MoneyInputFrame = { GoldBox = editBox(), SilverBox = editBox(), CopperBox = editBox() } },
}
function sellFrame.PriceInput:SetAmount(amount)
	self.amount = amount
	sellFrame:UpdatePostState()
end
function sellFrame.PriceInput:GetAmount()
	return self.amount
end
function sellFrame:IsShown()
	return true
end
function sellFrame:GetItem()
	return self.itemLocation
end
function sellFrame:GetSearchContext()
	return "SellItems"
end
function sellFrame:GetDefaultPrice()
	return self.itemLocation and math.ceil(VENDOR * 1.5 / SILVER) * SILVER or SILVER
end
function sellFrame:SetSearchResultPrice(price)
	self.searchResultPrice = price
end
function sellFrame:ClearSearchResultPrice()
	self.searchResultPrice = nil
end
function sellFrame:UpdatePostState() end
function sellFrame:OnSearchResultSelected(searchResult)
	if not searchResult then
		return
	end
	self.PriceInput:SetAmount(searchResult.buyoutAmount or 0)
	self:SetSearchResultPrice(searchResult.buyoutAmount)
end
function sellFrame:InitializeItemSellList()
	if self.initialized then
		return
	end
	self.initialized = true
	local onSelected = self.OnSearchResultSelected
	list.selectionCallback = function(rowData)
		onSelected(self, rowData)
		return true
	end
	list:SetDataProvider(function()
		return self.listDisplayedItemKey ~= nil
	end, function(index)
		return self.listDisplayedItemKey and env.C_AuctionHouse.GetItemSearchResultInfo(self.listDisplayedItemKey, index)
	end, function()
		return self.listDisplayedItemKey and env.C_AuctionHouse.GetNumItemSearchResults(self.listDisplayedItemKey) or 0
	end, function()
		return self.listDisplayedItemKey == nil or env.C_AuctionHouse.HasFullItemSearchResults(self.listDisplayedItemKey)
	end)
end
-- Green items: the cheapest auction of the whole list, whatever its suffix.
function sellFrame:GetBestEntry()
	if not self.itemLocation or not self.listDisplayedItemKey then
		return nil
	end
	local best
	for index = 1, env.C_AuctionHouse.GetNumItemSearchResults(self.listDisplayedItemKey) do
		local row = env.C_AuctionHouse.GetItemSearchResultInfo(self.listDisplayedItemKey, index)
		if not best or row.buyoutAmount < best.buyoutAmount then
			best = row
		end
	end
	return best
end
function sellFrame:UpdatePriceSelection()
	self:ClearSearchResultPrice()
	if self.listDisplayedItemKey and self.PriceInput:GetAmount() == self:GetDefaultPrice() then
		local best = self:GetBestEntry()
		if best then
			list:SetSelectedEntry(best)
		end
	end
end
function sellFrame:SetItem(itemLocation, _, refreshListWithPreviousItem)
	self.itemLocation = itemLocation
	self.PriceInput:SetAmount(self:GetDefaultPrice())
	local itemKey = itemLocation and env.C_AuctionHouse.GetItemKeyFromItem(itemLocation) or nil
	if refreshListWithPreviousItem and self.previousItemKey then
		itemKey = self.previousItemKey
	end
	if itemKey then
		itemKey.itemLevel, itemKey.itemSuffix = 0, 0 -- AuctionHouseUtil.ConvertItemSellItemKey
	end
	self.listDisplayedItemKey = itemKey
	if itemKey then
		auctionFrame:QueryItem(self:GetSearchContext(), itemKey, true)
	end
	self:UpdatePriceSelection()
	self.previousItemKey = itemKey
end

auctionFrame = { ItemSellFrame = sellFrame, ItemSellList = list }
function auctionFrame:QueryItem(_, itemKey, byItemID)
	if byItemID then
		env.C_AuctionHouse.SendSellSearchQuery(itemKey)
	else
		env.C_AuctionHouse.SendSearchQuery(itemKey)
	end
end

-- Helpers -------------------------------------------------------------------------------------

local function location(suffix)
	return {
		itemID = TUNIC,
		suffix = suffix,
		IsValid = function()
			return true
		end,
	}
end

local function shownPrices()
	local prices = {}
	for index = 1, list.getNumEntries() do
		prices[index] = list.getEntry(index).buyoutAmount
	end
	return table.concat(prices, ",")
end

local function panel()
	return ns.DescribePanel(ns.state, ns.GetSold(), sellFrame.PriceInput:GetAmount(), sellFrame.itemLocation ~= nil)
end

-- Places an item the way the game does and lets the search result arrive.
local function place(suffix, addonFirst)
	sellFrame:SetItem(location(suffix))
	deliver("ITEM_SEARCH_RESULTS_UPDATED", sellFrame.listDisplayedItemKey, addonFirst)
end

local function reset(onlyMatching)
	auctions, held, queries, moreRequests = {}, {}, {}, 0
	sendSuffixInKeys, sendLinks, pageSize = true, true, 100
	ns.db.onlyMatching = onlyMatching
end

-- The auction house from the screenshots: cheap other suffixes, two "of Agility" at 1g 12s 55c.
local function stockTunics()
	addAuction(STRENGTH, 1855)
	addAuction(STRENGTH, 3500)
	addAuction(MONKEY, 5055)
	addAuction(AGILITY, 11255)
	addAuction(AGILITY, 11255)
	addAuction(MONKEY, 13202)
	addAuction(AGILITY, 22260)
end

ns.Attach(auctionFrame)
sellFrame:InitializeItemSellList() -- first time the Sell tab is shown

-- Pure matching ---------------------------------------------------------------------------

local soldAgility = { suffix = AGILITY, name = "Superior Tunic of Agility", baseName = "Superior Tunic" }
local function row(suffix, name)
	return { itemKey = { itemID = TUNIC, itemSuffix = suffix }, itemLink = name and ("|Hitem:1|h[" .. name .. "]|h") or nil }
end
t.check(ns.SuffixText("Superior Tunic of Agility", "Superior Tunic") == "of Agility", "the suffix text is the name minus the base name")
t.check(ns.SuffixText("Superior Tunic", "Superior Tunic") == nil, "an item without a suffix has no suffix text")
t.check(ns.RowMatches(row(AGILITY), soldAgility) == true, "same suffix in the item key matches, even without a link")
t.check(ns.RowMatches(row(MONKEY), soldAgility) == false, "a different suffix in the item key does not match")
t.check(
	ns.RowMatches(row(0, "Superior Tunic of Agility"), soldAgility) == true,
	"a key without suffix falls back to the name: same name matches"
)
t.check(
	ns.RowMatches(row(0, "Superior Tunic of Strength"), soldAgility) == false,
	"a key without suffix falls back to the name: other name does not"
)
t.check(ns.RowMatches(row(0), soldAgility) == nil, "no suffix and no link yet: undecided, not a mismatch")
t.check(ns.RowMatches({ isVirtualEntry = true }, soldAgility) == nil, "Blizzard's 'none available' line is never judged")

-- Price and list -------------------------------------------------------------------------------

reset(true)
stockTunics()
place(AGILITY)
t.check(
	queries[1] == "sell 9001:0:0" and #queries == 1,
	"the addon sends no search of its own (got " .. table.concat(queries, " | ") .. ")"
)
t.check(
	sellFrame.PriceInput.amount == 11255,
	"the suggested price is the cheapest 'of Agility' (1g 12s 55c), not 18s 55c (got " .. sellFrame.PriceInput.amount .. ")"
)
t.check(shownPrices() == "11255,11255,22260", "the list shows only the three 'of Agility' auctions (got " .. shownPrices() .. ")")
t.check(
	panel().label == 'Only "of Agility"' and panel().count == "3 of 7 listings",
	"the panel reads: " .. panel().label .. " / " .. panel().count
)
local selected = list:GetSelectedEntry() -- two auctions tie at 1g 12s 55c; either is right
t.check(selected.buyoutAmount == 11255 and selected.itemKey.itemSuffix == AGILITY, "the cheapest matching auction is the selected row")

ns.SetOnlyMatching(false)
t.check(shownPrices() == "1855,3500,5055,11255,11255,13202,22260", "unticked, every variant is listed again (got " .. shownPrices() .. ")")
t.check(sellFrame.PriceInput.amount == 11255, "unticked, the price still comes from the same suffix")
t.check(panel().count == "3 of 7 match", "unticked, the count reads '" .. panel().count .. "'")
t.check(#queries == 1, "toggling sends nothing to the server")

-- Row decoration in the all-variants view
local function rowFrame()
	local frame = {}
	function frame:SetAlpha(alpha)
		self.alpha = alpha
	end
	function frame:CreateFontString()
		local text = {}
		function text:SetPoint() end
		function text:SetJustifyH() end
		function text:SetText(value)
			frame.text = value
		end
		return text
	end
	return frame
end
local first, fourth = rowFrame(), rowFrame()
list.ScrollBox.callbacks[1](first, 1)
list.ScrollBox.callbacks[1](fourth, 4)
t.check(first.alpha < 1 and first.text:find("of Strength", 1, true), "another variant's row is dimmed and labelled 'of Strength'")
t.check(fourth.alpha == 1 and fourth.text:find("of Agility", 1, true), "a matching row stays bright and is labelled 'of Agility'")
ns.SetOnlyMatching(true)
list.ScrollBox.callbacks[1](first, 1)
t.check(first.alpha == 1 and first.text == "", "in the matching-only view rows carry no label and are not dimmed")

-- The addon hearing the event before Blizzard's frame must end the same way
reset(true)
stockTunics()
place(AGILITY, true)
t.check(sellFrame.PriceInput.amount == 11255, "same price when the addon handles the result event before Blizzard does")

-- The user's own choice is not overridden by later results
sellFrame.PriceInput.MoneyInputFrame.SilverBox.hooks[1](nil, true) -- typed in the silver box
sellFrame.PriceInput.amount = 9900
addAuction(AGILITY, 8000)
env.C_AuctionHouse.SendSellSearchQuery(sellFrame.listDisplayedItemKey)
deliver("ITEM_SEARCH_RESULTS_UPDATED", sellFrame.listDisplayedItemKey)
t.check(sellFrame.PriceInput.amount == 9900, "a price the user typed survives new results")

reset(true)
stockTunics()
place(AGILITY)
ns.SetOnlyMatching(false)
list:SetSelectedEntry(list.getEntry(3)) -- the user clicks the 50s 55c "of the Monkey" row
deliver("ITEM_SEARCH_RESULTS_UPDATED", sellFrame.listDisplayedItemKey)
t.check(sellFrame.PriceInput.amount == 5055, "a row the user clicked keeps its price, even of another variant")
ns.SetOnlyMatching(true)

-- A new item starts suggesting again
place(MONKEY)
t.check(
	sellFrame.PriceInput.amount == 5055 and shownPrices() == "5055,13202",
	"placing 'of the Monkey' suggests and lists its own variant (got " .. shownPrices() .. ")"
)

-- No auction of this suffix at all
reset(true)
addAuction(STRENGTH, 1855)
addAuction(MONKEY, 5055)
place(AGILITY)
t.check(
	sellFrame.PriceInput.amount == sellFrame:GetDefaultPrice(),
	"with no 'of Agility' listed the price stays at Blizzard's default, not another variant's 18s 55c"
)
t.check(list:GetSelectedEntry() == nil and shownPrices() == "", "nothing is selected and the matching list is empty")
t.check(panel().note:find('No other "of Agility" is listed', 1, true), "the note says so: " .. panel().note)

-- Vendor price warning
sellFrame.PriceInput.amount = VENDOR
t.check(panel().note:find("At or below the vendor price", 1, true), "a buyout at the vendor price is flagged")
sellFrame.PriceInput.amount = VENDOR + 1
t.check(not panel().note:find("vendor price", 1, true), "one copper above the vendor price is not flagged")

-- The cheapest match is on a later page
reset(true)
for _ = 1, 5 do
	addAuction(STRENGTH, 2000)
end
addAuction(AGILITY, 9000)
pageSize = 3
place(AGILITY)
t.check(
	sellFrame.PriceInput.amount == sellFrame:GetDefaultPrice() and panel().note:find("Looking for", 1, true),
	"while pages are missing the price waits and the note says it is looking"
)
t.check(moreRequests == 1, "the next page was requested without the user scrolling")
deliver("ITEM_SEARCH_RESULTS_ADDED", sellFrame.listDisplayedItemKey)
t.check(
	sellFrame.PriceInput.amount == 9000,
	"the match found on the second page becomes the price (got " .. sellFrame.PriceInput.amount .. ")"
)
t.check(ns.state.full and moreRequests == 1, "no further pages are requested once the search is complete")

-- Keys without suffix: the name decides
reset(true)
stockTunics()
sendSuffixInKeys = false
place(AGILITY)
t.check(
	sellFrame.PriceInput.amount == 11255 and shownPrices() == "11255,11255,22260",
	"result keys without a suffix: names still give the right price and list"
)

-- Keys without suffix and no links yet: nothing is hidden, nothing is guessed
sendLinks = false
place(AGILITY)
t.check(shownPrices() == "1855,3500,5055,11255,11255,13202,22260", "rows that cannot be judged stay visible")
t.check(sellFrame.PriceInput.amount == sellFrame:GetDefaultPrice(), "and none of them is used as the price")

-- An item with no variants is left entirely to Blizzard
reset(true)
addAuction(0, 4000)
addAuction(0, 6000)
place(0)
t.check(
	ns.state.active == false and sellFrame.PriceInput.amount == 4000,
	"a plain item keeps Blizzard's behaviour and the panel stays hidden"
)

-- After a post Blizzard reloads the list for the item just sold, with an empty slot
reset(true)
stockTunics()
place(AGILITY)
sellFrame:SetItem(nil, nil, true)
deliver("ITEM_SEARCH_RESULTS_UPDATED", sellFrame.listDisplayedItemKey)
t.check(
	shownPrices() == "11255,11255,22260",
	"after posting, the reloaded list still shows only the sold variant (got " .. shownPrices() .. ")"
)
t.check(
	panel().note == "" and panel().count == "3 of 7 listings",
	"with the slot empty there is no note, and the count still reads '" .. panel().count .. "'"
)
t.check(#queries == 2 and queries[2] == "sell 9001:0:0", "only Blizzard's own searches were sent")

-- Diagnostic log
local kinds = {}
for _, entry in ipairs(ns.db.log) do
	kinds[entry.kind] = true
end
t.check(kinds.item and kinds.results and kinds.pick and kinds.toggle, "the diagnostic log recorded items, results, picks and toggles")
t.check(#ns.db.log <= 100, "the log is capped (" .. #ns.db.log .. " entries)")
