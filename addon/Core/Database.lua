-- AzerothVeil — Core/Database.lua
-- The one SavedVariables table, AzerothVeilDB (account-wide), and its schema migrations.
--
--   AzerothVeilDB = {
--     schema  = <number>,              -- the layout version below (Database.SCHEMA)
--     engine  = { ... },               -- the map engine's settings: PerfectMap's own, as it kept them
--                                      -- (Engine/Core.lua fills its defaults: FM.defaults)
--     modules = {                      -- one entry per module, kept even while it's disabled
--       [name] = { enabled = <bool>, settings = { [key] = value } },
--     },
--     core    = { ... },               -- the core's own preferences (the options window's last module...)
--   }
--
-- Rules:
--  * missing values are filled from the defaults; a value of the wrong type is put back to its default;
--  * a module's settings are never wiped when it's disabled (only its "enabled" changes), and a
--    module's entry is kept even if the module is gone from the code (it may come back);
--  * each change of layout is a numbered migration, run once, in order, on older tables (never on a
--    newer one: a table from a newer AzerothVeil is left alone and only read).
local _, ns = ...

local Database = {}
ns.Database = Database

Database.SCHEMA = 7

-- Fills dst with what's missing from defaults (tables merged deeply). A value whose type differs from
-- its default's is replaced by the default (a corrupted or hand-edited file).
function Database.FillDefaults(dst, defaults)
	for k, v in pairs(defaults) do
		local cur = dst[k]
		if type(v) == "table" then
			if type(cur) ~= "table" then
				cur = {}
				dst[k] = cur
			end
			Database.FillDefaults(cur, v)
		elseif cur == nil or type(cur) ~= type(v) then
			dst[k] = v
		end
	end
	return dst
end

-- migrations[n] brings a table at schema n - 1 to schema n
local migrations = {}

-- 1: the first layout. Settings that were the engine's in PerfectMap and are a module's in AzerothVeil
-- move to that module (only if present: a fresh table has none).
migrations[1] = function(root)
	local engine = root.engine
	local function Move(module, oldKey, newKey)
		if engine[oldKey] == nil then return end
		local m = root.modules[module] or {}
		root.modules[module] = m
		m.settings = m.settings or {}
		if m.settings[newKey] == nil then m.settings[newKey] = engine[oldKey] end
		engine[oldKey] = nil
	end
	Move("social", "friends", "show")
	Move("social", "friendsShare", "share")
	Move("social", "shareAsked", "asked")
end

-- 2: boats, zeppelins, the tram, their routes and live icons become the Transports module's. Their values
-- as the engine kept them (PerfectMap's switches) become the module's settings; the engine's keys stay, as
-- what the module writes while it runs (Engine/Core.lua turns them off at each load).
migrations[2] = function(root)
	local engine = root.engine
	local pins = type(engine.pins) == "table" and engine.pins or {}
	local m = root.modules.transports or {}
	root.modules.transports = m
	m.settings = type(m.settings) == "table" and m.settings or {}
	local set = m.settings
	local function Copy(key, value)
		if set[key] == nil and type(value) == "boolean" then set[key] = value end
	end
	Copy("boats", pins.boat)
	Copy("zeppelins", pins.zeppelin)
	Copy("tram", pins.tram)
	Copy("airships", pins.airship)
	Copy("enemyHarbors", engine.enemyHarbors)
	Copy("routesAll", engine.routes)
	Copy("tracking", engine.vessels)
	Copy("share", engine.vesselSync)
end

-- 3: the flight masters join the Transports module (their icons and the other faction's), as migration 2
migrations[3] = function(root)
	local engine = root.engine
	local pins = type(engine.pins) == "table" and engine.pins or {}
	local m = root.modules.transports or {}
	root.modules.transports = m
	m.settings = type(m.settings) == "table" and m.settings or {}
	if m.settings.flight == nil and type(pins.flight) == "boolean" then m.settings.flight = pins.flight end
	if m.settings.enemyFlight == nil and type(engine.enemyFlight) == "boolean" then m.settings.enemyFlight = engine.enemyFlight end
end

-- 4: the dungeons' and raids' icons, their maps and bosses become the Dungeons module's (PerfectMap's
-- switches dungeon / raid / dungeonMaps / dungeonBosses), as migration 2 did for the transports
migrations[4] = function(root)
	local engine = root.engine
	local pins = type(engine.pins) == "table" and engine.pins or {}
	local m = root.modules.dungeons or {}
	root.modules.dungeons = m
	m.settings = type(m.settings) == "table" and m.settings or {}
	local set = m.settings
	local function Copy(key, value)
		if set[key] == nil and type(value) == "boolean" then set[key] = value end
	end
	Copy("dungeonPins", pins.dungeon)
	Copy("raidPins", pins.raid)
	Copy("auto", engine.dungeonMaps)
	Copy("bosses", engine.dungeonBosses)
end

-- 5: the quests on the map and the quest log, PerfectMap's switches, become the Quests module's settings
migrations[5] = function(root)
	local engine = root.engine
	local pins = type(engine.pins) == "table" and engine.pins or {}
	local m = root.modules.quests or {}
	root.modules.quests = m
	m.settings = type(m.settings) == "table" and m.settings or {}
	local set = m.settings
	local function Copy(key, value)
		if set[key] == nil and type(value) == "boolean" then set[key] = value end
	end
	Copy("poi", engine.questPOI)
	Copy("offers", engine.questOffers)
	Copy("areas", engine.questAreas)
	Copy("questie", pins.questie)
	Copy("replace", engine.replaceQuestLog)
end

-- 6: the map's own options (the engine's Map tab in PerfectMap's menu) become the Map module's settings, the
-- minimap button's switch with them (AzerothVeilDB.core.minimap.hide); the engine's keys stay, as what the
-- module writes while it runs (Engine/Core.lua sets them off at each load: FM.MAP_OFF)
migrations[6] = function(root)
	local engine = root.engine
	local m = root.modules.map or {}
	root.modules.map = m
	m.settings = type(m.settings) == "table" and m.settings or {}
	local set = m.settings
	local function Copy(key, value)
		if set[key] == nil and type(value) == "boolean" then set[key] = value end
	end
	Copy("replaceM", engine.replaceM)
	if engine.reopen == "player" or engine.reopen == "last" then Copy("centerOnOpen", engine.reopen == "player") end
	Copy("rememberZoom", engine.rememberZoom)
	Copy("fadeMoving", engine.fadeMoving)
	Copy("hoverHighlight", engine.hoverHighlight)
	Copy("joinIcons", engine.joinIcons)
	Copy("addonPins", engine.addonPins)
	Copy("underground", engine.underground)
	Copy("minimapTerrain", engine.minimapTerrain)
	Copy("zoneFishing", engine.zoneFishing)
	local scale = tonumber(engine.iconScale)
	if set.iconScale == nil and scale then
		-- (PerfectMap's older sizes, 1.10 for 1.00: Engine/Core.lua's iconScale2, done here as it isn't yet)
		if not engine.iconScale2 then scale = math.floor(scale / 1.1 / 0.05 + 0.5) * 0.05 end
		set.iconScale = scale
	end
	local mini = type(root.core) == "table" and root.core.minimap
	if type(mini) == "table" and type(mini.hide) == "boolean" then
		Copy("minimapButton", not mini.hide)
		mini.hide = nil
	end
end

-- 7: the capitals, the townsfolk and the profession trainers (the engine's Places, Townsfolk and Professions
-- tabs) become the Icons module's settings, under the same keys as FM.db.pins; the engine's keys stay, as what
-- the module writes while it runs (Engine/Core.lua turns them off at each load)
local ICON_KEYS = {
	"capital", "innkeeper", "banker", "auctioneer", "repair", "classTrainer", "portalTrainer", "weaponMaster",
	"stable", "battlemaster", "spirit", "barber", "transmogrifier", "mailbox", "food", "drink", "reagents",
	"tradeGoods", "bags", "potions", "ammo", "poisons",
}
migrations[7] = function(root)
	local engine = root.engine
	local pins = type(engine.pins) == "table" and engine.pins or {}
	local m = root.modules.icons or {}
	root.modules.icons = m
	m.settings = type(m.settings) == "table" and m.settings or {}
	local set = m.settings
	local function Copy(key, value)
		if set[key] == nil and type(value) == "boolean" then set[key] = value end
	end
	for _, k in ipairs(ICON_KEYS) do Copy(k, pins[k]) end
	for k, v in pairs(pins) do
		if type(k) == "string" and k:match("^prof_") then Copy(k, v) end   -- (the profession trainers)
	end
end

-- (for tests)
Database.migrations = migrations

local root

-- Reads (once) and returns the SavedVariables table, migrated and with its parts present.
-- Called by Engine/Core.lua at ADDON_LOADED, when the game has read the file.
function Database.Load()
	if root then return root end
	local db = _G.AzerothVeilDB
	if type(db) ~= "table" then db = {} end
	if type(db.engine) ~= "table" then db.engine = {} end
	if type(db.modules) ~= "table" then db.modules = {} end
	if type(db.core) ~= "table" then db.core = {} end
	local from = tonumber(db.schema) or 0
	if from < Database.SCHEMA then
		for n = from + 1, Database.SCHEMA do
			if migrations[n] then migrations[n](db) end
			db.schema = n
		end
	elseif from > Database.SCHEMA then
		-- (written by a newer AzerothVeil: read as it is, nothing migrated down)
		db.newerSchema = from
	end
	_G.AzerothVeilDB = db
	root = db
	return root
end

function Database.Root() return root end

-- A module's entry, created on first use: { enabled = <bool|nil>, settings = {} }
function Database.Module(name)
	assert(root, "Database.Module: the settings aren't loaded yet")
	local m = root.modules[name]
	if type(m) ~= "table" then
		m = {}
		root.modules[name] = m
	end
	if type(m.settings) ~= "table" then m.settings = {} end
	return m
end

-- (for tests: forget the loaded table)
function Database._Reset() root = nil end
