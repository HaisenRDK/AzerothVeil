-- AzerothVeil — Engine/IconMenu.lua: the map's icon menu (the Map module's "Icon menu on the map", Modules/Map.lua).
-- A button in the map's top left corner, under the options' one, opening a little panel beside it: every kind of icon
-- the modules put on the map, each with its check box, to show it or not without opening the options.
-- Nothing of its own: its rows are the modules' own settings, those their declaration marks iconMenu = true
-- (Core/ModuleManager.lua), read and written only through the module manager, as the options window's (Menu.lua):
-- the same settings, every screen refreshed on its messages; greyed out (and not clickable) while the module, or
-- the option it hangs from, is off. A module's rows fold under its title (remembered, FM.db.iconMenuFolded).
-- Built the first time it opens; nothing runs while it's closed.
local _, FM = ...
local L = FM.L
local IM = {}
FM.IconMenu = IM

local S = FM.Style
local MM = FM.Modules

local WIDTH = 230
local ROW = 22
local HEAD = 20
local INDENT = 14
local PAD = 8

local button, panel, scroll, page
local sections = {}             -- { m, head, rows = { row } }

local function IconOf(x) if type(x) == "function" then return x() end return x end

local function Depth(m, spec)
	local d, x = 0, spec
	while x and x.parent do d = d + 1 x = m.settingByKey[x.parent] end
	return d
end

local function Folded()
	FM.db.iconMenuFolded = type(FM.db.iconMenuFolded) == "table" and FM.db.iconMenuFolded or {}
	return FM.db.iconMenuFolded
end

-- every row where it goes now (a folded module's hidden), and the panel as tall as that, up to the map's height
local function Layout()
	local y = 0
	local folded = Folded()
	for _, sec in ipairs(sections) do
		sec.head:ClearAllPoints()
		sec.head:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
		y = y + HEAD
		local fold = folded[sec.m.name]
		sec.head.arrow:SetText(fold and "+" or "-")
		for _, r in ipairs(sec.rows) do
			if fold then
				r:Hide()
			else
				r:ClearAllPoints()
				r:SetPoint("TOPLEFT", page, "TOPLEFT", r.indent, -y)
				r:Show()
				y = y + (r.sub and HEAD or ROW)
			end
		end
		y = y + 4
	end
	page:SetHeight(math.max(1, y))
	local most = (button:GetParent():GetHeight() or 500) - 80     -- (the map's view)
	local h = math.min(y, math.max(120, most))
	scroll:SetHeight(h)
	panel:SetHeight(h + PAD * 2)
end

local function Refresh()
	for _, sec in ipairs(sections) do
		for _, r in ipairs(sec.rows) do if r.Refresh then r:Refresh() end end
	end
end
IM.Refresh = function() if panel then Refresh() end end

local function Build(parent)
	panel = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	S.Panel(panel)
	panel:SetWidth(WIDTH + PAD * 2 + 20)
	panel:SetFrameLevel(button:GetFrameLevel() + 40)   -- (over the map's icons and quests)
	panel:EnableMouse(true)
	panel:EnableMouseWheel(true)                        -- (the wheel over it never zooms the map)
	panel:SetScript("OnMouseWheel", function() end)
	panel:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -4)
	scroll = S.Scroll(panel)
	scroll:SetPoint("TOPLEFT", PAD, -PAD)
	scroll:SetWidth(WIDTH)
	page = CreateFrame("Frame", nil, scroll)
	page:SetSize(WIDTH, 10)
	scroll:SetScrollChild(page)
	-- (each module with options marked for the menu: its title, then those options under their section's name)
	for _, m in ipairs(MM:Sorted()) do
		local rows, header, heads = {}, nil, 0
		for _, spec in ipairs(m.settings) do
			if spec.type == "header" then header = spec
			elseif spec.iconMenu and spec.type == "toggle" then
				if header and header ~= rows.lastHeader then
					rows.lastHeader = header
					heads = heads + 1
					local holder = CreateFrame("Frame", nil, page)
					holder:SetSize(WIDTH, HEAD)
					local sub = S.Text(holder, 10, nil, "ARTWORK")
					sub:SetPoint("LEFT", 4, -2)
					sub:SetTextColor(0.75, 0.75, 0.75)
					sub:SetText(header.label or "")
					holder.sub, holder.indent = true, 0
					rows[#rows + 1] = holder
				end
				local d = Depth(m, spec)
				local r = S.SwitchRow(page, spec.label or spec.key, IconOf(spec.icon),
					function() return MM:GetSetting(m.name, spec.key) end,
					function(v) MM:SetSetting(m.name, spec.key, v) end, WIDTH - d * INDENT)
				r.indent = d * INDENT
				r.tip = { spec.label, spec.tooltip }
				local base = r.Refresh
				function r:Refresh()
					base(self)
					local on = MM:IsOptionEditable(m.name, spec.key)
					self:SetEnabled(on)
					if self.SetGreyed and self.check then self:SetGreyed(not on) else self:SetAlpha(on and 1 or 0.4) end
				end
				r:Refresh()
				rows[#rows + 1] = r
			end
		end
		rows.lastHeader = nil
		if #rows > 0 then
			-- (a module's one section: no section name under its title)
			if heads == 1 and rows[1].sub then rows[1]:Hide() table.remove(rows, 1) end
			local head = CreateFrame("Button", nil, page)
			head:SetSize(WIDTH, HEAD)
			local arrow = S.Text(head, 12, nil, "ARTWORK")
			arrow:SetPoint("LEFT", 4, 0)
			arrow:SetTextColor(1, 0.82, 0)
			head.arrow = arrow
			local t = S.Text(head, 12, nil, "ARTWORK")
			t:SetPoint("LEFT", 18, 0)
			t:SetTextColor(1, 0.82, 0)
			t:SetText(m.title)
			head:SetScript("OnClick", function()
				local folded = Folded()
				folded[m.name] = not folded[m.name] or nil
				Layout()
			end)
			sections[#sections + 1] = { m = m, head = head, rows = rows }
		end
	end
	Layout()
end

-- the menu's button, made with the map (Map.lua): hidden while the Map module's option is off
function IM.Attach(parent, b)
	button = b
	b:SetShown(FM.db.iconMenu and true or false)
end

function IM.Toggle()
	if not button then return end
	if not panel then Build(button:GetParent()) end
	panel:SetShown(not panel:IsShown())
	if panel:IsShown() then Layout() Refresh() end
	if button.SetActive then button:SetActive(panel:IsShown()) end
end

-- the Map module's option changed (Modules/Map.lua)
function IM.Apply()
	if not button then return end
	local on = FM.db.iconMenu and true or false
	button:SetShown(on)
	if not on and panel then panel:Hide() if button.SetActive then button:SetActive(false) end end
end

-- (a module or one of its settings changed anywhere: shown here at once)
for _, message in ipairs({ "MODULE_STATE_CHANGED", "MODULE_SETTING_CHANGED", "MODULE_ENABLED_CHANGED" }) do
	FM.Callbacks:Register(message, "iconmenu", function() if panel and panel:IsShown() then Refresh() end end)
end
