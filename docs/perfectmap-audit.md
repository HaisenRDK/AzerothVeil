# Audit technique de PerfectMap 1.5.6

Audit réalisé le 22/11/2026 sur la copie installée dans
`E:\Blizzard\World of Warcraft\_forever_\Interface\AddOns\PerfectMap`.
Une copie intacte est conservée localement dans `.reference/PerfectMap/` (ignorée par Git), avec
OpenMap, FlareUI et ForeverDungeonJournal pour comparaison. Le commit `00f834f` contient aussi l'import
non modifié, ce qui permet de lire toutes nos modifications avec `git diff 00f834f -- addon/`.

## 1. Identité, version, licence

| Élément | Valeur |
|---|---|
| Version | 1.5.6 (`## Version` du .toc) |
| Interface | 16001 (client WoW Forever) |
| Auteur | sokenn_ (CurseForge) — le .toc n'a pas de champ `Author` |
| Licence | **GNU GPL v3** (`LICENSE.md`, `## X-License`) |
| SavedVariables | `PerfectMapDB` (compte) |
| OptionalDeps | Questie, ForeverQuestTint |
| Taille | 588 fichiers, 90 Mo (Tiles 60 Mo, Media 29 Mo, Lua+Data 0,5 Mo), ~17 000 lignes de Lua |

### Restrictions de licence et de provenance (`NOTICE.md`)

PerfectMap est sous GPL v3 *parce qu'il embarque des données dérivées de Questie*. Conséquences pour
AzerothVeil :

- **AzerothVeil est une œuvre dérivée et reste sous GPL v3.** Toute diffusion future (même à un ami)
  doit fournir le code source, la licence et conserver les mentions. Le dépôt contient déjà la GPL v3
  (`LICENSE` à la racine, `addon/LICENSE.md` déployé).
- Les mentions de `NOTICE.md` sont conservées **intégralement** ; un en-tête AzerothVeil y est ajouté.
- Composants tiers embarqués :
  - **OpenMap** (MIT, © 2026 OpenMap contributors) : tuiles (`Tiles/`), grottes, minimap, lieux,
    cartes de donjon, masques de villes, protocole « Friends ». Compatible GPL ; la notice MIT doit rester.
  - **Questie / QuestieDB** (GPL v3) : PNJ (`Townsfolk`), maîtres de vol, icônes `Media/Questie/`.
  - **ForeverQuestTint** (GPL v3) : `VanillaQuests.lua`, comportement de `Tint.lua`.
  - **MapUtils** par D4KiR (GPL v3) : boss, niveaux de zone, trajets des bateaux, icônes.
  - **Santiago Reyes** (cartes dessinées des donjons Forever) et **ForeverDungeonJournal / Exehn**
    (données des boss, cartes UBRS/Alcaz) : utilisés **avec la permission de leurs auteurs, accordée à
    PerfectMap**. ⚠️ Pour un usage personnel local, aucun problème. **Avant toute redistribution
    d'AzerothVeil, il faudra vérifier que ces permissions s'étendent à un dérivé** (ou retirer ces fichiers).
  - Art de la carte : celui de Blizzard, issu du client.

## 2. Fichier .toc et ordre de chargement

```
Core.lua  Style.lua  Tint.lua
Data\Tiles  Places  Townsfolk  FlightMasters  Levels  Vessels  Minimap  DungeonMaps  DungeonBosses
     DungeonSpots  DungeonJournal  DungeonDrawn  DungeonEntrances  VanillaQuests  Reveal  Caves  CaveMinimap
Geo.lua  Terrain.lua  Cities.lua  Isles.lua  Caves.lua  Routes.lua  Vessels.lua  Friends.lua
Map.lua  Pins.lua  AddonPins.lua  Spot.lua  Quests.lua  QuestLog.lua  Takeover.lua  Dungeon.lua  Menu.lua
```
`Bindings.xml` est chargé automatiquement par le client (raccourci `PERFECTMAP_TOGGLE`).

Contraintes d'ordre : `Core.lua` crée le namespace `FM` (le 2ᵉ argument de `...`) et `FM.defaults` ;
`Style.lua` doit précéder tout ce qui dessine ; les `Data\*` remplissent des tables `FM.*` lues par les
fichiers suivants ; `Map.lua` référence `FM.Terrain`, `FM.Cities`, … **au moment de l'appel** (pas au
chargement), mais `Pins.lua`, `Quests.lua`, `Dungeon.lua` y accrochent leurs fonctions.

## 3. Organisation et dépendances

| Fichier | Rôle | Lignes |
|---|---|---|
| `Core.lua` | defaults, migration de `PerfectMapDB`, touches M/L (override bindings), slash `/pmap`, choix du style | 252 |
| `Style.lua` | les deux habillages (moderne / classique), boutons, sliders, polices, tooltips | 442 |
| `Geo.lua` | conversions mapID ↔ unités monde (1002×668 = art d'Azeroth), terres « à part » (île de Zephras) | 182 |
| `Map.lua` | **moteur** : fenêtre, tuiles, vue, zoom, drag, survol des zones, joueur/groupe/cadavre, outils | 1661 |
| `Terrain.lua` | tuiles de la minimap du client en zoom très proche | 197 |
| `Cities.lua`, `Isles.lua`, `Caves.lua` | cartes des capitales, de l'île de Zephras, des grottes (art du client) | 152–215 |
| `Pins.lua` | marqueurs (catégories `FM.Pins.CATS`), regroupement des icônes identiques, survol, clic | 1486 |
| `AddonPins.lua` | recopie les pins des autres addons (HereBeDragons-Pins, fournisseurs de `WorldMapFrame`) | 318 |
| `Quests.lua` | quêtes à la Blizzard (`POIButtonTemplate`, zones, « ! »), miroir des icônes Questie | 1205 |
| `QuestLog.lua` | journal de quêtes ancré à droite de la carte | 1095 |
| `Dungeon.lua` | carte intérieure des donjons/raids/BG, étages, boss, entrées | 1435 |
| `Routes.lua`, `Vessels.lua` | lignes bateaux/zeppelins, position en direct, partage des passages (`PerfectMapSail`) | 376 / 850 |
| `Friends.lua` | amis et guilde sur la carte, partage de position (protocole OpenMap `OpenMapLoc`) | 473 |
| `Spot.lua` | clic droit : pin utilisateur, copie des coordonnées | 131 |
| `Takeover.lua` | remplace la carte et le journal de Blizzard | 232 |
| `Menu.lua` | panneau d'options interne à la carte (onglets) | 413 |
| `Tint.lua` | marques de ForeverQuestTint sur les quêtes | 193 |

Dépendances : toutes passent par le namespace `FM` (pas de `require`). `Map.lua` est le **chef
d'orchestre** : `Map.Refresh()` appelle directement `FM.Terrain/Caves/Cities/Isles/Routes/Vessels/Friends/
Pins/AddonPins/Quests.Layout(...)`, et son `OnUpdate` appelle leurs `Tick`. Le couplage est donc
**fort et explicite** — simple et rapide, mais chaque sous-système suppose que les autres existent.

## 4. Moteur de rendu seamless (`Map.lua`)

- **Unités monde** : 1 unité = 1 pixel de l'art d'Azeroth (1002 × 668). Toute la carte (continents,
  zones, villes) est exprimée dans ce repère (`Geo.lua` convertit depuis les rectangles des mapID).
- **Pyramide de tuiles** pré-calculée (`Tiles/<L>/<i>_<j>.blp`, générée hors jeu par `tools/build.js` à
  partir de l'art d'OpenMap) : niveaux L = 1, 2, 4, 8, 16 pixels/unité, tuiles de 512 px au pas de 510
  (2 px de recouvrement pour le filtrage). Les niveaux > 4 omettent la haute mer.
- **Sélection du niveau** (`PickLevel`) : le premier niveau ≥ 85 % de la densité écran.
  On dessine seulement les tuiles visibles de ce niveau, **par-dessus le niveau 1** (« underlay ») pour
  qu'aucune zone ne soit jamais vide pendant le chargement d'un fichier.
- **Cache et pool** (`Want`/`UpdateTiles`) : une tuile hors écran garde sa texture 25 s (max 64), puis
  retourne au pool. Pas de masque ni de fondu entre tuiles (une texture par cellule, bord à bord).
- **Zoom arrière maximal** : l'art du monde de Blizzard (`C_Map.GetMapArtLayerTextures(947)`) se fond
  dans la carte assemblée sur le premier cran de molette.
- **Zoom très proche** (jusqu'à 64 px/unité) : `Terrain.lua` pose les tuiles de la **minimap** du client.
- **Calques** : frames empilées par `FrameLevel` (tuiles → terrain → villes → îles/grottes → monde →
  surbrillance → routes → zones de quêtes → chemins Questie → pins → pins d'addons → bateaux → amis →
  quêtes → topLayer → joueur → donjon).

## 5. Zoom, déplacements, marqueurs, interactions

- **Molette** : facteur 1,35 par cran, animé en espace logarithmique (`Map.AnimateZoom`, constante 16/s),
  centré sur le curseur (`ZoomAt`). **Drag** : clic gauche + déplacement > 3 px. `Clamp()` borne la vue.
- **Ouverture** : centrée sur le joueur (`reopen = "player"`), à 220 unités de large, ou au dernier zoom
  (`rememberZoom`) ; 3 crans plus près en capitale ou sous terre.
- **Marqueurs** (`Pins.lua`) : catégories déclarées dans `FM.Pins.CATS` (vol, donjons, raids, capitales,
  bateaux, PNJ de ville, métiers…), visibilité par zoom, **regroupement** des icônes identiques qui se
  chevauchent (avec compteur), animation de glissement, survol avec tooltip, clic gauche (donjon → carte
  intérieure), clic droit (waypoint). Les icônes sont des atlas du client ou des `.tga` de `Media/`.
- **Clic droit sur zone vide** : menu `Spot.lua` (pin utilisateur `C_Map.SetUserWaypoint`, copie des coords).
- **Survol** : zone sous le curseur éclairée avec l'art de surbrillance de Blizzard
  (`C_Map.GetMapHighlightInfoAtPosition`), nom + niveaux + sous-zone (≤ 10 fois/s).
- **Échap** : un « key catcher » dédié, **pas** `UISpecialFrames` (qui contamine la gestion d'Échap).

## 6. Frames natives de Blizzard modifiées

PerfectMap **ne modifie pas** `WorldMapFrame` : il crée sa propre fenêtre (`PerfectMapFrame`,
`PortraitFrameTemplate` + `InsetFrameTemplate` en style classique) et **détourne** les ouvertures :

| Mécanisme | Fichier | Détail |
|---|---|---|
| Override bindings | Core.lua | les touches de `TOGGLEWORLDMAP` / `TOGGLEQUESTLOG` cliquent nos boutons (hors combat) |
| `WorldMapFrame:HookScript("OnShow")` | Takeover.lua | carte Blizzard rendue invisible (alpha 0) puis `HideUIPanel` à la frame suivante ; la nôtre s'ouvre |
| `hooksecurefunc(WorldMapFrame, "SetMapID" / "HandleUserAction*")` | Takeover.lua | reproduit l'action sur notre carte |
| `EventRegistry "MapCanvas.PingWaypointLocation"` | Takeover.lua | lien de pin dans le chat |
| `QuestLogFrame` & co `HookScript("OnShow")`, `hooksecurefunc("SelectQuestLogEntry")` | Takeover.lua | journal remplacé |
| Boutons d'en-tête du suivi de quêtes désactivés **en combat** | Takeover.lua | évite l'ouverture protégée de la carte native |
| `hooksecurefunc("QuestMapFrame_OpenToQuestDetails")` | Quests.lua | « afficher la quête » ouvre notre journal |
| Hooks sur les fournisseurs de pins de `WorldMapFrame` | AddonPins.lua | recopie des pins d'autres addons |

Précautions anti-taint notables : jamais `StaticPopup` (dialogue maison), jamais `UISpecialFrames`,
attributs `UIPanelLayout-*` modifiés uniquement hors combat. **Les `hooksecurefunc` sont irréversibles
sans /reload** : c'est la principale contrainte pour rendre ces fonctions désactivables à chaud.

## 7. Événements et traitements continus

| Fichier | Événements | Traitement continu |
|---|---|---|
| Core | ADDON_LOADED, PLAYER_LOGIN, UPDATE_BINDINGS, PLAYER_REGEN_ENABLED | — |
| Map | PLAYER_DEAD/ALIVE/UNGHOST, PLAYER_ENTERING_WORLD, CORPSE_POSITION_UPDATE | `OnUpdate` de la vue **uniquement carte ouverte** ; ne recalcule que si quelque chose a bougé (drag, zoom, joueur, curseur) ; `OnUpdate` de la poignée de redimensionnement (retour immédiat hors redimensionnement) |
| Pins | USER_WAYPOINT_UPDATED, TAXIMAP_OPENED, MODIFIER_STATE_CHANGED | — |
| Quests | QUEST_LOG_UPDATE, QUEST_POI_UPDATE, SUPER_TRACKING_CHANGED, QUEST_ACCEPTED… | — |
| Dungeon | zone/instance + AREA_POIS_UPDATED | `Tick` dans l'OnUpdate de la carte (carte ouverte) |
| Isles | ZONE_CHANGED_NEW_AREA, PLAYER_ENTERING_WORLD | — |
| Takeover | PLAYER_LOGIN, ADDON_LOADED, PLAYER_REGEN_DISABLED/ENABLED | — |
| Friends | CHAT_MSG_ADDON, BN_CHAT_MSG_ADDON, rosters guilde/amis, GROUP_ROSTER_UPDATE | **ticker 2 s permanent** (même carte fermée) — *désormais piloté par le module « Amis & guilde »* |
| Vessels | CHAT_MSG_ADDON, BN_CHAT_MSG_ADDON | **ticker 0,8 s permanent** (`CheckTriggers` : repère quand le joueur est sur un bateau) ; file d'envoi 0,2 s |

Conclusion : le moteur est sobre carte fermée, à deux exceptions près (Friends, Vessels) qui sont les
premières candidates à une désactivation par module.

## 8. Intégrations existantes

- **DungeonJournal** : intégration **statique uniquement**. `Data/DungeonJournal.lua` est généré hors jeu
  (`tools/journalpins.js`, outil non distribué) à partir des données de ForeverDungeonJournal (boss,
  niveaux, portraits, positions) ; deux cartes (UBRS, Alcaz 2) sont reprises. **Aucun appel à l'addon
  DungeonJournal en jeu.** ForeverDungeonJournal publie `_G.ForeverDungeonJournal_NS` : piste pour une
  intégration dynamique, **API à vérifier** avant usage.
- **Questie** : optionnel. Miroir de ses icônes via le registre HereBeDragons-Pins et hooks sur ses
  modules (`QuestieLoader:ImportModule`) ; bouton d'options Questie dans l'en-tête.
- **ForeverQuestTint** : `Tint.lua` lit sa configuration et reproduit ses marques.
- **OpenMap** : protocole `OpenMapLoc` partagé (amis) ; OpenMap utilise aussi le préfixe `OpenMap` pour
  ses propres pins partagés (piste pour le module Marqueurs).
- **Autres addons** : pins HereBeDragons (HandyNotes, TomTom, GatherMate2…) recopiés par `AddonPins.lua`.

## 9. Éléments critiques pour les performances et risques de régression

1. **Pyramide de tuiles + cache** (`Want`, `UpdateTiles`, `KEEP_*`) : toute modification peut provoquer
   des trous, des clignotements ou des rechargements de fichiers. *Ne pas toucher sans mesure (`/av stats`).*
2. **`Map.Refresh`** : appelé à chaque mouvement ; chaque `Layout` de sous-système y ajoute son coût.
   Ajouter un calque = ajouter du coût par frame pendant les déplacements.
3. **`OnUpdate` conditionnel** : le principe « rien ne tourne carte fermée » doit être préservé.
4. **Regroupement des pins** (`BuildTree`, `Rep`) : algorithme sensible, coûteux au changement de zoom.
5. **Valeurs « secrètes »** (moteur 12.x : `issecretvalue`) : tout calcul sur des données d'unité passe
   par `FM.Plain`. À respecter dans tout nouveau code.
6. **Taint** : la prise en charge de la carte et du journal est délicate (combat, panneaux protégés).
   Toute modification de `Takeover.lua` doit être testée en combat.
7. **Couplage de `Map.lua`** : déplacer/renommer un sous-système casse l'orchestration.
8. **Coexistence avec PerfectMap** : les deux addons prennent la touche M et la carte de Blizzard ;
   ils ne doivent pas être actifs ensemble (AzerothVeil avertit au login).

## 10. Décisions architecturales recommandées (et appliquées)

1. **Conserver le moteur tel quel** dans `addon/Engine/` (noms de fichiers et ordre de chargement
   inchangés) ; modifications ciblées et marquées « AzerothVeil » dans le code.
2. **Renommage minimal** : namespace `_G.AzerothVeil`, `AzerothVeilDB`, frames `AzerothVeil*`, chemins
   `Interface\AddOns\AzerothVeil\`, `/av`, raccourci `AZEROTHVEIL_TOGGLE`.
   **Préfixes réseau conservés** (`PerfectMapSail`, `OpenMapLoc`) pour rester interopérable.
3. **Style classique uniquement** (pas de style « moderne », pas de question au premier lancement).
4. **Cœur modulaire ajouté à côté du moteur** (`Core/`), sans réécrire l'orchestration de `Map.lua` :
   les modules pilotent des sous-systèmes du moteur via des points d'entrée `Start/Stop` explicites.
5. **Migration progressive** : un sous-système devient module quand on y travaille. Premier pilote :
   `Friends.lua` → module « Amis & guilde » (fonction réseau, ticker permanent, autonome).
6. Les options historiques de PerfectMap restent dans le menu de la carte ; les options des modules sont
   dans la configuration centrale (fenêtre Options du jeu).
