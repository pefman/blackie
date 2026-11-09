-- Blackie.PlanBuilder: turn a PathSolver plan into a shopping list + chat report.
-- (UI tabs later render the same db.lastPlan structure.)

local Blackie = Blackie
if not Blackie or not Blackie.DB then return end

Blackie.PlanBuilder = Blackie.PlanBuilder or {}
local BP = Blackie.PlanBuilder
local PS = Blackie.PathSolver
local Util = Blackie.Util

local function epoch()
	return time and time() or (GetTime and GetTime() or 0)
end

function BP.build(solveResult)
	if not solveResult or not solveResult.ok then
		local r = solveResult and solveResult.reason or "solve failed"
		Blackie:Print("no plan: " .. r ..
			(solveResult and solveResult.maxReached and (" (reached " .. solveResult.maxReached .. ")") or ""))
		return nil
	end

	local summary = PS.summarize(solveResult.plan)
	local CS = Blackie.Costing
	local RC = Blackie.RecipeCache

	-- Aggregate reagent demand across crafts.
	local demand = {} -- itemID -> {qty, name}
	for _, s in ipairs(summary) do
		for _, r in ipairs((s.recipe and s.recipe.reagents) or {}) do
			local id = r.itemId
			if id and id > 0 then
				demand[id] = demand[id] or { qty = 0, name = r.name }
				demand[id].qty = demand[id].qty + (r.count or 1) * s.n
			end
		end
	end

	local shoplines, noteLines, unknownN = {}, {}, 0
	local shopTotal = 0
	for id, d in pairs(demand) do
		local inBag = CS and CS.inBag(id) or 0
		local need = d.qty - math.min(inBag, d.qty)
		local unit, src = CS and CS.priceOf(id)
		if RC and RC.byItemID(id) then
			noteLines[#noteLines + 1] = format("item %d (%s) is blacksmith-made: can self-craft for %s ea",
				id, d.name or "?", unit and Util.money(unit) or "unknown")
		end
		if need > 0 then
			local line = { itemID = id, name = d.name, qty = need, unit = unit, source = src }
			shoplines[#shoplines + 1] = line
			if unit then
				shopTotal = shopTotal + unit * need
			else
				unknownN = unknownN + 1
			end
		end
	end
	table.sort(shoplines, function(a, b) return (a.unit or math.huge) < (b.unit or math.huge) end)

	-- Rank purchases used by the plan (dedupe by spellID/boundary skill).
	local rankLines = {}
	local seenRank = {}
	for _, e in ipairs(solveResult.plan) do
		if e.rankUp and e.rankUp.rank then
			local k = e.rankUp.rank.spellID or e.rankUp.rank.name
			if not seenRank[k] then
				seenRank[k] = true
				rankLines[#rankLines + 1] = { name = e.rankUp.rank.name, cost = e.rankUp.cost, atSkill = e.atSkill }
			end
		end
	end

	local plan = {
		ts = epoch(),
		target = solveResult.target,
		totalDP = solveResult.totalCost,
		shopTotal = shopTotal,
		unknownCount = unknownN,
		crafts = summary,
		shop = shoplines,
		ranks = rankLines,
		notes = noteLines,
	}
	local orderN = 0
	for s in pairs(seenRank) do orderN = orderN + 1 end
	plan.rankCount = orderN

	local db = Blackie.DB()
	db.lastPlan = plan
	return plan
end

-- Shared entry point: gather defaults (cached recipes, live skill, target,
-- AH/vendor prices), solve and build. Used by the Plan tab and /blackie plan.
-- Returns solveResult, plan (plan is nil unless the solve succeeded).
function BP.runPlan(opts)
	opts = opts or {}
	local RC = Blackie.RecipeCache
	local CS = Blackie.Costing

	local recipes = opts.recipes or (RC and RC.all()) or {}
	local current = opts.currentSkill
	if current == nil then
		current = (Blackie.Compat and Blackie.Compat.currentSkill()) or 0
	end
	local settings = Blackie.Profile().settings or {}
	local target = opts.target or settings.target or 300

	local result = PS.solve({
		current = current,
		target = target,
		recipes = recipes,
		allowOrange = opts.allowOrange or false,
		priceOf = opts.priceOf or (CS and CS.priceOf),
		priceOfName = opts.priceOfName,
	})
	local plan = nil
	if result.ok then plan = BP.build(result) end
	return result, plan
end

function BP.report(plan)
	if not plan then return end
	Blackie:Print(format("plan: %d craft steps, shop total %s (%d unpriced groups)",
		(function()
			local n = 0
			for _, s in ipairs(plan.crafts or {}) do n = n + s.n end
			return n
		end)(),
		Util.money(math.floor(plan.shopTotal or 0)), plan.unknownCount or 0))
	for i, c in ipairs(plan.crafts or {}) do
		Blackie:Print(format("  craft x%-3d %-38s (craft costs %s)",
			c.n, c.name or "?", Util.money(math.floor(c.cost or 0))))
	end
	for _, r in ipairs(plan.ranks or {}) do
		Blackie:Print(format("  rank-up at %d: %s (%s)",
			r.atSkill or 0, r.name or "?", r.cost and Util.money(r.cost) or "cost unknown - run /blackie trainer at the trainer"))
	end
	for i, s in ipairs(plan.shop or {}) do
		if i > 15 then
			Blackie:Print(format("  ... and %d more shopping lines", #plan.shop - 15))
			break
		end
		Blackie:Print(format("  buy x%-3d %-38s unit %s%s",
			s.qty, s.name or ("item " .. s.itemID), s.unit and Util.money(s.unit) or "PRICE UNKNOWN",
			s.source and (" [" .. s.source .. "]") or ""))
	end
	for _, n in ipairs(plan.notes or {}) do
		Blackie:Print("  note: " .. n)
	end
end
