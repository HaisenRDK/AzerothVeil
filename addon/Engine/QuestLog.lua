-- The quest log, docked on the right of the map window: the quests by zone with their objectives
-- (tick to track), and a quest's details (objectives, description, rewards, track / share / abandon). Replaces Blizzard's quest log beside its map. Built the first time it shows;
-- rebuilt only while shown, at most a few times a second.
local _, FM = ...
local L = FM.L
local QL = {}
local MEDIA = "Interface\\AddOns\\AzerothVeil\\Media\\"
FM.QuestLog = QL

local S = FM.Style
local max, min, floor = math.max, math.min, math.floor
local WIDTH = 300
local BAR = 26                          -- (as tall as the map's header bar, and drawn the same)
local PAD = 8

local panel, scroll, child, thumb, topTitle, back, bottom, search
local query = ""                          -- what's typed in the search box, lower case ("": all)
local headers = {}                        -- AzerothVeil: the zones of the list as last built (Collapse all)
local countBar, foldAll                   -- AzerothVeil: the line under the search box: the count, Collapse all
local buttons = {}
local mode, detailID = "list", nil
local collapsed = {}
local rows, pool = {}, {}
local pending = false
local tips = {}             -- AzerothVeil: the tooltips of the icons after the names (IconTip)
local hyper = false         -- AzerothVeil: the rows' text can carry links on this client (NewRow)
local IconEnter             -- (AzerothVeil: below, with the icons)
local CanFollow, TopLayout  -- (AzerothVeil: below, with the buttons)

local function DiffColor(level)
	local c = GetQuestDifficultyColor and level and GetQuestDifficultyColor(level)
	if c then return c.r, c.g, c.b end
	return 1, 0.82, 0
end

-- AzerothVeil: the list's colours, calmer than the game's pure ones on the dark: a quest's difficulty colour
-- drawn a third of the way to the text's parchment grey (still red, orange, yellow, green, grey), the zones'
-- names in a softer gold, the objectives in that grey, what's done dimmer, "ready" a quiet green
local SOFT = { 0.8, 0.77, 0.7 }
local function SoftColor(r, g, b)
	return r + (SOFT[1] - r) * 0.35, g + (SOFT[2] - g) * 0.35, b + (SOFT[3] - b) * 0.35
end
local ZONE_INK = { 0.96, 0.8, 0.38 }
local OBJ_INK = { 0.8, 0.78, 0.72 }
local READY = "|cff86c873"
local DONE = "|cff7c7a74"

-- AzerothVeil: the objective tracker full (as many quests tracked as the game allows; nil: no limit known)
local function WatchLimit()
	local n = C_QuestLog.GetMaxNumQuestsCanWatch and FM.Plain(C_QuestLog.GetMaxNumQuestsCanWatch())
	if type(n) ~= "number" then
		n = Constants and Constants.QuestWatchConsts and Constants.QuestWatchConsts.MAX_QUEST_WATCHES or MAX_WATCHABLE_QUESTS
	end
	return type(n) == "number" and n > 0 and n or nil
end
local function WatchCount()
	local n = C_QuestLog.GetNumQuestWatches and FM.Plain(C_QuestLog.GetNumQuestWatches())
	return type(n) == "number" and n or 0
end

-- AzerothVeil: tracking and focusing (super-tracking) wait for the end of a fight: the change fires its
-- event inside our call and Blizzard's map pins rebuild there, which the game blocks in combat (as FlareUI
-- found). The last choice per quest wins; the log shows it at once.
local fight = { watch = {}, focus = nil, frame = nil }

local function RealWatched(questID)
	return C_QuestLog.GetQuestWatchType and C_QuestLog.GetQuestWatchType(questID) ~= nil
end

local function Watched(questID)
	local w = fight.watch[questID]
	if w ~= nil then return w end
	return RealWatched(questID)
end

local function ApplyWatch(questID, on)
	if on then C_QuestLog.AddQuestWatch(questID) else C_QuestLog.RemoveQuestWatch(questID) end
end

local function AfterFight()
	if not fight.frame then
		fight.frame = CreateFrame("Frame")
		fight.frame:SetScript("OnEvent", function(self)
			self:UnregisterEvent("PLAYER_REGEN_ENABLED")
			for q, on in pairs(fight.watch) do
				if C_QuestLog.GetLogIndexForQuestID(q) and RealWatched(q) ~= on then ApplyWatch(q, on) end
			end
			wipe(fight.watch)
			local focus = fight.focus
			fight.focus = nil
			if focus and C_SuperTrack then C_SuperTrack.SetSuperTrackedQuestID(focus) end
			QL.Changed()
		end)
	end
	fight.frame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

local function SetWatched(questID, on)
	if InCombatLockdown() then
		fight.watch[questID] = on and true or false
		AfterFight()
		return
	end
	ApplyWatch(questID, on)
end

-- the quest followed with the waypoint arrow (or the one it will be after the fight)
local function Focused(questID)
	if fight.focus ~= nil then return fight.focus == questID end
	local s = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and FM.Plain(C_SuperTrack.GetSuperTrackedQuestID())
	return s == questID
end

-- questID 0: none
local function SetFocus(questID)
	if not C_SuperTrack then return end
	if InCombatLockdown() then
		fight.focus = questID
		AfterFight()
		QL.Refresh()
		return
	end
	C_SuperTrack.SetSuperTrackedQuestID(questID)
end

---------------------------------------------------------------------------
-- Rows (pooled buttons in the scroll child)
---------------------------------------------------------------------------
-- (the classic look: Blizzard's quest log, its list on dark with gold zone headers and their +/- buttons, the
-- quest's own page on parchment in dark ink)
-- (AzerothVeil: the game's own ink on a quest's page: QuestTitleFont's and QuestFont's black, QuestFontNormalSmall's brown)
local INK = { 0, 0, 0 }                   -- (titles and headings on the parchment)
local INK_TEXT = { 0, 0, 0 }              -- (its text)
local INK_SMALL = { 0.3, 0.18, 0 }        -- (its small lines: the level under the name)

local function RowEnter(self)
	if self.questID or self.header then
		if S.classic then self.hl:Show() else self.bg:SetVertexColor(1, 1, 1, (self.bgBase or 0) + 0.05) end
	end
	if self.questID then FM.Quests.Hint(self.questID) end
end
local function RowLeave(self)
	if self.questID or self.header then
		if S.classic then self.hl:Hide() else self.bg:SetVertexColor(1, 1, 1, self.bgBase or 0) end
	end
	if self.questID then FM.Quests.Hint(nil) end
end

-- AzerothVeil: a right click goes back from a quest's page to the list (the whole panel, as the map: QL.Back);
-- in the list, on a quest, it tracks or untracks it
local function RowClick(self, button)
	if button == "RightButton" then
		if QL.Back() then return end
		if self.questID then SetWatched(self.questID, not Watched(self.questID)) QL.Refresh() end
		return
	end
	if self.questID and IsModifiedClick and IsModifiedClick("CHATLINK") and GetQuestLink then
		local link = GetQuestLink(self.questID)
		if link and ChatEdit_InsertLink and ChatEdit_InsertLink(link) then return end
	end
	if self.header then
		collapsed[self.header] = not collapsed[self.header] or nil
		QL.Refresh()
	elseif self.questID then
		QL.ShowDetails(self.questID, false, true)      -- (picked in the log: its button flashes)
	end
end

-- AzerothVeil: a click on an icon after the name (a link of ours) is the row's, once
local clickedAt, clickedRow
local function RowClickOnce(self, button)
	local now = GetTime()
	if clickedAt == now and clickedRow == self then return end
	clickedAt, clickedRow = now, self
	RowClick(self, button)
end

-- the track box as it is (AzerothVeil: Blizzard's own check box, UICheckButtonTemplate)
local function ShowCheck(c)
	c:SetChecked(c.on and true or false)
end

local function NewRow()
	local b = CreateFrame("Button", nil, child)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetTexture(S.WHITE)
	b.bg:SetAllPoints()
	b.bg:SetVertexColor(1, 1, 1, 0)
	b.title = S.Text(b, 12)
	b.title:SetJustifyH("LEFT")
	b.title:SetWordWrap(true)
	b.body = S.Text(b, 11)
	b.body:SetJustifyH("LEFT")
	b.body:SetJustifyV("TOP")
	b.body:SetWordWrap(true)
	b.body:SetSpacing(2)
	-- AzerothVeil: Blizzard's own check box (its look, its highlight, its pressed state), not PerfectMap's
	b.check = CreateFrame("CheckButton", nil, b, "UICheckButtonTemplate")
	b.check:SetSize(22, 22)
	b.check:SetPoint("TOPRIGHT", -4, 0)
	b.sign = S.Text(b, 18, S.ACCENT)
	b.sign:SetPoint("RIGHT", -10, 0)
	b.shade = b:CreateTexture(nil, "BACKGROUND", nil, 1)
	b.shade:SetTexture(S.WHITE)
	b.shade:SetAllPoints()
	if b.shade.SetGradient and CreateColor then
		b.shade:SetGradient("HORIZONTAL", CreateColor(1, 0.85, 0.5, 0.13), CreateColor(1, 1, 1, 0.02))
	else
		b.shade:SetVertexColor(1, 1, 1, 0.07)
	end
	b.edge = b:CreateTexture(nil, "ARTWORK")
	b.edge:SetTexture(S.WHITE)
	b.edge:SetVertexColor(S.ACCENT[1], S.ACCENT[2], S.ACCENT[3], 0.9)
	b.edge:SetPoint("TOPLEFT")
	b.edge:SetPoint("BOTTOMLEFT")
	b.edge:SetWidth(2)
	b.count = S.Text(b, 11, S.DIM)
	b.count:SetPoint("RIGHT", b.sign, "LEFT", -8, 0)
	b.shade:Hide()
	b.edge:Hide()
	b.count:Hide()
	if S.classic then
		-- (classic: the titles lit as its quest log lights them; a zone's bar)
		b.hl = b:CreateTexture(nil, "BACKGROUND", nil, 2)
		b.hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
		b.hl:SetBlendMode("ADD")
		b.hl:SetAllPoints()
		b.hl:Hide()
		-- (a zone's bar: dark, in the tooltip's thin border; inside the row, a little in from its sides)
		b.bar = CreateFrame("Frame", nil, b, BackdropTemplateMixin and "BackdropTemplate" or nil)
		b.bar:SetPoint("TOPLEFT", 4, -1)
		b.bar:SetPoint("BOTTOMRIGHT", -4, 1)
		b.bar:SetFrameLevel(math.max(0, b:GetFrameLevel() - 1))   -- (under the row's own name and sign)
		if b.bar.SetBackdrop then
			b.bar:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
				tile = true, tileSize = 8, edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
			b.bar:SetBackdropColor(0.13, 0.1, 0.07, 1)
			b.bar:SetBackdropBorderColor(0.5, 0.42, 0.3, 1)
		end
		b.bar:Hide()
		S.Font(b.sign, 20)
	end
	b.check:SetScript("OnClick", function(self)
		local q = self:GetParent().questID
		if q then SetWatched(q, not Watched(q)) QL.Refresh() end
	end)
	b.check:SetScript("OnEnter", function(self)
		S.ShowTip(self, { L["Track"], L["Show it in the objective tracker."] })
	end)
	b.check:SetScript("OnLeave", function(self)
		S.HideTip()
	end)
	b:SetScript("OnEnter", RowEnter)
	b:SetScript("OnLeave", RowLeave)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")     -- (AzerothVeil: right click, RowClick)
	b:SetScript("OnClick", RowClickOnce)
	-- AzerothVeil: the icons after the name carry links of ours, for their tooltips (IconTip); where the
	-- client lets a frame's text do that (as FlareUI's About page does), else plain icons
	if b.SetHyperlinksEnabled and pcall(b.SetScript, b, "OnHyperlinkEnter", IconEnter)
		and pcall(b.SetScript, b, "OnHyperlinkLeave", GameTooltip_Hide) then
		b:SetHyperlinksEnabled(true)
		pcall(b.SetScript, b, "OnHyperlinkClick", function(self, _, _, button) RowClickOnce(self, button) end)
		hyper = true
	end
	return b
end

local function Release()
	wipe(tips)                  -- (AzerothVeil: the icons' tooltips go with their rows)
	for i = #rows, 1, -1 do
		local b = rows[i]
		b:Hide()
		b:ClearAllPoints()
		b.questID, b.header, b.bgBase = nil, nil, nil
		-- (AzerothVeil: a quest page's row, in the game's quest fonts: back to the list's, its shadow set again)
		if b.big then S.Font(b.title, 12) S.Font(b.body, 11) b.big, b.shadow = nil, nil end
		b.sign:Hide()
		b.shade:Hide()
		b.edge:Hide()
		b.count:Hide()
		if b.hl then b.hl:Hide() b.bar:Hide() end
		b.title:SetJustifyH("LEFT")
		b.title:SetWordWrap(true)
		if b.poi then b.poi:Hide() end
		pool[#pool + 1] = b
		rows[i] = nil
	end
end

local function Row()
	local b = tremove(pool) or NewRow()
	-- (classic: a quest's page is on parchment, its ink without the shadow the list's text has on the dark)
	local shadow = (S.classic and mode == "details") and 0 or 0.8
	if b.shadow ~= shadow then
		b.shadow = shadow
		b.title:SetShadowColor(0, 0, 0, shadow)
		b.body:SetShadowColor(0, 0, 0, shadow)
	end
	b:Show()
	b.bg:SetVertexColor(1, 1, 1, 0)
	rows[#rows + 1] = b
	return b
end

-- lay a row out at y; returns the y under it
local function Place(b, y, indent, title, body, check, right)
	local w = child:GetWidth()
	b:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
	b:SetWidth(w)
	b.check:SetShown(check ~= nil)
	if check ~= nil then
		b.check.on = check
		ShowCheck(b.check)
	end
	b.title:ClearAllPoints()
	b.title:SetPoint("TOPLEFT", indent, -4)
	-- (the track box's column kept clear all the way down: the name and the objectives both stop short
	-- of it, a long word broken rather than run under it)
	local clear = (right or 0) + (check ~= nil and 4 or 0)
	b.title:SetWidth(w - indent - PAD - clear)
	if b.title.SetNonSpaceWrap then b.title:SetNonSpaceWrap(true) end
	b.title:SetText(title or "")
	local h = (title and b.title:GetStringHeight() or 0) + 8
	b.body:ClearAllPoints()
	if body and body ~= "" then
		b.body:SetPoint("TOPLEFT", b.title, "BOTTOMLEFT", 0, -3)
		b.body:SetWidth(w - indent - PAD - (check ~= nil and clear or 0))
		if b.body.SetNonSpaceWrap then b.body:SetNonSpaceWrap(true) end
		b.body:SetText(body)
		b.body:Show()
		h = h + b.body:GetStringHeight() + 3
	else
		b.body:SetText("")
		b.body:Hide()
	end
	b:SetHeight(h)
	return y + h
end

---------------------------------------------------------------------------
-- Scrolling (our own thin bar)
---------------------------------------------------------------------------
local function UpdateThumb()
	local view, total = scroll:GetHeight(), child:GetHeight()
	if total <= view + 1 or view < 1 then thumb:Hide() return end
	local h = min(view, max(20, view * view / total))     -- (never longer than the list's own height)
	local f = min(1, scroll:GetVerticalScroll() / (total - view))
	thumb:SetHeight(h)
	thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 4, -f * (view - h))
	thumb:Show()
end

-- The wheel glides the list: its place kept here, exactly (not read back from the frame, which may round
-- it), eased toward where the wheel sends it by time (as smooth at any frame rate), and set on whole
-- screen pixels, so the text, the highlights and the boxes all move together, never a pixel apart.
-- A step of the wheel while it glides adds on to where it's going: spun, it runs on evenly.
local GLIDE, STEP = 12, 48
local scrollPos, scrollTo = 0, nil
local function Snap(y)
	local px = (PixelUtil and PixelUtil.GetPixelToUIUnitFactor and PixelUtil.GetPixelToUIUnitFactor() or 1) / scroll:GetEffectiveScale()
	return floor(y / px + 0.5) * px
end
local function SetPos(y)
	scrollPos = y
	scroll:SetVerticalScroll(Snap(y))
	UpdateThumb()
end
local function Glide(self, elapsed)
	local k = 1 - math.exp(-elapsed * GLIDE)
	local y = scrollPos + (scrollTo - scrollPos) * k
	if math.abs(scrollTo - y) < 0.25 then
		y, scrollTo = scrollTo, nil
		self:SetScript("OnUpdate", nil)
	end
	SetPos(y)
end

local function MaxScroll() return max(0, child:GetHeight() - scroll:GetHeight()) end

-- delta: the wheel's steps; 0 just keeps it within the list (laid out again, resized), at once
local function ScrollBy(delta)
	local maxScroll = MaxScroll()
	if delta == 0 then
		if scrollTo then scrollTo = min(max(scrollTo, 0), maxScroll) end
		SetPos(min(max(scrollPos, 0), maxScroll))
		return
	end
	local was = scrollTo
	scrollTo = min(max((scrollTo or scrollPos) - delta * STEP, 0), maxScroll)
	if not was then scroll:SetScript("OnUpdate", Glide) end
end

-- back to the top at once (a new list, a quest's page)
local function ScrollTop()
	if scrollTo then scrollTo = nil scroll:SetScript("OnUpdate", nil) end
	SetPos(0)
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------
local TICK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t "
local function ObjectivesText(questID, complete, dashes)
	local out = {}
	if complete and dashes then
		local index = C_QuestLog.GetLogIndexForQuestID(questID)
		local done = index and GetQuestLogCompletionText and GetQuestLogCompletionText(index)
		return READY .. "- " .. (done or QUEST_WATCH_QUEST_READY or L["Ready to turn in"]) .. "|r"
	end
	for _, o in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
		if o.text and o.text ~= "" then
			if dashes then
				out[#out + 1] = o.finished and (DONE .. "- " .. o.text .. "|r") or ("- " .. o.text)
			else
				out[#out + 1] = o.finished and (TICK .. "|cff8a8a8a" .. o.text .. "|r") or o.text
			end
		end
	end
	if complete then out[#out + 1] = TICK .. READY .. L["Ready to turn in"] .. "|r" end
	return table.concat(out, "\n")
end

-- a dungeon's or raid's quest: its icon, left of its name (as the game tags it: dungeon, heroic, raid)
local KIND_TAGS = { [81] = "dungeon", [85] = "dungeon", [62] = "raid", [88] = "raid", [89] = "raid", [41] = "pvp" }
local KIND_LABEL = { dungeon = L["Dungeon"], raid = L["Raid"], pvp = L["PvP"] }
local pvpIcon
-- (PvP: the game's crossed swords)
local function PvPIcon()
	if not pvpIcon then
		local get = C_Texture and C_Texture.GetAtlasInfo
		for _, a in ipairs({ "questlog-questtypeicon-pvp", "QuestPvP" }) do
			if get and get(a) then pvpIcon = "atlas:" .. a break end
		end
		pvpIcon = pvpIcon or "Interface\\Icons\\Ability_DualWield"
	end
	return pvpIcon
end
-- a quest's kind, for its icon: dungeon, raid, pvp (as the game tags it), else nil
local function Kind(questID)
	local tag = C_QuestLog.GetQuestTagInfo and C_QuestLog.GetQuestTagInfo(questID)
	if type(tag) ~= "table" then return nil end
	return KIND_TAGS[tag.tagID] or (type(tag.tagName) == "string" and tag.tagName:find("PvP") and "pvp") or nil
end
local function KindTexture(kind)
	if kind == "pvp" then return PvPIcon() end
	return kind == "raid" and FM.Pins.RAID_ICON or FM.Pins.DUNGEON_ICON
end

-- AzerothVeil: after each quest's name, its icons: its kind as the game tags it (dungeon, raid, PvP, elite,
-- group, class, world event, legendary), then the item it's done with if it has one (its own icon), else
-- daily or repeatable, else what its next objective asks (kill, collect, use, explore, talk, reputation).
-- The objectives' icons are Questie's (Media\Questie, so they show without it). Each one says what it
-- means under the mouse (IconTip); a click on one is the row's.
local QI = "Interface\\AddOns\\AzerothVeil\\Media\\Questie\\"
-- { icon, what it is, what that means }
local OBJECTIVE_MARK = {
	monster = { QI .. "slay", L["Kill"], L["Next objective: kill these creatures."] },
	player = { QI .. "slay", L["Defeat players"], L["Next objective: defeat players of the other faction."] },
	item = { QI .. "loot", L["Collect"], L["Next objective: collect these items."] },
	object = { QI .. "object", L["Use"], L["Next objective: use or click on something in the world."] },
	event = { QI .. "event", L["Explore"], L["Next objective: go somewhere, or make something happen there."] },
	reputation = { QI .. "reputation", L["Reputation"], L["Next objective: reach this standing with a faction."] },
	log = { QI .. "interact", L["Do"], L["Next objective: something to do (talk to someone, escort, ...)."] },
}
local KIND_MARK = {
	dungeon = L["To be done in a dungeon: better with a group."],
	raid = L["To be done in a raid."],
	pvp = L["Player versus player: against the other faction, or in a battleground."],
}
local TAG_MARK = {
	group = { "Interface\\TargetingFrame\\UI-TargetingFrame-Skull", L["Group quest"], L["Made for a group: too hard to do alone."] },
	elite = { "Interface\\TargetingFrame\\UI-TargetingFrame-Skull", L["Elite"], L["Elite enemies: better with a group."] },
	event = { QI .. "eventquest", L["World event"], L["Part of a world event: only while it lasts."] },
	legendary = { "Interface\\Icons\\INV_Misc_Orb_05", L["Legendary"], L["A legendary quest."] },
}
local function TagMark(questID)
	local kind = Kind(questID)
	if kind then return { KindTexture(kind), KIND_LABEL[kind], KIND_MARK[kind] } end
	local tag = C_QuestLog.GetQuestTagInfo and C_QuestLog.GetQuestTagInfo(questID)
	if type(tag) ~= "table" then return nil end
	local name = type(tag.tagName) == "string" and tag.tagName or ""
	if tag.tagID == 21 then
		local _, class = UnitClass("player")
		return { class and ("Interface\\Icons\\ClassIcon_" .. class:sub(1, 1) .. class:sub(2):lower()) or TAG_MARK.elite[1],
			L["Class quest"], L["A quest for your class only."] }
	end
	if tag.tagID == 82 then return TAG_MARK.event end
	if tag.tagID == 83 then return TAG_MARK.legendary end
	if name:find(L["Elite"]) then return TAG_MARK.elite end
	if tag.tagID == 1 then return TAG_MARK.group end
end

-- The icons are in the name's own line of text, where the game puts them (after a name on two lines too),
-- each in a link of ours: the row's hyperlinks on, its tooltip shown over it (OnHyperlinkEnter). tips: the
-- tooltips of the icons laid out now, by number (emptied as the rows are; declared at the top)
local function Inline(icon)
	if type(icon) == "string" and icon:sub(1, 6) == "atlas:" then return "|A:" .. icon:sub(7) .. ":14:14|a" end
	return "|T" .. tostring(icon) .. ":14:14|t"
end
-- an icon with its tooltip: { title, text, more } or { item = link }
local function IconTip(icon, tip)
	local s = Inline(icon)
	if not hyper then return " " .. s end
	tips[#tips + 1] = tip
	return " |Hazerothveil:" .. #tips .. "|h" .. s .. "|h"
end

function IconEnter(self, link)
	local t = tips[tonumber(type(link) == "string" and link:match("^azerothveil:(%d+)") or "")]
	if not t then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if t.item then
		if not pcall(GameTooltip.SetHyperlink, GameTooltip, t.item) then GameTooltip:SetText(t.item) end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(L["Quest item: the quest is done by using it."], 0.25, 0.88, 0.25, true)
	else
		GameTooltip:SetText(t[1] or "", 1, 0.82, 0)
		if t[2] then GameTooltip:AddLine(t[2], 1, 1, 1, true) end
		if t[3] then GameTooltip:AddLine(t[3], 0.8, 0.8, 0.8, true) end
	end
	GameTooltip:Show()
end

local function TypeIcon(questID)
	local m = TagMark(questID)
	if not m then return "" end
	return IconTip(m[1], { m[2], m[3] })
end

-- the quest's item to use, if it has one (and still wants it): its link and icon
local function QuestItem(questID, complete)
	local index = GetQuestLogSpecialItemInfo and C_QuestLog.GetLogIndexForQuestID(questID)
	if not index then return nil end
	local ok, link, texture, _, showWhenComplete = pcall(GetQuestLogSpecialItemInfo, index)
	if not ok or not link or not texture or (complete and not showWhenComplete) then return nil end
	return link, texture
end

-- after the kind: the item, else what it asks next (none for a failed quest or one ready to hand in:
-- the round button and the text say it)
local function QuestMark(questID, info, complete, failed)
	local link, texture = QuestItem(questID, complete)
	if link then return IconTip(texture, { item = link }) end
	if failed or complete then return "" end
	local todo, otype
	for _, o in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
		if not o.finished and o.text and o.text ~= "" then todo, otype = o.text, o.type break end
	end
	local freq = info and info.frequency
	if freq and freq ~= 0 then
		local daily = Enum and Enum.QuestFrequency and freq == Enum.QuestFrequency.Daily
		return IconTip(QI .. "repeatable", { daily and L["Daily"] or L["Repeatable"],
			daily and L["It can be done again each day."] or L["It can be done again."], todo })
	end
	local o = otype and OBJECTIVE_MARK[otype]
	if o then return IconTip(o[1], { o[2], o[3], todo }) end
	return IconTip(QI .. "incomplete", { L["Quest"], L["In progress."], todo })
end

-- AzerothVeil: left of each name, the round quest button of Blizzard's quest log and tracker: a yellow
-- "..." while in progress, a "?" when ready to hand in, the focused quest in its selected look (ring, brown
-- dots, glow). Blizzard's atlases (Blizzard_POIButton) on a button of our own, as FlareUI does: the
-- template's mixin reaches into the map's pins. A click focuses the quest (the waypoint arrow), or stops
-- focusing it; a right click is the row's. Its tooltip says what the icons after the name mean.
local POI_SIZE, POI_BLIZZARD = 14, 20

local function SizeAtlas(tex, atlas, k)
	tex:SetAtlas(atlas, true)
	local w, h = tex:GetSize()
	if w and h then tex:SetSize(w * k, h * k) end
end

local function PaintPOI(p, pressed)
	local k = POI_SIZE / POI_BLIZZARD
	SizeAtlas(p.ring, "UI-QuestPoi-QuestNumber" .. (pressed and "-Pressed" or "") .. (p.focus and "-SuperTracked" or ""), k)
	SizeAtlas(p.mark, p.done and "UI-QuestIcon-TurnIn-Normal"
		or (p.focus and "Quest-In-Progress-Icon-Brown" or "Quest-In-Progress-Icon-yellow"), k)
	p.mark:SetPoint("CENTER", pressed and 1 or 0, pressed and -1 or 0)
	p.glow:SetShown(p.focus and true or false)
end

local function POIEnter(self)
	local row = self:GetParent()
	RowEnter(row)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if self.done then
		GameTooltip:SetText(L["Ready to hand in"], 1, 0.82, 0)
		GameTooltip:AddLine(L["\"?\": go back to whoever gave it, to hand it in."], 1, 1, 1, true)
	else
		GameTooltip:SetText(L["In progress"], 1, 0.82, 0)
		GameTooltip:AddLine(L["\"...\": its objectives are still to be done."], 1, 1, 1, true)
	end
	if self.focus then GameTooltip:AddLine(L["Followed with the waypoint arrow (the lit ring)."], 0.25, 0.88, 0.25, true) end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(self.focus and L["Click: stop following it."] or L["Click: follow it with the waypoint arrow."], 0.8, 0.8, 0.8, true)
	GameTooltip:AddLine(L["Right-click on the quest: track it or not."], 0.8, 0.8, 0.8, true)
	GameTooltip:Show()
end

local function POILeave(self)
	RowLeave(self:GetParent())
	GameTooltip_Hide()
end

local function POIClick(self, button)
	if button == "RightButton" then RowClick(self:GetParent(), button) return end
	local q = self:GetParent().questID
	if not q then return end
	local focused = Focused(q)
	if SOUNDKIT then PlaySound(focused and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
	SetFocus(focused and 0 or q)
end

local function QuestButton(b, questID, done)
	local p = b.poi
	if not p then
		p = CreateFrame("Button", nil, b)
		p:SetSize(POI_SIZE, POI_SIZE)
		local k = POI_SIZE / POI_BLIZZARD
		p.glow = p:CreateTexture(nil, "BACKGROUND")
		p.glow:SetPoint("CENTER")
		p.glow:SetBlendMode("ADD")
		SizeAtlas(p.glow, "UI-QuestPoi-OuterGlow", k * 0.85)
		p.glow:SetAlpha(0.4)
		p.ring = p:CreateTexture(nil, "ARTWORK")
		p.ring:SetPoint("CENTER")
		p.mark = p:CreateTexture(nil, "OVERLAY")
		p.mark:SetPoint("CENTER")
		p.lit = p:CreateTexture(nil, "HIGHLIGHT")
		p.lit:SetPoint("CENTER")
		p.lit:SetBlendMode("ADD")
		SizeAtlas(p.lit, "UI-QuestPoi-InnerGlow", k)
		p:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		p:SetScript("OnEnter", POIEnter)
		p:SetScript("OnLeave", POILeave)
		p:SetScript("OnMouseDown", function(self, button) if button == "LeftButton" then PaintPOI(self, true) end end)
		p:SetScript("OnMouseUp", function(self) PaintPOI(self, false) end)
		p:SetScript("OnClick", POIClick)
		b.poi = p
	end
	done = done and true or false
	local focus = Focused(questID)
	if p.done ~= done or p.focus ~= focus or not p.painted then
		p.done, p.focus, p.painted = done, focus, true
		PaintPOI(p, false)
	end
	p:ClearAllPoints()
	p:SetPoint("TOPLEFT", b, "TOPLEFT", 5, -4)
	p:Show()
end

local function BuildList()
	local y, count = 4, 0
	local hidden = false
	local n = C_QuestLog.GetNumQuestLogEntries() or 0
	local zoneCounts, current = {}, nil
	local zoneTotal, zoneWatched = {}, {}         -- (AzerothVeil: each zone's quests in the log, and in the tracker)
	wipe(headers)
	-- (searching: a quest shows if its name, or its zone's, has what's typed; its zone opens for it)
	local function Matches(info, zone)
		if query == "" then return true end
		return (info.title or ""):lower():find(query, 1, true) or (zone or ""):lower():find(query, 1, true)
	end
	local zoneName
	for i = 1, n do
		local info = C_QuestLog.GetInfo(i)
		if info and info.isHeader then
			current, zoneName = i, info.title
			zoneCounts[i], zoneTotal[i], zoneWatched[i] = 0, 0, 0
			headers[#headers + 1] = info.title
		elseif info and current and not info.isHidden and info.questID then
			zoneTotal[current] = zoneTotal[current] + 1
			if Watched(info.questID) then zoneWatched[current] = zoneWatched[current] + 1 end
			if Matches(info, zoneName) then zoneCounts[current] = zoneCounts[current] + 1 end
		end
	end
	local shownQuests = 0
	for i = 1, n do
		local info = C_QuestLog.GetInfo(i)
		if info then
			if info.isHeader and query ~= "" and (zoneCounts[i] or 0) == 0 then
				hidden, zoneName = true, info.title           -- (searching: a zone with nothing found, left out)
			elseif info.isHeader then
				hidden = query == "" and collapsed[info.title] and true or false
				zoneName = info.title
				local b = Row()
				b.header = info.title
				b.bgBase = 0
				b.title:SetTextColor(0.96, 0.94, 0.88)
				S.Font(b.title, 13)
				b.big = true
				b.sign:SetText(hidden and "+" or "\226\128\147")
				b.sign:Show()
				b.shade:Show()
				b.edge:Show()
				-- (AzerothVeil: folded, its quests tracked / its quests in the log right after its name, in its
				-- font, if wanted: the Quests module)
				local name = info.title or ""
				if hidden and FM.db.questZoneCount and (zoneTotal[i] or 0) > 0 then
					name = ("%s (%d/%d)"):format(name, zoneWatched[i] or 0, zoneTotal[i])
				end
				b.count:Hide()
				local tx = 8
				if S.classic then
					-- (classic: as the game's quest log draws a zone: a dark bar in a thin border, its name in
					-- gold, a gold + or - on its right, no count)
					b.title:SetTextColor(ZONE_INK[1], ZONE_INK[2], ZONE_INK[3])
					b.shade:Hide()
					b.edge:Hide()
					b.bar:Show()
					tx = 10
				end
				-- (one line, in the middle of the bar's height)
				y = Place(b, y + 4, tx, name, nil, nil, 48)
				b:SetHeight(26)
				b.title:ClearAllPoints()
				b.title:SetPoint("LEFT", tx, 0)
				b.title:SetWordWrap(false)
				y = y - (b.title:GetStringHeight() + 8) + 26 + 2
			elseif not info.isHidden and info.questID then
				count = count + 1
				if not hidden and Matches(info, zoneName) then
					shownQuests = shownQuests + 1
					local q = info.questID
					local complete = C_QuestLog.IsComplete(q)
					local failed = C_QuestLog.IsFailed and C_QuestLog.IsFailed(q)
					local b = Row()
					b.questID = q
					b.title:SetTextColor(SoftColor(DiffColor(info.level)))
					-- (no "(Dungeon)" / "(PvP)" tag on the right: the icon left of the name says it)
					local right = 24
					-- (Forever Quest Tint: its sign on a quest new in Forever, its colour on the objectives if it
					-- recolours them, Tint.lua)
					local title = FM.Tint.MarkTitle(q, ("(%d) %s"):format(info.level or 0, info.title or "?"))
					-- (after the name: its kind's icon, then what it asks next: QuestMark)
					title = title .. TypeIcon(q) .. QuestMark(q, info, complete, failed)
					if failed then title = title .. L["  |cffff4040Failed|r"] end
					local or_, og, ob = FM.Tint.ObjectiveColour(q)
					if or_ then b.body:SetTextColor(or_, og, ob) else b.body:SetTextColor(OBJ_INK[1], OBJ_INK[2], OBJ_INK[3]) end
					-- (left of the name: Blizzard's round button, to focus it)
					QuestButton(b, q, complete)
					local indent = 22
					y = Place(b, y + 2, indent, title, ObjectivesText(q, complete, true), Watched(q), right)
				end
			end
		end
	end
	if count == 0 or (query ~= "" and shownQuests == 0) then
		local b = Row()
		b.title:SetTextColor(S.DIM[1], S.DIM[2], S.DIM[3])
		y = Place(b, y + 6, 10, count == 0 and L["No quests."] or L["No quest matches."], nil, nil)
	end
	local maxQ = Constants and Constants.QuestLogConsts and Constants.QuestLogConsts.MAXIMUM_NUM_QUESTS_LOG_CAN_ACCEPT or 25
	topTitle:SetText((L["Quests (%d/%d)"]):format(count, maxQ))
	return y + 6
end

---------------------------------------------------------------------------
-- A quest's details, as Blizzard's quest log gives them: its kind (elite, dungeon, group size), its
-- time left, what it asks, its text, and what it gives (items to receive and to choose from, each
-- with its tooltip and shift-click to link; money, experience, spells, honour)
---------------------------------------------------------------------------
local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d, e, f = pcall(fn, ...)
	if ok then return a, b, c, d, e, f end
end

-- reward item buttons (pooled, like the rows)
local items, itemPool = {}, {}
local ITEM_H = 36

-- AzerothVeil: the game's tooltip beside the log, on the map's side, level with the item (as the dungeon
-- panel's loot: UI/DungeonPanel.lua's TipBeside), not over the mouse
local function TipBeside(owner)
	GameTooltip:SetOwner(owner, "ANCHOR_NONE")
	GameTooltip:ClearAllPoints()
	GameTooltip:SetPoint("TOPRIGHT", owner, "TOPLEFT", (panel:GetLeft() or 0) - (owner:GetLeft() or 0) - 4, 0)
end

local function ItemEnter(self)
	TipBeside(self)
	local ok = false
	if self.currency then
		ok = GameTooltip.SetQuestLogCurrency and pcall(GameTooltip.SetQuestLogCurrency, GameTooltip, self.kind, self.index, detailID)
	elseif self.kind == "reward" or self.kind == "choice" then
		ok = GameTooltip.SetQuestLogItem and pcall(GameTooltip.SetQuestLogItem, GameTooltip, self.kind, self.index, detailID)
	elseif self.kind == "spell" then
		ok = GameTooltip.SetQuestLogRewardSpell and pcall(GameTooltip.SetQuestLogRewardSpell, GameTooltip, self.index, detailID)
	end
	if not ok then GameTooltip:SetText(self.label or "", 1, 1, 1) end
	GameTooltip:Show()
end

local function ItemClick(self, button)
	if button == "RightButton" then QL.Back() return end     -- (AzerothVeil: back to the list)
	local link = Try(GetQuestLogItemLink, self.kind, self.index)
	if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
end

local function NewItem()
	local b = CreateFrame("Button", nil, child)
	b:SetHeight(ITEM_H - 4)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetTexture(S.WHITE)
	b.bg:SetAllPoints()
	b.bg:SetVertexColor(1, 1, 1, 0.04)
	b.edge = b:CreateTexture(nil, "BORDER")
	b.edge:SetTexture(S.WHITE)
	b.edge:SetSize(30, 30)
	b.edge:SetPoint("LEFT", 2, 0)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(28, 28)
	b.icon:SetPoint("CENTER", b.edge, "CENTER")
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.count = S.FontString(b, "OVERLAY", "NumberFontNormal")
	b.count:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", -1, 1)
	b.name = S.Text(b, 11)
	if S.classic then b.name:SetShadowColor(0, 0, 0, 0) end     -- (on the parchment: no shadow)
	b.name:SetPoint("LEFT", b.icon, "RIGHT", 5, 0)
	b.name:SetPoint("RIGHT", -3, 0)
	b.name:SetJustifyH("LEFT")
	b.name:SetWordWrap(true)
	b.name:SetMaxLines(2)
	b:SetScript("OnEnter", function(self) self.bg:SetVertexColor(1, 1, 1, 0.1) ItemEnter(self) end)
	b:SetScript("OnLeave", function(self) self.bg:SetVertexColor(1, 1, 1, 0.04) GameTooltip_Hide() end)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnClick", ItemClick)
	return b
end

local function ReleaseItems()
	for i = #items, 1, -1 do
		items[i]:Hide()
		items[i]:ClearAllPoints()
		itemPool[#itemPool + 1] = items[i]
		items[i] = nil
	end
end

-- items in two columns from y: { kind, index, name, texture, count, quality }
local function ItemGrid(y, list)
	local w = child:GetWidth() - PAD * 2
	local colW = (w - 6) / 2
	for i, it in ipairs(list) do
		local b = tremove(itemPool) or NewItem()
		items[#items + 1] = b
		b.kind, b.index, b.label, b.currency = it[1], it[2], it[3], it[7]
		b.icon:SetTexture(it[4] or 134400)
		b.count:SetText(it[5] and it[5] > 1 and it[5] or "")
		b.name:SetText(it[3] or "")
		local c = it[6] and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[it[6]]
		-- (AzerothVeil: on the parchment, a name in its quality's colour gets a shadow, to read; one in ink none)
		local inked = S.classic and (not it[6] or it[6] <= 1)
		if S.classic then
			b.name:SetShadowOffset(1, -1)
			b.name:SetShadowColor(0, 0, 0, inked and 0 or 0.8)
		end
		if inked then b.name:SetTextColor(INK[1], INK[2], INK[3])
		elseif c then b.name:SetTextColor(c.r, c.g, c.b) else b.name:SetTextColor(1, 1, 1) end
		if c then b.edge:SetVertexColor(c.r, c.g, c.b, 1) else b.edge:SetVertexColor(0, 0, 0, 0.9) end
		b:SetWidth(colW)
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		b:SetPoint("TOPLEFT", child, "TOPLEFT", PAD + col * (colW + 6), -(y + row * ITEM_H))
		b:Show()
	end
	return y + math.ceil(#list / 2) * ITEM_H
end

-- (the classic icons for them: a glowing plus for experience, gold coins, a battle standard for honour)
local XP_ICON = "Interface\\Icons\\Spell_ChargePositive"
local MONEY_ICON = "Interface\\Icons\\INV_Misc_Coin_01"
local HONOR_ICON = "Interface\\Icons\\INV_BannerPVP_02"
local function Rewards(questID)
	local receive, choose = {}, {}
	if C_QuestLog.ShouldShowQuestRewards and Try(C_QuestLog.ShouldShowQuestRewards, questID) == false then return receive, choose end
	local xp = Try(GetQuestLogRewardXP, questID) or Try(GetQuestLogRewardXP)
	if xp and xp > 0 then
		receive[#receive + 1] = { "xp", 0, (BreakUpLargeNumbers and BreakUpLargeNumbers(xp) or xp) .. L[" experience"], XP_ICON }
	end
	local money = Try(GetQuestLogRewardMoney, questID) or Try(GetQuestLogRewardMoney)
	if money and money > 0 then
		receive[#receive + 1] = { "money", 0, GetMoneyString and GetMoneyString(money) or GetCoinTextureString(money), MONEY_ICON }
	end
	local honor = Try(GetQuestLogRewardHonor, questID)
	if honor and honor > 0 then receive[#receive + 1] = { "honor", 0, honor .. L[" honor"], HONOR_ICON } end
	for i = 1, (Try(GetNumQuestLogRewardSpells, questID) or 0) do
		local tex, name = Try(GetQuestLogRewardSpell, i, questID)
		if name then receive[#receive + 1] = { "spell", i, name, tex } end
	end
	for i, cur in ipairs(C_QuestLog.GetQuestRewardCurrencies and Try(C_QuestLog.GetQuestRewardCurrencies, questID) or {}) do
		receive[#receive + 1] = { "reward", i, cur.name, cur.texture, cur.totalRewardAmount, cur.quality, true }
	end
	for i = 1, (Try(GetNumQuestLogRewards, questID) or 0) do
		local name, tex, num, quality = Try(GetQuestLogRewardInfo, i, questID)
		if name then receive[#receive + 1] = { "reward", i, name, tex, num, quality } end
	end
	for i = 1, (Try(GetNumQuestLogChoices, questID, true) or Try(GetNumQuestLogChoices) or 0) do
		local name, tex, num, quality = Try(GetQuestLogChoiceInfo, i, questID)
		if name then choose[#choose + 1] = { "choice", i, name, tex, num, quality } end
	end
	return receive, choose
end

-- its kind and size, as the log's title line gives them; its time left
local function Tags(questID, info)
	local out = {}
	local tag = C_QuestLog.GetQuestTagInfo and Try(C_QuestLog.GetQuestTagInfo, questID)
	if type(tag) == "table" and tag.tagName then out[#out + 1] = tag.tagName end
	if info.suggestedGroup and info.suggestedGroup > 1 then out[#out + 1] = (L["Group: %d"]):format(info.suggestedGroup) end
	local left = Try(GetQuestLogTimeLeft)
	if left and left > 0 then out[#out + 1] = L["Time left: "] .. (SecondsToTime and SecondsToTime(left) or (left .. " s")) end
	local need = Try(GetQuestLogRequiredMoney)
	if need and need > 0 and GetCoinTextureString then out[#out + 1] = L["Requires "] .. GetCoinTextureString(need) end
	return table.concat(out, "   ")
end

-- (AzerothVeil: for the Dungeons module's quest list: the same rewards, the same native tooltips)
QL.Rewards = Rewards
function QL.RewardTooltip(owner, kind, index, questID, label, currency)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	local ok = false
	if currency then
		ok = GameTooltip.SetQuestLogCurrency and pcall(GameTooltip.SetQuestLogCurrency, GameTooltip, kind, index, questID)
	elseif kind == "reward" or kind == "choice" then
		ok = GameTooltip.SetQuestLogItem and pcall(GameTooltip.SetQuestLogItem, GameTooltip, kind, index, questID)
	elseif kind == "spell" then
		ok = GameTooltip.SetQuestLogRewardSpell and pcall(GameTooltip.SetQuestLogRewardSpell, GameTooltip, index, questID)
	end
	if not ok then GameTooltip:SetText(label or "", 1, 1, 1) end
	GameTooltip:Show()
end

local rewardBox
local function RewardBox(y0, y1)
	if not rewardBox then
		rewardBox = CreateFrame("Frame", nil, child)
		S.Panel(rewardBox, { 0, 0, 0, 0.32 }, { 1, 1, 1, 0.06 })
		rewardBox:SetFrameLevel(child:GetFrameLevel())
	end
	rewardBox:ClearAllPoints()
	rewardBox:SetPoint("TOPLEFT", child, "TOPLEFT", 2, -y0)
	rewardBox:SetPoint("TOPRIGHT", child, "TOPRIGHT", -2, -y0)
	rewardBox:SetHeight(y1 - y0)
	rewardBox:Show()
end

local function BuildDetails()
	local q = detailID
	local index = q and C_QuestLog.GetLogIndexForQuestID(q)
	if not index then mode, detailID = "list", nil return BuildList() end
	C_QuestLog.SetSelectedQuest(q)
	if SelectQuestLogEntry then pcall(SelectQuestLogEntry, index) end
	local info = C_QuestLog.GetInfo(index) or {}
	local complete = C_QuestLog.IsComplete(q)
	local description, objectives = GetQuestLogQuestText()
	local y = 6
	-- its name, in gold, its kind's icon after it; level, kind, group, time under it
	-- (classic: on the parchment, in dark ink, as Blizzard's quest log writes a quest's page)
	local CL = S.classic
	local function Head(fs) if CL then fs:SetTextColor(INK[1], INK[2], INK[3]) else fs:SetTextColor(1, 0.82, 0) end end
	-- (AzerothVeil: classic, in the game's own quest fonts as Blizzard's quest page: QuestTitleFont for the name and
	-- the headings, QuestFont for the text, QuestFontNormalSmall for the level; else ours at that size)
	local function Face(fs, name, size) if CL then S.GameFont(fs, name, size) else S.Font(fs, size) end end
	local b = Row()
	Head(b.title)
	Face(b.title, "QuestTitleFont", 16)
	Face(b.body, "QuestFontNormalSmall", 11)
	b.big = true
	if CL then b.body:SetTextColor(INK_SMALL[1], INK_SMALL[2], INK_SMALL[3]) else b.body:SetTextColor(DiffColor(info.level)) end
	local meta = (L["Level %d"]):format(info.level or 0)
	local tags = Tags(q, info)
	if tags ~= "" then meta = meta .. (CL and "   " or "   |cffb8b8b8") .. tags .. (CL and "" or "|r") end
	y = Place(b, y, PAD, FM.Tint.MarkTitle(q, info.title or "?") .. TypeIcon(q), meta, nil)
	-- what it asks, and its objectives
	local function Text(text, r, g, bb)
		if not text or text == "" then return end
		local t = Row()
		if CL and not r then r, g, bb = INK_TEXT[1], INK_TEXT[2], INK_TEXT[3] end
		t.title:SetTextColor(r or 0.92, g or 0.92, bb or 0.9)
		Face(t.title, "QuestFont", 12)
		t.big = true
		y = Place(t, y + 4, PAD, text, nil, nil)
	end
	Text(objectives)
	Text(ObjectivesText(q, complete), FM.Tint.ObjectiveColour(q))
	-- its story
	if description and description ~= "" then
		local h = Row()
		Head(h.title)
		Face(h.title, "QuestTitleFont", 15)
		h.big = true
		y = Place(h, y + 10, PAD, L["Description"], nil, nil)
		Text(description)
	end
	-- what it gives, in a box of its own
	local receive, choose = Rewards(q)
	if rewardBox then rewardBox:Hide() end
	if #receive > 0 or #choose > 0 then
		local top = y + 12
		local h = Row()
		if CL then h.title:SetTextColor(INK[1], INK[2], INK[3]) else h.title:SetTextColor(0.93, 0.85, 0.7) end
		Face(h.title, "QuestTitleFont", 15)
		h.big = true
		if not CL then h.title:SetJustifyH("CENTER") end     -- (classic: on the left, as Blizzard's page has it)
		y = Place(h, top + 6, PAD, L["Rewards"], nil, nil)
		if #choose > 0 then
			local r = Row()
			Head(r.title)
			Face(r.title, "QuestFont", 12)
			r.big = true
			y = Place(r, y + 2, PAD, L["You will be able to choose one of these rewards:"], nil, nil)
			y = ItemGrid(y + 2, choose) + 2
		end
		if #receive > 0 then
			local r = Row()
			Head(r.title)
			Face(r.title, "QuestFont", 12)
			r.big = true
			y = Place(r, y + 4, PAD, #choose > 0 and L["You will also receive:"] or L["You will receive:"], nil, nil)
			y = ItemGrid(y + 2, receive) + 2
		end
		y = y + 6
		if not CL then RewardBox(top, y) end      -- (classic: the rewards on the page itself)
	end
	topTitle:SetText("")
	return y + 6
end

---------------------------------------------------------------------------
-- AzerothVeil: whether a quest can be followed (in the tracker already, or room left there); else the limit
function CanFollow(q)
	if Watched(q) then return true end
	local limit = WatchLimit()
	if limit and WatchCount() >= limit then return false, limit end
	return true
end

-- AzerothVeil: the top of the log. A quest's page: the Back button's bar. The list: the search box across the
-- whole width, and under it the count on the left and Collapse all / Expand all at the end of the line, each if
-- wanted (the Quests module); no bar at all if none is
local function AnyOpen()
	for _, h in ipairs(headers) do if not collapsed[h] then return true end end
	return false
end
function TopLayout(details)
	local top = 0
	back:SetShown(details and true or false)
	if details then
		search:Hide()
		countBar:Hide()
		top = BAR
	else
		local wantSearch = FM.db.questSearch ~= false
		search:SetShown(wantSearch)
		if wantSearch then
			search:ClearAllPoints()
			search:SetPoint("LEFT", panel, "TOPLEFT", search.blizz and 12 or 8, -BAR / 2 - 1)
			search:SetPoint("RIGHT", panel, "TOPRIGHT", -10, -BAR / 2 - 1)
			top = BAR
		end
		local wantCount, wantFold = FM.db.questCount ~= false, FM.db.questFoldAll ~= false
		countBar:SetShown(wantCount or wantFold)
		if wantCount or wantFold then
			countBar:ClearAllPoints()
			countBar:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -top)
			countBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -top)
			topTitle:SetShown(wantCount)
			foldAll:SetShown(wantFold and #headers > 0)
			if wantFold then
				foldAll.label:SetText(AnyOpen() and L["Collapse all"] or L["Expand all"])
				foldAll:SetWidth(max(80, foldAll.label:GetStringWidth() + 26))
			end
			top = top + BAR
		end
	end
	panel.barBg:SetShown(top > 0)
	panel.barBg:SetHeight(max(1, top))
	panel.sep:SetShown(top > 0)
	panel.sep:SetPoint("TOPLEFT", 1, -top)
	panel.sep:SetPoint("TOPRIGHT", 0, -top)
	scroll:SetPoint("TOPLEFT", 2, -(top + 2))
end

local function UpdateButtons()
	local q = detailID
	local details = mode == "details" and q
	if panel.paper then panel.paper:SetShown(details and true or false) end
	TopLayout(details)
	bottom:SetShown(details and true or false)
	scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, details and (BAR + 4) or 4)
	if not details then return end
	-- AzerothVeil: Track: guided with the waypoint arrow, and in the objective tracker (greyed while the tracker
	-- is full and it isn't in it, saying why)
	local f = buttons.follow
	local ok, limit = CanFollow(q)
	local focused = Focused(q)
	f:SetEnabled(ok)
	f:SetActive(ok and focused)
	if not S.classic then f:SetAlpha(ok and 1 or 0.45) end
	if not ok then
		f.tip = { L["Track"], (L["The objective tracker is full (%d quests): untrack one to follow this one."]):format(limit) }
	elseif focused then
		f.tip = { L["Track"], L["Followed with the waypoint arrow. Click to stop (it stays in the objective tracker)."] }
	else
		f.tip = { L["Track"], L["Follow it with the waypoint arrow, and show it in the objective tracker."] }
	end
	-- Share: greyed with its reason
	local share = buttons.share
	local pushable = C_QuestLog.IsPushableQuest and C_QuestLog.IsPushableQuest(q)
	local grouped = IsInGroup() and true or false
	share:SetEnabled(pushable and grouped and true or false)
	if not S.classic then share:SetAlpha(pushable and grouped and 1 or 0.45) end
	share.tip = { L["Share"], not pushable and L["This quest can't be shared."]
		or not grouped and L["You're not in a group."] or L["Offer it to your group."] }
	buttons.abandon.label:SetText(buttons.abandon.armed == q and L["|cffff5050Sure?|r"] or L["Abandon"])
end

function QL.Refresh()
	pending = false
	if not panel or not panel:IsShown() then return end
	-- (a change of the log while the list glides: laid out once it's still, not under the wheel)
	if scrollTo then QL.Changed() return end
	Release()
	ReleaseItems()
	if rewardBox then rewardBox:Hide() end
	local h = mode == "details" and BuildDetails() or BuildList()
	child:SetHeight(max(1, h))
	UpdateButtons()
	ScrollBy(0)
end

-- the quest log changed (events come in bursts): refresh shortly, only if shown
function QL.Changed()
	if pending or not panel or not panel:IsVisible() then return end
	pending = true
	C_Timer.After(0.25, QL.Refresh)
end

function QL.ShowList()
	mode, detailID = "list", nil
	buttons.abandon.armed = nil
	FM.Quests.ClearSelection()
	ScrollTop()
	QL.Refresh()
end

-- AzerothVeil: a right click (on the log, or on a bare spot of the map: Map.lua) while a quest's page shows:
-- back to the list; true if it went back
function QL.Back()
	if not (panel and panel:IsShown() and mode == "details") then return false end
	QL.ShowList()
	return true
end

-- a quest's details; noMove: picked on the map itself, so the map stays where it is; ping: picked in the
-- log or opened from a tracker, its button flashes (not from a click on the button itself)
function QL.ShowDetails(questID, noMove, ping)
	if not panel or not FM.db.questLog then return end      -- (AzerothVeil: the Quests module off: no log)
	if not panel:IsShown() then QL.SetShown(true) end
	mode, detailID = "details", questID
	buttons.abandon.armed = nil
	ScrollTop()
	QL.Refresh()
	if noMove then FM.Quests.Select(questID) else FM.Quests.Focus(questID) end
	-- (as Blizzard's map does from its log; else any ping still going stopped)
	FM.Quests.Ping(ping and questID or nil)
end

---------------------------------------------------------------------------
-- Building, docking, showing
---------------------------------------------------------------------------
local function Build(parent, headerHeight)
	panel = CreateFrame("Frame", nil, parent)
	local E = FM.Map.Edges()          -- (where the window's insides begin: Map.lua)
	panel:SetPoint("TOPRIGHT", -E.r, -E.t)
	panel:SetPoint("BOTTOMRIGHT", -E.r, E.b)
	panel:SetWidth(WIDTH)
	panel:EnableMouse(true)
	panel:Hide()
	local bg = panel:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	if S.classic then
		-- (classic, opaque: the list on the dialog boxes' dark background over black; a quest's page on
		-- the quest frames' parchment, shown with it: UpdateButtons)
		local under = panel:CreateTexture(nil, "BACKGROUND", nil, -8)
		under:SetColorTexture(0, 0, 0, 1)
		under:SetAllPoints()
		-- (the game's own quest log background, else the dialogs' dark one)
		if not (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("QuestLog-main-background")
			and bg:SetAtlas("QuestLog-main-background", false) ~= false) then
			bg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background-Dark", "REPEAT", "REPEAT")
			bg:SetHorizTile(true)
			bg:SetVertTile(true)
		end
		bg:SetVertexColor(1, 1, 1, 1)
		-- (and Blizzard's inset border round the whole log, as round the map)
		local ok, inset = pcall(CreateFrame, "Frame", nil, panel, "InsetFrameTemplate")
		if ok and inset then
			inset:SetPoint("TOPLEFT", -3, 3)
			inset:SetPoint("BOTTOMRIGHT", 3, -3)
			inset:SetFrameLevel(math.max(0, panel:GetFrameLevel() - 1))
		end
		panel.paper = panel:CreateTexture(nil, "BACKGROUND", nil, 2)
		panel.paper:SetTexture("Interface\\QuestFrame\\QuestBG")
		panel.paper:SetTexCoord(0, 0.586, 0, 0.65)
		panel.paper:SetPoint("TOPLEFT", 1, -BAR)
		panel.paper:SetPoint("BOTTOMRIGHT", 0, BAR)      -- (its buttons on the dark below it)
		panel.paper:Hide()
	else
		bg:SetTexture(S.WHITE)
		bg:SetVertexColor(S.BG[1], S.BG[2], S.BG[3], S.BG[4])
	end
	local line = panel:CreateTexture(nil, "BORDER")
	line:SetTexture(S.WHITE)
	line:SetVertexColor(S.BORDER[1], S.BORDER[2], S.BORDER[3], S.BORDER[4])
	line:SetPoint("TOPLEFT")
	line:SetPoint("BOTTOMLEFT")
	line:SetWidth(1)

	-- its bar, a shade of its own under the map's header (the rule between them: the header's, Map.lua);
	-- in the list (AzerothVeil), the search box, and under it the count and Collapse all: TopLayout
	local barBg = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
	panel.barBg = barBg
	barBg:SetTexture(S.WHITE)
	barBg:SetVertexColor(1, 1, 1, 0.04)
	barBg:SetPoint("TOPLEFT", 1, 0)
	barBg:SetPoint("TOPRIGHT", 0, 0)
	barBg:SetHeight(BAR)
	if S.classic then barBg:SetVertexColor(0, 0, 0, 0.5) end
	-- AzerothVeil: the line under the search box: the count on the left, Collapse all / Expand all at its end
	countBar = CreateFrame("Frame", nil, panel)
	countBar:SetHeight(BAR)
	topTitle = S.Text(countBar, 12, S.ACCENT)
	if S.classic then topTitle:SetTextColor(ZONE_INK[1], ZONE_INK[2], ZONE_INK[3]) end
	topTitle:SetPoint("LEFT", countBar, "LEFT", 10, -1)
	foldAll = S.Button(countBar, L["Collapse all"], 100, 20, function()
		if AnyOpen() then
			for _, h in ipairs(headers) do collapsed[h] = true end
		else
			wipe(collapsed)
		end
		QL.Refresh()
	end)
	foldAll:SetPoint("RIGHT", countBar, "RIGHT", -8, -1)
	foldAll.tip = { L["Collapse all / Expand all"], L["Folds every zone of the list, or opens them all."] }
	-- (classic: the game's own search box, as its quest log has it)
	local blizzSearch = false
	if S.classic then
		local ok, sb = pcall(CreateFrame, "EditBox", nil, panel, "SearchBoxTemplate")
		if ok and sb then search, blizzSearch = S.Friz(sb), true end
	end
	search = search or CreateFrame("EditBox", nil, panel)
	search.blizz = blizzSearch          -- (AzerothVeil: laid out by TopLayout, across the whole width)
	search:SetHeight(blizzSearch and 20 or 18)
	search:SetAutoFocus(false)
	search:SetMaxLetters(60)
	local hint, clear
	if blizzSearch then
		hint = search.Instructions or S.Text(search, 11, S.DIM)
		hint:SetText(L["Search Quest Log"])
		clear = search.clearButton or CreateFrame("Button", nil, search)
	else
	S.Font(search, 11)
	search:SetTextColor(S.TEXT[1], S.TEXT[2], S.TEXT[3])
	search:SetTextInsets(20, 6, 0, 0)
	local sbg = search:CreateTexture(nil, "BACKGROUND")
	sbg:SetTexture(S.WHITE)
	sbg:SetVertexColor(0, 0, 0, 0.45)
	sbg:SetAllPoints()
	local sline = search:CreateTexture(nil, "BORDER")
	sline:SetTexture(S.WHITE)
	sline:SetVertexColor(1, 1, 1, 0.12)
	sline:SetPoint("BOTTOMLEFT")
	sline:SetPoint("BOTTOMRIGHT")
	sline:SetHeight(1)
	local glass = search:CreateTexture(nil, "ARTWORK")
	glass:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
	glass:SetSize(12, 12)
	glass:SetPoint("LEFT", 5, 0)
	glass:SetVertexColor(0.7, 0.7, 0.72)
	hint = S.Text(search, 11, S.DIM)
	hint:SetPoint("LEFT", 20, 0)
	hint:SetText(L["Search quests"])
	clear = CreateFrame("Button", nil, search)
	clear:SetSize(14, 14)
	clear:SetPoint("RIGHT", -3, 0)
	local cx = clear:CreateTexture(nil, "ARTWORK")
	cx:SetTexture(MEDIA .. "close")
	cx:SetAllPoints()
	cx:SetVertexColor(0.7, 0.7, 0.72)
	clear:SetScript("OnClick", function() search:SetText("") search:ClearFocus() end)
	clear:Hide()
	end
	search:SetScript("OnTextChanged", function(self)
		local t = self:GetText() or ""
		hint:SetShown(t == "" and not self:HasFocus())
		clear:SetShown(t ~= "")
		local q = t:lower():gsub("^%s+", ""):gsub("%s+$", "")
		if q ~= query then
			query = q
			ScrollTop()
			QL.Refresh()
		end
	end)
	search:SetScript("OnEditFocusGained", function() hint:Hide() end)
	search:SetScript("OnEditFocusLost", function(self) hint:SetShown((self:GetText() or "") == "") end)
	search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	back = S.Button(panel, L["Back"], 70, 20, function() QL.ShowList() end)
	back:SetPoint("TOPLEFT", 4, -3)
	back:Hide()
	local sep = panel:CreateTexture(nil, "BORDER")
	panel.sep = sep
	sep:SetTexture(S.WHITE)
	sep:SetVertexColor(S.BORDER[1], S.BORDER[2], S.BORDER[3], S.BORDER[4])
	sep:SetPoint("TOPLEFT", 1, -BAR)
	sep:SetPoint("TOPRIGHT", 0, -BAR)
	sep:SetHeight(1)

	scroll = CreateFrame("ScrollFrame", nil, panel)
	scroll:SetPoint("TOPLEFT", 2, -(BAR + 2))
	scroll:SetPoint("BOTTOMRIGHT", -8, 4)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(_, d) ScrollBy(d) end)
	-- (resized with the window: the bar fitted to the new height at once, the list laid out again shortly)
	scroll:SetScript("OnSizeChanged", function(self, w)
		if not (child and thumb) then return end
		child:SetWidth(w)
		ScrollBy(0)
		QL.Changed()
	end)
	child = CreateFrame("Frame", nil, scroll)
	child:SetSize(WIDTH - 10, 1)
	scroll:SetScrollChild(child)
	thumb = panel:CreateTexture(nil, "OVERLAY")
	thumb:SetTexture(S.WHITE)
	thumb:SetVertexColor(1, 1, 1, 0.18)
	thumb:SetWidth(3)
	if S.classic then thumb:SetVertexColor(0.75, 0.6, 0.3, 1) end      -- (classic: a gold bar, not a see-through one)
	thumb:Hide()

	-- the details' actions
	bottom = CreateFrame("Frame", nil, panel)
	bottom:SetPoint("BOTTOMLEFT", 1, 1)
	bottom:SetPoint("BOTTOMRIGHT", 0, 1)
	bottom:SetHeight(BAR)
	bottom:Hide()
	local bw = (WIDTH - 10 - 6) / 3
	local function Act(key, label, tip, fn)
		local b = S.Button(bottom, label, bw, 20, fn)
		b.tip = tip
		buttons[key] = b
		return b
	end
	-- AzerothVeil: Track = followed with the waypoint arrow (Navigate's), and put in the objective tracker if it
	-- isn't there; clicked again, the arrow let go (still tracked)
	Act("follow", L["Track"], nil, function()
		local q = detailID
		if not q or not CanFollow(q) then return end
		if Focused(q) then
			SetFocus(0)
		else
			if not Watched(q) then SetWatched(q, true) end
			SetFocus(q)
		end
		QL.Refresh()
	end):SetPoint("BOTTOMLEFT", 5, 3)
	Act("share", L["Share"], { L["Share"], L["Offer it to your group."] }, function()
		if not detailID or not IsInGroup() then return end
		C_QuestLog.SetSelectedQuest(detailID)
		QuestLogPushQuest()
	end):SetPoint("LEFT", buttons.follow, "RIGHT", 3, 0)
	Act("abandon", L["Abandon"], { L["Abandon"], L["Click twice to abandon it."] }, function(self)
		if not detailID then return end
		if self.armed == detailID then
			self.armed = nil
			C_QuestLog.SetSelectedQuest(detailID)
			C_QuestLog.SetAbandonQuest()
			C_QuestLog.AbandonQuest()
			QL.ShowList()
		else
			self.armed = detailID
			UpdateButtons()
			C_Timer.After(4, function() if self.armed then self.armed = nil UpdateButtons() end end)
		end
	end):SetPoint("LEFT", buttons.share, "RIGHT", 3, 0)

	panel:SetScript("OnShow", function() QL.Refresh() end)
	-- AzerothVeil: a right click on the log's own background (the page around its lines): back to the list
	panel:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then QL.Back() end end)
end

-- docked in the map window (called when the window is built)
function QL.Attach(parent, headerHeight)
	Build(parent, headerHeight)
	QL.Apply()                       -- (AzerothVeil: out if wanted and the Quests module has it)
end

-- AzerothVeil: out beside the map: wanted out (FM.db.questPanel, the fold button) and there at all
-- (FM.db.questLog, the Quests module)
local function Out() return FM.db.questPanel and FM.db.questLog and true or false end

-- AzerothVeil: suspended while the Dungeons module's side panel takes its place (Modules/Dungeons.lua):
-- hidden, its preference (FM.db.questPanel) untouched; back as it was when the suspension ends
local suspended = false
function QL.Suspend(on)
	suspended = on and true or false
	if not panel then return end
	if suspended then
		panel:Hide()
	else
		panel:SetShown(Out())
		FM.Map.SetSideWidth(Out() and WIDTH or 0)
		if FM.Map.questsButton then FM.Map.questsButton:SetActive(Out()) end
	end
end

-- AzerothVeil: the Quests module switched the log on or off (FM.db.questLog): shown or gone, its fold button
-- with it; the preference to have it out kept
function QL.Apply()
	if FM.Map.questsButton then FM.Map.questsButton:SetShown(FM.db.questLog and true or false) end
	if not panel then return end
	if not FM.db.questLog and mode == "details" then
		mode, detailID = "list", nil
		buttons.abandon.armed = nil
		FM.Quests.ClearSelection()
	end
	-- (AzerothVeil: the search box gone: what was typed goes with it)
	if FM.db.questSearch == false and query ~= "" then query = "" search:SetText("") end
	if suspended then return end
	panel:SetShown(Out())
	FM.Map.SetSideWidth(Out() and WIDTH or 0)
	if FM.Map.questsButton then FM.Map.questsButton:SetActive(Out()) end
	if panel:IsShown() then QL.Refresh() end     -- (AzerothVeil: the top's lines and the zones' counts as set)
end
function QL.IsSuspended() return suspended end
QL.WIDTH = WIDTH

function QL.SetShown(on)
	if not FM.db.questLog then return end    -- (AzerothVeil: the Quests module off: no log, its preference kept)
	FM.db.questPanel = on and true or false
	if not panel then return end
	if suspended then return end         -- (kept for when the dungeon's panel goes)
	panel:SetShown(on)
	FM.Map.SetSideWidth(on and WIDTH or 0)
	if FM.Map.questsButton then FM.Map.questsButton:SetActive(on) end
end

function QL.IsShown() return panel and panel:IsShown() end

function QL.Toggle() QL.SetShown(not (panel and panel:IsShown())) end

-- open the map and the log (on a quest's details when given one: from the objective tracker, Questie's,
-- another addon's "show this quest"; its button flashes, as from the log)
function QL.Open(questID)
	if not FM.db.questLog then return end    -- (AzerothVeil: the Quests module off: Blizzard's log, Takeover.lua)
	FM.Map.Show()
	-- (AzerothVeil: a quest asked for while a dungeon's panel holds the log's place: back on the world first)
	if suspended and FM.Dungeon.Active() then FM.Dungeon.Back() end
	QL.SetShown(true)
	if questID then QL.ShowDetails(questID, false, true) else QL.ShowList() end
end

-- the quest log key: open the map on the log, or close it if that's what's showing
function QL.ToggleKey()
	if FM.Map.IsShown() and QL.IsShown() then FM.Map.Hide() else QL.Open() end
end
