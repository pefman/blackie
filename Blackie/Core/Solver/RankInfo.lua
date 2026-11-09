-- Blackie.RankInfo: Blacksmithing rank ladder metadata (vanilla 1-300).
-- Rank costs are discovered from trainer scans only (no hardcoded price assumptions).

local Blackie = Blackie
if not Blackie then return end

Blackie.RankInfo = Blackie.RankInfo or {}
local RI = Blackie.RankInfo

RI.RANKS = {
	{ index = 1, name = "Apprentice", spellID = 2018, cap = 75,  reqSkill = 0,   reqLevel = 1 },
	{ index = 2, name = "Journeyman", spellID = 2019, cap = 150, reqSkill = 50,  reqLevel = 10 },
	{ index = 3, name = "Expert",     spellID = 2020, cap = 225, reqSkill = 125, reqLevel = 20 },
	{ index = 4, name = "Artisan",    spellID = 2021, cap = 300, reqSkill = 200, reqLevel = 35 },
}

-- Highest rank whose cap still covers skill value s.
function RI.rankForSkill(s)
	for i = #RI.RANKS, 1, -1 do
		if s >= RI.RANKS[i].reqSkill then return RI.RANKS[i] end
	end
	return RI.RANKS[1]
end

-- Cap that applies at skill value s: the smallest rank cap >= s.
-- (At s = 75 the player is AT the Apprentice wall, not past it.)
function RI.capForSkill(s)
	for _, r in ipairs(RI.RANKS) do
		if r.cap >= s then return r.cap end
	end
	return RI.RANKS[#RI.RANKS].cap
end

-- The rank that must be purchased to craft above cap(s).
function RI.nextRank(s)
	for _, r in ipairs(RI.RANKS) do
		if r.cap > s and s >= r.reqSkill - 25 then return r end
	end
	return nil
end

-- rankCost: prefer trainer-scan evidence (db.lastTrainer.ranks rows).
function RI.rankCost(rank)
	if not rank then return nil end
	local db = Blackie.DB and Blackie.DB()
	local lt = db and db.lastTrainer
	if lt and lt.ranks then
		for _, row in ipairs(lt.ranks) do
			if row.spellID == rank.spellID then
				local c = row.cost
				if type(c) == "string" and Blackie.Util then c = Blackie.Util.parseMoney(c) end
				if type(c) == "number" then return c, "trainer" end
			end
		end
	end
	return nil
end

RI.DEFAULT_RANK_COST_WARNING = "rank cost unknown (no trainer scan yet) "
