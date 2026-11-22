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

local function Release(pin)
	hosted[pin] = nil
	if pin:GetParent() == layer then pin:Hide() end
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
				if pool.EnumerateActive then
					for pin in pool:EnumerateActive() do
						if not Owner(template, pin) then break end
						local x, y = pin.normalizedX, pin.normalizedY
						local u, v
						-- (the gathering addons' icons, turned off with the tools' button: left out)
						if x and y and (gather or not GatherPin(template, pin)) then u, v = Geo.MapToUnits(map, x, y) end
						if u then
							if pin:GetParent() ~= layer then
								pin:SetParent(layer)
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
end

-- (the map closed: the next opening looks at the zone again)
function A.OnHide()
	lastZone = nil
end

function A.Refresh() Changed() end

-- /pmap addons: what it sees, to find why an addon's icons don't show
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
		if pool.EnumerateActive then
			for pin in pool:EnumerateActive() do active = active + 1 first = first or pin end
		end
		if active > 0 then
			local verdict = first and (Owner(template, first) and ("an addon's: shown"
				.. (GatherPin(template, first) and (GatherOn() and ", gathering" or ", gathering: hidden (tools' button)") or ""))
				or "Blizzard's / Questie's: left out") or "?"
			P(("  %s: %d (%s)%s"):format(tostring(template), active, verdict,
				first and not first.normalizedX and ", no position" or ""))
		end
	end
	P(("  on our map now: %d"):format(n))
end
