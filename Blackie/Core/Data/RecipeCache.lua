-- Blackie.RecipeCache: a persistent, API-built recipe store. No bundled data:
-- everything here is discovered from the client's own tradeskill/trainer APIs.
-- Profession-agnostic storage, but the first slice is Blacksmithing.

local Blackie = Blackie
if not Blackie or not Blackie.DB then return end

Blackie.RecipeCache = Blackie.RecipeCache or {}
local RC = Blackie.RecipeCache
local Compat, Util = Blackie.Compat, Blackie.Util

local PROFESSION = "Blacksmithing"

local function nowEpoch()
	local ok = time and time() or nil
	if ok then return ok end
	return GetTime and GetTime() or 0
end

local function cache()
	local db = Blackie.DB()
	db.recipeCache = db.recipeCache or {}
	db.recipeCache[PROFESSION] = db.recipeCache[PROFESSION] or {}
	return db.recipeCache[PROFESSION]
end

local function rowKey(r)
	if not r then return nil end
	if r.itemId and r.itemId > 0 then return "i" .. r.itemId end
	if r.recipeID and r.recipeID > 0 then return "r" .. tostring(r.recipeID) end
	if r.spellID and r.spellID > 0 then return "s" .. r.spellID end
	if type(r.name) == "string" and r.name ~= "" then return "n" .. r.name end
	return nil
end

function RC.profession() return PROFESSION end

function RC.count()
	local n = 0
	for _ in pairs(cache()) do n = n + 1 end
	return n
end

function RC.all()
	return cache()
end

function RC.get(keyOrItemID)
	if type(keyOrItemID) == "number" then keyOrItemID = "i" .. keyOrItemID end
	return cache()[keyOrItemID]
end

-- Merge one scan row into the persistent entry (never loses richer fields).
function RC.upsert(row, source)
	if not row then return nil end
	local c = cache()
	local key = rowKey(row)
	if not key then return nil end
	local old = c[key]
	local e = old or { key = key, firstSeen = nowEpoch() }
	if row.itemId and row.itemId > 0 then e.itemId = row.itemId end
	e.itemId = e.itemId or 0
	e.recipeID = row.recipeID or e.recipeID
	e.spellID = (row.spellID and row.spellID > 0 and row.spellID) or e.spellID
	e.name = row.name or e.name
	e.texture = row.texture or e.texture
	if type(row.requiredSkill) == "number" and row.requiredSkill > 0 then
		e.requiredSkill = row.requiredSkill
	end
	e.requiredSkill = e.requiredSkill or 0
	if row.reagents and next(row.reagents) then
		e.reagents = row.reagents
	end
	e.reagents = e.reagents or {}
	if row.difficult ~= nil then e.difficult = row.difficult end
	if row.known == true or row.craftable == true then e.seenKnown = true end
	e.source = e.source or source or "scan"
	e.lastScan = nowEpoch()
	c[key] = e
	return e
end

-- One pass over the currently visible tradeskill scan (UI may or may not be
-- open depending on driver; a nil result just means "nothing this pass").
function RC.upsertFromScan(silent)
	if not Compat.tsScanAvailable() then
		if not silent then Blackie:Print("recipe scan: no trade-scan API available yet (run /blackie probe)") end
		return false
	end
	local rows = Compat.tsRecipes()
	if not rows or #rows == 0 then
		if not silent then Blackie:Print("recipe scan: driver returned no recipes (open the tradeskill window, then /blackie rescan)") end
		return false
	end
	local added = 0
	for _, r in ipairs(rows) do
		RC.upsert(r, "scan")
		added = added + 1
	end
	RC.rebuildKnown(rows)
	if not silent then Blackie:Print(format("recipe scan: %d recipes merged from driver %s (total cached: %d)",
		added, tostring(Compat.driver), RC.count())) end
	return true
end

-- Mark known-ness from a fresh scan pass + the player spellbook.
function RC.rebuildKnown(scanRows)
	local p = Blackie.Profile()
	local c = cache()
	local seen = {}
	for _, r in ipairs(scanRows or {}) do
		local k = rowKey(r)
		if k and c[k] then
			seen[k] = true
			if r.known == true then c[k].known = true end
			if r.craftable == true then c[k].craftable = true end
		end
	end
	for k, e in pairs(c) do
		if not seen[k] then
			-- Not in this scan pass: fall back to spell knowledge where possible.
			if e.spellID then e.known = Compat.spellIsKnown(e.spellID) or e.known end
		end
		if e.known and e.itemId and e.itemId > 0 then
			p.known[e.itemId] = { ts = nowEpoch(), source = "spellbook" }
		end
	end
end

-- Recipes whose crafted item matches an itemID lookup (used by plan/UI).
function RC.byItemID(itemId)
	local c = cache()
	for _, e in pairs(c) do
		if e.itemId == itemId then return e end
	end
	return nil
end

-- Known-recipe map keyed by cache key (profile overlay + scan knowledge).
function RC.knownMap()
	local p = Blackie.Profile()
	local known = {}
	for k, e in pairs(cache()) do
		if e.known or e.seenKnown or (e.itemId and e.itemId > 0 and p.known[e.itemId]) then
			known[k] = true
		end
	end
	return known
end
