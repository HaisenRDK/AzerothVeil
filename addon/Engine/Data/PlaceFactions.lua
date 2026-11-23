-- AzerothVeil: the villages of one faction (the Map module's "Villages' factions", Engine/Labels.lua): their faction's
-- emblem before their name. [areaID] = 1 (the Alliance's) or 2 (the Horde's), the areas of Data/AreaLabels.lua.
-- Picked from where each faction's townsfolk stand (Data/Townsfolk.lua: a place whose nearest townsfolk are all one
-- faction's, four of them at least), then checked by hand: the neutral towns (Booty Bay, Gadgetzan, Ratchet,
-- Everlook...) and the places a camp of the other's only stands near (Jaedenar, Night Run...) left out.
local _, FM = ...

FM.PLACE_FACTIONS = {
	-- the Alliance's
	[9] = 1,      -- Northshire Valley
	[42] = 1,     -- Darkshire
	[69] = 1,     -- Lakeshire
	[87] = 1,     -- Goldshire
	[99] = 1,     -- Rebel Camp
	[108] = 1,    -- Sentinel Hill
	[131] = 1,    -- Kharanos
	[132] = 1,    -- Coldridge Valley
	[144] = 1,    -- Thelsamar
	[147] = 1,    -- The Farstrider Lodge
	[150] = 1,    -- Menethil Harbor
	[186] = 1,    -- Dolanaar
	[188] = 1,    -- Shadowglen
	[271] = 1,    -- Southshore
	[320] = 1,    -- Refuge Pointe
	[324] = 1,    -- Stromgarde Keep
	[348] = 1,    -- Aerie Peak
	[385] = 1,    -- Northwatch Hold
	[415] = 1,    -- Astranaar
	[442] = 1,    -- Auberdine
	[467] = 1,    -- Stonetalon Peak
	[513] = 1,    -- Theramore Isle
	[608] = 1,    -- Nijel's Point
	[1438] = 1,   -- Nethergarde Keep
	[1684] = 1,   -- Chillwind Point
	[1998] = 1,   -- Talonbranch Glade
	[2418] = 1,   -- Morgan's Vigil
	[16724] = 1,  -- Farholde Keep (WoW Forever)
	-- the Horde's
	[75] = 2,     -- Stonard
	[117] = 2,    -- Grom'gol Base Camp
	[154] = 2,    -- Deathknell
	[159] = 2,    -- Brill
	[220] = 2,    -- Red Cloud Mesa
	[222] = 2,    -- Bloodhoof Village
	[228] = 2,    -- The Sepulcher
	[272] = 2,    -- Tarren Mill
	[321] = 2,    -- Hammerfall
	[340] = 2,    -- Kargath
	[362] = 2,    -- Razor Hill
	[363] = 2,    -- Valley of Trials
	[367] = 2,    -- Sen'jin Village
	[378] = 2,    -- Camp Taurajo
	[380] = 2,    -- The Crossroads
	[460] = 2,    -- Sun Rock Retreat
	[484] = 2,    -- Freewind Post
	[496] = 2,    -- Brackenwall Village
	[1099] = 2,   -- Camp Mojache
	[1237] = 2,   -- Valormok
	[2408] = 2,   -- Shadowprey Village
	[2539] = 2,   -- Malaka'jin
	[16743] = 2,  -- Rog'mar (WoW Forever)
}
