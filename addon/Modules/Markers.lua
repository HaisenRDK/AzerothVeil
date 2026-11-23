-- AzerothVeil — Modules/Markers.lua
-- "Map markers": as many markers as you like on the map, each with a note, an icon and a colour, in categories of
-- your own (each shown or hidden on its own), kept for every character (AzerothVeilDB.markers, Core/Database.lua).
-- Ctrl-click on the map drops one (followed: Blizzard's waypoint on it) and opens its card; a click on one opens its
-- card again (note, icon, colour, category, follow, share, delete); Shift-click puts it in chat, Alt-click deletes
-- it. The list (the map's right-click menu, or /av markers) has them all, by category.
--
-- Sharing, as OpenMap's map pins (Map/Pins.lua, MIT), so OpenMap users and AzerothVeil users trade them: addon
-- messages under the prefix "OpenMap", one a marker ("P1", map, x, y, colour, note: tab-separated, 255 bytes at
-- most), to your group, your guild or your target; sent one each SEND_GAP (the game holds a burst back). Whoever
-- gets them is asked first (this addon's own window, UI/Markers.lua: not the game's StaticPopupDialogs), unless
-- they're from your group and you said so. A marker's icon isn't sent (OpenMap has none): one received has the
-- map pin, in its colour. Also a code to copy and paste ("OMPINS1:", OpenMap's), to trade them anywhere.
--
-- Off: no marker on the map, no Ctrl-click of its own (the waypoint's, as before), nothing sent or heard (the
-- addon message prefix, once registered, stays so until a reload, unused). Its markers are kept.
local _, ns = ...
local L = ns.L

local PREFIX = "OpenMap"        -- (OpenMap's map pins' addon messages)
local CODE = "OMPINS1:"         -- (a code of markers, to paste: OpenMap's)
local NOTE_MAX = 160            -- characters of a note
local SHARE_MAX = 100           -- markers from one share, at most
local SEND_GAP = 0.5            -- seconds between messages sent
local ASK_AFTER = 1.5           -- seconds after someone's last marker before asking (a share of several)
local NEAR = 5e-4               -- (two points this close on a map are one)
local MEDIA = "Interface\\AddOns\\AzerothVeil\\Media\\"
local RAID = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"

-- OpenMap's colours, in its order (shared as their number): { name, r, g, b }; the first leaves an icon as it is
local COLORS = {
	{ L["Gold"] },
	{ L["Red"], 1, 0.38, 0.32 },
	{ L["Green"], 0.5, 0.95, 0.4 },
	{ L["Blue"], 0.45, 0.72, 1 },
	{ L["Purple"], 0.82, 0.55, 1 },
}
-- the icons a marker can have: { texture or "atlas:", name, tinted by its colour }; the first is a received one's
local ICONS = {
	{ "atlas:Waypoint-MapPin-Untracked", L["Map pin"], true },
	{ RAID .. "1", L["Star"] }, { RAID .. "2", L["Circle"] }, { RAID .. "3", L["Diamond"] }, { RAID .. "4", L["Triangle"] },
	{ RAID .. "5", L["Moon"] }, { RAID .. "6", L["Square"] }, { RAID .. "7", L["Cross"] }, { RAID .. "8", L["Skull"] },
	{ MEDIA .. "Questie\\available", L["Quest"] }, { MEDIA .. "Questie\\loot", L["Loot"] },
	{ MEDIA .. "Questie\\slay", L["Enemy"] }, { MEDIA .. "Questie\\object", L["Object"] },
	{ MEDIA .. "Questie\\interact", L["Interact"] }, { MEDIA .. "Questie\\event", L["Event"] },
	{ MEDIA .. "dot", L["Dot"], true },
}

local Markers = ns.Modules:Register({
	name = "markers",
	title = L["Map markers"],
	description = L["Markers of your own on the map: a note, an icon and a colour each, in categories you make and show or hide on their own. Ctrl-click the map to drop one; share them with your group or guild, OpenMap users too."],
	onText = L["your markers show on the map; Ctrl-click drops one; shared markers reach you if that option is on."],
	offText = L["no marker shows, Ctrl-click sets the waypoint as before, nothing is sent or heard. Your markers are kept."],
	order = 35,
	icon = RAID .. "1",
	defaultEnabled = true,
	settings = {
		{ type = "header", label = L["On the map"] },
		{ key = "show", iconMenu = true, icon = RAID .. "1", type = "toggle", default = true,
			label = L["Show the markers"],
			tooltip = L["Your markers on the map, those of the categories you show."] },
		{ key = "ctrlClick", icon = "atlas:Waypoint-MapPin-Untracked", type = "toggle", default = true,
			label = L["Ctrl-click: drop a marker"],
			tooltip = L["Ctrl-click on the map drops a marker there and opens its card."] .. "\n" .. L["Off: Ctrl-click sets the waypoint, as before."] },
		{ key = "followNew", icon = "atlas:Waypoint-MapPin-Tracked", type = "toggle", default = true, parent = "ctrlClick",
			label = L["Follow a new marker"],
			tooltip = L["A marker you drop gets Blizzard's waypoint, and its arrow."] },
		{ type = "header", label = L["Sharing"] },
		{ key = "receive", icon = "Interface\\Icons\\INV_Letter_15", type = "toggle", default = true,
			label = L["Receive shared markers"],
			tooltip = L["Markers your group, your guild or another player share with you (AzerothVeil or OpenMap users): you're asked each time whether to add them."] .. "\n" .. L["Off: nothing is heard."] },
		{ key = "groupAdd", icon = "Interface\\Icons\\INV_Misc_GroupNeedMore", type = "toggle", default = false, parent = "receive",
			label = L["Your group's without asking"],
			tooltip = L["Markers shared with your party or raid are added at once."] },
	},
})
ns.Markers = Markers
Markers.COLORS, Markers.ICONS, Markers.CODE = COLORS, ICONS, CODE

---------------------------------------------------------------------------
-- The markers
---------------------------------------------------------------------------
local function Data() return ns.Database.Root().markers end
Markers.Data = Data

local function Round(v) return math.floor(v * 1e4 + 0.5) / 1e4 end

-- a note as plain text: no control characters, no escape codes ("|": links, colours), cut short (not mid-character)
function Markers.Clean(text)
	text = tostring(text or ""):gsub("%c", " "):gsub("|", "/")
	text = text:match("^%s*(.-)%s*$")
	if #text > NOTE_MAX then text = text:sub(1, NOTE_MAX):gsub("[\192-\255][\128-\191]*$", "") end
	return text
end

function Markers.ZoneName(id)
	local info = id and C_Map.GetMapInfo(id)
	return info and ns.Plain(info.name) or "?"
end

function Markers.Cat(id)
	for _, c in ipairs(Data().cats) do if c.id == id then return c end end
end

function Markers.CatName(c)
	if not c then return "?" end
	if c.name and c.name ~= "" then return c.name end
	if c.id == Data().shared then return L["Shared with me"] end
	return c.id == Data().cats[1].id and L["My markers"] or L["Category"]
end

-- the category new markers go in: the last one picked, if it's still there
function Markers.CurrentCat()
	local d = Data()
	return Markers.Cat(d.current) and d.current or d.cats[1].id
end

function Markers.Add(map, x, y, note, color, icon, cat, from)
	local d = Data()
	local m = { id = d.nextId, map = map, x = Round(x), y = Round(y), note = Markers.Clean(note),
		color = COLORS[color or 1] and color or 1, icon = ICONS[icon or 1] and icon or 1,
		cat = Markers.Cat(cat) and cat or Markers.CurrentCat(), from = from, at = time() }
	d.nextId = d.nextId + 1
	d.list[#d.list + 1] = m
	return m
end

function Markers.Remove(m)
	local list = Data().list
	for i = #list, 1, -1 do
		if list[i] == m then
			if Markers.Followed(m) then ns.Pins.ClearPin() end
			table.remove(list, i)
		end
	end
end

function Markers.InCat(id)
	local out = {}
	for _, m in ipairs(Data().list) do if m.cat == id then out[#out + 1] = m end end
	return out
end

function Markers.AddCat(name)
	local d = Data()
	local c = { id = d.nextCat, name = Markers.Clean(name), shown = true }
	d.nextCat = d.nextCat + 1
	d.cats[#d.cats + 1] = c
	return c
end

-- a category gone, with its markers (the first one stays: there's always one)
function Markers.RemoveCat(id)
	local d = Data()
	if d.cats[1].id == id then return false end
	for _, m in ipairs(Markers.InCat(id)) do Markers.Remove(m) end
	for i, c in ipairs(d.cats) do if c.id == id then table.remove(d.cats, i) break end end
	if d.shared == id then d.shared = nil end
	if d.current == id then d.current = nil end
	return true
end

-- the category of markers others shared (made the first time)
local function SharedCat()
	local d = Data()
	if not Markers.Cat(d.shared) then d.shared = Markers.AddCat("").id end
	return d.shared
end

---------------------------------------------------------------------------
-- On the map (Engine/Pins.lua's "marker" kind)
---------------------------------------------------------------------------
function Markers.IconOf(m) return (ICONS[m.icon] or ICONS[1])[1] end
function Markers.TintOf(m)
	local c, i = COLORS[m.color] or COLORS[1], ICONS[m.icon] or ICONS[1]
	if not (c[2] and i[3]) then return nil end
	return { c[2], c[3], c[4] }
end

-- where a marker is on the world (units)
function Markers.Units(m) return ns.Geo.MapToUnits(m.map, m.x, m.y) end

-- whether Blizzard's waypoint is on it
function Markers.Followed(m)
	local p = C_Map.HasUserWaypoint and C_Map.HasUserWaypoint() and C_Map.GetUserWaypoint()
	if not (p and p.uiMapID and p.position) then return false end
	local u, v = ns.Geo.MapToUnits(p.uiMapID, p.position.x, p.position.y)
	local mu, mv = Markers.Units(m)
	return u and mu and math.abs(u - mu) < 0.05 and math.abs(v - mv) < 0.05 or false
end

function Markers.Follow(m)
	local u, v = Markers.Units(m)
	if u then ns.Pins.FollowAt("marker", u, v) end
end

function Markers.Unfollow() ns.Pins.ClearPin() end

local function Lines(m)
	local lines = { { ("%s  %.1f, %.1f"):format(Markers.ZoneName(m.map), m.x * 100, m.y * 100), 1, 1, 1, 11 } }
	lines[#lines + 1] = { Markers.CatName(Markers.Cat(m.cat)), 0.7, 0.7, 0.72, 11 }
	if m.from then lines[#lines + 1] = { L["Shared by %s"]:format(m.from), 0.6, 0.8, 1, 11 } end
	lines[#lines + 1] = { L["Click: its card   Shift-click: in chat   Alt-click: delete"], 0.6, 0.6, 0.6, 10 }
	return lines
end

-- the markers on the map again (those of the categories shown), and every window that lists them
function Markers.Changed()
	if Markers.active then
		local on = Markers:IsOptionActive("show")
		ns.db.pins.marker = on
		local list = {}
		if on then
			local shown = {}
			for _, c in ipairs(Data().cats) do shown[c.id] = c.shown end
			for _, m in ipairs(Data().list) do
				local u, v
				if shown[m.cat] then u, v = Markers.Units(m) end
				if u and v then
					list[#list + 1] = { u = u, v = v, marker = m, icon = Markers.IconOf(m), tint = Markers.TintOf(m),
						title = m.note ~= "" and m.note or L["Map marker"], lines = Lines(m) }
				end
			end
		end
		ns.Pins.SetPins("marker", list)
		ns.Map.MarkDirty()
	end
	ns.Callbacks:Fire("MARKERS_CHANGED")
end

---------------------------------------------------------------------------
-- Clicks (Engine/Pins.lua's hooks, set while the module runs)
---------------------------------------------------------------------------
local function UI() return ns.MarkersUI end

-- Shift-click (the game's chat-link click): the marker into chat: Blizzard's map pin link where the game takes a
-- waypoint on its map (the waypoint set to it for the link, then put back as it was), with its note; else text
function Markers.ChatLink(m)
	local link
	if C_Map.GetUserWaypointHyperlink and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates
		and (not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(m.map)) then
		local before = C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
		if pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(m.map, m.x, m.y)) then
			local ok, l = pcall(C_Map.GetUserWaypointHyperlink)
			if ok and type(l) == "string" and l ~= "" then link = l end
		end
		if before then pcall(C_Map.SetUserWaypoint, before) elseif C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
	end
	local note = (m.note or ""):gsub("|", "||")
	local place = ("%s %.1f, %.1f"):format(Markers.ZoneName(m.map), m.x * 100, m.y * 100)
	local text = link and (note ~= "" and (link .. " " .. note) or link) or (note ~= "" and (note .. " (" .. place .. ")") or place)
	local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
	if not (insert and insert(text)) and ChatFrame_OpenChat then ChatFrame_OpenChat(text) end
end

local function OnMarkerClick(m)
	if IsAltKeyDown() then
		Markers.Remove(m)
		Markers.Changed()
	elseif IsModifiedClick and IsModifiedClick("CHATLINK") then
		Markers.ChatLink(m)
	elseif UI() then
		UI().Edit(m)
	end
end

-- a marker at a spot of the world (units): on its zone's map, else its continent's
function Markers.DropAt(u, v)
	local map = ns.Geo.ZoneAt(u, v) or ns.Geo.ContinentAt(u, v)
	if not map then return end
	local x, y = ns.Geo.UnitsToMap(map, u, v)
	if not (x and y) then return end
	local m = Markers.Add(map, x, y, "")
	Markers.Data().current = m.cat
	Markers.Changed()
	if Markers:IsOptionActive("followNew") then Markers.Follow(m) end
	if UI() then UI().Edit(m, true) end
	return m
end

local function OnCtrlClick(u, v)
	if not Markers:IsOptionActive("ctrlClick") then return false end
	return Markers.DropAt(u, v) ~= nil
end

---------------------------------------------------------------------------
-- Sharing: OpenMap's messages, paced; and its codes
---------------------------------------------------------------------------
local queue = {}                -- { message, channel, target }
local sending = false
local prefixDone = false
local function Prefix()
	if prefixDone or not (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) then return end
	prefixDone = true
	pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
end

local function Pump()
	local item = table.remove(queue, 1)
	if not item or not Markers.active then sending = false return end
	pcall(C_ChatInfo.SendAddonMessage, PREFIX, item[1], item[2], item[3])
	if #queue > 0 then Markers:After(SEND_GAP, Pump) else sending = false end
end

function Markers.Message(m)
	local head = ("P1\t%d\t%.4f\t%.4f\t%d\t"):format(m.map, m.x, m.y, m.color or 1)
	local note = m.note or ""
	if #head + #note > 255 then note = note:sub(1, 255 - #head):gsub("[\192-\255][\128-\191]*$", "") end
	return head .. note
end

-- where a share can go now: "group", "guild", "target"; its channel and whisper target, or nil
function Markers.Channel(to)
	if to == "group" then
		if IsInRaid() then return "RAID" end
		if IsInGroup() then return "PARTY" end
	elseif to == "guild" then
		if IsInGuild() then return "GUILD" end
	elseif to == "target" then
		if UnitIsPlayer("target") and not UnitIsUnit("target", "player") then
			return "WHISPER", GetUnitName("target", true)
		end
	end
end

local SHARE_TO = { group = L["your group"], guild = L["your guild"] }
-- markers to your group, guild or target: true if they're on their way
function Markers.Share(list, to)
	local channel, target = Markers.Channel(to)
	if not channel then
		ns.Print(to == "target" and L["Target a player first."] or to == "guild" and L["You aren't in a guild."] or L["You aren't in a group."])
		return false
	end
	if not (Markers.active and C_ChatInfo and C_ChatInfo.SendAddonMessage) or #list == 0 then return false end
	Prefix()
	for i = 1, math.min(#list, SHARE_MAX) do queue[#queue + 1] = { Markers.Message(list[i]), channel, target } end
	if not sending then sending = true Pump() end
	ns.Print(L["Sharing %d marker(s) with %s (AzerothVeil and OpenMap users are asked whether to add them)."]:format(
		math.min(#list, SHARE_MAX), target or SHARE_TO[to] or "?"))
	return true
end

local function Escape(note) return (note:gsub("[%%,;]", function(c) return ("%%%02X"):format(c:byte()) end)) end
local function Unescape(note) return (note:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end

function Markers.CodeOf(list)
	local parts = {}
	for _, m in ipairs(list) do
		parts[#parts + 1] = ("%d,%.4f,%.4f,%d,%s"):format(m.map, m.x, m.y, m.color or 1, Escape(m.note or ""))
	end
	return CODE .. table.concat(parts, ";")
end

-- a marker's fields from a message or a code, checked: a map this client places on the world, a point on it
function Markers.Valid(map, x, y, color, note)
	map, x, y, color = tonumber(map), tonumber(x), tonumber(y), tonumber(color)
	if not (map and x and y) or x < 0 or x > 1 or y < 0 or y > 1 or not ns.Geo.Rect(map) then return end
	return { map = map, x = Round(x), y = Round(y), color = COLORS[color or 1] and color or 1, note = Markers.Clean(note) }
end

function Markers.FromCode(text)
	local body = tostring(text or ""):match(CODE:gsub("%p", "%%%0") .. "(%S+)")
	if not body then return end
	local list = {}
	for part in body:gmatch("[^;]+") do
		local map, x, y, color, note = strsplit(",", part, 5)
		local q = Markers.Valid(map, x, y, color, Unescape(note or ""))
		if q then list[#list + 1] = q end
		if #list >= SHARE_MAX * 5 then break end
	end
	return list
end

-- markers not already there (the same place and note) added, in cat (default: the current one); how many
function Markers.AddAll(list, from, cat)
	local n = 0
	for _, q in ipairs(list) do
		local dup = false
		for _, m in ipairs(Data().list) do
			if m.map == q.map and math.abs(m.x - q.x) < NEAR and math.abs(m.y - q.y) < NEAR and m.note == q.note then dup = true break end
		end
		if not dup then Markers.Add(q.map, q.x, q.y, q.note, q.color, 1, cat, from) n = n + 1 end
	end
	Markers.Changed()
	return n
end

-- markers someone shares: gathered for a moment after their last, then you're asked about them all
local incoming = {}             -- sender -> { from, list, at, group }
local asking = false

local function Accept(batch)
	local n = Markers.AddAll(batch.list, batch.from, SharedCat())
	ns.Print(L["Added %d marker(s) from %s."]:format(n, batch.from))
end

local CheckIncoming
CheckIncoming = function()
	if asking then return end
	local now = GetTime()
	for from, batch in pairs(incoming) do
		if now - batch.at >= ASK_AFTER then
			incoming[from] = nil
			if batch.group and Markers:IsOptionActive("groupAdd") then
				Accept(batch)
			elseif UI() then
				asking = true
				UI().Ask(batch, function() Accept(batch) end, function()
					asking = false
					if next(incoming) and Markers.active then Markers:After(0.1, CheckIncoming) end
				end)
				return
			end
		end
	end
	if next(incoming) and Markers.active then Markers:After(0.5, CheckIncoming) end
end

function Markers.OnAddonMessage(_, prefix, text, channel, sender)
	if prefix ~= PREFIX then return end
	text, sender = ns.Plain(text), ns.Plain(sender)
	if type(text) ~= "string" or type(sender) ~= "string" then return end
	local name = Ambiguate and Ambiguate(sender, "none") or sender
	if name == UnitName("player") then return end      -- (your own, sent to your group or guild)
	local kind, map, x, y, color, note = strsplit("\t", text, 6)
	if kind ~= "P1" or not Markers:IsOptionActive("receive") then return end
	local q = Markers.Valid(map, x, y, color, note or "")
	if not q then return end
	local batch = incoming[name] or { from = name, list = {}, group = channel == "PARTY" or channel == "RAID" }
	incoming[name] = batch
	if #batch.list >= SHARE_MAX then return end
	batch.list[#batch.list + 1] = q
	batch.at = GetTime()
	Markers:After(ASK_AFTER + 0.05, CheckIncoming)
end

---------------------------------------------------------------------------
-- Life cycle
---------------------------------------------------------------------------
local function Apply(self)
	ns.Pins.OnMarkerClick = OnMarkerClick
	ns.Pins.OnCtrlClick = OnCtrlClick
	if ns.Spot then
		ns.Spot.markerItems = {
			{ L["Add a marker here"], RAID .. "1", function(u, v) Markers.DropAt(u, v) end },
			{ L["Map markers..."], "Interface\\Buttons\\UI-GuildButton-PublicNote-Up", function() if UI() then UI().OpenList() end end },
		}
	end
	if self:IsOptionActive("receive") then
		Prefix()
		self:RegisterEvent("CHAT_MSG_ADDON", Markers.OnAddonMessage)
	else
		self:UnregisterEvent("CHAT_MSG_ADDON")
		wipe(incoming)
	end
	Markers.Changed()
end

function Markers:Enable() Apply(self) end
function Markers:Refresh() Apply(self) end

function Markers:Disable()
	ns.Pins.OnMarkerClick, ns.Pins.OnCtrlClick = nil, nil
	if ns.Spot then ns.Spot.markerItems = nil end
	wipe(queue)
	wipe(incoming)
	sending, asking = false, false
	ns.db.pins.marker = false
	ns.Pins.SetPins("marker", {})
	ns.Map.MarkDirty()
	if UI() then UI().HideAll() end
	ns.Callbacks:Fire("MARKERS_CHANGED")
end
