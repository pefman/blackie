-- Blackie.Costing: hybrid price resolution for reagents:
--   player bags (free) -> cached AH quote -> cached vendor stock -> unknown.
-- Async AH lookups go through AHQueue (15-min result cache lives in DB.ahCache).

local Blackie = Blackie
if not Blackie or not Blackie.DB then return end

Blackie.Costing = Blackie.Costing or {}
local CS = Blackie.Costing
local Compat, Util = Blackie.Compat, Blackie.Util

local AH_TTL = 15 * 60      -- same TTL AHQueue writes into db.ahCache
local BAG_SNAPSHOT_TTL = 5  -- seconds; bag scans are cheap but not free

local function epoch()
	return time and time() or (GetTime and GetTime() or 0)
end

-- ---------------------------------------------------------------------------
-- bags
-- ---------------------------------------------------------------------------
local bagSnapshot, bagSnapshotTS

function CS.bags(force)
	local now = epoch()
	if not force and bagSnapshot and (now - bagSnapshotTS) < BAG_SNAPSHOT_TTL then
		return bagSnapshot
	end
	local counts = Compat.bagCounts()
	if not counts then return nil end
	bagSnapshot, bagSnapshotTS = counts, now
	local db = Blackie.DB()
	db.lastBags = { ts = now, counts = counts }
	return counts
end

function CS.inBag(itemID)
	local b = CS.bags()
	return b and b[itemID] or 0
end

-- ---------------------------------------------------------------------------
-- AH (cache read + async enqueue)
-- ---------------------------------------------------------------------------
local function ahAvailable()
	return AHQueue ~= nil and AHQueue.style ~= "unavailable"
		or Compat.exists("C_AuctionHouseService.QueryAuctionItems")
end

function CS.ahCached(itemID)
	local db = Blackie.DB()
	local e = db.ahCache and db.ahCache[itemID]
	if not e or type(e.buy) ~= "number" then return nil end
	if (epoch() - (e.ts or 0)) > AH_TTL then return nil end
	return e
end

-- cb(unitPrice|nil, source) ; source in "ah" | "cached-ah" | nil
function CS.ahAsync(itemID, cb)
	local cached = CS.ahCached(itemID)
	if cached then
		cb(cached.buy, "cached-ah")
		return true
	end
	if not ahAvailable() then
		cb(nil, nil)
		return false
	end
	AHQueue.enqueue(itemID, function(entry)
		if entry and type(entry.buy) == "number" then
			cb(entry.buy, "ah")
		else
			cb(nil, entry and entry.status or nil)
		end
	end)
	return true
end

-- ---------------------------------------------------------------------------
-- vendor
-- ---------------------------------------------------------------------------
function CS.vendorPrice(itemID)
	if Blackie.VendorScan then
		local e = Blackie.VendorScan.priceFor(itemID)
		if e then return e.unitCost end
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- unified sync + async pricing
-- ---------------------------------------------------------------------------
-- Returns unitPrice, source ("bag" is NOT a unit price concept: bags are handled
-- by the solver as free inventory). Sources here: "cached-ah" | "ah" | "vendor" | nil
function CS.priceOf(itemID)
	local cached = CS.ahCached(itemID)
	if cached then return cached.buy, "cached-ah" end
	local v = CS.vendorPrice(itemID)
	if v then return v, "vendor" end
	return nil, nil
end

function CS.priceOfAsync(itemID, cb)
	local p, src = CS.priceOf(itemID)
	if p then cb(p, src) return end
	CS.ahAsync(itemID, cb)
end

-- Cost breakdown for a recipe row (tsRecipes shape: .reagents = {{itemId,count}}).
-- freeFromBags counted separately; unknown-priced reagents returned as missing.
function CS.recipeCost(recipe)
	local total, breakdown, missingUnits, fromBags = 0, {}, {}, {}
	for _, r in ipairs(recipe.reagents or {}) do
		local id, need = r.itemId, (r.count or 1)
		if not id or id <= 0 then
			missingUnits[need] = (missingUnits[need] or 0) + 1
		else
			local have = CS.inBag(id)
			local free = math.min(have, need)
			local remaining = need - free
			fromBags[id] = (fromBags[id] or 0) + free
			if remaining > 0 then
				local unit, src = CS.priceOf(id)
				breakdown[id] = { need = need, free = free, unit = unit, source = src }
				if unit then
					total = total + unit * remaining
				else
					missingUnits[remaining] = (missingUnits[remaining] or 0) + remaining
				end
			end
		end
	end
	return { total = total, breakdown = breakdown, missingUnits = missingUnits, fromBags = fromBags }
end

-- Report helper used by /blackie price <itemID>
function CS.reportItem(itemID)
	local p, src = CS.priceOf(itemID)
	local have = CS.inBag(itemID)
	if p then
		Blackie:Print(format("item %d in bags: %d | unit price: %s (%s)",
			itemID, have, Util.money(p), src))
		return
	end
	if not ahAvailable() then
		Blackie:Print(format("item %d: no cached price and AH unavailable; vendor window or trainer scan may help.", itemID))
		return
	end
	Blackie:Print(format("item %d in bags: %d | querying AH...", itemID, have))
	CS.ahAsync(itemID, function(unit, source)
		if unit then
			Blackie:Print(format("item %d: unit price %s (%s), quantity seen %s",
				itemID, Util.money(unit), tostring(source),
				"see db.ahCache"))
		else
			Blackie:Print(format("item %d: no price known (AH status: %s); stand at an AH or open the vendor for it.",
				itemID, tostring(source)))
		end
	end)
end
