-- AzerothVeil — UI/Controls.lua
-- The controls a module's settings are drawn with, one builder per setting type of its declaration
-- (Core/ModuleManager.lua: settings = { { key, type, ... } }), all Blizzard's own pieces:
--   header  a title (GameFontNormal, gold); all = true: "Show all" / "Hide all" buttons beside it
--   toggle  UICheckButtonTemplate and its label; a child option (parent = key) indented under its parent
--   range   MinimalSliderWithSteppersTemplate, its value on the right
-- Each builder returns a row ({ Refresh = fn }) and the next y. A row reads and writes only through the
-- module manager (GetSetting / SetSetting / IsOptionEditable): no setting is kept here.
-- Greyed out (and not editable) while the module is off or its parent option is off.
local _, ns = ...
local MM = ns.Modules

local Controls = {}
ns.Controls = Controls

Controls.ROW_H = 24
local INDENT = 22

local function Tooltip(owner, title, text)
	if not title then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(title, 1, 0.82, 0)
	if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
	GameTooltip:Show()
end
Controls.Tooltip = Tooltip

-- how deep a setting sits under its parents (indent)
local function Depth(m, spec)
	local d, s = 0, spec
	while s and s.parent do
		d = d + 1
		s = m.settingByKey[s.parent]
	end
	return d
end

local Build = {}

function Build.header(page, m, spec, y, onChange)
	local fs = ns.Style.FontString(page, "ARTWORK", "GameFontNormal")
	fs:SetPoint("TOPLEFT", 0, y - 8)
	fs:SetText(spec.label or "")
	if not spec.all then return { Refresh = function() end }, y - 30 end
	-- (all = true: "Show all" / "Hide all" for its section, Blizzard's own buttons beside its title)
	local buttons, prev = {}, fs
	for _, b in ipairs({ { ns.L["Show all"], true }, { ns.L["Hide all"], false } }) do
		local btn = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
		ns.Style.FrizButton(btn)   -- (AzerothVeil: Friz Quadrata)
		btn:SetSize(100, 20)
		btn:SetPoint("LEFT", prev, "RIGHT", prev == fs and 12 or 4, 0)
		btn:SetText(b[1])
		btn:SetScript("OnClick", function()
			MM:SetSection(m.name, spec, b[2])
			if onChange then onChange() end
		end)
		buttons[#buttons + 1] = btn
		prev = btn
	end
	return { Refresh = function()
		for _, btn in ipairs(buttons) do btn:SetEnabled(MM:IsEnabled(m.name)) end
	end }, y - 30
end

function Build.toggle(page, m, spec, y, onChange)
	local check = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
	check:SetSize(26, 26)
	check:SetPoint("TOPLEFT", Depth(m, spec) * INDENT - 4, y + 2)
	local label = ns.Style.FontString(page, "ARTWORK", "GameFontHighlight")
	label:SetPoint("LEFT", check, "RIGHT", 2, 1)
	label:SetText(spec.label or spec.key)
	check:SetScript("OnClick", function(self)
		MM:SetSetting(m.name, spec.key, self:GetChecked())
		if onChange then onChange() end
	end)
	check:SetScript("OnEnter", function(self) Tooltip(self, spec.label, spec.tooltip) end)
	check:SetScript("OnLeave", GameTooltip_Hide)
	local row = {}
	function row.Refresh()
		check:SetChecked(MM:GetSetting(m.name, spec.key) and true or false)
		local editable = MM:IsOptionEditable(m.name, spec.key)
		check:SetEnabled(editable)
		label:SetFontObject(editable and "GameFontHighlight" or "GameFontDisable")
	end
	return row, y - Controls.ROW_H
end

-- AzerothVeil: a choice among a few (spec.values = { { value, label }, ... }): its label, then a button showing the
-- choice and opening the list of them (Style.Select: ours, not Blizzard's drop-down menus)
function Build.select(page, m, spec, y, onChange)
	local x = Depth(m, spec) * INDENT
	local r = ns.Style.Select(page, spec.label or spec.key, spec.values or {},
		function() return MM:GetSetting(m.name, spec.key) end,
		function(v) MM:SetSetting(m.name, spec.key, v) if onChange then onChange() end end, 380 - x)
	r:SetPoint("TOPLEFT", x, y)
	local row = {}
	function row.Refresh()
		r:Refresh()
		local editable = MM:IsOptionEditable(m.name, spec.key)
		r:SetEnabled(editable)
		r:SetAlpha(editable and 1 or 0.5)
	end
	return row, y - Controls.ROW_H - 2
end

-- (no module declares one yet: written to the template's API as other addons on this client use it)
function Build.range(page, m, spec, y, onChange)
	local x = Depth(m, spec) * INDENT
	local label = ns.Style.FontString(page, "ARTWORK", "GameFontHighlight")
	label:SetPoint("TOPLEFT", x, y - 4)
	label:SetText(spec.label or spec.key)
	local ok, holder = pcall(CreateFrame, "Frame", nil, page, "MinimalSliderWithSteppersTemplate")
	if not (ok and holder and holder.Slider) then
		return { Refresh = function() end }, y - Controls.ROW_H
	end
	holder:SetSize(220, 20)
	holder:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
	local value = ns.Style.FontString(page, "ARTWORK", "GameFontNormal")
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
		if not filling then
			MM:SetSetting(m.name, spec.key, v)
			if onChange then onChange() end
		end
	end)
	local row = {}
	function row.Refresh()
		local v = MM:GetSetting(m.name, spec.key) or spec.default or spec.min or 0
		filling = true
		slider:SetValue(v)
		filling = false
		Show(v)
		local editable = MM:IsOptionEditable(m.name, spec.key)
		slider:SetEnabled(editable)
		if holder.Back then holder.Back:SetEnabled(editable) end
		if holder.Forward then holder.Forward:SetEnabled(editable) end
		label:SetFontObject(editable and "GameFontHighlight" or "GameFontDisable")
	end
	return row, y - Controls.ROW_H - 30
end

-- A module's settings on parent, from its declaration: { rows, height }. onChange: after any change.
function Controls.BuildSettings(parent, m, onChange)
	local rows, y = {}, 0
	for _, spec in ipairs(m.settings) do
		local build = Build[spec.type]
		if build then
			local row
			row, y = build(parent, m, spec, y, onChange)
			rows[#rows + 1] = row
		end
	end
	return rows, -y
end
