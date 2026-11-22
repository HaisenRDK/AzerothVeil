-- AzerothVeil — Engine/Labels.lua: the places' names up close (the Map module's "Places' names up close").
-- The painted map writes its places' names (villages, camps, mines...) into its art; up close the minimap's terrain
-- (Terrain.lua) takes the art's place, and the names went with it. Here they're lettered again over the terrain,
-- at the middle of each place's ground (Data/AreaLabels.lua, from OpenMap's Explore.lua, MIT), in the player's
-- language (the client's names, C_Map.GetAreaInfo). They come and go with the terrain (Terrain.lua's mix: the
-- whole layer's alpha). With the fog of war on, only the places you've explored (their piece among the ones the
-- game lists as explored), as the painted map shows only those. AzerothVeil: the zones WoW Forever drew again
-- too (FM.AREA_LABEL_ALIAS), and the capitals' districts (FM.CITY_DISTRICTS, the Map module's own option).
-- Cheap: a zone's names read the first time it's in view up close (again only once more is explored, with the
-- fog on); one pooled font string per name in view; nothing laid out while the terrain isn't there.
local _, FM = ...
local Lb = {}
FM.Labels = Lb

local Geo, S, L = FM.Geo, FM.Style, FM.L
local NONE = {}
local SIZE = 12
local DISTRICT_SIZE = 11                  -- (AzerothVeil: the capitals' districts, a size under the places)
local ART_W, ART_H = 1002, 668            -- (a zone's art, in its pixels: the pieces' units)
local INK = { 1, 0.82, 0 }                -- (gold, outlined: Blizzard's own names over the land)

local layer
local zones                               -- { id, r, list = { { key, u, v, name } }, explored = { [key] = true } }
local pool, used = {}, {}

local function Zones()
	if zones then return zones end
	zones = {}
	for _, id in ipairs(FM.FOG_ZONES or NONE) do
		local r = Geo.Rect(id)
		if r then zones[#zones + 1] = { id = id, r = r } end
	end
	-- AzerothVeil: and the capitals, for their districts
	for id in pairs(FM.CITY_DISTRICTS or NONE) do
		local r = Geo.Rect(id)
		if r then zones[#zones + 1] = { id = id, r = r, city = true } end
	end
	return zones
end

-- (a piece's "w:h:x:y" -> its "x:y")
local function Offset(key) return key:match("^%d+:%d+:(%d+:%d+)$") end

-- a zone's names: each place's, once (two pieces of one place: its first). AzerothVeil: a zone WoW Forever drew
-- again takes its old art's (FM.AREA_LABEL_ALIAS); a capital, its districts' names (FM.CITY_DISTRICTS, through L)
local function Read(z)
	z.list = {}
	if z.city then
		local data = FM.CITY_DISTRICTS[z.id]
		for i = 1, #data, 3 do
			local u, v = Geo.MapToUnits(z.id, data[i + 1], data[i + 2])
			if u then z.list[#z.list + 1] = { u = u, v = v, name = L[data[i]], district = true } end
		end
		return
	end
	local art = C_Map.GetMapArtID and FM.Plain(C_Map.GetMapArtID(z.id))
	local labels = FM.AREA_LABELS or NONE
	local data = art and (labels[art] or labels[(FM.AREA_LABEL_ALIAS or NONE)[art]])
	if not data then return end
	-- (the pieces of the zone's art as it is: an old art's piece known by where it is)
	z.pieces = {}
	for key in pairs(art and FM.FOG_PIECES and FM.FOG_PIECES[art] or NONE) do
		local off = Offset(key)
		if off then z.pieces[off] = true end
	end
	local seen = {}
	for i = 1, #data, 4 do
		local info = C_Map.GetAreaInfo and C_Map.GetAreaInfo(data[i + 1])
		local name = FM.Plain(info)
		if type(name) == "string" and name ~= "" and not seen[name] then
			seen[name] = true
			local u, v = Geo.MapToUnits(z.id, data[i + 2], data[i + 3])
			if u then
				z.list[#z.list + 1] = { key = data[i], off = Offset(data[i]), u = u, v = v, name = name,
					px = data[i + 2] * ART_W, py = data[i + 3] * ART_H }
			end
		end
	end
end

-- the pieces of a zone the game lists as explored (the fog's test), by their "w:h:x:y", by where they are, and
-- their rectangles (AzerothVeil)
local function Explored(z)
	local set, offs, rects = {}, {}, {}
	local get = C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures
	local ok, list = false, nil
	if get then ok, list = pcall(get, z.id) end
	for _, e in ipairs(ok and type(list) == "table" and list or NONE) do
		if e.textureWidth then
			set[e.textureWidth .. ":" .. e.textureHeight .. ":" .. e.offsetX .. ":" .. e.offsetY] = true
			offs[e.offsetX .. ":" .. e.offsetY] = true
			rects[#rects + 1] = { e.offsetX, e.offsetY, e.offsetX + e.textureWidth, e.offsetY + e.textureHeight }
		end
	end
	z.explored, z.exploredAt, z.exploredRects = set, offs, rects
end

-- AzerothVeil: a place explored: its piece itself, or one at the same spot (a zone drawn again); a place whose
-- piece is nowhere in the zone's art as it is now: explored if its middle is in an explored piece
local function IsExplored(z, e)
	if e.district then return true end           -- (a capital: no fog in it)
	if z.explored[e.key] or (e.off and z.exploredAt[e.off]) then return true end
	if e.off and z.pieces and z.pieces[e.off] then return false end
	for _, r in ipairs(z.exploredRects) do
		if e.px >= r[1] and e.px <= r[3] and e.py >= r[2] and e.py <= r[4] then return true end
	end
	return false
end

local function Acquire(size)
	local fs = table.remove(pool)
	if not fs then
		fs = layer:CreateFontString(nil, "OVERLAY")
		fs:SetTextColor(INK[1], INK[2], INK[3])
	end
	if fs.size ~= size then
		fs.size = size
		S.Font(fs, size, "OUTLINE")
		fs:SetShadowColor(0, 0, 0, 0)
	end
	used[#used + 1] = fs
	return fs
end

local function ReleaseAll()
	for i = #used, 1, -1 do
		used[i]:Hide()
		pool[#pool + 1] = used[i]
		used[i] = nil
	end
end

function Lb.Init(parent)
	layer = parent
	layer:SetAlpha(0)
end

-- every pan / zoom (after Terrain.Layout)
function Lb.Layout(left, top, scale, vw, vh)
	if not layer then return end
	ReleaseAll()
	if not (FM.db.terrainNames and FM.Terrain.Active()) then return end
	local x1, y1 = left + vw / scale, top + vh / scale
	local fog = FM.Fog and FM.Fog.IsEnabled()
	for _, z in ipairs(Zones()) do
		local r = z.r
		if r[2] > left and r[1] < x1 and r[4] > top and r[3] < y1 and (not z.city or FM.db.cityDistricts) then
			if not z.list then Read(z) end
			if fog and not z.city and not z.explored then Explored(z) end
			for _, e in ipairs(z.list) do
				if e.u > left and e.u < x1 and e.v > top and e.v < y1 and (not fog or IsExplored(z, e)) then
					local fs = Acquire(e.district and DISTRICT_SIZE or SIZE)
					fs:SetText(e.name)
					fs:ClearAllPoints()
					fs:SetPoint("CENTER", layer, "TOPLEFT", (e.u - left) * scale, -(e.v - top) * scale)
					fs:Show()
				end
			end
		end
	end
end

-- (the terrain fading in or out: Terrain.lua, as it goes)
function Lb.SetTerrain(k)
	if layer then layer:SetAlpha(k) end
end

-- the player explored more (MAP_EXPLORATION_UPDATED, with the fog on): read again when next in view
function Lb.Explored()
	for _, z in ipairs(zones or NONE) do z.explored = nil end
	if FM.Map.IsShown() then FM.Map.MarkDirty() end
end
