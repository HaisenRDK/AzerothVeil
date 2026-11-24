-- AzerothVeil — Integrations/NeedRoll.lua
-- Optional integration with NeedRoll (by mikebvs, GPL v3): AzerothVeil hands it a dungeon or raid to show,
-- through the calls it makes public for other addons, nothing else. Never required, never changed: its files,
-- settings and SavedVariables are left alone; its own settings apply (a tab turned off there: it says no).
--
-- Its public surface (version 1.9.0, its docs/API.md and API.lua):
--   NeedRoll_ShowMap(instance, boss)    its layout map of a dungeon or raid; false if it has none
--   NeedRoll_ShowLoot(instance, boss)   its page of it (the Overview without a boss)
-- instance: its own ID ("DEADMINES", "SM_LIBRARY"), the game's instance ID, or a name. Both return true when
-- it opened, false when it couldn't, and print nothing. Each call is protected (pcall); anything missing
-- (another version) is detected and AzerothVeil falls back on its own dungeon map.
--
-- Which of its dungeons an entrance leads to: by the game's instance ID and, for an instance of several wings,
-- the wing's name as AzerothVeil's own data names it (Data/Places.lua: data, not displayed text). Always by its
-- own IDs: the dungeons new in WoW Forever have no instance ID in it, and its names are only English.
local _, ns = ...
local L = ns.L

local NR = {}
ns.NeedRoll = NR

NR.ADDON = "NeedRoll"

-- instance ID -> its dungeon(s) or raid (Stratholme: one entrance, two halves there)
NR.KEYS = {
	[389] = { "RAGEFIRE" }, [36] = { "DEADMINES" }, [43] = { "WAILING_CAVERNS" }, [33] = { "SHADOWFANG" },
	[34] = { "STOCKADE" }, [48] = { "BLACKFATHOM" }, [90] = { "GNOMEREGAN" }, [47] = { "RAZORFEN_KRAUL" },
	[129] = { "RAZORFEN_DOWNS" }, [70] = { "ULDAMAN" }, [209] = { "ZULFARRAK" }, [349] = { "MARAUDON" },
	[109] = { "SUNKEN_TEMPLE" }, [230] = { "BRD" }, [289] = { "SCHOLOMANCE" },
	[329] = { "STRAT_LIVE", "STRAT_UNDEAD" },
	[2959] = { "CITY_OF_DALARAN" }, [2970] = { "THE_DROWNED_CITY" }, [2974] = { "BLACKMAW_HOLD" },
	[2994] = { "ALCAZ_PRISON" }, [2998] = { "EXCAVATION_SITE_WETLANDS" }, [2999] = { "RUINS_OF_LORDAERON" },
	[3001] = { "SHAPERS_TERRACE" }, [3039] = { "KROLDOK_STRONGHOLD" }, [3065] = { "HALL_OF_THANES" },
	-- (the raids)
	[409] = { "MOLTEN_CORE" }, [249] = { "ONYXIA" }, [309] = { "ZULGURUB" }, [469] = { "BWL" },
	[509] = { "AQ20" }, [531] = { "AQ40" }, [533] = { "NAXXRAMAS" },
}
-- instances of several wings: AzerothVeil's wing name -> its dungeon
NR.WINGS = {
	[189] = {
		["Scarlet Monastery - Graveyard"] = "SM_GRAVEYARD", ["Scarlet Monastery - Library"] = "SM_LIBRARY",
		["Scarlet Monastery - Armory"] = "SM_ARMORY", ["Scarlet Monastery - Cathedral"] = "SM_CATHEDRAL",
	},
	[229] = { ["Lower Blackrock Spire"] = "LBRS", ["Upper Blackrock Spire"] = "UBRS" },
	[429] = { ["Dire Maul - East"] = "DM_EAST", ["Dire Maul - West"] = "DM_WEST", ["Dire Maul - North"] = "DM_NORTH" },
}
-- (its two halves of one of our entrances, named in the player's language)
local PART_NAMES = { STRAT_LIVE = L["Stratholme: Living"], STRAT_UNDEAD = L["Stratholme: Undead"] }

-- whether it can be handed a dungeon now
function NR.Available()
	return ns.IsAddOnLoaded(NR.ADDON) and type(_G.NeedRoll_ShowMap) == "function"
		and type(_G.NeedRoll_ShowLoot) == "function" or false
end

-- its dungeons for one of an entrance's wings ({ id, name } as Pins.lua gives them): { key, ... }
function NR.KeysFor(wing)
	if not (wing and wing.id and NR.Available()) then return {} end
	local wings = NR.WINGS[wing.id]
	if wings then return { wings[wing.name] } end
	local keys = NR.KEYS[wing.id]
	if keys then return { unpack(keys) } end
	return { wing.id }          -- (one this table doesn't know yet: by the game's instance ID, which it reads too)
end

-- a key's name in a list of several (one entrance, several of its dungeons)
function NR.Label(key) return PART_NAMES[key] end

-- Hands it one of its dungeons: its layout map, else its page. true when it took it; false if anything
-- failed or it said no (AzerothVeil then shows its own map).
function NR.Open(key)
	if key == nil or not NR.Available() then return false end
	local ok, shown = pcall(_G.NeedRoll_ShowMap, key)
	if ok and shown then return true end
	ok, shown = pcall(_G.NeedRoll_ShowLoot, key)
	return ok and shown and true or false
end
