local _, ns = ...

-- What the user sees on the Sell tab: a checkbox above the price list ("Only of Agility"),
-- a count beside it, a note under the Create Auction button, and, when every variant is
-- shown, each row's suffix with the other variants dimmed.

local DIMMED_ALPHA = 0.45
local RED, GREEN, GREY = "|cffff4040", "|cff40ff40", "|cff9d9d9d"

local list, sellFrame
local controls, check, label, count, note
local rowLabels = {} -- our text per list row frame; rows belong to Blizzard, so nothing is stored on them

-- The three texts of the panel, as a function of the state so that tests can read them.
-- `price` is the buyout typed in the form, `placed` whether an item is in the sell slot.
function ns.DescribePanel(state, sold, price, placed)
	local text = { label = "", count = "", note = "" }
	if not sold then
		return text
	end
	local what = sold.suffixText and ('"' .. sold.suffixText .. '"') or nil
	if state.active then
		text.label = what and ("Only " .. what) or "Only identical items"
		if state.filtering then
			text.count = string.format("%d of %d listings", state.matching + state.unknown, state.total)
		else
			text.count = string.format("%d of %d match", state.matching, state.total)
		end
		if not state.full then
			text.count = text.count .. ", loading..."
		end
	end
	if not placed then
		return text
	end
	local lines = {}
	if state.active and state.matching == 0 then
		if not state.full then
			lines[#lines + 1] = "Looking for other " .. (what or "identical") .. " listings..."
		elseif state.unknown > 0 then
			lines[#lines + 1] = "Still reading " .. state.unknown .. " listings..."
		else
			lines[#lines + 1] = "No other " .. (what or "identical item") .. " is listed. The price is yours to set."
		end
	end
	local vendor = sold.vendorPrice or 0
	if price > 0 and vendor > 0 and price <= vendor then
		lines[#lines + 1] = RED .. "At or below the vendor price (" .. GetMoneyString(vendor) .. ").|r"
	end
	text.note = table.concat(lines, "\n")
	return text
end

function ns.UpdatePanel()
	if not controls then
		return
	end
	local state = ns.state
	local location = sellFrame:GetItem()
	local placed = location ~= nil and location:IsValid() and true or false
	local text = ns.DescribePanel(state, ns.GetSold(), sellFrame.PriceInput:GetAmount() or 0, placed)
	controls:SetShown(state.active)
	check:SetChecked(ns.db.onlyMatching)
	label:SetText(text.label)
	count:SetText(GREY .. text.count .. "|r")
	note:SetText(text.note)
end

-- Runs for every row the list draws. `index` is the row's position in the list's provider.
local function decorateRow(_, rowFrame, index)
	local state, sold = ns.state, ns.GetSold()
	local text, alpha = nil, 1
	if state.active and sold and not state.filtering and type(index) == "number" and list.getEntry then
		local row = list.getEntry(index)
		local verdict = ns.RowMatches(row, sold)
		if verdict ~= nil then
			local name = ns.NameFromLink(row.itemLink)
			local suffix = ns.SuffixText(name, sold.baseName) or name or ""
			if verdict then
				text = GREEN .. suffix .. "|r"
			else
				text = GREY .. suffix .. "|r"
				alpha = DIMMED_ALPHA
			end
		end
	end
	rowFrame:SetAlpha(alpha)
	local rowLabel = rowLabels[rowFrame]
	if text and not rowLabel then
		rowLabel = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		rowLabel:SetPoint("RIGHT", -30, 0)
		rowLabel:SetJustifyH("RIGHT")
		rowLabels[rowFrame] = rowLabel
	end
	if rowLabel then
		rowLabel:SetText(text or "")
	end
end
ns.DecorateRow = decorateRow

function ns.CreatePanel(auctionFrame)
	list, sellFrame = auctionFrame.ItemSellList, auctionFrame.ItemSellFrame

	-- Child of the price list, so it shows and hides with it (item selling only). It sits in
	-- the strip above the column headers, left of Blizzard's "N Available" and refresh button.
	controls = CreateFrame("Frame", nil, list)
	controls:SetSize(250, 24)
	controls:SetPoint("BOTTOMLEFT", list, "TOPLEFT", 4, 4)

	check = CreateFrame("CheckButton", nil, controls, "UICheckButtonTemplate")
	check:SetSize(24, 24)
	check:SetPoint("LEFT")
	check:SetScript("OnClick", function(self)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		ns.SetOnlyMatching(self:GetChecked())
	end)
	check:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_AddNormalLine(GameTooltip, "Compare only with auctions of the same item, suffix included.", true)
		GameTooltip_AddNormalLine(GameTooltip, "Untick to see every variant. The suggested price always comes from the same suffix.", true)
		GameTooltip:Show()
	end)
	check:SetScript("OnLeave", GameTooltip_Hide)

	label = controls:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	label:SetPoint("LEFT", check, "RIGHT", 2, 0)
	count = controls:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	count:SetPoint("LEFT", label, "RIGHT", 8, 0)

	-- Its own frame, without a layoutIndex, so the sell form's vertical layout ignores it
	-- (Blizzard's Buyout Mode checkbox is attached the same way).
	local noteFrame = CreateFrame("Frame", nil, sellFrame)
	noteFrame:SetSize(300, 44)
	noteFrame:SetPoint("TOP", sellFrame.PostButton, "BOTTOM", 0, -10)
	note = noteFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	note:SetAllPoints()
	note:SetJustifyH("CENTER")
	note:SetJustifyV("TOP")

	list.ScrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnInitializedFrame, decorateRow, ns)

	ns.UpdatePanel()
end
