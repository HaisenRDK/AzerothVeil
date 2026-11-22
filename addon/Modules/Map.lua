-- AzerothVeil — Modules/Map.lua
-- "Map": how the map opens and what it draws. M opening it instead of Blizzard's, where it opens and at what
-- zoom, the minimap button, fading while you move; the fog of war (unexplored land as Blizzard's map shows
-- it, else the whole map), the zone under the cursor lit, identical icons summed, other addons' icons, the
-- icons' size; caves, the minimap's terrain and the zones' fishing skill up close.
--
-- The work is PerfectMap's (Engine/Map.lua, Pins.lua, AddonPins.lua, Caves.lua, Terrain.lua, the M key in
-- Engine/Core.lua and Takeover.lua) and the fog's (Engine/Fog.lua, from OpenMap). This module owns their
-- settings (once the engine's own Map tab in the options) and writes the engine's switches (FM.db.replaceM,
-- reopen, rememberZoom, fadeMoving, hoverHighlight, joinIcons, addonPins, iconScale, underground,
-- minimapTerrain, zoneFishing), all off while it's off (Engine/Core.lua turns them off at each load, before
-- it starts), and shows the minimap button or not (UI/MinimapButton.lua). The townsfolk of land not explored
-- yet (the Icons module's) shown or not: FM.db.npcUnexplored (Engine/Pins.lua, Found).
-- Off: the map plain. M opens Blizzard's map; this one still opens with /av or the addon compartment, whole,
-- without its extras (no fog, no highlight, no other addons' icons, no caves or terrain up close, no minimap
-- button), every townsfolk shown. The exploration event is heard only while the fog is on or the townsfolk of
-- unexplored land are hidden.
local _, ns = ...
local L = ns.L

local Map = ns.Modules:Register({
	name = "map",
	title = L["Map"],
	description = L["How the map opens and what it draws: M, the minimap button, the fog of war over the land you haven't explored, the zone under the cursor, other addons' icons, the icons' size, and the detail that comes in up close."],
	onText = L["the options below apply to the map."],
	offText = L["the map plain: M opens Blizzard's map; this one still opens with /av or the addon compartment, without fog, highlight, other addons' icons, caves or terrain up close, nor minimap button."],
	order = 5,
	icon = "Interface\\Icons\\INV_Misc_Map_01",
	defaultEnabled = true,
	settings = {
		{ type = "header", label = L["Map"] },
		{ key = "replaceM", type = "toggle", default = true,
			label = L["Open with M"],
			tooltip = L["M opens this map instead of Blizzard's. Outside combat, so do the map buttons, map pins in chat, quests' \"show on map\" and other addons."] },
		{ key = "centerOnOpen", type = "toggle", default = true,
			label = L["Centre on me when opened"],
			tooltip = L["Off: it opens where you left it."] },
		{ key = "rememberZoom", type = "toggle", default = true,
			label = L["Remember last zoom"],
			tooltip = L["The map opens at the zoom you closed it at."] .. "\n" .. L["Off: it always opens at the same zoom."] },
		{ key = "minimapButton", icon = ns.MEDIA .. "icon", type = "toggle", default = true,
			label = L["Minimap button"],
			tooltip = L["Left-click: open or close the map"] .. "\n" .. L["Right-click: options"] },
		{ key = "fadeMoving", type = "toggle", default = false,
			label = L["Fade while moving"],
			tooltip = L["The map turns see-through while you move."] },
		{ type = "header", label = L["Display"] },
		{ key = "fog", icon = "Interface\\Icons\\Ability_Vanish", type = "toggle", default = false,
			label = L["Fog of war"],
			tooltip = L["The land you haven't explored yet looks as on Blizzard's own map: blank parchment until you get there. Off: the whole map shows."] },
		{ key = "unexploredNPCs", icon = "Interface\\Minimap\\tracking\\innkeeper", type = "toggle", default = true,
			label = L["Townsfolk of unexplored areas"],
			tooltip = L["The townsfolk and trainers (the Icons module's) of the land you haven't explored yet show too."] .. "\n" .. L["Off: only where you've explored, as the game counts it; in a capital, once you've been in it."] },
		{ key = "hoverHighlight", type = "toggle", default = true,
			label = L["Highlight zone under cursor"],
			tooltip = L["The zone under the mouse lights up, as on Blizzard's continent map."] },
		{ key = "joinIcons", type = "toggle", default = true,
			label = L["Sum identical icons"],
			tooltip = L["Identical icons that overlap show as one, with their count, every one of them in its tooltip, at every zoom."] .. "\n" .. L["Off: every icon on its own."] },
		{ key = "addonPins", type = "toggle", default = true,
			label = L["Other addons' icons"],
			tooltip = L["Icons other addons put on Blizzard's map (GatherMate2, HandyNotes, TomTom and others) show on this one, exactly where they put them, with their own tooltips and clicks."] .. "\n" .. L["They show two steps of the wheel closer than the townsfolk."] },
		{ key = "iconScale", type = "range", default = 1, min = 0.6, max = 1.6, step = 0.05, fmt = "%.2f",
			label = L["Icon size"] },
		{ type = "header", label = L["Detail"] },
		{ key = "underground", type = "toggle", default = true,
			label = L["Caves up close"],
			tooltip = L["Zoom right in on a cave, mine, crypt or dungeon entrance and its own map surfaces: Blizzard's where it drew one, else the game's minimap of it inside."] },
		{ key = "minimapTerrain", type = "toggle", default = true,
			label = L["Minimap terrain up close"],
			tooltip = L["Zoomed right in, the ground turns into the minimap's own: trees, rocks, roads and buildings."] .. "\n" .. L["The sea stays the map's."] },
		{ key = "terrainNames", type = "toggle", default = true, parent = "minimapTerrain",
			label = L["Places' names up close"],
			tooltip = L["Over the minimap's terrain, the names of the places (villages, camps, mines...) the painted map writes."] .. "\n" .. L["With the fog of war, only the places you've explored."] },
		{ key = "zoneFishing", type = "toggle", default = false,
			label = L["Fishing skill of zones"],
			tooltip = L["Under the zone's name: the fishing skill its waters want."] },
	},
})

-- writes what's in effect into the engine's switches (as FM.MAP_OFF, Engine/Core.lua, while the module is off)
local function Apply(self, running)
	local function On(key) return running and self:IsOptionActive(key) or false end
	local db = ns.db
	local was = { replaceM = db.replaceM, iconScale = db.iconScale, addonPins = db.addonPins, zoneFishing = db.zoneFishing,
		npcUnexplored = db.npcUnexplored }
	db.replaceM = On("replaceM")
	db.reopen = On("centerOnOpen") and "player" or "last"
	db.rememberZoom = On("rememberZoom")
	db.fadeMoving = On("fadeMoving")
	db.hoverHighlight = On("hoverHighlight")
	db.joinIcons = On("joinIcons")
	db.addonPins = On("addonPins")
	db.iconScale = running and tonumber(self:Get("iconScale")) or 1
	db.underground = On("underground")
	db.minimapTerrain = On("minimapTerrain")
	db.zoneFishing = On("zoneFishing")
	db.terrainNames = On("terrainNames")
	db.npcUnexplored = not running or self:IsOptionActive("unexploredNPCs")
	if was.replaceM ~= db.replaceM and ns.ApplyBindings then ns.ApplyBindings() end   -- (M: ours or Blizzard's)
	if was.iconScale ~= db.iconScale and ns.Pins and ns.Pins.ApplyScale then ns.Pins.ApplyScale() end
	if was.addonPins ~= db.addonPins and ns.AddonPins then ns.AddonPins.Refresh() end
	if was.zoneFishing ~= db.zoneFishing and ns.Map.ResetHover then ns.Map.ResetHover() end
	if was.npcUnexplored ~= db.npcUnexplored and ns.Pins.RefreshExplored then ns.Pins.RefreshExplored() end
	if ns.MinimapButton then ns.MinimapButton.SetShown(On("minimapButton")) end
	-- the fog, and the exploration it follows (and the townsfolk only where you've explored): heard only while
	-- one of them is on
	local fog = On("fog")
	local foundOnly = db.npcUnexplored == false
	if ns.Fog then ns.Fog.SetEnabled(fog) end
	if fog or foundOnly then
		self:RegisterEvent("MAP_EXPLORATION_UPDATED", function()
			if ns.Fog and self:IsOptionActive("fog") then
				ns.Fog.Explored()
				if ns.Labels then ns.Labels.Explored() end        -- (the names of what's explored, with the fog)
			end
			if ns.db.npcUnexplored == false and ns.Pins.RefreshExplored then ns.Pins.RefreshExplored() end
		end)
	elseif running then
		self:UnregisterEvent("MAP_EXPLORATION_UPDATED")
	end
	ns.Map.MarkDirty()
end

function Map:Enable() Apply(self, true) end
function Map:Disable() Apply(self, false) end
function Map:Refresh() Apply(self, true) end
