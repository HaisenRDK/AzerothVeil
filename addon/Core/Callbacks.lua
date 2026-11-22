-- AzerothVeil — Core/Callbacks.lua
-- A small message bus: the way modules and the core talk without depending on each other.
--   ns.Callbacks:Register(message, owner, fn)   fn(message, ...) when the message is fired
--   ns.Callbacks:Unregister(message, owner)
--   ns.Callbacks:UnregisterAll(owner)           (the ModuleManager calls it when a module is disabled)
--   ns.Callbacks:Fire(message, ...)
-- One handler per (message, owner). The order handlers run in is not specified: don't rely on it.
-- An error in one handler is reported and doesn't stop the others.
--
-- Messages used today:
--   SETTINGS_LOADED                     the SavedVariables are read (Engine/Core.lua, at ADDON_LOADED)
--   MODULE_STATE_CHANGED(name, active)  a module was activated or deactivated (Core/ModuleManager.lua)
--   MODULE_SETTING_CHANGED(name, key, value)
local _, ns = ...

local Callbacks = { handlers = {} }
ns.Callbacks = Callbacks

function Callbacks:Register(message, owner, fn)
	assert(type(message) == "string", "Callbacks:Register: message must be a string")
	assert(owner ~= nil, "Callbacks:Register: owner is required")
	assert(type(fn) == "function", "Callbacks:Register: fn must be a function")
	local list = self.handlers[message]
	if not list then
		list = {}
		self.handlers[message] = list
	end
	list[owner] = fn
end

function Callbacks:Unregister(message, owner)
	local list = self.handlers[message]
	if list then list[owner] = nil end
end

function Callbacks:UnregisterAll(owner)
	for _, list in pairs(self.handlers) do list[owner] = nil end
end

function Callbacks:Fire(message, ...)
	local list = self.handlers[message]
	if not list then return end
	-- (a snapshot: a handler may register or unregister others while this runs)
	local snapshot, n = {}, 0
	for _, fn in pairs(list) do
		n = n + 1
		snapshot[n] = fn
	end
	for i = 1, n do ns.SafeCall(snapshot[i], message, ...) end
end
