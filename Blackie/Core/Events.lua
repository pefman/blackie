-- Blackie.Events: internal+world event bus with throttling helpers.
local Blackie = Blackie
local Events = {}
Blackie.Events = Events

Events.frame = CreateFrame("Frame")
Events.handlers = {}       -- event -> {fn,...}
Events.registered = {}     -- event -> true (world events registered on frame)
Events.pending = {}        -- internal delayed fires

Events.frame:SetScript("OnEvent", function(self, event, ...)
	Events:Dispatch(event, ...)
end)

function Events.Dispatch(event, ...)
	local list = Events.handlers[event]
	if not list then return end
	for i = 1, #list do
		local ok, err = pcall(list[i], ...)
		if not ok then
			Blackie:Print("Event handler error in " .. tostring(event) .. ": " .. tostring(err))
		end
	end
end

function Events.On(event, fn)
	Events.handlers[event] = Events.handlers[event] or {}
	table.insert(Events.handlers[event], fn)
	if not Events.registered[event] then
		Events.registered[event] = true
		Events.frame:RegisterEvent(event)
	end
end

-- Own ticker (no C_Timer dependency: works on older-classic or modern clients).
Events.timers = {}
Events.frame:SetScript("OnUpdate", function(self, elapsed)
	local now = GetTime()
	for i = #Events.timers, 1, -1 do
		local t = Events.timers[i]
		if t.at <= now then
			table.remove(Events.timers, i)
			local ok, err = pcall(t.fn)
			if not ok then
				Blackie:Print("Timer error: " .. tostring(err))
			end
		end
	end
end)

function Events.After(delay, fn)
	table.insert(Events.timers, { at = GetTime() + (tonumber(delay) or 0), fn = fn })
end

-- Fire an internal event once after `delay` seconds (coalesces repeats).
function Events.FireDelayed(event, delay)
	if Events.pending[event] then return end
	Events.pending[event] = true
	Events.After(delay, function()
		Events.pending[event] = nil
		Events:Dispatch(event)
	end)
end

-- Throttled polling helper: fn runs at most once every `interval` seconds for key.
function Events.everySeconds(key, interval, fn)
	Events._schedulers = Events._schedulers or {}
	local state = Events._schedulers[key]
	if state then
		state.pendingFn = fn
		return
	end
	state = { pendingFn = fn }
	Events._schedulers[key] = state
	local function tick()
		local f = state.pendingFn
		state.pendingFn = nil
		if f then
			local ok, err = pcall(f)
			if not ok then Blackie:Print("Scheduler error: " .. tostring(err)) end
		end
		if state.pendingFn then
			Events.After(interval, tick)
		else
			Events._schedulers[key] = nil
		end
	end
	Events.After(0, tick)
end
