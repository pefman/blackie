-- Blackie.APIProbe: the VERIFICATION layer. Compat already encodes the documented
-- WoW Forever API baseline (mainline 12.1.x surface -- see the Core/Compat.lua
-- header comment). This command confirms that baseline against a live client,
-- flags the names the docs do NOT cover (recipe enumeration, AH queries) with
-- YES/--, runs light runtime tests, and persists results in BlackieDB.probe.
-- Re-run after every client update (1.60.1 -> 1.60.2 is coming).
-- Run in game with:  /blackie probe        (adds runtime AH test: /blackie probe full)

local Blackie = Blackie
if not Blackie then return end

Blackie.APIProbe = Blackie.APIProbe or {}
local P = Blackie.APIProbe

local Compat = Blackie.Compat
local Util = Blackie.Util

-- API names the Compat shim depends on, grouped. Yes/-- lines get pasted back.
local CANDIDATES = {
	{ group = "ITEM", names = {
		"C_Item.GetItemCount", "C_Item.GetItemInfo", "C_Item.GetItemInfoInstant",
		"ItemInfo", "C_Item.GetItemLink",
		"GetItemInfo", "GetItemInfoInstant", "GetItemCount",
	} },
	-- C_TradeSkillUI.GetRecipeNumDisplayRecipes / GetRecipeDisplayRecipe are
	-- UNVERIFIED candidates (no wiki page, no mainline source-mirror hits); the
	-- rest of the C_TradeSkillUI block is documented mainline 12.1.x surface.
	{ group = "TRADE", names = {
		"C_TradeSkillUI.GetRecipeNumDisplayRecipes", "C_TradeSkillUI.GetRecipeDisplayRecipe",
		"C_TradeSkillUI.GetRecipeInfo", "C_TradeSkillUI.OpenTradeSkill",
		"C_TradeSkillUI.GetTradeSkillLevel", "C_TradeSkillUI.UpdateTradeSkills",
		"C_TradeSkillUI.GetNumTradeSkills", "C_TradeSkillUI.GetTradeSkillInfo",
		"C_TradeSkillUI.GetBaseProfessionInfo", "C_TradeSkillUI.GetChildProfessionInfo",
		"C_TradeSkillUI.GetTradeSkillTexture",
		"C_TradeSkillUI.GetRecipeInfoForSkillLineAbility", "C_TradeSkillUI.IsRecipeFavorite",
		"GetNumTradeSkills", "GetTradeSkillInfo", "GetNumTradeSkillReagents",
		"GetTradeSkillReagentInfo", "GetTradeSkillIcon", "GetTradeSkillDifficulty",
		"GetTradeSkillSpellID",
		"C_Professions.GetProfessions", "C_Professions.GetRecipeListEntries",
		"C_Professions.GetRecipeInfo", "C_Professions.OpenProfessionsFrame",
	} },
	{ group = "SPELL", names = {
		"C_Spell.GetSpellName", "C_Spell.GetSpellLevel", "C_Spell.IsSpellKnown",
		"C_Spell.CastSpell", "GetSpellName", "GetSpellLevel", "IsSpellKnown",
		"CastSpellByID", "CastSpell",
	} },
	{ group = "AH", names = {
		"C_AuctionHouseService.QueryAuctionItems",
		"C_AuctionHouseService.MakeAuctionQueryTable",
		"C_AuctionHouseService.CreateAdvancedQueryByItem",
		"C_AuctionHouseService.MakeAdvancedQueryByItem",
		"QueryAuctionItems", "MakeAuctionQueryTable",
	} },
	{ group = "BAGS", names = {
		"C_Container.GetContainerNumSlots", "C_Container.GetContainerItemLink",
		"C_Container.GetContainerItemID", "GetContainerNumSlots",
		"GetContainerItemLink", "GetContainerItemID",
	} },
	{ group = "MAP", names = {
		"C_Map.GetBestMapForUnit", "C_Map.GetMapInfo", "C_Map.GetPlayerMapPosition",
		"C_PlayerPositioning.GetMapID", "C_PlayerPositioning.GetPlayerMapPosition",
		"GetPlayerMapPosition", "GetDisplayMapID",
	} },
	{ group = "TRAINER", names = {
		"GetNumTrainerServices", "GetTrainerServiceInfo", "GetTrainerServiceItemID",
		"GetTrainerServiceSubText", "GetTrainerServiceDetail", "IsTrainerServiceLearnable",
		"TrainerServiceBuy",
		"C_Trainer.numServices", "C_Trainer.getTrainerServiceInfo",
		"C_Trainer.purchaseRecord", "C_Trainer.buyTrainerService",
	} },
	{ group = "MERCHANT", names = {
		"C_MerchantFrame.GetNumItems", "C_MerchantFrame.GetMerchantItemID",
		"C_MerchantFrame.GetMerchantItemNumPurchaseItems",
		"C_MerchantFrame.GetMerchantItemCostInfo", "C_MerchantFrame.GetItemName",
		"GetMerchantItemID", "GetMerchantItemInfo", "GetMerchantItemLink",
		"GetMerchantItemCostInfo",
	} },
}

-- UI frames whose presence tells us which Blizzard UI packages are loaded.
local FRAMES = {
	"TradeSkillFrame", "ProfessionsFrame", "SkillFrame", "MerchantFrame",
	"G_MerchantFrame", "AuctionFrame", "TrainerFrame", "Minimap",
}

-- Events to listen on for skill-gain / recipe-list updates.
local GAIN_EVENTS = {
	"TRADE_SKILL_UPDATE", "TRADECRAFT", "TRADE_SKILL_SHOW", "TRADE_SKILL_CAST",
	"SPELLS_CHANGED", "SKILL_LEARN", "PLAYER_LEVEL_UP",
}
if GAIN_EVENTS then end -- referenced by SkillupModel wiring in a later batch

local RANK_SPELLS = { 2018, 2019, 2020, 2021 } -- Apprentice / Journeyman / Expert / Master (blacksmithing)

local SAMPLE_ITEM = 5956 -- Blacksmith Hammer

function P.Run(fullMode)
	local lines = {}
	local function emit(s)
		Blackie:Print(s)
		lines[#lines + 1] = s
	end
	local function flag(ok)
		return ok and "|cff22cc66YES|r" or "|cffcc5555--|r"
	end

	local ci = Compat.clientInfo()
	emit(format("|cffffcc00== CLIENT ==|r  build=%s iface=%s date=%s ver=%s",
		tostring(ci.build), tostring(ci.interface), tostring(ci.buildDate), tostring(ci.clientVersion)))

	emit("|cffffcc00== API EXISTENCE ==|r")
	for _, grp in ipairs(CANDIDATES) do
		for _, name in ipairs(grp.names) do
			emit(format("%-6s %-46s %s", grp.group, name, flag(Compat.exists(name))))
		end
	end

	emit("|cffffcc00== UI FRAMES ==|r")
	for _, name in ipairs(FRAMES) do
		emit(format("%-6s %-46s %s", "FRAME", name, flag(_G[name] ~= nil)))
	end

	emit("|cffffcc00== MAPPIN SLASH ==|r")
	local mp = SlashCmdList and (SlashCmdList["MAPPIN"] or SlashCmdList["MAP_PIN"] or SlashCmdList["PIN"])
	emit(format("%-6s %-46s %s", "MAPPIN", "SlashCmdList[MAPPIN|MAP_PIN|PIN]", flag(mp ~= nil)))

	emit("|cffffcc00== RUNTIME TESTS ==|r")

	local function try(desc, fn)
		local ok, result = pcall(fn)
		if ok then
			emit(format("%-6s %-46s %s", "RUN", desc, tostring(result)))
		else
			emit(format("%-6s %-46s ERROR: %s", "RUN", desc, tostring(result)))
		end
	end

	try("itemInfo(5956)", function()
		local ref = Compat.itemInfo(SAMPLE_ITEM)
		if not ref then return "nil" end
		return format("style=%s name=%s quality=%s sell=%s",
			tostring(Compat.itemStyle or Compat.get("ITEM_STYLE")), ref.name,
			tostring(ref.quality), tostring(ref.sell))
	end)
	try("countItem(5956)", function()
		local n = Compat.countItem(SAMPLE_ITEM)
		if n == nil then return "nil" end
		return "n=" .. n
	end)
	try("itemLink(5956)", function()
		return tostring(Compat.itemLink(SAMPLE_ITEM))
	end)
	try("spellName(2018)", function()
		return tostring(Compat.spellName(2018))
	end)
	try("currentSkill()", function()
		local v = Compat.currentSkill()
		if v == nil then return "nil" end
		return "skill=" .. v
	end)
	for _, id in ipairs(RANK_SPELLS) do
		try("rankSpell " .. id, function()
			local known = Compat.spellIsKnown(id) and "known" or "not-known"
			local ok, lvl = Compat.raw("C_Spell.GetSpellLevel", id)
			if not ok then ok, lvl = Compat.raw("GetSpellLevel", id) end
			return known .. " level=" .. (ok and tostring(lvl) or "?")
		end)
	end
	try("tsScanDrivers()", function()
		local drivers = {}
		if Compat.exists("C_TradeSkillUI.GetRecipeNumDisplayRecipes")
			or Compat.exists("C_TradeSkillUI.GetNumTradeSkills") then drivers[#drivers + 1] = "C_TradeSkillUI" end
		if Compat.exists("GetNumTradeSkills") then drivers[#drivers + 1] = "Classic.Tradeskill" end
		if Compat.exists("C_Professions.GetNumRecipeListEntries") then drivers[#drivers + 1] = "C_Professions" end
		if Compat.driver then drivers[#drivers + 1] = "pinned=" .. Compat.driver end
		if #drivers == 0 then return "NONE (no trade-scan API found)" end
		return table.concat(drivers, ", ")
	end)
	try("bagCounts()", function()
		local bags = Compat.bagCounts()
		if not bags then return "nil" end
		local kinds, items = 0, 0
		for _, n in pairs(bags) do kinds = kinds + 1 items = items + n end
		return format("style=%s distinctItemIDs=%d itemCount=%d",
			tostring(Compat.containerStyle or Compat.get("CONTAINER_STYLE")), kinds, items)
	end)
	try("mapInfoForPlayer()", function()
		local m = Compat.mapInfoForPlayer()
		if not m then return "nil" end
		local pin = m.x and m.pinCommand(m.x, m.y) or "no position"
		return format("style=%s mapID=%s zone=%s pos=(%.1f,%.1f) pin=%s",
			tostring(m.style), tostring(m.mapID), tostring(m.zoneText),
			(m.x or 0) * 100, (m.y or 0) * 100, tostring(pin))
	end)
	try("mappinAvailable()", function()
		return tostring(Compat.mappinAvailable())
	end)
	try("guessMerchantFrame()", function()
		return tostring(Compat.guessMerchantFrame())
	end)
	try("gainFromChat()", function()
		local a, b = Compat.gainFromChat("Your Blacksmithing skill increases by 1")
		if not a then return "NO MATCH" end
		return format("matched skill=%s amount=%s", tostring(a), tostring(b))
	end)
	try("AHQueue.style", function()
		if not AHQueue then return "no AHQueue" end
		if not AHQueue.style then AHQueue.init() end
		return tostring(AHQueue.style)
	end)

	if fullMode then
		emit("|cffffcc00== AH LIVE TEST ==|r (stand at an auction house for a real answer)")
		if AHQueue then
			AHQueue.enqueue(SAMPLE_ITEM, function(entry)
				Blackie:Print(format("Blackie AH item %d -> status=%s buy=%s qty=%s %s",
					SAMPLE_ITEM, tostring(entry.status),
					entry.buy and Util.money(entry.buy) or "-",
					tostring(entry.availableQuantity),
					entry.message and ("(" .. entry.message .. ")") or ""))
			end)
		end
	end

	-- Persist what we learned for future sessions.
	Compat.persist()
	if BlackieDB then
		BlackieDB.probeLog = table.concat(lines, "\n")
		BlackieDB.probeLogTS = date and date() or GetTime()
	end
	emit("|cffffcc00== DONE ==|r  paste the whole report back for pinning.")
end
