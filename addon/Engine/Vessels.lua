-- Boats and zeppelins where they are right now. Each vessel's way and timing is recorded (Data\Vessels.lua,
-- once taken from MapUtils' data, GPLv3, and kept here: nothing of MapUtils is needed or read): once one
-- sailing has been seen (its "phase": when in the round trip it was where), where it is now follows from
-- the clock. A phase comes from:
--  * you, aboard: passing a vessel's trigger points in its direction of travel, or anywhere along its
--    way, sailing with it (two looks running, at its speed and heading);
--  * other PerfectMap users: traded over PerfectMap's own addon messages (its prefix), with your guild,
--    your group and your friends who use PerfectMap.
-- Light: a 0.8 s check of where you are (a handful of points), positions every frame while the map is
-- open, a frame per vessel in view.
local _, FM = ...
local V = {}
FM.Vessels = V

local Geo = FM.Geo
local floor, sqrt, min, max = math.floor, math.sqrt, math.min, math.max
local MEDIA = "Interface\\AddOns\\AzerothVeil\\Media\\MapUtils\\"
-- (boats: our own painted ones, bow up as MapUtils' ship, in their faction's colours (the goblins', in
-- yours: Pins.FactionArt); zeppelins: MapUtils')
local ICONS = { zeppelin = MEDIA .. "vessel_zeppelin" }
local RECTS = {                         -- (MapUtils' world rectangles of the two continents)
	[0] = { 44688.53, 29795.11, 32601.04, 9894.93 },
	[1] = { 44878.66, 29916.10, 8723.96, 14824.53 },
}
local T = {
	maxAge = 30 * 86400, freshCycles = 2, futureTolerance = 5,
	queryGap = 600, announceGap = 60, perMessage = 10, maxPerSender = 60,
	interval = 0.1, triggerInterval = 0.8, triggerRadius = 20, minMove = 6.16, commitMove = 17,
	maxMove = 80, triggerCooldown = 30, iconSize = 22,
}
local CODE = "f"                        -- (WoW Forever's timetables)
local PREFIX = "PerfectMapSail"         -- (AzerothVeil: kept as is, so sightings are traded with PerfectMap users too) (PerfectMap's own messages: "T?f..." a question, "T!f..." sailings)
local SERVER_CLOCK_PERIOD = 4294967296 / 1000 -- seconds in the transport clock's 32-bit millisecond counter

local issecret = _G.issecretvalue
local function Secret(...)
	if not issecret then return false end
	for i = 1, select("#", ...) do if issecret((select(i, ...))) then return true end end
	return false
end

local routes = FM.VESSELS or {}
-- (Zephras Isle's zeppelins left out: the isle isn't on the world map, they'd sail off its edge. Their
-- docks stay, as the routes leave them out too: Routes.lua)
for id, route in pairs(routes) do
	if route.raw == 2991 then routes[id] = nil end
end
local decoded, zoneIndex = {}, {}

---------------------------------------------------------------------------
-- Timetables
---------------------------------------------------------------------------
local function Decode(route)
	local d = { x = {}, y = {}, dx = {}, dy = {}, dt = {}, dir = {}, ddir = {}, offset = { [0] = 0 },
		plat = {}, trig = {}, zoning = {}, jump = {}, rawp = {} }
	local x, y, dir = 0, 0, 0
	local docked, dockTime, travelTime = {}, 0, 0
	for i, packed in ipairs(route.points) do
		local f = { strsplit(":", packed) }
		local dx, dy, dt, ddir = tonumber(f[1]) or 0, tonumber(f[2]) or 0, tonumber(f[3]) or 0, math.rad(tonumber(f[5]) or 0)
		x, y, dir = x + dx, y + dy, dir + ddir
		d.x[i], d.y[i], d.dir[i] = x, y, dir
		d.dx[i], d.dy[i], d.dt[i], d.ddir[i] = dx, dy, dt, ddir
		for k = 6, #f do
			local kind, number = f[k]:sub(1, 4), tonumber(f[k]:sub(5))
			if kind == "plat" and number then d.plat[number], docked[i] = i, true
			elseif kind == "trig" and number ~= 0 then tinsert(d.trig, i)
			elseif kind == "zone" then d.zoning[i] = true
			elseif kind == "jump" then d.jump[i] = true
			elseif kind == "rawp" then d.rawp[i] = true end
		end
		if docked[i] then dockTime = dockTime + dt else travelTime = travelTime + dt end
	end
	d.count = #route.points
	-- Preserve dock stops and fit the recorded travel segments to the full round trip.
	local travelScale = travelTime > 0 and (route.rtt - dockTime) / travelTime or 1
	for i = 1, d.count do
		if not docked[i] then d.dt[i] = d.dt[i] * travelScale end
		d.offset[i] = d.offset[i - 1] + d.dt[i]
	end
	return d
end

-- the server's clock, to the fraction of a second
local clockOffset
local function Now()
	if clockOffset then return GetTime() + clockOffset end
	return GetServerTime()
end
local function CalibrateClock()
	local f, last = CreateFrame("Frame"), GetServerTime()
	f:SetScript("OnUpdate", function(self)
		local now = GetServerTime()
		if now ~= last then clockOffset = now - GetTime() self:SetScript("OnUpdate", nil) end
	end)
end

local function ClockCutoff(now)
	-- A shared sighting has whole seconds. Use the first unambiguous second after a wrap.
	return math.ceil(floor(now / SERVER_CLOCK_PERIOD) * SERVER_CLOCK_PERIOD)
end

local function Build()
	local _, b = GetBuildInfo()
	return tostring(b or "")
end

local function Store()
	FM.db.vesselStore = FM.db.vesselStore or {}
	return FM.db.vesselStore
end

-- what's known of a vessel (yours or another PerfectMap user's sighting), if it's not too old
local function Valid(k, now)
	if type(k) ~= "table" or type(k.p) ~= "number" or type(k.t) ~= "number" then return false end
	now = now or Now()
	return k.t >= ClockCutoff(now) and now - k.t <= T.maxAge
end
local function Known(id, now)
	local k = Store()[id]
	return Valid(k, now) and k or nil
end
local function Outdated(k) return k and k.b and k.b ~= Build() end
local function Stale(route, k) return Outdated(k) or Now() - k.t >= route.rtt * T.freshCycles end

local function Cycle(id)
	local now = Now()
	local route, k = routes[id], Known(id, now)
	if not route or not k then return nil end
	return (now - k.p) % route.rtt
end

local function FindIndex(d, cycle)
	local start = d.hint or 1
	if start > d.count or start > 1 and d.offset[start - 1] > cycle then start = 1 end
	for i = start, d.count do
		if d.offset[i] > cycle then d.hint = i return i end
	end
	d.hint = d.count
	return d.count
end

-- a point of the way in the world: instance, west, north
local function ToWorld(route, d, index, x, y)
	if d.rawp[index] then return route.raw, x, y end
	if route.coords >= 0 then return route.coords, x, y end
	local instance = x < 0.5 and 1 or 0
	local r = RECTS[instance]
	return instance, r[3] - r[1] * x, r[4] - r[2] * y
end

local function Position(id)
	local route, d = routes[id], decoded[id]
	local cycle = Cycle(id)
	if not cycle or not d then return nil end
	local index = FindIndex(d, cycle)
	-- (crossing to the other continent, a zone change or a jump the way records: the sparkle goes across
	-- the map from where it left to where it arrives, over that stretch's time. Both ends given (and how
	-- far along): the way's own points in between lie off both continents' maps)
	if index > 1 and (d.zoning[index] or d.jump[index]) then
		local f = d.dt[index] > 0 and min(1, max(0, (cycle - d.offset[index - 1]) / d.dt[index])) or 1
		local instance, wx, wy = ToWorld(route, d, index - 1, d.x[index - 1], d.y[index - 1])
		local toInstance, toX, toY = ToWorld(route, d, index, d.x[index], d.y[index])
		return instance, wx, wy, d.dir[index - 1], true, toInstance, toX, toY, f
	end
	if d.jump[index] then return nil end
	local x, y, angle = d.x[index], d.y[index], d.dir[index]
	if index > 1 then
		local f = d.dt[index] > 0 and min(1, max(0, (cycle - d.offset[index - 1]) / d.dt[index])) or 1
		x = d.x[index - 1] + d.dx[index] * f
		y = d.y[index - 1] + d.dy[index] * f
		angle = d.dir[index - 1] + d.ddir[index] * f
	end
	local instance, wx, wy = ToWorld(route, d, index, x, y)
	return instance, wx, wy, angle, false
end

local function PlatformTimes(id)
	local route, d = routes[id], decoded[id]
	local cycle = Cycle(id)
	if not cycle or not d then return nil end
	local index = FindIndex(d, cycle)
	local list = {}
	for number, pi in pairs(d.plat) do
		local docked = pi == index
		local wait = docked and d.offset[pi] - cycle or d.offset[pi - 1] - cycle
		if wait < 0 then wait = wait + route.rtt end
		list[#list + 1] = { number = number, name = route.platforms[number], docked = docked, wait = wait }
	end
	table.sort(list, function(a, b) return a.number < b.number end)
	return list
end

---------------------------------------------------------------------------
-- Sharing: PerfectMap's own messages, with your guild, your group and your friends who use PerfectMap
---------------------------------------------------------------------------
local Comm = { queue = {}, nextSend = 0, received = {}, pending = {}, announce = {}, lastAnnounce = {} }
-- (what went out and came in, for /av sailings)
local stats = { sent = 0, failed = 0, lastFail = nil, queries = 0, data = 0, heard = {}, raw = 0, rawBy = {} }

local function SyncOn() return FM.db.vessels and FM.db.vesselSync end

local function Pump()
	if #Comm.queue == 0 then
		if Comm.ticker then Comm.ticker:Cancel() Comm.ticker = nil end
		return
	end
	if GetTime() < Comm.nextSend then return end
	local item = tremove(Comm.queue, 1)
	Comm.nextSend = GetTime() + 1.2
	-- (the game says whether it went: a result code, 0 / true / nothing when it did)
	local ok, result
	if item[2] == "BN" then
		if not BNSendGameData then return end
		ok, result = pcall(BNSendGameData, item[3], PREFIX, item[1])
	else
		ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, item[1], item[2], item[3])
	end
	if ok and (result == nil or result == true or result == 0) then
		stats.sent = stats.sent + 1
	else
		stats.failed = stats.failed + 1
		stats.lastFail = ("%s to %s: %s"):format(item[1]:sub(1, 3), tostring(item[2]), tostring(ok and result or "error"))
	end
	if V.log then FM.Print(("Sailings: sent %s to %s%s: %s"):format(item[1]:sub(1, 3), tostring(item[2]),
		item[3] and (" " .. tostring(item[3])) or "", ok and tostring(result) or "error")) end
end

local friendList = {}
local function Targets(dist, target)
	local t = {}
	if (dist == "ALL" or dist == "GUILD") and IsInGuild() then t[#t + 1] = { "GUILD" } end
	if dist == "ALL" then
		local g = IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT" or IsInRaid() and "RAID" or IsInGroup() and "PARTY"
		if g then t[#t + 1] = { g } end
		-- (and each friend who uses PerfectMap)
		if FM.Friends and FM.Friends.KnownFriends then
			for _, f in ipairs(FM.Friends.KnownFriends(friendList)) do
				if f.bn then t[#t + 1] = { "BN", f.bn } elseif f.whisper then t[#t + 1] = { "WHISPER", f.whisper } end
			end
		end
	elseif dist == "PARTY" or dist == "RAID" or dist == "INSTANCE_CHAT" then
		t[#t + 1] = { dist }
	elseif (dist == "WHISPER" or dist == "BN") and target then
		t[#t + 1] = { dist, target }
	end
	return t
end

local function Send(payload, dist, target)
	if not SyncOn() or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
	for _, tg in ipairs(Targets(dist, target)) do
		if #Comm.queue < 40 then tinsert(Comm.queue, { "T" .. payload, tg[1], tg[2] }) end
	end
	if not Comm.ticker and #Comm.queue > 0 then Comm.ticker = C_Timer.NewTicker(0.2, Pump) end
end

-- (only what we saw ourselves: what we heard from others is theirs to pass on)
local function Encode(id)
	local k = Store()[id]
	if not Valid(k) or k.s ~= "self" or Outdated(k) then return nil end
	return format("%d,%d,%d", id, floor(k.p * 1000), floor(k.t))
end

local function SendData(ids, dist, target)
	local parts = {}
	for _, id in ipairs(ids) do
		local e = Encode(id)
		if e then parts[#parts + 1] = e end
		if #parts >= T.perMessage then Send("!" .. CODE .. table.concat(parts, ";"), dist, target) wipe(parts) end
	end
	if #parts > 0 then Send("!" .. CODE .. table.concat(parts, ";"), dist, target) end
end

function V.Query(force)
	if not SyncOn() then return end
	local now, serverNow = GetTime(), Now()
	local cutoff = ClockCutoff(serverNow)
	if not force and Comm.queryCutoff == cutoff and Comm.lastQuery and now - Comm.lastQuery < T.queryGap then return end
	local missing, stale = {}, {}
	for id, route in pairs(routes) do
		local k = Known(id, serverNow)
		if not k then missing[#missing + 1] = id elseif Stale(route, k) then stale[#stale + 1] = id end
	end
	table.sort(missing)
	table.sort(stale)
	if #missing == 0 and #stale == 0 then return end
	Comm.lastQuery, Comm.queryCutoff = now, cutoff
	local body = table.concat(missing, ",")
	if #stale > 0 then body = body .. "|" .. table.concat(stale, ",") end
	Send("?" .. CODE .. body, "ALL")
end

local function FlushAnnounce()
	Comm.announceTimer = nil
	if not SyncOn() then wipe(Comm.announce) return end
	local ids, now, delay = {}, GetTime(), T.announceGap
	for id in pairs(Comm.announce) do
		local last = Comm.lastAnnounce[id]
		if last and now - last < T.announceGap then
			delay = min(delay, T.announceGap - (now - last))
		else
			ids[#ids + 1] = id
			Comm.lastAnnounce[id], Comm.announce[id] = now, nil
		end
	end
	if #ids > 0 then SendData(ids, "ALL") end
	if next(Comm.announce) then Comm.announceTimer = C_Timer.NewTimer(delay, FlushAnnounce) end
end

local function QueueAnnounce(id)
	if not SyncOn() then return end
	Comm.announce[id] = true
	if not Comm.announceTimer then Comm.announceTimer = C_Timer.NewTimer(5 + math.random() * 10, FlushAnnounce) end
end

local function ReplyTarget(chatType, sender, bnID)
	if chatType == "WHISPER" then return "WHISPER", sender end
	if chatType == "BN" then return "BN", bnID end
	if chatType == "GUILD" or chatType == "PARTY" or chatType == "RAID" or chatType == "INSTANCE_CHAT" then return chatType end
end

local function OnQuery(body, chatType, sender, bnID)
	local dist, target = ReplyTarget(chatType, sender, bnID)
	if not dist then return end
	local key = dist .. tostring(target or "")
	local pending = Comm.pending[key] or { dist = dist, target = target, ids = {} }
	local fresh, count = false, 0
	local missingText, staleText = body:match("^([^|]*)|?(.*)$")
	for _, part in ipairs({ { missingText or "", false }, { staleText or "", true } }) do
		for idText in part[1]:gmatch("%d+") do
			local id = tonumber(idText)
			local route = id and routes[id]
			local k = id and Store()[id]
			count = count + 1
			if count > 32 then break end
			if route and Valid(k) and k.s == "self" and not Outdated(k) then
				local recent = not Stale(route, k)
				if recent or not part[2] then pending.ids[id] = true end
				if recent then fresh = true end
			end
		end
	end
	if next(pending.ids) == nil then return end
	Comm.pending[key] = pending
	if not pending.timer then
		pending.timer = C_Timer.NewTimer((fresh and 1 or 2.5) + math.random() * (fresh and 2 or 5), function()
			Comm.pending[key] = nil
			local ids = {}
			for id in pairs(pending.ids) do ids[#ids + 1] = id end
			table.sort(ids)
			if #ids > 0 then SendData(ids, pending.dist, pending.target) end
		end)
	end
end

local function OnData(body, sender)
	local store, now = Store(), Now()
	local cutoff = ClockCutoff(now)
	for part in body:gmatch("[^;]+") do
		local e = Comm.received[sender]
		if not e or GetTime() - e.start > 60 then e = { start = GetTime(), count = 0 } Comm.received[sender] = e end
		e.count = e.count + 1
		if e.count > T.maxPerSender then return end
		local idText, phaseText, timeText = part:match("^(%d+),(%d+),(%d+)$")
		local id, phase, observed = tonumber(idText), tonumber(phaseText), tonumber(timeText)
		local route = id and routes[id]
		if route and phase and observed then
			phase = phase / 1000
			if phase >= 0 and phase < route.rtt and observed >= cutoff and observed <= now + T.futureTolerance and now - observed < T.maxAge then
				local k = store[id]
				local current = Valid(k, now) and not Outdated(k)
				-- Messages carry whole seconds. Keep a newer local sighting and its queued reply.
				if not current or observed >= floor(k.t) then
					for _, p in pairs(Comm.pending) do p.ids[id] = nil end
				end
				if not current or observed > floor(k.t) then
					store[id] = { p = phase, t = observed, s = sender, b = Build() }
					Comm.announce[id] = nil
				end
			end
		end
	end
end

local function IsSelf(sender)
	local name, realm = UnitFullName("player")
	if Secret(name, realm) or not name then return false end
	if sender == name then return true end
	for _, r in ipairs({ realm or "", GetNormalizedRealmName and GetNormalizedRealmName() or "" }) do
		if r ~= "" and sender == name .. "-" .. r then return true end
	end
	return false
end

local function OnMessage(message, chatType, sender, bnID)
	if message:sub(1, 1) ~= "T" then return end
	local payload = message:sub(2)
	local kind, code, body = payload:sub(1, 1), payload:sub(2, 2), payload:sub(3)
	if code ~= CODE then return end
	stats.heard[sender] = (stats.heard[sender] or 0) + 1
	if V.log then FM.Print(("Sailings: %s from %s (%s): %s"):format(kind == "?" and "a question" or "sailings", sender, chatType, body)) end
	if kind == "?" then
		stats.queries = stats.queries + 1
		OnQuery(body, chatType, sender, bnID)
	elseif kind == "!" then
		stats.data = stats.data + 1
		OnData(body, sender)
	end
end

---------------------------------------------------------------------------
-- Seeing a sailing ourselves (aboard: passing its trigger points the way it sails)
---------------------------------------------------------------------------
local lastPos, lastTrigger
local candidate                         -- a sailing seen once along a way: { id, cycle, at }, to be seen again
local PATH_NEAR = 25                    -- yards off a way (aboard, the deck's width)
local PATH_SPEED = 0.3                  -- how far off the vessel's speed you may be moving (a walk on deck)

-- Where along its way a vessel would be for you to be aboard it, moving as you are: a point of a stretch
-- of it (same continent, not a jump or a zone change) within PATH_NEAR, its heading yours and its speed
-- about yours; the nearest such: its time in the round trip, else nil
local function MatchPath(d, instance, wx, wy, dx, dy, moved, speed)
	local best, bestD
	for i = 2, d.count do
		local dt = d.dt[i]
		if dt > 0 and d.wi[i] == instance and d.wi[i - 1] == instance and not d.jump[i] and not d.zoning[i] then
			local ax, ay = d.wx[i - 1], d.wy[i - 1]
			local sx, sy = d.wx[i] - ax, d.wy[i] - ay
			local len2 = sx * sx + sy * sy
			if len2 > 1 then
				local f = ((wx - ax) * sx + (wy - ay) * sy) / len2
				if f >= 0 and f <= 1 then
					local px, py = ax + sx * f - wx, ay + sy * f - wy
					local dist = sqrt(px * px + py * py)
					if dist < PATH_NEAR and (not bestD or dist < bestD) then
						local len = sqrt(len2)
						local vs = len / dt
						if (dx * sx + dy * sy) / (len * moved) > 0.9 and speed > vs * (1 - PATH_SPEED) and speed < vs * (1 + PATH_SPEED) then
							best, bestD = d.offset[i - 1] + dt * f, dist
						end
					end
				end
			end
		end
	end
	return best
end

local function CurrentZone()
	local m = C_Map.GetBestMapForUnit("player")
	if Secret(m) then return nil end
	if m == 1414 or m == 1415 then return nil end
	if not m or m == 0 then m = select(8, GetInstanceInfo()) end
	return m
end

local function Observe(id, cycle)
	local route = routes[id]
	if not route then return end
	local now = Now()
	if V.log then
		local previous = Known(id)
		if previous then
			local predicted = (now - previous.p) % route.rtt
			local half = route.rtt / 2
			local correction = (cycle - predicted + half) % route.rtt - half
			FM.Print(("Sailings: %s, %.3f s round trip, %+.2f s timing correction after %.1f s."):format(
				route.vessel, route.rtt, correction, now - previous.t))
		end
	end
	Store()[id] = { p = (now - cycle) % route.rtt, t = now, s = "self", b = Build() }
	QueueAnnounce(id)
end

local function CheckTriggers()
	if not FM.db.vessels then return end
	local _, instanceType = GetInstanceInfo()
	local zone = (instanceType ~= "party" and instanceType ~= "raid") and CurrentZone() or nil
	local list = zone and zoneIndex[zone]
	if not list and instanceType == "none" then list = routes end
	if not list then lastPos = nil return end
	local u1, u2, _, instance = UnitPosition("player")
	if not u1 or Secret(u1, u2, instance) then return end
	local last = lastPos
	lastPos = { u2, u1, instance, GetTime() }
	if not last or last[3] ~= instance then return end
	local wx, wy = u2, u1
	local dx, dy = wx - last[1], wy - last[2]
	local moved = sqrt(dx * dx + dy * dy)
	if moved <= T.minMove or moved > T.maxMove then return end
	if IsSwimming() or UnitOnTaxi("player") then return end
	if lastTrigger and GetTime() - lastTrigger < T.triggerCooldown then return end
	for id, flag in pairs(list) do
		local route, d = routes[id], decoded[id]
		if flag ~= "virtual" and route and d then
			for _, index in ipairs(d.trig) do
				local ti, tx, ty = ToWorld(route, d, index, d.x[index], d.y[index])
				local pi, px, py = ToWorld(route, d, index - 1, d.x[index - 1], d.y[index - 1])
				if ti == instance and pi == instance and sqrt((wx - tx) ^ 2 + (wy - ty) ^ 2) < T.triggerRadius then
					local dir = route.direction
					local okDir = not dir or ((not dir.x or dx * (tx - px) > 0) and (not dir.y or dy * (ty - py) > 0))
					if okDir then
						if moved > T.commitMove then
							local sx, sy = tx - px, ty - py
							local lengthSquared = sx * sx + sy * sy
							if lengthSquared > 0 then
								local fraction = ((wx - px) * sx + (wy - py) * sy) / lengthSquared
								Observe(id, d.offset[index - 1] + d.dt[index] * fraction)
								lastTrigger = GetTime()
							end
						end
						return
					end
				end
			end
		end
	end
	-- (no trigger point passed: anywhere along a way, sailing with it, twice running, a time apart that
	-- fits: then it's that vessel, at that point of its round trip. Flying is never sailing)
	if IsFlying and IsFlying() then candidate = nil return end
	local elapsed = GetTime() - last[4]
	if elapsed <= 0 then return end
	local speed = moved / elapsed
	for id, flag in pairs(list) do
		local route, d = routes[id], decoded[id]
		if flag ~= "virtual" and route and d and d.wi then
			local cycle = MatchPath(d, instance, wx, wy, dx, dy, moved, speed)
			if cycle then
				local c = candidate
				if c and c.id == id then
					local half = route.rtt / 2
					local off = (cycle - (c.cycle + GetTime() - c.at) + half) % route.rtt - half
					if math.abs(off) < 3 then
						Observe(id, cycle)
						lastTrigger, candidate = GetTime(), nil
						return
					end
				end
				candidate = { id = id, cycle = cycle, at = GetTime() }
				return
			end
		end
	end
	candidate = nil
end

---------------------------------------------------------------------------
-- On the map
---------------------------------------------------------------------------
local layer
local pins = {}
local view = { left = 0, top = 0, scale = 1, vw = 1, vh = 1 }

local function FormatTime(s)
	s = max(0, floor(s))
	return format("%d:%02d", floor(s / 60), s % 60)
end

-- (the tooltip stays where the cursor put it while the icon moves on under it; each second only its
-- lines are written again, never moved)
local function PinEnter(self, refresh)
	local id = self.routeID
	local route = id and routes[id]
	if not route then return end
	if refresh then GameTooltip:ClearLines() else GameTooltip:SetOwner(self, "ANCHOR_CURSOR") end
	local name = route.vessel ~= "Unnamed Vessel" and route.vessel or (route.kind == "zeppelin" and "Zeppelin" or "Boat")
	GameTooltip:AddLine(name, 1, 0.82, 0)
	local k = Known(id)
	local stale = k and Stale(route, k)
	for _, p in ipairs(PlatformTimes(id) or {}) do
		local where = p.name or ("#" .. p.number)
		local wait = (stale and "~" or "") .. FormatTime(p.wait)
		if p.docked then
			local state = stale and "est. at dock, leaves in " or "docked, leaves in "
			GameTooltip:AddDoubleLine(where, state .. wait, 1, 1, 1, 0.4, 1, 0.4)
		else
			GameTooltip:AddDoubleLine(where, wait, 0.85, 0.85, 0.85, 1, 1, 1)
		end
	end
	if k then
		if Outdated(k) then GameTooltip:AddLine("Estimated position: last seen before this game patch", 1, 0.5, 0.3, true)
		elseif stale then GameTooltip:AddLine("Estimated position: waiting for a newer sighting", 1, 0.5, 0.3, true) end
		local by = k.s == "self" and "you" or tostring(k.s or "?")
		GameTooltip:AddLine(("Timetable from %s, %s ago"):format(by, SecondsToTime and SecondsToTime(max(60, Now() - k.t), true) or "?"), 0.6, 0.6, 0.62, true)
	end
	GameTooltip:Show()
	self.tipTime = GetTime()
end

-- whether a frame is one of the moving boats' and zeppelins' icons
function V.Owns(f) return f ~= nil and layer ~= nil and f:GetParent() == layer end

local function NewPin()
	local p = CreateFrame("Frame", nil, layer)
	p.texture = p:CreateTexture(nil, "OVERLAY")
	p.texture:SetAllPoints()
	-- (a dark outline round every vessel: the icon again, offset a pixel round it)
	p.outline = {}
	for i = 1, 8 do
		local t = p:CreateTexture(nil, "OVERLAY", nil, -1)
		t:SetVertexColor(0, 0, 0, 1)
		if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) t:SetTexelSnappingBias(0) end
		p.outline[i] = t
	end
	-- (while it crosses between zones, the stretch the game moves it through at once: no vessel, a light
	-- blue sparkle in its place, a soft glow breathing under a slowly turning star, as a teleport)
	local spark = CreateFrame("Frame", nil, p)
	spark:SetPoint("CENTER")
	spark:SetAlpha(0.55)            -- (discreet: a hint of where it is, not a flare)
	spark:Hide()
	spark.glow = spark:CreateTexture(nil, "OVERLAY", nil, 1)
	spark.glow:SetTexture("Interface\\AddOns\\AzerothVeil\\Media\\glow")
	spark.glow:SetBlendMode("ADD")
	spark.glow:SetVertexColor(0.35, 0.75, 1, 1)
	spark.glow:SetAllPoints()
	spark.star = spark:CreateTexture(nil, "OVERLAY", nil, 2)
	spark.star:SetTexture("Interface\\Cooldown\\star4")
	spark.star:SetBlendMode("ADD")
	spark.star:SetVertexColor(0.6, 0.9, 1, 1)
	spark.star:SetPoint("CENTER")
	local turn = spark:CreateAnimationGroup()
	turn:SetLooping("REPEAT")
	local r = turn:CreateAnimation("Rotation")
	r:SetTarget(spark.star)
	r:SetDegrees(-360)
	r:SetDuration(3)
	local breathe = spark:CreateAnimationGroup()
	breathe:SetLooping("BOUNCE")
	local a = breathe:CreateAnimation("Alpha")
	a:SetTarget(spark.glow)
	a:SetFromAlpha(0.45)
	a:SetToAlpha(1)
	a:SetDuration(0.7)
	a:SetSmoothing("IN_OUT")
	local twinkle = spark:CreateAnimationGroup()
	twinkle:SetLooping("BOUNCE")
	local ta = twinkle:CreateAnimation("Alpha")
	ta:SetTarget(spark.star)
	ta:SetFromAlpha(0.55)
	ta:SetToAlpha(1)
	ta:SetDuration(0.45)
	spark.anims = { turn, breathe, twinkle }
	p.spark = spark
	p:EnableMouse(true)
	FM.Style.PassClicks(p)
	p:SetScript("OnEnter", function(self) PinEnter(self) end)   -- (its own second argument isn't a refresh)
	p:SetScript("OnLeave", GameTooltip_Hide)
	return p
end

local function Sparkle(p, on, size)
	local spark = p.spark
	if on then
		spark:SetSize(size * 1.1, size * 1.1)
		spark.star:SetSize(size * 0.7, size * 0.7)
		if not spark:IsShown() then
			spark:Show()
			for _, g in ipairs(spark.anims) do g:Play() end
		end
	elseif spark:IsShown() then
		for _, g in ipairs(spark.anims) do g:Stop() end
		spark:Hide()
	end
end

local VESSEL_SCALE = 0.9                    -- (every moving boat and zeppelin a tenth smaller; boats as big as zeppelins: their pictures as long)
local function Show(p, route, angle, zoning)
	local size = T.iconSize * VESSEL_SCALE * FM.Pins.BASE_SCALE * (FM.db.iconScale or 1)
	local icon = ICONS[route.kind] or FM.Pins.FactionArt("boat", route.faction)
	p:SetSize(size, size)
	if p.icon ~= icon then
		p.icon = icon
		p.texture:SetTexture(icon)
		-- (round the painted boats lighter: Pins.PAINTED_OUTLINE, the harbors' own)
		local thin = route.kind == "ship" and FM.Pins.PAINTED_OUTLINE
		p.outlineWidth = thin and thin.width or 1
		for _, t in ipairs(p.outline) do t:SetTexture(icon) t:SetVertexColor(0, 0, 0, thin and thin.dark or 1) end
	end
	p.texture:SetRotation(angle)
	local _, physH = GetPhysicalScreenSize()
	local es = p:GetEffectiveScale()
	local step = ((physH and physH > 0 and es > 0) and 768 / physH / es or 1) * (p.outlineWidth or 1)
	for i, t in ipairs(p.outline) do
		local a = (i - 1) * math.pi / 4
		t:SetShown(not zoning)
		t:SetRotation(angle)
		t:SetSize(size, size)
		t:SetPoint("CENTER", p, "CENTER", floor(math.cos(a) + 0.5) * step, floor(math.sin(a) + 0.5) * step)
	end
	-- (crossing between zones: the sparkle instead of the vessel)
	p.texture:SetShown(not zoning)
	Sparkle(p, zoning, size)
	p:SetAlpha(1)
	p:Show()
end

local function Place()
	local n = 0
	local pinsOn = FM.db.pins
	if layer and FM.db.vessels and (pinsOn.boat or pinsOn.zeppelin) then
		local x1, y1 = view.left + view.vw / view.scale, view.top + view.vh / view.scale
		local pad = 20 / view.scale
		for id, route in pairs(routes) do
			local instance, wx, wy, angle, zoning, toInstance, toX, toY, f
			if pinsOn[route.kind == "zeppelin" and "zeppelin" or "boat"] then
				instance, wx, wy, angle, zoning, toInstance, toX, toY, f = Position(id)
			end
			local u, v
			if instance then u, v = Geo.WorldToUnits(instance, wy, wx) end
			-- (the sparkle on its way across: straight over the map, from one end to the other)
			if u and toInstance then
				local tu, tv = Geo.WorldToUnits(toInstance, toY, toX)
				if tu then u, v = u + (tu - u) * f, v + (tv - v) * f end
			end
			if u and u >= view.left - pad and u <= x1 + pad and v >= view.top - pad and v <= y1 + pad then
				n = n + 1
				local p = pins[n]
				if not p then p = NewPin() pins[n] = p end
				p.routeID = id
				Show(p, route, angle, zoning)
				p:SetPoint("CENTER", layer, "TOPLEFT", (u - view.left) * view.scale, (view.top - v) * view.scale)
				if GameTooltip:IsOwned(p) and GetTime() - (p.tipTime or 0) >= 1 then PinEnter(p, true) end
			end
		end
	end
	for i = n + 1, #pins do pins[i]:Hide() pins[i].routeID = nil end
end

function V.Init(parent)
	layer = parent
end

function V.Layout(left, top, scale, vw, vh)
	view.left, view.top, view.scale, view.vw, view.vh = left, top, scale, vw, vh
	Place()
end

-- (every frame while the map is open: each vessel where it is this very frame, smooth at the game's
-- frame rate, the fast stretch between zones and its sparkle too; a handful of positions, next to nothing)
function V.Tick()
	Place()
end

-- (Share transports location turned on: what's missing asked for now)
function V.SyncChanged()
	if SyncOn() then V.Query(true) end
end

-- /av sailings: whether the sharing is on, who's been heard, and what's known of each vessel
function V.Status(arg)
	local P = FM.Print
	if arg == "test" then
		-- (a message to yourself: whether this client hears PerfectMap's messages at all)
		-- (by name and realm: Forever's realms are named in full)
		local name, realm = UnitFullName("player")
		if not realm or realm == "" then realm = GetNormalizedRealmName and GetNormalizedRealmName() end
		local me = realm and realm ~= "" and (name .. "-" .. realm) or name
		local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, "Tx" .. CODE .. "test", "WHISPER", me)
		P(("Sailings: a test whispered to yourself: %s. If \"heard\" below goes up by one in a moment, hearing works."):format(
			ok and tostring(result) or "error"))
		C_Timer.After(2, function() V.Status() end)
		return
	end
	if arg == "log" then
		V.log = not V.log
		P("Sailings: message and timing diagnostics are " .. (V.log and "printed here now." or "no longer printed."))
		return
	end
	if not FM.db.vessels then P("Sailings: \"Live transport icons\" is off.") return end
	if not FM.db.vesselSync then P("Sailings: \"Share transports location\" is off: only your own sightings.") end
	local registered = C_ChatInfo.IsAddonMessagePrefixRegistered and C_ChatInfo.IsAddonMessagePrefixRegistered(PREFIX)
	local by = {}
	for k, v in pairs(stats.rawBy) do by[#by + 1] = k .. " " .. v end
	local friends = FM.Friends and FM.Friends.KnownFriends and #FM.Friends.KnownFriends(friendList) or 0
	P(("Sailings: prefix %s; %d sent, %d failed%s; to your guild, group and %d friend(s) with AzerothVeil or PerfectMap."):format(
		registered and "registered" or "NOT registered", stats.sent, stats.failed,
		stats.lastFail and (" (last: " .. stats.lastFail .. ")") or "", friends))
	P(("Sailings: %d heard%s; %d asking, %d with sailings, from %d players."):format(
		stats.raw, #by > 0 and (" (" .. table.concat(by, ", ") .. ")") or "",
		stats.queries, stats.data, (function() local c = 0 for _ in pairs(stats.heard) do c = c + 1 end return c end)()))
	local known, total = 0, 0
	for id, route in pairs(routes) do
		total = total + 1
		local k = Known(id)
		if k then
			known = known + 1
			local by = k.s == "self" and "you" or tostring(k.s or "?")
			local status = Outdated(k) and " (older client build)" or Stale(route, k) and " (estimate)" or ""
			P(("  %s: seen by %s, %s ago%s"):format(route.vessel or ("route " .. id), by,
				SecondsToTime and SecondsToTime(max(60, Now() - k.t), true) or "?", status))
		end
	end
	P(("Sailings: %d of %d boats and zeppelins known. Each becomes known when someone with AzerothVeil or PerfectMap rides it."):format(known, total))
end

function V.OnShow()
	V.Query(false)
end

---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("CHAT_MSG_ADDON")
pcall(ev.RegisterEvent, ev, "BN_CHAT_MSG_ADDON")
ev:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_LOGIN" then
		for id, route in pairs(routes) do
			local d = Decode(route)
			decoded[id] = d
			-- (each point on the ground, once: where a way is, to match you against it aboard)
			d.wi, d.wx, d.wy = {}, {}, {}
			for i = 1, d.count do d.wi[i], d.wx[i], d.wy[i] = ToWorld(route, d, i, d.x[i], d.y[i]) end
			for mapID, flag in pairs(route.zones or {}) do
				zoneIndex[mapID] = zoneIndex[mapID] or {}
				zoneIndex[mapID][id] = flag
			end
		end
		if next(decoded) == nil then return end
		CalibrateClock()
		C_Timer.NewTicker(T.triggerInterval, CheckTriggers)
		if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
		-- (a little after login, what's missing asked for: friends are greeted first, Friends.lua)
		C_Timer.After(20 + math.random() * 10, function() V.Query(true) end)
	elseif event == "CHAT_MSG_ADDON" then
		local prefix, message, chatType, sender = ...
		if Secret(prefix) or prefix ~= PREFIX then return end
		-- (everything on our prefix counted, before anything is turned away: /av sailings)
		stats.raw = stats.raw + 1
		if not Secret(chatType) then stats.rawBy[tostring(chatType)] = (stats.rawBy[tostring(chatType)] or 0) + 1 end
		if V.log then
			FM.Print(("Sailings: heard [%s] from %s: %s"):format(Secret(chatType) and "?" or tostring(chatType),
				Secret(sender) and "(secret)" or tostring(sender), Secret(message) and "(secret)" or tostring(message):sub(1, 60)))
		end
		if not SyncOn() then return end
		if Secret(message, chatType, sender) then return end
		if type(message) ~= "string" or type(sender) ~= "string" or message == "" or IsSelf(sender) then return end
		pcall(OnMessage, message, chatType, sender)
	elseif event == "BN_CHAT_MSG_ADDON" then
		-- (a Battle.net friend's: named by their character)
		local prefix, message, _, bnID = ...
		if Secret(prefix, message, bnID) or prefix ~= PREFIX or not SyncOn() then return end
		if type(message) ~= "string" or type(bnID) ~= "number" then return end
		stats.raw = stats.raw + 1
		stats.rawBy.BN = (stats.rawBy.BN or 0) + 1
		local g = C_BattleNet and C_BattleNet.GetGameAccountInfoByID and C_BattleNet.GetGameAccountInfoByID(bnID)
		local name = type(g) == "table" and FM.Plain(g.characterName)
		pcall(OnMessage, message, "BN", type(name) == "string" and name or "a friend", bnID)
	end
end)
