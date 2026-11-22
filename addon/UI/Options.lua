-- AzerothVeil — UI/Options.lua
-- The modules' options in the game's Options > AddOns > AzerothVeil page, editable there, drawn with
-- Blizzard's own pieces. (AzerothVeil's options screen is its own window, Engine/Menu.lua: the map's gear,
-- /av config, the minimap button; one tab per module, built from the same declarations. Both read and
-- write only through the module manager, and are refreshed on its messages: a change made in one shows
-- at once in the other.)
--
-- A view: left, the modules, each in its state's colour; right, the module picked, with the header
-- every module gets (its title, and on the same line its "Enable" check box), what it does, its state,
-- then its settings built from its declaration (UI/Controls.lua), greyed out with their saved values
-- while it's off. Built the first time it's shown; nothing runs while it's hidden.
local _, ns = ...
local L = ns.L
local MM = ns.Modules
local Controls = ns.Controls

local Options = {}
ns.Options = Options

local LIST_W = 200
local ROW_H = 22
local PAD = 14

local COLORS = {
	active = { 0.25, 1, 0.25 },
	disabled = { 0.6, 0.6, 0.6 },
	unavailable = { 1, 0.5, 0.25 },
}

local views = {}              -- every view built (the window's, the Settings page's)
local category

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
-- A view: the module list and the module picked, inside host (inset by margins)
---------------------------------------------------------------------------
local View = {}
View.__index = View

function View:RefreshRight()
	local m = self.selected and MM:Get(self.selected)
	if not m then return end
	local head = self.head
	head.title:SetText(m.title)
	head.desc:SetText(m.description or "")
	head.enable:SetChecked(MM:IsEnabled(m.name))
	-- (no "active / disabled" line: the check box says it; only why an enabled module doesn't run)
	local state, reason = MM:State(m.name)
	head.state:SetText(state == "unavailable" and (L["Not running"] .. (reason and (": " .. reason) or "")) or "")
	head.state:SetTextColor(1, 0.55, 0.3)
	head.reload:SetShown(m.needsReload and true or false)
	local page = self.pages[m.name]
	if not page then
		page = CreateFrame("Frame", nil, head.settings)
		page:SetPoint("TOPLEFT")
		page:SetPoint("TOPRIGHT")
		local height
		page.rows, height = Controls.BuildSettings(page, m)
		page:SetHeight(math.max(1, height))
		if #page.rows == 0 then
			local fs = ns.Style.FontString(page, "ARTWORK", "GameFontDisable")
			fs:SetPoint("TOPLEFT")
			fs:SetText(L["This module has no settings."])
		end
		self.pages[m.name] = page
	end
	for name, p in pairs(self.pages) do p:SetShown(name == m.name) end
	for _, row in ipairs(page.rows) do row.Refresh() end
end

function View:Refresh()
	if not self.host:IsVisible() then return end
	for _, b in ipairs(self.buttons) do
		local c = COLORS[MM:State(b.moduleName)] or COLORS.disabled
		b.text:SetTextColor(c[1], c[2], c[3])
		b.selectedTex:SetShown(b.moduleName == self.selected)
	end
	self:RefreshRight()
end

function View:Select(name)
	self.selected = name
	Core().optionsModule = name
	self:Refresh()
end

local function NewView(host, top, bottom, left, right)
	local v = setmetatable({ host = host, buttons = {}, pages = {}, head = {} }, View)
	-- the modules
	local list = Inset(host)
	list:SetPoint("TOPLEFT", left, -top)
	list:SetPoint("BOTTOMLEFT", left, bottom)
	list:SetWidth(LIST_W)
	local listHead = ns.Style.FontString(list, "ARTWORK", "GameFontNormal")
	listHead:SetPoint("TOPLEFT", 10, -10)
	listHead:SetText(L["Modules"])
	local y = -32
	for _, m in ipairs(MM:Sorted()) do
		local b = CreateFrame("Button", nil, list)
		b:SetPoint("TOPLEFT", 4, y)
		b:SetPoint("TOPRIGHT", -4, y)
		b:SetHeight(ROW_H)
		b.moduleName = m.name
		b.text = ns.Style.FontString(b, "ARTWORK", "GameFontHighlight")
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
		b:SetScript("OnClick", function(self) v:Select(self.moduleName) end)
		v.buttons[#v.buttons + 1] = b
		y = y - ROW_H
	end
	local foot = ns.Style.FontString(list, "ARTWORK", "GameFontDisableSmall")
	foot:SetPoint("BOTTOMLEFT", 10, 10)
	foot:SetPoint("BOTTOMRIGHT", -10, 10)
	foot:SetJustifyH("LEFT")
	foot:SetText(L["The same settings are in AzerothVeil's options window (/av config, the minimap button, the map's gear)."])

	-- the module picked: one header for every module, its title and its switch on one line
	local head = v.head
	local box = Inset(host)
	box:SetPoint("TOPLEFT", list, "TOPRIGHT", 6, 0)
	box:SetPoint("BOTTOMRIGHT", -right, bottom)
	local enableLabel = ns.Style.FontString(box, "ARTWORK", "GameFontNormal")
	enableLabel:SetPoint("TOPRIGHT", -PAD, -PAD - 4)
	enableLabel:SetText(L["Enable this module"])
	head.enable = CreateFrame("CheckButton", nil, box, "UICheckButtonTemplate")
	head.enable:SetSize(26, 26)
	head.enable:SetPoint("RIGHT", enableLabel, "LEFT", -2, -1)
	head.enable:SetScript("OnEnter", function(self)
		local title, lines = MM:SwitchTooltip(v.selected)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(title or L["Enable this module"], 1, 0.82, 0)
		for _, l in ipairs(lines) do GameTooltip:AddLine(l[1], l[2], l[3], l[4], true) end
		GameTooltip:Show()
	end)
	head.enable:SetScript("OnLeave", GameTooltip_Hide)
	head.enable:SetScript("OnClick", function(self)
		if v.selected then MM:SetEnabled(v.selected, self:GetChecked()) end
		Options.Refresh()
	end)
	head.title = ns.Style.FontString(box, "ARTWORK", "GameFontNormalLarge")
	head.title:SetPoint("TOPLEFT", PAD, -PAD)
	head.title:SetPoint("RIGHT", head.enable, "LEFT", -12, 0)
	head.title:SetJustifyH("LEFT")
	head.title:SetWordWrap(false)
	local rule = box:CreateTexture(nil, "ARTWORK")
	rule:SetColorTexture(1, 0.82, 0, 0.25)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", PAD, -PAD - 26)
	rule:SetPoint("TOPRIGHT", -PAD, -PAD - 26)
	head.desc = ns.Style.FontString(box, "ARTWORK", "GameFontHighlightSmall")
	head.desc:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 0, -8)
	head.desc:SetPoint("RIGHT", box, "RIGHT", -PAD, 0)
	head.desc:SetJustifyH("LEFT")
	head.desc:SetSpacing(2)
	head.state = ns.Style.FontString(box, "ARTWORK", "GameFontHighlightSmall")
	head.state:SetPoint("TOPLEFT", head.desc, "BOTTOMLEFT", 0, -8)
	head.state:SetPoint("RIGHT", box, "RIGHT", -PAD, 0)
	head.state:SetJustifyH("LEFT")
	head.reload = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
	ns.Style.FrizButton(head.reload)   -- (AzerothVeil: Friz Quadrata)
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

	local last = Core().optionsModule
	local first = MM:Sorted()[1]
	v.selected = (last and MM:Get(last) and last) or (first and first.name)
	views[#views + 1] = v
	return v
end

-- every view shown, refreshed (a setting or a module's state changed, from anywhere)
function Options.Refresh()
	for _, v in ipairs(views) do v:Refresh() end
end

---------------------------------------------------------------------------
-- /av config [module]: AzerothVeil's options window (Engine/Menu.lua), on that module's tab if named;
-- toggled when none is
---------------------------------------------------------------------------
function Options.Open(moduleName)
	local Menu = ns.Menu
	if not Menu then return end
	if moduleName and MM:Get(moduleName) then Menu.Open("module_" .. moduleName) else Menu.Toggle() end
end

---------------------------------------------------------------------------
-- The game's Settings page (at login, Core/Bootstrap.lua): the same view, editable there
---------------------------------------------------------------------------
function Options.Register()
	if category then return end
	-- (any change, from the map's menu, this window or that page: every view shown follows)
	ns.Callbacks:Register("MODULE_STATE_CHANGED", "options", function() Options.Refresh() end)
	ns.Callbacks:Register("MODULE_SETTING_CHANGED", "options", function() Options.Refresh() end)
	ns.Callbacks:Register("MODULE_ENABLED_CHANGED", "options", function() Options.Refresh() end)
	if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
	local panel = CreateFrame("Frame", "AzerothVeilSettingsPanel")
	panel.name = ns.TITLE
	panel:SetScript("OnShow", function(self)
		if not self.view then
			local t = ns.Style.FontString(self, "ARTWORK", "GameFontNormalLarge")
			t:SetPoint("TOPLEFT", 16, -14)
			t:SetText(ns.TITLE)
			self.view = NewView(self, 40, 10, 10, 10)
		end
		self.view:Refresh()
	end)
	category = Settings.RegisterCanvasLayoutCategory(panel, ns.TITLE)
	Settings.RegisterAddOnCategory(category)
end
