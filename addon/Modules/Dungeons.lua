-- AzerothVeil — Modules/Dungeons.lua
-- "Dungeons": the dungeons' and raids' entrances on the map, their interior maps (floors, bosses, ways in
-- and out), the map of the place you're in, and the side panel's Quests and Bosses tabs while a dungeon's
-- map is up. With DungeonJournal (optional, Integrations/DungeonJournal.lua), a click on an entrance
-- opens its page of that dungeon instead: no second interface besides it.
--
-- The maps are PerfectMap's (Engine/Dungeon.lua, Engine/Pins.lua); this module owns their settings and
-- writes the engine's switches (FM.db.pins.dungeon / raid, dungeonMaps, dungeonBosses, dungeonLevels,
-- dungeonWays), all false while it's off (Engine/Core.lua turns them off at each load, before it starts).
-- It also:
--   * routes the click on an entrance (Pins.OnDungeonClick): its map here, or DungeonJournal's page;
--     several dungeons or wings at one entrance: the engine's chooser, every one of them listed;
--   * keeps the world's view as it was when a dungeon was opened from its entrance, and puts it back
--     (Dungeon.ReturnView: the header's World button, a right-click), the side panel too;
--   * while a dungeon's map is up, suspends the quest log beside the map (its preference untouched) for
--     the Quests and Bosses tabs (UI/DungeonPanel.lua), and gives it back after.
-- Off: no icon, no map, no tab; nothing heard, nothing scheduled.
local _, ns = ...
local L = ns.L
local DJ = ns.DungeonJournal

local function DungeonIcon() return ns.Pins.DUNGEON_ICON end
local function RaidIcon() return ns.Pins.RAID_ICON end
local BOSS_ICON = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"

local Dungeons = ns.Modules:Register({
	name = "dungeons",
	title = L["Dungeons"],
	description = L["The dungeons' and raids' entrances on the map; a click opens the dungeon's own map in the map's window, its floors, its bosses, its ways in, with its quests and bosses beside it. With DungeonJournal, its page of the dungeon opens instead."],
	onText = L["the entrances, maps and tabs picked below are there; a dungeon's map is shown inside one if that option is on."],
	offText = L["no entrance icon, no dungeon map, no tab: nothing of it shows or runs."],
	order = 30,
	icon = DungeonIcon,
	settings = {
		{ type = "header", label = L["Display"] },
		{ key = "entrances", icon = DungeonIcon, type = "toggle", default = true,
			label = L["Show the entrances"],
			tooltip = L["An icon where each dungeon or raid is entered."] },
		{ key = "dungeonPins", icon = DungeonIcon, type = "toggle", default = true, parent = "entrances",
			label = L["Dungeons"], tooltip = L["The dungeons' entrances."] },
		{ key = "raidPins", icon = RaidIcon, type = "toggle", default = true, parent = "entrances",
			label = L["Raids"], tooltip = L["The raids' entrances."] },
		{ key = "levels", type = "toggle", default = true, parent = "entrances",
			label = L["Level ranges in tooltips"],
			tooltip = L["Under each dungeon's name in its tooltip: the levels it's made for, coloured as the game colours them."] },
		{ key = "maps", icon = "Interface\\Icons\\INV_Misc_Map_01", type = "toggle", default = true,
			label = L["Interior maps"],
			tooltip = L["A click on an entrance shows the dungeon's map in the map's window (several dungeons there: a list to pick from). Back: the World button, or a right-click."] },
		{ key = "bosses", icon = BOSS_ICON, type = "toggle", default = true, parent = "maps",
			label = L["Boss markers"],
			tooltip = L["Where each boss stands on the dungeon's map, with its portrait."] },
		{ key = "ways", icon = DungeonIcon, type = "toggle", default = true, parent = "maps",
			label = L["Entrances and exits"],
			tooltip = L["Where the dungeon's map is entered and left."] },
		{ key = "auto", icon = "Interface\\Icons\\INV_Misc_Map_02", type = "toggle", default = true,
			label = L["Map of the place you're in"],
			tooltip = L["Inside a dungeon, raid or battleground, the map shows that place's own map (the header's World button: the world's)."] },
		{ type = "header", label = L["Side panel"] },
		{ key = "questsTab", icon = "Interface\\GossipFrame\\AvailableQuestIcon", type = "toggle", default = true,
			label = L["Quests tab"],
			tooltip = L["While a dungeon's map is up, beside it: the quests of your quest log for that dungeon, their progress and rewards."] },
		{ key = "bossesTab", icon = BOSS_ICON, type = "toggle", default = true,
			label = L["Bosses tab"],
			tooltip = L["While a dungeon's map is up, beside it: its bosses, their levels; a click shows where one stands."] },
		{ type = "header", label = L["Integrations"] },
		{ key = "useDJ", icon = "Interface\\Icons\\INV_Misc_Book_09", type = "toggle", default = true,
			label = L["Use DungeonJournal when it's there"],
			tooltip = L["With the DungeonJournal addon loaded, a click on an entrance opens its page of that dungeon (its map, quests, bosses and loot); AzerothVeil's tabs then stay away. Its own settings (locked dungeons, spoilers) apply."] },
	},
})

---------------------------------------------------------------------------
-- DungeonJournal: in charge of the entrances' clicks while it's there and asked for
---------------------------------------------------------------------------
-- (DungeonJournal's two parts of one of our entrances, named in the player's language)
local PART_NAMES = { ["Stratholme: Living"] = L["Stratholme: Living"], ["Stratholme: Undead"] = L["Stratholme: Undead"] }

function Dungeons:UsesJournal()
	return self:IsOptionActive("useDJ") and DJ.Available() or false
end

---------------------------------------------------------------------------
-- The world's view kept while a dungeon's map is up, put back after
---------------------------------------------------------------------------
local saved                     -- { cx, cy, across } of the world as it was; nil: none kept

function Dungeons.SaveView()
	if saved then return end   -- (a second dungeon from the first's map: back to where it all began)
	local left, top, scale, vw, vh = ns.Map.ViewNow()
	if not (scale and scale > 0 and vw and vw > 0) then return end
	saved = { cx = left + vw / 2 / scale, cy = top + vh / 2 / scale, across = vw / scale }
end

function Dungeons.ReturnView()
	if not saved then return false end
	local v = saved
	saved = nil
	ns.Map.SetView(v.cx, v.cy, v.across)     -- (a land off the world map, Zephras Isle, too: SetView knows)
	ns.Map.MarkDirty()
	return true
end

function Dungeons.SavedView() return saved end

---------------------------------------------------------------------------
-- The click on an entrance (wings: { { id, name, raid, lo, hi }, ... } as Pins.lua gives them)
---------------------------------------------------------------------------
local function OpenHere(wing)
	Dungeons.SaveView()
	ns.Dungeon.OpenWing(wing)
end

function Dungeons:Click(wings, title)
	if not wings or #wings == 0 then return end
	if self:UsesJournal() then
		-- (its dungeons for these wings; a wing it doesn't have, a raid: AzerothVeil's own map)
		local entries = {}
		for _, w in ipairs(wings) do
			local keys = DJ.KeysFor(w)
			if #keys == 0 then
				if self:IsOptionActive("maps") then entries[#entries + 1] = w end
			else
				for _, key in ipairs(keys) do
					entries[#entries + 1] = { id = w.id, name = w.name, label = #keys > 1 and (PART_NAMES[key] or key) or w.label, raid = w.raid,
						lo = w.lo, hi = w.hi, key = key }
				end
			end
		end
		local function Pick(e)
			if e.key and DJ.Open(e.key) then return end
			if self:IsOptionActive("maps") then OpenHere(e) end     -- (DungeonJournal failed: ours)
		end
		if #entries == 1 then Pick(entries[1])
		elseif #entries > 1 then ns.Dungeon.Choose(entries, nil, title, Pick) end
		return
	end
	if not self:IsOptionActive("maps") then return end
	if #wings > 1 then
		ns.Dungeon.Choose(wings, nil, title, OpenHere)
	else
		OpenHere(wings[1])
	end
end

---------------------------------------------------------------------------
-- What the side panel shows (UI/DungeonPanel.lua draws it)
---------------------------------------------------------------------------
-- the dungeon's name in the player's language (the game's), else the data's
function Dungeons.InstanceName(inst)
	local name = inst and GetRealZoneText and GetRealZoneText(inst)
	if type(name) == "string" and name ~= "" then return name end
	return ns.Pins.InstanceName and ns.Pins.InstanceName(inst) or ""
end

-- The quests of the player's log for a dungeon: those under its heading (the game files a dungeon's
-- quests under its name, in the player's language: GetRealZoneText gives the same name). Their state is
-- the game's own: complete (ready to turn in), failed, or in progress, with each objective.
-- { { questID, title, level, complete, failed, objectives = { { text, finished } } } }
function Dungeons.QuestsFor(inst)
	local out = {}
	local name = Dungeons.InstanceName(inst)
	if name == "" or not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then return out end
	local under = false
	for i = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
		local info = C_QuestLog.GetInfo(i)
		if info then
			if info.isHeader then
				under = info.title == name
			elseif under and info.questID then
				local q = info.questID
				local objectives = {}
				for _, o in ipairs(C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(q) or {}) do
					if o.text and o.text ~= "" then objectives[#objectives + 1] = { text = o.text, finished = o.finished and true or false } end
				end
				out[#out + 1] = {
					questID = q, title = info.title, level = info.level,
					complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(q) and true or false,
					failed = C_QuestLog.IsFailed and C_QuestLog.IsFailed(q) and true or false,
					objectives = objectives,
				}
			end
		end
	end
	return out
end

-- The dungeon's bosses as its map shows them, floor by floor (Dungeon.CollectBosses):
-- { { name, level, levelText, displayID, kind, floor } }; floor nil: on no map
function Dungeons.BossesFor(inst)
	local out = {}
	for _, e in ipairs(ns.Dungeon.CollectBosses(inst) or {}) do
		local b = e.boss
		if b and b[1] then
			out[#out + 1] = { name = (b[1]:gsub("%s*<[^>]*>", "")), key = b[1], level = b[2] or nil,
				levelText = b[5], displayID = b[3], kind = b[4], floor = e.floor }
		end
	end
	return out
end

---------------------------------------------------------------------------
-- The side panel: up with a dungeon's map, the quest log suspended meanwhile
---------------------------------------------------------------------------
local panelUp = false

function Dungeons:TabsWanted()
	if self:UsesJournal() then return false end
	return self:IsOptionActive("questsTab") or self:IsOptionActive("bossesTab")
end

function Dungeons:ShowPanel(inst)
	local panel = ns.DungeonPanel
	if not (panel and inst and self:TabsWanted()) then self:HidePanel() return end
	if not panelUp then
		panelUp = true
		ns.QuestLog.Suspend(true)
		ns.Map.SetSideWidth(ns.QuestLog.WIDTH)
		self:RegisterEvent("QUEST_LOG_UPDATE", function() panel.Refresh() end)
	end
	panel.Show(self, inst)
end

function Dungeons:HidePanel()
	if not panelUp then return end
	panelUp = false
	self:UnregisterEvent("QUEST_LOG_UPDATE")
	if ns.DungeonPanel then ns.DungeonPanel.Hide() end
	ns.QuestLog.Suspend(false)
end

function Dungeons.PanelUp() return panelUp end

---------------------------------------------------------------------------
-- Switching the engine
---------------------------------------------------------------------------
local function Apply(self, running)
	local function On(key) return running and self:IsOptionActive(key) or false end
	local db = ns.db
	local wasLevels = db.dungeonLevels
	db.pins.dungeon = On("dungeonPins")
	db.pins.raid = On("raidPins")
	db.dungeonLevels = On("levels")
	db.dungeonBosses = On("bosses")
	db.dungeonWays = On("ways")
	db.dungeonMaps = On("auto")
	ns.Pins.OnDungeonClick = running and function(wings, title) self:Click(wings, title) end or nil
	ns.Dungeon.ReturnView = running and Dungeons.ReturnView or nil
	-- (the level ranges are written into the icons' tooltips: those built again)
	if wasLevels ~= db.dungeonLevels then
		if ns.Map.IsShown() then ns.Pins.RebuildPlaces() else ns.Pins.InvalidatePlaces() end
	elseif ns.Map.IsShown() then
		ns.Pins.Ensure()
	end
	if ns.Map.IsShown() then
		ns.Dungeon.Update()
		ns.Dungeon.Refresh()
	end
	ns.Map.MarkDirty()
end

function Dungeons:Enable()
	self:RegisterMessage("DUNGEON_MAP_SHOWN", function(_, inst) self:ShowPanel(inst) end)
	self:RegisterMessage("DUNGEON_MAP_CLOSED", function()
		self:HidePanel()
		-- (the window closed with the dungeon's map: nothing to go back to next time)
		if not ns.Map.IsShown() then saved = nil end
	end)
	Apply(self, true)
	-- (a dungeon's map already up: its panel)
	local inst = ns.Dungeon.Current()
	if inst then self:ShowPanel(inst) end
end

function Dungeons:Disable()
	self:HidePanel()
	-- (a dungeon's map from an entrance: closed, the world as it was)
	local inst, _, _, opened = ns.Dungeon.Current()
	if inst and opened then ns.Dungeon.Back() end
	saved = nil
	Apply(self, false)
	if ns.Dungeon.HideChooser then ns.Dungeon.HideChooser() end
end

function Dungeons:Refresh()
	Apply(self, true)
	local inst = ns.Dungeon.Current()
	if inst then self:ShowPanel(inst) else self:HidePanel() end
end
