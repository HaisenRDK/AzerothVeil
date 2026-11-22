-- AzerothVeil — Locales/frFR.lua
-- French texts of the core, the options and the modules. The keys are the English texts (enUS needs
-- no file: a missing key shows its English key). The engine's own texts (PerfectMap's) are English
-- for now: they're translated as they're moved to L[...].
local _, ns = ...
if ns.LOCALE ~= "frFR" then return end
local L = ns.L

-- Core
L["Toggle AzerothVeil"] = "Ouvrir / fermer AzerothVeil"
L["PerfectMap is loaded too: both take over the M key and Blizzard's map. Disable one of them in the AddOns list."] =
	"PerfectMap est aussi chargé : les deux prennent la touche M et la carte de Blizzard. Désactivez l'un des deux dans la liste des AddOns."

-- Module manager
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

-- Options
L["This module has no settings."] = "Ce module n'a pas de réglages."
L["Active"] = "Actif"
L["Disabled: its settings are kept and come back when it's enabled."] =
	"Désactivé : ses réglages sont conservés et reviennent à sa réactivation."
L["Not running"] = "Inactif"
L["Pick a module to turn it on or off and change its settings. The map's own settings are in the map's gear menu (/av)."] =
	"Choisissez un module pour l'activer, le désactiver ou modifier ses réglages. Les réglages de la carte elle-même sont dans le menu (roue dentée) de la carte (/av)."
L["Enable this module"] = "Activer ce module"
L["Reload the interface"] = "Recharger l'interface"
L["This module changed parts of the game that can only be put back by a reload."] =
	"Ce module a modifié des éléments du jeu qui ne peuvent être rétablis que par un rechargement."
L["The options can't be opened in combat."] = "Les options ne peuvent pas être ouvertes en combat."
L["Open the game's Options > AddOns > AzerothVeil."] = "Ouvrez Options du jeu > AddOns > AzerothVeil."
L["Friends & guild settings..."] = "Réglages Amis & guilde..."

-- Module: Friends & guild
L["Friends & guild"] = "Amis & guilde"
L["Friends and guild members who use AzerothVeil, PerfectMap or OpenMap and share where they are show on the map as a dot in their class colour. You can share your own place with them too.\n\nOff: nothing is sent or received, and nothing runs."] =
	"Les amis et membres de guilde qui utilisent AzerothVeil, PerfectMap ou OpenMap et partagent leur position apparaissent sur la carte sous forme d'un point à la couleur de leur classe. Vous pouvez aussi partager la vôtre.\n\nDésactivé : rien n'est envoyé ni reçu, et rien ne tourne."
L["Show friends & guild on the map"] = "Afficher amis et guilde sur la carte"
L["A class-coloured dot where each friend or guild member who shares their place stands."] =
	"Un point à la couleur de sa classe à l'endroit où se trouve chaque ami ou membre de guilde qui partage sa position."
L["Share where you are"] = "Partager ma position"
L["Your guild, and your friends who use AzerothVeil, PerfectMap or OpenMap, see you on their map (every 10 s while you move). Never from inside a dungeon, raid or battleground."] =
	"Votre guilde et vos amis qui utilisent AzerothVeil, PerfectMap ou OpenMap vous voient sur leur carte (toutes les 10 s quand vous bougez). Jamais depuis un donjon, un raid ou un champ de bataille."
