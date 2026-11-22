-- A right-click on a bare spot of the map: a small menu there, in the map's own style, to put the map
-- pin on that spot (or take it off) or to copy where it is ("Zone 45.2, 63.1": the game can't write
-- the clipboard, so it's shown selected, for Ctrl+C). Built the first time it's used.
local _, FM = ...
local SP = {}
FM.Spot = SP
local S, Geo = FM.Style, FM.Geo

local menu, copier
local rows = {}
local spot = {}                      -- the spot: u, v, its zone's mapID, name and x, y on it

-- the copy box: its text selected, Ctrl+C copies, Enter or Escape closes
local function Copier()
	if copier then return copier end
	copier = CreateFrame("Frame", "PerfectMapCopyCoords", UIParent)
	copier:SetSize(300, 70)
	copier:SetFrameStrata("DIALOG")
	copier:SetPoint("CENTER", 0, 120)
	copier:EnableMouse(true)
	S.Panel(copier, { 0.05, 0.055, 0.06, 0.97 })
	local head = S.Text(copier, 11, S.ACCENT)
	head:SetPoint("TOPLEFT", 10, -8)
	head:SetText("COORDINATES")
	local box = CreateFrame("EditBox", nil, copier)
	box:SetPoint("TOPLEFT", 10, -26)
	box:SetPoint("TOPRIGHT", -10, -26)
	box:SetHeight(20)
	box:SetAutoFocus(true)
	S.Font(box, 13)
	box:SetTextColor(1, 1, 1)
	local bg = box:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture(S.WHITE)
	bg:SetVertexColor(1, 1, 1, 0.06)
	bg:SetPoint("TOPLEFT", -4, 2)
	bg:SetPoint("BOTTOMRIGHT", 4, -2)
	box:SetScript("OnEscapePressed", function() copier:Hide() end)
	box:SetScript("OnEnterPressed", function() copier:Hide() end)
	box:SetScript("OnTextChanged", function(self, user) if user then self:SetText(self.value or "") self:HighlightText() end end)
	box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	copier.box = box
	local hint = S.Text(copier, 10, S.DIM)
	hint:SetPoint("BOTTOMLEFT", 10, 7)
	hint:SetText("Ctrl+C to copy   Enter: close")
	copier:Hide()
	return copier
end

local function Copy()
	local c = Copier()
	local text = spot.name and ("%s %.1f, %.1f"):format(spot.name, spot.x * 100, spot.y * 100) or ""
	c.box.value = text
	c.box:SetText(text)
	c:Show()
	c.box:SetFocus()
	c.box:HighlightText()
end

local function Row(i)
	local r = rows[i]
	if not r then
		r = S.Button(menu, "", 196, 22, function(self) SP.Hide() self.action() end, "row")
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(14, 14)
		r.icon:SetPoint("LEFT", 6, 0)
		r.label:ClearAllPoints()
		r.label:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
		r.label:SetJustifyH("LEFT")
		rows[i] = r
	end
	return r
end

function SP.Hide()
	if menu then menu:Hide() end
end

-- at (u, v) in world units, by the cursor
function SP.Open(u, v)
	local mapID, name = Geo.ZoneAt(u, v)
	if not mapID or not name or name == "" then SP.Hide() return end
	spot.u, spot.v, spot.map, spot.name = u, v, mapID, name
	spot.x, spot.y = nil, nil
	if mapID then spot.x, spot.y = Geo.UnitsToMap(mapID, u, v) end
	if not menu then
		menu = CreateFrame("Frame", nil, _G.PerfectMapFrame)
		menu:SetFrameStrata("DIALOG")
		menu:EnableMouse(true)
		menu:SetClampedToScreen(true)
		S.Panel(menu, { 0.05, 0.055, 0.06, 0.96 })
		menu.head = S.Text(menu, 11, S.ACCENT)
		menu.head:SetPoint("TOPLEFT", 10, -8)
		menu.head:SetPoint("RIGHT", -10, 0)
		menu.head:SetJustifyH("LEFT")
		menu.head:SetWordWrap(false)
	end
	menu.head:SetText(("%s  |cffb0b0b0%.1f, %.1f|r"):format(name:upper(), spot.x * 100, spot.y * 100))
	local list = {}
	if mapID then
		local has = C_Map.HasUserWaypoint and C_Map.HasUserWaypoint()
		list[#list + 1] = { has and "Move the map pin here" or "Place a map pin here", "Interface\\AddOns\\PerfectMap\\Media\\ring",
			function() FM.Pins.PlaceAt(u, v) end, "Waypoint-MapPin-ChatIcon" }
		if has then
			list[#list + 1] = { "Remove the map pin", "Interface\\Buttons\\UI-GroupLoot-Pass-Up", function() FM.Pins.ClearPin() end }
		end
		list[#list + 1] = { "Copy coordinates", "Interface\\Buttons\\UI-GuildButton-PublicNote-Up", Copy }
	end
	for _, r in ipairs(rows) do r:Hide() end
	local y = -26
	for i, item in ipairs(list) do
		local r = Row(i)
		r.label:SetText(item[1])
		if item[4] and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(item[4]) then
			r.icon:SetAtlas(item[4])
		else
			r.icon:SetTexture(item[2])
		end
		r.action = item[3]
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", 6, y)
		r:Show()
		y = y - 24
	end
	menu:SetSize(208, -y + 6)
	local x, cy = GetCursorPosition()
	local es = UIParent:GetEffectiveScale()
	menu:ClearAllPoints()
	menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / es + 6, cy / es - 4)
	menu:Show()
	PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
end
