-- AzerothVeil — Core/Events.lua
-- One frame hearing the game's events for the core and the modules, each handler under an owner so
-- everything an owner registered can be let go at once (a module being disabled).
--   ns.Events:Register(owner, event, fn)   fn(event, ...); false if this client doesn't know the event
--   ns.Events:Unregister(owner, event)
--   ns.Events:UnregisterAll(owner)
-- The game's event is unregistered from the frame as soon as no owner listens to it any more, so a
-- disabled module costs nothing, not even an empty call.
-- (Engine/ files from PerfectMap keep their own event frames as they were: they are not moved here.)
local _, ns = ...

local Events = { handlers = {} }
ns.Events = Events

local frame = CreateFrame("Frame")

frame:SetScript("OnEvent", function(_, event, ...)
	local list = Events.handlers[event]
	if not list then return end
	local snapshot, n = {}, 0
	for _, fn in pairs(list) do
		n = n + 1
		snapshot[n] = fn
	end
	for i = 1, n do ns.SafeCall(snapshot[i], event, ...) end
end)

function Events:Register(owner, event, fn)
	assert(owner ~= nil, "Events:Register: owner is required")
	assert(type(event) == "string", "Events:Register: event must be a string")
	assert(type(fn) == "function", "Events:Register: fn must be a function")
	local list = self.handlers[event]
	if not list then
		-- (an event this client lacks: refused, without breaking the caller)
		if not pcall(frame.RegisterEvent, frame, event) then return false end
		list = {}
		self.handlers[event] = list
	end
	list[owner] = fn
	return true
end

function Events:Unregister(owner, event)
	local list = self.handlers[event]
	if not list then return end
	list[owner] = nil
	if next(list) == nil then
		self.handlers[event] = nil
		frame:UnregisterEvent(event)
	end
end

function Events:UnregisterAll(owner)
	for event in pairs(self.handlers) do self:Unregister(owner, event) end
end

-- (for tests and /av modules: how many handlers listen to an event)
function Events:Count(event)
	local n = 0
	for _ in pairs(self.handlers[event] or {}) do n = n + 1 end
	return n
end
