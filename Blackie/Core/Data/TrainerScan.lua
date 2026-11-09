-- Blackie.TrainerScan: read whatever trainer window the player has open.
-- Purpose: recipe discovery at source + rank availability, stored per trainer snapshot.

local Blackie = Blackie
if not Blackie or not Blackie.DB then return end

Blackie.TrainerScan = Blackie.TrainerScan or {}
local TS = Blackie.TrainerScan
local Compat, Util = Blackie.Compat, Blackie.Util

local RANK_SPELLS = { [2018] = true, [2019] = true, [2020] = true, [2021] = true }
local RANK_WORDS = { "apprentice", "journeyman", "expert", "artisan", "master" }

local function epoch()
	return time and time() or (GetTime and GetTime() or 0)
end

local function isRankRow(row)
	if row.spellID and RANK_SPELLS[row.spellID] then return true end
	local n = string.lower(row.name or "")
	for _, w in ipairs(RANK_WORDS) do
		if n:find(w) and n:find("blacksmith") then return true end
	end
	return false
end

-- Pull "Requires Blacksmithing (NN)" style skill requirements out of detail text.
local function requiredSkillFromText(text)
	if type(text) ~= "string" then return nil end
	return tonumber(text:match("%((%d+)%)"))
end

-- Main scan: assumes a trainer list is currently open.
function TS.scan(printResults)
	local rows, style = Compat.trainerScan()
	if not rows then
		Blackie:Print("trainer scan failed: no trainer window open. Talk to a blacksmith trainer, open their skill list, then run it again.")
		return nil
	end

	local map = Compat.mapInfoForPlayer() or {}
	local db = Blackie.DB()
	local entry = {
		ts = epoch(),
		zone = map.zoneText, mapID = map.mapID, x = map.x, y = map.y,
		style = style,
		ranks = {}, recipes = {}, other = {},
	}

	local RC = Blackie.RecipeCache
	for _, row in ipairs(rows) do
		if isRankRow(row) then
			entry.ranks[#entry.ranks + 1] = row
		else
			local req = requiredSkillFromText(row.detail) or requiredSkillFromText(row.subText)
			entry.recipes[#entry.recipes + 1] = row
			-- A trainer-listed recipe is a source discovery even when not yet in the API recipe list.
			if RC and row.name then
				RC.upsert({
					name = row.name, itemId = 0, recipeID = row.spellID,
					requiredSkill = req, reagents = {}, known = false, craftable = false,
				}, "trainer")
			end
		end
	end

	entry.count = #rows
	db.lastTrainer = entry

	if Blackie.DiscoveryLog then
		local DL = Blackie.DiscoveryLog
		for _, row in ipairs(entry.recipes) do
			DL.record("trainer", row.itemID, row.name, 1, row.spellID and ("spell:" .. row.spellID) or nil)
		end
	end

	if printResults ~= false then
		TS.report(entry)
	end
	return entry
end

function TS.report(entry)
	if not entry then return end
	Blackie:Print(format(
		"trainer scan (%s%s): %d services, %d recipe rows, %d rank rows",
		tostring(entry.style or "?"),
		entry.zone and format(" @ %s", entry.zone) or "",
		entry.count or 0, #(entry.recipes or {}), #(entry.ranks or {})
	))
	for _, r in ipairs(entry.ranks or {}) do
		Blackie:Print(format("  rank: %s%s", r.name, r.cost and format(" (cost %s)", tostring(r.cost)) or ""))
	end
	local shownMax = 10
	for i, r in ipairs(entry.recipes or {}) do
		if i > shownMax then
			Blackie:Print(format("  ... and %d more recipe rows", #entry.recipes - shownMax))
			break
		end
		Blackie:Print(format("  recipe: %s%s", r.name, r.detail and format(" — %s", r.detail) or ""))
	end
	if entry.mapID and Compat.mappinAvailable() then
		Blackie:Print("tip: this trainer gets mappinned in Plan/Shopping tabs once UI lands.")
	end
end

function TS.learnRank(index)
	local ok, a, b = Compat.learnTrainerService(index)
	if ok and a then
		Blackie:Print("rank purchase attempted (trainer window must stay open).")
		return true
	end
	Blackie:Print("rank purchase failed (index out of range, or trainer style mismatch).")
	return false
end
