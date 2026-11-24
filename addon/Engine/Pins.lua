-- Points of interest. Each pin is just a texture (no frames: hovering and clicking are found by
-- distance from the cursor), placed in world units and kept in a coarse grid, so a pan or zoom only
-- looks at the cells in view. Textures are pooled and shared by every category.
-- Icons: the same ones Questie's townsfolk menu uses (the game's tracking icons, and Questie's own
-- copied into Media\Questie), and the atlases Ellesmere's map travel pins use for dungeons, raids and
-- transports. Townsfolk come from Data\Townsfolk.lua: no other addon is needed.
local _, FM = ...
local L = FM.L
local P = {}
FM.Pins = P

local S, Geo = FM.Style, FM.Geo
local floor = math.floor
local TRACK = "Interface\\Minimap\\tracking\\"
local MEDIA = "Interface\\AddOns\\AzerothVeil\\Media\\"
local CELL = 24                 -- grid cell, world units
local GRID_W = 1000

-- minZoom: how far in a category shows from, counted in steps of the wheel from right out (so it's
-- the same whatever the window's size; AzerothVeil: the map's steps, Map.lua): dungeons, raids, flight masters and the
-- ways into the next zone with the quest log's quests (step 4, Map.QUESTS_ZOOM), Questie's icons from where M
-- opens the map (step 6), every townsfolk kind with the cities (step 9, Map.TOWNSFOLK_ZOOM); boats & zeppelins right out already
-- group: which part of the menu lists it ("places", "townsfolk", "professions", "quests");
-- data: built-in townsfolk (true: its own list in Data\Townsfolk.lua; a string: that list, filtered by tag)
local OPEN_ZOOM = FM.W / FM.Map.OPEN_ACROSS * 0.97
local ICONS = "Interface\\Icons\\"

-- dungeons and raids: MapUtils' icons (the quest log's, no glow round them), the first the client has
local function Atlas(candidates, fallback)
	local get = C_Texture and C_Texture.GetAtlasInfo
	for _, name in ipairs(candidates) do
		if get and get(name) then return "atlas:" .. name end
	end
	return fallback
end
local DUNGEON_ICON = Atlas({ "questlog-questtypeicon-dungeon", "Dungeon", "DungeonSkull", "Dungeon-Normal" }, "atlas:dungeon")
local RAID_ICON = Atlas({ "questlog-questtypeicon-raid", "Raid" }, "atlas:raid")
-- the capitals: each its faction's emblem (the game's own; its PvP banner icon where the client lacks them)
local CAPITAL_ICON = {
	Alliance = Atlas({ "poi-alliance", "MountJournalIcons-Alliance" }, "Interface\\Icons\\INV_BannerPVP_02"),
	Horde = Atlas({ "poi-horde", "MountJournalIcons-Horde" }, "Interface\\Icons\\INV_BannerPVP_01"),
}
-- AzerothVeil: the zeppelin towers as OpenMap shows them (Map/Stitch.lua's LOOK, MIT): Blizzard's Horde airship
-- (the battleground maps' flying-vehicle atlas), its old seat-indicator picture where the client lacks it
local ZEPPELIN_ICON = Atlas({ "vehicle-air-horde" }, "Interface\\Vehicles\\SeatIndicator\\Vehicle-HordeZeppelin")
P.ZEPPELIN_ICON = ZEPPELIN_ICON
local CAPITALS = {               -- uiMapID, its faction
	{ 1453, "Alliance" }, { 1455, "Alliance" }, { 1457, "Alliance" },
	{ 1454, "Horde" }, { 1456, "Horde" }, { 1458, "Horde" },
}
local CATS = {
	{ key = "flight", label = L["Flight masters"], icon = TRACK .. "flightmaster", size = 18, minZoom = FM.Map.QUESTS_ZOOM, layer = 5, group = "transport" },   -- (AzerothVeil: step 4, Map.lua) (AzerothVeil: the Transports module's)
	{ key = "dungeon", label = L["Dungeons"], icon = DUNGEON_ICON, size = 20, minZoom = FM.Map.From(4), layer = 6, group = "dungeons" },
	{ key = "raid", label = L["Raids"], icon = RAID_ICON, size = 20, minZoom = FM.Map.From(4), layer = 6, group = "dungeons" },
	-- (the capitals: only right out (gone at the wheel's first step in), over every other icon: layer 8
	-- sorts them first, drawn in the OVERLAY layer)
	{ key = "capital", label = L["Capital cities"], icon = CAPITAL_ICON.Alliance, size = 24 * 0.8, minZoom = 0, maxZoom = FM.Map.From(3),
		layer = 8, drawLayer = "OVERLAY", group = "places" },
	-- AzerothVeil: the ways into the next zone (Data/ZoneExits.lua): a signpost "To <zone>" on each side of a crossing,
	-- a click shows that zone whole (its "To ..." under it: Labels.lua, with the places' names)
	-- (from the flight masters' zoom: a big zone shown whole, the Barrens', has its signposts too)
	{ key = "exit", label = L["Ways to other zones"], icon = MEDIA .. "signpost", size = 20, layer = 3, group = "places",
		minZoom = FM.Map.QUESTS_ZOOM, noJoin = true },
	-- (boats, zeppelins and the tram: on top of the rest, the routes end on them)
	{ key = "boat", label = L["Harbor"], icon = MEDIA .. "harbor_alliance", size = 22, minZoom = 0, layer = 7, group = "transport", noJoin = true },
	{ key = "zeppelin", label = L["Zeppelin towers"], icon = ZEPPELIN_ICON, size = 24, minZoom = 0, layer = 7, group = "transport", noJoin = true },
	{ key = "airship", label = L["Airships (Zephras Isle)"], icon = "atlas:vehicle-air-alliance", size = 24, minZoom = 0, layer = 7, group = "transport", noJoin = true },
	{ key = "tram", label = L["Deeprun Tram"], icon = MEDIA .. "tram", size = 20, minZoom = 0, layer = 7, group = "transport", noJoin = true },

	{ key = "questie", label = L["Questie icons"], icon = MEDIA .. "Questie\\available", size = 16, layer = 4, group = "quests", external = true,
		free = true },   -- (Questie's: exactly where Questie puts them, each on its own: never summed or moved)
	-- AzerothVeil: the map markers (the Markers module's, Modules/Markers.lua: P.SetPins("marker", ...)), each on its
	-- own, at every zoom, over the rest
	{ key = "marker", label = L["Map markers"], icon = "atlas:Waypoint-MapPin-Untracked", size = 20, minZoom = 0, layer = 7,
		group = "markers", noJoin = true },

	-- the kinds Questie's townsfolk menu has (and its icons for them)
	{ key = "innkeeper", label = L["Innkeepers"], icon = TRACK .. "innkeeper", data = true },
	{ key = "banker", label = L["Bankers"], icon = TRACK .. "banker", data = true },
	{ key = "auctioneer", label = L["Auctioneers"], icon = TRACK .. "auctioneer", data = true },
	{ key = "repair", label = L["Repair"], icon = TRACK .. "repair", data = true },
	{ key = "classTrainer", label = L["Class trainers"], icon = TRACK .. "class", data = true, myClass = true,
		everyClass = "allClassTrainers" },   -- (AzerothVeil: FM.db.allClassTrainers, the Icons module's: every class's)
	{ key = "portalTrainer", label = L["Portal trainers"], icon = "Interface\\Minimap\\vehicle-alliancemageportal", data = true, myClass = true },
	{ key = "weaponMaster", label = L["Weapon masters"], icon = MEDIA .. "Questie\\weaponmaster", data = true },
	{ key = "stable", label = L["Stable masters"], icon = TRACK .. "stablemaster", data = true },
	{ key = "battlemaster", label = L["Battlemasters"], icon = TRACK .. "battlemaster", data = true },
	{ key = "spirit", label = L["Spirit healers"], icon = "Interface\\raidframe\\raid-icon-rez", data = true, anyFaction = true },
	{ key = "barber", label = L["Barbers"], icon = MEDIA .. "Questie\\barbershop.png", data = true },   -- (a PNG: named in full)
	{ key = "transmogrifier", label = L["Transmogrifiers"], icon = TRACK .. "transmogrifier", data = true },
	{ key = "mailbox", label = L["Mailboxes"], icon = TRACK .. "mailbox", data = true },
	{ key = "food", label = L["Food"], icon = 133964, data = true },
	{ key = "drink", label = L["Drink"], icon = 134712, data = true },
	{ key = "reagents", label = L["Reagents"], icon = TRACK .. "reagents", data = true },
	{ key = "tradeGoods", label = L["Trade goods"], icon = 132912, data = true },
	{ key = "bags", label = L["Bags"], icon = 133634, data = true },
	{ key = "potions", label = L["Potions"], icon = 134831, data = true },
	{ key = "ammo", label = L["Ammo"], icon = TRACK .. "ammunition", data = true },
	{ key = "poisons", label = L["Poisons"], icon = TRACK .. "poisons", data = true },

	-- profession trainers, one kind each (Questie's profession icons)
	{ key = "prof_ALCHEMY", label = L["Alchemy"], icon = ICONS .. "trade_alchemy", data = "profTrainer", tag = "ALCHEMY" },
	{ key = "prof_BLACKSMITHING", label = L["Blacksmithing"], icon = ICONS .. "trade_blacksmithing", data = "profTrainer", tag = "BLACKSMITHING" },
	{ key = "prof_COOKING", label = L["Cooking"], icon = ICONS .. "inv_misc_food_15", data = "profTrainer", tag = "COOKING" },
	{ key = "prof_ENCHANTING", label = L["Enchanting"], icon = ICONS .. "trade_engraving", data = "profTrainer", tag = "ENCHANTING" },
	{ key = "prof_ENGINEERING", label = L["Engineering"], icon = ICONS .. "trade_engineering", data = "profTrainer", tag = "ENGINEERING" },
	{ key = "prof_FIRST_AID", label = L["First Aid"], icon = ICONS .. "spell_holy_sealofsacrifice", data = "profTrainer", tag = "FIRST_AID" },
	{ key = "prof_FISHING", label = L["Fishing"], icon = ICONS .. "trade_fishing", data = "profTrainer", tag = "FISHING" },
	{ key = "prof_HERBALISM", label = L["Herbalism"], icon = ICONS .. "trade_herbalism", data = "profTrainer", tag = "HERBALISM" },
	{ key = "prof_LEATHERWORKING", label = L["Leatherworking"], icon = ICONS .. "trade_leatherworking", data = "profTrainer", tag = "LEATHERWORKING" },
	{ key = "prof_MINING", label = L["Mining"], icon = ICONS .. "trade_mining", data = "profTrainer", tag = "MINING" },
	{ key = "prof_SKINNING", label = L["Skinning"], icon = ICONS .. "inv_misc_pelt_wolf_01", data = "profTrainer", tag = "SKINNING" },
	{ key = "prof_TAILORING", label = L["Tailoring"], icon = ICONS .. "trade_tailoring", data = "profTrainer", tag = "TAILORING" },
	{ key = "prof_RIDING", label = L["Riding"], icon = ICONS .. "spell_nature_swiftness", data = "profTrainer", tag = "RIDING" },
}
P.CATS = CATS
-- AzerothVeil: (here, before the tooltips use it)
local CLASSES = { WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true, SHAMAN = true, MAGE = true,
	WARLOCK = true, DRUID = true }
-- (a class trainer's kind in its class's colour: the Icons module's "Class colours"; else nil)
local function ClassColour(class)
	if not (class and FM.db.trainerClassColours) then return end
	return (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class))
		or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
end

P.ENEMY_TINT = { 1, 0.45, 0.4 }      -- (the other faction's flight masters: their icon in red)
local byKey = {}
for i, c in ipairs(CATS) do
	byKey[c.key] = c
	c.layer = c.layer or 2
	c.order = i
	c.minZoom = c.minZoom or OPEN_ZOOM
	if c.data then
		c.minZoom = FM.Map.TOWNSFOLK_ZOOM   -- (AzerothVeil: Map.lua)
		c.group = c.tag and "professions" or "townsfolk"
		c.size = c.size or 18
	end
end

-- (AzerothVeil: zeppelins as OpenMap shows them, every tower alike; no longer MapUtils' piers, the Forsaken one
-- on Tirisfal's side)
local TRANSPORT_ICON = {
	zeppelin = ZEPPELIN_ICON, airship = "atlas:vehicle-air-alliance",
}
-- whose a transport is: the goblins' boats serve both factions; every other boat is the Alliance's, every
-- zeppelin the Horde's
local NEUTRAL_ROUTES = { ["Booty Bay - Ratchet"] = true, ["Steamwheedle Port - Powderfuse Port"] = true }
function P.TransportFaction(kind, route)
	if kind == "zeppelin" then return "Horde" end
	if kind == "boat" then return NEUTRAL_ROUTES[route] and "Neutral" or "Alliance" end
	return "Neutral"
end
-- a harbor's or a boat's picture in its faction's colours (Media\<base>_horde / _alliance); the goblins'
-- ones, serving both, in yours
function P.FactionArt(base, faction)
	if faction ~= "Horde" and faction ~= "Alliance" then faction = UnitFactionGroup("player") end
	return MEDIA .. base .. (faction == "Horde" and "_horde" or "_alliance")
end
P.PAINTED_OUTLINE = { dark = 0.55, width = 1 }   -- (the outline round those pictures: a screen pixel, lighter)
-- the other faction's
function P.EnemyArt(base)
	return P.FactionArt(base, UnitFactionGroup("player") == "Horde" and "Alliance" or "Horde")
end
-- whether you can take it: a harbor's boats only your faction's and the neutral ones
function P.OwnFaction(kind, route)
	if kind ~= "boat" then return true end
	local f = P.TransportFaction(kind, route)
	return f == "Neutral" or f == UnitFactionGroup("player")
end
-- whether it shows: yours, or the other faction's too where the options say so (theirs in red)
function P.Usable(kind, route)
	return FM.db.enemyHarbors or P.OwnFaction(kind, route)
end
local TRAM_ICON = MEDIA .. "tram"   -- (MapUtils' pier_tram, its stray corner dots cleared)
local TRAMS = {                          -- { map, x, y, to }
	{ 1453, 0.6901, 0.3071, "Ironforge" },     -- Stormwind, Dwarven District
	{ 1455, 0.76676, 0.51133, "Stormwind" },   -- Ironforge, Tinker Town
}
-- (a zeppelin tower's platforms, a harbour's piers: this close, one icon)
local DOCK_YARDS = { zeppelin = 90, boat = 250 }
-- (a few townsfolk set a little off their spot, so their icon shows beside a tower's rather than under
-- it: their map, name, and how far (the data's units: hundredths of a percent of the map))
local NPC_MOVE = {
	[1434] = { ["Innkeeper Thulbek"] = { -19, 5 } },   -- (Grom'gol: some 12 yards west, off the zeppelin tower)
}
-- (towers whose middle isn't their platforms': where the tower drawn on the ground stands, in world
-- coordinates (continent, x, y), read off the minimap's own picture of it)
local DOCK_CENTRES = {
	{ "zeppelin", 1, 1343.8, -4650.1 },    -- Orgrimmar's tower, Durotar
	{ "zeppelin", 0, -12432.2, 207.0 },    -- Grom'gol's tower, Stranglethorn Vale
}
local function DockCentre(kind, cont, x, y)
	local near = DOCK_YARDS[kind]
	if not near then return nil end
	for _, c in ipairs(DOCK_CENTRES) do
		if c[1] == kind and c[2] == cont and (c[3] - x) ^ 2 + (c[4] - y) ^ 2 < near * near then
			return Geo.WorldToUnits(cont, c[3], c[4])
		end
	end
end
local DOCK_TITLE = { zeppelin = L["Zeppelin tower"], boat = L["Harbor"] }
local TRANSPORT_NAME = { boat = L["Boat"], zeppelin = L["Zeppelin"], airship = L["Airship"] }

local pinLayer, topLayer
local pool, shown, prevShown = {}, {}, {}
local nShown, nPrev = 0, 0
local pass = 0
local total = 0
local waypoint, waypointTex
local waypointPin, selectedTex          -- the icon the waypoint was set on (outlined); its texture now

---------------------------------------------------------------------------
-- Pins
---------------------------------------------------------------------------
local BuildTree, Rep                     -- (Joining, below)

local function AddPin(cat, u, v, pin)
	-- (past the world's right edge: the lands off its map, Zephras Isle, each in a place of its own, Geo.AWAY)
	if not u or u < 0 or v < 0 or u > FM.W * 3 or v > FM.H then return end
	pin.u, pin.v, pin.cat = u, v, cat
	cat.tree = nil                         -- (its groups worked out again when next shown)
	cat.pins = cat.pins or {}
	cat.grid = cat.grid or {}
	cat.pins[#cat.pins + 1] = pin
	local key = floor(u / CELL) * GRID_W + floor(v / CELL)
	local cell = cat.grid[key]
	if not cell then cell = {} cat.grid[key] = cell end
	cell[#cell + 1] = pin
	total = total + 1
	return pin
end

local function ClearCat(cat)
	if cat.pins then total = total - #cat.pins end
	cat.pins, cat.grid, cat.built, cat.tree = nil, nil, nil, nil
	FM.Map.MarkDirty()
end

-- (the icons' own size: what was 1.10 on the size slider is its 1.00 now)
P.BASE_SCALE = 1.1
local function PinSize(pin)
	return (pin.psize or pin.cat.size) * P.BASE_SCALE * (FM.db.iconScale or 1)
end

-- the size slider moved: every pin on the map now
function P.ApplyScale()
	for _, c in ipairs(CATS) do
		c.tree = nil                     -- (which icons overlap: worked out again for the new size)
		for _, pin in ipairs(c.pins or {}) do
			if pin.tex then
				pin.size = PinSize(pin)
				pin.tex:SetSize(pin.size, pin.size)
				if pin.fqt then
					local c = pin.tint
					FM.Tint.Gradient(pinLayer, pin.tex, true, pin.icon or pin.cat.icon, 0, 1, 0, 1, pin.size, c and c[4] or 1,
						"ARTWORK", math.min(pin.cat.layer + 1, 7))
				end
			end
		end
	end
	FM.Map.MarkDirty()
end

-- MapUtils' dark outline round the zeppelin and tram icons: the icon
-- again in black, a screen pixel off in each of eight directions, hung on the icon (it moves with it).
-- on: true, or { dark = how dark (0-1), width = how many screen pixels }
local function Outline(t, icon, on, layer)
	if not on then
		if t.outline then for i = 1, 8 do t.outline[i]:Hide() end end
		return
	end
	local dark, width = 1, 1
	if type(on) == "table" then dark, width = on.dark or 1, on.width or 1 end
	if not t.outline then
		t.outline = {}
		for i = 1, 8 do
			local o = pinLayer:CreateTexture(nil, "ARTWORK")
			if o.SetSnapToPixelGrid then o:SetSnapToPixelGrid(false) o:SetTexelSnappingBias(0) end
			t.outline[i] = o
		end
	end
	-- (where they sit: again only when the width changed, the textures going from one icon to another)
	if t.outlineWidth ~= width then
		t.outlineWidth = width
		local _, physH = GetPhysicalScreenSize()
		local es = pinLayer:GetEffectiveScale()
		local step = ((physH and physH > 0 and es > 0) and 768 / physH / es or 1) * width
		for i = 1, 8 do
			local o = t.outline[i]
			local a = (i - 1) * math.pi / 4
			local dx, dy = floor(math.cos(a) + 0.5) * step, floor(math.sin(a) + 0.5) * step
			o:ClearAllPoints()
			o:SetPoint("TOPLEFT", t, "TOPLEFT", dx, dy)
			o:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", dx, dy)
		end
	end
	for i = 1, 8 do
		local o = t.outline[i]
		S.SetIcon(o, icon)
		o:SetVertexColor(0, 0, 0, dark)
		o:SetAlpha(1)
		o:SetDrawLayer("ARTWORK", math.max(-8, layer - 1))
		o:Show()
	end
end

-- The waypoint's icon: a soft gold glow behind it (added on, so it lights the map round the icon),
-- so it reads as picked
local SEL = { 1, 0.78, 0.3 }
local function Selected(t, icon, on, layer)
	if not on then
		if t.glow then t.glow:Hide() end
		return
	end
	if not t.glow then
		local g = pinLayer:CreateTexture(nil, "ARTWORK")
		g:SetTexture(MEDIA .. "glow")
		g:SetBlendMode("ADD")
		g:SetPoint("CENTER", t, "CENTER")
		t.glow = g
	end
	local g = t.glow
	local w = t:GetWidth()
	g:SetSize(w * 2.3, w * 2.3)
	g:SetVertexColor(SEL[1], SEL[2], SEL[3], 0.9)
	g:SetDrawLayer("ARTWORK", math.max(-8, layer - 2))
	g:Show()
end

-- Questie's coloured glow round an objective's icon (its own texture and colour), hung on the icon
local function Halo(t, glow, layer)
	if not glow then
		if t.halo then t.halo:Hide() end
		return
	end
	local h = t.halo
	if not h then
		h = pinLayer:CreateTexture(nil, "ARTWORK")
		h:SetPoint("TOPLEFT", t, "TOPLEFT", 0, 0)
		h:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 0, 0)
		t.halo = h
	end
	h:ClearAllPoints()
	-- (as Questie sizes it: 1.13 of the icon)
	h:SetPoint("CENTER", t, "CENTER")
	h:SetSize(t:GetWidth() * 1.13, t:GetHeight() * 1.13)
	h:SetTexture(glow[1])
	h:SetVertexColor(glow[2], glow[3], glow[4], glow[5] or 1)
	h:SetDrawLayer("ARTWORK", math.max(-8, (layer or 0) - 1))
	h:SetAlpha(1)
	h:Show()
end

local function Acquire(pin)
	local t = tremove(pool)
	if not t then
		t = pinLayer:CreateTexture(nil, "ARTWORK")
		if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) t:SetTexelSnappingBias(0) end
	end
	local cat = pin.cat
	local icon = pin.icon or cat.icon
	S.SetIcon(t, icon)
	if cat.drawLayer then t:SetDrawLayer(cat.drawLayer, 0) else t:SetDrawLayer("ARTWORK", cat.layer) end
	t:SetDesaturated(pin.dim and true or false)
	local c = pin.tint
	if c then t:SetVertexColor(c[1], c[2], c[3], c[4] or 1) else t:SetVertexColor(1, 1, 1, 1) end
	t:SetAlpha(pin.dim and 0.7 or 1)
	local size = PinSize(pin)
	t:SetSize(size, size)
	Outline(t, icon, pin.outline, math.min(cat.layer, 7))
	Halo(t, pin.glow, math.min(cat.layer, 7))
	-- (Forever Quest Tint's gradient: Questie's yellow icons of quests new in Forever, Tint.lua)
	FM.Tint.Gradient(pinLayer, t, pin.fqt, icon, 0, 1, 0, 1, size, c and c[4] or 1, "ARTWORK", math.min(cat.layer + 1, 7))
	if t.fmTint then t.fmTint.solid:SetAlpha(1) t.fmTint.fade:SetAlpha(1) end
	pin.size = size
	pin.tex = t
	t:Show()
	return t
end

local function Release(pin)
	local t = pin.tex
	if t then
		t:Hide()
		t:ClearAllPoints()
		Outline(t, nil, false)
		Halo(t, nil)
		FM.Tint.Gradient(pinLayer, t, false)
		Selected(t, nil, false)
		pool[#pool + 1] = t
		pin.tex = nil
	end
end

-- Every icon stands on its spot, never moved by the zoom. Pins that are the same thing drawn the same
-- way (same kind, icon, tint, shading) and overlap are summed: one icon, the one nearest their middle,
-- with their count on it and all of them in its tooltip (Joining, below). A kind that comes on with the
-- zoom fades in, all of it at once
local GLIDE = 0.22                     -- seconds a pin takes to glide out of / into its group
local FADE = 0.18                      -- seconds a kind takes to fade in as the zoom brings it on

-- Joining, decided in the world once: the same things of a kind whose icons overlap where the kind first
-- shows (at M's opening zoom, if it shows before that), chained, are one group at every zoom: shown by the
-- one nearest their middle, with their count, never split by the zoom. Options' "Sum identical icons" off:
-- none summed, every icon on its own, no counts.
-- (A tree of groups, nearest pairs first; each group's head: the one shown.)
local JOIN_OVERLAP = 0.8               -- icons closer than this much of their size overlap
-- (world units a kind's icons overlap within, where it first shows: its icon's size at that zoom, the
-- window at its own width)
local function JoinReach(cat)
	local z = math.max(cat.minZoom or 0, OPEN_ZOOM)
	local pxPerUnit = z * (FM.db.window and FM.db.window.mapW or 960) / FM.W
	return JOIN_OVERLAP * (cat.size or 18) * P.BASE_SCALE * (FM.db.iconScale or 1) / pxPerUnit
end
local function IdKey(pin)
	local c, g = pin.tint, pin.glow
	return tostring(pin.icon or pin.cat.icon) .. (pin.dim and "|d" or "") .. (pin.outline and "|o" or "") .. (pin.fqt and "|t" or "")
		.. (c and ("|" .. floor(c[1] * 20) .. "," .. floor(c[2] * 20) .. "," .. floor(c[3] * 20) .. "," .. floor((c[4] or 1) * 20)) or "")
		.. (g and ("|g" .. floor(g[2] * 20) .. "," .. floor(g[3] * 20) .. "," .. floor(g[4] * 20)) or "")
end

local function Top(x)
	while x.parent do x = x.parent end
	return x
end

BuildTree = function(cat)
	cat.tree = true
	local list = cat.pins
	if not list then return end
	local reach = JoinReach(cat)
	cat.reach = reach
	local grid = {}
	for i, p in ipairs(list) do
		p.parent, p.n, p.head, p.cu, p.cv, p.order, p.leaves = nil, 1, p, p.u, p.v, i, nil
		p.idKey = IdKey(p)
		local key = floor(p.u / reach) * 100000 + floor(p.v / reach)
		local c = grid[key]
		if not c then c = {} grid[key] = c end
		c[#c + 1] = p
	end
	if cat.free then return end          -- (each one shown on its own, as it is)
	local edges = {}
	for _, p in ipairs(list) do
		local ci, cj = floor(p.u / reach), floor(p.v / reach)
		for i = ci - 1, ci + 1 do
			for j = cj - 1, cj + 1 do
				local c = grid[i * 100000 + j]
				if c then
					for _, q in ipairs(c) do
						if q.order > p.order and q.idKey == p.idKey then
							local du, dv = q.u - p.u, q.v - p.v
							local d = math.sqrt(du * du + dv * dv)
							if d < reach then edges[#edges + 1] = { d, p, q } end
						end
					end
				end
			end
		end
	end
	table.sort(edges, function(a, b) return a[1] < b[1] end)
	for _, e in ipairs(edges) do
		local a, b = Top(e[2]), Top(e[3])
		if a ~= b then
			local n = a.n + b.n
			local node = { d = e[1], a = a, b = b, n = n,
				cu = (a.cu * a.n + b.cu * b.n) / n, cv = (a.cv * a.n + b.cv * b.n) / n,
				head = a.head.order < b.head.order and a.head or b.head }
			a.parent, b.parent = node, node
		end
	end
	-- (each group shown by the one of them nearest its middle)
	local best = {}
	for _, p in ipairs(list) do
		local top = Top(p)
		if top ~= p then
			local du, dv = p.u - top.cu, p.v - top.cv
			local d = du * du + dv * dv
			local b = best[top]
			if not b or d < b then best[top] = d top.head = p end
		end
	end
end

-- the group a pin is shown in (itself, if none, or with summing off): the same at every zoom
Rep = function(pin)
	if FM.db.joinIcons == false or pin.cat.noJoin then return pin end
	local reach = pin.cat.reach or 0
	local x = pin
	while x.parent and x.parent.d <= reach do x = x.parent end
	return x
end

-- every pin in a group (its leaves), kept on it
local function Members(rep)
	if rep.leaves then return rep.leaves end
	local list = {}
	local function Walk(x)
		if x.a then Walk(x.a) Walk(x.b) else list[#list + 1] = x end
	end
	Walk(rep)
	-- (the one shown first, the others in the order they were added)
	table.sort(list, function(p, q)
		if p == rep.head then return true elseif q == rep.head then return false end
		return p.order < q.order
	end)
	rep.leaves = list
	return list
end

-- the most important on top
local ORDER = {}
for _, c in ipairs(CATS) do ORDER[#ORDER + 1] = c end
table.sort(ORDER, function(a, b) if a.layer ~= b.layer then return a.layer > b.layer end return a.order < b.order end)

-- Moving pins: gliding (drawn off its spot by (gx, gy), the offset closing over GLIDE seconds;
-- pin.into: the group it glides into, fading as it goes, let go once there) and fading in (pin.ft:
-- when; every pin of a kind that came on together has the same, so they show as one)
local anim, nAnim = {}, 0
local into, nInto, intoNext = {}, 0, {}
local function Ease(s) return s * s * (3 - 2 * s) end
local function Animate(pin)
	if not pin.anim then pin.anim = true nAnim = nAnim + 1 anim[nAnim] = pin end
end
local function StartGlide(pin, gx, gy, now)
	if gx * gx + gy * gy < 1 then pin.gt = nil return end
	pin.gx, pin.gy, pin.gt = gx, gy, now
	Animate(pin)
end
local function SetFade(pin, a)
	local t = pin.tex
	if not t then return end
	t:SetAlpha((pin.dim and 0.7 or 1) * a)
	if t.outline then for i = 1, 8 do t.outline[i]:SetAlpha(a) end end
	if t.halo then t.halo:SetAlpha(a) end
	if t.fmTint then t.fmTint.solid:SetAlpha(a) t.fmTint.fade:SetAlpha(a) end
end
-- drawn where it is now, as faded as it is now; true once it's still
local function Place(pin, now)
	local x, y
	local settled = true
	if pin.into then
		x, y = pin.into.dx, pin.into.dy
	else
		x, y = pin.bx, pin.by
	end
	local g = 1
	if pin.gt then
		g = (now - pin.gt) / GLIDE
		if g >= 1 then pin.gt, g = nil, 1
		else
			local k = 1 - Ease(g)
			x, y = x + pin.gx * k, y + pin.gy * k
		end
	end
	pin.dx, pin.dy = x, y
	pin.tex:SetPoint("CENTER", pinLayer, "TOPLEFT", x, -y)
	if pin.into then
		SetFade(pin, 1 - Ease(g))
	elseif pin.ft then
		local f = (now - pin.ft) / FADE
		if f >= 1 then pin.ft = nil SetFade(pin, 1) else SetFade(pin, Ease(math.max(f, 0))) end
	end
	return not pin.gt and not pin.ft and settled
end

local badges, nBadges = {}, 0

-- place the pins in view; called on every pan / zoom
local snapNext = false                 -- the next layout puts everything straight where it belongs (P.OnShow)

function P.Layout(left, top, scale, vw, vh, ppu, zoom)
	pass = pass + 1
	local now = GetTime()
	-- (the map just opened: no joining, splitting or fading in, as if it had never been closed)
	local snap = snapNext
	snapNext = false
	prevShown, shown = shown, prevShown
	nPrev, nShown = nShown, 0
	local nNext = 0
	local pins = FM.db.pins
	local x1, y1 = left + vw / scale, top + vh / scale
	local pad = 20 / scale
	local ci0, ci1 = floor((left - pad) / CELL), floor((x1 + pad) / CELL)
	local cj0, cj1 = floor((top - pad) / CELL), floor((y1 + pad) / CELL)
	-- a group (or a lone pin) shown by its head pin, where the group stands
	local function Show(head, rep, fading)
		if head.pass == pass and head.rep == rep then return end
		-- (where its first one stands: a group splitting leaves it where it was, the others come out of it)
		local x, y = (head.u - left) * scale, (head.v - top) * scale
		local r = PinSize(head) * 0.5
		local t = head.tex
		if snap then
			if not t then Acquire(head) end
			head.into, head.gt, head.ft = nil, nil, nil
			SetFade(head, 1)
		elseif head.into then
			-- (it was gliding into a group: out again, from where it is)
			head.into = nil
			SetFade(head, 1)
			StartGlide(head, head.dx - x, head.dy - y, now)
		elseif not t then
			t = Acquire(head)
			-- (it was in a group last time: it comes out of where the group was)
			local l = head.leader
			if head.lpass == pass - 1 and l and l.tex then
				StartGlide(head, l.dx - x, l.dy - y, now)
			else
				head.gt = nil
			end
			if fading then head.ft = fading SetFade(head, 0) Animate(head) else head.ft = nil end
		end
		head.leader = nil
		head.rep = rep
		head.bx, head.by = x, y
		head.tx, head.ty, head.r = x, y, r
		-- (the group's count on it, and every one of them in its tooltip)
		if rep ~= head and rep.a then
			head.members = Members(rep)
		else
			head.solo = head.solo or { head }
			head.members = head.solo
		end
		head.count = #head.members
		Place(head, now)
		head.pass = pass
		nShown = nShown + 1
		shown[nShown] = head
	end
	for _, cat in ipairs(ORDER) do
		local on = pins[cat.key] and cat.grid and zoom >= cat.minZoom and not (cat.maxZoom and zoom >= cat.maxZoom) and true or false
		-- (just come on with the zoom: the whole kind fades in from now, together)
		if on and cat.prevOn == false then cat.fadeFrom = now end
		cat.prevOn = on and true or false
		if snap and on then cat.fadeFrom = nil end
		local fading = cat.fadeFrom and now - cat.fadeFrom < FADE and cat.fadeFrom
		if on then
			if not cat.tree then BuildTree(cat) end
			local grid = cat.grid
			for ci = ci0, ci1 do
				for cj = cj0, cj1 do
					local cell = grid[ci * GRID_W + cj]
					if cell then
						for k = 1, #cell do
							local pin = cell[k]
							local u, v = pin.u, pin.v
							if u >= left - pad and u <= x1 + pad and v >= top - pad and v <= y1 + pad then
								-- its group at this zoom (decided in the world: Join)
								local rep = Rep(pin)
								local head = rep.head
								Show(head, rep, fading)
								if head ~= pin then
									pin.leader, pin.lpass = head, pass
									if snap and pin.tex then
										pin.into, pin.gt, pin.ft = nil, nil, nil
										Release(pin)
									elseif pin.tex and pin.pass ~= pass then
										-- (it was on the map: it glides into its group)
										if not pin.into then StartGlide(pin, pin.dx - head.dx, pin.dy - head.dy, now) Animate(pin) end
										pin.into = head
										pin.ft = nil
										pin.rep = nil
										pin.pass = pass
										nNext = nNext + 1
										intoNext[nNext] = pin
										Place(pin, now)
									end
								end
							end
						end
					end
				end
			end
		end
	end
	for i = 1, nPrev do
		local pin = prevShown[i]
		if pin.pass ~= pass then Release(pin) end
		prevShown[i] = nil
	end
	-- (the ones gliding into a group that's gone now: let go)
	for i = 1, nInto do
		local pin = into[i]
		if pin.into and pin.pass ~= pass then pin.into = nil Release(pin) end
		into[i] = nil
	end
	into, intoNext, nInto = intoNext, into, nNext
	-- the counts of summed pins: only on a group of identical icons, its own number (two different icons
	-- that merely overlap get none); hung on their pin, they follow it
	local nb = 0
	for i = 1, nShown do
		local pin = shown[i]
		if pin.count > 1 and FM.db.joinIcons ~= false then
			nb = nb + 1
			local b = badges[nb]
			if not b then
				b = pinLayer:CreateFontString(nil, "OVERLAY")
				S.Font(b, 11, "OUTLINE")
				b:SetTextColor(1, 1, 1)
				badges[nb] = b
			end
			b:SetText(pin.count)
			b:ClearAllPoints()
			b:SetPoint("CENTER", pin.tex, "CENTER", pin.size * 0.42, -pin.size * 0.32)
			b:Show()
		end
	end
	for i = nb + 1, nBadges do badges[i]:Hide() end
	nBadges = math.max(nb, nBadges)
	-- the user waypoint
	if waypoint then
		waypoint.sx, waypoint.sy = (waypoint.u - left) * scale, (waypoint.v - top) * scale
		waypoint.dx, waypoint.dy = waypoint.sx, waypoint.sy
	end
	-- (on its icon: that icon, or the group it's in, outlined in gold; on a bare spot, the ring)
	local carrier = waypointPin
	if carrier and not (carrier.tex and carrier.pass == pass and not carrier.into) then
		carrier = carrier.leader and carrier.leader.tex and carrier.leader.pass == pass and carrier.leader or nil
	end
	if selectedTex and (not carrier or selectedTex ~= carrier.tex) then Selected(selectedTex, nil, false) selectedTex = nil end
	if carrier and carrier.tex ~= selectedTex then
		selectedTex = carrier.tex
		Selected(selectedTex, carrier.icon or carrier.cat.icon, true, math.min(carrier.cat.layer, 7))
	end
	if waypointTex then
		if waypoint and not waypointPin then
			-- (the game's own map pin: its look while followed, and while not)
			local followed = C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint and C_SuperTrack.IsSuperTrackingUserWaypoint()
			local atlas = followed and "Waypoint-MapPin-Tracked" or "Waypoint-MapPin-Untracked"
			if waypointTex.atlas ~= atlas then
				waypointTex.atlas = atlas
				if not (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) and waypointTex:SetAtlas(atlas) ~= false) then
					waypointTex:SetTexture(MEDIA .. "ring")
					waypointTex:SetVertexColor(1, 0.82, 0.25)
				end
			end
			waypointTex:SetPoint("CENTER", topLayer, "TOPLEFT", waypoint.sx, -waypoint.sy)
			waypointTex:Show()
		else
			waypointTex:Hide()
		end
	end
end

-- every frame while something glides or fades (nothing to do otherwise)
function P.Tick()
	if nAnim == 0 then return end
	local now = GetTime()
	local n = 0
	for i = 1, nAnim do
		local pin = anim[i]
		anim[i] = nil
		if pin.tex and (pin.gt or pin.ft or pin.into) then
			if Place(pin, now) then
				pin.anim = nil
				if pin.into then pin.into = nil Release(pin) end   -- (it's in its group now)
			else
				n = n + 1
				anim[n] = pin
			end
		else
			pin.anim, pin.gt, pin.ft = nil, nil, nil
			if pin.into and pin.tex then pin.into = nil Release(pin) end
		end
	end
	nAnim = n
end

-- every icon the map may show, loaded before it's wanted: a kind coming on with the zoom shows all
-- at once, not one icon now and another when its file has loaded
local warm, warmed = {}, {}
local function Warm(icon)
	if not icon or warmed[icon] or not pinLayer then return end
	warmed[icon] = true
	local t = pinLayer:CreateTexture(nil, "BACKGROUND")
	S.SetIcon(t, icon)
	t:SetSize(1, 1)
	t:SetPoint("TOPLEFT", -50, 50)          -- (off the view, which clips it)
	t:SetAlpha(0.01)
	warm[#warm + 1] = t
end
local function WarmAll()
	for _, cat in ipairs(CATS) do
		Warm(cat.icon)
		for _, pin in ipairs(cat.pins or {}) do if pin.icon then Warm(pin.icon) end end
	end
end

-- external categories (quests): replace all their pins at once
function P.SetPins(key, list)
	local cat = byKey[key]
	if not cat then return end
	-- (AzerothVeil: the waypoint on one of them stays on its new self, at the same place)
	local was = waypointPin and waypointPin.cat == cat and waypointPin
	ClearCat(cat)
	for _, pin in ipairs(list) do
		AddPin(cat, pin.u, pin.v, pin)
		Warm(pin.icon)
	end
	cat.built = true
	if was then
		waypointPin = nil
		for _, pin in ipairs(cat.pins or {}) do
			if math.abs(pin.u - was.u) < 0.01 and math.abs(pin.v - was.v) < 0.01 then waypointPin = pin break end
		end
	end
end

---------------------------------------------------------------------------
-- Hover and click
---------------------------------------------------------------------------
local hovered = {}
local nHovered = 0
local tipLines = {}

local function CursorView()
	local _, _, sx, sy = FM.Map.CursorUnits()
	return sx, sy
end

-- the pins under the cursor: each placed pin hit, with the ones joined to it; anchor: the first hit
local anchor
local function FindUnderCursor()
	local sx, sy = CursorView()
	local n = 0
	anchor = nil
	for i = nShown, 1, -1 do
		local pin = shown[i]
		local r = pin.size * 0.5 + 2
		local dx, dy = pin.dx - sx, pin.dy - sy
		if dx * dx + dy * dy <= r * r then
			anchor = anchor or pin
			for m = 1, pin.count do
				if n >= 30 then break end
				n = n + 1
				hovered[n] = pin.members[m]
			end
		end
	end
	for i = n + 1, nHovered do hovered[i] = nil end
	nHovered = n
	return n
end

-- Questie's own icons, mirrored: Questie's own tooltip for them (every quest, objective and NPC it
-- lists for the icons under the cursor, exactly as on Blizzard's map), and its OnLeave after
local questieTip, questieCount
local qIcons = {}
-- (the tooltip's first line is the game's header, bigger than the rest: in Questie's list of quests it
-- would make the first one stand out. Set as the lines under it while Questie's tooltip is up, and
-- put back as the tooltip hides, so the game's other tooltips keep their header)
local headerKept
-- the icons under the cursor, looked for again (no tooltip): their count
function P.UnderCursor() return FindUnderCursor() end

-- the icons under the cursor now (each joined one too): list, count
function P.Hovered() return hovered, nHovered end

local function RestoreHeader()
	if not headerKept then return end
	for _, h in ipairs(headerKept) do
		if h.font then pcall(h.line.SetFont, h.line, h.font, h.size, h.flags) end
	end
	headerKept = nil
end
local function EvenHeader()
	RestoreHeader()
	local kept = {}
	for _, side in ipairs({ "Left", "Right" }) do
		local first, second = _G["GameTooltipText" .. side .. "1"], _G["GameTooltipText" .. side .. "2"]
		if first and second then
			local font, size, flags = first:GetFont()
			local f2, s2, fl2 = second:GetFont()
			if font and f2 then
				kept[#kept + 1] = { line = first, font = font, size = size, flags = flags }
				first:SetFont(f2, s2, fl2)
			end
		end
	end
	headerKept = kept
	if not GameTooltip.fmHeaderHook then
		GameTooltip.fmHeaderHook = true
		GameTooltip:HookScript("OnHide", RestoreHeader)
	end
	GameTooltip:Show()
end

local function EndQuestieTip()
	if not questieTip then return end
	local f = questieTip:GetScript("OnLeave")
	if f then pcall(f, questieTip) end
	questieTip, questieCount = nil, nil
	if GameTooltip:GetOwner() == pinLayer then GameTooltip:Hide() end
	RestoreHeader()
end
local function QuestieTip(n)
	wipe(qIcons)
	for i = 1, n do
		local icon = hovered[i].qicon
		if icon and icon.data then qIcons[#qIcons + 1] = icon end
	end
	if #qIcons == 0 then EndQuestieTip() return false end
	if questieTip == qIcons[1] and questieCount == #qIcons then return true end
	EndQuestieTip()
	local QL = _G.QuestieLoader
	local ok, MIT = false, nil
	if QL then ok, MIT = pcall(QL.ImportModule, QL, "MapIconTooltip") end
	if not (ok and MIT and MIT.ShowOnTooltip) then return false end
	local list = {}
	for i, icon in ipairs(qIcons) do list[i] = icon end
	if pcall(MIT.ShowOnTooltip, qIcons[1], GameTooltip, pinLayer, list) then
		questieTip, questieCount = qIcons[1], #qIcons
		EvenHeader()
		return true
	end
	return false
end

local hoverWaypoint = false
local tipFirst, tipCount, tipWaypoint      -- what the tooltip shows now (rebuilt only when that changes)
function P.Hover(clear)
	if clear then
		nHovered = 0
		-- (only an icon's own tooltip: the cursor on a button over the map keeps the button's)
		if tipFirst ~= nil then tipFirst = nil S.HideTip() end
		EndQuestieTip()
		return
	end
	local n = FindUnderCursor()
	-- (Questie's tooltip and ours are the same GameTooltip: ours goes first, then Questie fills it)
	local anyQuestie = false
	for i = 1, n do if hovered[i].qicon then anyQuestie = true break end end
	if anyQuestie then
		if tipFirst ~= nil then tipFirst = nil S.HideTip() end
		if QuestieTip(n) then return true end
	else
		EndQuestieTip()
	end
	hoverWaypoint = false
	if waypoint and waypoint.sx and not waypointPin then
		local sx, sy = CursorView()
		local dx, dy = waypoint.sx - sx, waypoint.sy - sy
		hoverWaypoint = dx * dx + dy * dy <= 144
	end
	if n == 0 and not hoverWaypoint then
		if tipFirst ~= nil then tipFirst = nil S.HideTip() end
		return false
	end
	local p = n > 0 and hovered[1] or waypoint
	local at = n > 0 and anchor or waypoint     -- (where it shows: the placed pin, by its count)
	if tipFirst == p and tipCount == n and tipWaypoint == hoverWaypoint then
		S.MoveTip(at.dx + (at.size or 16) * 0.5, -at.dy + 4, pinLayer)   -- (the same pins: it just follows them)
		return true
	end
	tipFirst, tipCount, tipWaypoint = p, n, hoverWaypoint
	wipe(tipLines)
	if hoverWaypoint then
		tipLines[#tipLines + 1] = L["Waypoint"]
		tipLines[#tipLines + 1] = { L["Right-click to remove it"], 0.6, 0.6, 0.62 }
	end
	-- AzerothVeil: the townsfolk by their kind only (each kind once, "x3" for three of them), unless the Icons module's
	-- "Townsfolk's names" asks for each one's name
	local kinds, kindAt = not FM.db.townsfolkNames and {} or nil, {}
	local gap = hoverWaypoint
	for i = 1, n do
		local pin = hovered[i]
		if kinds and pin.kind then
			local at = kindAt[pin.kind]
			if at then
				kinds[at] = kinds[at] + 1
				local line = tipLines[at]
				line[1] = pin.kind .. " x" .. kinds[at]
			else
				if gap then tipLines[#tipLines + 1] = " " end
				local c = ClassColour(pin.class)
				tipLines[#tipLines + 1] = { pin.kind, c and c.r or 1, c and c.g or 0.86, c and c.b or 0.45, 12 }
				kindAt[pin.kind] = #tipLines
				kinds[#tipLines] = 1
			end
		else
			if gap then tipLines[#tipLines + 1] = " " end
			tipLines[#tipLines + 1] = { pin.title or pin.cat.label, 1, 0.86, 0.45, 12 }
			if pin.kind then
				-- (AzerothVeil: a townsfolk named: under its name what it is, in the player's language, not the data's
				-- English title; a class trainer's in its class's colour if asked)
				local c = ClassColour(pin.class)
				tipLines[#tipLines + 1] = { "<" .. pin.kind .. ">", c and c.r or 0.8, c and c.g or 0.8, c and c.b or 0.8, 11 }
			elseif pin.lines then
				for _, l in ipairs(pin.lines) do tipLines[#tipLines + 1] = l end
			end
		end
		gap = true
	end
	if n > 0 then
		local first = hovered[1]
		local picked = waypointPin and (waypointPin == first or waypointPin.leader == first)
		local right = L["Right-click: "] .. ((first.marker and P.OnMarkerRightClick) and L["delete"]          -- (AzerothVeil: a marker's)
			or picked and L["remove waypoint"] or L["set waypoint"])
		tipLines[#tipLines + 1] = { first.exits and (L["Left-click: show that zone   "] .. right) or (first.insts or first.away) and (L["Left-click: its map   "] .. right) or right, 0.5, 0.5, 0.52, 10 }
	end
	-- (on the pin itself, not the cursor: it never trails behind)
	S.ShowTip(nil, tipLines, at.dx + (at.size or 16) * 0.5, -at.dy + 4, pinLayer)
	return true
end

local function Sound(key)
	if SOUNDKIT and SOUNDKIT[key] then PlaySound(SOUNDKIT[key]) end
end

local function ClearWaypoint()
	waypointPin = nil
	C_Map.ClearUserWaypoint()
	Sound("UI_MAP_WAYPOINT_REMOVE")
	FM.Map.MarkDirty()
end

local function SetWaypointAt(u, v, label, pin)
	local mapID = Geo.ZoneAt(u, v)
	if not mapID or not (C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(mapID)) then
		FM.Print(L["can't set a waypoint there"])
		return
	end
	local x, y = Geo.UnitsToMap(mapID, u, v)
	waypointPin = pin
	C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
	if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
	Sound("UI_MAP_WAYPOINT_SUPER_TRACK_ON")       -- (MapUtils' sound for it)
	FM.Map.MarkDirty()
end

-- (the map's right-click menu, Spot.lua: the pin on a bare spot, or off)
function P.PlaceAt(u, v) SetWaypointAt(u, v, nil, nil) end
-- AzerothVeil: the waypoint on an icon of a kind (a map marker: its key and place), outlined as an icon followed
function P.FollowAt(key, u, v)
	local cat = byKey[key]
	for _, pin in ipairs(cat and cat.pins or {}) do
		if math.abs(pin.u - u) < 0.01 and math.abs(pin.v - v) < 0.01 then SetWaypointAt(u, v, nil, pin) return end
	end
	SetWaypointAt(u, v, nil, nil)
end
function P.ClearPin() ClearWaypoint() end

-- the waypoint on an icon, or off it again if it's on it already
local function ToggleWaypoint(pin)
	if waypointPin and (waypointPin == pin or waypointPin.leader == pin) then ClearWaypoint() return end
	SetWaypointAt(pin.u, pin.v, pin.title, pin)
end

-- a right-click on the map: on an icon, the waypoint on it (or off it again); on the bare spot's
-- waypoint, off; true if it did either (else the map zooms out)
function P.RightClick()
	FindUnderCursor()
	if hoverWaypoint then ClearWaypoint() return true end
	local pin = nHovered > 0 and hovered[1]
	-- (AzerothVeil: a map marker: the Markers module's right-click, deleting it)
	if pin and pin.marker and P.OnMarkerRightClick then P.OnMarkerRightClick(pin.marker) return true end
	if pin then ToggleWaypoint(pin) return true end
	return false
end

function P.Click()
	FindUnderCursor()
	if hoverWaypoint then
		ClearWaypoint()
		return
	end
	if nHovered > 0 then
		local pin = hovered[1]
		-- (a Questie icon: Questie's own click: a chat link while typing, shift: hide the quest / remove
		-- a note, ctrl: TomTom; its map's own part, opening Blizzard's map, is left out as that's shut)
		-- (AzerothVeil: a map marker: the Markers module's click, its card)
		if pin.marker and P.OnMarkerClick then P.OnMarkerClick(pin.marker) return end
		local click = pin.qicon and pin.qicon:GetScript("OnClick")
		if click then pcall(click, pin.qicon, "LeftButton") return end
		-- (a dungeon's: its map; the waypoint is the right button's, on every icon)
		if pin.insts then
			-- (summed entrances: every dungeon of all of them to pick from; each part of an instance on its own)
			local wings, seen = {}, {}
			for i = 1, nHovered do
				for _, w in ipairs(hovered[i].wings or {}) do
					local k = w.id .. "|" .. (w.name or "")
					if not seen[k] then seen[k] = true wings[#wings + 1] = w end
				end
			end
			-- (AzerothVeil: the Dungeons module's click while it runs (its map here, or DungeonJournal's page))
			if P.OnDungeonClick then P.OnDungeonClick(wings, nHovered > 1 and nil or pin.title) return end
			if #wings > 1 then FM.Dungeon.Choose(wings, nil, nHovered > 1 and nil or pin.title)
			elseif wings[1] then FM.Dungeon.OpenWing(wings[1]) end
			return
		end
		-- (a dock to a land off the world map, Zephras Isle: that land's own map, as a dungeon's)
		if pin.away then FM.Isles.Open(pin.away) return end
		-- (AzerothVeil: a signpost into the next zone: that zone whole; into several, all of them)
		if pin.exits then FM.Map.Glide(FM.Map.ShowMaps, pin.exits) Sound("IG_MAINMENU_OPTION_CHECKBOX_ON") return end
		-- (AzerothVeil: a dock or a tram station, its click the Transports module's while it's on)
		if pin.travel and P.OnTravelClick then P.OnTravelClick(pin) return end
	elseif IsShiftKeyDown() then
		-- (AzerothVeil: the Markers module's Shift-click while it's on: a marker dropped there)
		local u, v = FM.Map.CursorUnits()
		if P.OnShiftClick then P.OnShiftClick(u, v) end
	elseif IsControlKeyDown() then
		local u, v = FM.Map.CursorUnits()
		SetWaypointAt(u, v)
	end
end

local function ReadWaypoint()
	waypoint = nil
	local p = C_Map.HasUserWaypoint and C_Map.HasUserWaypoint() and C_Map.GetUserWaypoint()
	if p and p.uiMapID and p.position then
		local u, v = Geo.MapToUnits(p.uiMapID, p.position.x, p.position.y)
		if u then waypoint = { u = u, v = v } end
	end
	-- (still on its icon? set elsewhere, by another addon or the game, it isn't any more)
	if waypointPin and not (waypoint and math.abs(waypoint.u - waypointPin.u) < 0.3 and math.abs(waypoint.v - waypointPin.v) < 0.3) then
		waypointPin = nil
	end
	FM.Map.MarkDirty()
end

---------------------------------------------------------------------------
-- Builders: the game's flight masters, the Forever places, the built-in townsfolk
---------------------------------------------------------------------------
local function FactionLabel(f, Faction)
	if not Faction then return nil end
	if f == Faction.Horde then return { FACTION_HORDE or "Horde", 1, 0.35, 0.3, 11 } end
	if f == Faction.Alliance then return { FACTION_ALLIANCE or "Alliance", 0.4, 0.6, 1, 11 } end
	return { L["Neutral"], 0.85, 0.85, 0.5, 11 }
end

-- The game's taxi list also has nodes WoW Forever has no flight master at (other versions', such as
-- Cataclysm's Crown Guard Tower): a node shows only where a flight master of WoW Forever really stands
-- (Data/FlightMasters.lua, from QuestieDB's Forever data). (Not "discovered": this client doesn't say)
local FM_NEAR = 2                      -- world units (some 70 yards) between a node and its flight master
local fmGrid
local function HasFlightMaster(u, v)
	local list = FM.FLIGHT_MASTERS
	if not list then return true end
	if not fmGrid then
		fmGrid = {}
		for i = 1, #list, 3 do
			local fu, fv = Geo.MapToUnits(list[i], list[i + 1] / 10000, list[i + 2] / 10000)
			if fu then
				local key = floor(fu / 8) * 4096 + floor(fv / 8)
				local cell = fmGrid[key]
				if not cell then cell = {} fmGrid[key] = cell end
				cell[#cell + 1] = fu
				cell[#cell + 1] = fv
			end
		end
	end
	local ci, cj = floor(u / 8), floor(v / 8)
	for i = ci - 1, ci + 1 do
		for j = cj - 1, cj + 1 do
			local cell = fmGrid[i * 4096 + j]
			if cell then
				for k = 1, #cell, 2 do
					local du, dv = cell[k] - u, cell[k + 1] - v
					if du * du + dv * dv <= FM_NEAR * FM_NEAR then return true end
				end
			end
		end
	end
	return false
end

local function BuildFlights()
	local cat = byKey.flight
	if cat.pins then ClearCat(cat) end
	cat.built = true
	local Faction = Enum and Enum.FlightPathFaction
	local mine = UnitFactionGroup("player") == "Horde" and Faction and Faction.Horde or Faction and Faction.Alliance
	local maps = {}
	for _, cont in ipairs(Geo.CONTINENTS) do maps[#maps + 1] = cont end
	for _, a in ipairs(Geo.AWAY) do maps[#maps + 1] = a.map end   -- (and the lands off the world map)
	for _, cont in ipairs(maps) do
		local nodes = C_TaxiMap.GetTaxiNodesForMap(cont) or {}
		for _, n in ipairs(nodes) do
			local name = n.name or ""
			local pos = n.position
			if pos and not name:find("^zz") then
				local f = n.faction
				local friendly = not Faction or f == Faction.Neutral or f == mine
				if friendly or FM.db.enemyFlight then
					local lines = { FactionLabel(f, Faction) }
					if n.isUndiscovered then lines[#lines + 1] = { L["Not discovered yet"], 0.6, 0.6, 0.62, 11 } end
					local u, v = Geo.MapToUnits(cont, pos.x, pos.y)
					if u and HasFlightMaster(u, v) then AddPin(cat, u, v, {
						title = name, lines = lines, dim = n.isUndiscovered,
						tint = not friendly and P.ENEMY_TINT or nil,
					}) end
				end
			end
		end
	end
end

-- the six capitals, each in the middle of its own city map, with its faction's emblem
local function BuildCapitals()
	local cat = byKey.capital
	if cat.pins then ClearCat(cat) end
	cat.built = true
	local mine = UnitFactionGroup("player")
	for _, c in ipairs(CAPITALS) do
		local r = Geo.Rect(c[1])
		local info = C_Map.GetMapInfo(c[1])
		if r and info then
			local friendly = c[2] == mine
			AddPin(cat, (r[1] + r[2]) / 2, (r[3] + r[4]) / 2, {
				title = info.name, icon = CAPITAL_ICON[c[2]],
				psize = c[2] == "Alliance" and cat.size * 1.2 or nil,   -- (the Alliance's emblem a fifth bigger)
				lines = { { c[2] == "Alliance" and L["Alliance capital"] or L["Horde capital"],
					friendly and 0.5 or 1, friendly and 0.9 or 0.45, friendly and 0.5 or 0.4, 11 } },
			})
		end
	end
end

-- AzerothVeil: the signposts on the ways into the next zone: one at each spot (a way into several zones, the Timbermaw
-- Hold's: one signpost for all of them), its zones' names the game's
local function ZoneName(id)
	local info = C_Map.GetMapInfo(id)
	local name = info and FM.Plain(info.name)
	return type(name) == "string" and name ~= "" and name or nil
end
local function BuildExits()
	local cat = byKey.exit
	if cat.pins then ClearCat(cat) end
	cat.built = true
	local data, at = FM.ZONE_EXITS or {}, {}
	for i = 1, #data, 4 do
		local map, to = data[i], data[i + 3]
		local name = ZoneName(to)
		local u, v = Geo.MapToUnits(map, data[i + 1] / 100, data[i + 2] / 100)
		if u and name and Geo.Rect(to) then
			local key = map .. ":" .. data[i + 1] .. ":" .. data[i + 2]
			local pin = at[key]
			if not pin then
				pin = { exits = {}, names = {}, lines = {} }
				at[key] = pin
				AddPin(cat, u, v, pin)
			end
			pin.exits[#pin.exits + 1] = to
			pin.names[#pin.names + 1] = L["To %s"]:format(name)
			pin.title = table.concat(pin.names, "\n")
		end
	end
end
function P.PinsOf(key)
	local cat = byKey[key]
	return cat and cat.pins
end

local function LevelLine(name, lo, hi)
	if FM.db.dungeonLevels == false then lo, hi = nil, nil end   -- (AzerothVeil: the Dungeons module's switch)
	local mid = floor(((lo or 0) + (hi or lo or 0)) / 2)
	local c = GetQuestDifficultyColor and GetQuestDifficultyColor(mid)
	local text = name
	if lo then text = ("%s  |cffb0b0b0%d-%d|r"):format(name, lo, hi or lo) end
	if c then return { text, c.r, c.g, c.b, 11 } end
	return { text, 1, 1, 1, 11 }
end

local instNames = {}                  -- instance mapID -> its name (Places.lua)
local instInfo = {}                   -- ... -> { name, raid, lo, hi }
-- (two parts of one instance (Lower and Upper Blackrock Spire): the instance, by the words their names
-- end with alike ("Blackrock Spire"), its levels both theirs)
local function Shared(a, b)
	local wa, wb = {}, {}
	for w in a:gmatch("%S+") do wa[#wa + 1] = w end
	for w in b:gmatch("%S+") do wb[#wb + 1] = w end
	local out = {}
	while #wa > 0 and #wb > 0 and wa[#wa] == wb[#wb] do
		table.insert(out, 1, wa[#wa])
		wa[#wa], wb[#wb] = nil, nil
	end
	return #out > 0 and table.concat(out, " ") or a
end
local function ReadInstances()
	if next(instInfo) then return end
	for _, e in ipairs(FM.PLACES and FM.PLACES.instances or {}) do
		for _, inst in ipairs(e[4] or {}) do
			local id = inst[1]
			if id and id ~= 0 then
				local had = instInfo[id]
				if had and had.name ~= inst[2] then
					had.name = Shared(had.name, inst[2])
					had.lo = math.min(had.lo or inst[4] or 0, inst[4] or had.lo or 0)
					had.hi = math.max(had.hi or inst[5] or 0, inst[5] or had.hi or 0)
				elseif not had then
					instInfo[id] = { name = inst[2], raid = inst[3], lo = inst[4], hi = inst[5] }
				end
				instNames[id] = instInfo[id].name
			end
		end
	end
end
function P.InstanceName(id)
	ReadInstances()
	return instNames[id]
end

-- AzerothVeil: a dungeon's name as shown, in the player's language: a wing's (the game has no name of its
-- own for one: translated here), else the game's name of the instance (GetRealZoneText, as DungeonJournal
-- gets it), else the data's. The data's name stays the key everywhere else (floors, DungeonJournal).
local WING_LABELS = {
	["Scarlet Monastery - Graveyard"] = L["Scarlet Monastery - Graveyard"],
	["Scarlet Monastery - Library"] = L["Scarlet Monastery - Library"],
	["Scarlet Monastery - Armory"] = L["Scarlet Monastery - Armory"],
	["Scarlet Monastery - Cathedral"] = L["Scarlet Monastery - Cathedral"],
	["Dire Maul - East"] = L["Dire Maul - East"],
	["Dire Maul - West"] = L["Dire Maul - West"],
	["Dire Maul - North"] = L["Dire Maul - North"],
	["Lower Blackrock Spire"] = L["Lower Blackrock Spire"],
	["Upper Blackrock Spire"] = L["Upper Blackrock Spire"],
}
function P.DisplayName(id, dataName)
	if dataName and WING_LABELS[dataName] then return WING_LABELS[dataName] end
	local n = id and GetRealZoneText and FM.Plain(GetRealZoneText(id))
	if type(n) == "string" and n ~= "" then return n end
	return dataName or (id and P.InstanceName(id)) or ""
end
function P.InstanceInfo(id)
	ReadInstances()
	return instInfo[id]
end
P.DUNGEON_ICON, P.RAID_ICON = DUNGEON_ICON, RAID_ICON

-- where the way into the dungeon or raid of this name is (its icon on the map): u, v. Names match
-- loosely ("The Deadmines" / "Deadmines", "Scarlet Monastery Library" / "Scarlet Monastery")
local function Simple(s)
	s = s:lower():gsub("^the ", "")
	s = s:gsub("[^%w]", "")
	return s
end

-- the world's zones and continents, by Simple name (read once from the game's maps)
local zoneNames
local function ZoneNames()
	if zoneNames then return zoneNames end
	zoneNames = {}
	local T = Enum and Enum.UIMapType
	for _, info in ipairs(C_Map.GetMapChildrenInfo and C_Map.GetMapChildrenInfo(947, nil, true) or {}) do
		if info.name and (not T or info.mapType == T.Zone or info.mapType == T.Continent) then
			zoneNames[Simple(info.name)] = true
		end
	end
	return zoneNames
end
-- where the way into this instance (its mapID) is: u, v (its dungeon / raid icon)
function P.InstanceUnits(id)
	for _, e in ipairs(FM.PLACES and FM.PLACES.instances or {}) do
		for _, inst in ipairs(e[4] or {}) do
			if inst[1] == id then
				if e[1] then return Geo.WorldToUnits(e[1], e[2], e[3]) end
				if e.map then return Geo.MapToUnits(e.map, e[2], e[3]) end
			end
		end
	end
end

function P.InstanceSpot(name)
	if type(name) ~= "string" or name == "" then return nil end
	local want = Simple(name)
	if want == "" then return nil end
	local zone = ZoneNames()[want]
	local bestU, bestV, bestLen
	for _, e in ipairs(FM.PLACES and FM.PLACES.instances or {}) do
		for _, inst in ipairs(e[4] or {}) do
			local have = inst[2] and Simple(inst[2])
			-- (the same name, or one starting with the other; or, a name no zone of the world has, one holding
			-- the other whole: "Blackrock Spire", the quest log's heading, is Lower and Upper Blackrock Spire's
			-- way in, while "Wetlands" stays the zone, not "Excavation Site: Wetlands". The longest such wins)
			local starts = have and (want:sub(1, #have) == have or have:sub(1, #want) == want)
			local holds = have and not zone and #have >= 6 and #want >= 6
				and (have:find(want, 1, true) or want:find(have, 1, true))
			if have and have ~= "" and (have == want or starts or holds)
				and (not bestLen or #have > bestLen) then
				local u, v
				if e[1] then u, v = Geo.WorldToUnits(e[1], e[2], e[3])
				elseif e.map then u, v = Geo.MapToUnits(e.map, e[2], e[3]) end
				if u then bestU, bestV, bestLen = u, v, #have end
			end
		end
	end
	return bestU, bestV
end

-- where the icon of the dock at (cont, x, y) stands. AzerothVeil: every way has its own icon, as OpenMap
-- shows them (PerfectMap made a tower's platforms and a harbour's piers one icon): with route, that way's
-- own dock nearest (cont, x, y); without, the nearest dock of that kind. (Routes.lua ends its lines there)
function P.DockUnits(kind, cont, x, y, route)
	local near = DOCK_YARDS[kind] or 60
	local best, bestD
	for _, t in ipairs(FM.PLACES and FM.PLACES.transports or {}) do
		if t[1] == kind and t[3] == cont and (not route or t[2] == route) then
			local d = (t[4] - x) ^ 2 + (t[5] - y) ^ 2
			if d < near * near and (not bestD or d < bestD) then best, bestD = t, d end
		end
	end
	if route and not best then return P.DockUnits(kind, cont, x, y) end
	if best then return Geo.WorldToUnits(cont, best[4], best[5]) end
end

local function BuildPlaces()
	local data = FM.PLACES
	if not data then return end
	local dungeon, raid = byKey.dungeon, byKey.raid
	local KIND_CAT = { boat = byKey.boat, zeppelin = byKey.zeppelin, airship = byKey.airship }
	for _, c in ipairs({ dungeon, raid, byKey.boat, byKey.zeppelin, byKey.airship, byKey.tram }) do if c.pins then ClearCat(c) end c.built = true end
	for _, e in ipairs(data.instances or {}) do
		local u, v
		if e[1] then u, v = Geo.WorldToUnits(e[1], e[2], e[3])
		elseif e.map then u, v = Geo.MapToUnits(e.map, e[2], e[3]) end
		if u then
			local list, allRaid = e[4], true
			local lines = {}
			for _, inst in ipairs(list) do
				if not inst[3] then allRaid = false end
				lines[#lines + 1] = LevelLine(P.DisplayName(inst[1], inst[2]), inst[4], inst[5])
			end
			local title
			if #list == 1 then
				title = P.DisplayName(list[1][1], list[1][2])
				lines[1] = LevelLine(list[1][3] and L["Raid"] or L["Dungeon"], list[1][4], list[1][5])
			else
				title = allRaid and L["Raids"] or L["Dungeons"]
			end
			-- (its instances, and each one the entrance leads to as it's named: two parts of one instance,
			-- Lower and Upper Blackrock Spire, are two)
			local insts, wings = {}, {}
			for i, inst in ipairs(list) do
				insts[i] = inst[1]
				wings[i] = { id = inst[1], name = inst[2], label = P.DisplayName(inst[1], inst[2]), raid = inst[3], lo = inst[4], hi = inst[5] }
			end
			AddPin(allRaid and raid or dungeon, u, v, { title = title, lines = lines, insts = insts, wings = wings })
		end
	end
	-- AzerothVeil: one icon for each way, where it leaves from, as OpenMap shows them (PerfectMap made a
	-- tower's platforms and a harbour's piers one icon naming every place they go to): Tanaris' tower, a
	-- zeppelin to Orgrimmar and one to Stranglethorn, is two icons. Each knows its way's other end.
	for _, t in ipairs(data.transports or {}) do
		local kind, route, cont, x, y, toCont, toX, toY = t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8]
		local u, v
		-- (only the boats you can take)
		if P.Usable(kind, route) then u, v = Geo.WorldToUnits(cont, x, y) end
		if u then
			local dest
			local du, dv = Geo.WorldToUnits(toCont, toX, toY)
			if du then dest = select(2, Geo.ZoneAt(du, dv)) end
			-- (to a land off the world map, Zephras Isle: a click on its dock on the world opens its map)
			local away = Geo.AwayOfInstance(toCont)
			if away and Geo.AwayOfInstance(cont) then away = nil end
			-- (the other end: that way's dock there)
			local tu, tv
			if du then tu, tv = P.DockUnits(kind, toCont, toX, toY, route) end
			if not tu then tu, tv = du, dv end
			local own = P.OwnFaction(kind, route)
			local faction = P.TransportFaction(kind, route)
			local name = TRANSPORT_NAME[kind] or L["Transport"]
			local lines = { { route, 0.7, 0.7, 0.72, 11 } }
			if not own then lines[2] = { L["The other faction's"], 1, 0.45, 0.4, 11 } end
			AddPin(KIND_CAT[kind] or byKey.boat, u, v, {
				title = dest and L["%s to %s"]:format(name, dest) or name, lines = lines,
				icon = kind == "boat" and P.FactionArt("harbor", faction) or TRANSPORT_ICON[kind],
				-- (MapUtils' dark outline: airships, harbors, trams; round our painted harbors, lighter. AzerothVeil:
				-- none round the zeppelins, OpenMap's icon drawn as it is)
				outline = kind == "boat" and P.PAINTED_OUTLINE or kind == "airship" or nil,
				away = away,
				dock = { kind = kind, cont = cont, x = x, y = y, near = DOCK_YARDS[kind] or 60, routes = { route } },
				travel = { { dest = dest, route = route, own = own, u = tu, v = tv } },
			})
		end
	end
	-- the Deeprun Tram's two stations (MapUtils' piers; Stormwind's at its WoW Forever spot)
	for i, t in ipairs(TRAMS) do
		local u, v = Geo.MapToUnits(t[1], t[2], t[3])
		-- (AzerothVeil: the other station, for the Transports module's click)
		local o = TRAMS[i == 1 and 2 or 1]
		local ou, ov = Geo.MapToUnits(o[1], o[2], o[3])
		-- (the city's name as the game gives it, in the player's language)
		local info = C_Map.GetMapInfo(o[1])
		local toName = info and info.name or t[4]
		if u then
			AddPin(byKey.tram, u, v, { title = L["Tram to %s"]:format(toName), lines = { { L["Deeprun Tram"], 0.7, 0.7, 0.72, 11 } }, icon = TRAM_ICON, outline = true,
				travel = ou and { { dest = toName, u = ou, v = ov, own = true } } or nil })
		end
	end
end

-- AzerothVeil: the townsfolk only where you've explored (the Map module's "Townsfolk of unexplored areas"
-- off: FM.db.npcUnexplored false), as OpenMap's "Only places you've found" (Map/Stitch.lua, MIT): the game's
-- explored areas at the spot or a little round it (C_MapExplorationInfo.GetExploredAreaIDsAtPosition). In a
-- capital (its own map has nothing to explore): found once you've been in it, or explored the zone's land
-- under it. Only in the zones the game has explored areas for (the fog's, FM.FOG_ZONES); anywhere else shown.
-- Each spot asked once: found stays found; not found is asked again once the player has explored more.
local CITY_ZONE = { [1453] = 1429, [1454] = 1411, [1455] = 1426, [1456] = 1412, [1457] = 1438, [1458] = 1420 }
local AROUND = { { 0, 0 }, { 0.015, 0 }, { -0.015, 0 }, { 0, 0.015 }, { 0, -0.015 } }
local foundAt = {}                    -- spot (or capital) -> found
local exploring                       -- the zones with explored areas, as a set
local vec
local function ExploredAt(map, x, y, around)
	local at = C_MapExplorationInfo and C_MapExplorationInfo.GetExploredAreaIDsAtPosition
	if not (at and CreateVector2D) then return true end      -- (not on this client: every one shown)
	vec = vec or CreateVector2D(0, 0)
	for i = 1, around and #AROUND or 1 do
		vec:SetXY(x + AROUND[i][1], y + AROUND[i][2])
		local ok, areas = pcall(at, map, vec)
		areas = ok and FM.Plain(areas)
		if type(areas) == "table" and #areas > 0 then return true end
	end
	return false
end
local function CityFound(city)
	local f = foundAt[city]
	if f ~= nil then return f end
	f = ExploredAt(city, 0.5, 0.5) or FM.Plain(C_Map.GetBestMapForUnit("player")) == city
	local zone, r = CITY_ZONE[city], Geo.Rect(city)
	if not f and r then
		local x, y = Geo.UnitsToMap(zone, (r[1] + r[2]) / 2, (r[3] + r[4]) / 2)
		f = x and ExploredAt(zone, x, y, true) or false
	end
	foundAt[city] = f
	return f
end
-- map, x, y: the townsfolk's own spot in its data (x, y in 1/10000ths of its map)
local function Found(map, x, y)
	if CITY_ZONE[map] then return CityFound(map) end
	if not exploring then
		exploring = {}
		for _, id in ipairs(FM.FOG_ZONES or {}) do exploring[id] = true end
	end
	if not exploring[map] then return true end
	local key = map * 1e9 + x * 10001 + y          -- (x, y up to 10000: one number per spot)
	local f = foundAt[key]
	if f == nil then
		f = ExploredAt(map, x / 10000, y / 10000, true)
		foundAt[key] = f
	end
	return f
end

-- the built-in townsfolk (Data\Townsfolk.lua): read into tables only while building, then let go
-- AzerothVeil: what a townsfolk's icon says it is, hovered (the Icons module's "Townsfolk's names" off): its kind, a
-- trainer by its class or profession (the data's tag), in the player's language (Locales)
local TRAINER = {
	WARRIOR = L["Warrior trainer"], PALADIN = L["Paladin trainer"], HUNTER = L["Hunter trainer"], ROGUE = L["Rogue trainer"],
	PRIEST = L["Priest trainer"], SHAMAN = L["Shaman trainer"], MAGE = L["Mage trainer"], WARLOCK = L["Warlock trainer"],
	DRUID = L["Druid trainer"], ALCHEMY = L["Alchemy trainer"], BLACKSMITHING = L["Blacksmithing trainer"],
	COOKING = L["Cooking trainer"], ENCHANTING = L["Enchanting trainer"], ENGINEERING = L["Engineering trainer"],
	FIRST_AID = L["First Aid trainer"], FISHING = L["Fishing trainer"], HERBALISM = L["Herbalism trainer"],
	LEATHERWORKING = L["Leatherworking trainer"], MINING = L["Mining trainer"], RIDING = L["Riding trainer"],
	SKINNING = L["Skinning trainer"], TAILORING = L["Tailoring trainer"],
}

local function BuildTownsfolk(todo)
	if not FM.LoadTownsfolk then return end
	local data, strings, tags = FM.LoadTownsfolk()
	local mine = UnitFactionGroup("player") == "Horde" and 2 or 1
	local _, myClass = UnitClass("player")
	local foundOnly = FM.db.npcUnexplored == false      -- (AzerothVeil: the Map module's switch)
	for _, cat in ipairs(todo) do
		local list = data[cat.data == true and cat.key or cat.data] or {}
		cat.pins, cat.grid = cat.pins or {}, cat.grid or {}
		for i = 1, #list, 7 do
			local map, x, y, name, sub, fac, tag = list[i], list[i + 1], list[i + 2], list[i + 3], list[i + 4], list[i + 5], list[i + 6]
			local ok = fac == 3 or fac == mine or (cat.anyFaction and fac == 0)
			if ok and cat.myClass and not (cat.everyClass and FM.db[cat.everyClass]) then ok = tags[tag] == myClass end
			if ok and cat.tag then ok = tags[tag] == cat.tag end
			if ok and foundOnly then ok = Found(map, x, y) end
			if ok then
				local move = NPC_MOVE[map] and NPC_MOVE[map][strings[name]]
				if move then x, y = x + move[1], y + move[2] end
				local u, v = Geo.MapToUnits(map, x / 10000, y / 10000)
				if u then
					local s = strings[sub]
					AddPin(cat, u, v, {
						title = strings[name] or cat.label,
						lines = s and { { "<" .. s .. ">", 0.8, 0.8, 0.8, 11 } } or nil,
						kind = (cat.key ~= "portalTrainer" and TRAINER[tags[tag]]) or cat.label,   -- (AzerothVeil)
						class = cat.key == "classTrainer" and CLASSES[tags[tag]] and tags[tag] or nil,
					})
				end
			end
		end
		cat.built = true
	end
end

-- build what's turned on and not built yet
function P.Ensure()
	local pins = FM.db.pins
	if pins.flight and not byKey.flight.built then BuildFlights() end
	if pins.capital and not byKey.capital.built then BuildCapitals() end
	if pins.exit and not byKey.exit.built then BuildExits() end
	if (pins.dungeon or pins.raid or pins.boat or pins.zeppelin or pins.airship or pins.tram) and not byKey.dungeon.built then BuildPlaces() end
	local todo
	for _, cat in ipairs(CATS) do
		if cat.data and pins[cat.key] and not cat.built then
			todo = todo or {}
			todo[#todo + 1] = cat
		end
	end
	if todo then BuildTownsfolk(todo) end
	WarmAll()
	FM.Map.MarkDirty()
end

-- AzerothVeil: the n icons of a kind nearest to u, v on its continent (the map's search, Find.lua), nearest first:
-- { pin, ... } (each pin.u, pin.v, pin.title). The kind is built if it isn't yet, even hidden (it then shows only
-- once turned on: Layout shows what's on)
function P.Nearest(key, u, v, n)
	local cat = byKey[key]
	if not cat or not u then return {} end
	if not cat.built then
		if cat.data then BuildTownsfolk({ cat })
		elseif key == "flight" then BuildFlights()
		elseif key == "exit" then BuildExits()
		elseif key == "capital" then BuildCapitals()
		else BuildPlaces() end
		WarmAll()
	end
	local cont = Geo.ContinentAt(u, v)
	local list = {}
	for _, pin in ipairs(cat.pins or {}) do
		if not cont or Geo.ContinentAt(pin.u, pin.v) == cont then
			local du, dv = pin.u - u, pin.v - v
			list[#list + 1] = { pin = pin, d = du * du + dv * dv }
		end
	end
	table.sort(list, function(a, b) return a.d < b.d end)
	local out = {}
	for i = 1, math.min(n or 3, #list) do out[i] = list[i].pin end
	return out
end

function P.SetShown(key, on)
	FM.db.pins[key] = on and true or false
	P.Ensure()
	if FM.Quests then FM.Quests.OnToggle() end
	FM.Map.MarkDirty()
end

-- (the other faction's harbors turned on or off)
function P.RebuildPlaces()
	byKey.dungeon.built = nil
	P.Ensure()
	if FM.Routes then FM.Routes.Rebuild() end
end

-- (AzerothVeil: the same, built only when the map next opens: nothing done while it's closed)
function P.InvalidatePlaces()
	byKey.dungeon.built = nil
	if FM.Routes then FM.Routes.Rebuild() end
end

-- (AzerothVeil: the same for the flight masters, built when the map next opens)
function P.InvalidateFlights()
	byKey.flight.built = nil
end

-- AzerothVeil: the townsfolk built again (with the map open; else when it next opens): the Map module's
-- "Townsfolk of unexplored areas" switched, or more of the world explored while it hides them. What wasn't
-- found is asked again; what was stays found
function P.RefreshExplored()
	for k, f in pairs(foundAt) do if not f then foundAt[k] = nil end end
	for _, cat in ipairs(CATS) do
		if cat.data and cat.built then ClearCat(cat) end
	end
	if FM.Map.IsShown() then P.Ensure() end
end

-- AzerothVeil: one kind of townsfolk built again (now with the map open, else when it opens): who it lists changed
function P.RebuildKind(key)
	local cat = byKey[key]
	if cat and cat.built then ClearCat(cat) end
	if FM.Map.IsShown() then P.Ensure() end
end

function P.RebuildFlights()
	byKey.flight.built = nil
	if FM.db.pins.flight then BuildFlights() end
	FM.Map.MarkDirty()
end

function P.OnShow()
	pass = pass + 1          -- (no glides out of where groups were the last time it was open)
	snapNext = true
	if P.BeforeOpen then P.BeforeOpen() end   -- (AzerothVeil: the Icons module's: your professions read again)
	P.Ensure()
end

function P.OnHide()
end

function P.StatsText()
	return ("%d on screen / %d"):format(nShown, total)
end

function P.Init(pins, top)
	pinLayer, topLayer = pins, top
	waypointTex = topLayer:CreateTexture(nil, "OVERLAY", nil, 5)
	waypointTex:SetSize(26, 26)
	waypointTex:Hide()
	local ev = CreateFrame("Frame")
	ev:RegisterEvent("USER_WAYPOINT_UPDATED")
	ev:RegisterEvent("TAXIMAP_OPENED")
	ev:RegisterEvent("MODIFIER_STATE_CHANGED")
	ev:SetScript("OnEvent", function(_, event, key)
		if event == "MODIFIER_STATE_CHANGED" then
			-- (Shift held or let go over Questie's icons: its tooltip again, with or without what Shift adds.
			-- Questie redraws it itself only over Blizzard's map)
			if questieTip and nHovered > 0 and (key == "LSHIFT" or key == "RSHIFT") then
				EndQuestieTip()
				QuestieTip(nHovered)
			end
		elseif event == "USER_WAYPOINT_UPDATED" then ReadWaypoint()
		elseif event == "TAXIMAP_OPENED" then byKey.flight.built = nil end
	end)
	ReadWaypoint()
end
