-- Blackie.ScrollList: reusable vertical list widget shared by all Panel tabs.
-- Plain widgets only (ScrollFrame + Button + Frame:CreateTexture): no FrameXML
-- templates, no mixins, and it never reads strata/attributes off foreign frames.

local Blackie = Blackie
if not Blackie then return end

Blackie.ScrollList = Blackie.ScrollList or {}
local SL = Blackie.ScrollList

local Util = Blackie.Util

local UP_TEX = {
	normal = "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up",
	pushed = "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Down",
	disabled = "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Disabled",
}
local DOWN_TEX = {
	normal = "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up",
	pushed = "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Down",
	disabled = "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Disabled",
}
local KNOB_TEX = "Interface\\Buttons\\UI-ScrollBar-Knob"

local WHEEL_STEPS = 3

local function setSimpleColor(tex, a, b, c, alpha)
	-- SetColorTexture is the modern API; fall back to SetTexture(r,g,b,a).
	if tex.SetColorTexture then
		tex:SetColorTexture(a, b, c, alpha)
	else
		tex:SetTexture(a, b, c, alpha)
	end
end

-- list = SL.New(parent, { rowHeight = 18, rightInset = 20 })
-- The caller sizes/positions `parent`; the ScrollFrame fills it leaving
-- `rightInset` on the right for the scrollbar.
function SL.New(parent, opts)
	opts = opts or {}
	local list = {}
	list.rowHeight = opts.rowHeight or 18
	list.data = {}
	list.offsetPx = 0
	list.rowFrames = {}
	list.hooks = nil
	list.renderer = nil

	local inset = opts.rightInset or 20

	local sf = CreateFrame("ScrollFrame", nil, parent)
	list.frame = sf
	sf:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
	sf:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -inset, 0)

	local content = CreateFrame("Frame", nil, sf)
	list.content = content
	content:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, 0)
	content:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 0, 0)
	content:SetHeight(list.rowHeight)
	sf:SetScrollChild(content)

	-- scrollbar assembly ---------------------------------------------------
	local sb = CreateFrame("Frame", nil, parent)
	sb:SetPoint("TOPLEFT", sf, "TOPRIGHT", 0, 0)
	sb:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 0, 0)
	sb:SetWidth(math.max(16, inset - 2))
	local track = sb:CreateTexture(nil, "BACKGROUND")
	track:SetPoint("TOPLEFT", sb, "TOPLEFT", 4, -2)
	track:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", -4, 2)
	setSimpleColor(track, 0.08, 0.08, 0.10, 0.85)

	local up = CreateFrame("Button", nil, sb)
	up:SetSize(16, 16)
	up:SetPoint("TOP", sb, "TOP", 0, 0)
	up:SetNormalTexture(UP_TEX.normal)
	up:SetPushedTexture(UP_TEX.pushed)
	if up.SetDisabledTexture then up:SetDisabledTexture(UP_TEX.disabled) end

	local down = CreateFrame("Button", nil, sb)
	down:SetSize(16, 16)
	down:SetPoint("BOTTOM", sb, "BOTTOM", 0, 0)
	down:SetNormalTexture(DOWN_TEX.normal)
	down:SetPushedTexture(DOWN_TEX.pushed)
	if down.SetDisabledTexture then down:SetDisabledTexture(DOWN_TEX.disabled) end

	local knob = CreateFrame("Button", nil, sb)
	knob:SetSize(16, 20)
	knob:SetNormalTexture(KNOB_TEX)

	up:SetScript("OnClick", function()
		list:ScrollRows(-(math.max(1, (list:GetVisibleRows() - 1))))
	end)
	down:SetScript("OnClick", function()
		list:ScrollRows(math.max(1, (list:GetVisibleRows() - 1)))
	end)

	-- geometry helpers ------------------------------------------------------
	function list:GetVisibleRows()
		local h = sf:GetHeight()
		if not h or h <= 0 then h = 200 end
		return math.max(1, math.floor((h + 1) / list.rowHeight))
	end

	function list:GetTotalHeight()
		return math.max(#list.data, 1) * list.rowHeight
	end

	function list:GetMaxOffset()
		local h = sf:GetHeight()
		if not h or h <= 0 then h = 200 end
		return math.max(0, list:GetTotalHeight() - h)
	end

	function list:GetTopRow()
		return math.floor(list.offsetPx / list.rowHeight) + 1
	end

	function Sync()
		list.offsetPx = Util.clamp(list.offsetPx, 0, list:GetMaxOffset())
		sf:SetVerticalScroll(list.offsetPx)
		content:SetHeight(list:GetTotalHeight())
		local usable = math.max(1, sb:GetHeight() - knob:GetHeight())
		local ratio = list:GetMaxOffset() > 0 and (list.offsetPx / list:GetMaxOffset()) or 0
		knob:ClearAllPoints()
		knob:SetPoint("TOP", sb, "TOP", 0, -usable * ratio)
		up:SetEnabled(list.offsetPx > 0.5)
		down:SetEnabled(list.offsetPx < list:GetMaxOffset() - 0.5)
	end
	list.Sync = Sync

	local function offsetFromCursor()
		local scale = UIParent:GetEffectiveScale()
		local _, cy = GetCursorPosition()
		cy = cy / scale
		local usable = math.max(1, sb:GetHeight() - knob:GetHeight())
		local ratio = (sb:GetTop() - cy) / usable
		return Util.clamp(ratio, 0, 1) * list:GetMaxOffset()
	end

	sb:EnableMouse(true)
	sb:SetScript("OnMouseDown", function() list.offsetPx = offsetFromCursor(); Sync() end)
	sb:SetScript("OnUpdate", function(self)
		if self.IsMouseButtonDown and self:IsMouseButtonDown() then
			list.offsetPx = offsetFromCursor()
			Sync()
		end
	end)

	sf:EnableMouseWheel(true)
	sf:SetScript("OnMouseWheel", function(_, delta)
		list:ScrollRows(-delta * WHEEL_STEPS)
	end)

	-- row pool ------------------------------------------------------------
	local function ensureRowPool(n)
		while #list.rowFrames < n do
			local i = #list.rowFrames + 1
			local f = CreateFrame("Button", nil, content)
			f:SetHeight(list.rowHeight)
			f:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * list.rowHeight)
			f:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(i - 1) * list.rowHeight)
			f.backdrop = f:CreateTexture(nil, "BACKGROUND")
			f.backdrop:SetAllPoints(f)
			setSimpleColor(f.backdrop, 0, 0, 0, 0)
			-- Panel.NewText is available at call time even though ScrollList loads first
			local function newFontString(kind)
				if Blackie.Panel and Blackie.Panel.NewText then
					return Blackie.Panel.NewText(f, "OVERLAY", kind)
				end
				return f:CreateFontString(nil, "OVERLAY")
			end
			f.label = newFontString("normal")
			f.label:SetPoint("LEFT", f, "LEFT", 6, 0)
			f.sub = newFontString("small")
			f.sub:SetPoint("RIGHT", f, "RIGHT", -8, 0)
			f:SetScript("OnEnter", function(self)
				if list.hooks and list.hooks.onEnter then list.hooks.onEnter(self, self.__item, self.__index) end
			end)
			f:SetScript("OnLeave", function(self)
				if list.hooks and list.hooks.onLeave then list.hooks.onLeave(self, self.__item, self.__index) end
			end)
			f:SetScript("OnClick", function(self)
				if list.hooks and list.hooks.onClick then list.hooks.onClick(self, self.__item, self.__index) end
			end)
			list.rowFrames[i] = f
		end
		for i = n + 1, #list.rowFrames do
			list.rowFrames[i]:Hide()
		end
	end

	function list:SetRenderer(fn) list.renderer = fn end
	function list:SetHooks(hooks) list.hooks = hooks end

	function list:Render()
		local vis = list:GetVisibleRows()
		ensureRowPool(vis + 1)
		local top = list:GetTopRow()
		for i = 1, #list.rowFrames do
			local f = list.rowFrames[i]
			local idx = top + i - 1
			local item = list.data[idx]
			if item then
				f:Show()
				f.__item = item
				f.__index = idx
				if list.renderer then list.renderer(f, item, idx) end
			else
				f.__item = nil
				f.__index = nil
				f:Hide()
				f.label:SetText("")
				f.sub:SetText("")
			end
		end
		Sync()
	end

	function list:SetRows(data)
		list.data = data or {}
		list.offsetPx = Util.clamp(list.offsetPx, 0, list:GetMaxOffset())
		list:Render()
	end

	function list:ScrollRows(rows)
		list.offsetPx = list.offsetPx + rows * list.rowHeight
		Sync()
		list:Render()
	end

	function list:ScrollToRow(rowIndex)
		list.offsetPx = (math.max(1, rowIndex or 1) - 1) * list.rowHeight
		Sync()
		list:Render()
	end

	return list
end
