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
