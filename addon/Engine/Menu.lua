-- The options panel: a flat panel over the map's top-right corner, its settings in tabs down its
-- left side (Map, Places, Townsfolk, Professions, Quests, Social), each page in two columns, every
-- row with its icon (the Map page's plain). Built the first time it opens; the last tab is remembered.
local _, FM = ...
local M = {}
FM.Menu = M

local S = FM.Style
local ICON = "Interface\\Icons\\"
local MEDIA = "Interface\\AddOns\\PerfectMap\\Media\\"
local TRACK = "Interface\\Minimap\\tracking\\"

local TAB_W = 128                 -- the tabs' column
local COL_W = 214                 -- each of a page's two columns
local GAP = 12
local ROW = 22
local PAD = 10

local panel, body                 -- body: what's inside the panel's frame (classic: inside Blizzard's border)
local rows = {}                   -- every switch, to refresh them all at once
local pages, tabs = {}, {}
local current

---------------------------------------------------------------------------
-- Building blocks: a page's two columns, each filled top down
---------------------------------------------------------------------------
local Column = {}
Column.__index = Column

-- (w: its width; a page with one column takes both columns' room, so its rows read whole)
local function NewColumn(page, x, w)
	return setmetatable({ page = page, x = x, y = -PAD, w = w or COL_W }, Column)
end

function Column:Section(text)
	if self.y < -PAD then self.y = self.y - 8 end
	local fs = S.Text(self.page, 11, S.ACCENT)
	fs:SetPoint("TOPLEFT", self.x + 2, self.y)
	fs:SetText(text:upper())
	local line = self.page:CreateTexture(nil, "ARTWORK")
	line:SetTexture(S.WHITE)
	line:SetVertexColor(1, 1, 1, 0.08)
	if S.classic then line:SetVertexColor(S.BORDER[1], S.BORDER[2], S.BORDER[3], 1) end   -- (classic: a gold rule)
	line:SetHeight(1)
	line:SetWidth(self.w)
	line:SetPoint("TOPLEFT", self.x, self.y - 15)
	self.y = self.y - 22
end

-- a switch: get / set its value; tip: the mouse-over text
function Column:Switch(label, icon, get, set, tip)
	local r = S.SwitchRow(self.page, label, icon, get, set, self.w)
	r:SetPoint("TOPLEFT", self.x, self.y)
	r.tip = tip
	rows[#rows + 1] = r
	self.y = self.y - ROW
	return r
end

-- a switch for one setting of FM.db; after: what to do once it changed
function Column:Option(label, icon, key, tip, after)
	return self:Switch(label, icon, function() return FM.db[key] end, function(v)
		FM.db[key] = v
		if after then after(v) end
	end, tip or label)
end

-- a switch for a kind of icon on the map (FM.Pins.CATS)
function Column:Pin(cat, label, tip, icon)
	return self:Switch(label or cat.label, icon or cat.icon,
		function() return FM.db.pins[cat.key] end,
		function(v) FM.Pins.SetShown(cat.key, v) end, tip)
end

function Column:Slider(label, icon, minV, maxV, step, get, set, fmt)
	local f = S.Slider(self.page, label, minV, maxV, step, get, set, fmt, self.w, icon)
	f:SetPoint("TOPLEFT", self.x, self.y - 2)
	self.y = self.y - 40
end

-- a row of small buttons: { label, onClick } ...
function Column:Buttons(list)
	local w = (self.w - 4 * (#list - 1)) / #list
	for i, b in ipairs(list) do
		local btn = S.Button(self.page, b[1], w, 18, b[2])
		btn:SetPoint("TOPLEFT", self.x + (i - 1) * (w + 4), self.y)
	end
	self.y = self.y - ROW - 2
end

local function Cats(group)
	local out = {}
	for _, cat in ipairs(FM.Pins.CATS) do if cat.group == group then out[#out + 1] = cat end end
	return out
end

local function SetAll(list, on)
	for _, cat in ipairs(list) do FM.db.pins[cat.key] = on end
	FM.Pins.Ensure()
	if FM.Quests then FM.Quests.OnToggle() end
	M.Refresh()
end

-- a long list of kinds, down two columns, with All / None over them
local function PinList(page, title, list)
	local a, b = NewColumn(page, 0), NewColumn(page, COL_W + GAP)
	a:Section(title)
	b:Section(" ")
	a:Buttons({ { "Show all", function() SetAll(list, true) end } })
	b:Buttons({ { "Hide all", function() SetAll(list, false) end } })
	local half = math.ceil(#list / 2)
	for i, cat in ipairs(list) do (i <= half and a or b):Pin(cat) end
	return math.min(a.y, b.y)
end

---------------------------------------------------------------------------
-- The pages
---------------------------------------------------------------------------
local BUILD = {}

function BUILD.map(page)
	local a, b = NewColumn(page, 0), NewColumn(page, COL_W + GAP)
	a:Section("Map")
	-- (the look: modern or classic; the new one shows after the reload it offers)
	a:Switch("Classic style", nil,
		function() return FM.db.style == "classic" end,
		function(v) FM.SetStyle(v and "classic" or "modern") end,
		{ "Classic style", "The map's windows and buttons as WoW Classic draws its own.",
			"Off: the modern look. The change shows fully after a reload, which it offers." })
	a:Option("Open with M", nil, "replaceM", { "Open with M",
		"M opens this map instead of Blizzard's. Outside combat, so do the map buttons, map pins in chat, quests' \"show on map\" and other addons." },
		FM.ApplyBindings)
	a:Switch("Centre on me when opened", nil,
		function() return FM.db.reopen == "player" end,
		function(v) FM.db.reopen = v and "player" or "last" end,
		{ "Centre on me when opened", "Off: it opens where you left it." })
	a:Option("Remember last zoom", nil, "rememberZoom", { "Remember last zoom",
		"The map opens at the zoom you closed it at.", "Off: it always opens at the same zoom." })
	a:Option("Highlight zone under cursor", nil, "hoverHighlight", { "Highlight zone under cursor",
		"The zone under the mouse lights up, as on Blizzard's continent map." }, function() FM.Map.MarkDirty() end)
	a:Option("Dungeon maps inside", nil, "dungeonMaps", { "Dungeon maps inside",
		"Inside a dungeon, raid or battleground the map shows its own map, every floor, you and your group on it.",
		"A right-click on it, or the header's World button, goes back to the world." }, function() FM.Dungeon.Update() end)
	a:Option("Bosses on dungeon maps", nil, "dungeonBosses", { "Bosses on dungeon maps",
		"Where each boss stands on a dungeon's map, with its portrait and level, as MapUtils shows them." },
		function() FM.Dungeon.Refresh() end)
	a:Option("Sum identical icons", nil, "joinIcons", { "Sum identical icons",
		"Identical icons that overlap show as one, with their count, every one of them in its tooltip, at every zoom.",
		"Off: every icon on its own." },
		function() FM.Map.MarkDirty() end)
	a:Option("Other addons' icons", nil, "addonPins", { "Other addons' icons",
		"Icons other addons put on Blizzard's map (GatherMate2, HandyNotes, TomTom and others) show on this one, exactly where they put them, with their own tooltips and clicks.",
		"They show two steps of the wheel closer than the townsfolk." }, function() FM.AddonPins.Refresh() end)
	a:Option("Fade while moving", nil, "fadeMoving", { "Fade while moving",
		"The map turns see-through while you move." })
	b:Section("Detail")
	b:Option("Caves up close", nil, "underground", { "Caves up close",
		"Zoom right in on a cave, mine, crypt or dungeon entrance and its own map surfaces: Blizzard's where it drew one, else the game's minimap of it inside." },
		function() FM.Map.MarkDirty() end)
	b:Option("Minimap terrain up close", nil, "minimapTerrain", { "Minimap terrain up close",
		"Zoomed right in, the ground turns into the minimap's own: trees, rocks, roads and buildings.",
		"The sea stays the map's." }, function() FM.Map.MarkDirty() end)
	b:Option("Fishing skill of zones", nil, "zoneFishing", { "Fishing skill of zones",
		"Under the zone's name: the fishing skill its waters want." }, function() FM.Map.ResetHover() end)
	b:Slider("Icon size", nil, 0.6, 1.6, 0.05,
		function() return FM.db.iconScale end,
		function(v) FM.db.iconScale = v FM.Pins.ApplyScale() end, "%.2f")
	return math.min(a.y, b.y)
end

function BUILD.places(page)
	local a, b = NewColumn(page, 0), NewColumn(page, COL_W + GAP)
	local P = FM.Pins
	a:Section("Places")
	for _, cat in ipairs(Cats("places")) do
		a:Pin(cat)
		if cat.key == "flight" then
			-- (the flight masters' own icon: they show in it, in red)
			local r = a:Option("Enemy flight masters", cat.icon, "enemyFlight", { "Enemy flight masters",
				"The other faction's flight masters too, in red." }, function() P.RebuildFlights() end)
			if r.icon then r.icon:SetVertexColor(P.ENEMY_TINT[1], P.ENEMY_TINT[2], P.ENEMY_TINT[3]) end
		end
	end
	b:Section("Boats & zeppelins")
	for _, cat in ipairs(Cats("transport")) do
		-- (harbors: yours in your faction's look, the other faction's in theirs)
		b:Pin(cat, nil, nil, cat.key == "boat" and P.FactionArt("harbor") or nil)
		if cat.key == "boat" then
			b:Option("Enemy harbors", P.EnemyArt("harbor"), "enemyHarbors", { "Enemy harbors",
				"The other faction's harbors too, with their boats' routes (their boats named in red in the tooltip)." },
				function() P.RebuildPlaces() end)
		end
	end
	b:Option("All routes", MEDIA .. "routes", "routes", { "All routes",
		"Every boat and zeppelin route at once: a thin line along the way it sails, Alliance boats blue, the rest red.",
		"Off: a harbor's or zeppelin tower's routes show with the cursor on it.",
		"Shown with their harbors' and towers' icons. Also the routes button in the map's tools, bottom left." }, function(v)
			if FM.Map.routesButton then FM.Map.routesButton:SetActive(v) end
			FM.Map.MarkDirty()
		end)
	b:Option("Live transport icons", P.FactionArt("boat"), "vessels", { "Live transport icons",
		"Each boat and zeppelin where it is right now, moving along its route.",
		"Known once someone has seen it sail: you aboard it, or someone sharing transports' locations." }, function() FM.Map.MarkDirty() end)
	return math.min(a.y, b.y)
end

function BUILD.townsfolk(page) return PinList(page, "Townsfolk", Cats("townsfolk")) end
function BUILD.professions(page) return PinList(page, "Profession trainers", Cats("professions")) end

function BUILD.quests(page)
	local a, b = NewColumn(page, 0), NewColumn(page, COL_W + GAP)
	local function QuestOption(label, icon, key, tip)
		a:Option(label, icon, key, tip, function() FM.Quests.OnToggle() end)
	end
	a:Section("On the map")
	QuestOption("Objectives & turn-ins", "Interface\\GossipFrame\\ActiveQuestIcon", "questPOI",
		{ "Objectives & turn-ins", "The quest log's quests, as Blizzard's map shows them." })
	QuestOption("Quests to pick up", "Interface\\GossipFrame\\AvailableQuestIcon", "questOffers",
		{ "Quests to pick up", "The quests you can take, as Blizzard's map shows them." })
	QuestOption("Quest areas", ICON .. "INV_Misc_Map_01", "questAreas",
		{ "Quest areas", "The blue area of the followed quest, and of the one under the mouse." })
	for _, cat in ipairs(Cats("quests")) do
		if not cat.external or _G.Questie then
			-- (with Questie's own logo)
			a:Pin(cat, nil, { cat.label, "Questie's quest, objective and turn-in icons, with its own tooltips." },
				_G.Questie and "Interface\\AddOns\\Questie\\Icons\\questie.png" or nil)
		end
	end
	b:Section("Quest log")
	b:Option("Replace Blizzard's quest log", "Interface\\QuestFrame\\UI-QuestLog-BookIcon", "replaceQuestLog",
		{ "Replace Blizzard's quest log", "L opens this map's quest log. Outside combat, so does clicking a quest in the objective tracker or its menu." },
		FM.ApplyBindings)
	b:Switch("Quest log beside the map", ICON .. "INV_Misc_Book_09",
		function() return FM.db.questPanel end,
		function(v) FM.QuestLog.SetShown(v) end,
		{ "Quest log beside the map", "Docked to the map's right: the window grows, the map keeps its shape." })
	return math.min(a.y, b.y)
end

function BUILD.social(page)
	local a = NewColumn(page, 0, COL_W * 2 + GAP)
	a:Section("Friends & guild")
	a:Option("Friends & guild on the map", "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon", "friends", { "Friends & guild on the map",
		"A class-coloured dot where each friend or guild member stands, for those who use PerfectMap or OpenMap and share where they are." },
		function() FM.Friends.Refresh() end)
	a:Option("Share where you are", ICON .. "INV_Letter_02", "friendsShare", { "Share where you are",
		"Your guild, and your friends who use PerfectMap or OpenMap, see you as a dot on their map (every 10 s while you move).",
		"Never from inside a dungeon, raid or battleground." }, function() FM.Friends.Refresh() end)
	a:Section("Boats & zeppelins")
	a:Option("Share transports location", ICON .. "INV_Letter_15", "vesselSync", { "Share transports location",
		"Trade where and when each boat and zeppelin was seen with other PerfectMap users (your guild, your group and your friends), for the live transport icons.",
		"/pmap sailings: what has been heard." }, function() FM.Vessels.SyncChanged() end)
	return a.y
end

local TABS = {
	{ key = "map", label = "Map", icon = ICON .. "INV_Misc_Map_01" },
	{ key = "places", label = "Places", icon = "Interface\\Minimap\\Dungeon" },
	{ key = "townsfolk", label = "Townsfolk", icon = TRACK .. "innkeeper" },
	{ key = "professions", label = "Professions", icon = "Interface\\GossipFrame\\TrainerGossipIcon", native = 16 },
	{ key = "quests", label = "Quests", icon = "Interface\\GossipFrame\\AvailableQuestIcon" },
	{ key = "social", label = "Social", icon = "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon" },
}

---------------------------------------------------------------------------
-- The panel and its tabs
---------------------------------------------------------------------------
local function Select(key)
	current = key
	FM.db.menuTab = key
	for k, page in pairs(pages) do page:SetShown(k == key) end
	for _, t in ipairs(tabs) do t:SetActive(t.key == key) end
end

-- A small picture drawn for its own pixels (the gossip book, 16 x 16): stretched to just any size it blurs.
-- Shown at a whole number of screen pixels for each of its own, as near the tabs' 16 as that comes,
-- worked out again each time the panel opens (the interface's scale may have changed)
local crisp = {}
local function Crisp(ic)
	local upp = (PixelUtil and PixelUtil.GetPixelToUIUnitFactor and PixelUtil.GetPixelToUIUnitFactor() or 1) / ic:GetEffectiveScale()
	local k = math.max(1, math.floor(16 / (ic.native * upp) + 0.5))
	local size = ic.native * k * upp
	ic:SetSize(size, size)
end

local function TabButton(spec, y)
	local b = S.Button(body, "", TAB_W - 8, 24, function() Select(spec.key) end, "row")
	b:SetPoint("TOPLEFT", 4, y)
	local ic = b:CreateTexture(nil, "ARTWORK")
	ic:SetSize(16, 16)
	ic:SetPoint("LEFT", 6, 0)
	S.SetIcon(ic, spec.icon)
	if spec.native then
		ic.native = spec.native
		ic:SetTexture(spec.icon, nil, nil, "NEAREST")
		if ic.SetSnapToPixelGrid then ic:SetSnapToPixelGrid(true) ic:SetTexelSnappingBias(0) end
		crisp[#crisp + 1] = ic
	end
	b.label:ClearAllPoints()
	b.label:SetPoint("LEFT", ic, "RIGHT", 7, 0)
	b.label:SetText(spec.label)
	b.key = spec.key
	return b
end

local function Build()
	-- classic: the map's own frame (Blizzard's window without a portrait, its title and close button), the
	-- pages in an inset as the map is; modern: a flat panel
	local blizz = false
	if S.classic then
		local ok, f = pcall(CreateFrame, "Frame", nil, PerfectMapFrame, "PortraitFrameTemplate")
		if ok and f then panel, blizz = f, true end
	end
	panel = panel or CreateFrame("Frame", nil, PerfectMapFrame)
	panel:SetFrameLevel(PerfectMapFrame:GetFrameLevel() + 40)
	panel:EnableMouse(true)
	panel:EnableMouseWheel(true)
	panel:SetScript("OnMouseWheel", function() end)
	if blizz then
		if panel.SetTitle then panel:SetTitle("Options")
		elseif panel.TitleText then panel.TitleText:SetText("Options") end
		if ButtonFrameTemplate_HidePortrait then pcall(ButtonFrameTemplate_HidePortrait, panel) end
		if panel.NineSlice and NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
			pcall(NineSliceUtil.ApplyLayoutByName, panel.NineSlice, "ButtonFrameTemplateNoPortrait")
		end
		local pc = panel.PortraitContainer or panel.portrait
		if pc then pc:Hide() end
		if panel.CloseButton then panel.CloseButton:SetScript("OnClick", function() M.Hide() end) end
	else
		S.Panel(panel, { 0.05, 0.055, 0.06, 0.97 }, nil, true)
	end
	panel:Hide()
	local E = blizz and S.FRAME or { l = 0, r = 0, t = 0, b = 0 }
	body = CreateFrame("Frame", nil, panel)
	body:SetPoint("TOPLEFT", E.l, -E.t)
	body:SetPoint("BOTTOMRIGHT", -E.r, E.b)
	-- (over the frame's own border and title bar)
	local top = panel:GetFrameLevel()
	for _, k in ipairs({ "NineSlice", "TitleContainer", "CloseButton" }) do
		local part = panel[k]
		if part and part.GetFrameLevel then top = math.max(top, part:GetFrameLevel()) end
	end
	body:SetFrameLevel(top + 1)

	-- the tabs, and the line between them and the pages
	local y = -PAD
	for _, spec in ipairs(TABS) do
		tabs[#tabs + 1] = TabButton(spec, y)
		y = y - 26
	end
	local tabsBottom = y
	if blizz then
		-- (the pages in Blizzard's inset, as the map's view is)
		local ok, inset = pcall(CreateFrame, "Frame", nil, body, "InsetFrameTemplate")
		if ok and inset then
			inset:SetPoint("TOPLEFT", TAB_W, -2)
			inset:SetPoint("BOTTOMRIGHT", 0, 24)
			inset:SetFrameLevel(body:GetFrameLevel())
		end
	else
		local sep = body:CreateTexture(nil, "ARTWORK")
		sep:SetTexture(S.WHITE)
		sep:SetVertexColor(1, 1, 1, 0.07)
		sep:SetWidth(1)
		sep:SetPoint("TOPLEFT", TAB_W, -6)
		sep:SetPoint("BOTTOMLEFT", TAB_W, 26)
	end

	-- the pages: as tall as the tallest
	local lowest = tabsBottom
	for _, spec in ipairs(TABS) do
		local page = CreateFrame("Frame", nil, body)
		page:SetFrameLevel(body:GetFrameLevel() + 2)
		page:SetPoint("TOPLEFT", TAB_W + GAP, 0)
		page:SetSize(COL_W * 2 + GAP, 10)
		pages[spec.key] = page
		lowest = math.min(lowest, BUILD[spec.key](page))
		page:Hide()
	end
	local h = -lowest + PAD + 22
	panel:SetSize(TAB_W + GAP + COL_W * 2 + GAP + PAD + E.l + E.r, h + E.t + E.b)
	for _, page in pairs(pages) do page:SetHeight(h - 22) end

	local foot = S.Text(body, 10, S.DIM)
	foot:SetPoint("BOTTOMLEFT", PAD, 8)
	foot:SetPoint("BOTTOMRIGHT", -PAD, 8)
	foot:SetJustifyH("LEFT")
	foot:SetWordWrap(false)
	foot:SetText("Drag: move   Wheel: zoom   Right-click: pin / coordinates (on an icon: waypoint)   /pmap help")

	Select(pages[FM.db.menuTab or ""] and FM.db.menuTab or "map")
end

function M.Toggle()
	if not panel then Build() end
	if panel:IsShown() then M.Hide() return end
	panel:ClearAllPoints()
	panel:SetPoint("TOPRIGHT", PerfectMapFrame, "TOPRIGHT", -6, -30)
	M.Refresh()
	panel:Show()
	for _, ic in ipairs(crisp) do Crisp(ic) end
	if FM.Map.optionsButton then FM.Map.optionsButton:SetActive(true) end
end

function M.Hide()
	if panel then panel:Hide() end
	if FM.Map.optionsButton then FM.Map.optionsButton:SetActive(false) end
end

function M.Refresh()
	if not panel then return end
	for _, r in ipairs(rows) do r:Refresh() end
end
