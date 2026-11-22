-- AzerothVeil — Modules/Icons.lua
-- "Icons": the capitals' emblems, the townsfolk of the towns (innkeepers, bankers, class trainers, mailboxes
-- and the rest) and the profession trainers on the map, each kind on its own; "Show all" / "Hide all" for a
-- section; every class's trainers if asked; the trainers of your own professions.
--
-- The work is PerfectMap's (Engine/Pins.lua: its kinds of icon, the townsfolk from Data/Townsfolk.lua). This
-- module owns their switches, once the engine's Places, Townsfolk and Professions tabs: its settings are the
-- kinds of Pins.CATS in the groups FM.ICON_GROUPS (same keys as FM.db.pins), and it writes FM.db.pins for them
-- and FM.db.allClassTrainers, all off while it's off (Engine/Core.lua turns them off at each load).
-- "My professions": a profession's trainers show when picked, or when you have that profession. Your
-- professions are read (C_SkillInfo by skill line, else GetProfessions: this client has no GetSkillLineInfo) when
-- the module starts, when the option changes and each time the map opens (Pins.BeforeOpen): no event heard.
-- Off: none of them shows; nothing of them is built.
-- (The townsfolk of land not explored yet: the Map module's "Townsfolk of unexplored areas", Modules/Map.lua.)
local _, ns = ...
local L = ns.L

local SECTIONS = {
	{ group = "places", label = L["Capital cities"] },
	{ group = "townsfolk", label = L["Townsfolk"], all = true },
	{ group = "professions", label = L["Profession trainers"], all = true },
}
local TIPS = {
	capital = L["Each capital's emblem, in its faction's colours, zoomed right out."],
	classTrainer = L["Your class's only."],
	portalTrainer = L["Your class's only."],
}
-- the professions' skill lines (the same in every language), by the engine's tags (Pins.CATS' prof_<TAG>)
local SKILL_LINES = {
	ALCHEMY = 171, BLACKSMITHING = 164, COOKING = 185, ENCHANTING = 333, ENGINEERING = 202, FIRST_AID = 129,
	FISHING = 356, HERBALISM = 182, LEATHERWORKING = 165, MINING = 186, SKINNING = 393, TAILORING = 197,
}
local TAG_OF = {}                     -- setting key -> profession tag

-- the declaration's settings: a section for each group, a switch for each kind in it (its label and icon the
-- engine's, its default PerfectMap's); the two options of their own put where they belong
local function Settings()
	local out, defaults = {}, ns.defaults and ns.defaults.pins or {}
	for _, sec in ipairs(SECTIONS) do
		out[#out + 1] = { type = "header", label = sec.label, all = sec.all }
		if sec.group == "professions" then
			out[#out + 1] = { key = "myProfessions", type = "toggle", default = false, noAll = true,
				icon = "Interface\\GossipFrame\\TrainerGossipIcon", label = L["My professions"],
				tooltip = L["The trainers of the professions you have, whether picked below or not; follows what you learn."] }
		end
		for _, cat in ipairs(ns.Pins.CATS) do
			if cat.group == sec.group then
				out[#out + 1] = { key = cat.key, type = "toggle", default = defaults[cat.key] == true,
					icon = cat.icon, label = cat.label, tooltip = TIPS[cat.key] }
				if cat.tag then TAG_OF[cat.key] = cat.tag end
				if cat.key == "classTrainer" then
					out[#out + 1] = { key = "allClassTrainers", type = "toggle", default = false, parent = "classTrainer",
						noAll = true, icon = cat.icon, label = L["Every class"],
						tooltip = L["Every class's trainers, not only yours."] }
				end
			end
		end
	end
	return out
end

local Icons = ns.Modules:Register({
	name = "icons",
	title = L["Icons"],
	description = L["The capitals' emblems, the townsfolk of the towns and the profession trainers on the map: innkeepers, bankers, class trainers, mailboxes and the rest, each kind on its own."],
	onText = L["the kinds picked below show on the map."],
	offText = L["none of them shows: no capital's emblem, no townsfolk, no trainer."],
	order = 10,
	icon = "Interface\\Minimap\\tracking\\innkeeper",
	defaultEnabled = true,
	settings = Settings(),
})

-- the professions the player has: { [tag] = true }
function Icons.MyProfessions()
	local known = {}
	local byID = C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID
	if byID then
		for tag, id in pairs(SKILL_LINES) do
			local ok, info = pcall(byID, id)
			local rank = ok and type(info) == "table" and tonumber(ns.Plain(info.rank))
			if rank and rank > 0 then known[tag] = true end
		end
	end
	if GetProfessions and GetProfessionInfo then
		local ok, a, b, c, d, e, f = pcall(GetProfessions)
		if ok then
			for _, index in pairs({ a, b, c, d, e, f }) do
				local ok2, _, _, _, _, _, _, line = pcall(GetProfessionInfo, index)
				line = ok2 and tonumber(ns.Plain(line))
				for tag, id in pairs(SKILL_LINES) do if id == line then known[tag] = true end end
			end
		end
	end
	return known
end

-- writes what's in effect into the engine's switches (all false while the module is off); builds what's
-- newly on only with the map open (else it's built when the map opens). opening: the map is opening (it
-- builds right after)
local function Apply(self, running, opening)
	local pins, db = ns.db.pins, ns.db
	local mine = running and self:IsOptionActive("myProfessions") and Icons.MyProfessions() or nil
	local changed = false
	for key in pairs(self.settingByKey) do
		if key ~= "myProfessions" and key ~= "allClassTrainers" then
			local on = running and self:IsOptionActive(key) or false
			if not on and mine and TAG_OF[key] and mine[TAG_OF[key]] then on = true end
			if pins[key] ~= on then pins[key] = on changed = true end
		end
	end
	local every = running and self:IsOptionActive("allClassTrainers") or false
	if db.allClassTrainers ~= every then
		db.allClassTrainers = every
		if not opening then ns.Pins.RebuildKind("classTrainer") end
	end
	if not changed or opening then return end
	if ns.Map.IsShown() then ns.Pins.Ensure() end
	ns.Map.MarkDirty()
end

function Icons:Enable()
	Apply(self, true)
	ns.Pins.BeforeOpen = function() Apply(self, true, true) end
end
function Icons:Disable()
	ns.Pins.BeforeOpen = nil
	Apply(self, false)
end
function Icons:Refresh() Apply(self, true) end
