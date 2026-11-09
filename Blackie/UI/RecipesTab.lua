-- Blackie.RecipesTab: "Recipes" panel page — every cached Blacksmithing recipe
-- with its difficulty band at your current skill, a search filter, and item
-- tooltips. Fed by /blackie rescan and trainer/vendor scans.

local Blackie = Blackie
if not Blackie or not Blackie.Panel then return end

Blackie.RecipesTab = Blackie.RecipesTab or {}
local RT = Blackie.RecipesTab

local Panel = Blackie.Panel
local Util = Blackie.Util

local BAND_COLORS = {
	grey = { 0.62, 0.62, 0.62 },
	green = { 0.30, 0.85, 0.30 },
	yellow = { 0.95, 0.80, 0.20 },
	orange = { 1.00, 0.52, 0.15 },
	red = { 0.90, 0.22, 0.22 },
}

local list
local headerText
local filterBox
local knownBtn
local knownOnly = false
local rows = {}
local curSkill = nil

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
		if not ok then Blackie:Print("recipes action failed: " .. tostring(err)) end
	end)
	return b
end

-- ---------------------------------------------------------------------------
-- Row data
-- ---------------------------------------------------------------------------
local function refresh()
	local RC = Blackie.RecipeCache
	local recipes = (RC and RC.all()) or {}
	local known = (RC and RC.knownMap()) or {}

	local filter = ""
	if filterBox and filterBox.GetText then
		filter = strlower(filterBox:GetText() or "")
	end

	rows = {}
	local knownN = 0
	for _, r in ipairs(recipes) do
		local isKnown = (r.key and known[r.key]) or (r.recipeID and known[r.recipeID]) or false
		if isKnown then knownN = knownN + 1 end
		if knownOnly and not isKnown then
			-- filtered out
		elseif filter == "" or (r.name and strfind(strlower(r.name), filter, 1, true)) then
			rows[#rows + 1] = { row = r, known = isKnown }
		end
	end

	table.sort(rows, function(a, b)
		local ra, rb = a.row.requiredSkill or 0, b.row.requiredSkill or 0
		if ra ~= rb then return ra < rb end
		return (a.row.name or "") < (b.row.name or "")
	end)

	curSkill = nil
	if Blackie.Compat and Blackie.Compat.currentSkill then
		local ok, v = pcall(Blackie.Compat.currentSkill)
		if ok and type(v) == "number" then curSkill = v end
	end

	local skillText = curSkill and tostring(curSkill) or "?"
	headerText:SetText(format("%d recipes (%d known) | skill %s/300 | hover an item for its tooltip",
		#rows, knownN, skillText))

	list:SetRows(rows)
end

RT.Refresh = refresh

-- ---------------------------------------------------------------------------
-- Building the page
-- ---------------------------------------------------------------------------
local function onEnterRow(f, item)
	if not item or not item.row then return end
	local r = item.row
	if (r.itemId or 0) <= 0 then return end
	if not (Blackie.Compat and Blackie.Compat.itemLink) then return end
	local link = Blackie.Compat.itemLink(r.itemId)
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
	headerText = Panel.NewText(page, "OVERLAY", "small")
	headerText:SetPoint("TOPLEFT", page, "TOPLEFT", 2, -4)
	headerText:SetText("loading recipes...")

	knownBtn = mkButton(page, 118, 20, "filter: all", function()
		knownOnly = not knownOnly
		knownBtn.label:SetText(knownOnly and "filter: known" or "filter: all")
		refresh()
	end)
	knownBtn:SetPoint("TOPRIGHT", page, "TOPRIGHT", -142, -2)

	local okE, eb = pcall(CreateFrame, "EditBox", nil, page, "SearchEditBoxMedium")
	filterBox = (okE and eb) or CreateFrame("EditBox", nil, page)
	filterBox:SetSize(130, 20)
	filterBox:SetPoint("TOPRIGHT", page, "TOPRIGHT", -4, -2)
	filterBox:SetMaxLetters(64)
	if filterBox.SetBackdrop then
		pcall(filterBox.SetBackdrop, filterBox, {
			bgFile = "Interface\\CandidateListBackgroundHighlight\\Blend8x8Tex", edgeSize = 1,
		})
	end
	filterBox:Enable()
	filterBox:SetText("")
	filterBox:SetScript("OnTextChanged", function() refresh() end)
	local ph = Panel.NewText(filterBox, "OVERLAY", "disabled")
	ph:SetPoint("LEFT", filterBox, "LEFT", 6, 0)
	ph:SetText("search")
	filterBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

	local area = CreateFrame("Frame", nil, page)
	area:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -26)
	area:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)

	list = Blackie.ScrollList.New(area, { rowHeight = 18 })
	list:SetRenderer(function(f, item)
		local r = item.row
		f.label:SetText(r.name or ("recipe " .. tostring(r.recipeID or r.itemId or "?")))
		local band = nil
		if curSkill and Blackie.SkillupModel then
			band = Blackie.SkillupModel.band(r, curSkill)
		end
		local c = (band and BAND_COLORS[band]) or { 0.85, 0.85, 0.85 }
		f.label:SetTextColor(c[1], c[2], c[3])
		f.sub:SetText(format("skill %d%s%s", r.requiredSkill or 0,
			band and (" | " .. band) or "",
			item.known and " | known" or ""))
	end)
	list:SetHooks({ onEnter = onEnterRow, onLeave = onLeaveRow })

	Panel.AddFooterButton("rescan tradeskill", function()
		local ok, n = Blackie.RecipeCache.upsertFromScan(true)
		refresh()
		if ok then Blackie:Print("recipes rescheduled: " .. tostring(n)) end
	end)
end

local function show()
	refresh()
end

Panel.RegisterTab("Recipes", { build = build, show = show })
