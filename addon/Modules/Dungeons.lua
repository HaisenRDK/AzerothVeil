-- AzerothVeil — Modules/Dungeons.lua
-- "Dungeons": the dungeons' and raids' entrances on the map, their interior maps (floors, bosses, ways in
-- and out), the map of the place you're in, and the side panel's Quests and Bosses tabs while a dungeon's
-- map is up. With DungeonJournal or NeedRoll (optional; the one picked in the Integrations module,
-- Modules/Integrations.lua), a click on an entrance opens its page of that dungeon instead: no second
-- interface besides it. So do Questie's data for the Quests tab (the Integrations module's option).
--
-- The maps are PerfectMap's (Engine/Dungeon.lua, Engine/Pins.lua); this module owns their settings and
-- writes the engine's switches (FM.db.pins.dungeon / raid, dungeonMaps, dungeonBosses, dungeonLevels,
-- dungeonWays), all false while it's off (Engine/Core.lua turns them off at each load, before it starts).
-- It also:
--   * routes the click on an entrance (Pins.OnDungeonClick): its map here, or the picked journal's page;
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
	description = L["The dungeons' and raids' entrances on the map; a click opens the dungeon's own map in the map's window, its floors, its bosses, its ways in, with its quests and bosses beside it. With DungeonJournal or NeedRoll, its page of the dungeon can open instead."],
	onText = L["the entrances, maps and tabs picked below are there; a dungeon's map is shown inside one if that option is on."],
	offText = L["no entrance icon, no dungeon map, no tab: nothing of it shows or runs."],
	order = 30,
	icon = DungeonIcon,
	settings = {
		{ type = "header", label = L["Display"] },
		{ key = "entrances", iconMenu = true, icon = DungeonIcon, type = "toggle", default = true,
			label = L["Show the entrances"],
			tooltip = L["An icon where each dungeon or raid is entered."] },
		{ key = "dungeonPins", iconMenu = true, icon = DungeonIcon, type = "toggle", default = true, parent = "entrances",
			label = L["Dungeons"], tooltip = L["The dungeons' entrances."] },
		{ key = "raidPins", iconMenu = true, icon = RaidIcon, type = "toggle", default = true, parent = "entrances",
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
			label = L["The dungeon's quests"],
			tooltip = L["While a dungeon's map is up, in the panel beside it: its quests first (those of your log; with Questie's data, all of them), their progress and rewards."] },
		{ key = "bossesTab", icon = BOSS_ICON, type = "toggle", default = true,
			label = L["The dungeon's bosses"],
			tooltip = L["While a dungeon's map is up, in the panel beside it: its bosses after its quests; a click opens a boss's page, its loot, and shows where it stands."] },
	},
})

---------------------------------------------------------------------------
-- DungeonJournal or NeedRoll: in charge of the entrances' clicks while it's there and picked
---------------------------------------------------------------------------
-- the picked journal (Integrations/*.lua: Available, KeysFor, Open, Label), if it's there; else nil (the
-- Integrations module's option, Modules/Integrations.lua: read at each click)
function Dungeons:Journal()
	local I = ns.Modules:Get("integrations")
	return I and I.Journal() or nil
end

function Dungeons:UsesJournal() return self:Journal() ~= nil end

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
	local J = self:Journal()
	if J then
		-- (its dungeons for these wings; a wing it doesn't have, a raid: AzerothVeil's own map)
		local entries = {}
		for _, w in ipairs(wings) do
			local keys = J.KeysFor(w)
			if #keys == 0 then
				if self:IsOptionActive("maps") then entries[#entries + 1] = w end
			else
				for _, key in ipairs(keys) do
					entries[#entries + 1] = { id = w.id, name = w.name, label = #keys > 1 and (J.Label(key) or key) or w.label, raid = w.raid,
						lo = w.lo, hi = w.hi, key = key }
				end
			end
		end
		local function Pick(e)
			if e.key and J.Open(e.key) then return end
			if self:IsOptionActive("maps") then OpenHere(e) end     -- (the journal failed, or said no: ours)
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
function Dungeons.LogQuestsFor(inst)
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
				local complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(q) and true or false
				local failed = C_QuestLog.IsFailed and C_QuestLog.IsFailed(q) and true or false
				out[#out + 1] = {
					questID = q, title = info.title, level = info.level, complete = complete, failed = failed,
					status = failed and "failed" or complete and "complete" or "active", inLog = true,
					objectives = objectives,
				}
			end
		end
	end
	return out
end

local STATUS_ORDER = { complete = 1, active = 2, failed = 3, available = 4, locked = 5, done = 6 }

-- The dungeon's quests for the Quests tab: with "Use Questie's data" (the Integrations module's) and Questie there, every quest Questie
-- files under the dungeon for your faction, each quest of your log taking its own entry's place (its
-- progress and rewards); else the quests of your log. Second result: "questie" or "log". nil while
-- Questie's quests are being read (onReady once they are).
function Dungeons.QuestsFor(inst, onReady)
	local log = Dungeons.LogQuestsFor(inst)
	local Qz = ns.Questie
	local MM = ns.Modules
	if not (MM:IsOptionActive("integrations", "questieDungeons") and Qz and Qz.Available()) then return log, "log" end
	local list = Qz.QuestsFor(inst, onReady, not MM:IsOptionActive("integrations", "questieOnlyMine"))
	if list == nil then return nil, "questie" end
	local mine = {}
	for _, q in ipairs(log) do mine[q.questID] = q end
	local out = {}
	for _, q in ipairs(list) do
		local l = mine[q.questID]
		if l then
			l.giver, l.reqLevel, l.faction, l.classes, l.text = q.giver, q.reqLevel, q.faction, q.classes, q.text
			out[#out + 1] = l
			mine[q.questID] = nil
		else
			out[#out + 1] = q
		end
	end
	for _, q in ipairs(log) do if mine[q.questID] then out[#out + 1] = q end end
	table.sort(out, function(a, b)
		local sa, sb = STATUS_ORDER[a.status] or 9, STATUS_ORDER[b.status] or 9
		if sa ~= sb then return sa < sb end
		if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
		return (a.title or "") < (b.title or "")
	end)
	return out, "questie"
end

-- a quest shown on the world map where it starts (its giver): the dungeon's map put away, the map on that
-- spot, a marker there (the quest's name, its giver) until it's clicked or another takes its place
function Dungeons.ShowQuest(q)
	local giver = q and q.giver
	if not (giver and giver.uiMap and giver.x) then return end
	if ns.Dungeon.Current() then ns.Dungeon.Back() end
	if ns.Map.SetMark then
		ns.Map.SetMark(giver.uiMap, giver.x, giver.y, q.title, giver.name and L["Given by %s"]:format(giver.name))
	end
	ns.Map.Glide(ns.Map.ShowSpot, giver.uiMap, giver.x, giver.y)
	ns.Map.MarkDirty()
end

-- the dungeon's entrance on the world map (the panel's entrance icon): its map put away, the world on you, then a
-- glide from you to its entrance (out a little and back in when it's far: Map.Glide). You not on the world map
-- (inside it): straight on its entrance
local ENTRANCE_ACROSS = 140            -- (how much of the world is across the view: the engine's on a way in)
function Dungeons.ShowEntrance(inst)
	if not ns.Pins.InstanceUnits then return end
	local u, v = ns.Pins.InstanceUnits(inst)      -- (both values: "a and f()" would keep only the first)
	if not (u and v) then return end
	saved = nil                         -- (to its entrance, not back to where it was opened from)
	if ns.Dungeon.Current() then ns.Dungeon.Back() end
	ns.Map.CenterOnPlayer(ENTRANCE_ACROSS)
	ns.Map.Glide(ns.Map.SetView, u, v, ENTRANCE_ACROSS)
	ns.Map.MarkDirty()
end

-- The dungeon's bosses as its map shows them, floor by floor (Dungeon.CollectBosses):
-- { { name, level, levelText, displayID, kind, floor } }; floor nil: on no map
function Dungeons.BossesFor(inst)
	local out = {}
	for _, e in ipairs(ns.Dungeon.CollectBosses(inst) or {}) do
		local b = e.boss
		if b and b[1] then
			out[#out + 1] = { name = (b[1]:gsub("%s*<[^>]*>", "")), key = b[1], level = b[2] or nil,
				levelText = b[5], displayID = b[3], kind = b[4], floor = e.floor, aliases = b[6] }
		end
	end
	return out
end

-- (a name as Engine/Data/DropRates.lua keys them: lower case, letters and digits only, no leading "the")
local function RateKey(name)
	if type(name) ~= "string" then return nil end
	return (name:gsub("%s*<[^>]*>", ""):lower():gsub("^the%s+", ""):gsub("[^%w]", ""))
end

-- An item's drop rate from a boss (0..1; Engine/Data/DropRates.lua, NeedRoll's): the boss's own, by its name or
-- one of its other names, else the item's single rate wherever it drops; nil when none is known
function Dungeons.DropRate(names, itemID)
	local R = ns.DROP_RATES
	if not (R and itemID) then return nil end
	for _, n in ipairs(names) do
		local t = R.byBoss[RateKey(n) or ""]
		if t and t[itemID] then return t[itemID] end
	end
	return R.byItem[itemID]
end

-- A boss's loot: DungeonJournal's list (read only) when it's installed; nil when it isn't, false when it
-- has nothing for that boss. AzerothVeil's own data has no loot: nothing is made up. (AzerothVeil: each item with
-- its drop rate when one is known: it.rate)
function Dungeons.BossLoot(inst, wingName, boss)
	if not DJ.NS() then return nil end
	local names = { boss.key, boss.name }
	for _, a in ipairs(boss.aliases or {}) do names[#names + 1] = a end
	local loot = DJ.BossLoot(inst, wingName, names)
	if not loot then return false end
	for _, it in ipairs(loot) do it.rate = Dungeons.DropRate(names, it.itemID) end
	return loot
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
		-- (an item's name and quality arriving from the server: the loot list drawn again)
		self:RegisterEvent("GET_ITEM_INFO_RECEIVED", function() panel.Refresh() end)
	end
	panel.Show(self, inst)
end

function Dungeons:HidePanel()
	if not panelUp then return end
	panelUp = false
	self:UnregisterEvent("QUEST_LOG_UPDATE")
	self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
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
	-- (a click on a boss on the dungeon's map: its page in the panel, while the panel is there)
	ns.Dungeon.OnBossClick = running and function(name)
		if panelUp and ns.DungeonPanel then ns.DungeonPanel.OpenBoss(name) end
	end or nil
	-- (a right-click on the dungeon's map: the panel back to the dungeon's page first, while it's on another)
	ns.Dungeon.OnBack = running and function() return ns.DungeonPanel and ns.DungeonPanel.Back() or false end or nil
	-- (the passages between floors: DungeonJournal's, where it's installed and the maps are the game's)
	ns.Dungeon.FloorLinks = On("ways") and DJ.FloorLinks or nil
	-- (the bosses no map places: in the Bosses tab, not over the map, while that tab is there)
	ns.Dungeon.BossListInPanel = running and function() return self:TabsWanted() and self:IsOptionActive("bossesTab") end or nil
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
	-- (the Integrations module's Questie options changed, or it turned on or off: the Quests tab drawn again)
	local function Integrations(_, name)
		if name == "integrations" and panelUp and ns.DungeonPanel then ns.DungeonPanel.Refresh() end
	end
	self:RegisterMessage("MODULE_SETTING_CHANGED", Integrations)
	self:RegisterMessage("MODULE_ENABLED_CHANGED", Integrations)
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
	if ns.Map.ClearMark then ns.Map.ClearMark() end
	Apply(self, false)
	if ns.Dungeon.HideChooser then ns.Dungeon.HideChooser() end
end

function Dungeons:Refresh()
	Apply(self, true)
	local inst = ns.Dungeon.Current()
	if inst then self:ShowPanel(inst) else self:HidePanel() end
end
