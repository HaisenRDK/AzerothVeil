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

Database.SCHEMA = 2

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
