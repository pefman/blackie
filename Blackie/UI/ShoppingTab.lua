-- Blackie.ShoppingTab: "Shopping" panel page — what to BUY for the last plan:
-- reagents (qty/unit/total with buy-this hints), rank purchases, self-craft
-- notes and totals. Reads db.lastPlan, same data the chat report uses.

local Blackie = Blackie
if not Blackie or not Blackie.Panel then return end

Blackie.ShoppingTab = Blackie.ShoppingTab or {}
local ST = Blackie.ShoppingTab

local Panel = Blackie.Panel
local Util = Blackie.Util

local list
local summaryText
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
		if not ok then Blackie:Print("shopping action failed: " .. tostring(err)) end
	end)
	return b
end

local function refresh()
	local db = Blackie.DB()
	local plan = db.lastPlan
	rows = {}
	if not plan then
		summaryText:SetText("no plan yet — run one on the Plan tab (or /blackie plan).")
		list:SetRows(rows)
		return
	end

	summaryText:SetText(format("plan to %d | DP total %s | shop total %s (%d unpriced) | hover items for tooltips",
		plan.target or 0,
		Util.money(math.floor(plan.totalDP or 0)),
		Util.money(math.floor(plan.shopTotal or 0)),
		plan.unknownCount or 0))

	for _, s in ipairs(plan.shop or {}) do
		local line
		if s.unit then
			line = format("buy x%d  %s | unit %s | total %s",
				s.qty, s.name or ("item " .. s.itemID),
				Util.money(s.unit), Util.money(math.floor(s.unit * s.qty)))
		else
			line = format("buy x%d  %s | price unknown (run /blackie price %s or wait for AH reads)",
				s.qty, s.name or ("item " .. s.itemID), tostring(s.itemID))
		end
		rows[#rows + 1] = { kind = "buy", text = line, itemID = s.itemID, src = s.source }
	end
	for _, r in ipairs(plan.ranks or {}) do
		rows[#rows + 1] = { kind = "rank", text = format("rank-up at %d: %s (%s)",
			r.atSkill or 0, r.name or "?", r.cost and Util.money(r.cost) or "cost ? - run /blackie trainer at the trainer") }
	end
	for _, note in ipairs(plan.notes or {}) do
		rows[#rows + 1] = { kind = "note", text = note }
	end
	list:SetRows(rows)
end

ST.Refresh = refresh

local function onEnterRow(f, item)
	if not item or (item.itemID or 0) <= 0 then return end
	if not (Blackie.Compat and Blackie.Compat.itemLink) then return end
	local link = Blackie.Compat.itemLink(item.itemID)
	if not link then return end
	pcall(function()
		GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink(link)
		GameTooltip:Show()
	end)
end

local function onLeaveRow()
	pcall(function() GameTooltip:Hide() end)
end

local function build(page)
	summaryText = Panel.NewText(page, "OVERLAY", "normal")
	summaryText:SetPoint("TOPLEFT", page, "TOPLEFT", 2, -4)
	summaryText:SetText("no plan yet")

	local rerunBtn = mkButton(page, 110, 22, "re-run plan", function()
		if Blackie.PlanTab and Blackie.PlanTab.Run then Blackie.PlanTab.Run() end
		refresh()
	end)
	rerunBtn:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -2)

	local area = CreateFrame("Frame", nil, page)
	area:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -26)
	area:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)

	list = Blackie.ScrollList.New(area, { rowHeight = 18 })
	list:SetRenderer(function(f, item)
		f.label:SetText(item.text)
		if item.kind == "buy" then
			f.label:SetTextColor(0.85, 0.9, 1.0)
			f.sub:SetText(item.src or "")
		elseif item.kind == "rank" then
			f.label:SetTextColor(1.0, 0.7, 0.3)
			f.sub:SetText("")
		else
			f.label:SetTextColor(0.62, 0.62, 0.62)
			f.sub:SetText("")
		end
	end)
	list:SetHooks({ onEnter = onEnterRow, onLeave = onLeaveRow })

	Panel.AddFooterButton("refresh shopping", refresh)
end

local function show()
	refresh()
end

Panel.RegisterTab("Shopping", { build = build, show = show })
