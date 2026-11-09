-- Blackie: shared namespace, version, SavedVariables helpers.
local Blackie = {}
Blackie.version = "0.1.0"
_G.Blackie = Blackie

function Blackie:Print(...)
	local parts = { ... }
	for i = 1, #parts do parts[i] = tostring(parts[i]) end
	(DEFAULT_CHAT_FRAME or ChatFrame1):AddMessage("|cff33ccffBlackie:|r " .. table.concat(parts, " "))
end

function Blackie.DB()
	if not BlackieDB then BlackieDB = {} end
	BlackieDB.version = BlackieDB.version or Blackie.version
	return BlackieDB
end

function Blackie.profileKey()
	return (GetRealmName() or "Realm") .. " - " .. (UnitName("player") or "Player")
end

function Blackie.Profile()
	local db = Blackie.DB()
	db.profiles = db.profiles or {}
	local key = Blackie.profileKey()
	if not db.profiles[key] then
		db.profiles[key] = { known = {}, settings = { target = 225 } }
	end
	local p = db.profiles[key]
	p.known = p.known or {}
	p.settings = p.settings or { target = 225 }
	return p
end
