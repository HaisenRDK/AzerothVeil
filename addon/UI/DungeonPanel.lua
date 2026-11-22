-- AzerothVeil — UI/DungeonPanel.lua
-- The side panel while a dungeon's map is up (Modules/Dungeons.lua shows and hides it): in the quest
-- log's place beside the map, drawn as it is (the dialogs' dark background, Blizzard's inset border, the
-- game's fonts and scroll bar), two tabs:
--   Quests  the quests of your log for that dungeon, their state and progress as the game gives them;
--           a click unfolds a quest's rewards (the game's own tooltips); Shift-click: its link in chat.
--   Bosses  the dungeon's bosses (portrait, level, floor); a click picks one: its floor up on the map,
--           its marker lit.
-- Only what the data really has: no quest givers, no "available" quests, no loot (DungeonJournal has
-- them: with it, its own pages are used instead of this panel). Built the first time; nothing runs while
-- it's hidden.
local _, ns = ...
local L = ns.L
local S = ns.Style

local P = {}
ns.DungeonPanel = P

local PAD, ROW = 10, 18
local frame, title, levels, scroll, child, empty, note
local tabButtons = {}
local pool, used = {}, {}
local module, inst
local tab = "quests"
local expanded = {}             -- questID -> true: its rewards shown
local selectedBoss
local pending = false

---------------------------------------------------------------------------
-- Pieces, pooled: each refresh puts them back and takes what it needs
---------------------------------------------------------------------------
local function Take(kind)
	pool[kind] = pool[kind] or {}
	local f = table.remove(pool[kind])
	if not f then
		if kind == "text" then
			f = child:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
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
			f.text = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
			f.text:SetPoint("LEFT", f.icon, "RIGHT", 4, 0)
			f.text:SetPoint("RIGHT", -44, 0)
			f.text:SetJustifyH("LEFT")
			f.text:SetWordWrap(false)
			f.right = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
			f.right:SetPoint("RIGHT", -4, 0)
		elseif kind == "boss" then
			f = CreateFrame("Button", nil, child)
			f:RegisterForClicks("LeftButtonUp")
			f:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
			f.sel = f:CreateTexture(nil, "BACKGROUND")
			f.sel:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
			f.sel:SetBlendMode("ADD")
			f.sel:SetVertexColor(1, 0.82, 0, 0.5)
			f.sel:SetAllPoints()
			f.portrait = f:CreateTexture(nil, "ARTWORK")
			f.portrait:SetSize(34, 34)
			f.portrait:SetPoint("LEFT", 2, 0)
			f.ring = f:CreateTexture(nil, "OVERLAY")
			f.ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
			f.ring:SetTexCoord(0, 0.6, 0, 0.6)
			f.ring:SetSize(50, 50)
			f.ring:SetPoint("CENTER", f.portrait, "CENTER", 0, 0)
			f.text = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
			f.text:SetPoint("TOPLEFT", f.portrait, "TOPRIGHT", 8, -3)
			f.text:SetPoint("RIGHT", -40, 0)
			f.text:SetJustifyH("LEFT")
			f.text:SetWordWrap(false)
			f.sub = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
			f.sub:SetPoint("TOPLEFT", f.text, "BOTTOMLEFT", 0, -3)
			f.right = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
			f.right:SetPoint("RIGHT", -4, 0)
		elseif kind == "loot" then
			f = CreateFrame("Button", nil, child)
			f:RegisterForClicks("LeftButtonUp")
			f.edge = f:CreateTexture(nil, "BORDER")
			f.edge:SetTexture("Interface\\Buttons\\WHITE8X8")
			f.edge:SetSize(26, 26)
			f.edge:SetPoint("LEFT", 0, 0)
			f.icon = f:CreateTexture(nil, "ARTWORK")
			f.icon:SetSize(24, 24)
			f.icon:SetPoint("CENTER", f.edge, "CENTER")
			f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			f.text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
			f.text:SetPoint("TOPLEFT", f.edge, "TOPRIGHT", 6, -1)
			f.text:SetPoint("RIGHT", 0, 0)
			f.text:SetJustifyH("LEFT")
			f.text:SetWordWrap(false)
			f.sub = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
			f.sub:SetPoint("TOPLEFT", f.text, "BOTTOMLEFT", 0, -2)
			f:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				if not pcall(GameTooltip.SetItemByID, GameTooltip, self.itemID) then GameTooltip:SetText(self.text:GetText() or "") end
				GameTooltip:Show()
			end)
			f:SetScript("OnLeave", GameTooltip_Hide)
			f:SetScript("OnClick", function(self)
				local link = C_Item and C_Item.GetItemInfo and select(2, C_Item.GetItemInfo(self.itemID))
				if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
			end)
		elseif kind == "item" then
			f = CreateFrame("Button", nil, child)
			f:SetSize(28, 28)
			f.icon = f:CreateTexture(nil, "ARTWORK")
			f.icon:SetAllPoints()
			f.count = f:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
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

local function Colour(level)
	local c = level and GetQuestDifficultyColor and GetQuestDifficultyColor(level)
	if c then return c.r, c.g, c.b end
	return 1, 0.82, 0
end

---------------------------------------------------------------------------
-- The tabs' contents
---------------------------------------------------------------------------
local function QuestsPage()
	local quests = module.QuestsFor(inst)
	local y = 6
	if #quests == 0 then
		y = Line(L["None of your quests is for this dungeon."], y, 0, 0.7, 0.7, 0.7)
		return y
	end
	for _, q in ipairs(quests) do
		local row = Take("row")
		row:SetPoint("TOPLEFT", PAD - 4, -y)
		row:SetPoint("RIGHT", child, "RIGHT", -PAD, 0)
		row:SetHeight(ROW)
		row.sel:SetShown(expanded[q.questID] and true or false)
		row.icon:SetTexture(q.complete and "Interface\\GossipFrame\\ActiveQuestIcon" or "Interface\\GossipFrame\\AvailableQuestIcon")
		row.icon:SetDesaturated(not q.complete)
		row.text:SetText(q.title or "")
		row.text:SetTextColor(Colour(q.level))
		row.right:SetText(q.level and tostring(q.level) or "")
		row:SetScript("OnClick", function()
			if IsShiftKeyDown() and GetQuestLink and ChatEdit_InsertLink then
				local link = GetQuestLink(q.questID)
				if link and ChatEdit_InsertLink(link) then return end
			end
			expanded[q.questID] = not expanded[q.questID] or nil
			P.Refresh()
		end)
		row:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			if not pcall(GameTooltip.SetHyperlink, GameTooltip, "quest:" .. q.questID) then
				GameTooltip:SetText(q.title or "", 1, 0.82, 0)
			end
			GameTooltip:AddLine(L["Click: its rewards.   Shift-click: link it in chat."], 0.6, 0.6, 0.6, true)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", GameTooltip_Hide)
		y = y + ROW + 1
		-- its state, as the game says it
		if q.failed then
			y = Line(L["Failed"], y, 22, 1, 0.3, 0.3)
		elseif q.complete then
			y = Line(L["Ready to turn in"], y, 22, 0.3, 1, 0.3)
		end
		for _, o in ipairs(q.objectives) do
			if o.finished then y = Line("- " .. o.text, y, 22, 0.55, 0.85, 0.55)
			else y = Line("- " .. o.text, y, 22, 0.85, 0.85, 0.85) end
		end
		-- its rewards, unfolded: the game's own (and its tooltips)
		if expanded[q.questID] then
			if C_QuestLog.SetSelectedQuest then pcall(C_QuestLog.SetSelectedQuest, q.questID) end
			local receive, choose = ns.QuestLog.Rewards(q.questID)
			local function Grid(list, label)
				if #list == 0 then return end
				y = Line(label, y + 2, 22, 1, 0.82, 0)
				local x = PAD + 22
				for _, it in ipairs(list) do
					if x + 28 > child:GetWidth() - PAD then x, y = PAD + 22, y + 31 end
					local b = Take("item")
					b:SetPoint("TOPLEFT", x, -y)
					b.icon:SetTexture(it[4] or 134400)
					b.count:SetText(it[5] and it[5] > 1 and it[5] or "")
					b.kind, b.index, b.label, b.currency, b.questID = it[1], it[2], it[3], it[7], q.questID
					x = x + 31
				end
				y = y + 33
			end
			Grid(choose, L["You will be able to choose one of these rewards:"])
			Grid(receive, #choose > 0 and L["You will also receive:"] or L["You will receive:"])
		end
		y = y + 6
	end
	return y
end

-- an item of a boss's loot: its icon, its name in the player's language and quality colour (the game's,
-- once the server has sent it: asked for, drawn again when it comes), its slot; the game's own tooltip
local function LootRow(it, y)
	local row = Take("loot")
	row:SetPoint("TOPLEFT", PAD + 34, -y)
	row:SetPoint("RIGHT", child, "RIGHT", -PAD, 0)
	row:SetHeight(26)
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
	row.sub:SetText(it.slot or "")
	row.itemID = id
	return y + 28
end

local function BossesPage()
	local bosses = module.BossesFor(inst)
	local y = 6
	if #bosses == 0 then
		return Line(L["No boss is known for this place."], y, 0, 0.7, 0.7, 0.7)
	end
	local _, _, nFloors, _, wing = ns.Dungeon.Current()
	for _, b in ipairs(bosses) do
		local row = Take("boss")
		row:SetPoint("TOPLEFT", PAD - 4, -y)
		row:SetPoint("RIGHT", child, "RIGHT", -PAD, 0)
		row:SetHeight(40)
		local picked = selectedBoss == b.key
		row.sel:SetShown(picked)
		if not (b.displayID and b.displayID > 0 and SetPortraitTextureFromCreatureDisplayID
			and pcall(SetPortraitTextureFromCreatureDisplayID, row.portrait, b.displayID)) then
			row.portrait:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
		end
		row.text:SetText(b.name)
		local where
		if not b.floor then where = L["Not placed on the map"]
		elseif (nFloors or 0) > 1 then where = L["Floor %d"]:format(b.floor) end
		row.sub:SetText(where or "")
		if b.level then
			row.right:SetText(b.levelText or tostring(b.level))
			row.right:SetTextColor(Colour(b.level))
		else
			row.right:SetText(b.kind == 3 and "|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:14|t" or "")
		end
		row:SetScript("OnClick", function()
			selectedBoss = (selectedBoss ~= b.key) and b.key or nil
			if selectedBoss and b.floor then ns.Dungeon.FocusBoss(b.key) end
			P.Refresh()
		end)
		row:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(b.name, 1, 0.82, 0)
			if b.level then GameTooltip:AddLine((LEVEL or L["Level"]) .. " " .. (b.levelText or b.level), Colour(b.level)) end
			GameTooltip:AddLine(b.floor and L["Click: its loot, and where it stands."] or L["Click: its loot."], 0.6, 0.6, 0.6)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", GameTooltip_Hide)
		y = y + 42
		-- picked: its loot (DungeonJournal's list, when it's installed)
		if picked then
			local loot = module.BossLoot(inst, wing, b)
			if loot == nil then
				y = Line(L["Loot isn't in AzerothVeil's own data: with DungeonJournal installed, each boss's loot shows here."], y, 34, 0.7, 0.7, 0.7)
			elseif loot == false or #loot == 0 then
				y = Line(L["No loot known for this boss."], y, 34, 0.7, 0.7, 0.7)
			else
				for _, it in ipairs(loot) do y = LootRow(it, y) end
			end
			y = y + 6
		end
	end
	return y
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------
local function SelectTab(key)
	tab = key
	P.Refresh()
end

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
	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background-Dark", "REPEAT", "REPEAT")
	bg:SetHorizTile(true)
	bg:SetVertTile(true)
	local ok, inset = pcall(CreateFrame, "Frame", nil, frame, "InsetFrameTemplate")
	if ok and inset then
		inset:SetPoint("TOPLEFT", -3, 3)
		inset:SetPoint("BOTTOMRIGHT", 3, -3)
		inset:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
	end
	title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", PAD, -PAD)
	title:SetPoint("RIGHT", -PAD, 0)
	title:SetJustifyH("LEFT")
	title:SetWordWrap(false)
	levels = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	levels:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
	-- the two tabs: Blizzard's panel buttons, the one shown held down
	local specs = { { "quests", L["Quests"] }, { "bosses", L["Bosses"] } }
	for i, s in ipairs(specs) do
		local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		b:SetSize((ns.QuestLog.WIDTH - 2 * PAD - 6) / 2, 22)
		b:SetPoint("TOPLEFT", PAD + (i - 1) * ((ns.QuestLog.WIDTH - 2 * PAD - 6) / 2 + 6), -50)
		b:SetText(s[2])
		b:SetScript("OnClick", function() SelectTab(s[1]) end)
		b.key = s[1]
		tabButtons[#tabButtons + 1] = b
	end
	scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 4, -80)
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
		local q, b = module:IsOptionActive("questsTab"), module:IsOptionActive("bossesTab")
		if tab == "quests" and not q then tab = "bosses" elseif tab == "bosses" and not b then tab = "quests" end
		for _, t in ipairs(tabButtons) do
			local on = (t.key == "quests" and q) or (t.key == "bosses" and b)
			t:SetEnabled(on and true or false)
			if t.key == tab then t:LockHighlight() else t:UnlockHighlight() end
		end
		title:SetText(module.InstanceName(inst))
		local info = ns.Pins.InstanceInfo and ns.Pins.InstanceInfo(inst)
		if info and info.lo then
			levels:SetText(L["Levels %s"]:format(info.lo == info.hi and tostring(info.lo) or (info.lo .. "-" .. (info.hi or info.lo))))
		else
			levels:SetText("")
		end
		ReleaseAll()
		child:SetWidth(scroll:GetWidth())
		local h = (tab == "quests" and q) and QuestsPage() or (b and BossesPage()) or 10
		child:SetHeight(math.max(10, h))
	end)
end

-- (Modules/Dungeons.lua) m: the module; i: the dungeon's instance
function P.Show(m, i)
	if not frame then Build() end
	if i ~= inst then selectedBoss = nil wipe(expanded) scroll:SetVerticalScroll(0) end
	module, inst = m, i
	frame:Show()
	P.Refresh()
end

function P.Hide()
	if frame then frame:Hide() end
	inst = nil
	selectedBoss = nil
	GameTooltip_Hide()
end

function P.IsShown() return frame and frame:IsShown() or false end
