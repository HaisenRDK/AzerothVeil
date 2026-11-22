-- AzerothVeil — Modules/Transports.lua
-- "Transports": harbors, zeppelin towers, the Deeprun Tram and Zephras Isle's airships on the map, the
-- lines of their routes, each boat and zeppelin where it is now (tracking), the sightings traded with
-- other AzerothVeil and PerfectMap users, and a click on a dock that takes the map to where it goes.
--
-- The work is PerfectMap's: Engine/Pins.lua (the docks' icons), Engine/Routes.lua (the lines),
-- Engine/Vessels.lua (live boats, the 0.8 s tracking check, the PerfectMapSail messages). This module
-- owns their settings and switches them: the engine's switches (FM.db.pins.boat..., FM.db.routes,
-- FM.db.vessels, FM.db.vesselSync, FM.db.enemyHarbors) are only what it writes, false while it's off
-- (Engine/Core.lua turns them off at each load, before it starts).
-- Off: no dock icon, no line, no live boat, no tracking timer, no addon message sent or heard.
--
-- The docks as OpenMap shows them: one icon for each way (Engine/Pins.lua), never merged or summed with
-- the ones near it (PerfectMap made a tower's platforms one icon): Tanaris' tower is two zeppelin icons.
-- The click (as OpenMap's DockClick, Map/Stitch.lua): no tooltip, no menu, straight to the other end of
-- that icon's way, the map centred on the dock there, at least as close as OpenMap's zoom 6.
-- Back: a click on the dock you arrived at (its way home), or as usual (wheel, drag, Center on me).
local _, ns = ...
local L = ns.L

local Transports = ns.Modules:Register({
	name = "transports",
	title = L["Transports"],
	description = L["Harbors, zeppelin towers and the Deeprun Tram on the map, the lines of their routes, and each boat and zeppelin where it is now. A click on a dock takes the map to where it goes.\n\nOff: none of it is shown and nothing of it runs."],
	order = 40,
	defaultEnabled = true,
	settings = {
		{ type = "header", label = L["Display"] },
		{ key = "boats", type = "toggle", default = true,
			label = L["Show boats"],
			tooltip = L["Harbors and their boats (yours and the goblins', which take everyone)."] },
		{ key = "enemyHarbors", type = "toggle", default = false, parent = "boats",
			label = L["The other faction's harbors"],
			tooltip = L["The other faction's harbors too, with their boats' routes (named in red)."] },
		{ key = "zeppelins", type = "toggle", default = true,
			label = L["Show zeppelins"],
			tooltip = L["Zeppelin towers and their zeppelins."] },
		{ key = "others", type = "toggle", default = true,
			label = L["Show other transports"],
			tooltip = L["The other ways to travel the game has data for: the Deeprun Tram, Zephras Isle's airships."] },
		{ key = "tram", type = "toggle", default = true, parent = "others",
			label = L["Deeprun Tram"],
			tooltip = L["The tram's two stations, in Stormwind and Ironforge."] },
		{ key = "airships", type = "toggle", default = false, parent = "others",
			label = L["Zephras Isle airships"],
			tooltip = L["The airships' docks to and from Zephras Isle (a click opens the isle's own map)."] },
		{ key = "routes", type = "toggle", default = true,
			label = L["Show route lines"],
			tooltip = L["A thin line along the way each boat and zeppelin sails, over its dock when the cursor is on it. Alliance boats blue, the rest red."] },
		{ key = "routesAll", type = "toggle", default = false, parent = "routes",
			label = L["Always show every route"],
			tooltip = L["Every route at once, not only the hovered dock's. Also the routes button in the map's tools."] },
		{ type = "header", label = L["Features"] },
		{ key = "tracking", type = "toggle", default = true,
			label = L["Boat & zeppelin tracking"],
			tooltip = L["Each boat and zeppelin where it is right now, moving along its route. Learnt while you ride one (a light check of where you are, every 0.8 s) or from players sharing it."] },
		{ key = "share", type = "toggle", default = true, parent = "tracking",
			label = L["Share sightings"],
			tooltip = L["Trade when each boat and zeppelin was seen with your guild, your group and your friends who use AzerothVeil or PerfectMap."] },
		{ key = "clickTravel", type = "toggle", default = true,
			label = L["Click: go to the destination"],
			tooltip = L["A click on a boat, zeppelin or tram icon takes the map straight to where it goes."] },
	},
})

-- the engine's icon kind -> this module's setting
local PIN_SETTING = { boat = "boats", zeppelin = "zeppelins", tram = "tram", airship = "airships" }

---------------------------------------------------------------------------
-- The click: the map to the other end (OpenMap's GlideToWorld(pin.to, 6), as a jump)
---------------------------------------------------------------------------
local OPENMAP_ZOOM = 6                 -- (OpenMap's dock click: world map widths across, / 6)

-- how much of the world is across the view after the jump: as now, or OpenMap's zoom if that's closer
function Transports.TravelAcross(across, worldWidth)
	local target = worldWidth / OPENMAP_ZOOM
	if not across or across <= 0 then return target end
	return math.min(across, target)
end

local function Travel(pin)
	local w = pin.travel and pin.travel[1]
	if not (w and w.u and w.v) then return end
	local _, _, scale, vw = ns.Map.ViewNow()
	local across = (scale and scale > 0 and vw) and vw / scale or nil
	ns.Map.SetView(w.u, w.v, Transports.TravelAcross(across, ns.W))
end

---------------------------------------------------------------------------
-- Switching the engine
---------------------------------------------------------------------------
-- writes what's in effect into the engine's switches (all false while the module is off)
local function Apply(self, running)
	local function On(key) return running and self:IsOptionActive(key) or false end
	local db = ns.db
	local wasEnemy = db.enemyHarbors
	for kind, key in pairs(PIN_SETTING) do db.pins[kind] = On(key) end
	db.enemyHarbors = On("enemyHarbors")
	db.routes = On("routesAll")
	db.vessels = On("tracking")
	db.vesselSync = On("share")
	ns.Routes.SetEnabled(On("routes"))
	if running then
		ns.Vessels.SetTracking(On("tracking"))
		ns.Vessels.SetSharing(On("share"))
	end
	ns.Pins.OnTravelClick = On("clickTravel") and Travel or nil
	-- (which harbors there are changed: built again; else only what's shown)
	if wasEnemy ~= db.enemyHarbors then
		if ns.Map.IsShown() then ns.Pins.RebuildPlaces() else ns.Pins.InvalidatePlaces() end
	elseif ns.Map.IsShown() then
		ns.Pins.Ensure()
	end
	if ns.Map.routesButton then ns.Map.routesButton:SetActive(db.routes) end
	ns.Map.MarkDirty()
end

function Transports:Enable()
	ns.Vessels.Start()
	Apply(self, true)
end

function Transports:Disable()
	ns.Vessels.Stop()
	Apply(self, false)
end

function Transports:Refresh(key, value)
	Apply(self, true)
	-- (sharing turned on: what's missing asked for now, as PerfectMap's option did)
	if key == "share" and value then ns.Vessels.SyncChanged() end
end
