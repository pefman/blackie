-- Blackie.PlanTab: "Plan" panel page — run the optimal-path solver and show
-- the craft sequence it produces, plus rank purchases and diagnostics.

local Blackie = Blackie
if not Blackie or not Blackie.Panel then return end

Blackie.PlanTab = Blackie.PlanTab or {}
local PT = Blackie.PlanTab

local Panel = Blackie.Panel
local Util = Blackie.Util

local list
local summaryText
local targetBox
local orangeBtn
local allowOrange = false
local rows = {}

local function mkButton(parent, w, h, text, onClick)
	local okB, b = pcall(CreateFrame, "Button", nil, parent, "UIPanelButtonTemplate")
	if not okB or not b then b = CreateFrame("Button", nil, parent) end
	b:SetSize(w, h)
	local fs = Panel.NewText(b, "OVERLAY", "normal")
	fs:SetPoint("CENTER", b, "CENTER", 0, 1)
	fs:SetText(text)
	b.label = fs
	b:SetScript("OnClick", function()
		local ok, err = pcall(onClick)
		if not ok then Blackie:Print("plan action failed: " .. tostring(err)) end
	end)
	return b
end

local function targetValue()
	if targetBox and targetBox.GetText then
		local v = tonumber(targetBox:GetText())
		if v then return Util.clamp(math.floor(v), 1, 300) end
	end
	local settings = Blackie.Profile().settings or {}
	return settings.target or 300
end

local function showPlan(plan)
	rows = {}
	for _, c in ipairs(plan.crafts or {}) do
		rows[#rows + 1] = { kind = "craft", text = c.name or "?", sub = "x" .. c.n,
			sub2 = Util.money(math.floor(c.cost or 0)) }
	end
	for _, r in ipairs(plan.ranks or {}) do
		rows[#rows + 1] = { kind = "rank", text = "rank-up at " .. tostring(r.atSkill or 0),
			sub = r.name or "?", sub2 = r.cost and Util.money(r.cost) or "cost ?" }
	end
	for _, note in ipairs(plan.notes or {}) do
		rows[#rows + 1] = { kind = "note", text = note, sub = "", sub2 = "" }
	end
	list:SetRows(rows)
	summaryText:SetText(format("plan to %d: %d craft steps | DP total %s | shop total %s (%d unpriced) — see Shopping tab",
		plan.target or 0,
		(function() local n = 0 for _, c in ipairs(plan.crafts or {}) do n = n + c.n end return n end)(),
		Util.money(math.floor(plan.totalDP or 0)),
		Util.money(math.floor(plan.shopTotal or 0)), plan.unknownCount or 0))
end

local function run()
	local target = targetValue()
	local settings = Blackie.Profile().settings or {}
	settings.target = target
	local result, plan = Blackie.PlanBuilder.runPlan({
		target = target,
		allowOrange = allowOrange,
	})
	if not result.ok then
		rows = {}
		list:SetRows(rows)
		local knownN = Blackie.RecipeCache and Blackie.RecipeCache.count() or 0
		summaryText:SetText(format("no plan: %s (reached %s of %d). Cached recipes: %d. Price reagents (/blackie price <item> or wait for AH reads) or open your tradeskill window + /blackie rescan.",
			result.reason or "?", tostring(result.maxReached), target, knownN))
		return
	end
	showPlan(plan)
end

PT.Run = run

local function build(page)
	local runBtn = mkButton(page, 110, 22, "RUN PLAN", run)
	runBtn:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -2)

	orangeBtn = mkButton(page, 128, 22, "orange: off", function()
		allowOrange = not allowOrange
		orangeBtn.label:SetText(allowOrange and "orange: risky-ok" or "orange: off")
	end)
	orangeBtn:SetPoint("RIGHT", runBtn, "LEFT", -6, 0)

	local tlab = Panel.NewText(page, "OVERLAY", "small")
	tlab:SetText("target:")

	local okE, eb = pcall(CreateFrame, "EditBox", nil, page, "InputBoxTemplate")
	targetBox = (okE and eb) or CreateFrame("EditBox", nil, page)
	targetBox:SetSize(52, 20)
	targetBox:SetMaxLetters(3)
	targetBox:Enable()
	targetBox:SetPoint("RIGHT", tlab, "LEFT", -4, 0)
	tlab:SetPoint("RIGHT", orangeBtn, "LEFT", -10, 0)
	targetBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

	summaryText = Panel.NewText(page, "OVERLAY", "normal")
	summaryText:SetPoint("TOPLEFT", page, "TOPLEFT", 2, -30)
	summaryText:SetPoint("TOPRIGHT", page, "TOPRIGHT", -2, -30)
	summaryText:SetWordWrap(true)
	summaryText:SetText("press RUN PLAN to compute an optimal 1-300 style path from cached recipes.")

	local area = CreateFrame("Frame", nil, page)
	area:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -62)
	area:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)

	list = Blackie.ScrollList.New(area, { rowHeight = 18 })
	list:SetRenderer(function(f, item)
		f.label:SetText(item.text)
		if item.kind == "craft" then
			f.label:SetTextColor(0.85, 0.9, 1.0)
		elseif item.kind == "rank" then
			f.label:SetTextColor(1.0, 0.7, 0.3)
		else
			f.label:SetTextColor(0.62, 0.62, 0.62)
		end
		f.sub:SetText(item.sub or "")
		if item.sub2 and item.sub2 ~= "" then
			f.sub:SetText(item.sub .. "  " .. item.sub2)
		end
	end)

	Panel.AddFooterButton("re-run plan", run)
end

local function show()
	if targetBox and not tonumber(targetBox:GetText() or "") then
		local settings = Blackie.Profile().settings or {}
		targetBox:SetText(tostring(settings.target or 300))
	end
	local db = Blackie.DB()
	if db.lastPlan then showPlan(db.lastPlan) end
end

Panel.RegisterTab("Plan", { build = build, show = show })
