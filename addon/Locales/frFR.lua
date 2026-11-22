-- AzerothVeil — Locales/frFR.lua
-- French texts: core, options, modules and the map engine's own (PerfectMap's) visible texts.
-- The keys are the English texts (Locales/enUS.lua: English needs no table; a key missing here shows in
-- English). scripts/check.sh fails if a L["..."] used in the code has no entry here.
-- Proper names of the game are kept as the French client names them; names the game gives at run time
-- (zones, cities, NPCs, quests) come from its own API, already in the player's language.
local _, ns = ...
if ns.LOCALE ~= "frFR" then return end
local L = ns.L

---------------------------------------------------------------------------
-- Core
---------------------------------------------------------------------------
L["Toggle AzerothVeil"] = "Ouvrir / fermer AzerothVeil"
L["PerfectMap is loaded too: both take over the M key and Blizzard's map. Disable one of them in the AddOns list."] =
	"PerfectMap est aussi chargé : les deux prennent la touche M et la carte de Blizzard. Désactivez l'un des deux dans la liste des AddOns."
L["window reset"] = "position de la fenêtre réinitialisée"
L["/av - open/close  |  /av config - settings & modules  |  /av modules [enable|disable <name>] - modules  |  /av stats - performance  |  /av reset - window position  |  /av find - centre on you  |  /av sailings [log|test] - boats & zeppelins shared  |  /av addons - other addons' icons"] =
	"/av - ouvrir/fermer  |  /av config - réglages et modules  |  /av modules [enable|disable <nom>] - modules  |  /av stats - performances  |  /av reset - position de la fenêtre  |  /av find - centrer sur vous  |  /av sailings [log|test] - bateaux et zeppelins partagés  |  /av addons - icônes des autres addons"

---------------------------------------------------------------------------
-- Module manager
---------------------------------------------------------------------------
L["Requires the addon %s"] = "Nécessite l'addon %s"
L["%s is loaded and takes its place"] = "%s est chargé et prend le relais"
L["Requires the module %s"] = "Nécessite le module %s"
L["Error while starting (see the error report)"] = "Erreur au démarrage (voir le rapport d'erreur)"
L["Circular dependency"] = "Dépendance circulaire"
L["active"] = "actif"
L["disabled"] = "désactivé"
L["unavailable"] = "indisponible"
L["Unknown module: %s"] = "Module inconnu : %s"
L["A /reload is needed to remove it completely."] = "Un /reload est nécessaire pour le retirer complètement."
L["Modules:"] = "Modules :"
L["/av modules enable <name>  |  /av modules disable <name>  |  /av config"] =
	"/av modules enable <nom>  |  /av modules disable <nom>  |  /av config"

---------------------------------------------------------------------------
-- Options window
---------------------------------------------------------------------------
L["Modules"] = "Modules"
L["This module has no settings."] = "Ce module n'a pas de réglages."
L["Active"] = "Actif"
L["Disabled: its settings are kept and come back when it's enabled."] =
	"Désactivé : ses réglages sont conservés et reviennent à sa réactivation."
L["Not running"] = "Inactif"
L["Disabled: its settings are kept."] = "Désactivé : ses réglages sont conservés."
L["The same settings are in AzerothVeil's options window (/av config, the minimap button, the map's gear)."] =
	"Les mêmes réglages sont dans la fenêtre d'options d'AzerothVeil (/av config, le bouton de la minicarte, la roue dentée de la carte)."
L["Settings"] = "Réglages"
L["Minimap button"] = "Bouton de la minicarte"
L["Left-click: open or close the map"] = "Clic gauche : ouvrir ou fermer la carte"
L["Right-click: options"] = "Clic droit : options"
L["Drag: move this button"] = "Glisser : déplacer ce bouton"
L["Enable this module"] = "Activer le module"
L["Reload the interface"] = "Recharger l'interface"
L["This module changed parts of the game that can only be put back by a reload."] =
	"Ce module a modifié des éléments du jeu qui ne peuvent être rétablis que par un rechargement."

---------------------------------------------------------------------------
-- Module: Friends & guild
---------------------------------------------------------------------------
L["Friends & guild"] = "Amis & guilde"
L["Friends and guild members who use AzerothVeil, PerfectMap or OpenMap and share where they are show on the map as a dot in their class colour. You can share your own place with them too.\n\nOff: nothing is sent or received, and nothing runs."] =
	"Les amis et membres de guilde qui utilisent AzerothVeil, PerfectMap ou OpenMap et partagent leur position apparaissent sur la carte sous forme d'un point à la couleur de leur classe. Vous pouvez aussi partager la vôtre.\n\nDésactivé : rien n'est envoyé ni reçu, et rien ne tourne."
L["Show friends & guild on the map"] = "Afficher amis et guilde sur la carte"
L["A class-coloured dot where each friend or guild member who shares their place stands."] =
	"Un point à la couleur de sa classe à l'endroit où se trouve chaque ami ou membre de guilde qui partage sa position."
L["Share where you are"] = "Partager ma position"
L["Your guild, and your friends who use AzerothVeil, PerfectMap or OpenMap, see you on their map (every 10 s while you move). Never from inside a dungeon, raid or battleground."] =
	"Votre guilde et vos amis qui utilisent AzerothVeil, PerfectMap ou OpenMap vous voient sur leur carte (toutes les 10 s quand vous bougez). Jamais depuis un donjon, un raid ou un champ de bataille."
L["Guild"] = "Guilde"
L["Friend"] = "Ami"
L["Updated %d s ago"] = "Mis à jour il y a %d s"
L["Friends and guild"] = "Amis et guilde"
L["Your friends and guild members who use AzerothVeil, PerfectMap or OpenMap show on your map as a dot where they stand. Share where you are, so they see you on theirs?"] =
	"Vos amis et membres de guilde qui utilisent AzerothVeil, PerfectMap ou OpenMap apparaissent sur votre carte sous forme d'un point. Partager votre position pour qu'ils vous voient sur la leur ?"
L["Share where I am"] = "Partager ma position"
L["Not now"] = "Pas maintenant"
L["Only your guild and friends, never from a dungeon, raid or battleground. /av config: Friends & guild."] =
	"Uniquement votre guilde et vos amis, jamais depuis un donjon, un raid ou un champ de bataille. /av config : Amis & guilde."

---------------------------------------------------------------------------
-- Module: Transports
---------------------------------------------------------------------------
L["Transports"] = "Transports"
L["Flight masters, harbors, zeppelin towers and the Deeprun Tram on the map, the lines of their routes, and each boat and zeppelin where it is now. A click on a dock takes the map to where it goes.\n\nOff: none of it is shown and nothing of it runs."] =
	"Les maîtres de vol, les ports, les tours des zeppelins et le Tram des profondeurs sur la carte, le tracé de leurs itinéraires, et chaque bateau et zeppelin là où il se trouve. Un clic sur un quai emmène la carte à sa destination.\n\nDésactivé : rien de tout cela n'est affiché et rien ne tourne."
L["Display"] = "Affichage"
L["Show boats"] = "Afficher les bateaux"
L["Show flight masters"] = "Afficher les maîtres de vol"
L["The flight masters of your faction (and the neutral ones) where WoW Forever has one."] =
	"Les maîtres de vol de votre faction (et les neutres), là où WoW Forever en a un."
L["Harbors and their boats (yours and the goblins', which take everyone)."] =
	"Les ports et leurs bateaux (ceux de votre faction et ceux des gobelins, ouverts à tous)."
L["The other faction's harbors"] = "Ports de l'autre faction"
L["The other faction's harbors too, with their boats' routes (named in red)."] =
	"Les ports de l'autre faction aussi, avec les itinéraires de leurs bateaux (nommés en rouge)."
L["Show zeppelins"] = "Afficher les zeppelins"
L["Zeppelin towers and their zeppelins."] = "Les tours des zeppelins et leurs zeppelins."
L["Show other transports"] = "Afficher les autres transports"
L["The other ways to travel the game has data for: the Deeprun Tram, Zephras Isle's airships."] =
	"Les autres moyens de transport dont le jeu fournit les données : le Tram des profondeurs, les dirigeables de l'île de Zephras."
L["Deeprun Tram"] = "Tram des profondeurs"
L["The tram's two stations, in Stormwind and Ironforge."] = "Les deux stations du tram, à Hurlevent et à Forgefer."
L["Zephras Isle airships"] = "Dirigeables de l'île de Zephras"
L["The airships' docks to and from Zephras Isle (a click opens the isle's own map)."] =
	"Les quais des dirigeables vers et depuis l'île de Zephras (un clic ouvre la carte de l'île)."
L["Show route lines"] = "Afficher les tracés des itinéraires"
L["A thin line along the way each boat and zeppelin sails, over its dock when the cursor is on it. Alliance boats blue, the rest red."] =
	"Une fine ligne le long du trajet de chaque bateau et zeppelin, affichée au survol de son quai. Bateaux de l'Alliance en bleu, les autres en rouge."
L["Always show every route"] = "Toujours afficher tous les tracés"
L["Every route at once, not only the hovered dock's. Also the routes button in the map's tools."] =
	"Tous les itinéraires en même temps, pas seulement ceux du quai survolé. Aussi le bouton des tracés dans les outils de la carte."
L["Features"] = "Fonctionnalités"
L["Boat & zeppelin tracking"] = "Suivi des bateaux et zeppelins"
L["Each boat and zeppelin where it is right now, moving along its route. Learnt while you ride one (a light check of where you are, every 0.8 s) or from players sharing it."] =
	"Chaque bateau et zeppelin là où il se trouve en ce moment, en mouvement sur son itinéraire. Appris quand vous voyagez à bord (une vérification légère de votre position toutes les 0,8 s) ou grâce aux joueurs qui le partagent."
L["Share sightings"] = "Partager les observations"
L["Trade when each boat and zeppelin was seen with your guild, your group and your friends who use AzerothVeil or PerfectMap."] =
	"Échanger l'heure à laquelle chaque bateau et zeppelin a été vu avec votre guilde, votre groupe et vos amis qui utilisent AzerothVeil ou PerfectMap."
L["Click: go to the destination"] = "Clic : aller à la destination"
L["A click on a boat, zeppelin or tram icon takes the map straight to where it goes."] =
	"Un clic sur l'icône d'un bateau, d'un zeppelin ou du tram emmène directement la carte à sa destination."
L["Turn on the Transports module and its route lines first (/av config)."] =
	"Activez d'abord le module Transports et ses tracés d'itinéraires (/av config)."

---------------------------------------------------------------------------
-- Map engine (PerfectMap): the window and its tools
---------------------------------------------------------------------------
L["Your corpse"] = "Votre cadavre"
L["Fishing: %s"] = "Pêche : %s"
L["Close (Esc)"] = "Fermer (Échap)"
L["Options"] = "Options"
L["AzerothVeil's settings."] = "Les réglages d'AzerothVeil."
L["Questie's own settings."] = "Les réglages de Questie."
L["Dungeon"] = "Donjon"
L["Dungeon / World"] = "Donjon / Monde"
L["Inside a dungeon: its map, or the world's."] = "Dans un donjon : sa carte, ou celle du monde."
L["Quest log"] = "Journal de quêtes"
L["Fold it away (L)."] = "Le replier (L)."
L["Bring it out (L)."] = "L'afficher (L)."
L["Map tools"] = "Outils de la carte"
L["Click: show or hide the map's tools."] = "Clic : afficher ou masquer les outils de la carte."
L["Boat & zeppelin routes"] = "Itinéraires des bateaux et zeppelins"
L["All shown: click to show each only over its dock."] = "Tous affichés : cliquez pour n'afficher chacun qu'au survol de son quai."
L["Each over its dock: click to show them all."] = "Au survol de leur quai : cliquez pour tous les afficher."
L["Center on me"] = "Centrer sur moi"
L["The map on where you are, as M opens it (inside a dungeon: its map)."] =
	"La carte centrée sur vous, comme à l'ouverture avec M (dans un donjon : sa carte)."
L["Gathering icons"] = "Icônes de récolte"
L["Shown: click to hide them."] = "Affichées : cliquez pour les masquer."
L["Hidden: click to show them."] = "Masquées : cliquez pour les afficher."
L["\nThe herbs, ore and other nodes of your gathering addons (GatherMate2, Gatherer...)."] =
	"\nLes herbes, minerais et autres points de vos addons de récolte (GatherMate2, Gatherer...)."
L["Ctrl+C to copy   Enter: close"] = "Ctrl+C pour copier   Entrée : fermer"
L["Move the map pin here"] = "Déplacer le repère ici"
L["Place a map pin here"] = "Placer un repère ici"
L["Remove the map pin"] = "Retirer le repère"
L["Copy coordinates"] = "Copier les coordonnées"

-- icons and their tooltips
L["Flight masters"] = "Maîtres de vol"
L["Dungeons"] = "Donjons"
L["Raids"] = "Raids"
L["Raid"] = "Raid"
L["Capital cities"] = "Capitales"
L["Alliance capital"] = "Capitale de l'Alliance"
L["Horde capital"] = "Capitale de la Horde"
L["Neutral"] = "Neutre"
L["Not discovered yet"] = "Pas encore découvert"
L["Harbor"] = "Port"
L["Zeppelin towers"] = "Tours des zeppelins"
L["Zeppelin tower"] = "Tour des zeppelins"
L["Airships (Zephras Isle)"] = "Dirigeables (île de Zephras)"
L["Boat"] = "Bateau"
L["Zeppelin"] = "Zeppelin"
L["Airship"] = "Dirigeable"
L["Transport"] = "Transport"
L["%s to %s"] = "%s pour %s"
L["Tram to %s"] = "Tram pour %s"
L["The other faction's"] = "De l'autre faction"
L["Questie icons"] = "Icônes de Questie"
L["Innkeepers"] = "Aubergistes"
L["Bankers"] = "Banquiers"
L["Auctioneers"] = "Commissaires-priseurs"
L["Repair"] = "Réparations"
L["Class trainers"] = "Maîtres de classe"
L["Portal trainers"] = "Maîtres des portails"
L["Weapon masters"] = "Maîtres d'armes"
L["Stable masters"] = "Maîtres des écuries"
L["Battlemasters"] = "Maîtres de guerre"
L["Spirit healers"] = "Gardiens des esprits"
L["Barbers"] = "Barbiers"
L["Transmogrifiers"] = "Transmogrificateurs"
L["Mailboxes"] = "Boîtes aux lettres"
L["Food"] = "Nourriture"
L["Drink"] = "Boissons"
L["Reagents"] = "Composants"
L["Trade goods"] = "Fournitures d'artisanat"
L["Bags"] = "Sacs"
L["Potions"] = "Potions"
L["Ammo"] = "Munitions"
L["Poisons"] = "Poisons"
L["Alchemy"] = "Alchimie"
L["Blacksmithing"] = "Forge"
L["Cooking"] = "Cuisine"
L["Enchanting"] = "Enchantement"
L["Engineering"] = "Ingénierie"
L["First Aid"] = "Secourisme"
L["Fishing"] = "Pêche"
L["Herbalism"] = "Herboristerie"
L["Leatherworking"] = "Travail du cuir"
L["Mining"] = "Minage"
L["Skinning"] = "Dépeçage"
L["Tailoring"] = "Couture"
L["Riding"] = "Monte"
L["Waypoint"] = "Point de passage"
L["Right-click to remove it"] = "Clic droit pour le retirer"
L["Right-click: "] = "Clic droit : "
L["remove waypoint"] = "retirer le point de passage"
L["set waypoint"] = "placer un point de passage"
L["Left-click: its map   "] = "Clic gauche : sa carte   "
L["can't set a waypoint there"] = "impossible de placer un point de passage ici"

-- boats and zeppelins live
L["est. at dock, leaves in "] = "à quai (estimé), départ dans "
L["docked, leaves in "] = "à quai, départ dans "
L["Estimated position: last seen before this game patch"] = "Position estimée : vu pour la dernière fois avant ce patch du jeu"
L["Estimated position: waiting for a newer sighting"] = "Position estimée : en attente d'une observation plus récente"
L["Timetable from %s, %s ago"] = "Horaires de %s, il y a %s"
L["Sailings: boat & zeppelin tracking is off (Transports module, /av config)."] =
	"Traversées : le suivi des bateaux et zeppelins est désactivé (module Transports, /av config)."
L["Sailings: sharing sightings is off (Transports module): only your own sightings."] =
	"Traversées : le partage des observations est désactivé (module Transports) : seulement vos propres observations."

-- dungeons
L["FLOORS  |cff9a9a9a%d / %d|r"] = "NIVEAUX  |cff9a9a9a%d / %d|r"
L["CHOOSE A DUNGEON"] = "CHOISIR UN DONJON"
L["Dungeons here"] = "Donjons ici"
L["This entrance leads to more than one: pick another."] = "Cette entrée mène à plusieurs donjons : choisissez-en un autre."
L["Level"] = "Niveau"
L["Boss"] = "Boss"
L["Raid entrance"] = "Entrée de raid"
L["Dungeon entrance"] = "Entrée de donjon"
L["ALSO HERE"] = "ÉGALEMENT ICI"
L["Floor "] = "Niveau "
L["Horde Flag"] = "Drapeau de la Horde"
L["Alliance Flag"] = "Drapeau de l'Alliance"
L["Flag"] = "Drapeau"
L["World"] = "Monde"
L["Map drawn by Santiago Reyes  \194\183  sreyesmaps.com"] = "Carte dessinée par Santiago Reyes  \194\183  sreyesmaps.com"
L["The game has no map of this place."] = "Le jeu n'a pas de carte de ce lieu."
L["Right-click: back to the world"] = "Clic droit : retour au monde"

-- quests on the map
L["Ready for turn-in"] = "Prête à être rendue"
L["Available Quest"] = "Quête disponible"
L["Quest available"] = "Quête disponible"
L["Turn in"] = "À rendre"
L["Quest"] = "Quête"

-- quest log
L["Track"] = "Suivre"
L["Untrack"] = "Ne plus suivre"
L["Show it in the objective tracker."] = "L'afficher dans le suivi des objectifs."
L["Ready to turn in"] = "Prête à être rendue"
L["|cff40e040Ready to turn in|r"] = "|cff40e040Prête à être rendue|r"
L["Ready to hand in"] = "Prête à être rendue"
L["PvP"] = "JcJ"
L["Kill"] = "Tuer"
L["Defeat players"] = "Vaincre des joueurs"
L["Collect"] = "Collecter"
L["Use"] = "Utiliser"
L["Explore"] = "Explorer"
L["Reputation"] = "Réputation"
L["Do"] = "Faire"
L["Group quest"] = "Quête de groupe"
L["Elite"] = "Élite"
L["World event"] = "Événement mondial"
L["Legendary"] = "Légendaire"
L["Class quest"] = "Quête de classe"
L["Failed"] = "Échouée"
L["  |cffff4040Failed|r"] = "  |cffff4040Échouée|r"
L["Daily"] = "Journalière"
L["Repeatable"] = "Répétable"
L["No quests."] = "Aucune quête."
L["No quest matches."] = "Aucune quête ne correspond."
L["Quests: |cffffffff%d/%d|r"] = "Quêtes : |cffffffff%d/%d|r"
L[" experience"] = " d'expérience"
L[" honor"] = " d'honneur"
L["Group: %d"] = "Groupe : %d"
L["Time left: "] = "Temps restant : "
L["Requires "] = "Nécessite "
L["Level %d"] = "Niveau %d"
L["Description"] = "Description"
L["Rewards"] = "Récompenses"
L["You will be able to choose one of these rewards:"] = "Vous pourrez choisir l'une de ces récompenses :"
L["You will also receive:"] = "Vous recevrez également :"
L["You will receive:"] = "Vous recevrez :"
L["|cffff5050Sure?|r"] = "|cffff5050Sûr ?|r"
L["Abandon"] = "Abandonner"
L["Search Quest Log"] = "Rechercher dans le journal"
L["Search quests"] = "Rechercher des quêtes"
L["Back"] = "Retour"
L["Navigate"] = "Guider"
L["Follow it with the in-game waypoint arrow."] = "La suivre avec la flèche de navigation du jeu."
L["Share"] = "Partager"
L["Offer it to your group."] = "La proposer à votre groupe."
L["Click twice to abandon it."] = "Cliquez deux fois pour l'abandonner."

-- the map's own options (its gear menu)
L["Show all"] = "Tout afficher"
L["Hide all"] = "Tout masquer"
L["Map"] = "Carte"
L["Open with M"] = "Ouvrir avec M"
L["M opens this map instead of Blizzard's. Outside combat, so do the map buttons, map pins in chat, quests' \"show on map\" and other addons."] =
	"M ouvre cette carte au lieu de celle de Blizzard. Hors combat, c'est aussi le cas des boutons de carte, des repères partagés dans le chat, du « afficher sur la carte » des quêtes et des autres addons."
L["Centre on me when opened"] = "Centrer sur moi à l'ouverture"
L["Off: it opens where you left it."] = "Désactivé : elle s'ouvre là où vous l'avez laissée."
L["Remember last zoom"] = "Mémoriser le dernier zoom"
L["The map opens at the zoom you closed it at."] = "La carte s'ouvre au zoom auquel vous l'avez fermée."
L["Off: it always opens at the same zoom."] = "Désactivé : elle s'ouvre toujours au même zoom."
L["Highlight zone under cursor"] = "Surligner la zone sous le curseur"
L["The zone under the mouse lights up, as on Blizzard's continent map."] = "La zone sous la souris s'éclaire, comme sur la carte des continents de Blizzard."
L["Dungeon maps inside"] = "Cartes des donjons à l'intérieur"
L["Inside a dungeon, raid or battleground the map shows its own map, every floor, you and your group on it."] =
	"Dans un donjon, un raid ou un champ de bataille, la carte affiche son plan, chaque niveau, vous et votre groupe."
L["A right-click on it, or the header's World button, goes back to the world."] =
	"Un clic droit dessus, ou le bouton Monde de l'en-tête, revient au monde."
L["Bosses on dungeon maps"] = "Boss sur les cartes des donjons"
L["Where each boss stands on a dungeon's map, with its portrait and level, as MapUtils shows them."] =
	"L'emplacement de chaque boss sur la carte d'un donjon, avec son portrait et son niveau, comme les affiche MapUtils."
L["Sum identical icons"] = "Regrouper les icônes identiques"
L["Identical icons that overlap show as one, with their count, every one of them in its tooltip, at every zoom."] =
	"Les icônes identiques qui se chevauchent n'en forment qu'une, avec leur nombre, et toutes dans son infobulle, à tous les zooms."
L["Off: every icon on its own."] = "Désactivé : chaque icône séparément."
L["Other addons' icons"] = "Icônes des autres addons"
L["Icons other addons put on Blizzard's map (GatherMate2, HandyNotes, TomTom and others) show on this one, exactly where they put them, with their own tooltips and clicks."] =
	"Les icônes que d'autres addons placent sur la carte de Blizzard (GatherMate2, HandyNotes, TomTom et d'autres) apparaissent sur celle-ci, au même endroit, avec leurs propres infobulles et clics."
L["They show two steps of the wheel closer than the townsfolk."] = "Elles apparaissent deux crans de molette plus près que les PNJ des villes."
L["Fade while moving"] = "Estomper en mouvement"
L["The map turns see-through while you move."] = "La carte devient transparente quand vous vous déplacez."
L["Detail"] = "Détails"
L["Caves up close"] = "Grottes en zoom rapproché"
L["Zoom right in on a cave, mine, crypt or dungeon entrance and its own map surfaces: Blizzard's where it drew one, else the game's minimap of it inside."] =
	"Zoomez sur une grotte, une mine, une crypte ou l'entrée d'un donjon et son plan apparaît : celui de Blizzard s'il existe, sinon la minicarte de l'intérieur."
L["Minimap terrain up close"] = "Terrain de la minicarte en zoom rapproché"
L["Zoomed right in, the ground turns into the minimap's own: trees, rocks, roads and buildings."] =
	"En zoom rapproché, le sol devient celui de la minicarte : arbres, rochers, routes et bâtiments."
L["The sea stays the map's."] = "La mer reste celle de la carte."
L["Fishing skill of zones"] = "Compétence de pêche des zones"
L["Under the zone's name: the fishing skill its waters want."] = "Sous le nom de la zone : la compétence de pêche requise par ses eaux."
L["Icon size"] = "Taille des icônes"
L["Places"] = "Lieux"
L["Enemy flight masters"] = "Maîtres de vol ennemis"
L["The other faction's flight masters too, in red."] = "Les maîtres de vol de l'autre faction aussi, en rouge."
L["Townsfolk"] = "PNJ des villes"
L["Profession trainers"] = "Maîtres de métiers"
L["Professions"] = "Métiers"
L["On the map"] = "Sur la carte"
L["Objectives & turn-ins"] = "Objectifs et quêtes à rendre"
L["The quest log's quests, as Blizzard's map shows them."] = "Les quêtes du journal, comme les affiche la carte de Blizzard."
L["Quests to pick up"] = "Quêtes à prendre"
L["The quests you can take, as Blizzard's map shows them."] = "Les quêtes que vous pouvez prendre, comme les affiche la carte de Blizzard."
L["Quest areas"] = "Zones de quête"
L["The blue area of the followed quest, and of the one under the mouse."] = "La zone bleue de la quête suivie et de celle sous la souris."
L["Questie's quest, objective and turn-in icons, with its own tooltips."] = "Les icônes de quêtes, d'objectifs et de quêtes à rendre de Questie, avec ses propres infobulles."
L["Quests"] = "Quêtes"
L["Replace Blizzard's quest log"] = "Remplacer le journal de quêtes de Blizzard"
L["L opens this map's quest log. Outside combat, so does clicking a quest in the objective tracker or its menu."] =
	"L ouvre le journal de quêtes de cette carte. Hors combat, c'est aussi le cas d'un clic sur une quête dans le suivi des objectifs ou son menu."
L["Quest log beside the map"] = "Journal de quêtes à côté de la carte"
L["Docked to the map's right: the window grows, the map keeps its shape."] = "Ancré à droite de la carte : la fenêtre s'agrandit, la carte garde ses proportions."
L["Drag: move   Wheel: zoom   Right-click: pin / coordinates (on an icon: waypoint)   /av help"] =
	"Glisser : déplacer   Molette : zoom   Clic droit : repère / coordonnées (sur une icône : point de passage)   /av help"
