-- Blackie.VendorScan: read the open merchant window, cache per-unit costs.
-- Costing later reads: bags -> vendorStock -> AH cache (hybrid pricing).

local Blackie = Blackie
if not Blackie or not Blackie.DB then return end

Blackie.VendorScan = Blackie.VendorScan or {}
local VS = Blackie.VendorScan
local Util = Blackie.Util

local MAX_AGE_DEFAULT = 60 * 60 * 24 * 7 -- 7 days is fine for vendor prices

local function epoch()
	return time and time() or (GetTime and GetTime() or 0)
end

local function normCost(cost)
	if type(cost) == "number" then return cost end
	if type(cost) == "string" then
		local c = cost:gsub("%s", "")
		if c:match("^%d+$") then return tonumber(c) end
		return Util.parseMoney(c)
	end
	return nil
end

-- Main scan: assumes a vendor window is currently open.
function VS.scan(printResults)
	local rows = Blackie.Compat.vendorScanNow()
	if not rows then
		Blackie:Print("vendor scan failed: no merchant window open. Open a shop, then run it again.")
		return nil
	end
	local db = Blackie.DB()
	db.vendorStock = db.vendorStock or {}
	local out = {}
	for _, row in ipairs(rows) do
		local unit = normCost(row.cost)
		unit = (unit or 0) / math.max(1, row.sub or 1)
		local e = {
			ts = epoch(),
			itemID = row.itemID,
			name = row.name,
			link = row.link,
			unitCost = unit,
			sub = row.sub or 1,
		}
		db.vendorStock[row.itemID] = e
		out[#out + 1] = e
	end
	db.lastVendor = { ts = epoch(), count = #out }

	if Blackie.DiscoveryLog then
		for _, e in ipairs(out) do
			Blackie.DiscoveryLog.record("vendor", e.itemID, e.name, e.sub, "unit:" .. tostring(e.unitCost) .. "c")
		end
	end

	if printResults ~= false then
		VS.report(out)
	end
	return out
end

function VS.priceFor(itemID, maxAge)
	local db = Blackie.DB()
	local e = db.vendorStock and db.vendorStock[itemID]
	if not e then return nil end
	local age = epoch() - (e.ts or 0)
	if age > (maxAge or MAX_AGE_DEFAULT) then return nil end
	return { unitCost = e.unitCost, name = e.name }
end

local function copperText(c)
	if not c then return "-" end
	return Util.money(math.floor(c))
end

function VS.report(rows)
	Blackie:Print(format("vendor scan: %d items stock-priced", #(rows or {})))
	local shownMax = 12
	for i, e in ipairs(rows or {}) do
		if i > shownMax then
			Blackie:Print(format("  ... and %d more", #rows - shownMax))
			break
		end
		Blackie:Print(format("  #%d itemID:%s %s = %s ea", i, tostring(e.itemID), e.name or "?", copperText(e.unitCost)))
	end
end
