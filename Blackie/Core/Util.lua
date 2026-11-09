-- Blackie.Util: pure helpers, no game API access.
local Blackie = Blackie
local Util = {}
Blackie.Util = Util

function Util.safePCall(fn, ...)
	if type(fn) ~= "function" then return false, "not-a-function" end
	return pcall(fn, ...)
end

function Util.money(copper)
	copper = math.floor(copper or 0)
	if copper < 0 then copper = 0 end
	local g = math.floor(copper / 10000)
	local r = copper % 10000
	local s = math.floor(r / 100)
	local c = r % 100
	local out = {}
	if g > 0 then out[#out + 1] = g .. "g" end
	if s > 0 then out[#out + 1] = s .. "s" end
	if c > 0 or #out == 0 then out[#out + 1] = c .. "c" end
	return table.concat(out, " ")
end

function Util.parseMoney(s)
	-- "4g55s37c", "4g 55s", "37c" -> copper
	if not s then return nil end
	s = tostring(s)
	local total = 0
	local g = s:match("(%d+)g")
	local si = s:match("(%d+)s")
	local c = s:match("(%d+)c")
	if not (g or si or c) then
		local num = tonumber(s)
		if num then return math.floor(num) end -- plain number = copper
		return nil
	end
	if g then total = total + tonumber(g) * 10000 end
	if si then total = total + tonumber(si) * 100 end
	if c then total = total + tonumber(c) end
	return total
end

function Util.count(t)
	local n = 0
	for _ in pairs(t or {}) do n = n + 1 end
	return n
end

function Util.newSet(items)
	local s = {}
	for _, v in ipairs(items or {}) do s[v] = true end
	return s
end

function Util.contains(list, v)
	for _, x in ipairs(list or {}) do
		if x == v then return true end
	end
	return false
end

function Util.clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

function Util.copy(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = v end
	return out
end

function Util.fieldOf(info, names)
	-- returns {name, value} of the first candidate field that is non-nil/secret
	if not info then return nil end
	for _, n in ipairs(names) do
		local v = info[n]
		if v ~= nil and v ~= "secret" then return n, v end
	end
	return nil
end

function Util.fieldVal(info, names)
	local _, v = Util.fieldOf(info, names)
	return v
end

function Util.idFromLink(link)
	if not link or type(link) ~= "string" then return nil end
	return tonumber(link:match("|Hitem:(%d+)")) or tonumber(link:match("item:(%d+)"))
end

function Util.spellIDFromLink(link)
	if not link or type(link) ~= "string" then return nil end
	return tonumber(link:match("|Hspell:(%d+)")) or tonumber(link:match("spell:(%d+)"))
end

function Util.quoteLink(link)
	if not link then return nil end
	local id = Util.idFromLink(link)
	if id then return "|cffffd000|Hitem:" .. id .. ":h0|h|h" end
	local sp = Util.spellIDFromLink(link)
	if sp then return "|cffffd000|Hspell:" .. sp .. "|h|h" end
	return link
end

function Util.parseSkillRange(s)
	-- "1-225", "225" -> from, to
	if not s then return nil end
	local a, b = s:match("^(%d+)%s*[%-–]%s*(%d+)$")
	if a then return tonumber(a), tonumber(b) end
	local n = tonumber(s)
	if n then return nil, n end
	return nil
end

function Util.splitSimple(s)
	local out = {}
	for w in tostring(s or ""):gmatch("%S+") do out[#out + 1] = w end
	return out
end

function Util.trim(s)
	return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function Util.formatLine(cols, widths)
	-- fixed width columns for console output
	local out = {}
	for i, col in ipairs(cols) do
		local w = widths and widths[i]
		if w then
			local str = tostring(col or "")
			if #str > w then str = str:sub(1, w - 1) .. ">" end
			out[#out + 1] = str .. string.rep(" ", math.max(0, w - #str))
		else
			out[#out + 1] = tostring(col or "")
		end
	end
	return table.concat(out, "")
end
