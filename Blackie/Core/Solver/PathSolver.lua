-- Blackie.PathSolver: dynamic 1..target leveling path via DP over skill points.
-- Cost model: per-unit prices resolved through an injected priceOf function
-- (production wires Blackie.Costing.priceOf). No hardcoded guides.
-- This file is pure Lua (loads fine offline) so it can be unit-tested.

local Blackie = Blackie
if not Blackie then return end

Blackie.PathSolver = Blackie.PathSolver or {}
local PS = Blackie.PathSolver
local SM = Blackie.SkillupModel
local RI = Blackie.RankInfo

local INF = math.huge

local function recipeKey(r)
	if r.recipeID then return "r" .. r.recipeID end
	if r.spellID then return "s" .. r.spellID end
	if r.itemId and r.itemId > 0 then return "i" .. r.itemId end
	return "n" .. (r.name or "?")
end

-- Default rank gating from RankInfo when caller supplies nothing.
local function defaultRankGate(s)
	if not RI then
		-- no rank model: assume no walls
		return math.huge, 0, nil
	end
	local cap = RI.capForSkill(s)
	if s < cap then return cap, 0, nil end
	local rank = RI.nextRank(s)
	if not rank then return cap, 0, nil end
	local cost = RI.rankCost(rank)
	return cap, cost or 0, rank
end

-- Resolve a recipe's craft cost. Returns total copper, or nil if any reagent
-- is unpriceable. opts.priceOf(itemID) -> number|nil ; optional opts.priceOfName(name).
local function recipeCraftCost(recipe, opts)
	local total = 0
	for _, r in ipairs(recipe.reagents or {}) do
		local unit
		if r.itemId and r.itemId > 0 and opts.priceOf then
			unit = opts.priceOf(r.itemId)
		end
		if unit == nil and opts.priceOfName and r.name then
			unit = opts.priceOfName(r.name)
		end
		if unit == nil then return nil end
		total = total + unit * (r.count or 1)
	end
	return total
end

function PS.solve(opts)
	opts = opts or {}
	local current = opts.current or 0
	local target = math.min(opts.target or 300, 300)
	local allowOrange = opts.allowOrange == true
	local recipes = opts.recipes or {}

	if current >= target then
		return { ok = true, plan = {}, totalCost = 0, unknownRecipes = {}, maxReached = current }
	end

	-- Precompute windows + costs; drop recipe rows that are unusable here.
	local usable, unknown = {}, {}
	local rankGate = opts.rankGateFn or defaultRankGate
	for _, rec in ipairs(recipes) do
		local lo = (rec.requiredSkill or 0) - (allowOrange and SM.ORANGE_SPAN or 0)
		if lo < 0 then lo = 0 end
		local hi = (rec.requiredSkill or 0) + SM.GREY_SPAN - 1
		if hi >= current and lo <= target - 1 then
			local cost = recipeCraftCost(rec, opts)
			if cost ~= nil then
				usable[#usable + 1] = { rec = rec, lo = lo, hi = hi, cost = cost }
			else
				unknown[recipeKey(rec)] = { name = rec.name, reason = "unpriceable reagents" }
			end
		end
	end

	if #usable == 0 then
		return { ok = false, plan = nil, totalCost = nil, unknownRecipes = unknown,
			maxReached = current, reason = "no priceable recipes in range" }
	end

	local dp, prev = {}, {}
	for s = 0, target do dp[s] = INF end
	dp[current] = 0

	for s = current, target - 1 do
		if dp[s] < INF then
			local cap, rankUpCost, rank = rankGate(s)
			if s < cap then rankUpCost = 0 end
			for _, u in ipairs(usable) do
				if s >= u.lo and s <= u.hi then
					local g = SM.gain(u.rec, s)
					if g > 0 then
						local ns = s + g
						if ns > target then ns = target end
						local nc = dp[s] + u.cost + rankUpCost
						if nc < dp[ns] then
							dp[ns] = nc
							prev[ns] = { rec = u.rec, from = s, gain = g, cost = u.cost,
								rankUp = (rankUpCost > 0) and { cost = rankUpCost, rank = rank } or nil }
						end
					end
				end
			end
		end
	end

	if dp[target] == INF then
		local maxReached = current
		for s = current, target do
			if dp[s] < INF and s > maxReached then maxReached = s end
		end
		return { ok = false, plan = nil, totalCost = nil, unknownRecipes = unknown,
			maxReached = maxReached, target = target, reason = "target unreachable with current knowledge" }
	end

	-- Reconstruct
	local plan = {}
	local s = target
	while s > current do
		local p = prev[s]
		if not p then break end
		plan[#plan + 1] = {
			name = p.rec.name, key = recipeKey(p.rec), recipe = p.rec,
			atSkill = p.from, gain = p.gain, craftCost = p.cost,
			band = SM.band(p.rec, p.from), rankUp = p.rankUp,
		}
		s = p.from
	end
	-- reverse into crafting order
	local out = {}
	for i = #plan, 1, -1 do out[#out + 1] = plan[i] end

	return {
		ok = true, plan = out, totalCost = dp[target],
		unknownRecipes = unknown, maxReached = target, target = target,
		craftCounts = nil, -- filled by PlanBuilder
	}
end

-- Quick helper used by UI/tests: summarize plan as "recipe xN" pairs.
function PS.summarize(plan)
	local counts, order = {}, {}
	for _, e in ipairs(plan or {}) do
		if not counts[e.key] then
			counts[e.key] = { name = e.name, recipe = e.recipe, n = 0, cost = 0 }
			order[#order + 1] = e.key
		end
		counts[e.key].n = counts[e.key].n + 1
		counts[e.key].cost = counts[e.key].cost + (e.craftCost or 0)
	end
	local list = {}
	for _, k in ipairs(order) do
		list[#list + 1] = counts[k]
	end
	return list
end

Blackie.PathSolver.recipeKey = recipeKey
