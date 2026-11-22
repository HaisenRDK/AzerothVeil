-- Copied from OpenMap (MIT, (c) 2026 OpenMap contributors): Data/Forever/Reveal.lua, generated there from the game's
-- tables (build 1.60.1.70245): the explored-area pieces of the lands off the world map (Isles.lua), so their maps show
-- whole from the start, nothing to explore first.
--   [UiMapArtID] = { ["w:h:x:y"] = "fileIDs, row-major" } (in the art's 1002 x 668 pixels)
-- The battlegrounds' (Dungeon.lua): from the same tables of WoW Forever (WorldMapOverlay, WorldMapOverlayTile, build
-- 1.60.1.71037), for every battleground map with any (only Alterac Valley's has).
local _, FM = ...
FM.MAP_REVEAL = {
	-- Alterac Valley (UiMap 1459)
	[2186] = {["288:256:348:13"] = "8097530, 8097531", ["256:293:399:375"] = "8097532, 8097533", ["320:320:335:172"] = "8097534, 8097535, 8097536, 8097537"},
	-- Zephras Isle (UiMap 2521)
	[2031] = {["141:147:415:289"] = "8124655", ["146:180:460:453"] = "8124654", ["158:141:457:339"] = "8124656", ["194:150:381:169"] = "8124679", ["198:152:298:351"] = "8124675", ["207:185:526:252"] = "8124666", ["207:206:398:230"] = "8124678", ["209:191:600:357"] = "8124653", ["212:271:350:372"] = "8124676, 8124677", ["227:239:652:222"] = "8124657", ["237:265:475:14"] = "8124658, 8124659", ["290:217:494:122"] = "8124660, 8124661", ["302:257:248:192"] = "8124662, 8124663, 8124664, 8124665", ["302:336:479:332"] = "8124671, 8124672, 8124673, 8124674", ["325:267:250:22"] = "8124667, 8124668, 8124669, 8124670"},
}
