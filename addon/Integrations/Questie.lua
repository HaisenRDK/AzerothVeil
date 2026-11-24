-- AzerothVeil — Integrations/Questie.lua
-- Optional: a dungeon's quests from Questie's database (Questie and QuestieDB, GPL v3 — the Questie team
-- accepts reuse under GPLv3, see their LICENSE.md), read at run time, read only; nothing of theirs is
-- changed or copied. Never required: without Questie, the Quests tab shows the quests of your log only.
--
-- What it uses (Questie 12.12.0 / QuestieDB 1.1.4 for WoW Forever, read in their code):
--   QuestDB.GetAllIds(), QuestDB.Get(id, key), NpcDB.Get(id, key)   QuestieDB's public surface (src/api.lua):
--       quest name and objectives text (localized), startedBy, questLevel, requiredLevel, requiredRaces,
--       zoneOrSort;
--       NPC name (localized), spawns { [areaId] = { { x, y } } } (0..100)
--   LibQuestieDB.Enum.factionRaceMasks                               ... its faction race masks
--   Questie.API.isReady                                               Questie's public "ready" flag
--   QuestieLoader:ImportModule("ZoneDB"):  instanceIdToAreaId, GetDungeons() (a dungeon's other area IDs
--       its quests may be filed under), GetUiMapIdByAreaId
--   QuestieLoader:ImportModule("QuestieDB").IsDoable(id)            Questie's own "can I take it now"
-- (the two last are Questie's modules, not its declared API: every call is protected, and anything missing
-- only leaves the part it gives out.)
-- AzerothVeil: what a quest needs and where it stands in its chain, as Questie's own quest details read them
-- (Modules/Journey/QuestDetailsFrame.lua): preQuestSingle (one of them done), preQuestGroup (all of them),
-- nextQuestInChain (else breadcrumbForQuestId) for the next step, exclusiveTo, parentQuest, requiredMinRep,
-- finishedBy (who it's handed in to) — through QuestDB.Get, read once per quest (QuestInfo); whether each quest
-- it names is done is the game's, read each time.
-- A quest's state is the game's whenever the game knows it: done (IsQuestFlaggedCompleted), in the log
-- (IsOnQuest / IsComplete / IsFailed); only "available" or "not yet" comes from Questie (IsDoable).
local _, ns = ...

local Q = {}
ns.Questie = Q

local index                    -- areaId -> { questID, ... }: Questie's quests by zone, built once
local infoOf = {}              -- AzerothVeil: questID -> its chain and needs, read once (QuestInfo, below)
local building = false
local waiting = {}             -- callbacks for when the index is done

local function Module(name)
	local loader = _G.QuestieLoader
	if type(loader) ~= "table" or type(loader.ImportModule) ~= "function" then return nil end
	local ok, m = pcall(loader.ImportModule, loader, name)
	return ok and type(m) == "table" and m or nil
end

-- whether Questie's data can be read now (both addons loaded, its database up, Questie ready)
function Q.Available()
	if not (ns.IsAddOnLoaded("Questie") and ns.IsAddOnLoaded("QuestieDB")) then return false end
	local qdb = _G.QuestDB
	if type(qdb) ~= "table" or type(qdb.Get) ~= "function" or type(qdb.GetAllIds) ~= "function" then return false end
	local api = _G.Questie and _G.Questie.API
	return type(api) == "table" and api.isReady == true
end

-- The area IDs a dungeon's quests are filed under in Questie (its own and the others it lists); empty
-- for a dungeon Questie doesn't know (some of WoW Forever's own)
function Q.AreasFor(inst)
	local out = {}
	local zones = Module("ZoneDB")
	if not (zones and type(zones.instanceIdToAreaId) == "table") then return out end
	local area = zones.instanceIdToAreaId[inst]
	if not area then return out end
	out[area] = true
	local ok, dungeons = pcall(zones.GetDungeons, zones)
	local entry = ok and type(dungeons) == "table" and dungeons[area]
	for _, alt in ipairs(type(entry) == "table" and type(entry[2]) == "table" and entry[2] or {}) do out[alt] = true end
	return out
end

-- Questie's quests by zone: built once, a few hundred quests a frame (no hitch), then done(true) for each
-- caller waiting. true when it's there already.
function Q.Index(done)
	if index then return true end
	if done then waiting[#waiting + 1] = done end
	if building then return false end
	building = true
	local qdb = _G.QuestDB
	local ids = qdb.GetAllIds()
	local built, i, n = {}, 1, #ids
	local function Step()
		local stop = math.min(n, i + 399)
		for k = i, stop do
			local id = ids[k]
			local ok, zone = pcall(qdb.Get, id, "zoneOrSort")
			if ok and type(zone) == "number" and zone > 0 then
				local list = built[zone]
				if not list then list = {} built[zone] = list end
				list[#list + 1] = id
			end
		end
		i = stop + 1
		if i <= n then C_Timer.After(0, Step) return end
		index, building = built, false
		local calls = waiting
		waiting = {}
		for _, f in ipairs(calls) do pcall(f, true) end
	end
	Step()
	return index ~= nil          -- (a small database: read in one go)
end

-- (for tests)
function Q._Reset() index, building, waiting, infoOf = nil, false, {}, {} end

local function Masks()
	local lib = _G.LibQuestieDB
	local masks = type(lib) == "table" and type(lib.Enum) == "table" and lib.Enum.factionRaceMasks
	return type(masks) == "table" and masks or nil
end

-- a quest's faction from the races it's for: "Alliance", "Horde", or nil (both, or not said)
local function FactionOf(races, masks)
	if not races or races == 0 or not masks or not (bit and bit.band) then return nil end
	local a = masks.Alliance and bit.band(races, masks.Alliance) ~= 0
	local h = masks.Horde and bit.band(races, masks.Horde) ~= 0
	if a and not h then return "Alliance" elseif h and not a then return "Horde" end
	return nil
end
Q.FactionOf = FactionOf

-- the classes a quest is for, from its class mask (bit n-1: the game's class n, as Questie keys them):
-- { classID, ... }, or nil (every class, or not said)
local function ClassesOf(mask)
	if not mask or mask == 0 or not (bit and bit.band) then return nil end
	local out = {}
	for id = 1, 12 do
		local b = 2 ^ (id - 1)
		if bit.band(mask, b) ~= 0 then out[#out + 1] = id end
	end
	if #out == 0 or #out >= 9 then return nil end   -- (all of a flavour's classes: no restriction)
	return out
end
Q.ClassesOf = ClassesOf

-- where a quest starts: its giver (name, areaName, area, uiMap, x, y: 0..1) or the item that starts it
local function Giver(startedBy)
	if type(startedBy) ~= "table" then return nil end
	local npcs, items = startedBy[1], startedBy[3]
	local npcDB = _G.NpcDB
	if type(npcs) == "table" and npcs[1] and type(npcDB) == "table" then
		local id = npcs[1]
		local okName, name = pcall(npcDB.Get, id, "name")
		local giver = { name = okName and name or nil }
		local okSpawns, spawns = pcall(npcDB.Get, id, "spawns")
		if okSpawns and type(spawns) == "table" then
			for area, list in pairs(spawns) do
				local p = type(list) == "table" and list[1]
				if p and tonumber(p[1]) and tonumber(p[2]) then
					local info = C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(area)
					giver.areaName = type(info) == "string" and info or nil
					local zones = Module("ZoneDB")
					if zones and zones.GetUiMapIdByAreaId then
						local okMap, uiMap = pcall(zones.GetUiMapIdByAreaId, zones, area)
						giver.uiMap = okMap and uiMap or nil
					end
					giver.x, giver.y = p[1] / 100, p[2] / 100
					giver.area = area             -- (AzerothVeil: to tell one standing inside the dungeon)
					break
				end
			end
		end
		if giver.name then return giver end
	end
	if type(items) == "table" and items[1] then
		local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(items[1])
		return { item = name or ("item:" .. items[1]) }
	end
	return nil
end

---------------------------------------------------------------------------
-- AzerothVeil: a quest's chain and needs (what doesn't change, read once per quest)
---------------------------------------------------------------------------

local function Field(id, key)
	local qdb = _G.QuestDB
	if type(qdb) ~= "table" or type(qdb.Get) ~= "function" then return nil end
	local ok, v = pcall(qdb.Get, id, key)
	if ok then return v end
end
local function Ids(v)
	local out = {}
	if type(v) == "table" then for _, x in ipairs(v) do if tonumber(x) and tonumber(x) > 0 then out[#out + 1] = tonumber(x) end end end
	return out
end
local function NextOf(id)
	local n = tonumber(Field(id, "nextQuestInChain")) or 0
	if n <= 0 then n = tonumber(Field(id, "breadcrumbForQuestId")) or 0 end
	return n > 0 and n or nil
end

local function QuestInfo(id)
	local info = infoOf[id]
	if info then return info end
	info = { single = Ids(Field(id, "preQuestSingle")), group = Ids(Field(id, "preQuestGroup")),
		exclusive = Ids(Field(id, "exclusiveTo")) }
	local parent = tonumber(Field(id, "parentQuest"))
	info.parent = parent and parent > 0 and parent or nil
	local rep = Field(id, "requiredMinRep")
	if type(rep) == "table" and tonumber(rep[1]) then info.rep = { tonumber(rep[1]), tonumber(rep[2]) or 0 } end
	-- the chain: back through a single prerequisite (one quest before it), on through the next step
	local seen, before, after = { [id] = true }, {}, {}
	local cur = id
	for _ = 1, 20 do
		local s1, g1 = Ids(Field(cur, "preQuestSingle")), Ids(Field(cur, "preQuestGroup"))
		local prev = (#s1 == 1 and s1[1]) or (#s1 == 0 and #g1 == 1 and g1[1]) or nil
		if not prev or seen[prev] then break end
		seen[prev] = true
		table.insert(before, 1, prev)
		cur = prev
	end
	cur = id
	for _ = 1, 20 do
		local n = NextOf(cur)
		if not n or seen[n] then break end
		seen[n] = true
		after[#after + 1] = n
		cur = n
	end
	info.before, info.after = before, after
	infoOf[id] = info
	return info
end

local function Done(id) return C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id) and true or false end
local function OnQuest(id) return C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(id) and true or false end
-- a quest's name in Questie's data (the player's language when it has it)
function Q.QuestName(id) return Field(id, "name") or ("quest:" .. id) end

-- what keeps a quest from being taken, and its chain: { oneOf = { ids }, allOf = { ids }, closedBy = id,
-- parent = id, rep = { factionID, value }, step, of, prev, next } (only what applies)
local function Needs(id)
	local info = QuestInfo(id)
	local out = {}
	if #info.single > 0 then
		local any = false
		for _, p in ipairs(info.single) do if Done(p) then any = true end end
		if not any then out.oneOf = info.single end
	end
	local missing = {}
	for _, p in ipairs(info.group) do if not Done(p) then missing[#missing + 1] = p end end
	if #missing > 0 then out.allOf = missing end
	for _, e in ipairs(info.exclusive) do if Done(e) or OnQuest(e) then out.closedBy = e break end end
	if info.parent and not OnQuest(info.parent) then out.parent = info.parent end
	out.rep = info.rep
	if #info.before + #info.after > 0 then
		out.step, out.of = #info.before + 1, #info.before + #info.after + 1
		out.prev, out.next = info.before[#info.before], info.after[1]
	end
	return out
end

-- a quest's state: the game's (done, in the log: complete, failed or active), else Questie's (available, locked)
function Q.Status(id, questie)
	if C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id) then return "done" end
	if C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(id) then
		if C_QuestLog.IsFailed and C_QuestLog.IsFailed(id) then return "failed" end
		if C_QuestLog.IsComplete and C_QuestLog.IsComplete(id) then return "complete" end
		return "active"
	end
	questie = questie or Module("QuestieDB")
	local okDo, doable = false, false
	if questie and type(questie.IsDoable) == "function" then okDo, doable = pcall(questie.IsDoable, id) end
	return (okDo and doable) and "available" or "locked"
end

-- a quest's chain, step by step: { { questID, title, level, status, giver }, ... } in order (this one among
-- them), and the index of this one; nil when it isn't part of one
function Q.Chain(id)
	if not Q.Available() then return nil end
	local info = QuestInfo(id)
	if #info.before + #info.after == 0 then return nil end
	local ids, here = {}, nil
	for _, x in ipairs(info.before) do ids[#ids + 1] = x end
	ids[#ids + 1] = id
	here = #ids
	for _, x in ipairs(info.after) do ids[#ids + 1] = x end
	local questie = Module("QuestieDB")
	local out = {}
	for i, x in ipairs(ids) do
		out[i] = { questID = x, title = Q.QuestName(x), level = tonumber(Field(x, "questLevel")),
			status = Q.Status(x, questie), giver = Giver(Field(x, "startedBy")) }
	end
	return out, here
end

-- A dungeon's quests in Questie: { { questID, title, level, reqLevel, status, giver, faction, text } } (giver.inside:
-- it stands in the dungeon itself),
-- status "done" | "active" | "complete" | "failed" | "available" | "locked"; faction "Alliance" | "Horde"
-- | nil (both); classes: { classID, ... } | nil (every class); text: what it asks (its objectives'
-- text, in the player's language when Questie has it). Those of the other faction or of other classes
-- left out unless all. nil while the index is being built (onReady called
-- once it's there); {} for a dungeon it has nothing for.
function Q.QuestsFor(inst, onReady, all)
	if not Q.Available() then return {} end
	if not Q.Index(onReady) then return nil end
	local qdb = _G.QuestDB
	local masks = Masks()
	local mine = UnitFactionGroup and UnitFactionGroup("player")
	local myClass = UnitClass and select(3, UnitClass("player"))
	local questie = Module("QuestieDB")
	local out, seen = {}, {}
	local areas = Q.AreasFor(inst)
	for area in pairs(areas) do
		for _, id in ipairs(index[area] or {}) do
			if not seen[id] then
				seen[id] = true
				local ok, v = pcall(qdb.GetAll, id, { "name", "startedBy", "questLevel", "requiredLevel", "requiredRaces", "objectivesText", "requiredClasses", "finishedBy" })
				local faction = ok and type(v) == "table" and FactionOf(v[5], masks) or nil
				local classes = ok and type(v) == "table" and ClassesOf(tonumber(v[7])) or nil
				local forMe = (not faction or faction == mine)
				if forMe and classes and myClass then
					forMe = false
					for _, c in ipairs(classes) do if c == myClass then forMe = true end end
				end
				if ok and type(v) == "table" and (all or forMe) then
					local status = Q.Status(id, questie)
					local text = {}
					for _, t in ipairs(type(v[6]) == "table" and v[6] or {}) do
						if type(t) == "string" and t ~= "" then text[#text + 1] = t end
					end
					local giver = Giver(v[2])
					-- (AzerothVeil: its giver inside the dungeon itself: picked up there; who it's handed in to, and
					-- whether that's inside too; what it needs and its chain)
					if giver and giver.area and areas[giver.area] then giver.inside = true end
					local ender = Giver(v[8])
					if ender and ender.area and areas[ender.area] then ender.inside = true end
					out[#out + 1] = { questID = id, title = v[1], level = v[3], reqLevel = v[4], status = status,
						giver = giver, ender = ender, faction = faction, classes = classes, text = text, needs = Needs(id) }
				end
			end
		end
	end
	return out
end
