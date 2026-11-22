-- Up close, the terrain as the minimap draws it: the game's own minimap tiles (Data/Minimap.lua, by
-- file ID: nothing shipped but the list) taking over from the painted map well past where it runs
-- out of detail. One clean change at one zoom (AzerothVeil: between the 4th and 5th step of the wheel past where M
-- opens the map): on one side the painted map, on the other the minimap, never a zoom showing both;
-- crossing it, one dissolves into the other over FADE seconds. Drawn through each continent's land
-- (Media/MiniLand, OpenMap's), so the sea stays the painted map's. Only the tiles in view are loaded.
-- As OpenMap's Map/Close.lua (MIT) does it.
local _, FM = ...
local T = {}
FM.Terrain = T
local Geo = FM.Geo
local floor, min, max = math.floor, math.min, math.max

local TILE = 1600 / 3                       -- yards a minimap tile
local MASK = "Interface\\AddOns\\AzerothVeil\\Media\\MiniLand\\"
local CONT_MAP = { [0] = 1415, [1] = 1414 } -- instance -> its continent's map
local MAX_TILES = 160                       -- (more in view than this: too far out to want them)
local MIX = 1                               -- how much it shows at its full (1: the minimap's own look)
local INSET = 0.5 / 256                     -- (half a texel in: no seam bled in from the next tile)

local layer
local tiles, pools = {}, {}                 -- key -> texture; instance -> free textures (each through its land)
local masks = {}                            -- instance -> its land's mask
local axes = {}                             -- instance -> tile (tx, ty) to world units: u = u0 + tx*a + ty*b ...
local wanted = {}
local FADE = 0.3                            -- seconds the change takes
local mix, goal = 0, 0                      -- how much it shows now (0..1, eased when drawn); where it's going

local function Smooth(x, a, b)
	local t = max(0, min(1, (x - a) / (b - a)))
	return t * t * (3 - 2 * t)
end

-- (the game's world <-> its map is linear: three points give it, once)
local function Axes(inst)
	local ax = axes[inst]
	if ax == nil then
		local u0, v0 = Geo.WorldToUnits(inst, 32 * TILE, 32 * TILE)
		local u1, v1 = Geo.WorldToUnits(inst, 32 * TILE, 31 * TILE)    -- one tile east
		local u2, v2 = Geo.WorldToUnits(inst, 31 * TILE, 32 * TILE)    -- one tile south
		if u0 and u1 and u2 then
			ax = { u0 = u0, v0 = v0, ua = u1 - u0, va = v1 - v0, ub = u2 - u0, vb = v2 - v0 }
			local det = ax.ua * ax.vb - ax.ub * ax.va
			if math.abs(det) < 1e-9 then ax = false else ax.det = det end
		else
			ax = false
		end
		axes[inst] = ax
	end
	return ax or nil
end

-- world units -> tile (fractional)
local function ToTile(ax, u, v)
	local du, dv = u - ax.u0, v - ax.v0
	return (du * ax.vb - dv * ax.ub) / ax.det, (dv * ax.ua - du * ax.va) / ax.det
end

local function Mask(inst)
	local m = masks[inst]
	if m == nil then
		local id = CONT_MAP[inst]
		m = false
		if id then
			m = layer:CreateMaskTexture()
			m:SetTexture(MASK .. id, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		end
		masks[inst] = m
	end
	return m or nil
end

local function NewTile(inst, fid)
	local pool = pools[inst]
	local t = pool and tremove(pool)
	if not t then
		t = layer:CreateTexture(nil, "ARTWORK")
		if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) t:SetTexelSnappingBias(0) end
		t:SetTexCoord(INSET, 1 - INSET, INSET, 1 - INSET)
		local m = Mask(inst)
		if m then t:AddMaskTexture(m) end
		t.inst = inst
	end
	t:SetTexture(fid, nil, nil, "LINEAR")
	t.mix = nil
	return t
end

local function Drop(key)
	local t = tiles[key]
	tiles[key] = nil
	t:Hide()
	t:ClearAllPoints()
	local pool = pools[t.inst] or {}
	pools[t.inst] = pool
	pool[#pool + 1] = t
end

local function DropAll()
	for key in pairs(tiles) do Drop(key) end
	for _, m in pairs(masks) do if m then m:Hide() end end
end

-- the zoom it changes at: halfway between two steps past M's opening zoom (so a step of the wheel always
-- lands clear of it), but always before the deepest zoom there is (a big window, or a sharp screen, goes
-- less deep). AzerothVeil: the terrain two steps sooner than PerfectMap's (between the 4th and 5th step,
-- not the 6th and 7th) and the caves two steps later (CAVES: between the 8th and 9th, or just before the
-- deepest zoom): the land explored in the minimap's look before its caves
local SWITCH, CAVES = 4.5, 8.5
local function At(deepest, steps)
	local step = FM.Map.ZOOM_STEP
	return min(FM.W / FM.Map.OPEN_ACROSS * step ^ (steps or SWITCH), deepest / math.sqrt(step))
end

-- (the zoom the caves come in at, over the minimap's terrain: Caves.lua)
function T.SwitchZoom(deepest) return At(deepest, CAVES) end

local function Shown() return Smooth(mix, 0, 1) end
-- AzerothVeil: what goes with the terrain, told how much of it shows: the cities in the open fade under it
-- (Cities.lua), the places' names come over it (Labels.lua)
local function Under(k)
	if FM.Cities then FM.Cities.SetTerrain(k) end
	if FM.Labels then FM.Labels.SetTerrain(k) end
end
-- (whether it's there or coming: Labels.lua lays its names out then)
function T.Active() return goal > 0 or mix > 0 end
local function SetAll(a)
	for _, t in pairs(tiles) do
		if t.mix ~= a then t.mix = a t:SetAlpha(a) end
	end
	Under(Shown())   -- (AzerothVeil: the cities under it and the places' names over it)
end

-- every pan / zoom
function T.Layout(left, top, scale, vw, vh, zoom, deepest)
	if not layer then return end
	goal = (FM.db.minimapTerrain ~= false and zoom >= At(deepest)) and 1 or 0
	if goal == 0 and mix <= 0 then
		if next(tiles) then DropAll() end
		Under(0)
		return
	end
	Under(Shown())
	local a = MIX * Shown()
	wipe(wanted)
	local right, bottom = left + vw / scale, top + vh / scale
	local list = FM.MINIMAP
	for inst, set in pairs(list or {}) do
		local id = CONT_MAP[inst]
		local r = id and Geo.Rect(id)
		local ax = r and r[2] > left and r[1] < right and r[4] > top and r[3] < bottom and Axes(inst)
		if ax then
			-- the tiles under the view's corners
			local x0, y0 = ToTile(ax, left, top)
			local x1, y1 = ToTile(ax, right, bottom)
			local tx0, tx1 = max(0, floor(min(x0, x1))), min(63, floor(max(x0, x1)))
			local ty0, ty1 = max(0, floor(min(y0, y1))), min(63, floor(max(y0, y1)))
			if (tx1 - tx0 + 1) * (ty1 - ty0 + 1) <= MAX_TILES then
				local m = Mask(inst)
				if m then
					m:ClearAllPoints()
					m:SetPoint("TOPLEFT", layer, "TOPLEFT", (r[1] - left) * scale, (top - r[3]) * scale)
					m:SetSize((r[2] - r[1]) * scale, (r[4] - r[3]) * scale)
					m:Show()
				end
				for tx = tx0, tx1 do
					for ty = ty0, ty1 do
						local fid = set[tx * 64 + ty]
						if fid then
							local key = inst * 4096 + tx * 64 + ty
							wanted[key] = true
							local t = tiles[key]
							if not t then
								t = NewTile(inst, fid)
								tiles[key] = t
							end
							-- (its corners: tile tx, ty runs to tx + 1, ty + 1)
							local ua = ax.u0 + tx * ax.ua + ty * ax.ub
							local va = ax.v0 + tx * ax.va + ty * ax.vb
							local ub = ua + ax.ua + ax.ub
							local vb = va + ax.va + ax.vb
							local sx, sy = (min(ua, ub) - left) * scale, (min(va, vb) - top) * scale
							t:ClearAllPoints()
							t:SetPoint("TOPLEFT", layer, "TOPLEFT", sx, -sy)
							-- (edge to edge with the next: no hairline, and no strip drawn twice to show while faded)
							t:SetPoint("BOTTOMRIGHT", layer, "TOPLEFT", (max(ua, ub) - left) * scale, -(max(va, vb) - top) * scale)
							if t.mix ~= a then t.mix = a t:SetAlpha(a) end
							t:Show()
						end
					end
				end
			end
		end
	end
	for key in pairs(tiles) do
		if not wanted[key] then Drop(key) end
	end
end

-- every frame while the map is open: the change under way (nothing to do otherwise)
function T.Tick(elapsed)
	if mix == goal then return end
	if goal > mix then mix = min(goal, mix + elapsed / FADE) else mix = max(goal, mix - elapsed / FADE) end
	if mix <= 0 then
		DropAll()
		Under(0)
		return
	end
	SetAll(MIX * Shown())
end

function T.Init(parent)
	layer = parent
end
