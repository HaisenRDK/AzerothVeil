-- AzerothVeil — Core/ModuleManager.lua
-- Registers the modules, keeps their settings, and starts and stops them.
--
-- A module is declared once, from its own file (Modules/<Name>.lua), with ns.Modules:Register{ ... }:
--
--   name            unique id (lower case), the key of its settings in AzerothVeilDB.modules
--   title, description, order        what the options window shows (order: its place in the list)
--   defaultEnabled  on or off the first time (default true)
--   dependencies    { "otherModule", ... }  AzerothVeil modules that must be active for it to run
--   requiresAddOns  { "AddOn", ... }        other addons that must be loaded for it to run
--   conflictsWithAddOns { "AddOn", ... }    other addons that, loaded, take its place (it then doesn't run)
--   reloadOnDisable true when it changes things that can't be undone without a /reload (hooksecurefunc,
--                   a secure template...): turning it off then asks for a reload
--   settings        { { key, type, default, label, tooltip, ... }, ... }  declarative (UI/Options.lua builds
--                   the controls from it). type: "toggle" (boolean), "range" (number: min, max, step),
--                   "header" (a title in the options, no value), "hidden" (stored, never shown).
--                   parent = "key": the option only counts (and is only editable) while that toggle is on.
--   Initialize(self)            once, just before its first Enable (never for a module that never runs)
--   Enable(self)                it starts: its events, frames, hooks...
--   Disable(self)               it stops and lets go of what it holds
--   Refresh(self, key, value)   one of its settings changed while it runs
--
-- Lifecycle and rules
--  * "enabled" is what the user asked for (saved). "active" is whether it runs now: enabled, its addons
--    there, its dependencies active, its conflicting addons absent, and the player logged in.
--  * Nothing of a module runs before its Enable or after its Disable. Its events, messages and timers
--    taken through its own helpers (self:RegisterEvent, self:RegisterMessage, self:After, self:NewTicker)
--    are let go by the manager after its Disable, even if Disable forgot them.
--  * A disabled module's settings are kept as they were and come back when it's enabled again.
--  * IsOptionActive(name, key) is false whenever the module isn't active, whatever the saved value.
--  * Disabling only stops it: its Lua file stays loaded (WoW loads every file in the .toc and can't
--    unload one). Its code costs memory, not time. Hooks on Blizzard's functions can't be removed: a
--    module that makes some must check IsActive() in them and say reloadOnDisable = true.
local _, ns = ...
local L = ns.L

local MM = { list = {}, byName = {}, started = false, settingsLoaded = false }
ns.Modules = MM

local Module = {}           -- the methods every module gets
Module.__index = Module

local VALID_TYPES = { toggle = true, range = true, header = true, hidden = true }

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------
function MM:Register(def)
	assert(type(def) == "table", "Modules:Register: a table is expected")
	local name = def.name
	assert(type(name) == "string" and name:match("^[%w_]+$"), "Modules:Register: name must be a word")
	assert(not self.byName[name], "Modules:Register: a module named '" .. name .. "' already exists")
	local m = setmetatable(def, Module)
	m.title = m.title or name
	m.order = m.order or 100
	if m.defaultEnabled == nil then m.defaultEnabled = true end
	m.dependencies = m.dependencies or {}
	m.requiresAddOns = m.requiresAddOns or {}
	m.conflictsWithAddOns = m.conflictsWithAddOns or {}
	m.settings = m.settings or {}
	m.settingByKey = {}
	for _, s in ipairs(m.settings) do
		assert(VALID_TYPES[s.type], ("Modules:Register(%s): unknown setting type '%s'"):format(name, tostring(s.type)))
		if s.type ~= "header" then
			assert(type(s.key) == "string", ("Modules:Register(%s): a setting needs a key"):format(name))
			m.settingByKey[s.key] = s
		end
	end
	m.active = false
	m.initialized = false
	m.reason = nil
	m._timers = {}
	self.list[#self.list + 1] = m
	self.byName[name] = m
	if self.settingsLoaded then self:LoadModuleSettings(m) end
	if self.started then self:Evaluate() end
	return m
end

function MM:Get(name) return self.byName[name] end

-- the modules in the options' order
function MM:Sorted()
	local out = {}
	for i, m in ipairs(self.list) do out[i] = m end
	table.sort(out, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return a.title < b.title
	end)
	return out
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
local function Coerce(spec, value)
	if spec.type == "toggle" then
		return value and true or false
	elseif spec.type == "range" then
		value = tonumber(value)
		if not value then return nil end
		if spec.min and value < spec.min then value = spec.min end
		if spec.max and value > spec.max then value = spec.max end
		return value
	end
	return value
end

function MM:LoadModuleSettings(m)
	local entry = ns.Database.Module(m.name)
	if type(entry.enabled) ~= "boolean" then entry.enabled = m.defaultEnabled end
	local settings = entry.settings
	for key, spec in pairs(m.settingByKey) do
		local v = settings[key]
		if v == nil or (spec.default ~= nil and type(v) ~= type(spec.default)) then
			settings[key] = spec.default
		elseif spec.type == "range" then
			settings[key] = Coerce(spec, v)
		end
	end
	m.entry = entry
	m.db = settings                -- (the module reads its settings here, live)
end

-- At SETTINGS_LOADED (Core/Bootstrap.lua): each module's saved entry, its defaults filled in
function MM:LoadSettings()
	self.settingsLoaded = true
	for _, m in ipairs(self.list) do self:LoadModuleSettings(m) end
end

-- the saved value, whatever the module's state (the options show it greyed out while it's off)
function MM:GetSetting(name, key)
	local m = self.byName[name]
	if not (m and m.db) then return nil end
	return m.db[key]
end

-- whether an option is in effect: the module active, the option on, and its parent option too
function MM:IsOptionActive(name, key)
	local m = self.byName[name]
	if not (m and m.active and m.db) then return false end
	local spec = m.settingByKey[key]
	if spec and spec.parent and not self:IsOptionActive(name, spec.parent) then return false end
	return m.db[key] and true or false
end

-- whether an option can be changed now (the options window greys the others)
function MM:IsOptionEditable(name, key)
	local m = self.byName[name]
	if not (m and m.db and m.entry.enabled) then return false end
	local spec = m.settingByKey[key]
	if spec and spec.parent then return self:IsOptionEditable(name, spec.parent) and m.db[spec.parent] and true or false end
	return true
end

function MM:SetSetting(name, key, value)
	local m = self.byName[name]
	assert(m, "Modules:SetSetting: no module '" .. tostring(name) .. "'")
	assert(m.db, "Modules:SetSetting: the settings aren't loaded yet")
	local spec = m.settingByKey[key]
	if spec then value = Coerce(spec, value) end
	if value == nil and spec and spec.default ~= nil then value = spec.default end
	if m.db[key] == value then return end
	m.db[key] = value
	-- (a module that doesn't run isn't told: it reads its settings when it's enabled)
	if m.active and m.Refresh then ns.SafeCall(m.Refresh, m, key, value) end
	ns.Callbacks:Fire("MODULE_SETTING_CHANGED", name, key, value)
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
function MM:IsEnabled(name)
	local m = self.byName[name]
	return m and m.entry and m.entry.enabled and true or false
end

function MM:IsActive(name)
	local m = self.byName[name]
	return m and m.active or false
end

-- "active", "disabled" or "unavailable", and why (a text) when it's unavailable
function MM:State(name)
	local m = self.byName[name]
	if not m then return "unknown" end
	if m.active then return "active" end
	if m.entry and not m.entry.enabled then return "disabled" end
	return "unavailable", m.reason
end

-- the modules that depend on this one (directly)
function MM:Dependents(name)
	local out = {}
	for _, m in ipairs(self.list) do
		for _, d in ipairs(m.dependencies) do
			if d == name then out[#out + 1] = m.name break end
		end
	end
	return out
end

function MM:SetEnabled(name, on)
	local m = self.byName[name]
	assert(m, "Modules:SetEnabled: no module '" .. tostring(name) .. "'")
	assert(m.entry, "Modules:SetEnabled: the settings aren't loaded yet")
	on = on and true or false
	if m.entry.enabled == on then return end
	m.entry.enabled = on
	if not on and m.reloadOnDisable and m.initialized then m.needsReload = true end
	if on then m.needsReload = nil end
	self:Evaluate()
	-- (asked for, whatever came of it: the option screens show it, even a module that can't run)
	ns.Callbacks:Fire("MODULE_ENABLED_CHANGED", name, on)
end
function MM:Enable(name) self:SetEnabled(name, true) end
function MM:Disable(name) self:SetEnabled(name, false) end

-- why it can't run (nil: it can); should: the modules already known to be running once this is done
local function Blocker(self, m, should)
	if not m.entry.enabled then return "disabled" end
	for _, addon in ipairs(m.requiresAddOns) do
		if not ns.IsAddOnLoaded(addon) then return L["Requires the addon %s"]:format(addon) end
	end
	for _, addon in ipairs(m.conflictsWithAddOns) do
		if ns.IsAddOnLoaded(addon) then return L["%s is loaded and takes its place"]:format(addon) end
	end
	for _, dep in ipairs(m.dependencies) do
		local d = self.byName[dep]
		if not d then return L["Requires the module %s"]:format(dep) end
		if not should[d] then return L["Requires the module %s"]:format(d.title) end
	end
	if m.failed then return m.reason end
	return nil
end

-- the modules with each one after those it depends on; the ones in a cycle are returned apart
local function TopoOrder(self)
	local order, mark, cyclic = {}, {}, {}
	local function Visit(m)
		if mark[m] == "done" then return true end
		if mark[m] == "visiting" then return false end
		mark[m] = "visiting"
		local ok = true
		for _, dep in ipairs(m.dependencies) do
			local d = self.byName[dep]
			if d and not Visit(d) then ok = false end
		end
		mark[m] = "done"
		if ok then order[#order + 1] = m else cyclic[m] = true end
		return ok
	end
	for _, m in ipairs(self:Sorted()) do Visit(m) end
	return order, cyclic
end

local function CleanUp(m)
	ns.Events:UnregisterAll(m)
	ns.Callbacks:UnregisterAll(m)
	for t in pairs(m._timers) do t:Cancel() end
	wipe(m._timers)
end

local function Deactivate(self, m)
	if not m.active then return end
	m.active = false
	if m.Disable then ns.SafeCall(m.Disable, m) end
	CleanUp(m)
	ns.Callbacks:Fire("MODULE_STATE_CHANGED", m.name, false)
end

local function Activate(self, m)
	if m.active then return end
	if not m.initialized then
		m.initialized = true
		if m.Initialize and not ns.SafeCall(m.Initialize, m) then
			m.initialized = false             -- (tried again the next time it's enabled)
			m.reason = L["Error while starting (see the error report)"]
			m.failed = true
			CleanUp(m)
			return
		end
	end
	m.active = true
	if m.Enable and not ns.SafeCall(m.Enable, m) then
		m.reason = L["Error while starting (see the error report)"]
		m.failed = true
		m.active = false
		if m.Disable then ns.SafeCall(m.Disable, m) end
		CleanUp(m)
		return
	end
	ns.Callbacks:Fire("MODULE_STATE_CHANGED", m.name, true)
end

-- Brings every module to the state it should be in. First which ones should run (dependencies first,
-- so a module is known to run before those that need it are looked at); then those that must stop stop
-- (the most dependent first: a module never runs while one it needs is stopped); then those that may
-- start start (dependencies first; one whose dependency failed to start stays off).
function MM:Evaluate()
	if not (self.started and self.settingsLoaded) then return end
	local order, cyclic = TopoOrder(self)
	for m in pairs(cyclic) do
		m.reason = L["Circular dependency"]
		Deactivate(self, m)
	end
	local should = {}
	for _, m in ipairs(order) do
		if not m.entry.enabled then m.failed = nil end      -- (turned off: a failure is forgotten)
		local reason = Blocker(self, m, should)
		should[m] = reason == nil
		m.reason = (reason ~= "disabled") and reason or nil
	end
	for i = #order, 1, -1 do
		local m = order[i]
		if m.active and not should[m] then Deactivate(self, m) end
	end
	for _, m in ipairs(order) do
		if should[m] and not m.active then
			local ready = true
			for _, dep in ipairs(m.dependencies) do
				local d = self.byName[dep]
				if not (d and d.active) then
					ready = false
					m.reason = L["Requires the module %s"]:format(d and d.title or dep)
				end
			end
			if ready then Activate(self, m) end
		end
	end
end

-- At PLAYER_LOGIN (Core/Bootstrap.lua): every addon is loaded, the game's data is there
function MM:Start()
	self.started = true
	self:Evaluate()
end

---------------------------------------------------------------------------
-- What every module can call on itself
---------------------------------------------------------------------------
function Module:IsActive() return self.active end
function Module:IsEnabled() return MM:IsEnabled(self.name) end
function Module:Get(key) return self.db and self.db[key] end
function Module:Set(key, value) MM:SetSetting(self.name, key, value) end
function Module:IsOptionActive(key) return MM:IsOptionActive(self.name, key) end

-- fn(event, ...): heard only while the module is active
function Module:RegisterEvent(event, fn)
	assert(self.active, "RegisterEvent: only while the module is active (in Enable or later)")
	return ns.Events:Register(self, event, fn)
end
function Module:UnregisterEvent(event) ns.Events:Unregister(self, event) end

function Module:RegisterMessage(message, fn)
	assert(self.active, "RegisterMessage: only while the module is active (in Enable or later)")
	ns.Callbacks:Register(message, self, fn)
end
function Module:UnregisterMessage(message) ns.Callbacks:Unregister(message, self) end
function Module:SendMessage(message, ...) ns.Callbacks:Fire(message, ...) end

-- timers cancelled with the module
function Module:After(seconds, fn)
	assert(self.active, "After: only while the module is active")
	local timers = self._timers
	local t
	t = C_Timer.NewTimer(seconds, function()
		timers[t] = nil
		if self.active then fn() end
	end)
	timers[t] = true
	return t
end
function Module:NewTicker(seconds, fn)
	assert(self.active, "NewTicker: only while the module is active")
	local t = C_Timer.NewTicker(seconds, function() if self.active then fn() end end)
	self._timers[t] = true
	return t
end

function Module:Print(msg)
	if ns.Print then ns.Print(("[%s] %s"):format(self.title, tostring(msg))) end
end

---------------------------------------------------------------------------
-- /av modules [enable|disable <name>]
---------------------------------------------------------------------------
local STATE_TEXT = {
	active = "|cff40ff40" .. L["active"] .. "|r",
	disabled = "|cff999999" .. L["disabled"] .. "|r",
	unavailable = "|cffff8040" .. L["unavailable"] .. "|r",
}

function MM:SlashCommand(args)
	args = args or ""
	local action, name = args:match("^(%a+)%s+([%w_]+)$")
	if action == "enable" or action == "disable" then
		if not self.byName[name] then ns.Print(L["Unknown module: %s"]:format(name)) return end
		self:SetEnabled(name, action == "enable")
		local state, reason = self:State(name)
		ns.Print(("%s: %s%s"):format(name, STATE_TEXT[state] or state, reason and (" (" .. reason .. ")") or ""))
		if self.byName[name].needsReload then ns.Print(L["A /reload is needed to remove it completely."]) end
		if ns.Options and ns.Options.Refresh then ns.Options.Refresh() end
		return
	end
	ns.Print(L["Modules:"])
	for _, m in ipairs(self:Sorted()) do
		local state, reason = self:State(m.name)
		ns.Print(("  %s (%s): %s%s"):format(m.title, m.name, STATE_TEXT[state] or state, reason and (" - " .. reason) or ""))
	end
	ns.Print(L["/av modules enable <name>  |  /av modules disable <name>  |  /av config"])
end
