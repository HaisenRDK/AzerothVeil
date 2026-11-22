-- The lands off the world map (Geo.AWAY: Zephras Isle, the Skyborn's start): a continent of their own in
-- the game, not on Azeroth's map. Each is a map apart, as MapUtils and OpenMap open it (the game's own
-- map of it): shown alone in the window (Map.SetAway: panned and zoomed within itself), never on the
-- world's. Everything is on it as on any zone (you and your group, quests and their areas, Questie's
-- icons, townsfolk, points of interest, other addons' icons), as all of it is placed by Geo.
--  * Standing on one, the map opens on it, as inside a dungeon its map; a right-click on the bare map
--    goes back to the world (until you move on, reopen the map or Center on me: then its map again).
--  * From the world: a left-click on an airship's dock bound there (Pins.lua) opens it; back the same way.
--  * Its art: the client's own map of it (C_Map art layer), drawn over its whole place, as the cities'.
-- Its name at the bottom and the right-click's hint, as a dungeon's map has them.
local _, FM = ...
local L = FM.L
local I = {}
FM.Isles = I

local Geo = FM.Geo
local S = FM.Style
local Plain = FM.Plain
local ART_W = 1002                      -- a map's art width (its frame's own units below)

local layer, overlay, title, hint
local isles = {}
local peek = false                      -- standing on one, but looking at the world (World / right-click)

---------------------------------------------------------------------------
-- A map whole from the start, nothing to explore first (theirs, and the battlegrounds': Dungeon.lua): every
-- explored-area piece over its base art (DataReveal.lua; and any the game gives as explored that the list
-- hasn't), cut in tiles as Blizzard's map cuts them (a piece's last row and column in files of the next power
-- of two). fn(file, x, y, w, h, u, v) for each tile: where in the art's pixels, and how much of its file
---------------------------------------------------------------------------
function I.EachRevealTile(m, tw, th, fn)
	local pieces, seen = {}, {}
	for key, ids in pairs(FM.MAP_REVEAL and FM.MAP_REVEAL[C_Map.GetMapArtID(m) or 0] or {}) do
		local pw, ph, px, py = strsplit(":", key)
		local files = {}
		for id in ids:gmatch("%d+") do files[#files + 1] = tonumber(id) end
		pieces[#pieces + 1] = { tonumber(pw), tonumber(ph), tonumber(px), tonumber(py), files }
		seen[key] = true
	end
	for _, e in ipairs(C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures
		and C_MapExplorationInfo.GetExploredMapTextures(m) or {}) do
		local key = e.textureWidth .. ":" .. e.textureHeight .. ":" .. e.offsetX .. ":" .. e.offsetY
		if not seen[key] and not e.isShownByMouseOver then
			pieces[#pieces + 1] = { e.textureWidth, e.textureHeight, e.offsetX, e.offsetY, e.fileDataIDs }
		end
	end
	local function FileSize(px) local s = 16 while s < px do s = s * 2 end return s end
	for _, p in ipairs(pieces) do
		local pw, ph, px, py, files = p[1], p[2], p[3], p[4], p[5]
		local across, down = math.ceil(pw / tw), math.ceil(ph / th)
		for j = 1, down do
			local h = j < down and th or (ph % th == 0 and th or ph % th)
			local fh = j < down and th or FileSize(h)
			for k = 1, across do
				local w = k < across and tw or (pw % tw == 0 and tw or pw % tw)
				local fw = k < across and tw or FileSize(w)
				local file = files[(j - 1) * across + k]
				if file then fn(file, px + tw * (k - 1), py + th * (j - 1), w, h, w / fw, h / fh) end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Its art
---------------------------------------------------------------------------
local function Build(c)
	local layers = C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(c.id)
	local info = layers and layers[1]
	local files = info and C_Map.GetMapArtLayerTextures(c.id, 1)
	if not info or not files or #files == 0 or info.layerWidth <= 0 then c.failed = true return end
	local f = c.frame
	local lw, lh, tw, th = info.layerWidth, info.layerHeight, info.tileWidth, info.tileHeight
	local sx, sy = ART_W / lw, c.h / lh            -- (the layer over its whole place)
	local cols = math.ceil(lw / tw)
	for i, file in ipairs(files) do
		local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
		local x, y = col * tw, row * th
		local w, h = math.min(tw, lw - x), math.min(th, lh - y)
		if w > 0 and h > 0 then
			local t = f:CreateTexture(nil, "ARTWORK")
			t:SetTexture(file, nil, nil, "TRILINEAR")
			-- (a part tile at the right or bottom stops 2 texels short of its art's end: drawn small, the
			-- texture's smaller copies would blend the file's blank rest into that edge, a pale line)
			t:SetTexCoord(0, (w < tw and w - 2 or w) / tw, 0, (h < th and h - 2 or h) / th)
			-- (edge to edge, as the map's own tiles: nothing drawn twice)
			t:SetPoint("TOPLEFT", f, "TOPLEFT", x * sx, -y * sy)
			t:SetPoint("BOTTOMRIGHT", f, "TOPLEFT", (x + w) * sx, -(y + h) * sy)
		end
	end
	-- the whole map from the start, nothing to explore first (I.EachRevealTile)
	I.EachRevealTile(c.id, tw, th, function(file, x, y, w, h, u, v)
		local t = f:CreateTexture(nil, "ARTWORK", nil, 1)
		t:SetTexture(file, nil, nil, "TRILINEAR")
		t:SetTexCoord(0, u, 0, v)
		t:SetPoint("TOPLEFT", f, "TOPLEFT", x * sx, -y * sy)
		t:SetPoint("BOTTOMRIGHT", f, "TOPLEFT", (x + w) * sx, -(y + h) * sy)
	end)
	c.built = true
end

-- layer: under the icons (the art); over: over them (its name and the hint)
function I.Init(parent, over)
	layer = parent
	for _, a in ipairs(Geo.AWAY) do
		local r = Geo.Rect(a.map)
		if r then
			local f = CreateFrame("Frame", nil, layer)
			local h = ART_W * (r[4] - r[3]) / (r[2] - r[1])
			f:SetSize(ART_W, h)
			f:SetFrameLevel(layer:GetFrameLevel() + 1)
			f:Hide()
			isles[#isles + 1] = { id = a.map, r = r, frame = f, h = h }
		end
	end
	-- (as a dungeon's map: its name in gold at the bottom, the right-click's hint left of the quest log's arrow)
	overlay = CreateFrame("Frame", nil, over)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(over:GetFrameLevel() + 1)
	overlay:Hide()
	title = overlay:CreateFontString(nil, "OVERLAY")
	S.Font(title, 20, "OUTLINE")
	title:SetTextColor(1, 0.82, 0)
	title:SetPoint("BOTTOM", 0, 12)
	hint = S.Text(overlay, 10, S.DIM)
	hint:SetPoint("RIGHT", overlay, "BOTTOMRIGHT", -54, 17)
	hint:SetText(L["Right-click: back to the world"])
end

function I.Layout(left, top, scale, vw, vh)
	local x1, y1 = left + vw / scale, top + vh / scale
	for _, c in ipairs(isles) do
		local r, f = c.r, c.frame
		if not c.failed and r[2] > left and r[1] < x1 and r[4] > top and r[3] < y1 then
			if not c.built then Build(c) end
			if c.built then
				local k = (r[2] - r[1]) * scale / ART_W          -- (screen px per art px)
				if k > 0 then
					f:SetScale(k)
					f:ClearAllPoints()
					f:SetPoint("TOPLEFT", layer, "TOPLEFT", (r[1] - left) * scale / k, (top - r[3]) * scale / k)
					f:Show()
				end
			end
		elseif f:IsShown() then
			f:Hide()
		end
	end
end

---------------------------------------------------------------------------
-- Where you are, and the map apart
---------------------------------------------------------------------------
-- the land you stand on (its map), else nil
function I.Here()
	local inst = Plain(select(8, GetInstanceInfo()))
	if not inst then
		local _, _, _, i = UnitPosition("player")
		inst = Plain(i)
	end
	return inst and Geo.AwayOfInstance(inst) or nil
end

-- (Map.SetAway: a land apart shown, or the world again)
function I.OnAway(mapID)
	if overlay then
		local info = mapID and C_Map.GetMapInfo(mapID)
		title:SetText(info and info.name or "")
		overlay:SetShown(mapID ~= nil)
	end
end

-- a land's map, from the world (an airship's dock bound there)
function I.Open(mapID)
	if not mapID then return end
	FM.Map.SetAway(mapID)
	PlaySound(SOUNDKIT and SOUNDKIT.IG_QUEST_LOG_OPEN or 844)
end

-- back to the world (a right-click on the bare map); standing on the land, until you move on
function I.Back()
	if not FM.Map.AwayMap() then return end
	if I.Here() then peek = true end
	FM.Map.SetAway(nil)
end

-- as the window opens, and as you move between lands: standing on one, its map (unless you're looking
-- at the world); on the world, a land's map opened from a dock goes as you leave it
function I.Update()
	local here = I.Here()
	local away = FM.Map.AwayMap()
	if here and not peek then
		if away ~= here then
			FM.Map.SetAway(here)
			FM.Map.CenterOnPlayer()
		end
	elseif away and not here and I.fromHere then
		FM.Map.SetAway(nil)
	end
	I.fromHere = here ~= nil
end

-- (the window closed: looking at the world from a land, its map is there again next time; a land's map
-- opened from a dock goes with the window)
function I.OnHide()
	peek = false
	if FM.Map.AwayMap() and not I.Here() then FM.Map.SetAway(nil) end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do ev:RegisterEvent(e) end
ev:SetScript("OnEvent", function()
	peek = false
	if FM.Map and FM.Map.IsShown() then I.Update() end
end)
