-- AzerothVeil — Integrations/Questie.lua
-- Optional: a dungeon's quests from Questie's database (Questie and QuestieDB, GPL v3 — the Questie team
-- accepts reuse under GPLv3, see their LICENSE.md), read at run time, read only; nothing of theirs is
-- changed or copied. Never required: without Questie, the Quests tab shows the quests of your log only.
--
-- What it uses (Questie 12.12.0 / QuestieDB 1.1.4 for WoW Forever, read in their code):
--   QuestDB.GetAllIds(), QuestDB.Get(id, key), NpcDB.Get(id, key)   QuestieDB's public surface (src/api.lua):
--       quest name (localized), startedBy, questLevel, requiredLevel, requiredRaces, zoneOrSort;
--       NPC name (localized), spawns { [areaId] = { { x, y } } } (0..100)
--   LibQuestieDB.Enum.factionRaceMasks                               ... its faction race masks
--   Questie.API.isReady                                               Questie's public "ready" flag
--   QuestieLoader:ImportModule("ZoneDB"):  instanceIdToAreaId, GetDungeons() (a dungeon's other area IDs
--       its quests may be filed under), GetUiMapIdByAreaId
--   QuestieLoader:ImportModule("QuestieDB").IsDoable(id)            Questie's own "can I take it now"
-- (the two last are Questie's modules, not its declared API: every call is protected, and anything missing
-- only leaves the part it gives out.)
-- A quest's state is the game's whenever the game knows it: done (IsQuestFlaggedCompleted), in the log
-- (IsOnQuest / IsComplete / IsFailed); only "available" or "not yet" comes from Questie (IsDoable).
local _, ns = ...

local Q = {}
ns.Questie = Q

local index                    -- areaId -> { questID, ... }: Questie's quests by zone, built once
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
function Q._Reset() index, building, waiting = nil, false, {} end

local function FactionMask()
	local lib = _G.LibQuestieDB
	local masks = type(lib) == "table" and type(lib.Enum) == "table" and lib.Enum.factionRaceMasks
	local faction = UnitFactionGroup and UnitFactionGroup("player")
	return type(masks) == "table" and masks[faction] or nil
end

local function ForMyFaction(races, mask)
	if not races or races == 0 or not mask or not (bit and bit.band) then return true end
	return bit.band(races, mask) ~= 0
end

-- where a quest starts: its giver (name, area, uiMap, x, y: 0..1) or the item that starts it
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

-- A dungeon's quests in Questie, for the player's faction: { { questID, title, level, reqLevel, status,
-- giver } }, status "done" | "active" | "complete" | "failed" | "available" | "locked". nil while the index
-- is being built (onReady called once it's there); {} for a dungeon it has nothing for.
function Q.QuestsFor(inst, onReady)
	if not Q.Available() then return {} end
	if not Q.Index(onReady) then return nil end
	local qdb = _G.QuestDB
	local mask = FactionMask()
	local questie = Module("QuestieDB")
	local out, seen = {}, {}
	for area in pairs(Q.AreasFor(inst)) do
		for _, id in ipairs(index[area] or {}) do
			if not seen[id] then
				seen[id] = true
				local ok, v = pcall(qdb.GetAll, id, { "name", "startedBy", "questLevel", "requiredLevel", "requiredRaces" })
				if ok and type(v) == "table" and ForMyFaction(v[5], mask) then
					local status
					if C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id) then status = "done"
					elseif C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(id) then
						if C_QuestLog.IsFailed and C_QuestLog.IsFailed(id) then status = "failed"
						elseif C_QuestLog.IsComplete and C_QuestLog.IsComplete(id) then status = "complete"
						else status = "active" end
					else
						local okDo, doable = false, false
						if questie and type(questie.IsDoable) == "function" then okDo, doable = pcall(questie.IsDoable, id) end
						status = (okDo and doable) and "available" or "locked"
					end
					out[#out + 1] = { questID = id, title = v[1], level = v[3], reqLevel = v[4], status = status, giver = Giver(v[2]) }
				end
			end
		end
	end
	return out
end
