local _, ns = ...

-- A small panel docked to the right edge of the auction house, visible with the browse
-- list: one "minimum" box per stat, a clear button and a line saying what the filter did.
-- Like Blizzard's own filters, the boxes apply when a search is run (Search, or Enter here).

local ROW_HEIGHT = 26
local PANEL_WIDTH = 170

local panel
local inputs = {}

function ns.UpdatePanelStatus()
	if not panel then
		return
	end
	local status = ns.status
	local text
	if status.unapplied then
		text = "|cffffd100Press Search to apply.|r"
	elseif not status.active then
		text = "No minimums set."
	else
		text = string.format("Showing %d of %d items.", status.shown, status.total)
		if status.pending > 0 then
			text = text .. string.format("\nReading %d more...", status.pending)
		end
		if not status.complete then
			text = text .. "\nMore results are still loading."
		end
	end
	panel.Status:SetText(text)
end

function ns.RefreshPanelInputs()
	for key, input in pairs(inputs) do
		local minimum = ns.db.minimums[key]
		input:SetText(minimum and tostring(minimum) or "")
	end
end

local function createRow(parent, stat, index)
	local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	label:SetPoint("TOPLEFT", 14, -36 - (index - 1) * ROW_HEIGHT)
	label:SetText(stat.label)

	local input = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	input:SetSize(44, 20)
	input:SetPoint("RIGHT", parent, "TOPRIGHT", -14, -42 - (index - 1) * ROW_HEIGHT)
	input:SetAutoFocus(false)
	input:SetNumeric(true)
	input:SetMaxLetters(4)
	input:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			ns.SetMinimum(stat.key, tonumber(self:GetText()))
		end
	end)
	input:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		ns.StartSearch()
	end)
	input:SetScript("OnEscapePressed", input.ClearFocus)
	inputs[stat.key] = input
end

function ns.CreatePanel()
	if panel or not AuctionHouseFrame then
		return
	end

	-- Child of the browse list so it shows and hides with it (Buy tab only).
	panel = CreateFrame("Frame", nil, AuctionHouseFrame.BrowseResultsFrame, "BackdropTemplate")
	panel:SetSize(PANEL_WIDTH, 36 + #ns.STATS * ROW_HEIGHT + 96)
	panel:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 2, -24)
	panel:SetFrameStrata("HIGH")
	panel:SetBackdrop({
		bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	panel:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
	panel:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
	panel:EnableMouse(true)

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	title:SetPoint("TOPLEFT", 14, -12)
	title:SetText("Minimum stats")

	for index, stat in ipairs(ns.STATS) do
		createRow(panel, stat, index)
	end

	local clear = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	clear:SetSize(PANEL_WIDTH - 28, 22)
	clear:SetPoint("TOPLEFT", 14, -40 - #ns.STATS * ROW_HEIGHT)
	clear:SetText(CLEAR_ALL)
	clear:SetScript("OnClick", ns.ClearMinimums)

	panel.Status = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	panel.Status:SetPoint("TOPLEFT", clear, "BOTTOMLEFT", 0, -8)
	panel.Status:SetPoint("RIGHT", -14, 0)
	panel.Status:SetJustifyH("LEFT")
	panel.Status:SetJustifyV("TOP")

	ns.RefreshPanelInputs()
	ns.UpdatePanelStatus()
end
