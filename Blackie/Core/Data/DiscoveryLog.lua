-- Blackie.DiscoveryLog: append-only journal of things seen during play.
-- Feels like a cheap "game telemetry -> dataset" pipeline: loot windows,
-- trainer scans, vendor scans. Kept small and capped.

local Blackie = Blackie
if not Blackie or not Blackie.DB then return end

Blackie.DiscoveryLog = Blackie.DiscoveryLog or {}
local DL = Blackie.DiscoveryLog
local Util = Blackie.Util

local MAX_ENTRIES = 800

local function log()
	local db = Blackie.DB()
	db.discoveryLog = db.discoveryLog or {}
	return db.discoveryLog
end

local function epoch()
	return time and time() or (GetTime and GetTime() or 0)
end

function DL.record(kind, itemID, name, qty, note)
	if not kind then return end
	local l = log()
	-- Cap oldest first; entries are roughly append-ordered.
	while #l >= MAX_ENTRIES do table.remove(l, 1) end
	l[#l + 1] = {
		ts = epoch(), kind = kind,
		itemID = (type(itemID) == "number" and itemID > 0) and itemID or nil,
		name = type(name) == "string" and name or nil,
		qty = (type(qty) == "number" and qty) or 1,
		note = note,
	}
end

-- Count how often an item has been seen (inventory-pressure hints for Costing).
function DL.seenCount(itemID)
	local n = 0
	for _, e in ipairs(log()) do
		if e.itemID == itemID then n = n + 1 end
	end
	return n
end

function DL.attachPlayerHandlers()
	if DL.attached then return end
	DL.attached = true
	-- Dispatch passes world varargs: for CHAT_MSG_LOOT that is (text, ...).
	Blackie.Events.On("CHAT_MSG_LOOT", function(text)
		if type(text) ~= "string" then return end
		local id = tonumber(text:match("|Hitem:(%d+)"))
		local name = text:match("%[(.-)%]")
		if not id then id = Util.idFromLink(text) end
		if id then
			DL.record("loot", id, name, 1)
		end
	end)
end
