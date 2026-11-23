-- AzerothVeil — Engine/Find.lua: the map's search box (the Map module's "Search on the map", Modules/Map.lua).
-- In the map's top left corner, beside the options' buttons: type a place, a zone or a kind of icon, and a list under
-- the box offers what it found (the places' names: Labels.lua; the zones: their game names; the kinds of icon: their
-- labels, Pins.CATS). Empty, the list offers the nearest of the kinds you look for most (innkeeper, bank, flight
-- master...). Picked: the map goes there, and what was found stands out in the quests' search glow (Quests.lua's),
-- the nearest icons of a kind with their own icon over it even while that kind is hidden. Escape, or the box's cross,
-- and it's gone.
-- Built with the map; nothing runs while the box is idle (the list is made as you type, the marks laid out with the map).
local _, FM = ...
local L = FM.L
local F = {}
FM.Find = F

local S = FM.Style
local NONE = {}

local BOX_W, BOX_H = 190, 22
local ROW_H = 20
local MAX_ROWS = 9
local NEAREST = 3               -- (the icons of a kind shown, nearest first)
local MARK_ICON = 18
-- (the kinds offered while the box is empty: Pins.CATS keys)
local QUICK = { "flight", "innkeeper", "banker", "auctioneer", "mailbox", "repair", "classTrainer", "stable", "spirit" }

local box, list, rows, markLayer
local marks = {}                -- { u, v, icon }: what stands out now
local markFrames = {}
local results = {}
local Mark                      -- (below)

local function CatOf(key)
	for _, c in ipairs(FM.Pins.CATS) do if c.key == key then return c end end
end

-- where you are (the player), else the view's middle
local function Here()
	local u, v
	if FM.Geo.UnitUnits then u, v = FM.Geo.UnitUnits("player") end      -- (both values: "a and f()" keeps only the first)
	if u and v then return u, v end
	local left, top, scale, vw, vh = FM.Map.ViewNow()
	return left + vw / scale / 2, top + vh / scale / 2
end

local function Clear()
	wipe(marks)
	for _, f in ipairs(markFrames) do f:Hide() end
	FM.Map.MarkDirty()
end
F.Clear = Clear

local Run
local function Go(r) Run(r) end
-- (what was picked: run safely, any error said in the chat, not lost)
local function Pick(r)
	box:ClearFocus()
	list:Hide()
	local ok, err = pcall(Go, r)
	if not ok then FM.Print("|cffff5555" .. tostring(err) .. "|r") end
end
Run = function(r)
	Clear()
	if FM.Dungeon then FM.Dungeon.ToWorld() end
	if r.kind == "place" then
		marks[1] = { r.u, r.v }
		FM.Map.SetView(r.u, r.v, 60)
	elseif r.kind == "zone" then
		FM.Map.ShowMapID(r.zone)
	elseif r.kind == "near" then
		local u, v = Here()
		local found = FM.Pins.Nearest(r.cat.key, u, v, NEAREST)
		if #found == 0 then
			FM.Print(L["None found on this continent."])
			return
		end
		for _, pin in ipairs(found) do
			marks[#marks + 1] = { pin.u, pin.v, pin.icon or r.cat.icon, pin.title }
		end
		-- (you and the nearest both in view, framed together; no closer in than the map's step 10, Map.lua)
		local near = found[1]
		FM.Map.ShowUnits(math.min(u, near.u), math.max(u, near.u), math.min(v, near.v), math.max(v, near.v),
			FM.W / FM.Map.Cran(10))
		FM.Print(L["Nearest: %s"]:format(near.title or r.cat.label))
	end
	FM.Map.MarkDirty()
end

-- the list under the box, for what's typed (q, folded)
local function Search(q)
	wipe(results)
	if q == "" then
		for _, key in ipairs(QUICK) do
			local c = CatOf(key)
			if c then results[#results + 1] = { kind = "near", cat = c, icon = c.icon, label = L["Nearest: %s"]:format(c.label) } end
		end
		return
	end
	if #q < 2 then return end
	-- (the kinds of icon whose name holds it)
	for _, c in ipairs(FM.Pins.CATS) do
		if c.label and (c.group == "townsfolk" or c.group == "professions" or c.key == "flight") and FM.Fold(c.label):find(q, 1, true) then
			results[#results + 1] = { kind = "near", cat = c, icon = c.icon, label = L["Nearest: %s"]:format(c.label) }
		end
	end
	-- (the zones)
	for _, id in ipairs(FM.FOG_ZONES or NONE) do
		local info = C_Map.GetMapInfo and C_Map.GetMapInfo(id)
		local name = info and FM.Plain(info.name)
		if type(name) == "string" and FM.Fold(name):find(q, 1, true) then
			results[#results + 1] = { kind = "zone", zone = id, icon = "Interface\\Icons\\INV_Misc_Map_01", label = name }
		end
	end
	-- (the places)
	local room = MAX_ROWS - #results
	if room > 0 and FM.Labels.SearchPlaces then
		for _, p in ipairs(FM.Labels.SearchPlaces(q, room)) do
			local zi = C_Map.GetMapInfo and C_Map.GetMapInfo(p[4])
			local zn = zi and FM.Plain(zi.name)
			results[#results + 1] = { kind = "place", u = p[1], v = p[2], label = p[3],
				sub = type(zn) == "string" and zn ~= p[3] and zn or nil, icon = "Interface\\AddOns\\AzerothVeil\\Media\\dot" }
		end
	end
end

local function Row(i)
	local r = rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, list)
	r:SetSize(BOX_W + 60, ROW_H)
	r:SetPoint("TOPLEFT", 6, -6 - (i - 1) * ROW_H)
	local hl = r:CreateTexture(nil, "HIGHLIGHT")
	hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	hl:SetBlendMode("ADD")
	hl:SetAllPoints()
	local ic = r:CreateTexture(nil, "ARTWORK")
	ic:SetSize(16, 16)
	ic:SetPoint("LEFT", 2, 0)
	r.icon = ic
	local t = S.Text(r, 11, nil, "ARTWORK")
	t:SetPoint("LEFT", ic, "RIGHT", 6, 0)
	t:SetPoint("RIGHT", -4, 0)
	t:SetJustifyH("LEFT")
	t:SetWordWrap(false)
	r.text = t
	-- (on the button's release, as soon as it's there: before anything else the click sets off)
	r:SetScript("OnMouseUp", function(self, button)
		if button == "LeftButton" and self.result and self:IsMouseOver() then Pick(self.result) end
	end)
	rows[i] = r
	return r
end

local function ShowList()
	local n = math.min(#results, MAX_ROWS)
	for i = 1, n do
		local r, res = Row(i), results[i]
		r.result = res
		S.SetIcon(r.icon, res.icon)
		r.text:SetText(res.sub and (res.label .. " |cff999999(" .. res.sub .. ")|r") or res.label)
		r:Show()
	end
	for i = n + 1, #rows do rows[i]:Hide() end
	if n == 0 then list:Hide() return end
	list:SetHeight(n * ROW_H + 12)
	list:Show()
end

local function Refresh()
	local q = FM.Fold(box:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
	Search(q)
	ShowList()
end

-- the box, made with the map (Map.lua): after anchor, in the map's top left corner; hidden while the option is off
function F.Attach(view, anchor, level)
	rows = {}
	markLayer = CreateFrame("Frame", nil, view)
	markLayer:SetAllPoints()
	markLayer:SetFrameLevel(level - 1)
	local ok, sb = pcall(CreateFrame, "EditBox", nil, view, "SearchBoxTemplate")
	box = ok and sb or CreateFrame("EditBox", nil, view, "InputBoxTemplate")
	S.Friz(box)
	box:SetSize(BOX_W, BOX_H)
	box:SetFrameLevel(level)
	box:SetAutoFocus(false)
	box:SetMaxLetters(60)
	box:SetPoint("LEFT", anchor, "RIGHT", 10, 0)
	if box.Instructions then box.Instructions:SetText(L["Search the map"]) end
	list = CreateFrame("Frame", nil, view, BackdropTemplateMixin and "BackdropTemplate" or nil)
	S.Panel(list)
	list:SetWidth(BOX_W + 72)
	list:SetFrameLevel(level + 5)
	list:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -6, -2)
	list:EnableMouse(true)
	list:Hide()
	box:HookScript("OnTextChanged", function(self, user)
		-- (only what you type: the game's search box sends an empty text of its own as it loses the focus, which
		-- would clear what was just found)
		if user and (self:GetText() or "") == "" then Clear() end
		if self:HasFocus() then Refresh() end
	end)
	box:HookScript("OnEditFocusGained", function() Refresh() end)
	box:HookScript("OnEditFocusLost", function()
		-- (a click on the list's own rows comes after the focus goes: it closes it itself)
		C_Timer.After(0.2, function() if not box:HasFocus() and not list:IsMouseOver() then list:Hide() end end)
	end)
	box:SetScript("OnEnterPressed", function(self)
		if results[1] then Pick(results[1]) else self:ClearFocus() list:Hide() end
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
		list:Hide()
		Clear()
	end)
	if box.clearButton then box.clearButton:HookScript("OnClick", function() Clear() list:Hide() end) end
	F.Apply()
end

-- the Map module's option changed (Modules/Map.lua)
function F.Apply()
	if not box then return end
	local on = FM.db.mapSearch and true or false
	box:SetShown(on)
	if not on then list:Hide() Clear() end
end

-- a mark: the aura the followed quest has (Quests.lua's glow, its colour), the ring the map pings a quest with
-- (Blizzard's minimap ping, growing), and the kind's icon in it
Mark = function()
	local f = FM.Quests.Glow(markLayer, 52)
	local ring = f:CreateTexture(nil, "BORDER")
	ring:SetTexture("Interface/minimap/UI-Minimap-Ping-Expand")
	ring:SetSize(46, 46)
	ring:SetPoint("CENTER")
	local g = f:CreateAnimationGroup()
	g:SetLooping("REPEAT")
	local s = g:CreateAnimation("Scale")
	s:SetTarget(ring)
	s:SetScaleFrom(0.5, 0.5)
	s:SetScaleTo(1.3, 1.3)
	s:SetDuration(1.1)
	local a = g:CreateAnimation("Alpha")
	a:SetTarget(ring)
	a:SetFromAlpha(1)
	a:SetToAlpha(0)
	a:SetDuration(1.1)
	f.ring = g
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetSize(MARK_ICON, MARK_ICON)
	f.icon:SetPoint("CENTER")
	return f
end

-- every pan / zoom (Map.lua): what was found, in the quests' search glow, a kind's icon over it
function F.Layout(left, top, scale)
	if not markLayer then return end
	local n = 0
	for _, m in ipairs(marks) do
		n = n + 1
		local f = markFrames[n]
		if not f then f = Mark() markFrames[n] = f end
		if m[3] then S.SetIcon(f.icon, m[3]) f.icon:Show() else f.icon:Hide() end
		f:ClearAllPoints()
		f:SetPoint("CENTER", markLayer, "TOPLEFT", (m[1] - left) * scale, -(m[2] - top) * scale)
		if not f:IsShown() then f:Show() f.anim:Play() f.ring:Play() end
	end
	for i = n + 1, #markFrames do markFrames[i]:Hide() end
end
