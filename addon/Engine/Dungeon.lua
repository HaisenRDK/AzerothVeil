-- A dungeon's or raid's own map in the window, over the world: Blizzard's art of each floor, which WoW
-- Forever's client has but no map for (Data\DungeonMaps.lua, OpenMap's list: 4 x 3 tiles of 256, the
-- picture 1002 x 668), and for a place the game does map (a battleground) its own art with you and
-- your group on it. Opened by itself inside an instance (on the floor named as the part you're in),
-- or with a left-click on a dungeon's icon; floors (and, at an entrance to several, the dungeons) as
-- buttons along its top. Back to the world: the header's World button, or a right-click on it.
-- Nothing runs while it's closed.
local _, FM = ...
local D = {}
FM.Dungeon = D
local S = FM.Style
local floor, min, max = math.floor, math.min, math.max
local Plain = FM.Plain

local PIC_W, PIC_H, TILE = 1002, 668, 256
local layer, noMap, title, credit
local gameArt, mapForeground
local tiles = {}
local unitPins, playerPins, unitsMapID
local unitLayers = {}
local geo = { x = 0, y = 0, w = 1, h = 1 }
-- what it shows: { insts = { instance mapIDs }, inst = the one shown, floor = its floor (data maps), or
-- uiMap = a map the game has (with positions on it) }; opened = from an icon (not where you are)
local view, opened = nil, false
local peek = false                -- inside, but looking at the world (the header's button)
local lastSub                     -- the part of the dungeon you were last seen in

-- a dungeon's floors: Santiago Reyes's drawing of it (Forever's own dungeons: Data/DungeonDrawn.lua),
-- else Blizzard's art; with the floors the DungeonJournal's maps add (Data/DungeonJournal.lua: Upper
-- Blackrock Spire, Alcaz Prison's second floor)
local floorsOf = {}
local function FloorsOf(inst)
	if not inst then return nil end
	local list = floorsOf[inst]
	if list == nil then
		local base = (FM.DUNGEON_DRAWN and FM.DUNGEON_DRAWN[inst]) or (FM.DUNGEON_MAPS and FM.DUNGEON_MAPS[inst])
		local extra = FM.DUNGEON_JOURNAL_FLOORS and FM.DUNGEON_JOURNAL_FLOORS[inst]
		if extra then
			list = {}
			for i, f in ipairs(base or {}) do list[i] = f end
			for i, f in pairs(extra) do list[i] = f end
		else
			list = base or false
		end
		floorsOf[inst] = list
	end
	return list or nil
end

-- the floor of an instance named as one of its parts is (Upper Blackrock Spire's own), else nil
local function FloorNamed(inst, name)
	for i, f in ipairs(FloorsOf(inst) or {}) do
		if name and f.name == name then return i end
	end
end

-- (MapUtils keeps Forever's newer dungeons under numbers of its own)
local MU_ID = { [2970] = 900001, [3039] = 900002, [2994] = 900003, [3001] = 900005 }
local function MUFloors(inst)
	return FM.DUNGEON_FLOORS and FM.DUNGEON_FLOORS[MU_ID[inst] or inst]
end

local function InstanceID()
	if not Plain(IsInInstance()) then return nil end
	return Plain(select(8, GetInstanceInfo()))
end

-- a battleground's map (an orphan map of the game's, its own art): never a place on the world, even one the
-- game also sets on its continent (Darkspear Islands, off Kalimdor)
local ORPHAN = Enum and Enum.UIMapType and Enum.UIMapType.Orphan or 6
function D.IsBattlegroundMap(m)
	local info = m and m ~= 0 and C_Map.GetMapInfo(m)
	return info and info.mapType == ORPHAN or false
end

-- inside: what to show there (its floors from the list; else a map the game has of it), or nil
local function Here()
	local id = InstanceID()
	if not id then return nil end
	if FloorsOf(id) then return { insts = { id }, inst = id } end
	local m = Plain(C_Map.GetBestMapForUnit("player"))
	if m and m ~= 0 and (not FM.Geo.Rect(m) or D.IsBattlegroundMap(m)) then return { uiMap = m } end
end

function D.Inside() return Here() ~= nil end
function D.Active() return layer ~= nil and layer:IsShown() end

-- the floor named as the part of the dungeon you're in (else the one shown, else the first)
local function FloorHere(floors, keep)
	local sub = Plain(GetSubZoneText and GetSubZoneText())
	if type(sub) == "string" and sub ~= "" then
		for i, f in ipairs(floors) do if f.name == sub then return i end end
	end
	return keep or 1
end

local function ClearTiles()
	for _, t in ipairs(tiles) do t:Hide() end
end

local function Tile(i)
	local t = tiles[i]
	if not t then
		t = layer:CreateTexture(nil, "ARTWORK")
		if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) t:SetTexelSnappingBias(0) end
		tiles[i] = t
	end
	return t
end

-- the picture (w x h in its own pixels) fitted to the window, in the middle
local function Fit(w, h)
	local vw, vh = layer:GetSize()
	local s = min(vw / w, vh / h)
	geo.w, geo.h = w * s, h * s
	geo.x, geo.y = (vw - geo.w) / 2, (vh - geo.h) / 2
	return s
end

---------------------------------------------------------------------------
-- The floors: a list down the map's left (the one shown lit, its number by it), the wheel over the
-- map going up and down them. At an entrance to several dungeons, a button above it names the one
-- shown and drops a list of them all, as a left-click on the entrance's icon does (D.Choose)
---------------------------------------------------------------------------
local Draw
local FLOOR_W, ROW_H = 200, 20
local floorPanel, floorHead
local floorRows = {}
local instButton, chooser
local chooserRows = {}

function D.SetFloor(i)
	if not view or not view.inst then return end
	local floors = FloorsOf(view.inst)
	if not floors or not floors[i] or i == view.floor then return end
	view.floor, view.picked = i, true
	Draw()
end

local function Floors(names, current)
	if not floorPanel then
		floorPanel = CreateFrame("Frame", nil, layer)
		floorPanel:SetFrameLevel(layer:GetFrameLevel() + 20)
		floorPanel:EnableMouse(true)
		S.Panel(floorPanel, { 0.05, 0.055, 0.06, 0.9 })
		floorHead = S.Text(floorPanel, 11, S.ACCENT)
		floorHead:SetPoint("TOPLEFT", 10, -8)
	end
	for _, r in ipairs(floorRows) do r:Hide() end
	if not names or #names < 2 then floorPanel:Hide() return end
	floorHead:SetText(("FLOORS  |cff9a9a9a%d / %d|r"):format(current, #names))
	local y = -26
	for i, name in ipairs(names) do
		local r = floorRows[i]
		if not r then
			r = S.Button(floorPanel, "", FLOOR_W - 12, ROW_H, function(self) D.SetFloor(self.index) end, "row")
			r.label:ClearAllPoints()
			r.label:SetPoint("LEFT", 8, 0)
			r.label:SetPoint("RIGHT", -6, 0)
			r.label:SetJustifyH("LEFT")
			r.label:SetWordWrap(false)
			floorRows[i] = r
		end
		r.index = i
		r.label:SetText(("%d   %s"):format(i, name))
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", 6, y)
		r:SetActive(i == current)
		r:Show()
		y = y - ROW_H - 2
	end
	floorPanel:SetSize(FLOOR_W, -y + 6)
	floorPanel:ClearAllPoints()
	floorPanel:SetPoint("TOPLEFT", layer, "TOPLEFT", 8, (instButton and instButton:IsShown()) and -38 or -8)
	floorPanel:Show()
end

-- the list of an entrance's dungeons, under anchor (else at the cursor): a click opens that one's map
function D.HideChooser()
	if chooser then chooser:Hide() end
end

function D.Choose(insts, anchor, name)
	if not insts or #insts == 0 then return end
	local parent = _G.PerfectMapFrame
	if not chooser then
		chooser = CreateFrame("Frame", nil, parent)
		chooser:SetFrameStrata("DIALOG")
		chooser:EnableMouse(true)
		chooser:SetClampedToScreen(true)
		S.Panel(chooser, { 0.05, 0.055, 0.06, 0.96 })
		chooser.head = S.Text(chooser, 11, S.ACCENT)
		chooser.head:SetPoint("TOPLEFT", 10, -8)
		chooser.head:SetText("CHOOSE A DUNGEON")
	end
	for _, r in ipairs(chooserRows) do r:Hide() end
	-- (each entry: an instance, or one part of one as the entrance names it: { id, name, raid, lo, hi })
	local ids = {}
	for i, e in ipairs(insts) do ids[i] = type(e) == "table" and e.id or e end
	local y, w = -26, 260
	for i, e in ipairs(insts) do
		local id = ids[i]
		local info = type(e) == "table" and e or (FM.Pins.InstanceInfo and FM.Pins.InstanceInfo(id)) or {}
		local r = chooserRows[i]
		if not r then
			r = S.Button(chooser, "", w - 12, 24, function(self)
				D.HideChooser()
				D.Open(self.insts, self.name, self.id, self.floor)
			end, "row")
			r.icon = r:CreateTexture(nil, "ARTWORK")
			r.icon:SetSize(16, 16)
			r.icon:SetPoint("LEFT", 6, 0)
			r.label:ClearAllPoints()
			r.label:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
			r.label:SetPoint("RIGHT", -52, 0)
			r.label:SetJustifyH("LEFT")
			r.label:SetWordWrap(false)
			r.levels = S.Text(r, 10)
			r.levels:SetPoint("RIGHT", -8, 0)
			chooserRows[i] = r
		end
		r.insts, r.id, r.name = insts, id, info.name or name
		r.floor = type(e) == "table" and FloorNamed(id, e.name) or nil
		S.SetIcon(r.icon, info.raid and FM.Pins.RAID_ICON or FM.Pins.DUNGEON_ICON)
		r.label:SetText(info.name or tostring(id))
		local hasMap = FloorsOf(id)
		r.label:SetAlpha(hasMap and 1 or 0.55)
		if info.lo then
			local c = GetQuestDifficultyColor and GetQuestDifficultyColor(floor((info.lo + (info.hi or info.lo)) / 2))
			r.levels:SetText(info.lo == info.hi and tostring(info.lo) or (info.lo .. "-" .. (info.hi or info.lo)))
			if c then r.levels:SetTextColor(c.r, c.g, c.b) end
		else
			r.levels:SetText("")
		end
		r:SetActive(view ~= nil and view.inst == id and layer:IsShown())
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", 6, y)
		r:Show()
		y = y - 26
	end
	chooser:SetSize(w, -y + 6)
	chooser:ClearAllPoints()
	if anchor then
		chooser:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
	else
		local x, cy = GetCursorPosition()
		local es = UIParent:GetEffectiveScale()
		chooser:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / es + 10, cy / es - 6)
	end
	chooser:Show()
end

local function InstanceButton()
	if not instButton then
		instButton = S.Button(layer, "", 230, 24, function(self) D.Choose(view and (view.choices or view.insts), self) end, "icon")
		instButton:SetFrameLevel(layer:GetFrameLevel() + 20)
		instButton:SetPoint("TOPLEFT", layer, "TOPLEFT", 8, -8)
		instButton.label:ClearAllPoints()
		instButton.label:SetPoint("LEFT", 10, 0)
		instButton.label:SetPoint("RIGHT", -24, 0)
		instButton.label:SetJustifyH("LEFT")
		local arrow = instButton:CreateTexture(nil, "ARTWORK")
		arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
		arrow:SetSize(14, 14)
		arrow:SetPoint("RIGHT", -6, -2)
		instButton.tip = { "Dungeons here", "This entrance leads to more than one: pick another." }
	end
	if view and view.insts and #view.insts > 1 then
		local info = FM.Pins.InstanceInfo and FM.Pins.InstanceInfo(view.inst) or {}
		instButton.label:SetText(info.name or view.name or "")
		instButton:Show()
	else
		instButton:Hide()
	end
end

---------------------------------------------------------------------------
-- Bosses, as MapUtils pins them (Data/DungeonBosses.lua, from its InstancePins): each one's portrait
-- in a ring, a dragon round an elite's; its level in its tooltip
---------------------------------------------------------------------------
local BOSS_SIZE, BOSS_SCALE = 34, 0.62 * 1.44      -- (MapUtils', a fifth bigger twice)
local RING = "Interface\\Minimap\\MiniMap-TrackingBorder"
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local FALLBACK = "Interface\\Icons\\INV_Misc_QuestionMark"
local DRAGONS = "Interface\\AddOns\\PerfectMap\\Media\\"   -- (MapUtils' dragons without their level ring: tools/dragons.js)
local STYLES = {
	[0] = { ring = { 0.55, 0.5, 0.4 } },
	[1] = { ring = { 0.95, 0.75, 0.25 }, dragon = "dragon_elite" },
	[2] = { ring = { 0.85, 0.87, 0.95 }, dragon = "dragon_rare-elite" },
	[3] = { ring = { 0.95, 0.75, 0.25 }, dragon = "dragon_elite" },
	[4] = { ring = { 0.85, 0.87, 0.95 }, dragon = "dragon_rare" },
}
local bossPins = {}

local function Masked(owner, tex)
	if not owner.CreateMaskTexture or not tex.AddMaskTexture then return end
	local m = owner:CreateMaskTexture()
	m:SetAllPoints(tex)
	m:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	tex:AddMaskTexture(m)
end

local function BossEnter(self)
	local b = self.boss
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(b[1], 1, 0.82, 0)
	if b[2] then
		local c = GetQuestDifficultyColor and GetQuestDifficultyColor(b[2])
		GameTooltip:AddLine((LEVEL or "Level") .. " " .. (b[5] or b[2]), c and c.r or 1, c and c.g or 1, c and c.b or 1)
	elseif b[4] == 3 then
		GameTooltip:AddLine("Boss", 1, 0.3, 0.3)
	end
	GameTooltip:Show()
end

local function NewBossPin()
	local p = CreateFrame("Frame", nil, layer)
	p:SetSize(BOSS_SIZE, BOSS_SIZE)
	p:SetScale(BOSS_SCALE)
	p:EnableMouse(true)
	FM.Style.PassClicks(p)
	p:SetScript("OnEnter", BossEnter)
	p:SetScript("OnLeave", GameTooltip_Hide)
	p.portrait = p:CreateTexture(nil, "ARTWORK")
	p.portrait:SetPoint("TOPLEFT", 2, -2)
	p.portrait:SetPoint("BOTTOMRIGHT", -2, 2)
	Masked(p, p.portrait)
	p.ring = p:CreateTexture(nil, "OVERLAY", nil, 1)
	p.ring:SetTexture(RING)
	p.ring:SetTexCoord(0, 0.6, 0, 0.6)
	p.ring:SetSize((BOSS_SIZE - 4) * 1.55, (BOSS_SIZE - 4) * 1.55)
	p.ring:SetPoint("CENTER", p.portrait, "CENTER")
	local k = (BOSS_SIZE - 4) / 64
	p.dragon = p:CreateTexture(nil, "OVERLAY", nil, 2)
	p.dragon:SetSize(256 * k, 128 * k)
	p.dragon:SetPoint("CENTER", p, "CENTER", -54 * k, -20 * k)
	local bs = 16 * (BOSS_SIZE - 4) / 34
	p.badge = CreateFrame("Frame", nil, p)
	p.badge:SetSize(bs, bs)
	p.badge:SetPoint("CENTER", p, "CENTER", 19.5 * k, -22 * k)
	p.badgeRing = p.badge:CreateTexture(nil, "BORDER")
	p.badgeRing:SetAllPoints()
	p.badgeFill = p.badge:CreateTexture(nil, "ARTWORK")
	p.badgeFill:SetPoint("TOPLEFT", 1.5, -1.5)
	p.badgeFill:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
	p.badgeFill:SetColorTexture(0.05, 0.04, 0.03, 0.95)
	p.badgeText = p.badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	p.badgeText:SetPoint("CENTER", 0.5, 0)
	local font, _, flags = p.badgeText:GetFont()
	if font then p.badgeText:SetFont(font, 8, flags) end
	p.badgeSkull = p.badge:CreateTexture(nil, "OVERLAY")
	p.badgeSkull:SetSize(bs - 5, bs - 5)
	p.badgeSkull:SetPoint("CENTER")
	p.badgeSkull:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
	Masked(p.badge, p.badgeRing)
	Masked(p.badge, p.badgeFill)
	return p
end

local function StyleBoss(p, b)
	if not (b[3] and b[3] > 0 and SetPortraitTextureFromCreatureDisplayID and pcall(SetPortraitTextureFromCreatureDisplayID, p.portrait, b[3])) then
		p.portrait:SetTexture(FALLBACK)
	end
	local style = STYLES[b[4]] or STYLES[0]
	if style.dragon then p.dragon:SetTexture(DRAGONS .. style.dragon) p.dragon:Show() else p.dragon:Hide() end
	p.badge:Hide()                     -- (no level badge: its level is in the tooltip)
end

-- the MapUtils map a floor is: the one of the same name, else the one in its place
local function FloorKey(inst, index, name)
	-- (a drawn floor says which it is)
	local ours = FloorsOf(inst)
	local own = ours and ours[index]
	if own and own.tiles == nil and own.key then return own.key end
	if own and own.tiles and FM.DUNGEON_DRAWN and FM.DUNGEON_DRAWN[inst] then return nil end
	local f = MUFloors(inst)
	if not f or #f.floors == 0 then return nil end
	if #f.floors == 1 then return (index == 1 or #(ours or {}) == 1) and f.floors[1].key or nil end
	if name then
		for _, fl in ipairs(f.floors) do if fl.name == name then return fl.key end end
	end
	local count = ours and #ours or 0
	if count == #f.floors then return f.floors[index] and f.floors[index].key end
	-- (the first floor: MapUtils' first unnamed one)
	if index == 1 then
		for _, fl in ipairs(f.floors) do if not fl.name then return fl.key end end
	end
end

-- (a boss's name as the journal gives it: MapUtils' without its title, each of a pair "A / B")
local function Names(name)
	local out = {}
	name = (name or ""):gsub("%s*<[^>]*>", "")
	for part in (name .. " / "):gmatch("(.-)%s*/%s*") do
		if part ~= "" then out[#out + 1] = part:lower() end
	end
	return out
end

-- the journal's place for a boss MapUtils has none for: floor, x, y (OpenMap's Data/DungeonSpots.lua)
local function Spot(inst, boss)
	local spots = FM.DUNGEON_BOSS_SPOTS and FM.DUNGEON_BOSS_SPOTS[inst]
	if not spots then return nil end
	spots.lower = spots.lower or {}
	if not next(spots.lower) then
		for name, s in pairs(spots) do if type(s) == "table" and name ~= "lower" then spots.lower[name:lower()] = s end end
	end
	for _, n in ipairs(Names(boss[1])) do
		local s = spots.lower[n]
		if s then return s[1], s[2], s[3] end
	end
end

local entrancePins = {}
local listPanel, listRows = nil, {}

local function Entrance(i, x, y, raid)
	local e = entrancePins[i]
	if not e then
		e = CreateFrame("Frame", nil, layer)
		e:SetSize(26, 26)
		e:EnableMouse(true)
		FM.Style.PassClicks(e)
		e.tex = e:CreateTexture(nil, "ARTWORK")
		e.tex:SetAllPoints()
		e:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.raid and "Raid entrance" or "Dungeon entrance", 1, 0.82, 0)
			GameTooltip:Show()
		end)
		e:SetScript("OnLeave", GameTooltip_Hide)
		entrancePins[i] = e
	end
	e.raid = raid
	S.SetIcon(e.tex, raid and FM.Pins.RAID_ICON or FM.Pins.DUNGEON_ICON)
	e:SetFrameLevel(layer:GetFrameLevel() + 3)
	e:ClearAllPoints()
	e:SetPoint("CENTER", layer, "TOPLEFT", geo.x + x * geo.w, -(geo.y + y * geo.h))
	e:Show()
end

-- the bosses with no place on any map: listed down the map's right (their portraits and levels)
local function List(bosses)
	if not listPanel then
		listPanel = CreateFrame("Frame", nil, layer)
		listPanel:SetFrameLevel(layer:GetFrameLevel() + 20)
		listPanel:EnableMouse(true)
		S.Panel(listPanel, { 0.05, 0.055, 0.06, 0.9 })
		listPanel.head = S.Text(listPanel, 11, S.ACCENT)
		listPanel.head:SetPoint("TOPLEFT", 10, -8)
		listPanel.head:SetText("ALSO HERE")
	end
	for _, r in ipairs(listRows) do r:Hide() end
	if #bosses == 0 then listPanel:Hide() return end
	local y = -26
	for i, b in ipairs(bosses) do
		local r = listRows[i]
		if not r then
			r = CreateFrame("Frame", nil, listPanel)
			r:SetSize(196, 22)
			r.portrait = r:CreateTexture(nil, "ARTWORK")
			r.portrait:SetSize(18, 18)
			r.portrait:SetPoint("LEFT", 4, 0)
			Masked(r, r.portrait)
			r.name = S.Text(r, 11)
			r.name:SetPoint("LEFT", r.portrait, "RIGHT", 6, 0)
			r.name:SetPoint("RIGHT", -28, 0)
			r.name:SetJustifyH("LEFT")
			r.name:SetWordWrap(false)
			r.level = S.Text(r, 10)
			r.level:SetPoint("RIGHT", -4, 0)
			r:EnableMouse(true)
			r:SetScript("OnEnter", BossEnter)
			r:SetScript("OnLeave", GameTooltip_Hide)
			listRows[i] = r
		end
		r.boss = b
		if not (b[3] and b[3] > 0 and SetPortraitTextureFromCreatureDisplayID and pcall(SetPortraitTextureFromCreatureDisplayID, r.portrait, b[3])) then
			r.portrait:SetTexture(FALLBACK)
		end
		r.name:SetText((b[1] or ""):gsub("%s*<[^>]*>", ""))
		if b[2] then
			r.level:SetText(b[5] or b[2])
			local c = GetQuestDifficultyColor and GetQuestDifficultyColor(b[2])
			if c then r.level:SetTextColor(c.r, c.g, c.b) end
		else
			r.level:SetText(b[4] == 3 and "|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:12|t" or "")
		end
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", 4, y)
		r:Show()
		y = y - 22
	end
	listPanel:SetSize(204, -y + 6)
	listPanel:ClearAllPoints()
	listPanel:SetPoint("TOPRIGHT", layer, "TOPRIGHT", -8, -8)
	listPanel:Show()
end

-- MapUtils' boss of a name (its portrait, level and kind), for a boss another source places
local byName
local function BossNamed(name)
	if not byName then
		byName = {}
		for _, b in pairs(FM.DUNGEON_BOSSES or {}) do
			for _, n in ipairs(Names(b[1])) do byName[n] = byName[n] or b end
		end
	end
	for _, n in ipairs(Names(name)) do
		if byName[n] then return byName[n] end
	end
end

-- a floor's bosses and its way in, each from the surest source that has it: the DungeonJournal's
-- places (CMaNGOS spawns, checked in game), MapUtils' own, the game's journal (OpenMap's), and a list
-- for those none places
-- No two bosses drawn on top of each other. A main boss with lesser ones round it (a boss among its
-- elites, an elite among rares): the lesser ones drawn smaller, beside it. Then any still on top of
-- another are moved apart, as little as it takes, the smaller moving more; off the way in too (that
-- stays on its swirl), and kept on the picture. spots: { x, y, b } in the layer's units; each gets
-- ax, ay (where it's drawn) and size (1, or SIDE_SIZE)
local SIDE_SIZE = 0.68
local SAME_SPOT = 0.045                        -- (of the map across: two sources' pins this close are one boss)
local BOSS_R = BOSS_SIZE * BOSS_SCALE * 0.5    -- a boss pin's reach, in the layer's units, full size
local WAY_R = 12
local RANK = { [3] = 4, [1] = 3, [2] = 2, [4] = 1 }   -- boss skull, elite, rare elite, rare
local function ArrangeBosses(spots, ways)
	local n = #spots
	for _, s in ipairs(spots) do
		s.ax, s.ay, s.size = s.x, s.y, 1
		s.rank = RANK[s.b[4]] or 0
	end
	-- (lesser ones on top of a greater one: smaller)
	for i = 1, n do
		local a = spots[i]
		for j = 1, n do
			local b = spots[j]
			if i ~= j and a.rank > b.rank then
				local dx, dy = a.x - b.x, a.y - b.y
				local need = BOSS_R * 2
				if dx * dx + dy * dy < need * need then b.size = SIDE_SIZE end
			end
		end
	end
	for _, s in ipairs(spots) do s.r = BOSS_R * s.size * 0.95 end
	local x0, y0, x1, y1 = geo.x, geo.y, geo.x + geo.w, geo.y + geo.h
	for _ = 1, 40 do
		local moved = false
		for i = 1, n do
			local a = spots[i]
			for j = i + 1, n do
				local b = spots[j]
				local need = a.r + b.r + 1
				local dx, dy = b.ax - a.ax, b.ay - a.ay
				local d2 = dx * dx + dy * dy
				if d2 < need * need then
					local d = math.sqrt(d2)
					if d < 0.01 then
						local t = (i * 2.399 + j * 0.7) % 6.2832
						dx, dy, d = math.cos(t), math.sin(t), 0
					else
						dx, dy = dx / d, dy / d
					end
					local wa, wb = a.r * a.r, b.r * b.r
					local push = need - d
					local fa, fb = wb / (wa + wb), wa / (wa + wb)
					a.ax, a.ay = a.ax - dx * push * fa, a.ay - dy * push * fa
					b.ax, b.ay = b.ax + dx * push * fb, b.ay + dy * push * fb
					moved = true
				end
			end
			for _, w in ipairs(ways) do
				local need = a.r + WAY_R
				local dx, dy = a.ax - w.x, a.ay - w.y
				local d2 = dx * dx + dy * dy
				if d2 < need * need then
					local d = math.sqrt(d2)
					if d < 0.01 then dx, dy, d = 0, 1, 0 else dx, dy = dx / d, dy / d end
					a.ax, a.ay = a.ax + dx * (need - d), a.ay + dy * (need - d)
					moved = true
				end
			end
			a.ax = min(max(a.ax, x0 + a.r), x1 - a.r)
			a.ay = min(max(a.ay, y0 + a.r), y1 - a.r)
		end
		if not moved then break end
	end
end

-- a boss the DungeonJournal places on no map of ours: MapUtils' place for it (on its own pictures), else
-- the game's journal's (OpenMap's): floor, x, y; or nil
local function OtherPlace(inst, jb)
	local want = {}
	for _, n in ipairs(Names(jb[1])) do want[n] = true end
	for _, a in ipairs(jb[8] or {}) do for _, n in ipairs(Names(a)) do want[n] = true end end
	for i, fl in ipairs(FloorsOf(inst) or {}) do
		local k = FloorKey(inst, i, fl.name)
		for _, row in ipairs(k and FM.DUNGEON_PINS and FM.DUNGEON_PINS[k] or {}) do
			local b = row[4] ~= 1 and FM.DUNGEON_BOSSES and FM.DUNGEON_BOSSES[row[3]]
			if b then
				for _, n in ipairs(Names(b[1])) do if want[n] then return i, row[1], row[2] end end
			end
		end
	end
	for name, s in pairs(FM.DUNGEON_BOSS_SPOTS and FM.DUNGEON_BOSS_SPOTS[inst] or {}) do
		if type(s) == "table" and name ~= "lower" and want[name:lower()] then return s[1], s[2], s[3] end
	end
end

local function PlaceBosses(inst, index, floorName)
	local n, ne = 0, 0
	local unlisted = {}
	local spots, ways = {}, {}
	local function Pin(x, y, b)
		n = n + 1
		local p = bossPins[n] or NewBossPin()
		bossPins[n] = p
		p.boss = b
		StyleBoss(p, b)
		spots[n] = { x = geo.x + x * geo.w, y = geo.y + y * geo.h, b = b, p = p }
	end
	if inst then
		local key = FloorKey(inst, index, floorName)
		local f = MUFloors(inst)
		local dj = FM.DUNGEON_JOURNAL and FM.DUNGEON_JOURNAL[inst]
		if dj and FM.db.dungeonBosses ~= false then
			-- the DungeonJournal's bosses, the surest: its list, levels, portraits and places (the others'
			-- bosses it doesn't list left out). One it places on no map of ours: the others' place for it;
			-- with none anywhere, listed beside the map
			for _, jb in ipairs(dj) do
				local info = BossNamed(jb[1])
				for _, a in ipairs(jb[8] or {}) do info = info or BossNamed(a) end
				local b = { jb[1], jb[2] or (info and info[2]) or false, jb[4] or (info and info[3]) or 0, jb[3], jb[9] }
				local f, x, y = jb[5], jb[6], jb[7]
				if not f then f, x, y = OtherPlace(inst, jb) end
				if f == index then Pin(x, y, b)
				elseif not f then unlisted[#unlisted + 1] = b end
			end
		elseif FM.db.dungeonBosses ~= false then
			-- (the ones it doesn't cover, the raids: MapUtils' pins on its pictures, else the game's journal's
			-- places; listed beside the map where neither has one)
			local seen = {}
			-- (where pins stand already: a second source naming the same boss otherwise, e.g. "The Lost
			-- Dwarves" and "Baelog / Eric", isn't pinned again on the same spot)
			local at = {}
			local function Taken(x, y)
				for _, p in ipairs(at) do
					if (p[1] - x) ^ 2 + ((p[2] - y) * 0.667) ^ 2 < SAME_SPOT * SAME_SPOT then return true end
				end
			end
			for _, fl in ipairs(f and f.floors or {}) do
				for _, row in ipairs(FM.DUNGEON_PINS and FM.DUNGEON_PINS[fl.key] or {}) do
					local b = FM.DUNGEON_BOSSES and FM.DUNGEON_BOSSES[row[3]]
					if b and not seen[b[1]] then
						if row[4] ~= 1 then
							if fl.key == key and not Taken(row[1], row[2]) then seen[b[1]] = true Pin(row[1], row[2], b) at[#at + 1] = { row[1], row[2] } end
						else
							local sf, sx, sy = Spot(inst, b)
							if sf then
								if sf == index and not Taken(sx, sy) then seen[b[1]] = true Pin(sx, sy, b) at[#at + 1] = { sx, sy } end
							elseif fl.key == key then
								seen[b[1]] = true
								unlisted[#unlisted + 1] = b
							end
						end
					end
				end
			end
		end
		-- the ways in: on the middle of each swirl drawn on this floor (Data\DungeonEntrances.lua, found
		-- in the picture itself); none where the floor draws none
		local ins = FM.DUNGEON_ENTRANCE_SPOTS and FM.DUNGEON_ENTRANCE_SPOTS[inst]
		local info = FM.Pins.InstanceInfo and FM.Pins.InstanceInfo(inst)
		-- (a floor the DungeonJournal's maps add: its way in, from the journal)
		local own = (FloorsOf(inst) or {})[index]
		local list = ins and ins[index] or (own and own.entrance and { own.entrance }) or {}
		for _, e in ipairs(list) do
			ne = ne + 1
			Entrance(ne, e[1], e[2], info and info.raid)
			ways[#ways + 1] = { x = geo.x + e[1] * geo.w, y = geo.y + e[2] * geo.h }
		end
	end
	ArrangeBosses(spots, ways)
	for i, s in ipairs(spots) do
		local p, k = s.p, BOSS_SCALE * s.size
		-- (the main ones over the ones beside them)
		p:SetFrameLevel(layer:GetFrameLevel() + 4 + (s.size < 1 and 0 or n) + i)
		p.badge:SetFrameLevel(p:GetFrameLevel() + 2)
		p:SetScale(k)
		p:ClearAllPoints()
		p:SetPoint("CENTER", layer, "TOPLEFT", s.ax / k, -s.ay / k)
		p:Show()
	end
	for i = n + 1, #bossPins do bossPins[i]:Hide() end
	for i = ne + 1, #entrancePins do entrancePins[i]:Hide() end
	List(unlisted)
end

local function DrawData()
	local floors = FloorsOf(view.inst)
	view.floor = min(view.floor or 1, #floors)
	local f = floors[view.floor]
	local name = (FM.Pins.InstanceName and FM.Pins.InstanceName(view.inst))
		or (FM.DUNGEON_FLOORS and FM.DUNGEON_FLOORS[view.inst] and FM.DUNGEON_FLOORS[view.inst].name) or ""
	-- (a floor named for a part of the instance, "Upper Blackrock Spire": that name alone)
	local own = f.name and name ~= "" and f.name:find(name, 1, true)
	title:SetText(f.name and f.name ~= name and (name ~= "" and not own and (name .. ": " .. f.name) or f.name) or name)
	ClearTiles()
	if f.texture then
		local bottom = f.bottom or 683 / 1024
		Fit(1024, 1024 * bottom)
		local t = Tile(1)
		t:SetTexture(f.texture, nil, nil, "LINEAR")
		t:SetTexCoord(0, 1, 0, bottom)
		t:SetSize(geo.w, geo.h)
		t:ClearAllPoints()
		t:SetPoint("TOPLEFT", layer, "TOPLEFT", geo.x, -geo.y)
		t:Show()
	else
		local s = Fit(PIC_W, PIC_H)
		for i, fid in ipairs(f.tiles) do
			local t = Tile(i)
			local c, r = (i - 1) % 4, floor((i - 1) / 4)
			t:SetTexture(fid, nil, nil, "LINEAR")
			t:SetTexCoord(0, 1, 0, 1)
			t:ClearAllPoints()
			t:SetPoint("TOPLEFT", layer, "TOPLEFT", geo.x + c * TILE * s, -(geo.y + r * TILE * s))
			t:SetPoint("BOTTOMRIGHT", layer, "TOPLEFT", geo.x + (c + 1) * TILE * s, -(geo.y + (r + 1) * TILE * s))
			t:Show()
		end
	end
	noMap:Hide()
	credit:SetShown(f.credit ~= nil)
	PlaceBosses(view.inst, view.floor, f.name)
	local names = {}
	for i, fl in ipairs(floors) do names[i] = fl.name or ("Floor " .. i) end
	Floors(names, view.floor)
end

---------------------------------------------------------------------------
-- A battleground's own icons, as the game's map has them: its objectives (Arathi Basin's bases, Alterac
-- Valley's towers, bunkers, graveyards and mines...: the game's area POIs, each in the icon of its state,
-- named with it) and the flags where they are (Warsong Gulch's, carried or dropped). All read from the
-- game, so every battleground Forever has shows as it has it. Objectives refresh on events (with a
-- periodic fallback); flag positions are polled separately from the camera animation.
---------------------------------------------------------------------------
local POI_FILE = "Interface\\Minimap\\POIIcons"
local POI_SIZE, FLAG_SIZE, TIP_NEAR = 22, 28, 12
local pois, flags = {}, {}
local nPois, nFlags = 0, 0
local poiAt, flagsAt, questsAt = 0, 0, 0
local questieDirty = false
local bgTip
local NO_IDS = {}
local MAX_GAME_ZOOM = FM.Map.ZOOM_STEP ^ 4
local FLAG_INTERVAL = 0.05
local game = { zoom = 1, cx = 0.5, cy = 0.5 }
local gameTiles, gameReveals = {}, {}

local function PositionXY(pos)
	pos = Plain(pos)
	if not pos then return end
	local x, y = pos:GetXY()
	return Plain(x), Plain(y)
end

local function Icon(list, i, size, sub)
	local t = list[i]
	if not t then
		t = mapForeground:CreateTexture(nil, "OVERLAY", nil, sub)
		t:SetSize(size, size)
		list[i] = t
	end
	return t
end

local function IsAtlas(name)
	return type(name) == "string" and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local function PlacePin(pin, x, y)
	local sx, sy = geo.x + x * geo.w, geo.y + y * geo.h
	pin.mx, pin.my = x, y
	if sx ~= pin.sx or sy ~= pin.sy then
		pin.sx, pin.sy = sx, sy
		pin:ClearAllPoints()
		pin:SetPoint("CENTER", mapForeground, "TOPLEFT", sx, -sy)
	end
	return sx, -sy
end

local function PlaceIcon(t, x, y)
	PlacePin(t, x, y)
	t:Show()
end

-- the log's quests on the map, as Blizzard's map shows them there (Quests.lua's buttons)
local questButtons, questieButtons = {}, {}
local function LayoutQuests(now)
	questsAt = now + 1
	FM.Quests.LayoutOnMap(questButtons, mapForeground, view.uiMap, PlacePin)
end

local function LayoutQuestie(m)
	questieDirty = false
	FM.Quests.LayoutQuestieOnMap(questieButtons, mapForeground, m, PlacePin)
end

local function StopGameCamera()
	game.target, game.dragX, game.dragY, game.dragging = nil, nil, nil, false
end

local function ClearBattleground()
	StopGameCamera()
	gameArt:Hide()
	for _, pins in ipairs(unitLayers) do pins:Hide() end
	FM.Map.EndGroupTip()
	for i = 1, nPois do pois[i]:Hide() end
	for i = 1, nFlags do flags[i]:Hide() end
	nPois, nFlags = 0, 0
	for _, b in ipairs(questButtons) do b:Hide() end
	LayoutQuestie()
end

local function LiveBattleground(m)
	if not m or Plain(C_Map.GetBestMapForUnit("player")) ~= m then return false end
	if C_PvP and C_PvP.IsBattleground then return Plain(C_PvP.IsBattleground()) == true end
	local _, kind = IsInInstance()
	return Plain(kind) == "pvp"
end

local function UpdateUnitMap(m)
	if not unitPins then return end
	if not view.live or (C_Map.GetMapDisplayInfo and Plain(C_Map.GetMapDisplayInfo(m))) then
		for _, pins in ipairs(unitLayers) do pins:Hide() end
		return
	end
	for _, pins in ipairs(unitLayers) do
		if unitsMapID ~= m then pins:SetUiMapID(m) end
		pins:Show()
	end
	unitsMapID = m
end

-- (a battleground's objectives and flags only while you're in it, as Blizzard's map shows them: from
-- outside, a quest's map, the game gives them in a state of no game (a neutral camp), nothing to read there)
local function ReadObjectives(now)
	local m = view and view.uiMap
	poiAt = now + 1
	view.live = LiveBattleground(m)
	UpdateUnitMap(m)
	local n = 0
	local A = C_AreaPoiInfo
	local coords = C_Minimap and C_Minimap.GetPOITextureCoords or GetPOITextureCoords
	local ids = view.live and A and A.GetAreaPOIForMap and Plain(A.GetAreaPOIForMap(m)) or NO_IDS
	for _, rawID in ipairs(ids) do
		local id = Plain(rawID)
		local info = id and Plain(A.GetAreaPOIInfo(m, id))
		if info then
			local x, y = PositionXY(info.position)
			local atlas, index = Plain(info.atlasName), Plain(info.textureIndex)
			local useAtlas = IsAtlas(atlas)
			if x and y and (useAtlas or coords and type(index) == "number") then
				n = n + 1
				local t = Icon(pois, n, POI_SIZE, 0)
				local tex = useAtlas and atlas or index
				if t.tex ~= tex then
					t.tex = tex
					if useAtlas then
						t:SetAtlas(atlas)
					else
						t:SetTexture(POI_FILE)
						t:SetTexCoord(coords(index))
					end
				end
				t.name, t.desc = Plain(info.name), Plain(info.description)
				PlaceIcon(t, x, y)
			end
		end
	end
	for i = n + 1, nPois do pois[i]:Hide() end
	nPois = n
end

local function ReadFlags(now)
	flagsAt = now + FLAG_INTERVAL
	local m = view.uiMap
	local count = view.live and Plain(GetNumBattlefieldFlagPositions and GetNumBattlefieldFlagPositions()) or 0
	local get = C_PvP and C_PvP.GetBattlefieldFlagPosition or GetBattlefieldFlagPosition
	local n = 0
	for i = 1, get and count or 0 do
		local a, b, c = get(i, m)
		a = Plain(a)
		local x, y, tex
		if type(a) == "table" and a.GetXY then
			x, y = PositionXY(a)
			tex = Plain(b)
		else
			x, y, tex = a, Plain(b), Plain(c)
		end
		local text = type(tex) == "string" and tex ~= ""
		local fileID = type(tex) == "number" and tex > 0
		if type(x) == "number" and type(y) == "number" and (x > 0 or y > 0) and (text or fileID) then
			n = n + 1
			local t = Icon(flags, n, FLAG_SIZE, 1)
			if t.tex ~= tex then
				t.tex = tex
				if IsAtlas(tex) then t:SetAtlas(tex)
				else
					local path = text and not tex:find("[/\\]") and ("Interface\\WorldStateFrame\\" .. tex) or tex
					t:SetTexture(path)
					t:SetTexCoord(0, 1, 0, 1)
				end
				t.name = text and tex:find("Horde") and "Horde Flag"
					or text and tex:find("Alliance") and "Alliance Flag" or "Flag"
			end
			PlaceIcon(t, x, y)
		end
	end
	for i = n + 1, nFlags do flags[i]:Hide() end
	nFlags = n
end

local function EndBattlegroundTip()
	if bgTip then bgTip = nil S.HideTip() end
end

-- over an objective or a flag: its name (and its state)
local function BattlegroundTip(cx, cy)
	local hit
	for i = nFlags, 1, -1 do
		local t = flags[i]
		if (t.sx - cx) ^ 2 + (t.sy - cy) ^ 2 <= TIP_NEAR * TIP_NEAR then hit = t break end
	end
	if not hit then
		for i = nPois, 1, -1 do
			local t = pois[i]
			if (t.sx - cx) ^ 2 + (t.sy - cy) ^ 2 <= TIP_NEAR * TIP_NEAR then hit = t break end
		end
	end
	if not hit then EndBattlegroundTip() return end
	local key = (hit.name or "") .. (hit.desc or "")
	if key == bgTip then return end
	bgTip = key
	local d = hit.desc
	S.ShowTip(nil, (d and d ~= "") and { hit.name or "", d } or { hit.name or "" }, hit.sx + 10, -hit.sy + 4, layer)
end

local function ClampCenter(center, viewSize, mapSize)
	local half = min(0.5, viewSize / (2 * mapSize))
	return min(max(center, half), 1 - half)
end

local function MovePins(pins, n)
	for i = 1, n do
		local pin = pins[i]
		if pin:IsShown() then PlacePin(pin, pin.mx, pin.my) end
	end
end

local function SyncUnitPinSizes()
	local scale = game.scale
	if not (unitPins and scale) or game.pinScale == scale then return end
	-- A size change rebuilds the native unit list. During zoom, update only when
	-- there is a visible difference, then restore the exact sizes when it settles.
	if game.target and game.pinScale and math.abs(scale / game.pinScale - 1) < 0.04 then return end
	game.pinScale = scale
	unitPins:SetPinSize("party", 12 / scale)
	unitPins:SetPinSize("raid", 12 / scale)
	playerPins:SetPinSize("player", 27 / scale)
end

local function LayoutGameCamera()
	local vw, vh = layer:GetSize()
	if vw <= 0 or vh <= 0 then return end
	game.vw, game.vh = vw, vh
	local s = min(vw / game.width, vh / game.height) * game.zoom
	geo.w, geo.h = game.width * s, game.height * s
	game.cx = ClampCenter(game.cx, vw, geo.w)
	game.cy = ClampCenter(game.cy, vh, geo.h)
	geo.x, geo.y = vw / 2 - game.cx * geo.w, vh / 2 - game.cy * geo.h
	if game.scale ~= s then
		game.scale = s
		gameArt:SetScale(s)
	end
	gameArt:SetPoint("TOPLEFT", layer, "TOPLEFT", geo.x / s, -geo.y / s)
	MovePins(pois, nPois)
	MovePins(flags, nFlags)
	MovePins(questButtons, #questButtons)
	MovePins(questieButtons, #questieButtons)
end

-- Bring a quest selected in the log into the camera's bounds before its pin flashes.
function D.RevealQuestPin(x, y)
	if not (game.vw and gameArt:IsVisible()) then return end
	local sx, sy = geo.x + x * geo.w, geo.y + y * geo.h
	local margin = 16
	if sx >= margin and sx <= game.vw - margin and sy >= margin and sy <= game.vh - margin then return end
	StopGameCamera()
	game.cx, game.cy = x, y
	LayoutGameCamera()
end

local function GameCursor()
	local x, y = GetCursorPosition()
	local s = layer:GetEffectiveScale()
	return x / s - layer:GetLeft(), layer:GetTop() - y / s
end

local function ZoomGame(_, delta)
	if not (view and view.uiMap and gameArt:IsShown() and game.vw) then return end
	local target = (game.target or game.zoom) * FM.Map.ZOOM_STEP ^ delta
	game.target = min(max(target, 1), MAX_GAME_ZOOM)
	game.zoomX, game.zoomY = GameCursor()
end

local function AnimateGameCamera(elapsed)
	local moved = false
	if game.dragX and not IsMouseButtonDown("LeftButton") then
		game.dragX, game.dragY, game.dragging = nil, nil, false
	end
	if game.dragX then
		local x, y = GameCursor()
		local dx, dy = x - game.dragX, y - game.dragY
		if (dx ~= 0 or dy ~= 0) and (game.dragging or dx * dx + dy * dy > 9) then
			game.cx, game.cy = game.cx - dx / geo.w, game.cy - dy / geo.h
			game.dragX, game.dragY, game.dragging = x, y, true
			moved = true
		end
		if game.target then game.zoomX, game.zoomY = x, y end
	end
	if game.target then
		local nextZoom
		nextZoom, game.target = FM.Map.AnimateZoom(game.zoom, game.target, elapsed)
		if nextZoom ~= game.zoom then
			local shift = 1 - game.zoom / nextZoom
			game.cx = game.cx + (game.zoomX - game.vw / 2) / geo.w * shift
			game.cy = game.cy + (game.zoomY - game.vh / 2) / geo.h * shift
			game.zoom, moved = nextZoom, true
		end
	end
	if moved then LayoutGameCamera() end
end

local function PaintGameTile(pool, i, sub, file, x, y, w, h, u, v)
	local t = pool[i]
	if not t then
		t = gameArt:CreateTexture(nil, "ARTWORK", nil, sub)
		if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) t:SetTexelSnappingBias(0) end
		pool[i] = t
	end
	t:SetTexture(file, nil, nil, "LINEAR")
	t:SetTexCoord(0, u, 0, v)
	t:SetPoint("TOPLEFT", gameArt, "TOPLEFT", x, -y)
	t:SetSize(w, h)
	t:Show()
end

local function LoadGameArt(m)
	local art = C_Map.GetMapArtID(m)
	if m == game.map and art == game.art then return true end
	local layers = C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(m)
	local L = layers and layers[1]
	local files = L and C_Map.GetMapArtLayerTextures and C_Map.GetMapArtLayerTextures(m, 1)
	if not (L and files and #files > 0 and L.layerWidth > 0 and L.layerHeight > 0 and L.tileWidth > 0 and L.tileHeight > 0) then
		return false
	end
	ClearBattleground()
	game.map, game.art = m, art
	game.width, game.height = L.layerWidth, L.layerHeight
	game.tileWidth, game.tileHeight = L.tileWidth, L.tileHeight
	game.scale = nil
	game.zoom, game.cx, game.cy = 1, 0.5, 0.5
	gameArt:SetSize(game.width, game.height)
	local tw, th = L.tileWidth, L.tileHeight
	local cols = math.ceil(game.width / tw)
	local nTiles = 0
	for i, file in ipairs(files) do
		local x, y = (i - 1) % cols * tw, floor((i - 1) / cols) * th
		local w, h = min(tw, game.width - x), min(th, game.height - y)
		if w <= 0 or h <= 0 then break end
		PaintGameTile(gameTiles, i, 0, file, x, y, w, h, w / tw, h / th)
		nTiles = i
	end
	for i = nTiles + 1, #gameTiles do gameTiles[i]:Hide() end
	return true
end

local function DrawGameReveals(m)
	local n = 0
	FM.Isles.EachRevealTile(m, game.tileWidth, game.tileHeight, function(file, x, y, w, h, u, v)
		n = n + 1
		PaintGameTile(gameReveals, n, 1, file, x, y, w, h, u, v)
	end)
	for i = n + 1, #gameReveals do gameReveals[i]:Hide() end
end

local function DrawGame()
	PlaceBosses()
	credit:Hide()
	local m = view.uiMap
	local info = C_Map.GetMapInfo(m)
	title:SetText(info and info.name or "")
	ClearTiles()
	Floors(nil)
	if not LoadGameArt(m) then ClearBattleground() noMap:Show() return end
	noMap:Hide()
	DrawGameReveals(m)
	LayoutGameCamera()
	SyncUnitPinSizes()
	gameArt:Show()
	local now = GetTime()
	ReadObjectives(now)
	ReadFlags(now)
	LayoutQuests(now)
	LayoutQuestie(m)
end

function Draw()
	if not view then return end
	InstanceButton()
	if view.uiMap then DrawGame() return end
	ClearBattleground()
	if view.inst and FloorsOf(view.inst) then DrawData()
	else
		ClearTiles()
		PlaceBosses()
		Floors(nil)
		title:SetText(view.name or "")
		noMap:Show()
	end
end

local function Show(v, fromIcon)
	view, opened = v, fromIcon and true or false
	if not layer:IsShown() then layer:Show() end
	Draw()
	if FM.Map.dungeonButton then
		FM.Map.dungeonButton.label:SetText("World")
		FM.Map.dungeonButton:Show()
	end
end

local function Close()
	D.HideChooser()
	view, opened = nil, false
	if layer:IsShown() then layer:Hide() FM.Map.MarkDirty() end
	ClearBattleground()
	EndBattlegroundTip()
	local inside = D.Inside() and FM.db.dungeonMaps ~= false
	if FM.Map.dungeonButton then
		FM.Map.dungeonButton.label:SetText("Dungeon")
		FM.Map.dungeonButton:SetShown(inside)
	end
end

-- a left-click on a dungeon's icon: its map (the first of an entrance's with one); name: for none
-- floor: the one to show first (a part of the instance on a floor of its own: Upper Blackrock Spire)
function D.Open(insts, name, chosen, floor)
	if not layer or not insts or #insts == 0 then return end
	-- (insts: instance IDs, or the chooser's entries, kept to offer the same choice again on the map)
	local ids, first = {}, nil
	for i, inst in ipairs(insts) do
		local id = type(inst) == "table" and inst.id or inst
		ids[i] = id
		if not first and FloorsOf(id) then first = id end
	end
	Show({ insts = ids, choices = insts, inst = chosen or first or ids[1], floor = floor or 1, name = name,
		picked = floor and true or nil }, true)
	PlaySound(SOUNDKIT and SOUNDKIT.IG_QUEST_LOG_OPEN or 844)
end

-- a map the game has of a place off the world (a battleground's), opened as from an icon: a quest picked
-- there (Blizzard's map goes to it too). false when the game has no art for it
function D.OpenMap(m)
	if not layer or not m or m == 0 then return false end
	local layers = C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(m)
	if not (layers and layers[1]) then return false end
	if not (view and view.uiMap == m and layer:IsShown()) then Show({ uiMap = m }, true) end
	return true
end

-- back on the world for something there (a quest picked on it): a map opened from an icon closed; inside,
-- the world peeked at, as the header's World button does
function D.ToWorld()
	if not D.Active() then return end
	if not opened then peek = true end
	Close()
end

-- one part of an instance an entrance leads to ({ id, name }): its map, on its own floor if it has one
function D.OpenWing(w)
	D.Open({ w.id }, w.name, w.id, FloorNamed(w.id, w.name))
end

-- On battleground maps the native frame positions group markers in the game client.
function D.Tick(elapsed)
	if not (view and view.uiMap and gameArt:IsVisible() and game.vw) then return end
	AnimateGameCamera(elapsed)
	local now = GetTime()
	if now >= poiAt then ReadObjectives(now) end
	if (view.live or nFlags > 0) and now >= flagsAt then ReadFlags(now) end
	if now >= questsAt then LayoutQuests(now) end
	if questieDirty then LayoutQuestie(view.uiMap) end
	local showUnits = unitPins and unitPins:IsShown()
	if showUnits then
		SyncUnitPinSizes()
		for _, pins in ipairs(unitLayers) do pins:UpdatePlayerPins() end
	end
	-- (over a member's dot: their name, as on the world map; else over an objective or a flag, its own)
	local focus = layer:IsMouseOver() and (GetMouseFoci and GetMouseFoci()[1] or GetMouseFocus and GetMouseFocus())
	if focus == layer then
		local sx, sy = GameCursor()
		if not showUnits then FM.Map.EndGroupTip() end
		if showUnits and FM.Map.GroupTipForUnits(sx, sy, layer, unitPins:GetMouseOverUnits()) then
			bgTip = nil
		else
			BattlegroundTip(sx, sy)
		end
	else
		FM.Map.EndGroupTip()
		EndBattlegroundTip()
	end
	return true
end

-- as the window opens and as you move: inside, the place you're in (on the part you're in, unless
-- you picked a floor); outside, a map opened from an icon stays until it's closed
function D.Update()
	if not layer then return end
	local here = FM.db.dungeonMaps ~= false and Here() or nil
	if not here then
		peek = false
		if not opened then Close() end
		return
	end
	if peek and not opened then Close() return end
	if opened then return end
	local same = view and ((here.uiMap and view.uiMap == here.uiMap) or (here.inst and view.inst == here.inst))
	if not same then
		here.floor = here.inst and FloorHere(FloorsOf(here.inst)) or nil
		Show(here, false)
		return
	end
	if view.uiMap then
		if gameArt:IsShown() and (layer:GetWidth() ~= game.vw or layer:GetHeight() ~= game.vh) then LayoutGameCamera() end
		return
	end
	-- (moved into another part: its floor, unless one was picked)
	local sub = Plain(GetSubZoneText and GetSubZoneText())
	if view.inst and sub ~= lastSub then
		lastSub = sub
		if not view.picked then
			local f = FloorHere(FloorsOf(view.inst), view.floor)
			if f ~= view.floor then view.floor = f Draw() end
		end
	end
end

-- inside a dungeon: its map up (the tools' Center on me); false when you aren't in one
function D.ShowHere()
	if not layer or FM.db.dungeonMaps == false or not D.Inside() then return false end
	peek = false
	if opened then Close() end
	D.Update()
	return true
end

-- back on the world from a dungeon's map: framed on its way in (its icon on the map)
local function ToEntrance(v)
	local inst = v and v.inst
	if not inst or not (FM.Pins and FM.Pins.InstanceUnits) then return end
	local u, w = FM.Pins.InstanceUnits(inst)
	if u then FM.Map.SetView(u, w, 140) FM.Map.MarkDirty() end
end

-- back on the world from a battleground's map: its continent, whole (as far up as there's one)
local function ToContinent(m, zoomOut)
	local CONTINENT = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2
	local id = m
	for _ = 1, 8 do
		local info = id and C_Map.GetMapInfo(id)
		if not info then break end
		if info.mapType == CONTINENT then m = id break end
		id = info.parentMapID
	end
	FM.Map.ShowMapID(m, zoomOut)
	FM.Map.MarkDirty()
end

-- the header's button: World (back from a dungeon's map), Dungeon (inside: its map again)
function D.TogglePeek(fromRightClick)
	if D.Active() then
		if not opened then peek = true end
		local was, here = view, Here()
		Close()
		if was and was.uiMap then
			-- (a battleground's: inside it, its continent; anywhere else, back on you as the map opens)
			local zoomOut = fromRightClick and LiveBattleground(was.uiMap)
			if zoomOut or (here and here.uiMap == was.uiMap) or not FM.Map.ViewAsOpened() then
				ToContinent(was.uiMap, zoomOut)
			else
				FM.Map.MarkDirty()
			end
		else
			ToEntrance(was)
		end
	else
		peek = false
		D.Update()
	end
end

-- (the window closed: a dungeon opened from its icon closes with it; the world's there next time.
-- Inside one, its map is there again next time, even if you were looking at the world)
function D.OnHide()
	D.HideChooser()
	peek = false
	StopGameCamera()
	poiAt, flagsAt, questsAt, questieDirty = 0, 0, 0, true
	if layer and opened then Close() end
end

-- Coalesce quest events into one update, and skip hidden maps.
function D.QuestsChanged(fromQuestie)
	if not (view and view.uiMap and layer:IsVisible()) then return end
	if fromQuestie then questieDirty = true else questsAt = 0 end
end

-- (an option changed: drawn again)
function D.Refresh()
	if layer and layer:IsVisible() then Draw() end
end

function D.Back()
	if D.Active() then D.TogglePeek(true) end
end

local function CreateUnitLayer(level)
	-- A fixed map rectangle inherits the same camera transform as the art.
	local pins = CreateFrame("UnitPositionFrame", nil, gameArt, "UnitPositionFrameTemplate")
	pins:SetAllPoints()
	pins:SetFrameLevel(level)
	pins:EnableMouse(false)
	pins:SetNeedsPeriodicUpdate(false)
	pins:Hide()
	unitLayers[#unitLayers + 1] = pins
	return pins
end

function D.Init(view_, level)
	layer = CreateFrame("Frame", nil, view_)
	layer:SetAllPoints()
	layer:SetFrameLevel(level)
	layer:SetClipsChildren(true)
	layer:EnableMouse(true)                    -- (the world under it isn't dragged or hovered)
	layer:EnableMouseWheel(true)
	layer:SetScript("OnMouseWheel", ZoomGame)
	layer:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" and view and view.uiMap and gameArt:IsShown() and game.vw then
			game.dragX, game.dragY = GameCursor()
			game.dragging = false
		end
	end)
	layer:SetScript("OnMouseUp", function(_, button)
		if button == "LeftButton" then game.dragX, game.dragY, game.dragging = nil, nil, false end
		-- (a right-click on a boss or the way in is theirs: only one on the bare map goes back)
		local focus = GetMouseFoci and GetMouseFoci()[1] or GetMouseFocus and GetMouseFocus()
		if focus and focus ~= layer then return end
		if button == "RightButton" then D.Back() end
	end)
	layer:Hide()
	local bg = layer:CreateTexture(nil, "BACKGROUND", nil, -8)
	bg:SetTexture(S.WHITE)
	bg:SetVertexColor(0.07, 0.065, 0.06, 1)
	bg:SetAllPoints()
	gameArt = CreateFrame("Frame", nil, layer)
	gameArt:SetFrameLevel(level + 1)
	gameArt:Hide()
	mapForeground = CreateFrame("Frame", nil, layer)
	local foregroundLevel = level + 2
	mapForeground:SetFrameLevel(foregroundLevel)
	mapForeground:SetAllPoints()
	title = mapForeground:CreateFontString(nil, "OVERLAY")
	S.Font(title, 20, "OUTLINE")
	title:SetTextColor(1, 0.82, 0)
	title:SetPoint("BOTTOM", 0, 12)
	credit = S.Text(mapForeground, 10, S.DIM)
	credit:SetPoint("BOTTOMLEFT", 10, 8)
	credit:SetText("Map drawn by Santiago Reyes  \194\183  sreyesmaps.com")
	credit:Hide()
	noMap = S.Text(mapForeground, 13, S.DIM)
	noMap:SetPoint("CENTER")
	noMap:SetText("The game has no map of this place.")
	noMap:Hide()
	local hint = S.Text(mapForeground, 10, S.DIM)
	-- (left of the quest log's arrow in the corner, 22 px wide at 24 px in and 6 up: level with its middle)
	hint:SetPoint("RIGHT", layer, "BOTTOMRIGHT", -54, 17)
	hint:SetText("Right-click: back to the world")
	if UnitPositionFrameMixin then
		unitPins = CreateUnitLayer(foregroundLevel + 1)
		local playerLevel = foregroundLevel + FM.Quests.PLAYER_PIN_LEVEL
		playerPins = unitPins
		if unitPins.SetShouldShowUnits then
			unitPins:SetShouldShowUnits("player", false)
			playerPins = CreateUnitLayer(playerLevel)
			playerPins:SetShouldShowUnits("party", false)
			playerPins:SetShouldShowUnits("raid", false)
		else
			playerPins:SetFrameLevel(playerLevel)
		end
		playerPins:SetPinTexture("player", "UI-WorldMapArrow")
	end
	layer:SetScript("OnSizeChanged", function()
		if not layer:IsVisible() then return end
		if view and view.uiMap and gameArt:IsShown() then LayoutGameCamera() else Draw() end
	end)
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
	ev:RegisterEvent(e)
end
pcall(ev.RegisterEvent, ev, "AREA_POIS_UPDATED")      -- (a battleground's objective changed hands)
ev:SetScript("OnEvent", function(_, event)
	if event == "AREA_POIS_UPDATED" then
		if view and view.uiMap and layer:IsVisible() then poiAt = 0 end
		return
	end
	if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
		peek, lastSub = false, nil
		if layer and not opened then view = nil end
	end
	if FM.Map and FM.Map.IsShown() then D.Update() end
end)
