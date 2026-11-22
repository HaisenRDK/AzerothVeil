-- AzerothVeil, based on PerfectMap (by sokenn_, GPL-3.0): a seamless, lightweight world map for WoW Forever.
-- Core: settings, events, the M key, slash commands. Nothing here runs per frame.
-- AzerothVeil changes: the namespace is published by Core/Init.lua (_G.AzerothVeil); the settings live in
-- AzerothVeilDB.engine (Core/Database.lua); the classic (Blizzard) look only; /av; module start-up signalled.
local ADDON, FM = ...
local L = FM.L

FM.W, FM.H = 1002, 668            -- Azeroth (947) art size: the map's world units
FM.WORLD = 947
FM.VERSION = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version") or "dev"

FM.defaults = {
	style = "classic",               -- AzerothVeil: Blizzard's own look only (the modern one is not offered)
	window = { mapW = 960 },         -- the map's width (its height follows: 3:2); left / top once moved
	replaceM = true,                 -- M opens PerfectMap, and so does everything that would open Blizzard's
	rememberZoom = true,             -- open at the zoom it was last closed at (else at M's own)
	reopen = "player",               -- "player": centre on you at each opening; "last": where you left it
	fadeMoving = false,              -- fade the window while you move
	zoneFishing = false,             -- the zone's fishing skill under its name
	dungeonMaps = true,
	dungeonBosses = true,            -- ... with their bosses on them (MapUtils' pins)              -- inside a dungeon, raid or battleground: its own map
	underground = true,              -- caves, mines and dungeon entrances surfacing up close (Caves.lua)
	minimapTerrain = true,           -- up close, the terrain as the minimap draws it
	hoverHighlight = true,           -- light up the zone under the cursor (Blizzard's highlight art)
	routes = false,                  -- every boat and zeppelin route (off: each shows over its dock's icon)
	fadeAlpha = 0.35,
	iconScale = 1,
	-- quests as Blizzard's map shows them: their buttons, the "!" of quests to pick up, their areas
	questPOI = true, questOffers = true, questAreas = true,
	pins = {
		flight = true, dungeon = true, raid = true, capital = true, boat = true, zeppelin = true, tram = true,
		airship = false,               -- (Zephras Isle's airships: off until picked)
		questie = true,                -- Questie's own map icons too, when Questie is installed
		innkeeper = true, banker = true, auctioneer = true, classTrainer = true, portalTrainer = false,
		repair = false, weaponMaster = false, stable = false, battlemaster = true, spirit = true,
		barber = true, transmogrifier = true,
		mailbox = true, food = false, drink = false, reagents = false, tradeGoods = false,
		bags = false, potions = false, ammo = false, poisons = false,
		-- (profession trainers, prof_<PROFESSION>: off until picked)
	},
	joinIcons = true,                -- identical icons that overlap: one, with their count, at every zoom (off: each on its own)
	addonPins = true,                -- other addons' icons (HereBeDragons-Pins), on this map too (AddonPins.lua)
	gatherPins = true,               -- ... of them, the gathering addons' (GatherMate2, Gatherer...): the tools' leaf button
	vessels = true,                  -- boats and zeppelins where they are now
	-- (AzerothVeil: friends / friendsShare / shareAsked are the "Friends & guild" module's settings now:
	-- Modules/Social.lua; Core/Database.lua moves the old values there)
	vesselSync = true,               -- ... sharing when they were seen with other PerfectMap users
	enemyFlight = false,             -- the other faction's flight masters
	enemyHarbors = false,            -- the other faction's harbors (and their boats' routes)
	replaceQuestLog = true,          -- L, and every "show this quest", open this map's quest log
	questLog = true,                 -- AzerothVeil: the quest log docked beside the map is there at all (the Quests module)
	questPanel = true,               -- the quest log docked beside the map (out or folded away)
	questSearch = true,              -- AzerothVeil: the log's search box (the Quests module's)
	questCount = true,               -- AzerothVeil: ... its count of quests, under it
	questFoldAll = true,             -- AzerothVeil: ... its Collapse all / Expand all button, at the count's end
	questZoneCount = true,           -- AzerothVeil: ... a folded zone's quests tracked / in the log, after its name
	npcUnexplored = true,            -- AzerothVeil: the townsfolk of land not explored yet too (the Map module's)
	terrainNames = true,             -- AzerothVeil: the places' names over the minimap's terrain up close (the Map module's)
	allClassTrainers = false,        -- AzerothVeil: every class's trainers, not only yours (the Icons module's)
}

-- (AzerothVeil: the icon kinds the Transports module owns)
FM.TRANSPORT_PINS = { "boat", "zeppelin", "airship", "tram", "flight" }
-- (AzerothVeil: and the Dungeons module's)
FM.DUNGEON_PINS_KEYS = { "dungeon", "raid" }
-- (AzerothVeil: and the Quests module's switches)
FM.QUEST_KEYS = { "questPOI", "questOffers", "questAreas", "questLog", "replaceQuestLog",
	"questSearch", "questCount", "questFoldAll", "questZoneCount" }
-- (AzerothVeil: and the Map module's switches, as they are while it's off: Modules/Map.lua)
FM.MAP_OFF = {
	replaceM = false, reopen = "last", rememberZoom = false, fadeMoving = false, hoverHighlight = false,
	joinIcons = false, addonPins = false, iconScale = 1, underground = false, minimapTerrain = false, zoneFishing = false,
	npcUnexplored = true, terrainNames = false,
}
-- (AzerothVeil: and the Icons module's kinds of icon: those of these groups of Pins.CATS, Modules/Icons.lua)
FM.ICON_GROUPS = { places = true, townsfolk = true, professions = true }

local function Merge(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			Merge(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end

function FM.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cffe0b050AzerothVeil|r " .. tostring(msg))
end

-- a value this client may hand out as secret (12.x engine): never compute with those
local issecret = _G.issecretvalue
function FM.Plain(v)
	if v == nil or (issecret and issecret(v)) then return nil end
	return v
end

---------------------------------------------------------------------------
-- The M key: an override binding on whatever key opens the world map, set out of combat.
---------------------------------------------------------------------------
-- (a key binding clicks on press, release or both depending on ActionButtonUseKeyDown: act on the
-- press, or on a release that came without one)
local function KeyButton(name, action)
	local b = CreateFrame("Button", name, UIParent)
	b:RegisterForClicks("AnyDown", "AnyUp")
	local pressed = false
	b:SetScript("OnClick", function(_, _, down)
		if down then
			pressed = true
			action()
		elseif pressed then
			pressed = false
		else
			action()
		end
	end)
end
KeyButton("AzerothVeilToggleButton", function() FM.Toggle() end)
KeyButton("AzerothVeilQuestLogButton", function() if FM.QuestLog then FM.QuestLog.ToggleKey() end end)
local bindOwner = CreateFrame("Frame")
local pendingBind = false

function FM.ApplyBindings()
	if InCombatLockdown() then pendingBind = true return end
	pendingBind = false
	ClearOverrideBindings(bindOwner)
	if not FM.db then return end
	local function Bind(action, button)
		for _, key in ipairs({ GetBindingKey(action) }) do
			SetOverrideBindingClick(bindOwner, false, key, button)
		end
	end
	if FM.db.replaceM then Bind("TOGGLEWORLDMAP", "AzerothVeilToggleButton") end
	if FM.db.replaceQuestLog then Bind("TOGGLEQUESTLOG", "AzerothVeilQuestLogButton") end
	if FM.Takeover then FM.Takeover.Apply() end      -- (Blizzard's map and log stopped, or not, by the same options)
end

function FM.Toggle()
	if not FM.Map then return end
	FM.Map.Toggle()
end
_G.AzerothVeil_Toggle = FM.Toggle
BINDING_HEADER_AZEROTHVEIL = "AzerothVeil"
BINDING_NAME_AZEROTHVEIL_TOGGLE = (FM.L and FM.L["Toggle AzerothVeil"]) or "Toggle AzerothVeil"

---------------------------------------------------------------------------
-- The look: modern or classic (Style.lua). Asked once, at the first start; changed in Options. Whatever's
-- been drawn already keeps the look it was drawn in, so a change then takes a reload: asked for, and done
-- with a click
---------------------------------------------------------------------------
-- (our own little dialog, drawn as the game's: never the game's StaticPopup. Its dialogs are shared by
-- the whole game, and an addon showing one, or touching their table, leaves them running as that addon's:
-- the game's own protected ones then fail (Quit, entering or leaving a battleground, releasing the spirit))
local dialog
local function Dialog(text, b1, b2, on1, on2)
	if not dialog then
		local f = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
		f:SetFrameStrata("DIALOG")
		f:SetToplevel(true)
		f:SetClampedToScreen(true)
		f:EnableMouse(true)
		f:SetWidth(360)
		f:SetPoint("TOP", UIParent, "TOP", 0, -135)
		if f.SetBackdrop then
			f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
				edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
				insets = { left = 11, right = 12, top = 12, bottom = 11 } })
		end
		f.text = FM.Style.FontString(f, "ARTWORK", "GameFontHighlight")
		f.text:SetWidth(320)
		f.text:SetPoint("TOP", 0, -18)
		f.text:SetJustifyH("CENTER")
		f.buttons = {}
		for i = 1, 2 do
			local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
			FM.Style.FrizButton(b)   -- (AzerothVeil: Friz Quadrata)
			b:SetSize(128, 21)
			b:SetScript("OnClick", function()
				f:Hide()
				if f.on[i] then f.on[i]() end
			end)
			f.buttons[i] = b
		end
		f.buttons[1]:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 16)
		f.buttons[2]:SetPoint("BOTTOMLEFT", f, "BOTTOM", 6, 16)
		dialog = f
	end
	dialog.text:SetText(text)
	dialog.buttons[1]:SetText(b1)
	dialog.buttons[2]:SetText(b2)
	dialog.on = { on1, on2 }
	dialog:SetHeight(dialog.text:GetStringHeight() + 18 + 16 + 21 + 20)
	dialog:Show()
end
function FM.AskStyle()
	Dialog("|cffe0b050Perfect|rMap\n\nWhich look would you like for the map?\n\n"
		.. "|cffffffffModern|r: flat and dark, with a touch of gold.\n|cffffffffClassic|r: WoW Classic's own windows and buttons.\n\n"
		.. "You can change it any time in the map's options.",
		"Modern", "Classic", function() FM.SetStyle("modern") end, function() FM.SetStyle("classic") end)
end
-- the look chosen: kept; drawn at once if nothing is drawn yet, else after the reload it asks for
function FM.SetStyle(style)
	FM.db.style = style
	local S = FM.Style
	if style == S.Theme() then return end
	if S.used then
		Dialog("|cffe0b050Perfect|rMap\n\nThe new look shows fully after the interface is reloaded.", "Reload now", "Later", ReloadUI)
	else
		S.ApplyTheme(style)
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("UPDATE_BINDINGS")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event, arg)
	if event == "ADDON_LOADED" and arg == ADDON then
		-- (AzerothVeil: one SavedVariables table, its engine part PerfectMap's own settings, as they were)
		local root = FM.Database.Load()
		local db = root.engine
		-- (older settings: boats, zeppelins and the tram were one switch; the icon size's 1.10 is 1.00 now)
		if db.pins and db.pins.transport ~= nil then
			for _, k in ipairs({ "boat", "zeppelin", "tram" }) do db.pins[k] = db.pins.transport end
			db.pins.transport = nil
		end
		if db.iconScale and not db.iconScale2 then
			db.iconScale = math.floor(db.iconScale / 1.1 / 0.05 + 0.5) * 0.05
		end
		db.iconScale2 = true
		-- (1.5: the routes show over their docks' icons; all of them only if asked again)
		if not db.routesHover then db.routes = nil db.routesHover = true end
		-- (the other faction's harbors: off for everyone once, whatever a test left them at)
		if not db.enemyHarborsOff then db.enemyHarbors = nil db.enemyHarborsOff = true end
		root.engine = Merge(db, FM.defaults)
		FM.db = root.engine
		-- (AzerothVeil: these switches belong to the Transports module (Modules/Transports.lua): its own
		-- settings are kept in AzerothVeilDB.modules.transports; here they're only what it writes while it
		-- runs. Off until it starts, so nothing of it shows while it's disabled)
		for _, k in ipairs(FM.TRANSPORT_PINS) do FM.db.pins[k] = false end
		FM.db.routes, FM.db.vessels, FM.db.vesselSync, FM.db.enemyHarbors = false, false, false, false
		FM.db.enemyFlight = false
		for _, k in ipairs(FM.DUNGEON_PINS_KEYS) do FM.db.pins[k] = false end
		FM.db.dungeonMaps, FM.db.dungeonBosses, FM.db.dungeonLevels, FM.db.dungeonWays = false, false, false, false
		for _, k in ipairs(FM.QUEST_KEYS) do FM.db[k] = false end
		FM.db.pins.questie = false
		for k, v in pairs(FM.MAP_OFF) do FM.db[k] = v end
		for _, c in ipairs(FM.Pins.CATS) do if FM.ICON_GROUPS[c.group] then FM.db.pins[c.key] = false end end
		FM.db.allClassTrainers = false
		FM.db.pins.marker = false                 -- (AzerothVeil: the Markers module's, Modules/Markers.lua)
		-- (AzerothVeil: the classic look, always: Blizzard's own frames, never the modern one)
		FM.db.style = "classic"
		FM.Style.ApplyTheme(FM.db.style)
		ev:UnregisterEvent("ADDON_LOADED")
		-- (the settings are there: the modules can be set up, Core/Bootstrap.lua)
		FM.Callbacks:Fire("SETTINGS_LOADED")
	elseif event == "PLAYER_LOGIN" then
		FM.ApplyBindings()
	elseif event == "UPDATE_BINDINGS" then
		FM.ApplyBindings()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pendingBind then FM.ApplyBindings() end
	end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_AZEROTHVEIL1, SLASH_AZEROTHVEIL2 = "/av", "/azerothveil"
SlashCmdList.AZEROTHVEIL = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "config" or msg == "options" then
		if FM.Options then FM.Options.Open() end
	elseif msg:match("^module") then
		if FM.Modules then FM.Modules:SlashCommand(msg:match("^modules?%s*(.*)$")) end
	elseif msg == "stats" then
		if FM.Map then FM.Map.PrintStats() end
	elseif msg == "reset" then
		FM.db.window = { mapW = FM.defaults.window.mapW }
		if FM.Map then FM.Map.ApplyWindow() end
		FM.Print(L["window reset"])
	elseif msg:match("^sailings") then
		if FM.Vessels then FM.Vessels.Status(msg:match("^sailings%s+(%a+)")) end
	elseif msg == "markers" then
		if FM.MarkersUI then FM.MarkersUI.OpenList() end          -- (AzerothVeil: the Markers module's list)
	elseif msg == "addons" then
		if FM.AddonPins then FM.AddonPins.Report() end
	elseif msg == "find" then
		if FM.Map then FM.Map.Show() FM.Map.CenterOnPlayer() end
	elseif msg == "help" then
		FM.Print(L["/av - open/close  |  /av config - settings & modules  |  /av modules [enable|disable <name>] - modules  |  /av stats - performance  |  /av reset - window position  |  /av find - centre on you  |  /av sailings [log|test] - boats & zeppelins shared  |  /av addons - other addons' icons  |  /av markers - map markers"])
	else
		FM.Toggle()
	end
end

