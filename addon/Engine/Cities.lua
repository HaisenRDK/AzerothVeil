-- The cities, as OpenMap draws them: the stitched tiles carry every zone but not the cities (each
-- zone's own art is cut where a city's map goes, and where its name banner for the city was), so
-- each city's own map comes from the client (C_Map art layer), cut to the city's plan (OpenMap's
-- MapCityMask) or with a round feather, and shows at once, whole, from the zoom M opens the map at (by
-- zoom, not by the window's size): over the two steps of the wheel before it it's already laid out,
-- unseen, so its files are loaded by then and it never comes in piece by piece.
-- The zone's name banner for the city (Media\CityBanner) shows with the zone, and gives way to the
-- city's own title as the city comes in. One frame per city, scaled as a whole: a pan or zoom moves
-- one frame, not its tiles; a city off the view, or not near its zoom, is hidden (its files not loaded).
-- AzerothVeil: Thunder Bluff's and Orgrimmar's plans (Media/CityMask) cut in closer than OpenMap's, so the city's map
-- (its own ground round the city, drawn darker than the zone's) doesn't spread over the zone's land round it.
local _, FM = ...
local C = {}
FM.Cities = C

local Geo = FM.Geo
local MEDIA = "Interface\\AddOns\\AzerothVeil\\Media\\"
local ART_W, ART_H = 1002, 668          -- a map's art size (its frame's own units below)

-- [city] = cut: its plan (else a round feather); title: its own title (the zone's banner for it goes)
local CITIES = {
	[1453] = {},                         -- Stormwind City
	[1454] = { cut = true, title = true }, -- Orgrimmar
	[1455] = { cut = true, title = true },   -- Ironforge
	[1456] = { cut = true, title = true }, -- Thunder Bluff
	[1457] = {},                         -- Darnassus
	[1458] = { cut = true, title = true },   -- Undercity
}
-- the zone's name banner for a city: [city] = { zone, x, y, width, height } in the zone's art pixels
-- (OpenMap's Data/Forever/Banners.lua)
local BANNERS = {
	[1454] = { 1411, 276, 7, 512, 128 },   -- Orgrimmar, on Durotar's map
	[1458] = { 1420, 484, 484, 512, 64 },  -- Undercity, on Tirisfal Glades'
	[1456] = { 1412, 306, 226, 256, 64 },  -- Thunder Bluff, on Mulgore's
	[1457] = { 1438, 113, 427, 512, 64 },  -- Darnassus, on Teldrassil's
}

-- AzerothVeil: up close, under the minimap's terrain (Terrain.lua), as OpenMap does it (Map/Close.lua, MIT). A city in
-- the open fades out as the terrain comes in: the minimap draws it, and the city's own map, cut wider than the
-- city, no longer lies over the land round it. Under the ground (Ironforge, Undercity: the minimap there is the
-- surface over them), the city's map fades out the same way, and the game's minimap of the city inside comes over
-- the terrain in its place (Data/CaveMinimap.lua, FM.CITY_MINIMAP: its WMO's pictures, made the first time they're wanted)
local UNDERGROUND = { [1455] = true, [1458] = true }
local MINI_DESAT = 0.35                 -- (toned as the caves' minimap pictures, Caves.lua)
local PAPER = { 1, 0.93, 0.80 }

local layer
local cities = {}
local under = 0                         -- how much the minimap's terrain shows (0..1)

-- a frame laid out in a map's art pixels, placed and scaled onto the view as a whole
local function ArtFrame(rect)
	local f = CreateFrame("Frame", nil, layer)
	f:SetSize(ART_W, ART_H)
	f.rect = rect
	f:Hide()
	return f
end

local function Place(f, left, top, scale)
	local r = f.rect
	local k = (r[2] - r[1]) * scale / ART_W          -- (screen px per art px)
	if k <= 0 then return end
	f:SetScale(k)
	f:SetPoint("TOPLEFT", layer, "TOPLEFT", (r[1] - left) * scale / k, (top - r[3]) * scale / k)
end

-- the city's art, the first time it shows
local function Build(c)
	local id = c.id
	local layers = C_Map.GetMapArtLayers(id)
	local info = layers and layers[1]
	local files = C_Map.GetMapArtLayerTextures(id, 1)
	if not info or not files then c.failed = true return end
	local f = c.frame
	local mask = f:CreateMaskTexture()
	mask:SetTexture(c.cut and (MEDIA .. "CityMask\\" .. id) or (MEDIA .. "FeatherRound"), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(f)
	local lw, lh, tw, th = info.layerWidth, info.layerHeight, info.tileWidth, info.tileHeight
	local sx, sy = ART_W / lw, ART_H / lh          -- (the layer in the frame's 1002 x 668)
	local cols = math.ceil(lw / tw)
	c.art = {}                                     -- (AzerothVeil: its tiles, faded on their own under the terrain)
	for i, file in ipairs(files) do
		local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
		local x, y = col * tw, row * th
		local w, h = math.min(tw, lw - x), math.min(th, lh - y)
		if w > 0 and h > 0 then
			local t = f:CreateTexture(nil, "ARTWORK")
			t:SetTexture(file, nil, nil, "TRILINEAR")
			t:SetTexCoord(0, w / tw, 0, h / th)
			t:SetSize(w * sx, h * sy)
			t:SetPoint("TOPLEFT", f, "TOPLEFT", x * sx, -y * sy)
			t:AddMaskTexture(mask)
			c.art[#c.art + 1] = t
		end
	end
	c.built = true
	c.artAlpha = nil                               -- (AzerothVeil: its tiles faded as the terrain wants, at the next Apply)
end

-- the game's minimap of an underground city inside: its pictures (file, centre X, Y, side in yards, rotation,
-- u1, v0), each a square turned about its centre, lowest floor first, on the city's frame (its art pixels)
local function MinimapPictures(c)
	local d = FM.CITY_MINIMAP and FM.CITY_MINIMAP[c.id]
	if not d then c.mini = false return end
	local r = c.r
	local kx, ky = ART_W / (r[2] - r[1]), ART_H / (r[4] - r[3])
	local f = CreateFrame("Frame", nil, c.frame)
	f:SetAllPoints(c.frame)
	local p = d[6]
	local n = #p / 7
	for i = 1, n do
		local j = (i - 1) * 7
		local u, v = Geo.WorldToUnits(d[1], p[j + 2], p[j + 3])
		local u2 = Geo.WorldToUnits(d[1], p[j + 2], p[j + 3] + p[j + 4])     -- (a side's length, in units)
		if u and u2 then
			local side = math.abs(u2 - u) * kx
			local t = f:CreateTexture(nil, "OVERLAY", nil, math.min(7, math.floor((i - 1) * 16 / n) - 8))
			t:SetTexture(p[j + 1], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "TRILINEAR")
			t:SetTexCoord(0, p[j + 6], p[j + 7], 1)
			t:SetRotation(p[j + 5])
			t:SetDesaturation(MINI_DESAT)
			t:SetVertexColor(PAPER[1], PAPER[2], PAPER[3])
			t:SetSize(side, side)
			t:SetPoint("CENTER", f, "TOPLEFT", (u - r[1]) * kx, -(v - r[3]) * ky)
		end
	end
	c.mini = f
end

-- a city's alpha for its zoom (a) and the terrain now: under it in the open, its minimap over it underground
local function Apply(c)
	local f, a = c.frame, c.alpha or 0
	-- (AzerothVeil: the Map module's "Minimap terrain in the capitals" off: the city's own map stays over the terrain)
	local under = FM.db.cityTerrain == false and 0 or under
	if c.underground then
		-- AzerothVeil: its own map fades out under the terrain too (as a city in the open), its minimap inside comes
		-- over the terrain in its place
		f:SetAlpha(a)
		local k = 1 - under
		if c.artAlpha ~= k then
			c.artAlpha = k
			for _, t in ipairs(c.art or {}) do t:SetAlpha(k) end
		end
		local m = a >= 1 and under or 0
		if m > 0.003 and c.mini == nil then MinimapPictures(c) end
		if c.mini then
			c.mini:SetAlpha(m)
			c.mini:SetShown(m > 0.003)
		end
	else
		f:SetAlpha(a * (1 - under))
	end
end

-- (the terrain fading in or out: Terrain.lua, as it goes)
function C.SetTerrain(k)
	if k == under then return end
	under = k
	for _, c in ipairs(cities) do
		if c.frame:IsShown() then Apply(c) end
	end
end

-- AzerothVeil: the zones' banners for their cities (Media\CityBanner, OpenMap's) are lettered in English: shown as they are
-- for a game in English; in another language, the zone's own art (the client's, lettered in its language) cut to the
-- banner's shape (that picture as the mask), made the first time it shows (the tiles have the zones' own cut out)
local ENGLISH = ({ enUS = true, enGB = true })[GetLocale and GetLocale() or "enUS"] or false

local function BuildBanner(c)
	c.bannerBuilt = true
	local f, b = c.banner, c.bannerDef
	local zone = b[1]
	local layers = C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(zone)
	local info = layers and layers[1]
	local files = info and C_Map.GetMapArtLayerTextures(zone, 1)
	if not info or not files or (info.layerWidth or 0) <= 0 then return end
	local mask = f:CreateMaskTexture()
	mask:SetTexture(MEDIA .. "CityBanner\\" .. c.id, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetSize(b[4], b[5])
	mask:SetPoint("TOPLEFT", f, "TOPLEFT", b[2], -b[3])
	local lw, lh, tw, th = info.layerWidth, info.layerHeight, info.tileWidth, info.tileHeight
	local sx, sy = ART_W / lw, ART_H / lh
	local x0, y0, x1, y1 = b[2] / sx, b[3] / sy, (b[2] + b[4]) / sx, (b[3] + b[5]) / sy   -- (the banner, in the layer's px)
	-- (a file of the art laid at bx, by (its picture bw x bh, the file fw x fh), cut to the banner)
	local function Crop(file, sub, bx, by, bw, bh, fw, fh)
		local ix0, iy0 = math.max(x0, bx), math.max(y0, by)
		local ix1, iy1 = math.min(x1, bx + bw), math.min(y1, by + bh)
		if bw > 0 and bh > 0 and ix1 > ix0 and iy1 > iy0 then
			local t = f:CreateTexture(nil, "OVERLAY", nil, sub)
			t:SetTexture(file, nil, nil, "TRILINEAR")
			t:SetTexCoord((ix0 - bx) / fw, (ix1 - bx) / fw, (iy0 - by) / fh, (iy1 - by) / fh)
			t:SetPoint("TOPLEFT", f, "TOPLEFT", ix0 * sx, -iy0 * sy)
			t:SetPoint("BOTTOMRIGHT", f, "TOPLEFT", ix1 * sx, -iy1 * sy)
			t:AddMaskTexture(mask)
		end
	end
	-- its base art (the banner there, blank)...
	local cols = math.ceil(lw / tw)
	for i, file in ipairs(files) do
		local bx, by = ((i - 1) % cols) * tw, math.floor((i - 1) / cols) * th
		Crop(file, 0, bx, by, math.min(tw, lw - bx), math.min(th, lh - by), tw, th)
	end
	-- ... and over it its pieces (Data/Fog.lua, FM.FOG_PIECES: every one, explored or not), the banner's name lettered
	-- on them, each cut in tiles as Blizzard's map cuts them (a piece's last row and column in files of the next power of two)
	local art = C_Map.GetMapArtID and FM.Plain(C_Map.GetMapArtID(zone))
	local function Pow2(px) local s = 16 while s < px do s = s * 2 end return s end
	for key, list in pairs(art and FM.FOG_PIECES and FM.FOG_PIECES[art] or {}) do
		local pw, ph, px, py = key:match("^(%d+):(%d+):(%d+):(%d+)$")
		pw, ph, px, py = tonumber(pw), tonumber(ph), tonumber(px), tonumber(py)
		if pw and px < x1 and px + pw > x0 and py < y1 and py + ph > y0 then
			local ids = {}
			for fid in tostring(list):gmatch("%d+") do ids[#ids + 1] = tonumber(fid) end
			local across, down = math.ceil(pw / tw), math.ceil(ph / th)
			for j = 1, down do
				local h = j < down and th or (ph - (down - 1) * th)
				for k = 1, across do
					local w = k < across and tw or (pw - (across - 1) * tw)
					local file = ids[(j - 1) * across + k]
					if file then
						Crop(file, 1, px + tw * (k - 1), py + th * (j - 1), w, h,
							k < across and tw or Pow2(w), j < down and th or Pow2(h))
					end
				end
			end
		end
	end
end

function C.Init(parent)
	layer = parent
	for id, def in pairs(CITIES) do
		local r = Geo.Rect(id)
		if r then
			local c = { id = id, cut = def.cut, title = def.title, r = r, underground = UNDERGROUND[id] }
			c.frame = ArtFrame(r)
			-- (the city on its layer's own level, its banner one over: both under the world's art, Map.lua's worldArt,
			-- one level up, which covers them as it comes in zoomed right out)
			c.frame:SetFrameLevel(layer:GetFrameLevel())
			local b = BANNERS[id]
			local zr = b and Geo.Rect(b[1])
			if zr then
				-- (the banner on a frame laid out in its zone's art pixels, over the city)
				c.banner = ArtFrame(zr)
				c.banner:SetFrameLevel(layer:GetFrameLevel() + 1)
				c.bannerDef = b
				if ENGLISH then
					local t = c.banner:CreateTexture(nil, "OVERLAY")
					t:SetTexture(MEDIA .. "CityBanner\\" .. id)
					t:SetSize(b[4], b[5])
					t:SetPoint("TOPLEFT", c.banner, "TOPLEFT", b[2], -b[3])
					c.bannerBuilt = true
				end
			end
			cities[#cities + 1] = c
		end
	end
end

local function InView(r, left, top, x1, y1)
	return r[2] > left and r[1] < x1 and r[4] > top and r[3] < y1
end

-- (shown from M's opening zoom; laid out unseen over the two wheel steps before it. AzerothVeil: from Map.CITIES_ZOOM)
local function FadeRange()
	local step = FM.Map.ZOOM_STEP
	local open = FM.Map.CITIES_ZOOM
	return open / (step * step), open
end

function C.Layout(left, top, scale, vw, vh, zoom)
	local x1, y1 = left + vw / scale, top + vh / scale
	local z0, z1 = FadeRange()
	zoom = zoom or 0
	-- (just before, there at 1% only, so the client has loaded its files. AzerothVeil: over the wheel's step before it,
	-- from the step's own zoom, the city fades in as the zoom goes, its zone's banner for it out: the wheel's step
	-- animates, so the fade runs with it; a step of the wheel lands on one or the other, never between)
	local p = zoom >= z1 and 1 or FM.Map.Between(zoom, 7, 9)        -- (steps 7 to 9: Map.lua)
	local a = zoom >= z1 and 1 or zoom >= z0 and math.max(0.01, p) or 0
	for _, c in ipairs(cities) do
		local f = c.frame
		if a > 0.003 and not c.failed and InView(c.r, left, top, x1, y1) then
			if not c.built then Build(c) end
			Place(f, left, top, scale)
			c.alpha = a
			Apply(c)                                       -- (AzerothVeil: with the terrain)
			f:Show()
		elseif f:IsShown() then
			f:Hide()
		end
		local b = c.banner
		if b then
			local ba = 1 - p                                -- (AzerothVeil: gone as the city's own map comes in)
			if ba > 0.003 and InView(b.rect, left, top, x1, y1) then
				if not c.bannerBuilt then BuildBanner(c) end      -- (AzerothVeil: another language: the zone's own)
				Place(b, left, top, scale)
				b:SetAlpha(ba)
				b:Show()
			elseif b:IsShown() then
				b:Hide()
			end
		end
	end
end
