-- Blizzard's map and quest log made unneeded: whatever would open them opens ours instead, and does
-- there what it would have done there.
--  * The M and L keys never reach them (Core.lua's override bindings).
--  * Anything else (the micro menu's and the minimap's buttons, a quest's "show on map", a map pin's link in
--    chat, other addons) still opens them: they're made unseen at once and hidden on the next frame, ours
--    opened where they were sent.
-- Keep the world map in the game's panel manager. Writing its layout attributes taints the native opening
-- path, including the protected READ emote when a quest is clicked in combat. Outside combat, close it
-- through the manager on the next frame so it releases the panel slot. In combat, pause quest tracker
-- header clicks before they open the native map. Other native openings stay with Blizzard.
-- Standalone classic quest logs use their own closing path.
local _, FM = ...
local T = {}
FM.Takeover = T

local at                        -- GetTime() of the last time it was taken over (one action = one frame)
local wasOpen, wasLog           -- ours, before that
local pendingClose = {}
local pendingApply = false
local nativeAt                  -- AzerothVeil: GetTime() of a show of Blizzard's map left to it (T.KeepNative)

-- the game's classic quest log, by every name a client gives it (and the addons Questie knows of)
local LOG_NAMES = { "QuestLogFrame", "ClassicQuestLog", "QuestLogExFrame" }
local logs = {}                 -- frame -> true: a classic quest log found (and hooked)

local function MapOn() return FM.db and FM.db.replaceM end
local function LogOn() return FM.db and FM.db.replaceQuestLog end
function T.MapStopped() return MapOn() and true or false end

-- The tracker opens the native map before our quest-details post-hook can run. Disable only its
-- quest header buttons so both mouse clicks and clicks forwarded by a secure button are stopped.
local QUEST_TRACKERS = { "QuestObjectiveTracker", "CampaignQuestObjectiveTracker" }
local questTrackers, disabledHeaders = {}, {}

local function PauseQuestHeaders(tracker)
	if not InCombatLockdown() or not (MapOn() or LogOn()) or not tracker.usedBlocks then return end
	for _, blocks in pairs(tracker.usedBlocks) do
		for _, block in pairs(blocks) do
			local header = block.HeaderButton
			if header and not header:IsForbidden() and not header:IsProtected() and FM.Plain(header:IsEnabled()) then
				header:Disable()
				disabledHeaders[header] = true
			end
		end
	end
end

local function HookQuestTrackers()
	for _, name in ipairs(QUEST_TRACKERS) do
		local tracker = _G[name]
		if tracker and tracker.Update and not questTrackers[tracker] then
			questTrackers[tracker] = true
			hooksecurefunc(tracker, "Update", PauseQuestHeaders)
			PauseQuestHeaders(tracker)
		end
	end
end

-- (the same action, still: its SetMapID / its toggling come after it was shown)
local function Now() return not InCombatLockdown() and at ~= nil and at == GetTime() end

-- (out of the panel manager, or back in it: its attributes, read by the game's GetUIPanelWindowInfo; with
-- "defined" cleared it reads its UIPanelWindows entry again)
local function Unmanage(f, out)
	if not f or InCombatLockdown() then return end
	if out then
		f:SetAttribute("UIPanelLayout-defined", true)
		f:SetAttribute("UIPanelLayout-area", nil)
	elseif f:GetAttribute("UIPanelLayout-defined") and not f:GetAttribute("UIPanelLayout-area") then
		f:SetAttribute("UIPanelLayout-defined", nil)
	end
end

local function Close(f)
	if not f then return end
	if not LogOn() then
		pendingClose[f] = nil
		f:SetAlpha(1)
		return false
	end
	if InCombatLockdown() and f:IsProtected() then
		f:SetAlpha(0)
		pendingClose[f] = true
		return true
	end
	pendingClose[f] = nil
	if f:IsShown() then f:Hide() end
	f:SetAlpha(1)
	Unmanage(f, true)            -- (its own code may have put itself back in, showing)
	return true
end

-- the options applied (only out of combat; else as the combat ends)
function T.Apply()
	if InCombatLockdown() then pendingApply = true return end
	pendingApply = false
	for f in pairs(logs) do Unmanage(f, LogOn()) end
end

---------------------------------------------------------------------------
-- What it would have done, done on ours
---------------------------------------------------------------------------
local function TakeMap(f)
	if not MapOn() or InCombatLockdown() then return end
	f:SetAlpha(0)                 -- (not seen for the frame it's open)
	local shownAt = GetTime()
	C_Timer.After(0, function()
		-- (AzerothVeil: opened for its quest log while ours isn't used: Blizzard's stays, ours goes)
		if nativeAt == shownAt then
			f:SetAlpha(1)
			FM.Map.Hide()
			return
		end
		if MapOn() and not InCombatLockdown() and f:IsShown() then HideUIPanel(f) end
		f:SetAlpha(1)
	end)
	if Now() then return end
	at = GetTime()
	wasOpen = FM.Map.IsShown() and true or false
	wasLog = FM.QuestLog.IsShown() and true or false
	FM.Map.Show()
end

-- The classic quest log (LOG_NAMES), where the client has one: a quest picked just before
-- (SelectQuestLogEntry in the same frame, as Questie does): its details; else the list
local pickedAt, picked
local function OnSelect(index)
	pickedAt, picked = GetTime(), index
end
local function TakeQuestLog(f)
	if not LogOn() then return end
	local q
	if pickedAt == GetTime() and picked and picked > 0 then
		local info = C_QuestLog.GetInfo and C_QuestLog.GetInfo(picked)
		q = info and not info.isHeader and info.questID or nil
		if not q and GetQuestLogTitle then q = select(8, GetQuestLogTitle(picked)) end
	end
	f:SetAlpha(0)
	C_Timer.After(0, function()
		if Close(f) then FM.QuestLog.Open(q) end
	end)
end

-- (sent to a map: a link, an addon's "show on map")
local function OnSetMapID(_, mapID)
	if Now() and mapID then
		FM.Map.ShowMapID(mapID)
		FM.Map.MarkDirty()
	end
end

-- M (from a button): closes ours if it was open
local function OnToggleSelf()
	if Now() and wasOpen then FM.Map.Hide() end
end

-- AzerothVeil: Blizzard's map shown in this frame for its quest log, which ours doesn't replace (the Quests
-- module off, or "Replace Blizzard's quest log" off): left to Blizzard, as WoW does without AzerothVeil.
-- Called from post-hooks of the same action (the L key, the objective tracker's "show this quest").
function T.KeepNative()
	if LogOn() or InCombatLockdown() then return end
	nativeAt = GetTime()
end

-- L (from a button): our log, as our L key does it
local function OnToggleQuestLog()
	if not LogOn() then T.KeepNative() return end
	if not Now() then return end
	if wasOpen and wasLog then FM.Map.Hide() else FM.QuestLog.Open() end
end

local function OnOpenQuestLog(_, mapID)
	if not LogOn() then T.KeepNative() return end
	if not Now() then return end
	if LogOn() then FM.QuestLog.Open() end
	if mapID then FM.Map.ShowMapID(mapID) end
end

-- a map pin from chat (or anything opening the map to your waypoint): ours, on the pin
local function OnPingWaypoint()
	if not MapOn() or InCombatLockdown() then return end
	local wp = C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
	if not wp or not wp.position then return end
	FM.Map.Show()
	FM.Map.ShowSpot(wp.uiMapID, wp.position.x, wp.position.y)   -- (its pin: Pins.lua, on USER_WAYPOINT_UPDATED)
end

---------------------------------------------------------------------------
-- Set up as each part is found (the map and the logs live in parts of the game's UI loaded at different
-- times; looked for again as each loads, which costs next to nothing when there's nothing new)
---------------------------------------------------------------------------
local mapHooked, selectHooked = false, false
local function Setup()
	local wm = _G.WorldMapFrame
	if wm and not mapHooked then
		mapHooked = true
		wm:HookScript("OnShow", TakeMap)
		if wm.SetMapID then hooksecurefunc(wm, "SetMapID", OnSetMapID) end
		if wm.HandleUserActionToggleSelf then hooksecurefunc(wm, "HandleUserActionToggleSelf", OnToggleSelf) end
		if wm.HandleUserActionToggleQuestLog then hooksecurefunc(wm, "HandleUserActionToggleQuestLog", OnToggleQuestLog) end
		if wm.HandleUserActionOpenQuestLog then hooksecurefunc(wm, "HandleUserActionOpenQuestLog", OnOpenQuestLog) end
		if EventRegistry and EventRegistry.RegisterCallback then
			EventRegistry:RegisterCallback("MapCanvas.PingWaypointLocation", OnPingWaypoint, T)
		end
	end
	for _, name in ipairs(LOG_NAMES) do
		local ql = _G[name]
		if type(ql) == "table" and ql.HookScript and ql ~= _G.QuestMapFrame and ql ~= wm and not logs[ql] then
			logs[ql] = true
			ql:HookScript("OnShow", TakeQuestLog)
		end
	end
	if not selectHooked and _G.SelectQuestLogEntry then
		selectHooked = true
		hooksecurefunc("SelectQuestLogEntry", OnSelect)
	end
	HookQuestTrackers()
	T.Apply()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		for tracker in pairs(questTrackers) do PauseQuestHeaders(tracker) end
		return
	elseif event == "PLAYER_REGEN_ENABLED" then
		for header in pairs(disabledHeaders) do
			if not header:IsForbidden() then header:Enable() end
			disabledHeaders[header] = nil
		end
		for f in pairs(pendingClose) do Close(f) end
		if pendingApply then T.Apply() end
		return
	end
	Setup()
end)

-- (for /av addons)
function T.Report(P)
	local names = {}
	for _, name in ipairs(LOG_NAMES) do
		if logs[_G[name]] then names[#names + 1] = name end
	end
	P("  Blizzard's quest log: " .. (#names > 0 and table.concat(names, ", ") or "none of its own (it's the map's)"))
	P("  Blizzard's world map takeover: " .. (MapOn() and (InCombatLockdown() and "paused in combat" or "on") or "off"))
end
