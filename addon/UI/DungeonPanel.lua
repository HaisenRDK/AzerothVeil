-- AzerothVeil — UI/DungeonPanel.lua
-- The side panel while a dungeon's map is up (Modules/Dungeons.lua shows and hides it): in the quest
-- log's place beside the map, drawn as it is (the dialogs' dark background, Blizzard's inset border, the
-- game's fonts and scroll bar). AzerothVeil: two pages, no tabs:
--   the dungeon's  its quests first (those of your log; with Questie's data, all of them), their state and
--                  progress as the game gives them; a click unfolds what it asks and its rewards (the game's own
--                  tooltips); Shift-click: its link in chat. Then its bosses (portrait with its dragon as on the
--                  map, level in a gold circle, floor): a click opens that boss's page.
--   a boss's       every boss's portrait down its left (a click: that one's page), the boss picked (its floor up on
--                  the map, its marker lit) and its loot (DungeonJournal's, when it's installed).
-- At its top: the dungeon's name (on a boss's page, a click goes back to the dungeon's), and beside it the dungeon
-- entrance's own icon: a click shows the world map, on you, and glides to the entrance.
-- Quests with Questie's data when that option is on (Integrations/Questie.lua): a line each, "(level)
-- Name" (green: done; yellow: to do), the book when it's in your log, its faction's and classes' icons
-- when every quest is listed (not only yours); a click: what
-- it asks, its giver, its rewards (yours), a button to its start on the world map (marked there). The panel is at the map's
-- right: its tooltips open on its left. Built the first time; nothing runs while it's hidden.
local _, ns = ...
local L = ns.L
local S = ns.Style

local P = {}
ns.DungeonPanel = P

local PAD, ROW = 10, 18
local HEAD_H = 56                -- the header: the entrance's icon, the dungeon's name, its levels
local STRIP_W, STRIP_ICON = 44, 34   -- a boss's page: every boss's portrait down its left
local frame, title, levels, scroll, child, empty, note
local nameButton, backArrow, entranceButton, strip
local stripButtons = {}
local pool, used = {}, {}
local module, inst
local page = "dungeon"          -- "dungeon" (its quests and bosses), "boss" (selectedBoss's), "quest" (selectedQuest's)
local selectedQuest
local selectedBoss
local pending = false

---------------------------------------------------------------------------
-- Pieces, pooled: each refresh puts them back and takes what it needs
---------------------------------------------------------------------------
local MEDIA = "Interface\\AddOns\\AzerothVeil\\Media\\"
local DRAGONS = { [2] = "dragon_rare-elite", [4] = "dragon_rare" }   -- (else the elite's, gold)
local BOSS_PORTRAIT = 44                 -- a boss's portrait
local BOSS_X, BOSS_Y = 34, 32            -- its centre in its row (room for its dragon above and on the left)
local BOSS_TEXT = 92                     -- its name, clear of its dragon's wing
local BOSS_ROW = 68                      -- a row, then the next
local LOOT_ICON = 34

-- the game's tooltip beside a line of the panel, its top right corner at the line's top left (the panel
-- is at the map's right: the tooltip on the map's side, level with what it's about)
local function TipBeside(owner)
	GameTooltip:SetOwner(owner, "ANCHOR_NONE")
	GameTooltip:ClearAllPoints()
	GameTooltip:SetPoint("TOPRIGHT", owner, "TOPLEFT", -4, 0)
end

local function Take(kind)
	pool[kind] = pool[kind] or {}
	local f = table.remove(pool[kind])
	if not f then
		if kind == "text" then
			f = S.FontString(child, "ARTWORK", "GameFontHighlightSmall")
			f:SetJustifyH("LEFT")
			f:SetWordWrap(true)
		elseif kind == "row" then
			f = CreateFrame("Button", nil, child)
			f:RegisterForClicks("LeftButtonUp")
			f:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
			f.sel = f:CreateTexture(nil, "BACKGROUND")
			f.sel:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
			f.sel:SetBlendMode("ADD")
			f.sel:SetVertexColor(1, 0.82, 0, 0.5)
			f.sel:SetAllPoints()
			f.icon = f:CreateTexture(nil, "ARTWORK")
			f.icon:SetSize(16, 16)
			f.icon:SetPoint("LEFT", 2, 0)
			f.text = S.FontString(f, "ARTWORK", "GameFontNormal")
			f.text:SetPoint("LEFT", f.icon, "RIGHT", 4, 0)
			f.text:SetJustifyH("LEFT")
			f.text:SetWordWrap(false)
			-- (at its end: the book when it's in your log; its faction's and classes' icons: QuestMarks)
			f.log = f:CreateTexture(nil, "ARTWORK")
			f.log:SetSize(15, 15)
			f.log:SetTexture("Interface\\QuestFrame\\UI-QuestLog-BookIcon")
			f.marks = {}
		elseif kind == "quest" then
			-- a quest: its icon, "(level) Name" and its marks on its first line, what's said of it under it
			f = CreateFrame("Button", nil, child)
			f:RegisterForClicks("LeftButtonUp")
			f:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
			f.sel = f:CreateTexture(nil, "BACKGROUND")
			f.sel:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
			f.sel:SetBlendMode("ADD")
			f.sel:SetVertexColor(1, 0.82, 0, 0.5)
			f.sel:SetAllPoints()
			f.icon = f:CreateTexture(nil, "ARTWORK")
			f.icon:SetSize(16, 16)
			f.icon:SetPoint("TOPLEFT", 2, -4)
			f.text = S.FontString(f, "ARTWORK", "GameFontNormal")
			f.text:SetPoint("TOPLEFT", 22, -5)
			f.text:SetJustifyH("LEFT")
			f.text:SetWordWrap(true)
			f.sub = S.FontString(f, "ARTWORK", "GameFontHighlightSmall")
			f.sub:SetPoint("TOPLEFT", f.text, "BOTTOMLEFT", 0, -2)
			f.sub:SetJustifyH("LEFT")
			f.sub:SetWordWrap(true)
			f.sub:SetTextColor(0.75, 0.75, 0.75)
			f.log = f:CreateTexture(nil, "ARTWORK")
			f.log:SetTexture("Interface\\QuestFrame\\UI-QuestLog-BookIcon")
			f.marks = {}
		elseif kind == "title" then
			f = S.FontString(child, "ARTWORK", "GameFontNormalLarge")
			f:SetJustifyH("LEFT")
			f:SetWordWrap(true)
		elseif kind == "section" then
			f = CreateFrame("Button", nil, child)
			f:SetHeight(22)
			f:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
			f.sign = f:CreateTexture(nil, "ARTWORK")
			f.sign:SetSize(16, 16)
			f.sign:SetPoint("LEFT", 2, 0)
			f.text = S.FontString(f, "ARTWORK", "GameFontNormalLarge")
			f.text:SetPoint("LEFT", f.sign, "RIGHT", 6, 0)
			f.text:SetJustifyH("LEFT")
		elseif kind == "bandtitle" then
			f = S.FontString(child, "ARTWORK", "GameFontNormalLarge")
			f:SetJustifyH("CENTER")
		elseif kind == "band" then
			-- the rewards' dark band, as Blizzard's quest page and the quest log's (Engine/QuestLog.lua): the whole
			-- width, a thin gold line along its top
			f = CreateFrame("Frame", nil, child)
			local bg = f:CreateTexture(nil, "BACKGROUND")
			bg:SetColorTexture(0.11, 0.08, 0.05, 1)
			bg:SetAllPoints()
			local line = f:CreateTexture(nil, "BORDER")
			line:SetColorTexture(0.62, 0.5, 0.3, 1)
			line:SetPoint("TOPLEFT")
			line:SetPoint("TOPRIGHT")
			line:SetHeight(1)
		elseif kind == "bigitem" then
			-- a reward: Blizzard's own button of its quest page (the icon, its name in a frame beside it), as the
			-- quest log's; else a plain one in the same layout
			local ok, b = pcall(CreateFrame, "Button", nil, child, "LargeItemButtonTemplate")
			if ok and b and b.Icon and b.Name then
				f = b
			else
				if ok and b then b:Hide() end
				f = CreateFrame("Button", nil, child)
				f.Icon = f:CreateTexture(nil, "ARTWORK")
				f.Icon:SetSize(36, 36)
				f.Icon:SetPoint("LEFT", 2, 0)
				f.Name = S.FontString(f, "ARTWORK", "GameFontHighlightSmall")
				f.Name:SetPoint("LEFT", f.Icon, "RIGHT", 6, 0)
				f.Name:SetPoint("RIGHT", -2, 0)
				f.Name:SetJustifyH("LEFT")
			end
			if not f.Count then
				f.Count = S.FontString(f, "OVERLAY", "NumberFontNormal")
				f.Count:SetPoint("BOTTOMRIGHT", f.Icon, "BOTTOMRIGHT", -1, 1)
			end
			S.Friz(f.Name)
			f.Name:SetShadowColor(0, 0, 0, 0.8)
			f.Name:SetShadowOffset(1, -1)
			f:RegisterForClicks("LeftButtonUp")
			f:SetScript("OnEnter", function(self)
				ns.QuestLog.RewardTooltip(self, self.kindOf, self.index, self.questID, self.label, self.currency)
				-- (beside the panel, on the map's side, as the rest of its tooltips)
				GameTooltip:ClearAllPoints()
				GameTooltip:SetPoint("TOPRIGHT", self, "TOPLEFT", -4, 0)
			end)
			f:SetScript("OnLeave", GameTooltip_Hide)
			f:SetScript("OnClick", function(self)
				local link = self.kindOf ~= "spell" and GetQuestLogItemLink and GetQuestLogItemLink(self.kindOf, self.index)
				if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
			end)
		elseif kind == "boss" then
			-- its portrait in a ring, a dragon round it (the map's boss pins', Engine/Dungeon.lua: the same
			-- picture, a 64-pixel portrait's), its level in a gold circle at its bottom left
			f = CreateFrame("Button", nil, child)
			f:RegisterForClicks("LeftButtonUp")
			f:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
			f.sel = f:CreateTexture(nil, "BACKGROUND")
			f.sel:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
			f.sel:SetBlendMode("ADD")
			f.sel:SetVertexColor(1, 0.82, 0, 0.5)
			f.sel:SetAllPoints()
			local k = BOSS_PORTRAIT / 64
			f.portrait = f:CreateTexture(nil, "ARTWORK")
			f.portrait:SetSize(BOSS_PORTRAIT, BOSS_PORTRAIT)
			f.portrait:SetPoint("CENTER", f, "TOPLEFT", BOSS_X, -BOSS_Y)
			f.ring = f:CreateTexture(nil, "OVERLAY", nil, 1)
			f.ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
			f.ring:SetTexCoord(0, 0.6, 0, 0.6)
			f.ring:SetSize(BOSS_PORTRAIT * 1.55, BOSS_PORTRAIT * 1.55)
			f.ring:SetPoint("CENTER", f.portrait, "CENTER")
			f.dragon = f:CreateTexture(nil, "OVERLAY", nil, 2)
			f.dragon:SetSize(256 * k, 128 * k)
			f.dragon:SetPoint("CENTER", f.portrait, "CENTER", -54 * k, -20 * k)
			f.badge = CreateFrame("Frame", nil, f)
			f.badge:SetSize(20, 20)
			f.badge:SetFrameLevel(f:GetFrameLevel() + 2)
			f.badge:SetPoint("CENTER", f.portrait, "CENTER", -BOSS_PORTRAIT * 0.36, -BOSS_PORTRAIT * 0.36)
			f.badgeRing = f.badge:CreateTexture(nil, "BORDER")
			f.badgeRing:SetTexture(MEDIA .. "dot")
			f.badgeRing:SetVertexColor(1, 0.78, 0.2)
			f.badgeRing:SetAllPoints()
			f.badgeFill = f.badge:CreateTexture(nil, "ARTWORK")
			f.badgeFill:SetTexture(MEDIA .. "dot")
			f.badgeFill:SetVertexColor(0.08, 0.05, 0.02)
			f.badgeFill:SetPoint("TOPLEFT", 2, -2)
			f.badgeFill:SetPoint("BOTTOMRIGHT", -2, 2)
			f.badgeText = S.FontString(f.badge, "OVERLAY", "GameFontHighlightSmall")
			f.badgeText:SetPoint("CENTER", 0.5, 0)
			local font, _, flags = f.badgeText:GetFont()
			if font then f.badgeText:SetFont(font, 9, flags) end
			f.badgeSkull = f.badge:CreateTexture(nil, "OVERLAY")
			f.badgeSkull:SetSize(13, 13)
			f.badgeSkull:SetPoint("CENTER")
			f.badgeSkull:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
			f.text = S.FontString(f, "ARTWORK", "GameFontNormalLarge")
			f.text:SetPoint("LEFT", f, "TOPLEFT", BOSS_TEXT, -BOSS_Y + 1)
			f.text:SetPoint("RIGHT", -4, 0)
			f.text:SetJustifyH("LEFT")
			f.text:SetWordWrap(false)
			f.sub = S.FontString(f, "ARTWORK", "GameFontDisable")
			f.sub:SetPoint("TOPLEFT", f.text, "BOTTOMLEFT", 0, -3)
		elseif kind == "loot" then
			f = CreateFrame("Button", nil, child)
			f:RegisterForClicks("LeftButtonUp")
			f.edge = f:CreateTexture(nil, "BORDER")
			f.edge:SetTexture("Interface\\Buttons\\WHITE8X8")
			f.edge:SetSize(LOOT_ICON + 2, LOOT_ICON + 2)
			f.edge:SetPoint("LEFT", 0, 0)
			f.icon = f:CreateTexture(nil, "ARTWORK")
			f.icon:SetSize(LOOT_ICON, LOOT_ICON)
			f.icon:SetPoint("CENTER", f.edge, "CENTER")
			f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			f.text = S.FontString(f, "ARTWORK", "GameFontHighlight")
			f.text:SetPoint("TOPLEFT", f.edge, "TOPRIGHT", 8, -4)
			f.text:SetPoint("RIGHT", 0, 0)
			f.text:SetJustifyH("LEFT")
			f.text:SetWordWrap(false)
			f.sub = S.FontString(f, "ARTWORK", "GameFontDisableSmall")
			f.sub:SetPoint("TOPLEFT", f.text, "BOTTOMLEFT", 0, -3)
			f:SetScript("OnEnter", function(self)
				TipBeside(self)
				if not pcall(GameTooltip.SetItemByID, GameTooltip, self.itemID) then GameTooltip:SetText(self.text:GetText() or "") end
				GameTooltip:Show()
			end)
			f:SetScript("OnLeave", GameTooltip_Hide)
			f:SetScript("OnClick", function(self)
				local link = C_Item and C_Item.GetItemInfo and select(2, C_Item.GetItemInfo(self.itemID))
				if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
			end)
		elseif kind == "button" then
			f = CreateFrame("Button", nil, child, "UIPanelButtonTemplate")
			S.FrizButton(f)   -- (AzerothVeil: Friz Quadrata)
			f:SetSize(190, 22)
		elseif kind == "item" then
			f = CreateFrame("Button", nil, child)
			f:SetSize(28, 28)
			f.icon = f:CreateTexture(nil, "ARTWORK")
			f.icon:SetAllPoints()
			f.count = S.FontString(f, "OVERLAY", "NumberFontNormal")
			f.count:SetPoint("BOTTOMRIGHT", -1, 1)
			f:SetScript("OnEnter", function(self)
				ns.QuestLog.RewardTooltip(self, self.kind, self.index, self.questID, self.label, self.currency)
			end)
			f:SetScript("OnLeave", GameTooltip_Hide)
		end
		f.kind = kind
	end
	f:ClearAllPoints()
	f:Show()
	used[#used + 1] = f
	return f
end

local function ReleaseAll()
	for _, f in ipairs(used) do
		f:Hide()
		local k = f.kind
		pool[k] = pool[k] or {}
		table.insert(pool[k], f)
	end
	wipe(used)
end

local function Line(text, y, indent, r, g, b)
	local fs = Take("text")
	fs:SetPoint("TOPLEFT", PAD + (indent or 0), -y)
	fs:SetWidth(child:GetWidth() - 2 * PAD - (indent or 0))
	fs:SetText(text)
	fs:SetTextColor(r or 1, g or 1, b or 1)
	return y + fs:GetStringHeight() + 3
end

-- a title in a page: "Loot", "Quest chain (4)"
local function Heading(text, n, y)
	local fs = Take("text")
	fs:SetPoint("TOPLEFT", PAD, -y)
	fs:SetWidth(child:GetWidth() - 2 * PAD)
	fs:SetText(n and ("%s  |cff9d9d9d(%d)|r"):format(text, n) or text)
	fs:SetTextColor(1, 0.82, 0)
	return y + fs:GetStringHeight() + 6
end

-- the dungeon's page's sections, folding: their state kept (FM.db.dungeonPanelFolded)
local function Folded()
	ns.db.dungeonPanelFolded = type(ns.db.dungeonPanelFolded) == "table" and ns.db.dungeonPanelFolded or {}
	return ns.db.dungeonPanelFolded
end

-- a section's title, a button: Blizzard's plus or minus before it, its count after it; a click folds it or opens
-- it. Returns where what's under it goes, and whether it's folded (shut: folded until it's opened once)
local function Section(key, text, n, y, shut)
	local b = Take("section")
	b:SetPoint("TOPLEFT", PAD - 4, -y)
	b:SetPoint("RIGHT", child, "RIGHT", -PAD, 0)
	local state = Folded()[key]
	local folded
	if state == nil then folded = shut and true or false else folded = state and true or false end
	b.sign:SetTexture(folded and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
	b.text:SetText(n and ("%s  |cff9d9d9d(%d)|r"):format(text, n) or text)
	b:SetScript("OnClick", function()
		Folded()[key] = not folded
		P.Refresh()
	end)
	return y + 26, folded
end

local function Colour(level)
	local c = level and GetQuestDifficultyColor and GetQuestDifficultyColor(level)
	if c then return c.r, c.g, c.b end
	return 1, 0.82, 0
end

---------------------------------------------------------------------------
-- The tabs' contents
---------------------------------------------------------------------------
-- each state: its icon (the game's quest marks) and its words
-- a quest's icon: done, a tick; ready to hand in, the yellow "?"; else the "!" (greyed: not yet for you)
local function QuestIcon(q)
	if q.status == "done" then return "Interface\\RaidFrame\\ReadyCheck-Ready", false end
	if q.status == "complete" then return "Interface\\GossipFrame\\ActiveQuestIcon", false end
	if q.status == "failed" then return "Interface\\RaidFrame\\ReadyCheck-NotReady", false end
	return "Interface\\GossipFrame\\AvailableQuestIcon", q.status == "locked"
end

local FACTION_ICON = { Alliance = "Interface\\FriendsFrame\\PlusManz-Alliance", Horde = "Interface\\FriendsFrame\\PlusManz-Horde" }
local CLASS_ICONS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes"
local CLASS_TOKEN = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID" }

-- the end of a quest's first line, right to left: the book (in your log), then (when every quest is listed, not only
-- yours) its faction's emblem and its classes' icons. Returns how wide they are, for its name to stop before them
local function QuestMarks(row, q, showWho)
	local right, w = nil, 0
	local function Put(t, size)
		t:SetSize(size, size)
		t:ClearAllPoints()
		if right then t:SetPoint("RIGHT", right, "LEFT", -1, 0) else t:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, -4) end
		t:Show()
		right, w = t, w + size + 1
	end
	if q.inLog then Put(row.log, 15) else row.log:Hide() end
	local n = 0
	local function Mark()
		n = n + 1
		local t = row.marks[n]
		if not t then t = row:CreateTexture(nil, "ARTWORK") row.marks[n] = t end
		t:SetTexCoord(0, 1, 0, 1)
		return t
	end
	if showWho then
		for i = #(q.classes or {}), 1, -1 do
			local token = CLASS_TOKEN[q.classes[i]]
			local c = token and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token]
			if c then
				local t = Mark()
				t:SetTexture(CLASS_ICONS)
				t:SetTexCoord(c[1], c[2], c[3], c[4])
				Put(t, 14)
			end
		end
		if FACTION_ICON[q.faction or ""] then
			local t = Mark()
			t:SetTexture(FACTION_ICON[q.faction])
			Put(t, 16)
		end
	end
	for i = n + 1, #row.marks do row.marks[i]:Hide() end
	return w
end

-- who a quest is for, said in its tooltip: "Alliance", "Mage, Warlock"... (the game's own names)
local function WhoFor(q)
	local parts = {}
	if q.faction then parts[#parts + 1] = q.faction == "Alliance" and (FACTION_ALLIANCE or "Alliance") or (FACTION_HORDE or "Horde") end
	for _, id in ipairs(q.classes or {}) do
		local token = CLASS_TOKEN[id]
		parts[#parts + 1] = token and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token] or token
	end
	return #parts > 0 and table.concat(parts, ", ") or nil
end

-- (a quest for the other faction, or for other classes)
local function NotMine(q)
	local myFaction = UnitFactionGroup and UnitFactionGroup("player")
	if q.faction and myFaction and q.faction ~= myFaction then return true end
	local myClass = UnitClass and select(3, UnitClass("player"))
	if q.classes and myClass then
		for _, c in ipairs(q.classes) do if c == myClass then return false end end
		return true
	end
	return false
end

-- a quest's state in words, and its colour
local function StatusText(q)
	if q.status == "done" then return L["Done"], 0.25, 0.9, 0.25 end
	if q.status == "complete" then return L["Ready to hand in"], 1, 0.82, 0 end
	if q.status == "failed" then return L["Failed"], 1, 0.3, 0.3 end
	if q.status == "active" then return L["In your quest log"], 0.55, 0.8, 1 end
	if q.status == "available" then return L["You can take it"], 0.25, 0.9, 0.25 end
	local level = UnitLevel and UnitLevel("player") or 0
	if q.reqLevel and q.reqLevel > level then return L["Required level %d"]:format(q.reqLevel), 1, 0.35, 0.35 end
	return L["Not available yet"], 0.6, 0.6, 0.6
end
local function Hex(text, r, g, b) return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, text) end

-- where a quest is picked up, in short
local function WhereText(q)
	local g = q.giver
	if g and g.inside then return L["Picked up in the dungeon"] end
	if g and g.name then return L["Given by %s"]:format(g.name) .. (g.areaName and ("  (" .. g.areaName .. ")") or "") end
	if g and g.item then return L["Started by an item: %s"]:format(g.item) end
end

local function QuestTitle(q, n)
	return (n and (n .. ".  ") or "") .. (q.level and ("(" .. q.level .. ") ") or "") .. (q.title or ("quest:" .. q.questID))
end

local OpenQuest                 -- (below: a quest's page)

-- a quest's row: its icon, "(level) Name" (green: done; yellow: to do; grey: not for you yet), its marks, and under
-- it its state, where it's picked up and its step in its chain. Returns the row and where the next one goes
local function QuestRow(q, y, showWho, sub)
	local row = Take("quest")
	row:SetPoint("TOPLEFT", PAD - 4, -y)
	row:SetPoint("RIGHT", child, "RIGHT", -PAD, 0)
	row.sel:Hide()
	local icon, grey = QuestIcon(q)
	row.icon:SetTexture(icon)
	row.icon:SetDesaturated(grey)
	local width = child:GetWidth() - 2 * PAD - 22
	local marks = QuestMarks(row, q, showWho)
	row.text:SetWidth(math.max(40, width - marks - 4))
	row.text:SetText(QuestTitle(q))
	if q.status == "done" then row.text:SetTextColor(0.25, 0.9, 0.25)
	elseif q.status == "locked" or NotMine(q) then row.text:SetTextColor(0.6, 0.6, 0.6)
	else row.text:SetTextColor(1, 0.82, 0) end
	if not sub then
		local parts = { Hex(StatusText(q)) }
		local where = WhereText(q)
		if where then parts[#parts + 1] = where end
		local n = q.needs
		if n and n.step then parts[#parts + 1] = L["Step %d of %d"]:format(n.step, n.of) end
		sub = table.concat(parts, "  \194\183  ")
	end
	row.sub:SetWidth(width)
	row.sub:SetText(sub)
	local h = 5 + row.text:GetStringHeight() + 2 + row.sub:GetStringHeight() + 5
	row:SetHeight(h)
	row:SetScript("OnClick", function()
		if IsShiftKeyDown() and GetQuestLink and ChatEdit_InsertLink then
			local link = GetQuestLink(q.questID)
			if link and ChatEdit_InsertLink(link) then return end
		end
		OpenQuest(q)
	end)
	row:SetScript("OnEnter", function(self)
		TipBeside(self)
		if not pcall(GameTooltip.SetHyperlink, GameTooltip, "quest:" .. q.questID) then
			GameTooltip:SetText(q.title or "", 1, 0.82, 0)
		end
		if q.inLog then GameTooltip:AddLine(L["In your quest log."], 1, 1, 1) end
		local who = WhoFor(q)
		if who then GameTooltip:AddLine(L["For: %s"]:format(who), 1, 1, 1) end
		GameTooltip:AddLine(L["Click: its page.   Shift-click: link it in chat."], 0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	return row, y + h + 2
end

-- the dungeon's quests: a row each
local function QuestsPage(y, quests, source)
	if quests == nil then
		return Line(L["Reading Questie's quests..."], y, 0, 0.7, 0.7, 0.7)
	end
	if #quests == 0 then
		y = Line(source == "questie" and L["Questie knows no quest for this dungeon."]
			or L["None of your quests is for this dungeon."], y, 0, 0.7, 0.7, 0.7)
		if source == "log" then y = Line(L["With Questie installed (and its option on), all the dungeon's quests show here."], y + 4, 0, 0.55, 0.55, 0.55) end
		return y
	end
	local showWho = not ns.Modules:IsOptionActive("integrations", "questieOnlyMine")   -- (the Integrations module's)
	for _, q in ipairs(quests) do
		local _
		_, y = QuestRow(q, y, showWho)
	end
	return y
end

-- the button to where a quest is picked up: the world map on its giver, marked there (none for a giver inside the
-- dungeon, or one with no place known)
local function GoButton(q, y, indent)
	local g = q.giver
	if not (g and g.uiMap and g.x and not g.inside) then return y end
	local b = Take("button")
	b:SetPoint("TOPLEFT", PAD + (indent or 0), -y)
	b:SetText(L["Where to pick it up"])
	b:SetScript("OnClick", function() module.ShowQuest(q) end)
	return y + 28
end

-- the rewards as Blizzard's quest page and the quest log's (Engine/QuestLog.lua): on a dark band the whole width,
-- "Rewards" centred in pale gold (QuestTitleFont, the Quests module's titles' font), what's said in a light parchment
-- colour, the items two by two in Blizzard's own buttons
local ITEM_ROW = 44
local function Rewards(q, y)
	local top = y
	local band = Take("band")
	-- (under the page's own texts: a level below the scroll child's)
	band:SetFrameLevel(math.max(0, child:GetFrameLevel() - 1))
	local w = child:GetWidth()
	local function Light(fs, r, g, b)
		fs:SetTextColor(r, g, b)
		fs:SetShadowColor(0, 0, 0, 0.8)
		fs:SetShadowOffset(1, -1)
	end
	local head = Take("bandtitle")
	head:SetPoint("TOPLEFT", PAD, -(y + 8))
	head:SetWidth(w - 2 * PAD)
	S.GameFont(head, "QuestTitleFont", 15, ns.db.questTitleFont == "blizzard")
	head:SetText(L["Rewards"])
	Light(head, 0.96, 0.84, 0.55)
	y = y + 8 + head:GetStringHeight() + 6
	local function Label(text)
		local fs = Take("text")
		fs:SetPoint("TOPLEFT", PAD, -y)
		fs:SetWidth(w - 2 * PAD)
		fs:SetText(text)
		Light(fs, 0.88, 0.82, 0.7)
		y = y + fs:GetStringHeight() + 4
	end
	local function Grid(list)
		local colW = (w - 2 * PAD - 6) / 2
		for i, it in ipairs(list) do
			local b = Take("bigitem")
			b:SetFrameLevel(child:GetFrameLevel() + 2)
			b:SetWidth(colW)
			local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
			b:SetPoint("TOPLEFT", child, "TOPLEFT", PAD + col * (colW + 6), -(y + row * ITEM_ROW))
			b.Icon:SetTexture(it[4] or 134400)
			b.Count:SetText(it[5] and it[5] > 1 and it[5] or "")
			b.Name:SetText(it[3] or "")
			local c = it[6] and it[6] > 1 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[it[6]]
			if c and ns.db.questRewardColors ~= false then b.Name:SetTextColor(c.r, c.g, c.b) else b.Name:SetTextColor(1, 1, 1) end
			b.kindOf, b.index, b.label, b.currency, b.questID = it[1], it[2], it[3], it[7], q.questID
		end
		y = y + math.ceil(#list / 2) * ITEM_ROW + 2
	end
	if q.inLog then
		if C_QuestLog.SetSelectedQuest then pcall(C_QuestLog.SetSelectedQuest, q.questID) end
		local receive, choose = ns.QuestLog.Rewards(q.questID)
		if #choose > 0 then
			Label(L["You will be able to choose one of these rewards:"])
			Grid(choose)
		end
		if #receive > 0 then
			Label(#choose > 0 and L["You will also receive:"] or L["You will receive:"])
			Grid(receive)
		end
		if #choose + #receive == 0 then Label(L["No reward."]) end
	else
		Label(L["Its rewards show once it's in your quest log."])
	end
	y = y + 8
	band:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -top)
	band:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -top)
	band:SetHeight(y - top)
	return y
end

-- a quest's page: what it is and where you stand with it, what keeps it from you, its chain, what it asks, who
-- gives it and takes it back, its rewards
local function QuestPage(quests)
	local q
	for _, x in ipairs(quests or {}) do if x.questID == selectedQuest then q = x end end
	if not q then return nil end
	local y = 6
	local head = Take("title")
	head:SetPoint("TOPLEFT", PAD, -y)
	head:SetWidth(child:GetWidth() - 2 * PAD)
	head:SetText(QuestTitle(q))
	y = y + head:GetStringHeight() + 4
	y = Line(Hex(StatusText(q)), y, 0)
	local who = WhoFor(q)
	if who then y = Line(L["For: %s"]:format(who), y, 0, 0.8, 0.8, 0.8) end
	-- what keeps it from you (Questie's data; whether each one is done, the game's)
	local n = q.needs or {}
	local Name = ns.Questie and ns.Questie.QuestName or function(id) return "quest:" .. id end
	local function Names(list)
		local out = {}
		for _, id in ipairs(list) do out[#out + 1] = Name(id) end
		return table.concat(out, ", ")
	end
	if q.status ~= "done" and q.status ~= "active" and q.status ~= "complete" then
		if n.oneOf then y = Line(L["First, one of these: %s"]:format(Names(n.oneOf)), y + 2, 0, 1, 0.55, 0.35) end
		if n.allOf then y = Line(L["First, all of these: %s"]:format(Names(n.allOf)), y + 2, 0, 1, 0.55, 0.35) end
		if n.parent then y = Line(L["Only while %s is in your quest log."]:format(Name(n.parent)), y + 2, 0, 1, 0.55, 0.35) end
		if n.closedBy then y = Line(L["No longer offered: you took %s instead."]:format(Name(n.closedBy)), y + 2, 0, 1, 0.35, 0.35) end
		if n.rep then
			local fname = GetFactionInfoByID and GetFactionInfoByID(n.rep[1])
			if not fname and C_Reputation and C_Reputation.GetFactionDataByID then
				local d = C_Reputation.GetFactionDataByID(n.rep[1])
				fname = d and d.name
			end
			local v, standing = n.rep[2], 4
			for i, at in ipairs({ 3000, 9000, 21000, 42000 }) do if v >= at then standing = 4 + i end end
			local label = _G["FACTION_STANDING_LABEL" .. standing] or tostring(v)
			y = Line(L["Requires %s with %s."]:format(label, fname or ("faction " .. n.rep[1])), y + 2, 0, 1, 0.55, 0.35)
		end
	end
	-- where it's picked up, and the way there when you can take it
	local g = q.giver
	if g and g.inside then y = Line(L["Picked up in the dungeon"] .. (g.name and ("  (" .. g.name .. ")") or ""), y + 4, 0, 0.75, 0.75, 0.75)
	elseif g and g.name then y = Line(L["Given by %s"]:format(g.name) .. (g.areaName and ("  (" .. g.areaName .. ")") or ""), y + 4, 0, 0.75, 0.75, 0.75)
	elseif g and g.item then y = Line(L["Started by an item: %s"]:format(g.item), y + 4, 0, 0.75, 0.75, 0.75) end
	local e = q.ender
	if e and e.name then
		y = Line(L["Handed in to %s"]:format(e.name) .. (e.inside and ("  (" .. L["in the dungeon"] .. ")") or (e.areaName and ("  (" .. e.areaName .. ")") or "")),
			y, 0, 0.75, 0.75, 0.75)
	end
	if q.status == "available" then y = GoButton(q, y + 4) end
	-- its chain, step by step, where you are in it; the step you can take, its way there
	local chain = ns.Questie and ns.Questie.Chain and ns.Questie.Chain(q.questID)
	if chain then
		y = Heading(L["Quest chain"], #chain, y + 8)
		local at
		for i, st in ipairs(chain) do if not at and st.status ~= "done" then at = i end end
		if not at then y = Line(L["You've done the whole chain."], y, 0, 0.25, 0.9, 0.25) end
		for i, st in ipairs(chain) do
			local text = Hex(StatusText(st))
			if i == at then text = Hex(L["You are here"], 1, 0.82, 0) .. "  \194\183  " .. text end
			local row
			row, y = QuestRow(st, y, false, text)
			row.text:SetText(QuestTitle(st, i))
			row.sel:SetShown(i == at)
			if st.questID == q.questID then row.text:SetTextColor(1, 1, 1) end
			-- (a step of this dungeon's: its page; another: its link's tooltip only)
			local mine
			for _, x in ipairs(quests) do if x.questID == st.questID then mine = x end end
			row:SetScript("OnClick", function() if mine and mine.questID ~= q.questID then OpenQuest(mine) end end)
			if st.status == "available" then y = GoButton(st, y, 22) end
		end
	end
	-- what it asks: Questie's words, the game's progress
	y = Heading(L["Objectives"], nil, y + 8)
	for _, t in ipairs(q.text or {}) do y = Line(t, y, 0, 1, 1, 1) end
	for _, o in ipairs(q.objectives or {}) do
		if o.finished then y = Line("- " .. o.text, y, 0, 0.55, 0.85, 0.55)
		else y = Line("- " .. o.text, y, 0, 0.85, 0.85, 0.85) end
	end
	if #(q.text or {}) == 0 and #(q.objectives or {}) == 0 then y = Line(L["What it asks isn't known here."], y, 0, 0.6, 0.6, 0.6) end
	-- its rewards: the game's own, once it's in your log, as the quest log's page shows them
	return Rewards(q, y + 12) + 8
end

-- an item's kind in the player's language, as the game says it: where it's worn and what it is ("Main droite,
-- Dague"); nil when the game can't say (DungeonJournal's English words then)
local function SlotText(id)
	local info = C_Item and C_Item.GetItemInfoInstant
	if not info then return nil end
	local ok, _, _, subType, equipLoc = pcall(info, id)
	if not ok then return nil end
	local where = type(equipLoc) == "string" and equipLoc ~= "" and _G[equipLoc]
	where = type(where) == "string" and where or nil
	subType = type(subType) == "string" and subType ~= "" and subType or nil
	if where and subType and where ~= subType then return where .. ", " .. subType end
	return where or subType
end

-- a drop rate in words: "25 %", "1,8 %", "0,6 %" (two digits at most past the first that isn't nought)
local function RateText(rate)
	local p = rate * 100
	local s
	if p >= 10 or p == math.floor(p) then s = ("%d"):format(math.floor(p + 0.5))
	elseif p >= 1 then s = ("%.1f"):format(p) else s = ("%.2f"):format(p) end
	if s:find(".", 1, true) then s = s:gsub("0+$", ""):gsub("[.]$", "") end
	return L["%s%% chance"]:format((s:gsub("%.", L["."])))
end

-- a pattern, plans, a recipe: the game's item class (Recipe), else what DungeonJournal says of it
local RECIPE_CLASS = Enum and Enum.ItemClass and Enum.ItemClass.Recipe or 9
local RECIPE_WORDS = { "Recipe", "Pattern", "Plans", "Blueprint", "Formula", "Schematic", "Manual" }
local function IsRecipe(it)
	local info = C_Item and C_Item.GetItemInfoInstant
	if info then
		local ok, _, _, _, _, _, classID = pcall(info, it.itemID)
		if ok and classID then return classID == RECIPE_CLASS end
	end
	local words = (it.slot or "") .. " " .. (it.name or "")
	for _, w in ipairs(RECIPE_WORDS) do if words:find(w, 1, true) then return true end end
	return false
end

-- an item of a boss's loot: its icon, its name in the player's language and quality colour (the game's,
-- once the server has sent it: asked for, drawn again when it comes), its slot; the game's own tooltip
local function LootRow(it, y)
	local row = Take("loot")
	row:SetPoint("TOPLEFT", PAD, -y)
	row:SetPoint("RIGHT", child, "RIGHT", -PAD, 0)
	row:SetHeight(LOOT_ICON + 2)
	local id = it.itemID
	local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
	row.icon:SetTexture(icon or 134400)
	local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
	if not name and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
	row.text:SetText(name or it.name or ("item:" .. id))
	local c = it.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[it.quality]
	if c then
		row.text:SetTextColor(c.r, c.g, c.b)
		row.edge:SetVertexColor(c.r, c.g, c.b, 1)
	else
		row.text:SetTextColor(1, 1, 1)
		row.edge:SetVertexColor(0.4, 0.4, 0.4, 1)
	end
	-- (its kind, then its drop rate when it's known: Engine/Data/DropRates.lua)
	local sub = SlotText(id) or it.slot or ""
	if it.rate then sub = (sub ~= "" and (sub .. "  \194\183  ") or "") .. RateText(it.rate) end
	row.sub:SetText(sub)
	row.itemID = id
	return y + LOOT_ICON + 6
end

-- a boss's portrait (its display ID's, else a skull)
local function Portrait(tex, b)
	if not (b.displayID and b.displayID > 0 and SetPortraitTextureFromCreatureDisplayID
		and pcall(SetPortraitTextureFromCreatureDisplayID, tex, b.displayID)) then
		tex:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
	end
end

-- a boss's row: portrait with its dragon, its level in the gold circle, its name, under it what's given. big: the
-- boss's page (its name on up to two lines, what's said under it on as many as it takes)
local function BossRow(b, y, sub, big)
	local row = Take("boss")
	row:SetPoint("TOPLEFT", PAD - 4, -y)
	row:SetPoint("RIGHT", child, "RIGHT", -PAD, 0)
	row:SetHeight(BOSS_ROW - 4)
	row.sel:Hide()
	Portrait(row.portrait, b)
	row.dragon:SetTexture(MEDIA .. (DRAGONS[b.kind] or "dragon_elite"))
	row.text:SetText(b.name)
	row.sub:SetText(sub or "")
	row.text:ClearAllPoints()
	row.sub:ClearAllPoints()
	if big then
		row.text:SetPoint("TOPLEFT", row, "TOPLEFT", BOSS_TEXT, -8)
		row.text:SetPoint("RIGHT", -4, 0)
		row.text:SetWordWrap(true)
		row.text:SetMaxLines(2)
		row.sub:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -3)
		row.sub:SetPoint("RIGHT", -4, 0)
		row.sub:SetWordWrap(true)
		row.sub:SetJustifyH("LEFT")
	else
		row.text:SetPoint("LEFT", row, "TOPLEFT", BOSS_TEXT, -BOSS_Y + 1)
		row.text:SetPoint("RIGHT", -4, 0)
		row.text:SetWordWrap(false)
		row.text:SetMaxLines(1)
		row.sub:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -3)
		row.sub:SetWordWrap(false)
	end
	-- its level in the gold circle (difficulty colour), or a boss's skull when it has none
	if b.level then
		row.badgeText:SetText(b.levelText or tostring(b.level))
		row.badgeText:SetTextColor(Colour(b.level))
		row.badgeText:Show()
		row.badgeSkull:Hide()
		row.badge:Show()
	elseif b.kind == 3 then
		row.badgeText:Hide()
		row.badgeSkull:Show()
		row.badge:Show()
	else
		row.badge:Hide()
	end
	row:SetScript("OnClick", nil)
	row:SetScript("OnEnter", nil)
	row:SetScript("OnLeave", nil)
	return row
end

local function Where(b, nFloors)
	if not b.floor then return L["Not placed on the map"] end
	if (nFloors or 0) > 1 then return L["Floor %d"]:format(b.floor) end
end

-- picks a boss: its page, its floor up on the map and its marker lit (nil: back to the dungeon's page)
local function PickBoss(b)
	selectedBoss, selectedQuest = b and b.key or nil, nil
	page = b and "boss" or "dungeon"
	ns.Dungeon.FocusBoss(b and b.floor and b.key or nil)
	scroll:SetVerticalScroll(0)
	P.Refresh()
end

-- a quest's page (QuestPage)
OpenQuest = function(q)
	selectedQuest, selectedBoss, page = q.questID, nil, "quest"
	ns.Dungeon.FocusBoss(nil)
	scroll:SetVerticalScroll(0)
	P.Refresh()
end

-- a boss's page from the dungeon's map (a click on its marker: Modules/Dungeons.lua), by its name (its key)
function P.OpenBoss(key)
	if not (frame and frame:IsShown() and module and inst) or not module:IsOptionActive("bossesTab") then return end
	for _, b in ipairs(module.BossesFor(inst)) do
		if b.key == key then PickBoss(b) return end
	end
end

-- back to the dungeon's page (the name at the top, a right-click on the dungeon's map); false when it's up already
function P.Back()
	if not (frame and frame:IsShown()) or page == "dungeon" then return false end
	PickBoss(nil)
	return true
end

-- the dungeon's bosses, under its quests: a row each, a click its page
local function BossList(y, bosses)
	local _, _, nFloors = ns.Dungeon.Current()
	for _, b in ipairs(bosses) do
		local row = BossRow(b, y, Where(b, nFloors))
		row:SetScript("OnClick", function() PickBoss(b) end)
		row:SetScript("OnEnter", function(self)
			TipBeside(self)
			GameTooltip:SetText(b.name, 1, 0.82, 0)
			if b.level then GameTooltip:AddLine((LEVEL or L["Level"]) .. " " .. (b.levelText or b.level), Colour(b.level)) end
			GameTooltip:AddLine(b.floor and L["Click: its loot, and where it stands."] or L["Click: its loot."], 0.6, 0.6, 0.6)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", GameTooltip_Hide)
		y = y + BOSS_ROW
	end
	return y
end

-- the dungeon's page: its quests, then its bosses (each as its option says)
local function DungeonPage(bosses)
	local y = 6
	if module:IsOptionActive("questsTab") then
		local quests, source = module.QuestsFor(inst, function() P.Refresh() end)
		local folded
		y, folded = Section("quests", L["Quests"], quests and #quests or nil, y)
		if not folded then y = QuestsPage(y, quests, source) end
		y = y + 8
	end
	if module:IsOptionActive("bossesTab") then
		local folded
		y, folded = Section("bosses", L["Bosses"], #bosses, y)
		if folded then
		elseif #bosses == 0 then
			y = Line(L["No boss is known for this place."], y, 0, 0.7, 0.7, 0.7)
		else
			y = BossList(y, bosses)
		end
	end
	return y
end

-- a boss's page: the boss, then its loot (DungeonJournal's list, when it's installed)
local function BossPage(bosses)
	local b, index
	for i, x in ipairs(bosses) do if x.key == selectedBoss then b, index = x, i end end
	if not b then page, selectedBoss = "dungeon", nil return DungeonPage(bosses) end
	local _, _, nFloors, _, wing = ns.Dungeon.Current()
	local where = Where(b, nFloors)
	local row = BossRow(b, 6, L["Boss %d of %d"]:format(index, #bosses) .. (where and ("\n" .. where) or ""), true)
	local textH = row.text:GetStringHeight() + 3 + row.sub:GetStringHeight() + 12
	local y = 6 + math.max(BOSS_ROW, textH) + 2
	local loot = module.BossLoot(inst, wing, b)
	if loot == nil then
		y = Heading(L["Loot"], nil, y)
		y = Line(L["Loot isn't in AzerothVeil's own data: with DungeonJournal installed, each boss's loot shows here."], y, 0, 0.7, 0.7, 0.7)
	elseif loot == false or #loot == 0 then
		y = Heading(L["Loot"], nil, y)
		y = Line(L["No loot known for this boss."], y, 0, 0.7, 0.7, 0.7)
	else
		-- its loot in two folding sections: what it drops, then the patterns, plans and recipes (folded at first)
		local items, recipes = {}, {}
		for _, it in ipairs(loot) do
			if IsRecipe(it) then recipes[#recipes + 1] = it else items[#items + 1] = it end
		end
		local folded
		if #items > 0 then
			y, folded = Section("loot", L["Loot"], #items, y)
			if not folded then for _, it in ipairs(items) do y = LootRow(it, y) end end
			y = y + 4
		end
		if #recipes > 0 then
			y, folded = Section("recipes", L["Patterns and recipes"], #recipes, y, true)
			if not folded then for _, it in ipairs(recipes) do y = LootRow(it, y) end end
		end
	end
	return y + 6
end

-- a boss's page: every boss's portrait down its left, the one shown lit
local function Strip(bosses)
	for _, sb in ipairs(stripButtons) do sb:Hide() end
	strip:SetShown(page == "boss")
	if page ~= "boss" then return end
	for i, b in ipairs(bosses) do
		local sb = stripButtons[i]
		if not sb then
			sb = CreateFrame("Button", nil, strip)
			sb:SetSize(STRIP_ICON + 6, STRIP_ICON + 6)
			sb.portrait = sb:CreateTexture(nil, "ARTWORK")
			sb.portrait:SetSize(STRIP_ICON, STRIP_ICON)
			sb.portrait:SetPoint("CENTER")
			sb.ring = sb:CreateTexture(nil, "OVERLAY")
			sb.ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
			sb.ring:SetTexCoord(0, 0.6, 0, 0.6)
			sb.ring:SetSize(STRIP_ICON * 1.55, STRIP_ICON * 1.55)
			sb.ring:SetPoint("CENTER")
			sb.lit = sb:CreateTexture(nil, "OVERLAY", nil, 1)
			sb.lit:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
			sb.lit:SetBlendMode("ADD")
			sb.lit:SetSize(STRIP_ICON * 1.3, STRIP_ICON * 1.3)
			sb.lit:SetPoint("CENTER")
			sb:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
			sb:SetScript("OnLeave", GameTooltip_Hide)
			stripButtons[i] = sb
		end
		Portrait(sb.portrait, b)
		local on = b.key == selectedBoss
		sb.lit:SetShown(on)
		sb.ring:SetVertexColor(on and 1 or 0.85, on and 0.82 or 0.85, on and 0.2 or 0.85)
		sb:ClearAllPoints()
		sb:SetPoint("TOP", strip, "TOP", 0, -(i - 1) * (STRIP_ICON + 8))
		sb:SetScript("OnClick", function() if b.key ~= selectedBoss then PickBoss(b) end end)
		sb:SetScript("OnEnter", function(self)
			TipBeside(self)
			GameTooltip:SetText(b.name, 1, 0.82, 0)
			if b.level then GameTooltip:AddLine((LEVEL or L["Level"]) .. " " .. (b.levelText or b.level), Colour(b.level)) end
			GameTooltip:Show()
		end)
		sb:Show()
	end
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------
local function Build()
	local parent = _G.AzerothVeilFrame
	frame = CreateFrame("Frame", nil, parent)
	local E = ns.Map.Edges()
	frame:SetPoint("TOPRIGHT", -E.r, -E.t)
	frame:SetPoint("BOTTOMRIGHT", -E.r, E.b)
	frame:SetWidth(ns.QuestLog.WIDTH)
	frame:SetFrameLevel(parent:GetFrameLevel() + 3)
	frame:EnableMouse(true)
	local under = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	under:SetColorTexture(0, 0, 0, 1)
	under:SetAllPoints()
	-- (the quest log's own background beside the map, Engine/QuestLog.lua: the game's quest log's, else the dialogs'
	-- dark one)
	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	if not (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("QuestLog-main-background")
		and bg:SetAtlas("QuestLog-main-background", false) ~= false) then
		bg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background-Dark", "REPEAT", "REPEAT")
		bg:SetHorizTile(true)
		bg:SetVertTile(true)
	end
	local ok, inset = pcall(CreateFrame, "Frame", nil, frame, "InsetFrameTemplate")
	if ok and inset then
		inset:SetPoint("TOPLEFT", -3, 3)
		inset:SetPoint("BOTTOMRIGHT", 3, -3)
		inset:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
	end
	-- the entrance's own icon (the map's swirl for a dungeon, its raid icon for a raid): to its entrance
	entranceButton = CreateFrame("Button", nil, frame)
	entranceButton:SetSize(26, 26)
	entranceButton:SetPoint("TOPLEFT", PAD - 2, -PAD + 2)
	entranceButton.icon = entranceButton:CreateTexture(nil, "ARTWORK")
	entranceButton.icon:SetAllPoints()
	entranceButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
	entranceButton:SetScript("OnClick", function() if module and inst then module.ShowEntrance(inst) end end)
	entranceButton:SetScript("OnEnter", function(self)
		TipBeside(self)
		GameTooltip:SetText(L["Its entrance"], 1, 0.82, 0)
		GameTooltip:AddLine(L["Click: the world map, from where you are to the dungeon's entrance."], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	entranceButton:SetScript("OnLeave", GameTooltip_Hide)
	-- the dungeon's name: on a boss's page, back to the dungeon's (an arrow before it says so)
	nameButton = CreateFrame("Button", nil, frame)
	nameButton:SetPoint("TOPLEFT", entranceButton, "TOPRIGHT", 4, 0)
	nameButton:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
	nameButton:SetHeight(26)
	backArrow = nameButton:CreateTexture(nil, "ARTWORK")
	backArrow:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
	backArrow:SetSize(22, 22)
	backArrow:SetPoint("LEFT", -2, 0)
	title = S.FontString(nameButton, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("RIGHT", 0, 0)
	title:SetJustifyH("LEFT")
	title:SetWordWrap(false)
	nameButton:SetScript("OnClick", function() if page ~= "dungeon" then PickBoss(nil) end end)
	nameButton:SetScript("OnEnter", function(self)
		if page == "dungeon" then return end
		title:SetTextColor(1, 1, 1)
		TipBeside(self)
		GameTooltip:SetText(L["Back to the dungeon's quests and bosses."], 1, 1, 1)
		GameTooltip:Show()
	end)
	nameButton:SetScript("OnLeave", function() title:SetTextColor(1, 0.82, 0) GameTooltip_Hide() end)
	levels = S.FontString(frame, "ARTWORK", "GameFontHighlightSmall")
	levels:SetPoint("TOPLEFT", entranceButton, "BOTTOMRIGHT", 4, 0)
	strip = CreateFrame("Frame", nil, frame)
	strip:SetPoint("TOPLEFT", 0, -HEAD_H - 4)
	strip:SetPoint("BOTTOMLEFT", 0, 8)
	strip:SetWidth(STRIP_W)
	strip:Hide()
	scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 4, -HEAD_H)
	scroll:SetPoint("BOTTOMRIGHT", -26, 8)
	child = CreateFrame("Frame", nil, scroll)
	child:SetSize(ns.QuestLog.WIDTH - 30, 10)
	scroll:SetScrollChild(child)
	frame:Hide()
end

function P.Refresh()
	if not (frame and frame:IsShown() and module and inst) then return end
	if pending then return end
	pending = true
	-- (quest events come in bursts: drawn once, on the next frame)
	C_Timer.After(0, function()
		pending = false
		if not (frame:IsShown() and module and inst) then return end
		if not module:IsOptionActive("bossesTab") then page, selectedBoss = "dungeon", nil end
		local bosses = module.BossesFor(inst)
		-- the header: the entrance's icon (when its place on the world is known), the name, its levels
		local info = ns.Pins.InstanceInfo and ns.Pins.InstanceInfo(inst)
		S.SetIcon(entranceButton.icon, info and info.raid and ns.Pins.RAID_ICON or ns.Pins.DUNGEON_ICON)
		entranceButton:SetShown(ns.Pins.InstanceUnits and ns.Pins.InstanceUnits(inst) ~= nil)
		title:SetText(module.InstanceName(inst))
		backArrow:SetShown(page ~= "dungeon")
		title:ClearAllPoints()
		title:SetPoint("LEFT", page ~= "dungeon" and 20 or 0, 0)
		title:SetPoint("RIGHT", 0, 0)
		if info and info.lo then
			levels:SetText(L["Levels %s"]:format(info.lo == info.hi and tostring(info.lo) or (info.lo .. "-" .. (info.hi or info.lo))))
		else
			levels:SetText("")
		end
		-- (a boss's page: the scroll beside the bosses' portraits)
		Strip(bosses)
		scroll:SetPoint("TOPLEFT", page == "boss" and STRIP_W + 2 or 4, -HEAD_H)
		ReleaseAll()
		child:SetWidth(scroll:GetWidth())
		local h
		if page == "quest" then
			h = QuestPage(module.QuestsFor(inst, function() P.Refresh() end))
			if not h then page, selectedQuest = "dungeon", nil end
		end
		if page == "boss" then h = BossPage(bosses) elseif not h then h = DungeonPage(bosses) end
		if page ~= "boss" then strip:Hide() end
		child:SetHeight(math.max(10, h))
	end)
end

-- (Modules/Dungeons.lua) m: the module; i: the dungeon's instance
function P.Show(m, i)
	if not frame then Build() end
	if i ~= inst then
		selectedBoss, selectedQuest, page = nil, nil, "dungeon" scroll:SetVerticalScroll(0)
		ns.Dungeon.FocusBoss(nil)
	end
	module, inst = m, i
	frame:Show()
	P.Refresh()
end

function P.Hide()
	if frame then frame:Hide() end
	inst = nil
	selectedBoss, selectedQuest, page = nil, nil, "dungeon"
	if ns.Dungeon then ns.Dungeon.FocusBoss(nil) end
	GameTooltip_Hide()
end

function P.IsShown() return frame and frame:IsShown() or false end
