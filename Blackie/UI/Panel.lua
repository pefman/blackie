-- Blackie.Panel: the GUI window (primary interface). Slash commands stay as
-- secondary diagnostics. Tabs self-register from the tab modules; content pages
-- are built lazily on first show. This file never reads strata/attributes off
-- foreign frames (Blizzard frames can expose secret values in Forever).

local Blackie = Blackie
if not Blackie then return end

Blackie.Panel = Blackie.Panel or {}
local P = Blackie.Panel

local Util = Blackie.Util

P.tabNames = {}
P.tabDefs = {}
local pageFrames = {}
local tabButtons = {}
local footerButtons = {}
local built = false
local activeTab = nil
local main, statusText, contentArea, footerBar, versionText
local dragging, dragByX, dragByY, engineDragging = false, 0, 0, false

-- Font helper: inherits the client default font, upgrading to the familiar
-- game fonts only when they exist (FrameXML availability is not guaranteed).
local FONT_OBJECTS = {
	normal = { "GameFontNormal", "SystemFont_S" },
	large = { "GameFontNormalLarge", "GameFontNormal" },
	small = { "GameFontNormalSmall", "GameFontNormal" },
	disabled = { "GameFontDisable", "GameFontNormalSmall" },
	highlight = { "GameFontHighlight", "GameFontNormal" },
	red = { "GameFontRed", "GameFontNormal" },
	yellow = { "GameFontYellow", "GameFontNormal" },
}

function P.NewText(parent, layer, kind)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	local cands = FONT_OBJECTS[kind or "normal"]
	if cands then
		for _, name in ipairs(cands) do
			local obj = _G[name]
			if obj then
				pcall(function() fs:SetFontObject(obj) end)
				break
			end
		end
	end
	return fs
end

local function makeButton(parent, w, h)
	local okB, b = pcall(CreateFrame, "Button", nil, parent, "UIPanelButtonTemplate")
	if not okB or not b then b = CreateFrame("Button", nil, parent) end
	b:SetSize(w or 96, h or 22)
	return b
end

-- Labels are always our own FontStrings (colored via P.NewText); the built-in
-- button text mechanism differs too much between client families.
local function buttonLabel(b, text, kind)
	local fs = P.NewText(b, "OVERLAY", kind)
	fs:SetPoint("CENTER", b, "CENTER", 0, 1)
	fs:SetText(text)
	b.label = fs
	return fs
end

-- ---------------------------------------------------------------------------
-- Tab registration (called at load time by the tab modules)
-- ---------------------------------------------------------------------------
function P.RegisterTab(name, def)
	if not P.tabDefs[name] then
		P.tabNames[#P.tabNames + 1] = name
	end
	P.tabDefs[name] = def
	if built and not activeTab then
		P.SetActiveTab(name)
	end
end

function P.AddFooterButton(label, onClick)
	if not built then
		footerButtons[#footerButtons + 1] = { label = label, onClick = onClick }
		return
	end
	P.BuildFooterButton({ label = label, onClick = onClick })
end

function P.BuildFooterButton(spec)
	local b = makeButton(footerBar, 110, 22)
	local x = -8 - (#footerButtons - 1) * 114
	b:SetPoint("BOTTOMRIGHT", footerBar, "BOTTOMRIGHT", x, 2)
	buttonLabel(b, spec.label, "normal")
	b:SetScript("OnClick", function()
		local ok, err = pcall(spec.onClick)
		if not ok then Blackie:Print("panel action failed: " .. tostring(err)) end
	end)
	footerButtons[#footerButtons + 1] = spec
	return b
end

-- ---------------------------------------------------------------------------
-- Build the window once
-- ---------------------------------------------------------------------------
local function savePosition()
	if not main then return end
	local w, h = UIParent:GetWidth(), UIParent:GetHeight()
	if not w or w <= 0 or not h or h <= 0 then return end
	local p = Blackie.Profile()
	p.settings = p.settings or {}
	p.settings.panelPos = {
		x = (main:GetLeft() or 0) / w,
		y = (main:GetBottom() or 0) / h,
	}
end

local function restorePosition()
	local p = Blackie.Profile()
	local pos = p.settings and p.settings.panelPos
	if pos and pos.x and pos.y then
		main:ClearAllPoints()
		main:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT",
			pos.x * UIParent:GetWidth(), pos.y * UIParent:GetHeight())
	else
		main:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end
end

local function EnsureBuilt()
	if built then return end
	built = true

	local okM, f = pcall(CreateFrame, "Frame", "BlackiePanel", UIParent, "BackdropTemplate")
	main = (okM and f) or CreateFrame("Frame", "BlackiePanel", UIParent)
	main:SetSize(660, 440)
	main:SetFrameStrata("DIALOG") -- only our own frame; never query foreign strata
	main:SetMovable(true)
	main:EnableMouse(true)
	main:RegisterForDrag("LeftButton")
	main:SetClampedToScreen(true)
	main:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
	})
	if main.SetBackdropColor then main:SetBackdropColor(0.07, 0.07, 0.09, 0.94) end
	restorePosition()
	main:Hide()

	-- title bar -------------------------------------------------------------
	local title = P.NewText(main, "OVERLAY", "large")
	title:SetPoint("TOPLEFT", main, "TOPLEFT", 16, -10)
	title:SetText("Blackie — Blacksmithing Companion")

	local close = makeButton(main, 26, 26)
	close:SetPoint("TOPRIGHT", main, "TOPRIGHT", -10, -8)
	buttonLabel(close, "X", "normal")
	close:SetScript("OnClick", function() P.Hide() end)

	statusText = P.NewText(main, "OVERLAY", "small")
	statusText:SetPoint("TOPRIGHT", main, "TOPRIGHT", -44, -14)

	-- tab strip -------------------------------------------------------------
	for i, name in ipairs(P.tabNames) do
		local b = makeButton(main, 120, 24)
		b.registeredOrder = i
		if i == 1 then
			b:SetPoint("TOPLEFT", main, "TOPLEFT", 12, -38)
		else
			b:SetPoint("TOPLEFT", tabButtons[P.tabNames[i - 1]], "TOPRIGHT", 4, 0)
		end
		buttonLabel(b, name, "normal")
		b:SetScript("OnClick", function() P.SetActiveTab(name) end)
		tabButtons[name] = b
	end

	-- content + footer areas --------------------------------------------------
	footerBar = CreateFrame("Frame", nil, main)
	footerBar:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT", 8, 6)
	footerBar:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -8, 6)
	footerBar:SetHeight(26)

	contentArea = CreateFrame("Frame", nil, main)
	contentArea:SetPoint("TOPLEFT", main, "TOPLEFT", 12, -66)
	contentArea:SetPoint("BOTTOMRIGHT", footerBar, "TOPRIGHT", 0, 4)

	versionText = P.NewText(main, "OVERLAY", "small")
	versionText:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT", 16, 34)
	versionText:SetText("v" .. (Blackie.version or "?"))

	-- drag handling: engine movement when available, manual as fallback ----
	main:SetScript("OnDragStart", function(self)
		dragging = true
		engineDragging = false
		local ok = pcall(function() self:StartMoving() end)
		if ok and self.StartMoving then engineDragging = true end
		if not engineDragging then
			local scale = UIParent:GetEffectiveScale()
			local cx, cy = GetCursorPosition()
			dragByX = cx / scale - (self:GetLeft() or 0)
			dragByY = cy / scale - (self:GetBottom() or 0)
		end
	end)
	main:SetScript("OnDragStop", function(self)
		dragging = false
		if engineDragging then pcall(function() self:StopMovingOrSizing() end) end
		engineDragging = false
		savePosition()
	end)
	main:SetScript("OnUpdate", function(self)
		if dragging and not engineDragging then
			local scale = UIParent:GetEffectiveScale()
			local cx, cy = GetCursorPosition()
			self:ClearAllPoints()
			self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT",
				cx / scale - dragByX, cy / scale - dragByY)
		end
	end)

	main:EnableKeyboard(true)
	main:SetPropagateKeyboardInput(true)
	main:SetScript("OnKeyDown", function(self, key)
		if key == "ESCAPE" then P.Hide() end
	end)

	-- queued footer buttons (registered before the window existed) ----------
	local queued = footerButtons
	footerButtons = {}
	for _, spec in ipairs(queued) do
		P.BuildFooterButton(spec)
	end

	main:SetScript("OnShow", function()
		P.RefreshStatus()
		if activeTab and P.tabDefs[activeTab] and P.tabDefs[activeTab].show then
			P.tabDefs[activeTab].show()
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Tab switching
-- ---------------------------------------------------------------------------
function P.EnsurePage(name)
	local def = P.tabDefs[name]
	if not def then return nil end
	if not pageFrames[name] then
		local page = CreateFrame("Frame", nil, contentArea)
		page:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 0, 0)
		page:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", 0, 0)
		page:Hide()
		pageFrames[name] = page
		if def.build then def.build(page) end
	end
	return pageFrames[name]
end

local function paintTabButton(name)
	local b = tabButtons[name]
	if not b then return end
	local active = (name == activeTab)
	local fs = b.label
	if fs then
		fs:SetTextColor(active and 1 or 0.72, active and 0.92 or 0.72, active and 0.35 or 0.65)
	end
	if b.SetChecked then pcall(b.SetChecked, active) end
end

local function runTabShow(name)
	local def = P.tabDefs[name]
	if def and def.show then
		local ok, err = pcall(def.show)
		if not ok then Blackie:Print("panel tab failed: " .. tostring(err)) end
	end
end

function P.SetActiveTab(name)
	if not P.tabDefs[name] then return end
	if built then P.EnsurePage(name) end
	activeTab = name
	for tabName, page in pairs(pageFrames) do
		if tabName == name then page:Show() else page:Hide() end
	end
	for tabName in pairs(tabButtons) do paintTabButton(tabName) end
	if main and main:IsShown() then runTabShow(name) end
end

-- ---------------------------------------------------------------------------
-- Show / hide / status
-- ---------------------------------------------------------------------------
function P.RefreshStatus()
	if not statusText then return end
	local skill = "?"
	if Blackie.Compat and Blackie.Compat.currentSkill then
		local ok, v = pcall(Blackie.Compat.currentSkill)
		if ok and type(v) == "number" then skill = tostring(v) end
	end
	local target = "?"
	local p = Blackie.Profile()
	if p.settings and p.settings.target then target = tostring(p.settings.target) end
	statusText:SetText(format("Blacksmithing %s/300  |  target %s", skill, target))
end

function P.Show(tabName)
	EnsureBuilt()
	if not main then return end
	if not activeTab then
		activeTab = tabName or P.tabNames[1]
	end
	if tabName then activeTab = tabName end
	if not pageFrames[activeTab] then P.EnsurePage(activeTab) end
	for tabName, page in pairs(pageFrames) do
		if tabName == activeTab then page:Show() else page:Hide() end
	end
	for tabName in pairs(tabButtons) do paintTabButton(tabName) end
	main:Show()
	main:Raise()
end

function P.Hide()
	if main then main:Hide() end
end

function P.Toggle(tabName)
	EnsureBuilt()
	if not main then return end
	if main:IsShown() then P.Hide() else P.Show(tabName) end
end

function P.IsShown()
	return main and main:IsShown()
end
