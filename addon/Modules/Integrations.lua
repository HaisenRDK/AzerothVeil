-- AzerothVeil — Modules/Integrations.lua
-- "Integrations": everything AzerothVeil does with another addon, one section each. Every one of them is
-- optional: an option whose addon isn't there is greyed, "(not installed)" (requiresAddOns on the setting,
-- Core/ModuleManager.lua), and nothing of that addon is used.
--   * Dungeon journals: what a click on a dungeon's entrance opens: AzerothVeil's map, DungeonJournal's page
--     or NeedRoll's (Integrations/DungeonJournal.lua, Integrations/NeedRoll.lua; the click itself is the
--     Dungeons module's, which asks this module: Integrations.Journal);
--   * Questie: its icons on the map (Engine/Quests.lua mirrors them), its data for the dungeons' quests
--     (the Dungeons module's Quests tab: Integrations/Questie.lua);
--   * Forever Quest Tint: its marks on this map's quests and quest log (Engine/Tint.lua);
--   * the other addons' map icons (HandyNotes, TomTom, GatherMate2, RareScanner...: Engine/AddonPins.lua).
-- It writes the engine's switches (FM.db.pins.questie, questTint, addonPins), all false while it's off
-- (Engine/Core.lua turns them off at each load, before it starts).
-- (The data AzerothVeil reads from DungeonJournal for its own dungeon maps, the floors' passages and the
-- bosses' loot, aren't settings: they're used where they're there. Sharing markers, places and boats'
-- sightings with OpenMap and PerfectMap users is the Markers, Friends & guild and Transports modules'.)
-- Off: no other addon is used; a dungeon's entrance opens AzerothVeil's map.
local _, ns = ...
local L = ns.L

local QUESTIE_ICON = "Interface\\AddOns\\Questie\\Icons\\questie.png"

-- an addon's own icon when it's there, else the game's (its option greyed then, its file absent)
local function AddonIcon(addon, path, fallback)
	return function() return ns.IsAddOnLoaded(addon) and path or fallback end
end
local OTHER_ICON = "Interface\\Icons\\INV_Misc_Map_02"
-- the addons whose icons each have an option (Engine/AddonPins.lua knows their pins: its KNOWN), then the rest
-- (the settings below, pins<Addon>, and Apply's FM.db.addonPinsBy)
local PIN_ADDONS = {
	{ "GatherMate2", AddonIcon("GatherMate2", "Interface\\AddOns\\GatherMate2\\Artwork\\Icon", "Interface\\Icons\\Trade_Herbalism") },
	{ "HandyNotes", "Interface\\Icons\\INV_Misc_Note_02" },
	{ "TomTom", AddonIcon("TomTom", "Interface\\AddOns\\TomTom\\Images\\Modern\\TomTom-Logo", "Interface\\Icons\\INV_Misc_Spyglass_02") },
	{ "RareScanner", AddonIcon("RareScanner", "Interface\\AddOns\\RareScanner\\Media\\Icons\\OriginalSkull", "Interface\\TargetingFrame\\UI-TargetingFrame-Skull") },
}

-- the journals a click on an entrance can open (the "journal" option's values; "ours": AzerothVeil's map)
local JOURNALS = { dj = ns.DungeonJournal, needroll = ns.NeedRoll }

local Integrations = ns.Modules:Register({
	name = "integrations",
	title = L["Integrations"],
	description = L["What AzerothVeil does with other addons, when they're installed: DungeonJournal or NeedRoll for the dungeons, Questie, Forever Quest Tint, and the icons other addons put on the map (HandyNotes, TomTom, GatherMate2, RareScanner...)."],
	onText = L["the addons picked below are used when they're installed."],
	offText = L["no other addon is used; a dungeon's entrance opens AzerothVeil's map."],
	order = 60,
	icon = "Interface\\Icons\\INV_Misc_Gear_01",
	settings = {
		{ type = "header", label = L["Dungeon journals"] },
		{ key = "journal", icon = "Interface\\Icons\\INV_Misc_Book_09", type = "select", default = "dj",
			values = { { "ours", L["AzerothVeil's map"] }, { "dj", "DungeonJournal" }, { "needroll", "NeedRoll" } },
			label = L["A click on an entrance opens"],
			tooltip = L["Which one shows a dungeon when its entrance is clicked: AzerothVeil's own map, or the page of that dungeon in DungeonJournal or NeedRoll (its map, quests, bosses and loot); AzerothVeil's tabs then stay away. Their own settings apply."] .. "\n" .. L["The one picked not installed, or without that dungeon: AzerothVeil's map."] },
		{ type = "header", label = "Questie" },
		{ key = "questieIcons", iconMenu = true, icon = QUESTIE_ICON, type = "toggle", default = true, requiresAddOns = { "Questie" },
			label = L["Questie icons"],
			tooltip = L["With Questie installed: Questie's quest, objective and turn-in icons, with its own tooltips."] },
		{ key = "questieDungeons", icon = "Interface\\GossipFrame\\AvailableQuestIcon", type = "toggle", default = true, requiresAddOns = { "Questie" },
			label = L["Use Questie's data for dungeon quests"],
			tooltip = L["With Questie installed: every quest of the dungeon for your faction, not only those of your log: available, not yet, in progress or done (the game's own state), who gives it and where. Read from Questie, nothing changed there."] },
		{ key = "questieOnlyMine", icon = "Interface\\TargetingFrame\\UI-PVP-FFA", type = "toggle", default = true, parent = "questieDungeons",
			requiresAddOns = { "Questie" },
			label = L["Only quests for my faction and class"],
			tooltip = L["Off: every quest of the dungeon, those of the other faction and of other classes too; a quest for one faction or for some classes only shows their icons at the end of its line."] },
		{ type = "header", label = "Forever Quest Tint" },
		{ key = "questTint", icon = "Interface\\GossipFrame\\AvailableQuestIcon", type = "toggle", default = true, requiresAddOns = { "ForeverQuestTint" },
			label = L["Its marks on the quests"],
			tooltip = L["The quests WoW Forever added marked as Forever Quest Tint marks them, by its own settings: its colour on their map icons, its sign after their names in the quest log."] },
		{ type = "header", label = L["Other addons' map icons"] },
		{ key = "addonPins", iconMenu = true, icon = OTHER_ICON, type = "toggle", default = true,
			label = L["Other addons' icons"],
			tooltip = L["Icons other addons put on Blizzard's map (GatherMate2, HandyNotes, TomTom and others) show on this one, exactly where they put them, with their own tooltips and clicks."] .. "\n" .. L["They show two steps of the wheel closer than the townsfolk."] },
		{ key = "pinsGatherMate2", iconMenu = true, icon = PIN_ADDONS[1][2], type = "toggle", default = true, parent = "addonPins",
			requiresAddOns = { "GatherMate2" }, label = "GatherMate2", tooltip = L["%s's icons on the map."]:format("GatherMate2") },
		{ key = "pinsHandyNotes", iconMenu = true, icon = PIN_ADDONS[2][2], type = "toggle", default = true, parent = "addonPins",
			requiresAddOns = { "HandyNotes" }, label = "HandyNotes", tooltip = L["%s's icons on the map."]:format("HandyNotes") },
		{ key = "pinsTomTom", iconMenu = true, icon = PIN_ADDONS[3][2], type = "toggle", default = true, parent = "addonPins",
			requiresAddOns = { "TomTom" }, label = "TomTom", tooltip = L["%s's icons on the map."]:format("TomTom") },
		{ key = "pinsRareScanner", iconMenu = true, icon = PIN_ADDONS[4][2], type = "toggle", default = true, parent = "addonPins",
			requiresAddOns = { "RareScanner" }, label = "RareScanner", tooltip = L["%s's icons on the map."]:format("RareScanner") },
		{ key = "pinsOthers", iconMenu = true, icon = OTHER_ICON, type = "toggle", default = true, parent = "addonPins",
			label = L["Other addons"], tooltip = L["The icons of every other addon that puts some on Blizzard's map."] },
		{ key = "addonButtons", icon = "Interface\\Buttons\\UI-OptionsButton", type = "toggle", default = true,
			label = L["Other addons' map buttons"],
			tooltip = L["The buttons other addons put on Blizzard's map (RareScanner's filters and others), on this one, under the icon menu's button: the same buttons, their clicks and menus their own. Questie's: this map's own Questie button."] },
	},
})

---------------------------------------------------------------------------
-- What the other modules ask
---------------------------------------------------------------------------
-- the dungeon journal picked (Integrations/*.lua: Available, KeysFor, Open, Label), if it's there; else nil
function Integrations.Journal()
	local MM = ns.Modules
	if not MM:IsOptionActive("integrations", "journal") then return nil end
	local J = JOURNALS[MM:GetSetting("integrations", "journal")]
	return J and J.Available() and J or nil
end

---------------------------------------------------------------------------
-- Switching the engine
---------------------------------------------------------------------------
local function Apply(self, running)
	local function On(key) return running and self:IsOptionActive(key) or false end
	local db = ns.db
	local was = { questTint = db.questTint }
	db.pins.questie = On("questieIcons")
	db.questTint = On("questTint")
	db.addonPins = On("addonPins")
	-- (each addon's icons: Engine/AddonPins.lua reads them at its next layout)
	local by = { others = On("pinsOthers") }
	for _, a in ipairs(PIN_ADDONS) do by[a[1]] = On("pins" .. a[1]) end
	db.addonPinsBy = by
	if ns.AddonPins then ns.AddonPins.Refresh() end
	db.addonButtons = On("addonButtons")
	if ns.AddonButtons then ns.AddonButtons.Update() end
	if was.questTint ~= db.questTint and ns.QuestLog and ns.QuestLog.Apply then ns.QuestLog.Apply() end
	if ns.Map.IsShown() then ns.Pins.Ensure() end
	if ns.Quests then ns.Quests.OnToggle() end
	ns.Map.MarkDirty()
end

function Integrations:Enable() Apply(self, true) end
function Integrations:Disable() Apply(self, false) end
function Integrations:Refresh() Apply(self, true) end
