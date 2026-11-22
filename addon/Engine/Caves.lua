-- Underground, as OpenMap does it (Map/Close.lua, MIT): caves, mines, crypts and dungeon entrance areas.
-- Zoomed in to where the minimap's terrain comes in (Terrain.lua), a cave in view that fills enough of it
-- shows at its real place, at once and whole (no fading in): Blizzard's own map of it where it drew one (Data/Caves.lua: its micro maps,
-- frameless through Media/CaveMask), else the game's minimap of it inside (Data/CaveMinimap.lua: its WMOs'
-- minimap pictures, each a square turned as the cave lies, toned as the minimap is). The surface round the
-- one you're centred on dims, so it stands out; zoom back out and it's gone again. Just before (a step out,
-- or a little less of the view), it's laid out unseen, so its files are loaded by the time it shows.
-- One frame per cave, laid out in its own units and scaled as a whole: a pan or zoom moves one frame.
local _, FM = ...
local C = {}
FM.Caves = C

local Geo = FM.Geo
local MEDIA = "Interface\\AddOns\\PerfectMap\\Media\\"
local min, max, floor = math.min, math.max, math.floor

local UNDER = 4                             -- view width / cave width it shows from (a quarter of the view, its longer way)
local WARM = 1.5                            -- ... and, this much less of the view, laid out unseen
-- (Blackrock Mountain's deeper floors never surface by themselves: they lie under its main one)
local UNDER_SKIP = { [34] = true, [35] = true }
local FOCUS = 0.8                           -- (how far off the middle of the view a cave still dims the surface)
local MINI_DESAT = 0.35                     -- (the minimap's pictures toned as the minimap up close)
local PAPER = { 1, 0.93, 0.80 }
local K = 16                                -- a cave frame's own units: px a world unit

local layer, dim
local caves = {}                            -- key -> cave { frame, r } or false; Blizzard's by map ID, the minimap's by -index
local rects = {}

-- world yards (continent's instance, X north, Y west) -> world units
local function Units(cont, x, y) return Geo.WorldToUnits(cont, x, y) end

-- a box of yards on the world: { u0, v0, u1, v1 } (its corners: north-west is the larger X and Y)
local function Box(cont, minX, minY, maxX, maxY)
	local u0, v0 = Units(cont, maxX, maxY)
	local u1, v1 = Units(cont, minX, minY)
	if not (u0 and u1) then return nil end
	return { min(u0, u1), min(v0, v1), max(u0, u1), max(v0, v1) }
end

local function RectOf(key)
	local r = rects[key]
	if r == nil then
		if key > 0 then
			local c = FM.CAVES[key]
			r = Box(c[2], c[3], c[4], c[5], c[6]) or false
		else
			local c = FM.CAVE_MINIMAP[-key]
			r = Box(c[1], c[2], c[3], c[4], c[5]) or false
		end
		rects[key] = r
	end
	return r or nil
end

-- a frame over a cave's box, in units of 1 / K world unit from its top-left
local function Frame(r)
	local f = CreateFrame("Frame", nil, layer)
	f:SetSize((r[3] - r[1]) * K, (r[4] - r[2]) * K)
	f:SetFrameLevel(layer:GetFrameLevel() + 1)
	f:Hide()
	return f
end

-- Blizzard's map of a cave: its 4 x 3 tiles (1002 x 668 of them drawn) through its mask
local function Blizzard(key, c, r)
	local f = Frame(r)
	local W, H = f:GetSize()
	local mask = f:CreateMaskTexture()
	mask:SetTexture(MEDIA .. "CaveMask\\" .. key, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(f)
	local tw, th = W / (1002 / 256), H / (668 / 256)          -- (one 256 px tile, in the frame's units)
	for n, fid in ipairs(c[11]) do
		local col, row = (n - 1) % 4, floor((n - 1) / 4)
		local pw, ph = min(256, 1002 - col * 256), min(256, 668 - row * 256)
		local t = f:CreateTexture(nil, "ARTWORK")
		t:SetTexture(fid, nil, nil, "TRILINEAR")
		t:SetTexCoord(0, pw / 256, 0, ph / 256)
		t:SetPoint("TOPLEFT", f, "TOPLEFT", col * tw, -row * th)
		t:SetPoint("BOTTOMRIGHT", f, "TOPLEFT", col * tw + tw * pw / 256, -(row * th + th * ph / 256))
		t:AddMaskTexture(mask)
	end
	return { frame = f, r = r }
end

-- the game's minimap of a cave: its pictures (file, centre X, Y, side in yards, rotation, u1, v0), each
-- a square turned about its centre, lowest floor first, under the ones above it
local function Minimap(c, r)
	local f = Frame(r)
	local p = c[6]
	local n = #p / 7
	for i = 1, n do
		local j = (i - 1) * 7
		local u, v = Units(c[1], p[j + 2], p[j + 3])
		local u2 = Units(c[1], p[j + 2], p[j + 3] + p[j + 4])     -- (a side's length, in units)
		if u and u2 then
			local side = math.abs(u2 - u) * K
			local t = f:CreateTexture(nil, "ARTWORK", nil, min(7, floor((i - 1) * 16 / n) - 8))
			t:SetTexture(p[j + 1], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "TRILINEAR")
			t:SetTexCoord(0, p[j + 6], p[j + 7], 1)
			t:SetRotation(p[j + 5])
			t:SetDesaturation(MINI_DESAT)
			t:SetVertexColor(PAPER[1], PAPER[2], PAPER[3])
			t:SetSize(side, side)
			t:SetPoint("CENTER", f, "TOPLEFT", (u - r[1]) * K, -(v - r[2]) * K)
		end
	end
	return { frame = f, r = r }
end

local function CaveOf(key)
	local cave = caves[key]
	if cave == nil then
		local r = RectOf(key)
		if not r then cave = false
		elseif key > 0 then cave = Blizzard(key, FM.CAVES[key], r)
		else cave = Minimap(FM.CAVE_MINIMAP[-key], r) end
		caves[key] = cave
	end
	return cave
end

-- one map per place: a cave with several floors in one spot (Tiragarde Keep) shows its first
local primary
local function Primary(key, c)
	if not primary then
		primary = {}
		for k, cc in pairs(FM.CAVES or {}) do
			if not UNDER_SKIP[k] and (not primary[cc[1]] or k < primary[cc[1]]) then primary[cc[1]] = k end
		end
	end
	return primary[c[1]] == key
end

function C.Init(parent)
	layer = parent
	dim = layer:CreateTexture(nil, "BACKGROUND")
	dim:SetColorTexture(0.05, 0.035, 0.02, 1)
	dim:SetAllPoints()
	dim:Hide()
end

-- every cave that may surface, with its box: key, rect, key, rect ... (worked out once)
local candidates
local function Candidates()
	if candidates then return candidates end
	candidates = {}
	for key, c in pairs(FM.CAVES) do
		local r = not UNDER_SKIP[key] and Primary(key, c) and RectOf(key)
		if r then candidates[#candidates + 1] = key candidates[#candidates + 1] = r end
	end
	for i in ipairs(FM.CAVE_MINIMAP) do
		local r = RectOf(-i)
		if r then candidates[#candidates + 1] = -i candidates[#candidates + 1] = r end
	end
	return candidates
end

-- whether a spot (world units) is in a cave's box
function C.Contains(u, v)
	local list = Candidates()
	for i = 1, #list, 2 do
		local r = list[i + 1]
		if u >= r[1] and u <= r[3] and v >= r[2] and v <= r[4] then return true end
	end
	return false
end

local shown = {}
-- every pan / zoom: deepest/fit as Terrain.Layout has it
function C.Layout(left, top, scale, vw, vh, zoom, deepest)
	if not layer then return end
	wipe(shown)
	local focus = false
	-- (with the minimap's terrain; laid out unseen from the step before it)
	local switch = FM.Terrain.SwitchZoom(deepest)
	zoom = zoom or 0
	local on = FM.db.underground ~= false and zoom >= switch
	local near = FM.db.underground ~= false and zoom >= switch / FM.Map.ZOOM_STEP
	if near then
		local hu, hv = vw / scale / 2, vh / scale / 2
		local u, v = left + hu, top + hv
		local list = Candidates()
		for i = 1, #list, 2 do
			local key, r = list[i], list[i + 1]
			if r[3] > u - hu and r[1] < u + hu and r[4] > v - hv and r[2] < v + hv then
				local fill = min((2 * hu) / (r[3] - r[1]), (2 * hv) / (r[4] - r[2]))   -- view / cave, its longer way
				if on and fill <= UNDER then
					shown[key] = 1
					local off = max(math.abs((r[1] + r[3]) / 2 - u) / hu, math.abs((r[2] + r[4]) / 2 - v) / hv)
					if off < FOCUS then focus = true end
				elseif fill <= UNDER * WARM then
					shown[key] = 0.01               -- (unseen: its files loading)
				end
			end
		end
	end
	for key, cave in pairs(caves) do
		if cave and not shown[key] and cave.frame:IsShown() then cave.frame:Hide() end
	end
	local k = scale / K
	for key, t in pairs(shown) do
		local cave = CaveOf(key)
		if cave then
			local f, r = cave.frame, cave.r
			f:SetScale(k)
			f:ClearAllPoints()
			f:SetPoint("TOPLEFT", layer, "TOPLEFT", (r[1] - left) * scale / k, (top - r[2]) * scale / k)
			f:SetAlpha(t)
			f:Show()
		end
	end
	-- (the surface round the cave you're centred on, dimmed)
	if focus then dim:SetAlpha(0.45) dim:Show() else dim:Hide() end
end
