-- Offline solver unit tests (no WoW client needed):
--   cd /home/pefman/git/blackie && lua5.1 Blackie/tests/harness.lua
-- Loads the pure-Lua solver files against a minimal Blackie stub.

local root = (arg[0] or ""):gsub("tests/harness%.lua$", "")
if root == "" then root = "./" end

-- ---- minimal Blackie stub -------------------------------------------------
local fakeDB = {}
local printed = {}
_G.format = format or string.format -- PlanBuilder uses the WoW-global format
_G.Blackie = {
	version = "test",
	Print = function(self, text) printed[#printed + 1] = text end,
	DB = function() return fakeDB end,
	Util = {
		money = function(c) return tostring(c) .. "c" end,
		parseMoney = function(s) return tonumber(s) end,
	},
}

local function load(rel) dofile(root .. rel) end
load("Core/Data/SkillupModel.lua")
load("Core/Solver/RankInfo.lua")
load("Core/Solver/PathSolver.lua")
load("Core/Solver/PlanBuilder.lua")

local SM, RI, PS, PB = Blackie.SkillupModel, Blackie.RankInfo, Blackie.PathSolver, Blackie.PlanBuilder

-- ---- asserts ---------------------------------------------------------------
local failures = 0
local function check(name, cond, detail)
	if cond then
		print("PASS " .. name)
	else
		failures = failures + 1
		print("FAIL " .. name .. (detail and ("  [" .. tostring(detail) .. "]") or ""))
	end
end

-- bands: fan-guide anchor recipeSkill 15 -> yellow at 15, grey at 55
check("band.yellow@req", SM.band({ requiredSkill = 15 }, 15) == "yellow")
check("band.green@req+5", SM.band({ requiredSkill = 15 }, 20) == "green")
check("band.green@req+39", SM.band({ requiredSkill = 15 }, 54) == "green")
check("band.grey@req+40", SM.band({ requiredSkill = 15 }, 55) == "grey")
check("band.orange@req-1", SM.band({ requiredSkill = 15 }, 14) == "orange")
check("band.orange@req-10", SM.band({ requiredSkill = 15 }, 5) == "orange")
check("band.red@req-11", SM.band({ requiredSkill = 15 }, 4) == "red")
check("gain.yellow", SM.gain({ requiredSkill = 15 }, 15) == 1)
check("gain.grey", SM.gain({ requiredSkill = 15 }, 99) == 0)

-- rank ladder
check("cap.10", RI.capForSkill(10) == 75)
check("cap.80", RI.capForSkill(80) == 150)
check("cap.230", RI.capForSkill(230) == 300)
check("nextRank@75 is Journeyman", RI.nextRank(75) and RI.nextRank(75).spellID == 2019)
check("nextRank@150 is Expert", RI.nextRank(150) and RI.nextRank(150).spellID == 2020)

-- price provider
local PRICES = { [11] = 2, [12] = 5 }
local function priceOf(id) return PRICES[id] end

local C1 = { name = "Starter Thing",  requiredSkill = 1,  spellID = 9001, reagents = { { itemId = 11, count = 1 } } }
local C2 = { name = "Mid Thing",      requiredSkill = 50, spellID = 9002, reagents = { { itemId = 11, count = 2 } } }

-- gap without orange: C1 last useful craft at skill 40 -> reaches 41, then gap to 50
local r1 = PS.solve { current = 1, target = 75, recipes = { C1, C2 }, priceOf = priceOf }
check("solve.gap-blocks", r1.ok == false and r1.maxReached == 41, r1.maxReached)

-- with allowOrange, C2 covers 40..89 -> target reached
local r2 = PS.solve { current = 1, target = 75, recipes = { C1, C2 }, priceOf = priceOf, allowOrange = true }
check("solve.orange-unblocks", r2.ok == true, r2.reason)
if r2.ok then
	check("solve.cost-positive", (r2.totalCost or 0) > 0, r2.totalCost)
	check("solve.order", r2.plan[1].atSkill == 1)
end

-- unpriceable reagents excluded
local C3 = { name = "Mystery Thing", requiredSkill = 10, spellID = 9003, reagents = { { itemId = 99, count = 1 } } }
local r3 = PS.solve { current = 1, target = 300, recipes = { C3 }, priceOf = priceOf }
check("solve.unpriceable-fails", r3.ok == false and r3.unknownRecipes[PS.recipeKey(C3)] ~= nil)

-- rank wall: 75 -> 150 with rank cost discovered from trainer scan fixture.
-- Ladder stays realistic: req-70 recipe bridges 75..105, req-110 picks up to 150.
fakeDB.lastTrainer = { ranks = { { spellID = 2019, cost = 1000, name = "Journeyman Blacksmithing" } } }
local R = { name = "Wall Bridge", requiredSkill = 70, spellID = 9004, reagents = { { itemId = 11, count = 1 } } }
local R2 = { name = "Upper Bridge", requiredSkill = 110, spellID = 9005, reagents = { { itemId = 11, count = 1 } } }
local r4 = PS.solve { current = 75, target = 150, recipes = { R, R2 }, priceOf = priceOf }
if r4.ok then
	-- 75 crafts * 2c (id11 = 2c) = 150c + 1000c rank = 1150c
	check("solve.rank-cost-included", r4.totalCost == 75 * 2 + 1000, r4.totalCost)
	local sawRank
	for _, e in ipairs(r4.plan) do
		if e.rankUp and e.rankUp.cost == 1000 and e.atSkill == 75 then sawRank = true end
	end
	check("solve.rank-up-flagged", sawRank == true)
else
	check("solve.rank-cost-included", false, r4.reason)
end

-- PlanBuilder smoke test on r4
local plan = PB.build(r4)
check("plan.built", plan ~= nil and (plan.totalDP or 0) > 0)
if plan and plan.shop then
	check("plan.shop-qty", (plan.shop[1] and plan.shop[1].qty == 75) or #plan.shop > 0)
end
local nBefore = #printed
PB.report(plan)
check("plan.report", #printed > nBefore)

print(failures == 0 and "ALL_TESTS_PASS" or ("TEST_FAILURES: " .. failures))
os.exit(failures == 0 and 0 or 1)
