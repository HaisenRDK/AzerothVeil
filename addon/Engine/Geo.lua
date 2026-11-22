-- Geometry: everything on the map is placed in world units (Azeroth 947 art pixels), from the
-- Forever client's own map tables (C_Map), read once and cached.
local _, FM = ...
local Geo = {}
FM.Geo = Geo

local W, H, WORLD = FM.W, FM.H, FM.WORLD
Geo.CONTINENTS = { 1414, 1415 }   -- Kalimdor, Eastern Kingdoms
local split                       -- world x where Kalimdor's rectangle hands over to the Eastern Kingdoms'

-- Lands off the world map: a continent of their own in the game (an instance of their own), not on
-- Azeroth's map. Each has a place in world units of its own, past the world's right edge where the
-- world's map never goes, at the continents' scale (its size in yards, from the game): everything on it
-- (you, your group, quests, Questie, townsfolk, points of interest...) is placed there as on any zone, and
-- the map shows it alone, as a map apart (Map.SetAway, Isles.lua).
--   map: its UiMap; instance: its world's; u0, v0: its place's top-left corner
Geo.AWAY = {
	{ map = 2521, instance = 2991, u0 = W + 100, v0 = 100 },   -- Zephras Isle (the Skyborn's start)
}

local rects = {}
local AwayRect
-- a map's rectangle on the world, in units: { left, right, top, bottom }, or nil
function Geo.Rect(mapID)
	local r = rects[mapID]
	if r == nil then
		local l, rr, t, b = C_Map.GetMapRectOnMap(mapID, WORLD)
		if l and rr and t and b and rr > l and b > t then
			r = { l * W, rr * W, t * H, b * H }
		else
			r = AwayRect(mapID) or false
		end
		rects[mapID] = r
	end
	return r or nil
end

-- yards per world unit: Kalimdor's, across
local function YardsPerUnit()
	local r = Geo.Rect(1414)
	local _, p0 = C_Map.GetWorldPosFromMapPos(1414, CreateVector2D(0, 0))
	local _, p1 = C_Map.GetWorldPosFromMapPos(1414, CreateVector2D(1, 0))
	if not (r and p0 and p1) then return nil end
	local _, y0 = p0:GetXY()
	local _, y1 = p1:GetXY()
	local k = math.abs(y1 - y0) / (r[2] - r[1])
	return k > 0 and k or nil
end

-- an away land's rectangle (its size in yards at the continents' scale, at its place), or that of a map
-- inside one (its place on the land's map)
function AwayRect(mapID)
	for _, a in ipairs(Geo.AWAY) do
		if mapID == a.map then
			local w, h = 90, 60
			local _, p0 = C_Map.GetWorldPosFromMapPos(a.map, CreateVector2D(0, 0))
			local _, p1 = C_Map.GetWorldPosFromMapPos(a.map, CreateVector2D(1, 1))
			local ypu = YardsPerUnit()
			if p0 and p1 and ypu then
				local x0, y0 = p0:GetXY()
				local x1, y1 = p1:GetXY()
				local ww, hh = math.abs(y1 - y0) / ypu, math.abs(x1 - x0) / ypu
				if ww > 1 and hh > 1 and ww < 800 and hh < 500 then w, h = ww, hh end
			end
			return { a.u0, a.u0 + w, a.v0, a.v0 + h }
		end
	end
	for _, a in ipairs(Geo.AWAY) do
		local l, rr, t, b = C_Map.GetMapRectOnMap(mapID, a.map)
		local ar = l and Geo.Rect(a.map)
		if ar and rr and t and b and rr > l and b > t then
			local aw, ah = ar[2] - ar[1], ar[4] - ar[3]
			return { ar[1] + l * aw, ar[1] + rr * aw, ar[3] + t * ah, ar[3] + b * ah }
		end
	end
end

-- the away land a world point is on (its map), else nil
function Geo.AwayAt(u, v)
	if u <= W then return nil end
	for _, a in ipairs(Geo.AWAY) do
		local r = Geo.Rect(a.map)
		if r and u >= r[1] and u <= r[2] and v >= r[3] and v <= r[4] then return a.map end
	end
end

-- the away land a map is (or is inside of): its map, else nil
function Geo.AwayOf(mapID)
	local id = mapID
	for _ = 1, 8 do
		if not id or id == 0 then return nil end
		for _, a in ipairs(Geo.AWAY) do
			if id == a.map then return a.map end
		end
		local info = C_Map.GetMapInfo(id)
		id = info and info.parentMapID
	end
end

-- the away land of a world (an instance ID), else nil
function Geo.AwayOfInstance(instanceID)
	for _, a in ipairs(Geo.AWAY) do
		if instanceID == a.instance then return a.map end
	end
end

function Geo.MapToUnits(mapID, x, y)
	local r = Geo.Rect(mapID)
	if r then return r[1] + x * (r[2] - r[1]), r[3] + y * (r[4] - r[3]) end
end

function Geo.UnitsToMap(mapID, u, v)
	local r = Geo.Rect(mapID)
	if r then return (u - r[1]) / (r[2] - r[1]), (v - r[3]) / (r[4] - r[3]) end
end

-- the continent a world point belongs to (its rectangle, split down the open sea between them; an away
-- land's own map on it)
function Geo.ContinentAt(u, v)
	local away = Geo.AwayAt(u, v)
	if away then return away end
	if not split then
		local k, e = Geo.Rect(1414), Geo.Rect(1415)
		split = (k and e) and (k[2] + e[1]) / 2 or W / 2
	end
	local id = u < split and 1414 or 1415
	local r = Geo.Rect(id)
	if r and u >= r[1] and u <= r[2] and v >= r[3] and v <= r[4] then return id end
end

-- the zone (or city) under a world point: mapID, name, continentID
function Geo.ZoneAt(u, v)
	local cont = Geo.ContinentAt(u, v)
	if not cont then return end
	local x, y = Geo.UnitsToMap(cont, u, v)
	local info = C_Map.GetMapInfoAtPosition(cont, x, y)
	if info and info.mapID and info.mapID ~= cont then return info.mapID, info.name, cont end
	-- (an away land is a zone itself: its own map, where no smaller one is)
	if Geo.AwayAt(u, v) then
		local own = C_Map.GetMapInfo(cont)
		return cont, own and own.name, cont
	end
	return nil, nil, cont
end

-- world positions (UnitPosition, the game's tables: first value north, second west) per instance
local worlds = {}
local worldsRead = false
local function ReadWorlds()
	worldsRead = true
	local maps = {}
	for _, cont in ipairs(Geo.CONTINENTS) do maps[#maps + 1] = cont end
	for _, a in ipairs(Geo.AWAY) do maps[#maps + 1] = a.map end
	for _, cont in ipairs(maps) do
		local i0, p0 = C_Map.GetWorldPosFromMapPos(cont, CreateVector2D(0, 0))
		local i1, p1 = C_Map.GetWorldPosFromMapPos(cont, CreateVector2D(0.5, 0.5))
		if i0 and p0 and p1 and i0 == i1 then
			local x0, y0 = p0:GetXY()
			local x1, y1 = p1:GetXY()
			if x1 ~= x0 and y1 ~= y0 then
				worlds[i0] = { cont = cont, x0 = x0, y0 = y0, dx = (x1 - x0) * 2, dy = (y1 - y0) * 2 }
			end
		end
	end
end

-- (instanceID, north, west) -> world units, or nil off the stitched continents
function Geo.WorldToUnits(instanceID, a, b)
	if not worldsRead then ReadWorlds() end
	local w = instanceID and worlds[instanceID]
	if not w or not a or not b then return end
	return Geo.MapToUnits(w.cont, (b - w.y0) / w.dy, (a - w.x0) / w.dx)
end

-- a unit's position in world units (nil in instances, or when the client keeps it secret)
local UnitPosition, Plain = UnitPosition, FM.Plain
function Geo.UnitUnits(unit)
	local a, b, _, inst = UnitPosition(unit)
	a, b, inst = Plain(a), Plain(b), Plain(inst)
	if not a then return end
	return Geo.WorldToUnits(inst, a, b)
end
