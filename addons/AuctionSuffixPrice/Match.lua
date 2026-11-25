local _, ns = ...

-- Decides whether an auction is the same variant ("of Agility") as the item being sold,
-- and which matching auction is the cheapest. No frames and no state: everything here is
-- exercised by tests/smoke.lua.

function ns.NameFromLink(link)
	if type(link) ~= "string" then
		return nil
	end
	return link:match("|h%[(.-)%]|h")
end

-- "Superior Tunic of Agility" minus "Superior Tunic" is "of Agility".
function ns.SuffixText(name, baseName)
	if not name or not baseName or baseName == "" then
		return nil
	end
	if name:sub(1, #baseName + 1) == baseName .. " " then
		return name:sub(#baseName + 2)
	end
	return nil
end

-- true: same variant; false: a different one; nil: cannot tell (yet).
-- The item key's suffix is exact, so it decides when both sides have one. The item name
-- covers the case where a key arrives without its suffix.
function ns.RowMatches(row, sold)
	if not row or row.isVirtualEntry or not row.itemKey then
		return nil
	end
	local rowSuffix = row.itemKey.itemSuffix or 0
	local soldSuffix = sold.suffix or 0
	if rowSuffix ~= 0 and soldSuffix ~= 0 then
		return rowSuffix == soldSuffix
	end
	local rowName = ns.NameFromLink(row.itemLink)
	if rowName and sold.name then
		return rowName == sold.name
	end
	if rowSuffix == 0 and soldSuffix == 0 then
		return true
	end
	if soldSuffix == 0 then
		return false
	end
	return nil
end

-- Same ordering Blizzard uses for its own suggestion: lowest buyout, then lowest bid.
function ns.IsCheaper(a, b)
	if b == nil then
		return a ~= nil
	elseif a == nil then
		return false
	elseif a.buyoutAmount ~= nil and b.buyoutAmount ~= nil then
		return a.buyoutAmount < b.buyoutAmount
	elseif a.buyoutAmount ~= nil or b.buyoutAmount ~= nil then
		return a.buyoutAmount ~= nil
	elseif a.bidAmount ~= nil and b.bidAmount ~= nil then
		return a.bidAmount < b.bidAmount
	elseif a.bidAmount ~= nil or b.bidAmount ~= nil then
		return a.bidAmount ~= nil
	end
	return false
end

-- Counts the auctions getRow(1..count) by verdict and finds the cheapest matching one.
function ns.Summarize(getRow, count, sold)
	local summary = { total = 0, matching = 0, other = 0, unknown = 0, best = nil }
	for index = 1, count do
		local row = getRow(index)
		if row and not row.isVirtualEntry then
			summary.total = summary.total + 1
			local verdict = ns.RowMatches(row, sold)
			if verdict == true then
				summary.matching = summary.matching + 1
				if ns.IsCheaper(row, summary.best) then
					summary.best = row
				end
			elseif verdict == false then
				summary.other = summary.other + 1
			else
				summary.unknown = summary.unknown + 1
			end
		end
	end
	return summary
end
