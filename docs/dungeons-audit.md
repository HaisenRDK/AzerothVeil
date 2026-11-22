# Audit — module Donjons (AzerothVeil 0.4.0)

Audit du 22/11/2026. Versions installées vérifiées : **ForeverDungeonJournal 2.1.3** (Exehn, identique à
`.reference/`), **OpenMap v0.8.12**, **PerfectMap 1.5.6** (désactivé, référence). Projet étudié :
**OpenMap_NoDungeonMap** (GitHub, Caesar1208, MIT, 4 commits, Interface 16001).

## 1. Ce qui existe déjà dans le moteur (PerfectMap, `Engine/`)

| Besoin | Existant | Fichier |
|---|---|---|
| Entrées de donjons et raids | catégories `dungeon` / `raid`, une icône par entrée (entrées proches partagées), infobulle nom + niveaux | `Pins.lua` (`BuildPlaces`, données `Data/Places.lua` d'OpenMap) |
| Plusieurs donjons / ailes à une entrée | sélecteur « CHOISIR UN DONJON » (`D.Choose`) | `Dungeon.lua` |
| Carte intérieure | calque dans la **même fenêtre**, par-dessus la carte du monde : art de Blizzard (4×3 tuiles), dessins de Santiago Reyes pour les donjons Forever, cartes de DungeonJournal (UBRS, Alcaz 2) | `Dungeon.lua`, `Data/DungeonMaps.lua`, `DungeonDrawn.lua`, `DungeonJournal.lua` |
| Étages | boutons d'étage en haut de la carte (`D.SetFloor`) | `Dungeon.lua` |
| Boss | repères avec portrait et niveau ; sources : données issues de DungeonJournal (copiées hors jeu avec permission), MapUtils, OpenMap ; boss non placés listés à part | `Dungeon.lua` (`PlaceBosses`), `Data/DungeonJournal.lua`, `DungeonBosses.lua`, `DungeonSpots.lua` |
| Entrées / sorties sur la carte intérieure | repères « Entrée de donjon » | `Dungeon.lua` (`Entrance`), `Data/DungeonEntrances.lua` |
| Carte automatique à l'intérieur | donjon, raid **et champ de bataille** (`dungeonMaps`) | `Dungeon.lua` (`D.Update`) |
| Retour au monde | bouton « Monde » de l'en-tête, clic droit ; **recentre sur l'entrée** (ne restaure pas la vue précédente) | `Dungeon.lua` (`TogglePeek`, `ToEntrance`) |

Les cartes intérieures sont des images fixes ajustées à la fenêtre (pas de zoom), sauf les cartes du jeu
(champs de bataille), qui ont déjà zoom et déplacement.

**Données réellement disponibles sans DungeonJournal** : entrées (positions vérifiées d'OpenMap), noms et
niveaux d'instance, cartes et étages, boss (nom en anglais, niveau, portrait, position) — **pas de quêtes de
donjon ni de butin** dans les données d'AzerothVeil. Noms localisés d'instance : `GetRealZoneText(id)`
(utilisé ainsi par DungeonJournal sur ce client).

## 2. DungeonJournal 2.1.3

- Espace de noms public **`_G.ForeverDungeonJournal_NS`** (`FDJ`). Fenêtre `ForeverDungeonJournalFrame`,
  strata `DIALOG`, créée au chargement complet (login).
- Donjons indexés **par nom anglais** (`FDJ.DB["The Deadmines"]`) : quêtes (id, nom, donneur en texte,
  récompenses avec itemID), boss, butin. **Pas de raids.** Cartes : `FDJ.DUNGEON_MAPS[nom]`.
- Correspondance instance → nom : `FDJ.INSTANCE_ID_TO_DUNGEON` (partielle : ~17 instances),
  `FDJ.SCARLET_WING_MAPS`.
- Fonctions d'ouverture (définies après la création de sa fenêtre) :
  `FDJ.OpenDungeonMap(nom)`, `FDJ.OpenBossPage(nom, index)`, `FDJ.OpenQuestPage(nom, questID)`,
  `_G.ForeverDungeonJournal_Toggle()`.
- **Spoilers / mode RPG** : `SelectDungeon` (appelé par toutes les fonctions d'ouverture) refuse un donjon
  verrouillé et affiche sa notice ; `FDJ.IsDungeonMapLocked(nom)` indique une carte encore verrouillée.
- Sa surcouche de carte du monde s'accroche au `WorldMapFrame` de Blizzard (`Systems/WorldMapOverlay.lua`).

## 3. OpenMap_NoDungeonMap

Désactive la carte de donjon d'OpenMap en **remplaçant ses fonctions internes**
(`mod.SetupDungeons`, `mod.HoldDungeonHere`, enveloppe `S.BuildDungeonPins`) et **remplace**
`FDJ.RefreshWorldMapOverlay` (échange temporaire de `FDJ.CurrentDungeon`) pour afficher la carte de
DungeonJournal sur le `WorldMapFrame`. Identifie les donjons **par comparaison de noms** (normalisés).
Pas de vérification de combat. → À **ne pas** reproduire : remplacement de fonctions d'autres addons,
dépendance à leurs locaux, noms fragiles.

## 4. Conflits possibles

1. AzerothVeil remplace la carte de Blizzard : la surcouche de DungeonJournal sur `WorldMapFrame` n'est
   donc pas visible dans AzerothVeil (comportement existant, inchangé).
2. Deux interfaces de donjon concurrentes si AzerothVeil affichait ses onglets quand DungeonJournal est actif.
3. PerfectMap actif en même temps (déjà signalé au login).
4. Fonctions de DungeonJournal absentes ou renommées dans une autre version → appels protégés et repli.

## 4 bis. Licence de DungeonJournal et données réutilisées (v0.4.1)

DungeonJournal ne déclare **aucune licence** (ni fichier, ni mention dans son README ou son .toc) : son
code et ses données sont donc « tous droits réservés » par défaut. PerfectMap en a copié une partie
**avec la permission de son auteur** (`Engine/Data/DungeonJournal.lua`). AzerothVeil **ne copie rien de
plus** : quand DungeonJournal est installé, il **lit à l'exécution** ses données publiques, en lecture
seule (`Integrations/DungeonJournal.lua`) :
- passages entre étages (`DUNGEON_MAPS[nom].transitions`), sur les cartes du jeu uniquement (ses étages
  pointent vers les dalles du jeu `<Nom><n>_` = notre étage n ; les donjons Forever dessinés ne
  correspondent pas) ;
- passages entre étages des donjons propres à Forever : Cité engloutie, Dalaran, Prison d'Alcaz,
  dont ses images sont **les mêmes** que les nôtres (dessins de Santiago Reyes, comparées une à une le
  22/11/2026 ; ordre des étages parfois différent : à Dalaran, ses Bas-Fonds sont son étage 1, notre 2).
  Table explicite par nom de fichier d'image (`DJ.PICTURES`), hauteur ramenée à la partie visible de
  notre image ; indications (nager, sauter, sortie du requin…) dites avec nos propres mots ;
- butin des boss (`DB[nom].bosses[i].loot` : itemID, nom, emplacement, qualité), affiché avec les noms,
  icônes et infobulles natives du jeu.
Repaire des Noiregueules : aucune source ne place ses boss (DungeonJournal : « Locations unverified; no
fabricated boss markers ») ; ils sont listés dans l'onglet Boss, sans position inventée.

## 4 ter. Questie (v0.4.2)

Questie 12.12.0 et QuestieDB 1.1.4 (Forever), **GPL v3** : leur équipe accepte la réutilisation sous GPLv3
(réserve sur les contributions historiques, voir leur LICENSE.md). AzerothVeil **lit** leurs données à
l'exécution, sans rien copier ni modifier (`Integrations/Questie.lua`) :
- `QuestDB` / `NpcDB` (surface publique de QuestieDB) : nom localisé, donneur, niveaux, races, zone ;
  nom localisé et positions des PNJ ;
- `Questie.API.isReady` (API publique) ; modules `ZoneDB` (numéro d'instance → zones du donjon, zones
  secondaires) et `QuestieDB.IsDoable` (disponibilité) via `QuestieLoader`, protégés par `pcall`.
- L'état « terminée / en cours / prête / échouée » vient **du jeu** ; seul « disponible / pas encore »
  vient de Questie. Pas de récompenses hors journal (ni Questie ni le jeu ne les donnent).
- Index des quêtes par zone construit une fois, par tranches de 400 par image (pas d'à-coup).
- Donjons propres à Forever absents de Questie (Cité engloutie, Repaire des Noiregueules, Prison d'Alcaz,
  Terrasse du Façonneur, Bastion Krol'dok) : journal seulement.

## 5. Décisions

- **Module `dungeons`** pilotant le moteur existant (comme Transports) : interrupteurs effectifs écrits
  par le module, remis à faux au chargement ; migration de schéma 4 pour reprendre les réglages.
- **Retour au monde** : le module mémorise la vue (centre, zoom, terre « à part ») à l'ouverture depuis
  une entrée et la restaure (bouton Monde et clic droit, existants) ; le panneau latéral est restauré.
  Ouvrir un second donjon depuis une carte de donjon garde le contexte du premier départ.
- **Panneau latéral** : le journal de quêtes du moteur est **suspendu** (sans toucher à sa préférence
  enregistrée) et remplacé par deux onglets Quêtes / Boss, rétabli au retour. Aucun autre addon touché.
  - Quêtes (sans DungeonJournal) : celles du journal du joueur rangées sous l'en-tête du donjon (nom
    localisé du jeu), état (en cours / prête à rendre / échouée) et progression fournis par le jeu,
    récompenses et infobulles natives. Pas de quêtes « disponibles » ni de donneurs : aucune donnée fiable.
  - Boss : ceux du moteur, avec leur étage ; clic → étage affiché et repère mis en évidence.
    **Pas de butin** sans DungeonJournal (aucune donnée ; rien n'est inventé).
- **DungeonJournal actif** (option « Utiliser DungeonJournal ») : AzerothVeil lui **délègue** le clic sur
  une entrée — sa page du donjon (carte si elle existe et n'est pas verrouillée, sinon page des boss),
  via ses fonctions publiques, sous `pcall`, sans rien modifier chez lui ; ses verrous anti-spoiler
  s'appliquent. Les onglets d'AzerothVeil ne s'affichent pas (pas d'interface concurrente). Correspondance
  **par numéro d'instance** (+ nom d'aile de nos données), table explicite dans AzerothVeil, vérifiée
  contre `FDJ.DB` ; Stratholme (une entrée) propose ses deux parties. Raids : carte d'AzerothVeil.
  Échec de délégation → repli sur la carte d'AzerothVeil.
