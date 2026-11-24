-- Forever Quest Tint (xanastar's addon, GNU GPL v3: https://github.com/alexdia25/forever-quest-tint) on this map.
-- It marks the quests that weren't in original Classic: a teal gradient on their yellow "!" and "?" map icons
-- (the game's and Questie's), its sign after their names in the quest log, and, if asked, their objectives in its
-- colour. This map draws its own icons and quest log, so the same is done here, as it does it and by its own
-- settings (its colour, its switches), whenever it's enabled; nothing at all when it isn't.
-- Its list of vanilla quests: Data\VanillaQuests.lua. The icon gradient follows its ApplyIconGradient: over the
-- icon, a desaturated copy of its art in the tint made vivid, solid over the bottom 45%, fading out by 75%.
local _, FM = ...
local T = {}
FM.Tint = T

local floor, min, max = math.floor, math.min, math.max
local SOLID, FADE = 0.45, 0.75          -- (as Forever Quest Tint: solid to 45% of the way up, gone by 75%)
local BRIGHTNESS = 1.15                 -- (its lift for the desaturated art)
local VIVID = 2                         -- (its DUI_VIVID: the tint pushed away from grey)
local DEFAULT_TINT = { 0.60, 0.90, 0.95 }
-- its quest-name sign: the infinity of its Media, cropped to the sign (its ICON_* constants)
local MARK_PATH = "Interface\\AddOns\\ForeverQuestTint\\Media\\Infinity.tga"
local MARK_L, MARK_R, MARK_T, MARK_B = 1, 63, 12, 51
local MARK_ASPECT = (MARK_R - MARK_L) / (MARK_B - MARK_T)
local MARK_BASELINE = -2

-- its settings while it's enabled (its saved variables exist only then), else nil
local function Cfg()
	if not (FM.db and FM.db.questTint) then return nil end       -- (AzerothVeil: the Integrations module's switch)
	local db = _G.ForeverQuestTintDB
	return type(db) == "table" and db or nil
end
local function Opt(db, key, default)
	local v = db[key]
	if v == nil then return default end
	return v
end
local function Colour(c)
	return type(c) == "table" and c[1] and c or DEFAULT_TINT
end

function T.Enabled() return Cfg() ~= nil end

-- (binary search over the sorted ranges, as it does)
local function IsVanilla(id)
	local R = FM.VANILLA_QUEST_RANGES
	if not R then return true end
	local lo, hi = 1, #R
	while lo <= hi do
		local mid = floor((lo + hi) / 2)
		local r = R[mid]
		if id < r[1] then hi = mid - 1
		elseif id > r[2] then lo = mid + 1
		else return true end
	end
	return false
end

-- a quest it marks: one not in original Classic (none when it's off)
function T.Marked(questID)
	return Cfg() ~= nil and type(questID) == "number" and questID > 0 and not IsVanilla(questID)
end

-- whether this quest's yellow icons get the gradient (its "Questie's map icons" switch covers the game's too)
function T.IconTinted(questID)
	local db = Cfg()
	return db ~= nil and Opt(db, "questieTint", true) and T.Marked(questID)
end

---------------------------------------------------------------------------
-- The icon gradient
---------------------------------------------------------------------------
local function Lift(x, avg) return max(0, min(1, (avg + (x - avg) * VIVID) * BRIGHTNESS)) end
local function Vivid()
	local db = Cfg()
	local c = Colour(db and db.tint)
	local avg = (c[1] + c[2] + c[3]) / 3
	return Lift(c[1], avg), Lift(c[2], avg), Lift(c[3], avg)
end

-- one piece of the gradient over tex, from..to of its height (what's drawn: as kept on g)
local function Slice(g, piece, tex, from, to, cLow, cHigh)
	local h, t, b = g.height, g.t, g.b
	piece:SetDrawLayer(g.layer, g.sublevel)
	piece:ClearAllPoints()
	piece:SetPoint("BOTTOMLEFT", tex, "BOTTOMLEFT", 0, h * from)
	piece:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", 0, h * from)
	piece:SetHeight(h * (to - from))
	piece:SetTexture(g.file)
	piece:SetTexCoord(g.l, g.r, b + (t - b) * to, b + (t - b) * from)
	piece:SetDesaturated(true)
	piece:SetGradient("VERTICAL", cLow, cHigh)
	piece:Show()
end

-- over tex (the icon: its art `file`, texture coordinates l, r, t, b, `height` tall), the gradient at strength
-- alpha, drawn by host (a frame) in layer/sublevel; show false hides it. What was drawn is kept on tex: when only
-- the strength changes (a fade), only that is redone.
function T.Gradient(host, tex, show, file, l, r, t, b, height, alpha, layer, sublevel)
	local g = tex.fmTint
	if not (show and file and height and height > 0) then
		if g then g.solid:Hide() g.fade:Hide() g.file = nil end     -- (drawn in full next time)
		return
	end
	if not g then
		g = { solid = host:CreateTexture(nil, layer, nil, sublevel), fade = host:CreateTexture(nil, layer, nil, sublevel),
			low = CreateColor(1, 1, 1, 1), high = CreateColor(1, 1, 1, 1), clear = CreateColor(1, 1, 1, 0) }
		tex.fmTint = g
	end
	local cr, cg, cb = Vivid()
	-- (the same as last drawn: only its strength, if that; compared field by field, nothing made each time)
	if g.file == file and g.l == l and g.r == r and g.t == t and g.b == b and g.height == height and g.layer == layer
		and g.sublevel == sublevel and g.cr == cr and g.cg == cg and g.cb == cb then
		if g.alpha ~= alpha then
			g.alpha = alpha
			g.low.a, g.high.a = alpha, alpha
			g.solid:SetGradient("VERTICAL", g.low, g.high)
			g.fade:SetGradient("VERTICAL", g.high, g.clear)
		end
		g.solid:Show() g.fade:Show()
		return
	end
	g.file, g.l, g.r, g.t, g.b, g.height, g.layer, g.sublevel, g.cr, g.cg, g.cb = file, l, r, t, b, height, layer, sublevel, cr, cg, cb
	g.alpha = alpha
	g.low:SetRGBA(cr, cg, cb, alpha)
	g.high:SetRGBA(cr, cg, cb, alpha)
	g.clear:SetRGBA(cr, cg, cb, 0)
	Slice(g, g.solid, tex, 0, SOLID, g.low, g.high)
	Slice(g, g.fade, tex, SOLID, FADE, g.high, g.clear)
end

-- the same over an icon drawn from an atlas (the game's quest icons)
local atlasInfo = {}               -- (an atlas's file and texture coordinates, asked of the game once)
function T.AtlasGradient(host, tex, show, atlas, alpha)
	local info
	if show and atlas then
		info = atlasInfo[atlas]
		if info == nil then
			info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) or false
			atlasInfo[atlas] = info
		end
	end
	if not info then T.Gradient(host, tex, false) return end
	local layer, sub = tex:GetDrawLayer()
	local h = tex:GetHeight()
	if not h or h <= 0 then h = host:GetHeight() end
	T.Gradient(host, tex, true, info.file or info.filename, info.leftTexCoord, info.rightTexCoord,
		info.topTexCoord, info.bottomTexCoord, h, alpha or 1, layer, min((sub or 0) + 1, 7))
end

-- Questie's icons it tints: its yellow "!" (available) and "?" (turn in), uncoloured
function T.QuestieIconTintable(file, r, g, b)
	local Qs = _G.Questie
	if not (file and type(Qs) == "table" and type(Qs.usedIcons) == "table") then return false end
	if (r or 1) < 0.999 or (g or 1) < 0.999 or (b or 1) < 0.999 then return false end
	local a, c = Qs.ICON_TYPE_AVAILABLE, Qs.ICON_TYPE_COMPLETE
	return (a and Qs.usedIcons[a] == file) or (c and Qs.usedIcons[c] == file) or false
end

---------------------------------------------------------------------------
-- The quest log
---------------------------------------------------------------------------
-- its sign for a marked quest's name (its icon or its text symbol, in its colour), and whether it goes first
function T.Marker(questID)
	local db = Cfg()
	if not (db and Opt(db, "marker", true) and T.Marked(questID)) then return nil end
	local c = Colour(Opt(db, "markerUseTint", true) and db.tint or db.markerColor)
	local r, g, b = floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5)
	local glyph
	if Opt(db, "markerIcon", true) then
		local h = tonumber(db.markerHeight) or 8
		local w = floor(h * MARK_ASPECT + 0.5)
		local gap = tonumber(db.markerGap) or 0
		local offX = Opt(db, "markerAtStart", false) and -gap or gap
		glyph = ("|T%s:%d:%d:%d:%d:64:64:%d:%d:%d:%d:%d:%d:%d|t"):format(MARK_PATH, h, w, offX,
			(tonumber(db.markerOffset) or 0) + MARK_BASELINE, MARK_L, MARK_R, MARK_T, MARK_B, r, g, b)
	else
		local sym = db.markerSymbol or "\226\136\158"
		if sym == "" then return nil end
		glyph = ("|cff%02x%02x%02x%s|r"):format(r, g, b, sym)
	end
	return glyph, Opt(db, "markerAtStart", false)
end

-- a quest's name with its sign, where it puts it
function T.MarkTitle(questID, title)
	local glyph, first = T.Marker(questID)
	if not glyph then return title end
	return first and (glyph .. " " .. title) or (title .. " " .. glyph)
end

-- the colour of a marked quest's objectives, when it recolours them: r, g, b (else nil)
function T.ObjectiveColour(questID)
	local db = Cfg()
	if not (db and Opt(db, "objectiveTint", false) and T.Marked(questID)) then return nil end
	local c = Colour(Opt(db, "objectiveUseTint", true) and db.tint or db.objectiveColor)
	return c[1], c[2], c[3]
end
