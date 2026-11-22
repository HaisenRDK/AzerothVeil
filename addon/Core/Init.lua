-- AzerothVeil — Core/Init.lua
-- Loaded first. Publishes the addon's one shared namespace (the table WoW hands every file of the addon
-- as its second vararg) and the few helpers everything else may rely on before the settings exist.
--
-- AzerothVeil is based on PerfectMap by sokenn_ (GPL-3.0); see LICENSE.md and NOTICE.md.
-- Copyright (C) 2026 AzerothVeil contributors. Licensed under the GNU GPL v3 or later.
local ADDON, ns = ...

-- the only global table the addon publishes (other globals: the key binding's function and texts, the
-- slash command, the SavedVariables, and a few named frames the game's key bindings need)
_G.AzerothVeil = ns

ns.ADDON = ADDON
ns.TITLE = "AzerothVeil"
ns.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

-- Localisation: L["English text"] gives the client's language's text, else the English key itself.
-- Locales/<locale>.lua fill it for their language only (nothing else is kept in memory).
ns.LOCALE = (GetLocale and GetLocale()) or "enUS"
ns.L = setmetatable({}, {
	__index = function(_, key) return key end,
})

-- Calls fn(...) and reports an error to the game's error handler instead of breaking the caller.
-- Returns true on success, followed by fn's results.
function ns.SafeCall(fn, ...)
	local results = { pcall(fn, ...) }
	if not results[1] then
		local handler = geterrorhandler and geterrorhandler()
		if handler then handler(results[2]) end
		return false, results[2]
	end
	return unpack(results)
end

-- Whether another addon is loaded (C_AddOns on this client; the old global as a fallback)
function ns.IsAddOnLoaded(name)
	local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
	if not loaded then return false end
	local ok, result = pcall(loaded, name)
	return ok and result and true or false
end

-- Escape closes a window of ours, heard as the map's window hears it (Engine/Map.lua): never through the
-- game's UISpecialFrames (a name an addon puts there taints the game's Escape handling). Out of combat the
-- key is kept from the game; in combat it closes the window and goes on to the game. Keyboard input is
-- only ever taken out of combat (letting keys through can't be set in a fight): asked in one, it waits
-- for its end, so the player's keys are never held.
function ns.TakeEscape(f, onEscape)
	local function Take()
		f:EnableKeyboard(true)
		f:SetPropagateKeyboardInput(true)
		f:SetScript("OnKeyDown", function(self, key)
			if InCombatLockdown() then
				if key == "ESCAPE" then local close = onEscape or self.Hide close(self) end
				return
			end
			if key == "ESCAPE" then
				self:SetPropagateKeyboardInput(false)
				local close = onEscape or self.Hide
				close(self)
				C_Timer.After(0, function() if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end end)
			else
				self:SetPropagateKeyboardInput(true)
			end
		end)
	end
	if not InCombatLockdown() then Take() return end
	local wait = CreateFrame("Frame")
	wait:RegisterEvent("PLAYER_REGEN_ENABLED")
	wait:SetScript("OnEvent", function(self) self:UnregisterAllEvents() Take() end)
end
