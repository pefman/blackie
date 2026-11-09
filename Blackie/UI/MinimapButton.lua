-- Blackie.MinimapButton: minimap quick-launch for the panel.
-- Wrapped ENTIRELY in pcall: 1.60.1 Beta 5 reorganized the minimap header and
-- textures, so button parenting/quadrants may differ per build. We only ever
-- set attributes on our own frame (no GetFrameStrata reads on foreign frames).

local Blackie = Blackie
if not Blackie or not Blackie.Panel then return end

Blackie.MinimapButton = Blackie.MinimapButton or {}
local MB = Blackie.MinimapButton

MB.button = nil

local ICON_NORMAL = "Interface\\Icons\\inv_misc_punchcards_blacksmith"
local ICON_PUSHED = "Interface\\Buttons\\ButtonPushed-Down"
local ICON_HIGHLIGHT = "Interface\\Buttons\\Button-Highlight"

function MB.Create()
	if MB.button then return true end
	if not Minimap then return false end

	local ok, err = pcall(function()
		local size = 24
		local scale = 1
		if Minimap.GetScale then
			local sMinimap = Minimap:GetScale()
			if sMinimap and sMinimap > 0 then scale = sMinimap end
		end

		local b = CreateFrame("Button", "BlackieMinimapButton", Minimap)
		b:SetSize(size * scale, size * scale)
		b:SetFrameStrata("HIGH") -- our own frame only
		b:RegisterForClicks("AnyUp")
		b:SetClampedToScreen(true)

		local tex = b:CreateTexture(nil, "BACKGROUND")
		tex:SetAllPoints(b)
		tex:SetTexture(ICON_NORMAL)
		if tex.SetTexCoord then tex:SetTexCoord(0.07, 0.93, 0.07, 0.93) end

		local pushed = b:CreateTexture(nil, "BACKGROUND")
		pushed:SetAllPoints(b)
		pushed:SetTexture(ICON_PUSHED)
		pushed:SetVertexColor(0.6, 0.6, 0.6)
		b:SetPushedTexture(pushed)

		if b.SetHighlightTexture then
			local hl = b:CreateTexture(nil, "OVERLAY")
			hl:SetAllPoints(b)
			hl:SetTexture(ICON_HIGHLIGHT)
			hl:SetBlendMode("ADD")
			pcall(b.SetHighlightTexture, b, hl)
		end

		-- bottom-left quadrant, the classic stable corner
		b:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, -4)
		if b.SetSwipePrevented then pcall(b.SetSwipePrevented, b, true) end

		b:SetScript("OnClick", function()
			Blackie.Panel.Toggle()
		end)
		b:SetScript("OnEnter", function(self)
			pcall(function()
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText("Blackie — blacksmithing companion", 1, 0.9, 0.35)
				GameTooltip:AddLine("Click to open the panel.", 0.8, 0.8, 0.8)
				GameTooltip:Show()
			end)
		end)
		b:SetScript("OnLeave", function()
			pcall(function() GameTooltip:Hide() end)
		end)

		MB.button = b
	end)
	if not ok then
		Blackie:Print("MinimapButton: setup failed (" .. tostring(err) .. ") — use /blackie to open the panel.")
		return false
	end
	return true
end
