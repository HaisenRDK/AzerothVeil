-- AzerothVeil — UI/Options.lua
-- The central options: AzerothVeil's own window, drawn as Blizzard's classic windows are (its metal frame,
-- title bar and close button: PortraitFrameTemplate without its portrait, as the map's window; inset panels,
-- check boxes, buttons and fonts of the game). /av config, the map's gear menu, or the button on its page
-- in the game's Options > AddOns > AzerothVeil open it.
--   * moved by its title bar, kept on screen, where it was left remembered (AzerothVeilDB.core.optionsWindow);
--   * left: the modules, each in its state's colour (active / disabled / unavailable);
--   * right: the module picked. Every module gets the same header, drawn here once for all of them: its
--     title, and on the same line, its "Enable" check box; under it what it does, its state, then its
--     settings, built from its declaration (UI/Controls.lua), greyed out with their saved values while
--     it's off.
-- No setting is kept here: everything goes through the module manager. Built the first time it opens;
-- nothing runs while it's closed.
local _, ns = ...
local L = ns.L
local MM = ns.Modules
local Controls = ns.Controls

local Options = {}
ns.Options = Options

local WIN_W, WIN_H = 780, 620
local LIST_W = 200
local ROW_H = 22
local PAD = 14
local EDGE = { l = 7, r = 7, t = 27, b = 7 }   -- (inside the classic frame: as the map's, Style.FRAME)

local win, category
local listButtons = {}
local pages = {}              -- module name -> its settings frame
local selected
local head                    -- the right side's parts

local COLORS = {
	active = { 0.25, 1, 0.25 },
	disabled = { 0.6, 0.6, 0.6 },
	unavailable = { 1, 0.5, 0.25 },
}

local function Inset(parent)
	local ok, f = pcall(CreateFrame, "Frame", nil, parent, "InsetFrameTemplate")
	if ok and f then return f end
	return CreateFrame("Frame", nil, parent)
end

local function Core()
	local root = ns.Database.Root()
	return root and root.core or {}
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
local function RefreshRight()
	local m = selected and MM:Get(selected)
	if not m then return end
	head.title:SetText(m.title)
	head.desc:SetText(m.description or "")
	head.enable:SetChecked(MM:IsEnabled(m.name))
	local state, reason = MM:State(m.name)
	local c = COLORS[state] or COLORS.disabled
	local text = (state == "active" and L["Active"])
		or (state == "disabled" and L["Disabled: its settings are kept and come back when it's enabled."])
		or (L["Not running"] .. (reason and (": " .. reason) or ""))
	head.state:SetText(text)
	head.state:SetTextColor(c[1], c[2], c[3])
	head.reload:SetShown(m.needsReload and true or false)
	local page = pages[m.name]
	if not page then
		page = CreateFrame("Frame", nil, head.settings)
		page:SetPoint("TOPLEFT")
		page:SetPoint("TOPRIGHT")
		local height
		page.rows, height = Controls.BuildSettings(page, m, function() Options.Refresh() end)
		page:SetHeight(math.max(1, height))
		if #page.rows == 0 then
			local fs = page:CreateFontString(nil, "ARTWORK", "GameFontDisable")
			fs:SetPoint("TOPLEFT")
			fs:SetText(L["This module has no settings."])
		end
		pages[m.name] = page
	end
	for name, p in pairs(pages) do p:SetShown(name == m.name) end
	for _, row in ipairs(page.rows) do row.Refresh() end
end

local function RefreshList()
	for _, b in ipairs(listButtons) do
		local c = COLORS[MM:State(b.moduleName)] or COLORS.disabled
		b.text:SetTextColor(c[1], c[2], c[3])
		b.selectedTex:SetShown(b.moduleName == selected)
	end
end

function Options.Refresh()
	if not (win and win:IsShown()) then return end
	RefreshList()
	RefreshRight()
end

local function Select(name)
	selected = name
	Core().optionsModule = name
	Options.Refresh()
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local function SavePosition()
	local left, top = win:GetLeft(), win:GetTop()
	if not left then return end
	Core().optionsWindow = { left = left, top = top }
	win:ClearAllPoints()
	win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

local function PlaceWindow()
	local pos = Core().optionsWindow
	win:ClearAllPoints()
	if type(pos) == "table" and tonumber(pos.left) and tonumber(pos.top) then
		win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.left, pos.top)
	else
		win:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	end
end

-- Escape closes it, heard as the map's window hears it (Engine/Map.lua): never through the game's
-- UISpecialFrames (taint). Out of combat the key is kept from the game; in combat it closes and goes on.
local function TakeEscape(f)
	f:EnableKeyboard(true)
	if not InCombatLockdown() then f:SetPropagateKeyboardInput(true) end
	f:SetScript("OnKeyDown", function(self, key)
		if InCombatLockdown() then
			if key == "ESCAPE" then self:Hide() end
			return
		end
		if key == "ESCAPE" then
			self:SetPropagateKeyboardInput(false)
			self:Hide()
			C_Timer.After(0, function() if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end end)
		else
			self:SetPropagateKeyboardInput(true)
		end
	end)
end

local function Build()
	local blizz = false
	local ok, f = pcall(CreateFrame, "Frame", "AzerothVeilOptionsWindow", UIParent, "PortraitFrameTemplate")
	if ok and f then
		win, blizz = f, true
	else
		win = CreateFrame("Frame", "AzerothVeilOptionsWindow", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
		if win.SetBackdrop then
			win:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
				edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
				insets = { left = 11, right = 12, top = 12, bottom = 11 } })
		end
	end
	win:Hide()
	win:SetSize(WIN_W, WIN_H)
	win:SetFrameStrata("DIALOG")
	win:SetToplevel(true)
	win:SetClampedToScreen(true)
	win:SetMovable(true)
	win:EnableMouse(true)
	local title = ns.TITLE .. "  |cff9a9a9a" .. (ns.VERSION or "") .. "|r"
	if blizz then
		-- (Blizzard's frame without its portrait, its corner closed as its own windows without one are)
		if ButtonFrameTemplate_HidePortrait then pcall(ButtonFrameTemplate_HidePortrait, win) end
		if win.NineSlice and NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
			pcall(NineSliceUtil.ApplyLayoutByName, win.NineSlice, "ButtonFrameTemplateNoPortrait")
		end
		local pc = win.PortraitContainer or win.portrait
		if pc then pc:Hide() end
		if win.SetTitle then win:SetTitle(title) elseif win.TitleText then win.TitleText:SetText(title) end
	else
		local t = win:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		t:SetPoint("TOP", 0, -8)
		t:SetText(title)
	end
	local close = win.CloseButton
	if not close then
		close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", 0, 0)
	end
	close:SetScript("OnClick", function() win:Hide() end)

	-- the title bar: drag to move (clear of the close button, over the frame's own parts)
	local bar = CreateFrame("Frame", nil, win)
	bar:SetPoint("TOPLEFT", 8, 0)
	bar:SetPoint("TOPRIGHT", -30, 0)
	bar:SetHeight(22)
	local level = win:GetFrameLevel()
	for _, k in ipairs({ "NineSlice", "TitleContainer", "CloseButton" }) do
		local part = win[k]
		if part and part.GetFrameLevel then level = math.max(level, part:GetFrameLevel()) end
	end
	bar:SetFrameLevel(level + 2)
	close:SetFrameLevel(level + 3)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function() win:StartMoving() end)
	bar:SetScript("OnDragStop", function() win:StopMovingOrSizing() SavePosition() end)

	-- the modules
	local list = Inset(win)
	list:SetPoint("TOPLEFT", EDGE.l + 2, -(EDGE.t + 4))
	list:SetPoint("BOTTOMLEFT", EDGE.l + 2, EDGE.b + 2)
	list:SetWidth(LIST_W)
	local listHead = list:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	listHead:SetPoint("TOPLEFT", 10, -10)
	listHead:SetText(L["Modules"])
	local y = -32
	for _, m in ipairs(MM:Sorted()) do
		local b = CreateFrame("Button", nil, list)
		b:SetPoint("TOPLEFT", 4, y)
		b:SetPoint("TOPRIGHT", -4, y)
		b:SetHeight(ROW_H)
		b.moduleName = m.name
		b.text = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		b.text:SetPoint("LEFT", 8, 0)
		b.text:SetPoint("RIGHT", -4, 0)
		b.text:SetJustifyH("LEFT")
		b.text:SetText(m.title)
		b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		b.selectedTex = b:CreateTexture(nil, "BACKGROUND")
		b.selectedTex:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
		b.selectedTex:SetBlendMode("ADD")
		b.selectedTex:SetVertexColor(1, 0.82, 0, 0.6)
		b.selectedTex:SetAllPoints()
		b.selectedTex:Hide()
		b:SetScript("OnClick", function(self) Select(self.moduleName) end)
		listButtons[#listButtons + 1] = b
		y = y - ROW_H
	end
	local foot = list:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	foot:SetPoint("BOTTOMLEFT", 10, 10)
	foot:SetPoint("BOTTOMRIGHT", -10, 10)
	foot:SetJustifyH("LEFT")
	foot:SetText(L["The map's own settings: the gear in its title bar."])

	-- the module picked: one header for every module, its title and its switch on one line
	head = {}
	local box = Inset(win)
	box:SetPoint("TOPLEFT", list, "TOPRIGHT", 6, 0)
	box:SetPoint("BOTTOMRIGHT", -(EDGE.r + 2), EDGE.b + 2)
	local enableLabel = box:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	enableLabel:SetPoint("TOPRIGHT", -PAD, -PAD - 4)
	enableLabel:SetText(L["Enable this module"])
	head.enable = CreateFrame("CheckButton", nil, box, "UICheckButtonTemplate")
	head.enable:SetSize(26, 26)
	head.enable:SetPoint("RIGHT", enableLabel, "LEFT", -2, -1)
	head.enable:SetScript("OnClick", function(self)
		if selected then MM:SetEnabled(selected, self:GetChecked()) end
		Options.Refresh()
	end)
	head.title = box:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	head.title:SetPoint("TOPLEFT", PAD, -PAD)
	head.title:SetPoint("RIGHT", head.enable, "LEFT", -12, 0)
	head.title:SetJustifyH("LEFT")
	head.title:SetWordWrap(false)
	local rule = box:CreateTexture(nil, "ARTWORK")
	rule:SetColorTexture(1, 0.82, 0, 0.25)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", PAD, -PAD - 26)
	rule:SetPoint("TOPRIGHT", -PAD, -PAD - 26)
	head.desc = box:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	head.desc:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 0, -8)
	head.desc:SetPoint("RIGHT", box, "RIGHT", -PAD, 0)
	head.desc:SetJustifyH("LEFT")
	head.desc:SetSpacing(2)
	head.state = box:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	head.state:SetPoint("TOPLEFT", head.desc, "BOTTOMLEFT", 0, -8)
	head.state:SetPoint("RIGHT", box, "RIGHT", -PAD, 0)
	head.state:SetJustifyH("LEFT")
	head.reload = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
	head.reload:SetSize(170, 22)
	head.reload:SetPoint("TOPRIGHT", head.state, "BOTTOMRIGHT", 0, -4)
	head.reload:SetText(L["Reload the interface"])
	head.reload:SetScript("OnClick", function() ReloadUI() end)
	head.reload:SetScript("OnEnter", function(self) Controls.Tooltip(self, L["Reload the interface"], L["This module changed parts of the game that can only be put back by a reload."]) end)
	head.reload:SetScript("OnLeave", GameTooltip_Hide)
	head.reload:Hide()
	head.settings = CreateFrame("Frame", nil, box)
	head.settings:SetPoint("TOPLEFT", head.state, "BOTTOMLEFT", 0, -32)
	head.settings:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -PAD, PAD)

	-- (keyboard taken only out of combat: built in a fight, Escape waits for its end, keys never held)
	if InCombatLockdown() then
		ns.Events:Register("optionsKeys", "PLAYER_REGEN_ENABLED", function()
			ns.Events:Unregister("optionsKeys", "PLAYER_REGEN_ENABLED")
			TakeEscape(win)
		end)
	else
		TakeEscape(win)
	end
	win:SetScript("OnShow", function() PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN or 839) Options.Refresh() end)
	win:SetScript("OnHide", function() PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE or 840) end)
	PlaceWindow()

	local last = Core().optionsModule
	local first = MM:Sorted()[1]
	selected = selected or (last and MM:Get(last) and last) or (first and first.name)
end

---------------------------------------------------------------------------
-- Opening, and the page in the game's Settings
---------------------------------------------------------------------------
-- /av config [module], the map's menu: the window (a module picked if named); toggled when none is named
function Options.Open(moduleName)
	if not win then Build() end
	if moduleName and MM:Get(moduleName) then
		selected = moduleName
		Core().optionsModule = moduleName
	elseif win:IsShown() then
		win:Hide()
		return
	end
	win:Show()
	win:Raise()
	Options.Refresh()
end

-- (at login, Core/Bootstrap.lua: the page in Options > AddOns, with a button opening the window)
function Options.Register()
	if category or not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
	local panel = CreateFrame("Frame", "AzerothVeilSettingsPanel")
	panel.name = ns.TITLE
	local t = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	t:SetPoint("TOPLEFT", 16, -16)
	t:SetText(ns.TITLE)
	local d = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -10)
	d:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
	d:SetJustifyH("LEFT")
	d:SetText(L["AzerothVeil's options are in a window of their own, which you can move anywhere: the button below, or /av config."])
	local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	b:SetSize(220, 26)
	b:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -14)
	b:SetText(L["Open AzerothVeil's options"])
	b:SetScript("OnClick", function() Options.Open(selected or Core().optionsModule or (MM:Sorted()[1] or {}).name) end)
	category = Settings.RegisterCanvasLayoutCategory(panel, ns.TITLE)
	Settings.RegisterAddOnCategory(category)
	-- (state changes made elsewhere, /av modules: shown at once if the window's open)
	ns.Callbacks:Register("MODULE_STATE_CHANGED", "options", function() Options.Refresh() end)
end
