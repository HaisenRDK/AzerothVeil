-- The options panel: a flat panel over the map's top-right corner, its settings in tabs down its
-- left side (AzerothVeil: one per module, the Map module's first), each page in two columns, every
-- row with its icon (the Map page's plain). Built the first time it opens; the last tab is remembered.
local _, FM = ...
local L = FM.L
local M = {}
FM.Menu = M

local S = FM.Style

local TAB_W = 156                 -- the tabs' column (AzerothVeil: wider, as the whole window)
local COL_W = 262                 -- each of a page's two columns
local GAP = 12
local ROW = 22
local PAD = 10
local VIEW_H = 600                -- AzerothVeil: the pages' height at most; a taller page scrolls (Blizzard's bar)
local BAR_W = 22                  -- (the scroll bar, right of the pages)

local panel, body                 -- body: what's inside the panel's frame (classic: inside Blizzard's border)
local rows = {}                   -- every switch, to refresh them all at once
local pages, tabs = {}, {}
local current

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
		-- (AzerothVeil: Blizzard's check box greyed as the game greys its own, else see-through)
		if self.SetGreyed and self.check then self:SetGreyed(not on) else self:SetAlpha(on and 1 or 0.4) end
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


local function ModuleHeader(page, m, y, width)
	local hb = Box(page, 0.9)
	hb:SetPoint("TOPLEFT", 0, y)
	hb:SetWidth(width)
	local icon = hb:CreateTexture(nil, "ARTWORK")
	icon:SetSize(36, 36)
	icon:SetPoint("TOPLEFT", 12, -12)
	S.SetIcon(icon, IconOf(m.icon) or "Interface\\Icons\\INV_Misc_Gear_01")
	local title = S.FontString(hb, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -1)
	title:SetText(m.title)
	local check = CreateFrame("CheckButton", nil, hb, "UICheckButtonTemplate")
	check:SetSize(28, 28)
	check:SetPoint("LEFT", title, "RIGHT", 6, 0)
	check:SetScript("OnClick", function(self) MM:SetEnabled(m.name, self:GetChecked()) M.Refresh() end)
	check:SetScript("OnEnter", function(self)
		local title, lines = MM:SwitchTooltip(m.name)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(title or L["Enable this module"], 1, 0.82, 0)
		for _, l in ipairs(lines) do GameTooltip:AddLine(l[1], l[2], l[3], l[4], true) end
		GameTooltip:Show()
	end)
	check:SetScript("OnLeave", GameTooltip_Hide)
	local desc = S.FontString(hb, "ARTWORK", "GameFontHighlightSmall")
	desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	desc:SetWidth(width - 12 - 36 - 10 - 14)
	desc:SetJustifyH("LEFT")
	desc:SetSpacing(2)
	desc:SetTextColor(0.75, 0.75, 0.75)
	desc:SetText(m.description or "")
	local state = S.FontString(hb, "ARTWORK", "GameFontHighlightSmall")
	state:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -6)
	state:SetWidth(width - 12 - 36 - 10 - 14)
	state:SetJustifyH("LEFT")
	-- (no "active / disabled" line: the check box says it. Only why it doesn't run, for a module that may
	-- not: an addon or a module it needs, an addon that takes its place)
	local mayFail = MM:CanBeUnavailable(m.name)
	local h = 12 + 1 + title:GetStringHeight() + 6 + desc:GetStringHeight() + (mayFail and (6 + 14) or 0) + 12
	hb:SetHeight(math.max(64, h))
	rows[#rows + 1] = { Refresh = function()
		check:SetChecked(MM:IsEnabled(m.name))
		local st, reason = MM:State(m.name)
		if mayFail and st == "unavailable" then
			state:SetText(L["Not running"] .. (reason and (": " .. reason) or ""))
			state:SetTextColor(1, 0.55, 0.3)
		else
			state:SetText("")
		end
	end }
	return y - hb:GetHeight() - 10
end

-- a section's box: its title, a rule, then its options two by two (a child option indented in its cell)
local function ModuleSection(page, m, label, specs, y, width, header)
	local sb = Box(page, 0.55)
	sb:SetPoint("TOPLEFT", 0, y)
	sb:SetWidth(width)
	local t = S.FontString(sb, "ARTWORK", "GameFontNormal")
	t:SetPoint("TOPLEFT", 12, -10)
	t:SetText(label)
	-- (AzerothVeil: a header declared with all = true: "Show all" / "Hide all" on its right, Blizzard's buttons)
	if header and header.all then
		local buttons = {}
		for i, b in ipairs({ { L["Hide all"], false }, { L["Show all"], true } }) do
			local btn = CreateFrame("Button", nil, sb, "UIPanelButtonTemplate")
			S.FrizButton(btn)   -- (AzerothVeil: Friz Quadrata)
			btn:SetSize(100, 20)
			btn:SetPoint("TOPRIGHT", -10 - (i - 1) * 104, -5)
			btn:SetText(b[1])
			btn:SetScript("OnClick", function() MM:SetSection(m.name, header, b[2]) M.Refresh() end)
			buttons[i] = btn
		end
		rows[#rows + 1] = { Refresh = function()
			for _, btn in ipairs(buttons) do btn:SetEnabled(MM:IsEnabled(m.name)) end
		end }
	end
	local rule = sb:CreateTexture(nil, "ARTWORK")
	rule:SetColorTexture(0.78, 0.62, 0.36, 0.35)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", 10, -28)
	rule:SetPoint("TOPRIGHT", -10, -28)
	-- (an option and the ones hanging from it are one group, never split: each child right under its
	-- parent. The groups go down the left column, then the right, in their order, the two about as tall)
	local cellW = (width - 20 - 12) / 2
	local top = -34
	local groups = MM:OptionGroups(m.name, specs)
	local function Height(g)
		local n = 0
		for _, spec in ipairs(g) do n = n + (spec.type == "range" and 2 or 1) end
		return n
	end
	local total = 0
	for _, g in ipairs(groups) do total = total + Height(g) end
	local half = math.ceil(total / 2)
	local used = { 0, 0 }
	local col = 1
	for _, g in ipairs(groups) do
		local h = Height(g)
		if col == 1 and used[1] > 0 and used[1] + h > half then col = 2 end
		for _, spec in ipairs(g) do
			local x = 10 + (col - 1) * (cellW + 12)
			local yy = top - used[col] * ROW
			if spec.type == "toggle" then
				local d = Depth(m, spec)
				local r = S.SwitchRow(sb, spec.label or spec.key, IconOf(spec.icon),
					function() return MM:GetSetting(m.name, spec.key) end,
					function(v) MM:SetSetting(m.name, spec.key, v) M.Refresh() end, cellW - d * INDENT)
				r:SetPoint("TOPLEFT", x + d * INDENT, yy)
				r.tip = { spec.label, spec.tooltip }
				rows[#rows + 1] = Greyable(r, function() return MM:IsOptionEditable(m.name, spec.key) end)
				used[col] = used[col] + 1
			elseif spec.type == "select" then
				-- (AzerothVeil: a choice among a few, Style.Select)
				local d = Depth(m, spec)
				local r = S.Select(sb, spec.label or spec.key, spec.values or {},
					function() return MM:GetSetting(m.name, spec.key) end,
					function(v) MM:SetSetting(m.name, spec.key, v) M.Refresh() end, cellW - d * INDENT, IconOf(spec.icon))
				r:SetPoint("TOPLEFT", x + d * INDENT, yy)
				r.tip = { spec.label, spec.tooltip }
				rows[#rows + 1] = Greyable(r, function() return MM:IsOptionEditable(m.name, spec.key) end)
				used[col] = used[col] + 1
			elseif spec.type == "range" then
				local f = S.Slider(sb, spec.label or spec.key, spec.min or 0, spec.max or 1, spec.step or 0.05,
					function() return MM:GetSetting(m.name, spec.key) end,
					function(v) MM:SetSetting(m.name, spec.key, v) end, spec.fmt, cellW, IconOf(spec.icon))
				f:SetPoint("TOPLEFT", x, yy - 2)
				used[col] = used[col] + 2
			end
		end
	end
	sb:SetHeight(34 + math.max(used[1], used[2]) * ROW + 10)
	return y - sb:GetHeight() - 8
end

local function ModulePage(page, m)
	local width = COL_W * 2 + GAP
	local y = ModuleHeader(page, m, 0, width)
	-- (its settings cut into sections at each header; the first ones, before any, under "Settings")
	local sections, current = {}, nil
	for _, spec in ipairs(m.settings) do
		if spec.type == "header" then
			current = { label = spec.label or "", specs = {}, header = spec }
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
		if #sec.specs > 0 then y = ModuleSection(page, m, sec.label, sec.specs, y, width, sec.header) end
	end
	return y
end

---------------------------------------------------------------------------
-- The pages
---------------------------------------------------------------------------
local BUILD = {}

-- (AzerothVeil: the engine's own tabs (Map, Places, Townsfolk, Professions, Quests) are the modules' now:
-- Map, Icons, Quests. Each module's tab is built from its declaration: ModulePage)
local TABS = {}

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
			local spec = { key = key, label = m.title, icon = IconOf(m.icon) or "Interface\\Icons\\INV_Misc_Gear_01" }
			-- (the Map module's tab first, where the engine's own Map tab was)
			if m.name == "map" then table.insert(TABS, 1, spec) else TABS[#TABS + 1] = spec end
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

	-- the pages: as tall as the tallest, up to VIEW_H; AzerothVeil: each in a scroll frame of its own (Style.Scroll,
	-- Blizzard's bar), its bar shown only where the page is taller than the view
	local lowest = tabsBottom
	for _, spec in ipairs(TABS) do
		local sf = S.Scroll(body)
		sf:SetFrameLevel(body:GetFrameLevel() + 2)
		if sf.bar then sf.bar:SetFrameLevel(body:GetFrameLevel() + 3) end
		sf:SetPoint("TOPLEFT", TAB_W + GAP, -1)
		local page = CreateFrame("Frame", nil, sf)
		page:SetSize(COL_W * 2 + GAP, 10)
		sf:SetScrollChild(page)
		pages[spec.key] = sf
		local bottom = BUILD[spec.key](page)
		page:SetHeight(math.max(1, -bottom))
		lowest = math.min(lowest, bottom)
		sf:Hide()
	end
	local viewH = math.min(-lowest, VIEW_H)
	local h = viewH + PAD + 22
	panel:SetSize(TAB_W + GAP + COL_W * 2 + GAP + BAR_W + PAD + E.l + E.r, h + E.t + E.b)
	for _, sf in pairs(pages) do
		sf:SetSize(COL_W * 2 + GAP, viewH)
	end

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
	-- (AzerothVeil: reload the interface, in the title bar, left of the close button: Blizzard's own button)
	local reload = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	S.FrizButton(reload)   -- (AzerothVeil: Friz Quadrata)
	reload:SetSize(96, 18)
	if panel.CloseButton then
		reload:SetPoint("RIGHT", panel.CloseButton, "LEFT", -2, 0)
	else
		reload:SetPoint("TOPRIGHT", -30, -2)
	end
	reload:SetFrameLevel(top + 5)
	reload:SetText(L["Reload"])
	reload:SetScript("OnClick", function() ReloadUI() end)
	reload:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(L["Reload the interface"], 1, 0.82, 0)
		GameTooltip:AddLine(L["As /reload: the addons are loaded again, the settings saved."], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	reload:SetScript("OnLeave", GameTooltip_Hide)
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

	if FM.db.menuTab == "quests" then FM.db.menuTab = "module_quests" end    -- (AzerothVeil: its options, a module's now)
	if FM.db.menuTab == "map" then FM.db.menuTab = "module_map" end          -- (AzerothVeil: and the map's)
	if FM.db.menuTab == "places" or FM.db.menuTab == "townsfolk" or FM.db.menuTab == "professions" then
		FM.db.menuTab = "module_icons"                                        -- (AzerothVeil: and the icons')
	end
	Select(pages[FM.db.menuTab or ""] and FM.db.menuTab or (TABS[1] and TABS[1].key))
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

-- AzerothVeil's options: opened (on that tab, if given: "module_<name>")
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
