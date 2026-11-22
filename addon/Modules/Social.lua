-- AzerothVeil — Modules/Social.lua
-- "Friends & guild": friends and guild members who share where they are, as dots on the map, and your
-- own place shared with them (OpenMap's protocol, prefix OpenMapLoc: seen by OpenMap and PerfectMap users).
-- The work is PerfectMap's Engine/Friends.lua; this module only starts and stops it and owns its settings.
-- Off: no addon message is sent or heard, no roster is scanned, no timer runs, no dot is drawn.
-- Its settings were PerfectMap's engine settings friends / friendsShare / shareAsked (moved here by the
-- schema migration 1, Core/Database.lua).
local _, ns = ...
local L = ns.L

local Social = ns.Modules:Register({
	name = "social",
	title = L["Friends & guild"],
	description = L["Friends and guild members who use AzerothVeil, PerfectMap or OpenMap and share where they are show on the map as a dot in their class colour. You can share your own place with them too.\n\nOff: nothing is sent or received, and nothing runs."],
	order = 50,
	icon = "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon",
	defaultEnabled = true,
	settings = {
		{ key = "show", icon = "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon", type = "toggle", default = true,
			label = L["Show friends & guild on the map"],
			tooltip = L["A class-coloured dot where each friend or guild member who shares their place stands."] },
		{ key = "share", icon = "Interface\\Icons\\INV_Letter_02", type = "toggle", default = false,
			label = L["Share where you are"],
			tooltip = L["Your guild, and your friends who use AzerothVeil, PerfectMap or OpenMap, see you on their map (every 10 s while you move). Never from inside a dungeon, raid or battleground."] },
		{ key = "asked", type = "hidden", default = false },
	},
})

function Social:Enable()
	-- (Friends.lua reads this module's settings table live: a change is seen at once)
	ns.Friends.Start(self.db)
end

function Social:Disable()
	ns.Friends.Stop()
end

function Social:Refresh()
	ns.Friends.Refresh()
end
