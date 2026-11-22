# Architecture d'AzerothVeil

## 1. Organisation des fichiers

```
AzerothVeil/                     dépôt Git (WSL)
├── addon/                       ← EXACTEMENT ce qui est chargé par WoW (déployé dans AddOns/AzerothVeil)
│   ├── AzerothVeil.toc          ordre de chargement
│   ├── Bindings.xml             raccourci clavier
│   ├── LICENSE.md, NOTICE.md    GPL v3 et mentions des tiers (obligatoires)
│   ├── Core/                    cœur AzerothVeil
│   │   ├── Init.lua             namespace _G.AzerothVeil, L[], SafeCall, IsAddOnLoaded
│   │   ├── Callbacks.lua        bus de messages entre modules
│   │   ├── Events.lua           frame d'événements centrale (handlers par propriétaire)
│   │   ├── Database.lua         AzerothVeilDB : schéma, valeurs par défaut, migrations
│   │   ├── ModuleManager.lua    enregistrement, cycle de vie, dépendances, réglages
│   │   └── Bootstrap.lua        chargé en dernier : réglages → modules, démarrage au login
│   ├── Locales/                 enUS (clés), frFR (core, modules, options et textes visibles du moteur)
│   ├── Engine/                  moteur cartographique hérité de PerfectMap 1.5.6 (noms de fichiers d'origine)
│   │   └── Data/                données (générées hors jeu par les outils de PerfectMap/OpenMap)
│   ├── Modules/                 modules fonctionnels (un fichier ou dossier par module)
│   ├── UI/                      Controls.lua (contrôles générés depuis les déclarations), Options.lua (fenêtre)
│   ├── Media/                   ressources graphiques (PerfectMap + futures)
│   └── Tiles/                   pyramide de tuiles de la carte (60 Mo)
├── scripts/                     check.sh, deploy.sh, deploy.conf.example (deploy.local.conf ignoré)
├── tests/                       tests unitaires Lua 5.1 du cœur (stubs de l'API WoW)
├── docs/                        audit, architecture, roadmap, développement
├── .reference/                  (ignoré) sources originales intactes : PerfectMap, OpenMap, FlareUI, DungeonJournal
├── .tools/                      (ignoré) Lua 5.1 local
├── build/                       (ignoré) copie préparée avant déploiement
└── CLAUDE.local.md, .claude/    (ignorés) configuration de l'agent IA
```

Les **intégrations tierces** vont dans `addon/Integrations/` (première : `DungeonJournal.lua`). Aujourd'hui celles de PerfectMap restent
dans `Engine/` (Quests.lua, Tint.lua, AddonPins.lua).

### Ordre de chargement (`AzerothVeil.toc`)

1. `Core/Init.lua` → `Locales/*` → `Core/Callbacks`, `Events`, `Database`, `ModuleManager`
2. `Engine/*` dans l'ordre exact de PerfectMap
3. `Modules/*` (chaque module s'enregistre ; rien ne s'exécute)
4. `UI/Controls.lua`, `UI/Options.lua`
5. `Core/Bootstrap.lua`

### Séquence de démarrage

```
chargement des fichiers ─ les modules s'enregistrent (aucun code fonctionnel)
ADDON_LOADED (Engine/Core.lua)
   └ Database.Load()  → migrations, AzerothVeilDB.engine = réglages PerfectMap (+ défauts)
   └ Fire SETTINGS_LOADED → Modules:LoadSettings()  (défauts des modules, état enabled)
PLAYER_LOGIN (Core/Bootstrap.lua)
   └ avertissement si PerfectMap est aussi chargé
   └ Modules:Start() → Evaluate() : Initialize + Enable des modules actifs
   └ Options.Register() → page dans Options > AddOns (bouton qui ouvre la fenêtre AzerothVeil)
```

## 2. Le cœur

- **Namespace** : un seul global, `_G.AzerothVeil` (le namespace `...` partagé par tous les fichiers, que
  le moteur appelle `FM`). Autres globaux strictement nécessaires : `AzerothVeilDB`, `/av`, raccourci
  clavier, frames nommées requises par les override bindings. `scripts/check.sh` refuse tout autre global.
- **Callbacks** (`ns.Callbacks`) : `Register(message, owner, fn)`, `Fire`, `UnregisterAll(owner)`. Les
  modules communiquent par messages, jamais en s'appelant directement.
- **Events** (`ns.Events`) : une frame centrale ; un événement du jeu est désenregistré dès que plus
  personne ne l'écoute (un module désactivé ne coûte rien).
- **Database** (`ns.Database`) : voir §4.

## 3. ModuleManager

### Déclaration (déclarative)

```lua
local M = ns.Modules:Register({
  name = "dungeons", title = L["Dungeons"], description = L["..."], order = 20,
  defaultEnabled = true,
  dependencies = { "markers" },                 -- modules AzerothVeil requis
  requiresAddOns = { },                         -- addons requis
  conflictsWithAddOns = { "ForeverDungeonJournal" }, -- si chargé, il prend le relais
  reloadOnDisable = false,                      -- true si hooks irréversibles
  settings = {
    { type = "header", label = L["Display"] },
    { key = "entrances", type = "toggle", default = true, label = ..., tooltip = ... },
    { key = "floors", type = "toggle", default = true, parent = "entrances" },
    { key = "scale", type = "range", default = 1, min = 0.5, max = 2, step = 0.05 },
    { key = "lastFloor", type = "hidden", default = 1 },
  },
})
function M:Initialize() end           -- une fois, juste avant le premier Enable
function M:Enable() end               -- démarre (événements, frames, hooks)
function M:Disable() end              -- s'arrête, libère
function M:Refresh(key, value) end    -- un réglage a changé pendant qu'il tourne
```

Un en-tête déclaré `all = true` reçoit les boutons « Tout afficher / Tout masquer » sur les deux écrans
(`MM:SectionToggles`, `MM:SetSection`) : ils agissent sur les options de sa section, sauf celles déclarées `noAll = true`.

Aides disponibles dans un module : `self.db` (ses réglages), `self:Get/Set(key)`,
`self:IsOptionActive(key)`, `self:RegisterEvent(event, fn)`, `self:RegisterMessage(msg, fn)`,
`self:SendMessage(msg, ...)`, `self:After(s, fn)`, `self:NewTicker(s, fn)`, `self:Print(msg)`.

### Cycle de vie et règles

| État | Signification |
|---|---|
| `enabled` (sauvegardé) | ce que l'utilisateur a demandé |
| `active` (exécution) | enabled **et** addons requis présents **et** dépendances actives **et** aucun addon en conflit **et** joueur connecté |
| `unavailable` | demandé mais bloqué (raison affichée dans les options et `/av modules`) |

- **Un module désactivé n'exécute rien.** `Initialize` n'est jamais appelé pour un module qui n'a jamais
  tourné. Après `Disable`, le manager libère de lui-même événements, messages et timers pris via les aides
  du module (même si `Disable` les oublie).
- **Ses réglages sont conservés** et reviennent à la réactivation. `IsOptionActive` renvoie toujours
  `false` quand le module n'est pas actif, quelle que soit la valeur enregistrée (et `false` si l'option
  parente est éteinte).
- **Dépendances** : ordre topologique ; arrêt des dépendants avant leurs dépendances, démarrage dans
  l'ordre inverse ; les cycles sont refusés ; un module dont le `Enable` échoue est nettoyé et marqué
  indisponible jusqu'à sa prochaine désactivation/réactivation.

### Désactivation logique ≠ déchargement

WoW charge **tous** les fichiers listés dans le `.toc` au démarrage et ne peut pas en décharger un.
Désactiver un module **arrête son exécution** mais son code reste en mémoire (coût mémoire négligeable,
coût CPU nul). Conséquences :

- Le code d'un module ne doit rien faire **au chargement du fichier** à part s'enregistrer
  (pas de `CreateFrame` avec scripts, pas d'événement, pas de hook au niveau fichier).
- Les `hooksecurefunc` / `HookScript` **ne peuvent pas être retirés** : le hook doit tester
  `self:IsActive()` en premier, et le module déclarer `reloadOnDisable = true` ; les options affichent
  alors « Recharger l'interface ».
- Les préfixes de messages d'addon enregistrés le restent jusqu'au prochain /reload (sans effet).
- **/reload nécessaire** : nouveaux fichiers ou modification du `.toc` (redémarrage complet du jeu),
  désactivation d'un module `reloadOnDisable`. Un vrai déchargement nécessiterait des addons
  « Load on Demand » séparés : non retenu à ce stade (complexité, un dossier par module).

### Modules du moteur (migration progressive)

Le moteur PerfectMap n'est pas réécrit. Un sous-système devient piloté par un module en lui ajoutant
des points d'entrée `Start/Stop` et en faisant de ses `Layout/Tick` des retours immédiats quand il est
arrêté. Les options correspondantes quittent `FM.db` pour les réglages du module (migration de schéma).

| Module | Moteur piloté | Mécanisme |
|---|---|---|
| `social` (Amis & guilde) | `Engine/Friends.lua` | `Friends.Start(cfg)/Stop()` ; lit les réglages du module en direct (`F.cfg`) |
| `transports` | `Engine/Vessels.lua`, `Routes.lua`, `Pins.lua` | `Vessels.Start/Stop/SetTracking/SetSharing`, `Routes.SetEnabled`, `Pins.OnTravelClick` ; le module **écrit** les interrupteurs que le moteur lit (`FM.db.pins.flight/boat/zeppelin/tram/airship`, `enemyFlight`, `routes`, `vessels`, `vesselSync`, `enemyHarbors`) : ce sont des valeurs effectives, remises à `false` à chaque chargement (`Engine/Core.lua`) et tant que le module est désactivé ; ses vrais réglages sont dans `AzerothVeilDB.modules.transports` |

| `quests` | `Engine/Quests.lua`, `QuestLog.lua`, `Takeover.lua`, `Core.lua` (touche L) | interrupteurs effectifs (`questPOI`, `questOffers`, `questAreas`, `pins.questie`, `questLog`, `replaceQuestLog`) ; `QuestLog.Apply` (journal présent ou non, bouton de repli) ; module éteint = comportement de WoW : L et le suivi d'objectifs ouvrent le journal de Blizzard (`Takeover.KeepNative`). `FM.db.questPanel` reste l'état replié/déplié du journal |
| `map` (Carte) | `Engine/Map.lua`, `Pins.lua`, `AddonPins.lua`, `Caves.lua`, `Terrain.lua`, `Core.lua` (touche M), `Takeover.lua`, `Fog.lua`, `UI/MinimapButton.lua` | interrupteurs effectifs (`replaceM`, `reopen`, `rememberZoom`, `fadeMoving`, `hoverHighlight`, `joinIcons`, `addonPins`, `iconScale`, `underground`, `minimapTerrain`, `zoneFishing`), valeurs « éteintes » dans `FM.MAP_OFF` (appliquées à chaque chargement) ; `MinimapButton.SetShown`, `Fog.SetEnabled/Explored`, `Labels` (noms des lieux de près, `terrainNames`, enfant de `minimapTerrain`), `Pins.RefreshExplored` (`MAP_EXPLORATION_UPDATED` écouté seulement si le brouillard est actif ou les PNJ inexplorés masqués), `npcUnexplored`. Ancien onglet « Carte » du moteur. Module éteint = carte nue : M ouvre la carte de Blizzard, ni brouillard, ni extras, ni bouton de minicarte (la carte reste ouverte par `/av` et le compartiment d'addons) |
| `markers` (Marqueurs de carte) | `Engine/Pins.lua` (catégorie `marker`, `P.SetPins`, `P.FollowAt`, crochets `P.OnMarkerClick` / `P.OnCtrlClick`), `Engine/Spot.lua` (`SP.markerItems`), `UI/Markers.lua` | données dans `AzerothVeilDB.markers` (`Database.CheckMarkers` : liste, catégories libres, catégorie « Partagés avec moi ») ; Ctrl+clic pose un marqueur suivi et ouvre sa fiche ; partage compatible OpenMap (préfixe `OpenMap`, messages `P1`, file espacée de 0,5 s, code `OMPINS1:`) ; réception écoutée seulement si l'option est cochée, confirmation par notre propre fenêtre (pas `StaticPopupDialogs`). Éteint : hooks retirés, rien sur la carte, rien d'envoyé ni d'écouté, marqueurs conservés |
| `icons` (Icônes) | `Engine/Pins.lua` (catégories des groupes `FM.ICON_GROUPS` : `places`, `townsfolk`, `professions`) | réglages générés depuis `Pins.CATS` (mêmes clés que `FM.db.pins` : `capital`, `innkeeper`… `prof_*`), interrupteurs effectifs remis à `false` à chaque chargement ; construction seulement carte ouverte (`Pins.Ensure`, sinon à l'ouverture). Remplace les onglets Lieux / PNJ des villes / Métiers du moteur. La synchro avec le menu de PNJ de Questie passe par `MM:SetSetting` (icons, ou transports pour `flight`). « Toutes les classes » (enfant de Maîtres de classe) → `FM.db.allClassTrainers`, `Pins.RebuildKind`. « Mes métiers » : un maître s'affiche s'il est coché **ou** si vous avez le métier (`C_SkillInfo.GetSkillLineInfoByID`, sinon `GetProfessions` ; pas de `GetSkillLineInfo` sur Forever), relu à l'activation, au changement d'option et à chaque ouverture de la carte (`Pins.BeforeOpen`) : aucun événement écouté |
| `dungeons` | `Engine/Dungeon.lua`, `Pins.lua`, `QuestLog.lua` | interrupteurs effectifs (`pins.dungeon/raid`, `dungeonMaps`, `dungeonBosses`, `dungeonLevels`, `dungeonWays`) ; `Pins.OnDungeonClick` (aiguillage du clic), `Dungeon.ReturnView` (retour au monde), `Dungeon.Choose(..., onPick)`, `Dungeon.CollectBosses/FocusBoss/Current`, messages `DUNGEON_MAP_SHOWN/CLOSED`, `QuestLog.Suspend` |

**Donjons — détails** (audit : `docs/dungeons-audit.md`).
- Clic sur une entrée : sans DungeonJournal, la carte intérieure du moteur (sélecteur si plusieurs
  donjons/ailes) ; avec DungeonJournal et l'option, **sa** page du donjon (`Integrations/DungeonJournal.lua` :
  fonctions publiques sous `pcall`, correspondance par numéro d'instance + nom d'aile de nos données,
  repli sur notre carte en cas d'échec).
- Retour : la vue du monde (centre, zoom) mémorisée à l'ouverture depuis une entrée est restaurée par le
  bouton Monde et le clic droit ; un second donjon ouvert depuis le premier garde le point de départ.
- Panneau latéral (`UI/DungeonPanel.lua`) : pendant qu'une carte de donjon est affichée (ouverte depuis
  une entrée ou automatiquement à l'intérieur), le journal de quêtes est suspendu (préférence intacte) et
  remplacé par les onglets Quêtes / Boss ; rétabli à la fermeture. Jamais quand DungeonJournal est aux
  commandes (pas d'interface concurrente).

**Capitales et noms de près.** Les villes à ciel ouvert s'effacent sous le terrain de la minimap
(`Cities.SetTerrain`, appelé par `Terrain.lua` pendant son fondu) ; Forgefer et Fossoyeuse gardent leur carte et
reçoivent leur minimap intérieure (`FM.CITY_MINIMAP`, OpenMap). Les noms des lieux (`Engine/Labels.lua`,
`Data/AreaLabels.lua` tiré de `Explore.lua` d'OpenMap, noms du client) sont posés sur le terrain, calque au niveau +5,
alpha = fondu du terrain ; avec le brouillard, seulement les morceaux listés explorés.

**PNJ des zones inexplorées** (option `unexploredNPCs` du module Carte → `FM.db.npcUnexplored`, vrai si le module
est éteint). Décochée, `Pins.lua` ne construit un PNJ que si le jeu donne une zone explorée à son emplacement ou
juste autour (`C_MapExplorationInfo.GetExploredAreaIDsAtPosition`, principe de « Only places you've found »
d'OpenMap, réécrit ici) ; dans une capitale : visitée, ou zone explorée sous son centre ; hors des zones à
exploration (`FM.FOG_ZONES`) : toujours affiché. Résultat mis en cache par emplacement (trouvé reste trouvé) ;
`MAP_EXPLORATION_UPDATED`, écouté seulement si l'option masque ou si le brouillard est actif, ne fait que vider
les « non trouvés » et reconstruire les PNJ (tout de suite carte ouverte, sinon à l'ouverture).

**Brouillard de guerre — détails** (`Engine/Fog.lua`, option « Brouillard de guerre » du module Carte, éteinte
par défaut : toute la carte). Les tuiles pré-rendues montrent toutes les zones explorées ; avec le brouillard, une
zone pas entièrement explorée est dessinée **comme la carte de Blizzard la dessine** : son art de base
(`C_Map.GetMapArtLayerTextures`, terres inexplorées vierges), puis par-dessus, dans l'ordre du jeu, seulement les
morceaux explorés (`C_MapExplorationInfo.GetExploredMapTextures`, avec leurs bords doux), le tout à travers le
territoire de la zone (`Media/FogTerritory/<uiMapID>`, `MapTerritory` d'OpenMap) pour ne pas déborder sur les
voisines. Une zone entièrement explorée est laissée aux tuiles (nombre total de morceaux : `Engine/Data/Fog.lua`,
copie du `Reveal.lua` d'OpenMap). 43 zones (celles d'OpenMap). Une frame par zone (≈ 12 tuiles de base + les
morceaux explorés), construite la première fois qu'elle est visible, refaite seulement quand le jeu liste plus de
morceaux explorés ; calque au niveau des villes (+2), au-dessus du terrain de la minimap, sous les icônes ; couvert
par l'art du monde au zoom le plus éloigné. Éteint : frames cachées, fichiers libérés. (Première version : découpe
« Hide unexplored areas » d'OpenMap, abandonnée : bords en blocs carrés sur ce client.)

**Transports — détails.**
- Un point par trajet, comme OpenMap (PerfectMap fusionnait les quais proches en une icône) : chaque
  icône connaît la destination de son trajet (`pin.travel`) ; les icônes de transport ne sont jamais
  regroupées par « Sum identical icons » (`noJoin`). Les tracés se terminent sur le point de leur trajet.
- Clic (repris d'OpenMap `DockClick` → `GlideToWorld(pin.to, 6)`) : sans menu ni infobulle, la carte va
  directement à l'autre extrémité (`Map.SetView`), au zoom 6 d'OpenMap ou plus près si on l'était déjà.
  Retour : cliquer sur le quai d'arrivée (trajet retour) ou navigation habituelle.
- Suivi des bateaux conservé tel quel (`CheckTriggers`, 0,8 s, fréquence inchangée) mais son ticker
  n'existe que si le module est actif **et** l'option « Suivi » activée ; le réseau (`PerfectMapSail`)
  n'écoute et n'envoie que si « Partager » (enfant de « Suivi ») est actif.

## 4. Configuration et persistance

`AzerothVeilDB` (SavedVariables, compte) :

```lua
{ schema = 2,
  engine  = { ... },    -- réglages de PerfectMap, mêmes clés (FM.db)
  modules = { social = { enabled = true, settings = { show = true, share = false, asked = false } } },
  core    = { optionsModule = "social" },
  markers = { list = { ... }, nextId, cats = { { id, name, shown } }, nextCat, shared, current } }
```

- Valeurs par défaut fusionnées à chaque chargement ; une valeur de mauvais type est remise par défaut.
- **Migrations** : `Database.migrations[n]` amène un schéma n-1 à n, exécutées une fois dans l'ordre ;
  un fichier venant d'une version plus récente n'est jamais rétrogradé. Migration 1 : options amis/guilde
  du moteur → module `social`. Migration 2 : options de transport de PerfectMap → module `transports` ; migration 3 : maîtres de vol (et ceux de l'autre faction) → module `transports` ; migration 4 : entrées, cartes et boss des donjons → module `dungeons`. Migration 5 : quêtes sur la carte, icônes Questie et remplacement du journal → module `quests`. Migration 6 : options de l'onglet Carte du moteur et `core.minimap.hide` → module `map`. Migration 7 : capitales, PNJ des villes et maîtres de métiers (`engine.pins`) → module `icons`.
- Les anciennes migrations internes de PerfectMap (dans `Engine/Core.lua`) sont conservées telles quelles
  sur `engine`.

### Interface de configuration

Deux écrans, **les mêmes réglages**, lus et écrits uniquement via le ModuleManager :

1. **La fenêtre d'options d'AzerothVeil — l'écran principal** (`Engine/Menu.lua`, issue du menu ⚙ de
   PerfectMap) : fenêtre indépendante de la carte (`AzerothVeilOptions`, enfant d'`UIParent`, cadre
   classique de Blizzard), ouverte par la ⚙ de la carte, `/av config`, le clic droit du bouton de
   minicarte ou le compartiment d'addons. Déplaçable par sa barre de titre, gardée à l'écran,
   **redimensionnable** par la poignée du coin (mise à l'échelle de toute la fenêtre, 0,75 à 1,6),
   position et échelle mémorisées (`FM.db.menuWindow`), fermée par sa croix ou Échap (`ns.TakeEscape` :
   jamais `UISpecialFrames`, clavier jamais pris en combat). Elle reste ouverte si la carte se ferme.
   Onglet du module Carte en premier, onglets du moteur (Lieux, PNJ, Métiers), puis **un onglet par module, généré** depuis
   sa déclaration, à la manière de FlareUI : un **en-tête** encadré (icône, titre, case d'activation juste
   à côté, description, état), puis **une boîte par section** (chaque `header` de la déclaration ; avant le
   premier : « Réglages ») avec ses options sur deux colonnes, sous-options en retrait. Grisées et non
   cliquables quand le module ou l'option parente est off.
2. **Options > AddOns > AzerothVeil** (page du jeu, `UI/Options.lua` + `UI/Controls.lua`) : liste des
   modules, en-tête générique (titre et « Activer le module » sur une ligne), réglages générés ;
   modifiable là aussi.

Bouton de minicarte (`UI/MinimapButton.lua`) : natif (bordure et fond de la minicarte du jeu), sans
bibliothèque, déplaçable autour de la minicarte (angle dans `AzerothVeilDB.core.minimap`), affiché
selon l'option « Bouton de la minicarte » du module Carte (masqué quand il est éteint) ; nommé et enfant de `Minimap`, il est donc rangé par les collecteurs de boutons
(tiroir de FlareUI). Le même double clic est offert dans le compartiment d'addons du jeu
(`AddonCompartmentFunc`).

Synchronisation : `SetSetting` émet `MODULE_SETTING_CHANGED`, `SetEnabled` émet `MODULE_ENABLED_CHANGED`
(même si l'état effectif ne change pas), l'activation/désactivation effective `MODULE_STATE_CHANGED` ;
les écrans (et le bouton des tracés de la carte) écoutent ces messages et se rafraîchissent.
Déclaration : `icon` (module et option) accepte un chemin, un `"atlas:..."` ou une fonction (art de la
faction du joueur, lu au moment du dessin). Composants natifs : `InsetFrameTemplate`,
`UICheckButtonTemplate`, `MinimalSliderWithSteppersTemplate`, `UIPanelButtonTemplate`, polices `GameFont*`.

## 5. Contrat des intégrations tierces

- Toujours **facultatives** : `requiresAddOns` pour un module qui n'a de sens qu'avec l'addon,
  `conflictsWithAddOns` quand l'autre addon doit prendre la main (ex. quêtes et boss de donjon quand
  DungeonJournal est actif).
- Ne jamais modifier les fichiers ni les SavedVariables d'un autre addon ; lecture seule de leur API
  publique, protégée par `pcall`, et **vérifiée dans leur code** avant usage.
- Testées au `PLAYER_LOGIN` (tous les addons sont chargés).

## 6. Traductions

- Langue détectée par `GetLocale()` ; `L["Texte anglais"]` renvoie la traduction ou, à défaut, la clé
  anglaise (repli). `Locales/frFR.lua` ne s'exécute que sur un client français.
- **Obligatoire** : tout texte visible (titres, options, infobulles, messages) passe par `L[]`, y compris
  dans le moteur. `scripts/check_locales.py` (étape 6 de `check.sh`) échoue si une clé n'a pas sa
  traduction française.
- Noms propres : ceux que le jeu fournit (zones, villes, PNJ, quêtes) viennent de ses API, déjà
  localisés (ex. `C_Map.GetMapInfo(id).name` pour le tram) ; les autres suivent les noms du client français.
- Ajouter une langue : créer `Locales/xxXX.lua` sur le modèle de frFR, l'ajouter au `.toc` et à
  `TRANSLATIONS` dans `scripts/check_locales.py`.
- Les messages de diagnostic (`/av stats`, `/av sailings`, `/av addons`) restent en anglais.

## 7. Compromis et limitations

- Couplage fort de `Map.lua` conservé (performances, stabilité) : les modules s'y branchent par des
  points d'entrée dédiés plutôt que par un système de calques générique — à introduire quand un 2ᵉ ou
  3ᵉ module de rendu le justifiera.
- Le code mort du style moderne (`Style.lua`, `FM.AskStyle`) est laissé en place (modification minimale).
- Les tuiles (60 Mo) et médias sont versionnés dans Git (dépôt local) pour un build reproductible.
- Tests unitaires limités au cœur (le moteur dépend de l'API graphique du client).
