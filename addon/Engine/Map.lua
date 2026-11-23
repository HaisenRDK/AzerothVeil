-- The map window: one canvas for the whole world, drawn from a tile pyramid (Tiles\<level>\<i>_<j>,
-- levels 1..16 pixels per world unit, 512px tiles stepping 510, every zone's own map stitched in).
-- At any zoom only the tiles of the one level that matches the screen are on screen (a few dozen at
-- most), over the coarsest level so nothing is ever blank while a file loads. No masks, no blending.
-- The zone under the cursor lights up with Blizzard's own highlight art for it (as OpenMap does).
-- Built the first time it opens; while it's closed, nothing runs at all.
local ADDON_NAME, FM = ...
local L = FM.L
local Map = {}
FM.Map = Map
-- one step of the wheel; how much of the world is across the view when M opens it on you
Map.ZOOM_STEP = 1.35
Map.OPEN_ACROSS = 220
-- (AzerothVeil: the zoom the quest log's quests show from (Quests.lua), and the flight masters with them
-- (Pins.lua): one value for both, so they always come on together)
Map.QUESTS_ZOOM = 1.7

local S = FM.Style
local Geo = FM.Geo
local floor, ceil, min, max, exp, log = math.floor, math.ceil, math.min, math.max, math.exp, math.log
local GetTime, GetCursorPosition = GetTime, GetCursorPosition
local debugprofilestop = debugprofilestop

local W, H = FM.W, FM.H
local STEP = 510
local TC0, TC1 = 1 / 512, 511 / 512
local MEDIA = "Interface\\AddOns\\AzerothVeil\\Media\\"
local LEVELS = { 1, 2, 4, 8, 16 }
local MAX_PPU = 64                -- deepest zoom: screen pixels per world unit (past the art's 16: the minimap's terrain)
local HEADER = 26
local KEEP_SECONDS = 25           -- a tile off screen keeps its file this long (panning back is free)
local KEEP_MAX = 64               -- ... and at most this many of them
local DETAIL = 1
local SETS = {
	[DETAIL] = { path = "Interface\\AddOns\\AzerothVeil\\Tiles\\", index = FM.TILES, top = 16,
		sub = { [1] = -8, [2] = -7, [4] = -6, [8] = -5, [16] = -4 } },
}
local NI, NJ = {}, {}
for _, L in ipairs(LEVELS) do NI[L], NJ[L] = ceil(W * L / STEP), ceil(H * L / STEP) end
-- which tiles exist (the levels above 4 leave out the open sea: the level below draws it)
for _, set in pairs(SETS) do
	set.has = {}
	for _, L in ipairs(LEVELS) do
		local h = {}
		for _, k in ipairs(set.index[L] or {}) do h[k] = true end
		set.has[L] = h
	end
end

local function Smooth(x, a, b)
	local t = (x - a) / (b - a)
	if t <= 0 then return 0 elseif t >= 1 then return 1 end
	return t * t * (3 - 2 * t)
end

-- state
local frame, view, tileLayer, pinLayer, topLayer, arrow, header
-- AzerothVeil: the coordinates at the map's bottom middle (the Map module's options): the player's and the cursor's,
-- each on the zone it's in (0-100); the player's written again 5 times a second at most, the cursor's as it moves
local coordText
local coordPlayer, coordCursor = nil, nil
local coordAt = 0
local function ShowCoords()
	if not coordText then return end
	local p = FM.db.playerCoords and coordPlayer
	local c = FM.db.cursorCoords and coordCursor
	if p and c then coordText:SetText(p .. "     " .. c) else coordText:SetText(p or c or "") end
	coordText:SetShown((p or c) and true or false)
end
-- (the Map module's options changed: written again from the next look)
function Map.RefreshCoords()
	if not FM.db.playerCoords then coordPlayer = nil end
	if not FM.db.cursorCoords then coordCursor = nil end
	coordAt = 0
	ShowCoords()
end
local function ZoneCoords(u, v, fmt)
	if not u then return nil end
	local mapID = Geo.ZoneAt(u, v)
	local x, y
	if mapID then x, y = Geo.UnitsToMap(mapID, u, v) end
	if not (x and y) or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
	return (fmt):format(x * 100, y * 100)
end
local worldArt, cityLayer
local built = false
local cx, cy, scale = W / 2, H / 2, 1        -- view centre (units) and UI px per unit
local vw, vh = 1, 1
local left, top = 0, 0
local ppuFactor = 1                          -- physical px per view px
local level = 1
local zoom = 1                               -- 1: the farthest
local atWorld = false                        -- zoomed right out: the world map as the game's own shows it
local worldAlpha = 0                         -- ... how much of it shows (it fades over the first step in)
local dirty = true
local stats = { loads = 0, refreshMs = 0, refreshes = 0, maxMs = 0 }

---------------------------------------------------------------------------
-- Tiles
---------------------------------------------------------------------------
local active = {}       -- key -> texture (on screen, or kept hidden with its file)
local wanted = {}       -- key -> pass that wanted it
local lastUse = {}      -- key -> GetTime() it was last on screen
local pool = {}
local pass = 0
local nActive, nShown = 0, 0

-- the cell (L, i, j) drawn from the tile (l, ii, jj) of its own level or a coarser one (that tile's part
-- over the cell). Every cell is one texture, edge to edge with its neighbours (each edge worked out the
-- same way for the cells either side of it): nothing overlaps, so the map faded (Fade while moving) shows
-- no grid where tiles would be drawn twice
local TCW = TC1 - TC0
local function Want(setID, L, i, j, alpha, l, ii, jj)
	local key = ((setID * 32 + L) * 32 + l) * 4096 + i * 64 + j
	if wanted[key] == pass then return end
	wanted[key] = pass
	local t = active[key]
	if not t then
		local set = SETS[setID]
		t = tremove(pool)
		if not t then
			t = tileLayer:CreateTexture(nil, "BACKGROUND")
			if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) t:SetTexelSnappingBias(0) end
		end
		t:SetTexture(set.path .. l .. "\\" .. ii .. "_" .. jj, "CLAMP", "CLAMP", "TRILINEAR")
		local k = L / l
		local si, sj = i - ii * k, j - jj * k
		t:SetTexCoord(TC0 + TCW * si / k, TC0 + TCW * (si + 1) / k, TC0 + TCW * sj / k, TC0 + TCW * (sj + 1) / k)
		t:SetDrawLayer("BACKGROUND", set.sub[L])
		t.fmA = nil
		active[key] = t
		nActive = nActive + 1
		stats.loads = stats.loads + 1
	end
	if t.fmA ~= alpha then t.fmA = alpha t:SetAlpha(alpha) end
	local size = STEP / L
	t:SetPoint("TOPLEFT", tileLayer, "TOPLEFT", (i * size - left) * scale, (top - j * size) * scale)
	t:SetPoint("BOTTOMRIGHT", tileLayer, "TOPLEFT", ((i + 1) * size - left) * scale, (top - (j + 1) * size) * scale)
	t:Show()
	nShown = nShown + 1
end

local function Range(L, x0, y0, x1, y1)
	local size = STEP / L
	return max(0, floor(x0 / size)), min(NI[L] - 1, floor(x1 / size)),
		max(0, floor(y0 / size)), min(NJ[L] - 1, floor(y1 / size))
end

-- one set's tiles for the view at level L; underlay: its coarsest level under them
local function DrawSet(setID, L, alpha, underlay)
	local has = SETS[setID].has
	local x1, y1 = left + vw / scale, top + vh / scale
	local i0, i1, j0, j1
	if underlay then
		i0, i1, j0, j1 = Range(1, left, top, x1, y1)
		for i = i0, i1 do for j = j0, j1 do
			if has[1][i * 64 + j] then Want(setID, 1, i, j, alpha, 1, i, j) end
		end end
	end
	if L > 1 or not underlay then
		i0, i1, j0, j1 = Range(L, left, top, x1, y1)
		for i = i0, i1 do for j = j0, j1 do
			-- (where this level has no tile, its nearest coarser one's part: every cell over the underlay
			-- alike, so faded the map is even all over)
			local l, ii, jj = L, i, j
			while l > 1 and not has[l][ii * 64 + jj] do l, ii, jj = l / 2, floor(ii / 2), floor(jj / 2) end
			if has[l][ii * 64 + jj] then Want(setID, L, i, j, alpha, l, ii, jj) end
		end end
	end
end

local function UpdateTiles()
	pass = pass + 1
	nShown = 0
	DrawSet(DETAIL, level, 1, true)
	-- off screen: hide (keep the file a while), then let go
	local now = GetTime()
	local kept = 0
	for key, t in pairs(active) do
		if wanted[key] == pass then
			lastUse[key] = now
		else
			if t:IsShown() then t:Hide() t:ClearAllPoints() end
			kept = kept + 1
			if now - (lastUse[key] or 0) > KEEP_SECONDS then
				t:SetTexture(nil)
				active[key], wanted[key], lastUse[key] = nil, nil, nil
				pool[#pool + 1] = t
				nActive = nActive - 1
				kept = kept - 1
			end
		end
	end
	if kept > KEEP_MAX then       -- too many kept: drop them all (the oldest are the same ones anyway)
		for key, t in pairs(active) do
			if wanted[key] ~= pass then
				t:SetTexture(nil)
				active[key], wanted[key], lastUse[key] = nil, nil, nil
				pool[#pool + 1] = t
				nActive = nActive - 1
			end
		end
	end
end

---------------------------------------------------------------------------
-- View
---------------------------------------------------------------------------
local function Measure()
	vw, vh = view:GetSize()
	if not vw or vw < 1 then vw, vh = 1, 1 end
	local _, physH = GetPhysicalScreenSize()
	ppuFactor = view:GetEffectiveScale() * (physH or 768) / 768
end

-- How far the map pans and zooms out: the whole world map, edge to edge, as Blizzard's world map and
-- OpenMap frame it at their farthest (its torn edge faded into the sea in the tiles). 3:2 like the
-- window, so the farthest zoom fills it exactly with no empty band on any side.
-- On a land off the world map (Zephras Isle: Geo.AWAY, Isles.lua) the bounds are that land's own place,
-- past the world's edge: it shows alone, as a map apart, panned and zoomed within itself.
local BX0, BY0, BX1, BY1 = 0, 0, W, H
local BW, BH = BX1 - BX0, BY1 - BY0
local awayMap                 -- the land shown on its own (its map), else nil: the world
local worldView               -- the world's view meanwhile: { cx, cy, scale }

local function Limits()
	local fit = max(vw / BW, vh / BH)
	return fit, max(fit, MAX_PPU / ppuFactor)
end
-- (the zoom every kind of icon comes on at is the world's: a land apart is as close in as its size makes it)
local function WorldFit() return max(vw / W, vh / H) end

local function Clamp()
	local fit, deepest = Limits()
	if scale < fit then scale = fit elseif scale > deepest then scale = deepest end
	local hw, hh = vw / 2 / scale, vh / 2 / scale
	if hw * 2 >= BW then cx = (BX0 + BX1) / 2 else cx = min(max(cx, BX0 + hw), BX1 - hw) end
	if hh * 2 >= BH then cy = (BY0 + BY1) / 2 else cy = min(max(cy, BY0 + hh), BY1 - hh) end
end

local function PickLevel()
	local ppu = scale * ppuFactor
	local L = 1
	for _, l in ipairs(LEVELS) do
		L = l
		if l >= ppu * 0.85 then break end
	end
	level = L
	return ppu
end

function Map.Refresh()
	if not built then return end
	local t0 = debugprofilestop()
	Clamp()
	left, top = cx - vw / 2 / scale, cy - vh / 2 / scale
	local ppu = PickLevel()
	zoom = scale / WorldFit()
	-- right out, the game's own world map; it dissolves into the stitched one over the first step in
	-- (the wheel's step animates, so the fade runs with the zoom: no jump from one picture to the other)
	worldAlpha = 1 - Smooth(zoom, 1.0, Map.ZOOM_STEP)
	atWorld = worldAlpha > 0.5
	UpdateTiles()
	local fit, deepest = Limits()
	FM.Terrain.Layout(left, top, scale, vw, vh, zoom, deepest / fit)
	FM.Labels.Layout(left, top, scale, vw, vh)                         -- AzerothVeil: the places' names (Labels.lua)
	FM.Names.Layout(left, top, scale, zoom, worldAlpha)                -- AzerothVeil: the continents' and seas' (Names.lua)
	FM.Caves.Layout(left, top, scale, vw, vh, zoom, deepest / fit)
	Map.PlaceWorld()
	FM.Fog.Layout(left, top, scale, vw, vh, worldAlpha >= 0.999)      -- AzerothVeil: the fog of war (Fog.lua)
	if worldAlpha < 0.999 then FM.Cities.Layout(left, top, scale, vw, vh, zoom) end
	FM.Isles.Layout(left, top, scale, vw, vh)
	FM.Routes.Layout(left, top, scale, vw, vh, zoom)
	FM.Vessels.Layout(left, top, scale, vw, vh)
	FM.Friends.Layout(left, top, scale, vw, vh)
	Map.PlaceHighlight()
	FM.Pins.Layout(left, top, scale, vw, vh, ppu, zoom)
	FM.AddonPins.Layout(left, top, scale, vw, vh, zoom)
	FM.Quests.Layout(left, top, scale, vw, vh, ppu, zoom)
	Map.UpdateUnits()
	local ms = debugprofilestop() - t0
	stats.refreshMs, stats.refreshes = ms, stats.refreshes + 1
	if ms > stats.maxMs then stats.maxMs = ms end
end

function Map.MarkDirty() dirty = true end
-- the view as last laid out: left, top, scale, vw, vh (a layer redrawing itself alone: Friends.lua)
function Map.ViewNow() return left, top, scale, vw, vh end

-- view px (from the view's top-left) <-> world units
function Map.CursorUnits()
	local x, y = GetCursorPosition()
	local es = view:GetEffectiveScale()
	local sx, sy = x / es - view:GetLeft(), view:GetTop() - y / es
	return left + sx / scale, top + sy / scale, sx, sy
end


---------------------------------------------------------------------------
-- Zoom (animated, about the cursor) and drag
---------------------------------------------------------------------------
local zoomTarget, zoomSX, zoomSY
local dragging, dragX, dragY, dragMoved

-- the world, or a land off it shown on its own (mapID: that land's; nil: back to the world, as it was)
function Map.SetAway(mapID)
	if mapID == awayMap then return end
	local r = mapID and Geo.Rect(mapID)
	if mapID and not r then return end
	if r then
		if not awayMap then worldView = { cx, cy, scale } end
		awayMap = mapID
		BX0, BY0, BX1, BY1 = r[1], r[3], r[2], r[4]
		cx, cy, scale = (r[1] + r[2]) / 2, (r[3] + r[4]) / 2, 0      -- (the whole land: Clamp fits it)
	else
		awayMap = nil
		BX0, BY0, BX1, BY1 = 0, 0, W, H
		if worldView then cx, cy, scale = worldView[1], worldView[2], worldView[3] end
		worldView = nil
	end
	BW, BH = BX1 - BX0, BY1 - BY0
	zoomTarget = nil
	if FM.Isles then FM.Isles.OnAway(awayMap) end
	dirty = true
end
function Map.AwayMap() return awayMap end

-- (a place on a land apart shows that land; one on the world, the world)
local function ModeFor(u, v)
	if u > W then
		local away = Geo.AwayAt(u, v)
		if away then Map.SetAway(away) end
	elseif awayMap then
		Map.SetAway(nil)
	end
end

function Map.SetView(u, v, unitsAcross)
	ModeFor(u, v)
	cx, cy = u, v
	if unitsAcross then scale = vw / unitsAcross end
	dirty = true
end


-- (the point at sx, sy of the view kept under it: from where the view is now, cx / cy, so a drag in the
-- same frame counts too)
local function ZoomAt(newScale, sx, sy)
	local u, v = cx - vw / 2 / scale + sx / scale, cy - vh / 2 / scale + sy / scale
	scale = newScale
	local fit, deepest = Limits()
	scale = min(max(scale, fit), deepest)
	cx, cy = u - sx / scale + vw / 2 / scale, v - sy / scale + vh / 2 / scale
end

local function OnWheel(_, delta)
	local _, _, sx, sy = Map.CursorUnits()
	local fit, deepest = Limits()
	local base = zoomTarget or scale
	zoomTarget = min(max(base * (Map.ZOOM_STEP ^ delta), fit), deepest)
	zoomSX, zoomSY = sx, sy
end

function Map.AnimateZoom(current, target, elapsed)
	local k = 1 - exp(-elapsed * 16)
	local from, to = log(current), log(target)
	local nextLog = from + (to - from) * k
	if math.abs(to - nextLog) < 0.002 then return target, nil end
	return exp(nextLog), target
end

local function OnMouseDown(_, button)
	FM.Dungeon.HideChooser()
	if button == "LeftButton" then FM.Spot.Hide() end
	if button == "LeftButton" then
		dragging, dragMoved = true, false
		dragX, dragY = GetCursorPosition()
	end
end

local function OnMouseUp(_, button)
	if button == "LeftButton" then
		local wasDrag = dragMoved
		dragging = false
		-- (a click on something with its own click over the map (a quest's button, a boat, another
		-- addon's icon) is that one's only: never also the icon under it, a dungeon's map say)
		local focus = GetMouseFoci and GetMouseFoci()[1] or GetMouseFocus and GetMouseFocus()
		if focus and focus ~= view then return end
		if not wasDrag then FM.Pins.Click(button) end
	elseif button == "RightButton" then
		-- (on a button of its own, a quest's: that one's, not the map's)
		local focus = GetMouseFoci and GetMouseFoci()[1] or GetMouseFocus and GetMouseFocus()
		if focus and focus ~= view then return end
		if FM.Pins.RightClick() then return end     -- (an icon: its waypoint)
		-- AzerothVeil: a quest's page open in the log: back to its list, not the menu
		if FM.QuestLog.Back() then return end
		-- (on a land apart, Zephras Isle: back to the world, as from a dungeon's map)
		if awayMap then FM.Isles.Back() return end
		-- (a bare spot: the menu to pin it or copy where it is; the wheel zooms out)
		local u, v = Map.CursorUnits()
		FM.Spot.Open(u, v)
	end
end

---------------------------------------------------------------------------
-- Player arrow, group, status line (only while the map is open)
---------------------------------------------------------------------------
local GetPlayerFacing = GetPlayerFacing
function Map.UpdatePlayer()
	local u, v = Geo.UnitUnits("player")
	-- (AzerothVeil: the player's coordinates, 5 times a second at most)
	if FM.db.playerCoords and coordText then
		local now = GetTime()
		if now - coordAt > 0.2 then
			coordAt = now
			local t = ZoneCoords(u, v, L["Player: %.1f, %.1f"])
			if t ~= coordPlayer then coordPlayer = t ShowCoords() end
		end
	end
	if not u then arrow:Hide() return end
	local sx, sy = (u - left) * scale, (v - top) * scale
	if sx < -20 or sy < -20 or sx > vw + 20 or sy > vh + 20 then arrow:Hide() return end
	arrow:SetPoint("CENTER", view, "TOPLEFT", sx, -sy)
	local f = FM.Plain(GetPlayerFacing())
	if f then arrow:SetRotation(f) end
	arrow:Show()
end

-- Where you died: the game's tombstone, while you're dead or a ghost (C_DeathInfo, as Blizzard's map
-- shows it). Looked up once on each death / revival / zoning (from your zone up its parent maps)
local corpse, corpseU, corpseV, corpseKnown
local CORPSE_ICONS = { "Navigation-Tombstone-Icon", "poi-graveyard-neutral" }
local CORPSE_SIZE = 20                 -- (the map's own icons' size: a dungeon's)
local function FindCorpse()
	corpseKnown, corpseU, corpseV = true, nil, nil
	if not (UnitIsDeadOrGhost and FM.Plain(UnitIsDeadOrGhost("player"))) then return end
	if not (C_DeathInfo and C_DeathInfo.GetCorpseMapPosition) then return end
	local m, guard = FM.Plain(C_Map.GetBestMapForUnit("player")), 0
	while m and m ~= 0 and guard < 5 do
		local ok, pos = pcall(C_DeathInfo.GetCorpseMapPosition, m)
		local x, y
		if ok and type(pos) == "table" then
			if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
		end
		if x and y and x > 0 and y > 0 and x < 1 and y < 1 then
			corpseU, corpseV = Geo.MapToUnits(m, x, y)
			if corpseU then return end
		end
		local info = C_Map.GetMapInfo(m)
		m = info and info.parentMapID
		guard = guard + 1
	end
end
function Map.UpdateCorpse()
	if not corpseKnown then FindCorpse() end
	if not corpseU then if corpse then corpse:Hide() end return end
	if not corpse then
		corpse = CreateFrame("Frame", nil, topLayer)
		corpse:SetFrameLevel(topLayer:GetFrameLevel() + 2)
		local t = corpse:CreateTexture(nil, "ARTWORK")
		t:SetAllPoints()
		-- (Blizzard's picture: its own corpse pin made once, unseen, and its picture and shape copied)
		local set
		local ok, ref = pcall(CreateFrame, "Frame", nil, nil, "CorpsePinTemplate")
		if ok and ref then
			ref:Hide()
			for _, r in ipairs({ ref:GetRegions() }) do
				if r.GetObjectType and r:GetObjectType() == "Texture" and (r:GetAtlas() or r:GetTexture()) then
					local atlas = r:GetAtlas()
					if atlas then t:SetAtlas(atlas) else t:SetTexture(r:GetTexture()) t:SetTexCoord(r:GetTexCoord()) end
					local w, h = ref:GetSize()
					if not (w and w > 0) then w, h = r:GetSize() end
					if w and w > 0 then corpse.aspect = (h or w) / w set = true end
					break
				end
			end
		end
		if not set then
			-- (else the game's tombstone)
			for _, a in ipairs(CORPSE_ICONS) do
				local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(a)
				if info and t:SetAtlas(a) ~= false then
					corpse.aspect = (info.height or 24) / (info.width or 24)
					set = true
					break
				end
			end
		end
		if not set then t:SetTexture("Interface\\Minimap\\POIIcons") t:SetTexCoord(0.5, 0.5625, 0, 0.0625) end
		corpse:EnableMouse(true)
		FM.Style.PassClicks(corpse)
		corpse:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(CORPSE or L["Your corpse"], 1, 1, 1)
			GameTooltip:Show()
		end)
		corpse:SetScript("OnLeave", GameTooltip_Hide)
	end
	-- (as big as a dungeon's icon, the tombstone's own shape kept)
	local size = CORPSE_SIZE * FM.Pins.BASE_SCALE * (FM.db.iconScale or 1)
	if corpse.fmSize ~= size then
		corpse.fmSize = size
		corpse:SetSize(size, size * (corpse.aspect or 1))
	end
	local sx, sy = (corpseU - left) * scale, (corpseV - top) * scale
	if sx < -20 or sy < -20 or sx > vw + 20 or sy > vh + 20 then corpse:Hide() return end
	corpse:ClearAllPoints()
	corpse:SetPoint("CENTER", topLayer, "TOPLEFT", sx, -sy)
	corpse:Show()
end
do
	local f = CreateFrame("Frame")
	for _, e in ipairs({ "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_ENTERING_WORLD", "CORPSE_POSITION_UPDATE" }) do
		pcall(f.RegisterEvent, f, e)
	end
	f:SetScript("OnEvent", function()
		corpseKnown = nil
		if Map.IsShown and Map.IsShown() then Map.MarkDirty() end
	end)
end

-- group members: placed on every frame with the map (so they move with it while it pans and zooms)
local group = {}
local PARTY, RAID = {}, {}
for i = 1, 4 do PARTY[i] = "party" .. i end
for i = 1, 40 do RAID[i] = "raid" .. i end
local function UpdateGroup()
	local n = GetNumGroupMembers()
	local raid = IsInRaid()
	local units = raid and RAID or PARTY
	local count = 0
	for i = 1, (raid and n or min(4, max(0, n - 1))) do
		local unit = units[i]
		-- (in a battleground the game may keep a member's identity and class secret: read only as plain values)
		if not FM.Plain(UnitIsUnit(unit, "player")) then
			local u, v = Geo.UnitUnits(unit)
			if u then
				local sx, sy = (u - left) * scale, (v - top) * scale
				if sx > -10 and sy > -10 and sx < vw + 10 and sy < vh + 10 then
					count = count + 1
					local d = group[count]
					if not d then
						d = topLayer:CreateTexture(nil, "OVERLAY", nil, 1)
						d:SetTexture(MEDIA .. "dot")
						d:SetSize(12, 12)
						group[count] = d
					end
					local class = FM.Plain((select(2, UnitClass(unit))))
					if d.class ~= class then
						d.class = class
						local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
						if c then d:SetVertexColor(c.r, c.g, c.b) else d:SetVertexColor(0.6, 0.8, 1) end
					end
					d:SetPoint("CENTER", topLayer, "TOPLEFT", sx, -sy)
					d.unit, d.sx, d.sy = unit, sx, sy
					d:Show()
				end
			end
		end
	end
	for i = count + 1, #group do group[i]:Hide() end
	group.n = count
end

-- Your group's names, as Blizzard's map gives them: over a member's dot (or several, close together),
-- a tooltip with each one's name in their class colour. dots: textures with .unit and .sx/.sy (where
-- they stand, from rel's top-left); n of them; cx, cy: the cursor, the same way. true when over one
local GROUP_NEAR = 8                       -- px from a dot's middle
local groupTip                             -- the names it shows now (rebuilt only when they change)
local tipNames = {}
local function AddGroupTipName(unit)
	local name = FM.Plain((UnitName(unit)))
	if type(name) ~= "string" then return false end
	local class = FM.Plain((select(2, UnitClass(unit))))
	local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	tipNames[#tipNames + 1] = { name, c and c.r or 1, c and c.g or 1, c and c.b or 1, 12 }
	return true
end

local function ShowGroupTip(x, y, rel)
	if #tipNames == 0 then Map.EndGroupTip() return false end
	local key = ""
	for _, l in ipairs(tipNames) do key = key .. l[1] .. ";" end
	if key ~= groupTip then
		groupTip = key
		S.ShowTip(nil, tipNames, x, y, rel)
	end
	return true
end

function Map.GroupTip(dots, n, cx, cy, rel)
	wipe(tipNames)
	local first
	for i = 1, n do
		local d = dots[i]
		if d.unit and d:IsShown() and (d.sx - cx) ^ 2 + (d.sy - cy) ^ 2 <= GROUP_NEAR * GROUP_NEAR then
			if AddGroupTipName(d.unit) then first = first or d end
		end
	end
	return ShowGroupTip(first and first.sx + 8, first and -first.sy + 4, rel)
end

-- UnitPositionFrame supplies the units under the cursor on a battleground's map.
function Map.GroupTipForUnits(cx, cy, rel, ...)
	wipe(tipNames)
	for i = 1, select("#", ...) do
		local unit = FM.Plain((select(i, ...)))
		if type(unit) == "string" and unit ~= "player" then AddGroupTipName(unit) end
	end
	return ShowGroupTip(cx + 8, -cy + 4, rel)
end

function Map.EndGroupTip()
	if groupTip then groupTip = nil S.HideTip() end
end

-- AzerothVeil: a marker put on a spot by a module (a dungeon quest's start: Modules/Dungeons.lua): the
-- quest's "!" in a pulsing gold light, its tooltip (a title and a line); a click takes it off. One at a
-- time; nothing drawn or run without one (its light's animation only while it's shown).
local mark, markU, markV, markTitle, markSub
local MEDIA = "Interface\\AddOns\\AzerothVeil\\Media\\"

function Map.SetMark(mapID, x, y, title, sub)
	markU, markV = Geo.MapToUnits(mapID, x, y)
	markTitle, markSub = title, sub
	dirty = true
end

function Map.ClearMark()
	markU, markV = nil, nil
	if mark then mark.anim:Stop() mark:Hide() end
end

local function UpdateMark()
	if not markU then if mark then mark:Hide() end return end
	if not mark then
		mark = CreateFrame("Button", nil, topLayer)
		mark:SetFrameLevel(topLayer:GetFrameLevel() + 3)
		mark:SetSize(26, 26)
		mark.glow = mark:CreateTexture(nil, "BACKGROUND")
		mark.glow:SetTexture(MEDIA .. "glow")
		mark.glow:SetBlendMode("ADD")
		mark.glow:SetVertexColor(1, 0.8, 0.2)
		mark.glow:SetSize(70, 70)
		mark.glow:SetPoint("CENTER")
		mark.ring = mark:CreateTexture(nil, "BORDER")
		mark.ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
		mark.ring:SetTexCoord(0, 0.6, 0, 0.6)
		mark.ring:SetBlendMode("ADD")
		mark.ring:SetSize(44, 44)
		mark.ring:SetPoint("CENTER")
		mark.icon = mark:CreateTexture(nil, "ARTWORK")
		mark.icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
		mark.icon:SetAllPoints()
		mark.anim = mark.glow:CreateAnimationGroup()
		local a = mark.anim:CreateAnimation("Alpha")
		a:SetFromAlpha(1) a:SetToAlpha(0.3) a:SetDuration(0.7)
		mark.anim:SetLooping("BOUNCE")
		mark:RegisterForClicks("LeftButtonUp")
		mark:SetScript("OnClick", function() GameTooltip_Hide() Map.ClearMark() end)
		mark:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(markTitle or "", 1, 0.82, 0)
			if markSub then GameTooltip:AddLine(markSub, 1, 1, 1) end
			GameTooltip:AddLine(L["Click: take this marker off."], 0.6, 0.6, 0.6)
			GameTooltip:Show()
		end)
		mark:SetScript("OnLeave", GameTooltip_Hide)
	end
	local sx, sy = (markU - left) * scale, (markV - top) * scale
	if sx < -30 or sy < -30 or sx > vw + 30 or sy > vh + 30 then mark:Hide() return end
	mark:ClearAllPoints()
	mark:SetPoint("CENTER", topLayer, "TOPLEFT", sx, -sy)
	mark:Show()
	if not mark.anim:IsPlaying() then mark.anim:Play() end
end

-- the player and the group, every frame (a handful of positions: next to nothing)
function Map.UpdateUnits()
	Map.UpdatePlayer()
	Map.UpdateCorpse()
	UpdateMark()                                   -- AzerothVeil
	UpdateGroup()
end

-- The zone under the cursor: lit as Blizzard's continent map lights it (its own highlight art), and
-- named at the top in the middle on a small card of our own (flat, dark, an accent line under it): its
-- name, its level range on a pill in MapUtils' colour, the area under the cursor and, if turned on,
-- its fishing skill under it
local hoverZone, highlight, hlRect
local card, cardName, cardPill, cardLevel, cardArea, cardExtra
local CARD_TOP = 12                      -- px from the view's top
local PAD_X, PAD_Y, GAP = 14, 7, 2
local zoneLines = {}                     -- the lines under the area (it changes by itself)
local areaText, areaAt = nil, 0

-- (the card as big as what it says, its name and pill centred on one line)
local function LayoutCard()
	local nameW, nameH = cardName:GetStringWidth(), cardName:GetStringHeight()
	local rowW = nameW
	if cardPill:IsShown() then
		local pw, ph = cardLevel:GetStringWidth() + 12, cardLevel:GetStringHeight() + 4
		cardPill:SetSize(pw, ph)
		rowW = rowW + 7 + pw
	end
	local w, y = rowW, PAD_Y + nameH
	for i = 1, 2 do
		local fs = i == 1 and cardArea or cardExtra
		if fs:IsShown() then
			fs:ClearAllPoints()
			fs:SetPoint("TOP", card, "TOP", 0, -(y + GAP))
			y = y + GAP + fs:GetStringHeight()
			w = max(w, fs:GetStringWidth())
		end
	end
	local cw = w + 2 * PAD_X
	card:SetSize(cw, y + PAD_Y + 1)
	cardName:ClearAllPoints()
	cardName:SetPoint("TOPLEFT", card, "TOPLEFT", (cw - rowW) / 2, -PAD_Y)
end

-- MapUtils' colour for a level range: the quest colour of its low end while under it, of its top
-- less two once past it, else "difficult" (orange)
local function LevelColor(lo, hi)
	local pl = UnitLevel("player") or 1
	local r, g, b = 1, 0.82, 0
	local c
	if pl < lo then c = GetQuestDifficultyColor and GetQuestDifficultyColor(lo)
	elseif pl > hi then c = GetQuestDifficultyColor and GetQuestDifficultyColor(hi - 2)
	else c = QuestDifficultyColors and QuestDifficultyColors.difficult end
	if type(c) == "table" and c.r then r, g, b = c.r, c.g, c.b end
	return r, g, b
end

local function ShowZoneText()
	cardArea:SetText(areaText or "")
	cardArea:SetShown(areaText ~= nil)
	local extra = table.concat(zoneLines, "\n")
	cardExtra:SetText(extra)
	cardExtra:SetShown(extra ~= "")
	LayoutCard()
end

-- the named area under the cursor (Blizzard's explored areas there), a few times a second at most
local vec
-- AzerothVeil: only once the zone's highlight is gone (zoomed in past it, Map.PlaceHighlight): while the zones light
-- up, the card names the zone alone
local function HighlightGone() return 1 - Smooth(zoom, 5, 9) <= 0.01 end
local function UpdateArea(mapID, u, v)
	if not card:IsShown() then return end
	local text
	local cr = mapID and not atWorld and HighlightGone() and Geo.Rect(mapID)
	if cr and C_MapExplorationInfo and C_MapExplorationInfo.GetExploredAreaIDsAtPosition and CreateVector2D then
		vec = vec or CreateVector2D(0, 0)
		vec:SetXY((u - cr[1]) / (cr[2] - cr[1]), (v - cr[3]) / (cr[4] - cr[3]))
		local ok, ids = pcall(C_MapExplorationInfo.GetExploredAreaIDsAtPosition, mapID, vec)
		if ok and type(ids) == "table" then
			local zone = card.zoneName
			for _, id in ipairs(ids) do
				local name = C_Map.GetAreaInfo(id)
				if name and name ~= "" and name ~= zone then text = name break end
			end
		end
	end
	if text ~= areaText then
		areaText = text
		ShowZoneText()
	end
end

local function ZoneLevels(mapID)
	local l = FM.ZONE_LEVELS and FM.ZONE_LEVELS[mapID]
	if l then return l[1], l[2], l[3] end
	if C_Map.GetMapLevels then
		local ok, lo, hi = pcall(C_Map.GetMapLevels, mapID)
		lo, hi = FM.Plain(lo), FM.Plain(hi)
		if ok and lo and hi and lo > 0 then return lo, hi end
	end
end

-- Blizzard's highlight for what's at (u, v) on a map (a zone on its continent; a continent on the
-- world), as a rectangle in world units
local WORLD_RECT = { 0, W, 0, H }
local function ReadHighlight(mapID, u, v)
	local cr = mapID == FM.WORLD and WORLD_RECT or Geo.Rect(mapID)
	if not cr then return end
	local nx, ny = (u - cr[1]) / (cr[2] - cr[1]), (v - cr[3]) / (cr[4] - cr[3])
	local file, atlas, px, py, tw, th, sx, sy = C_Map.GetMapHighlightInfoAtPosition(mapID, nx, ny)
	if not ((file and file > 0) or atlas) or not tw or tw <= 0 then return end
	local cw, ch = cr[2] - cr[1], cr[4] - cr[3]
	if atlas then highlight:SetAtlas(atlas) else highlight:SetTexture(file, nil, nil, "TRILINEAR") end
	if not atlas then highlight:SetTexCoord(0, px, 0, py) end
	return { cr[1] + sx * cw, cr[3] + sy * ch, tw * cw, th * ch }
end

function Map.PlaceHighlight()
	if not highlight then return end
	local a = 1 - Smooth(zoom, 5, 9)      -- (Blizzard's highlight art is the continent's: gone up close)
	if not hlRect or a <= 0.01 or not FM.db.hoverHighlight then highlight:Hide() return end
	highlight:SetPoint("TOPLEFT", highlight:GetParent(), "TOPLEFT", (hlRect[1] - left) * scale, (top - hlRect[2]) * scale)
	highlight:SetSize(hlRect[3] * scale, hlRect[4] * scale)
	highlight:SetAlpha(a)
	highlight:Show()
end

-- AzerothVeil: the zone's fishing skill in the colour of how it suits yours, as the game colours what you gather:
-- red under it (its fish get away), then orange, yellow, green, grey the farther above it you are; plain if you
-- don't fish. Your skill read as the Icons module reads it (C_SkillInfo by skill line, else GetProfessions)
local FISHING_LINE = 356
local function FishingSkill()
	local byID = C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID
	if byID then
		local ok, info = pcall(byID, FISHING_LINE)
		local rank = ok and type(info) == "table" and tonumber(FM.Plain(info.rank))
		if rank and rank > 0 then return rank end
	end
	if GetProfessions and GetProfessionInfo then
		local ok, _, _, _, fishing = pcall(GetProfessions)
		if ok and fishing then
			local ok2, _, _, rank, _, _, _, line = pcall(GetProfessionInfo, fishing)
			rank = ok2 and tonumber(FM.Plain(rank))
			if rank and rank > 0 and (not line or tonumber(FM.Plain(line)) == FISHING_LINE) then return rank end
		end
	end
end
local function FishingText(want)
	local need = tonumber(tostring(want):match("%d+"))
	local mine = need and FishingSkill()
	local text = (L["Fishing: %s"]):format(want)
	if not mine then return text end
	local c = mine < need and "ff1a1a" or mine < need + 25 and "ff8040" or mine < need + 50 and "ffff00"
		or mine < need + 100 and "40bf40" or "808080"
	return "|cff" .. c .. text .. "|r"
end

local function SetZone(mapID, name, cont, u, v)
	if mapID == hoverZone then return end
	hoverZone = mapID
	hlRect = nil
	areaText = nil
	wipe(zoneLines)
	if mapID and name and name ~= "" then
		card.zoneName = name
		cardName:SetText(name)
		local lo, hi = ZoneLevels(mapID)
		if lo and FM.db.zoneLevels ~= false then      -- (AzerothVeil: the Map module's "Levels of zones")
			local r, g, b = LevelColor(lo, hi)
			cardLevel:SetText(lo == hi and tostring(lo) or ("%d-%d"):format(lo, hi))
			cardLevel:SetTextColor(r, g, b)
			cardPill.bg:SetVertexColor(r, g, b, 0.16)
			cardPill.edge:SetVertexColor(r, g, b, 0.55)
			cardPill:Show()
		else
			cardPill:Hide()
		end
		local fish = FM.db.zoneFishing and FM.ZONE_FISHING and FM.ZONE_FISHING[mapID]
		if fish then zoneLines[#zoneLines + 1] = FishingText(fish) end
		ShowZoneText()
		card:Show()
		areaAt = 0
		if cont then hlRect = ReadHighlight(cont, u, v) end
	else
		card:Hide()
	end
	Map.PlaceHighlight()
end

-- (an option changed what's written for a zone: write it again on the next move)
function Map.ResetHover() hoverZone = false end

local function UpdateHover()
	local u, v = Map.CursorUnits()
	if atWorld then
		-- (as the game's world map: the continent under the cursor, lit with its own highlight)
		local info = C_Map.GetMapInfoAtPosition(FM.WORLD, u / W, v / H)
		local id = info and info.mapID ~= FM.WORLD and info.mapID or nil
		SetZone(id, info and info.name, id and FM.WORLD, u, v)
	else
		local mapID, name, cont = Geo.ZoneAt(u, v)
		SetZone(mapID, name, cont, u, v)
		-- (AzerothVeil: the cursor's coordinates)
		if FM.db.cursorCoords and coordText then
			local t = ZoneCoords(u, v, L["Cursor: %.1f, %.1f"])
			if t ~= coordCursor then coordCursor = t ShowCoords() end
		end
		local now = GetTime()
		if mapID and now - areaAt > 0.1 then
			areaAt = now
			UpdateArea(mapID, u, v)
		end
	end
	-- (over a button of its own, a quest's, a boat, a friend: that one's tooltip, not the icons' under it)
	local focus = GetMouseFoci and GetMouseFoci()[1] or GetMouseFocus and GetMouseFocus()
	if focus and focus ~= view then
		FM.Pins.Hover(true)
		-- (a moving boat or zeppelin over a harbor or tower: the dock under it still shows its routes)
		if FM.Vessels.Owns(focus) and FM.Pins.UnderCursor() > 0 then
			FM.Routes.Hover(nil, nil, nil, true)
		else
			FM.Routes.Hover(nil)
		end
		Map.EndGroupTip()
		return
	end
	-- (over a group member's dot: their name, before the icons under it)
	local _, _, sx, sy = Map.CursorUnits()
	if Map.GroupTip(group, group.n or 0, sx, sy, topLayer) then
		FM.Pins.Hover(true)
		FM.Routes.Hover(nil)
		return
	end
	local pinned = FM.Pins.Hover()
	FM.Routes.Hover(not pinned and u or nil, v, scale, pinned)
end

---------------------------------------------------------------------------
-- The per-frame driver: runs only while the window is shown, and only does work when
-- something moved (a drag, a zoom, the player, the cursor)
---------------------------------------------------------------------------
local lastMX, lastMY
local fadeOn = false

local function OnUpdate(_, elapsed)
	-- (inside a dungeon, its map is up over the world: only it moves; the world rests, unhovered)
	if FM.Dungeon.Active() then
		local start = debugprofilestop()
		if FM.Dungeon.Tick(elapsed) then
			local ms = debugprofilestop() - start
			stats.battlegroundMs = ms
			stats.battlegroundMax = max(ms, stats.battlegroundMax or 0)
			stats.battlegroundFrames = (stats.battlegroundFrames or 0) + 1
		end
		if lastMX then
			lastMX = nil
			SetZone(nil)
			FM.Pins.Hover(true)
			FM.Routes.Hover(nil)
			Map.EndGroupTip()
		end
		return
	end
	local changed = false
	if dragging then
		local x, y = GetCursorPosition()
		if x ~= dragX or y ~= dragY then
			local es = view:GetEffectiveScale()
			local dx, dy = (x - dragX) / es, (y - dragY) / es
			if dragMoved or dx * dx + dy * dy > 9 then
				dragMoved = true
				cx, cy = cx - dx / scale, cy + dy / scale
				dragX, dragY = x, y
				changed = true
			end
		end
		-- (zooming while dragging: about the cursor where it is now, so the ground held stays under it)
		if zoomTarget then
			local es = view:GetEffectiveScale()
			zoomSX, zoomSY = x / es - view:GetLeft(), view:GetTop() - y / es
		end
	end
	if zoomTarget then
		local nextScale
		nextScale, zoomTarget = Map.AnimateZoom(scale, zoomTarget, elapsed)
		ZoomAt(nextScale, zoomSX, zoomSY)
		changed = true
	end
	if changed or dirty then
		dirty = false
		Map.Refresh()
	else
		Map.UpdateUnits()
	end
	FM.Quests.Tick(elapsed)
	FM.Routes.Tick(elapsed)
	FM.Vessels.Tick(elapsed)
	FM.Pins.Tick()
	FM.AddonPins.Tick(elapsed)
	FM.Terrain.Tick(elapsed)
	FM.Friends.Tick()
	-- the cursor: every frame it moves or the map moves under it (tooltips stay on their pins)
	if view:IsMouseOver() then
		local x, y = GetCursorPosition()
		local moved = x ~= lastMX or y ~= lastMY
		if moved or changed then
			lastMX, lastMY = x, y
			UpdateHover()
		end
	elseif lastMX then
		lastMX = nil
		SetZone(nil)
		FM.Pins.Hover(true)
		FM.Routes.Hover(nil)
		Map.EndGroupTip()
		if coordCursor then coordCursor = nil ShowCoords() end      -- (AzerothVeil)
	end
	if FM.db.fadeMoving then
		local m = IsPlayerMoving() and not frame:IsMouseOver()
		if m ~= fadeOn then
			fadeOn = m
			frame:SetAlpha(m and FM.db.fadeAlpha or 1)
		end
	elseif fadeOn then
		fadeOn = false
		frame:SetAlpha(1)
	end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
-- The map always has the world's own shape (3:2): never a strip of empty space round it. Resizing
-- scales it; the quest log docks beside it (the window grows, the map keeps its shape).
local ASPECT = W / H
local MIN_MAP_W = 540
local sideWidth = 0
local sizing

-- where the window's insides begin: modern, a 1 px border and the header; classic, Blizzard's frame and
-- the inset round the map (Style.FRAME)
local function Edges()
	if S.classic then return S.FRAME end
	return { l = 1, r = 1, t = HEADER + 1, b = 1, gap = 0 }
end
Map.Edges = Edges

local function MaxMapWidth()
	local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
	local E = Edges()
	return max(MIN_MAP_W, min(sw - sideWidth - E.l - E.r - 2, (sh - E.t - E.b - 2) * ASPECT))
end

local function ApplySize()
	local mw = min(max(FM.db.window.mapW or 960, MIN_MAP_W), MaxMapWidth())
	local mh = mw / ASPECT
	view:SetSize(mw, mh)
	local E = Edges()
	frame:SetSize(mw + E.l + E.r + sideWidth, mh + E.t + E.b)
end

-- the window hangs from its top-left corner, so docking the log or resizing never moves the map
local function SaveWindow()
	local w = FM.db.window
	w.left, w.top = frame:GetLeft(), frame:GetTop()
	if w.left then
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", w.left, w.top)
	end
end

function Map.ApplyWindow()
	if not frame then return end
	local w = FM.db.window
	ApplySize()
	frame:ClearAllPoints()
	if w.left then
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", w.left, w.top)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
	end
end

-- room beside the map for the quest log
function Map.SetSideWidth(px)
	sideWidth = px > 0 and px + Edges().gap or 0     -- (classic: room for the insets' borders between them)
	if not frame then return end
	if frame:GetLeft() then SaveWindow() end
	ApplySize()
end

-- Escape closes it: heard by a key catcher of its own, never through the game's UISpecialFrames (a name an
-- addon puts in that list taints the game's Escape handling, and Escape stopping a cast gets blocked). Every
-- other key goes on to the game. Made as the addon loads: letting keys through can't be set in combat, while
-- showing and hiding it can, so the map opened in a fight (even first built then) closes with Escape too. In
-- combat an addon can't keep a key from the game: Escape closes it and goes on (the game's menu as well)
local keys = CreateFrame("Frame", nil, UIParent)
keys:SetFrameStrata("HIGH")
keys:SetSize(1, 1)
keys:SetPoint("TOPLEFT")
keys:Hide()
local function TakeKeys()
	keys:EnableKeyboard(true)
	keys:SetPropagateKeyboardInput(true)
end
if InCombatLockdown() then          -- (a reload in a fight: as it ends)
	local wait = CreateFrame("Frame")
	wait:RegisterEvent("PLAYER_REGEN_ENABLED")
	wait:SetScript("OnEvent", function(self) self:UnregisterAllEvents() TakeKeys() end)
else
	TakeKeys()
end
keys:SetScript("OnKeyDown", function(self, key)
	if InCombatLockdown() then
		if key == "ESCAPE" then Map.Hide() end
		return
	end
	if key == "ESCAPE" then
		self:SetPropagateKeyboardInput(false)
		Map.Hide()
		-- (every key the game's again, as soon as this one's done)
		C_Timer.After(0, function() if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end end)
	else
		self:SetPropagateKeyboardInput(true)
	end
end)
-- (keys the game's whatever closed it last: an Escape that closed it in the frame combat began)
keys:SetScript("OnShow", function(self) if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end end)

local function Build()
	built = true
	-- classic: Blizzard's own window (its metal frame, title bar, round portrait and close button), as the
	-- game's Map & Quest Log is drawn; modern: our flat one
	local blizz = false
	if S.classic then
		local ok, f = pcall(CreateFrame, "Frame", "AzerothVeilFrame", UIParent, "PortraitFrameTemplate")
		if ok and f then frame, blizz = f, true end
	end
	frame = frame or CreateFrame("Frame", "AzerothVeilFrame", UIParent)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:Hide()
	if blizz then
		S.used = true
		if frame.SetTitle then frame:SetTitle("AzerothVeil")
		elseif frame.TitleText then frame.TitleText:SetText("AzerothVeil") end
		-- (no portrait: Blizzard's frame without one, its corner closed as its own windows without one are)
		if ButtonFrameTemplate_HidePortrait then pcall(ButtonFrameTemplate_HidePortrait, frame) end
		if frame.NineSlice and NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
			pcall(NineSliceUtil.ApplyLayoutByName, frame.NineSlice, "ButtonFrameTemplateNoPortrait")
		end
		local pc = frame.PortraitContainer or frame.portrait
		if pc then pc:Hide() end
	else
		S.Panel(frame)
	end
	-- header: drag to move (classic: the title bar, right of the portrait)
	header = CreateFrame("Frame", nil, frame)
	if blizz then
		header:SetPoint("TOPLEFT", 8, 0)
		header:SetPoint("TOPRIGHT", -34, 0)          -- (clear of the close button)
		header:SetHeight(22)
		-- (over the frame's own border, title bar and close button: their frames sit above the window's)
		local top = frame:GetFrameLevel()
		for _, k in ipairs({ "NineSlice", "TitleContainer", "CloseButton", "PortraitContainer", "TopTileStreaks" }) do
			local part = frame[k]
			if part and part.GetFrameLevel then top = math.max(top, part:GetFrameLevel()) end
		end
		header:SetFrameLevel(top + 2)
	else
		header:SetPoint("TOPLEFT", S.INSET, -S.INSET)
		header:SetPoint("TOPRIGHT", -S.INSET, -S.INSET)
		header:SetHeight(HEADER)
	end
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", function() frame:StartMoving() end)
	header:SetScript("OnDragStop", function() frame:StopMovingOrSizing() SaveWindow() end)
	local headerBg = header:CreateTexture(nil, "BACKGROUND")
	headerBg:SetTexture(S.WHITE)
	headerBg:SetVertexColor(S.BG[1], S.BG[2], S.BG[3], 1)
	headerBg:SetAllPoints()
	-- (one rule along the header's bottom, the whole window wide: exactly where the map and the quest
	-- log begin, parting both from the bar)
	local headerRule = header:CreateTexture(nil, "BORDER")
	headerRule:SetTexture(S.WHITE)
	headerRule:SetVertexColor(1, 1, 1, 0.14)
	headerRule:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
	headerRule:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
	headerRule:SetHeight(1)
	local title = S.Text(header, 13, S.ACCENT)
	title:SetText("AzerothVeil")
	local close
	if blizz then
		-- (classic: the title bar is the frame's own; its title, its close button)
		headerBg:Hide()
		headerRule:Hide()
		title:Hide()
		close = frame.CloseButton or CreateFrame("Button", nil, frame, "UIPanelCloseButton")
		if not frame.CloseButton then close:SetPoint("TOPRIGHT", 0, 0) end
		close:SetScript("OnClick", function() Map.Hide() end)
		-- (the header's buttons, right of the title, left of the close button)
		close = { fm = true }
	elseif S.classic then
		-- (Blizzard's window couldn't be made: the dialog look, its own close button)
		headerBg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background-Dark")
		headerBg:SetVertexColor(1, 1, 1, 1)
		headerRule:SetVertexColor(0.85, 0.7, 0.4, 0.6)
		close = CreateFrame("Button", nil, header, "UIPanelCloseButton")
		close:SetSize(28, 28)
		close:SetPoint("RIGHT", -3, 0)
		close:SetScript("OnClick", function() Map.Hide() end)
	else
		close = S.Button(header, "", 26, 20, function() Map.Hide() end)
		close:SetPoint("RIGHT", -3, 0)
		close.tip = L["Close (Esc)"]
		local cross = close:CreateTexture(nil, "ARTWORK")
		cross:SetSize(12, 12)
		cross:SetPoint("CENTER")
		cross:SetTexture(MEDIA .. "close")
		cross:SetVertexColor(S.TEXT[1], S.TEXT[2], S.TEXT[3], 0.85)
		close:HookScript("OnEnter", function(self)
			self.bg:SetVertexColor(0.85, 0.2, 0.2, 0.55)
			cross:SetVertexColor(1, 1, 1, 1)
		end)
		close:HookScript("OnLeave", function()
			cross:SetVertexColor(S.TEXT[1], S.TEXT[2], S.TEXT[3], 0.85)
		end)
	end
	-- (AzerothVeil: the options' and Questie's buttons are in the map's top left corner now: below, with the
	-- map's other buttons)
	-- inside a dungeon: between its map and the world's (shown only there)
	local dungeon = S.Button(header, L["Dungeon"], 70, 20, function() FM.Dungeon.TogglePeek() end)
	if close.fm then dungeon:SetPoint("RIGHT", 0, 0) else dungeon:SetPoint("RIGHT", close, "LEFT", -4, 0) end
	dungeon.tip = { L["Dungeon / World"], L["Inside a dungeon: its map, or the world's."] }
	dungeon:Hide()
	Map.dungeonButton = dungeon

	-- the map
	view = CreateFrame("Frame", nil, frame)
	local E = Edges()
	view:SetPoint("TOPLEFT", E.l, -E.t)
	-- (the header's name centred over the map itself, not over the map and the quest log beside it)
	title:SetPoint("CENTER", view, "TOP", 0, HEADER / 2)
	view:SetSize(960, 640)
	if S.classic then
		-- (classic: the map in Blizzard's inset border, as its own map sits in its window)
		local ok, inset = pcall(CreateFrame, "Frame", nil, frame, "InsetFrameTemplate")
		if ok and inset then
			inset:SetPoint("TOPLEFT", view, "TOPLEFT", -3, 3)
			inset:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", 3, -3)
			inset:SetFrameLevel(frame:GetFrameLevel() + 1)
		end
		view:SetFrameLevel(frame:GetFrameLevel() + 3)
	end
	view:SetClipsChildren(true)
	view:EnableMouse(true)
	view:EnableMouseWheel(true)
	local sea = view:CreateTexture(nil, "BACKGROUND", nil, -8)   -- past the world's edge
	sea:SetTexture(S.WHITE)
	sea:SetVertexColor(0.05, 0.055, 0.06)
	sea:SetAllPoints()
	tileLayer = CreateFrame("Frame", nil, view)
	tileLayer:SetAllPoints()
	-- zoomed right out: the game's own world map art (built the first time it shows)
	worldArt = CreateFrame("Frame", nil, view)
	worldArt:SetSize(W, H)
	worldArt:SetFrameLevel(tileLayer:GetFrameLevel() + 4)   -- (over the cities)
	worldArt:Hide()
	-- the cities' own maps (and their zones' banners for them) over the stitched art
	-- up close, the terrain as the minimap draws it (Terrain.lua), over the painted map
	local terrainLayer = CreateFrame("Frame", nil, view)
	terrainLayer:SetAllPoints()
	terrainLayer:SetFrameLevel(tileLayer:GetFrameLevel() + 1)
	FM.Terrain.Init(terrainLayer)
	-- AzerothVeil: the fog of war (Fog.lua, the Map module): unexplored land as Blizzard's map shows it, under
	-- the icons and the world's art; it fades out as the terrain comes in up close (Fog.SetTerrain)
	local fogLayer = CreateFrame("Frame", nil, view)
	fogLayer:SetAllPoints()
	fogLayer:SetFrameLevel(tileLayer:GetFrameLevel() + 2)
	FM.Fog.Init(fogLayer)
	cityLayer = CreateFrame("Frame", nil, view)
	cityLayer:SetAllPoints()
	cityLayer:SetFrameLevel(tileLayer:GetFrameLevel() + 2)
	FM.Cities.Init(cityLayer)
	-- AzerothVeil: the places' names over the minimap's terrain up close (Labels.lua), over the cities and caves
	local labelLayer = CreateFrame("Frame", nil, view)
	labelLayer:SetAllPoints()
	labelLayer:SetFrameLevel(tileLayer:GetFrameLevel() + 5)
	FM.Labels.Init(labelLayer)
	-- AzerothVeil: the continents' and seas' names zoomed out (Names.lua), with the places'
	local namesLayer = CreateFrame("Frame", nil, view)
	namesLayer:SetAllPoints()
	namesLayer:SetFrameLevel(tileLayer:GetFrameLevel() + 5)
	FM.Names.Init(namesLayer)
	-- the hovered zone's highlight (Blizzard's own art for it, added on, as its map does), over cities too
	local hlLayer = CreateFrame("Frame", nil, view)
	hlLayer:SetAllPoints()
	hlLayer:SetFrameLevel(tileLayer:GetFrameLevel() + 5)
	highlight = hlLayer:CreateTexture(nil, "ARTWORK")
	highlight:SetBlendMode("ADD")
	highlight:Hide()
	-- boat and zeppelin routes
	local routeLayer = CreateFrame("Frame", nil, view)
	routeLayer:SetAllPoints()
	routeLayer:SetFrameLevel(tileLayer:GetFrameLevel() + 6)
	FM.Routes.Init(routeLayer)
	-- quest areas (Blizzard's blobs) over the art, then our pins, then Blizzard's quest buttons
	local blobLayer = CreateFrame("Frame", nil, view)
	blobLayer:SetAllPoints()
	blobLayer:SetFrameLevel(tileLayer:GetFrameLevel() + 7)
	-- Questie's patrol paths (Quests.lua), under the icons
	local pathLayer = CreateFrame("Frame", nil, view)
	pathLayer:SetAllPoints()
	pathLayer:SetFrameLevel(tileLayer:GetFrameLevel() + 12)
	Map.pathLayer = pathLayer
	pinLayer = CreateFrame("Frame", nil, view)
	pinLayer:SetAllPoints()
	pinLayer:SetFrameLevel(tileLayer:GetFrameLevel() + 14)
	-- other addons' icons (AddonPins.lua), over ours
	FM.AddonPins.Init(view, tileLayer:GetFrameLevel() + 15)
	-- boats and zeppelins where they are now
	local vesselLayer = CreateFrame("Frame", nil, view)
	vesselLayer:SetAllPoints()
	vesselLayer:SetFrameLevel(tileLayer:GetFrameLevel() + 16)
	FM.Vessels.Init(vesselLayer)
	-- friends and guild members where they stand (Friends.lua), over the boats
	local friendLayer = CreateFrame("Frame", nil, view)
	friendLayer:SetAllPoints()
	friendLayer:SetFrameLevel(tileLayer:GetFrameLevel() + 16)
	FM.Friends.Init(friendLayer)
	local questLayer = CreateFrame("Frame", nil, view)
	questLayer:SetAllPoints()
	questLayer:SetFrameLevel(tileLayer:GetFrameLevel() + 18)
	topLayer = CreateFrame("Frame", nil, view)
	topLayer:SetAllPoints()
	topLayer:SetFrameLevel(tileLayer:GetFrameLevel() + 30)
	-- the lands off the world map (Zephras Isle): their art at their own place, under every icon; their
	-- name and the right-click's hint over them (Isles.lua)
	local isleLayer = CreateFrame("Frame", nil, view)
	isleLayer:SetAllPoints()
	isleLayer:SetFrameLevel(tileLayer:GetFrameLevel() + 3)
	FM.Isles.Init(isleLayer, topLayer)
	-- caves and underground places, surfacing up close over the terrain (Caves.lua)
	local caveLayer = CreateFrame("Frame", nil, view)
	caveLayer:SetAllPoints()
	caveLayer:SetFrameLevel(tileLayer:GetFrameLevel() + 3)
	caveLayer:SetClipsChildren(true)
	FM.Caves.Init(caveLayer)
	Map.blobLayer, Map.questLayer = blobLayer, questLayer
	-- The player arrow must cover the corpse pin and the selected quest button's child display.
	local playerLayer = CreateFrame("Frame", nil, view)
	playerLayer:SetAllPoints()
	local playerLevel = max(topLayer:GetFrameLevel() + 3, questLayer:GetFrameLevel() + FM.Quests.PLAYER_PIN_LEVEL)
	playerLayer:SetFrameLevel(playerLevel)
	arrow = playerLayer:CreateTexture(nil, "OVERLAY")
	if not (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("UI-WorldMapArrow") and arrow:SetAtlas("UI-WorldMapArrow") ~= false) then
		arrow:SetTexture("Interface\\WorldMap\\WorldMapArrow")
	end
	arrow:SetSize(27, 27)
	arrow:Hide()
	-- An instance's map covers the entire world pin stack. Keep its shared controls above the backdrop.
	local instanceLevel = playerLevel + 1
	FM.Dungeon.Init(view, instanceLevel)

	-- the hovered zone's name and levels, top centre (as the world map's area label)
	-- (in the game's own font, like every text of ours: Style.Font)
	-- the zone under the cursor: its name (yellow, its level range in MapUtils' colour) at the top in
	-- the middle, the rest (white) under it
	card = CreateFrame("Frame", nil, topLayer)
	card:SetFrameLevel(topLayer:GetFrameLevel() + 4)
	card:SetPoint("TOP", view, "TOP", 0, -CARD_TOP)
	local cbg = card:CreateTexture(nil, "BACKGROUND")
	cbg:SetTexture(S.WHITE)
	cbg:SetVertexColor(S.BG[1], S.BG[2], S.BG[3], 0.82)
	cbg:SetAllPoints()
	local cline = card:CreateTexture(nil, "ARTWORK")
	cline:SetTexture(S.WHITE)
	cline:SetVertexColor(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 0.9)
	cline:SetPoint("BOTTOMLEFT")
	cline:SetPoint("BOTTOMRIGHT")
	cline:SetHeight(2)
	-- (AzerothVeil: the card's texts half as big again as PerfectMap's)
	cardName = S.Text(card, 24, { 0.97, 0.95, 0.9 })
	cardName:SetWordWrap(false)
	cardPill = CreateFrame("Frame", nil, card)
	cardPill:SetPoint("LEFT", cardName, "RIGHT", 7, 0)
	cardPill.bg = cardPill:CreateTexture(nil, "BACKGROUND", nil, 1)
	cardPill.bg:SetTexture(S.WHITE)
	cardPill.bg:SetAllPoints()
	cardPill.edge = cardPill:CreateTexture(nil, "ARTWORK")
	cardPill.edge:SetTexture(S.WHITE)
	cardPill.edge:SetPoint("BOTTOMLEFT")
	cardPill.edge:SetPoint("BOTTOMRIGHT")
	cardPill.edge:SetHeight(1)
	cardLevel = S.Text(cardPill, 17)
	cardLevel:SetPoint("CENTER", 0, 0)
	cardArea = S.Text(card, 18, { 0.86, 0.79, 0.62 })
	cardExtra = S.Text(card, 17, S.DIM)
	cardExtra:SetSpacing(2)
	if S.classic then
		-- (classic: as the classic world map writes the zone under the cursor: big outlined gold, no box)
		cbg:Hide()
		cline:Hide()
		S.Font(cardName, 30, "OUTLINE")
		cardName:SetTextColor(1, 0.82, 0)
		cardPill.bg:Hide()
		cardPill.edge:Hide()
		S.Font(cardLevel, 20, "OUTLINE")
		S.Font(cardArea, 20, "OUTLINE")
		S.Font(cardExtra, 17, "OUTLINE")
	end
	card:Hide()
	-- AzerothVeil: the coordinates, bottom middle of the map (ShowCoords)
	coordText = S.Text(card:GetParent(), 14, { 1, 0.82, 0 })
	S.Font(coordText, 14, "OUTLINE")
	coordText:SetShadowColor(0, 0, 0, 0)
	coordText:SetPoint("BOTTOM", view, "BOTTOM", 0, 10)      -- (bottom middle: the tools button holds the left corner)
	coordText:Hide()

	view:SetScript("OnMouseWheel", OnWheel)
	view:SetScript("OnMouseDown", OnMouseDown)
	view:SetScript("OnMouseUp", OnMouseUp)
	-- (the window resized: as much of the world across it as before, the picture only scaled: the zoom, the
	-- art it shows and which icons are on stay as they were, nothing switching midway through a drag)
	view:SetScript("OnSizeChanged", function()
		local was = vw
		Measure()
		if was and was > 1 and vw > 1 and scale and scale > 0 then
			local k = vw / was
			scale = scale * k
			if zoomTarget then zoomTarget = zoomTarget * k end
		end
		dirty = true
	end)
	view:SetScript("OnUpdate", OnUpdate)

	-- the quest log: an arrow in the map's bottom right corner, pointing the way it goes (right: fold
	-- it away; left: bring it out)
	-- (AzerothVeil: in the map's top right corner, against its right edge (the log's search and its "Quests"
	-- beside it), a little down from the header)
	local fold = S.Button(view, "", 24, 24, function() FM.QuestLog.Toggle() end, "round")
	fold:SetFrameLevel(instanceLevel + 1)
	fold:SetPoint("TOPRIGHT", view, "TOPRIGHT", -2, -8)
	fold.bg:SetVertexColor(0, 0, 0, 0.55)
	local arrowTex = fold:CreateTexture(nil, "ARTWORK")
	arrowTex:SetSize(12, 12)
	arrowTex:SetPoint("CENTER")
	arrowTex:SetTexture(MEDIA .. "chevron")
	arrowTex:SetVertexColor(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 1)
	function fold:SetActive(open)
		self.fmActive = open
		-- (the chevron's own art points right: turned round to point left while the log is out)
		if open then arrowTex:SetTexCoord(1, 0, 0, 1) else arrowTex:SetTexCoord(0, 1, 0, 1) end
		self.tip = open and { L["Quest log"], L["Fold it away (L)."] } or { L["Quest log"], L["Bring it out (L)."] }
		self.bg:SetVertexColor(0, 0, 0, 0.55)
	end
	fold:SetScript("OnLeave", function(self) self.bg:SetVertexColor(0, 0, 0, 0.55) S.HideTip() end)
	fold:SetActive(FM.db.questPanel)
	Map.questsButton = fold

	-- AzerothVeil: AzerothVeil's options, then Questie's when it's there, in the map's top left corner, bigger than
	-- they were in the header, a little in from the map's left edge and down from the header
	local CORNER, CORNER_ICON, CORNER_PAD = 32, 22, 8
	local function CornerButton(icon, onClick, tip)
		local b = S.Button(view, "", CORNER, CORNER, onClick, "round")
		b:SetFrameLevel(instanceLevel + 1)
		b.bg:SetVertexColor(0, 0, 0, 0.55)
		b:HookScript("OnLeave", function(self) self.bg:SetVertexColor(0, 0, 0, 0.55) end)
		local t = b:CreateTexture(nil, "ARTWORK")
		t:SetSize(CORNER_ICON, CORNER_ICON)
		t:SetPoint("CENTER")
		t:SetTexture(icon)
		b.tip = tip
		return b
	end
	local options = CornerButton("Interface\\Buttons\\UI-OptionsButton", function(self) FM.Menu.Toggle(self) end,
		{ L["Options"], L["AzerothVeil's settings."] })
	options:SetPoint("TOPLEFT", view, "TOPLEFT", CORNER_PAD, -CORNER_PAD)
	Map.optionsButton = options
	if _G.QuestieLoader and _G.Questie then
		local questie = CornerButton("Interface\\AddOns\\Questie\\Icons\\questie.png", function() Map.OpenQuestieOptions() end,
			{ "Questie", L["Questie's own settings."] })
		questie:SetPoint("LEFT", options, "RIGHT", 4, 0)
	end

	-- the map's tools: a button in the bottom left corner opening a little row of icon buttons beside
	-- it (each with its tooltip): the boat and zeppelin routes on and off, centre on me
	local TOOL = 22
	local tools = CreateFrame("Frame", nil, view)
	tools:SetFrameLevel(instanceLevel + 1)
	tools:SetHeight(TOOL)
	tools:Hide()
	local function IconButton(parent, icon, size, onClick)
		local b = S.Button(parent, "", TOOL, TOOL, onClick, "round")
		b:SetFrameLevel(instanceLevel + 2)
		b.bg:SetVertexColor(0, 0, 0, 0.55)
		b:SetScript("OnLeave", function(self) self.bg:SetVertexColor(0, 0, 0, 0.55) S.HideTip() end)
		local t = b:CreateTexture(nil, "ARTWORK")
		t:SetSize(size, size)
		t:SetPoint("CENTER")
		t:SetTexture(MEDIA .. icon)
		t:SetVertexColor(0.85, 0.85, 0.85, 1)
		b.icon = t
		return b
	end
	local toolsButton = IconButton(view, "menu", 13, function(self)
		tools:SetShown(not tools:IsShown())
		FM.db.toolsOpen = tools:IsShown()
		self.icon:SetVertexColor(tools:IsShown() and S.ACCENT[1] or 0.85, tools:IsShown() and S.ACCENT[2] or 0.85, tools:IsShown() and S.ACCENT[3] or 0.85, 1)
	end)
	toolsButton:SetPoint("BOTTOMLEFT", view, "BOTTOMLEFT", 8, 6)
	toolsButton.tip = { L["Map tools"], L["Click: show or hide the map's tools."] }
	tools:SetPoint("LEFT", toolsButton, "RIGHT", 4, 0)

	-- (in the row: the routes, lit in the accent colour while they show)
	local routesButton = IconButton(tools, "routes", 14, function(self)
		-- (AzerothVeil: the Transports module's "always show every route" setting; nothing while it's off)
		local MM = FM.Modules
		if not (MM and MM:IsOptionEditable("transports", "routesAll")) then
			FM.Print(FM.L["Turn on the Transports module and its route lines first (/av config)."])
			return
		end
		MM:SetSetting("transports", "routesAll", not MM:GetSetting("transports", "routesAll"))
		self:SetActive(FM.db.routes)
		if FM.Options and FM.Options.Refresh then FM.Options.Refresh() end
		dirty = true
	end)
	function routesButton:SetActive(on)
		self.fmActive = on
		if on then self.icon:SetVertexColor(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 1) else self.icon:SetVertexColor(0.7, 0.7, 0.7, 0.7) end
		self.tip = { L["Boat & zeppelin routes"], on and L["All shown: click to show each only over its dock."] or L["Each over its dock: click to show them all."] }
		self.bg:SetVertexColor(0, 0, 0, 0.55)
	end
	routesButton:SetActive(FM.db.routes)
	-- (... and centre on me)
	local centerButton = IconButton(tools, "locate", 15, function() Map.CenterOnMe() end)
	centerButton.tip = { L["Center on me"], L["The map on where you are, as M opens it (inside a dungeon: its map)."] }
	local row = { routesButton }
	-- (... and, with a gathering addon loaded (GatherMate2, Gatherer...), its herb and ore icons on and off)
	if FM.AddonPins and FM.AddonPins.HasGathering() then
		local gatherButton = IconButton(tools, "gather", 15, function(self)
			FM.db.gatherPins = not (FM.db.gatherPins ~= false)
			self:SetActive(FM.db.gatherPins)
			FM.AddonPins.Refresh()
			dirty = true
		end)
		function gatherButton:SetActive(on)
			self.fmActive = on
			if on then self.icon:SetVertexColor(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 1) else self.icon:SetVertexColor(0.7, 0.7, 0.7, 0.7) end
			self.tip = { L["Gathering icons"], (on and L["Shown: click to hide them."] or L["Hidden: click to show them."])
				.. L["\nThe herbs, ore and other nodes of your gathering addons (GatherMate2, Gatherer...)."] }
			self.bg:SetVertexColor(0, 0, 0, 0.55)
		end
		gatherButton:SetActive(FM.db.gatherPins ~= false)
		row[#row + 1] = gatherButton
	end
	row[#row + 1] = centerButton
	local step = TOOL + 3
	for i, b in ipairs(row) do b:SetPoint("LEFT", tools, "LEFT", (i - 1) * step, 0) end
	tools:SetWidth(#row * step - 3)
	if FM.db.toolsOpen then toolsButton:GetScript("OnClick")(toolsButton) end
	Map.routesButton = routesButton

	-- resize grip: six small dots in a triangle in the corner, lit in the accent colour under the cursor
	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(18, 18)
	grip:SetPoint("BOTTOMRIGHT", S.classic and -3 or -1, S.classic and 3 or 1)
	grip:SetFrameLevel(topLayer:GetFrameLevel() + 5)
	local plate = grip:CreateTexture(nil, "BACKGROUND")
	plate:SetTexture(S.WHITE)
	plate:SetAllPoints()
	plate:SetVertexColor(0, 0, 0, 0)
	local dots = {}
	for row = 0, 2 do
		for col = 0, row do
			local d = grip:CreateTexture(nil, "OVERLAY")
			d:SetTexture(S.WHITE)
			d:SetSize(2, 2)
			d:SetPoint("BOTTOMRIGHT", -(3 + col * 4), 3 + (row - col) * 4)
			dots[#dots + 1] = d
		end
	end
	local function Lit(on)
		local c = on and S.ACCENT or S.TEXT
		for _, d in ipairs(dots) do d:SetVertexColor(c[1], c[2], c[3], on and 1 or 0.45) end
		plate:SetVertexColor(1, 1, 1, on and 0.06 or 0)
	end
	Lit(false)
	grip:SetScript("OnEnter", function() Lit(true) pcall(SetCursor, "UI_RESIZE_CURSOR") end)
	grip:SetScript("OnLeave", function() if not sizing then Lit(false) end ResetCursor() end)
	-- (our own sizing: the map's width follows the cursor, its height follows the width)
	grip:SetScript("OnMouseDown", function()
		SaveWindow()
		local x, y = GetCursorPosition()
		local es = frame:GetEffectiveScale()
		sizing = { x = x / es, y = y / es, w = view:GetWidth() }
	end)
	grip:SetScript("OnMouseUp", function(self)
		sizing = nil
		if not self:IsMouseOver() then Lit(false) end
		FM.db.window.mapW = view:GetWidth()
		SaveWindow()
	end)
	grip:SetScript("OnUpdate", function()
		if not sizing then return end
		local x, y = GetCursorPosition()
		local es = frame:GetEffectiveScale()
		local dx, dy = x / es - sizing.x, (sizing.y - y / es) * ASPECT
		-- (the corner follows the cursor along whichever way it moves more, the two blended where they pull
		-- apart: continuous everywhere, so a drag that turns never makes the window jump)
		local d
		if (dx >= 0) == (dy >= 0) then d = math.abs(dx) > math.abs(dy) and dx or dy else d = dx + dy end
		FM.db.window.mapW = sizing.w + d
		ApplySize()
	end)

	frame:SetScript("OnShow", function()
		keys:Show()                -- (Escape: the key catcher, shown with it)
		Measure()
		dirty = true
	end)
	frame:SetScript("OnHide", function()
		keys:Hide()
		dragging, zoomTarget = false, nil
		S.HideTip()
		-- (any tooltip shown for something of ours (an icon, a boss, a route, a reward, Questie's for its
		-- icons) goes with the map: none is left standing in the world)
		FM.Pins.Hover(true)
		FM.Routes.Hover(nil)
		local owner = GameTooltip:IsShown() and GameTooltip:GetOwner()
		while owner do
			if owner == frame then GameTooltip:Hide() break end
			owner = owner.GetParent and owner:GetParent()
		end
		-- (AzerothVeil: the options are a window of their own now: they stay open when the map closes)
		FM.Pins.OnHide()
		FM.Quests.OnHide()
		FM.Dungeon.OnHide()
		FM.AddonPins.OnHide()
		Map.KeepZoom()
		FM.Isles.OnHide()
		FM.Spot.Hide()
	end)

	FM.Pins.Init(pinLayer, topLayer)
	FM.QuestLog.Attach(frame, HEADER)
	grip:SetFrameLevel(frame:GetFrameLevel() + 60)
	Map.ApplyWindow()
end


-- Zoomed right out: the world map as the game's own map shows it (Azeroth's art from the client,
-- the same files its world map draws), laid on the world (its art pixels are our units). It covers
-- the stitched map and the cities, and dissolves into them over the first step in (worldAlpha).
local worldBuilt = false
function Map.PlaceWorld()
	if not worldArt then return end
	if worldAlpha <= 0.003 then
		if worldArt:IsShown() then worldArt:Hide() end
		if not cityLayer:IsShown() then cityLayer:Show() end
		return
	end
	if not worldBuilt then
		worldBuilt = true
		local layers = C_Map.GetMapArtLayers(FM.WORLD)
		local info = layers and layers[1]
		local files = C_Map.GetMapArtLayerTextures(FM.WORLD, 1)
		if info and files then
			local lw, lh, tw, th = info.layerWidth, info.layerHeight, info.tileWidth, info.tileHeight
			local sx, sy = W / lw, H / lh
			local cols = ceil(lw / tw)
			-- AzerothVeil: with the continents' and seas' names lettered live (Names.lua), the world's art without its
			-- own (OpenMap's hand-cleaned tiles, MIT: Media/MapArt/947_<i>, its MapArtEdits)
			local clean = FM.db.mapNames ~= false and #files == 12
			for i, file in ipairs(files) do
				if clean then file = MEDIA .. "MapArt\\947_" .. i end
				local col, row = (i - 1) % cols, floor((i - 1) / cols)
				local x, y = col * tw, row * th
				local w, h = min(tw, lw - x), min(th, lh - y)
				if w > 0 and h > 0 then
					local t = worldArt:CreateTexture(nil, "ARTWORK")
					t:SetTexture(file, nil, nil, "TRILINEAR")
					-- (a part tile at the right or bottom stops 2 texels short of its art's end: drawn small, the
					-- texture's smaller copies blend the file's blank rest into that edge, a pale line)
					t:SetTexCoord(0, (w < tw and w - 2 or w) / tw, 0, (h < th and h - 2 or h) / th)
					-- (edge to edge with the next tile: no hairline, nothing drawn twice)
					t:SetPoint("TOPLEFT", worldArt, "TOPLEFT", x * sx, -y * sy)
					t:SetPoint("BOTTOMRIGHT", worldArt, "TOPLEFT", (x + w) * sx, -(y + h) * sy)
				end
			end
		end
	end
	-- (a frame W x H units, scaled to the view: its offsets are in its own units)
	worldArt:SetScale(scale)
	worldArt:SetPoint("TOPLEFT", view, "TOPLEFT", -left, top)
	worldArt:SetAlpha(worldAlpha)
	worldArt:Show()
	cityLayer:SetShown(worldAlpha < 0.999)
end

function Map.CenterOnPlayer(unitsAcross)
	local u, v = Geo.UnitUnits("player")
	if u then
		ModeFor(u, v)        -- (on a land apart: its map)
		cx, cy = u, v
		if unitsAcross then scale = vw / unitsAcross end
		dirty = true
	end
end

-- Center on me (the tools' button): as M opens the map, on you, at M's zoom (the one it was last
-- closed at), or closer if you're closer already. Any zoom on its way is stopped first
-- how much of the world is across the view when it opens: the zoom it was last closed at (Options'
-- "Remember last zoom"), else M's own
-- In a capital, or underground (a cave's own map, or indoors in a cave's box): the map opens three steps
-- of the wheel closer than M's zoom
local CAPITALS = { [1453] = true, [1454] = true, [1455] = true, [1456] = true, [1457] = true, [1458] = true }
local CLOSE_STEPS = 3
local function CloseIn(u, v)
	local m = FM.Plain(C_Map.GetBestMapForUnit("player"))
	local info = m and C_Map.GetMapInfo(m)
	if not info then return false end
	if CAPITALS[m] or CAPITALS[info.parentMapID] then return true end
	if Enum and Enum.UIMapType and info.mapType == Enum.UIMapType.Micro then return true end
	return (u and IsIndoors and FM.Plain(IsIndoors()) and FM.Caves.Contains(u, v)) and true or false
end

local function OpenAcross()
	return FM.db.rememberZoom and FM.db.window.across or Map.OPEN_ACROSS
end

-- the view as M opens the map: on you, at M's zoom (closer in a capital or underground); false where
-- you aren't on the world's map
function Map.ViewAsOpened()
	local u, v = Geo.UnitUnits("player")
	if not u then return false end
	zoomTarget = nil
	local across = OpenAcross()
	if not (FM.db.rememberZoom and FM.db.window.across) and CloseIn(u, v) then across = across / Map.ZOOM_STEP ^ CLOSE_STEPS end
	Map.CenterOnPlayer(across)
	return true
end

function Map.CenterOnMe()
	-- (inside a dungeon: its map, where you are)
	if FM.Dungeon.ShowHere() then return end
	local u, v = Geo.UnitUnits("player")
	if not u then return end
	zoomTarget = nil
	local across = OpenAcross()
	ModeFor(u, v)            -- (on a land apart, Zephras Isle: its map)
	if vw / scale > across then scale = vw / across end
	cx, cy = u, v
	dirty = true
end

local opened = false
function Map.Show()
	if not built then Build() end
	if frame:IsShown() then return end
	S.RefreshFonts()          -- (the game's font may have changed since: a font addon, a setting)
	frame:Show()
	Measure()
	if FM.db.reopen == "player" or not opened then
		-- (on you, at M's zoom; or, if Options say so, the one it had when it was last closed, kept across sessions too)
		if not Map.ViewAsOpened() then scale = vw / OpenAcross() cx, cy = W / 2, H / 2 end
	end
	opened = true
	FM.Pins.OnShow()
	FM.Dungeon.Update()
	FM.Quests.OnShow()
	FM.Vessels.OnShow()
	FM.Friends.OnShow()
	FM.Isles.Update()
	if not FM.Dungeon.Active() then Map.Refresh() end
end

-- show a whole map (a zone, a continent, the world; a dungeon's or a city's district: the zone it's in)
function Map.ShowMapID(mapID, zoomOut)
	if not built or not mapID then return end
	-- (a land off the world map, or a map on it: that land's map apart; anything else, the world's)
	local away = Geo.AwayOf(mapID)
	if away then Map.SetAway(away) elseif awayMap then Map.SetAway(nil) end
	local id, r = mapID, nil
	for _ = 1, 8 do
		if not id or id == 0 or id == FM.WORLD then break end
		r = Geo.Rect(id)
		if r then break end
		local info = C_Map.GetMapInfo(id)
		id = info and info.parentMapID
	end
	if r then
		local w, h = r[2] - r[1], r[4] - r[3]
		cx, cy = (r[1] + r[2]) / 2, (r[3] + r[4]) / 2
		scale = min(vw / (w * 1.08), vh / (h * 1.08))
	elseif id == FM.WORLD then
		scale, cx, cy = 0, W / 2, H / 2
	else
		return
	end
	if zoomOut then
		scale = Limits()
		zoomTarget = nil
	end
	dirty = true
end

-- AzerothVeil: several zones whole, together (a signpost into several zones, Pins.lua); one: Map.ShowMapID
function Map.ShowMaps(ids)
	if not built or not ids or not ids[1] then return end
	if not ids[2] then Map.ShowMapID(ids[1]) return end
	local l, r, t, b
	for _, id in ipairs(ids) do
		local rc = Geo.Rect(id)
		if rc then
			l, r = min(l or rc[1], rc[1]), max(r or rc[2], rc[2])
			t, b = min(t or rc[3], rc[3]), max(b or rc[4], rc[4])
		end
	end
	if not l then return end
	if awayMap then Map.SetAway(nil) end
	zoomTarget = nil
	cx, cy = (l + r) / 2, (t + b) / 2
	scale = min(vw / ((r - l) * 1.08), vh / ((b - t) * 1.08))
	dirty = true
end

-- a spot on a map in the middle of the view, close enough in to see where it is
function Map.ShowSpot(mapID, x, y)
	if not built then return end
	local u, v = Geo.MapToUnits(mapID, x, y)
	if not u then Map.ShowMapID(mapID) return end
	ModeFor(u, v)
	cx, cy = u, v
	scale = max(scale, vw / 160)
	dirty = true
end

-- Questie's settings window (its options engine; an older Questie's AceConfig one), over the map
function Map.OpenQuestieOptions()
	local QL = _G.QuestieLoader
	if not QL then return end
	for _, name in ipairs({ "QuestieOptionsEngine", "QuestieOptions" }) do
		local ok, mod = pcall(QL.ImportModule, QL, name)
		if ok and type(mod) == "table" and mod.ToggleConfigWindow then
			if pcall(mod.ToggleConfigWindow, mod) then
				local f = mod.popup or _G.QuestieConfigFrame
				if f and f.SetFrameStrata and f:IsShown() then f:SetFrameStrata("DIALOG") f:Raise() end
				return
			end
		end
	end
	if SlashCmdList and SlashCmdList.QUESTIE then pcall(SlashCmdList.QUESTIE, "") end
end

function Map.Hide()
	if frame then frame:Hide() end
end

-- (the zoom it's closed at: how much of the world is across the view, kept for next time)
local function KeepZoom()
	-- (on a land apart: the world's zoom, as it was before)
	local s = awayMap and worldView and worldView[3] or (zoomTarget or scale)
	if s and s > 0 and vw and vw > 0 then FM.db.window.across = vw / s end
end
Map.KeepZoom = KeepZoom

function Map.Toggle()
	if frame and frame:IsShown() then Map.Hide() else Map.Show() end
end

function Map.IsShown() return frame and frame:IsShown() end

function Map.PrintStats()
	UpdateAddOnMemoryUsage()
	local mem = GetAddOnMemoryUsage(ADDON_NAME)
	FM.Print(("level %d (%.1f px/unit)  tiles on screen %d, loaded %d (files loaded so far %d)"):format(
		level, scale * ppuFactor, nShown, nActive, stats.loads))
	FM.Print(("refresh %.2f ms (worst %.2f ms, %d refreshes)  pins %s  memory %.0f KB"):format(
		stats.refreshMs, stats.maxMs, stats.refreshes, FM.Pins.StatsText(), mem))
	if stats.battlegroundFrames then
		FM.Print(("battleground update %.2f ms (worst %.2f ms, %d frames)"):format(
			stats.battlegroundMs, stats.battlegroundMax, stats.battlegroundFrames))
	end
end
