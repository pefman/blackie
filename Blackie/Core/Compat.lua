-- Blackie.Compat
-- Feature-detection shim so the addon never hard-codes one API surface.
--
-- Documented API baseline (researched online 2026-11-09, encoded BEFORE probing):
--   * Forever shares Mainline WoW's UI architecture and "the vast majority of the
--     APIs available in 12.1.5" (Warcraft Wiki, Patch 1.60.1 API notes). So modern
--     Mainline names are tried FIRST in every shim below; 1.12-era classic globals
--     (GetTradeSkillInfo, GetTrainerServiceInfo, GetItemInfo...) are fallback
--     candidates only -- Mainline FrameXML was removed, so they may or may not
--     exist as shims (every use stays behind an exists() gate + persisted style).
--     Sources: warcraft.wiki.gg Patch_1.60.1/API_changes + API_changes/notes,
--     wowforeveraddons.com "Writing addons for WoW Forever", and the community
--     mainline UI source mirror (Gethe/wow-ui-source) for C_* signatures.
--   * Game type: "Camelot" is Forever's gameType; WOW_PROJECT_CAMELOT (18) exists
--     since build 70170 and the TOC accepts `## AllowLoadGameType: forever`.
--     Early beta had a bug where WOW_PROJECT_ID reported the retail value, so
--     Compat detects the client by version range + existence checks. Detection is
--     INFORMATIONAL ONLY -- no feature is gated on it.
--   * Midnight addon-disarmament is active in Forever: tainted code may hand
--     secret values to native APIs but ARITHMETIC/COMPARISON on them raises a Lua
--     error. Blackie never reads combat/health/aura numbers; numeric paths here
--     deal with itemIDs and cached prices only.
--   * FrameStrata on Blizzard frames can return a secret value (2026-10-08): UI
--     code must never call GetFrameStrata() on foreign frames; minimap and unit
--     frames were reskinned/reorganized in beta -- wrap such touches in pcall.
--   * Client updates: 1.60.1 -> 1.60.2 is the next patch; API surface can shift.
--     Re-run /blackie probe after every client update.
--
-- Runtime verification layer: the recipe-ENUMERATION surface and the exact AH query
-- surface are not documented for Forever; /blackie probe verifies them live and
-- the winning driver/style is persisted in BlackieDB.probe.
-- Pure Lua here (may be loaded in the offline test harness).

local Blackie = Blackie
local Util = Blackie.Util or {}
local Compat = {}
Blackie.Compat = Compat

-- ---------------------------------------------------------------------------
-- Lookup helpers
-- ---------------------------------------------------------------------------
function Compat.glob(dotName)
	local ns = _G
	for part in tostring(dotName):gmatch("[^%.]+") do
		if type(ns) ~= "table" then return nil end
		ns = ns[part]
		if ns == nil then return nil end
	end
	return ns
end

function Compat.exists(dotName)
	return Compat.glob(dotName) ~= nil
end

-- Compat.raw("C_Map.GetMapInfo", 1) -> ok, ...all return values...
function Compat.raw(dotName, ...)
	local fn = Compat.glob(dotName)
	if type(fn) ~= "function" then return false end
	return pcall(fn, ...)
end

function Compat.firstNumber(dotName, ...)
	local ok, v = Compat.raw(dotName, ...)
	if ok and type(v) == "number" then return v end
	return nil
end

-- ---------------------------------------------------------------------------
-- Persisted probe state
-- ---------------------------------------------------------------------------
local PERSISTED_KEYS = {
	"TRADESKILL_DRIVER", "ITEM_STYLE", "CONTAINER_STYLE", "AH_STYLE",
	"TRAINER_STYLE", "MERCHANT_FRAME", "MAP_STYLE", "GAIN_STYLE",
	"MAPPIN_OK", "DIFFICULTY_FIELD", "INTERFACE", "CLIENT_BUILD", "PROBE_VERSION",
}

function Compat.state()
	if not BlackieDB then BlackieDB = {} end
	BlackieDB.probe = BlackieDB.probe or {}
	return BlackieDB.probe
end

function Compat.set(key, value)
	Compat.state()[key] = value
end

function Compat.get(key)
	return Compat.state()[key]
end

function Compat.persist()
	local s = Compat.state()
	s.TRADESKILL_DRIVER = Compat.get("TRADESKILL_DRIVER")
	s.ITEM_STYLE = Compat.get("ITEM_STYLE")
	s.CONTAINER_STYLE = Compat.get("CONTAINER_STYLE")
	s.AH_STYLE = Compat.get("AH_STYLE")
	s.TRAINER_STYLE = Compat.get("TRAINER_STYLE")
	s.MERCHANT_FRAME = Compat.get("MERCHANT_FRAME")
	s.MAP_STYLE = Compat.get("MAP_STYLE")
	s.GAIN_STYLE = Compat.get("GAIN_STYLE")
	s.MAPPIN_OK = Compat.get("MAPPIN_OK")
	s.PROBE_VERSION = 1
end

-- SavedVariables are only trustworthy once ADDON_LOADED has fired (modern clients
-- assign them late). Restore persisted driver selections at that point.
if Blackie.Events then
	Blackie.Events.On("ADDON_LOADED", function(loaded) -- Dispatch passes world varargs only
		if loaded ~= "Blackie" then return end
		local s = Compat.state() or {}
		Compat.driver = s.TRADESKILL_DRIVER
		Compat.itemStyle = s.ITEM_STYLE
		Compat.containerStyle = s.CONTAINER_STYLE
		Compat.trainerStyle = s.TRAINER_STYLE
		Compat.merchantFrame = s.MERCHANT_FRAME
	end)
end

-- ---------------------------------------------------------------------------
-- Item info  (returns simple ref: {name, quality, sell, link, icon})
-- ---------------------------------------------------------------------------
local function refFromItemInfoObject(id)
	local class = Compat.glob("ItemInfo")
	if not class then return nil end
	local info
	if type(class.CreateFromItemID) == "function" then
		local ok, inst = pcall(class.CreateFromItemID, class, id)
		if ok and inst then info = inst end
	end
	if not info then
		local ok, inst = pcall(class, id)
		if ok and inst then info = inst end
	end
	if not info then return nil end
	local valid = true
	if type(info.isValid) == "function" then
		local okV, v = pcall(info.isValid, info)
		valid = okV and v ~= false
	elseif info.isValid ~= nil then
		valid = info.isValid ~= false
	end
	if not valid then return nil end
	local sell = Util.fieldVal(info, { "sellPrice", "sellingPrice", "vendorPrice", "sellPricePerQuantity", "sellPrice" })
	return {
		name = Util.fieldVal(info, { "name" }),
		quality = Util.fieldVal(info, { "quality", "qualityLevel" }),
		sell = (type(sell) == "number") and sell or nil,
		link = Util.fieldVal(info, { "itemLink", "link" }),
		icon = Util.fieldVal(info, { "iconID", "icon" }),
	}
end

local function refFromTuple(fn, id)
	-- works for both legacy GetItemInfo and C_Item.GetItemInfo tuple style
	local ok, name, link, quality, _ilvl, _req, _class, _sub, _subclass, _maxCount, _sp, _inv, icon, sell =
		Compat.raw(fn, id)
	if not ok or type(name) ~= "string" or name == "" then return nil end
	return {
		name = name,
		quality = (type(quality) == "number") and quality or nil,
		sell = (type(sell) == "number") and sell or nil,
		link = (type(link) == "string") and link or nil,
		icon = (type(icon) == "string" or type(icon) == "number") and icon or nil,
	}
end

local function refFromInstant(id)
	local ok, iname, ilink, iquality, _il, _rl, _c, _sb, _mc, _sp, _inv, iicon =
		Compat.raw("GetItemInfoInstant", id)
	if not ok or type(iname) ~= "string" or iname == "" then return nil end
	return { name = iname, quality = (type(iquality) == "number") and iquality or nil,
		sell = nil, link = (type(ilink) == "string") and ilink or nil,
		icon = (type(iicon) == "string" or type(iicon) == "number") and iicon or nil }
end

local ITEM_STYLE_CANDIDATES = {
	{ style = "tuple-C_Item", get = function(id)
		return refFromTuple("C_Item.GetItemInfo", id) or refFromTuple("C_Item.GetItemInfoInstant", id) end },
	{ style = "ItemInfo", get = refFromItemInfoObject },
	{ style = "tuple-legacy", get = function(id) return refFromTuple("GetItemInfo", id) end },
	{ style = "instant", get = refFromInstant },
}

function Compat.itemInfo(id)
	if not id or id == 0 then return nil end
	local startIdx = 1
	if Compat.itemStyle then
		for i, c in ipairs(ITEM_STYLE_CANDIDATES) do
			if c.style == Compat.itemStyle then startIdx = i break end
		end
	end
	for k = 0, #ITEM_STYLE_CANDIDATES - 1 do
		local c = ITEM_STYLE_CANDIDATES[((startIdx - 1 + k) % #ITEM_STYLE_CANDIDATES) + 1]
		local ref = c.get(id)
		if ref and ref.name then
			Compat.itemStyle = c.style
			Compat.set("ITEM_STYLE", c.style)
			return ref
		end
	end
	return nil
end

function Compat.countItem(itemId)
	if not itemId then return 0 end
	local n = Compat.firstNumber("C_Item.GetItemCount", itemId, true)
	if n ~= nil then return n end
	if _G.GetItemCount then
		local ok, v = pcall(GetItemCount, itemId, true)
		if ok and type(v) == "number" then return v end
	end
	return 0
end

function Compat.itemLink(itemId)
	local ref = Compat.itemInfo(itemId)
	if ref and ref.link then return ref.link end
	if itemId then
		local ok, link = Compat.raw("C_Item.GetItemLink", itemId, 0)
		if ok and type(link) == "string" and link ~= "" then return link end
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Spell helpers
-- ---------------------------------------------------------------------------
function Compat.spellName(spellID)
	if not spellID then return nil end
	local ok, v = Compat.raw("C_Spell.GetSpellName", spellID)
	if ok and type(v) == "string" and v ~= "" then return v end
	if _G.GetSpellName then
		local ok2, v2 = pcall(GetSpellName, spellID)
		if ok2 and type(v2) == "string" then return v2 end
	end
	return nil
end

function Compat.spellIsKnown(spellID)
	if not spellID then return false end
	local ok, known = Compat.raw("C_Spell.IsSpellKnown", spellID)
	if ok and type(known) == "boolean" then return known end
	ok, known = Compat.raw("IsSpellKnown", spellID)
	if ok and type(known) == "boolean" then return known end
	return false
end

function Compat.castSpell(spellID)
	local ok = Compat.raw("CastSpellByID", spellID, "player")
	if not ok then Compat.raw("CastSpell", spellID, "player") end
	return ok
end

-- ---------------------------------------------------------------------------
-- Current profession skill value
-- ---------------------------------------------------------------------------
function Compat.currentSkill()
	-- 1. modern direct call (retail Trade Skill Level API)
	if Compat.exists("C_TradeSkillUI.GetTradeSkillLevel") then
		local ok, lvl = Compat.raw("C_TradeSkillUI.GetTradeSkillLevel")
		if ok and type(lvl) == "number" and lvl >= 0 then return lvl end
	end
	-- 2. Classic-style: profession level hidden-spell ranks carry the skill cap
	local ranks = { 2018, 2019, 2020, 2021 }
	local best = 0
	for _, id in ipairs(ranks) do
		if Compat.spellIsKnown(id) then
			local ok, v = Compat.raw("C_Spell.GetSpellLevel", id)
			if not ok then
				ok, v = Compat.raw("GetSpellLevel", id)
			end
			if ok and type(v) == "number" and v <= 300 then best = math.max(best, v) end
		end
	end
	if best > 0 then return math.min(best, 300) end
	-- 3. no direct API found -- return the rank-spell estimate (0 = unknown)
	return best
end

-- ---------------------------------------------------------------------------
-- Trade skill recipe list (driver-selected)
-- ---------------------------------------------------------------------------
-- Build a normalized recipe row from a C_TradeSkillUI.GetRecipeInfo struct.
-- The struct itself is VERIFIED mainline API (recipeID / previousRecipeID /
-- nextRecipeID / unlockedRecipeLevel ... appear throughout Blizzard's own
-- Blizzard_Professions frames); the exact reagent/difficulty field spellings vary
-- across game eras, so candidates are merged defensively.
local function recipeFromCTSUInfo(recipeID)
	local okR, info = Compat.raw("C_TradeSkillUI.GetRecipeInfo", recipeID)
	if not okR or not info then return nil end
	local itemId = Util.fieldVal(info, { "itemId", "craftedItemID", "itemOutputID" }) or 0
	local name = Util.fieldVal(info, { "name", "recipeName", "craftedItemName" })
	local req = Util.fieldVal(info, { "requiredLevel", "requiredSkill", "skillLevel", "unlockedRecipeLevel" })
	local uses = Util.fieldVal(info, { "alternateReagents", "craftingReagents", "usesReagents", "reagents" })
	local reagents = {}
	if type(uses) == "table" then
		for _, r in ipairs(uses) do
			if type(r) == "table" then
				local rid = Util.fieldVal(r, { "itemID", "itemId" }) or 0
				local rc = Util.fieldVal(r, { "quantity", "reagentCount", "count", "amountRequired", "quantityRequired" }) or 0
				if rid and rid > 0 then reagents[#reagents + 1] = { itemId = rid, count = rc } end
			end
		end
	end
	return {
		name = name, itemId = itemId, recipeID = recipeID,
		requiredSkill = (type(req) == "number") and req or 0,
		reagents = reagents,
		difficult = info.difficult,
		known = info.isKnown, craftable = info.isCraftable,
	}
end

-- Modern (C_TradeSkillUI) enumeration. NOTE: the two names GetRecipeNumDisplayRecipes
-- and GetRecipeDisplayRecipe are UNVERIFIED candidates -- they have no wiki page and
-- zero hits in the mainline source mirror, but the probe flags them live (YES/--).
-- Second enumeration candidate (documented in older mainline eras):
-- C_TradeSkillUI.GetNumTradeSkills + GetTradeSkillInfo(i) -> recipeID.
local function scanCTSU()
	local out = {}
	local num = Compat.firstNumber("C_TradeSkillUI.GetRecipeNumDisplayRecipes")
	if num ~= nil then
		for i = 1, num do
			local okD, recipeID = Compat.raw("C_TradeSkillUI.GetRecipeDisplayRecipe", i, true, true)
			if not okD or not recipeID then break end
			local row = recipeFromCTSUInfo(recipeID)
			if row then out[#out + 1] = row end
		end
		if #out > 0 then return out end
	end
	num = Compat.firstNumber("C_TradeSkillUI.GetNumTradeSkills")
	if num ~= nil then
		for i = 1, num do
			local okD, recipeID = Compat.raw("C_TradeSkillUI.GetTradeSkillInfo", i)
			if not okD or not recipeID then break end
			local row = recipeFromCTSUInfo(recipeID)
			if row then out[#out + 1] = row end
		end
		if #out > 0 then return out end
	end
	return nil
end

local function scanClassic()
	local num = Compat.firstNumber("GetNumTradeSkills")
	if num == nil then return nil end
	local out = {}
	for i = 1, num do
		local okT, name, extra, skillLevel, iconFile = Compat.raw("GetTradeSkillInfo", i)
		if not okT or type(name) ~= "string" or name == "" then break end
		local reagents = {}
		local okR, numR = Compat.raw("GetNumTradeSkillReagents", i)
		if okR and type(numR) == "number" then
			for j = 1, numR do
				local okI, itemId, reagentCount = Compat.raw("GetTradeSkillReagentInfo", i, j)
				if okI and type(itemId) == "number" and itemId > 0 then
					reagents[#reagents + 1] = { itemId = itemId, count = reagentCount or 1 }
				end
			end
		end
		local spellID = nil
		local okS, sid = Compat.raw("GetTradeSkillSpellID", i) -- candidate; may not exist
		if okS and type(sid) == "number" then spellID = sid end
		out[#out + 1] = { name = name, itemId = 0, spellID = spellID, recipeID = nil,
			requiredSkill = (type(skillLevel) == "number") and skillLevel or 0,
			reagents = reagents, texture = iconFile }
	end
	return out
end

local function scanCProfessions()
	local numEntries = Compat.firstNumber("C_Professions.GetNumRecipeListEntries")
	if numEntries == nil then return nil end
	local out = {}
	for i = 1, numEntries do
		local okE, entry = Compat.raw("C_Professions.GetRecipeListEntry", i)
		if okE and entry then
			local recipeID = Util.fieldVal(entry, { "recipeID" })
			local okR, info = Compat.raw("C_Professions.GetRecipeInfo", recipeID)
			if okR and info then
				local itemId = Util.fieldVal(info, { "itemId", "craftedItemID" }) or 0
				local name = Util.fieldVal(info, { "name", "recipeName" })
				local req = Util.fieldVal(info, { "requiredLevel", "requiredSkill" })
				local uses = Util.fieldVal(info, { "usesReagents", "reagents" })
				local reagents = {}
				if type(uses) == "table" then
					for _, r in ipairs(uses) do
						if type(r) == "table" then
							local rid = Util.fieldVal(r, { "itemID" }) or 0
							local rc = Util.fieldVal(r, { "quantity" }) or 0
							if rid > 0 then reagents[#reagents + 1] = { itemId = rid, count = rc } end
						end
					end
				end
				out[#out + 1] = { name = name, itemId = itemId, recipeID = recipeID,
					requiredSkill = (type(req) == "number") and req or 0, reagents = reagents }
			end
		end
	end
	return out
end

function Compat.tsRecipes()
	if Compat.driver == "C_TradeSkillUI" then return scanCTSU() end
	if Compat.driver == "Classic.Tradeskill" then return scanClassic() end
	if Compat.driver == "C_Professions" then return scanCProfessions() end
	local attempts = {
		{ "C_TradeSkillUI", scanCTSU },
		{ "Classic.Tradeskill", scanClassic },
		{ "C_Professions", scanCProfessions },
	}
	for _, a in ipairs(attempts) do
		local out = a.scan()
		if out and #out > 0 then
			Compat.driver = a.driver
			Compat.set("TRADESKILL_DRIVER", a.driver)
			return out
		end
	end
	return nil
end

function Compat.tsScanAvailable()
	if Compat.driver then return true end
	return Compat.exists("C_TradeSkillUI.GetRecipeNumDisplayRecipes")
		or Compat.exists("C_TradeSkillUI.GetNumTradeSkills")
		or Compat.exists("GetNumTradeSkills")
		or Compat.exists("C_Professions.GetNumRecipeListEntries")
end

function Compat.recipeDifficultFlag(recipe)
	if recipe and recipe.recipeID and Compat.exists("C_TradeSkillUI.GetRecipeInfo") then
		local ok, info = Compat.raw("C_TradeSkillUI.GetRecipeInfo", recipe.recipeID)
		if ok and info then
			local v = Util.fieldVal(info, { "difficult" })
			if v ~= nil then return v end
		end
	end
	if recipe and recipe.spellID and Compat.exists("GetTradeSkillDifficulty") then
		local ok, d = Compat.raw("GetTradeSkillDifficulty", recipe.spellID)
		if ok and d ~= nil then return d end
	end
	if recipe and recipe.difficult ~= nil then return recipe.difficult end
	return nil
end

function Compat.castRecipe(recipe)
	if not recipe then return false end
	if recipe.spellID then return Compat.castSpell(recipe.spellID) end
	local link = recipe.itemLink
	if not link and recipe.itemId then link = Compat.itemLink(recipe.itemId) end
	if link and _G.CastSpellByName then
		-- open tradeskill UI approach is safer; double-click handled in UI
		return Compat.raw("CastSpellByName", recipe.name, "player")
	end
	return false
end

function Compat.openTradeskillUI()
	if _G.TradeSkillFrame then
		TradeSkillFrame:SetShown(true)
		return true
	end
	if Compat.raw("C_TradeSkillUI.OpenTradeSkill") then return true end
	if Compat.raw("C_Professions.OpenProfessionsFrame") then return true end
	return false
end

-- ---------------------------------------------------------------------------
-- Bags
-- ---------------------------------------------------------------------------
function Compat.bagCounts()
	if Compat.exists("C_Container.GetContainerNumSlots") or Compat.containerStyle == "C_Container" then
		local counts = {}
		for bag = 0, 4 do
			local ok, n = Compat.raw("C_Container.GetContainerNumSlots", bag)
			if ok and type(n) == "number" then
				for slot = 1, n do
					local okI, itemID = Compat.raw("C_Container.GetContainerItemID", bag, slot)
					if okI and type(itemID) == "number" and itemID > 0 then
						counts[itemID] = (counts[itemID] or 0) + 1
					end
				end
			end
		end
		Compat.containerStyle = "C_Container"
		Compat.set("CONTAINER_STYLE", "C_Container")
		return counts
	end
	if _G.GetContainerNumSlots then
		local counts = {}
		for bag = 0, 4 do
			local ok, n = Compat.raw("GetContainerNumSlots", bag)
			if ok and type(n) == "number" then
				for slot = 1, n do
					local link = nil
					local okL, l = Compat.raw("GetContainerItemLink", bag, slot)
					if okL then link = l end
					local id = link and Util.idFromLink(link)
					if not id then
						local okI, iid = Compat.raw("GetContainerItemID", bag, slot)
						if okI and type(iid) == "number" then id = iid end
					end
					if id then counts[id] = (counts[id] or 0) + 1 end
				end
			end
		end
		Compat.containerStyle = "legacy"
		Compat.set("CONTAINER_STYLE", "legacy")
		return counts
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Auction House (async)
-- ---------------------------------------------------------------------------
-- Always rebuilt fresh per -- load: a results table from a previous
-- session is dead after reload/relogin.
AHQueue = { pending = {}, inflight = 0, maxInFlight = 3, active = {}, seq = 0, style = nil, resultsTable = nil }

function AHQueue.init()
	if AHQueue.style then return AHQueue.style == "table" end
	local makeTable = Compat.glob("C_AuctionHouseService.MakeAuctionQueryTable")
	local queryFn = Compat.glob("C_AuctionHouseService.QueryAuctionItems")
	if makeTable and queryFn then
		local ok, tbl = pcall(makeTable)
		if ok and tbl then
			AHQueue.resultsTable = tbl
			AHQueue.style = "table"
			tbl:SetCallback("OnSuccess", function(_, results, callbackInfo)
				AHQueue:finish(callbackInfo, "success", results)
			end)
			tbl:SetCallback("OnError", function(_, code, msg, callbackInfo)
				AHQueue:finish(callbackInfo, "error", nil, tostring(msg))
			end)
			tbl:SetCallback("OnLoad", function() end)
			return true
		end
	end
	if queryFn then AHQueue.style = "no-table-api" else AHQueue.style = "unavailable" end
	return false
end

function AHQueue.enqueue(itemID, callback)
	local db = Blackie.DB()
	db.ahCache = db.ahCache or {}
	local entry = db.ahCache[itemID]
	if entry and type(entry.buy) == "number" and entry.ts then
		local age = (GetTime and GetTime() or 0) - entry.ts
		if age < 15 * 60 then
			callback(entry)
			return
		end
	end
	if not AHQueue.init() then
		callback({ status = "unavailable", ts = GetTime and GetTime() or 0 })
		return
	end
	table.insert(AHQueue.pending, { itemID = itemID, callbacks = { callback } })
	AHQueue.pump()
end

local function buildQueryOptions(itemID)
	-- Prefer a builder object when the client exposes one (newer retail style).
	for _, name in ipairs({ "C_AuctionHouseService.CreateAdvancedQueryByItem",
		"C_AuctionHouseService.MakeAdvancedQueryByItem" }) do
		local builder = Compat.glob(name)
		if builder then
			local ok, b = pcall(builder, itemID)
			if ok and b then return b end
		end
	end
	-- Otherwise the classic options table. Keep the field set conservative.
	return { itemID = itemID, exactMatch = true }
end

function AHQueue.pump()
	while AHQueue.inflight < AHQueue.maxInFlight and #AHQueue.pending > 0 do
		local q = table.remove(AHQueue.pending, 1)
		AHQueue.seq = AHQueue.seq + 1
		local queryId = tostring(q.itemID) .. "#" .. tostring(AHQueue.seq)
		q.queryId = queryId
		q.created = GetTime and GetTime() or 0
		AHQueue.active[queryId] = q
		local options = buildQueryOptions(q.itemID)
		local okQuery = Compat.raw("C_AuctionHouseService.QueryAuctionItems",
			options, AHQueue.resultsTable, 1, 0, true, queryId)
		if not okQuery then
			AHQueue.active[queryId] = nil
			-- Transient failure: fail the current batch but keep style detection intact
			-- so a later /blackie reprobe can try a different signature.
			AHQueue:finishStaleAll("query-call-failed")
			return
		end
		if Blackie.Events then Blackie.Events.After(25, function()
			if AHQueue.active[queryId] then
				AHQueue.active[queryId] = nil
				local e = { status = "timeout", ts = GetTime and GetTime() or 0, source = "ah" }
				if q.carryPrice then e.buy = q.carryPrice end
				for _, cb in ipairs(q.callbacks) do pcall(cb, e) end
				AHQueue.inflight = math.max(0, AHQueue.inflight - 1)
				AHQueue.pump()
			end
		end) end
	end
end

function AHQueue:finish(callbackInfo, status, results, message)
	local q = callbackInfo and AHQueue.active[callbackInfo]
	if not q then return end
	AHQueue.active[callbackInfo] = nil
	local db = Blackie.DB()
	db.ahCache = db.ahCache or {}
	local unit, avail
	if status == "success" and type(results) == "table" then
		for _, row in ipairs(results) do
			if type(row) == "table" then
				local price = Util.fieldVal(row, { "minAuctionPrice", "buyoutPrice", "currentBestBid", "startingBid", "price" })
				local perUnit = Util.fieldVal(row, { "minAuctionPricePerUnit", "unitBuyoutPrice" })
				local qty = Util.fieldVal(row, { "availableQuantity", "quantity" }) or 1
				if type(price) == "number" and price > 0 and qty > 0 then
					local u = perUnit or (price / qty)
					if not unit or u < unit then unit = u end
					avail = (avail or 0) + qty
				end
			end
		end
	end
	local e = { status = status, buy = unit, availableQuantity = avail, message = message,
		ts = GetTime and GetTime() or 0, source = "ah" }
	db.ahCache[q.itemID] = e
	for _, cb in ipairs(q.callbacks) do pcall(cb, e) end
	AHQueue.inflight = math.max(0, AHQueue.inflight - 1)
	AHQueue.pump()
end

function AHQueue:finishStaleAll(message)
	local stale = {}
	for _, q in pairs(AHQueue.active) do stale[#stale + 1] = q end
	for _, q in ipairs(AHQueue.pending) do stale[#stale + 1] = q end
	AHQueue.active = {}
	AHQueue.pending = {}
	AHQueue.inflight = 0
	local e = { status = "error", message = message, ts = GetTime and GetTime() or 0, source = "ah" }
	for _, q in ipairs(stale) do
		for _, cb in ipairs(q.callbacks) do pcall(cb, e) end
	end
end

function AHQueue.pendingCount()
	return #AHQueue.pending + AHQueue.inflight
end

-- ---------------------------------------------------------------------------
-- Trainers
-- ---------------------------------------------------------------------------
local function classicTrainerScan()
	if not Compat.exists("GetNumTrainerServices") then return nil end
	local num = Compat.firstNumber("GetNumTrainerServices")
	if num == nil then return nil end
	local out = {}
	for i = 1, num do
		local okT, name, hasIcon, icon, hasCost, costItemID, cost = Compat.raw("GetTrainerServiceInfo", i)
		if okT and type(name) == "string" and name ~= "" then
			local learnable = nil
			local okL, l = Compat.raw("IsTrainerServiceLearnable", i)
			if okL then learnable = l end
			local id = nil
			local okS, sid = Compat.raw("GetTrainerServiceItemID", i)
			if okS then id = sid end
			local subText = nil
			local okSub, st = Compat.raw("GetTrainerServiceSubText", i)
			if okSub then subText = st end
			local detail = nil
			local okD, d = Compat.raw("GetTrainerServiceDetail", i)
			if okD then detail = d end
			out[#out + 1] = { index = i, name = name, icon = icon, cost = cost, costItemID = costItemID,
				learnable = learnable, spellID = id, subText = subText, detail = detail }
		end
	end
	return out
end

local function ctrainerScan()
	if not Compat.exists("C_Trainer.numServices") then return nil end
	local num = Compat.firstNumber("C_Trainer.numServices")
	if num == nil then return nil end
	local out = {}
	for i = 1, num do
		local svc
		local okS, s = Compat.raw("C_Trainer.getTrainerServiceInfo", i)
		if okS then svc = s end
		if svc then
			out[#out + 1] = {
				index = i,
				name = Util.fieldVal(svc, { "name" }),
				icon = Util.fieldVal(svc, { "icon" }),
				cost = Util.fieldVal(svc, { "cost", "costs", "moneyCost" }),
				spellID = Util.fieldVal(svc, { "spellID", "spellId" }),
				subText = Util.fieldVal(svc, { "subText" }),
				detail = Util.fieldVal(svc, { "text", "detail" }),
				learnable = true,
			}
		end
	end
	return out
end

-- Docs-first order: Forever is mainline-family, C_Trainer is the documented
-- trainer surface. The classic GetTrainerService* globals were removed with
-- FrameXML and are kept as a gated fallback candidate only.
function Compat.trainerScan()
	local out = ctrainerScan()
	if out then
		Compat.trainerStyle = "C_Trainer"
		Compat.set("TRAINER_STYLE", "C_Trainer")
		return out
	end
	out = classicTrainerScan()
	if out then
		Compat.trainerStyle = "Classic.Trainer"
		Compat.set("TRAINER_STYLE", "Classic.Trainer")
		return out
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Map / pin
-- ---------------------------------------------------------------------------
function Compat.mapInfoForPlayer()
	local out = { style = nil }
	local mapID, style
	local ok, m = Compat.raw("C_Map.GetBestMapForUnit", "player")
	if ok and m then mapID, style = m, "C_Map" end
	if not mapID then
		ok, m = Compat.raw("C_PlayerPositioning.GetMapID")
		if ok and m then mapID, style = m, "C_PlayerPositioning" end
	end
	if not mapID then
		ok, m = Compat.raw("GetDisplayMapID")
		if ok and m then mapID, style = m, "classic" end
	end
	if not mapID then return nil end
	out.mapID = mapID
	out.style = style
	local okI, info = Compat.raw("C_Map.GetMapInfo", mapID)
	if okI and info then
		out.zoneText = Util.fieldVal(info, { "name", "mapName" }) or out.zoneText
	end
	if Compat.exists("C_Map.GetPlayerMapPosition") then
		local okP, pos = Compat.raw("C_Map.GetPlayerMapPosition", mapID, "player")
		if okP and pos and pos.x and pos.y then out.x, out.y = pos.x, pos.y end
	end
	if not out.x and Compat.exists("C_PlayerPositioning.GetPlayerMapPosition") then
		local okP, pos = Compat.raw("C_PlayerPositioning.GetPlayerMapPosition", mapID, "player")
		if okP and pos and pos.x and pos.y then out.x, out.y = pos.x, pos.y end
	end
	if not out.x and _G.GetPlayerMapPosition then
		local okP, x, y = Compat.raw("GetPlayerMapPosition", mapID, "player")
		if okP and x and y then out.x, out.y = x, y end
	end
	function out.pinCommand(x, y)
		return format("/mappin %s %.1f %.1f", mapID, (x or 0) * 100, (y or 0) * 100)
	end
	Compat.mapStyle = style
	Compat.set("MAP_STYLE", style)
	return out
end

function Compat.mappinAvailable()
	local v = Compat.get("MAPPIN_OK")
	if v ~= nil then return v end
	local ok = false
	if SlashCmdList and (SlashCmdList["MAPPIN"] or SlashCmdList["MAP_PIN"] or SlashCmdList["PIN"]) then
		ok = true
	end
	Compat.set("MAPPIN_OK", ok)
	return ok
end

-- ---------------------------------------------------------------------------
-- Merchant / vendor
-- ---------------------------------------------------------------------------
function Compat.guessMerchantFrame()
	if _G["G_MerchantFrame"] then return "G_MerchantFrame" end
	if _G["MerchantFrame"] then return "MerchantFrame" end
	if _G["SmallMerchantFrame"] then return "SmallMerchantFrame" end
	return nil
end

function Compat.vendorScanNow()
	local rows = {}
	local num = Compat.firstNumber("C_MerchantFrame.GetNumItems")
	if num ~= nil then
		for i = 1, num do
			local okI, id = Compat.raw("C_MerchantFrame.GetMerchantItemID", i)
			if okI and type(id) == "number" and id > 0 then
				local name = nil
				local sub = 1
				local okQ, q = Compat.raw("C_MerchantFrame.GetMerchantItemNumPurchaseItems", i)
				if okQ and type(q) == "number" and q > 0 then sub = q end
				local okC, cost = Compat.raw("C_MerchantFrame.GetMerchantItemCostInfo", i)
				if not okC then
					okC, cost = Compat.raw("GetMerchantItemCostInfo", i)
				end
				local okN, nm = Compat.raw("C_MerchantFrame.GetItemName", i)
				if okN then name = nm end
				rows[#rows + 1] = { itemID = id, sub = sub, cost = cost, name = name }
			end
		end
		if #rows > 0 then
			Compat.merchantFrame = "C_MerchantFrame"
			Compat.set("MERCHANT_FRAME", "C_MerchantFrame")
			return rows
		end
	end
	local frame = Compat.guessMerchantFrame()
	if _G.GetMerchantItemInfo and (frame == nil or (_G[frame] and frame)) then
		for i = 1, 12 do
			local okI, id = Compat.raw("GetMerchantItemID", i)
			if not okI then break end
			local sub = 1
			local okQ, q = Compat.raw("GetMerchantItemNumItems", i)
			if not okQ then okQ, q = Compat.raw("GetMerchantItemNumPurchaseItems", i) end
			if okQ and type(q) == "number" and q > 0 then sub = q end
			local okC, cost = Compat.raw("GetMerchantItemCostInfo", i)
			local link
			local okL, l = Compat.raw("GetMerchantItemLink", i)
			if okL then link = l end
			local idFromLink = link and Util.idFromLink(link)
			if (type(id) == "number" and id > 0) or idFromLink then
				rows[#rows + 1] = { itemID = id or idFromLink, sub = sub, cost = cost, link = link }
			end
		end
		if #rows > 0 then
			Compat.merchantFrame = frame or "GetMerchantItemInfo"
			Compat.set("MERCHANT_FRAME", Compat.merchantFrame)
			return rows
		end
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Learn a rank / recipe (best-effort, requires an open trainer UI context)
-- ---------------------------------------------------------------------------
function Compat.learnTrainerService(index)
	if Compat.trainerStyle == "C_Trainer" then
		return Compat.raw("C_Trainer.purchaseRecord", index) or Compat.raw("C_Trainer.buyTrainerService", index)
	end
	if _G.TrainerServiceBuy then
		return Compat.raw("TrainerServiceBuy", index)
	end
	return false
end

Compat.SKILL_GAIN_PATTERNS = {
	"Your (%a+) skill increases by %a?%s*(%d+)",
	"^(.+):? ? increases your skill by (%d+)",
	"The crafting skill of .*increases by (%d+)",
}

function Compat.gainFromChat(text)
	if type(text) ~= "string" then return nil end
	for _, pat in ipairs(Compat.SKILL_GAIN_PATTERNS) do
		local a, b = text:match(pat)
		if a and b then
			if tonumber(b) then return a, tonumber(b) end
			return nil, tonumber(a)
		end
	end
	return nil
end

-- Informational ONLY -- never gate functionality on game-type detection.
-- Documented: WOW_PROJECT_CAMELOT (18) exists since build 70170, but early beta
-- had a bug where WOW_PROJECT_ID reported the retail value, so the interface
-- version range (1.60.x -> 16001..) is the primary check and existence beats
-- hard-coded numbers. (TOC metadata `## AllowLoadGameType: forever` also works;
-- C_GameRules.IsGameRuleActive(Enum.GameRule.HardcoreRuleset...) detects RP/PvP.
function Compat.isForeverClient()
	local ok, _b, _v, _d, iface = Compat.raw("GetBuildInfo")
	if ok and type(iface) == "number" and iface >= 16000 and iface < 20000 then return true end
	local pid = rawget(_G, "WOW_PROJECT_ID")
	local camelot = rawget(_G, "WOW_PROJECT_CAMELOT")
	if camelot ~= nil and pid == camelot then return true end
	return false
end

function Compat.clientInfo()
	local ok, build, versionText, dateText, interfaceVersion = Compat.raw("GetBuildInfo")
	return {
		build = (ok and type(build) == "number") and build or nil,
		clientVersion = ok and type(versionText) == "string" and versionText or nil,
		buildDate = ok and type(dateText) == "string" and dateText or nil,
		interface = ok and type(interfaceVersion) == "number" and interfaceVersion or nil,
		forever = Compat.isForeverClient(),
	}
end
