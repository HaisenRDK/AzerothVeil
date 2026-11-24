-- Other addons' icons on our map, by themselves, with no addon set up one by one. Every addon that puts
-- icons on Blizzard's world map does it on that map's canvas: its own data provider (GatherMate2...),
-- or HereBeDragons-Pins' (HandyNotes, TomTom...), each acquiring pins of its own templates.
--  * Their icons show from two of the wheel's steps after the townsfolk (ShowZoom).
--  * Blizzard's map (hidden) is told the zone in the middle of our view, from the townsfolk zoom in and
--    never in combat (it holds the group's protected pins then): every provider fills in that zone's
--    pins, as when that map is opened on it.
--  * The pins an addon made (the game itself says which: Owner, below) are shown on our map, exactly
--    where their addon put them: their own frames, so their tooltips, clicks and menus are the addons'
--    own. Blizzard's own pins (we draw those ourselves) and Questie's (mirrored by Quests.lua) are
--    left out.
--  * Never moved, joined or pushed by ours, nor ours by them: placed outside the icons' layout.
local _, FM = ...
local A = {}
FM.AddonPins = A
local Geo = FM.Geo

local CHECK_EVERY = 0.5            -- seconds between looks for pins the hidden map laid out again

local layer
local hosted = {}                  -- pin -> the layout pass it was last placed in
local pass = 0
local lastZone
local checkAcc = 0
local owners = {}                  -- template -> true: an addon's pins (false: Blizzard's, or Questie's)
local mixinOf                      -- OnAcquired function -> the name of the global mixin it's from
local hooked = false

local function On() return FM.db and FM.db.addonPins ~= false end
local function OpenZoom() return FM.W / FM.Map.OPEN_ACROSS * 0.97 end
-- (their icons show two of the wheel's steps after the townsfolk; the zone is asked for from the
-- townsfolk' zoom, so they're there by then)
local function ShowZoom() return FM.W / FM.Map.OPEN_ACROSS * FM.Map.ZOOM_STEP ^ 2 * 0.97 end

local function Changed()
	if FM.Map and FM.Map.IsShown() then FM.Map.MarkDirty() end
end

-- Whose pins a template's are: the code that says how a pin behaves is its mixin, and the game knows
-- whether that was written by Blizzard (secure) or by an addon. (Where the pool was first made can't
-- tell: made while we move the hidden map, Blizzard's would look like ours.) A pin's OnAcquired is
-- found among the global mixins once; a pin whose mixin isn't a global one is an addon's (a library's
-- local mixin, such as HereBeDragons'). Questie's are left out.
local function IndexMixins()
	mixinOf = {}
	for name, t in pairs(_G) do
		if type(name) == "string" and type(t) == "table" then
			local f = rawget(t, "OnAcquired")
			if type(f) == "function" and not mixinOf[f] then mixinOf[f] = name end
		end
	end
end
local function Owner(template, pin)
	local o = owners[template]
	if o ~= nil then return o end
	o = false
	local f = pin.OnAcquired
	if type(f) == "function" and not tostring(template):find("Questie") then
		if not mixinOf then IndexMixins() end
		local name = mixinOf[f]
		if name then
			local secure, addon = issecurevariable(_G, name)
			o = not secure and not (type(addon) == "string" and addon:find("Questie")) or false
		else
			o = true
		end
	end
	owners[template] = o
	return o
end

-- Gathering addons (GatherMate2, Gatherer, GatherLite, GatherRadar... any addon whose name says it: "gather",
-- "herb", "mining"): the map's tools have a button for their icons, shown when one is loaded. Which pins are
-- theirs, whatever way they put them on Blizzard's map:
--  * their own data provider's pins (GatherMate2, GatherRadar...): by the pin's template, its mixin, and the
--    addon that wrote that mixin (the game says who did);
--  * HereBeDragons' pins (one template for every addon: GatherLite, HandyNotes...): by the addon that
--    registered the icon with the library (the game says who did that too), its reference and the icon's name.
-- (An addon's own fields on its pins (GatherRadar's pin.icon is a texture) never stand for HereBeDragons' icon.)
local WORDS = { "gather", "herb", "mining" }
local function Gathery(s)
	if type(s) ~= "string" then return false end
	s = s:lower()
	for _, w in ipairs(WORDS) do
		if s:find(w, 1, true) then return true end
	end
	return false
end
local gatherLoaded
function A.HasGathering()
	if gatherLoaded ~= nil then return gatherLoaded end
	gatherLoaded = false
	local n = C_AddOns and C_AddOns.GetNumAddOns and C_AddOns.GetNumAddOns() or 0
	for i = 1, n do
		local name = C_AddOns.GetAddOnInfo(i)
		if Gathery(name) and C_AddOns.IsAddOnLoaded(name) then
			gatherLoaded = true
			break
		end
	end
	return gatherLoaded
end
local gatherTemplate = {}           -- template -> true / false (a provider's pins)
local gatherIcon = setmetatable({}, { __mode = "k" })   -- HereBeDragons' icon frame -> true / false
local function GatherPin(template, pin)
	local lib = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
	if lib and template == lib.worldmapPinTemplate then
		local icon = pin.icon
		if type(icon) ~= "table" then return false end
		local g = gatherIcon[icon]
		if g ~= nil then return g end
		g = type(icon.GetName) == "function" and Gathery(icon:GetName()) or false
		local reg = lib.worldmapPinRegistry
		if not g and type(reg) == "table" then
			for ref, icons in pairs(reg) do
				if type(icons) == "table" and icons[icon] then
					-- (who registered it: the game knows only for a name; a table ref says it by its fields)
					local addon
					if type(ref) == "string" then addon = select(2, issecurevariable(reg, ref)) end
					g = Gathery(addon) or Gathery(ref)
						or (type(ref) == "table" and (Gathery(rawget(ref, "name")) or Gathery(rawget(ref, "moduleName"))))
						or Gathery(tostring(ref))
					break
				end
			end
		end
		gatherIcon[icon] = g and true or false
		return gatherIcon[icon]
	end
	local g = gatherTemplate[template]
	if g ~= nil then return g end
	g = Gathery(tostring(template))
	if not g and type(pin.OnAcquired) == "function" then
		if not mixinOf then IndexMixins() end
		local name = mixinOf[pin.OnAcquired]
		if name then
			local _, addon = issecurevariable(_G, name)
			g = Gathery(name) or Gathery(addon)
		end
	end
	gatherTemplate[template] = g and true or false
	return gatherTemplate[template]
end
local function GatherOn() return not FM.db or FM.db.gatherPins ~= false end

-- AzerothVeil: whose a pin is, so each addon's icons can be shown or not on their own (the Integrations module's
-- options: FM.db.addonPinsBy = { [addon] = true / false, others = ... }). The addons it names (KNOWN; a HandyNotes
-- plugin counts as HandyNotes), found as the gathering addons are:
--  * a provider's pins: by their template's name, else the global mixin their code comes from and the addon that
--    wrote it (the game says who did);
--  * HereBeDragons' pins (one template for every addon): by the reference the icon was registered under: a name,
--    or the addon's own table (its name field, or the global of that name: TomTom's, HandyNotes').
-- Any other: "others".
local KNOWN = { "GatherMate2", "HandyNotes", "TomTom", "RareScanner" }
local function Known(name)
	if type(name) ~= "string" then return nil end
	for _, k in ipairs(KNOWN) do
		if name:sub(1, #k) == k then return k end
	end
end
local templateAddon = {}                                   -- template -> addon (false: none it knows)
local iconAddon = setmetatable({}, { __mode = "k" })      -- HereBeDragons' icon frame -> addon (false: none)
local function RefAddon(ref, reg)
	if type(ref) == "string" then return Known(ref) or Known(select(2, issecurevariable(reg, ref))) end
	if type(ref) == "table" then
		local n = Known(rawget(ref, "name")) or Known(rawget(ref, "moduleName"))
		if n then return n end
		for _, k in ipairs(KNOWN) do if rawget(_G, k) == ref then return k end end
	end
end
local function PinAddon(template, pin)
	local lib = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
	if lib and template == lib.worldmapPinTemplate then
		local icon = pin.icon
		if type(icon) ~= "table" then return nil end
		local a = iconAddon[icon]
		if a == nil then
			a = false
			local reg = type(lib.worldmapPinRegistry) == "table" and lib.worldmapPinRegistry or {}
			for ref, icons in pairs(reg) do
				if type(icons) == "table" and icons[icon] then a = RefAddon(ref, reg) or false break end
			end
			iconAddon[icon] = a
		end
		return a or nil
	end
	local a = templateAddon[template]
	if a == nil then
		a = Known(tostring(template))
		if not a and type(pin.OnAcquired) == "function" then
			if not mixinOf then IndexMixins() end
			local name = mixinOf[pin.OnAcquired]
			if name then a = Known(name) or Known(select(2, issecurevariable(_G, name))) end
		end
		templateAddon[template] = a or false
	end
	return a or nil
end
-- (an addon's icons wanted: its own option, else the "others" one; none set: every one)
local function Wanted(addon)
	local by = FM.db and FM.db.addonPinsBy
	if type(by) ~= "table" then return true end
	return by[addon or "others"] ~= false
end

-- AzerothVeil: addons that draw on a layer of their own over Blizzard's map's canvas, not in its pin pools
-- (RareScanner: its RSWorldMap, a frame on WorldMapFrame.ScrollContainer.Child, its own pools, following the
-- map's zone through MapCanvas.MapSet). Their pins: known by the code that places them (a global mixin of
-- theirs), their place in their own fields; a pin they've released has no place (At: nil). Nothing of theirs
-- is called: their frames are shown on our map as the others' are, their tooltips and clicks their own.
local OWN_LAYERS = {
	{ addon = "RareScanner", mixin = "RSPinMixin", method = "ApplyCurrentPosition",
		-- (its place, and the zone it's in: its POI's own, so a pin of the zone just left, not yet laid out again,
		-- stays where it belongs instead of taking the new zone's place)
		At = function(pin)
			local poi = pin.POI
			if poi ~= nil then return pin.x, pin.y, type(poi) == "table" and tonumber(poi.mapID) or nil end
		end },
}
local ownPins = setmetatable({}, { __mode = "k" })   -- pin -> its OWN_LAYERS entry (every one seen)
local ownLayer = {}                                   -- entry -> its layer, once found
local ownPlaced = setmetatable({}, { __mode = "k" })  -- pin -> where it was last placed (x + y * 7)
local ownLookAt = -10

-- (the entries whose addon is loaded, its mixin there)
local function OwnMethod(e)
	local m = _G[e.mixin]
	return FM.IsAddOnLoaded(e.addon) and type(m) == "table" and type(m[e.method]) == "function" and m[e.method] or nil
end
local function AnyOwn()
	for _, e in ipairs(OWN_LAYERS) do if OwnMethod(e) then return true end end
	return false
end

-- their pins now on their layer (those we show are on ours: still known, ownPins); their layer, found once:
-- the frame on Blizzard's canvas whose children are their pins (looked for every few seconds until found)
local function LookForOwn(wm)
	local canvas = wm.ScrollContainer and wm.ScrollContainer.Child
	if not canvas then return false end
	local found = false
	for _, e in ipairs(OWN_LAYERS) do
		local fn = OwnMethod(e)
		if fn then
			local l = ownLayer[e]
			if not l and GetTime() - ownLookAt > 2 then
				ownLookAt = GetTime()
				for _, c in ipairs({ canvas:GetChildren() }) do
					if c.OnAcquired == nil then
						for _, g in ipairs({ c:GetChildren() }) do
							if g[e.method] == fn then l = c break end
						end
					end
					if l then break end
				end
				ownLayer[e] = l
			end
			if l then
				for _, g in ipairs({ l:GetChildren() }) do
					if g[e.method] == fn and not ownPins[g] then ownPins[g] = e found = true end
				end
			end
		end
	end
	return found
end

-- (whenever an addon's provider lays its pins out again, ours follow at once)
local function Hook(wm)
	if hooked then return end
	hooked = true
	for _, fn in ipairs({ "AcquirePin", "RemoveAllPinsByTemplate", "RemovePin" }) do
		if type(wm[fn]) == "function" then hooksecurefunc(wm, fn, Changed) end
	end
end

-- Telling Blizzard's map a zone leaves it tainted by us: harmless only while the game's own code can never
-- run it (Takeover.lua stops it from opening), and worth it only when an addon (not Questie, mirrored on
-- its own) has icons on it: its own provider (GatherMate2...), or icons in HereBeDragons' registry.
-- Looked at again every few seconds
local NONE = {}
-- the addon that made a provider of Blizzard's map (nil: the game's own). Its methods were written into it
-- by whoever made it: the game says whether that was secure code, and if not, which addon
local PROVIDER_KEYS = { "RefreshAllData", "OnAdded", "RemoveAllData" }
local function ProviderAddon(provider)
	if type(provider) ~= "table" then return nil end
	for _, k in ipairs(PROVIDER_KEYS) do
		if rawget(provider, k) ~= nil then
			local secure, addon = issecurevariable(provider, k)
			if secure then return nil end
			return type(addon) == "string" and addon ~= "" and addon or "?"
		end
	end
end
local needed, neededAt = false, -10
local function Needed(wm)
	if not (FM.Takeover and FM.Takeover.MapStopped()) then
		neededAt = -math.huge
		return false
	end
	local now = GetTime()
	if now - neededAt < 3 then return needed end
	neededAt, needed = now, false
	local hbd = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
	local hbdProvider = hbd and hbd.worldmapProvider
	for provider in pairs(type(wm.dataProviders) == "table" and wm.dataProviders or NONE) do
		-- (an addon's: added to the map by an addon, not by the game)
		local addon = provider ~= hbdProvider and ProviderAddon(provider)
		-- (Questie's own provider: its icons are mirrored by Quests.lua, never through here)
		if addon and not addon:find("^Questie") then
			needed = true
			return true
		end
	end
	for ref, icons in pairs(hbd and type(hbd.worldmapPinRegistry) == "table" and hbd.worldmapPinRegistry or NONE) do
		if ref ~= _G.Questie and type(icons) == "table" and next(icons) then
			needed = true
			return true
		end
	end
	-- AzerothVeil: an addon drawing on a layer of its own (RareScanner)
	if AnyOwn() then needed = true return true end
	return false
end

-- Blizzard's hidden map on the zone in the middle of the view
local function Drive(wm, left, top, scale, vw, vh)
	if InCombatLockdown() or wm:IsShown() or not wm.SetMapID or not Needed(wm) then return end
	local zone = Geo.ZoneAt(left + vw / scale / 2, top + vh / scale / 2)
	if not zone or zone == lastZone then return end
	lastZone = zone
	if wm:GetMapID() ~= zone then pcall(wm.SetMapID, wm, zone) end
end

-- AzerothVeil: a pool's pins in use: its own enumerator, else the map's (EnumeratePinsByTemplate, its public way)
local function Active(wm, template, pool)
	if type(pool) == "table" and pool.EnumerateActive then return pool:EnumerateActive() end
	if wm.EnumeratePinsByTemplate then return wm:EnumeratePinsByTemplate(template) end
	return function() end
end
-- AzerothVeil: where a pin is on its map (0 to 1): where MapCanvasPinMixin keeps it (SetPosition), else its
-- GetPosition, else (still on Blizzard's canvas) its anchor there; plain numbers only (ns.Plain: never a secret)
local function PinXY(wm, pin)
	local x, y = FM.Plain(pin.normalizedX), FM.Plain(pin.normalizedY)
	if type(x) == "number" and type(y) == "number" then return x, y end
	if type(pin.GetPosition) == "function" then
		local ok, px, py = pcall(pin.GetPosition, pin)
		px, py = FM.Plain(px), FM.Plain(py)
		if ok and type(px) == "number" and type(py) == "number" then return px, py end
	end
	local canvas = wm.ScrollContainer and wm.ScrollContainer.Child
	local point, rel, relPoint, ox, oy = pin:GetPoint(1)
	ox, oy = FM.Plain(ox), FM.Plain(oy)
	if canvas and rel == canvas and relPoint == "TOPLEFT" and type(ox) == "number" and type(oy) == "number" then
		local w, h = canvas:GetWidth(), canvas:GetHeight()
		local sc = pin:GetScale() or 1
		if w and w > 0 and h and h > 0 then return ox * sc / w, -oy * sc / h end
	end
end

-- AzerothVeil: where each pin came from (Blizzard's canvas, an addon's own layer), to give it back
local origin = setmetatable({}, { __mode = "k" })
local function Borrow(pin)
	if pin:GetParent() ~= layer then
		origin[pin] = pin:GetParent()
		pin:SetParent(layer)
	end
end

-- (AzerothVeil: given back to where it came from, not only hidden: its addon may show it again (a new zone laid
-- out, a pool's pin taken again) and it must then be on its own hidden map, not on ours, anchored elsewhere)
local function Release(pin)
	hosted[pin] = nil
	if pin:GetParent() == layer then
		local from = origin[pin]
		if from then pin:SetParent(from) else pin:Hide() end
	end
end

function A.Init(parent, level)
	layer = CreateFrame("Frame", nil, parent)
	layer:SetAllPoints()
	layer:SetFrameLevel(level)
end

local lastZoom = 0
function A.Layout(left, top, scale, vw, vh, zoom)
	if not layer then return end
	pass = pass + 1
	lastZoom = zoom
	local wm = _G.WorldMapFrame
	if On() and wm and type(wm.pinPools) == "table" and zoom >= OpenZoom() then
		Hook(wm)
		Drive(wm, left, top, scale, vw, vh)
		local map = wm:GetMapID()
		if map and zoom >= ShowZoom() then
			local level = layer:GetFrameLevel() + 1
			local gather = GatherOn()
			for template, pool in pairs(wm.pinPools) do
				do
					for pin in Active(wm, template, pool) do
						if not Owner(template, pin) then break end
						local x, y = PinXY(wm, pin)              -- (AzerothVeil: wherever it's kept)
						local u, v
						-- (the gathering addons' icons, turned off with the tools' button: left out)
						if x and y and (gather or not GatherPin(template, pin)) and Wanted(PinAddon(template, pin)) then   -- (AzerothVeil: its addon's option)
							u, v = Geo.MapToUnits(map, x, y)
						end
						if u then
							if pin:GetParent() ~= layer then
								Borrow(pin)
								pin:SetFrameLevel(level)
							end
							pin:SetScale(1)
							pin:ClearAllPoints()
							pin:SetPoint("CENTER", layer, "TOPLEFT", (u - left) * scale, (top - v) * scale)
							pin:Show()
							hosted[pin] = pass
						end
					end
				end
			end
			-- AzerothVeil: the pins of the addons with a layer of their own (RareScanner), at the same zoom
			local strata = layer:GetFrameStrata()
			for pin, e in pairs(ownPins) do
				local x, y, m = e.At(pin)
				local u, v
				if x and y and Wanted(e.addon) then u, v = Geo.MapToUnits(m or map, x, y) end
				if u then
					Borrow(pin)
					pin:SetFrameStrata(strata)
					pin:SetFrameLevel(level)
					pin:SetScale(1)
					pin:ClearAllPoints()
					pin:SetPoint("CENTER", layer, "TOPLEFT", (u - left) * scale, (top - v) * scale)
					pin:Show()
					hosted[pin] = pass
				end
				-- (what it was laid out from, placed or not: Tick looks again only once that changes)
				ownPlaced[pin] = x and y and x + y * 7 + (m or 0) * 13 or nil
			end
		end
	end
	for pin, p in pairs(hosted) do
		if p ~= pass then Release(pin) end
	end
end

-- (now and then: a pin the hidden map took back is put back on ours)
function A.Tick(elapsed)
	checkAcc = checkAcc + elapsed
	if checkAcc < CHECK_EVERY then return end
	checkAcc = 0
	for pin in pairs(hosted) do
		if pin:GetParent() ~= layer or select(2, pin:GetPoint(1)) ~= layer then Changed() return end
	end
	-- AzerothVeil: an addon with a layer of its own (RareScanner) laid its pins out again: new ones, others
	-- placed elsewhere or released (only while ours are shown, from their zoom)
	local wm = _G.WorldMapFrame
	if not (On() and wm and lastZoom >= ShowZoom() and AnyOwn()) then return end
	if LookForOwn(wm) then Changed() return end
	for pin, e in pairs(ownPins) do
		local x, y, m = e.At(pin)
		if (x and y and x + y * 7 + (m or 0) * 13 or nil) ~= ownPlaced[pin] then Changed() return end
	end
end

-- (the map closed: the next opening looks at the zone again)
function A.OnHide()
	lastZone = nil
	-- (AzerothVeil: and every pin given back, so Blizzard's map has them all if it's opened next)
	for pin in pairs(hosted) do Release(pin) end
end

function A.Refresh() Changed() end

-- /av addons: what it sees, to find why an addon's icons don't show
function A.Report()
	local P = FM.Print
	local wm = _G.WorldMapFrame
	P(("Other addons' icons: option %s, Blizzard's map %s, its zone %s (ours: %s), zoom %.2f (they show from %.2f)%s"):format(
		On() and "on" or "OFF", wm and "loaded" or "NOT LOADED", tostring(wm and wm:GetMapID()), tostring(lastZone),
		lastZoom, ShowZoom(), InCombatLockdown() and ", in combat" or ""))
	if not (wm and type(wm.pinPools) == "table") then return end
	-- (the addons that put a provider of icons on Blizzard's map: the game says who added each)
	local names = {}
	for provider in pairs(wm.dataProviders or {}) do
		local addon = ProviderAddon(provider)
		if addon then names[addon] = (names[addon] or 0) + 1 end
	end
	local list = {}
	for addon in pairs(names) do list[#list + 1] = addon end
	table.sort(list)
	P("  addons with icons on Blizzard's map: " .. (#list > 0 and table.concat(list, ", ") or "none"))
	P("  Blizzard's map replaced: " .. ((FM.Takeover and FM.Takeover.MapStopped()) and "yes" or "no (option off)")
		.. "; driven for those icons: " .. (Needed(wm) and "yes" or "no"))
	if FM.Takeover then FM.Takeover.Report(P) end
	local n = 0
	for pin in pairs(hosted) do n = n + 1 end
	for template, pool in pairs(wm.pinPools) do
		local active, first = 0, nil
		for pin in Active(wm, template, pool) do active = active + 1 first = first or pin end
		if active > 0 then
			local verdict = first and (Owner(template, first) and ("an addon's (" .. (PinAddon(template, first) or "others") .. ")"
				.. (Wanted(PinAddon(template, first)) and ": shown" or ": hidden (its option)")
				.. (GatherPin(template, first) and (GatherOn() and ", gathering" or ", gathering: hidden (tools' button)") or ""))
				or "Blizzard's / Questie's: left out") or "?"
			P(("  %s: %d (%s)%s"):format(tostring(template), active, verdict,
				first and not PinXY(wm, first) and ", no position" or ""))
		end
	end
	for _, e in ipairs(OWN_LAYERS) do
		if FM.IsAddOnLoaded(e.addon) then
			local known, placed = 0, 0
			for pin, pe in pairs(ownPins) do
				if pe == e then known = known + 1 if hosted[pin] then placed = placed + 1 end end
			end
			P(("  %s (a layer of its own): %s, %d pins seen, %d on our map"):format(e.addon,
				not OwnMethod(e) and "its code NOT FOUND" or ownLayer[e] and "layer found" or "layer NOT FOUND yet", known, placed))
		end
	end
	P(("  on our map now: %d"):format(n))
	if FM.AddonButtons then FM.AddonButtons.Report(P) end          -- (AzerothVeil: their map buttons)
end
