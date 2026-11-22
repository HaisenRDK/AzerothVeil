-- AzerothVeil — UI/MinimapButton.lua
-- The minimap button: left click, the map; right click, the options; dragged, it goes round the minimap
-- (its angle kept in AzerothVeilDB.core.minimap). Drawn as every addon's minimap button is (the minimap's
-- own tracking border and background), no library needed. A named, unprotected button on Minimap, so
-- minimap-button collectors (FlareUI's drawer among them) take it as they take the others.
-- Also the game's addon compartment entry (the .toc's AddonCompartmentFunc): the same two clicks.
-- Shown or hidden by the Map module (Modules/Map.lua); nothing runs but while it's dragged.
local _, ns = ...
local L = ns.L

local MB = {}
ns.MinimapButton = MB

local button

local function Cfg()
	local root = ns.Database.Root()
	if not root then return { angle = 225 } end
	local c = root.core.minimap
	if type(c) ~= "table" then
		c = { angle = 225 }
		root.core.minimap = c
	end
	return c
end

local function OnClick(which)
	if which == "RightButton" then
		if ns.Menu then ns.Menu.Toggle() end
	elseif ns.Toggle then
		ns.Toggle()
	end
end

local function Place()
	local angle = math.rad(tonumber(Cfg().angle) or 225)
	local r = (Minimap:GetWidth() / 2) + 10
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

-- (while dragged only: the angle from the minimap's centre to the cursor)
local function Drag()
	local mx, my = Minimap:GetCenter()
	local cx, cy = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	Cfg().angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
	Place()
end

local function Create()
	button = CreateFrame("Button", "AzerothVeilMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local bg = button:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetSize(20, 20)
	bg:SetPoint("TOPLEFT", 7, -5)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ns.MEDIA .. "icon")
	icon:SetSize(17, 17)
	icon:SetPoint("TOPLEFT", 7, -6)
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")
	button:SetScript("OnClick", function(_, which) OnClick(which) end)
	button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", Drag) end)
	button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(ns.TITLE, 1, 0.82, 0)
		GameTooltip:AddLine(L["Left-click: open or close the map"], 1, 1, 1)
		GameTooltip:AddLine(L["Right-click: options"], 1, 1, 1)
		GameTooltip:AddLine(L["Drag: move this button"], 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	Place()
end

-- (shown or not: the Map module's "Minimap button", Modules/Map.lua; hidden while that module is off)
local wanted = false
function MB.IsShown() return wanted end

function MB.SetShown(on)
	wanted = on and true or false
	if wanted and not button and Minimap then Create() end
	if button then button:SetShown(wanted) end
end

-- at login (Core/Bootstrap.lua), once the modules have started
function MB.Init()
	if wanted and not button and Minimap then Create() end
end

-- the game's addon compartment (.toc: AddonCompartmentFunc): the same clicks as the button's
function _G.AzerothVeil_OnAddonCompartmentClick(_, which)
	OnClick(which)
end
