-- Blackie.Commands: /blackie slash command dispatcher.

local Blackie = Blackie
if not Blackie then return end

Blackie.Commands = Blackie.Commands or {}
local C = Blackie.Commands
local Util = Blackie.Util

local pendingCommands = {
	open = "panel UI (Batch F)",
	recipes = "recipes UI (Batch F)",
	selftest = "self-test (Batch G)",
	copy = "plan copy (Batch F)",
	learn = "trainer learn helper (Batch F)",
}

function C.Help()
	Blackie:Print("commands:")
	Blackie:Print("  /blackie probe [full]   diagnose client APIs (paste report back)")
	Blackie:Print("  /blackie compat         show pinned driver selections")
	Blackie:Print("  /blackie target [n]     leveling target (75/150/225/300)")
	Blackie:Print("  /blackie version")
	Blackie:Print("  /blackie reset          forget pinned probe selections only")
	Blackie:Print("  /blackie rescan         refresh recipe list from the trade-skill API")
	Blackie:Print("  /blackie trainer        scan the open trainer window")
	Blackie:Print("  /blackie vendor         scan the open vendor window")
	Blackie:Print("  /blackie price <itemID> item price lookup (cached AH / vendor / bags)")
	Blackie:Print("  /blackie plan           compute optimal 1->target leveling path")
	Blackie:Print("  /blackie shopping      show shopping list of last plan")
	Blackie:Print("  coming soon: open, recipes, selftest, copy, learn")
end

function C.CompatDump()
	local s = Compat.state()
	for _, k in ipairs({ "TRADESKILL_DRIVER", "ITEM_STYLE", "CONTAINER_STYLE", "AH_STYLE",
		"TRAINER_STYLE", "MERCHANT_FRAME", "MAP_STYLE", "MAPPIN_OK", "PROBE_VERSION" }) do
		Blackie:Print(format("  %-18s %s", k, tostring(s[k])))
	end
end

function C.Target(rest)
	local p = Blackie.Profile()
	local n = rest and tonumber(rest)
	if n then
		if n < 1 or n > 300 then
			Blackie:Print("target must be 1..300")
			return
		end
		p.settings.target = n
		Blackie:Print("target set to " .. n)
		return
	end
	Blackie:Print("current target: " .. tostring(p.settings.target))
end

function C.Reset()
	if BlackieDB then
		BlackieDB.probe = nil
	end
	Blackie.Compat.driver = nil
	Blackie.Compat.itemStyle = nil
	Blackie.Compat.containerStyle = nil
	Blackie.Compat.trainerStyle = nil
	Blackie.Compat.merchantFrame = nil
	Blackie:Print("probe selections cleared; run /blackie probe again.")
end

function C.Version()
	local ci = Blackie.Compat.clientInfo()
	Blackie:Print(format("Blackie v%s  client build=%s iface=%s",
		Blackie.version, tostring(ci.build), tostring(ci.interface)))
end

function C.Rescan()
	if not Blackie.RecipeCache then Blackie:Print("RecipeCache missing (load order?)"); return end
	Blackie.RecipeCache.upsertFromScan()
end

function C.Trainer()
	if not Blackie.TrainerScan then Blackie:Print("TrainerScan missing (load order?)"); return end
	Blackie.TrainerScan.scan()
end

function C.Vendor()
	if not Blackie.VendorScan then Blackie:Print("VendorScan missing (load order?)"); return end
	Blackie.VendorScan.scan()
end

function C.Price(rest)
	if not Blackie.Costing then Blackie:Print("Costing missing (load order?)"); return end
	local itemID = tonumber(rest) or Util.idFromLink(rest or "")
	if not itemID then Blackie:Print("usage: /blackie price <itemID or item link>"); return end
	Blackie.Costing.reportItem(itemID)
end

function C.Plan()
	local RC, PS, PB, CS, Compat = Blackie.RecipeCache, Blackie.PathSolver, Blackie.PlanBuilder, Blackie.Costing, Blackie.Compat
	if not (RC and PS and PB and CS) then Blackie:Print("solver modules missing (load order?)"); return end
	local recipes = RC.all()
	if not recipes or #recipes == 0 then
		Blackie:Print("no cached recipes yet — open your spellbook (trade skill window) or run /blackie rescan")
		return
	end
	local current = Compat.currentSkill() or 0
	local target = Blackie.Profile().settings.target or 300
	Blackie:Print(format("solving %d -> %d with %d cached recipes...", current, target, #recipes))
	local result = PS.solve {
		current = current, target = target, recipes = recipes,
		allowOrange = false,
		priceOf = function(id) return CS.priceOf(id) end,
		priceOfName = function(name) return nil end,
	}
	if not result.ok then
		Blackie:Print("solver: " .. tostring(result.reason) ..
			(result.maxReached and (" (max reachable with current knowledge: " .. result.maxReached .. ")") or ""))
		Blackie:Print("tip: open a vendor and run /blackie vendor, stand at an AH, run /blackie trainer — pricing gates the solver.")
		return
	end
	local plan = PB.build(result)
	PB.report(plan)
end

function C.Shopping()
	local db = Blackie.DB()
	if not db.lastPlan then Blackie:Print("no plan yet — run /blackie plan"); return end
	Blackie:Print("shopping list (last plan, cached; re-run /blackie plan for fresh):")
	Blackie.PlanBuilder.report(db.lastPlan)
end

function C.Dispatch(input)
	local text = Util.trim(input or "")
	local cmd, rest = text:match("^(%S+)%s*(.*)$")
	cmd = cmd or ""
	if cmd == "" or cmd == "help" or cmd == "?" then
		C.Help()
	elseif cmd == "probe" then
		if Blackie.APIProbe then Blackie.APIProbe.Run(rest == "full") else Blackie:Print("probe not loaded") end
	elseif cmd == "rescan" then
		C.Rescan()
	elseif cmd == "trainer" then
		C.Trainer()
	elseif cmd == "vendor" then
		C.Vendor()
	elseif cmd == "price" then
		C.Price(rest)
	elseif cmd == "plan" then
		C.Plan()
	elseif cmd == "shopping" then
		C.Shopping()
	elseif cmd == "compat" then
		C.CompatDump()
	elseif cmd == "target" then
		C.Target(rest)
	elseif cmd == "reset" then
		C.Reset()
	elseif cmd == "version" then
		C.Version()
	elseif pendingCommands[cmd] then
		Blackie:Print("/blackie " .. cmd .. " — not implemented yet: " .. pendingCommands[cmd])
	else
		Blackie:Print("unknown subcommand: " .. cmd)
		C.Help()
	end
end

function C.Init()
	if Blackie.CommandsInitDone then return end
	Blackie.CommandsInitDone = true
	SLASH_BLACKIE1 = "/blackie"
	SLASH_BLACKIE2 = "/bl"
	SlashCmdList["BLACKIE"] = C.Dispatch
end
