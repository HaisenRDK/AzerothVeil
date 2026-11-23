-- AzerothVeil: the continents' and seas' names (Engine/Names.lua). Copied from OpenMap (MIT, (c) 2026 OpenMap
-- contributors): its Data/Forever/Labels.lua, measured there on Blizzard's map art: where the art lettered them.
--   map    the map whose art the lines are measured on (its pixels, 1002 x 668)
--   name   the client's own name for it: a map's (C_Map.GetMapInfo) or an area's (C_Map.GetAreaInfo); `text` if none
--   fade   "land" or "sea": until which zoom it shows (Names.lua)
--   ink, glow  the lettering's colour and its halo's (0-255); glowA the halo's strength
--   lines  one per word, as the art sets them: { left, right, baseline, cap height }, and `true` fifth for a line set
--          all in small capitals (the art's "THE")
local _, FM = ...

local LAND_INK, LAND_GLOW = { 78, 44, 12 }, { 243, 189, 81 }
local SEA_INK, SEA_GLOW = { 66, 60, 44 }, { 168, 172, 152 }

FM.MAP_NAMES = {
	{ map = 947, name = { map = 1414, text = "Kalimdor" }, fade = "land", ink = LAND_INK, glow = LAND_GLOW, glowA = 0.7,
		lines = { { 112, 332, 330, 20 } } },
	{ map = 947, name = { map = 1415, text = "Eastern Kingdoms" }, fade = "land", ink = LAND_INK, glow = LAND_GLOW, glowA = 0.7,
		lines = { { 660, 800, 387, 14 }, { 641, 816, 411.5, 14.5 } } },
	{ map = 1414, name = { area = 457, text = "The Veiled Sea" }, fade = "sea", ink = SEA_INK, glow = SEA_GLOW, glowA = 0.35,
		lines = { { 251, 287, 161, 11.5, true }, { 225, 314, 185, 17 }, { 246, 293, 209, 17 } } },
	{ map = 1415, name = { area = 214, text = "The Great Sea" }, fade = "sea", ink = SEA_INK, glow = SEA_GLOW, glowA = 0.35,
		lines = { { 229, 271, 279, 13, true }, { 209, 293, 303, 17 }, { 227, 274, 327, 17 } } },
	{ map = 1415, name = { area = 308, text = "The Forbidding Sea" }, fade = "sea", ink = SEA_INK, glow = SEA_GLOW, glowA = 0.35,
		lines = { { 730, 770, 243, 12.5, true }, { 677, 822, 269, 17 }, { 728, 771, 290, 17 } } },
}
