-- Quests on the map, as Blizzard's own map shows them:
--  * the quest buttons: Blizzard's POIButtonTemplate, set up as its map's quest pins are (the same
--    icons for in progress / ready to turn in / super-tracked, the same click: track and follow),
--    from C_QuestLog.GetQuestsOnMap for the zones the log's quests are in; on the continents' zoom
--    only the followed one, as Blizzard's continent map does (AzerothVeil: or every one, FM.db.questPOIFar);
--  * the "!" of quests to pick up: C_QuestLine for the zones in view, with Blizzard's atlases;
--  * the quest areas: Blizzard's QuestPOIFrame blobs (its fill and border textures), for the followed
--    quest, the one hovered and the one picked in the log, laid on that quest's zone.
--  * with Questie installed, its own map icons too (mirrored from HereBeDragons-Pins, untouched).
-- And every "show this quest" the game asks for opens this map's quest log (QuestLog.lua).
-- Only frames near the view exist; everything is gathered again only when the game says it changed.
local _, FM = ...
local L = FM.L
local Q = {}
FM.Quests = Q

local SELECTED_PIN_LEVEL = 20
-- POIButtonTemplate's Display is one level above the button.
Q.PLAYER_PIN_LEVEL = SELECTED_PIN_LEVEL + 2

local Geo = FM.Geo
local min, max = math.min, math.max
-- (zooms: steps of the wheel from right out, the same whatever the window's size)
local ZONE_ZOOM = FM.Map.QUESTS_ZOOM   -- zoom from which every quest's button shows (else only the followed one) (AzerothVeil: Map.lua, 1.7 as PerfectMap's)
local OFFER_ZOOM = 2.5      -- zoom from which the "!" show
local PATH_ZOOM = FM.W / FM.Map.OPEN_ACROSS * 0.97   -- ... Questie's patrol paths and the quest areas (with the townsfolk: Pins.lua)

local view = { left = 0, top = 0, scale = 1, vw = 1, vh = 1, ppu = 0, zoom = 1 }
local blobLayer, questLayer
local selected, hovered

local function Super()
	local q = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and FM.Plain(C_SuperTrack.GetSuperTrackedQuestID())
	return q and q > 0 and q or nil
end

local function InView(u, v, pad)
	pad = (pad or 24) / view.scale
	return u >= view.left - pad and v >= view.top - pad
		and u <= view.left + view.vw / view.scale + pad and v <= view.top + view.vh / view.scale + pad
end

local function ScreenXY(u, v)
	return (u - view.left) * view.scale, (view.top - v) * view.scale
end

local function Passthrough(f)
	-- (a drag or the wheel over a quest button still moves the map)
	FM.Style.PassClicks(f)
	f:EnableMouseWheel(false)
end

---------------------------------------------------------------------------
-- Quest buttons
---------------------------------------------------------------------------
local pois = {}             -- { questID, u, v, waypoint }
local poiDirty = true
local poiGen = 0
local buttons = {}

local Gather
local fresh = {}
-- the quests' buttons, where the game puts them now; true when that changed
local function GatherPOIs()
	poiDirty = false
	local was = pois
	pois, fresh = fresh, pois
	wipe(pois)
	Gather()
	-- (compared with the last look, field by field: no strings made each second)
	local same = #was == #pois
	if same then
		for i, p in ipairs(pois) do
			local o = was[i]
			if o.questID ~= p.questID or o.waypoint ~= p.waypoint
				or math.abs(o.u - p.u) > 0.05 or math.abs(o.v - p.v) > 0.05 then same = false break end
		end
	end
	if not same then poiGen = poiGen + 1 end
	return not same
end

-- (the buttons into pois). Only quests that are in the log right now, shown in it, each once: the game's
-- list for a map can hold others (one just abandoned or turned in, one it still has cached), which no
-- quest of yours stands for
local inLog, logMaps = {}, {}
function Gather()
	if not FM.db.questPOI or not C_QuestLog.GetQuestsOnMap then return end
	local maps, seen = logMaps, {}
	wipe(maps)
	wipe(inLog)
	for i = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader and not info.isHidden and info.questID and info.questID > 0 then
			inLog[info.questID] = true
			local m = GetQuestUiMapID and GetQuestUiMapID(info.questID)
			-- (a battleground's quests are on its own map, never the world's: Dungeon.lua)
			if m and m > 0 and not (FM.Dungeon and FM.Dungeon.IsBattlegroundMap(m)) then maps[m] = true end
		end
	end
	for m in pairs(maps) do
		for _, q in ipairs(C_QuestLog.GetQuestsOnMap(m) or {}) do
			if q.questID and inLog[q.questID] and q.x and not seen[q.questID] and not q.isMapIndicatorQuest
				and (not HaveQuestData or HaveQuestData(q.questID)) then
				local u, v = Geo.MapToUnits(m, q.x, q.y)
				if u then
					seen[q.questID] = true
					pois[#pois + 1] = { questID = q.questID, u = u, v = v }
				end
			end
		end
	end
	-- the followed quest's next waypoint, when its objective lies on another map (Blizzard's waypoint pin)
	local super = Super()
	if super and inLog[super] and C_QuestLog.GetNextWaypoint then
		local m, x, y = C_QuestLog.GetNextWaypoint(super)
		local u, v
		if m and x then u, v = Geo.MapToUnits(m, x, y) end
		if u then pois[#pois + 1] = { questID = super, u = u, v = v, waypoint = true } end
	end
end

-- AzerothVeil: a quest's level, for "(level) Name" in its tooltip (the Quests module's option): the log's, else
-- the game's for a quest not taken (when it has it), else Questie's database (when it's there); nil if none knows
local function QuestLevel(q)
	local index = C_QuestLog.GetLogIndexForQuestID(q)
	local info = index and C_QuestLog.GetInfo(index)
	local lvl = info and FM.Plain(info.level)
	if type(lvl) == "number" and lvl > 0 then return lvl end
	if C_QuestLog.GetQuestDifficultyLevel then
		local ok, l = pcall(C_QuestLog.GetQuestDifficultyLevel, q)
		l = ok and FM.Plain(l)
		if type(l) == "number" and l > 0 then return l end
	end
	local QL = _G.QuestieLoader
	if QL and QL.ImportModule then
		local ok, db = pcall(QL.ImportModule, QL, "QuestieDB")
		if ok and type(db) == "table" and db.QueryQuestSingle then
			local ok2, l = pcall(db.QueryQuestSingle, q, "questLevel")
			if ok2 and type(l) == "number" and l > 0 then return l end
		end
	end
end
-- AzerothVeil: the letter after a quest's level, as the game's quest addons write it: D a dungeon's, R a raid's,
-- P player versus player, + elite or group, L legendary (the game's tag for it, C_QuestLog.GetQuestTagInfo)
local TAG_LETTER = { [81] = "D", [85] = "D", [62] = "R", [88] = "R", [89] = "R", [41] = "P", [1] = "+", [83] = "L" }
function Q.LevelTag(q)
	local ok, tag = false, nil
	if C_QuestLog.GetQuestTagInfo then ok, tag = pcall(C_QuestLog.GetQuestTagInfo, q) end
	if not (ok and type(tag) == "table") then return "" end
	local letter = TAG_LETTER[FM.Plain(tag.tagID)]
	if letter then return letter end
	local name = FM.Plain(tag.tagName)
	if type(name) == "string" then
		if name:find("PvP") then return "P" end
		if name:find(L["Elite"]) or name:find("Elite") then return "+" end
	end
	return ""
end
-- "(60D) Name": its level and its letter
function Q.LevelText(q, level, name)
	return ("(%d%s) %s"):format(level, Q.LevelTag(q), name)
end

local function TipTitle(q, name)
	if not (FM.db.questTipLevel and name and name ~= "") then return name end
	local lvl = QuestLevel(q)
	return lvl and Q.LevelText(q, lvl, name) or name
end

local function POIEnter(self)
	local q = self:GetQuestID()
	if not q then return end
	self.HighlightTexture:Show()
	Q.Hint(q)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 5, 2)
	local index = C_QuestLog.GetLogIndexForQuestID(q)
	local info = index and C_QuestLog.GetInfo(index)
	local c = info and GetQuestDifficultyColor and GetQuestDifficultyColor(info.level)
	GameTooltip:SetText(TipTitle(q, C_QuestLog.GetTitleForQuestID(q) or ""), c and c.r or 1, c and c.g or 0.82, c and c.b or 0)
	local waypoint = q == Super() and C_QuestLog.GetNextWaypointText and C_QuestLog.GetNextWaypointText(q)
	if waypoint then
		GameTooltip:AddLine("- " .. waypoint, 1, 1, 1, true)
	elseif C_QuestLog.IsComplete(q) then
		GameTooltip:AddLine(QUEST_WATCH_QUEST_READY or L["Ready for turn-in"], 1, 1, 1, true)
	else
		for _, o in ipairs(C_QuestLog.GetQuestObjectives(q) or {}) do
			if o.text and not o.finished then GameTooltip:AddLine("- " .. o.text, 1, 1, 1, true) end
		end
	end
	GameTooltip:Show()
end

local function POILeave(self)
	self.HighlightTexture:Hide()
	GameTooltip:Hide()
	Q.Hint(nil)
end

local function POIClick(self, button)
	-- (Blizzard's own click has tracked and followed it; show its details too, as its map does)
	local q = self:GetQuestID()
	-- (no ping from a click on the button itself: only a quest picked in the log flashes)
	if q and button == "LeftButton" and FM.QuestLog then FM.QuestLog.ShowDetails(q, true) end
end

local function NewButton(parent)
	if not POIButtonUtil and C_AddOns and C_AddOns.LoadAddOn then C_AddOns.LoadAddOn("Blizzard_POIButton") end
	local b = CreateFrame("Button", nil, parent or questLayer, "POIButtonTemplate")
	b:SetScript("OnEnter", POIEnter)
	b:SetScript("OnLeave", POILeave)
	b:HookScript("OnClick", POIClick)
	Passthrough(b)
	return b
end

-- Blizzard's ping on a quest's button as its details open (its MapPinPingTemplate, the same numbers):
-- the minimap's ping widening and blinking twice, two loops, just under the quest buttons, on screen
-- at its pins' 0.65 whatever the zoom
-- (its button waited for up to PING_WAIT s from the first layout after: a quest the game hadn't placed yet
-- (its objectives' spots asked for as it's picked) gets its button a moment later; and the view's jump to a far
-- zone can make that first frame a long one)
local PING_LOOPS, PING_SCALE, PING_WAIT = 2, 0.65, 2
local ping, pingQuest, pingWant, pingBy
-- (a quest inside a dungeon: framed on the dungeon's way in (Q.Focus), so its icon there flashes instead)
local pingSpot                  -- { quest, u, v }

local function StopPing()
	pingQuest, pingWant = nil, nil
	if not ping then return end
	ping.drive:Stop()
	ping.grow:Stop()
	ping:Hide()
end

local function PingLoop()
	ping.loops = ping.loops - 1
	ping.drive:Play()
	ping.grow:Play()
end

local function NewPing(rel)
	ping = CreateFrame("Frame", nil, rel)
	ping:SetSize(70 * PING_SCALE, 70 * PING_SCALE)
	ping:SetFrameLevel(rel:GetFrameLevel() + 3)
	ping:Hide()
	local t = ping:CreateTexture(nil, "BACKGROUND")
	t:SetTexture("Interface/minimap/UI-Minimap-Ping-Expand")
	t:SetSize(50 * PING_SCALE, 50 * PING_SCALE)
	t:SetPoint("CENTER")
	t:SetAlpha(0)
	local drive = ping:CreateAnimationGroup()
	for _, s in ipairs({ { 0, 1, 0 }, { 1, 0, 0.45 }, { 0, 1, 0.575 }, { 1, 0, 0.95 } }) do
		local a = drive:CreateAnimation("Alpha")
		a:SetTarget(t)
		a:SetFromAlpha(s[1])
		a:SetToAlpha(s[2])
		a:SetStartDelay(s[3])
		a:SetDuration(0.2)
		a:SetOrder(1)
	end
	local grow = ping:CreateAnimationGroup()
	grow:SetLooping("REPEAT")
	local g = grow:CreateAnimation("Scale")
	g:SetTarget(t)
	g:SetScaleFrom(0.5, 0.5)
	g:SetScaleTo(1.2, 1.2)
	g:SetDuration(0.575)
	g:SetOrder(1)
	drive:SetScript("OnFinished", function()
		grow:Stop()
		if ping.loops > 0 then PingLoop() else StopPing() end
	end)
	ping.drive, ping.grow, ping.loops = drive, grow, 0
end

-- (on its button where the map now is, x, y from rel's top left (the world's quest layer, else a
-- battleground's map); none there: no ping, as Blizzard's finds no pin to ping. The view just moved there,
-- so its button is looked for a moment before giving up)
local function LayoutPing(x, y, rel, anchor)
	if not (pingQuest or pingWant) then return end
	if pingWant then
		pingBy = pingBy or GetTime() + PING_WAIT
		if GetTime() > pingBy then StopPing() return end
	end
	if not x then
		if pingQuest then StopPing() end
		return
	end
	-- (a battleground's map may be up before the world's quest layer was ever laid out)
	rel = rel or questLayer
	if not rel then return end
	if not ping then NewPing(rel) end
	if ping:GetParent() ~= rel then
		ping:SetParent(rel)
		ping:SetFrameLevel(rel:GetFrameLevel() + 3)
	end
	ping:ClearAllPoints()
	if anchor then ping:SetPoint("CENTER", anchor, "CENTER") else ping:SetPoint("CENTER", rel, "TOPLEFT", x, y) end
	if pingWant then
		pingQuest, pingWant = pingWant, nil
		ping.drive:Stop()
		ping.grow:Stop()
		ping:Show()
		ping.loops = PING_LOOPS
		PingLoop()
	end
end

function Q.Ping(questID)
	StopPing()
	pingWant, pingBy = questID, nil
	FM.Map.MarkDirty()
	if FM.Dungeon and FM.Dungeon.QuestsChanged then FM.Dungeon.QuestsChanged() end
end

-- a quest button set to its quest, as Blizzard's map sets its quest pins (level: its parent's)
local function Dress(b, questID, waypoint, isSuper, gen, level)
	-- (shown first: Blizzard's button sets its own look as it's shown, so ours comes after; and set
	-- again whenever it's shown anew, its quest changed, or the quest followed changed)
	local anew = not b:IsShown()
	if anew then b:Show() end
	if anew or b.fmGen ~= gen or b.fmQuest ~= questID or b.fmWaypoint ~= waypoint or b.fmSuper ~= isSuper then
		b.fmGen, b.fmQuest, b.fmWaypoint, b.fmSuper = gen, questID, waypoint, isSuper
		b:SetQuestID(questID)
		b.Display:ClearAllPoints()
		b.Display:SetPoint("CENTER")
		b:SetSelected(isSuper)
		b:SetStyle(waypoint and POIButtonUtil.Style.Waypoint or POIButtonUtil.GetStyle(questID))
		b:UpdateButtonStyle()
		b:SetFrameLevel(level + (isSuper and SELECTED_PIN_LEVEL or 4))
	end
	-- (Forever Quest Tint: its gradient on the plain turn-in "?" of a quest new in Forever, Tint.lua)
	local icon = b.Display and b.Display.Icon
	if icon and icon.GetAtlas then
		local atlas = icon:GetAtlas()
		FM.Tint.AtlasGradient(icon:GetParent(), icon, atlas == "UI-QuestIcon-TurnIn-Normal" and FM.Tint.IconTinted(questID), atlas)
	end
end

-- AzerothVeil: the followed quest stands out: a soft glow in a colour of its own (not the game's gold) round its
-- button, breathing slowly. And a quest ready to hand in, picked in the log: where it's handed in marked for a
-- few seconds (TURN_IN_SECONDS), its "?" in that glow (Q.Focus finds the spot)
local FOCUS_COLOUR = { 0.35, 0.8, 1 }
local TURN_IN_SECONDS = 10
local focusGlow, turnMark
local turnIn                    -- { quest, u, v }, while it's marked
local function Glow(parent, size)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(size, size)
	f:EnableMouse(false)
	local t = f:CreateTexture(nil, "BACKGROUND")
	t:SetAllPoints()
	local atlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("UI-QuestPoi-OuterGlow")
	if not (atlas and t:SetAtlas("UI-QuestPoi-OuterGlow") ~= false) then t:SetTexture("Interface\\Minimap\\UI-Minimap-Ping-Center") end
	t:SetBlendMode("ADD")
	t:SetVertexColor(FOCUS_COLOUR[1], FOCUS_COLOUR[2], FOCUS_COLOUR[3], 1)
	local g = f:CreateAnimationGroup()
	g:SetLooping("BOUNCE")
	local a = g:CreateAnimation("Alpha")
	a:SetFromAlpha(1)
	a:SetToAlpha(0.45)
	a:SetDuration(0.9)
	g:Play()
	f.glow, f.anim = t, g
	f:Hide()
	return f
end
local function FocusGlow(b)
	if not b then if focusGlow then focusGlow:Hide() end return end
	if not focusGlow then focusGlow = Glow(questLayer, 52) end
	focusGlow:SetFrameLevel(max(0, b:GetFrameLevel() - 1))
	focusGlow:ClearAllPoints()
	focusGlow:SetPoint("CENTER", b, "CENTER")
	if not focusGlow:IsShown() then focusGlow:Show() focusGlow.anim:Play() end
end
local function LayoutTurnIn()
	if not (turnIn and InView(turnIn.u, turnIn.v)) then if turnMark then turnMark:Hide() end return end
	if not turnMark then
		turnMark = Glow(questLayer, 60)
		turnMark.icon = turnMark:CreateTexture(nil, "ARTWORK")
		turnMark.icon:SetSize(26, 26)
		turnMark.icon:SetPoint("CENTER")
		if not (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("UI-QuestIcon-TurnIn-Normal")
			and turnMark.icon:SetAtlas("UI-QuestIcon-TurnIn-Normal") ~= false) then
			turnMark.icon:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
		end
		turnMark:SetFrameLevel(questLayer:GetFrameLevel() + SELECTED_PIN_LEVEL + 1)
	end
	local x, y = ScreenXY(turnIn.u, turnIn.v)
	turnMark:ClearAllPoints()
	turnMark:SetPoint("CENTER", questLayer, "TOPLEFT", x, y)
	if not turnMark:IsShown() then turnMark:Show() turnMark.anim:Play() end
end

-- AzerothVeil: the quests the log's search found (QuestLog.lua): their buttons shown at every zoom, each in a gold glow,
-- the others dimmed; nil while nothing is searched
local SEARCH_COLOUR = { 1, 0.78, 0.2 }
local SEARCH_DIM = 0.35
local searchSet
local searchGlows = {}
Q.SEARCH_COLOUR = SEARCH_COLOUR
Q.Glow = function(parent, size) return Glow(parent, size) end      -- (AzerothVeil: the map's search's too, Find.lua)
local function SearchGlow(i, b)
	local g = searchGlows[i]
	if not g then
		g = Glow(questLayer, 46)
		g.glow:SetVertexColor(SEARCH_COLOUR[1], SEARCH_COLOUR[2], SEARCH_COLOUR[3], 1)
		searchGlows[i] = g
	end
	g:SetFrameLevel(max(0, b:GetFrameLevel() - 1))
	g:ClearAllPoints()
	g:SetPoint("CENTER", b, "CENTER")
	if not g:IsShown() then g:Show() g.anim:Play() end
end
function Q.SetSearch(set)
	searchSet = set
	FM.Map.MarkDirty()
end
-- where the quests of set have their buttons (not their waypoints): l, r, t, b in the world's units, nil if none
function Q.SearchBounds(set)
	if poiDirty then GatherPOIs() end
	local l, r, t, b
	for _, p in ipairs(pois) do
		if set[p.questID] and not p.waypoint and p.u <= FM.W then
			l, r = min(l or p.u, p.u), max(r or p.u, p.u)
			t, b = min(t or p.v, p.v), max(b or p.v, p.v)
		end
	end
	return l, r, t, b
end

local function LayoutPOIs()
	local n, lit = 0, 0
	local focusButton               -- (AzerothVeil: the followed quest's own button, for its glow)
	local pingFor, px, py, pWay = pingQuest or pingWant, nil, nil, nil
	if pingSpot and pingSpot.quest == pingFor and InView(pingSpot.u, pingSpot.v) then
		px, py = ScreenXY(pingSpot.u, pingSpot.v)
		pingFor = nil
	end
	if FM.db.questPOI then
		local super = Super()
		local all = view.zoom >= ZONE_ZOOM or FM.db.questPOIFar     -- (AzerothVeil: at every zoom, the Quests module's option)
		for _, p in ipairs(pois) do
			local found = searchSet and searchSet[p.questID]
			if (all or found or p.questID == super) and InView(p.u, p.v) then
				n = n + 1
				local b = buttons[n]
				if not b then b = NewButton() buttons[n] = b end
				local isSuper = p.questID == super
				local x, y = ScreenXY(p.u, p.v)
				b:SetPoint("CENTER", questLayer, "TOPLEFT", x, y)
				-- (the quest's own button rather than its waypoint's)
				if p.questID == pingFor and (not px or (pWay and not p.waypoint)) then px, py, pWay = x, y, p.waypoint end
				Dress(b, p.questID, p.waypoint, isSuper, poiGen, questLayer:GetFrameLevel())
				if isSuper and (not focusButton or (focusButton.fmWaypoint and not p.waypoint)) then focusButton = b end
				-- (AzerothVeil: searching: the quests found lit, the others dimmed)
				b:SetAlpha((searchSet and not found) and SEARCH_DIM or 1)
				if found then lit = lit + 1 SearchGlow(lit, b) end
			end
		end
	end
	for i = n + 1, #buttons do buttons[i]:Hide() end
	for i = lit + 1, #searchGlows do if searchGlows[i]:IsShown() then searchGlows[i].anim:Stop() searchGlows[i]:Hide() end end
	FocusGlow(focusButton)          -- (AzerothVeil)
	LayoutTurnIn()
	LayoutPing(px, py)
end

-- The quest buttons on a map off the world (a battleground's, Dungeon.lua), as Blizzard's map shows them
-- there: every quest of the log the game places on it. pool: that map's own buttons; parent: what they're
-- on; place(b, x, y): one put at the map's x, y (0-1), returning where from parent's top left
local mapGen = 0                -- (a quest changed: set again)
function Q.LayoutOnMap(pool, parent, m, place)
	local n = 0
	local pingFor, px, py, anchor = pingQuest or pingWant, nil, nil, nil
	if FM.db.questPOI and m and C_QuestLog.GetQuestsOnMap then
		local super, seen = Super(), {}
		local pois = FM.Plain(C_QuestLog.GetQuestsOnMap(m))
		for _, entry in ipairs(pois or {}) do
			local q = FM.Plain(entry)
			local id = q and FM.Plain(q.questID)
			if id and not seen[id] and not FM.Plain(q.isMapIndicatorQuest) then
				local x, y = FM.Plain(q.x), FM.Plain(q.y)
				local index = x and y and FM.Plain(C_QuestLog.GetLogIndexForQuestID(id))
				local info = index and FM.Plain(C_QuestLog.GetInfo(index))
				if info and FM.Plain(info.questID) == id and not FM.Plain(info.isHeader) and not FM.Plain(info.isHidden)
					and (not HaveQuestData or HaveQuestData(id)) then
					seen[id] = true
					if id == pingWant then FM.Dungeon.RevealQuestPin(x, y) end
					n = n + 1
					local b = pool[n]
					if not b then b = NewButton(parent) pool[n] = b end
					local sx, sy = place(b, x, y)
					if id == pingFor then px, py, anchor = sx, sy, b end
					Dress(b, id, false, id == super, mapGen, parent:GetFrameLevel())
				end
			end
		end
	end
	for i = n + 1, #pool do pool[i]:Hide() end
	LayoutPing(px, py, parent, anchor)
end

---------------------------------------------------------------------------
-- Quests to pick up ("!")
---------------------------------------------------------------------------
local offers = {}           -- zoneID -> { { questID, u, v, atlas, alpha, name, line } }
local requested = {}        -- zoneID -> true once asked for
local offerDirty = false
local offerPins = {}
local zones

local OFFER_ATLAS
local function OfferAtlas(questID)
	if not OFFER_ATLAS then
		OFFER_ATLAS = {}
		local C = Enum and Enum.QuestClassification
		if C then
			OFFER_ATLAS[C.Normal or -1] = "QuestNormal"
			OFFER_ATLAS[C.Questline or -2] = "QuestNormal"
			OFFER_ATLAS[C.Recurring or -3] = "UI-QuestPoiRecurring-QuestBang"
			OFFER_ATLAS[C.Meta or -4] = "quest-wrapper-available"
			OFFER_ATLAS[C.Calling or -5] = "Quest-DailyCampaign-Available"
			OFFER_ATLAS[C.Campaign or -6] = "Quest-Campaign-Available"
			OFFER_ATLAS[C.Legendary or -7] = "UI-QuestPoiLegendary-QuestBang"
			OFFER_ATLAS[C.Important or -8] = "importantavailablequesticon"
		end
	end
	local cls = C_QuestInfoSystem and C_QuestInfoSystem.GetQuestClassification and C_QuestInfoSystem.GetQuestClassification(questID)
	return cls and OFFER_ATLAS[cls] or "QuestNormal"
end

local function Zones()
	if zones then return zones end
	zones = {}
	local ZONE = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
	for _, cont in ipairs(Geo.CONTINENTS) do
		for _, info in ipairs(C_Map.GetMapChildrenInfo(cont, nil, true) or {}) do
			if info.mapType == ZONE then
				local r = Geo.Rect(info.mapID)
				if r then zones[#zones + 1] = { id = info.mapID, r = r } end
			end
		end
	end
	-- (the lands off the world map, Zephras Isle: a zone each, at their own place)
	for _, a in ipairs(Geo.AWAY) do
		local r = Geo.Rect(a.map)
		if r then zones[#zones + 1] = { id = a.map, r = r } end
	end
	return zones
end

local function GatherOffers(zone)
	local list, seen = {}, {}
	local showHidden = C_Minimap and C_Minimap.IsTrackingHiddenQuests and C_Minimap.IsTrackingHiddenQuests()
	local function Add(info)
		if not info or not info.questID or seen[info.questID] or info.inProgress then return end
		if info.isHidden and not showHidden then return end
		if C_QuestLog.GetLogIndexForQuestID(info.questID) then return end
		-- (never one already done, or already taken: the game's lists for a zone can still hold them)
		if C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(info.questID) then return end
		if C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(info.questID) then return end
		if info.startMapID and info.startMapID ~= zone then
			local mi = C_Map.GetMapInfo(info.startMapID)
			if not mi or mi.parentMapID ~= zone then return end
		end
		local u, v = Geo.MapToUnits(zone, info.x or 0, info.y or 0)
		if not u then return end
		seen[info.questID] = true
		list[#list + 1] = { questID = info.questID, u = u, v = v, atlas = OfferAtlas(info.questID),
			alpha = info.isHidden and 0.5 or 1, name = info.questName, line = info.questLineName }
	end
	for _, info in ipairs(C_QuestLine.GetAvailableQuestLines(zone) or {}) do Add(info) end
	if C_QuestLine.GetForceVisibleQuests then
		for _, q in ipairs(C_QuestLine.GetForceVisibleQuests(zone) or {}) do Add(C_QuestLine.GetQuestLineInfo(q, zone)) end
	end
	offers[zone] = list
end

local function OfferEnter(self)
	local o = self.offer
	if not o then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 5, 2)
	GameTooltip:SetText(TipTitle(o.questID, o.name or ""), 1, 0.82, 0)
	if o.line and o.line ~= "" then GameTooltip:AddLine(o.line, 0.8, 0.8, 0.8, true) end
	GameTooltip:AddLine(AVAILABLE_QUEST or L["Available Quest"], 1, 1, 1)
	GameTooltip:Show()
end

local function OfferClick(self)
	local o = self.offer
	if o and C_SuperTrack and C_SuperTrack.SetSuperTrackedMapPin and Enum.SuperTrackingMapPinType then
		pcall(C_SuperTrack.SetSuperTrackedMapPin, Enum.SuperTrackingMapPinType.QuestOffer, o.questID)
	end
end

local function NewOffer()
	local b = CreateFrame("Button", nil, questLayer)
	b:SetSize(24, 24)
	b.tex = b:CreateTexture(nil, "ARTWORK")
	b.tex:SetAllPoints()
	b:SetScript("OnEnter", OfferEnter)
	b:SetScript("OnLeave", GameTooltip_Hide)
	b:SetScript("OnClick", OfferClick)
	b:SetFrameLevel(questLayer:GetFrameLevel() + 2)
	Passthrough(b)
	return b
end

local offerShown = {}           -- (the quests drawn this layout: one table, reused)
local function LayoutOffers()
	local n = 0
	if FM.db.questOffers and view.zoom >= OFFER_ZOOM and C_QuestLine and C_QuestLine.GetAvailableQuestLines then
		local x1, y1 = view.left + view.vw / view.scale, view.top + view.vh / view.scale
		local shown = offerShown
		wipe(shown)
		for _, z in ipairs(Zones()) do
			local r = z.r
			if r[2] > view.left and r[1] < x1 and r[4] > view.top and r[3] < y1 then
				if not requested[z.id] then
					requested[z.id] = true
					C_QuestLine.RequestQuestLinesForMap(z.id)
					GatherOffers(z.id)
				end
				for _, o in ipairs(offers[z.id] or {}) do
					if not shown[o.questID] and InView(o.u, o.v) then
						shown[o.questID] = true
						n = n + 1
						local b = offerPins[n]
						if not b then b = NewOffer() offerPins[n] = b end
						if b.offer ~= o then
							b.offer = o
							b.tex:SetAtlas(o.atlas)
							b.tex:SetAlpha(o.alpha)
						end
						b:SetPoint("CENTER", questLayer, "TOPLEFT", ScreenXY(o.u, o.v))
						b:Show()
						-- (Forever Quest Tint: its gradient on the plain yellow "!" of a quest new in Forever)
						FM.Tint.AtlasGradient(b, b.tex, o.atlas == "QuestNormal" and o.alpha >= 1 and FM.Tint.IconTinted(o.questID), o.atlas)
					end
				end
			end
		end
	end
	for i = n + 1, #offerPins do offerPins[i]:Hide() end
end

---------------------------------------------------------------------------
-- Quest areas (Blizzard's blobs)
---------------------------------------------------------------------------
local blobGen = 0            -- bumped when the game says quests' areas may have changed

-- The game's quest area (QuestPOIFrame) is drawn in screen pixels, at the size its frame has when
-- it's drawn: neither its own scale nor its parent's changes it afterwards, it only follows its
-- frame's corner. So, as Blizzard's map does, it's drawn again whenever the zoom changed, in the
-- same frame and from the frame's rectangle as it is now (GetRect): it stays exactly on its ground at
-- any zoom, with nothing to see of the redrawing. Panning only moves it.
local function NewBlob()
	local h = CreateFrame("Frame", nil, blobLayer)
	h:EnableMouse(false)
	local f = CreateFrame("QuestPOIFrame", nil, h)
	f:SetAllPoints(h)
	-- (in the background: at the bottom of its layer, under every icon, path and button)
	h:SetFrameLevel(blobLayer:GetFrameLevel())
	f:SetFrameLevel(blobLayer:GetFrameLevel())
	f:SetFrameStrata(blobLayer:GetFrameStrata())
	f:SetFillTexture("Interface\\WorldMap\\UI-QuestBlob-Inside")
	f:SetBorderTexture("Interface\\WorldMap\\UI-QuestBlob-Outside")
	f:SetFillAlpha(128)
	f:SetBorderAlpha(192)
	f:SetBorderScalar(1.0)
	f:EnableMouse(false)
	h.blob = f
	return h
end

-- the holder over its map's rectangle on the screen now; drawn again when its size on screen changed
local function Place(h)
	local r = h.r
	h:ClearAllPoints()
	h:SetPoint("TOPLEFT", blobLayer, "TOPLEFT", ScreenXY(r[1], r[3]))
	if h.drawnScale ~= view.scale or h.drawnGen ~= blobGen then
		h.drawnScale, h.drawnGen = view.scale, blobGen
		h:SetSize((r[2] - r[1]) * view.scale, (r[4] - r[3]) * view.scale)
		local f = h.blob
		-- (its place and size on screen worked out NOW: the game draws the area from the frame's last
		-- worked-out rectangle, which is otherwise the previous frame's; drawn from that, the area
		-- trailed each zoom step and sprang back. As OpenMap does for Blizzard's own areas)
		h:GetRect()
		f:GetRect()
		f:SetMapID(h.m)
		f:DrawNone()
		f:DrawBlob(h.q, true)
	end
end

-- One holder per quest, kept once drawn: going back to a quest already seen at this zoom only shows it
-- again. The one shown fades in, the one before fades out (by time, as smooth at any frame rate). While
-- the quest log is out and the map rests, the areas of its quests in view are drawn ahead, unseen, one
-- every tenth of a second: a quest hovered in the log then shows at once, with nothing to draw.
local blobOf = {}            -- quest -> its holder
local live = {}              -- holders shown or fading
local active                 -- the one wanted now
local BLOB_FADE = 14

local function InView(r)
	local x1, y1 = view.left + view.vw / view.scale, view.top + view.vh / view.scale
	return r[2] >= view.left and r[1] <= x1 and r[4] >= view.top and r[3] <= y1
end

-- the holder for quest q (made, or kept, for its map now), or nil when it has no area on the map
local function Holder(q)
	local m = GetQuestUiMapID and GetQuestUiMapID(q)
	local r = m and m > 0 and Geo.Rect(m)
	if not r then return nil end
	local h = blobOf[q]
	if not h then
		h = NewBlob()
		h.q, h.alpha, h.target = q, 0, 0
		h:SetAlpha(0)
		h:Hide()
		blobOf[q] = h
	end
	if h.m ~= m then h.m, h.drawnScale = m, nil end
	h.r = r
	return h
end

local function LayoutBlobs()
	local want
	-- (from the zoom the townsfolk and Questie's icons come on at: M's opening zoom; one quest's area at a
	-- time, never more: the one under the cursor, else the one picked, else the one followed)
	if FM.db.questAreas and view.zoom >= PATH_ZOOM then
		local q = hovered or selected or Super()
		if q and q > 0 then want = Holder(q) end
	end
	if want ~= active then
		if active then active.target = 0 end
		active = want
		if want then want.target = 1 live[want] = true end
	end
	for h in pairs(live) do
		if InView(h.r) then
			Place(h)
			if not h:IsShown() then h:Show() end
		elseif h:IsShown() then
			h:Hide()
		end
	end
end

-- every frame: the fades
local function FadeBlobs(elapsed)
	if not next(live) then return end
	local k = 1 - math.exp(-elapsed * BLOB_FADE)
	for h in pairs(live) do
		local a = h.alpha + (h.target - h.alpha) * k
		if math.abs(h.target - a) < 0.01 then a = h.target end
		h.alpha = a
		h:SetAlpha(a)
		if a == 0 and h.target == 0 then h:Hide() live[h] = nil end
	end
end

-- drawn ahead: the log's quests with an area in view, one at a time, once the map has rested a moment
local ahead, aheadScale, aheadGen = {}, nil, nil
local restAt, stale = 0, false
local function DrawAhead()
	if not (FM.db.questAreas and view.zoom >= PATH_ZOOM and FM.QuestLog and FM.QuestLog.IsShown()) then return end
	if aheadScale ~= view.scale or aheadGen ~= blobGen then
		aheadScale, aheadGen = view.scale, blobGen
		restAt, stale = GetTime(), true
		return
	end
	if GetTime() - restAt < 0.3 then return end
	if stale then
		stale = false
		wipe(ahead)
		for i = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
			local info = C_QuestLog.GetInfo(i)
			if info and not info.isHeader and info.questID and info.questID > 0 then ahead[#ahead + 1] = info.questID end
		end
	end
	while #ahead > 0 do
		local h = Holder(table.remove(ahead))
		if h and not live[h] and InView(h.r) and (h.drawnScale ~= view.scale or h.drawnGen ~= blobGen) then
			h:SetAlpha(0)
			h:Show()
			Place(h)
			h:Hide()
			return
		end
	end
end

---------------------------------------------------------------------------
-- Questie's icons, mirrored (as they show on Blizzard's map when Questie is installed)
---------------------------------------------------------------------------
local hbd, questieMap, questieTooltip
local questieDirty = true
local scheduled = false

-- Questie's notes (Type "manual") for its townsfolk kinds: ours show instead. The others it puts on
-- the map (what its search shows on the map, the moonwells, meeting stones...) are mirrored too
local QUESTIE_TOWNSFOLK_KEYS          -- (Questie's townsfolk kinds: QUESTIE_TOWNSFOLK, below)
local function OwnTownsfolkNotes()
	local skip = {}
	local frames = questieMap and questieMap.manualFrames
	if type(frames) ~= "table" then return skip, false end
	for typ, byId in pairs(frames) do
		-- (its townsfolk and profession kinds: ours; "any" (search), "moonwell" and the rest: Questie's)
		if QUESTIE_TOWNSFOLK_KEYS[typ] or type(typ) == "number" then
			for _, names in pairs(byId) do
				for _, name in pairs(names) do
					local f = _G[name]
					if f then skip[f] = true end
				end
			end
		end
	end
	return skip, true
end

local function MirrorQuestie()
	local list = {}
	if not (hbd and _G.Questie and FM.db.pins.questie) then return list end
	local skip, known = OwnTownsfolkNotes()
	for icon, data in pairs(hbd.worldmapPins) do
		local d = icon.data
		local manualOk = d and (d.Type ~= "manual" or (known and not skip[icon]))
		if d and d.Id and manualOk and not icon.hidden and data.instanceID then
			-- (HereBeDragons' world x is the game's second coordinate, y its first)
			local u, v = Geo.WorldToUnits(data.instanceID, data.y, data.x)
			local t = icon.texture
			local file = t and t:GetTexture()
			if u and file then
				-- (its colour and fading: a faded icon (another quest focused, an objective done) stays faded)
				local r, g, b, a = t:GetVertexColor()
				a = (a or 1) * (icon:GetAlpha() or 1)
				local glow
				local gt = icon.glowTexture
				if gt and gt:IsShown() then
					local gr, gg, gb, ga = gt:GetVertexColor()
					glow = { gt:GetTexture(), gr or 1, gg or 1, gb or 1, (ga or 1) * (icon:GetAlpha() or 1) }
				end
				local quest = d.QuestData
				local lines = {}
				if d.Type == "manual" then
					lines[1] = nil
				elseif d.Type == "available" then
					lines[1] = { L["Quest available"], 0.6, 0.9, 0.6, 11 }
				elseif d.Type == "complete" then
					lines[1] = { L["Turn in"], 1, 0.82, 0.2, 11 }
				elseif d.ObjectiveData and d.ObjectiveData.Description then
					lines[1] = { d.ObjectiveData.Description, 1, 1, 1, 11 }
				end
				if d.Name then lines[#lines + 1] = { d.Name, 0.7, 0.7, 0.72, 11 } end
				list[#list + 1] = {
					u = u, v = v, icon = file, tint = { r or 1, g or 1, b or 1, a }, glow = glow,
					-- (Forever Quest Tint: its gradient on Questie's yellow "!" and "?" of a quest new in Forever)
					-- (the icon's path as Questie gave it: Forever Quest Tint keeps it, the texture may answer a file ID)
					fqt = FM.Tint.IconTinted(d.Id) and FM.Tint.QuestieIconTintable(icon.fqtIcon or file, r, g, b) or nil,
					psize = min(max(icon:GetWidth() or 16, 12), 22),
					title = quest and (quest.name or quest.Name) or d.Name or L["Quest"], lines = lines,
					qicon = icon,      -- (Questie's own frame: its tooltip and its click, Pins.lua)
				}
			end
		end
	end
	return list
end

local function RebuildQuestie()
	questieDirty = false
	FM.Pins.SetPins("questie", MirrorQuestie())
end

local function LeaveQuestiePin(b)
	if GameTooltip:GetOwner() ~= b then return end
	local icon = b.questie
	local leave = icon and icon.data == b.questieData and icon:GetScript("OnLeave")
	if leave then pcall(leave, icon) end
	if GameTooltip:GetOwner() == b then GameTooltip:Hide() end
end

local function NewQuestieMapPin(parent, pool)
	local b = CreateFrame("Button", nil, parent)
	b:SetFrameLevel(parent:GetFrameLevel() + 3)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.glow = b:CreateTexture(nil, "BACKGROUND")
	b.glow:SetPoint("CENTER")
	b:EnableMouseWheel(false)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnEnter", function(self)
		local icon, data = self.questie, self.questieData
		if not icon or icon.data ~= data or icon.hidden then return end
		if questieTooltip and questieTooltip.ShowOnTooltip then
			local nearby = { icon }
			for _, pin in ipairs(pool) do
				local other = pin.questie
				if pin ~= self and pin:IsShown() and other and other.data == pin.questieData and not other.hidden
					and (pin.mx - self.mx) ^ 2 + (pin.my - self.my) ^ 2 <= 0.01 ^ 2 then
					nearby[#nearby + 1] = other
				end
			end
			if pcall(questieTooltip.ShowOnTooltip, icon, GameTooltip, self, nearby) then return end
		end
		local quest = data.QuestData
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(quest and (quest.name or quest.Name) or data.Name or L["Quest"])
		if data.ObjectiveData and data.ObjectiveData.Description then
			GameTooltip:AddLine(data.ObjectiveData.Description, 1, 1, 1, true)
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", LeaveQuestiePin)
	b:SetScript("OnHide", LeaveQuestiePin)
	b:SetScript("OnClick", function(self, button)
		if button == "RightButton" then FM.Dungeon.Back() return end
		local icon = self.questie
		local click = icon and icon.data == self.questieData and not icon.hidden and icon:GetScript("OnClick")
		if click then pcall(click, icon, button) end
	end)
	return b
end

-- Questie's frames retain their map-local coordinates even when HereBeDragons cannot project them to the world.
local EMPTY_QUESTIE_FRAMES = {}
function Q.LayoutQuestieOnMap(pool, parent, m, place)
	local n = 0
	local function Add(icon, data)
		if not icon or icon.miniMapIcon or icon.hidden or icon._needsUnload or not icon.data then return end
		if (icon.UiMapID or (data and data.uiMapID)) ~= m then return end
		local x, y = icon.x, icon.y
		local tex = icon.texture
		local file = tex and tex:GetTexture()
		if not file or type(x) ~= "number" or type(y) ~= "number" or x < 0 or x > 100 or y < 0 or y > 100 then return end
		n = n + 1
		local b = pool[n]
		if not b then b = NewQuestieMapPin(parent, pool) pool[n] = b end
		if b.questie ~= icon or b.questieData ~= icon.data then LeaveQuestiePin(b) end
		b.questie, b.questieData = icon, icon.data
		b.mx, b.my = x / 100, y / 100
		local size = min(max(icon:GetWidth() or 16, 12), 22)
		local r, g, blue, a = tex:GetVertexColor()
		local alpha = icon:GetAlpha() or 1
		a = (a or 1) * alpha
		b:SetSize(size, size)
		b.icon:SetTexture(file)
		b.icon:SetTexCoord(tex:GetTexCoord())
		b.icon:SetVertexColor(r or 1, g or 1, blue or 1, a)
		local glow = icon.glowTexture
		if glow and glow:IsShown() then
			b.glow:SetTexture(glow:GetTexture())
			b.glow:SetSize(size * 1.13, size * 1.13)
			local gr, gg, gb, ga = glow:GetVertexColor()
			b.glow:SetVertexColor(gr or 1, gg or 1, gb or 1, (ga or 1) * alpha)
			b.glow:Show()
		else
			b.glow:Hide()
		end
		local tinted = FM.Tint.IconTinted(icon.data.Id) and FM.Tint.QuestieIconTintable(icon.fqtIcon or file, r, g, blue)
		FM.Tint.Gradient(b, b.icon, tinted, file, 0, 1, 0, 1, size, a, "ARTWORK", 1)
		place(b, b.mx, b.my)
		b:Show()
	end
	if m and _G.Questie and FM.db.pins.questie then
		if questieMap and questieMap.questIdFrames then
			for _, frames in pairs(questieMap.questIdFrames) do
				for _, name in pairs(frames) do Add(_G[name]) end
			end
			for _, byId in pairs(questieMap.manualFrames or EMPTY_QUESTIE_FRAMES) do
				for _, frames in pairs(byId) do
					for _, name in pairs(frames) do Add(_G[name]) end
				end
			end
		elseif hbd and hbd.worldmapPins then
			for icon, data in pairs(hbd.worldmapPins) do Add(icon, data) end
		end
	end
	for i = n + 1, #pool do
		local b = pool[i]
		b:Hide()
		b.questie, b.questieData = nil, nil
	end
end

-- Questie's townsfolk: its own icons for them aren't mirrored (Type "manual"); whatever it tracks,
-- ours show instead (the same NPCs from our data: one set of icons, not two)
local QUESTIE_TOWNSFOLK = {
	["Repair"] = "repair", ["Auctioneer"] = "auctioneer", ["Banker"] = "banker", ["Battlemaster"] = "battlemaster",
	["Innkeeper"] = "innkeeper", ["Barber"] = "barber", ["Transmogrifier"] = "transmogrifier",
	["Weapon Master"] = "weaponMaster", ["Stable Master"] = "stable", ["Class Trainer"] = "classTrainer",
	["Portal Trainer"] = "portalTrainer", ["Spirit Healer"] = "spirit", ["Mailbox"] = "mailbox",
	["Food"] = "food", ["Drink"] = "drink", ["Reagents"] = "reagents", ["Trade Goods"] = "tradeGoods",
	["Bags"] = "bags", ["Potions"] = "potions", ["Ammo"] = "ammo", ["Poisons"] = "poisons", ["Flight Master"] = "flight",
}
QUESTIE_TOWNSFOLK_KEYS = QUESTIE_TOWNSFOLK
-- (only when a kind is turned on in Questie: what's then turned off here stays off, until Questie's
-- switch for it goes off and on again. FM.db.questieSeen: Questie's switches as last seen)
local function SyncQuestieTownsfolk()
	local Qs, QL = _G.Questie, _G.QuestieLoader
	local cfg = Qs and Qs.db and Qs.db.profile and Qs.db.profile.townsfolkConfig
	if type(cfg) ~= "table" then return end
	local first = FM.db.questieSeen == nil      -- (the first look only notes them: the user's choices stand)
	FM.db.questieSeen = FM.db.questieSeen or {}
	local seen, changed = FM.db.questieSeen, false
	-- (AzerothVeil: turned on as the module's setting it is: the flight masters the Transports module's, the
	-- rest the Icons module's; never the engine's switch itself, which the module writes)
	local MM = FM.Modules
	local function Follow(questieKey, ours)
		local on = cfg[questieKey] and true or false
		local key = tostring(questieKey)
		local owner = ours == "flight" and "transports" or "icons"
		local m = MM and MM:Get(owner)
		if on and not first and not seen[key] and m and m.settingByKey[ours] and not MM:GetSetting(owner, ours) then
			MM:SetSetting(owner, ours, true)
			changed = true
		end
		seen[key] = on
	end
	for qk, ours in pairs(QUESTIE_TOWNSFOLK) do Follow(qk, ours) end
	-- (professions: Questie keys them by profession)
	local ok, QP = false, nil
	if QL then ok, QP = pcall(QL.ImportModule, QL, "QuestieProfessions") end
	if ok and QP and type(QP.professionKeys) == "table" then
		for name, id in pairs(QP.professionKeys) do Follow(id, "prof_" .. name) end
	end
	if changed and FM.Menu then FM.Menu.Refresh() end
end

-- Questie's patrol paths (its QuestieWaypoints), drawn again as lines on our map: its colour and
-- opacity settings, shown while their NPC's icon is. One frame laid out in world units, scaled and
-- moved as a whole; rebuilt only when Questie's paths change.
local QW, pathCanvas
local pathsDirty = true
local lines, outlines = {}, {}
local nLines, linesScale = 0, nil

local function Line(set, i, layer, sub)
	local l = set[i]
	if not l then
		l = pathCanvas:CreateLine(nil, layer, nil, sub)
		set[i] = l
	end
	return l
end

local function BuildPaths()
	pathsDirty = false
	local n = 0
	if QW and QW.paths and _G.Questie and FM.db.pins.questie then
		pathCanvas = pathCanvas or CreateFrame("Frame", nil, FM.Map.pathLayer)
		pathCanvas:SetSize(FM.W, FM.H)
		for path in pairs(QW.paths) do
			local ok, a = pcall(QW.WorldMapAlpha, path)
			if ok and a and path.uiMapId and path.points then
				local okc, c = pcall(QW.Color, path)
				if not okc or type(c) ~= "table" then c = { 1, 0.7, 0.2, 1 } end
				local pu, pv
				for _, p in ipairs(path.points) do
					local u, v = Geo.MapToUnits(path.uiMapId, p.x / 100, p.y / 100)
					if u and pu then
						n = n + 1
						local o = Line(outlines, n, "ARTWORK", 0)
						o:SetColorTexture(0, 0, 0, 0.8 * a)
						o:SetStartPoint("TOPLEFT", pathCanvas, pu, -pv)
						o:SetEndPoint("TOPLEFT", pathCanvas, u, -v)
						o:Show()
						local l = Line(lines, n, "ARTWORK", 1)
						l:SetColorTexture(c[1], c[2], c[3], (c[4] or 1) * a)
						l:SetStartPoint("TOPLEFT", pathCanvas, pu, -pv)
						l:SetEndPoint("TOPLEFT", pathCanvas, u, -v)
						l:Show()
					end
					pu, pv = u, v
				end
			end
		end
	end
	for i = n + 1, nLines do lines[i]:Hide() outlines[i]:Hide() end
	nLines, linesScale = n, nil
end

local function LayoutPaths()
	if pathsDirty then BuildPaths() end
	if not pathCanvas then return end
	-- (from the zoom Questie's icons show from, as they do)
	if nLines == 0 or view.zoom < PATH_ZOOM then pathCanvas:Hide() return end
	-- (a frame of W x H units at the view's scale: its offsets and line widths are in its own units)
	pathCanvas:SetScale(view.scale)
	pathCanvas:SetPoint("TOPLEFT", FM.Map.pathLayer, "TOPLEFT", -view.left, view.top)
	if linesScale ~= view.scale then
		linesScale = view.scale
		for i = 1, nLines do
			outlines[i]:SetThickness(4.5 / view.scale)
			lines[i]:SetThickness(2.5 / view.scale)
		end
	end
	pathCanvas:Show()
end

local function RefreshQuestie()
	if FM.Dungeon.Active() then FM.Dungeon.QuestsChanged(true) else RebuildQuestie() end
end

local function QuestieChanged()
	questieDirty = true
	if scheduled or not (FM.Map and FM.Map.IsShown()) then return end
	scheduled = true
	C_Timer.After(0.15, function()
		scheduled = false
		if questieDirty and FM.Map.IsShown() then RefreshQuestie() end
	end)
end

---------------------------------------------------------------------------
-- Driven by the map
---------------------------------------------------------------------------
function Q.Layout(left, top, scale, vw, vh, ppu, zoom)
	if questieDirty and not FM.Dungeon.Active() then RebuildQuestie() end
	view.left, view.top, view.scale, view.vw, view.vh, view.ppu, view.zoom = left, top, scale, vw, vh, ppu, zoom or 1
	if not questLayer then blobLayer, questLayer = FM.Map.blobLayer, FM.Map.questLayer end
	if poiDirty then GatherPOIs() end
	LayoutPOIs()
	LayoutOffers()
	LayoutBlobs()
	LayoutPaths()
end

-- a quest under the cursor in the log: its area on the map (only that drawn again, not the whole map)
-- Only once the cursor rests on it a moment: the row lights at once, and running the cursor down the list
-- (or the list gliding under it) draws nothing on the map on the way
local HINT_REST = 0.12
local hintWant, hintAt, hintPending = nil, 0, false
function Q.Hint(questID)
	hintWant, hintAt = questID, GetTime()
	hintPending = hintWant ~= hovered
end
local function ApplyHint()
	if not hintPending or GetTime() - hintAt < HINT_REST then return end
	hintPending = false
	hovered = hintWant
	if blobLayer then LayoutBlobs() else FM.Map.MarkDirty() end
end

local tickAcc, offerAcc, poiAcc = 0, 0, 0
function Q.Tick(elapsed)
	ApplyHint()
	FadeBlobs(elapsed)
	tickAcc = tickAcc + elapsed
	if tickAcc < 0.1 then return end
	tickAcc = 0
	DrawAhead()
	-- (the game fills in where a new quest's objectives are a little after it's taken, not always
	-- saying so: looked at again each second while the map is open, laid out again only on a change)
	poiAcc = poiAcc + 0.1
	if poiAcc >= 1 then
		poiAcc = 0
		if FM.db.questPOI and GatherPOIs() then FM.Map.MarkDirty() end
	end
	if offerDirty then
		offerAcc = offerAcc + 0.1
		if offerAcc >= 0.5 then
			offerAcc, offerDirty = 0, false
			for zone in pairs(requested) do GatherOffers(zone) end
			FM.Map.MarkDirty()
		end
	end
end

function Q.OnShow()
	poiDirty = true
	SyncQuestieTownsfolk()
	if questieDirty and not FM.Dungeon.Active() then RebuildQuestie() end
	pathsDirty = true
end

-- (Questie can hide or show its icons without telling the pin library: look again at each opening)
function Q.OnHide()
	StopPing()
	questieDirty = true
	hovered, hintWant, hintPending = nil, nil, false
end

function Q.OnToggle()
	poiDirty = true
	questieDirty = true
	pathsDirty = true
	if FM.Map and FM.Map.IsShown() then
		RefreshQuestie()
		FM.Dungeon.QuestsChanged()
		FM.Map.MarkDirty()
	end
end

---------------------------------------------------------------------------
-- Picking a quest: its area shows; Focus also brings it into view
---------------------------------------------------------------------------
-- a quest to be done inside a dungeon or raid: where its way in is (u, v). The log lists such quests
-- under the dungeon's name; else the game's tag and the map it gives the quest name it
local INSTANCE_TAGS = { [81] = true, [85] = true, [62] = true, [88] = true, [89] = true }
local function DungeonEntrance(questID)
	if not (FM.Pins and FM.Pins.InstanceSpot) then return nil end
	local header, found
	for i = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
		local info = C_QuestLog.GetInfo(i)
		if info then
			if info.isHeader then header = info.title
			elseif info.questID == questID then found = true break end
		end
	end
	local u, v
	if found and header then u, v = FM.Pins.InstanceSpot(header) end
	if not u then
		local tag = C_QuestLog.GetQuestTagInfo and C_QuestLog.GetQuestTagInfo(questID)
		local m = type(tag) == "table" and INSTANCE_TAGS[tag.tagID] and GetQuestUiMapID and GetQuestUiMapID(questID)
		local info = m and m > 0 and C_Map.GetMapInfo(m)
		if info and info.name then u, v = FM.Pins.InstanceSpot(info.name) end
	end
	return u, v
end

-- AzerothVeil: where a quest ready to hand in is handed in. The game's button for it can stay where its
-- objectives were on this client: Questie's turn-in "?" for it first (its own data: the one nearest you), else
-- the game's next waypoint for it; nil if neither knows
local function TurnInSpot(questID)
	local best, bu, bv
	local pu, pv = Geo.UnitUnits("player")
	for icon, data in pairs(hbd and _G.Questie and hbd.worldmapPins or {}) do
		local d = icon.data
		if d and d.Type == "complete" and d.Id == questID and data.instanceID then
			local u, v = Geo.WorldToUnits(data.instanceID, data.y, data.x)
			if u then
				local dist = pu and ((u - pu) ^ 2 + (v - pv) ^ 2) or 0
				if not best or dist < best then best, bu, bv = dist, u, v end
			end
		end
	end
	if bu then return bu, bv end
	if C_QuestLog.GetNextWaypoint then
		local ok, m, x, y = pcall(C_QuestLog.GetNextWaypoint, questID)
		m, x, y = FM.Plain(m), FM.Plain(x), FM.Plain(y)
		if ok and m and x and y then return Geo.MapToUnits(m, x, y) end
	end
end

function Q.Focus(questID)
	selected = questID
	pingSpot = nil
	if poiDirty then GatherPOIs() end
	local u, v
	for _, p in ipairs(pois) do
		if p.questID == questID and not p.waypoint then u, v = p.u, p.v break end
	end
	-- AzerothVeil: ready to hand in: framed where it's handed in, marked there a few seconds (and pinged there)
	turnIn = nil
	if FM.Plain(C_QuestLog.IsComplete(questID)) then
		local tu, tv = TurnInSpot(questID)
		if tu then
			u, v = tu, tv
			pingSpot = { quest = questID, u = tu, v = tv }
			local mark = { quest = questID, u = tu, v = tv }
			turnIn = mark
			C_Timer.After(TURN_IN_SECONDS, function()
				if turnIn == mark then turnIn = nil FM.Map.MarkDirty() end
			end)
		end
	end
	local m = GetQuestUiMapID and FM.Plain(GetQuestUiMapID(questID))
	local dungeon = FM.Dungeon
	local battleground = m and m > 0 and dungeon and dungeon.IsBattlegroundMap(m)
	local worldTurnIn = u and FM.Plain(C_QuestLog.IsComplete(questID))
	-- A battleground can also have a rectangle on the continent. Open its own map for the quest.
	if battleground and not worldTurnIn and dungeon.OpenMap(m) then
		FM.Map.MarkDirty()
		return
	end
	-- (inside a dungeon: its way in, unless it's done and has its hand-in on the map)
	if not worldTurnIn then
		local du, dv = DungeonEntrance(questID)
		if du then u, v = du, dv pingSpot = { quest = questID, u = du, v = dv } end
	end
	if not u and m and m > 0 and dungeon and not battleground and not Geo.Rect(m) and dungeon.OpenMap(m) then
		FM.Map.MarkDirty()
		return
	end
	if dungeon then dungeon.ToWorld() end
	if u then
		FM.Map.Glide(FM.Map.SetView, u, v, 140)         -- (AzerothVeil: gliding there)
	else
		local r = m and m > 0 and Geo.Rect(m)
		if r then
			FM.Map.Glide(FM.Map.SetView, (r[1] + r[2]) / 2, (r[3] + r[4]) / 2, max(r[2] - r[1], (r[4] - r[3]) * 1.5) * 1.1)
		end
	end
	FM.Map.MarkDirty()
end

function Q.Select(questID)
	selected = questID
	FM.Map.MarkDirty()
end


function Q.ClearSelection()
	selected = nil
	FM.Map.MarkDirty()
end

---------------------------------------------------------------------------
-- Every "show this quest" the game does (tracker clicks, its menu) opens our map and log
---------------------------------------------------------------------------
local function HookQuestDetails()
	if Q.hooked or not _G.QuestMapFrame_OpenToQuestDetails then return end
	Q.hooked = true
	hooksecurefunc("QuestMapFrame_OpenToQuestDetails", function(questID)
		if InCombatLockdown() or not questID then return end
		-- (AzerothVeil: ours not used: Blizzard's log keeps it, Takeover.lua)
		if not FM.db.replaceQuestLog then FM.Takeover.KeepNative() return end
		FM.QuestLog.Open(questID)
	end)
end

---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "ADDON_LOADED", "QUEST_LOG_UPDATE", "QUEST_POI_UPDATE",
	"QUEST_WATCH_LIST_CHANGED", "SUPER_TRACKING_CHANGED", "QUESTLINE_UPDATE", "QUEST_ACCEPTED", "QUEST_TURNED_IN",
	"QUEST_REMOVED" }) do
	pcall(ev.RegisterEvent, ev, e)      -- (one the client lacks mustn't keep the others from being heard)
end
ev:SetScript("OnEvent", function(_, event, arg)
	if event == "PLAYER_LOGIN" then
		-- Questie's icons are in its own copy of HereBeDragons-Pins (a Questie module now, not
		-- LibStub's: that one is other addons', without them); an older Questie: LibStub's
		local QLd = _G.QuestieLoader
		local ok, mod = false, nil
		if QLd and QLd.ImportModule then ok, mod = pcall(QLd.ImportModule, QLd, "HBDPins") end
		if ok and type(mod) == "table" and type(mod.worldmapPins) == "table" then
			hbd = mod
		else
			local LibStub = _G.LibStub
			hbd = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
		end
		if hbd then
			for _, fn in ipairs({ "AddWorldMapIconMap", "AddWorldMapIconWorld", "RemoveWorldMapIcon", "RemoveAllWorldMapIcons" }) do
				if hbd[fn] then hooksecurefunc(hbd, fn, QuestieChanged) end
			end
		end
		-- Questie's patrol paths: its map module is told whenever they change
		local QL = _G.QuestieLoader
		if QL then
			local okMap, map = pcall(QL.ImportModule, QL, "QuestieMap")
			if okMap and type(map) == "table" then questieMap = map end
			local okTip, tooltip = pcall(QL.ImportModule, QL, "MapIconTooltip")
			if okTip and type(tooltip) == "table" then questieTooltip = tooltip end
			local ok1, waypoints = pcall(QL.ImportModule, QL, "QuestieWaypoints")
			local ok2, wmap = pcall(QL.ImportModule, QL, "WaypointMap")
			if ok1 and type(waypoints) == "table" then
				QW = waypoints
				-- (Questie hiding, showing or fading its icons (a quest focused in its tracker, an objective
				-- done...) tells the map library nothing, only its paths: heard here, mirrored at once)
				if type(QW.OwnerChanged) == "function" then hooksecurefunc(QW, "OwnerChanged", QuestieChanged) end
			end
			-- (a quest focused in Questie's tracker: our map, when open, goes to it as Blizzard's would)
			local ok3, TU = pcall(QL.ImportModule, QL, "TrackerUtils")
			if ok3 and type(TU) == "table" and type(TU.FocusQuest) == "function" then
				hooksecurefunc(TU, "FocusQuest", function(_, questId)
					QuestieChanged()
					if type(questId) == "number" and FM.Map and FM.Map.IsShown() then Q.Focus(questId) end
				end)
			end
			if ok3 and type(TU) == "table" and type(TU.UnFocus) == "function" then hooksecurefunc(TU, "UnFocus", QuestieChanged) end
			if ok2 and type(wmap) == "table" and wmap.Invalidate then
				hooksecurefunc(wmap, "Invalidate", function()
					pathsDirty = true
					if FM.Map and FM.Map.IsShown() then FM.Map.MarkDirty() end
				end)
			end
		end
		HookQuestDetails()
		return
	elseif event == "ADDON_LOADED" then
		if arg == "Blizzard_UIPanels_Game" or arg == "Blizzard_WorldMap" then HookQuestDetails() end
		return
	elseif event == "QUESTLINE_UPDATE" then
		if arg then wipe(requested) end      -- (the game wants the zones asked for again)
		offerDirty = true
		return
	end
	poiDirty = true
	mapGen = mapGen + 1
	if FM.Dungeon and FM.Dungeon.QuestsChanged then FM.Dungeon.QuestsChanged() end
	if event == "QUEST_POI_UPDATE" or event == "QUEST_LOG_UPDATE" then blobGen = blobGen + 1 end
	if event ~= "SUPER_TRACKING_CHANGED" then offerDirty = true end
	if FM.Map and FM.Map.IsShown() then FM.Map.MarkDirty() end
	if FM.QuestLog then FM.QuestLog.Changed() end
end)
