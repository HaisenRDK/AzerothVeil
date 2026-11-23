-- AzerothVeil — Modules/Quests.lua
-- "Quests": the quest log's quests on the map as Blizzard's map shows them (their buttons, the "!" of
-- quests to pick up, the quest areas), Questie's icons when it's installed, and the quest log docked
-- beside the map, which the L key and the objective tracker's clicks can open instead of Blizzard's.
--
-- The work is PerfectMap's: Engine/Quests.lua (the map's quests), Engine/QuestLog.lua (the log),
-- Engine/Takeover.lua and the L key (Engine/Core.lua). This module owns their settings and writes the
-- engine's switches (FM.db.questPOI, questOffers, questAreas, pins.questie, questLog, replaceQuestLog),
-- all false while it's off (Engine/Core.lua turns them off at each load, before it starts).
-- Off: WoW's own way. No quest on the map, no log beside it; L and the tracker open Blizzard's quest log.
-- (The engine's quest events stay heard: the Dungeons module's Quests tab reads them too.)
local _, ns = ...
local L = ns.L

local QUESTIE_ICON = "Interface\\AddOns\\Questie\\Icons\\questie.png"

local Quests = ns.Modules:Register({
	name = "quests",
	title = L["Quests"],
	description = L["The quest log's quests on the map as Blizzard's map shows them, the quests to pick up and the quest areas, Questie's icons, and a quest log docked beside the map that L and the objective tracker open."],
	onText = L["the quests picked below show on the map; the quest log beside it replaces Blizzard's if that option is on."],
	offText = L["WoW's own way: no quest on this map, no quest log beside it; L and the objective tracker open Blizzard's quest log."],
	order = 20,
	icon = "Interface\\GossipFrame\\AvailableQuestIcon",
	defaultEnabled = true,
	settings = {
		{ type = "header", label = L["On the map"] },
		{ key = "poi", iconMenu = true, icon = "Interface\\GossipFrame\\ActiveQuestIcon", type = "toggle", default = true,
			label = L["Objectives & turn-ins"],
			tooltip = L["The quest log's quests, as Blizzard's map shows them."] },
		{ key = "poiFar", icon = "Interface\\Icons\\INV_Misc_Map_01", type = "toggle", default = true, parent = "poi",
			label = L["At every zoom"],
			tooltip = L["Every quest of the log shows on the map even zoomed right out, over the continents. Off: there, only the followed one, as Blizzard's continent map does."] },
		{ key = "offers", iconMenu = true, icon = "Interface\\GossipFrame\\AvailableQuestIcon", type = "toggle", default = true,
			label = L["Quests to pick up"],
			tooltip = L["The quests you can take, as Blizzard's map shows them."] },
		{ key = "areas", icon = "Interface\\Icons\\INV_Misc_Map_01", type = "toggle", default = true,
			label = L["Quest areas"],
			tooltip = L["The blue area of the followed quest, and of the one under the mouse."] },
		{ key = "questie", iconMenu = true, icon = QUESTIE_ICON, type = "toggle", default = true,
			label = L["Questie icons"],
			tooltip = L["With Questie installed: Questie's quest, objective and turn-in icons, with its own tooltips."] },
		{ key = "tipLevel", icon = "Interface\\Icons\\INV_Misc_Note_02", type = "toggle", default = true,
			label = L["Quest level in tooltips"],
			tooltip = L["Hovering a quest on the map: its level before its name, \"(level) Name\", with its kind's letter: D dungeon, R raid, P PvP, + elite or group, L legendary."] },
		{ type = "header", label = L["Quest log"] },
		{ key = "log", icon = "Interface\\Icons\\INV_Misc_Book_09", type = "toggle", default = true,
			label = L["Quest log beside the map"],
			tooltip = L["Docked to the map's right: the window grows, the map keeps its shape. The button at the map's bottom right folds it away or brings it out."] },
		{ key = "replace", icon = "Interface\\QuestFrame\\UI-QuestLog-BookIcon", type = "toggle", default = true, parent = "log",
			label = L["Replace Blizzard's quest log"],
			tooltip = L["L opens this map's quest log. Outside combat, so does clicking a quest in the objective tracker or its menu."] },
		{ key = "kindStyle", icon = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull", type = "select", default = "text", parent = "log",
			values = { { "text", L["Text: (Elite), (Dungeon)..."] }, { "icon", L["Icon"] } },
			label = L["Quest kind"],
			tooltip = L["In the list, an elite, dungeon, raid or group quest's kind: written at the end of its line, as Blizzard's quest log does, or an icon after its name."] },
		{ key = "objIcons", icon = "Interface\\AddOns\\AzerothVeil\\Media\\Questie\\loot", type = "toggle", default = true, parent = "log",
			label = L["Quest objective icons"],
			tooltip = L["In the list, after a quest's name: the icon of what it asks next (kill, collect, use...), or of the item it's done with."] },
		{ key = "kindFrame", icon = "Interface\\AddOns\\AzerothVeil\\Media\\dragon_elite", type = "toggle", default = true, parent = "log",
			label = L["Dungeon and elite frames"],
			tooltip = L["Round the icon left of a quest: the dungeon's or raid's symbol behind it for a dungeon's or a raid's quest, the elite bosses' dragon for an elite quest."] },
		{ key = "diffColors", icon = "Interface\\GossipFrame\\AvailableQuestIcon", type = "toggle", default = true, parent = "log",
			label = L["Quest colour by difficulty"],
			tooltip = L["In the list, each quest's name in its difficulty's colour (red, orange, yellow, green, grey). Off: all in yellow."] },
		{ key = "titleFont", icon = "Interface\\Icons\\INV_Misc_Book_11", type = "select", default = "ours", parent = "log",
			values = { { "ours", L["Friz Quadrata"] }, { "blizzard", L["Blizzard"] } },
			label = L["Titles' font"],
			tooltip = L["On a quest's page, the font of its titles (its name, Description, Rewards): the addon's, or Blizzard's decorative one."] },
		{ key = "textFont", icon = "Interface\\Icons\\INV_Misc_Note_01", type = "select", default = "ours", parent = "log",
			values = { { "ours", L["Friz Quadrata"] }, { "blizzard", L["Blizzard"] } },
			label = L["Text's font"],
			tooltip = L["On a quest's page, the font of its text: the addon's, or the game's."] },
		{ key = "rewardColors", icon = "Interface\\Icons\\INV_Misc_Gem_Emerald_02", type = "toggle", default = true, parent = "log",
			label = L["Rewards in their quality's colour"],
			tooltip = L["On a quest's page, each reward's name in its quality's colour: green uncommon, blue rare, purple epic..."] },
		{ key = "search", icon = "Interface\\Common\\UI-Searchbox-Icon", type = "toggle", default = true, parent = "log",
			label = L["Search box"],
			tooltip = L["At the top of the quest log, across its whole width."] },
		{ key = "count", icon = "Interface\\Icons\\INV_Misc_Note_01", type = "toggle", default = true, parent = "log",
			label = L["Quest count"],
			tooltip = L["Under the search box: your quests, out of as many as the log can hold."] },
		{ key = "foldAll", icon = "Interface\\Buttons\\UI-MinusButton-Up", type = "toggle", default = true, parent = "log",
			label = L["Collapse all / Expand all"],
			tooltip = L["At the end of the count's line: folds every zone of the list, or opens them all."] },
		{ key = "zoneCount", icon = "Interface\\Icons\\INV_Misc_Map_01", type = "toggle", default = true, parent = "log",
			label = L["Quests per zone"],
			tooltip = L["After a folded zone's name: its quests in the objective tracker / its quests in the log."] },
	},
})

-- writes what's in effect into the engine's switches (all false while the module is off)
local function Apply(self, running)
	local function On(key) return running and self:IsOptionActive(key) or false end
	local db = ns.db
	db.questPOI = On("poi")
	db.questPOIFar = On("poiFar")
	db.questOffers = On("offers")
	db.questAreas = On("areas")
	db.pins.questie = On("questie")
	db.questLog = On("log")
	db.replaceQuestLog = On("replace")
	db.questTipLevel = On("tipLevel")
	db.questKindStyle = running and self:Get("kindStyle") or "text"
	db.questObjIcons = On("objIcons")
	db.questKindFrame = On("kindFrame")
	db.questDiffColors = On("diffColors")
	db.questTitleFont = running and self:Get("titleFont") or "ours"
	db.questTextFont = running and self:Get("textFont") or "ours"
	db.questRewardColors = On("rewardColors")
	db.questSearch = On("search")
	db.questCount = On("count")
	db.questFoldAll = On("foldAll")
	db.questZoneCount = On("zoneCount")
	if ns.QuestLog and ns.QuestLog.Apply then ns.QuestLog.Apply() end
	if ns.ApplyBindings then ns.ApplyBindings() end      -- (the L key: ours or Blizzard's)
	if ns.Map.IsShown() then ns.Pins.Ensure() end
	if ns.Quests then ns.Quests.OnToggle() end
	ns.Map.MarkDirty()
end

function Quests:Enable() Apply(self, true) end
function Quests:Disable() Apply(self, false) end
function Quests:Refresh() Apply(self, true) end
