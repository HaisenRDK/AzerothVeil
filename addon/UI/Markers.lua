-- AzerothVeil — UI/Markers.lua: the map markers' windows (the Markers module's, Modules/Markers.lua), in Blizzard's
-- own frames: a marker's card (its note, icon, colour, category; follow, share, chat, delete), the list of every
-- marker by category (shown or hidden, renamed, added, deleted; shared, exported, imported as a code), the code box,
-- and the question asked when someone shares markers with you (this addon's own window, never the game's
-- StaticPopupDialogs). Each built the first time it's wanted; nothing here runs before.
local _, ns = ...
local L = ns.L
local S = ns.Style

local UI = {}
ns.MarkersUI = UI

local card, list, codeBox, ask
local function M() return ns.Markers end

---------------------------------------------------------------------------
-- Building blocks
---------------------------------------------------------------------------
-- a window as the options' (Blizzard's frame without a portrait, its title, its close button), moved by its title
-- bar, closed by Escape
local function Window(title, w, h)
	local ok, f = pcall(CreateFrame, "Frame", nil, UIParent, "PortraitFrameTemplate")
	if not (ok and f) then
		f = CreateFrame("Frame", nil, UIParent)
		S.Panel(f, { 0.05, 0.055, 0.06, 0.97 }, nil, true)
		local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", 2, 2)
		f.CloseButton = close
	end
	f:SetSize(w, h)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	if f.SetTitle then f:SetTitle(title) elseif f.TitleText then f.TitleText:SetText(title) end
	if ButtonFrameTemplate_HidePortrait then pcall(ButtonFrameTemplate_HidePortrait, f) end
	if f.NineSlice and NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
		pcall(NineSliceUtil.ApplyLayoutByName, f.NineSlice, "ButtonFrameTemplateNoPortrait")
	end
	local pc = f.PortraitContainer or f.portrait
	if pc then pc:Hide() end
	if f.CloseButton then f.CloseButton:SetScript("OnClick", function() f:Hide() end) end
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetPoint("CENTER")
	ns.TakeEscape(f, function() f:Hide() end)
	f:Hide()
	return f
end

local function Button(parent, text, w, onClick, tip)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	S.FrizButton(b)   -- (AzerothVeil: Friz Quadrata)
	b:SetSize(w, 22)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	if tip then
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(text, 1, 0.82, 0)
			GameTooltip:AddLine(tip, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", GameTooltip_Hide)
	end
	return b
end

local function Text(parent, font)
	local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlightSmall")
	fs:SetJustifyH("LEFT")
	return fs
end

local function Edit(parent, w)
	local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	S.Friz(e)   -- (AzerothVeil: Friz Quadrata)
	e:SetSize(w, 20)
	e:SetAutoFocus(false)
	e:SetScript("OnEscapePressed", e.ClearFocus)
	return e
end

local function SetIcon(tex, icon) S.SetIcon(tex, icon) end

-- the colour shown for a marker's colour (the first, gold: the map pin's own)
local function Swatch(i)
	local c = M().COLORS[i]
	if c and c[2] then return c[2], c[3], c[4] end
	return 1, 0.82, 0
end

-- the share buttons' work: the markers to group / guild / target
local function ShareButtons(parent, getList, x, y)
	local row = {}
	for i, to in ipairs({ { "group", L["Group"] }, { "guild", L["Guild"] }, { "target", L["Target"] } }) do
		local b = Button(parent, to[2], 82, function() M().Share(getList(), to[1]) end,
			to[1] == "target" and L["Whispered to your target, if it's a player."] or nil)
		b:SetPoint("TOPLEFT", x + (i - 1) * 86, y)
		row[i] = b
	end
	return row
end

local listening = false
local function Listen()
	if listening then return end
	listening = true
	ns.Callbacks:Register("MARKERS_CHANGED", "markersUI", function() UI.Refresh() end)
end

---------------------------------------------------------------------------
-- A marker's card
---------------------------------------------------------------------------
local function BuildCard()
	card = Window(L["Map marker"], 330, 356)
	local f = card
	f.place = Text(f, "GameFontNormal")
	f.place:SetPoint("TOPLEFT", 16, -34)
	f.place:SetPoint("RIGHT", -16, 0)

	local noteLabel = Text(f)
	noteLabel:SetPoint("TOPLEFT", 16, -58)
	noteLabel:SetText(L["Note"])
	f.note = Edit(f, 292)
	f.note:SetPoint("TOPLEFT", 20, -72)
	f.note:SetMaxLetters(160)
	f.note:SetScript("OnTextChanged", function(self, user)
		if user and f.marker then
			f.marker.note = M().Clean(self:GetText())
			M().Changed()
		end
	end)
	f.note:SetScript("OnEnterPressed", function() f:Hide() end)

	-- the icons, two rows
	local iconLabel = Text(f)
	iconLabel:SetPoint("TOPLEFT", 16, -100)
	iconLabel:SetText(L["Icon"])
	f.icons = {}
	for i, ic in ipairs(M().ICONS) do
		local b = CreateFrame("Button", nil, f)
		b:SetSize(28, 28)
		b:SetPoint("TOPLEFT", 16 + ((i - 1) % 8) * 36, -116 - math.floor((i - 1) / 8) * 32)
		b.tex = b:CreateTexture(nil, "ARTWORK")
		b.tex:SetSize(22, 22)
		b.tex:SetPoint("CENTER")
		SetIcon(b.tex, ic[1])
		b.sel = b:CreateTexture(nil, "OVERLAY")
		b.sel:SetTexture("Interface\\Buttons\\CheckButtonHilight")
		b.sel:SetBlendMode("ADD")
		b.sel:SetAllPoints()
		b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		b:SetScript("OnClick", function()
			if f.marker then f.marker.icon = i M().Changed() end
		end)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(ic[2], 1, 1, 1)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", GameTooltip_Hide)
		f.icons[i] = b
	end

	-- the colours
	local colorLabel = Text(f)
	colorLabel:SetPoint("TOPLEFT", 16, -186)
	colorLabel:SetText(L["Colour"])
	f.colors = {}
	for i, c in ipairs(M().COLORS) do
		local b = CreateFrame("Button", nil, f)
		b:SetSize(26, 26)
		b:SetPoint("TOPLEFT", 70 + (i - 1) * 32, -180)
		b.border = b:CreateTexture(nil, "BACKGROUND")
		b.border:SetColorTexture(0, 0, 0, 1)
		b.border:SetAllPoints()
		b.fill = b:CreateTexture(nil, "ARTWORK")
		b.fill:SetPoint("TOPLEFT", 3, -3)
		b.fill:SetPoint("BOTTOMRIGHT", -3, 3)
		b.fill:SetColorTexture(Swatch(i))
		b:SetScript("OnClick", function()
			if f.marker then f.marker.color = i M().Changed() end
		end)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(c[1], 1, 1, 1)
			GameTooltip:AddLine(L["Shared with the marker; it tints the map pin and the dot."], 0.8, 0.8, 0.8, true)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", GameTooltip_Hide)
		f.colors[i] = b
	end

	-- its category: the previous and next ones
	local catLabel = Text(f)
	catLabel:SetPoint("TOPLEFT", 16, -220)
	catLabel:SetText(L["Category"])
	f.cat = Text(f, "GameFontHighlight")
	f.cat:SetPoint("LEFT", catLabel, "RIGHT", 10, 0)
	f.cat:SetWidth(150)
	local function Step(d)
		local m = f.marker
		if not m then return end
		local cats = M().Data().cats
		local at = 1
		for i, c in ipairs(cats) do if c.id == m.cat then at = i end end
		m.cat = cats[(at - 1 + d) % #cats + 1].id
		M().Data().current = m.cat
		M().Changed()
	end
	local prev = Button(f, "<", 28, function() Step(-1) end)
	prev:SetPoint("TOPRIGHT", -50, -215)
	local nextB = Button(f, ">", 28, function() Step(1) end)
	nextB:SetPoint("TOPRIGHT", -18, -215)

	-- follow, chat, share, delete, the list
	f.follow = Button(f, L["Follow"], 144, function()
		local m = f.marker
		if not m then return end
		if M().Followed(m) then M().Unfollow() else M().Follow(m) end
		C_Timer.After(0, UI.Refresh)
	end, L["Blizzard's waypoint on it, and its arrow."])
	f.follow:SetPoint("TOPLEFT", 16, -248)
	local chat = Button(f, L["In chat"], 144, function() if f.marker then M().ChatLink(f.marker) end end,
		L["Its link in the chat box (also Shift-click on it)."])
	chat:SetPoint("TOPLEFT", 166, -248)
	local shareLabel = Text(f)
	shareLabel:SetPoint("TOPLEFT", 16, -282)
	shareLabel:SetText(L["Share"])
	ShareButtons(f, function() return { f.marker } end, 56, -276)
	local delete = Button(f, L["Delete"], 144, function()
		if f.marker then M().Remove(f.marker) f.marker = nil M().Changed() f:Hide() end
	end, L["Also a right-click on it."])
	delete:SetPoint("TOPLEFT", 16, -312)
	local all = Button(f, L["Map markers..."], 144, function() UI.OpenList() end)
	all:SetPoint("TOPLEFT", 166, -312)
	f:SetScript("OnHide", function() f.marker = nil if f.note:HasFocus() then f.note:ClearFocus() end end)
end

local function RefreshCard()
	if not (card and card:IsShown() and card.marker) then return end
	local f, m = card, card.marker
	-- (deleted meanwhile, from the list or by Alt-click: the card goes)
	local there = false
	for _, x in ipairs(M().Data().list) do if x == m then there = true break end end
	if not there then f:Hide() return end
	f.place:SetText(("%s  |cffb0b0b0%.1f, %.1f|r"):format(M().ZoneName(m.map), m.x * 100, m.y * 100))
	if not f.note:HasFocus() then f.note:SetText(m.note or "") end
	for i, b in ipairs(f.icons) do
		b.sel:SetShown(i == m.icon)
		local tint = M().ICONS[i][3] and M().COLORS[m.color] and M().COLORS[m.color][2]
		if tint then b.tex:SetVertexColor(Swatch(m.color)) else b.tex:SetVertexColor(1, 1, 1) end
	end
	for i, b in ipairs(f.colors) do
		if i == m.color then b.border:SetColorTexture(1, 1, 1, 1) else b.border:SetColorTexture(0, 0, 0, 1) end
	end
	f.cat:SetText(M().CatName(M().Cat(m.cat)))
	f.follow:SetText(M().Followed(m) and L["Stop following"] or L["Follow"])
end

-- a marker's card (fresh: just dropped, its note to write)
function UI.Edit(m, fresh)
	if not card then BuildCard() end
	Listen()
	card.marker = m
	card:Show()
	card:Raise()
	RefreshCard()
	if fresh then card.note:SetFocus() end
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------
local CAT_W, ROW_H = 190, 22
local selected                      -- the category picked in the list

local function Scroll(parent, w, h)
	local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
	sf:SetSize(w, h)
	local child = CreateFrame("Frame", nil, sf)
	child:SetSize(w, 1)
	sf:SetScrollChild(child)
	sf.child, sf.rows = child, {}
	return sf
end

local function CatRow(sf, i)
	local r = sf.rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, sf.child)
	r:SetSize(CAT_W - 4, ROW_H)
	r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
	r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
	r.check:SetSize(22, 22)
	r.check:SetPoint("LEFT", -2, 0)
	r.check:SetScript("OnClick", function(self)
		local c = M().Cat(r.catID)
		if c then c.shown = self:GetChecked() and true or false M().Changed() end
	end)
	r.check:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(L["Shown on the map"], 1, 1, 1)
		GameTooltip:Show()
	end)
	r.check:SetScript("OnLeave", GameTooltip_Hide)
	r.name = Text(r, "GameFontHighlight")
	r.name:SetPoint("LEFT", r.check, "RIGHT", 2, 0)
	r.name:SetPoint("RIGHT", -30, 0)
	r.name:SetWordWrap(false)
	r.count = Text(r, "GameFontDisableSmall")
	r.count:SetPoint("RIGHT", -4, 0)
	r.count:SetJustifyH("RIGHT")
	r.hl = r:CreateTexture(nil, "BACKGROUND")
	r.hl:SetAllPoints()
	r.hl:SetColorTexture(1, 0.82, 0, 0.15)
	r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	r:SetScript("OnClick", function() selected = r.catID list.deleteArmed = nil UI.Refresh() end)
	sf.rows[i] = r
	return r
end

local function MarkerRow(sf, i)
	local r = sf.rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, sf.child)
	r:SetSize(sf.child:GetWidth() - 4, ROW_H + 6)
	r:SetPoint("TOPLEFT", 0, -(i - 1) * (ROW_H + 6))
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(20, 20)
	r.icon:SetPoint("LEFT", 2, 0)
	r.note = Text(r, "GameFontHighlight")
	r.note:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, 2)
	r.note:SetPoint("RIGHT", -26, 0)
	r.note:SetWordWrap(false)
	r.place = Text(r, "GameFontDisableSmall")
	r.place:SetPoint("TOPLEFT", r.note, "BOTTOMLEFT", 0, -1)
	r.place:SetPoint("RIGHT", -26, 0)
	r.del = CreateFrame("Button", nil, r, "UIPanelCloseButton")
	r.del:SetSize(22, 22)
	r.del:SetPoint("RIGHT", 0, 0)
	r.del:SetScript("OnClick", function() if r.marker then M().Remove(r.marker) M().Changed() end end)
	r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	r:SetScript("OnClick", function()
		local m = r.marker
		if not m then return end
		local u, v = M().Units(m)
		if u and ns.Map then ns.Map.Show() ns.Map.Glide(ns.Map.SetView, u, v) end   -- (open already: gliding there)
		UI.Edit(m)
	end)
	r:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(L["Click: show it on the map, and its card"], 1, 1, 1)
		GameTooltip:Show()
	end)
	r:SetScript("OnLeave", GameTooltip_Hide)
	sf.rows[i] = r
	return r
end

local function Selected()
	local d = M().Data()
	if not M().Cat(selected) then selected = d.cats[1].id end
	return M().Cat(selected)
end

local function BuildList()
	list = Window(L["Map markers"], 560, 430)
	local f = list
	local catTitle = Text(f, "GameFontNormal")
	catTitle:SetPoint("TOPLEFT", 16, -34)
	catTitle:SetText(L["Categories"])
	f.cats = Scroll(f, CAT_W, 236)
	f.cats:SetPoint("TOPLEFT", 14, -54)
	-- the category picked: its name, new, delete
	local nameLabel = Text(f)
	nameLabel:SetPoint("TOPLEFT", 16, -300)
	nameLabel:SetText(L["Name"])
	f.name = Edit(f, CAT_W - 10)
	f.name:SetPoint("TOPLEFT", 20, -314)
	f.name:SetMaxLetters(40)
	local function Rename()
		local c = Selected()
		if c then c.name = M().Clean(f.name:GetText()) M().Changed() end
	end
	f.name:SetScript("OnEnterPressed", function(self) Rename() self:ClearFocus() end)
	f.name:SetScript("OnEditFocusLost", Rename)
	local new = Button(f, L["New"], 92, function()
		local c = M().AddCat(L["Category"] .. " " .. (#M().Data().cats + 1))
		selected = c.id
		M().Changed()
		f.name:SetFocus()
		f.name:HighlightText()
	end, L["A new category, shown on the map."])
	new:SetPoint("TOPLEFT", 14, -340)
	f.delete = Button(f, L["Delete"], 92, function()
		local c = Selected()
		if not c then return end
		if f.deleteArmed ~= c.id then f.deleteArmed = c.id UI.Refresh() return end
		f.deleteArmed = nil
		if M().RemoveCat(c.id) then selected = nil M().Changed() end
	end, L["The category and its markers (click twice). The first one stays."])
	f.delete:SetPoint("TOPLEFT", 112, -340)

	-- the markers of the category picked
	f.markTitle = Text(f, "GameFontNormal")
	f.markTitle:SetPoint("TOPLEFT", 220, -34)
	f.marks = Scroll(f, 300, 290)
	f.marks:SetPoint("TOPLEFT", 218, -54)
	f.empty = Text(f, "GameFontDisable")
	f.empty:SetPoint("TOPLEFT", 222, -60)
	f.empty:SetWidth(290)
	f.empty:SetText(L["No marker in this category. Ctrl-click the map to drop one."])

	-- the category's markers: shared, exported; a code imported into it
	local shareLabel = Text(f)
	shareLabel:SetPoint("TOPLEFT", 220, -354)
	shareLabel:SetText(L["Share the category"])
	ShareButtons(f, function() return M().InCat(Selected().id) end, 218, -368)
	local export = Button(f, L["Export"], 100, function()
		UI.Code(M().CodeOf(M().InCat(Selected().id)))
	end, L["The category's markers as a code to copy (OpenMap's too)."])
	export:SetPoint("TOPLEFT", 14, -380)
	local import = Button(f, L["Import"], 92, function() UI.Code(nil) end,
		L["Paste a code of markers (AzerothVeil's or OpenMap's): they go in this category."])
	import:SetPoint("TOPLEFT", 116, -380)
end

local function RefreshList()
	if not (list and list:IsShown()) then return end
	local f = list
	local d = M().Data()
	local cur = Selected()
	for i, c in ipairs(d.cats) do
		local r = CatRow(f.cats, i)
		r.catID = c.id
		r.check:SetChecked(c.shown and true or false)
		r.name:SetText(M().CatName(c))
		r.count:SetText(#M().InCat(c.id))
		r.hl:SetShown(c.id == cur.id)
		r:Show()
	end
	for i = #d.cats + 1, #f.cats.rows do f.cats.rows[i]:Hide() end
	f.cats.child:SetHeight(math.max(1, #d.cats * ROW_H))
	if not f.name:HasFocus() then f.name:SetText(M().CatName(cur)) end
	f.delete:SetText(f.deleteArmed == cur.id and L["Sure?"] or L["Delete"])
	f.delete:SetEnabled(cur.id ~= d.cats[1].id)
	local marks = M().InCat(cur.id)
	f.markTitle:SetText(M().CatName(cur))
	for i, m in ipairs(marks) do
		local r = MarkerRow(f.marks, i)
		r.marker = m
		S.SetIcon(r.icon, M().IconOf(m))
		local t = M().TintOf(m)
		if t then r.icon:SetVertexColor(t[1], t[2], t[3]) else r.icon:SetVertexColor(1, 1, 1) end
		r.note:SetText(m.note ~= "" and m.note or ("|cff9a9a9a" .. L["(no note)"] .. "|r"))
		r.place:SetText(("%s  %.1f, %.1f%s"):format(M().ZoneName(m.map), m.x * 100, m.y * 100,
			m.from and ("  |cff99ccff" .. L["Shared by %s"]:format(m.from) .. "|r") or ""))
		r:Show()
	end
	for i = #marks + 1, #f.marks.rows do f.marks.rows[i]:Hide() end
	f.marks.child:SetHeight(math.max(1, #marks * (ROW_H + 6)))
	f.empty:SetShown(#marks == 0)
end

function UI.OpenList()
	if not (M() and M().active) then
		ns.Print(L["Turn on the Map markers module first (/av config)."])
		return
	end
	if not list then BuildList() end
	Listen()
	list:Show()
	list:Raise()
	RefreshList()
end

---------------------------------------------------------------------------
-- The code box: a code to copy, or a box to paste one into
---------------------------------------------------------------------------
local function BuildCode()
	codeBox = Window("", 520, 200)
	local f = codeBox
	f.help = Text(f)
	f.help:SetPoint("TOPLEFT", 16, -34)
	f.help:SetPoint("RIGHT", -16, 0)
	local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
	sf:SetPoint("TOPLEFT", 16, -56)
	sf:SetPoint("BOTTOMRIGHT", -34, 44)
	local box = CreateFrame("EditBox", nil, sf)
	box:SetMultiLine(true)
	box:SetMaxLetters(0)
	box:SetAutoFocus(false)
	box:SetFontObject(ChatFontNormal)
	box:SetWidth(460)
	box:SetScript("OnEscapePressed", function() f:Hide() end)
	box:SetScript("OnTextChanged", function(self, user)
		if user and f.text then self:SetText(f.text) self:HighlightText() end   -- (a code to copy: as it is)
	end)
	sf:SetScrollChild(box)
	f.box = box
	f.add = Button(f, L["Add the markers"], 140, function()
		local got = M().FromCode(f.box:GetText())
		if not got or #got == 0 then ns.Print(L["That isn't a code of markers (it starts %s)."]:format(M().CODE)) return end
		ns.Print(L["Added %d marker(s) from the code."]:format(M().AddAll(got, nil, Selected().id)))
		f:Hide()
	end)
	f.add:SetPoint("BOTTOMRIGHT", -16, 14)
end

-- text: a code to show, selected for Ctrl-C; nil: an empty box to paste one into
function UI.Code(text)
	if not codeBox then BuildCode() end
	local f = codeBox
	f.text = text
	local title = text and L["Export markers"] or L["Import markers"]
	if f.SetTitle then f:SetTitle(title) elseif f.TitleText then f.TitleText:SetText(title) end
	f.help:SetText(text and L["Ctrl-C to copy, then paste it anywhere (another player's AzerothVeil or OpenMap: Import)."]
		or L["Paste a code of markers here (Ctrl-V), then Add the markers."])
	f.box:SetText(text or "")
	f.add:SetShown(not text)
	f:Show()
	f:Raise()
	f.box:SetFocus()
	if text then f.box:HighlightText() end
end

---------------------------------------------------------------------------
-- Markers shared with you: asked
---------------------------------------------------------------------------
local function BuildAsk()
	ask = Window(L["Shared markers"], 340, 170)
	local f = ask
	f.text = Text(f, "GameFontHighlight")
	f.text:SetPoint("TOPLEFT", 16, -36)
	f.text:SetPoint("RIGHT", -16, 0)
	f.text:SetSpacing(2)
	f.yes = Button(f, L["Add them"], 120, function()
		local add = f.onAdd
		f.onAdd = nil
		if add then add() end
		f:Hide()
	end)
	f.yes:SetPoint("BOTTOMLEFT", 40, 14)
	f.no = Button(f, L["Ignore"], 120, function() f:Hide() end)
	f.no:SetPoint("BOTTOMRIGHT", -40, 14)
	f:SetScript("OnHide", function()
		f.onAdd = nil
		local done = f.onDone
		f.onDone = nil
		if done then done() end
	end)
end

-- batch: { from, list }; onAdd: added; onDone: answered or closed
function UI.Ask(batch, onAdd, onDone)
	if not ask then BuildAsk() end
	local f = ask
	local lines = {}
	for i = 1, math.min(3, #batch.list) do
		local q = batch.list[i]
		lines[i] = M().ZoneName(q.map) .. (q.note ~= "" and (": " .. q.note) or "")
	end
	if #batch.list > 3 then lines[#lines + 1] = L["... and %d more"]:format(#batch.list - 3) end
	f.text:SetText(L["%s shared %d marker(s) with you:"]:format(batch.from, #batch.list)
		.. "\n|cffffd100" .. table.concat(lines, "\n") .. "|r")
	f:SetHeight(math.max(130, f.text:GetStringHeight() + 90))
	f.onAdd, f.onDone = onAdd, onDone
	f:Show()
	f:Raise()
	PlaySound(SOUNDKIT and SOUNDKIT.TELL_MESSAGE or 3081)
end

---------------------------------------------------------------------------
function UI.Refresh()
	RefreshCard()
	RefreshList()
end

function UI.HideAll()
	for _, f in ipairs({ card, list, codeBox, ask }) do if f then f:Hide() end end
end
