-- Blackie.Main: initialization orchestration.

local Blackie = Blackie
if not Blackie then return end

Blackie.Main = Blackie.Main or {}

local initialized = false

local function init()
	if initialized then return end
	initialized = true

	Blackie.Profile() -- ensures data shape

	if Blackie.Commands then Blackie.Commands.Init() end
	if Blackie.CutShort then Blackie.CutShort.Init() end
	if Blackie.DiscoveryLog then Blackie.DiscoveryLog.attachPlayerHandlers() end
	if Blackie.MinimapButton then pcall(Blackie.MinimapButton.Create) end

	-- One silent recipe refresh shortly after login (cheap once a driver is pinned).
	Blackie.Events.After(2, function()
		if Blackie.RecipeCache and Blackie.Compat.tsScanAvailable()
			and Blackie.Compat.tsScanAvailable() ~= false then
			Blackie.RecipeCache.upsertFromScan(true)
		end
	end) -- no-op until Batch G

	local ci = Blackie.Compat.clientInfo()
	Blackie:Print(format("v%s loaded (iface %s) — click the minimap button or type /blackie to open the panel",
		Blackie.version, tostring(ci.interface)))
end

-- Events.Dispatch passes only the world-event varargs (no frame, no event name).
-- For ADDON_LOADED that is the loaded addon name.
Blackie.Events.On("ADDON_LOADED", function(loadedName)
	if loadedName == "Blackie" then init() end
end)

-- Belt-and-suspenders: some 16xx loaders may have fired ADDON_LOADED already;
-- the ticker-driven fallback runs init once frames are live.
Blackie.Events.After(0.5, init)
