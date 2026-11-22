-- AzerothVeil — Engine/Fog.lua: the fog of war (the Map module's "Fog of war", Modules/Map.lua).
-- The stitched tiles show every zone whole, as if all of it were explored. With the fog on, a zone you haven't
-- explored all of is drawn as Blizzard's own map draws it: its base art (the game's map art, C_Map art layer:
-- the land you haven't found blank), and over it, in the game's order, only the pieces the game says you've
-- explored (C_MapExplorationInfo.GetExploredMapTextures), each with its own soft edges. Through the zone's
-- territory (Media/FogTerritory/<uiMapID>, OpenMap's MapTerritory, MIT) only: a zone's art runs past its
-- borders, and its neighbours stay as the tiles (or their own fog) paint them. A zone explored whole is left
-- to the tiles (its piece count: Data/Fog.lua, FM.FOG_PIECES, from OpenMap).
-- Cheap: a zone's frame is made the first time it's in view with the fog on (its base art, about a dozen
-- files, and its explored pieces), and made again only when the player has explored more of it
-- (F.Explored: MAP_EXPLORATION_UPDATED, heard by the module while the fog is on); one frame per zone, scaled
-- as a whole (a pan or zoom moves frames, not textures); a zone off the view is hidden. Off: nothing shown,
-- every file let go. Over the minimap's terrain up close (Terrain.lua: there only on the land not explored
-- yet, Near), under the icons; covered by the world's
-- own art zoomed right out (Map.lua's worldArt), as Blizzard's world map has no fog either.
local _, FM = ...
local F = {}
FM.Fog = F

local Geo = FM.Geo
local floor, ceil, min = math.floor, math.ceil, math.min
local ART_W, ART_H = 1002, 668          -- a zone's art (its frame's own units below)
local TERRITORY = "Interface\\AddOns\\AzerothVeil\\Media\\FogTerritory\\"
local NONE = {}

local layer
local on = false
local terrain = 0                       -- AzerothVeil: how much the minimap's terrain shows (Terrain.lua)
local zones = {}                        -- { id, r, frame, tex = { textures }, count = explored pieces when made, whole, dirty }

local function Pow2(px) local s = 16 while s < px do s = s * 2 end return s end

-- the pieces the game says are explored, as it lists them (the ones shown only under the mouse left out)
local function Explored(id)
	local get = C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures
	local ok, list = false, nil
	if get then ok, list = pcall(get, id) end
	local out = {}
	for _, e in ipairs(ok and type(list) == "table" and list or NONE) do
		if not e.isShownByMouseOver and type(e.fileDataIDs) == "table" then out[#out + 1] = e end
	end
	return out, ok and type(list) == "table" and #list or 0
end

-- how many pieces the zone's art has in all (nil: not known, then always drawn)
local function PieceCount(id)
	local art = C_Map.GetMapArtID and C_Map.GetMapArtID(id)
	local data = art and FM.FOG_PIECES and FM.FOG_PIECES[art]
	if not data then return nil end
	local n = 0
	for _ in pairs(data) do n = n + 1 end
	return n
end

-- a zone's frame let go: hidden, its files dropped (a frame can't be destroyed: a new one is made next time)
local function Drop(z)
	if z.frame then
		z.frame:Hide()
		for _, t in ipairs(z.tex) do t:SetTexture(nil) end
		for _, t in ipairs(z.near or NONE) do t:SetTexture(nil) end
	end
	z.frame, z.tex, z.near, z.art = nil, nil, nil, nil
end

-- AzerothVeil: up close, over the minimap's terrain (Terrain.lua), the fog only where it hides something: the
-- base art through each piece not explored yet (the piece's own file as the mask: its soft edges), so the
-- terrain shows through the land you've explored and the fog stays on the rest. Made the first time the
-- terrain comes in over the zone (and again with it when more is explored); its alpha the terrain's.
local function Near(z)
	local f, a = z.frame, z.art
	if not (f and a) or z.near then return end
	local data = FM.FOG_PIECES and FM.FOG_PIECES[C_Map.GetMapArtID and FM.Plain(C_Map.GetMapArtID(z.id))]
	local near = CreateFrame("Frame", nil, f)
	near:SetAllPoints(f)
	near:SetAlpha(terrain)
	f.near = near
	z.near = {}
	if not data then return end
	local done = {}
	for _, e in ipairs(a.explored) do
		done[e.textureWidth .. ":" .. e.textureHeight .. ":" .. e.offsetX .. ":" .. e.offsetY] = true
	end
	local tw, th, sx, sy, lw, lh = a.tw, a.th, a.sx, a.sy, a.lw, a.lh
	local cols = ceil(lw / tw)
	for key, list in pairs(data) do
		if not done[key] then
			local pw, ph, px, py = key:match("^(%d+):(%d+):(%d+):(%d+)$")
			pw, ph, px, py = tonumber(pw), tonumber(ph), tonumber(px), tonumber(py)
			local ids = {}
			for fid in tostring(list):gmatch("%d+") do ids[#ids + 1] = tonumber(fid) end
			local across, down = ceil((pw or 0) / tw), ceil((ph or 0) / th)
			for j = 1, down do
				local h = j < down and th or (ph - (down - 1) * th)
				local fh = j < down and th or Pow2(h)
				for k = 1, across do
					local w = k < across and tw or (pw - (across - 1) * tw)
					local fw = k < across and tw or Pow2(w)
					local file = ids[(j - 1) * across + k]
					local x0, y0 = px + tw * (k - 1), py + th * (j - 1)
					if file and w > 0 and h > 0 then
						-- the piece's file as it's laid on the map (its whole file, from its corner)
						local mask = near:CreateMaskTexture()
						local ok = pcall(mask.SetTexture, mask, file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
						if ok then
							mask:SetPoint("TOPLEFT", f, "TOPLEFT", x0 * sx, -y0 * sy)
							mask:SetSize(fw * sx, fh * sy)
							-- the base art's tiles under it, each cut to the piece's rectangle
							local x1, y1 = x0 + w, y0 + h
							for i, base in ipairs(a.files) do
								local bx, by = ((i - 1) % cols) * tw, floor((i - 1) / cols) * th
								local bw, bh = min(tw, lw - bx), min(th, lh - by)
								local ix0, iy0 = math.max(x0, bx), math.max(y0, by)
								local ix1, iy1 = min(x1, bx + bw), min(y1, by + bh)
								if bw > 0 and bh > 0 and ix1 > ix0 and iy1 > iy0 then
									local ew, eh = (bw < tw and bw - 2 or bw) / tw, (bh < th and bh - 2 or bh) / th
									local t = near:CreateTexture(nil, "ARTWORK")
									t:SetTexture(base, nil, nil, "TRILINEAR")
									t:SetTexCoord((ix0 - bx) / bw * ew, (ix1 - bx) / bw * ew, (iy0 - by) / bh * eh, (iy1 - by) / bh * eh)
									t:SetPoint("TOPLEFT", f, "TOPLEFT", ix0 * sx, -iy0 * sy)
									t:SetPoint("BOTTOMRIGHT", f, "TOPLEFT", ix1 * sx, -iy1 * sy)
									t:AddMaskTexture(f.territory)
									t:AddMaskTexture(mask)
									z.near[#z.near + 1] = t
								end
							end
						end
					end
				end
			end
		end
	end
end

-- the zone as Blizzard's map draws it: base art, then the explored pieces over it, through its territory
local function Build(z, pieces)
	local id = z.id
	local layers = C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(id)
	local info = layers and layers[1]
	local files = info and C_Map.GetMapArtLayerTextures(id, 1)
	if not info or not files or #files == 0 or (info.layerWidth or 0) <= 0 then z.failed = true return end
	local lw, lh, tw, th = info.layerWidth, info.layerHeight, info.tileWidth, info.tileHeight
	local sx, sy = ART_W / lw, ART_H / lh
	local f = CreateFrame("Frame", nil, layer)
	f:SetSize(ART_W, ART_H)
	f:SetFrameLevel(layer:GetFrameLevel())
	f:Hide()
	-- (AzerothVeil: the zone as the map draws it, away from the terrain; Near's cut-outs over the terrain)
	local far = CreateFrame("Frame", nil, f)
	far:SetAllPoints(f)
	far:SetAlpha(1 - terrain)
	f.far = far
	local territory = f:CreateMaskTexture()
	territory:SetTexture(TERRITORY .. id, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	territory:SetAllPoints(f)
	f.territory = territory
	local tex = {}
	local function Tile(file, sub, x, y, w, h, u, v)
		local t = far:CreateTexture(nil, "ARTWORK", nil, sub)
		t:SetTexture(file, nil, nil, "TRILINEAR")
		t:SetTexCoord(0, u, 0, v)
		t:SetPoint("TOPLEFT", f, "TOPLEFT", x * sx, -y * sy)
		t:SetPoint("BOTTOMRIGHT", f, "TOPLEFT", (x + w) * sx, -(y + h) * sy)
		t:AddMaskTexture(territory)
		tex[#tex + 1] = t
	end
	-- its base art, edge to edge (a part tile at the right or bottom stops 2 texels short of its art's end, as
	-- Isles.lua and the world's art do: no pale line blended in from the file's blank rest)
	local cols = ceil(lw / tw)
	for i, file in ipairs(files) do
		local x, y = ((i - 1) % cols) * tw, floor((i - 1) / cols) * th
		local w, h = min(tw, lw - x), min(th, lh - y)
		if w > 0 and h > 0 then Tile(file, 0, x, y, w, h, (w < tw and w - 2 or w) / tw, (h < th and h - 2 or h) / th) end
	end
	-- the explored pieces, in the game's order, cut in tiles as Blizzard's map cuts them (a piece's last row and
	-- column in files of the next power of two)
	for _, e in ipairs(pieces) do
		local pw, ph, px, py = e.textureWidth, e.textureHeight, e.offsetX, e.offsetY
		local across, down = ceil(pw / tw), ceil(ph / th)
		for j = 1, down do
			local h = j < down and th or (ph - (down - 1) * th)
			local fh = j < down and th or Pow2(h)
			for k = 1, across do
				local w = k < across and tw or (pw - (across - 1) * tw)
				local fw = k < across and tw or Pow2(w)
				local file = e.fileDataIDs[(j - 1) * across + k]
				if file and w > 0 and h > 0 then Tile(file, 1, px + tw * (k - 1), py + th * (j - 1), w, h, w / fw, h / fh) end
			end
		end
	end
	z.frame, z.tex = f, tex
	z.art = { files = files, lw = lw, lh = lh, tw = tw, th = th, sx = sx, sy = sy, explored = pieces }
	if terrain > 0 then Near(z) end
end

-- up to date with what's explored: made again only when the game lists more explored pieces than when it was
-- made; none at all once the zone is explored whole (the tiles show it as it is)
local function Update(z)
	z.dirty = false
	local pieces, count = Explored(z.id)
	if z.count == count and (z.frame or z.whole) then return end
	z.count = count
	Drop(z)
	local all = PieceCount(z.id)
	z.whole = all ~= nil and count >= all
	if not z.whole then Build(z, pieces) end
end

function F.Init(parent)
	layer = parent
	for _, id in ipairs(FM.FOG_ZONES or NONE) do
		local r = Geo.Rect(id)
		if r then zones[#zones + 1] = { id = id, r = r, dirty = true } end
	end
end

-- covered: the world's own art over everything (zoomed right out)
function F.Layout(left, top, scale, vw, vh, covered)
	if not layer then return end
	local x1, y1 = left + vw / scale, top + vh / scale
	for _, z in ipairs(zones) do
		local r = z.r
		local want = on and not covered and not z.failed and r[2] > left and r[1] < x1 and r[4] > top and r[3] < y1
		if want and z.dirty then Update(z) end
		local f = z.frame
		if want and f then
			local k = (r[2] - r[1]) * scale / ART_W          -- (screen px per art px)
			if k > 0 then
				f:SetScale(k)
				f:ClearAllPoints()
				f:SetPoint("TOPLEFT", layer, "TOPLEFT", (r[1] - left) * scale / k, (top - r[3]) * scale / k)
				f:Show()
				if terrain > 0 and not z.near then Near(z) end   -- (AzerothVeil: the fog over the terrain)
			end
		elseif f and f:IsShown() then
			f:Hide()
		end
	end
end

-- the fog on or off (the Map module); off, every zone's files are let go
function F.SetEnabled(v)
	v = v and true or false
	if v == on then return end
	on = v
	for _, z in ipairs(zones) do
		if not on then Drop(z) z.count, z.whole = nil, nil end
		z.dirty, z.failed = true, nil
	end
	if FM.Map and FM.Map.MarkDirty then FM.Map.MarkDirty() end
end
function F.IsEnabled() return on end

-- AzerothVeil: up close the minimap's terrain takes over (Terrain.lua tells how much of it shows): the zone as the
-- map draws it fades out, and the fog stays only on the land not explored yet (Near)
function F.SetTerrain(k)
	if k == terrain then return end
	terrain = k
	for _, z in ipairs(zones) do
		local f = z.frame
		if f then
			if k > 0 and f:IsShown() then Near(z) end
			f.far:SetAlpha(1 - k)
			if f.near then f.near:SetAlpha(k) end
		end
	end
end

-- the player explored somewhere (MAP_EXPLORATION_UPDATED): each zone checked again as it comes into view
function F.Explored()
	if not on then return end
	for _, z in ipairs(zones) do z.dirty = true end
	if FM.Map and FM.Map.MarkDirty then FM.Map.MarkDirty() end
end
