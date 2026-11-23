-- AzerothVeil — Engine/Names.lua: the continents' and seas' names on the map zoomed out (the Map module's
-- "Continents' and seas' names"), lettered as OpenMap letters them (Map/Stitch.lua, MIT): where Blizzard's map art
-- had them (Data/MapNames.lua), in the client's font (Friz Quadrata; its own in other alphabets), dark ink, a capital
-- starting each word and small capitals after, set wide across the art's line, in a soft light halo (copies of each
-- letter in a tight ring round it).
-- Cheap: built once, the first time it shows (one frame, in world units x UNITS, scaled as a whole: a pan or zoom
-- moves one frame); land and sea names fade by the zoom (the continents' under the world's own art right out, the
-- zones' art taking over closer in); nothing laid out while they don't show.
local _, FM = ...
local N = {}
FM.Names = N

local Geo = FM.Geo
local UNITS = 4                 -- font units per world unit
local CAP = 0.69                -- Friz Quadrata's capital height, in font sizes
local MIDDLE = 0.36             -- ... the middle of its letters' box, above the baseline
local SMALL = 0.78              -- small capitals, to the capitals
local TRACK = 0.1               -- the least letter spacing, in cap heights
local SPACE = 0.4               -- a word space, in cap heights
local TRACK_MAX = 0.3           -- AzerothVeil: the most letter spacing, in cap heights (a shorter word, another language's,
                                -- isn't stretched across the English one's whole line)
local EDGE = 12                 -- AzerothVeil: world units a name keeps clear of the world's edges
local HALO_R = 0.09             -- the halo's ring, in cap heights
local INK_ALPHA = 0.9
local NONE = {}

local layer, root
local groups = {}               -- "land" / "sea" -> frame
local built = false

local function Smooth(x, a, b)
	local t = math.max(0, math.min(1, (x - a) / (b - a)))
	return t * t * (3 - 2 * t)
end

-- a map's art rectangle on the world, in world units (the world's own: the whole of it)
local function Rect(map)
	if map == FM.WORLD then return { 0, FM.W, 0, FM.H } end
	return Geo.Rect(map)
end

local function NameOf(label)
	local n, text = label.name, nil
	if n.map then
		local info = C_Map.GetMapInfo(n.map)
		text = info and FM.Plain(info.name)
	elseif n.area then
		text = FM.Plain(C_Map.GetAreaInfo(n.area))
	end
	return (type(text) == "string" and text ~= "") and text or n.text
end

-- the name's words onto the art's lines: one each, or (another language's, more or fewer words) all on the widest
local function SetLines(label, text)
	local words = {}
	for word in text:gmatch("%S+") do words[#words + 1] = word end
	local lines = label.lines
	if #words == #lines then
		local out = {}
		for i, line in ipairs(lines) do out[i] = { line, words[i] } end
		return out
	end
	local widest = lines[1]
	for _, line in ipairs(lines) do
		if line[2] - line[1] > widest[2] - widest[1] then widest = line end
	end
	return { { widest, text } }
end

local function Letter(f, label)
	local r = Rect(label.map)
	if not r then return end
	local sx, sy = (r[2] - r[1]) / FM.W, (r[4] - r[3]) / FM.H
	local ink, glow = label.ink, label.glow
	local font = FM.Style.FontPath()
	for _, set in ipairs(SetLines(label, NameOf(label))) do
		local line, text = set[1], set[2]
		local left, right = (r[1] + line[1] * sx) * UNITS, (r[1] + line[2] * sx) * UNITS
		local base, cap = (r[3] + line[3] * sy) * UNITS, line[4] * sy * UNITS
		local glyphs, width, wordStart = {}, 0, true
		for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
			if ch == " " then
				glyphs[#glyphs + 1] = { w = SPACE * cap }
				width = width + SPACE * cap
				wordStart = true
			else
				local size = cap / CAP * ((wordStart or line[5]) and 1 or SMALL)
				local fs = f:CreateFontString(nil, "OVERLAY")
				fs:SetFont(font, size, "")
				fs:SetText(#ch == 1 and ch:upper() or (ch:upper() ~= ch and ch:upper() or ch))
				fs:SetTextColor(ink[1] / 255, ink[2] / 255, ink[3] / 255, INK_ALPHA)
				fs:SetShadowOffset(0, 0)
				local w = fs:GetStringWidth()
				glyphs[#glyphs + 1] = { fs = fs, size = size, w = w }
				width = width + w
				wordStart = false
			end
		end
		local gaps = #glyphs - 1
		local track = gaps > 0 and math.min(TRACK_MAX * cap, math.max(TRACK * cap, (right - left - width) / gaps)) or 0
		local total = width + track * gaps
		local x = (left + right) / 2 - total / 2
		-- (AzerothVeil: the whole name inside the world, clear of its edges)
		local lo, hi = EDGE * UNITS, (FM.W - EDGE) * UNITS
		if x + total > hi then x = hi - total end
		if x < lo then x = lo end
		for _, g in ipairs(glyphs) do
			if g.fs then
				local y = -base + MIDDLE * g.size
				g.fs:SetPoint("LEFT", f, "TOPLEFT", x, y)
				-- the halo: 8 copies in a tight ring round it, in the glow's colour (no shadows: a shadow's offset isn't
				-- scaled with the name, and showed as a second, ghost letter)
				local rr, a = HALO_R * cap, math.min(1, label.glowA / 4)
				for i = 1, 8 do
					local angle = (i - 1) / 8 * 2 * math.pi
					local dx, dy = rr * math.cos(angle), rr * math.sin(angle)
					local copy = f:CreateFontString(nil, "ARTWORK")
					copy:SetFont(font, g.size, "")
					copy:SetText(g.fs:GetText())
					copy:SetTextColor(glow[1] / 255, glow[2] / 255, glow[3] / 255, a)
					copy:SetShadowOffset(0, 0)
					copy:SetShadowColor(0, 0, 0, 0)
					copy:SetPoint("LEFT", f, "TOPLEFT", x + dx, y + dy)
				end
			end
			x = x + g.w + track
		end
	end
end

local function Build()
	built = true
	root = CreateFrame("Frame", nil, layer)
	root:SetSize(1, 1)
	for _, kind in ipairs({ "land", "sea" }) do
		local g = CreateFrame("Frame", nil, root)
		g:SetPoint("TOPLEFT")
		g:SetSize(1, 1)
		groups[kind] = g
	end
	for _, label in ipairs(FM.MAP_NAMES or NONE) do
		local g = groups[label.fade] or groups.sea
		pcall(Letter, g, label)
	end
end

function N.Init(parent)
	layer = parent
end

-- every pan / zoom: zoom as Map.lua has it (1: the whole world), worldAlpha the world's own art's
function N.Layout(left, top, scale, zoom, worldAlpha)
	if not layer then return end
	local on = FM.db.mapNames ~= false
	-- (right out over the world's own art too, cleaned of its names (Map.lua): until the zones' art is near enough
	-- to read; the seas a little longer)
	-- (two steps of the wheel further in than they first were)
	local k = (FM.Map.ZOOM_STEP or 1.25) ^ 2
	local land = on and (1 - Smooth(zoom, 1.6 * k, 2.4 * k)) or 0
	local sea = on and (1 - Smooth(zoom, 2.0 * k, 3.0 * k)) or 0
	if land <= 0.01 and sea <= 0.01 then
		if root then root:Hide() end
		return
	end
	if not built then Build() end
	local k = scale / UNITS
	root:SetScale(k)
	root:ClearAllPoints()
	root:SetPoint("TOPLEFT", layer, "TOPLEFT", -left * UNITS, top * UNITS)
	groups.land:SetAlpha(land)
	groups.sea:SetAlpha(sea)
	root:Show()
end
