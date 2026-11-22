-- Friends and guild members on the map, where they stand: a class-coloured dot for each one who
-- uses PerfectMap (or OpenMap: the same messages) and shares where they are. Your party and raid are
-- Map.lua's own dots, so they're left out here.
-- Sharing (asked once as the map opens; Options: Share where you are; off until it's turned on):
-- your place as an addon message (prefix OpenMapLoc, OpenMap's own) every 10 s while you move, each
-- minute while you stand still, to your guild and to your friends who use either addon; never from
-- inside a dungeon, raid or battleground. Those friends are found by a hello as they come online
-- (H1, answered H2 or with a place). The messages: "L1 map x y class level" (tab-separated; a uiMapID,
-- x and y on it 0..1), "L0" (stopped sharing), "H1", "H2".
-- Light: nothing runs per frame; while the map is closed what arrives is only noted, and drawn when
-- it opens (then again each 10 s, or as it arrives).
-- The protocol and the way it's sent: OpenMap's Map/Friends.lua (MIT, (c) 2026 OpenMap contributors).
-- AzerothVeil: driven by the "Friends & guild" module (Modules/Social.lua). F.Start() / F.Stop(): until it's
-- started (and once stopped) it hears nothing, sends nothing, scans nothing and draws nothing. Its two
-- switches are the module's settings (F.cfg: show, share, asked), no longer PerfectMap's FM.db.
local _, FM = ...
local F = {}
FM.Friends = F
local S, Geo = FM.Style, FM.Geo
F.running = false
F.cfg = nil                   -- (the module's settings table, set by F.Start)
local function ShowOn() return F.running and F.cfg and F.cfg.show and true or false end
local function ShareOn() return F.running and F.cfg and F.cfg.share and true or false end

local PREFIX = "OpenMapLoc"
local TICK = 2                -- seconds between looks at where you are
local SEND_EVERY = 10         -- seconds between places sent while you move
local STILL_EVERY = 60        -- ... and while you stand still
local GONE_AFTER = 150        -- seconds without word before someone's dot goes
local MOVED = 0.002           -- (a move this small on a zone's map isn't one)
local SEND_GAP = 0.5          -- seconds between messages sent
local REDRAW_EVERY = 10
local DOT = "Interface\\AddOns\\AzerothVeil\\Media\\dot"

local Plain = FM.Plain
local roster = {}             -- full name -> { guild = true, friend = true, guid }: online now
local friends = {}            -- full name -> { whisper = name } or { bn = gameAccountID }
local known = {}              -- full name -> true: friends who use either addon
local live = {}               -- full name -> { map, x, y, class, level, guild, at }: those sharing
local last = { at = -math.huge }
local sharing = false
local realm
local layer, dots, nDots = nil, {}, 0
local dirty, redrawAt = false, 0

---------------------------------------------------------------------------
-- Names ("Name-Realm"; on your own realm the game gives them without one)
---------------------------------------------------------------------------
local function Realm()
	if not realm then
		local r = Plain(GetNormalizedRealmName and GetNormalizedRealmName())
		if type(r) ~= "string" or r == "" then r = (Plain(GetRealmName()) or ""):gsub("[%s%-]", "") end
		if r == "" then return "" end
		realm = r
	end
	return realm
end

local function Full(name, rlm)
	name = Plain(name)
	if type(name) ~= "string" or name == "" then return end
	if name:find("-", 1, true) then return name end
	rlm = Plain(rlm)
	if type(rlm) == "string" and rlm ~= "" then return name .. "-" .. rlm:gsub("[%s%-]", "") end
	return name .. "-" .. Realm()
end

-- (shown without the realm: Forever's read "CAMWOWUS1Realm2PvP"; one from elsewhere marked (*))
local function Shown(full)
	local name, rlm = full:match("^([^%-]+)%-?(.*)$")
	if rlm ~= "" and Realm() ~= "" and rlm:lower() ~= Realm():lower() then name = name .. (FOREIGN_SERVER_LABEL or " (*)") end
	return name or full
end

local function IsMe(full)
	local me = Plain(UnitName("player"))
	if type(full) ~= "string" or not me then return false end
	local name, rlm = full:match("^([^%-]+)%-?(.*)$")
	return name == me and (rlm == "" or rlm:lower() == Realm():lower())
end

local function ClassColor(class)
	local c = type(class) == "string" and ((C_ClassColor and C_ClassColor.GetClassColor(class)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

---------------------------------------------------------------------------
-- Sending: one message each SEND_GAP, one waiting for each place it goes (a newer one replaces it)
---------------------------------------------------------------------------
local outbox, order = {}, {}
local sender = CreateFrame("Frame")
sender:Hide()
local wait = 0
sender:SetScript("OnUpdate", function(self, elapsed)
	wait = wait - elapsed
	if wait > 0 then return end
	local key = tremove(order, 1)
	if not key then self:Hide() return end
	local m = outbox[key]
	outbox[key] = nil
	wait = SEND_GAP
	if m.text:sub(1, 2) == "L1" and not ShareOn() then return end   -- (turned off since)
	if m.bn then
		if BNSendGameData then pcall(BNSendGameData, m.bn, PREFIX, m.text) end
	elseif C_ChatInfo and C_ChatInfo.SendAddonMessage then
		pcall(C_ChatInfo.SendAddonMessage, PREFIX, m.text, m.channel, m.target)
	end
end)

local function Send(key, text, channel, target, bn)
	if not outbox[key] then order[#order + 1] = key end
	outbox[key] = { text = text, channel = channel, target = target, bn = bn }
	sender:Show()
end

local function ToFriend(full, text)
	local f = friends[full]
	if not f then return end
	if f.bn then Send(full, text, nil, nil, f.bn) else Send(full, text, "WHISPER", f.whisper) end
end

-- the friends online who use either addon, guild mates left out (they have the guild's): into out, each
-- { whisper = name } or { bn = gameAccountID } (Vessels.lua shares the boats' sailings with them too)
function F.KnownFriends(out)
	wipe(out)
	local guild = IsInGuild()
	for full in pairs(known) do
		local f = friends[full]
		if f and not (guild and roster[full] and roster[full].guild) then out[#out + 1] = f end
	end
	return out
end

-- to your guild, and to each friend online who uses either addon (a guild mate has it from the guild's)
local function Broadcast(text)
	local guild = IsInGuild()
	if guild then Send("GUILD", text, "GUILD") end
	for full in pairs(known) do
		if friends[full] and not (guild and roster[full] and roster[full].guild) then ToFriend(full, text) end
	end
end

-- where you are: a zone's uiMapID and x, y on it; nil in an instance or when the game won't say
local function Here()
	if Plain(IsInInstance()) then return end
	local best = Plain(C_Map.GetBestMapForUnit("player"))
	if type(best) ~= "number" or not Geo.Rect(best) then return end
	local p = C_Map.GetPlayerMapPosition(best, "player")
	if not p then return end
	local x, y = p:GetXY()
	x, y = Plain(x), Plain(y)
	if type(x) ~= "number" or type(y) ~= "number" or (x <= 0 and y <= 0) then return end
	return best, x, y
end

local function Stop()
	if sharing then
		sharing = false
		last.at, last.text = -math.huge, nil
		Broadcast("L0")
	end
end

local function Tick()
	if not ShareOn() then Stop() return end
	local m, x, y = Here()
	if not m then Stop() return end
	local moved = m ~= last.map or math.abs(x - last.x) > MOVED or math.abs(y - last.y) > MOVED
	if GetTime() - last.at < (moved and SEND_EVERY or STILL_EVERY) then return end
	local _, class = UnitClass("player")
	class = Plain(class)
	last.map, last.x, last.y, last.at = m, x, y, GetTime()
	last.text = ("L1\t%d\t%.4f\t%.4f\t%s\t%d"):format(m, x, y, type(class) == "string" and class or "",
		tonumber(Plain(UnitLevel("player"))) or 0)
	sharing = true
	Broadcast(last.text)
end

---------------------------------------------------------------------------
-- Who's online: the guild roster and the friends lists (to know where to send, and who may whisper)
---------------------------------------------------------------------------
local function ScanGuild()
	if not IsInGuild() or not GetGuildRosterInfo then return end
	for i = 1, tonumber(Plain(GetNumGuildMembers())) or 0 do
		local name, _, _, _, _, _, _, _, online, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(i)
		local full = Plain(online) and Full(name)
		if full and not IsMe(full) then roster[full] = { guild = true, guid = Plain(guid) } end
	end
end

local function Friend(full, how, guid)
	local r = roster[full] or { guid = Plain(guid) }
	r.friend = true
	roster[full] = r
	if how.bn or not friends[full] then friends[full] = how end   -- (Battle.net reaches any realm)
end

local function ScanFriends()
	if not (C_FriendList and C_FriendList.GetNumFriends) then return end
	for i = 1, tonumber(Plain(C_FriendList.GetNumFriends())) or 0 do
		local f = C_FriendList.GetFriendInfoByIndex(i)
		local full = type(f) == "table" and Plain(f.connected) and Full(f.name)
		if full then Friend(full, { whisper = f.name }, f.guid) end
	end
end

-- (Battle.net friends in this same game and of your faction: the game keeps the other one's apart)
local function SameFaction(g)
	local mine = Plain(UnitFactionGroup("player"))
	return type(mine) == "string" and type(g) == "table" and Plain(g.factionName) == mine
end

local function ScanBattleNet()
	if not (BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo) then return end
	for i = 1, tonumber(Plain(BNGetNumFriends())) or 0 do
		local a = C_BattleNet.GetFriendAccountInfo(i)
		local g = type(a) == "table" and a.gameAccountInfo
		if type(g) == "table" and Plain(g.isOnline) and g.clientProgram == (BNET_CLIENT_WOW or "WoW")
			and (not WOW_PROJECT_ID or g.wowProjectID == WOW_PROJECT_ID) and SameFaction(g) then
			local full = Full(g.characterName, g.realmName)
			if full then Friend(full, { bn = g.gameAccountID }, g.playerGuid) end
		end
	end
end

local function Scan()
	local before = {}
	for full in pairs(friends) do before[full] = true end
	wipe(roster) wipe(friends)
	for _, scan in ipairs({ ScanGuild, ScanFriends, ScanBattleNet }) do
		local ok, err = pcall(scan)
		if not ok then geterrorhandler()(err) end
	end
	-- a friend just online: a hello, to learn whether they use either addon (they learn you do)
	if ShowOn() or ShareOn() then
		for full in pairs(friends) do
			if not before[full] and not IsMe(full) then ToFriend(full, "H1") end
		end
	end
	dirty = true
end

-- (roster events come in bursts: one scan for them, soon while the map is open, else in 30 s)
local scanning = false
local function QueueScan()
	if scanning then return end
	scanning = true
	C_Timer.After(FM.Map.IsShown() and 1 or 30, function() scanning = false if F.running then Scan() end end)
end

local function AskRosters()
	if IsInGuild() then
		if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) elseif GuildRoster then pcall(GuildRoster) end
	end
	if C_FriendList and C_FriendList.ShowFriends then pcall(C_FriendList.ShowFriends) end
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local function Heard(full, text, guild)
	local kind, m, x, y, class, level = strsplit("\t", text, 6)
	if friends[full] then known[full] = true end
	if kind == "H1" or kind == "H2" then
		if kind == "H1" and friends[full] then ToFriend(full, sharing and ShareOn() and last.text or "H2") end
		return
	end
	if not guild and not friends[full] then return end      -- (a whisper only from a friend)
	if kind == "L0" then
		if live[full] then live[full] = nil dirty = true end
	elseif kind == "L1" then
		m, x, y = tonumber(m), tonumber(x), tonumber(y)
		if not (m and x and y) or x < 0 or x > 1 or y < 0 or y > 1 or not Geo.Rect(m) then return end
		live[full] = { map = m, x = x, y = y, class = class and class:match("^%u+$"), level = tonumber(level),
			guild = guild or (roster[full] and roster[full].guild) or false, at = GetTime() }
		dirty = true
	end
end

local function OnAddonMessage(prefix, text, channel, from)
	if prefix ~= PREFIX then return end
	text, channel, from = Plain(text), Plain(channel), Plain(from)
	if type(text) ~= "string" or (channel ~= "GUILD" and channel ~= "WHISPER") then return end
	local full = Full(from)
	if not full or IsMe(full) then return end
	Heard(full, text, channel == "GUILD")
end

local function OnBattleNetMessage(prefix, text, id)
	if prefix ~= PREFIX then return end
	text, id = Plain(text), Plain(id)
	if type(text) ~= "string" or type(id) ~= "number" then return end
	local g = C_BattleNet and C_BattleNet.GetGameAccountInfoByID and C_BattleNet.GetGameAccountInfoByID(id)
	local full = type(g) == "table" and Full(g.characterName, g.realmName)
	if not full or IsMe(full) or not SameFaction(g) then return end
	friends[full] = friends[full] or { bn = id }
	Heard(full, text, false)
end

---------------------------------------------------------------------------
-- On the map: a dot each (hovered: who, level, where)
---------------------------------------------------------------------------
local function InGroup(full)
	if not IsInGroup() then return false end
	local short = full:match("^[^%-]+")
	return (UnitInParty(short) or UnitInRaid(short)) and true or false
end

local function DotEnter(self)
	local p = self.p
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(Shown(self.full), ClassColor(p.class))
	if p.level and p.level > 0 then GameTooltip:AddLine((LEVEL or "Level") .. " " .. p.level, 1, 1, 1) end
	local info = C_Map.GetMapInfo(p.map)
	GameTooltip:AddLine(("%s  %.1f, %.1f"):format(info and info.name or "?", p.x * 100, p.y * 100), 1, 1, 1)
	GameTooltip:AddLine(p.guild and (GUILD or "Guild") or (FRIEND or "Friend"), 0.6, 0.8, 1)
	local ago = GetTime() - p.at
	if ago >= 20 then GameTooltip:AddLine(("Updated %d s ago"):format(ago), 0.6, 0.6, 0.6) end
	GameTooltip:Show()
end

local function NewDot()
	local d = CreateFrame("Frame", nil, layer)
	d:SetSize(12, 12)
	d.tex = d:CreateTexture(nil, "OVERLAY")
	d.tex:SetTexture(DOT)
	d.tex:SetAllPoints()
	d:EnableMouse(true)
	FM.Style.PassClicks(d)
	d:SetScript("OnEnter", DotEnter)
	d:SetScript("OnLeave", GameTooltip_Hide)
	return d
end

-- who's where: worked out again only when something arrived (or every REDRAW_EVERY s: dots go stale)
local placed = {}             -- { u, v, full, p }
local nPlaced = 0
local function Gather()
	dirty = false
	redrawAt = GetTime()
	nPlaced = 0
	if not ShowOn() then return end
	local now = GetTime()
	for full, p in pairs(live) do
		if now - p.at > GONE_AFTER or IsMe(full) then
			live[full] = nil
		elseif not InGroup(full) then
			local u, v = Geo.MapToUnits(p.map, p.x, p.y)
			if u then
				nPlaced = nPlaced + 1
				local e = placed[nPlaced] or {}
				e.u, e.v, e.full, e.p = u, v, full, p
				placed[nPlaced] = e
			end
		end
	end
end

-- every pan / zoom (a handful of dots)
function F.Layout(left, top, scale, vw, vh)
	if not layer then return end
	if not F.running then
		for i = 1, nDots do dots[i]:Hide() end
		nDots = 0
		return
	end
	if dirty or GetTime() - redrawAt > REDRAW_EVERY then Gather() end
	local n = 0
	for i = 1, nPlaced do
		local e = placed[i]
		local sx, sy = (e.u - left) * scale, (e.v - top) * scale
		if sx > -10 and sy > -10 and sx < vw + 10 and sy < vh + 10 then
			n = n + 1
			local d = dots[n] or NewDot()
			dots[n] = d
			d.full, d.p = e.full, e.p
			if d.class ~= e.p.class then
				d.class = e.p.class
				d.tex:SetVertexColor(ClassColor(e.p.class))
			end
			d:SetPoint("CENTER", layer, "TOPLEFT", sx, -sy)
			d:Show()
		end
	end
	for i = n + 1, nDots do dots[i]:Hide() end
	nDots = n
end

-- (while the map is open: what arrived is drawn at once, by this layer alone, not the whole map)
function F.Tick()
	if not F.running then return end
	if dirty or GetTime() - redrawAt > REDRAW_EVERY then F.Layout(FM.Map.ViewNow()) end
end

---------------------------------------------------------------------------
-- Asked once, the first time the map opens: whether to share where you are
---------------------------------------------------------------------------
local ask
local function Answer(share)
	if F.cfg then
		F.cfg.asked = true
		if share then
			F.cfg.share = true
			F.Refresh()
			if FM.Options and FM.Options.Refresh then FM.Options.Refresh() end
		end
	end
	ask:Hide()
end

local function BuildAsk()
	ask = CreateFrame("Frame", nil, _G.AzerothVeilFrame)
	ask:SetWidth(440)
	ask:SetPoint("CENTER")
	ask:SetFrameStrata("DIALOG")
	ask:EnableMouse(true)
	S.Panel(ask, nil, nil, true)
	-- (laid out top to bottom, every text wrapped inside the box: its height follows them)
	local title = S.Text(ask, 13, S.ACCENT)
	title:SetPoint("TOP", 0, -14)
	title:SetText("Friends and guild")
	local text = S.Text(ask, 12)
	text:SetPoint("TOP", title, "BOTTOM", 0, -10)
	text:SetWidth(400)
	text:SetJustifyH("CENTER")
	text:SetWordWrap(true)
	text:SetText("Your friends and guild members who use AzerothVeil, PerfectMap or OpenMap show on your map as a dot where they stand. Share where you are, so they see you on theirs?")
	local yes = S.Button(ask, "Share where I am", 170, 22, function() Answer(true) end)
	yes:SetPoint("TOPRIGHT", text, "BOTTOM", -6, -14)
	local no = S.Button(ask, "Not now", 170, 22, function() Answer(false) end)
	no:SetPoint("TOPLEFT", text, "BOTTOM", 6, -14)
	local note = S.Text(ask, 10, S.DIM)
	note:SetPoint("TOP", yes, "BOTTOMRIGHT", 6, -12)
	note:SetWidth(400)
	note:SetJustifyH("CENTER")
	note:SetWordWrap(true)
	note:SetText("Only your guild and friends, never from a dungeon, raid or battleground. /av config: Friends & guild.")
	function ask:Fit()
		self:SetHeight(14 + title:GetStringHeight() + 10 + text:GetStringHeight() + 14 + 22 + 12 + note:GetStringHeight() + 14)
	end
end

function F.OnShow()
	if not F.running then return end
	if scanning then scanning = false Scan() end
	AskRosters()
	dirty = true
	if F.cfg and not F.cfg.asked and not F.cfg.share and not InCombatLockdown() then
		if not ask then BuildAsk() end
		ask:Show()
		ask:Fit()
	end
end

-- an option changed: drawn again; sharing turned on: sent at once (off: they're told)
function F.Refresh()
	dirty = true
	FM.Map.MarkDirty()
	if not F.running then return end
	if ShareOn() or sharing then last.at = -math.huge Tick() end
end

function F.Init(parent)
	layer = parent
end

-- (AzerothVeil: started and stopped by the module, never at load: PerfectMap started it at PLAYER_LOGIN)
local EVENTS = { "CHAT_MSG_ADDON", "BN_CHAT_MSG_ADDON", "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE",
	"FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE",
	"GROUP_ROSTER_UPDATE" }
local ev = CreateFrame("Frame")
local ticker, startTimer
local prefixRegistered = false

-- cfg: the module's settings table ({ show, share, asked }), read live (a change is seen at once)
function F.Start(cfg)
	F.cfg = cfg
	if F.running then F.Refresh() return end
	F.running = true
	if not prefixRegistered and C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
		-- (a prefix can't be unregistered: once registered, it stays so until the next /reload; harmless)
		prefixRegistered = pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
	end
	for _, e in ipairs(EVENTS) do pcall(ev.RegisterEvent, ev, e) end
	ticker = C_Timer.NewTicker(TICK, Tick)
	startTimer = C_Timer.NewTimer(5, function() startTimer = nil if F.running then AskRosters() QueueScan() end end)
	dirty = true
	if FM.Map and FM.Map.MarkDirty then FM.Map.MarkDirty() end
end

-- everything let go: no event, no timer, nobody known; those you shared with are told you stopped
function F.Stop()
	if not F.running then return end
	Stop()                                   -- ("L0" to those who had your place: queued before running goes)
	F.running = false
	ev:UnregisterAllEvents()
	if ticker then ticker:Cancel() ticker = nil end
	if startTimer then startTimer:Cancel() startTimer = nil end
	wipe(live) wipe(known) wipe(roster) wipe(friends)
	nPlaced = 0
	for i = 1, nDots do dots[i]:Hide() end
	nDots = 0
	if ask then ask:Hide() end
	if FM.Map and FM.Map.MarkDirty then FM.Map.MarkDirty() end
end

ev:SetScript("OnEvent", function(self, event, ...)
	if not F.running then return end
	if event == "CHAT_MSG_ADDON" then
		local prefix, text, channel, from = ...
		OnAddonMessage(prefix, text, channel, from)
	elseif event == "BN_CHAT_MSG_ADDON" then
		local prefix, text, _, id = ...
		OnBattleNetMessage(prefix, text, id)
	elseif event == "GROUP_ROSTER_UPDATE" then
		dirty = true
	else
		QueueScan()
	end
end)
