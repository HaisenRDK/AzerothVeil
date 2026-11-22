-- PerfectMap's own chrome, in one of two looks (Options' "Classic style"; asked at the first start):
--  * modern: flat, dark panels, 1px borders, one accent colour; no Blizzard templates;
--  * classic: as WoW Classic draws its windows: the dialog boxes' dark background and gold-edged border,
--    the red panel buttons, check boxes, the options' slider, Blizzard's gold.
-- Everything is drawn in the look set when it's made: a change of look takes a reload (Menu.lua asks).
-- The map art itself is Blizzard's either way.
local _, FM = ...
local S = {}
FM.Style = S

local WHITE = "Interface\\AddOns\\AzerothVeil\\Media\\white"
S.WHITE = WHITE
S.ACCENT = { 0.95, 0.74, 0.32 }
S.BG = { 0.06, 0.065, 0.075, 0.94 }
S.BORDER = { 1, 1, 1, 0.09 }
S.TEXT = { 0.92, 0.92, 0.9 }
S.DIM = { 0.6, 0.6, 0.62 }
S.classic = false
S.used = false                      -- (anything drawn yet: a change of look then takes a reload)

-- the look, from the settings, before anything's drawn (Core.lua, as the settings load). The colours are
-- changed in place: every part reads them as it's made
local LOOKS = {
	modern = { ACCENT = { 0.95, 0.74, 0.32 }, BG = { 0.06, 0.065, 0.075, 0.94 }, BORDER = { 1, 1, 1, 0.09 },
		TEXT = { 0.92, 0.92, 0.9 }, DIM = { 0.6, 0.6, 0.62 } },
	classic = { ACCENT = { 1, 0.82, 0 }, BG = { 0.03, 0.03, 0.03, 1 }, BORDER = { 0.55, 0.45, 0.25, 1 },
		TEXT = { 1, 1, 1 }, DIM = { 0.72, 0.68, 0.6 } },
}
-- how far a window's insides keep from its edge: past its border (classic: the dialog's thick one)
S.INSET = 1
-- the classic look's map window: Blizzard's own (PortraitFrameTemplate: its metal frame, title bar, portrait
-- and close button). Where its insides begin, past the frame and the inset border round the map and the
-- quest log: left, right, top (under the title bar), bottom; and the room between the map and the log
S.FRAME = { l = 7, r = 7, t = 27, b = 7, gap = 8 }
function S.ApplyTheme(style)
	S.classic = style == "classic"
	S.INSET = S.classic and 7 or 1
	for k, v in pairs(LOOKS[S.classic and "classic" or "modern"]) do
		local t = S[k]
		for i = 1, 4 do t[i] = v[i] end
	end
end
function S.Theme() return S.classic and "classic" or "modern" end

-- the classic look's pieces: the dialog boxes' background and border, the tooltip's (for small ones)
local DIALOG_BG = "Interface\\DialogFrame\\UI-DialogBox-Background"
local DIALOG_EDGE = "Interface\\DialogFrame\\UI-DialogBox-Border"
local TIP_BG = "Interface\\Tooltips\\UI-Tooltip-Background"
local TIP_EDGE = "Interface\\Tooltips\\UI-Tooltip-Border"
local function Backdrop(f)
	if not f.SetBackdrop and BackdropTemplateMixin then
		Mixin(f, BackdropTemplateMixin)
		f:HookScript("OnSizeChanged", f.OnBackdropSizeChanged)
	end
	return f.SetBackdrop ~= nil
end
-- (a border over everything inside a frame: its own frame, high above its children, taking no clicks)
local function EdgeOver(f, edge, size)
	local e = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
	e:SetAllPoints()
	e:SetFrameLevel(math.min(f:GetFrameLevel() + 80, 9000))
	e:EnableMouse(false)
	if e.SetBackdrop then
		e:SetBackdrop({ edgeFile = edge, edgeSize = size })
		e:SetBackdropBorderColor(1, 1, 1, 1)
	end
	f.fmEdge = e
	return e
end
S.Backdrop = Backdrop

-- The game's own font: whatever its text is drawn in now (GameFontNormal: a font addon or a
-- different client language changes it there), else the client's standard one. Read again each
-- time the map opens, and every string of ours follows when it changed.
local FALLBACK = "Fonts\\FRIZQT__.TTF"
local current
local registry = setmetatable({}, { __mode = "k" })   -- font string -> { size, flags }

function S.FontPath()
	local path = GameFontNormal and GameFontNormal:GetFont()
	if type(path) ~= "string" or path == "" then path = _G.STANDARD_TEXT_FONT end
	if type(path) ~= "string" or path == "" then path = FALLBACK end
	return path
end

local function Apply(fs, size, flags)
	if not fs:SetFont(current, size, flags) then fs:SetFont(FALLBACK, size, flags) end
end

function S.Font(fs, size, flags)
	current = current or S.FontPath()
	size, flags = size or 12, flags or ""
	-- (already so: nothing done; the quest log sets its rows' fonts at every refresh)
	local r = registry[fs]
	if r and r[1] == size and r[2] == flags and r[3] == current then return fs end
	if r then r[1], r[2], r[3], r[4] = size, flags, current, nil else registry[fs] = { size, flags, current } end
	Apply(fs, size, flags)
	fs:SetShadowOffset(1, -1)
	fs:SetShadowColor(0, 0, 0, 0.8)
	return fs
end

function S.RefreshFonts()
	local path = S.FontPath()
	if path == current then return end
	current = path
	for fs, a in pairs(registry) do
		if not a[4] then Apply(fs, a[1], a[2]) a[3] = path end      -- (AzerothVeil: the game's font objects' kept)
	end
end

-- AzerothVeil: a font string in one of the game's own font objects' face, size and flags (QuestTitleFont,
-- QuestFont, QuestFontNormalSmall: a quest's page as Blizzard writes it), read from the object as the game has it
-- now; else ours at that size. Its shadow left as it is
function S.GameFont(fs, name, size)
	local obj = _G[name]
	local file, h, flags
	if obj and obj.GetFont then file, h, flags = obj:GetFont() end
	if type(file) ~= "string" or file == "" or type(h) ~= "number" then return S.Font(fs, size) end
	flags = flags or ""
	local r = registry[fs]
	if r and r[1] == h and r[2] == flags and r[3] == file then return fs end
	if r then r[1], r[2], r[3], r[4] = h, flags, file, true else registry[fs] = { h, flags, file, true } end
	if not fs:SetFont(file, h, flags) then fs:SetFont(FALLBACK, h, flags) end
	return fs
end

function S.Text(parent, size, color, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	S.Font(fs, size)
	local c = color or S.TEXT
	fs:SetTextColor(c[1], c[2], c[3])
	return fs
end

-- background + 1px border on any frame (classic: the dialog boxes' background and border; big: the
-- dialog's own thick gold-edged border, else the tooltip's thinner one)
function S.Panel(f, bg, border, big)
	S.used = true
	bg = bg or S.BG
	border = border or S.BORDER
	if S.classic and Backdrop(f) then
		-- (opaque: the dialog's background over solid black, nothing of the world through it)
		local under = f:CreateTexture(nil, "BACKGROUND", nil, -8)
		under:SetColorTexture(0, 0, 0, 1)
		under:SetPoint("TOPLEFT", 3, -3)
		under:SetPoint("BOTTOMRIGHT", -3, 3)
		f:SetBackdrop({ bgFile = DIALOG_BG, tile = true, tileSize = 32, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
		f:SetBackdropColor(1, 1, 1, 1)
		if f.Center then f.Center:SetDrawLayer("BACKGROUND", -7) end   -- (the dialog's background over the black)
		if big then EdgeOver(f, DIALOG_EDGE, 24) else EdgeOver(f, TIP_EDGE, 14) end
		return f
	end
	local t = f:CreateTexture(nil, "BACKGROUND", nil, -8)
	t:SetTexture(WHITE)
	t:SetVertexColor(bg[1], bg[2], bg[3], bg[4] or 1)
	t:SetAllPoints()
	f.fmBg = t
	local function Line(p1, p2, w, h)
		local l = f:CreateTexture(nil, "BORDER", nil, 7)
		l:SetTexture(WHITE)
		l:SetVertexColor(border[1], border[2], border[3], border[4] or 1)
		l:SetPoint(p1)
		l:SetPoint(p2)
		if w then l:SetWidth(w) else l:SetHeight(h) end
		return l
	end
	Line("TOPLEFT", "TOPRIGHT", nil, 1)
	Line("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
	Line("TOPLEFT", "BOTTOMLEFT", 1, nil)
	Line("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
	return f
end

-- the classic look's buttons, by kind:
--  "action" (a button with words): the red panel button;
--  "icon" (a button with an icon on it): a small dark square in the tooltip's border;
--  "round" (a button on the map): round, as the minimap's and the world map's own;
--  "row" (an entry of a list): plain, lit as the classic quest log lights its titles.
-- Each has what the flat one has (label, bg, tip, SetActive), so the rest of the map treats them alike.
local function ClassicButton(parent, label, width, height, onClick, kind)
	local b
	if kind == "action" then
		b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
		b:SetSize(width or 80, height or 20)
		b:SetText(label)
		b.label = b:GetFontString()
	else
		b = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
		b:SetSize(width or 80, height or 20)
		-- (the map's own buttons, "round" in the modern look: as the other classic icon buttons, a dark square
		-- in the tooltip's gold border, the same size as the flat one and its icon in the middle)
		if (kind == "icon" or kind == "round") and b.SetBackdrop then
			b:SetBackdrop({ bgFile = TIP_BG, edgeFile = TIP_EDGE, tile = true, tileSize = 8, edgeSize = 10,
				insets = { left = 2, right = 2, top = 2, bottom = 2 } })
			b:SetBackdropColor(0.08, 0.07, 0.06, 0.95)
			b:SetBackdropBorderColor(0.8, 0.68, 0.45, 1)
			b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		else
			b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		end
		local fs = S.Text(b, 11, kind == "row" and S.ACCENT or nil)
		fs:SetPoint("CENTER")
		fs:SetText(label)
		b.label = fs
	end
	-- (what the flat one's background was set to by the rest of the map: kept, unseen)
	b.bg = b:CreateTexture(nil, "BACKGROUND", nil, -8)
	b.bg:SetAlpha(0)
	b:HookScript("OnEnter", function(self) if self.tip then S.ShowTip(self, self.tip) end end)
	b:HookScript("OnLeave", function() S.HideTip() end)
	if onClick then b:SetScript("OnClick", onClick) end
	function b:SetActive(on)
		self.fmActive = on
		if on then self:LockHighlight() else self:UnlockHighlight() end
		if kind ~= "action" then
			local c = on and S.ACCENT or (kind == "row" and S.ACCENT or S.TEXT)
			self.label:SetTextColor(c[1], c[2], c[3])
		end
	end
	return b
end

-- a button: flat (modern), or as kind asks in the classic look (the default: "action" with words, else "icon")
function S.Button(parent, label, width, height, onClick, kind)
	S.used = true
	if S.classic then
		return ClassicButton(parent, label, width, height, onClick, kind or ((label and label ~= "") and "action" or "icon"))
	end
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width or 80, height or 20)
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture(WHITE)
	bg:SetAllPoints()
	bg:SetVertexColor(1, 1, 1, 0.05)
	b.bg = bg
	local fs = S.Text(b, 11)
	fs:SetPoint("CENTER")
	fs:SetText(label)
	b.label = fs
	b:SetScript("OnEnter", function(self)
		self.bg:SetVertexColor(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 0.25)
		if self.tip then S.ShowTip(self, self.tip) end
	end)
	b:SetScript("OnLeave", function(self)
		self.bg:SetVertexColor(1, 1, 1, self.fmActive and 0.14 or 0.05)
		S.HideTip()
	end)
	b:SetScript("OnClick", onClick)
	function b:SetActive(on)
		self.fmActive = on
		self.bg:SetVertexColor(1, 1, 1, on and 0.14 or 0.05)
		self.label:SetTextColor(on and S.ACCENT[1] or S.TEXT[1], on and S.ACCENT[2] or S.TEXT[2], on and S.ACCENT[3] or S.TEXT[3])
	end
	return b
end

-- a row with an optional icon, a label and a flat switch; the whole row toggles
function S.SwitchRow(parent, label, icon, get, set, width)
	local r = CreateFrame("Button", nil, parent)
	r:SetSize(width or 200, 22)
	local hl = r:CreateTexture(nil, "BACKGROUND")
	hl:SetTexture(WHITE)
	hl:SetAllPoints()
	hl:SetVertexColor(1, 1, 1, 0)
	local x = 4
	if icon then
		local ic = r:CreateTexture(nil, "ARTWORK")
		ic:SetSize(16, 16)
		ic:SetPoint("LEFT", 4, 0)
		S.SetIcon(ic, icon)
		r.icon = ic
		x = 26
	end
	local fs = S.Text(r, 11)
	fs:SetPoint("LEFT", x, 0)
	fs:SetPoint("RIGHT", -40, 0)
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(false)
	fs:SetText(label)
	local track = r:CreateTexture(nil, "ARTWORK")
	track:SetTexture(WHITE)
	track:SetSize(28, 12)
	track:SetPoint("RIGHT", -6, 0)
	local knob = r:CreateTexture(nil, "OVERLAY")
	knob:SetTexture(WHITE)
	knob:SetSize(10, 10)
	-- (classic: AzerothVeil: Blizzard's own check box, UICheckButtonTemplate, on the left as in the game's
	-- options, then the icon and the label in white; the whole row toggles it)
	local check
	if S.classic then
		track:Hide()
		knob:Hide()
		check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
		check:SetSize(24, 24)
		check:SetPoint("LEFT", 0, 0)
		check:SetScript("OnClick", function() r:Click() end)
		check:SetScript("OnEnter", function() r:GetScript("OnEnter")(r) end)
		check:SetScript("OnLeave", function() r:GetScript("OnLeave")(r) end)
		r.check = check
		local x2 = 26
		if r.icon then
			r.icon:ClearAllPoints()
			r.icon:SetPoint("LEFT", x2, 0)
			x2 = x2 + 20
		end
		fs:ClearAllPoints()
		fs:SetPoint("LEFT", x2, 0)
		fs:SetPoint("RIGHT", -4, 0)
		fs:SetTextColor(1, 1, 1)
		r.label = fs
	end
	function r:Refresh()
		local on = get()
		if check then
			check:SetChecked(on and true or false)
		elseif on then
			track:SetVertexColor(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 0.9)
			knob:SetVertexColor(1, 1, 1, 1)
			knob:SetPoint("CENTER", track, "CENTER", 8, 0)
		else
			track:SetVertexColor(1, 1, 1, 0.15)
			knob:SetVertexColor(0.75, 0.75, 0.75, 1)
			knob:SetPoint("CENTER", track, "CENTER", -8, 0)
		end
	end
	-- (greyed out: Blizzard's disabled check box and grey label; Engine/Menu.lua's Greyable)
	function r:SetGreyed(off)
		if check then
			check:SetEnabled(not off)
			fs:SetTextColor(off and 0.5 or 1, off and 0.5 or 1, off and 0.5 or 1)
			if self.icon then self.icon:SetDesaturated(off and true or false) end
		end
	end
	r:SetScript("OnClick", function(self)
		set(not get())
		self:Refresh()
	end)
	r:SetScript("OnEnter", function(self)
		hl:SetVertexColor(1, 1, 1, 0.05)
		if self.tip then S.ShowTip(self, self.tip) end
	end)
	r:SetScript("OnLeave", function() hl:SetVertexColor(1, 1, 1, 0) S.HideTip() end)
	r:Refresh()
	return r
end

-- flat slider: an optional icon, label, value text, a thin bar with a square thumb
function S.Slider(parent, label, minV, maxV, step, get, set, fmt, width, icon)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(width or 200, 34)
	local fs = S.Text(f, 11)
	if icon then
		local ic = f:CreateTexture(nil, "ARTWORK")
		ic:SetSize(16, 16)
		ic:SetPoint("TOPLEFT", 4, 0)
		S.SetIcon(ic, icon)
		fs:SetPoint("TOPLEFT", 26, -2)
	else
		fs:SetPoint("TOPLEFT", 4, -2)
	end
	fs:SetText(label)
	local val = S.Text(f, 11, S.ACCENT)
	val:SetPoint("TOPRIGHT", -6, -2)
	local s = CreateFrame("Slider", nil, f, (S.classic and BackdropTemplateMixin) and "BackdropTemplate" or nil)
	s:SetOrientation("HORIZONTAL")
	s:SetPoint("BOTTOMLEFT", 4, 4)
	s:SetPoint("BOTTOMRIGHT", -6, 4)
	s:SetHeight(12)
	if S.classic and s.SetBackdrop then
		-- (classic: the game's options slider, its bar and its thumb)
		s:SetHeight(17)
		s:SetBackdrop({ bgFile = "Interface\\Buttons\\UI-SliderBar-Background", edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
			tile = true, tileSize = 8, edgeSize = 8, insets = { left = 3, right = 3, top = 6, bottom = 6 } })
		s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
		local th = s:GetThumbTexture()
		if th then th:SetSize(32, 32) end
	else
		local bar = s:CreateTexture(nil, "BACKGROUND")
		bar:SetTexture(WHITE)
		bar:SetVertexColor(1, 1, 1, 0.15)
		bar:SetPoint("LEFT")
		bar:SetPoint("RIGHT")
		bar:SetHeight(3)
		local thumb = s:CreateTexture(nil, "OVERLAY")
		thumb:SetTexture(WHITE)
		thumb:SetVertexColor(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 1)
		thumb:SetSize(8, 12)
		s:SetThumbTexture(thumb)
	end
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step)
	s:SetObeyStepOnDrag(true)
	local function Show(v) val:SetText((fmt or "%.2f"):format(v)) end
	s:SetValue(get())
	Show(get())
	s:SetScript("OnValueChanged", function(_, v)
		v = math.floor(v / step + 0.5) * step
		Show(v)
		set(v)
	end)
	return f
end

-- an icon spec: "atlas:Name", a file path, or a file ID
-- A click on this frame (an icon on the map) also reaches the map under it, so a drag starting on it
-- still moves the map. The game allows setting that only out of combat: in combat it waits for the end
-- (set then, the call failed with "Interface action failed because of an AddOn")
local passWaiting = {}
local passEvents = CreateFrame("Frame")
passEvents:SetScript("OnEvent", function(self)
	for f in pairs(passWaiting) do f:SetPropagateMouseClicks(true) passWaiting[f] = nil end
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
end)
function S.PassClicks(f)
	if not f.SetPropagateMouseClicks then return end
	if InCombatLockdown() then
		passWaiting[f] = true
		passEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
	else
		f:SetPropagateMouseClicks(true)
	end
end

function S.SetIcon(tex, icon)
	if type(icon) == "string" and icon:sub(1, 6) == "atlas:" then
		tex:SetAtlas(icon:sub(7))
	else
		tex:SetTexture(icon)
		tex:SetTexCoord(0, 1, 0, 1)
	end
end

---------------------------------------------------------------------------
-- Tooltips: the game's own (GameTooltip), for every text shown on mouse-over, the same box the
-- boat routes', Blizzard's quest pins' and Questie's use (and whatever skins it, skins ours too)
---------------------------------------------------------------------------
local owned                              -- the frame our tooltip shows for (to hide only ours)

-- lines: a string, or a list of { text, r, g, b } / strings (the first is the title; " " a gap).
-- Shown beside owner, or at (anchorX, anchorY) from rel's top-left (pins: it stays on them)
function S.ShowTip(owner, lines, anchorX, anchorY, rel)
	if type(lines) == "string" then lines = { lines } end
	local tt = GameTooltip
	if rel then
		tt:SetOwner(rel, "ANCHOR_NONE")
		tt:ClearAllPoints()
		tt:SetPoint("BOTTOMLEFT", rel, "TOPLEFT", anchorX, anchorY)
	elseif owner then
		tt:SetOwner(owner, "ANCHOR_RIGHT")
	else
		tt:SetOwner(UIParent, "ANCHOR_CURSOR")
	end
	for i, line in ipairs(lines) do
		local text, r, g, b = line, nil, nil, nil
		if type(line) == "table" then text, r, g, b = line[1], line[2], line[3], line[4] end
		if i == 1 then
			tt:SetText(text, r or 1, g or 0.82, b or 0)
		elseif text == " " then
			tt:AddLine(" ")
		else
			tt:AddLine(text, r or 1, g or 1, b or 1, true)
		end
	end
	tt:Show()
	owned = tt:GetOwner()
end

function S.MoveTip(x, y, rel)
	local tt = GameTooltip
	if not tt:IsShown() or tt:GetOwner() ~= rel then return end
	tt:ClearAllPoints()
	tt:SetPoint("BOTTOMLEFT", rel, "TOPLEFT", x, y)
end

function S.HideTip()
	if owned and GameTooltip:GetOwner() == owned then GameTooltip:Hide() end
	owned = nil
end
