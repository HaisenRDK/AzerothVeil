-- The options panel: a flat panel over the map's top-right corner, its settings in tabs down its
-- left side (Map, Places, Townsfolk, Professions, Quests, Social), each page in two columns, every
-- row with its icon (the Map page's plain). Built the first time it opens; the last tab is remembered.
local _, FM = ...
local L = FM.L
local M = {}
FM.Menu = M

local S = FM.Style
local ICON = "Interface\\Icons\\"
local MEDIA = "Interface\\AddOns\\AzerothVeil\\Media\\"
local TRACK = "Interface\\Minimap\\tracking\\"

local TAB_W = 156                 -- the tabs' column (AzerothVeil: wider, as the whole window)
local COL_W = 262                 -- each of a page's two columns
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

---------------------------------------------------------------------------
-- AzerothVeil: a module's options, from its declaration (Core/ModuleManager.lua: settings = { ... }),
-- read and written only through the module manager: the same settings as AzerothVeil's own window and the
-- game's Options page (UI/Options.lua), every screen refreshed on its messages. Greyed out (and not
-- clickable) while the module, or the option it hangs from, is off; their saved values kept.
---------------------------------------------------------------------------
local MM = FM.Modules
local INDENT = 14

local function IconOf(x) if type(x) == "function" then return x() end return x end

-- a switch row, greyed out and not clickable while editable() is false
local function Greyable(r, editable)
	local base = r.Refresh
	function r:Refresh()
		base(self)
		local on = editable()
		self:SetEnabled(on)
		self:SetAlpha(on and 1 or 0.4)
	end
	r:Refresh()
	return r
end

local function Depth(m, spec)
	local d, x = 0, spec
	while x and x.parent do d = d + 1 x = m.settingByKey[x.parent] end
	return d
end

-- A module's page, as FlareUI lays its own out (drawn here with the game's pieces): a header box with
-- the module's icon, its title and, right beside it, its on/off check box, what it does and its state;
-- then a box for each section of its settings (each "header" of its declaration starts one), its
-- options in two columns. Greyed out (and not clickable) while the module or the option they hang from
-- is off, their saved values kept.
local BOX_BG = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark"
local BOX_EDGE = "Interface\\Tooltips\\UI-Tooltip-Border"
local function Box(parent, alpha)
	local f = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	if f.SetBackdrop then
		f:SetBackdrop({ bgFile = BOX_BG, edgeFile = BOX_EDGE, tile = true, tileSize = 16, edgeSize = 14,
			insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		f:SetBackdropColor(1, 1, 1, alpha)
		f:SetBackdropBorderColor(0.78, 0.62, 0.36, 0.9)
	end
	return f
end

local STATE_COLOR = { active = { 0.4, 0.9, 0.4 }, disabled = { 0.6, 0.6, 0.6 }, unavailable = { 1, 0.55, 0.3 } }

local function ModuleHeader(page, m, y, width)
	local hb = Box(page, 0.9)
	hb:SetPoint("TOPLEFT", 0, y)
	hb:SetWidth(width)
	local icon = hb:CreateTexture(nil, "ARTWORK")
	icon:SetSize(36, 36)
	icon:SetPoint("TOPLEFT", 12, -12)
	S.SetIcon(icon, IconOf(m.icon) or "Interface\\Icons\\INV_Misc_Gear_01")
	local title = hb:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -1)
	title:SetText(m.title)
	local check = CreateFrame("CheckButton", nil, hb, "UICheckButtonTemplate")
	check:SetSize(28, 28)
	check:SetPoint("LEFT", title, "RIGHT", 6, 0)
	check:SetScript("OnClick", function(self) MM:SetEnabled(m.name, self:GetChecked()) M.Refresh() end)
	check:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(L["Enable this module"], 1, 0.82, 0)
		GameTooltip:Show()
	end)
	check:SetScript("OnLeave", GameTooltip_Hide)
	local desc = hb:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	desc:SetWidth(width - 12 - 36 - 10 - 14)
	desc:SetJustifyH("LEFT")
	desc:SetSpacing(2)
	desc:SetTextColor(0.75, 0.75, 0.75)
	desc:SetText(m.description or "")
	local state = hb:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	state:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -6)
	state:SetWidth(width - 12 - 36 - 10 - 14)
	state:SetJustifyH("LEFT")
	local h = 12 + 1 + title:GetStringHeight() + 6 + desc:GetStringHeight() + 6 + 14 + 12
	hb:SetHeight(math.max(64, h))
	rows[#rows + 1] = { Refresh = function()
		check:SetChecked(MM:IsEnabled(m.name))
		local st, reason = MM:State(m.name)
		local c = STATE_COLOR[st] or STATE_COLOR.disabled
		state:SetText(st == "active" and L["Active"] or st == "disabled" and L["Disabled: its settings are kept."]
			or (L["Not running"] .. (reason and (": " .. reason) or "")))
		state:SetTextColor(c[1], c[2], c[3])
	end }
	return y - hb:GetHeight() - 10
end

-- a section's box: its title, a rule, then its options two by two (a child option indented in its cell)
local function ModuleSection(page, m, label, specs, y, width)
	local sb = Box(page, 0.55)
	sb:SetPoint("TOPLEFT", 0, y)
	sb:SetWidth(width)
	local t = sb:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	t:SetPoint("TOPLEFT", 12, -10)
	t:SetText(label)
	local rule = sb:CreateTexture(nil, "ARTWORK")
	rule:SetColorTexture(0.78, 0.62, 0.36, 0.35)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", 10, -28)
	rule:SetPoint("TOPRIGHT", -10, -28)
	local cellW = (width - 20 - 12) / 2
	local slot, top = 0, -34
	for _, spec in ipairs(specs) do
		if spec.type == "toggle" then
			local col, row = slot % 2, math.floor(slot / 2)
			local d = Depth(m, spec)
			local r = S.SwitchRow(sb, spec.label or spec.key, IconOf(spec.icon),
				function() return MM:GetSetting(m.name, spec.key) end,
				function(v) MM:SetSetting(m.name, spec.key, v) M.Refresh() end, cellW - d * INDENT)
			r:SetPoint("TOPLEFT", 10 + col * (cellW + 12) + d * INDENT, top - row * ROW)
			r.tip = { spec.label, spec.tooltip }
			rows[#rows + 1] = Greyable(r, function() return MM:IsOptionEditable(m.name, spec.key) end)
			slot = slot + 1
		elseif spec.type == "range" then
			if slot % 2 == 1 then slot = slot + 1 end           -- (a slider: a line of its own)
			local f = S.Slider(sb, spec.label or spec.key, spec.min or 0, spec.max or 1, spec.step or 0.05,
				function() return MM:GetSetting(m.name, spec.key) end,
				function(v) MM:SetSetting(m.name, spec.key, v) end, spec.fmt, cellW, IconOf(spec.icon))
			f:SetPoint("TOPLEFT", 10, top - math.floor(slot / 2) * ROW - 2)
			slot = slot + 4
		end
	end
	local nRows = math.ceil(slot / 2)
	sb:SetHeight(34 + nRows * ROW + 10)
	return y - sb:GetHeight() - 8
end

local function ModulePage(page, m)
	local width = COL_W * 2 + GAP
	local y = ModuleHeader(page, m, 0, width)
	-- (its settings cut into sections at each header; the first ones, before any, under "Settings")
	local sections, current = {}, nil
	for _, spec in ipairs(m.settings) do
		if spec.type == "header" then
			current = { label = spec.label or "", specs = {} }
			sections[#sections + 1] = current
		elseif spec.type == "toggle" or spec.type == "range" then
			if not current then
				current = { label = L["Settings"], specs = {} }
				sections[#sections + 1] = current
			end
			current.specs[#current.specs + 1] = spec
		end
	end
	for _, sec in ipairs(sections) do
		if #sec.specs > 0 then y = ModuleSection(page, m, sec.label, sec.specs, y, width) end
	end
	return y
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
	a:Buttons({ { L["Show all"], function() SetAll(list, true) end } })
	b:Buttons({ { L["Hide all"], function() SetAll(list, false) end } })
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
	a:Section(L["Map"])
	-- (AzerothVeil: no "Classic style" switch: Blizzard's classic look is the only one)
	a:Option(L["Open with M"], nil, "replaceM", { L["Open with M"],
		L["M opens this map instead of Blizzard's. Outside combat, so do the map buttons, map pins in chat, quests' \"show on map\" and other addons."] },
		FM.ApplyBindings)
	a:Switch(L["Centre on me when opened"], nil,
		function() return FM.db.reopen == "player" end,
		function(v) FM.db.reopen = v and "player" or "last" end,
		{ L["Centre on me when opened"], L["Off: it opens where you left it."] })
	-- (AzerothVeil: the minimap button, UI/MinimapButton.lua)
	if FM.MinimapButton then
		a:Switch(L["Minimap button"], FM.MEDIA .. "icon",
			function() return FM.MinimapButton.IsShown() end,
			function(v) FM.MinimapButton.SetShown(v) end,
			{ L["Minimap button"], L["Left-click: open or close the map"] .. "\n" .. L["Right-click: options"] })
	end
	a:Option(L["Remember last zoom"], nil, "rememberZoom", { L["Remember last zoom"],
		L["The map opens at the zoom you closed it at."], L["Off: it always opens at the same zoom."] })
	a:Option(L["Highlight zone under cursor"], nil, "hoverHighlight", { L["Highlight zone under cursor"],
		L["The zone under the mouse lights up, as on Blizzard's continent map."] }, function() FM.Map.MarkDirty() end)
	a:Option(L["Dungeon maps inside"], nil, "dungeonMaps", { L["Dungeon maps inside"],
		L["Inside a dungeon, raid or battleground the map shows its own map, every floor, you and your group on it."],
		L["A right-click on it, or the header's World button, goes back to the world."] }, function() FM.Dungeon.Update() end)
	a:Option(L["Bosses on dungeon maps"], nil, "dungeonBosses", { L["Bosses on dungeon maps"],
		L["Where each boss stands on a dungeon's map, with its portrait and level, as MapUtils shows them."] },
		function() FM.Dungeon.Refresh() end)
	a:Option(L["Sum identical icons"], nil, "joinIcons", { L["Sum identical icons"],
		L["Identical icons that overlap show as one, with their count, every one of them in its tooltip, at every zoom."],
		L["Off: every icon on its own."] },
		function() FM.Map.MarkDirty() end)
	a:Option(L["Other addons' icons"], nil, "addonPins", { L["Other addons' icons"],
		L["Icons other addons put on Blizzard's map (GatherMate2, HandyNotes, TomTom and others) show on this one, exactly where they put them, with their own tooltips and clicks."],
		L["They show two steps of the wheel closer than the townsfolk."] }, function() FM.AddonPins.Refresh() end)
	a:Option(L["Fade while moving"], nil, "fadeMoving", { L["Fade while moving"],
		L["The map turns see-through while you move."] })
	b:Section(L["Detail"])
	b:Option(L["Caves up close"], nil, "underground", { L["Caves up close"],
		L["Zoom right in on a cave, mine, crypt or dungeon entrance and its own map surfaces: Blizzard's where it drew one, else the game's minimap of it inside."] },
		function() FM.Map.MarkDirty() end)
	b:Option(L["Minimap terrain up close"], nil, "minimapTerrain", { L["Minimap terrain up close"],
		L["Zoomed right in, the ground turns into the minimap's own: trees, rocks, roads and buildings."],
		L["The sea stays the map's."] }, function() FM.Map.MarkDirty() end)
	b:Option(L["Fishing skill of zones"], nil, "zoneFishing", { L["Fishing skill of zones"],
		L["Under the zone's name: the fishing skill its waters want."] }, function() FM.Map.ResetHover() end)
	b:Slider(L["Icon size"], nil, 0.6, 1.6, 0.05,
		function() return FM.db.iconScale end,
		function(v) FM.db.iconScale = v FM.Pins.ApplyScale() end, "%.2f")
	return math.min(a.y, b.y)
end

function BUILD.places(page)
	local a, b = NewColumn(page, 0), NewColumn(page, COL_W + GAP)
	local P = FM.Pins
	a:Section(L["Places"])
	for _, cat in ipairs(Cats("places")) do
		a:Pin(cat)
	end
	-- (AzerothVeil: boats, zeppelins, the tram and their routes: the Transports module's own tab)
	return math.min(a.y, b.y)
end

function BUILD.townsfolk(page) return PinList(page, L["Townsfolk"], Cats("townsfolk")) end
function BUILD.professions(page) return PinList(page, L["Profession trainers"], Cats("professions")) end

function BUILD.quests(page)
	local a, b = NewColumn(page, 0), NewColumn(page, COL_W + GAP)
	local function QuestOption(label, icon, key, tip)
		a:Option(label, icon, key, tip, function() FM.Quests.OnToggle() end)
	end
	a:Section(L["On the map"])
	QuestOption(L["Objectives & turn-ins"], "Interface\\GossipFrame\\ActiveQuestIcon", "questPOI",
		{ L["Objectives & turn-ins"], L["The quest log's quests, as Blizzard's map shows them."] })
	QuestOption(L["Quests to pick up"], "Interface\\GossipFrame\\AvailableQuestIcon", "questOffers",
		{ L["Quests to pick up"], L["The quests you can take, as Blizzard's map shows them."] })
	QuestOption(L["Quest areas"], ICON .. "INV_Misc_Map_01", "questAreas",
		{ L["Quest areas"], L["The blue area of the followed quest, and of the one under the mouse."] })
	for _, cat in ipairs(Cats("quests")) do
		if not cat.external or _G.Questie then
			-- (with Questie's own logo)
			a:Pin(cat, nil, { cat.label, L["Questie's quest, objective and turn-in icons, with its own tooltips."] },
				_G.Questie and "Interface\\AddOns\\Questie\\Icons\\questie.png" or nil)
		end
	end
	b:Section(L["Quest log"])
	b:Option(L["Replace Blizzard's quest log"], "Interface\\QuestFrame\\UI-QuestLog-BookIcon", "replaceQuestLog",
		{ L["Replace Blizzard's quest log"], L["L opens this map's quest log. Outside combat, so does clicking a quest in the objective tracker or its menu."] },
		FM.ApplyBindings)
	b:Switch(L["Quest log beside the map"], ICON .. "INV_Misc_Book_09",
		function() return FM.db.questPanel end,
		function(v) FM.QuestLog.SetShown(v) end,
		{ L["Quest log beside the map"], L["Docked to the map's right: the window grows, the map keeps its shape."] })
	return math.min(a.y, b.y)
end


local TABS = {
	{ key = "map", label = L["Map"], icon = ICON .. "INV_Misc_Map_01" },
	{ key = "places", label = L["Places"], icon = "Interface\\Minimap\\Dungeon" },
	{ key = "townsfolk", label = L["Townsfolk"], icon = TRACK .. "innkeeper" },
	{ key = "professions", label = L["Professions"], icon = "Interface\\GossipFrame\\TrainerGossipIcon", native = 16 },
	{ key = "quests", label = L["Quests"], icon = "Interface\\GossipFrame\\AvailableQuestIcon" },
}
-- (AzerothVeil: then a tab for each module, its options built from its declaration: ModulePage)

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
	-- (AzerothVeil: a window of its own, AzerothVeil's options screen, no longer hung on the map: moved by
	-- its title bar, resized by its corner grip, kept on screen, where and how big it was left remembered,
	-- closed by its button or Escape; opened by the map's gear, /av config and the minimap button)
	if S.classic then
		local ok, f = pcall(CreateFrame, "Frame", "AzerothVeilOptions", UIParent, "PortraitFrameTemplate")
		if ok and f then panel, blizz = f, true end
	end
	panel = panel or CreateFrame("Frame", "AzerothVeilOptions", UIParent)
	panel:SetFrameStrata("DIALOG")
	panel:SetToplevel(true)
	panel:SetClampedToScreen(true)
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:EnableMouseWheel(true)
	panel:SetScript("OnMouseWheel", function() end)
	if blizz then
		local title = "AzerothVeil  |cff9a9a9a" .. L["Options"] .. "|r"
		if panel.SetTitle then panel:SetTitle(title)
		elseif panel.TitleText then panel.TitleText:SetText(title) end
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

	-- (AzerothVeil: the modules' tabs after the map's own)
	if MM then
		for _, m in ipairs(MM:Sorted()) do
			local key = "module_" .. m.name
			TABS[#TABS + 1] = { key = key, label = m.title, icon = IconOf(m.icon) or "Interface\\Icons\\INV_Misc_Gear_01" }
			BUILD[key] = function(page) return ModulePage(page, m) end
		end
	end
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
	foot:SetText(L["Drag: move   Wheel: zoom   Right-click: pin / coordinates (on an icon: waypoint)   /av help"])

	-- (AzerothVeil: moved by the title bar, over the frame's own parts, clear of the close button)
	local bar = CreateFrame("Frame", nil, panel)
	bar:SetPoint("TOPLEFT", 8, 0)
	bar:SetPoint("TOPRIGHT", -30, 0)
	bar:SetHeight(22)
	bar:SetFrameLevel(top + 3)
	if panel.CloseButton then panel.CloseButton:SetFrameLevel(top + 4) end
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function() panel:StartMoving() end)
	bar:SetScript("OnDragStop", function() panel:StopMovingOrSizing() M.SavePlace() end)
	-- (... and resized by the corner grip: the whole window and its contents, kept in proportion, its
	-- top-left corner staying where it is)
	local grip = CreateFrame("Button", nil, panel)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -4, 4)
	grip:SetFrameLevel(top + 5)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	local sizing
	grip:SetScript("OnMouseDown", function()
		local x = GetCursorPosition()
		local es = panel:GetEffectiveScale()
		sizing = { x = x, scale = panel:GetScale(), width = panel:GetWidth() * es,
			left = panel:GetLeft() * es, top = panel:GetTop() * es }
		grip:SetScript("OnUpdate", function()
			local cx = GetCursorPosition()
			local k = (sizing.width + (cx - sizing.x)) / sizing.width
			local scale = math.min(M.MAX_SCALE, math.max(M.MIN_SCALE, sizing.scale * k))
			panel:SetScale(scale)
			local e = panel:GetEffectiveScale()
			panel:ClearAllPoints()
			panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", sizing.left / e, sizing.top / e)
		end)
	end)
	grip:SetScript("OnMouseUp", function()
		grip:SetScript("OnUpdate", nil)
		sizing = nil
		FM.db.menuWindow = FM.db.menuWindow or {}
		FM.db.menuWindow.scale = panel:GetScale()
		M.SavePlace()
	end)
	panel:SetScale(FM.db.menuWindow and tonumber(FM.db.menuWindow.scale) or 1)
	FM.TakeEscape(panel, function() M.Hide() end)

	Select(pages[FM.db.menuTab or ""] and FM.db.menuTab or "map")
end

M.MIN_SCALE, M.MAX_SCALE = 0.75, 1.6

-- (where it was left: its top-left corner, kept with its size)
function M.SavePlace()
	if not (panel and panel:GetLeft()) then return end
	local w = FM.db.menuWindow or {}
	FM.db.menuWindow = w
	w.left, w.top = panel:GetLeft(), panel:GetTop()
	panel:ClearAllPoints()
	panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", w.left, w.top)
end

local function Place()
	local w = FM.db.menuWindow
	panel:ClearAllPoints()
	if w and tonumber(w.left) and tonumber(w.top) then
		panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", w.left, w.top)
	elseif FM.Map.IsShown() and AzerothVeilFrame then
		-- (never moved yet: over the map's top-right corner, as PerfectMap showed it)
		panel:SetPoint("TOPRIGHT", AzerothVeilFrame, "TOPRIGHT", -6, -30)
	else
		panel:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	end
end

-- AzerothVeil's options: opened (on that tab, if given: "map", "places"... or "module_<name>")
function M.Open(tab)
	if not panel then Build() end
	if tab and pages[tab] then Select(tab) end
	if panel:IsShown() then panel:Raise() M.Refresh() return end
	Place()
	M.Refresh()
	panel:Show()
	for _, ic in ipairs(crisp) do Crisp(ic) end
	if FM.Map.optionsButton then FM.Map.optionsButton:SetActive(true) end
end

function M.IsShown() return panel and panel:IsShown() or false end

function M.Toggle()
	if panel and panel:IsShown() then M.Hide() return end
	M.Open()
end

function M.Hide()
	if panel then panel:Hide() end
	if FM.Map.optionsButton then FM.Map.optionsButton:SetActive(false) end
end

function M.Refresh()
	if not panel then return end
	for _, r in ipairs(rows) do r:Refresh() end
end

-- (AzerothVeil: a module or one of its settings changed anywhere (AzerothVeil's window, the game's Options
-- page, /av modules, the map's tools): shown here at once)
for _, message in ipairs({ "MODULE_STATE_CHANGED", "MODULE_SETTING_CHANGED", "MODULE_ENABLED_CHANGED" }) do
	FM.Callbacks:Register(message, "menu", function() M.Refresh() end)
end
