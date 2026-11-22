-- Boat and zeppelin routes: a thin, soft line along the way each vessel really sails (Data\Places.lua
-- sailings, from the game's tables; OpenMap's), dock to dock, the crossing between the two continents
-- a bowed arc. Alliance boats blue, the rest red, in the game's own faction colours. By default a route shows only with the
-- cursor on its harbor or zeppelin tower (only that dock's, easing in and out); with all of them on (the
-- option), they rest quiet until the cursor comes near one: then it lights up, a little wider, and says
-- where it runs. Light: one frame per route, laid out once; nothing built until a route first shows.
local _, FM = ...
local R = {}
FM.Routes = R

local Geo = FM.Geo
local floor, sqrt, min, max = math.floor, math.sqrt, math.min, math.max
local QUIET, LIT = 0.92, 1
local LIT_FADE = { 3, 12 }       -- zoom over which the hovered route's lift fades (up close it's barely there)
local EASE = 8
local HOVER_PX = 8
-- the factions' own colours, as the game has them (PLAYER_FACTION_COLORS: 0 the Horde's, 1 the Alliance's;
-- its values where a client lacks it): Alliance boats blue, every other route (the Horde's zeppelins, the
-- goblins' boats) red
local function GameColour(i, r, g, b)
	local c = PLAYER_FACTION_COLORS and PLAYER_FACTION_COLORS[i]
	if c and c.r then return { c.r, c.g, c.b } end
	return { r, g, b }
end
local BLUE, RED
local KINDS = { boat = true, zeppelin = true }   -- (Zephras Isle's airships: its map isn't on the world)

local layer
local routes = {}
local built = false
local lit
local zoomNow = 1
local easing = true              -- (a route still on its way up or down: Tick has work)
local focus = {}                 -- route -> true: the routes of the dock under the cursor
local allWas

local function Smooth(x, a, b)
	local t = (x - a) / (b - a)
	if t <= 0 then return 0 elseif t >= 1 then return 1 end
	return t * t * (3 - 2 * t)
end

-- (whose it is, and whether you can take it: Pins.lua's, as the harbors shown)
local function Faction(sail) return FM.Pins.TransportFaction(sail[1], sail[2]) end

-- a bowed arc from p0 to p2 (world units) onto way: bowed away from the world's middle line
local function Arc(way, p0, p2)
	local du, dv = p2[1] - p0[1], p2[2] - p0[2]
	local len = sqrt(du * du + dv * dv)
	if len <= 0 then return end
	local side = ((p0[2] + p2[2]) / 2 < FM.H / 2) and -1 or 1
	local nu, nv = -dv / len, du / len
	if nv * side < 0 then nu, nv = -nu, -nv end
	local cu, cv = (p0[1] + p2[1]) / 2 + nu * 0.12 * len, (p0[2] + p2[2]) / 2 + nv * 0.12 * len
	local steps = max(8, min(32, floor(len / 6)))
	if #way == 0 then way[1] = { p0[1], p0[2] } end
	for k = 1, steps do
		local t = k / steps
		way[#way + 1] = { (1 - t) ^ 2 * p0[1] + 2 * (1 - t) * t * cu + t * t * p2[1],
			(1 - t) ^ 2 * p0[2] + 2 * (1 - t) * t * cv + t * t * p2[2] }
	end
end

-- The way, dock to dock: the docks of this route (Data\Places.lua transports of the same name that
-- its sailing passes by), in the order it calls at them, each leg one bowed arc between them.
-- (Two different sailings share a name, "Orgrimmar Zepplins": a dock counts only where this one goes.)
local DOCK_NEAR = 120                   -- yards
local function Way(sail)
	local docks = {}
	for _, t in ipairs(FM.PLACES.transports or {}) do
		if t[2] == sail[2] then
			local best, at
			for pi, piece in ipairs(sail[3]) do
				if piece[1] == t[3] then
					local pts = piece[2]
					for k = 1, #pts - 1, 2 do
						local d = sqrt((pts[k] - t[4]) ^ 2 + (pts[k + 1] - t[5]) ^ 2)
						if not best or d < best then best, at = d, pi * 10000 + k end
					end
				end
			end
			if best and best < DOCK_NEAR then
				local u, v = Geo.WorldToUnits(t[3], t[4], t[5])
				if u then docks[#docks + 1] = { u, v, at = at, best = best, c = t[3], x = t[4], y = t[5] } end
			end
		end
	end
	table.sort(docks, function(a, b) return a.at < b.at end)
	-- one stop per dock: the same dock listed once per direction, and of two towers side by side
	-- (Undercity's), the one this sailing really leaves from
	local stops = {}
	for _, d in ipairs(docks) do
		local merged = false
		for _, s in ipairs(stops) do
			if s.c == d.c and (s.x - d.x) ^ 2 + (s.y - d.y) ^ 2 < 100 * 100 then
				if d.best < s.best then s[1], s[2], s.best, s.x, s.y = d[1], d[2], d.best, d.x, d.y end
				merged = true
				break
			end
		end
		if not merged then stops[#stops + 1] = d end
	end
	-- (each line ends right on its dock's icon: a zeppelin tower's in the tower's middle)
	if FM.Pins and FM.Pins.DockUnits then
		for _, s in ipairs(stops) do
			local u, v = FM.Pins.DockUnits(sail[1], s.c, s.x, s.y)
			if u then s[1], s[2] = u, v end
		end
	end
	-- (each leg, dock to next dock, a route of its own: over a dock, only the legs that call at it show)
	local legs = {}
	for i = 1, #stops - 1 do
		local way = {}
		Arc(way, stops[i], stops[i + 1])
		legs[#legs + 1] = { way = way, stops = { stops[i], stops[i + 1] } }
	end
	return legs
end

-- Each route a crisp, thin dashed line along its way, drawn on the screen itself (not on a scaled frame:
-- no blur). Its picture (Media\dash) is one period of it, a dash and a gap, repeated along each stretch,
-- every stretch going on from where the one before left off (its distance from the route's start), so the
-- dashes run on unbroken round the bends; soft at its edges and the dashes' ends, so it stays smooth at any
-- angle. In its faction's colour, over a faint wider shadow, dashed the same, that lifts it off any ground.
-- Only the stretches in view are drawn; the same width and dashes on screen at every zoom.
local DASH = "Interface\\AddOns\\PerfectMap\\Media\\dash"
-- A dash and its gap: some 13 px on screen, but laid on the ground, not on the screen (zoomed, the dashes
-- stay where they are and grow or shrink with it); each time the zoom doubles or halves, the ground's
-- period halves or doubles, so they keep about their size, the old dashes where they were, new ones in
-- between. (Measured on the screen, they slid along the route at every zoom)
local PERIOD = 13
local LOG2 = math.log(2)
local function GroundPeriod(scale)
	return 2 ^ floor(math.log(PERIOD / scale) / LOG2 + 0.5)
end
local WIDTH, SHADOW = 2.4, 6         -- px on screen: the line, its shadow
local LIT_WIDTH = 3.4                -- ... the hovered one's

local NO_LEGS = {}
local function Build()
	built = true
	for _, sail in ipairs(FM.PLACES and FM.PLACES.sailings or {}) do
		for _, leg in ipairs(KINDS[sail[1]] and FM.Pins.Usable(sail[1], sail[2]) and Way(sail) or NO_LEGS) do
			local way = leg.way
			if #way > 1 then
				local route = { kind = sail[1], name = sail[2], faction = Faction(sail), way = way, stops = leg.stops,
					alpha = FM.db.routes and QUIET or 0, lines = {}, shadows = {} }
				if not BLUE then BLUE, RED = GameColour(1, 0.29, 0.33, 0.91), GameColour(0, 0.90, 0.05, 0.07) end
				route.color = route.faction == "Alliance" and BLUE or RED
				route.r, route.g, route.b = route.color[1], route.color[2], route.color[3]
				-- (where it runs: the zones of its two docks; the game names two routes "Orgrimmar Zepplins")
				local a = select(2, Geo.ZoneAt(way[1][1], way[1][2]))
				local b = select(2, Geo.ZoneAt(way[#way][1], way[#way][2]))
				route.ends = (a and b) and (a .. "  -  " .. b) or route.name
				-- (its bounds, to skip it whole when it's out of view)
				local u0, v0, u1, v1 = math.huge, math.huge, -math.huge, -math.huge
				for _, p in ipairs(way) do
					u0, v0, u1, v1 = min(u0, p[1]), min(v0, p[2]), max(u1, p[1]), max(v1, p[2])
				end
				route.box = { u0, v0, u1, v1 }
				-- (each point's distance from the start, in world units: where the dashes stand along it)
				local along, d = { 0 }, 0
				for k = 2, #way do
					d = d + sqrt((way[k][1] - way[k - 1][1]) ^ 2 + (way[k][2] - way[k - 1][2]) ^ 2)
					along[k] = d
				end
				route.along = along
				route.frame = CreateFrame("Frame", nil, layer)
				route.frame:SetAllPoints()
				route.frame:SetAlpha(route.alpha)
				route.frame:Hide()
				routes[#routes + 1] = route
			end
		end
	end
end

local function Seg(r, k)
	local ln = r.lines[k]
	if not ln then
		local sh = r.frame:CreateLine(nil, "ARTWORK", nil, 1)
		sh:SetTexture(DASH, "REPEAT", "CLAMP")
		sh:SetVertexColor(0, 0, 0, 0.32)
		r.shadows[k] = sh
		ln = r.frame:CreateLine(nil, "ARTWORK", nil, 3)
		ln:SetTexture(DASH, "REPEAT", "CLAMP")
		ln:SetVertexColor(r.r, r.g, r.b, 1)
		r.lines[k] = ln
	end
	return ln, r.shadows[k]
end

-- the stretches of a route in view, laid on the screen
local function Draw(r, left, top, scale, x1, y1)
	local way = r.way
	-- (only the routes shown by a dock's hover are drawn wider: with them all on, none stands out)
	local w = (focus[r] and not FM.db.routes) and LIT_WIDTH or WIDTH
	local period = GroundPeriod(scale)
	local n = 0
	local pad = 8 / scale
	for k = 1, #way - 1 do
		local a, b = way[k], way[k + 1]
		if max(a[1], b[1]) >= left - pad and min(a[1], b[1]) <= x1 + pad and max(a[2], b[2]) >= top - pad and min(a[2], b[2]) <= y1 + pad then
			n = n + 1
			local ln, sh = Seg(r, n)
			local ax, ay = (a[1] - left) * scale, (top - a[2]) * scale
			local bx, by = (b[1] - left) * scale, (top - b[2]) * scale
			ln:SetStartPoint("TOPLEFT", r.frame, ax, ay)
			ln:SetEndPoint("TOPLEFT", r.frame, bx, by)
			sh:SetStartPoint("TOPLEFT", r.frame, ax, ay)
			sh:SetEndPoint("TOPLEFT", r.frame, bx, by)
			local t0, t1 = r.along[k] / period, r.along[k + 1] / period
			ln:SetTexCoord(t0, t1, 0, 1)
			sh:SetTexCoord(t0, t1, 0, 1)
			if ln.fmW ~= w then ln.fmW = w ln:SetThickness(w) sh:SetThickness(w + SHADOW - WIDTH) end
			ln:Show()
			sh:Show()
		end
	end
	for k = n + 1, #r.lines do
		if r.lines[k]:IsShown() then r.lines[k]:Hide() r.shadows[k]:Hide() end
	end
end

local view = {}
function R.Init(parent)
	layer = parent
end

-- (a route shows with its kind's icons: boats', or zeppelins')
local KIND_KEY = { boat = "boat", zeppelin = "zeppelin", airship = "airship" }
local NONE = {}
-- (which routes there are changed, the other faction's harbors turned on or off: built again when next shown)
function R.Rebuild()
	for _, r in ipairs(routes) do r.frame:Hide() end
	wipe(routes)
	wipe(focus)
	lit, built = nil, false
	if FM.Map then FM.Map.MarkDirty() end
end

local function Shown()
	return FM.db.routes and (FM.db.pins.boat or FM.db.pins.zeppelin)
end

-- (where it shows: in view, its kind's icons on, and all of them asked for, its dock hovered, or fading out)
local function Wanted(r)
	return FM.db.routes or focus[r] or r.alpha > 0.003
end

function R.Layout(left, top, scale, vw, vh, zoom)
	if zoomNow ~= zoom then easing = true end
	if allWas ~= FM.db.routes then allWas = FM.db.routes easing = true end
	zoomNow = zoom
	view.left, view.top, view.scale, view.vw, view.vh = left, top, scale, vw, vh
	if not built then
		if not (Shown() or next(focus)) then return end
		Build()
	end
	local x1, y1 = left + vw / scale, top + vh / scale
	for _, r in ipairs(routes) do
		local box = r.box
		local on = FM.db.pins[KIND_KEY[r.kind] or "boat"] and Wanted(r)
			and box[3] >= left and box[1] <= x1 and box[4] >= top and box[2] <= y1
		if on then
			Draw(r, left, top, scale, x1, y1)
			r.frame:Show()
		elseif r.frame:IsShown() then
			r.frame:Hide()
		end
	end
end

-- the hovered route (or the hovered dock's) eases up, the others back down: quiet, or, one at a time, out
function R.Tick(elapsed)
	if #routes == 0 or not easing then return end
	local busy = false
	local up = QUIET + (LIT - QUIET) * (1 - Smooth(zoomNow, LIT_FADE[1], LIT_FADE[2]))
	local rest = FM.db.routes and QUIET or 0
	local k = 1 - math.exp(-elapsed * EASE)      -- (by time: the same at any frame rate)
	for _, r in ipairs(routes) do
		local target = (focus[r] and not FM.db.routes) and up or rest
		if math.abs(r.alpha - target) > 0.002 then
			r.alpha = r.alpha + (target - r.alpha) * k
			busy = true
		else
			r.alpha = target
			if target == 0 and r.frame:IsShown() then r.frame:Hide() end
		end
		r.frame:SetAlpha(r.alpha)
	end
	easing = busy                    -- (all where they belong: nothing to do until something changes)
end

-- a route of this dock (Pins.lua's dock icon: its kind, place and the routes named on it): one of those
-- names, calling at it
local function Serves(r, d)
	if r.kind ~= d.kind then return false end
	local named = false
	for _, name in ipairs(d.routes) do if name == r.name then named = true break end end
	if not named then return false end
	local near = d.near + 50
	for _, st in ipairs(r.stops) do
		if st.c == d.cont and (st.x - d.x) ^ 2 + (st.y - d.y) ^ 2 < near * near then return true end
	end
	return false
end

-- the routes of the dock icons under the cursor (none: nil)
local function Focus(pins, n)
	if FM.db.routes then n = 0 end          -- (all of them on: a dock's hover adds nothing)
	local changed = false
	for r in pairs(focus) do
		local keep = false
		for i = 1, n do
			local d = pins[i].dock
			if d and Serves(r, d) then keep = true break end
		end
		if not keep then focus[r] = nil changed = true end
	end
	for i = 1, n do
		local d = pins[i].dock
		if d then
			if not built and layer and view.scale then Build() end
			for _, r in ipairs(routes) do
				if not focus[r] and Serves(r, d) then focus[r] = true changed = true end
			end
		end
	end
	if changed then
		easing = true
		if view.scale then R.Layout(view.left, view.top, view.scale, view.vw, view.vh, zoomNow) end
	end
end

local function Light(route, owner)
	-- (the line under the cursor: only its tooltip, the line itself as it was)
	if route == lit then return end
	lit = route
	if route then
		GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
		GameTooltip:AddLine(route.kind == "zeppelin" and "Zeppelin" or "Boat", 1, 0.82, 0)
		GameTooltip:AddLine(route.ends, 1, 1, 1)
		if route.faction == "Neutral" then
			GameTooltip:AddLine("Neutral", 1, 0.82, 0)
		else
			local c = route.color
			GameTooltip:AddLine(route.faction == "Alliance" and (FACTION_ALLIANCE or "Alliance") or (FACTION_HORDE or "Horde"),
				c[1] + 0.25, c[2] + 0.25, c[3] + 0.25)
		end
		GameTooltip:Show()
	elseif GameTooltip:GetOwner() == owner then
		GameTooltip:Hide()
	end
end

-- the route nearest the cursor (world units u, v), within HOVER_PX on screen; nil u: none. onPins: the
-- cursor is on icons (Pins.Hovered): a dock's shows its routes
local NO_PINS = {}
function R.Hover(u, v, scale, onPins)
	if onPins and FM.Pins.Hovered then Focus(FM.Pins.Hovered()) elseif next(focus) then Focus(NO_PINS, 0) end
	if not u or not Shown() or #routes == 0 then return Light(nil, layer) end
	local best, bestD = nil, HOVER_PX / scale
	for _, r in ipairs(routes) do
		local way = r.frame:IsShown() and r.way or NONE   -- (its kind turned off: not hovered)
		for k = 1, #way - 1 do
			local ax, ay = way[k][1] - u, way[k][2] - v
			local dx, dy = way[k + 1][1] - way[k][1], way[k + 1][2] - way[k][2]
			local len2 = dx * dx + dy * dy
			local t = len2 > 0 and max(0, min(1, -(ax * dx + ay * dy) / len2)) or 0
			local d = sqrt((ax + dx * t) ^ 2 + (ay + dy * t) ^ 2)
			if d < bestD then best, bestD = r, d end
		end
	end
	Light(best, layer)
end
