-- Blackie.SkillupModel: estimated difficulty band + skill gain for a recipe at a
-- given skill level. Calibrated from the fan-guide observation
-- "recipe skill 15: Yellow at 15, Grey at 55" -> grey band = requiredSkill + GREY_SPAN.
-- Pure data model; tweak the constants from live calibration later.

local Blackie = Blackie
if not Blackie then return end

Blackie.SkillupModel = Blackie.SkillupModel or {}
local SM = Blackie.SkillupModel

-- Tunable band offsets relative to recipe.requiredSkill (player skill s):
--   s >= r + GREY_SPAN               -> grey   (no gain, waste)
--   r + YELLOW_SPAN <= s < GREY_SPAN-> green
--   r <= s < r + YELLOW_SPAN         -> yellow
--   r - ORANGE_SPAN <= s < r         -> orange (gain but failure risk)
--   s < r - ORANGE_SPAN              -> red    (avoid)
SM.GREY_SPAN = 40
SM.YELLOW_SPAN = 5
SM.ORANGE_SPAN = 10

-- Estimated skill gained per successful craft. Vanilla-ish: any craftable
-- (non-grey/non-red) craft gives +1; orange also carries failure risk.
SM.GAIN = { grey = 0, green = 1, yellow = 1, orange = 1, red = 0 }

function SM.band(recipe, skill)
	local r = recipe.requiredSkill or 0
	if skill >= r + SM.GREY_SPAN then return "grey" end
	if skill >= r + SM.YELLOW_SPAN then return "green" end
	if skill >= r then return "yellow" end
	if skill >= r - SM.ORANGE_SPAN then return "orange" end
	return "red"
end

function SM.gain(recipe, skill)
	return SM.GAIN[SM.band(recipe, skill)] or 0
end

-- Usable skill window for a recipe (what PathSolver iterates over).
function SM.usableWindow(recipe, allowOrange)
	local r = recipe.requiredSkill or 0
	local lo = allowOrange and (r - SM.ORANGE_SPAN) or r
	local hi = r + SM.GREY_SPAN - 1
	return lo, hi
end

-- Whether the solver should treat a craft at this skill as safe (no fail rolls).
function SM.allowCraft(recipe, skill, allowOrange)
	local b = SM.band(recipe, skill)
	if b == "red" or b == "grey" then return false end
	if b == "orange" and not allowOrange then return false end
	return true
end
