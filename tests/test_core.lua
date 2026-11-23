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
		InvalidatePlaces = function() st.rebuilds = st.rebuilds + 1 end,
		RebuildFlights = function() st.flights = (st.flights or 0) + 1 end,
		InvalidateFlights = function() st.flights = (st.flights or 0) + 1 end }
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

test("every change is announced, so every option screen follows", function()
	local ns = LoadCore(nil)
	Recorder(ns, { name = "a", settings = { { key = "x", type = "toggle", default = false } } })
	Recorder(ns, { name = "b", requiresAddOns = { "Missing" } })
	Boot(ns)
	local heard = {}
	for _, msg in ipairs({ "MODULE_STATE_CHANGED", "MODULE_SETTING_CHANGED", "MODULE_ENABLED_CHANGED" }) do
		ns.Callbacks:Register(msg, "screen", function(m) heard[#heard + 1] = m end)
	end
	ns.Modules:SetSetting("a", "x", true)
	eq(heard[#heard], "MODULE_SETTING_CHANGED", "setting")
	ns.Modules:Disable("a")
	eq(heard[#heard], "MODULE_ENABLED_CHANGED", "switch")
	local n = #heard
	ns.Modules:Disable("b")                    -- (can't run anyway: its state doesn't change)
	eq(#heard, n + 1, "still announced") eq(heard[#heard], "MODULE_ENABLED_CHANGED", "switch of a module that can't run")
end)

test("the on/off check box's tooltip: what on and off do, why it doesn't run", function()
	local ns = LoadCore(nil)
	ns.Modules:Register({ name = "a", title = "A", onText = "it shows", offText = "nothing runs" })
	ns.Modules:Register({ name = "b", title = "B", requiresAddOns = { "Missing" } })
	Boot(ns)
	local title, lines = ns.Modules:SwitchTooltip("a")
	eq(title, "A", "title") eq(lines[1][1], "Enabled: it shows", "on") eq(lines[2][1], "Disabled: nothing runs", "off")
	eq(#lines, 3, "no reason while it runs")
	local _, lb = ns.Modules:SwitchTooltip("b")
	assert(lb[#lb][1]:find("Missing"), "why it doesn't run")
	eq(ns.Modules:CanBeUnavailable("a"), false, "a can always run") eq(ns.Modules:CanBeUnavailable("b"), true, "b may not")
end)

test("options grouped with the ones hanging from them, in order", function()
	local ns = LoadCore(nil)
	local m = ns.Modules:Register({ name = "g", settings = {
		{ key = "a", type = "toggle" }, { key = "b", type = "toggle" },
		{ key = "a1", type = "toggle", parent = "a" }, { key = "c", type = "toggle" },
		{ key = "b1", type = "toggle", parent = "b" }, { key = "b11", type = "toggle", parent = "b1" },
	} })
	local groups = ns.Modules:OptionGroups("g", m.settings)
	eq(#groups, 3, "three groups")
	eq(groups[1][1].key .. groups[1][2].key, "aa1", "a then its child")
	eq(groups[2][1].key .. groups[2][2].key .. groups[2][3].key, "bb1b11", "b, its child and grandchild")
	eq(groups[3][1].key, "c", "c alone")
end)

print("Transports module")
test("on by default: the engine's switches written, tracking and sharing running", function()
	local ns, st = LoadTransports(nil)
	Boot(ns)
	local db = ns.db
	eq(ns.Modules:IsActive("transports"), true, "active")
	eq(db.pins.boat, true, "boats") eq(db.pins.zeppelin, true, "zeppelins")
	eq(db.pins.tram, true, "tram") eq(db.pins.airship, false, "airships off by default")
	eq(db.pins.flight, true, "flight masters") eq(db.enemyFlight, false, "enemy flight masters off by default")
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
	for _, k in ipairs({ "boat", "zeppelin", "tram", "airship", "flight" }) do eq(db.pins[k], false, "pins." .. k) end
	eq(db.enemyFlight, false, "enemy flight masters")
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
	eq(get("zeppelins"), true, "missing: default") eq(_G.AzerothVeilDB.schema, ns.Database.SCHEMA, "latest schema")
end)
test("migration 3 and the flight masters: theirs kept, enemy ones rebuilt only when changed", function()
	local ns, st = LoadTransports({ schema = 2, engine = { pins = { flight = false }, enemyFlight = true } })
	Boot(ns)
	eq(ns.Modules:GetSetting("transports", "flight"), false, "flight from PerfectMap's switch")
	eq(ns.Modules:GetSetting("transports", "enemyFlight"), true, "enemy flight kept")
	eq(ns.db.enemyFlight, false, "not in effect: its parent is off")
	ns.Modules:SetSetting("transports", "flight", true)
	eq(ns.db.pins.flight, true, "flight masters shown") eq(ns.db.enemyFlight, true, "enemy ones too")
	local n = st.flights or 0
	ns.Modules:SetSetting("transports", "zeppelins", false)
	eq(st.flights or 0, n, "no rebuild for another option")
end)

---------------------------------------------------------------------------
-- Modules/Quests.lua, on a stand-in engine that records what it's told
---------------------------------------------------------------------------
local function LoadQuests(saved)
	local ns = LoadCore(saved)
	local st = { applied = 0, bindings = 0, toggled = 0 }
	ns.db = { pins = {} }
	ns.QuestLog = { Apply = function() st.applied = st.applied + 1 end }
	ns.ApplyBindings = function() st.bindings = st.bindings + 1 end
	ns.Quests = { OnToggle = function() st.toggled = st.toggled + 1 end }
	ns.Pins = { Ensure = function() end }
	ns.Map = { IsShown = function() return false end, MarkDirty = function() end }
	assert(loadfile(ADDON_DIR .. "Modules/Quests.lua"))("AzerothVeil", ns)
	return ns, st
end

print("Quests module")
test("on by default: the quests on the map, the log, ours on L", function()
	local ns, st = LoadQuests(nil)
	Boot(ns)
	local db = ns.db
	eq(db.questPOI, true, "poi") eq(db.questOffers, true, "offers") eq(db.questAreas, true, "areas")
	eq(db.pins.questie, true, "questie") eq(db.questLog, true, "log") eq(db.replaceQuestLog, true, "L")
	eq(st.applied > 0, true, "log told") eq(st.bindings > 0, true, "L bound again")
end)
test("disabled: WoW's own way, settings kept", function()
	local ns = LoadQuests(nil)
	Boot(ns)
	ns.Modules:Disable("quests")
	local db = ns.db
	for _, k in ipairs({ "questPOI", "questOffers", "questAreas", "questLog", "replaceQuestLog" }) do eq(db[k], false, k) end
	eq(db.pins.questie, false, "questie")
	eq(ns.Modules:GetSetting("quests", "log"), true, "setting kept")
end)
test("no log beside the map: L stays Blizzard's", function()
	local ns = LoadQuests(nil)
	Boot(ns)
	ns.Modules:SetSetting("quests", "log", false)
	eq(ns.db.questLog, false, "no log") eq(ns.db.replaceQuestLog, false, "L: Blizzard's")
	eq(ns.db.questPOI, true, "the map's quests are their own options")
end)
test("migration 5: PerfectMap's quest switches become the module's settings", function()
	local ns = LoadQuests({ schema = 4, engine = { questPOI = false, questAreas = true, replaceQuestLog = false, pins = { questie = false } } })
	Boot(ns)
	local get = function(k) return ns.Modules:GetSetting("quests", k) end
	eq(get("poi"), false, "poi") eq(get("areas"), true, "areas") eq(get("replace"), false, "replace")
	eq(get("questie"), false, "questie") eq(get("offers"), true, "missing: default")
end)

---------------------------------------------------------------------------
-- Modules/Map.lua, on a stand-in engine that records what it's told
---------------------------------------------------------------------------
local MAP_OFF = {
	replaceM = false, reopen = "last", rememberZoom = false, fadeMoving = false, hoverHighlight = false,
	joinIcons = false, addonPins = false, iconScale = 1, underground = false, minimapTerrain = false, zoneFishing = false,
	npcUnexplored = true, terrainNames = false,
}
local function LoadMapModule(saved)
	local ns = LoadCore(saved)
	local st = { bindings = 0, scaled = 0, button = nil, fog = nil, explored = 0 }
	ns.db = { pins = {} }
	for k, v in pairs(MAP_OFF) do ns.db[k] = v end
	ns.ApplyBindings = function() st.bindings = st.bindings + 1 end
	st.refound = 0
	ns.Pins = { ApplyScale = function() st.scaled = st.scaled + 1 end, RefreshExplored = function() st.refound = st.refound + 1 end }
	ns.AddonPins = { Refresh = function() end }
	ns.MinimapButton = { SetShown = function(on) st.button = on end }
	ns.Fog = { SetEnabled = function(on) st.fog = on end, Explored = function() st.explored = st.explored + 1 end }
	ns.Map = { MarkDirty = function() end, ResetHover = function() end }
	assert(loadfile(ADDON_DIR .. "Modules/Map.lua"))("AzerothVeil", ns)
	return ns, st
end

print("Map module")
test("on by default: M ours, the map's options in effect, no fog", function()
	local ns, st = LoadMapModule(nil)
	Boot(ns)
	local db = ns.db
	eq(db.replaceM, true, "M") eq(db.reopen, "player", "centre on me") eq(db.rememberZoom, true, "zoom")
	eq(db.hoverHighlight, true, "highlight") eq(db.joinIcons, true, "sum") eq(db.addonPins, true, "addons' icons")
	eq(db.underground, true, "caves") eq(db.minimapTerrain, true, "terrain") eq(db.zoneFishing, false, "fishing")
	eq(db.fadeMoving, false, "fade") eq(db.iconScale, 1, "size")
	eq(st.bindings > 0, true, "M bound") eq(st.button, true, "minimap button") eq(st.fog, false, "no fog")
end)
test("the fog: on, then off; the exploration heard only while it's on", function()
	local ns, st = LoadMapModule(nil)
	Boot(ns)
	ns.Modules:SetSetting("map", "fog", true)
	eq(st.fog, true, "fog on")
	stub.fire("MAP_EXPLORATION_UPDATED")
	eq(st.explored, 1, "explored heard")
	ns.Modules:SetSetting("map", "fog", false)
	eq(st.fog, false, "fog off")
	stub.fire("MAP_EXPLORATION_UPDATED")
	eq(st.explored, 1, "not heard any more")
end)
test("disabled: the map plain, settings kept", function()
	local ns, st = LoadMapModule(nil)
	Boot(ns)
	ns.Modules:SetSetting("map", "fog", true)
	ns.Modules:SetSetting("map", "iconScale", 1.3)
	eq(ns.db.iconScale, 1.3, "size in effect")
	ns.Modules:Disable("map")
	for k, v in pairs(MAP_OFF) do eq(ns.db[k], v, k) end
	eq(st.button, false, "no minimap button") eq(st.fog, false, "no fog")
	eq(ns.Modules:GetSetting("map", "fog"), true, "fog setting kept")
	eq(ns.Modules:GetSetting("map", "iconScale"), 1.3, "size kept")
end)
test("migration 6: the engine's map options and the minimap button become the module's", function()
	local ns = LoadMapModule({ schema = 5, engine = { replaceM = false, reopen = "last", zoneFishing = true,
		iconScale = 1.2, iconScale2 = true, hoverHighlight = false }, core = { minimap = { angle = 90, hide = true } } })
	Boot(ns)
	local get = function(k) return ns.Modules:GetSetting("map", k) end
	eq(get("replaceM"), false, "M") eq(get("centerOnOpen"), false, "reopen") eq(get("zoneFishing"), true, "fishing")
	eq(get("iconScale"), 1.2, "size") eq(get("hoverHighlight"), false, "highlight")
	eq(get("minimapButton"), false, "button hidden") eq(get("rememberZoom"), true, "missing: default")
	eq(get("fog"), false, "fog: off by default")
	local root = ns.Database.Root()
	eq(root.core.minimap.hide, nil, "old switch gone") eq(root.core.minimap.angle, 90, "angle kept")
	eq(ns.db.replaceM, false, "in effect: as set")
end)

test("the places' names up close: on with the minimap's terrain, off with it", function()
	local ns = LoadMapModule(nil)
	Boot(ns)
	eq(ns.db.terrainNames, true, "on by default")
	ns.Modules:SetSetting("map", "minimapTerrain", false)
	eq(ns.db.terrainNames, false, "terrain off: no names")
	eq(ns.Modules:GetSetting("map", "terrainNames"), true, "setting kept")
	ns.Modules:SetSetting("map", "minimapTerrain", true)
	ns.Modules:SetSetting("map", "terrainNames", false)
	eq(ns.db.terrainNames, false, "names off")
end)
test("townsfolk of unexplored areas: shown by default; hidden, they follow the exploration", function()
	local ns, st = LoadMapModule(nil)
	Boot(ns)
	eq(ns.db.npcUnexplored, true, "shown") eq(st.refound, 0, "nothing rebuilt")
	stub.fire("MAP_EXPLORATION_UPDATED")
	eq(st.refound, 0, "exploration not heard")
	ns.Modules:SetSetting("map", "unexploredNPCs", false)
	eq(ns.db.npcUnexplored, false, "hidden") eq(st.refound, 1, "rebuilt")
	stub.fire("MAP_EXPLORATION_UPDATED")
	eq(st.refound, 2, "explored more: rebuilt") eq(st.explored, 0, "fog off: not told")
	ns.Modules:Disable("map")
	eq(ns.db.npcUnexplored, true, "map module off: every one shown") eq(st.refound, 3, "rebuilt")
	stub.fire("MAP_EXPLORATION_UPDATED")
	eq(st.refound, 3, "not heard any more")
	eq(ns.Modules:GetSetting("map", "unexploredNPCs"), false, "setting kept")
end)

---------------------------------------------------------------------------
-- Modules/Icons.lua, on a stand-in engine
---------------------------------------------------------------------------
local function LoadIcons(saved)
	local ns = LoadCore(saved)
	local st = { ensured = 0 }
	ns.db = { pins = {}, allClassTrainers = false }
	ns.defaults = { pins = { capital = true, innkeeper = true, food = false } }
	ns.Pins = {
		CATS = {
			{ key = "flight", group = "transport", label = "Flight", icon = "f" },
			{ key = "capital", group = "places", label = "Capitals", icon = "c" },
			{ key = "innkeeper", group = "townsfolk", label = "Inn", icon = "i" },
			{ key = "classTrainer", group = "townsfolk", label = "Class", icon = "k" },
			{ key = "food", group = "townsfolk", label = "Food", icon = 1 },
			{ key = "prof_MINING", group = "professions", label = "Mining", icon = "m", tag = "MINING" },
			{ key = "prof_FISHING", group = "professions", label = "Fishing", icon = "p", tag = "FISHING" },
		},
		Ensure = function() st.ensured = st.ensured + 1 end,
		RebuildKind = function(key) st.rebuilt = (st.rebuilt or "") .. key end,
	}
	ns.Plain = function(v) return v end
	st.shown = false
	ns.Map = { MarkDirty = function() end, IsShown = function() return st.shown end }
	assert(loadfile(ADDON_DIR .. "Modules/Icons.lua"))("AzerothVeil", ns)
	return ns, st
end
local function SectionHeader(ns, label)
	for _, spec in ipairs(ns.Modules:Get("icons").settings) do
		if spec.type == "header" and spec.label == label then return spec end
	end
end

print("Icons module")
test("its settings: the kinds of its groups, PerfectMap's defaults; on by default", function()
	local ns = LoadIcons(nil)
	Boot(ns)
	local m = ns.Modules:Get("icons")
	eq(m.settingByKey.flight, nil, "flight masters: not its own") eq(m.settingByKey.capital.icon, "c", "engine's icon")
	eq(ns.db.pins.capital, true, "capitals") eq(ns.db.pins.innkeeper, true, "innkeepers")
	eq(ns.db.pins.food, false, "food: off") eq(ns.db.pins.prof_MINING, false, "trainers: off until picked")
end)
test("a kind turned on: built only with the map open; disabled: none, settings kept", function()
	local ns, st = LoadIcons(nil)
	Boot(ns)
	ns.Modules:SetSetting("icons", "food", true)
	eq(ns.db.pins.food, true, "food in effect") eq(st.ensured, 0, "map closed: nothing built")
	st.shown = true
	ns.Modules:SetSetting("icons", "prof_MINING", true)
	eq(st.ensured, 1, "map open: built")
	ns.Modules:Disable("icons")
	for _, k in ipairs({ "capital", "innkeeper", "food", "prof_MINING" }) do eq(ns.db.pins[k], false, k) end
	eq(ns.Modules:GetSetting("icons", "food"), true, "kept")
	ns.Modules:Enable("icons")
	eq(ns.db.pins.food, true, "back")
end)
test("a section's Show all / Hide all: its kinds, not its options of their own", function()
	local ns = LoadIcons(nil)
	Boot(ns)
	local townsfolk = SectionHeader(ns, "Townsfolk")
	eq(townsfolk.all, true, "buttons declared")
	eq(table.concat(ns.Modules:SectionToggles("icons", townsfolk), ","), "innkeeper,classTrainer,food", "its kinds")
	ns.Modules:SetSection("icons", townsfolk, true)
	eq(ns.db.pins.food, true, "food on") eq(ns.Modules:GetSetting("icons", "allClassTrainers"), false, "every class: left alone")
	eq(ns.db.pins.prof_MINING, false, "another section: left alone")
	ns.Modules:SetSection("icons", townsfolk, false)
	eq(ns.db.pins.innkeeper, false, "innkeepers off") eq(ns.db.pins.capital, true, "capitals: left alone")
	local profs = SectionHeader(ns, "Profession trainers")
	eq(table.concat(ns.Modules:SectionToggles("icons", profs), ","), "prof_FISHING,prof_MINING", "not my professions; the common ones before the gathering ones")
end)
test("every class's trainers: the engine's switch, the kind built again", function()
	local ns, st = LoadIcons(nil)
	Boot(ns)
	ns.Modules:SetSetting("icons", "allClassTrainers", true)
	eq(ns.db.allClassTrainers, false, "class trainers off: none")
	ns.Modules:SetSetting("icons", "classTrainer", true)
	eq(ns.db.allClassTrainers, true, "every class") eq(st.rebuilt, "classTrainer", "rebuilt")
	ns.Modules:SetSetting("icons", "classTrainer", false)
	eq(ns.db.allClassTrainers, false, "its parent off: off")
end)
test("my professions: their trainers shown, read again as the map opens", function()
	local ns, st = LoadIcons(nil)
	local known = { [186] = 75 }
	_G.C_SkillInfo = { GetSkillLineInfoByID = function(id) return { rank = known[id] or 0 } end }
	Boot(ns)
	eq(ns.db.pins.prof_MINING, false, "option off: not shown")
	ns.Modules:SetSetting("icons", "myProfessions", true)
	eq(ns.db.pins.prof_MINING, true, "mining: mine") eq(ns.db.pins.prof_FISHING, false, "fishing: not mine")
	eq(ns.Modules:GetSetting("icons", "prof_MINING"), true, "its own box ticked")
	eq(ns.Modules:GetSetting("icons", "prof_FISHING"), false, "not mine: not ticked")
	known[356] = 1
	ns.Pins.BeforeOpen()
	eq(ns.db.pins.prof_FISHING, true, "learnt: shown at the next opening")
	eq(ns.Modules:GetSetting("icons", "prof_FISHING"), true, "and its box ticked")
	ns.Modules:SetSetting("icons", "prof_FISHING", false)
	ns.Pins.BeforeOpen()
	eq(ns.Modules:GetSetting("icons", "prof_FISHING"), false, "unticked by hand: stays so")
	ns.Modules:Disable("icons")
	eq(ns.Pins.BeforeOpen, nil, "nothing at the opening while off") eq(ns.db.pins.prof_MINING, false, "off")
	_G.C_SkillInfo = nil
end)
test("migration 7: the engine's townsfolk, trainers and capitals become the module's", function()
	local ns = LoadIcons({ schema = 6, engine = { pins = { capital = false, food = true, prof_MINING = true, boat = false } } })
	Boot(ns)
	local get = function(k) return ns.Modules:GetSetting("icons", k) end
	eq(get("capital"), false, "capitals") eq(get("food"), true, "food") eq(get("prof_MINING"), true, "mining")
	eq(get("innkeeper"), true, "missing: default") eq(get("boat"), nil, "not its own")
	eq(ns.db.pins.food, true, "in effect")
end)

---------------------------------------------------------------------------
-- Modules/Markers.lua, on a stand-in engine, network and UI
---------------------------------------------------------------------------
local function strsplitStub(sep, text, limit)
	local out, start = {}, 1
	while true do
		if limit and #out == limit - 1 then out[#out + 1] = text:sub(start) break end
		local i = text:find(sep, start, true)
		if not i then out[#out + 1] = text:sub(start) break end
		out[#out + 1] = text:sub(start, i - 1)
		start = i + #sep
	end
	return unpack(out)
end
local function LoadMarkers(saved)
	local ns = LoadCore(saved)
	local st = { sets = {}, followed = nil, cleared = 0, sent = {}, edited = nil, asked = nil, group = false, guild = true }
	_G.strsplit, _G.GetTime, _G.time = strsplitStub, function() return st.now or 0 end, os.time
	_G.IsInRaid = function() return false end
	_G.IsInGroup = function() return st.group end
	_G.IsInGuild = function() return st.guild end
	_G.UnitName = function() return "Me" end
	_G.Ambiguate = function(name) return (name:gsub("%-.*$", "")) end
	_G.IsAltKeyDown = function() return false end
	_G.IsModifiedClick = function() return false end
	_G.C_ChatInfo = {
		RegisterAddonMessagePrefix = function(p) st.prefix = p end,
		SendAddonMessage = function(prefix, text, channel, target) st.sent[#st.sent + 1] = { prefix, text, channel, target } end,
	}
	_G.C_Map = { HasUserWaypoint = function() return false end, GetMapInfo = function(id) return { name = "Zone" .. id } end }
	ns.db = { pins = {} }
	ns.Plain = function(v) return v end
	ns.Pins = {
		SetPins = function(key, list)
			for _, pin in ipairs(list) do assert(pin.u and pin.v, "a pin without its place") end
			st.sets[#st.sets + 1] = list
		end,
		FollowAt = function(key, u, v) st.followed = { u, v } end,
		ClearPin = function() st.cleared = st.cleared + 1 end,
	}
	local rects = { [1429] = { 0, 100, 0, 100 }, [1415] = { 0, 200, 0, 200 } }
	ns.Geo = {
		Rect = function(id) return rects[id] end,
		MapToUnits = function(id, x, y) local r = rects[id] if r then return r[1] + x * (r[2] - r[1]), r[3] + y * (r[4] - r[3]) end end,
		UnitsToMap = function(id, u, v) local r = rects[id] if r then return (u - r[1]) / (r[2] - r[1]), (v - r[3]) / (r[4] - r[3]) end end,
		ZoneAt = function(u, v) if u <= 100 and v <= 100 then return 1429 end end,
		ContinentAt = function() return 1415 end,
	}
	ns.Map = { MarkDirty = function() end, IsShown = function() return true end }
	ns.Spot = {}
	assert(loadfile(ADDON_DIR .. "Modules/Markers.lua"))("AzerothVeil", ns)
	ns.MarkersUI = {
		Edit = function(m, fresh) st.edited = { m, fresh } end,
		Ask = function(batch, onAdd, onDone) st.asked = { batch, onAdd, onDone } end,
		HideAll = function() end,
	}
	return ns, st
end
local function LastSet(st) return st.sets[#st.sets] or {} end

print("Map markers module")
test("Ctrl-click drops a marker, followed, its card open; on the map", function()
	local ns, st = LoadMarkers(nil)
	Boot(ns)
	local d = ns.Database.Root().markers
	eq(#d.cats, 1, "one category") eq(#d.list, 0, "no marker")
	eq(ns.Pins.OnCtrlClick(45, 63), true, "taken")
	eq(#d.list, 1, "dropped") eq(d.list[1].map, 1429, "on its zone") eq(d.list[1].x, 0.45, "x")
	eq(st.followed ~= nil, true, "followed") eq(st.edited[2], true, "card, fresh")
	eq(#LastSet(st), 1, "on the map") eq(ns.db.pins.marker, true, "kind on")
	eq(ns.Pins.OnCtrlClick(150, 150), true, "at sea: on the continent") eq(d.list[2].map, 1415, "continent")
	ns.Modules:SetSetting("markers", "ctrlClick", false)
	eq(ns.Pins.OnCtrlClick(10, 10), false, "off: the waypoint's, as before")
end)
test("categories: hidden off the map; one deleted with its markers; the first stays", function()
	local ns, st = LoadMarkers(nil)
	Boot(ns)
	local M = ns.Markers
	local c = M.AddCat("Rares")
	M.Add(1429, 0.1, 0.1, "a", 2, 3, c.id)
	M.Add(1429, 0.2, 0.2, "b")
	M.Changed()
	eq(#LastSet(st), 2, "both shown")
	c.shown = false
	M.Changed()
	eq(#LastSet(st), 1, "hidden category: off the map")
	eq(M.RemoveCat(c.id), true, "deleted") eq(#M.Data().list, 1, "its marker with it")
	eq(M.RemoveCat(M.Data().cats[1].id), false, "the first stays")
end)
test("OpenMap's message and code: same format, notes cleaned and escaped", function()
	local ns = LoadMarkers(nil)
	Boot(ns)
	local M = ns.Markers
	local m = M.Add(1429, 0.452, 0.631, "note|with\ncodes", 2)
	eq(m.note, "note/with codes", "cleaned")
	eq(M.Message(m), "P1\t1429\t0.4520\t0.6310\t2\tnote/with codes", "message")
	m.note = "a;b,c%d"
	local code = M.CodeOf({ m })
	eq(code:sub(1, 8), "OMPINS1:", "code") eq(code:find("a;b", 1, true), nil, "escaped")
	local back = M.FromCode("paste: " .. code)
	eq(#back, 1, "read back") eq(back[1].note, "a;b,c%d", "note back") eq(back[1].color, 2, "colour")
	eq(M.Valid(9999, 0.5, 0.5, 1, ""), nil, "unknown map refused") eq(M.Valid(1429, 1.5, 0.5, 1, ""), nil, "off the map refused")
end)
test("sharing: paced, to the right channel; nothing without a group", function()
	local ns, st = LoadMarkers(nil)
	Boot(ns)
	local M = ns.Markers
	local a, b = M.Add(1429, 0.1, 0.1, "a"), M.Add(1429, 0.2, 0.2, "b")
	eq(M.Share({ a, b }, "group"), false, "no group")
	st.group = true
	eq(M.Share({ a, b }, "group"), true, "shared")
	eq(#st.sent, 1, "one at once") eq(st.sent[1][1], "OpenMap", "OpenMap's prefix") eq(st.sent[1][3], "PARTY", "party")
	stub.runTimers()
	eq(#st.sent, 2, "the next after its gap")
end)
test("receiving: asked, then added to Shared with me; your own ignored; off: not heard", function()
	local ns, st = LoadMarkers(nil)
	Boot(ns)
	local M = ns.Markers
	stub.fire("CHAT_MSG_ADDON", "OpenMap", "P1\t1429\t0.5\t0.5\t3\thi", "GUILD", "Me-Realm")
	stub.fire("CHAT_MSG_ADDON", "OpenMap", "V1\t1.0\tx", "GUILD", "Bob-Realm")
	stub.fire("CHAT_MSG_ADDON", "OpenMap", "P1\t1429\t0.5\t0.5\t3\thi", "GUILD", "Bob-Realm")
	st.now = 2
	stub.runTimers()
	eq(st.asked ~= nil, true, "asked") eq(#st.asked[1].list, 1, "one marker (own and version left out)")
	eq(st.asked[1].from, "Bob", "from")
	st.asked[2]()
	local got = M.Data().list[1]
	eq(got.note, "hi", "added") eq(got.from, "Bob", "its sender") eq(M.CatName(M.Cat(got.cat)), "Shared with me", "category")
	ns.Modules:SetSetting("markers", "receive", false)
	eq(ns.Events:Count("CHAT_MSG_ADDON"), 0, "not heard any more")
end)
test("your group's without asking, if said so", function()
	local ns, st = LoadMarkers(nil)
	Boot(ns)
	ns.Modules:SetSetting("markers", "groupAdd", true)
	stub.fire("CHAT_MSG_ADDON", "OpenMap", "P1\t1429\t0.3\t0.3\t1\t", "PARTY", "Ann")
	st.now = 2
	stub.runTimers()
	eq(st.asked, nil, "not asked") eq(#ns.Markers.Data().list, 1, "added")
end)
test("disabled: nothing on the map, no click of its own, markers kept", function()
	local ns, st = LoadMarkers(nil)
	Boot(ns)
	ns.Markers.Add(1429, 0.1, 0.1, "a")
	ns.Modules:Disable("markers")
	eq(ns.Pins.OnCtrlClick, nil, "no Ctrl-click") eq(ns.Pins.OnMarkerClick, nil, "no click")
	eq(#LastSet(st), 0, "off the map") eq(ns.db.pins.marker, false, "kind off")
	eq(ns.Events:Count("CHAT_MSG_ADDON"), 0, "nothing heard")
	eq(#ns.Database.Root().markers.list, 1, "kept")
end)
test("saved markers checked: a marker without a place dropped, a lost category put back", function()
	local ns = LoadMarkers({ schema = 7, markers = { list = { { id = 3, map = 1429, x = 0.1, y = 0.1, cat = 9 }, { id = 4 } },
		cats = { { id = 1, name = "Mine" } } } })
	ns.Database.Load()
	local d = ns.Database.Root().markers
	eq(#d.list, 1, "one kept") eq(d.list[1].cat, 1, "in the first category") eq(d.nextId, 4, "next id") eq(d.cats[1].shown, true, "shown")
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

---------------------------------------------------------------------------
-- Modules/Dungeons.lua and Integrations/DungeonJournal.lua, on a stand-in engine and DungeonJournal
---------------------------------------------------------------------------
-- dj: nil (not installed) or { locked = { [name] = true }, broken = true }
local function LoadDungeons(saved, dj)
	local ns = LoadCore(saved)
	_G.ForeverDungeonJournal_NS, _G.ForeverDungeonJournalFrame, _G.ForeverDungeonJournal_Toggle = nil, nil, nil
	local st = { opened = {}, chosen = nil, view = nil, suspended = nil, panel = nil, journal = {}, side = nil }
	ns.db = { pins = {} }
	ns.W = 1002
	ns.Pins = {
		DUNGEON_ICON = "d", RAID_ICON = "r",
		RebuildPlaces = function() st.rebuilt = (st.rebuilt or 0) + 1 end,
		InvalidatePlaces = function() st.rebuilt = (st.rebuilt or 0) + 1 end,
		Ensure = function() end,
		InstanceName = function(id) return "Instance " .. id end,
		InstanceInfo = function() return { lo = 17, hi = 26 } end,
	}
	st.left, st.top, st.scale, st.vw, st.vh = 100, 50, 4, 800, 533
	ns.Map = {
		ViewNow = function() return st.left, st.top, st.scale, st.vw, st.vh end,
		SetView = function(u, v, across) st.view = { u, v, across } end,
		MarkDirty = function() end,
		IsShown = function() return st.mapShown or false end,
		SetSideWidth = function(w) st.side = w end,
	}
	ns.Dungeon = {
		OpenWing = function(w) st.opened[#st.opened + 1] = w.id end,
		Choose = function(entries, _, _, onPick) st.chosen = { entries = entries, onPick = onPick } end,
		Update = function() end, Refresh = function() end, HideChooser = function() end,
		Current = function() return st.current, 1, 2, st.currentOpened end,
		Back = function() st.back = true end,
		CollectBosses = function(inst) return st.bosses or {} end,
	}
	ns.QuestLog = { WIDTH = 300, Suspend = function(on) st.suspended = on end }
	ns.DungeonPanel = { Show = function(_, inst) st.panel = inst end, Hide = function() st.panel = false end, Refresh = function() end }
	if dj then
		stub.loadedAddOns.ForeverDungeonJournal = true
		local FDJ = { DB = { ["The Deadmines"] = { bosses = { { name = "Edwin VanCleef", loot = { { 5191, "Cruel Barb", "One-Hand, Sword", 3 } } },
				{ name = "Mr. Smite", loot = {} } } },
			["Stratholme: Living"] = {}, ["Stratholme: Undead"] = {}, ["Scarlet Monastery: Library"] = {} },
			DUNGEON_MAPS = { ["The Deadmines"] = {
				floors = { { tiles = "Interface\\WorldMap\\TheDeadmines\\TheDeadmines1_" }, { tiles = "Interface\\WorldMap\\TheDeadmines\\TheDeadmines3_" } },
				transitions = { { floor = 1, to = 2, x = 0.4, y = 0.5, dir = "down" } } },
				["City of Dalaran"] = {
					floors = { { texture = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\DalaranUnderbellyMap", texBottom = 0.5 },
						{ texture = "Interface\\AddOns\\ForeverDungeonJournal\\Media\\DalaranCityMap", texBottom = 0.5 } },
					transitions = { { floor = 1, to = 2, x = 0.7, y = 0.6, labelKey = "MAP_SAFE_EXIT", color = { 1, 0, 0 } },
						{ floor = 2, to = 1, x = 0.2, y = 0.2, labelKey = "MAP_UNKNOWN" } } } } }
		FDJ.IsDungeonMapLocked = function(name) return dj.locked and dj.locked[name] or false end
		FDJ.OpenDungeonMap = function(name) if dj.broken then error("broken") end st.journal[#st.journal + 1] = "map:" .. name end
		FDJ.OpenBossPage = function(name) if dj.broken then error("broken") end st.journal[#st.journal + 1] = "bosses:" .. name end
		_G.ForeverDungeonJournal_NS = FDJ
		_G.ForeverDungeonJournalFrame = { IsShown = function() return st.djShown end }
		_G.ForeverDungeonJournal_Toggle = function() st.djShown = true end
	end
	assert(loadfile(ADDON_DIR .. "Integrations/DungeonJournal.lua"))("AzerothVeil", ns)
	assert(loadfile(ADDON_DIR .. "Integrations/Questie.lua"))("AzerothVeil", ns)
	assert(loadfile(ADDON_DIR .. "Modules/Dungeons.lua"))("AzerothVeil", ns)
	-- (Boot without a reset: the stand-in DungeonJournal stays loaded)
	ns.Database.Load() ns.Modules:LoadSettings()
	if dj then stub.loadedAddOns.ForeverDungeonJournal = true end
	ns.Modules:Start()
	return ns, st
end
local DEADMINES = { id = 36, name = "Deadmines", lo = 17, hi = 26 }

print("Dungeons module")
test("on by default: the engine's switches, its click and its way back", function()
	local ns = LoadDungeons(nil)
	local db = ns.db
	eq(ns.Modules:IsActive("dungeons"), true, "active")
	eq(db.pins.dungeon, true, "dungeons") eq(db.pins.raid, true, "raids") eq(db.dungeonLevels, true, "levels")
	eq(db.dungeonBosses, true, "bosses") eq(db.dungeonWays, true, "ways") eq(db.dungeonMaps, true, "map inside")
	eq(type(ns.Pins.OnDungeonClick), "function", "click") eq(type(ns.Dungeon.ReturnView), "function", "way back")
end)
test("disabled: nothing shows, its dungeon map closed, settings kept", function()
	local ns, st = LoadDungeons(nil)
	st.current, st.currentOpened = 36, true
	ns.Modules:Disable("dungeons")
	local db = ns.db
	for _, k in ipairs({ "dungeon", "raid" }) do eq(db.pins[k], false, "pins." .. k) end
	eq(db.dungeonMaps, false, "map inside") eq(db.dungeonBosses, false, "bosses")
	eq(ns.Pins.OnDungeonClick, nil, "no click") eq(ns.Dungeon.ReturnView, nil, "no way back hook")
	eq(st.back, true, "the dungeon opened from its entrance closed")
	eq(ns.Modules:GetSetting("dungeons", "entrances"), true, "setting kept")
end)
test("parent options switch their children off", function()
	local ns = LoadDungeons(nil)
	ns.Modules:SetSetting("dungeons", "entrances", false)
	eq(ns.db.pins.dungeon, false, "dungeons") eq(ns.db.pins.raid, false, "raids") eq(ns.db.dungeonLevels, false, "levels")
	ns.Modules:SetSetting("dungeons", "maps", false)
	eq(ns.db.dungeonBosses, false, "bosses") eq(ns.db.dungeonWays, false, "ways")
	eq(ns.db.dungeonMaps, true, "the map inside is its own option")
end)
test("an entrance: its map opens, the world's view kept and put back", function()
	local ns, st = LoadDungeons(nil)
	ns.Pins.OnDungeonClick({ DEADMINES }, "Deadmines")
	eq(st.opened[1], 36, "opened")
	st.left, st.scale = 900, 20                 -- (moved meanwhile, on the dungeon's map)
	eq(ns.Dungeon.ReturnView(), true, "put back")
	eq(st.view[1], 100 + 800 / 2 / 4, "centre x") eq(st.view[2], 50 + 533 / 2 / 4, "centre y") eq(st.view[3], 200, "zoom")
	eq(ns.Dungeon.ReturnView(), false, "nothing kept twice")
end)
test("several wings: a list, every one of them; a second dungeon keeps the first start", function()
	local ns, st = LoadDungeons(nil)
	local wings = { { id = 189, name = "Scarlet Monastery - Library" }, { id = 189, name = "Scarlet Monastery - Armory" } }
	ns.Pins.OnDungeonClick(wings, "Scarlet Monastery")
	eq(#st.opened, 0, "nothing opened yet") eq(#st.chosen.entries, 2, "both offered")
	st.chosen.onPick(wings[2])
	eq(st.opened[1], 189, "the picked one")
	st.left = 700
	ns.Pins.OnDungeonClick({ DEADMINES }, "Deadmines")          -- (another, the first still up)
	ns.Dungeon.ReturnView()
	eq(st.view[1], 100 + 800 / 2 / 4, "back to where it all began")
end)
test("interior maps off and no DungeonJournal: a click does nothing", function()
	local ns, st = LoadDungeons(nil)
	ns.Modules:SetSetting("dungeons", "maps", false)
	ns.Pins.OnDungeonClick({ DEADMINES }, "Deadmines")
	eq(#st.opened, 0, "nothing")
end)
test("DungeonJournal: its page of the dungeon; locked map: its boss page", function()
	local ns, st = LoadDungeons(nil, { locked = {} })
	ns.Pins.OnDungeonClick({ DEADMINES }, "Deadmines")
	eq(st.journal[1], "map:The Deadmines", "its map") eq(st.djShown, true, "its window shown") eq(#st.opened, 0, "not ours")
	local ns2, st2 = LoadDungeons(nil, { locked = { ["The Deadmines"] = true } })
	ns2.Pins.OnDungeonClick({ DEADMINES }, "Deadmines")
	eq(st2.journal[1], "bosses:The Deadmines", "its spoiler lock respected")
end)
test("DungeonJournal: by instance ID and wing, both parts of Stratholme, raids on our map", function()
	local ns, st = LoadDungeons(nil, {})
	ns.Pins.OnDungeonClick({ { id = 329, name = "Stratholme" } }, "Stratholme")
	eq(#st.chosen.entries, 2, "its two parts")
	st.chosen.onPick(st.chosen.entries[2])
	eq(st.journal[1], "bosses:Stratholme: Undead", "the picked part")
	ns.Pins.OnDungeonClick({ { id = 189, name = "Scarlet Monastery - Library" } }, "SM")
	eq(st.journal[2], "bosses:Scarlet Monastery: Library", "a wing by its data name")
	ns.Pins.OnDungeonClick({ { id = 409, name = "Molten Core", raid = true } }, "MC")
	eq(st.opened[1], 409, "a raid it doesn't have: our map")
end)
test("DungeonJournal failing, or not wanted: our own map", function()
	local ns, st = LoadDungeons(nil, { broken = true })
	ns.Pins.OnDungeonClick({ DEADMINES }, "Deadmines")
	eq(st.opened[1], 36, "fallback")
	local ns2, st2 = LoadDungeons(nil, {})
	ns2.Modules:SetSetting("dungeons", "useDJ", false)
	ns2.Pins.OnDungeonClick({ DEADMINES }, "Deadmines")
	eq(st2.opened[1], 36, "option off: ours") eq(#st2.journal, 0, "journal left alone")
end)
test("without DungeonJournal: no key, no error", function()
	local ns = LoadDungeons(nil)
	eq(#ns.DungeonJournal.KeysFor(DEADMINES), 0, "no keys") eq(ns.DungeonJournal.Available(), false, "not available")
	eq(ns.DungeonJournal.Open("The Deadmines"), false, "nothing opened")
end)
test("side panel: up with a dungeon's map, the quest log given back after", function()
	local ns, st = LoadDungeons(nil)
	ns.Callbacks:Fire("DUNGEON_MAP_SHOWN", 36, true)
	eq(st.panel, 36, "panel shown") eq(st.suspended, true, "quest log suspended") eq(st.side, 300, "room kept")
	ns.Callbacks:Fire("DUNGEON_MAP_CLOSED", 36, true)
	eq(st.panel, false, "panel hidden") eq(st.suspended, false, "quest log back")
	ns.Modules:SetSetting("dungeons", "questsTab", false)
	ns.Modules:SetSetting("dungeons", "bossesTab", false)
	ns.Callbacks:Fire("DUNGEON_MAP_SHOWN", 36, true)
	eq(st.panel, false, "no tab wanted: no panel") eq(st.suspended, false, "quest log untouched")
end)
test("side panel: none while DungeonJournal is in charge", function()
	local ns, st = LoadDungeons(nil, {})
	ns.Callbacks:Fire("DUNGEON_MAP_SHOWN", 36, false)
	eq(st.panel, nil, "no second interface") eq(st.suspended, nil, "quest log untouched")
end)
test("quests: those under the dungeon's heading, their state as the game gives it", function()
	local ns = LoadDungeons(nil)
	_G.GetRealZoneText = function(id) return id == 36 and "Les Mortemines" or "" end
	local log = {
		{ isHeader = true, title = "Elwynn" }, { title = "Elsewhere", questID = 1, level = 5 },
		{ isHeader = true, title = "Les Mortemines" }, { title = "Red Silk", questID = 2, level = 18 },
		{ title = "The Defias", questID = 3, level = 22 }, { isHeader = true, title = "Westfall" },
	}
	_G.C_QuestLog = {
		GetNumQuestLogEntries = function() return #log end, GetInfo = function(i) return log[i] end,
		IsComplete = function(q) return q == 3 end, IsFailed = function() return false end,
		GetQuestObjectives = function(q) return q == 2 and { { text = "Silk 3/6", finished = false } } or {} end,
	}
	local quests = ns.Modules:Get("dungeons").QuestsFor(36)
	eq(#quests, 2, "only the dungeon's") eq(quests[1].questID, 2, "first") eq(quests[1].objectives[1].text, "Silk 3/6", "progress")
	eq(quests[2].complete, true, "ready to turn in, as the game says")
	_G.GetRealZoneText, _G.C_QuestLog = nil, nil
end)
test("bosses: as the map has them; none known: an empty list", function()
	local ns, st = LoadDungeons(nil)
	local mod = ns.Modules:Get("dungeons")
	eq(#mod.BossesFor(36), 0, "no data, no error")
	st.bosses = { { boss = { "Edwin VanCleef <Defias Kingpin>", 21, 1, 3 }, floor = 2 }, { boss = { "Mr. Smite", 20 } } }
	local list = mod.BossesFor(36)
	eq(list[1].name, "Edwin VanCleef", "title left out") eq(list[1].floor, 2, "its floor") eq(list[2].floor, nil, "not placed")
end)
test("passages between floors: DungeonJournal's, in our floors, on the same pictures only", function()
	local ns = LoadDungeons(nil, {})
	local GAME = { tiles = { 1, 2, 3 } }
	local links = ns.DungeonJournal.FloorLinks(36, { GAME, GAME, GAME })
	eq(#links, 1, "one passage") eq(links[1].floor, 1, "from our floor 1") eq(links[1].to, 3, "to our floor 3 (the game's map 3)")
	eq(links[1].y, 0.5, "the game's maps: as it is")
	local drawn = { texture = "x", bottom = 0.25 }
	eq(#ns.DungeonJournal.FloorLinks(36, { drawn, drawn, drawn }), 0, "other pictures: none")
	-- its own pictures of Forever's dungeons, matched by picture (Dalaran: its floors the other way round)
	local d = ns.DungeonJournal.FloorLinks(2959, { { texture = "city", bottom = 0.5 }, { texture = "underbelly", bottom = 0.25 } })
	eq(#d, 2, "both") eq(d[1].floor, 2, "its Underbelly: our floor 2") eq(d[1].to, 1, "to our City")
	eq(d[1].y, 1.2, "its height scaled to our picture's") eq(d[1].hint, "The safe way out.", "what to do there")
	eq(d[1].color[1], 1, "its colour") eq(d[2].hint, nil, "a hint it has that we don't know: none")
	eq(#ns.DungeonJournal.FloorLinks(2959, { GAME, GAME }), 0, "our floors not drawings: none")
	local ns2 = LoadDungeons(nil)
	eq(ns2.DungeonJournal.FloorLinks(36, { GAME, GAME, GAME }), nil, "no DungeonJournal: none")
	eq(type(ns.Dungeon.FloorLinks), "function", "given to the engine")
	ns.Modules:SetSetting("dungeons", "ways", false)
	eq(ns.Dungeon.FloorLinks, nil, "entrances and exits off: none")
end)
test("a boss's loot: DungeonJournal's list by its name or another; none without it", function()
	local ns = LoadDungeons(nil, {})
	local mod = ns.Modules:Get("dungeons")
	local loot = mod.BossLoot(36, nil, { key = "Edwin VanCleef <Defias Kingpin>", name = "Edwin VanCleef" })
	eq(#loot, 1, "its loot") eq(loot[1].itemID, 5191, "item ID") eq(loot[1].quality, 3, "quality")
	eq(mod.BossLoot(36, nil, { key = "Someone", name = "Someone", aliases = { "Mr. Smite" } })[1], nil, "an alias: its (empty) list")
	eq(mod.BossLoot(36, nil, { key = "Nobody", name = "Nobody" }), false, "a boss it doesn't have")
	local ns2 = LoadDungeons(nil)
	eq(ns2.Modules:Get("dungeons").BossLoot(36, nil, { key = "Edwin VanCleef", name = "Edwin VanCleef" }), nil, "no DungeonJournal: nil")
end)
test("unplaced bosses go to the Bosses tab, not over the map", function()
	local ns = LoadDungeons(nil)
	eq(ns.Dungeon.BossListInPanel(), true, "in the tab")
	ns.Modules:SetSetting("dungeons", "bossesTab", false)
	eq(ns.Dungeon.BossListInPanel(), false, "no tab: on the map, as before")
	local ns2 = LoadDungeons(nil, {})
	eq(ns2.Dungeon.BossListInPanel(), false, "DungeonJournal in charge: no tab of ours")
end)

-- a stand-in Questie: quests 1-5 in the Deadmines (area 1581, and 10029), 6 for the Horde only
local function FakeQuestie(ready)
	stub.loadedAddOns.Questie, stub.loadedAddOns.QuestieDB = true, true
	local quests = {
		[1] = { "Red Silk Bandanas", { { 101 } }, 18, 14, 1, 1581 },
		[2] = { "Oh Brother...", { { 102 } }, 20, 15, 0, 10029 },
		[3] = { "Underground Assault", { nil, nil, { 900 } }, 20, 15, 0, 1581 },
		[4] = { "The Defias Brotherhood", { { 101 } }, 22, 14, 0, 1581, { "Kill Edwin VanCleef." } },
		[5] = { "Too Soon", { { 102 } }, 30, 28, 0, 1581 },
		[6] = { "Horde Only", { { 102 } }, 20, 15, 2, 1581 },
		[7] = { "Elsewhere", { { 101 } }, 10, 5, 0, 12 },
		[8] = { "Mages Only", { { 102 } }, 20, 15, 0, 1581, nil, 128 },
	}
	local KEYS = { name = 1, startedBy = 2, questLevel = 3, requiredLevel = 4, requiredRaces = 5, zoneOrSort = 6, objectivesText = 7, requiredClasses = 8 }
	_G.QuestDB = {
		GetAllIds = function() return { 1, 2, 3, 4, 5, 6, 7, 8 } end,
		Get = function(id, key) return quests[id] and quests[id][KEYS[key]] end,
		GetAll = function(id, keys) local v = { n = #keys } for i, k in ipairs(keys) do v[i] = quests[id][KEYS[k]] end return v end,
	}
	_G.NpcDB = { Get = function(id, key)
		if key == "name" then return id == 101 and "Gryan Stoutmantle" or "Wilder Thistlenettle" end
		if key == "spawns" then return { [40] = { { 56.3, 47.5 } } } end
	end }
	_G.LibQuestieDB = { Enum = { factionRaceMasks = { Alliance = 1, Horde = 2 } } }
	_G.Questie = { API = { isReady = ready } }
	local zone = { instanceIdToAreaId = { [36] = 1581 }, GetDungeons = function() return { [1581] = { "The Deadmines", { 10029 } } } end,
		GetUiMapIdByAreaId = function(_, area) return area == 40 and 1436 or nil end }
	local qdb = { IsDoable = function(id) return id ~= 5 end }
	_G.QuestieLoader = { ImportModule = function(_, name) return name == "ZoneDB" and zone or name == "QuestieDB" and qdb or nil end }
	_G.UnitFactionGroup = function() return "Alliance" end
	_G.UnitLevel = function() return 20 end
	_G.UnitClass = function() return "Guerrier", "WARRIOR", 1 end
	_G.bit = { band = function(a, b) return (a % (2 * b)) >= b and b or 0 end }
	_G.C_Map = { GetAreaInfo = function(area) return area == 40 and "Marche de l'Ouest" or nil end }
	_G.GetRealZoneText = function(id) return id == 36 and "Les Mortemines" or "" end
	local log = { { isHeader = true, title = "Les Mortemines" }, { title = "Oh Brother...", questID = 2, level = 20 } }
	_G.C_QuestLog = {
		GetNumQuestLogEntries = function() return #log end, GetInfo = function(i) return log[i] end,
		IsComplete = function() return false end, IsFailed = function() return false end,
		GetQuestObjectives = function(q) return q == 2 and { { text = "Foreman Thistlenettle's Explorers' League Badge: 0/1", finished = false } } or {} end,
		IsQuestFlaggedCompleted = function(q) return q == 1 end,
		IsOnQuest = function(q) return q == 2 end,
	}
end
local function ClearQuestie()
	for _, k in ipairs({ "QuestDB", "NpcDB", "LibQuestieDB", "Questie", "QuestieLoader", "UnitFactionGroup", "UnitLevel", "UnitClass", "bit", "C_Map", "GetRealZoneText", "C_QuestLog" }) do _G[k] = nil end
end

test("Questie: every quest of the dungeon for my faction, with the game's state, its giver and where", function()
	local ns = LoadDungeons(nil)
	FakeQuestie(true)
	ns.Questie._Reset()
	local quests, source = ns.Modules:Get("dungeons").QuestsFor(36)
	eq(source, "questie", "from Questie")
	local by = {}
	for _, q in ipairs(quests) do by[q.questID] = q end
	eq(by[6], nil, "the other faction's left out") eq(by[7], nil, "another zone's left out")
	eq(by[1].status, "done", "done, as the game says") eq(by[2].status, "active", "in the log")
	eq(by[2].inLog, true, "the log's own entry: its progress") eq(#by[2].objectives, 1, "objectives kept")
	eq(by[2].giver.name, "Wilder Thistlenettle", "its giver (an alternative area)")
	eq(by[4].status, "available", "available (Questie)") eq(by[5].status, "locked", "not yet") eq(by[5].reqLevel, 28, "required level")
	eq(by[3].giver.item, "item:900", "started by an item")
	eq(by[4].giver.areaName, "Marche de l'Ouest", "the giver's zone") eq(by[4].giver.uiMap, 1436, "its map")
	eq(quests[1].status, "active", "in progress first")
	eq(by[4].text[1], "Kill Edwin VanCleef.", "what it asks") eq(#by[2].text, 0, "none known: none")
	eq(by[1].faction, "Alliance", "for one faction: said") eq(by[4].faction, nil, "for both: none")
	eq(by[8], nil, "another class's left out")
	-- the other faction's and other classes' shown too when that option is off
	ns.Modules:SetSetting("dungeons", "onlyMine", false)
	local all = {}
	for _, q in ipairs(ns.Modules:Get("dungeons").QuestsFor(36)) do all[q.questID] = q end
	eq(all[6] and all[6].faction, "Horde", "the Horde's, with its faction")
	eq(all[8] and all[8].classes and all[8].classes[1], 8, "the mages', with its class (the game's 8)")
	eq(ns.Questie.ClassesOf(1503), nil, "every class: no restriction")
	ClearQuestie()
end)
test("Questie: option off, not ready, or a dungeon it doesn't know: the log only / nothing", function()
	local ns = LoadDungeons(nil)
	local mod = ns.Modules:Get("dungeons")
	FakeQuestie(true)
	ns.Questie._Reset()
	ns.Modules:SetSetting("dungeons", "useQuestie", false)
	local q, source = mod.QuestsFor(36)
	eq(source, "log", "option off: the log") eq(#q, 1, "its one quest")
	ns.Modules:SetSetting("dungeons", "useQuestie", true)
	_G.Questie.API.isReady = false
	eq(select(2, mod.QuestsFor(36)), "log", "not ready yet: the log")
	_G.Questie.API.isReady = true
	local none = mod.QuestsFor(2974)
	eq(#none, 0, "Blackmaw Hold: Questie has nothing")
	ClearQuestie()
end)
test("Questie: a quest shown on the world map where it starts, marked there, the dungeon's map put away", function()
	local ns, st = LoadDungeons(nil)
	st.current = 36
	ns.Map.ShowSpot = function(m, x, y) st.spot = { m, x, y } end
	ns.Map.SetMark = function(m, x, y, title, sub) st.mark = { m, x, y, title, sub } end
	ns.Modules:Get("dungeons").ShowQuest({ title = "The Defias Brotherhood",
		giver = { name = "Gryan Stoutmantle", uiMap = 1436, x = 0.563, y = 0.475 } })
	eq(st.back, true, "back on the world") eq(st.spot[1], 1436, "its map") eq(st.spot[2], 0.563, "x")
	eq(st.mark[1], 1436, "marked there") eq(st.mark[4], "The Defias Brotherhood", "its name on the marker")
	eq(st.mark[5], "Given by Gryan Stoutmantle", "and its giver")
end)

test("migration 4: PerfectMap's dungeon switches become the module's", function()
	local ns = LoadDungeons({ schema = 3, engine = { pins = { raid = false }, dungeonBosses = false } })
	eq(ns.Modules:GetSetting("dungeons", "raidPins"), false, "raids") eq(ns.Modules:GetSetting("dungeons", "bosses"), false, "bosses")
	eq(ns.Modules:GetSetting("dungeons", "dungeonPins"), true, "missing: default")
end)

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
