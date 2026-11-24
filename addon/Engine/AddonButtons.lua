-- AzerothVeil — Engine/AddonButtons.lua: other addons' buttons on the map (the Integrations module's "Other addons'
-- map buttons", Modules/Integrations.lua).
-- Addons put their world map buttons (RareScanner's filters, others...) through the Krowi_WorldMapButtons library:
-- each one a frame of their own on Blizzard's map, in a column from its top left corner on WoW Forever, laid out
-- again by the library at every change of map (its SetPoints). While this map is shown, those buttons are lent to
-- it: the same frames (their clicks, menus and tooltips their addons' own), in a column under the icon menu's
-- button (Map.lua), each put back there whenever the library lays them out; given back to Blizzard's map (their
-- parent, strata and level as they were) when this map closes or the option goes off.
-- Left alone: Blizzard's own buttons the library lists too (not made by it: their names aren't its), and Questie's
-- (this map has its own Questie button, Map.lua). Nothing of theirs is changed but where their buttons stand; the
-- library's SetPoints and Add are followed (hooksecurefunc), only acting while this map is shown with the option on.
-- Their parent while they're here is a frame of ours standing for Blizzard's map: their code asks their parent
-- what Blizzard's map knows (RareScanner's menu: self:GetParent():GetMapID()), so it answers the same, reading
-- Blizzard's map (the zone it's on, which this map keeps on the zone in view: AddonPins.lua): getters only, nothing
-- of Blizzard's map called that changes or fires anything.
-- Nothing runs while the map is closed.
local _, FM = ...
local B = {}
FM.AddonButtons = B

local LIB = "Krowi_WorldMapButtons-1.4"
local GAP = 4

local parent, AnchorOf, level  -- the buttons' parent here (Attach), the frame the column hangs under (a function), level
local taken = {}               -- button -> { parent, strata, level } as it was, to give it back
local hooked = false
local busy = false

local function Lib()
	local ls = _G.LibStub
	return ls and ls(LIB, true) or nil
end

local function Wanted() return parent ~= nil and FM.db and FM.db.addonButtons and FM.Map.IsShown() and true or false end

-- an addon's button the library made (its name: "Krowi_WorldMapButtons<n>"), not Questie's
local function Theirs(b)
	local n = type(b) == "table" and b.GetName and b:GetName()
	if type(n) ~= "string" or not n:find("^Krowi_WorldMapButtons") then return false end
	local q = _G.Questie
	if type(q) == "table" and type(q.WorldMap) == "table" and q.WorldMap.Button == b then return false end
	return true
end

local function GiveBack()
	local any = false
	for b, was in pairs(taken) do
		b:SetParent(was.parent)
		b:SetFrameStrata(was.strata)
		b:SetFrameLevel(was.level)
		taken[b] = nil
		any = true
	end
	return any
end

-- the buttons where they go now: in a column on this map while it's shown, else back on Blizzard's
function B.Update()
	if busy then return end
	local lib = Lib()
	if not (lib and type(lib.Buttons) == "table") then return end
	if not Wanted() then
		if GiveBack() and type(lib.SetPoints) == "function" then
			-- (back where the library puts them)
			busy = true
			pcall(lib.SetPoints)
			busy = false
		end
		return
	end
	if not hooked then
		hooked = true
		-- (the library lays its buttons out again at each change of Blizzard's map, and when one is added)
		if type(lib.SetPoints) == "function" then hooksecurefunc(lib, "SetPoints", B.Update) end
		if type(lib.Add) == "function" then hooksecurefunc(lib, "Add", function() B.Update() end) end
	end
	local anchor = AnchorOf()
	local strata = parent:GetFrameStrata()
	local y = 0
	for _, b in ipairs(lib.Buttons) do
		if Theirs(b) then
			if not taken[b] then
				taken[b] = { parent = b:GetParent(), strata = b:GetFrameStrata(), level = b:GetFrameLevel() }
				b:SetParent(parent)
			end
			b:SetFrameStrata(strata)
			b:SetFrameLevel(level)
			if b:IsShown() then
				b:ClearAllPoints()
				b:SetPoint("TOP", anchor, "BOTTOM", 0, -GAP - y)
				y = y + (b:GetHeight() or 0) + GAP
			end
		end
	end
end

-- (what their code may ask their parent, read from Blizzard's map)
local GETTERS = { "GetMapID", "GetCanvasContainer", "GetCanvas", "GetCanvasScale", "GetCanvasZoomPercent" }

-- Map.lua: this map's view, the frame the column hangs under (a function), the level the buttons take
function B.Attach(view, anchorOf, frameLevel)
	AnchorOf, level = anchorOf, frameLevel
	parent = CreateFrame("Frame", nil, view)
	parent:SetAllPoints(view)
	parent:SetFrameLevel(frameLevel)
	for _, name in ipairs(GETTERS) do
		parent[name] = function()
			local wm = _G.WorldMapFrame
			local f = wm and wm[name]
			if type(f) == "function" then return f(wm) end
		end
	end
end

-- /av addons: the buttons seen
function B.Report(P)
	local lib = Lib()
	if not (lib and type(lib.Buttons) == "table") then P("  map buttons (Krowi_WorldMapButtons): none") return end
	local names = {}
	for _, b in ipairs(lib.Buttons) do
		local n = b.GetName and b:GetName() or "?"
		names[#names + 1] = tostring(n) .. (Theirs(b) and (taken[b] and " (on our map)" or " (an addon's)") or " (left alone)")
	end
	P("  map buttons (Krowi_WorldMapButtons): " .. (#names > 0 and table.concat(names, ", ") or "none"))
end
