-- The cities, as OpenMap draws them: the stitched tiles carry every zone but not the cities (each
-- zone's own art is cut where a city's map goes, and where its name banner for the city was), so
-- each city's own map comes from the client (C_Map art layer), cut to the city's plan (OpenMap's
-- MapCityMask) or with a round feather, and shows at once, whole, from the zoom M opens the map at (by
-- zoom, not by the window's size): over the two steps of the wheel before it it's already laid out,
-- unseen, so its files are loaded by then and it never comes in piece by piece.
-- The zone's name banner for the city (Media\CityBanner) shows with the zone, and gives way to the
-- city's own title as the city comes in. One frame per city, scaled as a whole: a pan or zoom moves
-- one frame, not its tiles; a city off the view, or not near its zoom, is hidden (its files not loaded).
local _, FM = ...
local C = {}
FM.Cities = C

local Geo = FM.Geo
local MEDIA = "Interface\\AddOns\\PerfectMap\\Media\\"
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

local layer
local cities = {}

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
		end
	end
	c.built = true
end

function C.Init(parent)
	layer = parent
	for id, def in pairs(CITIES) do
		local r = Geo.Rect(id)
		if r then
			local c = { id = id, cut = def.cut, title = def.title, r = r }
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
				local t = c.banner:CreateTexture(nil, "OVERLAY")
				t:SetTexture(MEDIA .. "CityBanner\\" .. id)
				t:SetSize(b[4], b[5])
				t:SetPoint("TOPLEFT", c.banner, "TOPLEFT", b[2], -b[3])
			end
			cities[#cities + 1] = c
		end
	end
end

local function InView(r, left, top, x1, y1)
	return r[2] > left and r[1] < x1 and r[4] > top and r[3] < y1
end

-- (shown from M's opening zoom; laid out unseen over the two wheel steps before it)
local function FadeRange()
	local step = FM.Map.ZOOM_STEP
	local open = FM.W / FM.Map.OPEN_ACROSS * 0.97
	return open / (step * step), open
end

function C.Layout(left, top, scale, vw, vh, zoom)
	local x1, y1 = left + vw / scale, top + vh / scale
	local z0, z1 = FadeRange()
	zoom = zoom or 0
	-- (no fading: there, or not; just before, there at 1% only, so the client has loaded its files)
	local a = zoom >= z1 and 1 or zoom >= z0 and 0.01 or 0
	for _, c in ipairs(cities) do
		local f = c.frame
		if a > 0.003 and not c.failed and InView(c.r, left, top, x1, y1) then
			if not c.built then Build(c) end
			Place(f, left, top, scale)
			f:SetAlpha(a)
			f:Show()
		elseif f:IsShown() then
			f:Hide()
		end
		local b = c.banner
		if b then
			local ba = (c.title and a >= 1) and 0 or 1      -- (gone the moment the city's own title is there)
			if ba > 0.003 and InView(b.rect, left, top, x1, y1) then
				Place(b, left, top, scale)
				b:SetAlpha(ba)
				b:Show()
			elseif b:IsShown() then
				b:Hide()
			end
		end
	end
end

