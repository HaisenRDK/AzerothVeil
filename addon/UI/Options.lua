-- AzerothVeil — UI/Options.lua
-- The central options: one page in the game's own Settings window (Options > AddOns > AzerothVeil),
-- drawn with Blizzard's own pieces (InsetFrameTemplate, UICheckButtonTemplate,
-- MinimalSliderWithSteppersTemplate, UIPanelButtonTemplate, the game's fonts).
--   left: the modules, each in its state's colour (active / disabled / unavailable);
--   right: the module picked: what it does, its on/off switch, its state, and its settings, built from
--   its declaration (Core/ModuleManager.lua: settings = { ... }). While the module is off its settings
--   are shown greyed out with their saved values, and can't be changed.
-- The map's own settings (PerfectMap's) stay in the map's gear menu for now.
-- Built the first time it's shown; nothing runs while it's closed.
local _, ns = ...
local L = ns.L
local MM = ns.Modules

local Options = {}
ns.Options = Options

local LIST_W = 190
local ROW_H = 22
local PAD = 16

local panel, category
local listButtons = {}
local pages = {}              -- module name -> its settings frame
local selected
local right                   -- the right side's parts

local COLORS = {
	active = { 0.25, 1, 0.25 },
	disabled = { 0.6, 0.6, 0.6 },
	unavailable = { 1, 0.5, 0.25 },
}

local function Tooltip(owner, title, text)
	if not title then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(title, 1, 0.82, 0)
	if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
	GameTooltip:Show()
end

local function Inset(parent)
	local ok, f = pcall(CreateFrame, "Frame", nil, parent, "InsetFrameTemplate")
	if ok and f then return f end
	return CreateFrame("Frame", nil, parent)
end

---------------------------------------------------------------------------
-- A module's settings, built from its declaration
---------------------------------------------------------------------------
local Rows = {}

function Rows.header(page, spec, y)
	local fs = page:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	fs:SetPoint("TOPLEFT", 0, y - 6)
	fs:SetText(spec.label or "")
	return { Refresh = function() end }, y - 26
end

function Rows.toggle(page, spec, y, moduleName)
	local check = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
	check:SetSize(26, 26)
	check:SetPoint("TOPLEFT", (spec.parent and 20 or 0) - 4, y + 2)
	local label = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	label:SetPoint("LEFT", check, "RIGHT", 2, 1)
	label:SetText(spec.label or spec.key)
	check:SetScript("OnClick", function(self)
		MM:SetSetting(moduleName, spec.key, self:GetChecked())
		Options.Refresh()
	end)
	check:SetScript("OnEnter", function(self) Tooltip(self, spec.label, spec.tooltip) end)
	check:SetScript("OnLeave", GameTooltip_Hide)
	local row = {}
	function row.Refresh()
		check:SetChecked(MM:GetSetting(moduleName, spec.key) and true or false)
		local editable = MM:IsOptionEditable(moduleName, spec.key)
		check:SetEnabled(editable)
		label:SetFontObject(editable and "GameFontHighlight" or "GameFontDisable")
	end
	return row, y - ROW_H - 4
end

-- (no module declares one yet: written to the template's API as other addons on this client use it)
function Rows.range(page, spec, y, moduleName)
	local label = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	label:SetPoint("TOPLEFT", spec.parent and 20 or 0, y - 4)
	label:SetText(spec.label or spec.key)
	local ok, holder = pcall(CreateFrame, "Frame", nil, page, "MinimalSliderWithSteppersTemplate")
	if not (ok and holder and holder.Slider) then
		return { Refresh = function() end }, y - ROW_H
	end
	holder:SetSize(220, 20)
	holder:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
	local value = page:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	value:SetPoint("LEFT", holder, "RIGHT", 8, 0)
	local slider = holder.Slider
	local step = spec.step or 1
	slider:SetMinMaxValues(spec.min or 0, spec.max or 1)
	slider:SetValueStep(step)
	slider:SetObeyStepOnDrag(true)
	local filling = false
	local function Show(v)
		value:SetText(spec.format and spec.format(v) or (step < 1 and ("%.2f"):format(v) or tostring(math.floor(v + 0.5))))
	end
	slider:SetScript("OnValueChanged", function(_, v)
		if holder.UpdateStepperStates then holder:UpdateStepperStates() end
		Show(v)
		if not filling then MM:SetSetting(moduleName, spec.key, v) end
	end)
	local row = {}
	function row.Refresh()
		local v = MM:GetSetting(moduleName, spec.key) or spec.default or spec.min or 0
		filling = true
		slider:SetValue(v)
		filling = false
		Show(v)
		local editable = MM:IsOptionEditable(moduleName, spec.key)
		slider:SetEnabled(editable)
		if holder.Back then holder.Back:SetEnabled(editable) end
		if holder.Forward then holder.Forward:SetEnabled(editable) end
		label:SetFontObject(editable and "GameFontHighlight" or "GameFontDisable")
	end
	return row, y - ROW_H - 30
end

local function BuildPage(m)
	local page = CreateFrame("Frame", nil, right.settings)
	page:SetAllPoints()
	page.rows = {}
	local y = 0
	for _, spec in ipairs(m.settings) do
		local build = Rows[spec.type]
		if build then
			local row
			row, y = build(page, spec, y, m.name)
			page.rows[#page.rows + 1] = row
		end
	end
	if #page.rows == 0 then
		local fs = page:CreateFontString(nil, "ARTWORK", "GameFontDisable")
		fs:SetPoint("TOPLEFT")
		fs:SetText(L["This module has no settings."])
	end
	page:Hide()
	return page
end

---------------------------------------------------------------------------
-- The right side: the module picked
---------------------------------------------------------------------------
local function RefreshRight()
	local m = selected and MM:Get(selected)
	if not m then return end
	right.title:SetText(m.title)
	right.desc:SetText(m.description or "")
	right.enable:SetChecked(MM:IsEnabled(m.name))
	local state, reason = MM:State(m.name)
	local c = COLORS[state] or COLORS.disabled
	local text = (state == "active" and L["Active"]) or (state == "disabled" and L["Disabled: its settings are kept and come back when it's enabled."])
		or (L["Not running"] .. (reason and (": " .. reason) or ""))
	right.state:SetText(text)
	right.state:SetTextColor(c[1], c[2], c[3])
	right.reload:SetShown(m.needsReload and true or false)
	for name, page in pairs(pages) do page:SetShown(name == m.name) end
	local page = pages[m.name]
	if not page then
		page = BuildPage(m)
		pages[m.name] = page
		page:Show()
	end
	for _, row in ipairs(page.rows) do row.Refresh() end
end

local function RefreshList()
	for _, b in ipairs(listButtons) do
		local state = MM:State(b.moduleName)
		local c = COLORS[state] or COLORS.disabled
		b.text:SetTextColor(c[1], c[2], c[3])
		b.selectedTex:SetShown(b.moduleName == selected)
	end
end

function Options.Refresh()
	if not (panel and panel:IsShown()) then return end
	RefreshList()
	RefreshRight()
end

local function Select(name)
	selected = name
	local root = ns.Database.Root()
	if root then root.core.optionsModule = name end
	Options.Refresh()
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
local function Build()
	-- the title
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", PAD, -PAD)
	title:SetText(ns.TITLE)
	local version = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	version:SetPoint("LEFT", title, "RIGHT", 8, -1)
	version:SetText(ns.VERSION or "")
	local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	sub:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
	sub:SetJustifyH("LEFT")
	sub:SetText(L["Pick a module to turn it on or off and change its settings. The map's own settings are in the map's gear menu (/av)."])

	-- the modules
	local list = Inset(panel)
	list:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -12)
	list:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", PAD, PAD)
	list:SetWidth(LIST_W)
	local y = -6
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

	-- the module picked
	right = {}
	local box = Inset(panel)
	box:SetPoint("TOPLEFT", list, "TOPRIGHT", 10, 0)
	box:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD, PAD)
	right.title = box:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	right.title:SetPoint("TOPLEFT", PAD, -PAD)
	right.desc = box:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	right.desc:SetPoint("TOPLEFT", right.title, "BOTTOMLEFT", 0, -8)
	right.desc:SetPoint("RIGHT", box, "RIGHT", -PAD, 0)
	right.desc:SetJustifyH("LEFT")
	right.desc:SetSpacing(2)
	right.enable = CreateFrame("CheckButton", nil, box, "UICheckButtonTemplate")
	right.enable:SetSize(26, 26)
	right.enable:SetPoint("TOPLEFT", right.desc, "BOTTOMLEFT", -4, -12)
	local enableLabel = box:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	enableLabel:SetPoint("LEFT", right.enable, "RIGHT", 2, 1)
	enableLabel:SetText(L["Enable this module"])
	right.enable:SetScript("OnClick", function(self)
		if selected then MM:SetEnabled(selected, self:GetChecked()) end
		Options.Refresh()
	end)
	right.state = box:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	right.state:SetPoint("TOPLEFT", right.enable, "BOTTOMLEFT", 4, -4)
	right.state:SetPoint("RIGHT", box, "RIGHT", -PAD, 0)
	right.state:SetJustifyH("LEFT")
	right.reload = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
	right.reload:SetSize(160, 22)
	right.reload:SetPoint("TOPLEFT", right.state, "BOTTOMLEFT", 0, -6)
	right.reload:SetText(L["Reload the interface"])
	right.reload:SetScript("OnClick", function() ReloadUI() end)
	right.reload:SetScript("OnEnter", function(self) Tooltip(self, L["Reload the interface"], L["This module changed parts of the game that can only be put back by a reload."]) end)
	right.reload:SetScript("OnLeave", GameTooltip_Hide)
	right.reload:Hide()
	local rule = box:CreateTexture(nil, "ARTWORK")
	rule:SetColorTexture(1, 0.82, 0, 0.25)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", right.state, "BOTTOMLEFT", -4, -36)
	rule:SetPoint("RIGHT", box, "RIGHT", -PAD, 0)
	right.settings = CreateFrame("Frame", nil, box)
	right.settings:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 4, -10)
	right.settings:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -PAD, PAD)

	local root = ns.Database.Root()
	local last = root and root.core.optionsModule
	local first = MM:Sorted()[1]
	selected = (last and MM:Get(last) and last) or (first and first.name)
end

-- Registered in the game's Settings window at login (Core/Bootstrap.lua)
function Options.Register()
	if panel then return end
	panel = CreateFrame("Frame", "AzerothVeilOptionsPanel")
	panel.name = ns.TITLE
	panel:Hide()
	panel:SetScript("OnShow", function(self)
		if not self.built then
			self.built = true
			Build()
		end
		Options.Refresh()
	end)
	-- (state changes made elsewhere, /av modules: shown at once if it's open)
	ns.Callbacks:Register("MODULE_STATE_CHANGED", "options", function() Options.Refresh() end)
	if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
		category = Settings.RegisterCanvasLayoutCategory(panel, ns.TITLE)
		Settings.RegisterAddOnCategory(category)
	end
end

-- /av config [module]: the game's Settings window on this page (a module picked if named)
function Options.Open(moduleName)
	if not panel then Options.Register() end
	if moduleName and MM:Get(moduleName) then
		selected = moduleName
		local root = ns.Database.Root()
		if root then root.core.optionsModule = moduleName end
	end
	if InCombatLockdown() then
		ns.Print(L["The options can't be opened in combat."])
		return
	end
	local id = category and ((category.GetID and category:GetID()) or category.ID)
	if not (id and Settings and Settings.OpenToCategory and pcall(Settings.OpenToCategory, id)) then
		ns.Print(L["Open the game's Options > AddOns > AzerothVeil."])
		return
	end
	Options.Refresh()
end
