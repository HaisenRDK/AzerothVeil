-- Unit tests of AzerothVeil's core (Core/*.lua) outside the game, under Lua 5.1.
-- Run: scripts/check.sh (or: lua5.1 tests/test_core.lua <path to addon/>)
local ADDON_DIR = arg[1] or "addon/"
package.path = "tests/?.lua;" .. package.path
local stub = require("wowstub")

local CORE_FILES = { "Core/Init.lua", "Core/Callbacks.lua", "Core/Events.lua", "Core/Database.lua", "Core/ModuleManager.lua" }

-- loads the core files as WoW would: each called with (addonName, namespace)
local function LoadCore(savedVariables)
	stub.reset()
	_G.AzerothVeil = nil
	_G.AzerothVeilDB = savedVariables
	local ns = {}
	for _, file in ipairs(CORE_FILES) do
		local chunk = assert(loadfile(ADDON_DIR .. file))
		chunk("AzerothVeil", ns)
	end
	ns.Print = function(msg) stub.printed[#stub.printed + 1] = msg end
	return ns
end

---------------------------------------------------------------------------
local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed = passed + 1
		print("  ok   " .. name)
	else
		failed = failed + 1
		print("  FAIL " .. name .. "\n       " .. tostring(err))
	end
end
local function eq(a, b, what)
	if a ~= b then error(("%s: expected %s, got %s"):format(what or "value", tostring(b), tostring(a)), 2) end
end

-- a module that records what was called on it
local function Recorder(ns, def)
	local calls = {}
	def.calls = calls
	def.Initialize = function(self) calls[#calls + 1] = "Initialize" end
	def.Enable = function(self)
		calls[#calls + 1] = "Enable"
		self:RegisterEvent("PLAYER_TARGET_CHANGED", function() calls[#calls + 1] = "event" end)
		self:RegisterMessage("SOMETHING", function() calls[#calls + 1] = "message" end)
		self:NewTicker(1, function() calls[#calls + 1] = "tick" end)
	end
	def.Disable = function(self) calls[#calls + 1] = "Disable" end
	def.Refresh = function(self, key, value) calls[#calls + 1] = "Refresh:" .. key .. "=" .. tostring(value) end
	return ns.Modules:Register(def)
end
local function count(list, what)
	local n = 0
	for _, c in ipairs(list) do if c == what then n = n + 1 end end
	return n
end

local function Boot(ns)
	ns.Database.Load()
	ns.Modules:LoadSettings()
	ns.Modules:Start()
end

print("Database")
test("fresh table: schema and parts", function()
	local ns = LoadCore(nil)
	local root = ns.Database.Load()
	eq(root.schema, ns.Database.SCHEMA, "schema")
	eq(type(root.engine), "table", "engine")
	eq(type(root.modules), "table", "modules")
	eq(type(root.core), "table", "core")
	eq(_G.AzerothVeilDB, root, "global")
end)
test("migration 1 moves PerfectMap's friends settings to the social module", function()
	local ns = LoadCore({ engine = { friends = false, friendsShare = true, shareAsked = true, iconScale = 1.2 } })
	local root = ns.Database.Load()
	eq(root.engine.friends, nil, "engine.friends removed")
	eq(root.engine.iconScale, 1.2, "other engine settings kept")
	eq(root.modules.social.settings.show, false, "show")
	eq(root.modules.social.settings.share, true, "share")
	eq(root.modules.social.settings.asked, true, "asked")
end)
test("a newer schema is left alone", function()
	local ns = LoadCore({ schema = 99, engine = { friends = true } })
	local root = ns.Database.Load()
	eq(root.schema, 99, "schema")
	eq(root.engine.friends, true, "not migrated")
end)
test("FillDefaults fills what's missing and fixes wrong types", function()
	local ns = LoadCore(nil)
	local t = ns.Database.FillDefaults({ a = "oops", b = 5, nested = 3 }, { a = true, b = 1, c = "x", nested = { d = 1 } })
	eq(t.a, true, "wrong type replaced")
	eq(t.b, 5, "kept")
	eq(t.c, "x", "filled")
	eq(t.nested.d, 1, "nested")
end)
test("a corrupted file (not a table) starts afresh", function()
	local ns = LoadCore("garbage")
	local root = ns.Database.Load()
	eq(type(root.modules), "table", "modules")
end)

print("Events and callbacks")
test("the game's event is released when nobody listens", function()
	local ns = LoadCore(nil)
	local frame = stub.frames[1]
	local heard = 0
	ns.Events:Register("a", "PLAYER_LOGIN", function() heard = heard + 1 end)
	ns.Events:Register("b", "PLAYER_LOGIN", function() heard = heard + 1 end)
	stub.fire("PLAYER_LOGIN")
	eq(heard, 2, "both heard")
	ns.Events:UnregisterAll("a")
	eq(frame:IsEventRegistered("PLAYER_LOGIN"), true, "still registered for b")
	ns.Events:Unregister("b", "PLAYER_LOGIN")
	eq(frame:IsEventRegistered("PLAYER_LOGIN"), false, "released")
end)
test("an unknown event is refused without error", function()
	local ns = LoadCore(nil)
	eq(ns.Events:Register("a", "UNKNOWN_EVENT", function() end), false, "refused")
end)
test("an error in a handler doesn't stop the others", function()
	local ns = LoadCore(nil)
	local heard = false
	ns.Callbacks:Register("M", "a", function() error("boom") end)
	ns.Callbacks:Register("M", "b", function() heard = true end)
	ns.Callbacks:Fire("M")
	eq(heard, true, "other handler ran")
	eq(#stub.errors, 1, "error reported")
end)

print("Module manager")
test("nothing runs before login; Initialize once; Enable at Start", function()
	local ns = LoadCore(nil)
	local m = Recorder(ns, { name = "a" })
	ns.Database.Load()
	ns.Modules:LoadSettings()
	eq(#m.calls, 0, "nothing before Start")
	ns.Modules:Start()
	eq(m.calls[1], "Initialize", "first")
	eq(m.calls[2], "Enable", "then")
	eq(ns.Modules:IsActive("a"), true, "active")
end)
test("a module off by default never runs (not even Initialize)", function()
	local ns = LoadCore(nil)
	local m = Recorder(ns, { name = "a", defaultEnabled = false })
	Boot(ns)
	eq(#m.calls, 0, "no call")
	eq(ns.Modules:State("a"), "disabled", "state")
end)
test("disabling stops it and lets go of its events, messages and timers", function()
	local ns = LoadCore(nil)
	local m = Recorder(ns, { name = "a" })
	Boot(ns)
	eq(ns.Events:Count("PLAYER_TARGET_CHANGED"), 1, "event registered")
	ns.Modules:Disable("a")
	eq(count(m.calls, "Disable"), 1, "Disable called")
	eq(ns.Events:Count("PLAYER_TARGET_CHANGED"), 0, "event released")
	eq(stub.liveTimers(), 0, "ticker cancelled")
	local before = #m.calls
	stub.fire("PLAYER_TARGET_CHANGED")
	ns.Callbacks:Fire("SOMETHING")
	stub.runTimers()
	eq(#m.calls, before, "nothing of it runs once disabled")
end)
test("settings are kept while disabled and an option is never active then", function()
	local ns = LoadCore(nil)
	local m = Recorder(ns, { name = "a", settings = {
		{ key = "x", type = "toggle", default = false },
	} })
	Boot(ns)
	ns.Modules:SetSetting("a", "x", true)
	eq(ns.Modules:IsOptionActive("a", "x"), true, "active while enabled")
	ns.Modules:Disable("a")
	eq(ns.Modules:GetSetting("a", "x"), true, "saved value kept")
	eq(ns.Modules:IsOptionActive("a", "x"), false, "never active while the module is off")
	eq(ns.Modules:IsOptionEditable("a", "x"), false, "not editable while off")
	ns.Modules:Enable("a")
	eq(ns.Modules:IsOptionActive("a", "x"), true, "back when enabled")
	eq(count(m.calls, "Initialize"), 1, "Initialize only once")
	eq(count(m.calls, "Enable"), 2, "enabled twice")
end)
test("the enabled flag and settings persist across a reload", function()
	local ns = LoadCore(nil)
	Recorder(ns, { name = "a", settings = { { key = "x", type = "toggle", default = false } } })
	Boot(ns)
	ns.Modules:SetSetting("a", "x", true)
	ns.Modules:Disable("a")
	local saved = _G.AzerothVeilDB
	ns = LoadCore(saved)
	local m = Recorder(ns, { name = "a", settings = { { key = "x", type = "toggle", default = false } } })
	Boot(ns)
	eq(ns.Modules:IsEnabled("a"), false, "still disabled")
	eq(#m.calls, 0, "doesn't run")
	eq(ns.Modules:GetSetting("a", "x"), true, "setting kept")
end)
test("Refresh only while active; values coerced", function()
	local ns = LoadCore(nil)
	local m = Recorder(ns, { name = "a", settings = {
		{ key = "x", type = "toggle", default = false },
		{ key = "n", type = "range", default = 1, min = 0.5, max = 2 },
	} })
	Boot(ns)
	ns.Modules:SetSetting("a", "x", 1)
	eq(ns.Modules:GetSetting("a", "x"), true, "toggle coerced to boolean")
	eq(count(m.calls, "Refresh:x=true"), 1, "Refresh called")
	ns.Modules:SetSetting("a", "n", 10)
	eq(ns.Modules:GetSetting("a", "n"), 2, "range clamped")
	ns.Modules:Disable("a")
	local before = #m.calls
	ns.Modules:SetSetting("a", "x", false)
	eq(#m.calls, before, "no Refresh while disabled")
end)
test("parent option", function()
	local ns = LoadCore(nil)
	Recorder(ns, { name = "a", settings = {
		{ key = "p", type = "toggle", default = false },
		{ key = "c", type = "toggle", default = true, parent = "p" },
	} })
	Boot(ns)
	eq(ns.Modules:IsOptionActive("a", "c"), false, "child off while parent off")
	eq(ns.Modules:IsOptionEditable("a", "c"), false, "child greyed")
	ns.Modules:SetSetting("a", "p", true)
	eq(ns.Modules:IsOptionActive("a", "c"), true, "child on")
end)
test("dependencies: the dependent stops with its dependency and comes back with it", function()
	local ns = LoadCore(nil)
	local base = Recorder(ns, { name = "base" })
	local dep = Recorder(ns, { name = "dep", dependencies = { "base" } })
	Boot(ns)
	eq(ns.Modules:IsActive("dep"), true, "both active")
	ns.Modules:Disable("base")
	eq(ns.Modules:IsActive("dep"), false, "dependent stopped")
	eq(ns.Modules:IsEnabled("dep"), true, "but still wanted")
	local state, reason = ns.Modules:State("dep")
	eq(state, "unavailable", "state")
	assert(reason and reason:find("base"), "reason names the dependency")
	-- (stopped before its dependency)
	local iDep, iBase
	for i, c in ipairs(dep.calls) do if c == "Disable" then iDep = i end end
	eq(count(base.calls, "Disable"), 1, "base disabled")
	assert(iDep, "dep disabled")
	ns.Modules:Enable("base")
	eq(ns.Modules:IsActive("dep"), true, "dependent back")
end)
test("a module registered before its dependency still starts after it", function()
	local ns = LoadCore(nil)
	local order = {}
	ns.Modules:Register({ name = "child", order = 1, dependencies = { "parent" }, Enable = function() order[#order + 1] = "child" end })
	ns.Modules:Register({ name = "parent", order = 2, Enable = function() order[#order + 1] = "parent" end })
	Boot(ns)
	eq(order[1], "parent", "parent first")
	eq(order[2], "child", "child second")
end)
test("required and conflicting addons", function()
	local ns = LoadCore(nil)
	Recorder(ns, { name = "needsQuestie", requiresAddOns = { "Questie" } })
	Recorder(ns, { name = "yieldsToDJ", conflictsWithAddOns = { "ForeverDungeonJournal" } })
	ns.Database.Load()
	ns.Modules:LoadSettings()
	stub.loadedAddOns.ForeverDungeonJournal = true
	ns.Modules:Start()
	eq(ns.Modules:IsActive("needsQuestie"), false, "Questie missing")
	eq(ns.Modules:IsActive("yieldsToDJ"), false, "DungeonJournal takes its place")
	eq(select(1, ns.Modules:State("yieldsToDJ")), "unavailable", "state")
end)
test("a module whose Enable fails is not left half running", function()
	local ns = LoadCore(nil)
	local disabled = false
	ns.Modules:Register({ name = "bad",
		Enable = function(self) self:RegisterEvent("PLAYER_TARGET_CHANGED", function() end) error("broken") end,
		Disable = function() disabled = true end })
	Boot(ns)
	eq(ns.Modules:IsActive("bad"), false, "not active")
	eq(disabled, true, "cleaned up")
	eq(ns.Events:Count("PLAYER_TARGET_CHANGED"), 0, "event released")
	eq(#stub.errors, 1, "error reported")
end)
test("circular dependencies are refused", function()
	local ns = LoadCore(nil)
	Recorder(ns, { name = "x", dependencies = { "y" } })
	Recorder(ns, { name = "y", dependencies = { "x" } })
	Boot(ns)
	eq(ns.Modules:IsActive("x"), false, "x")
	eq(ns.Modules:IsActive("y"), false, "y")
end)
test("reloadOnDisable asks for a reload once it has run", function()
	local ns = LoadCore(nil)
	local m = Recorder(ns, { name = "hooks", reloadOnDisable = true })
	Boot(ns)
	ns.Modules:Disable("hooks")
	eq(m.needsReload, true, "reload asked")
	ns.Modules:Enable("hooks")
	eq(m.needsReload, nil, "not any more once back on")
end)
test("duplicate names and bad setting types are refused", function()
	local ns = LoadCore(nil)
	ns.Modules:Register({ name = "a" })
	assert(not pcall(ns.Modules.Register, ns.Modules, { name = "a" }), "duplicate refused")
	assert(not pcall(ns.Modules.Register, ns.Modules, { name = "b", settings = { { key = "k", type = "color" } } }), "bad type refused")
end)


---------------------------------------------------------------------------
-- Modules/Transports.lua, on a stand-in engine that records what it's told
---------------------------------------------------------------------------
local function LoadTransports(saved, engineDb)
	local ns = LoadCore(saved)
	local st = { started = false, stops = 0, tracking = false, sharing = false, routes = false, rebuilds = 0, view = nil }
	ns.W = 1002
	ns.db = engineDb or { pins = {} }       -- (the engine's FM.db: what the module writes into)
	ns.Vessels = {
		Start = function() st.started = true end,
		Stop = function() st.started = false st.stops = st.stops + 1 st.tracking, st.sharing = false, false end,
		SetTracking = function(on) st.tracking = on end,
		SetSharing = function(on) st.sharing = on end,
		SyncChanged = function() st.synced = true end,
	}
	ns.Routes = { SetEnabled = function(on) st.routes = on end }
	ns.Pins = { RebuildPlaces = function() st.rebuilds = st.rebuilds + 1 end, Ensure = function() end,
		InvalidatePlaces = function() st.rebuilds = st.rebuilds + 1 end }
	st.scale, st.vw = 2, 800
	ns.Map = {
		IsShown = function() return false end,
		MarkDirty = function() end,
		ViewNow = function() return 0, 0, st.scale, st.vw, 533 end,
		SetView = function(u, v, across) st.view = { u, v, across } end,
	}
	local chunk = assert(loadfile(ADDON_DIR .. "Modules/Transports.lua"))
	chunk("AzerothVeil", ns)
	return ns, st
end

print("Transports module")
test("on by default: the engine's switches written, tracking and sharing running", function()
	local ns, st = LoadTransports(nil)
	Boot(ns)
	local db = ns.db
	eq(ns.Modules:IsActive("transports"), true, "active")
	eq(db.pins.boat, true, "boats") eq(db.pins.zeppelin, true, "zeppelins")
	eq(db.pins.tram, true, "tram") eq(db.pins.airship, false, "airships off by default")
	eq(db.routes, false, "all routes off by default") eq(st.routes, true, "route lines on")
	eq(db.vessels, true, "live boats") eq(db.vesselSync, true, "sync")
	eq(st.started, true, "vessels started") eq(st.tracking, true, "tracking timer") eq(st.sharing, true, "sharing")
	eq(type(ns.Pins.OnTravelClick), "function", "click to travel")
end)
test("disabled: nothing of it shows or runs, its settings kept", function()
	local ns, st = LoadTransports(nil)
	Boot(ns)
	ns.Modules:Disable("transports")
	local db = ns.db
	for _, k in ipairs({ "boat", "zeppelin", "tram", "airship" }) do eq(db.pins[k], false, "pins." .. k) end
	eq(db.routes, false, "routes") eq(db.vessels, false, "vessels") eq(db.vesselSync, false, "sync")
	eq(db.enemyHarbors, false, "enemy harbors")
	eq(st.started, false, "vessels stopped") eq(st.stops, 1, "Stop called")
	eq(st.tracking, false, "no tracking timer") eq(st.sharing, false, "no messages")
	eq(st.routes, false, "no route lines")
	eq(ns.Pins.OnTravelClick, nil, "click to travel gone")
	eq(ns.Modules:GetSetting("transports", "boats"), true, "setting kept")
	eq(ns.Modules:IsOptionActive("transports", "boats"), false, "but not active")
	ns.Modules:Enable("transports")
	eq(db.pins.boat, true, "back on") eq(st.tracking, true, "tracking back")
end)
test("disabled at login: the engine is never started", function()
	local ns, st = LoadTransports({ modules = { transports = { enabled = false } } })
	Boot(ns)
	eq(st.started, false, "never started")
	eq(ns.Modules:IsActive("transports"), false, "inactive")
end)
test("tracking off stops the 0.8 s timer and the sharing under it", function()
	local ns, st = LoadTransports(nil)
	Boot(ns)
	ns.Modules:SetSetting("transports", "tracking", false)
	eq(st.tracking, false, "timer stopped") eq(st.sharing, false, "sharing stopped (its parent is off)")
	eq(ns.db.vessels, false, "no live boats") eq(ns.db.vesselSync, false, "no sync")
	eq(ns.Modules:GetSetting("transports", "share"), true, "share setting kept")
	ns.Modules:SetSetting("transports", "tracking", true)
	eq(st.tracking, true, "timer back") eq(st.sharing, true, "sharing back")
end)
test("parent options: route lines and other transports", function()
	local ns, st = LoadTransports(nil)
	Boot(ns)
	ns.Modules:SetSetting("transports", "routesAll", true)
	eq(ns.db.routes, true, "all routes")
	ns.Modules:SetSetting("transports", "routes", false)
	eq(st.routes, false, "no lines at all") eq(ns.db.routes, false, "all routes off with their parent")
	ns.Modules:SetSetting("transports", "airships", true)
	ns.Modules:SetSetting("transports", "others", false)
	eq(ns.db.pins.tram, false, "tram off with its parent") eq(ns.db.pins.airship, false, "airships too")
end)
test("the other faction's harbors: rebuilt only when it changes", function()
	local ns, st = LoadTransports(nil)
	Boot(ns)
	local before = st.rebuilds
	ns.Modules:SetSetting("transports", "zeppelins", false)
	eq(st.rebuilds, before, "no rebuild")
	ns.Modules:SetSetting("transports", "enemyHarbors", true)
	eq(st.rebuilds, before + 1, "rebuilt")
end)
test("click: straight to the way's other end, at OpenMap's zoom or closer", function()
	local ns, st = LoadTransports(nil)
	Boot(ns)
	ns.Pins.OnTravelClick({ travel = { { u = 100, v = 200 } } })
	eq(st.view[1], 100, "u") eq(st.view[2], 200, "v")
	eq(math.abs(st.view[3] - 1002 / 6) < 1e-9, true, "zoomed in to OpenMap's 6")
	st.scale = 10                                 -- (closer already: 80 units across)
	ns.Pins.OnTravelClick({ travel = { { u = 1, v = 2 } } })
	eq(st.view[3], 80, "kept as close")
	st.view = nil
	ns.Pins.OnTravelClick({ travel = { { dest = "?" } } })
	eq(st.view, nil, "no destination: nothing")
	ns.Modules:SetSetting("transports", "clickTravel", false)
	eq(ns.Pins.OnTravelClick, nil, "option off: no click")
end)
test("migration 2: PerfectMap's transport switches become the module's settings", function()
	local saved = { schema = 1, engine = { pins = { boat = false, airship = true }, routes = true, vessels = false, vesselSync = false, enemyHarbors = true } }
	local ns = LoadTransports(saved, nil)
	Boot(ns)
	local get = function(k) return ns.Modules:GetSetting("transports", k) end
	eq(get("boats"), false, "boats") eq(get("airships"), true, "airships") eq(get("routesAll"), true, "routes")
	eq(get("tracking"), false, "tracking") eq(get("share"), false, "share") eq(get("enemyHarbors"), true, "enemy")
	eq(get("zeppelins"), true, "missing: default") eq(_G.AzerothVeilDB.schema, 2, "schema 2")
end)

print("Localisation")
local function LoadLocale(locale)
	stub.reset()
	stub.locale = locale
	local ns = {}
	for _, file in ipairs({ "Core/Init.lua", "Locales/enUS.lua", "Locales/frFR.lua" }) do
		assert(loadfile(ADDON_DIR .. file))("AzerothVeil", ns)
	end
	stub.locale = nil
	return ns
end
test("French client: French texts; English as the fallback", function()
	local fr = LoadLocale("frFR")
	eq(fr.L["Enable this module"], "Activer le module", "translated")
	eq(fr.L["Some text nobody translated"], "Some text nobody translated", "fallback")
	local en = LoadLocale("enUS")
	eq(en.L["Enable this module"], "Enable this module", "English")
	local de = LoadLocale("deDE")
	eq(de.L["Transports"], "Transports", "another language: English")
end)

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
