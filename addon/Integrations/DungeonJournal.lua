-- AzerothVeil — Integrations/DungeonJournal.lua
-- Optional integration with DungeonJournal (ForeverDungeonJournal, by Exehn): AzerothVeil hands it a
-- dungeon to show, through what it makes public, nothing else. Never required, never changed: its files,
-- settings and SavedVariables are left alone; its own locks (RPG mode: a dungeon or its map not unlocked
-- yet) apply, as its page-opening functions check them themselves.
--
-- Its public surface (version 2.1.3, read in its code, Core/Journal.lua):
--   _G.ForeverDungeonJournal_NS            its namespace: DB (dungeons by English name), DUNGEON_MAPS,
--                                          INSTANCE_ID_TO_DUNGEON, IsDungeonMapLocked(name)
--   FDJ.OpenDungeonMap(name)               its page of that dungeon, on its map
--   FDJ.OpenBossPage(name, index)          ... on its bosses
--   _G.ForeverDungeonJournal_Toggle()      its window shown / hidden
-- Each call is protected (pcall); anything missing (another version) is detected and AzerothVeil falls
-- back on its own dungeon map.
--
-- Which of its dungeons an entrance leads to: by the game's instance ID (the same in every language) and,
-- for an instance of several wings, the wing's name as AzerothVeil's own data names it (Data/Places.lua:
-- data, not displayed text): never by comparing localized names. Checked against its DB at each use.
local _, ns = ...

local DJ = {}
ns.DungeonJournal = DJ

DJ.ADDON = "ForeverDungeonJournal"

-- instance ID -> its dungeon(s) in DungeonJournal (Stratholme: one entrance, two parts there)
DJ.KEYS = {
	[389] = { "Ragefire Chasm" }, [36] = { "The Deadmines" }, [43] = { "Wailing Caverns" },
	[33] = { "Shadowfang Keep" }, [34] = { "The Stockade" }, [48] = { "Blackfathom Deeps" },
	[90] = { "Gnomeregan" }, [47] = { "Razorfen Kraul" }, [129] = { "Razorfen Downs" },
	[70] = { "Uldaman" }, [209] = { "Zul'Farrak" }, [349] = { "Maraudon" }, [109] = { "Sunken Temple" },
	[230] = { "Blackrock Depths" }, [289] = { "Scholomance" },
	[329] = { "Stratholme: Living", "Stratholme: Undead" },
	[2959] = { "City of Dalaran" }, [2970] = { "The Drowned City" }, [2974] = { "Blackmaw Hold" },
	[2994] = { "Alcaz Prison" }, [2998] = { "Excavation Site: Wetlands" }, [2999] = { "Ruins of Lordaeron" },
	[3001] = { "Shaper's Terrace" }, [3039] = { "Krol'dok Stronghold" }, [3065] = { "Hall of Thanes" },
}
-- instances of several wings: AzerothVeil's wing name -> its dungeon in DungeonJournal
DJ.WINGS = {
	[189] = {
		["Scarlet Monastery - Graveyard"] = "Scarlet Monastery: Graveyard",
		["Scarlet Monastery - Library"] = "Scarlet Monastery: Library",
		["Scarlet Monastery - Armory"] = "Scarlet Monastery: Armory",
		["Scarlet Monastery - Cathedral"] = "Scarlet Monastery: Cathedral",
	},
	[229] = {
		["Lower Blackrock Spire"] = "Lower Blackrock Spire",
		["Upper Blackrock Spire"] = "Upper Blackrock Spire",
	},
	[429] = {
		["Dire Maul - East"] = "Dire Maul: East",
		["Dire Maul - West"] = "Dire Maul: West",
		["Dire Maul - North"] = "Dire Maul: North",
	},
}

-- its namespace, if it's loaded and looks as expected; else nil
function DJ.NS()
	if not ns.IsAddOnLoaded(DJ.ADDON) then return nil end
	local f = _G.ForeverDungeonJournal_NS
	if type(f) ~= "table" or type(f.DB) ~= "table" then return nil end
	return f
end

-- whether it can be handed a dungeon now (its page-opening functions exist: made once it's set up)
function DJ.Available()
	local f = DJ.NS()
	return f ~= nil and type(f.OpenBossPage) == "function" and type(f.OpenDungeonMap) == "function"
end

-- its dungeons for one of an entrance's wings ({ id, name } as Pins.lua gives them): { key, ... }, only
-- those its DB has
function DJ.KeysFor(wing)
	local f = DJ.NS()
	local out = {}
	if not (f and wing and wing.id) then return out end
	local candidates
	local wings = DJ.WINGS[wing.id]
	if wings then
		candidates = { wings[wing.name] }
	else
		candidates = DJ.KEYS[wing.id]
		-- (an instance this table doesn't know yet: its own table by ID, if it has one)
		if not candidates and type(f.INSTANCE_ID_TO_DUNGEON) == "table" and f.INSTANCE_ID_TO_DUNGEON[wing.id] then
			candidates = { f.INSTANCE_ID_TO_DUNGEON[wing.id] }
		end
	end
	for _, key in ipairs(candidates or {}) do
		if key and f.DB[key] then out[#out + 1] = key end
	end
	return out
end

-- Hands it one of its dungeons: its window shown on that dungeon's page (its map, if it has one not
-- locked; else its bosses). true when it took it (a locked dungeon too: it says so itself); false if
-- anything failed (AzerothVeil then shows its own map).
function DJ.Open(key)
	local f = DJ.NS()
	if not (f and key and f.DB[key] and DJ.Available()) then return false end
	local hasMap = type(f.DUNGEON_MAPS) == "table" and f.DUNGEON_MAPS[key] ~= nil
	local locked = false
	if hasMap and type(f.IsDungeonMapLocked) == "function" then
		local ok, l = pcall(f.IsDungeonMapLocked, key)
		locked = ok and l and true or false
	end
	local frame = _G.ForeverDungeonJournalFrame
	if frame and frame.IsShown and not frame:IsShown() and type(_G.ForeverDungeonJournal_Toggle) == "function" then
		if not pcall(_G.ForeverDungeonJournal_Toggle) then return false end
	end
	local ok
	if hasMap and not locked then ok = pcall(f.OpenDungeonMap, key) else ok = pcall(f.OpenBossPage, key) end
	return ok and true or false
end

---------------------------------------------------------------------------
-- Its data, read only, for AzerothVeil's own dungeon maps when it's installed (as PerfectMap reused it):
-- the passages between floors and the bosses' loot. Nothing of it is changed or copied.
---------------------------------------------------------------------------
-- its dungeons for an instance (any wing; a wing named: that one only)
local function KeysOf(inst, wingName)
	if wingName and DJ.WINGS[inst] then
		local k = DJ.WINGS[inst][wingName]
		if k then return { k } end
	end
	if DJ.WINGS[inst] then
		local out = {}
		for _, k in pairs(DJ.WINGS[inst]) do out[#out + 1] = k end
		return out
	end
	return DJ.KEYS[inst] or {}
end

-- The passages to other floors on the game's own maps of a dungeon (4 x 3 tiles: its classic ones),
-- as its maps mark them: { { floor, to, x, y, dir } } in AzerothVeil's floors. Its floor i is the game's
-- map "<Name><n>_": AzerothVeil's floor n (the same pictures, in the game's order). ourTiles: whether
-- AzerothVeil shows the game's tiles for this instance (else the pictures differ: none).
function DJ.FloorLinks(inst, ourTiles)
	local f = DJ.NS()
	if not (f and ourTiles and type(f.DUNGEON_MAPS) == "table") then return nil end
	local out = {}
	for _, key in ipairs(KeysOf(inst)) do
		local data = f.DUNGEON_MAPS[key]
		if type(data) == "table" and type(data.transitions) == "table" and type(data.floors) == "table" then
			local ours = {}
			for i, fl in ipairs(data.floors) do
				local n = type(fl) == "table" and type(fl.tiles) == "string" and tonumber(fl.tiles:match("(%d+)_$"))
				ours[i] = n
			end
			for _, t in ipairs(data.transitions) do
				local from, to = ours[t.floor], ours[t.to]
				if from and to and tonumber(t.x) and tonumber(t.y) then
					out[#out + 1] = { floor = from, to = to, x = t.x, y = t.y, dir = t.dir }
				end
			end
		end
	end
	return out
end

local function Plain(name)
	return type(name) == "string" and name:gsub("%s*<[^>]*>", ""):lower():gsub("^%s+", ""):gsub("%s+$", "") or nil
end

-- A boss's loot as it lists it: { { itemID, name, slot, quality } }, or nil when it doesn't have that boss.
-- names: the boss's name and its other names (AzerothVeil's data, taken from its own originally).
function DJ.BossLoot(inst, wingName, names)
	local f = DJ.NS()
	if not f then return nil end
	local want = {}
	for _, n in ipairs(names or {}) do
		local p = Plain(n)
		if p then want[p] = true end
	end
	for _, key in ipairs(KeysOf(inst, wingName)) do
		local d = f.DB[key]
		for _, b in ipairs(type(d) == "table" and type(d.bosses) == "table" and d.bosses or {}) do
			if type(b) == "table" and want[Plain(b.name) or ""] and type(b.loot) == "table" then
				local out = {}
				for _, it in ipairs(b.loot) do
					if type(it) == "table" and tonumber(it[1]) then
						out[#out + 1] = { itemID = it[1], name = it[2], slot = it[3], quality = tonumber(it[4]) }
					end
				end
				return out
			end
		end
	end
	return nil
end
