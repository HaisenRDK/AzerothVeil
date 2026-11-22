-- AzerothVeil — Core/Bootstrap.lua
-- Loaded last: every module is registered by now. Starts the modules at the right moments:
--   SETTINGS_LOADED (Engine/Core.lua, at ADDON_LOADED)  each module's saved settings, defaults filled in
--   PLAYER_LOGIN                                        the enabled modules start (every addon is loaded:
--                                                       their requiresAddOns can be checked)
local _, ns = ...
local L = ns.L

local CORE = "core"           -- (the owner of the core's own handlers)

ns.Callbacks:Register("SETTINGS_LOADED", CORE, function()
	ns.Modules:LoadSettings()
end)

ns.Events:Register(CORE, "PLAYER_LOGIN", function()
	ns.Events:Unregister(CORE, "PLAYER_LOGIN")
	-- (PerfectMap and AzerothVeil both take over M, L and Blizzard's map: only one of them should run)
	if ns.IsAddOnLoaded("PerfectMap") then
		ns.Print("|cffff4040" .. L["PerfectMap is loaded too: both take over the M key and Blizzard's map. Disable one of them in the AddOns list."] .. "|r")
	end
	ns.Modules:Start()
	if ns.Options and ns.Options.Register then ns.SafeCall(ns.Options.Register) end
	if ns.MinimapButton then ns.SafeCall(ns.MinimapButton.Init) end
end)
